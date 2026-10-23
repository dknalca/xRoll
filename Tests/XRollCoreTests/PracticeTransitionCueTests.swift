import XCTest
@testable import XRollCore

final class PracticeTransitionCueTests: XCTestCase {
    private func exercise(bars: Int, repeats: Int = 1, bpm: Int = 60, notes: [Exercise.Note]) -> Exercise {
        Exercise(format: 1, id: "cues", title: "Avisos", family: "test", level: 1,
            bpm: bpm, meter: [4, 4], bars: bars, grid: 4, repeats: repeats,
            kit: "kit", loop: nil, offset: 0, notes: notes)
    }

    func testAnnouncesFirstEntryOfASoundAndTheClosingBar() {
        let phrase = exercise(bars: 3, notes: [
            .init(step: 0, sound: "kick"),
            .init(step: 4, sound: "kick"),
            .init(step: 4, sound: "snare"),
            .init(step: 8, sound: "kick")
        ])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.kind), [.soundEnters("snare"), .closing])
        XCTAssertEqual(cues.map(\.timeMilliseconds), [4_000, 8_000])
        XCTAssertEqual(cues.map(\.leadMilliseconds), [2_400, 2_400])
    }

    func testEntryCueOnlyAppearsInTheFirstRound() {
        let phrase = exercise(bars: 2, repeats: 2, notes: [
            .init(step: 0, sound: "kick"),
            .init(step: 4, sound: "kick"),
            .init(step: 4, sound: "snare")
        ])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.kind), [.soundEnters("snare"), .lastRound, .closing])
        XCTAssertEqual(cues.map(\.timeMilliseconds), [4_000, 8_000, 12_000])
    }

    func testEntryTakesPriorityWhenItCoincidesWithTheClosingBar() {
        let phrase = exercise(bars: 2, notes: [
            .init(step: 0, sound: "kick"),
            .init(step: 4, sound: "snare")
        ])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.kind), [.soundEnters("snare")])
        XCTAssertEqual(cues.first?.timeMilliseconds, 4_000)
    }

    func testSingleBarOnlyAnnouncesTheFinalRound() {
        let phrase = exercise(bars: 1, repeats: 3, notes: [.init(step: 0, sound: "kick")])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.kind), [.lastRound])
        XCTAssertEqual(cues.first?.timeMilliseconds, 8_000)
    }

    func testSingleRoundOfOneBarHasNoCues() {
        let phrase = exercise(bars: 1, notes: [.init(step: 0, sound: "kick")])
        XCTAssertTrue(PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase)).isEmpty)
    }

    func testCueLeadIsCappedToKeepTheLabelBrief() {
        let phrase = exercise(bars: 3, bpm: 40, notes: [
            .init(step: 0, sound: "kick"),
            .init(step: 4, sound: "snare"),
            .init(step: 8, sound: "kick")
        ])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.leadMilliseconds), [2_400, 2_400])
    }

    func testReturningSoundAfterASilentBarIsNotANewEntry() {
        let phrase = exercise(bars: 4, notes: [
            .init(step: 0, sound: "kick"),
            .init(step: 0, sound: "snare"),
            .init(step: 4, sound: "kick"),
            .init(step: 8, sound: "snare"),
            .init(step: 12, sound: "kick")
        ])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.kind), [.closing])
    }

    func testEntryMarkerTargetsTheFirstHitInsteadOfTheStartOfItsBar() {
        let phrase = exercise(bars: 3, notes: [
            .init(step: 0, sound: "kick"),
            .init(step: 6, sound: "snare"),
            .init(step: 8, sound: "kick")
        ])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.kind), [.soundEnters("snare"), .closing])
        XCTAssertEqual(cues.map(\.timeMilliseconds), [6_000, 8_000])
    }

    func testSimultaneousNewSoundsDoNotProduceAnotherEntryWhenTheyReturn() {
        let phrase = exercise(bars: 5, notes: [
            .init(step: 0, sound: "kick"),
            .init(step: 4, sound: "clap"),
            .init(step: 4, sound: "snare"),
            .init(step: 8, sound: "kick"),
            .init(step: 12, sound: "snare"),
            .init(step: 16, sound: "kick")
        ])
        let cues = PracticeTransitionCuePlanner.cues(for: ExerciseTimeline(exercise: phrase))
        XCTAssertEqual(cues.map(\.kind), [.soundEnters("clap"), .closing])
    }
}
