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
                 offset: exercise.offset, notes: exercise.notes)
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
        let mean = offsets.isEmpty ? 0 : offsets.reduce(0, +) / Double(offsets.count)
        timingLabel = mean < -15 ? "Tiendes a adelantar el golpe" : mean > 15 ? "Tiendes a retrasar el golpe" : "Tu pulso está centrado"
        guard !offsets.isEmpty else { medianOffsetMilliseconds = nil; medianAbsoluteDeviationMilliseconds = nil; percentile95AbsoluteMilliseconds = nil; soundStatistics = []; return }
        let median = offsets[offsets.count / 2]
        medianOffsetMilliseconds = median
        let deviations = offsets.map { abs($0 - median) }.sorted()
        medianAbsoluteDeviationMilliseconds = deviations[deviations.count / 2]
        let absolute = offsets.map(abs).sorted()
        percentile95AbsoluteMilliseconds = absolute[min(absolute.count - 1, Int((Double(absolute.count - 1) * 0.95).rounded(.up)))]
        let sounds = Set(score.hits.compactMap { $0.expectedNote?.sound }).union(score.misses.map(\.sound))
        soundStatistics = sounds.sorted().map { sound in
            let judged = score.hits.filter { $0.expectedNote?.sound == sound }
            return SoundStatistics(sound: sound, expected: judged.count + score.misses.filter { $0.sound == sound }.count,
                                   perfect: judged.filter { $0.judgement == .perfect }.count,
                                   good: judged.filter { $0.judgement == .good }.count,
                                   regular: judged.filter { $0.judgement == .regular }.count,
                                   missed: score.misses.filter { $0.sound == sound }.count)
        }
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
        let offsets = score.hits.compactMap(\.offsetMilliseconds)
        let mean = offsets.isEmpty ? 0 : offsets.reduce(0, +) / Double(offsets.count)
        let spread = offsets.isEmpty ? 0 : offsets.map { abs($0 - mean) }.reduce(0, +) / Double(offsets.count)
        if spread > 45 { return .init(message: "Hay variación entre golpes: baja el tempo y toca una vuelta corta.", bpmAdjustment: -6, repeats: 2, help: .full) }
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
