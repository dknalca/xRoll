import Foundation

typealias Hit = (Int, Int)
struct Definition {
    let id: String
    let title: String
    let bpm: Int
    let grid: Int
    let bars: Int
    let hits: [Hit]

    init(id: String, title: String, bpm: Int, grid: Int = 16, bars: Int = 1, hits: [Hit]) {
        self.id = id
        self.title = title
        self.bpm = bpm
        self.grid = grid
        self.bars = bars
        self.hits = hits
    }
}
let q = [0, 4, 8, 12]
let e = [0, 2, 4, 6, 8, 10, 12, 14]
let tripletEighths = [0, 2, 3, 5, 6, 8, 9, 11]
func repeated(_ hits: [Hit], bars: Int, stepsPerBar: Int = 16) -> [Hit] {
    (0..<bars).flatMap { bar in hits.map { ($0.0 + bar * stepsPerBar, $0.1) } }
}
let rockBackbeat = e.map { ($0, 42) } + [(0,36),(4,38),(8,36),(12,38)]
let disco = e.map { ($0, 42) } + [(0,36),(4,36),(8,36),(12,36),(4,38),(12,38)]
let reggaeOneDrop = [2,6,10,14].map { ($0, 42) } + [(8,36),(8,37)]
let dembow = q.map { ($0, 42) } + [(0,36),(6,36),(12,36),(4,38),(10,38)]
let definitions: [Definition] = [
    .init(id: "20_rock_01_backbeat", title: "Rock 01 · Backbeat", bpm: 78, hits: rockBackbeat + [(14,36)]),
    .init(id: "20_rock_02_crash", title: "Rock 02 · Entrada con crash", bpm: 82, hits: rockBackbeat + [(14,36),(0,49)]),
    .init(id: "20_rock_03_fill", title: "Rock 03 · Fill de toms", bpm: 82, bars: 2, hits: rockBackbeat + rockBackbeat.map { ($0.0 + 16, $0.1) } + [(29,41),(30,48),(31,49)]),
    .init(id: "20_rock_04_resistencia", title: "Rock 04 · Ocho compases", bpm: 88, bars: 8, hits: repeated(e.map { ($0,42) } + [(0,36),(4,38),(8,36),(10,36),(12,38)], bars: 8)),
    .init(id: "21_funk_01_16", title: "Funk 01 · Charles de 16", bpm: 68, hits: Array(0..<16).map { ($0,42) } + [(0,36),(4,38),(6,36),(8,36),(12,38)]),
    .init(id: "21_funk_02_silencio", title: "Funk 02 · Silencio", bpm: 70, hits: [0,2,4,6,8,10,14].map { ($0,42) } + [(0,36),(4,38),(10,36),(12,38)]),
    .init(id: "21_funk_03_sincopa", title: "Funk 03 · Bombo sincopado", bpm: 72, hits: Array(0..<16).map { ($0,42) } + [(0,36),(3,36),(4,38),(8,36),(11,36),(12,38)]),
    .init(id: "21_funk_04_clap", title: "Funk 04 · Palmada", bpm: 74, hits: Array(0..<16).map { ($0,42) } + [(0,36),(4,38),(4,39),(8,36),(12,38),(12,39)]),
    .init(id: "22_blues_01_shuffle", title: "Blues 01 · Shuffle", bpm: 66, grid: 12, hits: tripletEighths.map { ($0,42) } + [(0,36),(3,38),(6,36),(9,38)]),
    .init(id: "22_blues_02_respuesta", title: "Blues 02 · Respuesta", bpm: 70, grid: 12, hits: tripletEighths.map { ($0,42) } + [(0,36),(3,38),(8,36),(9,38),(11,41)]),
    .init(id: "22_blues_03_frase", title: "Blues 03 · Frase de cuatro compases", bpm: 74, grid: 12, bars: 4, hits: repeated(tripletEighths.map { ($0,51) } + [(0,36),(3,38),(6,36),(9,38)], bars: 4, stepsPerBar: 12) + [(47,41)]),
    .init(id: "22_blues_04_cierre", title: "Blues 04 · Doce compases", bpm: 76, grid: 12, bars: 12, hits: repeated(tripletEighths.map { ($0,51) } + [(0,36),(3,38),(6,36),(9,38)], bars: 12, stepsPerBar: 12) + [(142,41),(143,48),(143,49)]),
    .init(id: "23_jazz_01_ride", title: "Jazz 01 · Ride ternario", bpm: 64, grid: 12, hits: tripletEighths.map { ($0,51) } + [(3,38),(9,38)]),
    .init(id: "23_jazz_02_dos_cuatro", title: "Jazz 02 · Dos y cuatro", bpm: 68, grid: 12, hits: tripletEighths.map { ($0,51) } + [(3,38),(9,38),(0,36),(6,36)]),
    .init(id: "23_jazz_03_comping", title: "Jazz 03 · Comping sencillo", bpm: 70, grid: 12, hits: tripletEighths.map { ($0,51) } + [(0,36),(3,38),(8,36),(9,38)]),
    .init(id: "23_jazz_04_frase", title: "Jazz 04 · Fraseo de cuatro compases", bpm: 74, grid: 12, bars: 4, hits: repeated(tripletEighths.map { ($0,51) } + [(0,36),(3,38),(6,36),(9,38)], bars: 4, stepsPerBar: 12) + [(46,41),(47,48)]),
    .init(id: "24_disco_01_pulso", title: "Disco 01 · Bombo a negras", bpm: 80, hits: disco),
    .init(id: "24_disco_02_abierto", title: "Disco 02 · Charles abierto", bpm: 80, hits: disco.filter { $0.0 != 14 || $0.1 != 42 } + [(14,46)]),
    .init(id: "24_disco_03_frase", title: "Disco 03 · Frase de cuatro compases", bpm: 84, bars: 4, hits: repeated(disco, bars: 4) + [(48,49)]),
    .init(id: "25_reggae_01_one_drop", title: "Reggae 01 · One drop", bpm: 68, hits: reggaeOneDrop),
    .init(id: "25_reggae_02_skank", title: "Reggae 02 · Skank a contratiempo", bpm: 68, hits: reggaeOneDrop + [(6,37),(14,37)]),
    .init(id: "25_reggae_03_frase", title: "Reggae 03 · Frase de cuatro compases", bpm: 72, bars: 4, hits: repeated(reggaeOneDrop + [(6,37),(14,37)], bars: 4) + [(48,49)]),
    .init(id: "26_dembow_01_base", title: "Dembow 01 · Patrón base", bpm: 88, hits: dembow),
    .init(id: "26_dembow_02_charles", title: "Dembow 02 · Charles a corcheas", bpm: 88, hits: e.map { ($0,42) } + [(0,36),(6,36),(12,36),(4,38),(10,38)]),
    .init(id: "26_dembow_03_frase", title: "Dembow 03 · Frase de cuatro compases", bpm: 92, bars: 4, hits: repeated(e.map { ($0,42) } + [(0,36),(6,36),(12,36),(4,38),(10,38)], bars: 4) + [(48,49)]),
    .init(id: "27_clave_01_tres_dos", title: "Clave 01 · Son 3-2", bpm: 72, bars: 2, hits: [(0,37),(6,37),(12,37),(20,37),(24,37)]),
    .init(id: "27_clave_02_dos_tres", title: "Clave 02 · Son 2-3", bpm: 72, bars: 2, hits: [(4,37),(8,37),(16,37),(22,37),(28,37)]),
    .init(id: "27_clave_03_bossa", title: "Clave 03 · Bossa básica", bpm: 72, bars: 2, hits: repeated(e.map { ($0,42) }, bars: 2) + [(0,36),(6,36),(12,36),(20,37),(24,36),(30,36)])
]
func vlq(_ value: Int) -> [UInt8] { var value = value; var bytes = [UInt8(value & 127)]; value >>= 7; while value > 0 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }; return bytes.reversed() }
func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }
func be32(_ value: Int) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value & 255)] }
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
let chapterByPrefix = ["20": "rock", "21": "funk", "22": "blues", "23": "jazz", "24": "disco", "25": "reggae", "26": "dembow", "27": "clave-bossa"]
let firstPrerequisite = [
    "rock": "10_hh_08_fill_cierre",
    "disco": "20_rock_04_resistencia",
    "funk": "24_disco_03_frase",
    "reggae": "21_funk_04_clap",
    "dembow": "25_reggae_03_frase",
    "blues": "26_dembow_03_frase",
    "jazz": "22_blues_04_cierre",
    "clave-bossa": "23_jazz_04_frase"
]
var previousByChapter = [String: String]()
for item in definitions {
    let components = item.id.split(separator: "_")
    let chapter = chapterByPrefix[String(components[0])]!
    let position = Int(components[2])!
    let prerequisite = previousByChapter[chapter] ?? firstPrerequisite[chapter]!
    let title = Array(item.title.utf8); let tempo = 60_000_000 / item.bpm; var events: [(Int, Int, [UInt8])] = [(0,0,[255,3] + vlq(title.count) + title),(0,1,[255,81,3,UInt8((tempo >> 16) & 255),UInt8((tempo >> 8) & 255),UInt8(tempo & 255)]),(0,2,[255,88,4,4,2,24,8])]
    var metadata = ["xroll/1 id=\(item.id)", "xroll/1 chapter=\(chapter)", "xroll/1 position=\(position)", "xroll/1 prerequisite=\(prerequisite)", "xroll/1 objective=\(item.title)", "xroll/1 new-difficulty=\(chapter)-\(position)", "xroll/1 recommended-help=full"]
    let lastPosition = ["rock": 4, "funk": 4, "blues": 4, "jazz": 4, "disco": 3, "reggae": 3, "dembow": 3, "clave-bossa": 3][chapter]!
    if position == lastPosition { metadata.append("xroll/1 flag=checkpoint") }
    for (index, text) in metadata.enumerated() { let bytes = Array(text.utf8); events.append((0, 3 + index, [255, 1] + vlq(bytes.count) + bytes)) }
    for (step, note) in item.hits { let tick = step * 1_920 / item.grid; events.append((tick,100,[153,UInt8(note),100])); events.append((tick + 60,99,[137,UInt8(note),0])) }
    events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }; var track = [UInt8](); var previous = 0
    for event in events { track += vlq(event.0 - previous) + event.2; previous = event.0 }; track += vlq(max(0, 1_920 * item.bars - previous)) + [255,47,0]
    let bytes = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(480) + Array("MTrk".utf8) + be32(track.count) + track
    try Data(bytes).write(to: directory.appendingPathComponent(item.id + ".mid"), options: .atomic)
    previousByChapter[chapter] = item.id
}
