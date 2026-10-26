import XCTest
import SQLite3
import XRollRealtimeQueue
@testable import XRollCore

final class AuditRegressionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-audit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func attempt(records: [HitRecord] = [], index: Int = 0) -> PracticeAttempt {
        PracticeAttempt(exerciseID: "audit", timestamp: Date(timeIntervalSince1970: 1_000 + Double(index)),
            bpm: 100, score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0,
            meanOffsetMilliseconds: 0, hitRecords: records,
            trainingContext: .init(evaluationScope: .fullPattern, completedBars: 16, tempoPolicyVersion: 1))
    }

    private func record(step: Int = 0, time: Double = 0) -> HitRecord {
        HitRecord(sequence: 0, judgement: .perfect, expectedSound: "kick", expectedStep: step,
            expectedTimeMilliseconds: time, expectedVelocity: nil, hand: nil, target: nil,
            actualSound: "kick", actualTimeMilliseconds: 0, actualVelocity: nil,
            role: nil, padID: nil, offsetMilliseconds: 0)
    }

    private var exercise: Exercise {
        Exercise(format: 1, id: "audit", title: "Auditoría", family: "test", level: 1, bpm: 100,
            meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "test", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")])
    }

    func testInvalidNestedRecordsRollBackTheWholeImportAndReopenSafely() throws {
        let url = directory.appendingPathComponent("history.sqlite")
        let store = try ProgressStore(url: url)
        for invalid in [record(step: -1), record(time: 1e300), record(time: .infinity)] {
            XCTAssertThrowsError(try store.importAttempts([attempt(index: 1), attempt(records: [invalid], index: 2)]))
            XCTAssertTrue(try store.attempts().isEmpty)
        }
        XCTAssertTrue(try ProgressStore(url: url).attempts().isEmpty)
    }

    func testPreviouslyStoredInvalidRecordsDoNotCrashDiagnosticsOrExports() throws {
        let url = directory.appendingPathComponent("legacy.sqlite")
        let store = try ProgressStore(url: url)
        try store.record(attempt(records: [record()]))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let bad = try JSONEncoder().encode([record(step: -1), record(time: 1e300)])
        let text = String(decoding: bad, as: UTF8.self).replacingOccurrences(of: "'", with: "''")
        XCTAssertEqual(sqlite3_exec(database, "UPDATE attempts SET hit_records_json = '\(text)'", nil, nil, nil), SQLITE_OK)
        let reopened = try ProgressStore(url: url)
        XCTAssertTrue(try reopened.attempts()[0].hitRecords.isEmpty)
        let direct = HistoricalDiagnosticsBuilder.build(attempts: [attempt(records: [record(step: -1), record(time: 1e300)])],
            exercisesByID: [exercise.id: exercise])
        XCTAssertTrue(direct.bySubdivision.isEmpty)
        XCTAssertEqual(try reopened.exportJSON(to: directory.appendingPathComponent("recovered.json")), 1)
    }

    func testInvalidNestedConditionsCannotBeImportedOrAccreditLegacyProgress() throws {
        let store = try ProgressStore(url: directory.appendingPathComponent("context.sqlite"))
        let data = try JSONEncoder().encode(attempt())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["trainingContext"] = ["evaluationScope": "fullPattern", "completedBars": 16,
            "practiceConditions": ["bpm": 100, "repeats": -1, "selectedSounds": ["kick"],
                "gapMetronomeLevel": 0, "metronomeEnabled": true, "loopEnabled": false, "showsVisualGuides": true]]
        let invalid = try JSONDecoder().decode(PracticeAttempt.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try store.importAttempts([invalid]))
        XCTAssertTrue(try store.courseEvidence().isEmpty)
    }

    func testStreamedJSONImportPreservesEscapesBoundariesAndRollsBackTrailingGarbage() throws {
        let store = try ProgressStore(url: directory.appendingPathComponent("stream.sqlite"))
        let source = directory.appendingPathComponent("source.json")
        let values = (0..<1_005).map { attempt(records: [record()], index: $0) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(values).write(to: source)
        XCTAssertEqual(try store.importJSON(from: source), 1_005)
        XCTAssertEqual(try store.importJSON(from: source), 0)
        let escaped = PracticeAttempt(exerciseID: "comillas \" y \\ llaves } ] {", timestamp: Date(), bpm: 100,
            score: 70, stars: 1, perfect: 0, good: 1, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: nil)
        var invalid = try encoder.encode([escaped])
        invalid.append(contentsOf: " basura".utf8)
        try invalid.write(to: source)
        XCTAssertThrowsError(try store.importJSON(from: source))
        XCTAssertEqual(try store.courseEvidence().count, 1_005)
        for malformed in ["[{},]", "[", "[]{}", "[1]", "[{}"] {
            try Data(malformed.utf8).write(to: source)
            XCTAssertThrowsError(try store.importJSON(from: source))
        }
        try encoder.encode([escaped]).write(to: source)
        XCTAssertEqual(try store.importJSON(from: source), 1)
    }

    func testBackgroundSnapshotAndImportPublishOnMainAndKeepTheOwnersConnectionUsable() throws {
        let store = try ProgressStore(url: directory.appendingPathComponent("background.sqlite"))
        let url = directory.appendingPathComponent("import.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([attempt(records: [record()])]).write(to: url)
        let imported = expectation(description: "Importación")
        store.importJSONInBackground(from: url) { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(try? result.get(), 1)
            imported.fulfill()
        }
        wait(for: [imported], timeout: 10)
        let snapshot = expectation(description: "Instantánea")
        store.loadSnapshotInBackground(exercises: [exercise], graph: nil, selectedExerciseID: exercise.id) { result in
            XCTAssertTrue(Thread.isMainThread)
            if case .success(let value) = result {
                XCTAssertGreaterThanOrEqual(value.recentAttempts.count, 1)
                XCTAssertGreaterThanOrEqual(value.diagnostics.bySound.first?.expected ?? 0, 1)
            } else { XCTFail("No se pudo cargar la instantánea: \(result)") }
            snapshot.fulfill()
        }
        try store.record(attempt(index: 2))
        wait(for: [snapshot], timeout: 10)
        XCTAssertEqual(try store.attempts().count, 2)
        let summaries = expectation(description: "Resumen agregado")
        store.loadExerciseProgressInBackground { result in
            XCTAssertTrue(Thread.isMainThread)
            if case .success(let values) = result { XCTAssertEqual(values["audit"]?.attemptCount, 2) }
            else { XCTFail("No se pudo leer el resumen agrupado: \(result)") }
            summaries.fulfill()
        }
        wait(for: [summaries], timeout: 10)
    }

    func testCompactedEvidencePreservesCourseStatesAndEveryAwardIncludingTwoPasses() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        let graph = try CourseGraph(exercises: exercises)
        var evidence = [CourseAttemptEvidence]()
        for exercise in exercises {
            for score in [69.0, 70, 80, 90, 95, 99] {
                for _ in 0..<4 {
                    evidence.append(.init(exerciseID: exercise.id, bpm: exercise.bpm, score: score, stars: 3,
                        trainingContext: .init(evaluationScope: .fullPattern, completedBars: 16, tempoPolicyVersion: 1)))
                }
            }
        }
        let compacted = CourseAttemptEvidence.compacted(evidence)
        XCTAssertLessThan(compacted.count, evidence.count)
        XCTAssertEqual(graph.states(evidence: evidence), graph.states(evidence: compacted))
        XCTAssertEqual(graph.worlds(evidence: evidence), graph.worlds(evidence: compacted))
        for exercise in exercises {
            for step in TempoLadder.steps(for: exercise) {
                XCTAssertEqual(TempoLadder.isPassed(step, exerciseID: exercise.id, evidence: evidence),
                    TempoLadder.isPassed(step, exerciseID: exercise.id, evidence: compacted))
            }
        }
    }

    func testCommunityReloadSkipsDuplicateIDsWithoutDeletingTheFiles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("data/exercises"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mid" }.sorted { $0.path < $1.path }
        let source = try XCTUnwrap(files.first)
        let bundled = try MIDIExerciseLoader.load(url: source, kit: kit, level: 1)
        for name in ["first.mid", "second.mid"] { try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name)) }
        XCTAssertTrue(try catalog.loadCommunityExercises(in: directory, kit: kit, bundled: [bundled]).isEmpty)
        XCTAssertEqual(try catalog.loadCommunityExercises(in: directory, kit: kit, bundled: []).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("second.mid").path))
    }

    func testImportedMapsAndAllPresetsKeepMixedChannelsAndPhysicalIDs() throws {
        let base = PadLayoutFactory.make(.core, device: .init(name: "Original", uid: 1))
        let pads = base.pads.enumerated().map { index, pad in
            PadMapV2.Pad(id: pad.id, row: pad.row, column: pad.column, sound: pad.sound, role: pad.role,
                input: .init(number: pad.input.number, channel: index.isMultiple(of: 2) ? 1 : 10))
        }
        let map = PadMapV2(id: "mixed", name: "Canales mixtos", preset: .custom, device: base.device, created: base.created, pads: pads)
        let imported = map.rebound(to: .init(name: "Seleccionado", uid: 987))
        XCTAssertEqual(imported.pads, map.pads)
        XCTAssertEqual(imported.device.uid, 987)
        for preset in [PadLayoutPreset.core, .drumKit, .mirror] {
            let applied = PadLayoutFactory.applying(preset, to: imported)
            XCTAssertEqual(applied.pads.map(\.input), pads.map(\.input))
            XCTAssertEqual(applied.pads.map(\.id), pads.map(\.id))
        }
    }

    func testRealtimeQueuePreservesFullSizedPacketsAndCountsEveryRejectedPacket() throws {
        let queue = try XCTUnwrap(xroll_realtime_queue_create(2))
        defer { xroll_realtime_queue_destroy(queue) }
        var input = (0..<Int(XROLL_MAX_PACKET_BYTES)).map { UInt8($0 % 251) }
        XCTAssertTrue(xroll_realtime_queue_push(queue, 123, 456, &input, UInt16.max))
        XCTAssertTrue(xroll_realtime_queue_push(queue, 124, 457, &input, 257))
        XCTAssertFalse(xroll_realtime_queue_push(queue, 125, 458, &input, 3))
        XCTAssertFalse(xroll_realtime_queue_push(queue, 125, 458, nil, 3))
        XCTAssertEqual(xroll_realtime_queue_dropped(queue), 2)
        var output = [UInt8](repeating: 0, count: Int(XROLL_MAX_PACKET_BYTES))
        var time: UInt64 = 0; var callback: UInt64 = 0; var length: UInt16 = 0
        XCTAssertTrue(xroll_realtime_queue_pop(queue, &time, &callback, &output, &length))
        XCTAssertEqual(time, 123); XCTAssertEqual(callback, 456); XCTAssertEqual(length, UInt16.max)
        XCTAssertEqual(output, input)
        XCTAssertTrue(xroll_realtime_queue_pop(queue, &time, &callback, &output, &length))
        XCTAssertEqual(length, 257)
    }
}
