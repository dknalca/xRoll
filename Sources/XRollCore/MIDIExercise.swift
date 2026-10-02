import Foundation

public enum MIDIExerciseError: LocalizedError {
    case invalidFile(String)
    case unsupportedFormat(Int)
    case fileTooLarge
    case patternTooLong(Int)
    case unsupportedTiming
    case unsupportedMeter
    case unsupportedTempoChanges
    case missingTempo
    case invalidTempo
    case unsupportedSound(note: Int)
    case unsupportedSubdivision(tick: Int)
    case noPlayableNotes

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let message): return "MIDI no válido: \(message)."
        case .unsupportedFormat(let format): return "El formato MIDI \(format) no es compatible; usa SMF 0 o 1."
        case .fileTooLarge: return "El archivo MIDI supera el límite de 32 MB."
        case .patternTooLong(let bars): return "El MIDI dura \(bars) compases; el máximo admitido es 256."
        case .unsupportedTiming: return "El MIDI debe usar pulsos por negra, no timecode."
        case .unsupportedMeter: return "El MIDI debe estar en compás 4/4."
        case .unsupportedTempoChanges: return "El MIDI debe mantener un BPM fijo."
        case .missingTempo: return "El MIDI debe declarar un BPM con un metaevento de tempo."
        case .invalidTempo: return "El tempo del MIDI debe ser mayor que cero."
        case .unsupportedSound(let note): return "La nota MIDI \(note) no pertenece al kit activo."
        case .unsupportedSubdivision(let tick): return "El MIDI usa una subdivision fuera de la rejilla (tick \(tick))."
        case .noPlayableNotes: return "El MIDI no contiene notas de percusión del kit activo."
        }
    }
}

/// Minimal Standard MIDI File reader for community exercises. It intentionally
/// uses only portable MIDI data: track name, tempo, time signature and note-on.
public enum MIDIExerciseLoader {
    public static let maximumFileBytes = 32 * 1_024 * 1_024
    public static let maximumBars = 256

    public static func load(url: URL, kit: KitManifest, level: Int) throws -> Exercise {
        try kit.validate()
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize,
           fileSize > maximumFileBytes {
            throw MIDIExerciseError.fileTooLarge
        }
        let fileData = try Data(contentsOf: url)
        guard fileData.count <= maximumFileBytes else { throw MIDIExerciseError.fileTooLarge }
        var reader = MIDIReader(bytes: Array(fileData))
        guard reader.readASCII(count: 4) == "MThd" else { throw MIDIExerciseError.invalidFile("falta MThd") }
        let headerLength = try reader.readUInt32()
        guard headerLength >= 6 else { throw MIDIExerciseError.invalidFile("cabecera corta") }
        let format = try reader.readUInt16()
        let tracks = Int(try reader.readUInt16())
        let division = try reader.readUInt16()
        guard format == 0 || format == 1 else { throw MIDIExerciseError.unsupportedFormat(Int(format)) }
        guard tracks > 0, format != 0 || tracks == 1 else {
            throw MIDIExerciseError.invalidFile("número de pistas incompatible con el formato SMF")
        }
        guard division & 0x8000 == 0, division > 0 else { throw MIDIExerciseError.unsupportedTiming }
        if headerLength > 6 { try reader.skip(Int(headerLength - 6)) }

        var tempoEventCount = 0
        var meterEvents = [[Int]]()
        var title: String?
        var endTick = 0
        var hits: [(tick: Int, note: Int, velocity: Int)] = []
        var textEvents = [String]()
        var tempos = Set<Int>()

        for _ in 0..<tracks {
            guard reader.readASCII(count: 4) == "MTrk" else { throw MIDIExerciseError.invalidFile("falta MTrk") }
            let length = Int(try reader.readUInt32())
            let track = try reader.readBytes(count: length)
            let parsed = try parseTrack(track)
            tempos.formUnion(parsed.tempos)
            tempoEventCount += parsed.tempoEventCount
            meterEvents.append(contentsOf: parsed.meterEvents)
            title = title ?? parsed.title
            endTick = max(endTick, parsed.endTick)
            hits.append(contentsOf: parsed.hits)
            textEvents.append(contentsOf: parsed.textEvents)
        }

        guard meterEvents.allSatisfy({ $0 == [4, 4] }) else { throw MIDIExerciseError.unsupportedMeter }
        guard tempos.count <= 1 else { throw MIDIExerciseError.unsupportedTempoChanges }
        guard tempoEventCount <= 1 else { throw MIDIExerciseError.invalidFile("declara más de un metaevento de tempo") }
        guard let parsedTempo = tempos.first else { throw MIDIExerciseError.missingTempo }
        guard parsedTempo > 0 else { throw MIDIExerciseError.invalidTempo }
        let noteToSound = Dictionary(uniqueKeysWithValues: kit.sounds.map { ($0.gmNote, $0.id) })
        let sixteenthTicks = Double(division) / 4
        let tripletTicks = Double(division) / 3
        let usesTriplets = hits.contains { abs(Double($0.tick).truncatingRemainder(dividingBy: sixteenthTicks)) > 0.01 } && hits.allSatisfy { abs(Double($0.tick).truncatingRemainder(dividingBy: tripletTicks)) < 0.01 }
        let grid = usesTriplets ? 12 : 16
        let ticksPerStep = Double(division) * 4 / Double(grid)
        let resolved = try hits.map { hit -> (tick: Int, step: Int, sound: String, velocity: Int) in
            guard let sound = noteToSound[hit.note] else { throw MIDIExerciseError.unsupportedSound(note: hit.note) }
            let position = Double(hit.tick) / ticksPerStep
            let step = Int(position.rounded())
            guard abs(position - Double(step)) < 0.01 else { throw MIDIExerciseError.unsupportedSubdivision(tick: hit.tick) }
            return (hit.tick, step, sound, hit.velocity)
        }
        let soundsByTick = Dictionary(grouping: resolved, by: \.tick).mapValues { Set($0.map(\.sound)) }
        let notes = resolved.map { hit in
            Exercise.Note(
                step: hit.step,
                sound: hit.sound,
                hand: suggestedHand(for: hit.sound, step: hit.step, simultaneousSounds: soundsByTick[hit.tick] ?? []),
                velocity: hit.velocity
            )
        }
        guard !notes.isEmpty else { throw MIDIExerciseError.noPlayableNotes }
        let lastTick = max(endTick, hits.map(\.tick).max() ?? 0)
        let rawBarCount = max(1, ceil(Double(lastTick) / (Double(division) * 4)))
        guard rawBarCount.isFinite else { throw MIDIExerciseError.invalidFile("duración MIDI no finita") }
        guard rawBarCount <= Double(maximumBars) else {
            let reportedBars = rawBarCount >= Double(Int.max) ? Int.max : Int(rawBarCount)
            throw MIDIExerciseError.patternTooLong(reportedBars)
        }
        let barCount = Int(rawBarCount)
        let bpm = max(1, Int((60_000_000 / Double(parsedTempo)).rounded()))
        let fileID = url.deletingPathExtension().lastPathComponent
        let metadata = try MIDIExerciseMetadataParser.parse(textEvents: textEvents)
        let exercise = Exercise(
            format: 1, id: metadata?.id ?? fileID, title: title ?? fileID.replacingOccurrences(of: "_", with: " ").capitalized,
            family: "midi", level: level, bpm: bpm, meter: [4, 4], bars: barCount,
            grid: grid, repeats: 8, kit: kit.id, loop: nil, offset: 0, notes: notes, metadata: metadata
        )
        try exercise.validate(availableSounds: Set(kit.sounds.map(\.id)))
        return exercise
    }

    /// Bombo mano izquierda, caja mano derecha y el charles con la mano que
    /// quede libre: con caja simultanea va la izquierda, con bombo la derecha.
    private static func suggestedHand(for sound: String, step: Int, simultaneousSounds: Set<String>) -> String {
        switch sound {
        case "kick", "clap": return "L"
        case "rim": return "R"
        case "hihat_closed", "hihat_open":
            if simultaneousSounds.contains("snare") { return "L" }
            if simultaneousSounds.contains("kick") { return "R" }
            return step.isMultiple(of: 4) ? "R" : "L"
        default: return "R"
        }
    }

    private static func parseTrack(_ bytes: [UInt8]) throws -> (tempos: Set<Int>, tempoEventCount: Int, meterEvents: [[Int]], title: String?, endTick: Int, hits: [(tick: Int, note: Int, velocity: Int)], textEvents: [String]) {
        var reader = MIDIReader(bytes: bytes)
        var tick = 0; var runningStatus: UInt8?; var tempos = Set<Int>(); var tempoEventCount = 0; var meterEvents = [[Int]](); var title: String?; var hits: [(Int, Int, Int)] = []; var textEvents = [String]()
        while !reader.isAtEnd {
            let delta = try reader.readVariableLength()
            let nextTick = tick.addingReportingOverflow(delta)
            guard !nextTick.overflow else { throw MIDIExerciseError.invalidFile("duración fuera de rango") }
            tick = nextTick.partialValue
            let first = try reader.readByte()
            let status: UInt8
            var firstData: UInt8?
            if first & 0x80 == 0 { guard let runningStatus else { throw MIDIExerciseError.invalidFile("running status") }; status = runningStatus; firstData = first }
            else { status = first; runningStatus = status < 0xF0 ? status : nil }

            if status == 0xFF {
                let type = try reader.readByte(); let length = try reader.readVariableLength(); let data = try reader.readBytes(count: length)
                if type == 0x03 { title = String(bytes: data, encoding: .utf8) }
                if type == 0x01, let text = String(bytes: data, encoding: .utf8) { textEvents.append(text) }
                if type == 0x51 {
                    guard data.count == 3 else { throw MIDIExerciseError.invalidFile("metaevento de tempo incompleto") }
                    tempoEventCount += 1
                    tempos.insert(Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2]))
                }
                if type == 0x58 {
                    guard data.count == 4 else { throw MIDIExerciseError.invalidFile("metaevento de compás incompleto") }
                    let denominatorExponent = Int(data[1])
                    guard denominatorExponent <= 7 else { throw MIDIExerciseError.unsupportedMeter }
                    meterEvents.append([Int(data[0]), 1 << denominatorExponent])
                }
                continue
            }
            guard status < 0xF0 else { throw MIDIExerciseError.invalidFile("evento de sistema") }
            let command = status & 0xF0
            let data1 = try firstData ?? reader.readByte()
            let data2: UInt8? = (command == 0xC0 || command == 0xD0) ? nil : try reader.readByte()
            if command == 0x90, let data2, data2 > 0 { hits.append((tick, Int(data1), Int(data2))) }
        }
        return (tempos, tempoEventCount, meterEvents, title, tick, hits, textEvents)
    }
}

private struct MIDIReader {
    let bytes: [UInt8]; var index = 0
    var isAtEnd: Bool { index >= bytes.count }
    mutating func readByte() throws -> UInt8 { guard index < bytes.count else { throw MIDIExerciseError.invalidFile("fin inesperado") }; defer { index += 1 }; return bytes[index] }
    mutating func readBytes(count: Int) throws -> [UInt8] { guard count >= 0, index + count <= bytes.count else { throw MIDIExerciseError.invalidFile("bloque truncado") }; defer { index += count }; return Array(bytes[index..<(index + count)]) }
    mutating func readASCII(count: Int) -> String? { try? String(bytes: readBytes(count: count), encoding: .ascii) }
    mutating func readUInt16() throws -> UInt16 { let b = try readBytes(count: 2); return UInt16(b[0]) << 8 | UInt16(b[1]) }
    mutating func readUInt32() throws -> UInt32 { let b = try readBytes(count: 4); return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]) }
    mutating func readVariableLength() throws -> Int { var value = 0; for _ in 0..<4 { let byte = try readByte(); value = value << 7 | Int(byte & 0x7F); if byte & 0x80 == 0 { return value } }; throw MIDIExerciseError.invalidFile("delta demasiado largo") }
    mutating func skip(_ count: Int) throws { _ = try readBytes(count: count) }
}
