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

/// Un cerrojo serializa la configuración y los golpes vivos. El render sigue
/// ocurriendo en Core Audio, fuera de la cola de entrega MIDI y de la interfaz.
public final class SampleAudioEngine {
    static func scheduledSegmentFrameCount(sampleFrameCount: AVAudioFrameCount, sampleRate: Double,
                                           startHostTime: UInt64, chokeHostTime: UInt64) -> AVAudioFrameCount {
        guard sampleRate.isFinite, sampleRate > 0, chokeHostTime > startHostTime else { return 0 }
        let interval = AudioClock.milliseconds(from: startHostTime, to: chokeHostTime)
        let framesUntilChoke = floor(interval * sampleRate / 1_000)
        guard framesUntilChoke.isFinite, framesUntilChoke > 0 else { return 0 }
        return AVAudioFrameCount(min(Double(sampleFrameCount), framesUntilChoke))
    }

    static func scheduledChokeKey(soundID: String, chokeGroup: String?) -> String {
        if let chokeGroup { return "group:\(chokeGroup)" }
        return "sound:\(soundID)"
    }

    static func usesDirectMetronome(pitchCents: Float) -> Bool {
        abs(pitchCents) < 0.5
    }

    private struct PendingChokeHit {
        let soundID: String
        let hostTime: UInt64
        let volume: Float
    }

    private struct ActiveLiveVoice {
        let soundID: String
        let node: AVAudioPlayerNode
        let renderedFramesAtAdmission: AVAudioFramePosition

        var hasRenderedAttack: Bool {
            guard let time = node.lastRenderTime, time.isSampleTimeValid || time.isHostTimeValid,
                  let playerTime = node.playerTime(forNodeTime: time), playerTime.isSampleTimeValid else { return false }
            return playerTime.sampleTime > renderedFramesAtAdmission
        }
    }

    private struct PreparedBufferKey: Hashable {
        let source: ObjectIdentifier
        let frameCount: AVAudioFrameCount
        let gain: Float
    }

    private struct CachedBuffer {
        let buffer: AVAudioPCMBuffer
        let byteCount: Int
    }

    private final class LoadedSound {
        let chokeKey: String
        let buffer: AVAudioPCMBuffer
        let liveVoices: [AVAudioPlayerNode]
        let scheduledVoices: [AVAudioPlayerNode]
        var nextLiveVoice = 0
        var nextScheduledVoice = 0

        init(chokeKey: String, buffer: AVAudioPCMBuffer, liveVoices: [AVAudioPlayerNode], scheduledVoices: [AVAudioPlayerNode]) {
            self.chokeKey = chokeKey
            self.buffer = buffer
            self.liveVoices = liveVoices
            self.scheduledVoices = scheduledVoices
        }
    }

    private let engine: AVAudioEngine
    private let scheduledTime: (UInt64) -> AVAudioTime
    private let controlLock = NSRecursiveLock()
    private let loopPlayer = AVAudioPlayerNode()
    private let loopTimePitch = AVAudioUnitTimePitch()
    private let metronomePlayer = AVAudioPlayerNode()
    private let directMetronomePlayer = AVAudioPlayerNode()
    private let metronomeTimePitch = AVAudioUnitTimePitch()
    private let latencyClickPlayer = AVAudioPlayerNode()
    private let voicesPerSound: Int
    private var sounds: [String: LoadedSound] = [:]
    private var pendingScheduledChokeHits = [String: PendingChokeHit]()
    private var activeLiveVoices: [String: ActiveLiveVoice] = [:]
    private var samplePlayers: [AVAudioPlayerNode] = []
    private var soundGains: [String: Float] = [:]
    private var preparedBuffers: [PreparedBufferKey: CachedBuffer] = [:]
    private var preparedBufferOrder: [PreparedBufferKey] = []
    private var preparedBufferBytes = 0
    private var preparedBufferHits = 0
    private var preparedBufferMisses = 0
    private let maximumPreparedBufferBytes = 4 * 1_024 * 1_024
    private let maximumPreparedBufferCount = 64
    private var loopBuffer: AVAudioPCMBuffer?
    private var metronomeBuffer: AVAudioPCMBuffer?
    private var metronomeAccentBuffer: AVAudioPCMBuffer?
    private var latencyClickBuffer: AVAudioPCMBuffer?
    public private(set) var loopTempo: LoopTempo?
    public private(set) var metronomeSourceName: String?

    /// Pools independientes y acotados para golpes vivos y notas futuras.
    public convenience init(voicesPerSound: Int = 6) {
        self.init(engine: AVAudioEngine(), voicesPerSound: voicesPerSound)
    }

    // Permite verificar el audio con renderizado manual, sin salida física.
    init(engine: AVAudioEngine, voicesPerSound: Int = 6,
         scheduledTime: @escaping (UInt64) -> AVAudioTime = { AVAudioTime(hostTime: $0) }) {
        self.engine = engine
        self.scheduledTime = scheduledTime
        self.voicesPerSound = max(4, voicesPerSound)
        engine.attach(loopPlayer)
        engine.attach(loopTimePitch)
        engine.attach(metronomePlayer)
        engine.attach(directMetronomePlayer)
        engine.attach(metronomeTimePitch)
        engine.attach(latencyClickPlayer)
        engine.connect(loopPlayer, to: loopTimePitch, format: nil)
        engine.connect(loopTimePitch, to: engine.mainMixerNode, format: nil)
        engine.connect(metronomePlayer, to: metronomeTimePitch, format: nil)
        engine.connect(metronomeTimePitch, to: engine.mainMixerNode, format: nil)
        engine.connect(directMetronomePlayer, to: engine.mainMixerNode, format: nil)
        engine.connect(latencyClickPlayer, to: engine.mainMixerNode, format: nil)
    }

    public func load(kit: KitManifest, from directory: URL) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        stop()
        samplePlayers.forEach { engine.detach($0) }
        samplePlayers.removeAll()
        sounds.removeAll()
        activeLiveVoices.removeAll()
        soundGains.removeAll()
        clearPreparedBuffers()

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

            // Las voces programadas tienen un pool acotado; los sonidos largos
            // conservan más nodos sin dejar que un re-disparo acumule colas.
            let voiceCount = ["crash", "ride"].contains(sound.id) ? voicesPerSound : min(4, voicesPerSound)
            // Un pool pequeño de voces vivas permite golpes muy rápidos sobre el
            // mismo sonido sin reciclar el mismo nodo en la misma llamada.
            let liveVoiceCount = min(4, voicesPerSound)
            let liveVoices = (0..<liveVoiceCount).map { _ -> AVAudioPlayerNode in
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
                samplePlayers.append(node)
                return node
            }
            // Las voces programadas son independientes de las voces MIDI en vivo.
            let scheduledVoices = (0..<voiceCount).map { _ -> AVAudioPlayerNode in
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
                samplePlayers.append(node)
                return node
            }
            let loadedSound = LoadedSound(
                chokeKey: Self.scheduledChokeKey(soundID: sound.id, chokeGroup: sound.chokeGroup),
                buffer: buffer,
                liveVoices: liveVoices,
                scheduledVoices: scheduledVoices
            )
            sounds[sound.id] = loadedSound
        }

        guard let metronomeFormat = sounds["hihat_closed"]?.buffer.format ?? sounds.values.first?.buffer.format,
              let regularClick = makeMetronomeClick(format: metronomeFormat, frequency: 1_450),
              let accentedClick = makeMetronomeClick(format: metronomeFormat, frequency: 2_050) else {
            throw SampleAudioEngineError.unableToReadSample("claqueta sintetizada")
        }
        metronomeBuffer = regularClick
        metronomeAccentBuffer = accentedClick
        connectMetronome(format: metronomeFormat)
        metronomeSourceName = "claqueta sintetizada"
    }

    public func start() throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard !engine.isRunning else { return }
        try engine.start()
    }

    #if os(macOS)
    public func setOutputDevice(_ deviceID: AudioDeviceID) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        do {
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
        } catch {
            if wasRunning { try? engine.start() }
            throw error
        }
    }
    #endif

    public func stop() {
        controlLock.lock()
        defer { controlLock.unlock() }
        engine.stop()
        sounds.values.flatMap(\.liveVoices).forEach { $0.stop() }
        activeLiveVoices.removeAll()
        sounds.values.flatMap(\.scheduledVoices).forEach { $0.stop() }
        pendingScheduledChokeHits.removeAll()
        loopPlayer.stop()
        metronomePlayer.stop()
        directMetronomePlayer.stop()
    }

    /// Cancela solo notas programadas; los golpes vivos siguen disponibles.
    public func stopScheduledSounds() {
        controlLock.lock()
        defer { controlLock.unlock() }
        sounds.values.flatMap(\.scheduledVoices).forEach { $0.stop() }
        pendingScheduledChokeHits.removeAll()
        metronomePlayer.stop()
        directMetronomePlayer.stop()
    }

    public func loadLoop(url: URL) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        let file = try AVAudioFile(forReading: url)
        guard file.length <= AVAudioFramePosition(UInt32.max), let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SampleAudioEngineError.loopNotLoaded
        }
        try file.read(into: buffer)
        loopBuffer = buffer
        loopTempo = LoopTempoDetector.detect(url: url)
    }

    /// Replaces the synthesized click with an optional custom click sample.
    public func loadMetronome(url: URL) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        let file = try AVAudioFile(forReading: url)
        guard file.length <= AVAudioFramePosition(UInt32.max), let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SampleAudioEngineError.unableToReadSample(url.lastPathComponent)
        }
        try file.read(into: buffer)
        metronomeBuffer = buffer
        metronomeAccentBuffer = buffer
        metronomeSourceName = url.lastPathComponent
        connectMetronome(format: buffer.format)
        clearPreparedBuffers()
    }

    private func connectMetronome(format: AVAudioFormat) {
        metronomePlayer.stop()
        directMetronomePlayer.stop()
        engine.connect(metronomePlayer, to: metronomeTimePitch, format: format)
        engine.connect(metronomeTimePitch, to: engine.mainMixerNode, format: format)
        engine.connect(directMetronomePlayer, to: engine.mainMixerNode, format: format)
    }

    public func previewMetronome(volume: Float = 1, pitchCents: Float = 0) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard let buffer = metronomeBuffer else {
            throw SampleAudioEngineError.soundNotLoaded("metrónomo")
        }
        let usesDirect = Self.usesDirectMetronome(pitchCents: pitchCents)
        let player = usesDirect ? directMetronomePlayer : metronomePlayer
        metronomePlayer.stop()
        directMetronomePlayer.stop()
        if !usesDirect { metronomeTimePitch.pitch = min(2_400, max(-2_400, pitchCents)) }
        player.volume = min(1, max(0, volume))
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        player.play()
    }

    public func startLoop(atHostTime hostTime: UInt64, targetBPM: Double, volume: Float = 0.72) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard let loopBuffer, let sourceBPM = loopTempo?.bpm, sourceBPM > 0 else { throw SampleAudioEngineError.loopNotLoaded }
        loopPlayer.stop()
        loopTimePitch.rate = Float(targetBPM / sourceBPM)
        loopPlayer.volume = min(1, max(0, volume))
        loopPlayer.scheduleBuffer(loopBuffer, at: AVAudioTime(hostTime: hostTime), options: .loops)
        loopPlayer.play(at: AVAudioTime(hostTime: hostTime))
    }

    public func stopLoop() {
        controlLock.lock()
        defer { controlLock.unlock() }
        loopPlayer.stop()
    }

    /// El volumen por sonido se guarda fuera del WAV: todos los samples se
    /// normalizan a un pico común al cargar y esta ganancia permite equilibrar
    /// el kit sin modificar archivos del usuario.
    public func setSoundVolume(_ volume: Float, for soundID: String) {
        controlLock.lock()
        defer { controlLock.unlock() }
        soundGains[soundID] = min(1.5, max(0, volume))
    }

    public func play(soundID: String, volume: Float = 1) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard let sound = sounds[soundID] else {
            throw SampleAudioEngineError.soundNotLoaded(soundID)
        }

        // Rotar separa el nodo que cortamos del que recibe el nuevo ataque.
        // .interrupts impide encolar el golpe detrás de una cola anterior.
        let voice = sound.liveVoices[sound.nextLiveVoice]
        sound.nextLiveVoice = (sound.nextLiveVoice + 1) % sound.liveVoices.count
        let chokeKey = sound.chokeKey
        // Solo se corta una cola que ya ha empezado a renderizarse. Dos golpes
        // admitidos en el mismo quantum (p. ej. un lote MIDI) no deben cancelar
        // el ataque anterior antes de que Core Audio lo haya consumido.
        if let previous = activeLiveVoices[chokeKey], previous.node !== voice,
           previous.node.isPlaying, previous.soundID != soundID || previous.hasRenderedAttack {
            previous.node.stop()
        }

        let renderedFrames = voice.isPlaying
            ? voice.lastRenderTime.flatMap { time -> AVAudioTime? in
                guard time.isSampleTimeValid || time.isHostTimeValid else { return nil }
                return voice.playerTime(forNodeTime: time)
            }?.sampleTime ?? 0
            : 0
        activeLiveVoices[chokeKey] = ActiveLiveVoice(soundID: soundID, node: voice, renderedFramesAtAdmission: renderedFrames)

        voice.volume = effectiveVolume(for: soundID, requested: volume)
        voice.scheduleBuffer(sound.buffer, at: nil, options: [.interrupts])
        if !voice.isPlaying { voice.play() }
    }

    /// Prepara una señal de diagnóstico de 3,5 kHz fuera de la ruta MIDI. Se
    /// conecta directamente al mixer para no medir la latencia de TimePitch.
    public func prepareLatencyClick() throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = max(44_100, format.sampleRate)
        guard format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * 0.006)),
              let channels = buffer.floatChannelData else {
            throw SampleAudioEngineError.unableToReadSample("click de latencia")
        }
        buffer.frameLength = buffer.frameCapacity
        let count = Int(buffer.frameLength)
        for index in 0..<count {
            let envelope = Float(1 - Double(index) / Double(max(1, count - 1)))
            let sample = sin(Float(2 * Double.pi * 3_500 * Double(index) / sampleRate)) * envelope
            for channel in 0..<Int(format.channelCount) { channels[channel][index] = sample }
        }
        latencyClickBuffer = buffer
    }

    public func playLatencyClick() throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard let latencyClickBuffer else { throw SampleAudioEngineError.soundNotLoaded("click de latencia") }
        latencyClickPlayer.stop()
        latencyClickPlayer.scheduleBuffer(latencyClickBuffer, at: nil, options: [.interrupts])
        latencyClickPlayer.play()
    }

    public func schedule(soundID: String, atHostTime hostTime: UInt64, volume: Float = 1) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard let sound = sounds[soundID] else {
            throw SampleAudioEngineError.soundNotLoaded(soundID)
        }

        let chokeKey = sound.chokeKey
        if let previous = pendingScheduledChokeHits[chokeKey] {
            // El evento está en el futuro: recortamos su buffer hasta la
            // siguiente repetición del sonido o golpe del grupo de choke.
            try schedule(previous, stoppingAtHostTime: hostTime)
        }
        // La ganancia pertenece al evento, no al nodo reutilizado por otros
        // golpes futuros. Se congela también la mezcla vigente al admitirlo.
        pendingScheduledChokeHits[chokeKey] = PendingChokeHit(soundID: soundID, hostTime: hostTime,
            volume: effectiveVolume(for: soundID, requested: volume))
    }

    /// Completa las voces pendientes después de añadir el patrón entero. Se usa
    /// antes de que empiece la reproducción, no a mitad de sesión.
    public func flushScheduledSounds() throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        let pending = pendingScheduledChokeHits.values.sorted { $0.hostTime < $1.hostTime }
        pendingScheduledChokeHits.removeAll()
        for hit in pending {
            try scheduleUnchoked(soundID: hit.soundID, atHostTime: hit.hostTime, volume: hit.volume)
        }
    }

    private func schedule(_ hit: PendingChokeHit, stoppingAtHostTime chokeHostTime: UInt64) throws {
        guard let sound = sounds[hit.soundID] else { throw SampleAudioEngineError.soundNotLoaded(hit.soundID) }
        let frameCount = Self.scheduledSegmentFrameCount(
            sampleFrameCount: sound.buffer.frameLength,
            sampleRate: sound.buffer.format.sampleRate,
            startHostTime: hit.hostTime,
            chokeHostTime: chokeHostTime
        )
        guard frameCount > 0 else { return }
        let voice = sound.scheduledVoices[sound.nextScheduledVoice]
        sound.nextScheduledVoice = (sound.nextScheduledVoice + 1) % sound.scheduledVoices.count
        let buffer = try preparedBuffer(from: sound.buffer, frameCount: frameCount, gain: hit.volume)
        voice.scheduleBuffer(buffer, at: scheduledTime(hit.hostTime), options: [])
        if !voice.isPlaying { voice.play() }
    }

    /// Copia un prefijo corto del sample. La nota queda programada en su host
    /// time y su cola termina justo antes del siguiente golpe del choke group.
    /// Así el scheduling por adelantado respeta el mismo choke que `play()`.
    private func preparedBuffer(from source: AVAudioPCMBuffer, frameCount: AVAudioFrameCount, gain: Float) throws -> AVAudioPCMBuffer {
        guard frameCount > 0 else { throw SampleAudioEngineError.unableToReadSample("segmento de choke") }
        if frameCount == source.frameLength, gain == 1 { return source }
        let key = PreparedBufferKey(source: ObjectIdentifier(source), frameCount: frameCount, gain: gain)
        if let cached = preparedBuffers[key] {
            preparedBufferHits += 1
            preparedBufferOrder.removeAll { $0 == key }
            preparedBufferOrder.append(key)
            return cached.buffer
        }
        preparedBufferMisses += 1
        guard let trimmed = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frameCount) else {
            throw SampleAudioEngineError.unableToReadSample("segmento de choke")
        }
        trimmed.frameLength = frameCount
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(trimmed.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else {
            throw SampleAudioEngineError.unableToReadSample("segmento de choke")
        }
        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData, let destination = destinationBuffers[index].mData,
                  source.frameLength > 0 else {
                throw SampleAudioEngineError.unableToReadSample("segmento de choke")
            }
            let bytesPerFrame = sourceBuffers[index].mDataByteSize / source.frameLength
            memcpy(destination, sourceData, Int(frameCount * bytesPerFrame))
        }
        if trimmed.format.commonFormat == .pcmFormatFloat32 {
            let fadeFrames = frameCount < source.frameLength ? min(64, Int(frameCount)) : 0
            let fadeStart = Int(frameCount) - fadeFrames
            for bufferIndex in destinationBuffers.indices {
                let audioBuffer = destinationBuffers[bufferIndex]
                guard let data = audioBuffer.mData else { continue }
                let channelCount = Int(audioBuffer.mNumberChannels)
                let samples = data.assumingMemoryBound(to: Float.self)
                if gain != 1 {
                    for index in 0..<(Int(frameCount) * channelCount) { samples[index] *= gain }
                }
                for frame in 0..<fadeFrames {
                    let fadeGain = Float(fadeFrames - frame - 1) / Float(max(1, fadeFrames))
                    for channel in 0..<channelCount {
                        samples[(fadeStart + frame) * channelCount + channel] *= fadeGain
                    }
                }
            }
        }
        let bytes = destinationBuffers.reduce(0) { $0 + Int($1.mDataByteSize) }
        if bytes <= maximumPreparedBufferBytes {
            while preparedBuffers.count >= maximumPreparedBufferCount || preparedBufferBytes + bytes > maximumPreparedBufferBytes {
                let oldest = preparedBufferOrder.removeFirst()
                if let removed = preparedBuffers.removeValue(forKey: oldest) { preparedBufferBytes -= removed.byteCount }
            }
            preparedBuffers[key] = CachedBuffer(buffer: trimmed, byteCount: bytes)
            preparedBufferOrder.append(key)
            preparedBufferBytes += bytes
        }
        return trimmed
    }

    private func clearPreparedBuffers() {
        preparedBuffers.removeAll()
        preparedBufferOrder.removeAll()
        preparedBufferBytes = 0
        preparedBufferHits = 0
        preparedBufferMisses = 0
    }

    // Diagnóstico interno verificable sin exponer buffers mutables al llamador.
    var scheduledBufferCacheStatistics: (count: Int, bytes: Int, hits: Int, misses: Int) {
        controlLock.lock()
        defer { controlLock.unlock() }
        return (preparedBuffers.count, preparedBufferBytes, preparedBufferHits, preparedBufferMisses)
    }

    private func scheduleUnchoked(soundID: String, atHostTime hostTime: UInt64, volume: Float) throws {
        guard let sound = sounds[soundID] else { throw SampleAudioEngineError.soundNotLoaded(soundID) }

        let voice = sound.scheduledVoices[sound.nextScheduledVoice]
        sound.nextScheduledVoice = (sound.nextScheduledVoice + 1) % sound.scheduledVoices.count
        let buffer = try preparedBuffer(from: sound.buffer, frameCount: sound.buffer.frameLength, gain: volume)
        voice.scheduleBuffer(buffer, at: scheduledTime(hostTime), options: [])
        if !voice.isPlaying { voice.play() }
    }

    /// La claqueta neutra evita el procesador de tono. Los tonos alterados usan
    /// una ruta independiente para no transponer los pads ni el acompañamiento.
    public func scheduleMetronome(accented: Bool = false, atHostTime hostTime: UInt64, volume: Float = 1, pitchCents: Float = 0) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard let regularBuffer = metronomeBuffer else {
            throw SampleAudioEngineError.soundNotLoaded("metrónomo")
        }
        let buffer = accented ? (metronomeAccentBuffer ?? regularBuffer) : regularBuffer
        let usesDirect = Self.usesDirectMetronome(pitchCents: pitchCents)
        let player = usesDirect ? directMetronomePlayer : metronomePlayer
        if !usesDirect { metronomeTimePitch.pitch = min(2_400, max(-2_400, pitchCents)) }
        let prepared = try preparedBuffer(from: buffer, frameCount: buffer.frameLength, gain: min(1, max(0, volume)))
        player.volume = 1
        player.scheduleBuffer(prepared, at: scheduledTime(hostTime), options: [])
        if !player.isPlaying { player.play() }
    }

    private func makeMetronomeClick(format: AVAudioFormat, frequency: Double) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0,
              format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * 0.018)),
              let channels = buffer.floatChannelData else { return nil }

        buffer.frameLength = buffer.frameCapacity
        let frameCount = Int(buffer.frameLength)
        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let envelope = exp(-time * 210)
            let fundamental = sin(2 * Double.pi * frequency * time)
            let overtone = 0.28 * sin(2 * Double.pi * frequency * 2.73 * time)
            let sample = Float((fundamental + overtone) * envelope * 0.42)
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = sample
            }
        }
        return buffer
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
