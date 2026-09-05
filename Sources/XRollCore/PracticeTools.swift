import Foundation

/// Ajustes de una sesión que no alteran el archivo original del ejercicio.
public struct PracticeConfiguration: Equatable {
    public var bpm: Int
    public var repeats: Int

    public init(exercise: Exercise, bpm: Int? = nil, repeats: Int? = nil) {
        self.bpm = min(240, max(40, bpm ?? exercise.bpm))
        self.repeats = min(16, max(1, repeats ?? exercise.repeats))
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
            else if (item?.latestScore ?? 0) < 75 { reason = "Conviene consolidarlo" }
            else { reason = "Repaso para mantener el pulso" }
            return WarmupRecommendation(exerciseID: exercise.id, title: exercise.title, bpm: exercise.bpm, reason: reason)
        }
    }
}

public struct SoundStatistics: Equatable {
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

    public init(score: ExerciseScore) {
        let offsets = score.hits.compactMap(\.offsetMilliseconds)
        let mean = offsets.isEmpty ? 0 : offsets.reduce(0, +) / Double(offsets.count)
        timingLabel = mean < -15 ? "Tiendes a adelantar el golpe" : mean > 15 ? "Tiendes a retrasar el golpe" : "Tu pulso está centrado"
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
