import Foundation

/// Transporte de una vuelta acompañada opcional, separado del origen del score.
/// Las dos cuentas de entrada y la referencia no añaden compases acreditables.
public struct PracticeRehearsalPlan: Equatable {
    public let countInMilliseconds: Double
    public let referenceExercise: Exercise?
    public let referenceStartMilliseconds: Double
    public let referenceEndMilliseconds: Double
    public let scoringStartMilliseconds: Double

    public init(exercise: Exercise, reference: Exercise? = nil, countInBars: Int = 2, enabled: Bool) {
        let timeline = ExerciseTimeline(exercise: exercise)
        countInMilliseconds = timeline.barDurationMilliseconds * Double(min(4, max(1, countInBars)))
        referenceStartMilliseconds = countInMilliseconds
        if enabled {
            let source = reference ?? exercise
            let oneRound = PracticeConfiguration(exercise: source, bpm: exercise.bpm, repeats: 1).applying(to: source)
            referenceExercise = oneRound
            referenceEndMilliseconds = countInMilliseconds + ExerciseTimeline(exercise: oneRound).patternDurationMilliseconds
            scoringStartMilliseconds = referenceEndMilliseconds + countInMilliseconds
        } else {
            referenceExercise = nil
            referenceEndMilliseconds = countInMilliseconds
            scoringStartMilliseconds = countInMilliseconds
        }
    }
}

/// Ajustes de una sesión que no alteran el archivo original del ejercicio.
public struct PracticeConfiguration: Equatable {
    public var bpm: Int
    public var repeats: Int

    public init(exercise: Exercise, bpm: Int? = nil, repeats: Int? = nil) {
        self.bpm = min(240, max(40, bpm ?? exercise.bpm))
        self.repeats = Self.normalizedRepeats(repeats ?? exercise.repeats)
    }

    /// El inicio guiado prepara aprendizaje, no retos opcionales de velocidad.
    public static func guided(for exercise: Exercise) -> PracticeConfiguration {
        .init(exercise: exercise, bpm: CourseLessonCriteria.targetBPM(for: exercise),
              repeats: defaultRepeats(forBars: exercise.bars))
    }

    /// Longitudes en potencias de dos para elegir sesiones cortas o largas.
    public static func normalizedRepeats(_ value: Int) -> Int {
        let options = [1, 2, 4, 8, 16]
        return options.first(where: { $0 >= value }) ?? 16
    }

    /// Unos ocho compases de práctica, no ocho vueltas de una frase completa.
    /// Una forma larga se toca entera una vez; nunca se recorta su transición.
    public static func defaultRepeats(forBars bars: Int) -> Int {
        [1, 2, 4, 8].last(where: { $0 <= 8 / max(1, bars) }) ?? 1
    }

    public func applying(to exercise: Exercise) -> Exercise {
        Exercise(format: exercise.format, id: exercise.id, title: exercise.title, family: exercise.family,
                  level: exercise.level, bpm: bpm, meter: exercise.meter, bars: exercise.bars,
                  grid: exercise.grid, repeats: repeats, kit: exercise.kit, loop: exercise.loop,
                  offset: exercise.offset, notes: exercise.notes, metadata: exercise.metadata)
    }

    /// La calibración aísla el motor regular del MIDI, aunque su lección de
    /// origen enseñe un groove completo. Nunca modifica el archivo curricular.
    public static func calibrationExercise(from exercise: Exercise) -> Exercise {
        Exercise(format: exercise.format, id: exercise.id, title: exercise.title, family: exercise.family,
            level: exercise.level, bpm: exercise.bpm, meter: exercise.meter, bars: exercise.bars,
            grid: exercise.grid, repeats: 8, kit: exercise.kit, loop: nil, offset: exercise.offset,
            notes: exercise.notes.filter { $0.sound == "hihat_closed" }, metadata: exercise.metadata)
    }

    /// Conserva el compás de la célula y su acompañamiento; incluye dos si la
    /// célula cruza la barra. Solo se usa con alcance correctivo, nunca para
    /// acreditar una versión abreviada del patrón completo.
    public static func correctiveContext(in exercise: Exercise, stepRange: ClosedRange<Int>) -> (exercise: Exercise, stepRange: ClosedRange<Int>) {
        let totalSteps = exercise.bars * exercise.grid
        let lower = min(totalSteps - 1, max(0, stepRange.lowerBound))
        let upper = min(totalSteps - 1, max(lower, stepRange.upperBound))
        let firstBar = lower / exercise.grid
        let lastBar = upper / exercise.grid
        let origin = firstBar * exercise.grid
        let end = (lastBar + 1) * exercise.grid
        let notes = exercise.notes.compactMap { note -> Exercise.Note? in
            let step = (note.step + exercise.offset) % totalSteps
            guard step >= origin, step < end else { return nil }
            return .init(step: step - origin, sound: note.sound, hand: note.hand, target: note.target, velocity: note.velocity)
        }
        let context = Exercise(format: exercise.format, id: exercise.id, title: exercise.title, family: exercise.family,
            level: exercise.level, bpm: exercise.bpm, meter: exercise.meter, bars: lastBar - firstBar + 1,
            grid: exercise.grid, repeats: exercise.repeats, kit: exercise.kit, loop: exercise.loop,
            offset: 0, notes: notes, metadata: exercise.metadata)
        return (context, (lower - origin)...(upper - origin))
    }

    /// 0 = frase completa; 1/2 = primera/segunda mitad de todos sus compases.
    /// Una célula correctiva limita adicionalmente los pasos seleccionados.
    public static func notes(in exercise: Exercise, fragment: Int, stepRange: ClosedRange<Int>? = nil) -> [Exercise.Note] {
        let midpoint = exercise.bars * exercise.grid / 2
        return exercise.notes.filter { note in
            guard stepRange?.contains(note.step) ?? true else { return false }
            switch fragment {
            case 1: return note.step < midpoint
            case 2: return note.step >= midpoint
            default: return true
            }
        }
    }
}

/// El cierre se basa en el tiempo recorrido, no en el porcentaje de aciertos ni
/// en la duración configurada. Un abandono no acredita compases sin tocar.
public struct PracticeCompletion: Equatable {
    public let completedBars: Int
    public let totalBars: Int
    public var isComplete: Bool { completedBars == totalBars }

    public init(exercise: Exercise, elapsedMilliseconds: Double) {
        totalBars = exercise.bars * exercise.repeats
        let barDuration = ExerciseTimeline(exercise: exercise).barDurationMilliseconds
        completedBars = Int(max(0, min(Double(totalBars), floor(elapsedMilliseconds / barDuration))))
    }

    public func context(from original: TrainingContext) -> TrainingContext {
        TrainingContext(phase: original.phase, gapMetronomeLevel: original.gapMetronomeLevel,
                        showsVisualGuides: original.showsVisualGuides,
                         evaluationScope: isComplete ? original.evaluationScope : .fragment,
                         completedBars: completedBars, practiceConditions: original.practiceConditions,
                         tempoPolicyVersion: original.tempoPolicyVersion)
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

/// Requisitos de un premio de velocidad o de dominio a tempo musical fijo.
public struct TempoPracticeStep: Equatable {
    public let label: String
    public let bpm: Int
    public let requiredScore: Double
    public let requiredPasses: Int
    public let minimumBars: Int?
    public let award: TempoAward
    public let requiresKnownFullPattern: Bool
    public let isHistorical: Bool

    public init(label: String, bpm: Int, requiredScore: Double, requiredPasses: Int, minimumBars: Int? = nil, award: TempoAward, requiresKnownFullPattern: Bool = false, isHistorical: Bool = false) {
        self.label = label
        self.bpm = bpm
        self.requiredScore = requiredScore
        self.requiredPasses = requiredPasses
        self.minimumBars = minimumBars
        self.award = award
        self.requiresKnownFullPattern = requiresKnownFullPattern
        self.isHistorical = isHistorical
    }

    public var requirements: String {
        "\(Int(requiredScore)) %" + (minimumBars.map { " · \($0) compases" } ?? "")
            + (requiredPasses > 1 ? " · \(requiredPasses) intentos" : "")
    }
}

/// Rangos orientativos de las rutas concretas del curso, no límites universales
/// de cada género. El tempo fijo real se lee siempre del MIDI.
public struct GenreTempoProfile: Equatable {
    public let name: String
    public let suggestedRange: ClosedRange<Int>
    public static func profile(for exercise: Exercise) -> GenreTempoProfile? {
        switch exercise.metadata?.chapter {
        case "hiphop": return .init(name: "Hip-hop / boom bap", suggestedRange: 80...95)
        case "rock": return .init(name: "Rock", suggestedRange: 80...120)
        case "disco": return .init(name: "Disco", suggestedRange: 110...125)
        case "funk": return .init(name: "Funk", suggestedRange: 85...110)
        case "reggae": return .init(name: "Reggae", suggestedRange: 65...85)
        case "dembow": return .init(name: "Dembow", suggestedRange: 85...105)
        case "blues": return .init(name: "Blues / Shuffle", suggestedRange: 70...110)
        case "jazz": return .init(name: "Jazz básico", suggestedRange: 80...110)
        case "jazz-intermediate": return .init(name: "Jazz intermedio", suggestedRange: 100...130)
        case "clave-bossa": return .init(name: "Clave / Bossa", suggestedRange: 85...115)
        default: return nil
        }
    }
}

public enum TempoLadder {
    public static let currentPolicyVersion = 1
    public static func steps(for exercise: Exercise) -> [TempoPracticeStep] {
        if GenreTempoProfile.profile(for: exercise) != nil {
            func step(_ label: String, _ score: Double, _ bars: Int, _ passes: Int, _ award: TempoAward) -> TempoPracticeStep {
                .init(label: label, bpm: exercise.bpm, requiredScore: score, requiredPasses: passes,
                    minimumBars: max(exercise.bars, bars), award: award, requiresKnownFullPattern: true)
            }
            return [step("Base", 70, exercise.bars, 1, .stars(1)),
                    step("Precisión", 80, exercise.bars, 1, .stars(2)),
                    step("Groove", 90, exercise.bars, 1, .stars(3)),
                    step("Sostener", 90, 8, 1, .trophies(1)),
                    step("Resistencia", 90, 16, 1, .trophies(2)),
                    step("Dominio", 95, 16, 2, .trophies(3))]
        }
        return technicalSteps()
    }

    /// Las rutas de género se tocan siempre a su tempo musical; sus premios
    /// escalan en precisión y aguante, no en velocidad.
    public static func isFixedTempoRoute(for exercise: Exercise) -> Bool {
        GenreTempoProfile.profile(for: exercise) != nil
    }

    private static func technicalSteps(historical: Bool = false) -> [TempoPracticeStep] {
        let values: [(String, Int, TempoAward)] = [("Aprender",70,.stars(1)), ("Base",85,.stars(2)),
            ("Consolidar",100,.stars(3)), ("Difícil",120,.trophies(1)), ("Jefe",140,.trophies(2)), ("Nivel dios",160,.trophies(3))]
        return values.map { label, bpm, award in
            .init(label: historical ? "Histórico · \(label)" : label, bpm: bpm, requiredScore: 70,
                  requiredPasses: 1, minimumBars: bpm == 160 ? 16 : nil, award: award, isHistorical: historical)
        }
    }

    public static func passedAttempts(for step: TempoPracticeStep, exerciseID: String, attempts: [PracticeAttempt]) -> Int {
        passedAttempts(for: step, exerciseID: exerciseID, evidence: attempts.map(CourseAttemptEvidence.init))
    }

    private static func qualifies(_ evidence: CourseAttemptEvidence, for step: TempoPracticeStep, exerciseID: String) -> Bool {
        evidence.exerciseID == exerciseID
            && evidence.bpm == step.bpm
            && evidence.score >= step.requiredScore
            && (step.requiresKnownFullPattern ? evidence.trainingContext.evaluationScope == .fullPattern : evidence.trainingContext.evaluationScope.countsAsCompletePattern)
            && (!step.isHistorical || evidence.trainingContext.tempoPolicyVersion == nil)
            && (step.minimumBars == nil || evidence.trainingContext.completedBars >= step.minimumBars!)
    }

    public static func passedAttempts(for step: TempoPracticeStep, exerciseID: String, evidence: [CourseAttemptEvidence]) -> Int {
        evidence.filter { qualifies($0, for: step, exerciseID: exerciseID) }.count
    }

    /// Estrellas visibles de un escalón: solo cuentan intentos que alcanzan su
    /// precisión, aunque varios escalones compartan el mismo tempo musical.
    public static func bestStars(for step: TempoPracticeStep, exerciseID: String, evidence: [CourseAttemptEvidence]) -> Int? {
        evidence.filter { qualifies($0, for: step, exerciseID: exerciseID) }.map(\.stars).max()
    }

    /// Escalón que corresponde a un tempo y una duración dados. Sirve para
    /// restaurar preferencias cuando varios escalones comparten BPM.
    public static func stepIndex(for exercise: Exercise, bpm: Int, repeats: Int) -> Int? {
        let steps = steps(for: exercise)
        let candidates = steps.indices.filter { steps[$0].bpm == bpm }
        guard !candidates.isEmpty else { return nil }
        return candidates.first(where: { Self.repeats(for: steps[$0], exercise: exercise) == repeats })
            ?? candidates.first(where: { (Self.repeats(for: steps[$0], exercise: exercise) ?? 1) <= repeats })
            ?? candidates[0]
    }

    public static func isPassed(_ step: TempoPracticeStep, exerciseID: String, attempts: [PracticeAttempt]) -> Bool {
        passedAttempts(for: step, exerciseID: exerciseID, attempts: attempts) >= step.requiredPasses
    }

    public static func isPassed(_ step: TempoPracticeStep, exerciseID: String, evidence: [CourseAttemptEvidence]) -> Bool {
        passedAttempts(for: step, exerciseID: exerciseID, evidence: evidence) >= step.requiredPasses
    }

    public static func nextStep(for exercise: Exercise, attempts: [PracticeAttempt]) -> TempoPracticeStep? {
        nextStep(for: exercise, evidence: attempts.map(CourseAttemptEvidence.init))
    }

    public static func nextStep(for exercise: Exercise, evidence: [CourseAttemptEvidence]) -> TempoPracticeStep? {
        steps(for: exercise).first { !isPassed($0, exerciseID: exercise.id, evidence: evidence) }
    }

    public static func highestPassedStep(for exercise: Exercise, attempts: [PracticeAttempt]) -> TempoPracticeStep? {
        highestPassedStep(for: exercise, evidence: attempts.map(CourseAttemptEvidence.init))
    }

    public static func highestPassedStep(for exercise: Exercise, evidence: [CourseAttemptEvidence]) -> TempoPracticeStep? {
        let current = steps(for: exercise).reversed().first { isPassed($0, exerciseID: exercise.id, evidence: evidence) }
        guard GenreTempoProfile.profile(for: exercise) != nil else { return current }
        let historical = technicalSteps(historical: true).reversed().first { isPassed($0, exerciseID: exercise.id, evidence: evidence) }
        func rank(_ step: TempoPracticeStep) -> Int {
            switch step.award { case .stars(let count): return count; case .trophies(let count): return count + 3 }
        }
        if let historical, current.map({ rank(historical) > rank($0) }) ?? true { return historical }
        return current
    }

    public static func isConsolidated(_ exercise: Exercise, attempts: [PracticeAttempt], minimumScore: Double = 70) -> Bool {
        isConsolidated(exercise, evidence: attempts.map(CourseAttemptEvidence.init), minimumScore: minimumScore)
    }

    public static func isConsolidated(_ exercise: Exercise, evidence: [CourseAttemptEvidence], minimumScore: Double = 70) -> Bool {
        CourseLessonCriteria.isPassed(exercise, evidence: evidence, minimumScore: max(minimumScore, CourseLessonCriteria.minimumScore))
    }

    /// A checkpoint concede equivalencias nuevas únicamente con evidencia
    /// explícita de ritmo completo; el alcance histórico desconocido puede
    /// mantener progreso previo, pero no crear créditos por checkpoint.
    public static func isCheckpointPassed(_ exercise: Exercise, evidence: [CourseAttemptEvidence], minimumScore: Double = 70) -> Bool {
        return evidence.contains {
            $0.exerciseID == exercise.id
                && CourseLessonCriteria.lessonEvidenceIsEligible($0, for: exercise)
                && $0.score >= max(minimumScore, CourseLessonCriteria.minimumScore)
                && $0.trainingContext.evaluationScope == .fullPattern
        }
    }

    public static func repeats(for step: TempoPracticeStep, exercise: Exercise) -> Int? {
        guard let minimumBars = step.minimumBars else { return nil }
        return PracticeConfiguration.normalizedRepeats(Int(ceil(Double(minimumBars) / Double(exercise.bars))))
    }
}

/// Criterio de aprendizaje básico, independiente de los retos opcionales de
/// dominio: ritmo completo al tempo musical de género o al de aprendizaje técnico.
public enum CourseLessonCriteria {
    public static let minimumScore = 70.0
    /// Las rutas de género usan el tempo del MIDI; el tronco técnico mantiene
    /// su objetivo de aprendizaje limitado a 100 BPM.
    public static func targetBPM(for exercise: Exercise) -> Int {
        GenreTempoProfile.profile(for: exercise) == nil ? min(exercise.bpm, 100) : exercise.bpm
    }

    /// Siguiente premio de precisión/aguante en géneros o de velocidad en el
    /// tronco técnico. Conserva el reto cuando falta acreditar su duración.
    public static func optionalTempoStep(for exercise: Exercise, evidence: [CourseAttemptEvidence]) -> TempoPracticeStep? {
        if GenreTempoProfile.profile(for: exercise) != nil { return TempoLadder.nextStep(for: exercise, evidence: evidence) }
        let target = targetBPM(for: exercise)
        let highestPassedBPM = evidence
            .filter {
                $0.exerciseID == exercise.id && $0.score >= minimumScore
                    && lessonEvidenceIsEligible($0, for: exercise)
            }
            .map(\.bpm).max() ?? target
        let base = max(target, highestPassedBPM)
        return TempoLadder.steps(for: exercise).first {
            ($0.bpm > base || ($0.bpm == base && $0.minimumBars != nil))
                && !TempoLadder.isPassed($0, exerciseID: exercise.id, evidence: evidence)
        }
    }

    /// Una lección pendiente se prepara al tempo que permite aprender y avanzar.
    /// Solo un ritmo ya superado propone retos opcionales de velocidad.
    public static func preparationStep(for exercise: Exercise, evidence: [CourseAttemptEvidence]) -> TempoPracticeStep {
        let target = targetBPM(for: exercise)
        guard isPassed(exercise, evidence: evidence) else {
            return .init(label: "Aprender el ritmo", bpm: target, requiredScore: minimumScore,
                requiredPasses: 1, award: .stars(1))
        }
        return optionalTempoStep(for: exercise, evidence: evidence)
            ?? TempoLadder.steps(for: exercise).last
            ?? .init(label: "Aprender el ritmo", bpm: target, requiredScore: minimumScore,
                requiredPasses: 1, award: .stars(1))
    }

    /// Apoyo automático para un ritmo completo pendiente. Los intentos lentos
    /// vuelven al objetivo en pasos pequeños y nunca acreditan un tempo no tocado.
    public static func recovery(for exercise: Exercise, attempt: CourseAttemptEvidence,
                                evidence: [CourseAttemptEvidence]) -> CourseLearningRecovery? {
        let target = targetBPM(for: exercise)
        guard attempt.exerciseID == exercise.id, attempt.trainingContext.evaluationScope == .fullPattern,
              attempt.trainingContext.phase == .integrate, attempt.bpm <= target,
              !isPassed(exercise, evidence: evidence),
              attempt.score < minimumScore || attempt.bpm < target else { return nil }
        let passed = attempt.score >= minimumScore
        let bpm = passed ? min(target, attempt.bpm + (attempt.score >= 85 ? 4 : 2)) : max(40, attempt.bpm - 4)
        let repeats = [1,2,4].last(where: { $0 * exercise.bars <= 4 }) ?? 1
        return CourseLearningRecovery(bpm: bpm, targetBPM: target, repeats: repeats, successful: passed)
    }

    public static func isPassed(_ exercise: Exercise, evidence: [CourseAttemptEvidence], minimumScore: Double = CourseLessonCriteria.minimumScore) -> Bool {
        evidence.contains {
            $0.exerciseID == exercise.id
                && $0.score >= minimumScore
                && lessonEvidenceIsEligible($0, for: exercise)
        }
    }

    fileprivate static func lessonEvidenceIsEligible(_ evidence: CourseAttemptEvidence, for exercise: Exercise) -> Bool {
        switch evidence.trainingContext.evaluationScope {
        case .fullPattern:
            if GenreTempoProfile.profile(for: exercise) != nil {
                if evidence.trainingContext.tempoPolicyVersion == nil {
                    return evidence.bpm >= (exercise.metadata?.previousLearningBPM ?? min(exercise.bpm, 100))
                }
                return evidence.bpm == exercise.bpm
            }
            return evidence.bpm >= targetBPM(for: exercise)
        case .legacyUnknown:
            // Historial anterior al contexto de sesión solo se conserva con el
            // criterio antiguo; no acreditamos retroactivamente prácticas lentas.
            return evidence.bpm >= 100
        case .selectedVoices, .fragment, .corrective:
            return false
        }
    }
}

public struct CourseLearningRecovery: Equatable {
    public let bpm: Int
    public let targetBPM: Int
    public let repeats: Int
    public let successful: Bool
    public var title: String { successful ? "¡Buen ritmo!" : "Vamos paso a paso" }
    public var actionTitle: String { successful ? "Continuar" : "Reintentar" }
    public var message: String {
        successful
            ? "Seguimos con el mismo ritmo a \(bpm) BPM. Nos acercamos al objetivo de \(targetBPM) BPM sin saltos grandes."
            : "Repetimos el mismo ritmo a \(bpm) BPM con guía completa. El objetivo sigue siendo \(targetBPM) BPM."
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

public enum DailyPracticeBlockKind: String, Codable, Equatable {
    case warmup
    case review
    case challenge
    case integrate
}

public struct DailyPracticeBlock: Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: DailyPracticeBlockKind
    public let exerciseID: String
    public let title: String
    public let reason: String
    public let bpm: Int
    public let repeats: Int
    public let phase: TrainingPhase
    public let gapMetronomeLevel: Int
    public let metronomeEnabled: Bool
    public let loopEnabled: Bool
    public let loopIdentifier: String?
    public let focusedSound: String?
    public let estimatedSeconds: Int
    public var isCompleted: Bool
    public var isSkipped: Bool

    public init(id: UUID = UUID(), kind: DailyPracticeBlockKind, exerciseID: String, title: String, reason: String, bpm: Int, repeats: Int, phase: TrainingPhase, gapMetronomeLevel: Int = 0, metronomeEnabled: Bool = true, loopEnabled: Bool = false, loopIdentifier: String? = nil, focusedSound: String? = nil, estimatedSeconds: Int, isCompleted: Bool = false, isSkipped: Bool = false) {
        self.id = id; self.kind = kind; self.exerciseID = exerciseID; self.title = title; self.reason = reason
        self.bpm = min(240, max(40, bpm)); self.repeats = PracticeConfiguration.normalizedRepeats(repeats)
        self.phase = phase; self.gapMetronomeLevel = min(3, max(0, gapMetronomeLevel))
        self.metronomeEnabled = metronomeEnabled; self.loopEnabled = loopEnabled; self.loopIdentifier = loopIdentifier
        self.focusedSound = focusedSound; self.estimatedSeconds = max(1, estimatedSeconds)
        self.isCompleted = isCompleted; self.isSkipped = isSkipped
    }
}

public struct DailyPracticePlan: Codable, Equatable, Identifiable {
    public let id: UUID
    public let day: Date
    public let targetSeconds: Int
    public var blocks: [DailyPracticeBlock]
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(id: UUID = UUID(), day: Date, targetSeconds: Int = 300, blocks: [DailyPracticeBlock], startedAt: Date? = nil, finishedAt: Date? = nil) {
        self.id = id; self.day = Calendar.current.startOfDay(for: day); self.targetSeconds = max(60, targetSeconds)
        self.blocks = blocks; self.startedAt = startedAt; self.finishedAt = finishedAt
    }

    public var estimatedSeconds: Int { blocks.reduce(0) { $0 + $1.estimatedSeconds } }
    public var completedBlockCount: Int { blocks.filter(\.isCompleted).count }
    public var skippedBlockCount: Int { blocks.filter(\.isSkipped).count }
    public var currentBlock: DailyPracticeBlock? { blocks.first(where: { !$0.isCompleted && !$0.isSkipped }) }
    public var isComplete: Bool { !blocks.isEmpty && currentBlock == nil }

    public mutating func markStarted(at date: Date = Date()) {
        if startedAt == nil { startedAt = date }
    }

    @discardableResult
    public mutating func completeBlock(_ id: UUID, skipped: Bool = false, at date: Date = Date()) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }), !blocks[index].isCompleted, !blocks[index].isSkipped else { return false }
        blocks[index].isCompleted = !skipped
        blocks[index].isSkipped = skipped
        markStarted(at: date)
        if isComplete { finishedAt = date }
        return true
    }
}

public enum DailyPracticePlanner {
    public static func makePlan(exercises: [Exercise], attempts: [PracticeAttempt], dueGoals: [CoachingGoal] = [], preferredChallengeExerciseID: String? = nil, targetSeconds: Int = 300, now: Date = Date()) -> DailyPracticePlan? {
        guard !exercises.isEmpty else { return nil }
        let eligibleAttempts = attempts.filter { $0.trainingContext.evaluationScope == .fullPattern }
        let latestByExercise = Dictionary(grouping: eligibleAttempts, by: \.exerciseID).mapValues { $0.max(by: { $0.timestamp < $1.timestamp })! }
        let knownExercises = exercises.filter { latestByExercise[$0.id]?.score ?? 0 >= CourseLessonCriteria.minimumScore }
        let warmup = knownExercises.max { lhs, rhs in
            let left = latestByExercise[lhs.id]?.score ?? 0
            let right = latestByExercise[rhs.id]?.score ?? 0
            return left == right ? lhs.level > rhs.level : left < right
        } ?? exercises.min(by: { $0.level < $1.level })!
        let dueGoal = dueGoals.filter { $0.state != .confirmed && $0.nextReviewAt <= now }
            .sorted { $0.nextReviewAt < $1.nextReviewAt }.first
        let reviewExercise = dueGoal.flatMap { goal in exercises.first(where: { $0.id == goal.exerciseID }) }
        let practicedIDs = Set(eligibleAttempts.map(\.exerciseID))
        let challenge = preferredChallengeExerciseID.flatMap { id in exercises.first(where: { $0.id == id && $0.id != warmup.id }) }
            ?? exercises.filter { $0.id != warmup.id && !practicedIDs.contains($0.id) && $0.level <= warmup.level + 1 }
                .min(by: { $0.level < $1.level })
            ?? exercises.first(where: { $0.id != warmup.id && $0.level <= warmup.level + 1 })
        let integration = knownExercises.first(where: { $0.id == warmup.id }) ?? warmup

        var blocks = [DailyPracticeBlock]()
        func block(_ kind: DailyPracticeBlockKind, _ exercise: Exercise, _ reason: String, phase: TrainingPhase = .integrate, focusedSound: String? = nil, gap: Int = 0, conditions: PracticeConditions? = nil) -> DailyPracticeBlock {
            let bpm = conditions?.bpm ?? min(exercise.bpm, kind == .warmup ? 90 : exercise.bpm)
            let repeats = conditions?.repeats ?? 2
            let seconds = max(35, Int(ceil(60.0 / Double(bpm) * 4 * Double(exercise.bars * repeats))) + 12)
            return DailyPracticeBlock(kind: kind, exerciseID: exercise.id, title: exercise.title, reason: reason,
                                      bpm: bpm, repeats: repeats, phase: phase,
                                      gapMetronomeLevel: conditions?.gapMetronomeLevel ?? gap,
                                      metronomeEnabled: conditions?.metronomeEnabled ?? true,
                                      loopEnabled: conditions?.loopEnabled ?? false,
                                      loopIdentifier: conditions?.loopIdentifier,
                                      focusedSound: focusedSound, estimatedSeconds: seconds)
        }
        blocks.append(block(.warmup, warmup, latestByExercise[warmup.id] == nil ? "Un patrón sencillo para entrar en ritmo." : "Un ritmo conocido para empezar con confianza."))
        if let dueGoal, let reviewExercise {
            blocks.append(block(.review, reviewExercise, "Repaso pendiente: \(dueGoal.recommendation.explanation)", phase: .transfer,
                                focusedSound: dueGoal.recommendation.sound, conditions: dueGoal.baselineConditions))
        }
        if let challenge, challenge.id != warmup.id {
            blocks.append(block(.challenge, challenge, "Un paso nuevo con una dificultad principal."))
        }
        blocks.append(block(.integrate, integration, "Toca el groove completo y cierra la sesión."))

        var remaining = max(90, targetSeconds - 25)
        for index in blocks.indices {
            let blockCountAfter = blocks.count - index - 1
            let available = max(35, remaining - blockCountAfter * 35)
            let current = blocks[index]
            if current.estimatedSeconds > available && current.kind != .review {
                let exercise = exercises.first(where: { $0.id == current.exerciseID })!
                let oneRepeatSeconds = max(35, Int(ceil(60.0 / Double(current.bpm) * 4 * Double(exercise.bars))) + 12)
                blocks[index] = DailyPracticeBlock(id: current.id, kind: current.kind, exerciseID: current.exerciseID, title: current.title,
                    reason: current.reason, bpm: current.bpm, repeats: 1, phase: current.phase, gapMetronomeLevel: current.gapMetronomeLevel,
                    metronomeEnabled: current.metronomeEnabled, loopEnabled: current.loopEnabled, loopIdentifier: current.loopIdentifier,
                    focusedSound: current.focusedSound, estimatedSeconds: oneRepeatSeconds)
            }
            remaining -= blocks[index].estimatedSeconds
        }
        let accurateTarget = max(targetSeconds, blocks.reduce(0) { $0 + $1.estimatedSeconds })
        return DailyPracticePlan(day: now, targetSeconds: accurateTarget, blocks: blocks)
    }
}

/// Estado de la ruta acreditada. `.locked` indica que aún no se ha acreditado
/// una estación; no impide seleccionar ni practicar su ejercicio.
public enum CourseLevelStatus: Equatable {
    case locked
    case available
    case mastered
}

public enum CourseCreditSource: Equatable {
    case individualAttempt
    case checkpoint(exerciseID: String)
}

public struct CourseLevelState: Equatable {
    public let exerciseID: String
    public let status: CourseLevelStatus
    public let bestScore: Double?
    public let creditSource: CourseCreditSource?
    public let chapterAccredited: Bool

    public init(
        exerciseID: String,
        status: CourseLevelStatus,
        bestScore: Double?,
        creditSource: CourseCreditSource? = nil,
        chapterAccredited: Bool = false
    ) {
        self.exerciseID = exerciseID
        self.status = status
        self.bestScore = bestScore
        self.creditSource = creditSource
        self.chapterAccredited = chapterAccredited
    }
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
        let advancedPassLevels = completeAttempts.compactMap { attempt -> Int? in
            guard attempt.bpm > 100, attempt.score >= completionScore,
                  let exercise = exercises.first(where: { $0.id == attempt.exerciseID }) else { return nil }
            return exercise.level
        }
        let highestAdvancedLevel = advancedPassLevels.max()
        var previousSatisfied = true

        return ordered.map { exercise in
            let bestScore = bestScores[exercise.id]
            let completed = bestScore != nil
            let advancedUnlock = highestAdvancedLevel.map { exercise.level < $0 } ?? false
            let status: CourseLevelStatus = completed ? .mastered : (previousSatisfied || advancedUnlock || exercise.id == fastStartID ? .available : .locked)
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
        recommend(exercises: exercises, courseLevels: courseLevels, evidence: attempts.map(CourseAttemptEvidence.init))
    }

    public static func recommend(exercises: [Exercise], courseLevels: [CourseLevelState], evidence: [CourseAttemptEvidence]) -> CourseRecommendation? {
        let levelStates = Dictionary(uniqueKeysWithValues: courseLevels.map { ($0.exerciseID, $0) })
        let states = levelStates.mapValues(\.status)
        let ordered = orderedMainExercises(exercises, courseLevels: courseLevels)
        if !ordered.isEmpty,
           ordered.allSatisfy({ levelStates[$0.id]?.chapterAccredited == true }) {
            return nil
        }
        // La exploración y los retos avanzados pueden abrir ejercicios futuros,
        // pero la guía permanece en el primer capítulo sin acreditar.
        let pending = ordered.filter { levelStates[$0.id]?.chapterAccredited != true }
        let chapter = pending.first?.metadata?.chapter
        let candidates = pending.filter { chapter == nil || $0.metadata?.chapter == chapter }
        if let current = candidates.first(where: {
            (courseLevels.isEmpty || states[$0.id] == .available)
                && guidedStep(for: $0, evidence: evidence) != nil
        }), let step = guidedStep(for: current, evidence: evidence) {
            return .init(exerciseID: current.id, courseLevel: current.level, tempoStep: step, isCourseCompletion: true)
        }
        if let review = candidates.first(where: { exercise in
            guard states[exercise.id] == .mastered,
                  levelStates[exercise.id]?.chapterAccredited != true else { return false }
            return guidedStep(for: exercise, evidence: evidence) != nil
        }),
           let step = guidedStep(for: review, evidence: evidence) {
            return .init(exerciseID: review.id, courseLevel: review.level, tempoStep: step, isCourseCompletion: false)
        }
        return nil
    }

    /// Continuación desde Resultados. Permite explorar dentro del bloque actual,
    /// pero para cambiar de bloque exige su acreditación y omite los ya cerrados.
    public static func nextExercise(after exerciseID: String, exercises: [Exercise], courseLevels: [CourseLevelState], evidence: [CourseAttemptEvidence]) -> Exercise? {
        let ordered = orderedMainExercises(exercises, courseLevels: courseLevels)
        guard let index = ordered.firstIndex(where: { $0.id == exerciseID }) else { return nil }
        let states = Dictionary(uniqueKeysWithValues: courseLevels.map { ($0.exerciseID, $0) })
        let pending = ordered.filter { states[$0.id]?.chapterAccredited != true }
        guard let firstPending = pending.first else { return nil }
        let currentChapter = ordered[index].metadata?.chapter
        if currentChapter == firstPending.metadata?.chapter,
           let next = ordered.dropFirst(index + 1).first(where: {
               $0.metadata?.chapter == currentChapter
                   && states[$0.id]?.chapterAccredited != true
                   && states[$0.id]?.status != .mastered
           }) {
            return next
        }
        guard let recommendation = recommend(exercises: exercises, courseLevels: courseLevels, evidence: evidence),
              recommendation.exerciseID != exerciseID else { return nil }
        return ordered.first { $0.id == recommendation.exerciseID }
    }

    private static func orderedMainExercises(_ exercises: [Exercise], courseLevels: [CourseLevelState]) -> [Exercise] {
        // Los estados de CourseGraph conservan el orden topológico del MIDI.
        // El nivel numérico histórico no refleja el orden actual de capítulos
        // (p. ej. Coordinación precede a Subdivisión).
        let positions = Dictionary(uniqueKeysWithValues: courseLevels.enumerated().map { ($0.element.exerciseID, $0.offset) })
        return exercises.filter { !($0.metadata?.chapter.hasPrefix("fills-") ?? false) }.sorted {
            let left = positions[$0.id] ?? Int.max
            let right = positions[$1.id] ?? Int.max
            if left != right { return left < right }
            return $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level
        }
    }

    private static func guidedStep(for exercise: Exercise, evidence: [CourseAttemptEvidence]) -> TempoPracticeStep? {
        guard !CourseLessonCriteria.isPassed(exercise, evidence: evidence) else { return nil }
        return TempoPracticeStep(
            label: "Ritmo completo",
            bpm: CourseLessonCriteria.targetBPM(for: exercise),
            requiredScore: CourseLessonCriteria.minimumScore,
            requiredPasses: 1,
            award: .stars(1)
        )
    }
}

/// Prioriza una única microtarea a partir de datos persistidos. La interfaz
/// solo presenta el plan y confirma su configuración antes de iniciar audio.
public enum NextSessionPlanner {
    public static func plan(exercises: [Exercise], courseLevels: [CourseLevelState], attempts: [PracticeAttempt], eligibleExerciseIDs: Set<String>? = nil) -> NextSessionPlan? {
        let eligible = exercises
            .filter { exercise in
                (eligibleExerciseIDs?.contains(exercise.id) ?? true)
            }
            .sorted { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
        guard !eligible.isEmpty else { return nil }
        let evidence = attempts.map(CourseAttemptEvidence.init)
        let recommendation = CourseRecommendationPlanner.recommend(
            exercises: eligible,
            courseLevels: courseLevels,
            evidence: evidence
        )

        if let recommendation,
           let exercise = eligible.first(where: { $0.id == recommendation.exerciseID }) {
            if attempts.isEmpty {
                return makePlan(
                    for: exercise,
                    bpm: recommendation.tempoStep.bpm,
                    kind: .firstSession,
                    reason: "Empieza por este ritmo completo, a su tempo de referencia de \(recommendation.tempoStep.bpm) BPM."
                )
            }
            if let recent = attempts.first,
               recent.exerciseID == exercise.id,
               recent.score < CourseLessonCriteria.minimumScore {
                if let weak = recent.soundStatistics.min(by: { $0.accuracy < $1.accuracy }), weak.accuracy < 70 {
                    return makePlan(for: exercise, bpm: recommendation.tempoStep.bpm, kind: .corrective, reason: "Repite el ritmo y presta atención a \(weak.sound); fue la voz con más margen en el último intento.")
                }
                return makePlan(for: exercise, bpm: recommendation.tempoStep.bpm, kind: .consolidate, reason: "Repite el ritmo completo a \(recommendation.tempoStep.bpm) BPM; un intento más estable te permitirá continuar.")
            }
            return makePlan(
                for: exercise,
                bpm: recommendation.tempoStep.bpm,
                kind: .continueCourse,
                reason: "Es la siguiente lección disponible. Superarla al tempo de referencia permite continuar; los retos de velocidad son opcionales."
            )
        }

        let states = Dictionary(uniqueKeysWithValues: courseLevels.map { ($0.exerciseID, $0) })
        let attemptsByExercise = Dictionary(grouping: attempts, by: \.exerciseID)
        let reviewCandidates = eligible.filter { exercise in
            guard states[exercise.id]?.status == .mastered else { return false }
            if case .checkpoint = states[exercise.id]?.creditSource { return false }
            return true
        }
        guard let review = reviewCandidates.min(by: { left, right in
            let leftScore = attemptsByExercise[left.id]?.first?.score ?? 100
            let rightScore = attemptsByExercise[right.id]?.first?.score ?? 100
            return leftScore == rightScore ? left.level < right.level : leftScore < rightScore
        }) else { return nil }
        return makePlan(for: review, bpm: review.bpm, kind: .review, reason: "La ruta está acreditada. Repasa este ritmo o elige cualquier otro bloque.")
    }

    private static func makePlan(for exercise: Exercise, bpm: Int, kind: NextSessionKind, reason: String) -> NextSessionPlan {
        let repeats = PracticeConfiguration.normalizedRepeats(exercise.repeats)
        let configured = PracticeConfiguration(exercise: exercise, bpm: bpm, repeats: repeats).applying(to: exercise)
        return NextSessionPlan(
            exerciseID: exercise.id,
            title: exercise.title,
            bpm: bpm,
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

/// Explicación breve compartida por ambos resultados. No cambia puntuación,
/// acreditación ni acciones: limita las conclusiones a la evidencia disponible.
public struct PracticeResultFeedback: Equatable {
    public let headline: String
    public let recommendation: String

    public init(score: ExerciseScore, summary: PracticeResultSummary,
                coaching: CoachingRecommendation? = nil, soundName: (String) -> String) {
        let associatedHits = score.hits.filter { $0.expectedNote != nil }
        if case .weakSound(let sound, _, _) = summary.diagnosis,
           associatedHits.filter({ $0.expectedNote?.sound == sound }).count
            + score.misses.filter({ $0.sound == sound }).count >= 4 {
            headline = "«\(soundName(sound))» necesita más apoyo."
            recommendation = "Escucha su referencia y concéntrate en colocar esa entrada dentro del ritmo."
            return
        }
        guard associatedHits.count >= 8 else {
            headline = "Aún faltan golpes para valorar una tendencia."
            recommendation = "Sigue la guía en la próxima vuelta. Con más golpes podremos señalar qué conviene mejorar."
            return
        }
        // Una mediana global puede ocultar que una voz llega tarde mientras
        // las demás van centradas. Exigimos cuatro golpes y dirección en 3/4,
        // además de los mínimos del coaching, antes de señalar un sonido.
        let allowsSoundTiming: Bool
        switch summary.diagnosis {
        case .solid, .timingBias: allowsSoundTiming = true
        default: allowsSoundTiming = false
        }
        if let coaching, coaching.opportunities >= 4, coaching.issueCount >= 2,
           coaching.issue != .repeatedMiss,
           allowsSoundTiming {
            let offsets = associatedHits.filter { $0.expectedNote?.sound == coaching.sound }.compactMap(\.offsetMilliseconds)
            let matching = offsets.filter { coaching.issue == .early ? $0 < -15 : $0 > 15 }.count
            if offsets.count >= 4, matching * 4 >= offsets.count * 3 {
                let early = coaching.issue == .early
                headline = "«\(soundName(coaching.sound))» tiende a llegar \(early ? "pronto" : "tarde")."
                recommendation = early
                    ? "Escucha su referencia y espera un poco más antes de tocar, manteniendo el pulso del resto."
                    : "Escucha su referencia y prepara ese golpe un poco antes, manteniendo el pulso del resto."
                return
            }
        }
        switch summary.diagnosis {
        case .insufficientEvidence, .weakSound:
            headline = "Todavía no hay una dificultad suficientemente repetida."
            recommendation = "Mantén la guía y busca repetir el patrón con regularidad en la próxima práctica."
        case .inconsistent:
            headline = "La separación entre los golpes todavía varía."
            recommendation = "Escucha la claqueta y busca una separación regular entre los golpes, sin perseguir cada nota."
        case .timingBias(let offset):
            headline = offset < 0 ? "Tiendes a llegar antes del pulso." : "Tiendes a llegar después del pulso."
            recommendation = offset < 0
                ? "Espera un poco más antes de tocar y escucha cómo coincide cada golpe con la referencia."
                : "Prepara el movimiento un poco antes y escucha cómo coincide cada golpe con la referencia."
        case .solid:
            if score.percentage < 70, score.extraCount > 0 {
                headline = "Se registraron \(score.extraCount) toques extra."
                recommendation = "Toca solo las notas del patrón y deja espacio en los silencios."
            } else {
                headline = "Tus golpes asociados mantienen un pulso estable."
                recommendation = "Conserva esa regularidad en la siguiente práctica."
            }
        }
    }
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
