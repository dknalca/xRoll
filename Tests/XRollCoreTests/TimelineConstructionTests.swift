import XCTest
@testable import XRollCore

final class TimelineConstructionTests: XCTestCase {
    /// Algoritmo anterior como oráculo: expandir todas las vueltas y ordenar al final.
    private func referenceNotes(for exercise: Exercise) -> [ScheduledExerciseNote] {
        let stepDuration = 60_000 / Double(exercise.bpm) * 4 / Double(exercise.grid)
        let totalSteps = exercise.bars * exercise.grid
        let patternDuration = stepDuration * Double(totalSteps)
        var notes = [ScheduledExerciseNote]()
        for repetition in 0..<exercise.repeats {
            for (index, note) in exercise.notes.enumerated() {
                let step = (note.step + exercise.offset) % totalSteps
                notes.append(.init(index: repetition * exercise.notes.count + index,
                    step: step, sound: note.sound, hand: note.hand, target: note.target, velocity: note.velocity,
                    timeMilliseconds: Double(repetition) * patternDuration + Double(step) * stepDuration))
            }
        }
        return notes.sorted {
            $0.timeMilliseconds == $1.timeMilliseconds
                ? $0.index < $1.index : $0.timeMilliseconds < $1.timeMilliseconds
        }
    }

    private func copy(_ exercise: Exercise, repeats: Int, offset: Int) -> Exercise {
        Exercise(format: exercise.format, id: exercise.id, title: exercise.title, family: exercise.family,
            level: exercise.level, bpm: exercise.bpm, meter: exercise.meter, bars: exercise.bars,
            grid: exercise.grid, repeats: repeats, kit: exercise.kit, loop: exercise.loop,
            offset: offset, notes: exercise.notes, metadata: exercise.metadata)
    }

    func testEveryBundledTimelineMatchesThePreviousAlgorithmExactly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit)
        XCTAssertFalse(exercises.isEmpty)
        for exercise in exercises {
            for repeats in [1, 4, 16] {
                for offset in [0, 1, exercise.bars * exercise.grid - 1] {
                    let configured = copy(exercise, repeats: repeats, offset: offset)
                    XCTAssertEqual(ExerciseTimeline(exercise: configured).notes, referenceNotes(for: configured),
                        "\(exercise.id), \(repeats) vueltas, offset \(offset)")
                }
            }
        }
    }

    func testUnsortedSimultaneousNotesKeepTheirOriginalIdentityAndMetadata() {
        for grid in [12, 16] {
            for bars in [1, 3, 8] {
                let exercise = Exercise(format: 1, id: "order", title: "Orden", family: "test", level: 1,
                    bpm: 95, meter: [4, 4], bars: bars, grid: grid, repeats: 16, kit: "test", loop: nil,
                    offset: grid * bars - 1, notes: [
                        .init(step: bars * grid - 1, sound: "ride", hand: "L", target: .init(type: .pad, value: "ride-pad"), velocity: 1),
                        .init(step: grid / 2, sound: "snare", hand: "R", target: .init(type: .role, value: "snare-right"), velocity: 127),
                        .init(step: 0, sound: "kick", velocity: 64),
                        .init(step: 0, sound: "snare", target: .init(type: .any)),
                        .init(step: 1, sound: "hihat_closed")
                    ])
                XCTAssertEqual(ExerciseTimeline(exercise: exercise).notes, referenceNotes(for: exercise))
            }
        }
    }

    func testEmptyPatternsAndZeroRepetitionsRemainEmpty() {
        let empty = Exercise(format: 1, id: "empty", title: "Vacío", family: "test", level: 1, bpm: 100,
            meter: [4, 4], bars: 1, grid: 16, repeats: 16, kit: "test", loop: nil, offset: 0, notes: [])
        XCTAssertTrue(ExerciseTimeline(exercise: empty).notes.isEmpty)
        let zeroRepeats = Exercise(format: 1, id: "zero", title: "Cero", family: "test", level: 1, bpm: 100,
            meter: [4, 4], bars: 1, grid: 16, repeats: 0, kit: "test", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")])
        XCTAssertTrue(ExerciseTimeline(exercise: zeroRepeats).notes.isEmpty)
    }
}
