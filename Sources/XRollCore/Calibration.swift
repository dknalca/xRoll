import Foundation

public enum CalibrationInputKind: String, Codable, Equatable {
    case midi
    case keyboard
    case touch
}

public struct CalibrationProfileKey: Codable, Equatable, Hashable {
    public let inputKind: CalibrationInputKind
    public let inputIdentifier: String
    public let outputIdentifier: String
    public let sampleRate: Double
    public let bufferFrames: Int

    public init(
        inputKind: CalibrationInputKind,
        inputIdentifier: String,
        outputIdentifier: String,
        sampleRate: Double,
        bufferFrames: Int
    ) {
        self.inputKind = inputKind
        self.inputIdentifier = inputIdentifier
        self.outputIdentifier = outputIdentifier
        self.sampleRate = sampleRate
        self.bufferFrames = bufferFrames
    }
}

public struct CalibrationEstimate: Equatable {
    public let offsetMilliseconds: Double
    public let medianAbsoluteDeviationMilliseconds: Double
    public let acceptedHitCount: Int

    public init(offsetMilliseconds: Double, medianAbsoluteDeviationMilliseconds: Double, acceptedHitCount: Int) {
        self.offsetMilliseconds = offsetMilliseconds
        self.medianAbsoluteDeviationMilliseconds = medianAbsoluteDeviationMilliseconds
        self.acceptedHitCount = acceptedHitCount
    }
}

public struct CalibrationHitAssociation: Equatable {
    public let targetTimeMilliseconds: Double
    public let rawOffsetMilliseconds: Double

    public init(targetTimeMilliseconds: Double, rawOffsetMilliseconds: Double) {
        self.targetTimeMilliseconds = targetTimeMilliseconds
        self.rawOffsetMilliseconds = rawOffsetMilliseconds
    }
}

/// Empareja golpes de calibración con objetivos sin aplicar la ventana Regular
/// del scorer. Cada objetivo se consume una sola vez y se descartan golpes fuera
/// de la mitad de la separación local, donde la asociación dejaría de ser única.
public struct CalibrationMatcher {
    private let targetTimesMilliseconds: [Double]
    private var consumedTargetIndices = Set<Int>()

    public init(targetTimesMilliseconds: [Double]) {
        self.targetTimesMilliseconds = targetTimesMilliseconds.sorted()
    }

    public mutating func associateHit(atMilliseconds hitTimeMilliseconds: Double) -> CalibrationHitAssociation? {
        let availableIndices = targetTimesMilliseconds.indices.filter { !consumedTargetIndices.contains($0) }
        guard let nearestIndex = availableIndices.min(by: { left, right in
            let leftDistance = abs(hitTimeMilliseconds - targetTimesMilliseconds[left])
            let rightDistance = abs(hitTimeMilliseconds - targetTimesMilliseconds[right])
            return leftDistance == rightDistance
                ? targetTimesMilliseconds[left] < targetTimesMilliseconds[right]
                : leftDistance < rightDistance
        }) else { return nil }

        let leftSpacing = nearestIndex > 0
            ? targetTimesMilliseconds[nearestIndex] - targetTimesMilliseconds[nearestIndex - 1]
            : Double.infinity
        let rightSpacing = nearestIndex + 1 < targetTimesMilliseconds.count
            ? targetTimesMilliseconds[nearestIndex + 1] - targetTimesMilliseconds[nearestIndex]
            : Double.infinity
        let localSpacing = min(leftSpacing, rightSpacing)
        let rawOffset = hitTimeMilliseconds - targetTimesMilliseconds[nearestIndex]
        guard localSpacing.isFinite, localSpacing > 0, abs(rawOffset) < localSpacing / 2 else { return nil }

        consumedTargetIndices.insert(nearestIndex)
        return CalibrationHitAssociation(
            targetTimeMilliseconds: targetTimesMilliseconds[nearestIndex],
            rawOffsetMilliseconds: rawOffset
        )
    }
}

public enum CalibrationError: LocalizedError, Equatable {
    case notEnoughHits(minimum: Int)

    public var errorDescription: String? {
        switch self {
        case .notEnoughHits(let minimum): return "Hacen falta al menos \(minimum) golpes para calibrar."
        }
    }
}

public enum CalibrationEstimator {
    public static func estimate(
        rawOffsetsMilliseconds: [Double],
        discardFirst: Int = 4,
        minimumAcceptedHits: Int = 8
    ) throws -> CalibrationEstimate {
        let accepted = Array(rawOffsetsMilliseconds.dropFirst(max(0, discardFirst)))
        guard accepted.count >= minimumAcceptedHits else {
            throw CalibrationError.notEnoughHits(minimum: minimumAcceptedHits)
        }
        let offset = median(accepted)
        let deviations = accepted.map { abs($0 - offset) }
        return CalibrationEstimate(
            offsetMilliseconds: offset,
            medianAbsoluteDeviationMilliseconds: median(deviations),
            acceptedHitCount: accepted.count
        )
    }

    public static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

public struct CalibrationProfile: Codable, Equatable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let key: CalibrationProfileKey
    /// Reservado para diagnósticos internos; la app no depende de esta medida.
    public let systemLatencyMilliseconds: Double?
    /// La prueba guiada estima el desfase práctico de la ruta y del usuario.
    public let userCalibrationBiasMilliseconds: Double?
    public let scoringCompensationMilliseconds: Double
    public let medianAbsoluteDeviationMilliseconds: Double
    public let calibratedAt: Date

    /// La compensación guiada se aplica al scoring de su ruta exacta.
    public var offsetMilliseconds: Double { scoringCompensationMilliseconds }

    public init(key: CalibrationProfileKey, estimate: CalibrationEstimate, calibratedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.key = key
        systemLatencyMilliseconds = nil
        userCalibrationBiasMilliseconds = estimate.offsetMilliseconds
        scoringCompensationMilliseconds = estimate.offsetMilliseconds
        medianAbsoluteDeviationMilliseconds = estimate.medianAbsoluteDeviationMilliseconds
        self.calibratedAt = calibratedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, key, systemLatencyMilliseconds, userCalibrationBiasMilliseconds
        case scoringCompensationMilliseconds, medianAbsoluteDeviationMilliseconds, calibratedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container, debugDescription: "El perfil de calibración pertenece a un esquema anterior.")
        }
        schemaVersion = version
        key = try container.decode(CalibrationProfileKey.self, forKey: .key)
        systemLatencyMilliseconds = try container.decodeIfPresent(Double.self, forKey: .systemLatencyMilliseconds)
        userCalibrationBiasMilliseconds = try container.decodeIfPresent(Double.self, forKey: .userCalibrationBiasMilliseconds)
        guard userCalibrationBiasMilliseconds != nil else {
            throw DecodingError.dataCorruptedError(forKey: .userCalibrationBiasMilliseconds, in: container, debugDescription: "El perfil no contiene calibración guiada.")
        }
        scoringCompensationMilliseconds = try container.decode(Double.self, forKey: .scoringCompensationMilliseconds)
        medianAbsoluteDeviationMilliseconds = try container.decode(Double.self, forKey: .medianAbsoluteDeviationMilliseconds)
        calibratedAt = try container.decode(Date.self, forKey: .calibratedAt)
    }
}

public enum CalibrationProfileStore {
    public static func load(from url: URL) throws -> [CalibrationProfile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CalibrationProfile].self, from: Data(contentsOf: url))
    }

    public static func save(_ profiles: [CalibrationProfile], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: url, options: .atomic)
    }
}
