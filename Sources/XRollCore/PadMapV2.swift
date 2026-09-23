import Foundation

public enum PadLayoutPreset: String, Codable, CaseIterable {
    case core = "xroll_core"
    case drumKit = "drum_kit"
    case mirror
    case custom
}

public enum PadOrientation: String, Codable, CaseIterable {
    case rightHanded = "right_handed"
    case leftHanded = "left_handed"
}

public struct PadMapV2: Codable, Equatable {
    public struct Device: Codable, Equatable {
        public let name: String
        public let uid: Int
        public init(name: String, uid: Int) { self.name = name; self.uid = uid }
    }
    public struct Input: Codable, Equatable {
        public let message: String
        public let number: Int
        public let channel: Int
        public init(message: String = "note", number: Int, channel: Int) { self.message = message; self.number = number; self.channel = channel }
    }
    public struct Pad: Codable, Equatable {
        public let id: String
        public let row: Int
        public let column: Int
        public let sound: String
        public let role: String?
        public let input: Input
        enum CodingKeys: String, CodingKey { case id, row, sound, role, input; case column = "col" }
        public init(id: String, row: Int, column: Int, sound: String, role: String? = nil, input: Input) {
            self.id = id; self.row = row; self.column = column; self.sound = sound; self.role = role; self.input = input
        }
    }

    public let format: Int
    public let id: String
    public let name: String
    public let preset: PadLayoutPreset
    /// Campo legado para abrir mapas v2 anteriores; no altera el layout.
    public let orientation: PadOrientation
    public let device: Device
    public let created: String
    public let pads: [Pad]

    public init(id: String, name: String, preset: PadLayoutPreset, orientation: PadOrientation = .rightHanded, device: Device, created: String, pads: [Pad]) {
        format = 2; self.id = id; self.name = name; self.preset = preset; self.orientation = orientation; self.device = device; self.created = created; self.pads = pads
    }

    public init(migrating map: PadMap) {
        self.init(id: "custom-\(map.deviceUID)", name: "Layout personalizado", preset: .custom, device: .init(name: map.device, uid: map.deviceUID), created: map.created, pads: map.pads.map {
            .init(id: "r\($0.row)c\($0.column)", row: $0.row, column: $0.column, sound: $0.sound, input: .init(message: $0.message, number: $0.number, channel: $0.channel))
        })
    }

    public func validate(availableSounds: Set<String>) throws {
        guard format == 2, !id.isEmpty, !name.isEmpty, !device.name.isEmpty else { throw PadMapValidationError.emptyDevice }
        var ids = Set<String>(), positions = Set<String>(), messages = Set<String>(), roles = Set<String>()
        for pad in pads {
            guard ids.insert(pad.id).inserted else { throw PadMapValidationError.duplicatePadID(pad.id) }
            guard (0...3).contains(pad.row), (0...3).contains(pad.column) else { throw PadMapValidationError.invalidPosition(row: pad.row, column: pad.column) }
            guard availableSounds.contains(pad.sound) else { throw PadMapValidationError.unknownSound(pad.sound) }
            guard positions.insert("\(pad.row):\(pad.column)").inserted else { throw PadMapValidationError.duplicatePosition(row: pad.row, column: pad.column) }
            guard pad.input.message == "note", (0...127).contains(pad.input.number) else { throw PadMapValidationError.invalidNote(pad.input.number) }
            guard (1...16).contains(pad.input.channel) else { throw PadMapValidationError.invalidChannel(pad.input.channel) }
            guard messages.insert("\(pad.input.message):\(pad.input.number):\(pad.input.channel)").inserted else { throw PadMapValidationError.duplicateMessage(note: pad.input.number, channel: pad.input.channel) }
            if let role = pad.role { guard roles.insert(role).inserted else { throw PadMapValidationError.duplicateRole(role) } }
        }
    }

}

public struct PadMapV2Router {
    private let byInput: [PadMapV2.Pad?]
    public init(_ map: PadMapV2) {
        var inputs = Array<PadMapV2.Pad?>(repeating: nil, count: 16 * 128)
        for pad in map.pads { inputs[Self.index(note: pad.input.number, channel: pad.input.channel)] = pad }
        byInput = inputs
    }
    public func pad(for event: MIDINoteOn) -> PadMapV2.Pad? {
        guard (0...127).contains(event.note), (1...16).contains(event.channel) else { return nil }
        return byInput[Self.index(note: event.note, channel: event.channel)]
    }
    public func soundID(for event: MIDINoteOn) -> String? { pad(for: event)?.sound }
    private static func index(note: Int, channel: Int) -> Int { (channel - 1) * 128 + note }
}

public enum PadLayoutFactory {
    public static func make(_ preset: PadLayoutPreset, device: PadMapV2.Device, channel: Int = 10) -> PadMapV2 {
        let core: [(Int, Int, String, String?)] = [(0,0,"kick","kick"),(0,1,"rim",nil),(0,2,"snare","snare"),(0,3,"clap",nil),(1,0,"kick","kick_alt"),(1,1,"tom_low",nil),(1,2,"hihat_closed","hh_center"),(1,3,"snare","snare_alt"),(2,0,"hihat_closed","hh_left"),(2,1,"hihat_closed","hh_right"),(2,2,"hihat_open",nil),(2,3,"hihat_open","hh_open_alt"),(3,0,"tom_high",nil),(3,1,"crash",nil),(3,2,"crash","crash_alt"),(3,3,"ride",nil)]
        let drum: [(Int, Int, String, String?)] = [(0,0,"crash",nil),(0,1,"kick","kick_left"),(0,2,"kick","kick_right"),(0,3,"ride",nil),(1,0,"rim",nil),(1,1,"snare","snare_left"),(1,2,"snare","snare_right"),(1,3,"clap",nil),(2,0,"hihat_closed","hh_left"),(2,1,"hihat_open",nil),(2,2,"hihat_closed","hh_right"),(2,3,"ride","ride_alt"),(3,0,"tom_low",nil),(3,1,"tom_low","tom_low_alt"),(3,2,"tom_high",nil),(3,3,"crash","crash_alt")]
        let mirror: [(Int, Int, String, String?)] = [(0,0,"crash",nil),(0,1,"kick","kick_left"),(0,2,"kick","kick_right"),(0,3,"ride",nil),(1,0,"clap",nil),(1,1,"snare","snare_left"),(1,2,"snare","snare_right"),(1,3,"clap","clap_alt"),(2,0,"hihat_open",nil),(2,1,"hihat_closed","hh_left"),(2,2,"hihat_closed","hh_right"),(2,3,"hihat_open","hh_alt"),(3,0,"tom_high",nil),(3,1,"tom_low","tom_left"),(3,2,"tom_low","tom_right"),(3,3,"tom_high","tom_alt")]
        let definition = preset == .drumKit ? drum : (preset == .mirror ? mirror : core)
        let pads = definition.map { value in PadMapV2.Pad(id: "r\(value.0)c\(value.1)", row: value.0, column: value.1, sound: value.2, role: value.3, input: .init(number: 36 + value.0 * 4 + value.1, channel: min(16, max(1, channel)))) }
        let title = preset == .drumKit ? "Drum Kit" : (preset == .mirror ? "Mirror" : "xRoll Core")
        return PadMapV2(id: preset.rawValue, name: title, preset: preset, device: device, created: ISO8601DateFormatter().string(from: Date()), pads: pads)
    }

    /// Applies a visual/sound layout to pads already learned from a real
    /// controller. MIDI note and channel remain attached to their physical
    /// row/column; only the sound assigned to that pad changes.
    public static func applying(_ preset: PadLayoutPreset, to physicalMap: PadMapV2) -> PadMapV2 {
        let template = make(preset, device: physicalMap.device)
        let physicalByPosition = Dictionary(uniqueKeysWithValues: physicalMap.pads.map { ("\($0.row):\($0.column)", $0) })
        let pads = template.pads.compactMap { desired -> PadMapV2.Pad? in
            guard let physical = physicalByPosition["\(desired.row):\(desired.column)"] else { return nil }
            return .init(
                id: physical.id,
                row: physical.row,
                column: physical.column,
                sound: desired.sound,
                role: desired.role,
                input: physical.input
            )
        }
        return PadMapV2(
            id: preset.rawValue,
            name: template.name,
            preset: preset,
            device: physicalMap.device,
            created: ISO8601DateFormatter().string(from: Date()),
            pads: pads
        )
    }
}
