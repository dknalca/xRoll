import Foundation

struct Exercise: Decodable {
    struct Note: Decodable { let step: Int; let sound: String }
    let id: String; let title: String; let bpm: Int; let notes: [Note]
}

let gmNotes = ["kick": 36, "snare": 38, "clap": 39, "tom_low": 41, "hihat_closed": 42, "hihat_open": 46, "tom_high": 48, "crash": 49, "ride": 51]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let directory = root.appendingPathComponent("data/exercises", isDirectory: true)
let encoder = JSONDecoder()

func vlq(_ value: Int) -> [UInt8] {
    var value = value
    var bytes = [UInt8(value & 0x7F)]
    value >>= 7
    while value > 0 { bytes.append(UInt8((value & 0x7F) | 0x80)); value >>= 7 }
    return bytes.reversed()
}

func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
func be32(_ value: Int) -> [UInt8] { [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }

for source in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let exercise = try encoder.decode(Exercise.self, from: Data(contentsOf: source))
    let ppq = 480
    let tempo = 60_000_000 / max(1, exercise.bpm)
    var events: [(tick: Int, order: Int, bytes: [UInt8])] = []
    let title = Array(exercise.title.utf8)
    events.append((0, 0, [0xFF, 0x03] + vlq(title.count) + title))
    events.append((0, 1, [0xFF, 0x51, 0x03, UInt8((tempo >> 16) & 0xFF), UInt8((tempo >> 8) & 0xFF), UInt8(tempo & 0xFF)]))
    events.append((0, 2, [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]))
    for note in exercise.notes {
        guard let gm = gmNotes[note.sound] else { continue }
        let tick = note.step * ppq / 4
        events.append((tick, 3, [0x99, UInt8(gm), 100]))
        events.append((tick + 60, 2, [0x89, UInt8(gm), 0]))
    }
    events.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }
    var track = [UInt8](); var lastTick = 0
    for event in events { track += vlq(event.tick - lastTick); track += event.bytes; lastTick = event.tick }
    track += vlq(max(0, ppq * 4 - lastTick)) + [0xFF, 0x2F, 0x00]
    var midi = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(ppq)
    midi += Array("MTrk".utf8) + be32(track.count) + track
    try Data(midi).write(to: source.deletingPathExtension().appendingPathExtension("mid"), options: .atomic)
}
