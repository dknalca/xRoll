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

    /// Proyección del recorrido sobre la misma evidencia curricular. Los nombres
    /// de API históricos se conservan; cada bloque se presenta como una estación.
    public func worlds(evidence: [CourseAttemptEvidence]) -> [CourseWorld] {
        let courseStates = states(evidence: evidence)
        let byID = Dictionary(uniqueKeysWithValues: courseStates.map { ($0.exerciseID, $0) })
        let recommendation = CourseRecommendationPlanner.recommend(exercises: nodes.map(\.exercise),
            courseLevels: courseStates, evidence: evidence)
        let currentChapter = mainChapterIDs.first { chapter in
            nodes.contains { $0.metadata.chapter == chapter && byID[$0.metadata.id]?.chapterAccredited != true }
        }
        return mainChapterIDs.enumerated().map { index, chapter in
            let chapterNodes = nodes.filter { $0.metadata.chapter == chapter }
            let levels = chapterNodes.map { node in
                CourseWorld.Level(exercise: node.exercise, number: node.metadata.position,
                    isBoss: node.metadata.flags.contains("checkpoint"),
                    isPassed: byID[node.metadata.id]?.status == .mastered,
                    isNext: recommendation?.exerciseID == node.metadata.id)
            }
            return CourseWorld(id: chapter, number: index + 1, levels: levels,
                isCompleted: chapterNodes.allSatisfy { byID[$0.metadata.id]?.chapterAccredited == true },
                isCurrent: currentChapter == chapter)
        }
    }

    /// La celebración pertenece a una acreditación nueva, no a repetir un reto
    /// conocido ni a aprobar uno futuro cuya estación aún no puede acreditarse.
    public func worldVictory(completing attempt: CourseAttemptEvidence,
                             previousEvidence: [CourseAttemptEvidence]) -> CourseWorldVictory? {
        guard attempt.trainingContext.evaluationScope == .fullPattern,
              let chapter = node(for: attempt.exerciseID)?.metadata.chapter,
              !chapter.hasPrefix("fills-") else { return nil }
        let before = worlds(evidence: previousEvidence)
        let after = worlds(evidence: previousEvidence + [attempt])
        guard let world = after.first(where: { $0.id == chapter }), world.isCompleted,
              before.first(where: { $0.id == chapter })?.isCompleted == false else { return nil }
        let next = after.first(where: \.isCurrent)
        return CourseWorldVictory(worldNumber: world.number, worldTitle: world.title,
            nextWorldNumber: next?.number, nextWorldTitle: next?.title)
    }

    /// Aprobar un nivel prioriza continuar por su estación. Un ejercicio
    /// explorado en otra parada no redirige silenciosamente a la estación actual.
    public func campaignContinuation(after attempt: CourseAttemptEvidence,
                                     evidence: [CourseAttemptEvidence]) -> CourseWorld.Level? {
        guard attempt.trainingContext.evaluationScope == .fullPattern,
              let node = node(for: attempt.exerciseID),
              CourseLessonCriteria.isPassed(node.exercise, evidence: [attempt]),
              let current = worlds(evidence: evidence).first(where: \.isCurrent),
              current.id == node.metadata.chapter,
              let next = current.nextLevel, next.id != attempt.exerciseID else { return nil }
        return next
    }

    /// Devuelve la primera estación anterior pendiente, no solo la inmediatamente
    /// anterior: una prueba adelantada puede depender de varios bloques abiertos.
    public func pendingChapter(before exerciseID: String, states: [CourseLevelState]) -> Node? {
        guard let chapter = node(for: exerciseID)?.metadata.chapter,
              let index = mainChapterIDs.firstIndex(of: chapter) else { return nil }
        let accredited = Dictionary(uniqueKeysWithValues: states.map { ($0.exerciseID, $0.chapterAccredited) })
        let statuses = Dictionary(uniqueKeysWithValues: states.map { ($0.exerciseID, $0.status) })
        for chapterID in mainChapterIDs.prefix(index) {
            let chapterNodes = nodes.filter { $0.metadata.chapter == chapterID }
            if !chapterNodes.allSatisfy({ accredited[$0.metadata.id] == true }) {
                return chapterNodes.first { statuses[$0.metadata.id] != .mastered } ?? chapterNodes.first
            }
        }
        return nil
    }

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

public struct CourseWorld: Equatable, Identifiable {
    public struct Level: Equatable, Identifiable {
        public var id: String { exercise.id }
        public let exercise: Exercise
        public let number: Int
        public let isBoss: Bool
        public let isPassed: Bool
        public let isNext: Bool
        public var title: String {
            let parts = exercise.title.split(separator: "·", maxSplits: 1)
            return String(parts.last ?? Substring(exercise.title)).trimmingCharacters(in: .whitespaces)
        }
        public var label: String { isBoss ? "Reto de estación" : "Nivel \(number)" }
        public var actionTitle: String { isBoss ? CourseWorld.challengeActionTitle : "Empezar nivel \(number)" }
        public var continuationTitle: String { isBoss ? CourseWorld.challengeActionTitle : "Continuar" }
        public var continuationMessage: String {
            isBoss ? "Nivel superado. Te espera el reto final de esta estación." : "Nivel superado. Sigue con \(title)."
        }
    }

    public let id: String
    public let number: Int
    public let levels: [Level]
    public let isCompleted: Bool
    public let isCurrent: Bool
    public var title: String { Self.title(for: id) }
    public var completedLevelCount: Int { levels.filter(\.isPassed).count }
    public var nextLevel: Level? { levels.first(where: \.isNext) }
    public var boss: Level? { levels.first(where: \.isBoss) }
    public var isBossReady: Bool { isCurrent && nextLevel?.isBoss == true }
    public var statusLabel: String {
        if isCompleted { return "Estación completada" }
        if isBossReady { return "Reto de estación listo" }
        if isCurrent { return "Tu parada actual" }
        return "Próxima parada"
    }

    public static let challengeActionTitle = "Preparar reto final"
    public static let challengeNeedsRetry = "Reto pendiente: necesitas al menos el 70 % con el patrón completo al tempo de aprendizaje."
    public static let challengeCompleted = "Reto superado: esta estación ya está completada."
    public static let challengeSaved = "Tu resultado queda guardado. Completa las estaciones anteriores para continuar el recorrido."
    public static func pendingStationMessage(_ title: String) -> String {
        "Reto superado. Para completar esta estación, completa antes \(title). Tu resultado queda guardado."
    }
    public static func challengeTitle(for chapter: String) -> String { "Reto de estación · \(title(for: chapter))" }
    public static func challengeInstructions(bpm: Int) -> String {
        "El reto reúne los ritmos de esta estación. Toca el patrón completo a \(bpm) BPM y alcanza el 70 % para completarla. Si quedan estaciones anteriores pendientes, tu resultado queda guardado hasta terminarlas."
    }

    public static func title(for chapter: String) -> String {
        switch chapter {
        case "initiation": return "Iniciación"
        case "fundamentals": return "Fundamentos"
        case "coordination": return "Coordinación"
        case "subdivision": return "Subdivisión"
        case "groove": return "Groove y fraseo"
        case "hiphop": return "Hip-hop"
        case "rock": return "Rock"
        case "disco": return "Disco"
        case "funk": return "Funk"
        case "reggae": return "Reggae"
        case "dembow": return "Dembow"
        case "blues": return "Blues / Shuffle"
        case "jazz": return "Jazz"
        case "clave-bossa": return "Clave / Bossa"
        case "fills": return "Redobles y transiciones"
        default: return chapter.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}

public struct CourseWorldVictory: Equatable {
    public let worldNumber: Int
    public let worldTitle: String
    public let nextWorldNumber: Int?
    public let nextWorldTitle: String?
    public var title: String { "¡Estación \(worldNumber) completada!" }
    public var message: String {
        if let nextWorldNumber, let nextWorldTitle {
            return "Has completado \(worldTitle). Próxima parada: \(nextWorldNumber) · \(nextWorldTitle)."
        }
        return "Has completado \(worldTitle) y llegado al final de la línea. ¡Recorrido completado!"
    }
    public var actionTitle: String { nextWorldTitle == nil ? "Ver mi recorrido" : "Siguiente parada" }
}
