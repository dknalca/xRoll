import AVFoundation
import Foundation

public enum SampleAudioEngineError: LocalizedError {
    case sampleMissing(String)
    case sampleTooLong(String)
    case unableToReadSample(String)
    case soundNotLoaded(String)
    case loopNotLoaded

    public var errorDescription: String? {
        switch self {
        case .sampleMissing(let file):
            return "No existe el sample \(file)."
        case .sampleTooLong(let file):
            return "El sample \(file) supera el limite de fotogramas cargables."
        case .unableToReadSample(let file):
            return "No se puede cargar el sample \(file)."
        case .soundNotLoaded(let sound):
            return "El sonido \(sound) no esta cargado."
        case .loopNotLoaded:
            return "El loop no está cargado."
        }
    }
}

public final class SampleAudioEngine {
    private final class LoadedSound {
        let chokeGroup: String?
        let buffer: AVAudioPCMBuffer
        let voices: [AVAudioPlayerNode]
        var nextVoice = 0

        init(chokeGroup: String?, buffer: AVAudioPCMBuffer, voices: [AVAudioPlayerNode]) {
            self.chokeGroup = chokeGroup
            self.buffer = buffer
            self.voices = voices
        }
    }

    private let engine = AVAudioEngine()
    private let loopPlayer = AVAudioPlayerNode()
    private let loopTimePitch = AVAudioUnitTimePitch()
    private let voicesPerSound: Int
    private var sounds: [String: LoadedSound] = [:]
    private var loopBuffer: AVAudioPCMBuffer?
    public private(set) var loopTempo: LoopTempo?

    public init(voicesPerSound: Int = 4) {
        self.voicesPerSound = max(1, voicesPerSound)
        engine.attach(loopPlayer)
        engine.attach(loopTimePitch)
        engine.connect(loopPlayer, to: loopTimePitch, format: nil)
        engine.connect(loopTimePitch, to: engine.mainMixerNode, format: nil)
    }

    public func load(kit: KitManifest, from directory: URL) throws {
        stop()
        sounds.removeAll()

        for sound in kit.sounds {
            let url = directory.appendingPathComponent(sound.file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SampleAudioEngineError.sampleMissing(sound.file)
            }

            let file = try AVAudioFile(forReading: url)
            guard file.length <= AVAudioFramePosition(UInt32.max) else {
                throw SampleAudioEngineError.sampleTooLong(sound.file)
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw SampleAudioEngineError.unableToReadSample(sound.file)
            }
            try file.read(into: buffer)

            let voices = (0..<voicesPerSound).map { _ -> AVAudioPlayerNode in
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
                return node
            }
            sounds[sound.id] = LoadedSound(
                chokeGroup: sound.chokeGroup,
                buffer: buffer,
                voices: voices
            )
        }
    }

    public func start() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    public func stop() {
        engine.stop()
        sounds.values.flatMap(\.voices).forEach { $0.stop() }
        loopPlayer.stop()
    }

    /// Cancels preview and metronome buffers while keeping the audio engine ready
    /// for the next exercise.
    public func stopScheduledSounds() {
        sounds.values.flatMap(\.voices).forEach { $0.stop() }
    }

    public func loadLoop(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length <= AVAudioFramePosition(UInt32.max), let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SampleAudioEngineError.loopNotLoaded
        }
        try file.read(into: buffer)
        loopBuffer = buffer
        loopTempo = LoopTempoDetector.detect(url: url)
    }

    public func startLoop(atHostTime hostTime: UInt64, targetBPM: Double, volume: Float = 0.72) throws {
        guard let loopBuffer, let sourceBPM = loopTempo?.bpm, sourceBPM > 0 else { throw SampleAudioEngineError.loopNotLoaded }
        loopPlayer.stop()
        loopTimePitch.rate = Float(targetBPM / sourceBPM)
        loopPlayer.volume = min(1, max(0, volume))
        loopPlayer.scheduleBuffer(loopBuffer, at: AVAudioTime(hostTime: hostTime), options: .loops)
        loopPlayer.play(at: AVAudioTime(hostTime: hostTime))
    }

    public func stopLoop() { loopPlayer.stop() }

    public func play(soundID: String, volume: Float = 1) throws {
        guard let sound = sounds[soundID] else {
            throw SampleAudioEngineError.soundNotLoaded(soundID)
        }

        if let chokeGroup = sound.chokeGroup {
            sounds.values
                .filter { $0.chokeGroup == chokeGroup }
                .flatMap(\.voices)
                .forEach { $0.stop() }
        }

        let voice = sound.voices[sound.nextVoice]
        sound.nextVoice = (sound.nextVoice + 1) % sound.voices.count
        voice.volume = min(1, max(0, volume))
        voice.scheduleBuffer(sound.buffer, at: nil, options: [])
        if !voice.isPlaying { voice.play() }
    }

    public func schedule(soundID: String, atHostTime hostTime: UInt64, volume: Float = 1) throws {
        guard let sound = sounds[soundID] else {
            throw SampleAudioEngineError.soundNotLoaded(soundID)
        }

        let voice = sound.voices[sound.nextVoice]
        sound.nextVoice = (sound.nextVoice + 1) % sound.voices.count
        voice.volume = min(1, max(0, volume))
        voice.scheduleBuffer(sound.buffer, at: AVAudioTime(hostTime: hostTime), options: [])
        if !voice.isPlaying { voice.play() }
    }
}
