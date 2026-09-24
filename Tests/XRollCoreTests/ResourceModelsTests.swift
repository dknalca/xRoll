import XCTest
@testable import XRollCore

final class ResourceModelsTests: XCTestCase {
    func testGuidedCalibrationBecomesScoringCompensation() {
        let key = CalibrationProfileKey(inputKind: .midi, inputIdentifier: "pad", outputIdentifier: "output", sampleRate: 48_000, bufferFrames: 64)
        let profile = CalibrationProfile(key: key, estimate: .init(offsetMilliseconds: 18, medianAbsoluteDeviationMilliseconds: 4, acceptedHitCount: 12))

        XCTAssertEqual(profile.userCalibrationBiasMilliseconds, 18)
        XCTAssertEqual(profile.scoringCompensationMilliseconds, 18)
        XCTAssertEqual(profile.offsetMilliseconds, 18)
    }

    func testTouchCalibrationProfileRemainsDistinctFromMIDIInput() throws {
        let touch = CalibrationProfileKey(inputKind: .touch, inputIdentifier: "touchscreen", outputIdentifier: "speaker", sampleRate: 48_000, bufferFrames: 256)
        let midi = CalibrationProfileKey(inputKind: .midi, inputIdentifier: "touchscreen", outputIdentifier: "speaker", sampleRate: 48_000, bufferFrames: 256)
        let decoded = try JSONDecoder().decode(CalibrationProfileKey.self, from: JSONEncoder().encode(touch))

        XCTAssertEqual(decoded, touch)
        XCTAssertNotEqual(decoded, midi)
    }

    func testCalibrationMatcherUsesRawHitsOutsideScoringWindowAndConsumesTargetsOnce() {
        var matcher = CalibrationMatcher(targetTimesMilliseconds: [0, 500, 1_000])

        let first = matcher.associateHit(atMilliseconds: 85)
        let duplicateInsideFirstWindow = matcher.associateHit(atMilliseconds: 100)
        let second = matcher.associateHit(atMilliseconds: 590)
        let distantExtra = matcher.associateHit(atMilliseconds: 1_600)

        XCTAssertEqual(first?.targetTimeMilliseconds, 0)
        XCTAssertEqual(first?.rawOffsetMilliseconds, 85)
        XCTAssertNil(duplicateInsideFirstWindow, "Un golpe extra no debe consumir el siguiente objetivo.")
        XCTAssertEqual(second?.targetTimeMilliseconds, 500)
        XCTAssertEqual(second?.rawOffsetMilliseconds, 90)
        XCTAssertNil(distantExtra)
    }

    func testLiveMIDIProcessorCanResolveWithoutPlayingAudio() throws {
        let kitURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Kits/hiphop_basic/kit.json")
        let kit = try ResourceCatalog().loadKit(at: kitURL)
        let map = PadLayoutFactory.make(.core, device: .init(name: "test", uid: 1))
        let processor = LiveMIDIProcessor(
            audio: SampleAudioEngine(),
            kitRouter: KitNoteRouter(kit: kit),
            padRouter: PadMapV2Router(map)
        )

        let hit = processor.resolve(MIDINoteOn(hostTime: 1_000, channel: 10, note: 36, velocity: 100))

        XCTAssertEqual(hit?.soundID, "kick")
        XCTAssertEqual(hit?.padID, "r0c0")
        XCTAssertEqual(hit?.row, 0)
        XCTAssertEqual(hit?.column, 0)
    }

    func testLegacyCalibrationProfilesAreRejectedForRemeasurement() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-legacy-calibration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = """
        [{"key":{"inputKind":"midi","inputIdentifier":"pad","outputIdentifier":"output","sampleRate":48000,"bufferFrames":64},"offsetMilliseconds":12,"medianAbsoluteDeviationMilliseconds":2,"calibratedAt":"2026-09-01T00:00:00Z"}]
        """
        try legacy.data(using: .utf8)!.write(to: url)

        XCTAssertThrowsError(try CalibrationProfileStore.load(from: url))
    }

    func testDecoderStreamsNoteOnEvents() {
        let bytes: [UInt8] = [0x99, 36, 100, 38, 80]
        var events: [MIDINoteOn] = []
        bytes.withUnsafeBufferPointer { buffer in
            MIDIByteDecoder.decodeNoteOnEvents(bytes: buffer, hostTime: 123) { events.append($0) }
        }

        XCTAssertEqual(events, [
            MIDINoteOn(hostTime: 123, channel: 10, note: 36, velocity: 100),
            MIDINoteOn(hostTime: 123, channel: 10, note: 38, velocity: 80)
        ])
    }
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

    func testPairsBandOnsetsAndCalculatesSummary() {
        let pads = [
            RecordingTransient(timeSeconds: 1, amplitude: 1),
            RecordingTransient(timeSeconds: 2, amplitude: 1),
            RecordingTransient(timeSeconds: 3, amplitude: 1)
        ]
        let sounds = [
            RecordingTransient(timeSeconds: 1.012, amplitude: 1),
            RecordingTransient(timeSeconds: 2.018, amplitude: 1),
            RecordingTransient(timeSeconds: 3.024, amplitude: 1)
        ]
        let measurements = LatencyRecordingAnalysis.pair(padOnsets: pads, soundOnsets: sounds)
        let summary = try! XCTUnwrap(LatencyRecordingAnalysis.summary(of: measurements))

        XCTAssertEqual(measurements.count, 3)
        XCTAssertEqual(measurements[0].milliseconds, 12, accuracy: 0.001)
        XCTAssertEqual(measurements[1].milliseconds, 18, accuracy: 0.001)
        XCTAssertEqual(measurements[2].milliseconds, 24, accuracy: 0.001)
        XCTAssertEqual(summary.medianMilliseconds, 18, accuracy: 0.001)
        XCTAssertEqual(summary.percentile95Milliseconds, 23.4, accuracy: 0.001)
    }

    func testDecodesNoteOnAndIgnoresNoteOffVelocityZero() {
        let events = MIDIByteDecoder.noteOnEvents(
            bytes: [0x99, 36, 100, 38, 0, 0x89, 42, 80],
            hostTime: 123
        )

        XCTAssertEqual(events, [MIDINoteOn(hostTime: 123, channel: 10, note: 36, velocity: 100)])
    }

    func testMIDITimestampResolverPreservesPlausibleCoreMIDITimes() {
        let callbackHostTime = AudioClock.currentHostTime()
        let coreMIDIHostTime = AudioClock.hostTime(offsetByNanoseconds: -30_000_000, from: callbackHostTime)

        let result = MIDITimestampResolver.resolve(
            coreMIDIHostTime: coreMIDIHostTime,
            callbackHostTime: callbackHostTime
        )

        XCTAssertEqual(result, MIDITimestampResolution(hostTime: coreMIDIHostTime, source: .coreMIDI))
    }

    func testMIDITimestampResolverFallsBackForZeroStaleAndImpossibleFutureTimes() {
        let callbackHostTime = AudioClock.currentHostTime()
        let staleHostTime = AudioClock.hostTime(offsetByNanoseconds: -25_000_000_000, from: callbackHostTime)
        let futureHostTime = AudioClock.hostTime(afterMilliseconds: 500, from: callbackHostTime)

        let invalidHostTimes: [UInt64] = [0, staleHostTime, futureHostTime]
        for invalidHostTime in invalidHostTimes {
            let result = MIDITimestampResolver.resolve(
                coreMIDIHostTime: invalidHostTime,
                callbackHostTime: callbackHostTime
            )

            XCTAssertEqual(result, MIDITimestampResolution(hostTime: callbackHostTime, source: .callbackFallback))
        }
    }

    func testMIDIDecoderRetainsRawAndCallbackTimesWhenUsingFallback() {
        let callbackHostTime = AudioClock.currentHostTime()
        let staleHostTime = AudioClock.hostTime(offsetByNanoseconds: -25_000_000_000, from: callbackHostTime)
        let events = MIDIByteDecoder.noteOnEvents(
            bytes: [0x99, 42, 100],
            hostTime: staleHostTime,
            callbackHostTime: callbackHostTime
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].hostTime, callbackHostTime)
        XCTAssertEqual(events[0].coreMIDIHostTime, staleHostTime)
        XCTAssertEqual(events[0].callbackHostTime, callbackHostTime)
        XCTAssertEqual(events[0].timestampSource, .callbackFallback)
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

    func testCoreLayoutUsesAllSixteenPads() {
        let core = PadLayoutFactory.make(.core, device: .init(name: "Pad", uid: 42))

        XCTAssertEqual(core.pads.count, 16)
        XCTAssertEqual(core.pads.filter { $0.sound == "kick" }.count, 2)
        XCTAssertEqual(core.pads.filter { $0.sound == "snare" }.count, 2)
        XCTAssertEqual(core.pads.filter { $0.sound == "hihat_closed" }.count, 3)
        XCTAssertEqual(core.pads.filter { $0.sound == "hihat_open" }.count, 2)
        XCTAssertEqual(core.pads.filter { $0.sound == "crash" }.count, 2)
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

    func testCustomLayoutPreservesImportedSoundsRolesAndPhysicalInputs() {
        let device = PadMapV2.Device(name: "Pad", uid: 42)
        let base = PadLayoutFactory.make(.core, device: device)
        let imported = PadMapV2(
            id: "imported-layout",
            name: "Mi mezcla",
            preset: .custom,
            device: device,
            created: "2026-09-24",
            pads: base.pads.map {
                .init(
                    id: $0.id,
                    row: $0.row,
                    column: $0.column,
                    sound: $0.row.isMultiple(of: 2) ? "snare" : "kick",
                    role: "imported_\($0.id)",
                    input: $0.input
                )
            }
        )

        let reapplied = PadLayoutFactory.applying(.custom, to: imported)

        XCTAssertEqual(reapplied.pads, imported.pads)
        XCTAssertEqual(reapplied.name, imported.name)
        XCTAssertEqual(reapplied.device, imported.device)
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
        XCTAssertEqual(builder.assignedCount, 1)
        XCTAssertEqual(builder.assignedPads.first?.input.number, 36)
        XCTAssertEqual(builder.assign(kick), .duplicate(note: 36, channel: 10, existingSound: "kick"))
        guard case .complete(let map) = builder.assign(MIDINoteOn(hostTime: 0, channel: 10, note: 38, velocity: 100)) else {
            return XCTFail("El segundo pad debe completar el mapa")
        }
        XCTAssertEqual(map.pads.map(\.sound), ["kick", "snare"])
        XCTAssertEqual(map.preset, .core)
    }

    func testLearningAllPhysicalPadsPreservesNotesAndChannelsAcrossLayouts() {
        var builder = PadMapBuilder(device: "M-Vave", deviceUID: 265_410_049, created: "2026-09-23")
        var learnedMap: PadMapV2?

        for (index, step) in PadMapBuilder.suggestedSteps.enumerated() {
            let event = MIDINoteOn(hostTime: UInt64(index), channel: 1, note: 60 + index, velocity: 100)
            let result = builder.assign(event)
            if index == PadMapBuilder.suggestedSteps.count - 1 {
                guard case .complete(let map) = result else { return XCTFail("Los 16 pads deben completar el asistente.") }
                learnedMap = map
            } else {
                guard case .assigned = result else { return XCTFail("La posición física \(step.row),\(step.column) no se asignó.") }
            }
        }

        let physical = try! XCTUnwrap(learnedMap)
        XCTAssertEqual(physical.pads.count, 16)
        XCTAssertEqual(physical.pads.map(\.input.channel), Array(repeating: 1, count: 16))
        XCTAssertEqual(Set(physical.pads.map(\.input.number)), Set(60...75))

        let mirror = PadLayoutFactory.applying(.mirror, to: physical)
        XCTAssertEqual(mirror.pads.count, 16)
        for pad in mirror.pads {
            let learned = try! XCTUnwrap(physical.pads.first { $0.id == pad.id })
            XCTAssertEqual(pad.input, learned.input)
            XCTAssertEqual(pad.row, learned.row)
            XCTAssertEqual(pad.column, learned.column)
        }
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

    func testTimelineReturnsOnlyNotesInsideAVisibleWindow() {
        let exercise = Exercise(
            format: 1, id: "viewport", title: "Viewport", family: "test", level: 1,
            bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 2,
            kit: "kit", loop: nil, offset: 0,
            notes: [
                .init(step: 0, sound: "kick"),
                .init(step: 4, sound: "snare"),
                .init(step: 4, sound: "clap"),
                .init(step: 8, sound: "kick")
            ]
        )
        let timeline = ExerciseTimeline(exercise: exercise)

        let simultaneous = timeline.noteRange(from: 500, through: 500)
        XCTAssertEqual(Array(timeline.notes[simultaneous].map(\.sound)), ["snare", "clap"])
        XCTAssertTrue(timeline.noteRange(from: 501, through: 999).isEmpty)
        XCTAssertEqual(timeline.notes[timeline.noteRange(from: 2_000, through: 2_000)].map(\.sound), ["kick"])
        XCTAssertTrue(timeline.noteRange(from: 900, through: 800).isEmpty)
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

    func testTimedPadHitUsesTheOriginalHostTime() {
        let start = AudioClock.hostTime(afterMilliseconds: 1_000, from: 10_000)
        let input = AudioClock.hostTime(afterMilliseconds: 37, from: start)
        let hit = TimedPadHit(sound: "kick", hostTime: input, practiceStartHostTime: start)

        XCTAssertEqual(hit.timeMilliseconds, 37, accuracy: 0.001)
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
        XCTAssertEqual(exercises.count, 77)
        XCTAssertNoThrow(try CurriculumValidator.validateIntegratedExercises(exercises))
        XCTAssertTrue(exercises.allSatisfy { $0.metadata != nil })
        let graph = try CourseGraph(exercises: exercises)
        let chapters = graph.nodes.map(\.metadata.chapter)
        XCTAssertTrue(graph.mainChapterIDs.allSatisfy { graph.checkpoint(for: $0) != nil })
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "disco")), try XCTUnwrap(chapters.firstIndex(of: "funk")))
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "dembow")), try XCTUnwrap(chapters.firstIndex(of: "blues")))
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "jazz")), try XCTUnwrap(chapters.firstIndex(of: "clave-bossa")))
        XCTAssertEqual(exercises.first?.title, "I-01 · Bombo y caja")
        XCTAssertEqual(exercises.first?.notes.map(\.sound), ["kick", "snare", "kick", "snare"])
        let ternaryExercises = exercises.filter { $0.id.hasPrefix("22_") || $0.id.hasPrefix("23_") }
        XCTAssertEqual(ternaryExercises.count, 8)
        XCTAssertTrue(ternaryExercises.allSatisfy { $0.grid == 12 })
        let phrase = try XCTUnwrap(exercises.first { $0.id == "02_sub_09_frase_integrada" })
        XCTAssertEqual(phrase.bars, 4)
        XCTAssertEqual(phrase.bpm, 78)
        XCTAssertTrue(phrase.notes.contains { $0.sound == "hihat_closed" && $0.step.isMultiple(of: 16) == false && $0.step % 2 == 1 })
        XCTAssertTrue(phrase.notes.contains { $0.sound == "kick" && $0.step % 16 == 6 })
        let coordinationCheckpoint = try XCTUnwrap(exercises.first { $0.id == "03_coord_08_independencia" })
        XCTAssertEqual(coordinationCheckpoint.bars, 4)
        XCTAssertTrue(Set(coordinationCheckpoint.notes.map(\.sound)).isSuperset(of: ["kick", "snare", "hihat_closed", "hihat_open", "clap"]))
        let grooveCheckpoint = try XCTUnwrap(exercises.first { $0.id == "04_groove_07_completo" })
        XCTAssertEqual(grooveCheckpoint.bars, 4)
        XCTAssertTrue(Set(grooveCheckpoint.notes.map(\.sound)).isSuperset(of: ["kick", "snare", "hihat_closed", "clap", "tom_low", "tom_high", "crash"]))
        XCTAssertEqual(try XCTUnwrap(exercises.first { $0.id == "20_rock_04_resistencia" }).bars, 8)
        XCTAssertEqual(try XCTUnwrap(exercises.first { $0.id == "21_funk_04_clap" }).bars, 4)
        XCTAssertEqual(try XCTUnwrap(exercises.first { $0.id == "22_blues_04_cierre" }).bars, 12)
        XCTAssertEqual(try XCTUnwrap(exercises.first { $0.id == "27_clave_01_tres_dos" }).notes.map(\.step), [0, 6, 12, 20, 24])
        XCTAssertEqual(try XCTUnwrap(exercises.first { $0.id == "27_clave_03_bossa" }).bars, 6)
    }

    func testActiveCatalogHasNoDuplicateRhythms() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        let groups = Dictionary(grouping: exercises) { exercise in
            "\(exercise.bars):\(exercise.grid):" + exercise.notes.sorted { $0.step == $1.step ? $0.sound < $1.sound : $0.step < $1.step }.map { "\($0.step):\($0.sound)" }.joined(separator: ",")
        }
        XCTAssertTrue(groups.values.allSatisfy { $0.count == 1 }, "Hay ritmos activos duplicados: \(groups.values.filter { $0.count > 1 }.map { $0.map(\.id) })")
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

    func testDuplicatePadsOnlyMatchTheRequestedRoleOrPhysicalPad() {
        let roleExercise = Exercise(
            format: 1, id: "role-target", title: "Rol", family: "test", level: 1,
            bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick", target: .init(type: .role, value: "kick_right"))]
        )
        let roleScore = PracticeSession(exercise: roleExercise)
        roleScore.register(.init(sound: "kick", timeMilliseconds: 0, role: "kick_left", padID: "r0c1"))
        roleScore.register(.init(sound: "kick", timeMilliseconds: 0, role: "kick_right", padID: "r0c2"))

        XCTAssertEqual(roleScore.score.hits.map(\.judgement), [.extra, .perfect])
        XCTAssertTrue(roleScore.score.misses.isEmpty)

        let padExercise = Exercise(
            format: 1, id: "pad-target", title: "Pad", family: "test", level: 1,
            bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick", target: .init(type: .pad, value: "r0c2"))]
        )
        let padScore = PracticeSession(exercise: padExercise)
        padScore.register(.init(sound: "kick", timeMilliseconds: 0, role: "kick_left", padID: "r0c1"))
        padScore.register(.init(sound: "kick", timeMilliseconds: 0, role: "kick_right", padID: "r0c2"))

        XCTAssertEqual(padScore.score.hits.map(\.judgement), [.extra, .perfect])
        XCTAssertTrue(padScore.score.misses.isEmpty)
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

    func testCountInHitsAreUnscoredButEarlyFirstBeatHitsStillCount() {
        let exercise = Exercise(
            format: 1, id: "count-in", title: "Count in", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick", hand: "L")]
        )
        let session = PracticeSession(exercise: exercise)

        XCTAssertNil(session.registerIfScorable(.init(sound: "kick", timeMilliseconds: -300)))
        XCTAssertTrue(session.hits.isEmpty)

        let firstBeat = try! XCTUnwrap(session.registerIfScorable(.init(sound: "kick", timeMilliseconds: -20)))
        XCTAssertEqual(firstBeat.judgement, .perfect)
        XCTAssertEqual(session.score.extraCount, 0)
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

    func testResultAnalyzerPrioritizesCorrectivePracticeForAWeakSound() {
        let exercise = Exercise(format: 1, id: "result", title: "Result", family: "test", level: 1, bpm: 100, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [
            .init(step: 0, sound: "kick"), .init(step: 4, sound: "snare")
        ])
        let score = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 100, grid: 16, hits: [.init(sound: "kick", timeMilliseconds: 4)])
        let summary = PracticeResultAnalyzer.summarize(score: score, insights: PracticeInsights(score: score), hasCorrectivePlan: true, canAdvance: false)

        XCTAssertEqual(summary.diagnosis, .weakSound(sound: "snare", accuracy: 0, missed: 1))
        XCTAssertEqual(summary.action, .corrective)
    }

    func testResultAnalyzerAdvancesWhenTheAttemptIsConsolidated() {
        let exercise = Exercise(format: 1, id: "advance", title: "Advance", family: "test", level: 1, bpm: 100, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let score = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 100, grid: 16, hits: [.init(sound: "kick", timeMilliseconds: 5)])
        let summary = PracticeResultAnalyzer.summarize(score: score, insights: PracticeInsights(score: score), hasCorrectivePlan: false, canAdvance: true)

        XCTAssertEqual(summary.diagnosis, .solid)
        XCTAssertEqual(summary.action, .advance)
    }

    func testNextSessionPlannerStartsWithTheFirstAvailableExercise() {
        let first = Exercise(format: 1, id: "first", title: "Primero", family: "course", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 2, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let second = Exercise(format: 1, id: "second", title: "Segundo", family: "course", level: 2, bpm: 90, meter: [4, 4], bars: 1, grid: 16, repeats: 2, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let plan = try! XCTUnwrap(NextSessionPlanner.plan(exercises: [second, first], courseLevels: [.init(exerciseID: first.id, status: .available, bestScore: nil), .init(exerciseID: second.id, status: .locked, bestScore: nil)], attempts: []))

        XCTAssertEqual(plan.exerciseID, first.id)
        XCTAssertEqual(plan.kind, .firstSession)
        XCTAssertEqual(plan.estimatedDurationMilliseconds, 6_000, accuracy: 0.001)
    }

    func testNextSessionPlannerSkipsExercisesCreditedByCheckpoint() {
        let skipped = Exercise(format: 1, id: "skipped", title: "Acreditado", family: "course", level: 1, bpm: 70, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let next = Exercise(format: 1, id: "next", title: "Siguiente", family: "course", level: 2, bpm: 75, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "snare")])
        let states = [
            CourseLevelState(exerciseID: skipped.id, status: .mastered, bestScore: nil, creditSource: .checkpoint(exerciseID: "chapter_checkpoint"), chapterAccredited: true),
            CourseLevelState(exerciseID: next.id, status: .available, bestScore: nil)
        ]

        let plan = NextSessionPlanner.plan(exercises: [skipped, next], courseLevels: states, attempts: [])

        XCTAssertEqual(plan?.exerciseID, next.id)
    }

    func testNextSessionPlannerUsesTheEligibleBundledExercise() {
        let bundled = Exercise(format: 1, id: "bundled-midi", title: "Ritmo integrado", family: "midi", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 2, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let imported = Exercise(format: 1, id: "imported-midi", title: "Ritmo importado", family: "midi", level: 0, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 2, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])

        let plan = NextSessionPlanner.plan(exercises: [bundled, imported], courseLevels: [], attempts: [], eligibleExerciseIDs: [bundled.id])

        XCTAssertEqual(plan?.exerciseID, bundled.id)
    }

    func testNextSessionPlannerCorrectsTheWeakestRecentSound() {
        let exercise = Exercise(format: 1, id: "current", title: "Actual", family: "course", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let attempt = PracticeAttempt(exerciseID: exercise.id, timestamp: Date(), bpm: 80, score: 60, stars: 1, perfect: 1, good: 0, regular: 0, miss: 1, extra: 0, meanOffsetMilliseconds: nil, soundStatistics: [.init(sound: "snare", expected: 2, perfect: 0, good: 0, regular: 0, missed: 2)])
        let plan = try! XCTUnwrap(NextSessionPlanner.plan(exercises: [exercise], courseLevels: [.init(exerciseID: exercise.id, status: .available, bestScore: 60)], attempts: [attempt]))

        XCTAssertEqual(plan.kind, .corrective)
        XCTAssertTrue(plan.reason.contains("snare"))
    }

    func testResultAnalyzerUsesMissesWhenNoHitWasAssociated() {
        let exercise = Exercise(format: 1, id: "missed", title: "Missed", family: "test", level: 1, bpm: 100, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "snare")])
        let score = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 100, grid: 16, hits: [])
        let summary = PracticeResultAnalyzer.summarize(score: score, insights: PracticeInsights(score: score), hasCorrectivePlan: true, canAdvance: false)

        XCTAssertEqual(summary.diagnosis, .weakSound(sound: "snare", accuracy: 0, missed: 1))
        XCTAssertEqual(summary.action, .corrective)
    }

    func testAutopilotAndResultUseTheSameRobustSpread() {
        let exercise = Exercise(format: 1, id: "spread", title: "Spread", family: "test", level: 1, bpm: 60, meter: [4, 4], bars: 1, grid: 4, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [
            .init(step: 0, sound: "kick"), .init(step: 1, sound: "snare")
        ])
        let score = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 60, grid: 4, hits: [
            .init(sound: "kick", timeMilliseconds: -50), .init(sound: "snare", timeMilliseconds: 1_050)
        ])
        let insights = PracticeInsights(score: score)
        let summary = PracticeResultAnalyzer.summarize(score: score, insights: insights, hasCorrectivePlan: false, canAdvance: true)
        let autopilot = PracticeAutopilot.recommend(score: score, insights: insights, bpm: 60, repeats: 8)

        XCTAssertEqual(insights.medianOffsetMilliseconds, 0)
        XCTAssertEqual(insights.medianAbsoluteDeviationMilliseconds, 50)
        XCTAssertEqual(summary.diagnosis, .inconsistent(spreadMilliseconds: 50))
        XCTAssertEqual(summary.action, .repeatWithAdjustment)
        XCTAssertEqual(autopilot.bpmAdjustment, -6)
        XCTAssertEqual(autopilot.help, .full)
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

    func testParsesVersionedCurriculumMetadataFromMIDITextEvents() throws {
        let metadata = try MIDIExerciseMetadataParser.parse(textEvents: [
            "unrelated text",
            "xroll/1 id=02_sub_04_bombo_y",
            "xroll/1 chapter=subdivision",
            "xroll/1 position=4",
            "xroll/1 prerequisite=02_sub_03_groove",
            "xroll/1 objective=Colocar el bombo entre pulsos",
            "xroll/1 new-difficulty=first-offbeat-kick",
            "xroll/1 recommended-help=full",
            "xroll/1 flag=checkpoint"
        ])

        XCTAssertEqual(metadata?.id, "02_sub_04_bombo_y")
        XCTAssertEqual(metadata?.chapter, "subdivision")
        XCTAssertEqual(metadata?.position, 4)
        XCTAssertEqual(metadata?.prerequisites, ["02_sub_03_groove"])
        XCTAssertEqual(metadata?.recommendedHelp, .full)
        XCTAssertEqual(metadata?.flags, ["checkpoint"])
    }

    func testRejectsMalformedCurriculumMetadataWithoutRejectingPlainMIDI() throws {
        XCTAssertNil(try MIDIExerciseMetadataParser.parse(textEvents: ["unrelated text"]))
        XCTAssertThrowsError(try MIDIExerciseMetadataParser.parse(textEvents: [
            "xroll/1 id=duplicate",
            "xroll/1 id=duplicate-again",
            "xroll/1 chapter=test",
            "xroll/1 position=1"
        ]))
        XCTAssertThrowsError(try MIDIExerciseMetadataParser.parse(textEvents: [
            "xroll/1 id=test",
            "xroll/1 chapter=test",
            "xroll/1 position=1",
            "xroll/1 recommended-help=turbo"
        ]))
    }

    func testCourseProgressDoesNotUnlockFromPartialPractice() {
        let exercises = (1...2).map { level in
            Exercise(format: 1, id: "level_\(level)", title: "Nivel \(level)", family: "test", level: level, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        }
        let partial = PracticeAttempt(exerciseID: "level_1", timestamp: .init(), bpm: 80, score: 100, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0, trainingContext: .init(evaluationScope: .selectedVoices))

        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [partial], fastStartID: nil).map(\.status), [.available, .locked])
    }

    func testCourseProgressRequiresConsolidarToUnlock() {
        let exercises = (1...2).map { level in
            Exercise(format: 1, id: "level_\(level)", title: "Nivel \(level)", family: "test", level: level, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        }
        let learnPass = PracticeAttempt(exerciseID: "level_1", timestamp: .init(), bpm: 70, score: 100, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let basePass = PracticeAttempt(exerciseID: "level_1", timestamp: .init(), bpm: 85, score: 70, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let consolidatePass = PracticeAttempt(exerciseID: "level_1", timestamp: .init(), bpm: 100, score: 70, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)

        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [learnPass, basePass], fastStartID: nil).map(\.status), [.available, .locked])
        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [learnPass, basePass, consolidatePass], fastStartID: nil).map(\.status), [.mastered, .available])
    }

    func testTempoLadderUsesFixedStepsAndLongChallenge() {
        let exercise = Exercise(format: 1, id: "level_1", title: "Nivel 1", family: "test", level: 1, bpm: 92, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let steps = TempoLadder.steps(for: exercise)
        XCTAssertEqual(steps.map(\.bpm), [70, 85, 100, 120, 140, 160])
        XCTAssertEqual(steps.map(\.requiredPasses), [1, 1, 1, 1, 1, 1])
        XCTAssertEqual(steps.map(\.award), [.stars(1), .stars(2), .stars(3), .trophies(1), .trophies(2), .trophies(3)])
        XCTAssertEqual(steps.last?.minimumBars, 16)
        XCTAssertEqual(TempoLadder.repeats(for: try! XCTUnwrap(steps.last), exercise: exercise), 16)

        let attempts = [
            PracticeAttempt(exerciseID: exercise.id, timestamp: .init(), bpm: 70, score: 80, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0),
            PracticeAttempt(exerciseID: exercise.id, timestamp: .init(), bpm: 85, score: 80, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        ]
        XCTAssertEqual(TempoLadder.nextStep(for: exercise, attempts: attempts)?.label, "Consolidar")
    }

    func testPassingOneTempoDoesNotInventBadgesAtEarlierTempos() {
        let exercise = Exercise(format: 1, id: "direct-tempo", title: "Directo", family: "test", level: 1, bpm: 70, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let evidence = [CourseAttemptEvidence(
            exerciseID: exercise.id,
            bpm: 100,
            score: 80,
            stars: 2,
            trainingContext: .init(evaluationScope: .fullPattern, completedBars: 1)
        )]
        let steps = TempoLadder.steps(for: exercise)

        XCTAssertTrue(TempoLadder.isPassed(steps[2], exerciseID: exercise.id, evidence: evidence))
        XCTAssertFalse(TempoLadder.isPassed(steps[0], exerciseID: exercise.id, evidence: evidence))
        XCTAssertEqual(TempoLadder.nextStep(for: exercise, evidence: evidence)?.label, "Aprender")
    }

    func testNivelDiosRequiresSixteenCompletedBarsOfAFullPattern() throws {
        let exercise = Exercise(format: 1, id: "level_1", title: "Nivel 1", family: "test", level: 1, bpm: 70, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let levelGod = try XCTUnwrap(TempoLadder.steps(for: exercise).last)
        let fifteenBars = PracticeAttempt(
            exerciseID: exercise.id, timestamp: .init(), bpm: 160, score: 90, stars: 3,
            perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0,
            trainingContext: TrainingContext(evaluationScope: .fullPattern, completedBars: 15)
        )
        let sixteenBars = PracticeAttempt(
            exerciseID: exercise.id, timestamp: .init(), bpm: 160, score: 90, stars: 3,
            perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0,
            trainingContext: TrainingContext(evaluationScope: .fullPattern, completedBars: 16)
        )
        let partialPattern = PracticeAttempt(
            exerciseID: exercise.id, timestamp: .init(), bpm: 160, score: 100, stars: 3,
            perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0,
            trainingContext: TrainingContext(evaluationScope: .selectedVoices, completedBars: 16)
        )

        XCTAssertFalse(TempoLadder.isPassed(levelGod, exerciseID: exercise.id, attempts: [fifteenBars, partialPattern]))
        XCTAssertTrue(TempoLadder.isPassed(levelGod, exerciseID: exercise.id, attempts: [sixteenBars]))
    }

    func testCourseRecommendationUsesCurrentStationThenPendingTempoStep() {
        let first = Exercise(format: 1, id: "first", title: "Primero", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let second = Exercise(format: 1, id: "second", title: "Segundo", family: "test", level: 2, bpm: 110, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let initial = CourseRecommendationPlanner.recommend(exercises: [first, second], courseLevels: [.init(exerciseID: first.id, status: .available, bestScore: nil), .init(exerciseID: second.id, status: .locked, bestScore: nil)], attempts: [])
        XCTAssertEqual(initial?.exerciseID, first.id)
        XCTAssertEqual(initial?.tempoStep.label, "Aprender")

        let learnPass = PracticeAttempt(exerciseID: first.id, timestamp: .init(), bpm: 70, score: 80, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let base = CourseRecommendationPlanner.recommend(exercises: [first, second], courseLevels: [.init(exerciseID: first.id, status: .available, bestScore: nil), .init(exerciseID: second.id, status: .locked, bestScore: nil)], attempts: [learnPass])
        XCTAssertEqual(base?.tempoStep.label, "Base")

        let next = CourseRecommendationPlanner.recommend(exercises: [first, second], courseLevels: [.init(exerciseID: first.id, status: .mastered, bestScore: 80), .init(exerciseID: second.id, status: .available, bestScore: nil)], attempts: [learnPass])
        XCTAssertEqual(next?.exerciseID, second.id)
        XCTAssertEqual(next?.tempoStep.bpm, 70)
    }

    func testCourseRecommendationStopsWhenEveryMainChapterIsAccredited() {
        let exercise = Exercise(format: 1, id: "only", title: "Único", family: "test", level: 1, bpm: 70, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let state = CourseLevelState(exerciseID: exercise.id, status: .mastered, bestScore: 80, chapterAccredited: true)

        XCTAssertNil(CourseRecommendationPlanner.recommend(exercises: [exercise], courseLevels: [state], evidence: []))
    }

    func testCourseProgressKeepsLegacyCompletionButNotMasteryEvidence() throws {
        let exercise = Exercise(format: 1, id: "level_1", title: "Nivel 1", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let legacyContext = try JSONDecoder().decode(TrainingContext.self, from: Data(#"{"phase":"integrate","gapMetronomeLevel":0,"showsVisualGuides":true}"#.utf8))
        let legacy = PracticeAttempt(exerciseID: exercise.id, timestamp: .init(), bpm: 80, score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0, trainingContext: legacyContext)

        XCTAssertEqual(legacyContext.evaluationScope, .legacyUnknown)
        XCTAssertEqual(CourseProgress.states(exercises: [exercise], attempts: [legacy], fastStartID: nil).first?.status, .available)
        XCTAssertFalse(MasteryEvaluator.seals(exercise: exercise, attempts: [legacy]).first?.achieved ?? true)
    }

    func testFastStartDoesNotBypassConsolidationOfThePreviousStation() {
        let exercises = [
            Exercise(format: 1, id: "00_i_01_bombo_caja", title: "I-01", family: "test", level: 1, bpm: 68, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: []),
            Exercise(format: 1, id: "00_i_02_charles_negras", title: "I-02", family: "test", level: 2, bpm: 68, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: []),
            Exercise(format: 1, id: "00_i_03_ritmo_completo", title: "I-03", family: "test", level: 3, bpm: 72, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: []),
            Exercise(format: 1, id: "01_fund_01_pulso", title: "Fundamentos", family: "test", level: 4, bpm: 70, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        ]
        let fastStart = PracticeAttempt(exerciseID: "00_i_03_ritmo_completo", timestamp: .init(), bpm: 100, score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)

        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [fastStart]).map(\.status), [.available, .locked, .mastered, .locked])
    }

    func testCourseGraphUsesMIDIPrerequisitesAndFastStart() throws {
        func exercise(_ id: String, level: Int, chapter: String, position: Int, prerequisites: [String] = [], flags: [String] = []) -> Exercise {
            Exercise(
                format: 1, id: id, title: id, family: "test", level: level, bpm: 80,
                meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil,
                offset: 0, notes: [], metadata: .init(
                    id: id, chapter: chapter, position: position,
                    prerequisites: prerequisites, objective: nil, newDifficulty: nil,
                    recommendedHelp: .full, flags: flags
                )
            )
        }
        let exercises = [
            exercise("i1", level: 1, chapter: "initiation", position: 1),
            exercise("i3", level: 2, chapter: "initiation", position: 2, prerequisites: ["i1"], flags: ["fast-start", "checkpoint"]),
            exercise("fund1", level: 3, chapter: "fundamentals", position: 1, prerequisites: ["i3"], flags: ["checkpoint"]),
            exercise("fill1", level: 4, chapter: "fills-1", position: 1, prerequisites: ["i1"], flags: ["checkpoint"])
        ]
        let graph = try CourseGraph(exercises: exercises)

        XCTAssertEqual(graph.states(attempts: []).map(\.status), [.available, .available, .locked, .available])

        let fastStart = PracticeAttempt(exerciseID: "i3", timestamp: .init(), bpm: 100, score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let fastStartStates = graph.states(attempts: [fastStart])
        XCTAssertEqual(fastStartStates.map(\.status), [.mastered, .mastered, .available, .available])
        XCTAssertEqual(fastStartStates[0].creditSource, .checkpoint(exerciseID: "i3"))
        XCTAssertTrue(fastStartStates[0].chapterAccredited)

        let firstConsolidated = PracticeAttempt(exerciseID: "i1", timestamp: .init(), bpm: 100, score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        XCTAssertEqual(graph.states(attempts: [firstConsolidated, fastStart]).map(\.status), [.mastered, .mastered, .available, .available])
    }

    func testLegacyUnknownCheckpointAttemptDoesNotGrantNewChapterEquivalency() throws {
        func exercise(_ id: String, position: Int, prerequisites: [String], flags: [String]) -> Exercise {
            Exercise(
                format: 1, id: id, title: id, family: "test", level: position, bpm: 70,
                meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [],
                metadata: .init(id: id, chapter: "initiation", position: position, prerequisites: prerequisites, objective: nil, newDifficulty: nil, recommendedHelp: .full, flags: flags)
            )
        }
        let exercises = [
            exercise("basic", position: 1, prerequisites: [], flags: ["fast-start"]),
            exercise("checkpoint", position: 2, prerequisites: ["basic"], flags: ["checkpoint"])
        ]
        let graph = try CourseGraph(exercises: exercises)
        let legacyAttempt = PracticeAttempt(
            exerciseID: "checkpoint", timestamp: .init(), bpm: 100, score: 90, stars: 3,
            perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0,
            trainingContext: .init(evaluationScope: .legacyUnknown, completedBars: 1)
        )

        let states = graph.states(attempts: [legacyAttempt])
        let checkpointState = try XCTUnwrap(states.first(where: { $0.exerciseID == "checkpoint" }))
        XCTAssertEqual(checkpointState.status, .mastered, "Conserva el resultado individual reconocido históricamente")
        XCTAssertFalse(checkpointState.chapterAccredited, "Un contexto desconocido no da créditos equivalentes del checkpoint")
        XCTAssertNotEqual(states.first(where: { $0.exerciseID == "basic" })?.creditSource, .checkpoint(exerciseID: "checkpoint"))
    }

    func testCheckpointCreditsItsChapterButRespectsChapterOrder() throws {
        func exercise(_ id: String, level: Int, chapter: String, position: Int, prerequisites: [String] = [], flags: [String] = []) -> Exercise {
            Exercise(
                format: 1, id: id, title: id, family: "test", level: level, bpm: 80,
                meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil,
                offset: 0, notes: [], metadata: .init(
                    id: id, chapter: chapter, position: position,
                    prerequisites: prerequisites, objective: nil, newDifficulty: nil,
                    recommendedHelp: .full, flags: flags
                )
            )
        }
        let exercises = [
            exercise("i1", level: 1, chapter: "initiation", position: 1, flags: ["fast-start"]),
            exercise("i2", level: 2, chapter: "initiation", position: 2, prerequisites: ["i1"], flags: ["checkpoint"]),
            exercise("f1", level: 3, chapter: "fundamentals", position: 1, prerequisites: ["i2"]),
            exercise("f2", level: 4, chapter: "fundamentals", position: 2, prerequisites: ["f1"], flags: ["checkpoint"])
        ]
        let graph = try CourseGraph(exercises: exercises)
        func passed(_ id: String) -> CourseAttemptEvidence {
            CourseAttemptEvidence(
                exerciseID: id,
                bpm: 100,
                score: 80,
                trainingContext: .init(evaluationScope: .fullPattern, completedBars: 1)
            )
        }

        let futureCheckpoint = graph.states(evidence: [passed("f2")])
        XCTAssertTrue(futureCheckpoint.first(where: { $0.exerciseID == "f2" })?.status == .mastered)
        XCTAssertFalse(futureCheckpoint.first(where: { $0.exerciseID == "f2" })?.chapterAccredited ?? true)
        XCTAssertEqual(futureCheckpoint.first(where: { $0.exerciseID == "f1" })?.status, .locked)

        let sequentialCheckpoints = graph.states(evidence: [passed("f2"), passed("i2")])
        XCTAssertEqual(sequentialCheckpoints.map(\.status), [.mastered, .mastered, .mastered, .mastered])
        XCTAssertEqual(sequentialCheckpoints.first(where: { $0.exerciseID == "f1" })?.creditSource, .checkpoint(exerciseID: "f2"))
        XCTAssertTrue(sequentialCheckpoints.allSatisfy(\.chapterAccredited))
    }

    func testPracticePreferencesRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-preferences-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let preferences = PracticePreferences(exerciseID: "hh_03", bpm: 95, repeats: 6)
        try PracticePreferencesStore.save(preferences, to: url)
        XCTAssertEqual(try PracticePreferencesStore.load(from: url), preferences)
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

    func testScoringWindowsAlwaysRespectTheExerciseSubdivision() {
        let tuning = PracticeTuning()
        let windows = tuning.scoringWindows(bpm: 160, grid: 16)

        XCTAssertEqual(windows.regularMilliseconds, 42.1875, accuracy: 0.001)
        XCTAssertLessThanOrEqual(windows.goodMilliseconds, windows.regularMilliseconds)
        XCTAssertLessThanOrEqual(windows.perfectMilliseconds, windows.goodMilliseconds)
    }

    func testScoresKeepsTheMostRecentAttemptsInChronologicalOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-progress-history-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ProgressStore(url: url)
        let start = Date(timeIntervalSince1970: 1_000)
        for score in 0...24 {
            try store.record(PracticeAttempt(exerciseID: "test", timestamp: start.addingTimeInterval(Double(score)), bpm: 100, score: Double(score), stars: 0, perfect: 0, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: nil))
        }

        XCTAssertEqual(try store.scores(for: "test"), (5...24).map(Double.init))
    }

    func testCourseEvidenceIsNotLimitedToTheRecentAttemptWindow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-course-evidence-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ProgressStore(url: url)
        let start = Date(timeIntervalSince1970: 10_000)
        for index in 0..<1_005 {
            try store.record(PracticeAttempt(
                exerciseID: "checkpoint",
                timestamp: start.addingTimeInterval(Double(index)),
                bpm: 100,
                score: 75,
                stars: 2,
                perfect: 1,
                good: 0,
                regular: 0,
                miss: 0,
                extra: 0,
                meanOffsetMilliseconds: nil,
                trainingContext: .init(evaluationScope: .fullPattern, completedBars: 4)
            ))
        }

        XCTAssertEqual(try store.attempts(limit: 1_000).count, 1_000)
        XCTAssertEqual(try store.courseEvidence().count, 1_005)
    }

    func testCommunityMIDIRejectsTempoChanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-tempo-change-\(UUID().uuidString).mid")
        defer { try? FileManager.default.removeItem(at: url) }
        let track: [UInt8] = [
            0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,
            0x60, 0xFF, 0x51, 0x03, 0x06, 0x1A, 0x80,
            0x00, 0x99, 0x24, 0x64,
            0x00, 0xFF, 0x2F, 0x00
        ]
        let header: [UInt8] = [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 96]
        let trackHeader: [UInt8] = [0x4D, 0x54, 0x72, 0x6B, 0, 0, 0, UInt8(track.count)]
        try Data(header + trackHeader + track).write(to: url)
        let kit = KitManifest(format: 1, id: "test", name: "Test", sounds: [.init(id: "kick", label: "Bombo", file: "kick.wav", gmNote: 36, chokeGroup: nil)])

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: kit, level: 1)) { error in
            guard case .unsupportedTempoChanges = error as? MIDIExerciseError else {
                return XCTFail("Se esperaba rechazar el cambio de tempo, se obtuvo: \(error)")
            }
        }
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

    // MARK: - Endurecimiento del loader MIDI y validación de recursos

    private func writeCommunityMIDI(track: [UInt8], division: UInt16 = 480) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-loader-\(UUID().uuidString).mid")
        let header: [UInt8] = [
            0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1,
            UInt8(division >> 8), UInt8(division & 0xFF)
        ]
        let count = UInt32(track.count)
        let trackHeader: [UInt8] = [
            0x4D, 0x54, 0x72, 0x6B,
            UInt8((count >> 24) & 0xFF), UInt8((count >> 16) & 0xFF),
            UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF)
        ]
        try Data(header + trackHeader + track).write(to: url)
        return url
    }

    private func communityKit() -> KitManifest {
        KitManifest(format: 1, id: "test", name: "Test", sounds: [
            .init(id: "kick", label: "Bombo", file: "kick.wav", gmNote: 36, chokeGroup: nil),
            .init(id: "snare", label: "Caja", file: "snare.wav", gmNote: 38, chokeGroup: nil)
        ])
    }

    private func vlq(_ value: Int) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        return bytes
    }

    private func tempoTrack(notes: [(delta: Int, note: UInt8)], tempo: [UInt8]? = [0x07, 0xA1, 0x20]) -> [UInt8] {
        var track: [UInt8] = [0x00, 0xFF, 0x03, 0x04] + Array("Test".utf8)
        track += [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]
        if let tempo { track += [0x00, 0xFF, 0x51, 0x03] + tempo }
        for note in notes { track += vlq(note.delta) + [0x99, note.note, 0x64] }
        track += [0x00, 0xFF, 0x2F, 0x00]
        return track
    }

    func testCommunityMIDIRejectsNoteOutsideTheKit() throws {
        let url = try writeCommunityMIDI(track: tempoTrack(notes: [(0, 36), (120, 45)]))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .unsupportedSound(let note) = error as? MIDIExerciseError, note == 45 else {
                return XCTFail("Se esperaba rechazar la nota 45, se obtuvo: \(error)")
            }
        }
    }

    func testCommunityMIDIRejectsMissingTempo() throws {
        let url = try writeCommunityMIDI(track: tempoTrack(notes: [(0, 36)], tempo: nil))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .missingTempo = error as? MIDIExerciseError else {
                return XCTFail("Se esperaba exigir metaevento de tempo, se obtuvo: \(error)")
            }
        }
    }

    func testCommunityMIDIRejectsZeroTempo() throws {
        let url = try writeCommunityMIDI(track: tempoTrack(notes: [(0, 36)], tempo: [0x00, 0x00, 0x00]))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .invalidTempo = error as? MIDIExerciseError else {
                return XCTFail("Se esperaba rechazar tempo cero, se obtuvo: \(error)")
            }
        }
    }

    func testCommunityMIDIRejectsOffGridSubdivision() throws {
        // División 480: semicorchea = 120 ticks. El tick 60 no cae en rejilla de 16 ni de 12.
        let url = try writeCommunityMIDI(track: tempoTrack(notes: [(0, 36), (60, 38)]))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .unsupportedSubdivision(let tick) = error as? MIDIExerciseError, tick == 60 else {
                return XCTFail("Se esperaba rechazar el tick 60, se obtuvo: \(error)")
            }
        }
    }

    func testKitRejectsDuplicateGMNote() {
        let kit = KitManifest(format: 1, id: "test", name: "Test", sounds: [
            .init(id: "kick", label: "Bombo", file: "kick.wav", gmNote: 36, chokeGroup: nil),
            .init(id: "snare", label: "Caja", file: "snare.wav", gmNote: 36, chokeGroup: nil)
        ])

        XCTAssertThrowsError(try kit.validate()) { error in
            guard case .duplicateNoteNumber(let note) = error as? ResourceValidationError, note == 36 else {
                return XCTFail("Se esperaba nota GM duplicada, se obtuvo: \(error)")
            }
        }
    }

    func testKitRejectsUnknownSoundID() {
        let kit = KitManifest(format: 1, id: "test", name: "Test", sounds: [
            .init(id: "bombo", label: "Bombo", file: "bombo.wav", gmNote: 36, chokeGroup: nil)
        ])

        XCTAssertThrowsError(try kit.validate()) { error in
            guard case .unknownSound(let id) = error as? ResourceValidationError, id == "bombo" else {
                return XCTFail("Se esperaba sonido fuera del catalogo, se obtuvo: \(error)")
            }
        }
    }

    func testPadMapV2DuplicatePadIDReportsID() {
        let map = PadMapV2(id: "test", name: "Test", preset: .custom, device: .init(name: "Pad", uid: 1), created: "2026-09-20", pads: [
            .init(id: "r0c0", row: 0, column: 0, sound: "kick", input: .init(number: 36, channel: 10)),
            .init(id: "r0c0", row: 0, column: 1, sound: "snare", input: .init(number: 38, channel: 10))
        ])

        XCTAssertThrowsError(try map.validate(availableSounds: ["kick", "snare"])) { error in
            guard case .duplicatePadID(let id) = error as? PadMapValidationError, id == "r0c0" else {
                return XCTFail("Se esperaba id de pad duplicado, se obtuvo: \(error)")
            }
        }
    }

    func testPadMapV2DuplicateRoleReportsRole() {
        let map = PadMapV2(id: "test", name: "Test", preset: .custom, device: .init(name: "Pad", uid: 1), created: "2026-09-20", pads: [
            .init(id: "r0c0", row: 0, column: 0, sound: "kick", role: "kick_left", input: .init(number: 36, channel: 10)),
            .init(id: "r0c1", row: 0, column: 1, sound: "kick", role: "kick_left", input: .init(number: 37, channel: 10))
        ])

        XCTAssertThrowsError(try map.validate(availableSounds: ["kick"])) { error in
            guard case .duplicateRole(let role) = error as? PadMapValidationError, role == "kick_left" else {
                return XCTFail("Se esperaba rol duplicado, se obtuvo: \(error)")
            }
        }
    }

    func testExerciseRejectsInvalidVelocity() {
        let exercise = Exercise(
            format: 1, id: "test", title: "Test", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick", velocity: 200)]
        )

        XCTAssertThrowsError(try exercise.validate(availableSounds: ["kick"])) { error in
            guard case .invalidVelocity(let velocity) = error as? ResourceValidationError, velocity == 200 else {
                return XCTFail("Se esperaba velocity invalida, se obtuvo: \(error)")
            }
        }
    }

    func testHihatTakesTheFreeHandOnSimultaneousHits() throws {
        // División 480: paso = 120 ticks. Caja+charles en el paso 0, bombo+charles en el paso 4.
        // El kit de prueba no trae charles: se usa el real con hihat_closed (42).
        let kit = try ResourceCatalog().loadKit(at: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let url = try writeCommunityMIDI(track: tempoTrack(notes: [(0, 38), (0, 42), (480, 36), (0, 42)]))
        defer { try? FileManager.default.removeItem(at: url) }
        let exercise = try MIDIExerciseLoader.load(url: url, kit: kit, level: 1)

        let hands = Dictionary(uniqueKeysWithValues: exercise.notes.map { ("\($0.step):\($0.sound)", $0.hand) })
        XCTAssertEqual(hands["0:snare"], "R")
        XCTAssertEqual(hands["0:hihat_closed"], "L", "Con caja simultanea el charles va con la izquierda")
        XCTAssertEqual(hands["4:kick"], "L")
        XCTAssertEqual(hands["4:hihat_closed"], "R", "Con bombo simultaneo el charles va con la derecha")
    }

    func testExerciseRejectsGridOutsideTwelveOrSixteen() {
        let exercise = Exercise(
            format: 1, id: "test", title: "Test", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 8, repeats: 1,
            kit: "kit", loop: nil, offset: 0, notes: []
        )

        XCTAssertThrowsError(try exercise.validate(availableSounds: [])) { error in
            guard case .invalidGrid(let grid) = error as? ResourceValidationError, grid == 8 else {
                return XCTFail("Se esperaba rejilla invalida, se obtuvo: \(error)")
            }
        }
    }
}
