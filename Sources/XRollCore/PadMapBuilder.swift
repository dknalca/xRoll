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
    case duplicate(note: Int, channel: Int, existingSound: String)
    case complete(PadMap)
}

public struct PadMapBuilder {
    public static let suggestedSteps = [
        PadMapCaptureStep(sound: "kick", row: 0, column: 0),
        PadMapCaptureStep(sound: "snare", row: 0, column: 2),
        PadMapCaptureStep(sound: "clap", row: 0, column: 3),
        PadMapCaptureStep(sound: "hihat_closed", row: 1, column: 2),
        PadMapCaptureStep(sound: "hihat_open", row: 2, column: 2),
        PadMapCaptureStep(sound: "crash", row: 3, column: 1)
    ]

    private let device: String
    private let deviceUID: Int
    private let created: String
    private let steps: [PadMapCaptureStep]
    private var pads: [PadMap.Pad] = []

    public init(device: String, deviceUID: Int, created: String, steps: [PadMapCaptureStep] = suggestedSteps) {
        self.device = device
        self.deviceUID = deviceUID
        self.created = created
        self.steps = steps
    }

    public var nextStep: PadMapCaptureStep? { steps.dropFirst(pads.count).first }

    public mutating func assign(_ event: MIDINoteOn) -> PadMapCaptureResult {
        guard let step = nextStep else {
            return .complete(PadMap(device: device, deviceUID: deviceUID, created: created, pads: pads))
        }
        if let existing = pads.first(where: { $0.number == event.note && $0.channel == event.channel }) {
            return .duplicate(note: event.note, channel: event.channel, existingSound: existing.sound)
        }
        pads.append(.init(
            sound: step.sound,
            number: event.note,
            channel: event.channel,
            row: step.row,
            column: step.column
        ))
        let map = PadMap(device: device, deviceUID: deviceUID, created: created, pads: pads)
        return nextStep == nil ? .complete(map) : .assigned(sound: step.sound, remaining: steps.count - pads.count)
    }
}
