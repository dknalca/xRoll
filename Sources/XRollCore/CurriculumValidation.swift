import Foundation

public enum CurriculumValidationError: LocalizedError, Equatable {
    case missingMetadata(String)
    case duplicateID(String)
    case invalidChapterPosition(chapter: String)
    case unknownPrerequisite(exerciseID: String, prerequisiteID: String)
    case cyclicPrerequisites(String)
    case invalidFastStartCount(Int)

    public var errorDescription: String? {
        switch self {
        case .missingMetadata(let id): return "Faltan metadatos curriculares en \(id)."
        case .duplicateID(let id): return "El identificador curricular \(id) está repetido."
        case .invalidChapterPosition(let chapter): return "Las posiciones del capítulo \(chapter) no son consecutivas."
        case .unknownPrerequisite(let exerciseID, let prerequisiteID): return "\(exerciseID) requiere un ejercicio inexistente: \(prerequisiteID)."
        case .cyclicPrerequisites(let id): return "Los prerrequisitos curriculares contienen un ciclo en \(id)."
        case .invalidFastStartCount(let count): return "El curso debe declarar una sola vía rápida; encontró \(count)."
        }
    }
}

public enum CurriculumValidator {
    public static func validateIntegratedExercises(_ exercises: [Exercise]) throws {
        let metadata = try exercises.map { exercise -> MIDIExerciseMetadata in
            guard let metadata = exercise.metadata else { throw CurriculumValidationError.missingMetadata(exercise.id) }
            return metadata
        }
        var identifiers = Set<String>()
        for item in metadata {
            guard identifiers.insert(item.id).inserted else { throw CurriculumValidationError.duplicateID(item.id) }
        }
        for (_, chapter) in Dictionary(grouping: metadata, by: \.chapter) {
            let positions = chapter.map(\.position).sorted()
            guard positions == Array(1...chapter.count) else {
                throw CurriculumValidationError.invalidChapterPosition(chapter: chapter[0].chapter)
            }
        }
        let knownIDs = Set(metadata.map(\.id))
        for item in metadata {
            for prerequisite in item.prerequisites where !knownIDs.contains(prerequisite) {
                throw CurriculumValidationError.unknownPrerequisite(exerciseID: item.id, prerequisiteID: prerequisite)
            }
        }
        let fastStartCount = metadata.filter { $0.flags.contains("fast-start") }.count
        guard fastStartCount == 1 else { throw CurriculumValidationError.invalidFastStartCount(fastStartCount) }

        let prerequisites = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0.prerequisites) })
        var visiting = Set<String>()
        var visited = Set<String>()
        func visit(_ id: String) throws {
            if visited.contains(id) { return }
            guard visiting.insert(id).inserted else { throw CurriculumValidationError.cyclicPrerequisites(id) }
            for prerequisite in prerequisites[id, default: []] { try visit(prerequisite) }
            visiting.remove(id)
            visited.insert(id)
        }
        for item in metadata { try visit(item.id) }
    }
}
