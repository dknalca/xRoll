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

    public init(debugEnabled: Bool = false, anticipationBars: Int = 2, perfectWindowMilliseconds: Double = 35, goodWindowMilliseconds: Double = 65, regularWindowMilliseconds: Double = 120, manualTimingOffsetMilliseconds: Double = 0, countInVolume: Double = 0.85, loopVolume: Double = 0.72, metronomePitchSemitones: Double = 0, padFlashMilliseconds: Int = 120) {
        self.debugEnabled = debugEnabled
        self.anticipationBars = min(4, max(1, anticipationBars))
        self.perfectWindowMilliseconds = min(100, max(5, perfectWindowMilliseconds))
        self.goodWindowMilliseconds = min(150, max(self.perfectWindowMilliseconds, goodWindowMilliseconds))
        self.regularWindowMilliseconds = min(250, max(self.goodWindowMilliseconds, regularWindowMilliseconds))
        self.manualTimingOffsetMilliseconds = min(200, max(-200, manualTimingOffsetMilliseconds))
        self.countInVolume = min(1, max(0, countInVolume))
        self.loopVolume = min(1, max(0, loopVolume))
        self.metronomePitchSemitones = min(24, max(-12, metronomePitchSemitones))
        self.padFlashMilliseconds = min(500, max(30, padFlashMilliseconds))
    }

    private enum CodingKeys: String, CodingKey {
        case debugEnabled, anticipationBars, perfectWindowMilliseconds, goodWindowMilliseconds, regularWindowMilliseconds, manualTimingOffsetMilliseconds, countInVolume, loopVolume, metronomePitchSemitones, padFlashMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            debugEnabled: try values.decodeIfPresent(Bool.self, forKey: .debugEnabled) ?? false,
            anticipationBars: try values.decodeIfPresent(Int.self, forKey: .anticipationBars) ?? 2,
            perfectWindowMilliseconds: try values.decodeIfPresent(Double.self, forKey: .perfectWindowMilliseconds) ?? 35,
            goodWindowMilliseconds: try values.decodeIfPresent(Double.self, forKey: .goodWindowMilliseconds) ?? 65,
            regularWindowMilliseconds: try values.decodeIfPresent(Double.self, forKey: .regularWindowMilliseconds) ?? 120,
            manualTimingOffsetMilliseconds: try values.decodeIfPresent(Double.self, forKey: .manualTimingOffsetMilliseconds) ?? 0,
            countInVolume: try values.decodeIfPresent(Double.self, forKey: .countInVolume) ?? 0.85,
            loopVolume: try values.decodeIfPresent(Double.self, forKey: .loopVolume) ?? 0.72,
            metronomePitchSemitones: try values.decodeIfPresent(Double.self, forKey: .metronomePitchSemitones) ?? 0,
            padFlashMilliseconds: try values.decodeIfPresent(Int.self, forKey: .padFlashMilliseconds) ?? 120
        )
    }

    public var scoringWindows: ScoringWindows {
        ScoringWindows(perfectMilliseconds: perfectWindowMilliseconds, goodMilliseconds: goodWindowMilliseconds, regularMilliseconds: regularWindowMilliseconds)
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
