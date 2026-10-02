import Foundation

/// Parámetros de afinado que se pueden ajustar desde Ajustes > Debug sin
/// modificar ejercicios ni recompilar la aplicación.
public struct PracticeTuning: Codable, Equatable {
    public var debugEnabled: Bool
    public var anticipationBars: Int
    public var perfectWindowMilliseconds: Double
    public var goodWindowMilliseconds: Double
    public var regularWindowMilliseconds: Double
    public var manualTimingOffsetMilliseconds: Double
    public var countInVolume: Double
    public var loopVolume: Double
    public var metronomePitchSemitones: Double
    public var padFlashMilliseconds: Int
    /// Ganancia posterior a la normalización, por id de sonido del kit.
    public var soundVolumes: [String: Double]

    public init(debugEnabled: Bool = false, anticipationBars: Int = 2, perfectWindowMilliseconds: Double = 35, goodWindowMilliseconds: Double = 65, regularWindowMilliseconds: Double = 95, manualTimingOffsetMilliseconds: Double = 0, countInVolume: Double = 0.85, loopVolume: Double = 0.72, metronomePitchSemitones: Double = 0, padFlashMilliseconds: Int = 120, soundVolumes: [String: Double] = [:]) {
        self.debugEnabled = debugEnabled
        self.anticipationBars = min(4, max(1, anticipationBars))
        self.perfectWindowMilliseconds = min(35, max(5, perfectWindowMilliseconds))
        self.goodWindowMilliseconds = min(65, max(self.perfectWindowMilliseconds, goodWindowMilliseconds))
        self.regularWindowMilliseconds = min(95, max(self.goodWindowMilliseconds, regularWindowMilliseconds))
        self.manualTimingOffsetMilliseconds = min(200, max(-200, manualTimingOffsetMilliseconds))
        self.countInVolume = min(1, max(0, countInVolume))
        self.loopVolume = min(1, max(0, loopVolume))
        self.metronomePitchSemitones = min(24, max(-12, metronomePitchSemitones))
        self.padFlashMilliseconds = min(500, max(30, padFlashMilliseconds))
        self.soundVolumes = soundVolumes.mapValues { min(1.5, max(0, $0)) }
    }

    private enum CodingKeys: String, CodingKey {
        case debugEnabled, anticipationBars, perfectWindowMilliseconds, goodWindowMilliseconds, regularWindowMilliseconds, manualTimingOffsetMilliseconds, countInVolume, loopVolume, metronomePitchSemitones, padFlashMilliseconds, soundVolumes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            debugEnabled: try values.decodeIfPresent(Bool.self, forKey: .debugEnabled) ?? false,
            anticipationBars: try values.decodeIfPresent(Int.self, forKey: .anticipationBars) ?? 2,
            perfectWindowMilliseconds: try values.decodeIfPresent(Double.self, forKey: .perfectWindowMilliseconds) ?? 35,
            goodWindowMilliseconds: try values.decodeIfPresent(Double.self, forKey: .goodWindowMilliseconds) ?? 65,
            regularWindowMilliseconds: try values.decodeIfPresent(Double.self, forKey: .regularWindowMilliseconds) ?? 95,
            manualTimingOffsetMilliseconds: try values.decodeIfPresent(Double.self, forKey: .manualTimingOffsetMilliseconds) ?? 0,
            countInVolume: try values.decodeIfPresent(Double.self, forKey: .countInVolume) ?? 0.85,
            loopVolume: try values.decodeIfPresent(Double.self, forKey: .loopVolume) ?? 0.72,
            metronomePitchSemitones: try values.decodeIfPresent(Double.self, forKey: .metronomePitchSemitones) ?? 0,
            padFlashMilliseconds: try values.decodeIfPresent(Int.self, forKey: .padFlashMilliseconds) ?? 120,
            soundVolumes: try values.decodeIfPresent([String: Double].self, forKey: .soundVolumes) ?? [:]
        )
    }

    public func scoringWindows(bpm: Int, grid: Int) -> ScoringWindows {
        let automatic = ScoringWindows(bpm: bpm, grid: grid)
        guard debugEnabled else { return automatic }
        return ScoringWindows(
            perfectMilliseconds: min(perfectWindowMilliseconds, automatic.perfectMilliseconds),
            goodMilliseconds: min(goodWindowMilliseconds, automatic.goodMilliseconds),
            regularMilliseconds: min(regularWindowMilliseconds, automatic.regularMilliseconds)
        )
    }
}

public enum PracticeTuningStore {
    public static func load(from url: URL) throws -> PracticeTuning {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        return try JSONDecoder().decode(PracticeTuning.self, from: Data(contentsOf: url))
    }

    public static func save(_ tuning: PracticeTuning, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tuning).write(to: url, options: .atomic)
    }
}
