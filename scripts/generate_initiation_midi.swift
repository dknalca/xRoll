import Foundation

struct ExerciseDefinition {
    let filename: String
    let title: String
    let bpm: Int
    let notes: [(step: Int, note: Int)]
}

let exercises = [
    // Cada bloque empieza ya con un ritmo. Las capas del preparador permiten
    // descomponerlo sin convertir el catálogo en ejercicios de un solo pad.
    ExerciseDefinition(filename: "00_i_01_bombo_caja", title: "I-01 · Bombo y caja", bpm: 68, notes: [(0, 36), (4, 38), (8, 36), (12, 38)]),
    ExerciseDefinition(filename: "00_i_02_charles_negras", title: "I-02 · Añade charles", bpm: 68, notes: [(0, 36), (0, 42), (4, 38), (4, 42), (8, 36), (8, 42), (12, 38), (12, 42)]),
    ExerciseDefinition(filename: "00_i_03_ritmo_completo", title: "I-03 · Ritmo completo · vía rápida", bpm: 72, notes: [(0, 36), (0, 42), (2, 42), (4, 38), (4, 42), (6, 42), (8, 36), (8, 42), (10, 42), (12, 38), (12, 42), (14, 42)]),
    ExerciseDefinition(filename: "00_i_04_transferencia", title: "I-04 · Consolidar el groove", bpm: 72, notes: [(0, 36), (0, 42), (2, 42), (4, 38), (4, 42), (6, 42), (8, 36), (8, 42), (10, 42), (12, 38), (12, 42), (14, 42)])
]

func vlq(_ value: Int) -> [UInt8] {
    var value = value
    var bytes = [UInt8(value & 0x7F)]
    value >>= 7
    while value > 0 { bytes.append(UInt8((value & 0x7F) | 0x80)); value >>= 7 }
    return bytes.reversed()
}
func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
func be32(_ value: Int) -> [UInt8] { [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let directory = root.appendingPathComponent("data/exercises", isDirectory: true)
let ppq = 480

for exercise in exercises {
    let tempo = 60_000_000 / exercise.bpm
    let title = Array(exercise.title.utf8)
    var events: [(tick: Int, order: Int, bytes: [UInt8])] = [
        (0, 0, [0xFF, 0x03] + vlq(title.count) + title),
        (0, 1, [0xFF, 0x51, 0x03, UInt8((tempo >> 16) & 0xFF), UInt8((tempo >> 8) & 0xFF), UInt8(tempo & 0xFF)]),
        (0, 2, [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])
    ]
    for hit in exercise.notes {
        let tick = hit.step * ppq / 4
        events.append((tick, 3, [0x99, UInt8(hit.note), 100]))
        events.append((tick + 60, 2, [0x89, UInt8(hit.note), 0]))
    }
    events.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }
    var track = [UInt8](); var previousTick = 0
    for event in events { track += vlq(event.tick - previousTick); track += event.bytes; previousTick = event.tick }
    track += vlq(max(0, ppq * 4 - previousTick)) + [0xFF, 0x2F, 0x00]
    let midi = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(ppq) + Array("MTrk".utf8) + be32(track.count) + track
    try Data(midi).write(to: directory.appendingPathComponent(exercise.filename).appendingPathExtension("mid"), options: .atomic)
}
