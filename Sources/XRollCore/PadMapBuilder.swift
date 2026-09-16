import Foundation

public struct PadMapCaptureStep: Equatable {
    public let sound: String
    public let row: Int
    public let column: Int

    public init(sound: String, row: Int, column: Int) {
        self.sound = sound
        self.row = row
        self.column = column
    }
}

public enum PadMapCaptureResult: Equatable {
    case assigned(sound: String, remaining: Int)
    case skipped(sound: String, remaining: Int)
    case duplicate(note: Int, channel: Int, existingSound: String)
    case complete(PadMapV2)
}

public struct PadMapBuilder {
    public static let suggestedSteps = [
        PadMapCaptureStep(sound: "kick", row: 0, column: 0),
        PadMapCaptureStep(sound: "rim", row: 0, column: 1),
        PadMapCaptureStep(sound: "snare", row: 0, column: 2),
        PadMapCaptureStep(sound: "clap", row: 0, column: 3),
        PadMapCaptureStep(sound: "kick", row: 1, column: 0),
        PadMapCaptureStep(sound: "tom_low", row: 1, column: 1),
        PadMapCaptureStep(sound: "hihat_closed", row: 1, column: 2),
        PadMapCaptureStep(sound: "snare", row: 1, column: 3),
        PadMapCaptureStep(sound: "hihat_closed", row: 2, column: 0),
        PadMapCaptureStep(sound: "hihat_closed", row: 2, column: 1),
        PadMapCaptureStep(sound: "hihat_open", row: 2, column: 2),
        PadMapCaptureStep(sound: "hihat_open", row: 2, column: 3),
        PadMapCaptureStep(sound: "tom_high", row: 3, column: 0),
        PadMapCaptureStep(sound: "crash", row: 3, column: 1),
        PadMapCaptureStep(sound: "crash", row: 3, column: 2),
        PadMapCaptureStep(sound: "ride", row: 3, column: 3)
    ]

    private let device: String
    private let deviceUID: Int
    private let created: String
    private let steps: [PadMapCaptureStep]
    private var pads: [PadMapV2.Pad] = []
    private var stepIndex = 0

    public init(device: String, deviceUID: Int, created: String, steps: [PadMapCaptureStep] = suggestedSteps) {
        self.device = device
        self.deviceUID = deviceUID
        self.created = created
        self.steps = steps
    }

    public var nextStep: PadMapCaptureStep? {
        guard stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    public mutating func assign(_ event: MIDINoteOn) -> PadMapCaptureResult {
        guard let step = nextStep else {
            return .complete(map)
        }
        if let existing = pads.first(where: { $0.input.number == event.note && $0.input.channel == event.channel }) {
            return .duplicate(note: event.note, channel: event.channel, existingSound: existing.sound)
        }
        pads.append(PadMapV2.Pad(
            id: "r\(step.row)c\(step.column)",
            row: step.row,
            column: step.column,
            sound: step.sound,
            input: PadMapV2.Input(number: event.note, channel: event.channel)
        ))
        stepIndex += 1
        return nextStep == nil ? .complete(map) : .assigned(sound: step.sound, remaining: steps.count - stepIndex)
    }

    public mutating func skip() -> PadMapCaptureResult? {
        guard let step = nextStep else { return nil }
        stepIndex += 1
        return nextStep == nil ? .complete(map) : .skipped(sound: step.sound, remaining: steps.count - stepIndex)
    }

    private var map: PadMapV2 {
        PadMapV2(id: PadLayoutPreset.core.rawValue, name: "xRoll Core", preset: .core, device: .init(name: device, uid: deviceUID), created: created, pads: pads)
    }
}
