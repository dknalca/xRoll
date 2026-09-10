import Foundation

typealias Hit = (Int, Int)
struct Definition { let id: String; let title: String; let bpm: Int; let hits: [Hit] }
let q = [0, 4, 8, 12]
let e = [0, 2, 4, 6, 8, 10, 12, 14]
let definitions: [Definition] = [
    .init(id: "20_rock_01_backbeat", title: "Rock 01 · Backbeat", bpm: 78, hits: q.flatMap { [($0, 42)] } + [(0,36),(4,38),(8,36),(12,38)]),
    .init(id: "20_rock_02_crash", title: "Rock 02 · Entrada con crash", bpm: 82, hits: e.map { ($0,42) } + [(0,49),(0,36),(4,38),(8,36),(12,38)]),
    .init(id: "20_rock_03_fill", title: "Rock 03 · Fill de toms", bpm: 82, hits: e.map { ($0,42) } + [(0,36),(4,38),(8,36),(12,38),(13,41),(14,48),(15,49)]),
    .init(id: "20_rock_04_resistencia", title: "Rock 04 · Ocho compases", bpm: 88, hits: e.map { ($0,42) } + [(0,36),(4,38),(8,36),(12,38)]),
    .init(id: "21_funk_01_16", title: "Funk 01 · Charles de 16", bpm: 68, hits: Array(0..<16).map { ($0,42) } + [(0,36),(4,38),(8,36),(12,38)]),
    .init(id: "21_funk_02_silencio", title: "Funk 02 · Silencio", bpm: 70, hits: [0,2,4,6,8,10,14].map { ($0,42) } + [(0,36),(4,38),(10,36),(12,38)]),
    .init(id: "21_funk_03_sincopa", title: "Funk 03 · Bombo sincopado", bpm: 72, hits: Array(0..<16).map { ($0,42) } + [(0,36),(3,36),(4,38),(8,36),(11,36),(12,38)]),
    .init(id: "21_funk_04_clap", title: "Funk 04 · Palmada", bpm: 74, hits: Array(0..<16).map { ($0,42) } + [(0,36),(4,38),(4,39),(8,36),(12,38),(12,39)]),
    .init(id: "22_blues_01_shuffle", title: "Blues 01 · Shuffle", bpm: 66, hits: [0,3,4,7,8,11,12,15].map { ($0,42) } + [(0,36),(4,38),(8,36),(12,38)]),
    .init(id: "22_blues_02_respuesta", title: "Blues 02 · Respuesta", bpm: 70, hits: [0,3,4,7,8,11,12,15].map { ($0,42) } + [(0,36),(4,38),(10,36),(12,38),(15,41)]),
    .init(id: "22_blues_03_frase", title: "Blues 03 · Frase", bpm: 74, hits: [0,3,4,7,8,11,12,15].map { ($0,51) } + [(0,36),(4,38),(8,36),(12,38)]),
    .init(id: "22_blues_04_cierre", title: "Blues 04 · Cierre", bpm: 76, hits: [0,3,4,7,8,11,12,15].map { ($0,51) } + [(0,36),(4,38),(8,36),(12,38),(13,41),(14,48),(15,49)]),
    .init(id: "23_jazz_01_ride", title: "Jazz 01 · Ride ternario", bpm: 64, hits: [0,3,4,7,8,11,12,15].map { ($0,51) } + [(4,38),(12,38)]),
    .init(id: "23_jazz_02_dos_cuatro", title: "Jazz 02 · Dos y cuatro", bpm: 68, hits: [0,3,4,7,8,11,12,15].map { ($0,51) } + [(4,38),(12,38),(0,36),(8,36)]),
    .init(id: "23_jazz_03_comping", title: "Jazz 03 · Comping sencillo", bpm: 70, hits: [0,3,4,7,8,11,12,15].map { ($0,51) } + [(0,36),(4,38),(10,36),(12,38)]),
    .init(id: "23_jazz_04_frase", title: "Jazz 04 · Fraseo", bpm: 74, hits: [0,3,4,7,8,11,12,15].map { ($0,51) } + [(0,36),(4,38),(8,36),(12,38),(14,41),(15,48)])
]
func vlq(_ value: Int) -> [UInt8] { var value = value; var bytes = [UInt8(value & 127)]; value >>= 7; while value > 0 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }; return bytes.reversed() }
func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }
func be32(_ value: Int) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value & 255)] }
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
for item in definitions {
    let title = Array(item.title.utf8); let tempo = 60_000_000 / item.bpm; var events: [(Int, Int, [UInt8])] = [(0,0,[255,3] + vlq(title.count) + title),(0,1,[255,81,3,UInt8((tempo >> 16) & 255),UInt8((tempo >> 8) & 255),UInt8(tempo & 255)]),(0,2,[255,88,4,4,2,24,8])]
    for (step, note) in item.hits { let tick = step * 120; events.append((tick,3,[153,UInt8(note),100])); events.append((tick + 60,2,[137,UInt8(note),0])) }
    events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }; var track = [UInt8](); var previous = 0
    for event in events { track += vlq(event.0 - previous) + event.2; previous = event.0 }; track += vlq(max(0, 1920 - previous)) + [255,47,0]
    let bytes = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(480) + Array("MTrk".utf8) + be32(track.count) + track
    try Data(bytes).write(to: directory.appendingPathComponent(item.id + ".mid"), options: .atomic)
}
