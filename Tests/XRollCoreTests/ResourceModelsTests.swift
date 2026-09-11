import XCTest
@testable import XRollCore

final class ResourceModelsTests: XCTestCase {
    func testSeparatesNearbyTransients() {
        var samples = Array(repeating: Float.zero, count: 100)
        samples[10] = 1
        samples[25] = 0.8

        let transients = LatencyRecordingAnalysis.transients(
            in: samples,
            sampleRate: 1_000,
            thresholdRatio: 0.1,
            minimumSeparationMilliseconds: 2
        )

        XCTAssertEqual(transients.count, 2)
        XCTAssertEqual(transients[0].timeSeconds, 0.01, accuracy: 0.0001)
        XCTAssertEqual(transients[1].timeSeconds, 0.025, accuracy: 0.0001)
    }

    func testFindsOnePrimaryOnsetPerSeparatedSound() {
        var samples = Array(repeating: Float.zero, count: 1_000)
        samples[100] = 1
        samples[101] = 0.8
        samples[500] = 0.9

        let onsets = LatencyRecordingAnalysis.primaryOnsets(
            in: samples,
            sampleRate: 1_000,
            thresholdRatio: 0.1,
            envelopeMilliseconds: 1,
            minimumSeparationMilliseconds: 200
        )

        XCTAssertEqual(onsets.count, 2)
        XCTAssertEqual(onsets[0].timeSeconds, 0.1, accuracy: 0.0001)
        XCTAssertEqual(onsets[1].timeSeconds, 0.5, accuracy: 0.0001)
    }

    func testDecodesNoteOnAndIgnoresNoteOffVelocityZero() {
        let events = MIDIByteDecoder.noteOnEvents(
            bytes: [0x99, 36, 100, 38, 0, 0x89, 42, 80],
            hostTime: 123
        )

        XCTAssertEqual(events, [MIDINoteOn(hostTime: 123, channel: 10, note: 36, velocity: 100)])
    }

    func testRoutesKitNotesToTheirSounds() {
        let kit = KitManifest(
            format: 1,
            id: "test",
            name: "Test",
            sounds: [
                .init(id: "kick", label: "Bombo", file: "kick.wav", gmNote: 36, chokeGroup: nil),
                .init(id: "snare", label: "Caja", file: "snare.wav", gmNote: 38, chokeGroup: nil)
            ]
        )

        let router = KitNoteRouter(kit: kit)

        XCTAssertEqual(router.soundID(for: 36), "kick")
        XCTAssertEqual(router.soundID(for: 38), "snare")
        XCTAssertNil(router.soundID(for: 42))
    }

    func testRoutesMappedNoteUsingItsChannel() throws {
        let map = PadMap(
            device: "Pad",
            deviceUID: 42,
            created: "2026-09-05",
            pads: [.init(sound: "kick", number: 12, channel: 2, row: 0, column: 0)]
        )
        try map.validate(availableSounds: ["kick"])
        let router = PadMapRouter(padMap: map)

        XCTAssertEqual(router.soundID(for: MIDINoteOn(hostTime: 0, channel: 2, note: 12, velocity: 100)), "kick")
        XCTAssertNil(router.soundID(for: MIDINoteOn(hostTime: 0, channel: 1, note: 12, velocity: 100)))
    }

    func testRejectsDuplicateMappedMessages() {
        let map = PadMap(
            device: "Pad",
            deviceUID: 42,
            created: "2026-09-05",
            pads: [
                .init(sound: "kick", number: 36, channel: 10, row: 0, column: 0),
                .init(sound: "snare", number: 36, channel: 10, row: 0, column: 1)
            ]
        )

        XCTAssertThrowsError(try map.validate(availableSounds: ["kick", "snare"]))
    }

    func testPadMapV2AllowsSeveralPadsForOneSoundAndMigratesV1() throws {
        let legacy = PadMap(device: "Pad", deviceUID: 42, created: "2026-09-10", pads: [
            .init(sound: "kick", number: 36, channel: 10, row: 0, column: 0)
        ])
        let migrated = PadMapV2(migrating: legacy)
        XCTAssertEqual(migrated.format, 2)
        XCTAssertEqual(migrated.pads.first?.id, "r0c0")

        let drum = PadLayoutFactory.make(.drumKit, device: .init(name: "Pad", uid: 42))
        try drum.validate(availableSounds: ["kick", "rim", "snare", "clap", "tom_low", "hihat_closed", "hihat_open", "tom_high", "crash", "ride"])
        XCTAssertEqual(drum.pads.filter { $0.sound == "kick" }.count, 2)
        XCTAssertEqual(PadMapV2Router(drum).soundID(for: MIDINoteOn(hostTime: 0, channel: 10, note: 37, velocity: 100)), "kick")
    }

    func testLayoutPresetKeepsThePhysicalMIDINotes() {
        let device = PadMapV2.Device(name: "Pad", uid: 42)
        let physical = PadLayoutFactory.make(.drumKit, device: device)
        let remapped = PadLayoutFactory.applying(.mirror, to: physical)

        for pad in remapped.pads {
            let original = physical.pads.first { $0.row == pad.row && $0.column == pad.column }
            XCTAssertEqual(pad.input.number, original?.input.number)
            XCTAssertEqual(pad.input.channel, original?.input.channel)
        }
        XCTAssertNotEqual(remapped.pads.first(where: { $0.row == 1 && $0.column == 0 })?.sound, physical.pads.first(where: { $0.row == 1 && $0.column == 0 })?.sound)
    }

    func testPadMapBuilderRejectsDuplicateAndCompletes() {
        var builder = PadMapBuilder(
            device: "Pad",
            deviceUID: 7,
            created: "2026-09-05",
            steps: [
                .init(sound: "kick", row: 0, column: 0),
                .init(sound: "snare", row: 0, column: 1)
            ]
        )
        let kick = MIDINoteOn(hostTime: 0, channel: 10, note: 36, velocity: 100)

        XCTAssertEqual(builder.assign(kick), .assigned(sound: "kick", remaining: 1))
        XCTAssertEqual(builder.assign(kick), .duplicate(note: 36, channel: 10, existingSound: "kick"))
        guard case .complete(let map) = builder.assign(MIDINoteOn(hostTime: 0, channel: 10, note: 38, velocity: 100)) else {
            return XCTFail("El segundo pad debe completar el mapa")
        }
        XCTAssertEqual(map.pads.map(\.sound), ["kick", "snare"])
    }

    func testBuildsTimelineForEveryRepeat() {
        let exercise = Exercise(
            format: 1, id: "test", title: "Test", family: "test", level: 1,
            bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 2,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick", hand: "L"), .init(step: 4, sound: "snare", hand: "R")]
        )
        let timeline = ExerciseTimeline(exercise: exercise)

        XCTAssertEqual(timeline.stepDurationMilliseconds, 125, accuracy: 0.001)
        XCTAssertEqual(timeline.notes.map(\.timeMilliseconds), [0, 500, 2_000, 2_500])
    }

    func testTimelineAppliesEntryOffsetAndWrapsWithinTheBar() {
        let exercise = Exercise(format: 1, id: "offset", title: "Offset", family: "test", level: 1, bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 2, notes: [.init(step: 0, sound: "kick", hand: "L"), .init(step: 15, sound: "snare", hand: "R")])
        let timeline = ExerciseTimeline(exercise: exercise)
        XCTAssertEqual(timeline.notes.map(\.timeMilliseconds), [125, 250], "La nota del paso 15 vuelve al inicio tras desplazarla")
    }

    func testExerciseRejectsOffsetOutsideItsGrid() {
        let exercise = Exercise(format: 1, id: "offset", title: "Offset", family: "test", level: 1, bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 16, notes: [])
        XCTAssertThrowsError(try exercise.validate(availableSounds: []))
    }

    func testAudioClockMovesForwardByTheRequestedDuration() {
        let start: UInt64 = 1_000
        XCTAssertGreaterThan(AudioClock.hostTime(afterMilliseconds: 10, from: start), start)
    }

    func testLoadsTheBundledMIDIExerciseCatalog() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let router = KitNoteRouter(kit: kit)
        XCTAssertEqual(router.soundID(for: 37), "rim")
        XCTAssertEqual(router.soundID(for: 41), "tom_low")
        XCTAssertEqual(router.soundID(for: 48), "tom_high")
        XCTAssertEqual(router.soundID(for: 51), "ride")
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        XCTAssertEqual(exercises.count, 64)
        XCTAssertEqual(exercises.first?.title, "I-01 · Bombo y caja")
        XCTAssertEqual(exercises.first?.notes.map(\.sound), ["kick", "snare", "kick", "snare"])
    }

    func testActiveCatalogHasNoDuplicateRhythmsAtSameTempo() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        let groups = Dictionary(grouping: exercises) { exercise in
            "\(exercise.bpm):\(exercise.bars):\(exercise.grid):" + exercise.notes.sorted { $0.step == $1.step ? $0.sound < $1.sound : $0.step < $1.step }.map { "\($0.step):\($0.sound)" }.joined(separator: ",")
        }
        XCTAssertTrue(groups.values.allSatisfy { $0.count == 1 }, "Hay ritmos activos duplicados a igual tempo: \(groups.values.filter { $0.count > 1 }.map { $0.map(\.id) })")
    }

    func testWarnsWhenCommunityMIDIIntroducesTooMuchAtOnce() {
        let exercise = Exercise(format: 1, id: "dense", title: "Dense", family: "midi", level: 1, bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 8, kit: "kit", loop: nil, offset: 0, notes: [
            .init(step: 0, sound: "kick"), .init(step: 0, sound: "snare"), .init(step: 0, sound: "hihat_closed"), .init(step: 0, sound: "clap"), .init(step: 1, sound: "kick")
        ])
        let warnings = PedagogicalMIDIValidator.warnings(for: exercise)
        XCTAssertGreaterThanOrEqual(warnings.count, 3)
    }

    func testScoresJudgementsExtrasAndMisses() {
        let timeline = ExerciseTimeline(
            exercise: Exercise(
                format: 1, id: "test", title: "Test", family: "test", level: 1,
                bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
                kit: "kit", loop: nil, offset: 0,
                notes: [.init(step: 0, sound: "kick", hand: "L"), .init(step: 4, sound: "snare", hand: "R")]
            )
        )
        let score = RhythmScorer.score(
            timeline: timeline, bpm: 80, grid: 16,
            hits: [
                .init(sound: "kick", timeMilliseconds: 20),
                .init(sound: "kick", timeMilliseconds: 25),
                .init(sound: "snare", timeMilliseconds: 820)
            ]
        )

        XCTAssertEqual(score.hits.map(\.judgement), [.perfect, .extra, .regular])
        XCTAssertTrue(score.misses.isEmpty)
        XCTAssertEqual(score.percentage, 72.5, accuracy: 0.001)
        XCTAssertEqual(score.stars, 2)
        XCTAssertEqual(score.meanOffsetMilliseconds!, 45, accuracy: 0.001)
    }

    func testHitRecordsPreserveTargetExecutionAndMiss() {
        let exercise = Exercise(
            format: 1, id: "record-test", title: "Record test", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [
                .init(step: 0, sound: "kick", hand: "L", velocity: 92),
                .init(step: 4, sound: "snare", hand: "R", velocity: 76)
            ]
        )
        let score = RhythmScorer.score(
            timeline: ExerciseTimeline(exercise: exercise), bpm: 80, grid: 16,
            hits: [.init(sound: "kick", timeMilliseconds: 20, role: "kick_left", padID: "r0c0", velocity: 91)]
        )

        let records = HitRecord.records(from: score)
        XCTAssertEqual(records.count, 2)
        let played = try! XCTUnwrap(records.first { $0.judgement == .perfect })
        XCTAssertEqual(played.expectedStep, 0)
        XCTAssertEqual(played.expectedVelocity, 92)
        XCTAssertEqual(played.hand, "L")
        XCTAssertEqual(played.actualVelocity, 91)
        XCTAssertEqual(played.role, "kick_left")
        XCTAssertEqual(played.padID, "r0c0")
        XCTAssertEqual(played.offsetMilliseconds!, 20, accuracy: 0.001)

        let missed = try! XCTUnwrap(records.first { $0.judgement == .miss })
        XCTAssertEqual(missed.expectedSound, "snare")
        XCTAssertEqual(missed.expectedStep, 4)
        XCTAssertEqual(missed.hand, "R")
        XCTAssertNil(missed.actualTimeMilliseconds)
    }

    func testHistoricalDiagnosticsFindsSubdivisionAndWhaleIsolatesMistake() {
        let exercise = Exercise(format: 1, id: "diagnostic", title: "Diagnostic", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [
            .init(step: 0, sound: "kick", hand: "L", velocity: 90), .init(step: 6, sound: "snare", hand: "R", velocity: 80)
        ])
        let score = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 80, grid: 16, hits: [.init(sound: "kick", timeMilliseconds: 8, velocity: 88)])
        let attempt = PracticeAttempt(exerciseID: exercise.id, timestamp: .init(), bpm: 80, score: score.percentage, stars: score.stars, perfect: score.perfectCount, good: score.goodCount, regular: score.regularCount, miss: score.misses.count, extra: score.extraCount, meanOffsetMilliseconds: score.meanOffsetMilliseconds, hitRecords: HitRecord.records(from: score))
        let diagnostics = HistoricalDiagnosticsBuilder.build(attempts: [attempt], exercisesByID: [exercise.id: exercise])
        XCTAssertEqual(diagnostics.bySound.first?.label, "snare")
        XCTAssertTrue(diagnostics.bySubdivision.contains { $0.label == "&" && $0.missed == 1 })
        let whale = try! XCTUnwrap(WhaleMethod.plan(exercise: exercise, score: score))
        XCTAssertEqual(whale.focusStep, 6)
        XCTAssertEqual(whale.stepRange, 5...7)
    }

    func testMasteryRequiresAllFourTrainingContexts() {
        let exercise = Exercise(format: 1, id: "mastery", title: "Mastery", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let passing: (Int, TrainingContext) -> PracticeAttempt = { bpm, context in
            .init(exerciseID: exercise.id, timestamp: .init(), bpm: bpm, score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 5, trainingContext: context)
        }
        let attempts = [passing(80, .init()), passing(65, .init()), passing(95, .init()), passing(80, .init(gapMetronomeLevel: 2)), passing(80, .init(phase: .transfer, showsVisualGuides: false))]
        XCTAssertTrue(MasteryEvaluator.seals(exercise: exercise, attempts: attempts).allSatisfy(\.achieved))
    }

    func testPracticeSessionReturnsTheImmediateJudgement() {
        let exercise = Exercise(
            format: 1, id: "test", title: "Test", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick", hand: "L")]
        )
        let session = PracticeSession(exercise: exercise)

        let result = session.register(.init(sound: "kick", timeMilliseconds: 20))

        XCTAssertEqual(result.judgement, .perfect)
        XCTAssertEqual(session.score.percentage, 100, accuracy: 0.001)
    }

    func testProgressStorePersistsAttemptsAndReturnsSummary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-progress-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ProgressStore(url: url)
        let record = HitRecord.records(from: RhythmScorer.score(
            timeline: ExerciseTimeline(exercise: Exercise(format: 1, id: "hh_01", title: "Test", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])),
            bpm: 80, grid: 16, hits: [.init(sound: "kick", timeMilliseconds: 10)]
        ))
        try store.record(.init(exerciseID: "hh_01", timestamp: Date(timeIntervalSince1970: 1), bpm: 80, score: 65, stars: 1, perfect: 2, good: 1, regular: 0, miss: 1, extra: 0, meanOffsetMilliseconds: -12, hitRecords: record))
        try store.record(.init(exerciseID: "hh_01", timestamp: Date(timeIntervalSince1970: 2), bpm: 80, score: 40, stars: 0, perfect: 1, good: 0, regular: 0, miss: 3, extra: 0, meanOffsetMilliseconds: 4))

        let summary = try XCTUnwrap(store.progress(for: "hh_01"))
        XCTAssertEqual(summary.attemptCount, 2)
        XCTAssertEqual(summary.bestScore, 65, accuracy: 0.001)
        XCTAssertEqual(summary.latestScore, 40, accuracy: 0.001)
        XCTAssertEqual(try store.attempts(filter: .init(exerciseID: "hh_01")).last?.hitRecords, record)
    }

    func testProgressStoreExportsCSV() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-export-\(UUID().uuidString)", isDirectory: true)
        let database = directory.appendingPathComponent("progress.sqlite")
        let csv = directory.appendingPathComponent("progress.csv")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(url: database)
        try store.record(.init(exerciseID: "hh_01", timestamp: Date(timeIntervalSince1970: 1), bpm: 80, score: 75, stars: 2, perfect: 3, good: 1, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 2))
        try store.exportCSV(to: csv)

        XCTAssertTrue(try String(contentsOf: csv).contains("hh_01"))
    }

    func testProgressFilterAndJSONExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-filter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(url: directory.appendingPathComponent("progress.sqlite"))
        try store.record(.init(exerciseID: "hh_01", timestamp: Date(timeIntervalSince1970: 1), bpm: 80, score: 55, stars: 1, perfect: 1, good: 1, regular: 0, miss: 1, extra: 0, meanOffsetMilliseconds: nil))
        try store.record(.init(exerciseID: "hh_02", timestamp: Date(timeIntervalSince1970: 2), bpm: 90, score: 90, stars: 3, perfect: 4, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 1))
        let attempts = try store.attempts(filter: .init(minimumScore: 80))
        XCTAssertEqual(attempts.map(\.exerciseID), ["hh_02"])
        XCTAssertEqual(try store.attempts(filter: .init(maximumScore: 60)).map(\.exerciseID), ["hh_01"])
        let json = directory.appendingPathComponent("progress.json")
        try store.exportJSON(to: json, filter: .init(exerciseID: "hh_01"))
        XCTAssertTrue(try String(contentsOf: json).contains("hh_01"))
        XCTAssertFalse(try String(contentsOf: json).contains("hh_02"))
    }

    func testPracticeConfigurationClampsAndChangesTimeline() {
        let exercise = Exercise(format: 1, id: "test", title: "Test", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick", hand: "L")])
        let configured = PracticeConfiguration(exercise: exercise, bpm: 300, repeats: 0).applying(to: exercise)
        XCTAssertEqual(configured.bpm, 240)
        XCTAssertEqual(configured.repeats, 1)
        XCTAssertEqual(PracticeConfiguration(exercise: exercise, repeats: 7).repeats, 8)
        XCTAssertEqual(ExerciseTimeline(exercise: configured).stepDurationMilliseconds, 62.5, accuracy: 0.001)
    }

    func testWarmupPrioritizesNewExerciseAndInsightsShowTiming() {
        let one = Exercise(format: 1, id: "one", title: "Uno", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick", hand: "L")])
        let two = Exercise(format: 1, id: "two", title: "Dos", family: "test", level: 2, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick", hand: "L")])
        XCTAssertEqual(WarmupPlanner.recommend(exercises: [two, one], progress: ["two": .init(attemptCount: 1, bestScore: 90, latestScore: 90)]).first?.exerciseID, "one")
        let score = RhythmScorer.score(timeline: ExerciseTimeline(exercise: one), bpm: 80, grid: 16, hits: [.init(sound: "kick", timeMilliseconds: -20)])
        let insights = PracticeInsights(score: score)
        XCTAssertEqual(insights.timingLabel, "Tiendes a adelantar el golpe")
        XCTAssertEqual(insights.soundStatistics.first?.accuracy ?? -1, 100, accuracy: 0.001)
    }

    func testRecoveryAdvisorOrdersProblems() {
        XCTAssertEqual(RecoveryAdvisor.assess(missingSamples: ["kick.wav"], hasMIDIInput: false), .missingSamples(["kick.wav"]))
        XCTAssertEqual(RecoveryAdvisor.assess(missingSamples: [], hasMIDIInput: false), .noMIDIInput)
        XCTAssertEqual(RecoveryAdvisor.assess(missingSamples: [], hasMIDIInput: true), .ready)
    }

    func testCourseProgressUnlocksOnlyAfterMasteringPreviousLevel() {
        let exercises = (1...3).map { level in
            Exercise(format: 1, id: "level_\(level)", title: "Nivel \(level)", family: "test", level: level, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        }
        XCTAssertEqual(CourseProgress.states(exercises: exercises, progress: [:]).map(\.status), [.available, .locked, .locked])
        let first = ExerciseProgress(attemptCount: 1, bestScore: 70, latestScore: 70)
        XCTAssertEqual(CourseProgress.states(exercises: exercises, progress: ["level_1": first]).map(\.status), [.mastered, .available, .locked])
    }

    func testPracticePreferencesRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-preferences-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let preferences = PracticePreferences(exerciseID: "hh_03", bpm: 95, repeats: 6)
        try PracticePreferencesStore.save(preferences, to: url)
        XCTAssertEqual(try PracticePreferencesStore.load(from: url), preferences)
    }

    func testVelocityCurveKeepsSoftHitsAudibleAndCapsHardHits() {
        XCTAssertGreaterThan(VelocityCurve.gain(for: 1), 0.15)
        XCTAssertLessThan(VelocityCurve.gain(for: 1), VelocityCurve.gain(for: 64))
        XCTAssertEqual(VelocityCurve.gain(for: 127), 1, accuracy: 0.0001)
    }

    func testTuningClampsAndPersists() throws {
        let tuning = PracticeTuning(debugEnabled: true, anticipationBars: 8, perfectWindowMilliseconds: 80, goodWindowMilliseconds: 20, regularWindowMilliseconds: 10, manualTimingOffsetMilliseconds: 500, countInVolume: 2, metronomePitchSemitones: 30, padFlashMilliseconds: 1)
        XCTAssertEqual(tuning.anticipationBars, 4)
        XCTAssertEqual(tuning.goodWindowMilliseconds, 80)
        XCTAssertEqual(tuning.regularWindowMilliseconds, 80)
        XCTAssertEqual(tuning.manualTimingOffsetMilliseconds, 200)
        XCTAssertEqual(tuning.metronomePitchSemitones, 24)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-tuning-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try PracticeTuningStore.save(tuning, to: url)
        XCTAssertEqual(try PracticeTuningStore.load(from: url), tuning)
    }

    func testCalibrationOffsetChangesTheJudgement() {
        let timeline = ExerciseTimeline(
            exercise: Exercise(
                format: 1, id: "test", title: "Test", family: "test", level: 1,
                bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
                kit: "kit", loop: nil, offset: 0,
                notes: [.init(step: 0, sound: "kick", hand: "L")]
            )
        )
        let score = RhythmScorer.score(
            timeline: timeline, bpm: 120, grid: 16,
            hits: [.init(sound: "kick", timeMilliseconds: 50)],
            calibrationOffsetMilliseconds: 50
        )

        XCTAssertEqual(score.hits.first?.judgement, .perfect)
        XCTAssertEqual(score.hits.first?.offsetMilliseconds ?? .infinity, 0, accuracy: 0.001)
    }

    func testCalibrationUsesMedianAfterWarmupAndReportsDispersion() throws {
        let estimate = try CalibrationEstimator.estimate(
            rawOffsetsMilliseconds: [400, 300, 200, 100, 18, 20, 21, 19, 22, 20, 1_000, 19],
            discardFirst: 4,
            minimumAcceptedHits: 8
        )

        XCTAssertEqual(estimate.offsetMilliseconds, 20, accuracy: 0.001)
        XCTAssertEqual(estimate.medianAbsoluteDeviationMilliseconds, 1, accuracy: 0.001)
        XCTAssertEqual(estimate.acceptedHitCount, 8)
    }

    func testCalibrationRejectsTooFewHitsAfterWarmup() {
        XCTAssertThrowsError(
            try CalibrationEstimator.estimate(rawOffsetsMilliseconds: [0, 1, 2, 3, 4], discardFirst: 4)
        )
    }

    func testRejectsDuplicateNotesAtTheSameStep() {
        let exercise = Exercise(
            format: 1,
            id: "test",
            title: "Test",
            family: "test",
            level: 1,
            bpm: 80,
            meter: [4, 4],
            bars: 1,
            grid: 16,
            repeats: 4,
            kit: "kit",
            loop: nil,
            offset: 0,
            notes: [
                .init(step: 0, sound: "kick", hand: "L"),
                .init(step: 0, sound: "kick", hand: "L")
            ]
        )

        XCTAssertThrowsError(try exercise.validate(availableSounds: ["kick"]))
    }

    func testAcceptsSimultaneousNotesWithDifferentSounds() throws {
        let exercise = Exercise(
            format: 1,
            id: "test",
            title: "Test",
            family: "test",
            level: 1,
            bpm: 80,
            meter: [4, 4],
            bars: 1,
            grid: 16,
            repeats: 4,
            kit: "kit",
            loop: nil,
            offset: 0,
            notes: [
                .init(step: 0, sound: "kick", hand: "L"),
                .init(step: 0, sound: "snare", hand: "R")
            ]
        )

        XCTAssertNoThrow(try exercise.validate(availableSounds: ["kick", "snare"]))
    }

    func testDetectsTempoFromLoopFilename() {
        let url = URL(fileURLWithPath: "/tmp/bass 90bpm.wav")
        let detected = LoopTempoDetector.detect(url: url)
        XCTAssertEqual(detected?.bpm, 90)
        XCTAssertEqual(detected?.source, "nombre del archivo")
    }
}
