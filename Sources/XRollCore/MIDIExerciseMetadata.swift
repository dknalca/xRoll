import Foundation

/// Metadatos curriculares transportados por metaeventos de texto `xroll/1`.
/// Son opcionales para mantener la compatibilidad con MIDI comunitario.
public struct MIDIExerciseMetadata: Codable, Equatable {
    public let id: String
    public let chapter: String
    public let position: Int
    public let prerequisites: [String]
    public let objective: String?
    public let newDifficulty: String?
    public let recommendedHelp: PracticeHelp?
    public let flags: [String]
}

public enum MIDIExerciseMetadataParser {
    public static func parse(textEvents: [String]) -> MIDIExerciseMetadata? {
        var values = [String: [String]]()
        for event in textEvents {
            guard event.hasPrefix("xroll/1 ") else { continue }
            let entry = event.dropFirst("xroll/1 ".count)
            guard let separator = entry.firstIndex(of: "=") else { return nil }
            let key = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
            guard !key.isEmpty, !value.isEmpty else { return nil }
            values[key, default: []].append(value)
        }

        guard !values.isEmpty,
              let id = singleValue("id", in: values),
              let chapter = singleValue("chapter", in: values),
              let positionText = singleValue("position", in: values),
              let position = Int(positionText), position > 0 else { return nil }

        let prerequisites = values["prerequisite", default: []]
        let objective = singleValue("objective", in: values)
        let newDifficulty = singleValue("new-difficulty", in: values)
        let recommendedHelp = singleValue("recommended-help", in: values).flatMap(PracticeHelp.init(rawValue:))
        if values["recommended-help"] != nil, recommendedHelp == nil { return nil }
        return MIDIExerciseMetadata(
            id: id,
            chapter: chapter,
            position: position,
            prerequisites: prerequisites,
            objective: objective,
            newDifficulty: newDifficulty,
            recommendedHelp: recommendedHelp,
            flags: values["flag", default: []]
        )
    }

    private static func singleValue(_ key: String, in values: [String: [String]]) -> String? {
        guard let entries = values[key] else { return nil }
        return entries.count == 1 ? entries[0] : nil
    }
}
