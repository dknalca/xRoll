import XCTest
@testable import XRollCore

final class CheckpointNavigationTests: XCTestCase {
    func testFutureCheckpointIdentifiesTheEarliestPendingChapterAndKeepsEvidence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = ResourceCatalog()
        let kit = try catalog.loadKit(at: root.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json"))
        let graph = try CourseGraph(exercises: catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: kit))
        let future = try XCTUnwrap(graph.checkpoint(for: "subdivision"))
        func passed(_ exercise: Exercise) -> CourseAttemptEvidence {
            .init(exerciseID: exercise.id, bpm: CourseLessonCriteria.targetBPM(for: exercise), score: 90,
                trainingContext: .init(evaluationScope: .fullPattern, completedBars: exercise.bars * exercise.repeats))
        }
        var evidence = [passed(future.exercise)]
        for chapter in graph.mainChapterIDs.prefix(while: { $0 != "subdivision" }) {
            let states = graph.states(evidence: evidence)
            XCTAssertEqual(graph.pendingChapter(before: future.exercise.id, states: states)?.metadata.chapter, chapter)
            XCTAssertFalse(try XCTUnwrap(states.first { $0.exerciseID == future.exercise.id }).chapterAccredited)
            evidence.append(passed(try XCTUnwrap(graph.checkpoint(for: chapter)).exercise))
        }
        let accredited = graph.states(evidence: evidence)
        XCTAssertNil(graph.pendingChapter(before: future.exercise.id, states: accredited))
        XCTAssertTrue(try XCTUnwrap(accredited.first { $0.exerciseID == future.exercise.id }).chapterAccredited)
        let first = try XCTUnwrap(graph.nodes.first)
        XCTAssertNil(graph.pendingChapter(before: first.exercise.id, states: []))
        XCTAssertNil(graph.pendingChapter(before: "unknown", states: []))
    }
}
