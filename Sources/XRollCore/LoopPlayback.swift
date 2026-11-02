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

public struct LoopLibraryOption: Identifiable, Equatable {
    public let id: String
    public let fileName: String
    public let bpm: Double?
    public let url: URL

    public init(id: String, fileName: String, bpm: Double?, url: URL) {
        self.id = id
        self.fileName = fileName
        self.bpm = bpm
        self.url = url
    }
}

/// Descubre los archivos distribuidos y recomienda un acompañamiento por
/// estilo primero, cercanía de BPM después. Nunca modifica el BPM del ejercicio.
public enum LoopLibraryCatalog {
    public static let automaticSelectionID = "__xroll_loop_auto__"

    private static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "m4a"]
    private static let styleAliases: [(id: String, aliases: [String])] = [
        ("hiphop", ["hiphop", "boombap"]),
        ("rock", ["rock"]),
        ("disco", ["disco"]),
        ("funk", ["funk"]),
        ("reggae", ["reggae"]),
        ("dembow", ["dembow"]),
        ("blues", ["blues", "shuffle"]),
        ("jazz", ["jazz"]),
        ("clavebossa", ["clavebossa", "bossa"])
    ]

    public static func discover(in directory: URL, fileManager: FileManager = .default) -> [LoopLibraryOption] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let prefix = directory.standardizedFileURL.path + "/"
        return enumerator.compactMap { $0 as? URL }
            .filter { url in
                audioExtensions.contains(url.pathExtension.lowercased())
                    && ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
            }
            .compactMap { url in
                guard let bpm = LoopTempoDetector.detect(url: url)?.bpm else { return nil }
                let path = url.standardizedFileURL.path
                let id = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
                return LoopLibraryOption(
                    id: id,
                    fileName: url.lastPathComponent,
                    bpm: bpm,
                    url: url
                )
            }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    public static func recommended(
        for exercise: Exercise,
        targetBPM: Double? = nil,
        options: [LoopLibraryOption]
    ) -> LoopLibraryOption? {
        let candidates = options.filter { $0.bpm != nil }
        guard !candidates.isEmpty else { return nil }

        let genre = requestedGenre(for: exercise)
        let genreMatches = genre.map { genre in candidates.filter { containsGenre($0, genre: genre) } } ?? []
        let generic = candidates.filter { option in
            !styleAliases.contains { containsGenre(option, genre: $0.id) }
        }
        let pool = !genreMatches.isEmpty ? genreMatches : (!generic.isEmpty ? generic : candidates)
        let target = targetBPM ?? Double(exercise.bpm)
        return pool.min { left, right in
            let leftDistance = abs((left.bpm ?? target) - target)
            let rightDistance = abs((right.bpm ?? target) - target)
            if leftDistance == rightDistance { return left.id < right.id }
            return leftDistance < rightDistance
        }
    }

    private static func requestedGenre(for exercise: Exercise) -> String? {
        let description = normalized([
            exercise.metadata?.chapter ?? "",
            exercise.title,
            exercise.id
        ].joined(separator: " "))
        return styleAliases.first { style in
            style.aliases.contains(where: { description.contains($0) })
        }?.id
    }

    private static func containsGenre(_ option: LoopLibraryOption, genre: String) -> Bool {
        guard let style = styleAliases.first(where: { $0.id == genre }) else { return false }
        let name = normalized(option.id + " " + option.fileName)
        return style.aliases.contains(where: { name.contains($0) })
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
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
        // AVAudioUnitTimePitch uses 1.0 as normal speed, not percentages.
        timePitch.rate = Float(targetBPM / sourceBPM)
        player.volume = min(1, max(0, volume))
        player.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: .loops)
        player.play(at: AVAudioTime(hostTime: hostTime))
    }

    public func stop() { player.stop() }
}
