import XCTest
@testable import XRollCore

final class PracticeStartupTests: XCTestCase {
    private func exercise(bpm: Int, grid: Int, bars: Int, repeats: Int) -> Exercise {
        Exercise(format: 1, id: "startup", title: "Inicio", family: "test", level: 1, bpm: bpm,
            meter: [4, 4], bars: bars, grid: grid, repeats: repeats, kit: "test", loop: nil, offset: 1,
            notes: [.init(step: 0, sound: "kick"), .init(step: grid - 1, sound: "snare")])
    }

    func testLightweightTimingPreservesTimelineDurationsForBothGrids() {
        for grid in [12, 16] {
            for bpm in [40, 68, 95, 110, 160, 240] {
                for bars in [1, 2, 8, 256] {
                    let source = exercise(bpm: bpm, grid: grid, bars: bars, repeats: 16)
                    let timeline = ExerciseTimeline(exercise: source)
                    let step = 60_000 / Double(bpm) * 4 / Double(grid)
                    XCTAssertEqual(timeline.stepDurationMilliseconds, step)
                    XCTAssertEqual(timeline.barDurationMilliseconds, step * Double(grid))
                    XCTAssertEqual(timeline.patternDurationMilliseconds, step * Double(bars * grid))
                    XCTAssertEqual(timeline.notes.count, source.notes.count * source.repeats)
                    for note in timeline.notes {
                        let original = source.notes[note.index % source.notes.count]
                        let repetition = note.index / source.notes.count
                        let shiftedStep = (original.step + source.offset) % (bars * grid)
                        let expectedTime = Double(repetition) * (step * Double(bars * grid)) + Double(shiftedStep) * step
                        XCTAssertEqual(note.timeMilliseconds, expectedTime)
                        XCTAssertEqual(note.sound, original.sound)
                    }
                }
            }
        }
    }

    func testReferencePlanKeepsTheSameOriginsWithoutExpandingRepeatedNotes() {
        for grid in [12, 16] {
            let scored = exercise(bpm: 95, grid: grid, bars: 2, repeats: 16)
            let reference = exercise(bpm: 70, grid: grid, bars: 8, repeats: 16)
            let timeline = ExerciseTimeline(exercise: scored)
            let oneRound = PracticeConfiguration(exercise: reference, bpm: scored.bpm, repeats: 1).applying(to: reference)
            let referenceTimeline = ExerciseTimeline(exercise: oneRound)
            for countInBars in [0, 1, 2, 4, 8] {
                let expectedCountIn = timeline.barDurationMilliseconds * Double(min(4, max(1, countInBars)))
                let direct = PracticeRehearsalPlan(exercise: scored, reference: reference, countInBars: countInBars, enabled: false)
                XCTAssertNil(direct.referenceExercise)
                XCTAssertEqual(direct.scoringStartMilliseconds, expectedCountIn)
                XCTAssertEqual(direct.referenceEndMilliseconds, expectedCountIn)
                let together = PracticeRehearsalPlan(exercise: scored, reference: reference, countInBars: countInBars, enabled: true)
                XCTAssertEqual(together.referenceExercise, oneRound)
                XCTAssertEqual(together.referenceStartMilliseconds, expectedCountIn)
                XCTAssertEqual(together.referenceEndMilliseconds, expectedCountIn + referenceTimeline.patternDurationMilliseconds)
                XCTAssertEqual(together.scoringStartMilliseconds, together.referenceEndMilliseconds + expectedCountIn)
            }
        }
    }

    func testCompletionKeepsTheSameBarBoundariesWithoutBuildingATimeline() {
        for grid in [12, 16] {
            let source = exercise(bpm: 95, grid: grid, bars: 8, repeats: 16)
            let barDuration = ExerciseTimeline(exercise: source).barDurationMilliseconds
            let totalBars = source.bars * source.repeats
            for elapsed in [-1.0, 0, barDuration.nextDown, barDuration, barDuration.nextUp,
                            barDuration * 7.5, barDuration * Double(totalBars), barDuration * Double(totalBars + 1)] {
                let completion = PracticeCompletion(exercise: source, elapsedMilliseconds: elapsed)
                let expected = Int(max(0, min(Double(totalBars), floor(elapsed / barDuration))))
                XCTAssertEqual(completion.completedBars, expected)
                XCTAssertEqual(completion.totalBars, totalBars)
                XCTAssertEqual(completion.isComplete, expected == totalBars)
            }
        }
    }

    func testNextSessionDurationMatchesTheConfiguredTimeline() throws {
        for grid in [12, 16] {
            for bars in [1, 8, 256] {
                let source = exercise(bpm: 95, grid: grid, bars: bars, repeats: 16)
                let state = CourseLevelState(exerciseID: source.id, status: .available, bestScore: nil)
                let plan = try XCTUnwrap(NextSessionPlanner.plan(exercises: [source], courseLevels: [state], attempts: []))
                let configured = PracticeConfiguration(exercise: source, bpm: plan.bpm, repeats: plan.repeats).applying(to: source)
                let duration = ExerciseTimeline(exercise: configured).patternDurationMilliseconds * Double(plan.repeats)
                XCTAssertEqual(plan.estimatedDurationMilliseconds, duration)
            }
        }
    }
}
