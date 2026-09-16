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

/// Contexto de una sesión evaluada. Se conserva junto al resultado para que
/// los sellos de dominio no dependan de la interfaz que la produjo.
public struct TrainingContext: Codable, Equatable {
    public let phase: TrainingPhase
    public let gapMetronomeLevel: Int
    public let showsVisualGuides: Bool
    public let evaluationScope: EvaluationScope

    public init(phase: TrainingPhase = .integrate, gapMetronomeLevel: Int = 0, showsVisualGuides: Bool = true, evaluationScope: EvaluationScope = .fullPattern) {
        self.phase = phase
        self.gapMetronomeLevel = min(3, max(0, gapMetronomeLevel))
        self.showsVisualGuides = showsVisualGuides
        self.evaluationScope = evaluationScope
    }

    private enum CodingKeys: String, CodingKey {
        case phase, gapMetronomeLevel, showsVisualGuides, evaluationScope
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        phase = try values.decodeIfPresent(TrainingPhase.self, forKey: .phase) ?? .integrate
        gapMetronomeLevel = min(3, max(0, try values.decodeIfPresent(Int.self, forKey: .gapMetronomeLevel) ?? 0))
        showsVisualGuides = try values.decodeIfPresent(Bool.self, forKey: .showsVisualGuides) ?? true
        // Los intentos anteriores no describen si se puntuó el ritmo completo.
        evaluationScope = try values.decodeIfPresent(EvaluationScope.self, forKey: .evaluationScope) ?? .legacyUnknown
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
}

public enum WhaleMethod {
    public static func plan(exercise: Exercise, score: ExerciseScore) -> WhalePlan? {
        let problem = score.misses.first.map { ($0.sound, $0.step) }
            ?? score.hits.filter { $0.judgement == .regular }.max { abs($0.offsetMilliseconds ?? 0) < abs($1.offsetMilliseconds ?? 0) }.flatMap { hit in hit.expectedNote.map { ($0.sound, $0.step) } }
            ?? score.hits.filter { $0.judgement == .good }.max { abs($0.offsetMilliseconds ?? 0) < abs($1.offsetMilliseconds ?? 0) }.flatMap { hit in hit.expectedNote.map { ($0.sound, $0.step) } }
        guard let problem else { return nil }
        let maximum = exercise.bars * exercise.grid - 1
        let range = max(0, problem.1 - 1)...min(maximum, problem.1 + 1)
        let targetSounds = Array(Set(exercise.notes.filter { range.contains($0.step) }.map(\.sound))).sorted()
        return WhalePlan(focusSound: problem.0, focusStep: problem.1, stepRange: range,
                         targetSounds: targetSounds,
                         bpm: max(40, Int((Double(exercise.bpm) * 0.8).rounded())),
                         message: "No es un ejercicio nuevo: detectó un error en \(problem.0) y propone repetir su línea completa; xRoll acompaña el resto.")
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
