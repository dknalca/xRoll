import Foundation

public struct KitNoteRouter: Equatable {
    private let soundByNote: [Int: String]

    public init(kit: KitManifest) {
        soundByNote = Dictionary(
            uniqueKeysWithValues: kit.sounds.map { ($0.gmNote, $0.id) }
        )
    }

    public func soundID(for note: Int) -> String? {
        soundByNote[note]
    }

    public func soundID(for event: MIDINoteOn) -> String? {
        soundID(for: event.note)
    }
}
