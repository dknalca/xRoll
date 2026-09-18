import Foundation

public enum MIDIExerciseError: LocalizedError {
    case invalidFile(String)
    case unsupportedTiming
    case unsupportedMeter
    case unsupportedTempoChanges
    case noPlayableNotes

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let message): return "MIDI no válido: \(message)."
        case .unsupportedTiming: return "El MIDI debe usar pulsos por negra, no timecode."
        case .unsupportedMeter: return "El MIDI debe estar en compás 4/4."
        case .unsupportedTempoChanges: return "El MIDI debe mantener un BPM fijo."
        case .noPlayableNotes: return "El MIDI no contiene notas de percusión del kit activo."
        }
    }
}

/// Minimal Standard MIDI File reader for community exercises. It intentionally
/// uses only portable MIDI data: track name, tempo, time signature and note-on.
public enum MIDIExerciseLoader {
    public static func load(url: URL, kit: KitManifest, level: Int) throws -> Exercise {
        var reader = MIDIReader(bytes: Array(try Data(contentsOf: url)))
        guard reader.readASCII(count: 4) == "MThd" else { throw MIDIExerciseError.invalidFile("falta MThd") }
        let headerLength = try reader.readUInt32()
        guard headerLength >= 6 else { throw MIDIExerciseError.invalidFile("cabecera corta") }
        _ = try reader.readUInt16() // format 0 and 1 both work for exercises
        let tracks = Int(try reader.readUInt16())
        let division = try reader.readUInt16()
        guard division & 0x8000 == 0, division > 0 else { throw MIDIExerciseError.unsupportedTiming }
        if headerLength > 6 { try reader.skip(Int(headerLength - 6)) }

        var tempo = 750_000 // 80 BPM: a friendly fallback for community files
        var meter = [4, 4]
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
            if let parsedMeter = parsed.meter { meter = parsedMeter }
            title = title ?? parsed.title
            endTick = max(endTick, parsed.endTick)
            hits.append(contentsOf: parsed.hits)
            textEvents.append(contentsOf: parsed.textEvents)
        }

        guard meter == [4, 4] else { throw MIDIExerciseError.unsupportedMeter }
        guard tempos.count <= 1 else { throw MIDIExerciseError.unsupportedTempoChanges }
        if let parsedTempo = tempos.first { tempo = parsedTempo }
        let noteToSound = Dictionary(uniqueKeysWithValues: kit.sounds.map { ($0.gmNote, $0.id) })
        let sixteenthTicks = Double(division) / 4
        let tripletTicks = Double(division) / 3
        let usesTriplets = hits.contains { abs(Double($0.tick).truncatingRemainder(dividingBy: sixteenthTicks)) > 0.01 } && hits.allSatisfy { abs(Double($0.tick).truncatingRemainder(dividingBy: tripletTicks)) < 0.01 }
        let grid = usesTriplets ? 12 : 16
        let ticksPerStep = Double(division) * 4 / Double(grid)
        let notes = hits.compactMap { hit -> Exercise.Note? in
            guard let sound = noteToSound[hit.note] else { return nil }
            let step = Int((Double(hit.tick) / ticksPerStep).rounded())
            return Exercise.Note(step: step, sound: sound, hand: suggestedHand(for: sound, step: step), velocity: hit.velocity)
        }
        guard !notes.isEmpty else { throw MIDIExerciseError.noPlayableNotes }
        let totalSteps = max(grid, Int(ceil(Double(max(endTick, hits.map(\.tick).max() ?? 0)) / ticksPerStep / Double(grid))) * grid)
        let bpm = max(1, Int((60_000_000 / Double(tempo)).rounded()))
        let fileID = url.deletingPathExtension().lastPathComponent
        let metadata = MIDIExerciseMetadataParser.parse(textEvents: textEvents)
        let exercise = Exercise(
            format: 1, id: metadata?.id ?? fileID, title: title ?? fileID.replacingOccurrences(of: "_", with: " ").capitalized,
            family: "midi", level: level, bpm: bpm, meter: meter, bars: totalSteps / grid,
            grid: grid, repeats: 8, kit: kit.id, loop: nil, offset: 0, notes: notes, metadata: metadata
        )
        try exercise.validate(availableSounds: Set(kit.sounds.map(\.id)))
        return exercise
    }

    private static func suggestedHand(for sound: String, step: Int) -> String {
        switch sound {
        case "kick", "clap": return "L"
        case "rim": return "R"
        case "hihat_closed", "hihat_open": return step.isMultiple(of: 4) ? "R" : "L"
        default: return "R"
        }
    }

    private static func parseTrack(_ bytes: [UInt8]) throws -> (tempos: Set<Int>, meter: [Int]?, title: String?, endTick: Int, hits: [(tick: Int, note: Int, velocity: Int)], textEvents: [String]) {
        var reader = MIDIReader(bytes: bytes)
        var tick = 0; var runningStatus: UInt8?; var tempos = Set<Int>(); var meter: [Int]?; var title: String?; var hits: [(Int, Int, Int)] = []; var textEvents = [String]()
        while !reader.isAtEnd {
            tick += try reader.readVariableLength()
            let first = try reader.readByte()
            let status: UInt8
            var firstData: UInt8?
            if first & 0x80 == 0 { guard let runningStatus else { throw MIDIExerciseError.invalidFile("running status") }; status = runningStatus; firstData = first }
            else { status = first; runningStatus = status < 0xF0 ? status : nil }

            if status == 0xFF {
                let type = try reader.readByte(); let length = try reader.readVariableLength(); let data = try reader.readBytes(count: length)
                if type == 0x03 { title = String(bytes: data, encoding: .utf8) }
                if type == 0x01, let text = String(bytes: data, encoding: .utf8) { textEvents.append(text) }
                if type == 0x51, data.count == 3 { tempos.insert(Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2])) }
                if type == 0x58, data.count >= 2 { meter = [Int(data[0]), 1 << Int(data[1])] }
                continue
            }
            guard status < 0xF0 else { throw MIDIExerciseError.invalidFile("evento de sistema") }
            let command = status & 0xF0
            let data1 = try firstData ?? reader.readByte()
            let data2: UInt8? = (command == 0xC0 || command == 0xD0) ? nil : try reader.readByte()
            if command == 0x90, let data2, data2 > 0 { hits.append((tick, Int(data1), Int(data2))) }
        }
        return (tempos, meter, title, tick, hits, textEvents)
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
