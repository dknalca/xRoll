import Foundation

public enum PadMapValidationError: LocalizedError, Equatable {
    case unsupportedFormat(Int)
    case emptyDevice
    case invalidChannel(Int)
    case invalidNote(Int)
    case invalidPosition(row: Int, column: Int)
    case unknownSound(String)
    case duplicateSound(String)
    case duplicatePosition(row: Int, column: Int)
    case duplicateMessage(note: Int, channel: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format): return "Formato de mapa no compatible: \(format)."
        case .emptyDevice: return "El mapa no indica el dispositivo."
        case .invalidChannel(let channel): return "El canal MIDI \(channel) no es valido."
        case .invalidNote(let note): return "La nota MIDI \(note) no es valida."
        case .invalidPosition(let row, let column): return "La posicion \(row),\(column) queda fuera de la rejilla."
        case .unknownSound(let sound): return "El sonido \(sound) no existe en el kit."
        case .duplicateSound(let sound): return "El sonido \(sound) aparece mas de una vez."
        case .duplicatePosition(let row, let column): return "La posicion \(row),\(column) aparece mas de una vez."
        case .duplicateMessage(let note, let channel): return "La nota \(note) del canal \(channel) aparece mas de una vez."
        }
    }
}

public struct PadMap: Codable, Equatable {
    public struct Pad: Codable, Equatable {
        public let sound: String
        public let message: String
        public let number: Int
        public let channel: Int
        public let row: Int
        public let column: Int

        public init(sound: String, message: String = "note", number: Int, channel: Int, row: Int, column: Int) {
            self.sound = sound
            self.message = message
            self.number = number
            self.channel = channel
            self.row = row
            self.column = column
        }
    }

    public let format: Int
    public let device: String
    public let deviceUID: Int
    public let created: String
    public let pads: [Pad]

    enum CodingKeys: String, CodingKey {
        case format, device, pads, created
        case deviceUID = "device_uid"
    }

    public init(format: Int = 1, device: String, deviceUID: Int, created: String, pads: [Pad]) {
        self.format = format
        self.device = device
        self.deviceUID = deviceUID
        self.created = created
        self.pads = pads
    }

    public func validate(availableSounds: Set<String>) throws {
        guard format == 1 else { throw PadMapValidationError.unsupportedFormat(format) }
        guard !device.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PadMapValidationError.emptyDevice
        }

        var sounds = Set<String>()
        var positions = Set<String>()
        var messages = Set<String>()
        for pad in pads {
            guard pad.message == "note" else { throw PadMapValidationError.invalidNote(pad.number) }
            guard (0...127).contains(pad.number) else { throw PadMapValidationError.invalidNote(pad.number) }
            guard (1...16).contains(pad.channel) else { throw PadMapValidationError.invalidChannel(pad.channel) }
            guard (0...3).contains(pad.row), (0...3).contains(pad.column) else {
                throw PadMapValidationError.invalidPosition(row: pad.row, column: pad.column)
            }
            guard availableSounds.contains(pad.sound) else { throw PadMapValidationError.unknownSound(pad.sound) }
            guard sounds.insert(pad.sound).inserted else { throw PadMapValidationError.duplicateSound(pad.sound) }
            guard positions.insert("\(pad.row):\(pad.column)").inserted else {
                throw PadMapValidationError.duplicatePosition(row: pad.row, column: pad.column)
            }
            guard messages.insert("\(pad.number):\(pad.channel)").inserted else {
                throw PadMapValidationError.duplicateMessage(note: pad.number, channel: pad.channel)
            }
        }
    }
}

public struct PadMapRouter {
    private let soundByNoteAndChannel: [String: String]

    public init(padMap: PadMap) {
        soundByNoteAndChannel = Dictionary(
            uniqueKeysWithValues: padMap.pads.map { ("\($0.number):\($0.channel)", $0.sound) }
        )
    }

    public func soundID(for event: MIDINoteOn) -> String? {
        soundByNoteAndChannel["\(event.note):\(event.channel)"]
    }
}

public enum PadMapStore {
    public static func load(at url: URL, availableSounds: Set<String>) throws -> PadMap {
        let padMap = try JSONDecoder().decode(PadMap.self, from: Data(contentsOf: url))
        try padMap.validate(availableSounds: availableSounds)
        return padMap
    }

    public static func save(_ padMap: PadMap, to url: URL, availableSounds: Set<String>) throws {
        try padMap.validate(availableSounds: availableSounds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(padMap).write(to: url, options: .atomic)
    }
}
