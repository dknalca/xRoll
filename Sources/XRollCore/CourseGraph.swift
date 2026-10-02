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
        states(evidence: attempts.map(CourseAttemptEvidence.init), completionScore: completionScore)
    }

    public func states(evidence: [CourseAttemptEvidence], completionScore: Double = 70) -> [CourseLevelState] {
        let evidenceByExercise = Dictionary(grouping: evidence, by: \.exerciseID)
        let directScores = Dictionary(uniqueKeysWithValues: nodes.compactMap { node -> (String, Double)? in
            let qualifying = evidenceByExercise[node.metadata.id, default: []].filter {
                TempoLadder.isConsolidated(node.exercise, evidence: [$0], minimumScore: completionScore)
            }
            guard let best = qualifying.map(\.score).max() else { return nil }
            return (node.metadata.id, best)
        })
        let directlyCompleted = Set(directScores.keys)
        let advancedPasses = Set(nodes.compactMap { node -> String? in
            let consolidationBPM = TempoLadder.steps(for: node.exercise).first(where: { $0.label == "Consolidar" })?.bpm ?? 100
            let passedAdvancedTempo = evidenceByExercise[node.metadata.id, default: []].contains {
                $0.bpm > consolidationBPM
                    && $0.score >= completionScore
                    && $0.trainingContext.evaluationScope.countsAsCompletePattern
            }
            return passedAdvancedTempo ? node.metadata.id : nil
        })
        let advancedUnlocks = Set(nodes.enumerated().flatMap { index, node in
            advancedPasses.contains(node.metadata.id)
                ? nodes[..<index].map { $0.metadata.id }
                : []
        })
        let fullPatternCompleted = Set(nodes.compactMap { node -> String? in
            guard evidenceByExercise[node.metadata.id, default: []].contains(where: {
                $0.trainingContext.evaluationScope == .fullPattern
                    && TempoLadder.isConsolidated(node.exercise, evidence: [$0], minimumScore: completionScore)
            }) else { return nil }
            return node.metadata.id
        })
        let passedCheckpoints = Set(nodes.compactMap { node -> String? in
            guard node.metadata.flags.contains("checkpoint"),
                  TempoLadder.isCheckpointPassed(
                    node.exercise,
                    evidence: evidenceByExercise[node.metadata.id, default: []],
                    minimumScore: completionScore
                  ) else { return nil }
            return node.metadata.id
        })
        let mainChapters = orderedChapters(excludingFills: true)
        var accreditedMainChapters = Set<String>()
        var checkpointCredits = [String: String]()

        for (index, chapterID) in mainChapters.enumerated() {
            let chapterNodes = nodes.filter { $0.metadata.chapter == chapterID }
            let previousChapterAccredited = index == 0 || accreditedMainChapters.contains(mainChapters[index - 1])
            let allExercisesPassed = chapterNodes.allSatisfy { directlyCompleted.contains($0.metadata.id) }
            let checkpoint = chapterNodes.first(where: { $0.metadata.flags.contains("checkpoint") })
            let passedCheckpoint = checkpoint.map { passedCheckpoints.contains($0.metadata.id) } ?? false
            let chapterAccredited = previousChapterAccredited && (allExercisesPassed || passedCheckpoint)
            guard chapterAccredited else { continue }

            accreditedMainChapters.insert(chapterID)
            if passedCheckpoint, !allExercisesPassed, let checkpoint {
                for node in chapterNodes where !directlyCompleted.contains(node.metadata.id) {
                    checkpointCredits[node.metadata.id] = checkpoint.metadata.id
                }
            }
        }

        let fillChapters = orderedChapters(excludingFills: false).filter { $0.hasPrefix("fills-") }
        var accreditedFillChapters = Set<String>()
        for chapterID in fillChapters {
            let chapterNodes = nodes.filter { $0.metadata.chapter == chapterID }
            let allExercisesPassed = chapterNodes.allSatisfy { directlyCompleted.contains($0.metadata.id) }
            let checkpoint = chapterNodes.first(where: { $0.metadata.flags.contains("checkpoint") })
            let checkpointPassed = checkpoint.map { passedCheckpoints.contains($0.metadata.id) } ?? false
            let checkpointPrerequisitesPassed = checkpoint?.metadata.prerequisites.allSatisfy(fullPatternCompleted.contains) ?? false
            guard allExercisesPassed || (checkpointPassed && checkpointPrerequisitesPassed) else { continue }
            accreditedFillChapters.insert(chapterID)
            if checkpointPassed, !allExercisesPassed, let checkpoint {
                for node in chapterNodes where !directlyCompleted.contains(node.metadata.id) {
                    checkpointCredits[node.metadata.id] = checkpoint.metadata.id
                }
            }
        }

        let completedForPrerequisites = directlyCompleted.union(checkpointCredits.keys)
        let chapterIndexByID = Dictionary(uniqueKeysWithValues: mainChapters.enumerated().map { ($0.element, $0.offset) })
        return nodes.map { node in
            let exerciseID = node.metadata.id
            let directScore = directScores[exerciseID]
            let checkpointCreditID = checkpointCredits[exerciseID]
            let isMastered = directScore != nil || checkpointCreditID != nil
            let chapterIndex = chapterIndexByID[node.metadata.chapter]
            let previousChapterAccredited: Bool
            if node.metadata.chapter.hasPrefix("fills-") || chapterIndex == nil || chapterIndex == 0 {
                previousChapterAccredited = true
            } else if let chapterIndex {
                previousChapterAccredited = accreditedMainChapters.contains(mainChapters[chapterIndex - 1])
            } else {
                previousChapterAccredited = false
            }
            let isFastStart = node.metadata.flags.contains("fast-start")
            let isCheckpoint = node.metadata.flags.contains("checkpoint")
            let prerequisitesPassed = node.metadata.prerequisites.allSatisfy(completedForPrerequisites.contains)
            let available = isMastered || isFastStart || advancedUnlocks.contains(exerciseID) || (
                previousChapterAccredited && (isCheckpoint || prerequisitesPassed)
            )
            let chapterAccredited = node.metadata.chapter.hasPrefix("fills-")
                ? accreditedFillChapters.contains(node.metadata.chapter)
                : accreditedMainChapters.contains(node.metadata.chapter)
            return CourseLevelState(
                exerciseID: exerciseID,
                status: isMastered ? .mastered : (available ? .available : .locked),
                bestScore: directScore,
                creditSource: checkpointCreditID.map(CourseCreditSource.checkpoint(exerciseID:)) ?? (directScore == nil ? nil : .individualAttempt),
                chapterAccredited: chapterAccredited
            )
        }
    }

    public func checkpoint(for chapterID: String) -> Node? {
        nodes.first { $0.metadata.chapter == chapterID && $0.metadata.flags.contains("checkpoint") }
    }

    public var mainChapterIDs: [String] { orderedChapters(excludingFills: true) }

    private func orderedChapters(excludingFills: Bool) -> [String] {
        nodes.reduce(into: [String]()) { chapters, node in
            if excludingFills && node.metadata.chapter.hasPrefix("fills-") { return }
            if !chapters.contains(node.metadata.chapter) { chapters.append(node.metadata.chapter) }
        }
    }

    public func node(for exerciseID: String) -> Node? {
        nodesByID[exerciseID]
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
