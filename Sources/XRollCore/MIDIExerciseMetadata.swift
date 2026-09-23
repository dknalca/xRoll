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

public enum MIDIExerciseMetadataError: LocalizedError, Equatable {
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let detail): return "Metadato xroll/1 no válido: \(detail)."
        }
    }
}

public enum MIDIExerciseMetadataParser {
    /// Devuelve `nil` si no hay ninguna línea `xroll/1` (MIDI comunitario sin
    /// metadatos, practicable pero fuera del recorrido oficial). Si hay líneas
    /// `xroll/1` y alguna es incorrecta, lanza en vez de degradar en silencio:
    /// una errata en un ejercicio integrado no debe pasar por "comunitario".
    public static func parse(textEvents: [String]) throws -> MIDIExerciseMetadata? {
        var values = [String: [String]]()
        for event in textEvents {
            guard event.hasPrefix("xroll/1 ") else { continue }
            let entry = event.dropFirst("xroll/1 ".count)
            guard let separator = entry.firstIndex(of: "=") else {
                throw MIDIExerciseMetadataError.malformed("falta '=' en '\(event)'")
            }
            let key = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
            guard !key.isEmpty, !value.isEmpty else {
                throw MIDIExerciseMetadataError.malformed("clave o valor vacio en '\(event)'")
            }
            values[key, default: []].append(value)
        }

        guard !values.isEmpty else { return nil }
        guard let id = try singleValue("id", in: values),
              let chapter = try singleValue("chapter", in: values),
              let positionText = try singleValue("position", in: values),
              let position = Int(positionText), position > 0 else {
            throw MIDIExerciseMetadataError.malformed("id, chapter o position no validos")
        }

        let prerequisites = values["prerequisite", default: []]
        let objective = try singleValue("objective", in: values)
        let newDifficulty = try singleValue("new-difficulty", in: values)
        let recommendedHelp = try singleValue("recommended-help", in: values).flatMap(PracticeHelp.init(rawValue:))
        if values["recommended-help"] != nil, recommendedHelp == nil {
            throw MIDIExerciseMetadataError.malformed("recommended-help desconocido")
        }
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

    private static func singleValue(_ key: String, in values: [String: [String]]) throws -> String? {
        guard let entries = values[key] else { return nil }
        guard entries.count == 1 else {
            throw MIDIExerciseMetadataError.malformed("'\(key)' aparece mas de una vez")
        }
        return entries[0]
    }
}
