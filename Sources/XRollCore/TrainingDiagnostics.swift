import Foundation

/// Alcance de la evidencia recogida durante una práctica.
public enum EvaluationScope: String, Codable, Equatable {
    case fullPattern
    case selectedVoices
    case fragment
    case corrective
    case legacyUnknown

    public var countsAsCompletePattern: Bool {
        self == .fullPattern || self == .legacyUnknown
    }
}

/// Ajustes relevantes para decidir si dos intentos se pueden comparar.
/// Los historiales antiguos no tienen este dato y no deben producir afirmaciones
/// de mejora entre condiciones desconocidas.
public struct PracticeConditions: Codable, Equatable {
    public let bpm: Int
    public let repeats: Int
    public let selectedSounds: [String]
    public let stepRangeLowerBound: Int?
    public let stepRangeUpperBound: Int?
    public let gapMetronomeLevel: Int
    public let metronomeEnabled: Bool
    public let loopEnabled: Bool
    public let loopIdentifier: String?
    public let showsVisualGuides: Bool
    public let visualGuideLevel: String?
    public let calibrationProfileKey: CalibrationProfileKey?

    public init(
        bpm: Int,
        repeats: Int,
        selectedSounds: Set<String>,
        stepRange: ClosedRange<Int>? = nil,
        gapMetronomeLevel: Int = 0,
        metronomeEnabled: Bool = true,
        loopEnabled: Bool = false,
        loopIdentifier: String? = nil,
        showsVisualGuides: Bool = true,
        visualGuideLevel: String? = nil,
        calibrationProfileKey: CalibrationProfileKey? = nil
    ) {
        self.bpm = bpm
        self.repeats = max(1, repeats)
        self.selectedSounds = selectedSounds.sorted()
        self.stepRangeLowerBound = stepRange?.lowerBound
        self.stepRangeUpperBound = stepRange?.upperBound
        self.gapMetronomeLevel = min(3, max(0, gapMetronomeLevel))
        self.metronomeEnabled = metronomeEnabled
        self.loopEnabled = loopEnabled
        self.loopIdentifier = loopIdentifier
        self.showsVisualGuides = showsVisualGuides
        self.visualGuideLevel = visualGuideLevel
        self.calibrationProfileKey = calibrationProfileKey
    }

    public var isFullPattern: Bool { stepRangeLowerBound == nil && stepRangeUpperBound == nil }

    /// La prueba de retención puede quitar la guía visual, pero mantiene tempo,
    /// patrón, ruta de audio y calibración para que el objetivo siga siendo comparable.
    public func isComparableForRetention(to other: PracticeConditions) -> Bool {
        bpm == other.bpm && repeats == other.repeats && selectedSounds == other.selectedSounds
            && stepRangeLowerBound == other.stepRangeLowerBound && stepRangeUpperBound == other.stepRangeUpperBound
            && gapMetronomeLevel == other.gapMetronomeLevel && metronomeEnabled == other.metronomeEnabled
            && loopEnabled == other.loopEnabled && loopIdentifier == other.loopIdentifier
            && calibrationProfileKey == other.calibrationProfileKey
    }
}

/// Contexto de una sesión evaluada. Se conserva junto al resultado para que
/// los sellos de dominio no dependan de la interfaz que la produjo.
public struct TrainingContext: Codable, Equatable {
    public let phase: TrainingPhase
    public let gapMetronomeLevel: Int
    public let showsVisualGuides: Bool
    public let evaluationScope: EvaluationScope
    public let completedBars: Int
    public let practiceConditions: PracticeConditions?

    public init(phase: TrainingPhase = .integrate, gapMetronomeLevel: Int = 0, showsVisualGuides: Bool = true, evaluationScope: EvaluationScope = .fullPattern, completedBars: Int = 0, practiceConditions: PracticeConditions? = nil) {
        self.phase = phase
        self.gapMetronomeLevel = min(3, max(0, gapMetronomeLevel))
        self.showsVisualGuides = showsVisualGuides
        self.evaluationScope = evaluationScope
        self.completedBars = max(0, completedBars)
        self.practiceConditions = practiceConditions
    }

    private enum CodingKeys: String, CodingKey {
        case phase, gapMetronomeLevel, showsVisualGuides, evaluationScope, completedBars, practiceConditions
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        phase = try values.decodeIfPresent(TrainingPhase.self, forKey: .phase) ?? .integrate
        gapMetronomeLevel = min(3, max(0, try values.decodeIfPresent(Int.self, forKey: .gapMetronomeLevel) ?? 0))
        showsVisualGuides = try values.decodeIfPresent(Bool.self, forKey: .showsVisualGuides) ?? true
        // Los intentos anteriores no describen si se puntuó el ritmo completo.
        evaluationScope = try values.decodeIfPresent(EvaluationScope.self, forKey: .evaluationScope) ?? .legacyUnknown
        completedBars = max(0, try values.decodeIfPresent(Int.self, forKey: .completedBars) ?? 0)
        practiceConditions = try values.decodeIfPresent(PracticeConditions.self, forKey: .practiceConditions)
    }
}

public enum CoachingIssue: String, Codable, Equatable {
    case repeatedMiss
    case early
    case late
}

public enum CoachingReviewOutcome: Equatable {
    case resolved
    case stillNeedsPractice
    case insufficientEvidence
}

/// Una dificultad concreta elegible para una microlección.
public struct CoachingRecommendation: Codable, Equatable {
    public let sound: String
    public let step: Int
    public let issue: CoachingIssue
    public let opportunities: Int
    public let issueCount: Int
    public let medianOffsetMilliseconds: Double?

    public var stepRange: ClosedRange<Int> { max(0, step - 1)...(step + 1) }
    public var explanation: String {
        switch issue {
        case .repeatedMiss: return "Este golpe se quedó sin respuesta en varias vueltas."
        case .early: return "Este golpe tiende a llegar antes del pulso."
        case .late: return "Este golpe tiende a llegar después del pulso."
        }
    }
}

public enum CoachingAnalyzer {
    private struct Key: Hashable { let sound: String; let step: Int }

    /// Solo recomienda problemas repetidos: requiere al menos tres oportunidades
    /// y dos fallos o desfases coherentes en la misma posición del patrón.
    public static func recommendation(
        exercise: Exercise,
        score: ExerciseScore,
        minimumOpportunities: Int = 3,
        minimumIssues: Int = 2,
        timingThresholdMilliseconds: Double = 45
    ) -> CoachingRecommendation? {
        let records = HitRecord.records(from: score).filter { $0.expectedSound != nil && $0.expectedStep != nil }
        let validSteps = exercise.bars * exercise.grid
        let groups = Dictionary(grouping: records.filter { ($0.expectedStep ?? validSteps) < validSteps }) {
            Key(sound: $0.expectedSound!, step: $0.expectedStep!)
        }
        let candidates = groups.compactMap { key, records -> CoachingRecommendation? in
            guard records.count >= minimumOpportunities else { return nil }
            let misses = records.filter { $0.judgement == .miss }.count
            if misses >= minimumIssues {
                return CoachingRecommendation(sound: key.sound, step: key.step, issue: .repeatedMiss, opportunities: records.count, issueCount: misses, medianOffsetMilliseconds: nil)
            }
            let offsets = records.compactMap { $0.offsetMilliseconds }
            guard offsets.count >= minimumOpportunities else { return nil }
            let early = offsets.filter { $0 <= -timingThresholdMilliseconds }.count
            let late = offsets.filter { $0 >= timingThresholdMilliseconds }.count
            let issue: CoachingIssue
            let count: Int
            if early >= minimumIssues && early * 2 >= offsets.count { issue = .early; count = early }
            else if late >= minimumIssues && late * 2 >= offsets.count { issue = .late; count = late }
            else { return nil }
            let sorted = offsets.sorted()
            let median = sorted[sorted.count / 2]
            return CoachingRecommendation(sound: key.sound, step: key.step, issue: issue, opportunities: records.count, issueCount: count, medianOffsetMilliseconds: median)
        }
        return candidates.sorted { lhs, rhs in
            if lhs.issueCount != rhs.issueCount { return lhs.issueCount > rhs.issueCount }
            if lhs.opportunities != rhs.opportunities { return lhs.opportunities > rhs.opportunities }
            if lhs.step != rhs.step { return lhs.step < rhs.step }
            return lhs.sound < rhs.sound
        }.first
    }

    public static func isResolved(_ recommendation: CoachingRecommendation, by score: ExerciseScore, minimumOpportunities: Int = 3, timingThresholdMilliseconds: Double = 45) -> Bool {
        reviewOutcome(for: recommendation, score: score, minimumOpportunities: minimumOpportunities,
                      timingThresholdMilliseconds: timingThresholdMilliseconds) == .resolved
    }

    public static func reviewOutcome(for recommendation: CoachingRecommendation, score: ExerciseScore, minimumOpportunities: Int = 3, timingThresholdMilliseconds: Double = 45) -> CoachingReviewOutcome {
        let records = HitRecord.records(from: score).filter { $0.expectedSound == recommendation.sound && $0.expectedStep == recommendation.step }
        guard records.count >= minimumOpportunities else { return .insufficientEvidence }
        let misses = records.filter { $0.judgement == .miss }.count
        if misses >= 2 { return .stillNeedsPractice }
        let offsets = records.compactMap(\.offsetMilliseconds)
        guard offsets.count >= minimumOpportunities else { return .insufficientEvidence }
        switch recommendation.issue {
        case .repeatedMiss: return misses < 2 ? .resolved : .stillNeedsPractice
        case .early: return offsets.filter { $0 <= -timingThresholdMilliseconds }.count < 2 ? .resolved : .stillNeedsPractice
        case .late: return offsets.filter { $0 >= timingThresholdMilliseconds }.count < 2 ? .resolved : .stillNeedsPractice
        }
    }
}

public struct CoachingComparison: Equatable {
    public enum Outcome: Equatable { case improved, similar, declined, insufficientEvidence, conditionsDiffer }
    public let outcome: Outcome
    public let baselineOpportunities: Int
    public let followUpOpportunities: Int
    public let baselineMisses: Int
    public let followUpMisses: Int
    public let baselineMedianAbsoluteOffset: Double?
    public let followUpMedianAbsoluteOffset: Double?

    public static func compare(
        baseline: PracticeAttempt,
        followUp: PracticeAttempt,
        recommendation: CoachingRecommendation,
        minimumOpportunities: Int = 4
    ) -> CoachingComparison {
        let sameConditions = baseline.exerciseID == followUp.exerciseID
            && baseline.bpm == followUp.bpm
            && baseline.trainingContext.evaluationScope == .fullPattern
            && followUp.trainingContext.evaluationScope == .fullPattern
            && baseline.trainingContext.practiceConditions != nil
            && baseline.trainingContext.practiceConditions == followUp.trainingContext.practiceConditions
            && baseline.trainingContext.practiceConditions?.isFullPattern == true
        let left = relevantRecords(baseline.hitRecords, recommendation: recommendation)
        let right = relevantRecords(followUp.hitRecords, recommendation: recommendation)
        let leftOffsets = left.compactMap { $0.offsetMilliseconds }.map(abs).sorted()
        let rightOffsets = right.compactMap { $0.offsetMilliseconds }.map(abs).sorted()
        let leftMisses = left.filter { $0.judgement == .miss }.count
        let rightMisses = right.filter { $0.judgement == .miss }.count
        let leftMedian = median(leftOffsets)
        let rightMedian = median(rightOffsets)
        let outcome: Outcome
        if !sameConditions { outcome = .conditionsDiffer }
        else if left.count < minimumOpportunities || right.count < minimumOpportunities { outcome = .insufficientEvidence }
        else if recommendation.issue == .repeatedMiss {
            if rightMisses < leftMisses { outcome = .improved }
            else if rightMisses > leftMisses { outcome = .declined }
            else { outcome = .similar }
        } else {
            let missChange = rightMisses - leftMisses
            let offsetChange = (rightMedian ?? 0) - (leftMedian ?? 0)
            if missChange <= 0 && offsetChange <= -5 { outcome = .improved }
            else if missChange > 0 || offsetChange >= 5 { outcome = .declined }
            else { outcome = .similar }
        }
        return CoachingComparison(outcome: outcome, baselineOpportunities: left.count, followUpOpportunities: right.count,
                                  baselineMisses: leftMisses, followUpMisses: rightMisses,
                                  baselineMedianAbsoluteOffset: leftMedian, followUpMedianAbsoluteOffset: rightMedian)
    }

    private static func relevantRecords(_ records: [HitRecord], recommendation: CoachingRecommendation) -> [HitRecord] {
        records.filter { $0.expectedSound == recommendation.sound && $0.expectedStep == recommendation.step }
    }

    private static func median(_ sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }
}

public struct CoachingGoal: Codable, Equatable, Identifiable {
    public enum State: String, Codable { case pending, confirmed, needsPractice }
    public let id: UUID
    public let exerciseID: String
    public let recommendation: CoachingRecommendation
    public let baselineConditions: PracticeConditions?
    public let createdAt: Date
    public var nextReviewAt: Date
    public var reviewCount: Int
    public var state: State

    public init(id: UUID = UUID(), exerciseID: String, recommendation: CoachingRecommendation, baselineConditions: PracticeConditions? = nil, createdAt: Date = Date(), nextReviewAt: Date? = nil, reviewCount: Int = 0, state: State = .pending) {
        self.id = id; self.exerciseID = exerciseID; self.recommendation = recommendation
        self.baselineConditions = baselineConditions
        self.createdAt = createdAt; self.nextReviewAt = nextReviewAt ?? Calendar.current.date(byAdding: .day, value: 1, to: createdAt) ?? createdAt.addingTimeInterval(86_400)
        self.reviewCount = max(0, reviewCount); self.state = state
    }

    public mutating func recordReview(successful: Bool, at date: Date = Date()) {
        if successful {
            reviewCount += 1
            if reviewCount >= 3 { state = .confirmed }
            else {
                let interval = reviewCount == 1 ? 3 : 7
                nextReviewAt = Calendar.current.date(byAdding: .day, value: interval, to: date) ?? date.addingTimeInterval(Double(interval) * 86_400)
            }
        } else {
            state = .needsPractice
            nextReviewAt = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        }
    }
}

public struct PulseDriftPoint: Equatable {
    public let pulseIndex: Int
    public let medianOffsetMilliseconds: Double
    public let metronomeAudible: Bool
}

public struct PulseDriftReport: Equatable {
    public enum Trend: Equatable { case stable, early, late, insufficientEvidence }
    public let points: [PulseDriftPoint]
    public let silentGapDriftMilliseconds: Double?
    public let trend: Trend
}

public enum GapMetronomePattern {
    public static func isAudible(bar: Int, beat: Int, level: Int) -> Bool {
        guard bar >= 0, (0..<4).contains(beat) else { return true }
        switch min(3, max(0, level)) {
        case 1: return bar % 4 != 3
        case 2: return bar % 4 < 2
        case 3: return bar % 2 == 0 && beat == 0
        default: return true
        }
    }
}

public enum PulseDriftAnalyzer {
    public static func analyze(records: [HitRecord], barDurationMilliseconds: Double, gapLevel: Int, stableThresholdMilliseconds: Double = 5) -> PulseDriftReport {
        guard barDurationMilliseconds > 0, gapLevel > 0 else {
            return PulseDriftReport(points: [], silentGapDriftMilliseconds: nil, trend: .insufficientEvidence)
        }
        let beatDuration = barDurationMilliseconds / 4
        let grouped = Dictionary(grouping: records.compactMap { record -> (Int, Double)? in
            guard let expected = record.expectedTimeMilliseconds, let offset = record.offsetMilliseconds else { return nil }
            let pulseIndex = max(0, Int((expected / beatDuration).rounded()))
            return (pulseIndex, offset)
        }, by: { $0.0 })
        let points = grouped.keys.sorted().compactMap { pulseIndex -> PulseDriftPoint? in
            guard let values = grouped[pulseIndex]?.map({ $0.1 }).sorted(), !values.isEmpty else { return nil }
            let bar = pulseIndex / 4, beat = pulseIndex % 4
            return PulseDriftPoint(pulseIndex: pulseIndex, medianOffsetMilliseconds: values[values.count / 2],
                                   metronomeAudible: GapMetronomePattern.isAudible(bar: bar, beat: beat, level: gapLevel))
        }
        let silent = points.filter { !$0.metronomeAudible }
        guard silent.count >= 2 else { return PulseDriftReport(points: points, silentGapDriftMilliseconds: nil, trend: .insufficientEvidence) }
        let drift = silent.last!.medianOffsetMilliseconds - silent.first!.medianOffsetMilliseconds
        let trend: PulseDriftReport.Trend = drift >= stableThresholdMilliseconds ? .late : drift <= -stableThresholdMilliseconds ? .early : .stable
        return PulseDriftReport(points: points, silentGapDriftMilliseconds: drift, trend: trend)
    }
}

public struct PulseTrainingStage: Equatable, Identifiable {
    public let index: Int
    public let title: String
    public let phase: TrainingPhase
    public let gapMetronomeLevel: Int
    public let showsVisualGuides: Bool
    public let explanation: String
    public var id: Int { index }
}

public enum PulseTrainingPlan {
    public static let stages: [PulseTrainingStage] = [
        .init(index: 0, title: "Encuentra el pulso", phase: .integrate, gapMetronomeLevel: 0, showsVisualGuides: true, explanation: "Toca el patrón completo con notas y metrónomo."),
        .init(index: 1, title: "Recuerda el patrón", phase: .transfer, gapMetronomeLevel: 0, showsVisualGuides: false, explanation: "Las notas desaparecen; la claqueta sigue marcando cada pulso."),
        .init(index: 2, title: "Un compás en silencio", phase: .transfer, gapMetronomeLevel: 1, showsVisualGuides: false, explanation: "La claqueta calla un compás de cada cuatro."),
        .init(index: 3, title: "Dos compases en silencio", phase: .transfer, gapMetronomeLevel: 2, showsVisualGuides: false, explanation: "La claqueta alterna dos compases audibles y dos en silencio."),
        .init(index: 4, title: "Pulso ancla", phase: .transfer, gapMetronomeLevel: 3, showsVisualGuides: false, explanation: "Solo oyes el primer pulso de cada dos compases.")
    ]

    /// Avanza tras dos rondas completas con score básico aprobado. La etapa es
    /// opcional y no modifica el crédito del curso ni los sellos de dominio.
    public static func nextStage(after attempts: [PracticeAttempt], exerciseID: String, exercise: Exercise? = nil) -> PulseTrainingStage {
        let relevant = attempts.filter { $0.exerciseID == exerciseID && $0.trainingContext.evaluationScope == .fullPattern }
        var highestPassed = -1
        for stage in stages {
            let passing = relevant.filter {
                $0.trainingContext.phase == stage.phase
                    && $0.trainingContext.gapMetronomeLevel == stage.gapMetronomeLevel
                    && $0.trainingContext.showsVisualGuides == stage.showsVisualGuides
                    && $0.score >= CourseLessonCriteria.minimumScore
                    && $0.trainingContext.practiceConditions != nil
            }
            func passedPulseDrift(_ attempt: PracticeAttempt) -> Bool {
                guard stage.gapMetronomeLevel == 0 else {
                    guard let exercise, let conditions = attempt.trainingContext.practiceConditions else { return false }
                    let configured = PracticeConfiguration(exercise: exercise, bpm: attempt.bpm, repeats: conditions.repeats).applying(to: exercise)
                    let timeline = ExerciseTimeline(exercise: configured)
                    return PulseDriftAnalyzer.analyze(records: attempt.hitRecords, barDurationMilliseconds: timeline.barDurationMilliseconds,
                                                      gapLevel: stage.gapMetronomeLevel).trend == .stable
                }
                return true
            }
            let passedTwiceUnderSameConditions = passing.contains { first in
                passing.filter {
                    $0.trainingContext.practiceConditions == first.trainingContext.practiceConditions
                        && passedPulseDrift($0)
                }.count >= 2
            }
            if passedTwiceUnderSameConditions { highestPassed = stage.index }
            else { break }
        }
        return stages[min(stages.count - 1, highestPassed + 1)]
    }
}

public struct HistoricalDiagnostic: Equatable {
    public let label: String
    public let expected: Int
    public let successful: Int
    public let missed: Int
    public let medianOffsetMilliseconds: Double?

    public var accuracy: Double { expected == 0 ? 0 : Double(successful) / Double(expected) * 100 }
    public var timingLabel: String {
        guard let medianOffsetMilliseconds else { return "sin golpes registrados" }
        if medianOffsetMilliseconds < -15 { return "adelantado" }
        if medianOffsetMilliseconds > 15 { return "retrasado" }
        return "centrado"
    }
}

public struct HistoricalDiagnostics: Equatable {
    public let bySound: [HistoricalDiagnostic]
    public let byHand: [HistoricalDiagnostic]
    public let byRole: [HistoricalDiagnostic]
    public let byPad: [HistoricalDiagnostic]
    public let bySubdivision: [HistoricalDiagnostic]
    public let byLoop: [HistoricalDiagnostic]
    public let byTransition: [HistoricalDiagnostic]

    public var priority: HistoricalDiagnostic? {
        (bySound + byHand + byRole + byPad + bySubdivision).filter { $0.expected > 0 }
            .min { lhs, rhs in lhs.accuracy == rhs.accuracy ? lhs.expected > rhs.expected : lhs.accuracy < rhs.accuracy }
    }
}

public enum HistoricalDiagnosticsBuilder {
    private struct Accumulator { var expected = 0; var successful = 0; var missed = 0; var offsets = [Double]() }

    public static func build(attempts: [PracticeAttempt], exercisesByID: [String: Exercise]) -> HistoricalDiagnostics {
        var sounds = [String: Accumulator](), hands = [String: Accumulator](), roles = [String: Accumulator]()
        var pads = [String: Accumulator](), subdivisions = [String: Accumulator](), loops = [String: Accumulator](), transitions = [String: Accumulator]()

        func add(_ record: HitRecord, label: String?, to dictionary: inout [String: Accumulator]) {
            guard let label, record.expectedSound != nil else { return }
            var value = dictionary[label, default: .init()]
            value.expected += 1
            if record.judgement != .miss { value.successful += 1 }
            else { value.missed += 1 }
            if let offset = record.offsetMilliseconds { value.offsets.append(offset) }
            dictionary[label] = value
        }

        for attempt in attempts {
            let records = attempt.hitRecords.sorted { $0.sequence < $1.sequence }
            let exercise = exercisesByID[attempt.exerciseID]
            let stepsPerBeat = max(1, (exercise?.grid ?? 16) / 4)
            let patternMilliseconds = exercise.map { 60_000 / Double(attempt.bpm) * 4 * Double($0.bars) }
            for (index, record) in records.enumerated() {
                add(record, label: record.expectedSound, to: &sounds)
                add(record, label: record.hand.map { "Mano \($0)" }, to: &hands)
                add(record, label: record.role ?? ((record.target?.type == .role) ? record.target?.value : nil), to: &roles)
                add(record, label: record.padID ?? ((record.target?.type == .pad) ? record.target?.value : nil), to: &pads)
                if let step = record.expectedStep {
                    let local = step % stepsPerBeat
                    let label: String
                    if stepsPerBeat == 4 { label = ["Pulso", "e", "&", "a"][local] }
                    else if stepsPerBeat == 3 { label = ["Pulso", "tri", "ple"][local] }
                    else { label = "Subdivisión \(local + 1)" }
                    add(record, label: label, to: &subdivisions)
                }
                if let expectedTime = record.expectedTimeMilliseconds, let patternMilliseconds, patternMilliseconds > 0 {
                    add(record, label: "Vuelta \(Int(expectedTime / patternMilliseconds) + 1)", to: &loops)
                }
                if let next = records.dropFirst(index + 1).first(where: { $0.expectedSound != nil })?.expectedSound,
                   let sound = record.expectedSound { add(record, label: "\(sound) → \(next)", to: &transitions) }
            }
        }
        func result(_ values: [String: Accumulator]) -> [HistoricalDiagnostic] {
            values.map { label, value in
                let ordered = value.offsets.sorted()
                return HistoricalDiagnostic(label: label, expected: value.expected, successful: value.successful, missed: value.missed,
                                            medianOffsetMilliseconds: ordered.isEmpty ? nil : ordered[ordered.count / 2])
            }.sorted { lhs, rhs in lhs.accuracy == rhs.accuracy ? lhs.label < rhs.label : lhs.accuracy < rhs.accuracy }
        }
        return HistoricalDiagnostics(bySound: result(sounds), byHand: result(hands), byRole: result(roles), byPad: result(pads), bySubdivision: result(subdivisions), byLoop: result(loops), byTransition: result(transitions))
    }
}

/// Micro-rutina automática: rodea el error, reduce el tempo y deja listo el
/// siguiente fragmento para el encadenado hacia atrás.
public struct WhalePlan: Equatable {
    public let focusSound: String
    public let focusStep: Int
    public let stepRange: ClosedRange<Int>
    public let targetSounds: [String]
    public let bpm: Int
    public let message: String
    public let coachingCue: String
}

public enum WhaleMethod {
    public static func plan(exercise: Exercise, recommendation: CoachingRecommendation) -> WhalePlan {
        let maximum = exercise.bars * exercise.grid - 1
        let range = max(0, recommendation.step - 1)...min(maximum, recommendation.step + 1)
        let targetSounds = Array(Set(exercise.notes.filter { range.contains($0.step) }.map(\.sound))).sorted()
        let stepDuration = max(1, exercise.grid / 4)
        let subdivision = recommendation.step % stepDuration
        let subdivisionName = stepDuration == 4 ? ["el pulso", "e", "y", "a"][subdivision]
            : stepDuration == 3 ? ["el pulso", "tri", "ple"][subdivision]
            : "la subdivisión \(subdivision + 1)"
        let direction = recommendation.issue == .early ? "antes" : recommendation.issue == .late ? "después" : ""
        let cue = direction.isEmpty
            ? "Prepara \(recommendation.sound) en \(subdivisionName) y escucha cómo encaja con las voces que siguen sonando."
            : "Prepara \(recommendation.sound) en \(subdivisionName), sin adelantarte ni llegar \(direction) del pulso."
        return WhalePlan(focusSound: recommendation.sound, focusStep: recommendation.step, stepRange: range,
                         targetSounds: targetSounds, bpm: max(40, Int((Double(exercise.bpm) * 0.8).rounded())),
                         message: "Dificultad repetida en \(recommendation.opportunities) oportunidades: \(recommendation.explanation)",
                         coachingCue: cue)
    }

    public static func plan(exercise: Exercise, score: ExerciseScore) -> WhalePlan? {
        let problem = score.misses.first.map { ($0.sound, $0.step) }
            ?? score.hits.filter { $0.judgement == .regular }.max { abs($0.offsetMilliseconds ?? 0) < abs($1.offsetMilliseconds ?? 0) }.flatMap { hit in hit.expectedNote.map { ($0.sound, $0.step) } }
            ?? score.hits.filter { $0.judgement == .good }.max { abs($0.offsetMilliseconds ?? 0) < abs($1.offsetMilliseconds ?? 0) }.flatMap { hit in hit.expectedNote.map { ($0.sound, $0.step) } }
        guard let problem else { return nil }
        let maximum = exercise.bars * exercise.grid - 1
        let range = max(0, problem.1 - 1)...min(maximum, problem.1 + 1)
        let targetSounds = Array(Set(exercise.notes.filter { range.contains($0.step) }.map(\.sound))).sorted()
        let stepsPerBeat = max(1, exercise.grid / 4)
        let subdivision = problem.1 % stepsPerBeat
        let subdivisionName: String
        if subdivision == 0 {
            subdivisionName = "el pulso"
        } else if stepsPerBeat == 4 {
            subdivisionName = ["", "e", "y", "a"][subdivision]
        } else if stepsPerBeat == 3 {
            subdivisionName = ["", "tri", "ple"][subdivision]
        } else {
            subdivisionName = "la subdivisión \(subdivision + 1)"
        }
        let cue = subdivisionName == "el pulso"
            ? "Prepara \(problem.0) justo en el pulso; escucha cómo encaja con las voces que siguen sonando."
            : "Prepara \(problem.0) en «\(subdivisionName)»; escucha cómo encaja con las voces que siguen sonando."
        return WhalePlan(focusSound: problem.0, focusStep: problem.1, stepRange: range,
                         targetSounds: targetSounds,
                         bpm: max(40, Int((Double(exercise.bpm) * 0.8).rounded())),
                         message: "Vamos a desbloquear este momento: xRoll aísla una célula breve y acompaña el resto del compás.",
                         coachingCue: cue)
    }
}

public struct MasterySeal: Equatable {
    public let label: String
    public let achieved: Bool
    public let detail: String
}

public enum MasteryEvaluator {
    public static func seals(exercise: Exercise, attempts: [PracticeAttempt]) -> [MasterySeal] {
        func passes(_ attempt: PracticeAttempt) -> Bool {
            guard attempt.score >= 85 else { return false }
            let offsets = attempt.hitRecords.compactMap(\.offsetMilliseconds).map(abs).sorted()
            return offsets.isEmpty || offsets[offsets.count / 2] <= 20
        }
        let relevant = attempts.filter {
            $0.exerciseID == exercise.id && $0.trainingContext.evaluationScope == .fullPattern
        }
        let precision = relevant.contains { abs($0.bpm - exercise.bpm) <= 2 && passes($0) }
        let slow = relevant.contains { $0.bpm <= exercise.bpm - 15 && passes($0) }
        let fast = relevant.contains { $0.bpm >= exercise.bpm + 15 && passes($0) }
        let gap = relevant.contains { $0.trainingContext.gapMetronomeLevel >= 2 && passes($0) }
        let blind = relevant.contains { $0.trainingContext.phase == .transfer && !$0.trainingContext.showsVisualGuides && passes($0) }
        return [
            .init(label: "Precisión", achieved: precision, detail: "85 % al tempo nominal"),
            .init(label: "Elasticidad", achieved: slow && fast, detail: "−15 y +15 BPM"),
            .init(label: "Pulso interno", achieved: gap, detail: "Gap 2+2 superado"),
            .init(label: "Memoria", achieved: blind, detail: "Transferencia sin guía")
        ]
    }
}
