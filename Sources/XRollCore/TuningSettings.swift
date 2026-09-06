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
    public var padFlashMilliseconds: Int

    public init(debugEnabled: Bool = false, anticipationBars: Int = 2, perfectWindowMilliseconds: Double = 35, goodWindowMilliseconds: Double = 65, regularWindowMilliseconds: Double = 120, manualTimingOffsetMilliseconds: Double = 0, countInVolume: Double = 0.85, padFlashMilliseconds: Int = 120) {
        self.debugEnabled = debugEnabled
        self.anticipationBars = min(4, max(1, anticipationBars))
        self.perfectWindowMilliseconds = min(100, max(5, perfectWindowMilliseconds))
        self.goodWindowMilliseconds = min(150, max(self.perfectWindowMilliseconds, goodWindowMilliseconds))
        self.regularWindowMilliseconds = min(250, max(self.goodWindowMilliseconds, regularWindowMilliseconds))
        self.manualTimingOffsetMilliseconds = min(200, max(-200, manualTimingOffsetMilliseconds))
        self.countInVolume = min(1, max(0, countInVolume))
        self.padFlashMilliseconds = min(500, max(30, padFlashMilliseconds))
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
