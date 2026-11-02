import Foundation

public struct KitNoteRouter: Equatable {
    private let soundByNote: [Int: String]

    public init(kit: KitManifest) {
        var sounds = [Int: String]()
        for sound in kit.sounds where (0...127).contains(sound.gmNote) {
            sounds[sound.gmNote] = sound.id
        }
        soundByNote = sounds
    }

    public func soundID(for note: Int) -> String? {
        soundByNote[note]
    }

    public func soundID(for event: MIDINoteOn) -> String? {
        soundID(for: event.note)
    }
}
