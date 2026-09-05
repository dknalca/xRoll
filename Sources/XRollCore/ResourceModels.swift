import Foundation

public enum ResourceValidationError: LocalizedError, Equatable {
    case unsupportedFormat(Int)
    case emptyIdentifier(String)
    case duplicateSound(String)
    case unknownSound(String)
    case invalidMeter([Int])
    case invalidGrid(Int)
    case invalidStep(Int)
    case duplicateNote(step: Int, sound: String)
    case invalidHand(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Formato no compatible: \(format)."
        case .emptyIdentifier(let name):
            return "Falta el identificador \(name)."
        case .duplicateSound(let sound):
            return "El sonido \(sound) aparece mas de una vez."
        case .unknownSound(let sound):
            return "El sonido \(sound) no existe en el kit."
        case .invalidMeter(let meter):
            return "El compas \(meter) no es 4/4."
        case .invalidGrid(let grid):
            return "La rejilla \(grid) no es valida."
        case .invalidStep(let step):
            return "El paso \(step) queda fuera del ejercicio."
        case .duplicateNote(let step, let sound):
            return "La nota \(sound) se repite en el paso \(step)."
        case .invalidHand(let hand):
            return "La mano \(hand) no es valida."
        }
    }
}

public struct KitManifest: Codable, Equatable {
    public struct Sound: Codable, Equatable {
        public let id: String
        public let label: String
        public let file: String
        public let gmNote: Int
        public let chokeGroup: String?

        enum CodingKeys: String, CodingKey {
            case id, label, file
            case gmNote = "gm_note"
            case chokeGroup = "choke_group"
        }
    }

    public let format: Int
    public let id: String
    public let name: String
    public let sounds: [Sound]

    public func validate() throws {
        guard format == 1 else { throw ResourceValidationError.unsupportedFormat(format) }
        guard !id.isEmpty else { throw ResourceValidationError.emptyIdentifier("id del kit") }

        var identifiers = Set<String>()
        for sound in sounds {
            guard !sound.id.isEmpty else { throw ResourceValidationError.emptyIdentifier("id de sonido") }
            guard identifiers.insert(sound.id).inserted else {
                throw ResourceValidationError.duplicateSound(sound.id)
            }
        }
    }
}

public struct Exercise: Codable, Equatable {
    public struct Note: Codable, Equatable {
        public let step: Int
        public let sound: String
        public let hand: String?
    }

    public let format: Int
    public let id: String
    public let title: String
    public let family: String
    public let level: Int
    public let bpm: Int
    public let meter: [Int]
    public let bars: Int
    public let grid: Int
    public let repeats: Int
    public let kit: String
    public let loop: String?
    public let offset: Int
    public let notes: [Note]

    public func validate(availableSounds: Set<String>) throws {
        guard format == 1 else { throw ResourceValidationError.unsupportedFormat(format) }
        guard !id.isEmpty else { throw ResourceValidationError.emptyIdentifier("id del ejercicio") }
        guard meter == [4, 4] else { throw ResourceValidationError.invalidMeter(meter) }
        guard bars > 0, grid > 0, repeats > 0, bpm > 0 else {
            throw ResourceValidationError.invalidGrid(grid)
        }

        let totalSteps = bars * grid
        var seenNotes = Set<String>()
        for note in notes {
            guard availableSounds.contains(note.sound) else {
                throw ResourceValidationError.unknownSound(note.sound)
            }
            guard (0..<totalSteps).contains(note.step) else {
                throw ResourceValidationError.invalidStep(note.step)
            }
            if let hand = note.hand, hand != "L" && hand != "R" {
                throw ResourceValidationError.invalidHand(hand)
            }
            let key = "\(note.step):\(note.sound)"
            guard seenNotes.insert(key).inserted else {
                throw ResourceValidationError.duplicateNote(step: note.step, sound: note.sound)
            }
        }
    }
}

public struct ResourceCatalog {
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default, decoder: JSONDecoder = JSONDecoder()) {
        self.fileManager = fileManager
        self.decoder = decoder
    }

    public func loadKit(at url: URL) throws -> KitManifest {
        let kit = try decoder.decode(KitManifest.self, from: Data(contentsOf: url))
        try kit.validate()
        return kit
    }

    public func loadExercises(in directory: URL, kit: KitManifest) throws -> [Exercise] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let availableSounds = Set(kit.sounds.map(\.id))
        let exercises = try urls.map { url -> Exercise in
            let exercise = try decoder.decode(Exercise.self, from: Data(contentsOf: url))
            try exercise.validate(availableSounds: availableSounds)
            guard exercise.kit == kit.id else {
                throw ResourceValidationError.emptyIdentifier("kit incorrecto en \(url.lastPathComponent)")
            }
            return exercise
        }

        let levels = exercises.map(\.level).sorted()
        guard levels == Array(1...exercises.count) else {
            throw ResourceValidationError.emptyIdentifier("niveles consecutivos de ejercicios")
        }
        return exercises
    }

    public func missingSampleFiles(for kit: KitManifest, in directory: URL) -> [String] {
        kit.sounds.map(\.file).filter { !fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }
}

