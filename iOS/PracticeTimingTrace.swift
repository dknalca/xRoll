import Foundation
import XRollCore

enum PracticeTraceInput: String, Codable {
    case touch
    case midi
}

struct PracticeTimingSample: Codable {
    var sequence = 0
    let input: PracticeTraceInput
    let inputHostTime: UInt64
    let workerHostTime: UInt64?
    let audioSubmissionStartHostTime: UInt64?
    let audioSubmissionReturnHostTime: UInt64?
    let audioSubmissionError: String?
    let mainDeliveryHostTime: UInt64
    let visualUpdateHostTime: UInt64?
    let estimatedPresentationHostTime: UInt64?
    let frameIntervalMilliseconds: Double?
    let visualPredictionMilliseconds: Double?
    let targetHostTime: UInt64?
    let expectedNoteTimeMilliseconds: Double?
    let nearestExpectedTargetHostTime: UInt64?
    let nearestExpectedTargetTimeMilliseconds: Double?
    let scoredOffsetMilliseconds: Double?
    let calibrationHitTimeMilliseconds: Double?
    let calibrationTargetTimeMilliseconds: Double?
    let rawCalibrationOffsetMilliseconds: Double?
    let judgement: String?
    let soundID: String?
    let midiNote: Int?
    let midiChannel: Int?
    let midiVelocity: Int?
    let midiCoreMIDIHostTime: UInt64?
    let midiCallbackHostTime: UInt64?
    let midiTimestampSource: MIDITimestampSource?
    let sourceIdentifier: String?
    let touchTimestampSeconds: Double?
}

struct PracticeTimingTraceDocument: Codable {
    let schemaVersion: Int
    let capturedAt: Date
    let sessionID: String
    let exerciseID: String
    let bpm: Int
    let isCalibration: Bool
    let outcome: String
    let inputKind: String
    let inputIdentifier: String
    let outputIdentifier: String
    let scoringCompensationMilliseconds: Double
    let calibrationTargetTimesMillisecondsBySound: [String: [Double]]
    let predictsVisualFrame: Bool
    let sampleRate: Double
    let bufferFrames: Int
    let totalEventCount: Int
    let truncatedEventCount: Int
    let midiDroppedPacketCount: UInt64
    let samples: [PracticeTimingSample]
}

/// Buffer circular acotado; captura únicamente fuera del callback CoreMIDI y
/// escribe un JSON al terminar una sesión para comparar relojes sin logging RT.
final class PracticeTimingTraceBuffer {
    private let lock = NSLock()
    private let capacity: Int
    private var storage: [PracticeTimingSample?]
    private var nextIndex = 0
    private var count = 0
    private var nextSequence = 0

    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: self.capacity)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage = Array(repeating: nil, count: capacity)
        nextIndex = 0
        count = 0
        nextSequence = 0
    }

    func append(_ sample: PracticeTimingSample) {
        lock.lock()
        defer { lock.unlock() }
        var sample = sample
        sample.sequence = nextSequence
        nextSequence += 1
        storage[nextIndex] = sample
        nextIndex = (nextIndex + 1) % capacity
        count = min(capacity, count + 1)
    }

    func snapshot() -> [PracticeTimingSample] {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return [] }
        let oldestIndex = count == capacity ? nextIndex : 0
        return (0..<count).compactMap { storage[(oldestIndex + $0) % capacity] }
    }

    var totalEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return nextSequence
    }

    func export(_ document: PracticeTimingTraceDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }
}
