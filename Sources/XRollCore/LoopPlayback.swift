import AVFoundation
import Foundation

public struct LoopTempo: Equatable {
    public let bpm: Double
    public let source: String

    public init(bpm: Double, source: String) {
        self.bpm = bpm
        self.source = source
    }
}

/// Finds a loop tempo from its filename first (for example `bass 90bpm.wav`).
/// When the filename has no tempo, it derives the most plausible whole-bar tempo
/// from the file duration. This keeps user loops usable without a sidecar file.
public enum LoopTempoDetector {
    public static func detect(url: URL) -> LoopTempo? {
        let name = url.deletingPathExtension().lastPathComponent
        let expression = try? NSRegularExpression(pattern: #"(?i)(\d{2,3}(?:[\.,]\d+)?)\s*bpm"#)
        let range = NSRange(name.startIndex..., in: name)
        if let match = expression?.firstMatch(in: name, range: range), let swiftRange = Range(match.range(at: 1), in: name) {
            let value = name[swiftRange].replacingOccurrences(of: ",", with: ".")
            if let bpm = Double(value), (40...260).contains(bpm) { return LoopTempo(bpm: bpm, source: "nombre del archivo") }
        }

        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        guard seconds > 0 else { return nil }
        let candidates = [1, 2, 4, 8, 16].map { bars in 240 * Double(bars) / seconds }.filter { (40...260).contains($0) }
        guard let bpm = candidates.min(by: { abs($0 - 120) < abs($1 - 120) }) else { return nil }
        return LoopTempo(bpm: bpm, source: "duración del loop")
    }
}

public final class LoopPlaybackEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var buffer: AVAudioPCMBuffer?
    public private(set) var detectedTempo: LoopTempo?

    public init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
    }

    public func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length <= AVAudioFramePosition(UInt32.max), let loaded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return }
        try file.read(into: loaded)
        buffer = loaded
        detectedTempo = LoopTempoDetector.detect(url: url)
    }

    public func start(atHostTime hostTime: UInt64, targetBPM: Double, volume: Float = 0.72) throws {
        guard let buffer, let sourceBPM = detectedTempo?.bpm, sourceBPM > 0 else { return }
        if !engine.isRunning { try engine.start() }
        player.stop()
        timePitch.rate = Float(targetBPM / sourceBPM * 100)
        player.volume = min(1, max(0, volume))
        player.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: .loops)
        player.play(at: AVAudioTime(hostTime: hostTime))
    }

    public func stop() { player.stop() }
}
