import Foundation

/// Redobles de una única idea por vez. Cada familia tiene una versión aislada
/// y otra de tres compases: groove → redoble → groove de resolución.
struct FillExercise {
    let file: String
    let title: String
    let bpm: Int
    let bars: Int
    let notes: [(Int, Int)]
}

let eighths = [0, 2, 4, 6, 8, 10, 12, 14]
let basicGroove = eighths.map { ($0, 42) } + [(0, 36), (4, 38), (8, 36), (12, 38)]

func inContext(_ fill: [(Int, Int)]) -> [(Int, Int)] {
    // Compás 1: groove conocido. Compás 2: deja hueco desde el pulso 3
    // para el redoble. Compás 3: resolución clara con crash en el uno.
    let firstBar = basicGroove
    let fillSteps = Set(fill.map(\.0))
    // El charles se retira exactamente donde entra el fill: evita que los
    // toms se solapen con HH y hace audible el hueco de la transición.
    let secondHihat = [0, 2, 4, 6, 8, 10, 12, 14]
        .filter { !fillSteps.contains($0) }
        .map { ($0 + 16, 42) }
    let secondGroove = secondHihat + [(16, 36), (20, 38)]
    let resolution = eighths.map { ($0 + 32, 42) } + [(32, 49), (32, 36), (36, 38), (40, 36), (44, 38)]
    return firstBar + secondGroove + fill.map { ($0.0 + 16, $0.1) } + resolution
}

let snareEighths = [(8, 38), (10, 38), (12, 38), (14, 38)]
let descendingToms = [(8, 48), (10, 48), (12, 41), (14, 41)]
let snareSixteenths = [(8, 38), (9, 38), (10, 38), (11, 38), (12, 38), (13, 38), (14, 38), (15, 38)]
let linear = [(8, 36), (9, 38), (10, 48), (11, 38), (12, 36), (13, 41), (14, 38), (15, 41)]

let exercises = [
    FillExercise(file: "30_fill_01_caja_corcheas_aislado", title: "Redoble 1A · Caja a corcheas", bpm: 70, bars: 1, notes: snareEighths),
    FillExercise(file: "30_fill_01_caja_corcheas_groove", title: "Redoble 1B · Caja dentro del groove", bpm: 70, bars: 3, notes: inContext(snareEighths)),
    FillExercise(file: "30_fill_02_bajada_toms_aislado", title: "Redoble 2A · Bajada de toms", bpm: 75, bars: 1, notes: descendingToms),
    FillExercise(file: "30_fill_02_bajada_toms_groove", title: "Redoble 2B · Toms dentro del groove", bpm: 75, bars: 3, notes: inContext(descendingToms)),
    FillExercise(file: "30_fill_03_caja_16_aislado", title: "Redoble 3A · Caja en semicorcheas", bpm: 80, bars: 1, notes: snareSixteenths),
    FillExercise(file: "30_fill_03_caja_16_groove", title: "Redoble 3B · Semicorcheas dentro del groove", bpm: 80, bars: 3, notes: inContext(snareSixteenths)),
    FillExercise(file: "30_fill_04_lineal_aislado", title: "Redoble 4A · Lineal con bombo y toms", bpm: 85, bars: 1, notes: linear),
    FillExercise(file: "30_fill_04_lineal_groove", title: "Redoble 4B · Lineal dentro del groove", bpm: 85, bars: 3, notes: inContext(linear))
]

func vlq(_ value: Int) -> [UInt8] {
    var value = value
    var bytes = [UInt8(value & 0x7F)]
    value >>= 7
    while value > 0 { bytes.append(UInt8((value & 0x7F) | 0x80)); value >>= 7 }
    return bytes.reversed()
}
func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
func be32(_ value: Int) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value & 0xFF)] }

let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
for exercise in exercises {
    let ppq = 480
    let tempo = 60_000_000 / exercise.bpm
    let title = Array(exercise.title.utf8)
    var events: [(Int, Int, [UInt8])] = [
        (0, 0, [0xFF, 0x03] + vlq(title.count) + title),
        (0, 1, [0xFF, 0x51, 0x03, UInt8((tempo >> 16) & 0xFF), UInt8((tempo >> 8) & 0xFF), UInt8(tempo & 0xFF)]),
        (0, 2, [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])
    ]
    for (step, note) in exercise.notes {
        let tick = step * ppq / 4
        events.append((tick, 3, [0x99, UInt8(note), 100]))
        events.append((tick + 60, 2, [0x89, UInt8(note), 0]))
    }
    events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    var track = [UInt8](), lastTick = 0
    for event in events { track += vlq(event.0 - lastTick) + event.2; lastTick = event.0 }
    track += vlq(max(0, ppq * 4 * exercise.bars - lastTick)) + [0xFF, 0x2F, 0]
    let midi = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(ppq) + Array("MTrk".utf8) + be32(track.count) + track
    try Data(midi).write(to: directory.appendingPathComponent(exercise.file).appendingPathExtension("mid"), options: .atomic)
}
