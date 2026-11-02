import XCTest
@testable import XRollCore

final class MIDIExerciseMetadataParserTests: XCTestCase {
    private let required = ["xroll/1 id=lesson", "xroll/1 chapter=station", "xroll/1 position=2"]

    func testReadsRepeatedFieldsAndIgnoresOtherTextEvents() throws {
        let events = ["otro texto"] + required + [
            "xroll/1 prerequisite=first", "xroll/1 prerequisite=second",
            "xroll/1 flag=checkpoint", "xroll/1 flag=fast-start",
            "xroll/1 objective= aprender = tocar ", "xroll/1 recommended-help=full",
            "xroll/1 previous-learning-bpm=72", "xroll/1 future-field=conserva compatibilidad"
        ]
        let metadata = try XCTUnwrap(MIDIExerciseMetadataParser.parse(textEvents: events))
        XCTAssertEqual(metadata.id, "lesson")
        XCTAssertEqual(metadata.chapter, "station")
        XCTAssertEqual(metadata.position, 2)
        XCTAssertEqual(metadata.prerequisites, ["first", "second"])
        XCTAssertEqual(metadata.flags, ["checkpoint", "fast-start"])
        XCTAssertEqual(metadata.objective, "aprender = tocar")
        XCTAssertEqual(metadata.recommendedHelp, .full)
        XCTAssertEqual(metadata.previousLearningBPM, 72)
        XCTAssertNil(try MIDIExerciseMetadataParser.parse(textEvents: ["otro texto"]))
    }

    func testRejectsMalformedAndDuplicateValuesWithExistingErrors() {
        let cases: [([String], MIDIExerciseMetadataError)] = [
            (["xroll/1 id"], .malformed("falta '=' en 'xroll/1 id'")),
            (["xroll/1 id= "], .malformed("clave o valor vacio en 'xroll/1 id= '")),
            (required + ["xroll/1 id=other"], .malformed("'id' aparece mas de una vez")),
            (required + ["xroll/1 previous-learning-bpm=101"], .malformed("previous-learning-bpm fuera de 1...100")),
            (required + ["xroll/1 recommended-help=unknown"], .malformed("recommended-help desconocido"))
        ]
        for (events, expected) in cases {
            XCTAssertThrowsError(try MIDIExerciseMetadataParser.parse(textEvents: events)) {
                XCTAssertEqual($0 as? MIDIExerciseMetadataError, expected)
            }
        }
    }
}
