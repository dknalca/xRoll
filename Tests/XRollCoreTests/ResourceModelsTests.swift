import XCTest
import SQLite3
import AVFoundation
@testable import XRollCore

final class ResourceModelsTests: XCTestCase {
    func testEveryPendingLessonPreparesAtATempoThatActuallyAllowsCourseProgress() throws {
        for node in try campaignGraph().nodes {
            let lesson = node.exercise
            let prepared = CourseLessonCriteria.preparationStep(for: lesson, evidence: [])
            XCTAssertEqual(prepared.bpm, CourseLessonCriteria.targetBPM(for: lesson), lesson.id)
            let attempt = CourseAttemptEvidence(exerciseID: lesson.id, bpm: prepared.bpm, score: 70, stars: 1,
                trainingContext: .init(evaluationScope: .fullPattern, completedBars: lesson.bars))
            XCTAssertTrue(CourseLessonCriteria.isPassed(lesson, evidence: [attempt]), lesson.id)
            let optional = CourseLessonCriteria.preparationStep(for: lesson, evidence: [attempt])
            XCTAssertGreaterThan(optional.bpm, prepared.bpm,
                "Una lección superada no debe volver a un tempo inferior: \(lesson.id)")
            XCTAssertFalse(TempoLadder.isPassed(optional, exerciseID: lesson.id, evidence: [attempt]), lesson.id)
        }
    }

    func testPassedLessonPreparesTheNextHigherChallengeInsteadOfRepeatingALowerStep() throws {
        let lesson = try XCTUnwrap(try campaignGraph().node(for: "02_sub_03_groove")).exercise
        let attempt = CourseAttemptEvidence(exerciseID: lesson.id, bpm: 72, score: 70, stars: 1,
            trainingContext: .init(evaluationScope: .fullPattern, completedBars: lesson.bars))
        let next = CourseLessonCriteria.preparationStep(for: lesson, evidence: [attempt])
        XCTAssertEqual(next.bpm, 85, "Superar 72 BPM no debe proponer el escalón inferior de 70 BPM")
        XCTAssertEqual(next.label, "Base")
    }

    func testOptionalTempoChallengeKeepsUnmetDurationWithoutGrantingOtherTempoAwards() throws {
        let lesson = try XCTUnwrap(try campaignGraph().node(for: "02_sub_03_groove")).exercise
        func attempt(bpm: Int, bars: Int, scope: EvaluationScope = .fullPattern) -> CourseAttemptEvidence {
            .init(exerciseID: lesson.id, bpm: bpm, score: 90, stars: 3,
                trainingContext: .init(evaluationScope: scope, completedBars: bars))
        }
        let short = attempt(bpm: 160, bars: 4)
        let pending = try XCTUnwrap(CourseLessonCriteria.optionalTempoStep(for: lesson, evidence: [short]))
        XCTAssertEqual(pending.bpm, 160, "Faltan los 16 compases, no más velocidad")
        XCTAssertEqual(pending.minimumBars, 16)
        XCTAssertEqual(CourseLessonCriteria.preparationStep(for: lesson, evidence: [short]), pending)
        XCTAssertGreaterThanOrEqual((TempoLadder.repeats(for: pending, exercise: lesson) ?? 1) * lesson.bars, 16)
        XCTAssertFalse(TempoLadder.isPassed(pending, exerciseID: lesson.id, evidence: [short]))
        let complete = attempt(bpm: 160, bars: 16)
        XCTAssertNil(CourseLessonCriteria.optionalTempoStep(for: lesson, evidence: [complete]))
        XCTAssertNil(CourseLessonCriteria.optionalTempoStep(for: lesson, evidence: [attempt(bpm: 180, bars: 16)]))
        XCTAssertFalse(TempoLadder.isPassed(pending, exerciseID: lesson.id, evidence: [attempt(bpm: 180, bars: 16)]),
            "Tocar a 180 no acredita el premio de 160")
        let partial = attempt(bpm: 160, bars: 16, scope: .selectedVoices)
        XCTAssertEqual(CourseLessonCriteria.optionalTempoStep(for: lesson, evidence: [partial])?.bpm, 85)
        for node in try campaignGraph().nodes {
            XCTAssertGreaterThan(try XCTUnwrap(CourseLessonCriteria.optionalTempoStep(for: node.exercise, evidence: [])).bpm,
                CourseLessonCriteria.targetBPM(for: node.exercise), node.exercise.id)
        }
    }

    func testLearningRecoveryUsesSmallTempoStepsWithoutAccreditingSlowOrPartialAttempts() throws {
        let lesson = try XCTUnwrap(try campaignGraph().node(for: "02_sub_03_groove")).exercise
        func attempt(bpm: Int, score: Double, scope: EvaluationScope = .fullPattern, phase: TrainingPhase = .integrate) -> CourseAttemptEvidence {
            .init(exerciseID: lesson.id, bpm: bpm, score: score, stars: score >= 70 ? 1 : 0,
                trainingContext: .init(phase: phase, evaluationScope: scope, completedBars: 8))
        }
        let failed = attempt(bpm: 72, score: 50)
        let support = try XCTUnwrap(CourseLessonCriteria.recovery(for: lesson, attempt: failed, evidence: []))
        XCTAssertEqual(support.bpm, 68)
        XCTAssertEqual(support.repeats, 4)
        XCTAssertEqual(support.actionTitle, "Reintentar")
        let slow = attempt(bpm: 68, score: 90)
        XCTAssertFalse(CourseLessonCriteria.isPassed(lesson, evidence: [failed,slow]))
        XCTAssertEqual(CourseLessonCriteria.recovery(for: lesson, attempt: slow, evidence: [failed])?.bpm, 72)
        XCTAssertEqual(CourseLessonCriteria.recovery(for: lesson, attempt: attempt(bpm: 68, score: 75), evidence: [])?.bpm, 70)
        XCTAssertEqual(CourseLessonCriteria.recovery(for: lesson, attempt: attempt(bpm: 71, score: 90), evidence: [])?.bpm, 72)
        XCTAssertEqual(CourseLessonCriteria.recovery(for: lesson, attempt: attempt(bpm: 40, score: 10), evidence: [])?.bpm, 40)
        for scope in [EvaluationScope.selectedVoices, .fragment, .corrective, .legacyUnknown] {
            XCTAssertNil(CourseLessonCriteria.recovery(for: lesson, attempt: attempt(bpm: 68, score: 90, scope: scope), evidence: []))
        }
        XCTAssertNil(CourseLessonCriteria.recovery(for: lesson, attempt: attempt(bpm: 68, score: 90, phase: .transfer), evidence: []))
        let passed = attempt(bpm: 72, score: 70)
        XCTAssertNil(CourseLessonCriteria.recovery(for: lesson, attempt: passed, evidence: []))
        XCTAssertNil(CourseLessonCriteria.recovery(for: lesson, attempt: failed, evidence: [passed]))
        let longLesson = try XCTUnwrap(try campaignGraph().checkpoint(for: "jazz-intermediate")).exercise
        let longAttempt = CourseAttemptEvidence(exerciseID: longLesson.id, bpm: 72, score: 30,
            trainingContext: .init(evaluationScope: .fullPattern, completedBars: 8))
        XCTAssertEqual(CourseLessonCriteria.recovery(for: longLesson, attempt: longAttempt, evidence: [])?.repeats, 1,
            "El apoyo conserva la frase completa de ocho compases")
    }

    func testCommonTrunkKeepsGroovesAndItsCheckpointsOnlyUsePreviouslyTaughtVocabulary() throws {
        let graph = try campaignGraph()
        let initiation = try XCTUnwrap(graph.checkpoint(for: "initiation")).exercise
        let firstFoundation = try XCTUnwrap(graph.node(for: "01_fund_01_pulso")).exercise
        func cells(_ exercise: Exercise) -> Set<String> {
            Set(exercise.notes.map { "\($0.sound):\($0.step % exercise.grid)" })
        }
        XCTAssertTrue(cells(firstFoundation).isSuperset(of: cells(initiation)), "Fundamentos no retira el motor ya aprendido")
        for chapter in ["fundamentals", "coordination", "subdivision", "groove"] {
            let lessons = graph.nodes.filter { $0.metadata.chapter == chapter }.map(\.exercise)
            XCTAssertEqual(Set(lessons.map(\.bpm)).count, 1, chapter)
            for lesson in lessons {
                XCTAssertTrue(Set(lesson.notes.map(\.sound)).isSuperset(of: ["kick", "snare", "hihat_closed"]), lesson.id)
                XCTAssertGreaterThanOrEqual(lesson.notes.count, 8, lesson.id)
                XCTAssertTrue(Dictionary(grouping: lesson.notes, by: \.step).values.allSatisfy { $0.count <= 2 }, lesson.id)
            }
            let learned = lessons.dropLast().reduce(into: Set<String>()) { $0.formUnion(cells($1)) }
            let final = try XCTUnwrap(lessons.last)
            XCTAssertEqual(cells(final), learned, "El cierre integra lo aprendido sin introducir células nuevas: \(chapter)")
        }
    }

    func testCalibrationStillUsesOnlyRegularHiHatWhenItsSourceLessonIsACompleteGroove() throws {
        let source = try XCTUnwrap(try campaignGraph().node(for: "02_sub_02_corcheas")).exercise
        XCTAssertGreaterThan(Set(source.notes.map(\.sound)).count, 1)
        let calibration = PracticeConfiguration.calibrationExercise(from: source)
        XCTAssertEqual(Set(calibration.notes.map(\.sound)), ["hihat_closed"])
        XCTAssertEqual(calibration.notes.map(\.step), Array(stride(from: 0, to: 16, by: 2)))
        XCTAssertEqual(calibration.repeats, 8)
        XCTAssertEqual(ExerciseTimeline(exercise: calibration).notes.count, 64)
        XCTAssertEqual(calibration.bpm, source.bpm)
    }

    func testTouchPracticeProjectionUsesOnlyRequiredSoundsInStableMapOrder() {
        for preset in [PadLayoutPreset.core, .drumKit, .mirror] {
            let map = PadLayoutFactory.make(preset, device: .init(name: "Táctil", uid: 0))
            let notes: [Exercise.Note] = [.init(step: 8, sound: "snare"), .init(step: 0, sound: "kick"),
                .init(step: 1, sound: "hihat_closed"), .init(step: 2, sound: "kick")]
            let compact = map.practicePads(for: notes)
            XCTAssertEqual(compact.count, 3)
            XCTAssertEqual(Set(compact.map(\.sound)), ["kick", "snare", "hihat_closed"])
            XCTAssertEqual(compact, map.practicePads(for: Array(notes.reversed())))
            XCTAssertTrue(compact.allSatisfy { map.pads.contains($0) }, "Debe conservar ID, rol, nota y canal del pad original")
            XCTAssertEqual(map.pads.count, 16, "Equipo conserva su rejilla completa")
            XCTAssertTrue(map.practicePads(for: []).isEmpty)
            XCTAssertEqual(map.practicePads(for: [.init(step: 0, sound: "hihat_closed")]).count, 1,
                "La calibración de charles solo necesita un botón")
        }
    }

    func testTouchPracticeProjectionPreservesExactPadAndRoleTargets() throws {
        let map = PadLayoutFactory.make(.drumKit, device: .init(name: "Táctil", uid: 0))
        let left = try XCTUnwrap(map.pads.first { $0.role == "kick_left" })
        let right = try XCTUnwrap(map.pads.first { $0.role == "kick_right" })
        let notes: [Exercise.Note] = [
            .init(step: 0, sound: "kick", target: .init(type: .role, value: "kick_left")),
            .init(step: 2, sound: "kick", target: .init(type: .pad, value: right.id)),
            .init(step: 4, sound: "kick")
        ]
        XCTAssertEqual(Set(map.practicePads(for: notes).map(\.id)), [left.id, right.id])
        XCTAssertTrue(map.practicePads(for: [.init(step: 0, sound: "snare", target: .init(type: .pad, value: left.id))]).isEmpty,
            "Un ID de bombo no sirve para una caja")
        XCTAssertTrue(map.practicePads(for: [.init(step: 0, sound: "kick", target: .init(type: .role, value: "unknown"))]).isEmpty)
    }

    func testEveryBundledExerciseHasACompactProjectionOfItsMappedSounds() throws {
        let exercises = try campaignGraph().nodes.map(\.exercise)
        for preset in [PadLayoutPreset.core, .drumKit, .mirror] {
            let map = PadLayoutFactory.make(preset, device: .init(name: "Táctil", uid: 0))
            let mappedSounds = Set(map.pads.map(\.sound))
            for exercise in exercises {
                let projected = map.practicePads(for: exercise.notes)
                let sounds = Set(exercise.notes.map(\.sound)).intersection(mappedSounds)
                XCTAssertEqual(projected.count, sounds.count, exercise.id)
                XCTAssertEqual(Set(projected.map(\.sound)), sounds, exercise.id)
            }
        }
    }

    func testJazzCoursesHaveDistinctProgressionAndConsecutiveFinalChallenges() throws {
        let graph = try campaignGraph()
        let basic = graph.nodes.filter { $0.metadata.chapter == "jazz" }
        let intermediate = graph.nodes.filter { $0.metadata.chapter == "jazz-intermediate" }
        XCTAssertEqual(basic.count, 8)
        XCTAssertEqual(intermediate.count, 12)
        XCTAssertEqual(Set(basic.map { $0.exercise.bpm }), [64])
        XCTAssertEqual(Set(intermediate.map { $0.exercise.bpm }), [72])
        XCTAssertTrue((basic + intermediate).allSatisfy { $0.exercise.grid == 12 && $0.exercise.meter == [4,4] })
        let basicChallenge = try XCTUnwrap(graph.checkpoint(for: "jazz"))
        let intermediateChallenge = try XCTUnwrap(graph.checkpoint(for: "jazz-intermediate"))
        XCTAssertEqual(basicChallenge.exercise.id, "23_jazz_04_frase", "Conserva los registros del curso básico existente")
        XCTAssertEqual(intermediate.first?.metadata.prerequisites, [basicChallenge.exercise.id])
        XCTAssertEqual(intermediateChallenge.metadata.position, 12)
        XCTAssertEqual(intermediateChallenge.exercise.bars, 8)
        let basicIndex = try XCTUnwrap(graph.mainChapterIDs.firstIndex(of: "jazz"))
        XCTAssertEqual(graph.mainChapterIDs[basicIndex + 1], "jazz-intermediate")
        XCTAssertEqual(graph.mainChapterIDs[basicIndex + 2], "clave-bossa")
        XCTAssertEqual(graph.worlds(evidence: []).first { $0.id == "jazz" }?.title, "Jazz básico")
        XCTAssertEqual(graph.worlds(evidence: []).first { $0.id == "jazz-intermediate" }?.title, "Jazz intermedio")
        for node in intermediate.dropFirst() {
            XCTAssertTrue(node.exercise.notes.contains { $0.sound == "hihat_closed" && $0.step % 12 == 3 },
                "Mantiene la referencia de dos al añadir comping y fills: \(node.exercise.id)")
        }
        XCTAssertEqual(Set(intermediate.compactMap { $0.metadata.newDifficulty }).count, 12)
    }

    private func campaignGraph() throws -> CourseGraph {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        return try CourseGraph(exercises: catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit))
    }

    private func campaignPass(_ exercise: Exercise) -> CourseAttemptEvidence {
        .init(exerciseID: exercise.id, bpm: CourseLessonCriteria.targetBPM(for: exercise), score: 70, stars: 1,
            trainingContext: .init(evaluationScope: .fullPattern, completedBars: exercise.bars))
    }

    func testCampaignHasOneCurrentWorldOneNextLevelAndOneFinalBossPerWorld() throws {
        let graph = try campaignGraph()
        let worlds = graph.worlds(evidence: [])
        XCTAssertEqual(worlds.count, 15)
        XCTAssertEqual(worlds.map(\.id), graph.mainChapterIDs)
        XCTAssertEqual(worlds.flatMap(\.levels).count, 121)
        XCTAssertEqual(worlds.filter(\.isCurrent).map(\.id), ["initiation"])
        XCTAssertEqual(worlds.flatMap(\.levels).filter(\.isNext).count, 1)
        XCTAssertEqual(worlds.first?.nextLevel?.number, 1)
        XCTAssertFalse(worlds.first?.isBossReady ?? true)
        for world in worlds {
            XCTAssertEqual(world.levels.map(\.number), Array(1...world.levels.count))
            XCTAssertEqual(world.levels.filter(\.isBoss).count, 1)
            XCTAssertEqual(world.levels.last?.id, world.boss?.id)
            XCTAssertFalse(world.isCompleted)
            XCTAssertFalse(world.id.hasPrefix("fills-"))
        }
    }

    func testRailwayPresentationUsesStationLabelsAndOneSharedChallengeAction() throws {
        let graph = try campaignGraph()
        let stations = graph.worlds(evidence: [])
        let first = try XCTUnwrap(stations.first)
        XCTAssertEqual(first.statusLabel, "Tu parada actual")
        XCTAssertEqual(stations[1].statusLabel, "Próxima parada")
        XCTAssertEqual(first.nextLevel?.actionTitle, "Empezar nivel 1")
        XCTAssertEqual(first.boss?.label, "Reto de estación")
        XCTAssertEqual(first.boss?.actionTitle, "Preparar reto final")
        XCTAssertEqual(first.boss?.continuationTitle, first.boss?.actionTitle)
        XCTAssertEqual(CourseWorld.challengeTitle(for: first.id), "Reto de estación · Iniciación")
        let passed = campaignPass(try XCTUnwrap(first.boss).exercise)
        let completion = try XCTUnwrap(graph.worldVictory(completing: passed, previousEvidence: []))
        XCTAssertEqual(completion.title, "¡Estación 1 completada!")
        XCTAssertEqual(completion.actionTitle, "Siguiente parada")
        XCTAssertTrue(completion.message.contains("Próxima parada: 2 · Fundamentos"))
        XCTAssertEqual(graph.worlds(evidence: [passed])[0].statusLabel, "Estación completada")
    }

    func testCampaignBossIsRecommendedAfterRegularLevelsAndVictoryNeedsEligibleFullPattern() throws {
        let graph = try campaignGraph()
        let world = try XCTUnwrap(graph.worlds(evidence: []).first)
        let regular = world.levels.filter { !$0.isBoss }.map { campaignPass($0.exercise) }
        let first = try XCTUnwrap(regular.first)
        XCTAssertEqual(graph.campaignContinuation(after: first, evidence: [first])?.number, 2,
            "Una estrella al 70 % permite continuar sin imponer un reto de tempo")
        let ready = try XCTUnwrap(graph.worlds(evidence: regular).first)
        XCTAssertTrue(ready.isBossReady)
        XCTAssertFalse(ready.isCompleted)
        let boss = try XCTUnwrap(ready.boss).exercise
        XCTAssertTrue(graph.campaignContinuation(after: try XCTUnwrap(regular.last), evidence: regular)?.isBoss ?? false)
        for scope in [EvaluationScope.selectedVoices, .fragment, .corrective, .legacyUnknown] {
            let partial = CourseAttemptEvidence(exerciseID: boss.id, bpm: boss.bpm, score: 100, stars: 3,
                trainingContext: .init(evaluationScope: scope, completedBars: 8))
            XCTAssertNil(graph.worldVictory(completing: partial, previousEvidence: regular))
            XCTAssertNil(graph.campaignContinuation(after: partial, evidence: regular + [partial]))
        }
        let slow = CourseAttemptEvidence(exerciseID: boss.id, bpm: CourseLessonCriteria.targetBPM(for: boss) - 1,
            score: 100, stars: 3, trainingContext: .init(evaluationScope: .fullPattern, completedBars: 8))
        XCTAssertNil(graph.worldVictory(completing: slow, previousEvidence: regular))
        let failed = CourseAttemptEvidence(exerciseID: boss.id, bpm: boss.bpm, score: 69.99, stars: 0,
            trainingContext: .init(evaluationScope: .fullPattern, completedBars: 8))
        XCTAssertNil(graph.worldVictory(completing: failed, previousEvidence: regular))
        let passed = campaignPass(boss)
        let victory = try XCTUnwrap(graph.worldVictory(completing: passed, previousEvidence: regular))
        XCTAssertEqual(victory.worldNumber, 1)
        XCTAssertEqual(victory.nextWorldTitle, "Fundamentos")
        let after = graph.worlds(evidence: regular + [passed])
        XCTAssertTrue(after[0].isCompleted)
        XCTAssertTrue(after[1].isCurrent)
        XCTAssertEqual(after[0].completedLevelCount, after[0].levels.count)
        XCTAssertNil(graph.worldVictory(completing: passed, previousEvidence: regular + [passed]), "Un repaso no anuncia otro mundo nuevo")
    }

    func testFutureBossKeepsItsVictoryPendingAndCampaignContinuesAtTheFirstUnfinishedWorld() throws {
        let graph = try campaignGraph()
        let futureBoss = campaignPass(try XCTUnwrap(graph.checkpoint(for: "fundamentals")).exercise)
        XCTAssertNil(graph.worldVictory(completing: futureBoss, previousEvidence: []))
        XCTAssertNil(graph.campaignContinuation(after: futureBoss, evidence: [futureBoss]))
        let pending = graph.worlds(evidence: [futureBoss])
        XCTAssertTrue(pending[0].isCurrent)
        XCTAssertFalse(pending[1].isCompleted)
        XCTAssertTrue(pending[1].boss?.isPassed ?? false)
        let firstBoss = campaignPass(try XCTUnwrap(graph.checkpoint(for: "initiation")).exercise)
        let victory = try XCTUnwrap(graph.worldVictory(completing: firstBoss, previousEvidence: [futureBoss]))
        XCTAssertEqual(victory.nextWorldNumber, 3)
        XCTAssertEqual(victory.nextWorldTitle, "Coordinación")
    }

    func testCompletedCampaignIsRebuiltFromStoredEvidenceAfterReopening() throws {
        let graph = try campaignGraph()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("campaign.sqlite")
        let passes = try graph.mainChapterIDs.map { campaignPass(try XCTUnwrap(graph.checkpoint(for: $0)).exercise) }
        let last = try XCTUnwrap(passes.last)
        let finale = try XCTUnwrap(graph.worldVictory(completing: last, previousEvidence: Array(passes.dropLast())))
        XCTAssertNil(finale.nextWorldNumber)
        XCTAssertEqual(finale.actionTitle, "Ver mi recorrido")
        do {
            let store = try ProgressStore(url: url)
            for pass in passes {
                try store.record(.init(exerciseID: pass.exerciseID, timestamp: Date(), bpm: pass.bpm,
                    score: pass.score, stars: pass.stars, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0,
                    meanOffsetMilliseconds: 0, trainingContext: pass.trainingContext))
            }
        }
        let reopened = try ProgressStore(url: url)
        let worlds = graph.worlds(evidence: try reopened.courseEvidence())
        XCTAssertTrue(worlds.allSatisfy(\.isCompleted))
        XCTAssertTrue(worlds.allSatisfy { !$0.isCurrent && $0.nextLevel == nil })
    }

    func testMIDIRealtimeBytesDoNotConsumeNoteDataOrRunningStatus() {
        let hostTime = AudioClock.currentHostTime()
        let expected = MIDIByteDecoder.noteOnEvents(bytes: [0x90, 36, 100, 38, 110], hostTime: hostTime)
        for realtime in UInt8(0xF8)...UInt8(0xFF) {
            let interleaved: [UInt8] = [realtime, 0x90, realtime, 36, realtime, 100, realtime, 38, realtime, 110, realtime]
            XCTAssertEqual(MIDIByteDecoder.noteOnEvents(bytes: interleaved, hostTime: hostTime), expected)
        }
    }

    func testMIDIIncompleteMessageDoesNotConsumeTheNextStatus() {
        let events = MIDIByteDecoder.noteOnEvents(bytes: [0x90, 36, 0x91, 38, 110, 0xF8, 40, 0], hostTime: AudioClock.currentHostTime())
        XCTAssertEqual(events.map(\.note), [38])
        XCTAssertEqual(events.map(\.channel), [2])
        XCTAssertEqual(events.map(\.velocity), [110])
    }

    func testPracticeFragmentsSplitTheWholePhraseAndIntersectCorrectiveRange() {
        for grid in [12, 16] {
            let exercise = Exercise(format: 1, id: "phrase", title: "Frase", family: "test", level: 1,
                bpm: 80, meter: [4, 4], bars: 4, grid: grid, repeats: 2, kit: "kit", loop: nil, offset: 0,
                notes: (0..<(4 * grid)).map { .init(step: $0, sound: "kick") })
            let first = PracticeConfiguration.notes(in: exercise, fragment: 1)
            let second = PracticeConfiguration.notes(in: exercise, fragment: 2)
            XCTAssertEqual(first.count, 2 * grid)
            XCTAssertEqual(second.count, 2 * grid)
            XCTAssertEqual(first + second, exercise.notes)
            XCTAssertEqual(PracticeConfiguration.notes(in: exercise, fragment: 0), exercise.notes)
            let cell = PracticeConfiguration.notes(in: exercise, fragment: 2, stepRange: (2 * grid - 1)...(2 * grid + 1))
            XCTAssertEqual(cell.map(\.step), [2 * grid, 2 * grid + 1])
        }
    }

    func testInterruptedPracticeCannotClaimAllBarsOrEarnTheLongTempoAward() {
        let exercise = Exercise(format: 1, id: "duration", title: "Duración", family: "test", level: 1,
            bpm: 160, meter: [4, 4], bars: 1, grid: 16, repeats: 16, kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")])
        let session = PracticeSession(exercise: exercise)
        for note in session.timeline.notes.prefix(12) {
            session.register(.init(sound: note.sound, timeMilliseconds: note.timeMilliseconds))
        }
        let completion = PracticeCompletion(exercise: exercise, elapsedMilliseconds: session.timeline.barDurationMilliseconds * 12)
        let context = completion.context(from: .init(evaluationScope: .fullPattern))
        XCTAssertEqual(session.score.percentage, 75)
        XCTAssertEqual(completion.completedBars, 12)
        XCTAssertFalse(completion.isComplete)
        XCTAssertEqual(context.evaluationScope, .fragment)
        let evidence = CourseAttemptEvidence(exerciseID: exercise.id, bpm: 160, score: session.score.percentage,
            stars: session.score.stars, trainingContext: context)
        let step = TempoLadder.steps(for: exercise).last!
        XCTAssertFalse(TempoLadder.isPassed(step, exerciseID: exercise.id, evidence: [evidence]))
        XCTAssertFalse(TempoLadder.isConsolidated(exercise, evidence: [evidence]))
        XCTAssertEqual(PracticeCompletion(exercise: exercise, elapsedMilliseconds: -1).completedBars, 0)
        let finished = PracticeCompletion(exercise: exercise, elapsedMilliseconds: session.timeline.barDurationMilliseconds * 16)
        XCTAssertTrue(finished.isComplete)
        XCTAssertEqual(finished.context(from: .init(evaluationScope: .fullPattern)).completedBars, 16)
        XCTAssertEqual(finished.context(from: .init(evaluationScope: .selectedVoices)).evaluationScope, .selectedVoices)
    }

    func testCalibrationIngressKeepsRawOffsetsOutsideScoringWindows() {
        let exercise = Exercise(format: 1, id: "raw-calibration", title: "Calibración", family: "test", level: 1,
            bpm: 72, meter: [4, 4], bars: 1, grid: 16, repeats: 2, kit: "kit", loop: nil, offset: 0,
            notes: stride(from: 0, to: 16, by: 2).map { .init(step: $0, sound: "hihat_closed") })
        for offset in [-120.0, 120.0] {
            let ingress = PracticeSessionIngress()
            let session = PracticeSession(exercise: exercise)
            let finished = expectation(description: "cerrar calibración bruta \(offset)")
            var rawOffsets = [Double]()
            ingress.begin(session, generation: UUID(), calibration: true)
            for note in session.timeline.notes {
                ingress.submit(.init(sound: note.sound, timeMilliseconds: note.timeMilliseconds + offset)) { _, result in
                    if let association = result.calibrationAssociation { rawOffsets.append(association.rawOffsetMilliseconds) }
                }
            }
            ingress.finish { _, score in
                XCTAssertTrue(score?.hits.compactMap(\.offsetMilliseconds).isEmpty == true)
                XCTAssertEqual(rawOffsets.count, 16)
                do {
                    let estimate = try CalibrationEstimator.estimate(rawOffsetsMilliseconds: rawOffsets)
                    XCTAssertEqual(estimate.offsetMilliseconds, offset, accuracy: 0.001)
                    XCTAssertEqual(estimate.acceptedHitCount, 12)
                } catch { XCTFail("La calibración bruta debe admitir este desfase: \(error)") }
                finished.fulfill()
            }
            wait(for: [finished], timeout: 2)
        }
    }

    func testHostTimeIngressRejectsStaleHitsAfterRestartAndUsesTheNewClock() {
        let exercise = Exercise(format: 1, id: "host-generation", title: "Generaciones", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")])
        let ingress = PracticeSessionIngress()
        let base = AudioClock.currentHostTime()
        let firstStart = AudioClock.hostTime(afterMilliseconds: 1_000, from: base)
        ingress.begin(PracticeSession(exercise: exercise), generation: UUID(), startHostTime: firstStart, admissionHostTime: base)
        let cancelled = expectation(description: "cancelar generación anterior")
        ingress.cancel { _ in cancelled.fulfill() }
        XCTAssertNil(ingress.submit(sound: "kick", hostTime: firstStart) { _, _ in XCTFail("La entrada cancelada debe estar cerrada.") })

        let secondAdmission = AudioClock.hostTime(afterMilliseconds: 2_000, from: base)
        let secondStart = AudioClock.hostTime(afterMilliseconds: 3_000, from: base)
        let secondGeneration = UUID()
        ingress.begin(PracticeSession(exercise: exercise), generation: secondGeneration,
            startHostTime: secondStart, admissionHostTime: secondAdmission)
        XCTAssertNil(ingress.submit(sound: "kick", hostTime: firstStart) { _, _ in XCTFail("Un golpe viejo no debe entrar en el nuevo reloj.") })
        let finished = expectation(description: "cerrar con el reloj nuevo")
        XCTAssertEqual(ingress.submit(sound: "kick", hostTime: secondStart) { generation, result in
            XCTAssertEqual(generation, secondGeneration)
            XCTAssertEqual(result.scoredHit?.hit.timeMilliseconds ?? -1, 0, accuracy: 0.001)
            XCTAssertEqual(result.scoredHit?.judgement, .perfect)
        }, secondGeneration)
        ingress.finish { generation, score in
            XCTAssertEqual(generation, secondGeneration)
            XCTAssertEqual(score?.percentage, 100)
            XCTAssertEqual(score?.hits.count, 1)
            finished.fulfill()
        }
        XCTAssertNil(ingress.submit(sound: "kick", hostTime: secondStart) { _, _ in XCTFail("El cierre ya rechazó nuevas entradas.") })
        wait(for: [cancelled, finished], timeout: 2)
    }

    func testHostTimeIngressFinalScoreDoesNotWaitForPresentation() {
        let exercise = Exercise(format: 1, id: "delayed-ui", title: "Interfaz ocupada", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")])
        let ingress = PracticeSessionIngress()
        let base = AudioClock.currentHostTime()
        let generation = UUID()
        let presentation = DispatchQueue(label: "xRoll.test.delayed-presentation")
        presentation.suspend()
        let rendered = expectation(description: "presentar después del cierre")
        let finished = expectation(description: "score sin esperar a la interfaz")
        ingress.begin(PracticeSession(exercise: exercise), generation: generation, startHostTime: base, admissionHostTime: base)
        ingress.submit(sound: "kick", hostTime: base) { returnedGeneration, result in
            presentation.async {
                XCTAssertEqual(returnedGeneration, generation)
                XCTAssertEqual(result.scoredHit?.judgement, .perfect)
                rendered.fulfill()
            }
        }
        ingress.finish { _, score in
            XCTAssertEqual(score?.percentage, 100)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        presentation.resume()
        wait(for: [rendered], timeout: 2)
    }

    func testResourceValidationThrowsWhenRequiredSamplesAreMissing() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let directory = root.appendingPathComponent("Resources/Kits/hiphop_basic")
        let kit = try catalog.loadKit(at: directory.appendingPathComponent("kit.json"))
        let missingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try catalog.validateSampleFiles(for: kit, in: missingDirectory)) { error in
            XCTAssertEqual(error as? ResourceValidationError, .missingSampleFiles(kit.sounds.map(\.file)))
        }
        XCTAssertNoThrow(try catalog.validateSampleFiles(for: kit, in: directory))
    }

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

    func testAudioEngineUsesSynthesizedMetronomeWithoutOptionalSample() throws {
        let kitURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Kits/hiphop_basic/kit.json")
        let kit = try ResourceCatalog().loadKit(at: kitURL)
        let engine = SampleAudioEngine()

        try engine.load(kit: kit, from: kitURL.deletingLastPathComponent())

        XCTAssertEqual(engine.metronomeSourceName, "claqueta sintetizada")
    }

    func testScheduledChokeCutsThePreviousHiHatAtTheNextHitTime() {
        let sampleFrameCount: AVAudioFrameCount = 18_000
        let sampleRate = 44_100.0
        let start = AudioClock.currentHostTime()
        let nextSixteenth = AudioClock.hostTime(afterMilliseconds: 93.75, from: start)
        let frames = SampleAudioEngine.scheduledSegmentFrameCount(
            sampleFrameCount: sampleFrameCount, sampleRate: sampleRate,
            startHostTime: start, chokeHostTime: nextSixteenth)

        XCTAssertGreaterThan(frames, 0)
        XCTAssertLessThan(frames, sampleFrameCount)
        XCTAssertLessThanOrEqual(Double(frames) / sampleRate * 1_000, 93.75)
        XCTAssertEqual(SampleAudioEngine.scheduledSegmentFrameCount(
            sampleFrameCount: sampleFrameCount, sampleRate: sampleRate,
            startHostTime: start, chokeHostTime: start), 0)
        XCTAssertEqual(SampleAudioEngine.scheduledSegmentFrameCount(
            sampleFrameCount: sampleFrameCount, sampleRate: sampleRate,
            startHostTime: nextSixteenth, chokeHostTime: start), 0)
        XCTAssertEqual(SampleAudioEngine.scheduledSegmentFrameCount(
            sampleFrameCount: sampleFrameCount, sampleRate: sampleRate,
            startHostTime: start, chokeHostTime: AudioClock.hostTime(afterMilliseconds: 100_000_000, from: start)),
            sampleFrameCount, "Un intervalo largo no debe desbordar AVAudioFrameCount")
    }

    func testScheduledHitsChokeTheSameSoundAndShareExplicitChokeGroups() {
        XCTAssertEqual(
            SampleAudioEngine.scheduledChokeKey(soundID: "kick", chokeGroup: nil),
            "sound:kick"
        )
        XCTAssertNotEqual(
            SampleAudioEngine.scheduledChokeKey(soundID: "kick", chokeGroup: nil),
            SampleAudioEngine.scheduledChokeKey(soundID: "snare", chokeGroup: nil)
        )
        XCTAssertEqual(
            SampleAudioEngine.scheduledChokeKey(soundID: "hihat_open", chokeGroup: "hihat"),
            SampleAudioEngine.scheduledChokeKey(soundID: "hihat_closed", chokeGroup: "hihat")
        )
    }

    func testNeutralMetronomeBypassesThePitchProcessor() {
        XCTAssertTrue(SampleAudioEngine.usesDirectMetronome(pitchCents: 0))
        XCTAssertTrue(SampleAudioEngine.usesDirectMetronome(pitchCents: 0.4))
        XCTAssertFalse(SampleAudioEngine.usesDirectMetronome(pitchCents: 100))
    }

    func testRapidLiveHiHatHitsRenderWithoutAudioHardware() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Resources/Kits/hiphop_basic")
        let kit = try ResourceCatalog().loadKit(at: directory.appendingPathComponent("kit.json"))
        let engine = AVAudioEngine()
        let audio = SampleAudioEngine(engine: engine)
        try audio.load(kit: kit, from: directory)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        try audio.start()
        defer { audio.stop() }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))

        // Más de una vuelta del pool, semicorcheas a 160/240 BPM y dobles.
        // Se inspecciona el PCM renderizado, no solo el estado isPlaying.
        for frameCount: AVAudioFrameCount in [4_096, 2_756, 2_048] {
            for hit in 0..<32 {
                try audio.play(soundID: "hihat_closed")
                XCTAssertEqual(try engine.renderOffline(frameCount, to: output), .success)
                let channels = try XCTUnwrap(output.floatChannelData)
                let peak = (0..<Int(output.frameLength)).reduce(Float.zero) {
                    max($0, abs(channels[0][$1]), abs(channels[1][$1]))
                }
                XCTAssertGreaterThan(peak, 0.01, "Golpe mudo \(hit), intervalo \(frameCount) frames")
            }
        }
    }

    func testLiveChokeCutsOnlyItsGroupAndSurvivesRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-choke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        // Señales sintéticas: una cola sostenida y un ataque corto permiten
        // distinguir un choke real de una voz que simplemente dejó de sonar.
        for (name, length) in [("open", 44_100), ("closed", 64), ("other", 44_100)] {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
            buffer.frameLength = 44_100
            let channel = try XCTUnwrap(buffer.floatChannelData)[0]
            for frame in 0..<44_100 { channel[frame] = frame < length ? 0.2 : 0 }
            var settings = format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: directory.appendingPathComponent("\(name).wav"), settings: settings)
            try file.write(from: buffer)
        }
        let kit = KitManifest(format: 1, id: "choke", name: "Choke", sounds: [
            .init(id: "open", label: "Abierto", file: "open.wav", gmNote: 46, chokeGroup: "hat"),
            .init(id: "closed", label: "Cerrado", file: "closed.wav", gmNote: 42, chokeGroup: "hat"),
            .init(id: "other", label: "Otro", file: "other.wav", gmNote: 36, chokeGroup: nil)
        ])
        let engine = AVAudioEngine()
        let audio = SampleAudioEngine(engine: engine)
        try audio.load(kit: kit, from: directory)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try audio.start()
        defer { audio.stop() }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        func peak() throws -> Float {
            XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
            let channel = try XCTUnwrap(output.floatChannelData)[0]
            return (0..<Int(output.frameLength)).reduce(Float.zero) { max($0, abs(channel[$1])) }
        }
        for _ in 0..<2 {
            try audio.play(soundID: "open")
            XCTAssertGreaterThan(try peak(), 0.1)
            try audio.play(soundID: "closed")
            _ = try peak() // Renderizar el ataque y el posible bloque de transición.
            XCTAssertLessThan(try peak(), 0.000_01, "El cerrado debe cortar la cola del abierto")
            try audio.play(soundID: "other")
            _ = try peak()
            try audio.play(soundID: "closed")
            _ = try peak()
            XCTAssertGreaterThan(try peak(), 0.1, "El choke no debe cortar sonidos de otro grupo")
            audio.stop()
            try audio.start()
        }
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

    func testPadMapV2RouterIgnoresOutOfRangeInputs() {
        let map = PadMapV2(id: "invalid-inputs", name: "Mapa", preset: .custom, device: .init(name: "Pad", uid: 1), created: "2026-09-25", pads: [
            .init(id: "bad-note", row: 0, column: 0, sound: "kick", input: .init(number: 128, channel: 10)),
            .init(id: "bad-channel", row: 0, column: 1, sound: "snare", input: .init(number: 38, channel: 0)),
            .init(id: "valid", row: 0, column: 2, sound: "snare", input: .init(number: 38, channel: 10))
        ])
        let router = PadMapV2Router(map)

        XCTAssertNil(router.soundID(for: MIDINoteOn(hostTime: 1, channel: 10, note: 0, velocity: 100)))
        XCTAssertEqual(router.soundID(for: MIDINoteOn(hostTime: 2, channel: 10, note: 38, velocity: 100)), "snare")
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
        XCTAssertEqual(exercises.count, 129)
        XCTAssertNoThrow(try CurriculumValidator.validateIntegratedExercises(exercises))
        XCTAssertTrue(exercises.allSatisfy { $0.metadata != nil })
        let graph = try CourseGraph(exercises: exercises)
        let chapters = graph.nodes.map(\.metadata.chapter)
        XCTAssertTrue(graph.mainChapterIDs.allSatisfy { graph.checkpoint(for: $0) != nil })
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "fundamentals")), try XCTUnwrap(chapters.firstIndex(of: "coordination")))
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "coordination")), try XCTUnwrap(chapters.firstIndex(of: "subdivision")))
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "subdivision")), try XCTUnwrap(chapters.firstIndex(of: "groove")))
        let evidence = [
            CourseAttemptEvidence(exerciseID: "00_i_03_ritmo_completo", bpm: 72, score: 80, stars: 2, trainingContext: .init(evaluationScope: .fullPattern, completedBars: 1)),
            CourseAttemptEvidence(exerciseID: "01_fund_06_control", bpm: 70, score: 80, stars: 2, trainingContext: .init(evaluationScope: .fullPattern, completedBars: 4))
        ]
        let states = Dictionary(uniqueKeysWithValues: graph.states(evidence: evidence).map { ($0.exerciseID, $0.status) })
        XCTAssertEqual(states["03_coord_01_alternancia"], .available)
        XCTAssertEqual(states["02_sub_01_corchea_aislada"], .locked)
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "disco")), try XCTUnwrap(chapters.firstIndex(of: "funk")))
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "dembow")), try XCTUnwrap(chapters.firstIndex(of: "blues")))
        XCTAssertLessThan(try XCTUnwrap(chapters.firstIndex(of: "jazz")), try XCTUnwrap(chapters.firstIndex(of: "clave-bossa")))
        XCTAssertEqual(exercises.first?.title, "I-01 · Bombo y caja")
        XCTAssertEqual(exercises.first?.metadata?.objective, "Sigue cuatro pulsos: bombo en uno y tres, caja en dos y cuatro.")
        XCTAssertEqual(exercises.first?.notes.map(\.sound), ["kick", "snare", "kick", "snare"])
        let ternaryExercises = exercises.filter { $0.id.hasPrefix("22_") || $0.id.hasPrefix("23_") || $0.id.hasPrefix("28_") }
        XCTAssertEqual(ternaryExercises.count, 28)
        XCTAssertTrue(ternaryExercises.allSatisfy { $0.grid == 12 })
        let phrase = try XCTUnwrap(exercises.first { $0.id == "02_sub_09_frase_integrada" })
        XCTAssertEqual(phrase.bars, 4)
        XCTAssertEqual(phrase.bpm, 72)
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
        XCTAssertEqual(try XCTUnwrap(exercises.first { $0.id == "27_clave_01_tres_dos" }).notes.filter { $0.sound == "rim" }.map(\.step), [0, 6, 12, 20, 24])
        XCTAssertEqual(try XCTUnwrap(exercises.first { $0.id == "27_clave_03_bossa" }).bars, 6)
    }

    func testPhraseLengthDoesNotMultiplyDefaultPracticeDuration() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        for exercise in exercises {
            let totalBars = exercise.bars * exercise.repeats
            XCTAssertLessThanOrEqual(totalBars, max(8, exercise.bars), exercise.id)
            XCTAssertGreaterThanOrEqual(totalBars, exercise.bars, "La frase debe sonar completa: \(exercise.id)")
            let timeline = ExerciseTimeline(exercise: exercise)
            XCTAssertEqual(timeline.notes.count, exercise.notes.count * exercise.repeats, exercise.id)
            let godStep = try XCTUnwrap(TempoLadder.steps(for: exercise).last)
            let challengeRepeats = try XCTUnwrap(TempoLadder.repeats(for: godStep, exercise: exercise))
            XCTAssertGreaterThanOrEqual(challengeRepeats * exercise.bars, 16, "El reto largo sigue siendo opcional: \(exercise.id)")
        }
        for (bars, repeats) in [(1,8), (2,4), (3,2), (4,2), (6,1), (8,1), (12,1)] {
            XCTAssertEqual(PracticeConfiguration.defaultRepeats(forBars: bars), repeats)
        }
    }

    func testRevisedGenreLessonsKeepTheirSkillsAndPlayableSimultaneity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        for chapter in ["hiphop", "rock", "disco", "funk", "reggae", "dembow", "blues", "jazz", "jazz-intermediate", "clave-bossa"] {
            let lessons = exercises.filter { $0.metadata?.chapter == chapter }.sorted { $0.metadata!.position < $1.metadata!.position }
            XCTAssertEqual(lessons.count, ["hiphop", "jazz-intermediate"].contains(chapter) ? 12 : 8)
            XCTAssertEqual(Set(lessons.map(\.bpm)).count, 1, "No sumar tempo a una variación de patrón: \(chapter)")
            for lesson in lessons {
                let simultaneous = Dictionary(grouping: lesson.notes, by: \.step)
                XCTAssertTrue(simultaneous.values.allSatisfy { $0.count <= 2 }, "Evitar apilar tres voces al añadir una dificultad: \(lesson.id)")
            }
            let checkpoint = try XCTUnwrap(lessons.last)
            let learnedSounds = Set(lessons.dropLast().flatMap { $0.notes.map(\.sound) })
            XCTAssertTrue(Set(checkpoint.notes.map(\.sound)).isSuperset(of: learnedSounds), "La prueba debe conservar las voces aprendidas: \(chapter)")
            // Se comprueba la posición musical de cada voz, no solo su presencia:
            // un aro en negras no sustituye la evidencia de un aro sincopado.
            func rhythmicVocabulary(_ lesson: Exercise) -> Set<String> {
                Set(lesson.notes.map { "\($0.sound):\($0.step % lesson.grid)" })
            }
            let vocabulary = lessons.dropLast().reduce(into: Set<String>()) { $0.formUnion(rhythmicVocabulary($1)) }
            XCTAssertTrue(rhythmicVocabulary(checkpoint).isSuperset(of: vocabulary),
                "Faltan células aprendidas en el cierre de \(chapter): \(vocabulary.subtracting(rhythmicVocabulary(checkpoint)).sorted())")
            XCTAssertTrue(lessons.allSatisfy { lesson in
                (0..<lesson.bars).allSatisfy { bar in
                    let sounds = Set(lesson.notes.filter { $0.step / lesson.grid == bar }.map(\.sound))
                    return sounds.contains("kick") || (chapter == "jazz" && sounds.contains("ride"))
                }
            }, "No debe haber compases de relleno vacíos en \(chapter)")
        }
        let hiphop = exercises.filter { $0.metadata?.chapter == "hiphop" }
        XCTAssertTrue(hiphop.allSatisfy { lesson in
            lesson.notes.contains { $0.sound == "kick" && $0.step % 4 != 0 }
        }, "Hip-hop no debe volver al bombo básico a negras")
        for lesson in hiphop where lesson.metadata!.position >= 4 {
            XCTAssertTrue(lesson.notes.contains { $0.sound == "rim" }, lesson.id)
            XCTAssertTrue(lesson.notes.contains { $0.sound == "clap" }, lesson.id)
        }
        let jazz = exercises.filter { $0.metadata?.chapter == "jazz" }
        XCTAssertTrue(jazz.allSatisfy { lesson in
            (0..<lesson.bars).allSatisfy { bar in
                let notes = lesson.notes.filter { $0.step / lesson.grid == bar }
                let isFill = notes.contains { $0.sound.hasPrefix("tom_") }
                return notes.filter { $0.sound == "ride" }.count == (isFill ? 5 : 6)
            }
        }, "El ride de jazz debe distinguirse del shuffle continuo")
        let reggae = exercises.filter { $0.metadata?.chapter == "reggae" }
        for lesson in reggae {
            XCTAssertGreaterThanOrEqual(lesson.bars, 2, "Reggae parte de un groove completo, no de un gesto aislado")
            for bar in 0..<lesson.bars {
                let notes = lesson.notes.filter { $0.step / lesson.grid == bar }
                XCTAssertTrue(Set(notes.map(\.sound)).isSuperset(of: ["kick", "rim"]))
                XCTAssertTrue(notes.contains { $0.step % lesson.grid == 8 && $0.sound == "kick" })
                XCTAssertGreaterThanOrEqual(notes.filter { $0.sound.hasPrefix("hihat") }.count, lesson.metadata!.position <= 2 ? 7 : 5)
            }
        }
    }

    func testAdvancedExerciseAndTempoRemainPassedAfterReopeningProgress() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        let graph = try CourseGraph(exercises: exercises)
        let future = try XCTUnwrap(exercises.first { $0.id == "25_reggae_02_skank" })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.sqlite")
        do {
            let store = try ProgressStore(url: url)
            try store.record(.init(exerciseID: future.id, timestamp: Date(), bpm: 140, score: 85, stars: 2,
                perfect: 10, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0,
                trainingContext: .init(evaluationScope: .fullPattern, completedBars: 8)))
        }
        let reopened = try ProgressStore(url: url)
        let evidence = try reopened.courseEvidence()
        let state = try XCTUnwrap(graph.states(evidence: evidence).first { $0.exerciseID == future.id })
        XCTAssertEqual(state.status, .mastered, "Una lección futura superada conserva su resultado individual")
        XCTAssertFalse(state.chapterAccredited, "No acredita bloques anteriores sin tocar")
        XCTAssertEqual(TempoLadder.highestPassedStep(for: future, evidence: evidence)?.label, "Jefe")
        XCTAssertEqual(TempoLadder.highestPassedStep(for: future, evidence: evidence)?.award, .trophies(2))
        XCTAssertEqual(try reopened.progress(for: future.id)?.attemptCount, 1)
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
        XCTAssertEqual(score.stars, 1)
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
        XCTAssertTrue(whale.coachingCue.contains("«y»"))
        XCTAssertTrue(whale.coachingCue.contains("snare"))
    }

    func testCoachingAnalyzerRequiresRepeatedSameDirectionTimingEvidence() {
        let exercise = Exercise(format: 1, id: "coaching", title: "Coaching", family: "test", level: 1,
                                bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 4, kit: "kit", loop: nil, offset: 0,
                                notes: [.init(step: 0, sound: "kick")])
        let bar = ExerciseTimeline(exercise: exercise).barDurationMilliseconds
        let oneMiss = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 80, grid: 16,
                                         hits: [.init(sound: "kick", timeMilliseconds: 60), .init(sound: "kick", timeMilliseconds: bar),
                                                .init(sound: "kick", timeMilliseconds: bar * 2), .init(sound: "kick", timeMilliseconds: bar * 3)])
        XCTAssertNil(CoachingAnalyzer.recommendation(exercise: exercise, score: oneMiss))

        let lateScore = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 80, grid: 16,
                                           hits: (0..<4).map { .init(sound: "kick", timeMilliseconds: Double($0) * bar + 55) })
        let recommendation = try! XCTUnwrap(CoachingAnalyzer.recommendation(exercise: exercise, score: lateScore))
        XCTAssertEqual(recommendation.issue, .late)
        XCTAssertEqual(recommendation.opportunities, 4)
        XCTAssertEqual(recommendation.issueCount, 4)
        XCTAssertEqual(recommendation.stepRange, 0...1)
    }

    func testCoachingComparisonRequiresMatchingFullPatternConditions() {
        let exerciseID = "coach-comparison"
        let recommendation = CoachingRecommendation(sound: "kick", step: 0, issue: .late, opportunities: 4, issueCount: 3, medianOffsetMilliseconds: 50)
        let conditions = PracticeConditions(bpm: 80, repeats: 4, selectedSounds: ["kick"], loopEnabled: false)
        func attempt(_ offsets: [Double], timestamp: TimeInterval, context: TrainingContext? = nil) -> PracticeAttempt {
            let records = offsets.enumerated().map { index, offset in
                HitRecord(sequence: index, judgement: .good, expectedSound: "kick", expectedStep: 0,
                          expectedTimeMilliseconds: Double(index) * 750, expectedVelocity: nil, hand: nil, target: nil,
                          actualSound: "kick", actualTimeMilliseconds: Double(index) * 750 + offset,
                          actualVelocity: nil, role: nil, padID: nil, offsetMilliseconds: offset)
            }
            return PracticeAttempt(exerciseID: exerciseID, timestamp: Date(timeIntervalSince1970: timestamp), bpm: 80,
                                   score: 90, stars: 3, perfect: 4, good: 0, regular: 0, miss: 0, extra: 0,
                                   meanOffsetMilliseconds: 0, hitRecords: records,
                                   trainingContext: context ?? .init(practiceConditions: conditions))
        }
        let baseline = attempt([50, 52, 48, 54], timestamp: 1)
        let improved = attempt([10, 12, 8, 14], timestamp: 2)
        XCTAssertEqual(CoachingComparison.compare(baseline: baseline, followUp: improved, recommendation: recommendation).outcome, .improved)
        let unknownConditions = attempt([10, 12, 8, 14], timestamp: 3, context: .init())
        XCTAssertEqual(CoachingComparison.compare(baseline: baseline, followUp: unknownConditions, recommendation: recommendation).outcome, .conditionsDiffer)
    }

    func testRetentionConditionsAllowRemovingVisualGuideButNotChangingTempoOrRoute() {
        let baseline = PracticeConditions(bpm: 80, repeats: 4, selectedSounds: ["kick"], showsVisualGuides: true, visualGuideLevel: "full")
        let transfer = PracticeConditions(bpm: 80, repeats: 4, selectedSounds: ["kick"], showsVisualGuides: false, visualGuideLevel: "normal")
        let changedTempo = PracticeConditions(bpm: 90, repeats: 4, selectedSounds: ["kick"], showsVisualGuides: false)

        XCTAssertTrue(baseline.isComparableForRetention(to: transfer))
        XCTAssertFalse(baseline.isComparableForRetention(to: changedTempo))
    }

    func testCoachingReviewDoesNotTreatTooFewHitsAsFailure() {
        let exercise = Exercise(format: 1, id: "review-evidence", title: "Review", family: "test", level: 1,
                                bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0,
                                notes: [.init(step: 0, sound: "kick")])
        let score = RhythmScorer.score(timeline: ExerciseTimeline(exercise: exercise), bpm: 80, grid: 16,
                                       hits: [.init(sound: "kick", timeMilliseconds: 0)])
        let recommendation = CoachingRecommendation(sound: "kick", step: 0, issue: .late, opportunities: 4, issueCount: 3, medianOffsetMilliseconds: 50)

        XCTAssertEqual(CoachingAnalyzer.reviewOutcome(for: recommendation, score: score), .insufficientEvidence)
    }

    func testPulseDriftAnalyzerSeparatesStableBiasFromGrowingDrift() {
        let stableRecords = (0..<16).map { pulse in
            HitRecord(sequence: pulse, judgement: .perfect, expectedSound: "kick", expectedStep: pulse,
                      expectedTimeMilliseconds: Double(pulse) * 500, expectedVelocity: nil, hand: nil, target: nil,
                      actualSound: "kick", actualTimeMilliseconds: Double(pulse) * 500 + 12,
                      actualVelocity: nil, role: nil, padID: nil, offsetMilliseconds: 12)
        }
        let stable = PulseDriftAnalyzer.analyze(records: stableRecords, barDurationMilliseconds: 2_000, gapLevel: 1)
        XCTAssertEqual(stable.trend, .stable)
        XCTAssertEqual(stable.silentGapDriftMilliseconds ?? -1, 0, accuracy: 0.001)

        let driftingRecords = (0..<16).map { pulse in
            let bar = pulse / 4
            let beat = pulse % 4
            let audible = GapMetronomePattern.isAudible(bar: bar, beat: beat, level: 2)
            let offset = audible ? 0.0 : Double(bar - 2) * 20
            return HitRecord(sequence: pulse, judgement: .perfect, expectedSound: "kick", expectedStep: pulse,
                             expectedTimeMilliseconds: Double(pulse) * 500, expectedVelocity: nil, hand: nil, target: nil,
                             actualSound: "kick", actualTimeMilliseconds: Double(pulse) * 500 + offset,
                             actualVelocity: nil, role: nil, padID: nil, offsetMilliseconds: offset)
        }
        let drifting = PulseDriftAnalyzer.analyze(records: driftingRecords, barDurationMilliseconds: 2_000, gapLevel: 2)
        XCTAssertEqual(drifting.trend, .late)
        XCTAssertGreaterThan(drifting.silentGapDriftMilliseconds ?? 0, 5)
    }

    func testPulseDriftKeepsOffbeatsInTheirActualMetronomeBeat() {
        let records = [5_750.0, 6_500.0].enumerated().map { index, time in
            HitRecord(sequence: index, judgement: .perfect, expectedSound: "kick", expectedStep: index,
                expectedTimeMilliseconds: time, expectedVelocity: nil, hand: nil, target: nil,
                actualSound: "kick", actualTimeMilliseconds: time + 12, actualVelocity: nil,
                role: nil, padID: nil, offsetMilliseconds: 12)
        }
        let report = PulseDriftAnalyzer.analyze(records: records, barDurationMilliseconds: 2_000, gapLevel: 1)
        XCTAssertEqual(report.points.map(\.pulseIndex), [11, 13])
        XCTAssertEqual(report.points.map(\.metronomeAudible), [true, false],
            "El contratiempo anterior al silencio todavía pertenece al compás audible")
        XCTAssertEqual(report.trend, .insufficientEvidence,
            "Un solo pulso durante el silencio no permite acreditar estabilidad")
    }

    func testMasteryRequiresAllFourTrainingContexts() {
        let exercise = Exercise(format: 1, id: "mastery", title: "Mastery", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let passing: (Int, TrainingContext) -> PracticeAttempt = { bpm, context in
            .init(exerciseID: exercise.id, timestamp: .init(), bpm: bpm, score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 5, trainingContext: context)
        }
        let attempts = [passing(80, .init()), passing(65, .init()), passing(95, .init()), passing(80, .init(gapMetronomeLevel: 2)), passing(80, .init(phase: .transfer, showsVisualGuides: false))]
        XCTAssertTrue(MasteryEvaluator.seals(exercise: exercise, attempts: attempts).allSatisfy(\.achieved))

        let partialTransfer = passing(80, .init(phase: .transfer, showsVisualGuides: false, evaluationScope: .selectedVoices))
        let memorySeal = MasteryEvaluator.seals(exercise: exercise, attempts: [partialTransfer])
            .first(where: { $0.label == "Memoria" })
        XCTAssertFalse(memorySeal?.achieved ?? true, "Una transferencia parcial no puede conceder el sello de memoria.")
    }

    func testPulseTrainingAdvancesOnlyAfterTwoEquivalentFullPatternAttempts() {
        let exerciseID = "pulse-plan"
        let firstConditions = PracticeConditions(bpm: 80, repeats: 2, selectedSounds: ["kick"], loopEnabled: false)
        let otherConditions = PracticeConditions(bpm: 90, repeats: 2, selectedSounds: ["kick"], loopEnabled: false)
        let transferConditions = PracticeConditions(bpm: 80, repeats: 2, selectedSounds: ["kick"], loopEnabled: false, showsVisualGuides: false)
        func passing(_ timestamp: TimeInterval, conditions: PracticeConditions, phase: TrainingPhase = .integrate, showsGuides: Bool = true) -> PracticeAttempt {
            .init(exerciseID: exerciseID, timestamp: Date(timeIntervalSince1970: timestamp), bpm: conditions.bpm,
                  score: 80, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0,
                  meanOffsetMilliseconds: 0,
                  trainingContext: .init(phase: phase, gapMetronomeLevel: 0, showsVisualGuides: showsGuides,
                                          evaluationScope: .fullPattern, completedBars: 2, practiceConditions: conditions))
        }
        XCTAssertEqual(PulseTrainingPlan.nextStage(after: [passing(1, conditions: firstConditions)], exerciseID: exerciseID).index, 0)
        XCTAssertEqual(PulseTrainingPlan.nextStage(after: [passing(1, conditions: firstConditions), passing(2, conditions: otherConditions)], exerciseID: exerciseID).index, 0)
        let guidedPair = [passing(1, conditions: firstConditions), passing(2, conditions: firstConditions)]
        XCTAssertEqual(PulseTrainingPlan.nextStage(after: guidedPair, exerciseID: exerciseID).index, 1)
        XCTAssertEqual(PulseTrainingPlan.nextStage(after: guidedPair + [passing(3, conditions: transferConditions, phase: .transfer, showsGuides: false)], exerciseID: exerciseID).index, 1)
        let blindPair = [passing(3, conditions: transferConditions, phase: .transfer, showsGuides: false), passing(4, conditions: transferConditions, phase: .transfer, showsGuides: false)]
        XCTAssertEqual(PulseTrainingPlan.nextStage(after: guidedPair + blindPair, exerciseID: exerciseID).index, 2)
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

    func testPracticeSessionEmitsMissesAfterTheirRegularWindowCloses() {
        let exercise = Exercise(
            format: 1, id: "live-miss", title: "Live miss", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick"), .init(step: 1, sound: "snare")]
        )
        let regularWindow = ScoringWindows(bpm: exercise.bpm, grid: exercise.grid).regularMilliseconds
        let session = PracticeSession(exercise: exercise)

        let atWindowBoundary = session.registerWithMisses(.init(sound: "clap", timeMilliseconds: regularWindow))
        XCTAssertTrue(atWindowBoundary.expiredMisses.isEmpty, "El límite superior todavía pertenece a la ventana Regular.")

        let laterHit = session.registerWithMisses(.init(sound: "snare", timeMilliseconds: 200))

        XCTAssertEqual(laterHit.scoredHit.judgement, .perfect)
        XCTAssertEqual(laterHit.expiredMisses.map(\.sound), ["kick"])
        XCTAssertEqual(session.score.misses.map(\.sound), ["kick"])
    }

    func testConsumedNoteDoesNotEmitAsLiveMiss() {
        let exercise = Exercise(
            format: 1, id: "consumed-live-miss", title: "Consumed note", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick"), .init(step: 1, sound: "snare")]
        )
        let session = PracticeSession(exercise: exercise)

        XCTAssertEqual(session.registerWithMisses(.init(sound: "kick", timeMilliseconds: 0)).scoredHit.judgement, .perfect)
        let laterHit = session.registerWithMisses(.init(sound: "snare", timeMilliseconds: 200))

        XCTAssertTrue(laterHit.expiredMisses.isEmpty)
        XCTAssertTrue(session.score.misses.isEmpty)
    }

    func testPracticeSessionIngressDeliversExpiredMissesWithTheNextHit() {
        let exercise = Exercise(
            format: 1, id: "ingress-live-miss", title: "Ingress live miss", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick"), .init(step: 1, sound: "snare")]
        )
        let ingress = PracticeSessionIngress()
        let generation = UUID()
        let processed = expectation(description: "entregar golpe y fallo vencido")
        let finished = expectation(description: "cerrar generación")
        ingress.begin(PracticeSession(exercise: exercise), generation: generation)

        ingress.submit(.init(sound: "snare", timeMilliseconds: 200)) { returnedGeneration, result in
            XCTAssertEqual(returnedGeneration, generation)
            XCTAssertEqual(result.scoredHit?.judgement, .perfect)
            XCTAssertEqual(result.expiredMisses.map(\.sound), ["kick"])
            processed.fulfill()
        }
        ingress.finish { returnedGeneration, score in
            XCTAssertEqual(returnedGeneration, generation)
            XCTAssertEqual(score?.misses.map(\.sound), ["kick"])
            finished.fulfill()
        }

        wait(for: [processed, finished], timeout: 2)
    }

    func testIncrementalPracticeScoringMatchesReferenceForChronologicalHits() {
        let exercise = Exercise(
            format: 1, id: "incremental", title: "Incremental", family: "test", level: 1,
            bpm: 100, meter: [4, 4], bars: 2, grid: 16, repeats: 2,
            kit: "kit", loop: nil, offset: 0,
            notes: [
                .init(step: 0, sound: "kick"), .init(step: 4, sound: "snare"),
                .init(step: 8, sound: "kick", target: .init(type: .role, value: "kick_right")),
                .init(step: 12, sound: "clap")
            ]
        )
        let timeline = ExerciseTimeline(exercise: exercise)
        let hits = [
            TimedPadHit(sound: "kick", timeMilliseconds: 4),
            TimedPadHit(sound: "snare", timeMilliseconds: 62),
            TimedPadHit(sound: "kick", timeMilliseconds: 122, role: "kick_right"),
            TimedPadHit(sound: "clap", timeMilliseconds: 181),
            TimedPadHit(sound: "kick", timeMilliseconds: 244),
            TimedPadHit(sound: "snare", timeMilliseconds: 301),
            TimedPadHit(sound: "kick", timeMilliseconds: 360, role: "kick_left"),
            TimedPadHit(sound: "clap", timeMilliseconds: 420),
            TimedPadHit(sound: "kick", timeMilliseconds: 484),
            TimedPadHit(sound: "snare", timeMilliseconds: 541),
            TimedPadHit(sound: "kick", timeMilliseconds: 601, role: "kick_right"),
            TimedPadHit(sound: "clap", timeMilliseconds: 660),
            TimedPadHit(sound: "kick", timeMilliseconds: 724),
            TimedPadHit(sound: "snare", timeMilliseconds: 781),
            TimedPadHit(sound: "kick", timeMilliseconds: 840, role: "kick_right"),
            TimedPadHit(sound: "clap", timeMilliseconds: 900)
        ]
        let session = PracticeSession(exercise: exercise, calibrationOffsetMilliseconds: 3)
        hits.forEach { session.register($0) }

        XCTAssertEqual(
            session.score,
            RhythmScorer.score(timeline: timeline, bpm: exercise.bpm, grid: exercise.grid, hits: hits, calibrationOffsetMilliseconds: 3)
        )
    }

    func testOutOfOrderPracticeHitsUseReferenceScoringAndReturnTheNewHitJudgement() {
        let exercise = Exercise(
            format: 1, id: "out-of-order", title: "Out of order", family: "test", level: 1,
            bpm: 240, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick"), .init(step: 1, sound: "kick")]
        )
        let timeline = ExerciseTimeline(exercise: exercise)
        let windows = ScoringWindows(perfectMilliseconds: 35, goodMilliseconds: 45, regularMilliseconds: 50)
        let session = PracticeSession(exercise: exercise, scoringWindows: windows)
        let laterHit = TimedPadHit(sound: "kick", timeMilliseconds: 20)
        let earlierHit = TimedPadHit(sound: "kick", timeMilliseconds: 0)

        XCTAssertEqual(session.register(laterHit).judgement, .perfect)
        XCTAssertEqual(session.register(earlierHit).judgement, .perfect)
        XCTAssertEqual(
            session.score,
            RhythmScorer.score(timeline: timeline, bpm: exercise.bpm, grid: exercise.grid, hits: [laterHit, earlierHit], scoringWindows: windows)
        )
        XCTAssertEqual(session.score.hits.map(\.judgement), [.perfect, .good])
    }

    func testPracticeSessionIngressFinishesAfterAdmittedHitsAndRejectsLaterOnes() {
        let exercise = Exercise(
            format: 1, id: "ingress", title: "Ingress", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")]
        )
        let ingress = PracticeSessionIngress()
        let generation = UUID()
        let finished = expectation(description: "procesar el golpe y cerrar la sesión")
        var deliveryOrder = [String]()
        ingress.begin(PracticeSession(exercise: exercise), generation: generation)

        XCTAssertEqual(
            ingress.submit(.init(sound: "kick", timeMilliseconds: 0)) { returnedGeneration, result in
                XCTAssertEqual(returnedGeneration, generation)
                XCTAssertEqual(result.scoredHit?.judgement, .perfect)
                deliveryOrder.append("golpe")
            },
            generation
        )
        ingress.finish { returnedGeneration, score in
            XCTAssertEqual(returnedGeneration, generation)
            XCTAssertEqual(score?.percentage, 100)
            deliveryOrder.append("cierre")
            finished.fulfill()
        }

        wait(for: [finished], timeout: 2)
        XCTAssertEqual(deliveryOrder, ["golpe", "cierre"])
        XCTAssertNil(ingress.submit(.init(sound: "kick", timeMilliseconds: 1)) { _, _ in })
    }

    func testPracticeSessionIngressAdmitsMIDIWorkerHitBeforeFinishBarrier() {
        let exercise = Exercise(
            format: 1, id: "midi-worker-ingress", title: "MIDI worker ingress", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")]
        )
        let ingress = PracticeSessionIngress()
        let generation = UUID()
        let startHostTime = AudioClock.currentHostTime()
        let processed = expectation(description: "admitir el golpe desde el worker MIDI")
        let finished = expectation(description: "cerrar después del golpe admitido")
        ingress.begin(PracticeSession(exercise: exercise), generation: generation)

        DispatchQueue.global(qos: .userInitiated).async {
            let admittedGeneration = ingress.submit(
                TimedPadHit(sound: "kick", hostTime: startHostTime, practiceStartHostTime: startHostTime)
            ) { returnedGeneration, result in
                XCTAssertEqual(returnedGeneration, generation)
                XCTAssertEqual(result.scoredHit?.hit.timeMilliseconds ?? -1, 0, accuracy: 0.001)
                XCTAssertEqual(result.scoredHit?.judgement, .perfect)
                processed.fulfill()
            }
            XCTAssertEqual(admittedGeneration, generation)
            ingress.finish { returnedGeneration, score in
                XCTAssertEqual(returnedGeneration, generation)
                XCTAssertEqual(score?.percentage ?? -1, 100, accuracy: 0.001)
                XCTAssertEqual(score?.hits.count, 1)
                finished.fulfill()
            }
        }

        wait(for: [processed, finished], timeout: 2)
    }

    func testPracticeSessionIngressRoutesHitsToTheirGenerationWhenRestarted() {
        let exercise = Exercise(
            format: 1, id: "restart", title: "Restart", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1,
            kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")]
        )
        let ingress = PracticeSessionIngress()
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        let finished = expectation(description: "terminar segunda generación")
        ingress.begin(PracticeSession(exercise: exercise), generation: firstGeneration)
        XCTAssertEqual(ingress.submit(.init(sound: "kick", timeMilliseconds: 0)) { generation, result in
            XCTAssertEqual(generation, firstGeneration)
            XCTAssertEqual(result.scoredHit?.judgement, .perfect)
        }, firstGeneration)

        ingress.begin(PracticeSession(exercise: exercise), generation: secondGeneration)
        XCTAssertEqual(ingress.submit(.init(sound: "kick", timeMilliseconds: 0)) { generation, result in
            XCTAssertEqual(generation, secondGeneration)
            XCTAssertEqual(result.scoredHit?.judgement, .perfect)
        }, secondGeneration)
        ingress.finish { generation, score in
            XCTAssertEqual(generation, secondGeneration)
            XCTAssertEqual(score?.percentage, 100)
            XCTAssertEqual(score?.hits.count, 1)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
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

    func testProgressStoreMigratesLegacyAttemptTableWithoutDroppingRows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-legacy-progress-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE attempts (
          id INTEGER PRIMARY KEY, exercise_id TEXT NOT NULL, timestamp REAL NOT NULL,
          bpm INTEGER NOT NULL, score REAL NOT NULL, stars INTEGER NOT NULL,
          perfect INTEGER NOT NULL, good INTEGER NOT NULL, regular INTEGER NOT NULL,
          miss INTEGER NOT NULL, extra INTEGER NOT NULL, mean_offset_ms REAL
        )
        """
        XCTAssertEqual(sqlite3_exec(database, legacySchema, nil, nil, nil), SQLITE_OK)
        let legacyRow = "INSERT INTO attempts (exercise_id, timestamp, bpm, score, stars, perfect, good, regular, miss, extra, mean_offset_ms) VALUES ('old', 1, 80, 75, 2, 1, 0, 0, 0, 0, 4)"
        XCTAssertEqual(sqlite3_exec(database, legacyRow, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let store = try ProgressStore(url: url)
        let attempt = PracticeAttempt(
            exerciseID: "legacy", timestamp: Date(timeIntervalSince1970: 1), bpm: 80,
            score: 75, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0,
            extra: 0, meanOffsetMilliseconds: 4
        )
        try store.record(attempt)

        let attempts = try store.attempts(limit: 10)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.first(where: { $0.exerciseID == "old" })?.trainingContext.evaluationScope, .legacyUnknown)
        XCTAssertEqual(attempts.first(where: { $0.exerciseID == "legacy" })?.trainingContext.evaluationScope, .fullPattern)
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

    func testProgressStoreImportsAttemptsAtomicallyWithoutDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceStore = try ProgressStore(url: directory.appendingPathComponent("source.sqlite"))
        let destinationStore = try ProgressStore(url: directory.appendingPathComponent("destination.sqlite"))
        let json = directory.appendingPathComponent("progress.json")
        let attempt = PracticeAttempt(
            exerciseID: "hh_01",
            timestamp: Date(timeIntervalSince1970: 1_728_000_000.125),
            bpm: 85,
            score: 87.5,
            stars: 2,
            perfect: 4,
            good: 2,
            regular: 1,
            miss: 0,
            extra: 1,
            meanOffsetMilliseconds: -6,
            trainingContext: .init(phase: .transfer, showsVisualGuides: false)
        )
        try sourceStore.record(attempt)
        try sourceStore.exportJSON(to: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportedAttempts = try decoder.decode([PracticeAttempt].self, from: Data(contentsOf: json))

        XCTAssertEqual(exportedAttempts.first?.timestamp, attempt.timestamp,
            "La exportación conserva la fracción de segundo del historial")
        XCTAssertEqual(try sourceStore.importAttempts(exportedAttempts), 0,
            "Restaurar el propio archivo no debe duplicar intentos existentes")
        XCTAssertEqual(try destinationStore.importAttempts(exportedAttempts + exportedAttempts), 1)
        XCTAssertEqual(try destinationStore.importAttempts(exportedAttempts), 0)
        XCTAssertEqual(try destinationStore.attempts(limit: 10), exportedAttempts)
        XCTAssertEqual(try destinationStore.courseEvidence().first?.trainingContext.phase, .transfer)
    }

    func testProgressImportReadsLegacyAttemptsWithoutDiagnosticFields() throws {
        let data = Data("""
        [{
          "exerciseID": "legacy",
          "timestamp": "2024-01-01T00:00:00Z",
          "bpm": 80,
          "score": 75,
          "stars": 2,
          "perfect": 1,
          "good": 1,
          "regular": 0,
          "miss": 0,
          "extra": 0,
          "meanOffsetMilliseconds": null
        }]
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let attempts = try decoder.decode([PracticeAttempt].self, from: data)

        XCTAssertEqual(attempts.count, 1)
        XCTAssertTrue(attempts[0].hitRecords.isEmpty)
        XCTAssertEqual(attempts[0].trainingContext.evaluationScope, .legacyUnknown)
    }

    func testInvalidImportedAttemptThrowsAndRollsBackTheWholeBatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-invalid-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(url: directory.appendingPathComponent("progress.sqlite"))
        func attempt(id: String, bpm: Int = 80, score: Double = 90, perfect: Int = 4) -> PracticeAttempt {
            .init(exerciseID: id, timestamp: Date(timeIntervalSince1970: 1_728_000_000.125), bpm: bpm, score: score, stars: 3,
                perfect: perfect, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        }
        let original = attempt(id: "saved")
        try store.record(original)
        for invalid in [attempt(id: "overflow-bpm", bpm: Int.max),
                        attempt(id: "overflow-count", perfect: Int.max),
                        attempt(id: "negative-count", perfect: -1),
                        attempt(id: "invalid-score", score: 101),
                        attempt(id: "nonfinite-score", score: .nan)] {
            XCTAssertThrowsError(try store.importAttempts([attempt(id: "rolled-back"), invalid]))
            XCTAssertEqual(try store.attempts(limit: Int.max), [original])
        }
        XCTAssertEqual(try store.scores(for: "saved", limit: Int.max), [90])
    }

    func testEmptyExerciseCatalogProducesARecoverableError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-empty-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try ResourceCatalog().loadExercises(in: directory, kit: communityKit())) { error in
            XCTAssertEqual(error as? ResourceValidationError, .emptyExerciseCatalog)
        }
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

    func testDailyPracticePlanIncludesWarmupChallengeAndIntegrationWithinTarget() {
        let first = Exercise(format: 1, id: "daily-one", title: "Conocido", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let next = Exercise(format: 1, id: "daily-two", title: "Nuevo", family: "test", level: 2, bpm: 100, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "snare")])
        let attempt = PracticeAttempt(exerciseID: first.id, timestamp: Date(timeIntervalSince1970: 10), bpm: 80,
                                      score: 90, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0,
                                      meanOffsetMilliseconds: 0)
        let plan = try! XCTUnwrap(DailyPracticePlanner.makePlan(exercises: [first, next], attempts: [attempt], now: Date(timeIntervalSince1970: 20)))

        XCTAssertEqual(plan.blocks.map(\.kind), [.warmup, .challenge, .integrate])
        XCTAssertEqual(plan.blocks.first?.exerciseID, first.id)
        XCTAssertEqual(plan.blocks[1].exerciseID, next.id)
        XCTAssertLessThanOrEqual(plan.estimatedSeconds, plan.targetSeconds)
        XCTAssertEqual(plan.currentBlock?.kind, .warmup)
        let firstID = plan.blocks[0].id
        var resumed = plan
        XCTAssertTrue(resumed.completeBlock(firstID, at: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(resumed.currentBlock?.kind, .challenge)
        XCTAssertTrue(resumed.blocks[0].isCompleted)
    }

    func testDailyPracticePlanAddsDueCorrectiveReview() {
        let exercise = Exercise(format: 1, id: "daily-review", title: "Repasar", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [.init(step: 0, sound: "kick")])
        let recommendation = CoachingRecommendation(sound: "kick", step: 0, issue: .late, opportunities: 4, issueCount: 3, medianOffsetMilliseconds: 50)
        let conditions = PracticeConditions(bpm: 88, repeats: 4, selectedSounds: ["kick"], gapMetronomeLevel: 1,
                                            metronomeEnabled: true, loopEnabled: true, loopIdentifier: "loop-a")
        let due = CoachingGoal(exerciseID: exercise.id, recommendation: recommendation, baselineConditions: conditions,
                               createdAt: Date(timeIntervalSince1970: 1), nextReviewAt: Date(timeIntervalSince1970: 5))
        let plan = try! XCTUnwrap(DailyPracticePlanner.makePlan(exercises: [exercise], attempts: [], dueGoals: [due], now: Date(timeIntervalSince1970: 10)))
        let review = try! XCTUnwrap(plan.blocks.first(where: { $0.kind == .review }))
        XCTAssertEqual(review.focusedSound, "kick")
        XCTAssertEqual(review.phase, .transfer, "La retención se comprueba en el patrón completo, no aislando la célula.")
        XCTAssertEqual(review.bpm, 88)
        XCTAssertEqual(review.repeats, 4)
        XCTAssertEqual(review.gapMetronomeLevel, 1)
        XCTAssertTrue(review.loopEnabled)
        XCTAssertEqual(review.loopIdentifier, "loop-a")
    }

    func testProgressStorePersistsTrainingPlansAndReviewGoals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-training-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProgressStore(url: directory.appendingPathComponent("progress.sqlite"))
        let plan = DailyPracticePlan(day: Date(timeIntervalSince1970: 1_700_000_000), blocks: [])
        let baseline = PracticeConditions(bpm: 80, repeats: 2, selectedSounds: ["kick"])
        let goal = CoachingGoal(exerciseID: "exercise", recommendation: .init(sound: "kick", step: 0, issue: .repeatedMiss, opportunities: 4, issueCount: 2, medianOffsetMilliseconds: nil), baselineConditions: baseline, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.saveTrainingState(plan, forKey: "daily")
        try store.saveTrainingState([goal], forKey: "goals")
        XCTAssertEqual(try store.loadTrainingState(DailyPracticePlan.self, forKey: "daily"), plan)
        XCTAssertEqual(try store.loadTrainingState([CoachingGoal].self, forKey: "goals"), [goal])
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
        XCTAssertEqual(plan.bpm, 80)
        XCTAssertEqual(plan.bpm, CourseRecommendationPlanner.recommend(
            exercises: [second, first],
            courseLevels: [.init(exerciseID: first.id, status: .available, bestScore: nil), .init(exerciseID: second.id, status: .locked, bestScore: nil)],
            evidence: []
        )?.tempoStep.bpm)
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
        let fragment = PracticeAttempt(exerciseID: "level_1", timestamp: .init().addingTimeInterval(1), bpm: 100, score: 100, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0, trainingContext: .init(evaluationScope: .fragment))

        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [partial, fragment], fastStartID: nil).map(\.status), [.available, .locked])
    }

    func testCourseProgressAdvancesAtTheLearningTempoWithoutTempoChallenges() {
        let exercises = (1...3).map { level in
            Exercise(format: 1, id: "level_\(level)", title: "Nivel \(level)", family: "test", level: level, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        }
        let learnPass = PracticeAttempt(exerciseID: "level_1", timestamp: .init(), bpm: 70, score: 100, stars: 3, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let basePass = PracticeAttempt(exerciseID: "level_1", timestamp: .init(), bpm: 80, score: 70, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let consolidatePass = PracticeAttempt(exerciseID: "level_1", timestamp: .init(), bpm: 100, score: 70, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)

        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [learnPass], fastStartID: nil).map(\.status), [.available, .locked, .locked])
        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [learnPass, basePass], fastStartID: nil).map(\.status), [.mastered, .available, .locked])
        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [learnPass, basePass, consolidatePass], fastStartID: nil).map(\.status), [.mastered, .available, .locked])

        let advancedPass = PracticeAttempt(exerciseID: "level_3", timestamp: .init(), bpm: 120, score: 70, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        XCTAssertEqual(CourseProgress.states(exercises: exercises, attempts: [advancedPass], fastStartID: nil).map(\.status), [.available, .available, .mastered])
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

        let withTrophy = attempts + [
            PracticeAttempt(exerciseID: exercise.id, timestamp: .init(), bpm: 120, score: 80, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        ]
        XCTAssertEqual(TempoLadder.highestPassedStep(for: exercise, attempts: withTrophy)?.award, .trophies(1))
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

        let oneStarAtTargetTempo = [CourseAttemptEvidence(
            exerciseID: exercise.id,
            bpm: 70,
            score: 70,
            stars: 1,
            trainingContext: .init(evaluationScope: .fullPattern, completedBars: 1)
        )]
        XCTAssertTrue(TempoLadder.isPassed(steps[0], exerciseID: exercise.id, evidence: oneStarAtTargetTempo))
    }

    func testStarsRequireSeventyEightyAndNinetyPercentOfTheNetScore() {
        let exercise = Exercise(format: 1, id: "stars", title: "Estrellas", family: "test", level: 1,
            bpm: 80, meter: [4, 4], bars: 7, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0,
            notes: (0..<100).map { .init(step: $0, sound: "kick") })
        let timeline = ExerciseTimeline(exercise: exercise)
        for (hits, expectedStars) in [(50,0), (69,0), (70,1), (79,1), (80,2), (89,2), (90,3), (100,3)] {
            let score = RhythmScorer.score(timeline: timeline, bpm: 80, grid: 16,
                hits: timeline.notes.prefix(hits).map { .init(sound: $0.sound, timeMilliseconds: $0.timeMilliseconds) })
            XCTAssertEqual(score.percentage, Double(hits), accuracy: 0.001)
            XCTAssertEqual(score.stars, expectedStars, "Umbral de \(hits) %")
        }
        let penalized = RhythmScorer.score(timeline: timeline, bpm: 80, grid: 16,
            hits: timeline.notes.prefix(70).map { .init(sound: $0.sound, timeMilliseconds: $0.timeMilliseconds) }
                + [.init(sound: "snare", timeMilliseconds: 0)])
        XCTAssertEqual(penalized.percentage, 69.75, accuracy: 0.001)
        XCTAssertEqual(penalized.stars, 0, "El redondeo visual no concede estrellas por debajo del umbral")
    }

    func testCourseLessonUsesLearningTargetAndRequiresFullPattern() {
        let exercise = Exercise(format: 1, id: "lesson", title: "Lección", family: "test", level: 1, bpm: 82, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let slow = CourseAttemptEvidence(exerciseID: exercise.id, bpm: 70, score: 100, stars: 3, trainingContext: .init(evaluationScope: .fullPattern, completedBars: 1))
        let partial = CourseAttemptEvidence(exerciseID: exercise.id, bpm: 82, score: 100, stars: 3, trainingContext: .init(evaluationScope: .selectedVoices, completedBars: 1))
        let complete = CourseAttemptEvidence(exerciseID: exercise.id, bpm: 82, score: 70, stars: 2, trainingContext: .init(evaluationScope: .fullPattern, completedBars: 1))

        XCTAssertEqual(CourseLessonCriteria.targetBPM(for: exercise), 82)
        XCTAssertFalse(CourseLessonCriteria.isPassed(exercise, evidence: [slow, partial]))
        XCTAssertTrue(CourseLessonCriteria.isPassed(exercise, evidence: [complete]))

        let fastExercise = Exercise(format: 1, id: "fast-lesson", title: "Lección rápida", family: "test", level: 2, bpm: 120, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        XCTAssertEqual(CourseLessonCriteria.targetBPM(for: fastExercise), 100)
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

    func testCourseRecommendationUsesOneLearningTempoThenMovesToNextLesson() {
        let first = Exercise(format: 1, id: "first", title: "Primero", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let second = Exercise(format: 1, id: "second", title: "Segundo", family: "test", level: 2, bpm: 110, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let initial = CourseRecommendationPlanner.recommend(exercises: [first, second], courseLevels: [.init(exerciseID: first.id, status: .available, bestScore: nil), .init(exerciseID: second.id, status: .locked, bestScore: nil)], attempts: [])
        XCTAssertEqual(initial?.exerciseID, first.id)
        XCTAssertEqual(initial?.tempoStep.label, "Ritmo completo")
        XCTAssertEqual(initial?.tempoStep.bpm, 80)

        let learnPass = PracticeAttempt(exerciseID: first.id, timestamp: .init(), bpm: 70, score: 80, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let baseRecommendation = CourseRecommendationPlanner.recommend(exercises: [first, second], courseLevels: [.init(exerciseID: first.id, status: .available, bestScore: nil), .init(exerciseID: second.id, status: .locked, bestScore: nil)], attempts: [learnPass])
        XCTAssertEqual(baseRecommendation?.tempoStep.label, "Ritmo completo")
        XCTAssertEqual(baseRecommendation?.tempoStep.bpm, 80)
        let basePass = PracticeAttempt(exerciseID: first.id, timestamp: .init(), bpm: 80, score: 80, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)

        let next = CourseRecommendationPlanner.recommend(exercises: [first, second], courseLevels: [.init(exerciseID: first.id, status: .mastered, bestScore: 80), .init(exerciseID: second.id, status: .available, bestScore: nil)], attempts: [learnPass])
        XCTAssertEqual(next?.exerciseID, second.id)
        XCTAssertEqual(next?.tempoStep.bpm, 100)

        let consolidatePass = PracticeAttempt(exerciseID: first.id, timestamp: .init(), bpm: 100, score: 70, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)
        let afterConsolidating = CourseRecommendationPlanner.recommend(
            exercises: [first, second],
            courseLevels: [.init(exerciseID: first.id, status: .mastered, bestScore: 70), .init(exerciseID: second.id, status: .available, bestScore: nil)],
            attempts: [learnPass, basePass, consolidatePass]
        )
        XCTAssertEqual(afterConsolidating?.exerciseID, second.id)
        XCTAssertEqual(afterConsolidating?.tempoStep.label, "Ritmo completo")
        XCTAssertEqual(afterConsolidating?.tempoStep.bpm, 100)

        let noMoreExercises = CourseRecommendationPlanner.recommend(
            exercises: [first],
            courseLevels: [.init(exerciseID: first.id, status: .mastered, bestScore: 70)],
            attempts: [learnPass, basePass, consolidatePass]
        )
        XCTAssertNil(noMoreExercises, "Los retos de velocidad no bloquean la ruta de aprendizaje")
    }

    func testCourseRecommendationStopsWhenEveryMainChapterIsAccredited() {
        let exercise = Exercise(format: 1, id: "only", title: "Único", family: "test", level: 1, bpm: 70, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let state = CourseLevelState(exerciseID: exercise.id, status: .mastered, bestScore: 80, chapterAccredited: true)

        XCTAssertNil(CourseRecommendationPlanner.recommend(exercises: [exercise], courseLevels: [state], evidence: []))
    }

    func testCourseRecommendationDoesNotReturnToExercisesCoveredByCheckpoint() {
        let coveredExercise = Exercise(format: 1, id: "covered", title: "Cubierto", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let nextExercise = Exercise(format: 1, id: "next", title: "Siguiente", family: "test", level: 2, bpm: 90, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [])
        let levels = [
            CourseLevelState(
                exerciseID: coveredExercise.id,
                status: .mastered,
                bestScore: nil,
                creditSource: .checkpoint(exerciseID: "block_checkpoint"),
                chapterAccredited: true
            ),
            CourseLevelState(exerciseID: nextExercise.id, status: .locked, bestScore: nil)
        ]

        XCTAssertNil(CourseRecommendationPlanner.recommend(
            exercises: [coveredExercise, nextExercise],
            courseLevels: levels,
            evidence: []
        ))
    }

    func testBundledCheckpointContinuationStaysInTheFirstUnaccreditedChapter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        let graph = try CourseGraph(exercises: exercises)
        var evidence = [CourseAttemptEvidence]()

        for (index, chapter) in graph.mainChapterIDs.enumerated() {
            let checkpoint = try XCTUnwrap(graph.checkpoint(for: chapter)).exercise
            let before = graph.states(evidence: evidence)
            let pending = try XCTUnwrap(CourseRecommendationPlanner.recommend(
                exercises: exercises, courseLevels: before, evidence: evidence))
            XCTAssertEqual(graph.node(for: pending.exerciseID)?.metadata.chapter, chapter)
            let continuation = CourseRecommendationPlanner.nextExercise(after: checkpoint.id,
                exercises: exercises, courseLevels: before, evidence: evidence)
            XCTAssertTrue(continuation == nil || continuation?.metadata?.chapter == chapter,
                "No debe saltar al bloque siguiente mientras el actual no está acreditado")

            evidence.append(.init(exerciseID: checkpoint.id, bpm: CourseLessonCriteria.targetBPM(for: checkpoint),
                score: 80, stars: 2, trainingContext: .init(evaluationScope: .fullPattern,
                    completedBars: checkpoint.bars * checkpoint.repeats)))
            let after = graph.states(evidence: evidence)
            let next = CourseRecommendationPlanner.nextExercise(after: checkpoint.id,
                exercises: exercises, courseLevels: after, evidence: evidence)
            if index + 1 < graph.mainChapterIDs.count {
                XCTAssertEqual(try XCTUnwrap(next).metadata?.chapter, graph.mainChapterIDs[index + 1])
                // Repasar un ejercicio de un bloque acreditado debe continuar
                // por la ruta pendiente, no por otra lección del bloque cerrado.
                let first = try XCTUnwrap(graph.nodes.first { $0.metadata.chapter == chapter }).exercise
                XCTAssertEqual(CourseRecommendationPlanner.nextExercise(after: first.id,
                    exercises: exercises, courseLevels: after, evidence: evidence)?.id, next?.id)
            } else {
                XCTAssertNil(next)
                XCTAssertNil(CourseRecommendationPlanner.recommend(exercises: exercises,
                    courseLevels: after, evidence: evidence))
            }
        }
    }

    func testCourseRecommendationDoesNotSkipAnOpenChapterForAnAvailableFutureExercise() {
        func exercise(_ id: String, level: Int, chapter: String) -> Exercise {
            Exercise(format: 1, id: id, title: id, family: "test", level: level, bpm: 80,
                meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [],
                metadata: .init(id: id, chapter: chapter, position: 1, prerequisites: [],
                    objective: nil, newDifficulty: nil, recommendedHelp: .full, flags: []))
        }
        let current = exercise("current", level: 1, chapter: "initiation")
        let future = exercise("future", level: 2, chapter: "fundamentals")
        let states: [CourseLevelState] = [
            .init(exerciseID: current.id, status: .mastered, bestScore: 90),
            .init(exerciseID: future.id, status: .available, bestScore: nil)
        ]
        // Un resultado legado puede dominar individualmente una lección sin
        // cumplir todavía el criterio vigente del bloque.
        XCTAssertEqual(CourseRecommendationPlanner.recommend(exercises: [current, future],
            courseLevels: states, evidence: [])?.exerciseID, current.id)
        XCTAssertNil(CourseRecommendationPlanner.nextExercise(after: current.id,
            exercises: [current, future], courseLevels: states, evidence: []))
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

    func testAdvancedTempoUnlocksEarlierExercisesWithoutAccreditingThem() throws {
        func exercise(_ id: String, level: Int, chapter: String, position: Int, prerequisites: [String] = [], flags: [String] = []) -> Exercise {
            Exercise(
                format: 1, id: id, title: id, family: "test", level: level, bpm: 80,
                meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil,
                offset: 0, notes: [], metadata: .init(
                    id: id, chapter: chapter, position: position, prerequisites: prerequisites,
                    objective: nil, newDifficulty: nil, recommendedHelp: .full, flags: flags
                )
            )
        }
        let exercises = [
            exercise("i1", level: 1, chapter: "initiation", position: 1, flags: ["fast-start"]),
            exercise("i2", level: 2, chapter: "initiation", position: 2, prerequisites: ["i1"]),
            exercise("i3", level: 3, chapter: "initiation", position: 3, prerequisites: ["i2"], flags: ["checkpoint"]),
            exercise("f1", level: 4, chapter: "fundamentals", position: 1, prerequisites: ["i3"]),
            exercise("f2", level: 5, chapter: "fundamentals", position: 2, prerequisites: ["f1"], flags: ["checkpoint"])
        ]
        let graph = try CourseGraph(exercises: exercises)
        let advancedPass = PracticeAttempt(exerciseID: "f1", timestamp: .init(), bpm: 120, score: 70, stars: 2, perfect: 1, good: 0, regular: 0, miss: 0, extra: 0, meanOffsetMilliseconds: 0)

        XCTAssertEqual(graph.states(attempts: [advancedPass]).map(\.status), [.available, .available, .available, .mastered, .locked])
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
        XCTAssertEqual(tuning.perfectWindowMilliseconds, 35)
        XCTAssertEqual(tuning.goodWindowMilliseconds, 35)
        XCTAssertEqual(tuning.regularWindowMilliseconds, 35)
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

    func testDebugScoringWindowsCanSetJudgementThresholds() {
        let tuning = PracticeTuning(debugEnabled: true, perfectWindowMilliseconds: 12, goodWindowMilliseconds: 24, regularWindowMilliseconds: 48)
        let windows = tuning.scoringWindows(bpm: 100, grid: 16)

        XCTAssertEqual(windows.perfectMilliseconds, 12)
        XCTAssertEqual(windows.goodMilliseconds, 24)
        XCTAssertEqual(windows.regularMilliseconds, 48)
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

    func testLoopRecommendationPrioritizesGenreThenClosestTempo() throws {
        let metadata = try XCTUnwrap(try MIDIExerciseMetadataParser.parse(textEvents: [
            "xroll/1 id=10_hh_01",
            "xroll/1 chapter=hiphop",
            "xroll/1 position=1"
        ]))
        let hiphop = Exercise(
            format: 1, id: "10_hh_01", title: "Hip-hop · Boom bap", family: "midi",
            level: 1, bpm: 72, meter: [4, 4], bars: 1, grid: 16, repeats: 4,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")], metadata: metadata
        )
        let options = [
            LoopLibraryOption(id: "bass 90bpm.wav", fileName: "bass 90bpm.wav", bpm: 90, url: URL(fileURLWithPath: "/loops/bass 90bpm.wav")),
            LoopLibraryOption(id: "Piano 88bpm.wav", fileName: "Piano 88bpm.wav", bpm: 88, url: URL(fileURLWithPath: "/loops/Piano 88bpm.wav")),
            LoopLibraryOption(id: "Hip hop 86bpm.wav", fileName: "Hip hop 86bpm.wav", bpm: 86, url: URL(fileURLWithPath: "/loops/Hip hop 86bpm.wav")),
            LoopLibraryOption(id: "Bass Hiphop 93bpm.wav", fileName: "Bass Hiphop 93bpm.wav", bpm: 93, url: URL(fileURLWithPath: "/loops/Bass Hiphop 93bpm.wav"))
        ]

        XCTAssertEqual(LoopLibraryCatalog.recommended(for: hiphop, options: options)?.id, "Hip hop 86bpm.wav")
        XCTAssertEqual(LoopLibraryCatalog.recommended(for: hiphop, targetBPM: 95, options: options)?.id, "Bass Hiphop 93bpm.wav")

        let genericMetadata = try XCTUnwrap(try MIDIExerciseMetadataParser.parse(textEvents: [
            "xroll/1 id=generic",
            "xroll/1 chapter=groove",
            "xroll/1 position=1"
        ]))
        let genericExercise = Exercise(
            format: 1, id: "generic", title: "Groove", family: "midi", level: 1,
            bpm: 90, meter: [4, 4], bars: 1, grid: 16, repeats: 4,
            kit: "kit", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")], metadata: genericMetadata
        )
        XCTAssertEqual(LoopLibraryCatalog.recommended(for: genericExercise, targetBPM: 91, options: options)?.id, "bass 90bpm.wav")
    }

    // MARK: - Endurecimiento del loader MIDI y validación de recursos

    private func writeCommunityMIDI(track: [UInt8], division: UInt16 = 480, format: UInt16 = 1) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-loader-\(UUID().uuidString).mid")
        let header: [UInt8] = [
            0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6,
            UInt8(format >> 8), UInt8(format & 0xFF), 0, 1,
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

    private func tempoTrack(
        notes: [(delta: Int, note: UInt8)],
        tempo: [UInt8]? = [0x07, 0xA1, 0x20],
        additionalTempos: [[UInt8]] = [],
        meters: [[UInt8]] = [[0x04, 0x02, 0x18, 0x08]]
    ) -> [UInt8] {
        var track: [UInt8] = [0x00, 0xFF, 0x03, 0x04] + Array("Test".utf8)
        for meter in meters { track += [0x00, 0xFF, 0x58, UInt8(meter.count)] + meter }
        if let tempo { track += [0x00, 0xFF, 0x51, 0x03] + tempo }
        for additionalTempo in additionalTempos { track += [0x00, 0xFF, 0x51, 0x03] + additionalTempo }
        for note in notes { track += vlq(note.delta) + [0x99, note.note, 0x64] }
        track += [0x00, 0xFF, 0x2F, 0x00]
        return track
    }

    func testCommunityMIDIRejectsSMFFormatTwo() throws {
        let url = try writeCommunityMIDI(track: tempoTrack(notes: [(0, 36)]), format: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .unsupportedFormat(2) = error as? MIDIExerciseError else {
                return XCTFail("Se esperaba rechazar SMF tipo 2; se obtuvo: \(error)")
            }
        }
    }

    func testCommunityMIDIAcceptsSMFFormatZero() throws {
        let url = try writeCommunityMIDI(track: tempoTrack(notes: [(0, 36)]), format: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        let exercise = try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)
        XCTAssertEqual(exercise.notes.map(\.sound), ["kick"])
        XCTAssertEqual(exercise.bpm, 120)
    }

    func testCommunityMIDIRejectsOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-oversized-\(UUID().uuidString).mid")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(MIDIExerciseLoader.maximumFileBytes + 1))
        try file.close()

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .fileTooLarge = error as? MIDIExerciseError else {
                return XCTFail("Se esperaba limitar el tamaño del MIDI; se obtuvo: \(error)")
            }
        }
    }

    func testCommunityMIDIRejectsMeterChangesBackToFourFour() throws {
        let track = tempoTrack(notes: [(0, 36)], meters: [
            [0x04, 0x02, 0x18, 0x08],
            [0x03, 0x02, 0x18, 0x08],
            [0x04, 0x02, 0x18, 0x08]
        ])
        let url = try writeCommunityMIDI(track: track)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .unsupportedMeter = error as? MIDIExerciseError else {
                return XCTFail("Se esperaba rechazar cambios de compás; se obtuvo: \(error)")
            }
        }
    }

    func testCommunityMIDIRejectsDuplicateTempoEvents() throws {
        let track = tempoTrack(notes: [(0, 36)], additionalTempos: [[0x07, 0xA1, 0x20]])
        let url = try writeCommunityMIDI(track: track)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .invalidFile(let message) = error as? MIDIExerciseError, message.contains("más de un metaevento") else {
                return XCTFail("Se esperaba rechazar metaeventos de tempo duplicados; se obtuvo: \(error)")
            }
        }
    }

    func testCommunityMIDIRejectsPatternsLongerThanTheSupportedLimit() throws {
        let notes = (0..<257).map { _ in (delta: 1_920, note: UInt8(36)) }
        let url = try writeCommunityMIDI(track: tempoTrack(notes: notes))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MIDIExerciseLoader.load(url: url, kit: communityKit(), level: 1)) { error in
            guard case .patternTooLong(let bars) = error as? MIDIExerciseError, bars == 257 else {
                return XCTFail("Se esperaba limitar la duración del ejercicio; se obtuvo: \(error)")
            }
        }
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

    func testPadMapV2RejectsWhitespaceOnlyIdentifiers() {
        let map = PadMapV2(id: " ", name: "\n", preset: .custom, device: .init(name: "Pad", uid: 1), created: "2026-09-25", pads: [
            .init(id: "r0c0", row: 0, column: 0, sound: "kick", role: " \t", input: .init(number: 36, channel: 10))
        ])

        XCTAssertThrowsError(try map.validate(availableSounds: ["kick"]))
    }

    func testExerciseRejectsWhitespaceOnlyPadTarget() {
        let exercise = Exercise(format: 1, id: "target", title: "Target", family: "test", level: 1, bpm: 80, meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "kit", loop: nil, offset: 0, notes: [
            .init(step: 0, sound: "kick", target: .init(type: .pad, value: " \t"))
        ])

        XCTAssertThrowsError(try exercise.validate(availableSounds: ["kick"]))
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
