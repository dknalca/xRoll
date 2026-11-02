import XCTest
@testable import XRollCore

final class CurriculumValidationTests: XCTestCase {
    private func lesson(_ id: String, position: Int, prerequisites: [String] = [], flags: [String] = []) -> Exercise {
        let metadata = MIDIExerciseMetadata(id: id, chapter: "chapter", position: position,
            prerequisites: prerequisites, objective: nil, newDifficulty: nil, recommendedHelp: nil, flags: flags)
        return Exercise(format: 1, id: id, title: id, family: "test", level: position, bpm: 100,
            meter: [4, 4], bars: 1, grid: 16, repeats: 1, kit: "test", loop: nil, offset: 0,
            notes: [.init(step: 0, sound: "kick")], metadata: metadata)
    }

    func testValidationPreservesEachCurriculumRule() throws {
        let first = lesson("first", position: 1, flags: ["fast-start"])
        let last = lesson("last", position: 2, prerequisites: ["first"], flags: ["checkpoint"])
        XCTAssertNoThrow(try CurriculumValidator.validateIntegratedExercises([first, last]))

        func check(_ lessons: [Exercise], _ expected: CurriculumValidationError) {
            XCTAssertThrowsError(try CurriculumValidator.validateIntegratedExercises(lessons)) {
                XCTAssertEqual($0 as? CurriculumValidationError, expected)
            }
        }
        check([first, first], .duplicateID("first"))
        check([first, lesson("last", position: 3, flags: ["checkpoint"])], .invalidChapterPosition(chapter: "chapter"))
        check([first, lesson("last", position: 2)], .missingChapterCheckpoint(chapter: "chapter"))
        check([lesson("first", position: 1, flags: ["fast-start", "checkpoint"]), last],
              .multipleChapterCheckpoints(chapter: "chapter"))
        check([lesson("first", position: 1, flags: ["fast-start", "checkpoint"]), lesson("last", position: 2)],
              .checkpointNotLast(chapter: "chapter"))
        check([first, lesson("last", position: 2, prerequisites: ["unknown"], flags: ["checkpoint"])],
              .unknownPrerequisite(exerciseID: "last", prerequisiteID: "unknown"))
        check([lesson("first", position: 1), last], .invalidFastStartCount(0))
        check([lesson("first", position: 1, prerequisites: ["last"], flags: ["fast-start"]), last],
              .cyclicPrerequisites("first"))
    }
}
