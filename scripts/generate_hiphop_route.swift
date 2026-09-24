import Foundation

struct RouteExercise { let file: String; let title: String; let bpm: Int; let bars: Int; let notes: [(Int, Int)] }
let q = [0, 4, 8, 12]
let eighths = [0, 2, 4, 6, 8, 10, 12, 14]
let sixteenths = Array(0...15)
let exercises = [
    RouteExercise(file: "10_hh_01_boom_bap", title: "Hip-hop 1 · Boom bap con aro", bpm: 72, bars: 1, notes: q.map { ($0, 42) } + [(0,36),(4,37),(8,36),(12,37)]),
    RouteExercise(file: "10_hh_02_bombo_sincopado", title: "Hip-hop 2 · Bombo sincopado", bpm: 72, bars: 1, notes: q.map { ($0,42) } + [(0,36),(6,36),(8,36),(12,38),(4,38)]),
    RouteExercise(file: "10_hh_03_silencio", title: "Hip-hop 3 · El valor del silencio", bpm: 72, bars: 1, notes: [(0,42),(4,42),(8,42)] + [(0,36),(4,38),(8,36),(12,38)]),
    RouteExercise(file: "10_hh_04_aro", title: "Hip-hop 4 · Aro y palmada", bpm: 72, bars: 1, notes: q.map { ($0,42) } + [(0,36),(4,37),(8,36),(12,39)]),
    RouteExercise(file: "10_hh_05_half_time", title: "Hip-hop 5 · Half-time", bpm: 72, bars: 1, notes: eighths.map { ($0,42) } + [(0,36),(8,38),(10,36)]),
    RouteExercise(file: "10_hh_06_dos_compases", title: "Hip-hop 6 · Dos compases", bpm: 72, bars: 2, notes: eighths.map { ($0,42) } + eighths.map { ($0 + 16,42) } + [(0,36),(4,38),(8,36),(12,38),(16,36),(22,36),(24,38),(28,39)]),
    RouteExercise(file: "10_hh_07_charles_16", title: "Hip-hop 7 · Charles en semicorcheas", bpm: 72, bars: 1, notes: sixteenths.map { ($0,42) } + [(0,36),(4,38),(8,36),(12,38)]),
    RouteExercise(file: "10_hh_08_fill_cierre", title: "Hip-hop 8 · Fill de cierre", bpm: 72, bars: 1, notes: eighths.map { ($0,42) } + [(0,36),(4,38),(8,36),(12,41),(14,48),(15,49)])
]
let hiphopBar1: [(Int, Int)] = q.map { ($0, 42) } + [(0,36),(4,37),(8,36),(12,37)]
let hiphopBar2: [(Int, Int)] = [0,4,10].map { ($0 + 16, 42) } + [(16,36),(22,36),(26,36),(20,38),(28,38)]
let hiphopBar3: [(Int, Int)] = eighths.map { ($0 + 32, 42) } + [(32,36),(40,38),(42,36),(44,36),(60,38)]
let hiphopBar4: [(Int, Int)] = sixteenths.map { ($0 + 48, 42) } + [(48,36),(52,38),(56,36),(60,41),(62,48),(63,49)]
let hiphopCheckpoint = hiphopBar1 + hiphopBar2 + hiphopBar3 + hiphopBar4
let checkpointOverrides: [String: (bars: Int, notes: [(Int, Int)])] = [
    "10_hh_08_fill_cierre": (4, hiphopCheckpoint)
]
func vlq(_ value: Int) -> [UInt8] { var v = value; var bytes = [UInt8(v & 0x7F)]; v >>= 7; while v > 0 { bytes.append(UInt8((v & 0x7F) | 0x80)); v >>= 7 }; return bytes.reversed() }
func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16), UInt8(v >> 8), UInt8(v & 0xFF)] }
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
for (index, exercise) in exercises.enumerated() {
    let tempo = 60_000_000 / exercise.bpm; let title = Array(exercise.title.utf8); let ppq = 480
    let override = checkpointOverrides[exercise.file]
    let bars = override?.bars ?? exercise.bars
    let notes = override?.notes ?? exercise.notes
    var events: [(Int, Int, [UInt8])] = [(0,0,[0xFF,0x03] + vlq(title.count) + title),(0,1,[0xFF,0x51,0x03,UInt8((tempo >> 16) & 0xFF),UInt8((tempo >> 8) & 0xFF),UInt8(tempo & 0xFF)]),(0,2,[0xFF,0x58,0x04,0x04,0x02,0x18,0x08])]
    var metadata = ["xroll/1 id=\(exercise.file)", "xroll/1 chapter=hiphop", "xroll/1 position=\(index + 1)", "xroll/1 objective=\(exercise.title)", "xroll/1 new-difficulty=hiphop-\(index + 1)", "xroll/1 recommended-help=full"]
    metadata.append("xroll/1 prerequisite=\(index == 0 ? "04_groove_07_completo" : exercises[index - 1].file)")
    if index == exercises.count - 1 { metadata.append("xroll/1 flag=checkpoint") }
    for (metadataIndex, text) in metadata.enumerated() { let bytes = Array(text.utf8); events.append((0, 3 + metadataIndex, [0xFF, 0x01] + vlq(bytes.count) + bytes)) }
    for (step,note) in notes { let tick = step * ppq / 4; events.append((tick,100,[0x99,UInt8(note),100])); events.append((tick + 60,99,[0x89,UInt8(note),0])) }
    events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }; var track = [UInt8](); var last = 0
    for event in events { track += vlq(event.0 - last) + event.2; last = event.0 }
    track += vlq(max(0, ppq * 4 * bars - last)) + [0xFF,0x2F,0]
    let midi = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(ppq) + Array("MTrk".utf8) + be32(track.count) + track
    try Data(midi).write(to: directory.appendingPathComponent(exercise.file).appendingPathExtension("mid"), options: .atomic)
}
