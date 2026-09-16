import Foundation

/// Ajustes de una sesión que no alteran el archivo original del ejercicio.
public struct PracticeConfiguration: Equatable {
    public var bpm: Int
    public var repeats: Int

    public init(exercise: Exercise, bpm: Int? = nil, repeats: Int? = nil) {
        self.bpm = min(240, max(40, bpm ?? exercise.bpm))
        self.repeats = Self.normalizedRepeats(repeats ?? exercise.repeats)
    }

    /// Practice lengths double each time, making short checks and long focused
    /// sessions equally quick to choose.
    public static func normalizedRepeats(_ value: Int) -> Int {
        let options = [1, 2, 4, 8, 16]
        return options.first(where: { $0 >= value }) ?? 16
    }

    public func applying(to exercise: Exercise) -> Exercise {
        Exercise(format: exercise.format, id: exercise.id, title: exercise.title, family: exercise.family,
                  level: exercise.level, bpm: bpm, meter: exercise.meter, bars: exercise.bars,
                  grid: exercise.grid, repeats: repeats, kit: exercise.kit, loop: exercise.loop,
                  offset: exercise.offset, notes: exercise.notes, metadata: exercise.metadata)
    }
}

public enum TempoAward: Equatable {
    case stars(Int)
    case trophies(Int)

    public var label: String {
        switch self {
        case .stars(let count): return "\(count) estrella\(count == 1 ? "" : "s")"
        case .trophies(let count): return "\(count) trofeo\(count == 1 ? "" : "s")"
        }
    }

    public var symbolName: String {
        switch self {
        case .stars: return "star.fill"
        case .trophies: return "trophy.fill"
        }
    }

    public var count: Int {
        switch self { case .stars(let count), .trophies(let count): return count }
    }
}

/// Escalones comunes que hacen comparable el progreso entre todos los ritmos.
public struct TempoPracticeStep: Equatable {
    public let label: String
    public let bpm: Int
    public let requiredScore: Double
    public let requiredPasses: Int
    public let minimumBars: Int?
    public let award: TempoAward

    public init(label: String, bpm: Int, requiredScore: Double, requiredPasses: Int, minimumBars: Int? = nil, award: TempoAward) {
        self.label = label
        self.bpm = bpm
        self.requiredScore = requiredScore
        self.requiredPasses = requiredPasses
        self.minimumBars = minimumBars
        self.award = award
    }
}

public enum TempoLadder {
    public static func steps(for exercise: Exercise) -> [TempoPracticeStep] {
        return [
            .init(label: "Aprender", bpm: 70, requiredScore: 70, requiredPasses: 1, award: .stars(1)),
            .init(label: "Base", bpm: 85, requiredScore: 70, requiredPasses: 1, award: .stars(2)),
            .init(label: "Consolidar", bpm: 100, requiredScore: 70, requiredPasses: 1, award: .stars(3)),
            .init(label: "Difícil", bpm: 120, requiredScore: 70, requiredPasses: 1, award: .trophies(1)),
            .init(label: "Jefe", bpm: 140, requiredScore: 70, requiredPasses: 1, award: .trophies(2)),
            .init(label: "Nivel dios", bpm: 160, requiredScore: 70, requiredPasses: 1, minimumBars: 16, award: .trophies(3))
        ]
    }

    public static func passedAttempts(for step: TempoPracticeStep, exerciseID: String, attempts: [PracticeAttempt]) -> Int {
        attempts.filter {
            $0.exerciseID == exerciseID
                && $0.bpm == step.bpm
                && $0.score >= step.requiredScore
                && $0.trainingContext.evaluationScope.countsAsCompletePattern
                && (step.minimumBars == nil || $0.trainingContext.completedBars >= step.minimumBars!)
        }.count
    }

    public static func isPassed(_ step: TempoPracticeStep, exerciseID: String, attempts: [PracticeAttempt]) -> Bool {
        passedAttempts(for: step, exerciseID: exerciseID, attempts: attempts) >= step.requiredPasses
    }

    public static func nextStep(for exercise: Exercise, attempts: [PracticeAttempt]) -> TempoPracticeStep? {
        steps(for: exercise).first { !isPassed($0, exerciseID: exercise.id, attempts: attempts) }
    }

    public static func highestPassedStep(for exercise: Exercise, attempts: [PracticeAttempt]) -> TempoPracticeStep? {
        steps(for: exercise).reversed().first { isPassed($0, exerciseID: exercise.id, attempts: attempts) }
    }

    public static func isConsolidated(_ exercise: Exercise, attempts: [PracticeAttempt], minimumScore: Double = 70) -> Bool {
        guard let step = steps(for: exercise).first(where: { $0.label == "Consolidar" }) else { return false }
        return attempts.contains {
            $0.exerciseID == exercise.id
                && $0.bpm == step.bpm
                && $0.score >= max(minimumScore, step.requiredScore)
                && $0.trainingContext.evaluationScope.countsAsCompletePattern
        }
    }

    public static func repeats(for step: TempoPracticeStep, exercise: Exercise) -> Int? {
        guard let minimumBars = step.minimumBars else { return nil }
        return PracticeConfiguration.normalizedRepeats(Int(ceil(Double(minimumBars) / Double(exercise.bars))))
    }
}

/// D-A-I-T: el mismo patrón se aborda con un objetivo didáctico distinto.
public enum TrainingPhase: String, CaseIterable, Codable {
    case discover, isolate, integrate, transfer
    public var label: String { switch self { case .discover: return "Descubrir"; case .isolate: return "Aislar"; case .integrate: return "Integrar"; case .transfer: return "Transferir" } }
    public var explanation: String { switch self {
    case .discover: return "Escucha y localiza el patrón; no se puntúa."
    case .isolate: return "Practica una voz o micro-fragmento lento antes de volver al groove."
    case .integrate: return "Toca el ritmo completo dentro de su contexto."
    case .transfer: return "Retira una guía para comprobar pulso interno y memoria."
    } }
}

/// Las 16 combinaciones de una negra en rejilla de semicorcheas. Sirve para
/// describir objetivamente la densidad rítmica de MIDI importado.
public enum RhythmAlphabet {
    public static func letters(for exercise: Exercise) -> [Int] {
        guard exercise.grid == 16 else { return [] }
        let stepsPerBar = 16
        return (0..<exercise.bars).flatMap { bar in
            (0..<4).map { beat in
                let base = bar * stepsPerBar + beat * 4
                let mask = (0..<4).reduce(0) { value, offset in
                    value | (exercise.notes.contains { $0.step == base + offset } ? (1 << (3 - offset)) : 0)
                }
                return mask + 1
            }
        }
    }
}

public struct WarmupRecommendation: Equatable {
    public let exerciseID: String
    public let title: String
    public let bpm: Int
    public let reason: String
}

/// Propone una sesión corta: primero ejercicios nuevos, después los menos dominados.
public enum WarmupPlanner {
    public static func recommend(exercises: [Exercise], progress: [String: ExerciseProgress], count: Int = 3) -> [WarmupRecommendation] {
        exercises.sorted { left, right in
            let leftProgress = progress[left.id]
            let rightProgress = progress[right.id]
            let leftScore = leftProgress?.latestScore ?? -1
            let rightScore = rightProgress?.latestScore ?? -1
            if leftScore == rightScore { return left.level < right.level }
            return leftScore < rightScore
        }.prefix(max(1, count)).map { exercise in
            let item = progress[exercise.id]
            let reason: String
            if item == nil { reason = "Aún no lo has practicado" }
            else if (item?.latestScore ?? 0) < 70 { reason = "Conviene consolidarlo" }
            else { reason = "Repaso para mantener el pulso" }
            return WarmupRecommendation(exerciseID: exercise.id, title: exercise.title, bpm: exercise.bpm, reason: reason)
        }
    }
}

public enum CourseLevelStatus: Equatable {
    case locked
    case available
    case mastered
}

public struct CourseLevelState: Equatable {
    public let exerciseID: String
    public let status: CourseLevelStatus
    public let bestScore: Double?
}

/// Mantiene una escalera sencilla para principiantes: superar un nivel al 70 %
/// abre el siguiente; un resultado peor nunca vuelve a bloquear lo conseguido.
public enum CourseProgress {
    public static func states(exercises: [Exercise], progress: [String: ExerciseProgress], masteryScore: Double = 70) -> [CourseLevelState] {
        var previousMastered = true
        return exercises.sorted { $0.level < $1.level }.map { exercise in
            let item = progress[exercise.id]
            let mastered = (item?.bestScore ?? 0) >= masteryScore
            let status: CourseLevelStatus = mastered ? .mastered : (previousMastered ? .available : .locked)
            previousMastered = previousMastered && mastered
            return CourseLevelState(exerciseID: exercise.id, status: status, bestScore: item?.bestScore)
        }
    }

    /// La progresión solo usa resultados que representan el ritmo completo. Los
    /// intentos históricos conservan el desbloqueo anterior, pero no sirven para
    /// sellos avanzados porque su alcance no se puede verificar.
    public static func states(exercises: [Exercise], attempts: [PracticeAttempt], completionScore: Double = 70, fastStartID: String? = "00_i_03_ritmo_completo") -> [CourseLevelState] {
        if let graph = try? CourseGraph(exercises: exercises) {
            return graph.states(attempts: attempts, completionScore: completionScore)
        }
        let completeAttempts = attempts.filter { attempt in
            guard let exercise = exercises.first(where: { $0.id == attempt.exerciseID }) else { return false }
            return TempoLadder.isConsolidated(exercise, attempts: [attempt], minimumScore: completionScore)
        }
        let bestScores = Dictionary(grouping: completeAttempts, by: \.exerciseID).mapValues { attempts in
            attempts.map(\.score).max() ?? 0
        }
        let ordered = exercises.sorted { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
        var previousSatisfied = true

        return ordered.map { exercise in
            let bestScore = bestScores[exercise.id]
            let completed = bestScore != nil
            let status: CourseLevelStatus = completed ? .mastered : (previousSatisfied || exercise.id == fastStartID ? .available : .locked)
            previousSatisfied = previousSatisfied && completed
            return CourseLevelState(exerciseID: exercise.id, status: status, bestScore: bestScore)
        }
    }
}

public enum NextSessionKind: Equatable {
    case firstSession
    case corrective
    case consolidate
    case continueCourse
    case review
}

public struct NextSessionPlan: Equatable {
    public let exerciseID: String
    public let title: String
    public let bpm: Int
    public let repeats: Int
    public let estimatedDurationMilliseconds: Double
    public let kind: NextSessionKind
    public let reason: String
}

public struct CourseRecommendation: Equatable {
    public let exerciseID: String
    public let courseLevel: Int
    public let tempoStep: TempoPracticeStep
    public let isCourseCompletion: Bool

    public init(exerciseID: String, courseLevel: Int, tempoStep: TempoPracticeStep, isCourseCompletion: Bool) {
        self.exerciseID = exerciseID
        self.courseLevel = courseLevel
        self.tempoStep = tempoStep
        self.isCourseCompletion = isCourseCompletion
    }
}

/// Determina una única tarea actual sin ocultar los ritmos ya desbloqueados.
public enum CourseRecommendationPlanner {
    public static func recommend(exercises: [Exercise], courseLevels: [CourseLevelState], attempts: [PracticeAttempt]) -> CourseRecommendation? {
        let states = Dictionary(uniqueKeysWithValues: courseLevels.map { ($0.exerciseID, $0.status) })
        let ordered = exercises.sorted { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
        if let current = ordered.first(where: { states[$0.id] == .available }),
           let step = TempoLadder.nextStep(for: current, attempts: attempts) {
            return .init(exerciseID: current.id, courseLevel: current.level, tempoStep: step, isCourseCompletion: step.label == "Consolidar")
        }
        if let review = ordered.first(where: { states[$0.id] == .mastered && TempoLadder.nextStep(for: $0, attempts: attempts) != nil }),
           let step = TempoLadder.nextStep(for: review, attempts: attempts) {
            return .init(exerciseID: review.id, courseLevel: review.level, tempoStep: step, isCourseCompletion: false)
        }
        return nil
    }
}

/// Prioriza una única microtarea a partir de datos persistidos. La interfaz
/// solo presenta el plan y confirma su configuración antes de iniciar audio.
public enum NextSessionPlanner {
    public static func plan(exercises: [Exercise], courseLevels: [CourseLevelState], attempts: [PracticeAttempt], eligibleExerciseIDs: Set<String>? = nil) -> NextSessionPlan? {
        let availableIDs = Set(courseLevels.filter { $0.status != .locked }.map(\.exerciseID))
        let candidates = exercises
            .filter { exercise in
                (eligibleExerciseIDs?.contains(exercise.id) ?? true) && (availableIDs.isEmpty || availableIDs.contains(exercise.id))
            }
            .sorted { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
        guard !candidates.isEmpty else { return nil }

        let attemptsByExercise = Dictionary(grouping: attempts, by: \.exerciseID)
        if attempts.isEmpty {
            return makePlan(for: candidates[0], kind: .firstSession, reason: "Empieza por el primer groove: construye una base estable antes de añadir variaciones.")
        }

        if let recent = attempts.first,
           let current = candidates.first(where: { $0.id == recent.exerciseID }),
           recent.score < 70 {
            if let weak = recent.soundStatistics.min(by: { $0.accuracy < $1.accuracy }), weak.accuracy < 70 {
                return makePlan(for: current, kind: .corrective, reason: "Refuerza \(weak.sound): fue la voz con más margen en el último intento.")
            }
            return makePlan(for: current, kind: .consolidate, reason: "Repite este nivel: el último intento aún necesita consolidación antes de avanzar.")
        }

        if let next = candidates.first(where: { (attemptsByExercise[$0.id]?.map(\.score).max() ?? 0) < 70 }) {
            return makePlan(for: next, kind: .continueCourse, reason: "Es el siguiente escalón disponible del curso.")
        }

        let review = candidates.min { left, right in
            let leftScore = attemptsByExercise[left.id]?.last?.score ?? 100
            let rightScore = attemptsByExercise[right.id]?.last?.score ?? 100
            return leftScore == rightScore ? left.level < right.level : leftScore < rightScore
        } ?? candidates[0]
        return makePlan(for: review, kind: .review, reason: "El curso está consolidado; repasa el ritmo con más margen de mejora.")
    }

    private static func makePlan(for exercise: Exercise, kind: NextSessionKind, reason: String) -> NextSessionPlan {
        let repeats = PracticeConfiguration.normalizedRepeats(exercise.repeats)
        let configured = PracticeConfiguration(exercise: exercise, repeats: repeats).applying(to: exercise)
        return NextSessionPlan(
            exerciseID: exercise.id,
            title: exercise.title,
            bpm: configured.bpm,
            repeats: repeats,
            estimatedDurationMilliseconds: ExerciseTimeline(exercise: configured).patternDurationMilliseconds * Double(repeats),
            kind: kind,
            reason: reason
        )
    }
}

public struct PracticePreferences: Codable, Equatable {
    public var exerciseID: String?
    public var bpm: Int?
    public var repeats: Int?

    public init(exerciseID: String? = nil, bpm: Int? = nil, repeats: Int? = nil) {
        self.exerciseID = exerciseID; self.bpm = bpm; self.repeats = repeats
    }
}

public enum PracticePreferencesStore {
    public static func load(from url: URL) throws -> PracticePreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        return try JSONDecoder().decode(PracticePreferences.self, from: Data(contentsOf: url))
    }

    public static func save(_ preferences: PracticePreferences, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preferences).write(to: url, options: .atomic)
    }
}

public struct SoundStatistics: Codable, Equatable {
    public let sound: String
    public let expected: Int
    public let perfect: Int
    public let good: Int
    public let regular: Int
    public let missed: Int
    public var accuracy: Double { expected == 0 ? 0 : Double(perfect + good + regular) / Double(expected) * 100 }
}

public struct PracticeInsights: Equatable {
    public let timingLabel: String
    public let soundStatistics: [SoundStatistics]
    public let medianOffsetMilliseconds: Double?
    public let medianAbsoluteDeviationMilliseconds: Double?
    public let percentile95AbsoluteMilliseconds: Double?

    public init(score: ExerciseScore) {
        let offsets = score.hits.compactMap(\.offsetMilliseconds).sorted()
        let sounds = Set(score.hits.compactMap { $0.expectedNote?.sound }).union(score.misses.map(\.sound))
        soundStatistics = sounds.sorted().map { sound in
            let judged = score.hits.filter { $0.expectedNote?.sound == sound }
            return SoundStatistics(sound: sound, expected: judged.count + score.misses.filter { $0.sound == sound }.count,
                                   perfect: judged.filter { $0.judgement == .perfect }.count,
                                   good: judged.filter { $0.judgement == .good }.count,
                                   regular: judged.filter { $0.judgement == .regular }.count,
                                   missed: score.misses.filter { $0.sound == sound }.count)
        }
        guard !offsets.isEmpty else {
            timingLabel = "Aún no hay golpes asociados"
            medianOffsetMilliseconds = nil; medianAbsoluteDeviationMilliseconds = nil; percentile95AbsoluteMilliseconds = nil
            return
        }
        let median = CalibrationEstimator.median(offsets)
        timingLabel = median < -15 ? "Tiendes a adelantar el golpe" : median > 15 ? "Tiendes a retrasar el golpe" : "Tu pulso está centrado"
        medianOffsetMilliseconds = median
        let deviations = offsets.map { abs($0 - median) }
        medianAbsoluteDeviationMilliseconds = CalibrationEstimator.median(deviations)
        let absolute = offsets.map(abs).sorted()
        percentile95AbsoluteMilliseconds = absolute[min(absolute.count - 1, Int((Double(absolute.count - 1) * 0.95).rounded(.up)))]
    }
}

public enum PracticeResultDiagnosis: Equatable {
    case insufficientEvidence
    case weakSound(sound: String, accuracy: Double, missed: Int)
    case inconsistent(spreadMilliseconds: Double)
    case timingBias(offsetMilliseconds: Double)
    case solid
}

public enum PracticeResultAction: Equatable {
    case corrective
    case repeatWithAdjustment
    case advance
    case repeatSame
}

public struct PracticeResultSummary: Equatable {
    public let diagnosis: PracticeResultDiagnosis
    public let action: PracticeResultAction
    public let precision: Double
    public let medianOffsetMilliseconds: Double?
    public let consistencyMilliseconds: Double?
    public let percentile95AbsoluteMilliseconds: Double?
}

public enum PracticeResultAnalyzer {
    public static func summarize(score: ExerciseScore, insights: PracticeInsights, hasCorrectivePlan: Bool, canAdvance: Bool) -> PracticeResultSummary {
        let diagnosis: PracticeResultDiagnosis
        if let weakest = insights.soundStatistics.min(by: { $0.accuracy < $1.accuracy }), weakest.accuracy < 70 {
            diagnosis = .weakSound(sound: weakest.sound, accuracy: weakest.accuracy, missed: weakest.missed)
        } else if insights.medianOffsetMilliseconds == nil {
            diagnosis = .insufficientEvidence
        } else if let spread = insights.medianAbsoluteDeviationMilliseconds, spread > 45 {
            diagnosis = .inconsistent(spreadMilliseconds: spread)
        } else if let median = insights.medianOffsetMilliseconds, abs(median) > 15 {
            diagnosis = .timingBias(offsetMilliseconds: median)
        } else {
            diagnosis = .solid
        }

        let action: PracticeResultAction
        if hasCorrectivePlan, case .weakSound = diagnosis { action = .corrective }
        else if case .inconsistent = diagnosis { action = .repeatWithAdjustment }
        else if score.percentage >= 70, canAdvance { action = .advance }
        else if score.percentage < 70 { action = .repeatWithAdjustment }
        else { action = .repeatSame }

        return PracticeResultSummary(
            diagnosis: diagnosis,
            action: action,
            precision: score.percentage,
            medianOffsetMilliseconds: insights.medianOffsetMilliseconds,
            consistencyMilliseconds: insights.medianAbsoluteDeviationMilliseconds,
            percentile95AbsoluteMilliseconds: insights.percentile95AbsoluteMilliseconds
        )
    }
}

public enum PracticeHelp: String, CaseIterable, Codable {
    case full, normal, reduced
    public var label: String { switch self { case .full: return "Completa"; case .normal: return "Normal"; case .reduced: return "Reducida" } }
}

/// Primera capa del Ghost Coach: convierte el último patrón en una instrucción
/// concreta y reproducible antes de mostrar una visualización temporal completa.
public enum GhostCoach {
    public static func cue(score: ExerciseScore, insights: PracticeInsights) -> String {
        guard let weak = insights.soundStatistics.min(by: { $0.accuracy < $1.accuracy }) else { return "Completa una vuelta para que Ghost Coach pueda comparar tu interpretación." }
        let direction = (score.meanOffsetMilliseconds ?? 0) < -12 ? "retrasando ligeramente" : (score.meanOffsetMilliseconds ?? 0) > 12 ? "anticipando ligeramente" : "manteniendo el pulso"
        return "Ghost Coach: reproduce el patrón y repite " + weak.sound + " " + direction + "; es la voz con más margen de mejora."
    }
}

public struct AutopilotRecommendation: Equatable {
    public let message: String
    public let bpmAdjustment: Int
    public let repeats: Int
    public let help: PracticeHelp
}

public enum PracticeAutopilot {
    public static func recommend(score: ExerciseScore, insights: PracticeInsights, bpm: Int, repeats: Int) -> AutopilotRecommendation {
        if let spread = insights.medianAbsoluteDeviationMilliseconds, spread > 45 { return .init(message: "Hay variación entre golpes: baja el tempo y toca una vuelta corta.", bpmAdjustment: -6, repeats: 2, help: .full) }
        if let weakest = insights.soundStatistics.min(by: { $0.accuracy < $1.accuracy }), weakest.accuracy < 70 { return .init(message: "Aísla \(weakest.sound) antes de integrar el patrón.", bpmAdjustment: 0, repeats: 2, help: .normal) }
        if score.percentage >= 85 { return .init(message: "Vas sólido: sube un poco el tempo o reduce ayudas.", bpmAdjustment: 4, repeats: repeats, help: .reduced) }
        return .init(message: "Repite el patrón con la misma configuración y centra cada golpe.", bpmAdjustment: 0, repeats: repeats, help: .normal)
    }
}

public enum RecoveryAdvice: Equatable {
    case missingSamples([String])
    case noMIDIInput
    case invalidPadMap
    case audioUnavailable
    case ready

    public var message: String {
        switch self {
        case .missingSamples(let files): return "Faltan sonidos: \(files.joined(separator: ", ")). Copialos a Resources/Kits/hiphop_basic."
        case .noMIDIInput: return "No hay controlador MIDI conectado. Puedes practicar con el teclado o conectar el M-Vave."
        case .invalidPadMap: return "El mapa de pads no es válido. Ábrelo en Mapear pads y vuelve a asignarlo."
        case .audioUnavailable: return "No se pudo abrir el audio. Comprueba la salida de sonido y reinicia xRoll."
        case .ready: return "Todo está listo para practicar."
        }
    }
}

public enum RecoveryAdvisor {
    public static func assess(missingSamples: [String], hasMIDIInput: Bool, hasInvalidPadMap: Bool = false, hasAudio: Bool = true) -> RecoveryAdvice {
        if !missingSamples.isEmpty { return .missingSamples(missingSamples) }
        if !hasAudio { return .audioUnavailable }
        if hasInvalidPadMap { return .invalidPadMap }
        if !hasMIDIInput { return .noMIDIInput }
        return .ready
    }
}
