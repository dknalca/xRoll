import AVFoundation
import AudioToolbox
import Foundation

public enum SampleAudioEngineError: LocalizedError {
    case sampleMissing(String)
    case sampleTooLong(String)
    case unableToReadSample(String)
    case soundNotLoaded(String)
    case loopNotLoaded
    case unableToSelectOutputDevice(OSStatus)

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
        case .unableToSelectOutputDevice(let status):
            return "No se pudo seleccionar la salida de audio (\(status))."
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
    private let metronomePlayer = AVAudioPlayerNode()
    private let metronomeTimePitch = AVAudioUnitTimePitch()
    private let voicesPerSound: Int
    private var sounds: [String: LoadedSound] = [:]
    private var soundGains: [String: Float] = [:]
    private var loopBuffer: AVAudioPCMBuffer?
    private var metronomeBuffer: AVAudioPCMBuffer?
    public private(set) var loopTempo: LoopTempo?
    public private(set) var metronomeSourceName: String?

    // A bounded pool prevents long cymbal tails from making the mixer process
    // hundreds of simultaneous nodes. Once full, play() steals immediately;
    // a fresh hit must never wait behind an old tail.
    public init(voicesPerSound: Int = 6) {
        self.voicesPerSound = max(4, voicesPerSound)
        engine.attach(loopPlayer)
        engine.attach(loopTimePitch)
        engine.attach(metronomePlayer)
        engine.attach(metronomeTimePitch)
        engine.connect(loopPlayer, to: loopTimePitch, format: nil)
        engine.connect(loopTimePitch, to: engine.mainMixerNode, format: nil)
        engine.connect(metronomePlayer, to: metronomeTimePitch, format: nil)
        engine.connect(metronomeTimePitch, to: engine.mainMixerNode, format: nil)
    }

    public func load(kit: KitManifest, from directory: URL) throws {
        stop()
        sounds.removeAll()
        soundGains.removeAll()

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
            normalizePeak(buffer)

            // Cymbals sustain for 10–12 seconds and deserve a little more
            // overlap. Keeping this pool small is intentional: a finger roll
            // should replace an old tail, never create a delayed audio queue.
            let voiceCount = ["crash", "ride"].contains(sound.id) ? voicesPerSound : min(4, voicesPerSound)
            let voices = (0..<voiceCount).map { _ -> AVAudioPlayerNode in
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

    public func setOutputDevice(_ deviceID: AudioDeviceID) throws {
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw SampleAudioEngineError.unableToSelectOutputDevice(-1)
        }
        var selectedDevice = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDevice,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw SampleAudioEngineError.unableToSelectOutputDevice(status) }
        if wasRunning { try engine.start() }
    }

    public func stop() {
        engine.stop()
        sounds.values.flatMap(\.voices).forEach { $0.stop() }
        loopPlayer.stop()
        metronomePlayer.stop()
    }

    /// Cancels preview and metronome buffers while keeping the audio engine ready
    /// for the next exercise.
    public func stopScheduledSounds() {
        sounds.values.flatMap(\.voices).forEach { $0.stop() }
        metronomePlayer.stop()
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

    /// Loads a dedicated click. If absent, scheduleMetronome keeps the kit
    /// fallback so an old project remains usable.
    public func loadMetronome(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length <= AVAudioFramePosition(UInt32.max), let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SampleAudioEngineError.unableToReadSample(url.lastPathComponent)
        }
        try file.read(into: buffer)
        metronomeBuffer = buffer
        metronomeSourceName = url.lastPathComponent
    }

    public func previewMetronome(volume: Float = 1, pitchCents: Float = 0) throws {
        guard let buffer = metronomeBuffer ?? sounds["clap"]?.buffer else {
            throw SampleAudioEngineError.soundNotLoaded("metrónomo")
        }
        metronomePlayer.stop()
        metronomeTimePitch.pitch = min(1_200, max(-1_200, pitchCents))
        metronomePlayer.volume = min(1, max(0, volume))
        metronomePlayer.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        metronomePlayer.play()
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

    /// El volumen por sonido se guarda fuera del WAV: todos los samples se
    /// normalizan a un pico común al cargar y esta ganancia permite equilibrar
    /// el kit sin modificar archivos del usuario.
    public func setSoundVolume(_ volume: Float, for soundID: String) {
        soundGains[soundID] = min(1.5, max(0, volume))
    }

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

        // A node queues a buffer if it is already playing, which makes rapid
        // hits feel swallowed by long crash/tom tails. Prefer an idle voice;
        // if all are busy, steal the oldest round-robin voice so the new hit is
        // always immediate.
        let voice = sound.voices.first(where: { !$0.isPlaying }) ?? sound.voices[sound.nextVoice]
        if voice.isPlaying { voice.stop() }
        sound.nextVoice = (sound.nextVoice + 1) % sound.voices.count
        voice.volume = effectiveVolume(for: soundID, requested: volume)
        // .interrupts is the critical live-input rule. AVAudioPlayerNode may
        // otherwise append a buffer behind a tail on some CoreAudio devices;
        // that produces a burst of late hits. A pad hit always wins over a
        // previous tail on this voice.
        voice.scheduleBuffer(sound.buffer, at: nil, options: [.interrupts])
        // Calling play after schedule is intentional even after stealing a
        // voice: it removes a race between stop() and isPlaying on bursts.
        voice.play()
    }

    public func schedule(soundID: String, atHostTime hostTime: UInt64, volume: Float = 1) throws {
        guard let sound = sounds[soundID] else {
            throw SampleAudioEngineError.soundNotLoaded(soundID)
        }

        let voice = sound.voices[sound.nextVoice]
        sound.nextVoice = (sound.nextVoice + 1) % sound.voices.count
        voice.volume = effectiveVolume(for: soundID, requested: volume)
        voice.scheduleBuffer(sound.buffer, at: AVAudioTime(hostTime: hostTime), options: [])
        if !voice.isPlaying { voice.play() }
    }

    /// Schedules the click through its own pitch unit so the metronome can be
    /// tuned without transposing drum pads or the accompaniment.
    public func scheduleMetronome(soundID: String, atHostTime hostTime: UInt64, volume: Float = 1, pitchCents: Float = 0) throws {
        guard let buffer = metronomeBuffer ?? sounds[soundID]?.buffer else {
            throw SampleAudioEngineError.soundNotLoaded(soundID)
        }
        metronomeTimePitch.pitch = min(1_200, max(-1_200, pitchCents))
        metronomePlayer.volume = min(1, max(0, volume))
        metronomePlayer.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: [])
        if !metronomePlayer.isPlaying { metronomePlayer.play() }
    }

    private func effectiveVolume(for soundID: String, requested: Float) -> Float {
        min(1.5, max(0, requested) * (soundGains[soundID] ?? 1))
    }

    /// Igualamos el pico de cada WAV a -1 dBFS al cargarlo. Es reversible en
    /// memoria, no altera los archivos del kit, y evita que un crash o tom
    /// grabado más bajo obligue a tocar más fuerte que el resto del kit.
    private func normalizePeak(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channels[channel][frame])) }
        }
        guard peak > 0.000_1 else { return }
        let gain = min(8, 0.891_251 / peak) // -1 dBFS; evita ganancias absurdas en silencio.
        guard gain != 1 else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) { channels[channel][frame] *= gain }
        }
    }
}
