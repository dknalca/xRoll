import Foundation

/// Grafo curricular derivado exclusivamente de los metaeventos MIDI integrados.
public struct CourseGraph: Equatable {
    public struct Node: Equatable {
        public let exercise: Exercise
        public let metadata: MIDIExerciseMetadata
    }

    public let nodes: [Node]
    private let nodesByID: [String: Node]

    public init(exercises: [Exercise]) throws {
        try CurriculumValidator.validateIntegratedExercises(exercises)
        let unorderedNodes = exercises.compactMap { exercise -> Node? in
            exercise.metadata.map { Node(exercise: exercise, metadata: $0) }
        }.sorted {
            $0.exercise.level == $1.exercise.level
                ? $0.metadata.id < $1.metadata.id
                : $0.exercise.level < $1.exercise.level
        }
        let nodesByID = Dictionary(uniqueKeysWithValues: unorderedNodes.map { ($0.metadata.id, $0) })
        self.nodes = try Self.topologicallyOrdered(unorderedNodes, nodesByID: nodesByID)
        self.nodesByID = nodesByID
    }

    public func states(attempts: [PracticeAttempt], completionScore: Double = 70) -> [CourseLevelState] {
        let completedIDs = Set(attempts.compactMap { attempt -> String? in
            guard attempt.score >= completionScore,
                  let node = nodesByID[attempt.exerciseID],
                  attempt.bpm == node.exercise.bpm,
                  attempt.trainingContext.evaluationScope.countsAsCompletePattern else { return nil }
            return attempt.exerciseID
        })
        return nodes.map { node in
            let completed = completedIDs.contains(node.metadata.id)
            let available = completed
                || node.metadata.flags.contains("fast-start")
                || node.metadata.prerequisites.allSatisfy(completedIDs.contains)
            return CourseLevelState(
                exerciseID: node.metadata.id,
                status: completed ? .mastered : (available ? .available : .locked),
                bestScore: bestCompletionScore(for: node, attempts: attempts, completionScore: completionScore)
            )
        }
    }

    public func node(for exerciseID: String) -> Node? {
        nodesByID[exerciseID]
    }

    private func bestCompletionScore(for node: Node, attempts: [PracticeAttempt], completionScore: Double) -> Double? {
        attempts
            .filter {
                $0.exerciseID == node.metadata.id
                    && $0.score >= completionScore
                    && $0.bpm == node.exercise.bpm
                    && $0.trainingContext.evaluationScope.countsAsCompletePattern
            }
            .map(\.score)
            .max()
    }

    private static func topologicallyOrdered(_ nodes: [Node], nodesByID: [String: Node]) throws -> [Node] {
        var visited = Set<String>()
        var visiting = Set<String>()
        var ordered = [Node]()
        func visit(_ node: Node) throws {
            guard !visited.contains(node.metadata.id) else { return }
            guard visiting.insert(node.metadata.id).inserted else {
                throw CurriculumValidationError.cyclicPrerequisites(node.metadata.id)
            }
            for prerequisite in node.metadata.prerequisites {
                if let prerequisiteNode = nodesByID[prerequisite] { try visit(prerequisiteNode) }
            }
            visiting.remove(node.metadata.id)
            visited.insert(node.metadata.id)
            ordered.append(node)
        }
        for node in nodes { try visit(node) }
        return ordered
    }
}
