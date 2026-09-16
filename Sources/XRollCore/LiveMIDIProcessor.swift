import Foundation

/// Resultado de una entrada MIDI ya resuelta y reproducida. La interfaz puede
/// consumirlo después sin retrasar el sonido.
public struct LiveMIDIHit: Equatable {
    public let soundID: String
    public let role: String?
    public let padID: String?
    public let row: Int?
    public let column: Int?

    public init(soundID: String, role: String? = nil, padID: String? = nil, row: Int? = nil, column: Int? = nil) {
        self.soundID = soundID
        self.role = role
        self.padID = padID
        self.row = row
        self.column = column
    }
}

/// Mantiene la ruta MIDI-audio separada de la interfaz. El router se puede
/// reemplazar al cambiar de layout sin detener la entrega de notas.
public final class LiveMIDIProcessor {
    private let lock = NSLock()
    private let audio: SampleAudioEngine
    private let kitRouter: KitNoteRouter
    private var padRouter: PadMapV2Router?

    public init(audio: SampleAudioEngine, kitRouter: KitNoteRouter, padRouter: PadMapV2Router? = nil) {
        self.audio = audio
        self.kitRouter = kitRouter
        self.padRouter = padRouter
    }

    public func setPadRouter(_ router: PadMapV2Router?) {
        lock.lock()
        padRouter = router
        lock.unlock()
    }

    public func process(_ event: MIDINoteOn) throws -> LiveMIDIHit? {
        lock.lock()
        let pad = padRouter?.pad(for: event)
        let soundID = pad?.sound ?? kitRouter.soundID(for: event)
        lock.unlock()

        guard let soundID else { return nil }
        try audio.play(soundID: soundID)
        return LiveMIDIHit(soundID: soundID, role: pad?.role, padID: pad?.id, row: pad?.row, column: pad?.column)
    }
}
