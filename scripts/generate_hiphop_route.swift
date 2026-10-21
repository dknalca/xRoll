import Foundation

struct RouteExercise { let file: String; let title: String; let objective: String; let difficulty: String; let bpm: Int; let bars: Int; let notes: [(Int, Int)] }
let eighths = [0, 2, 4, 6, 8, 10, 12, 14]
typealias Hit = (Int, Int)
func shifted(_ notes: [Hit], by steps: Int) -> [Hit] { notes.map { ($0.0 + steps, $0.1) } }
// El tronco común ya enseña corcheas, síncopas y fills. Aquí se aplican al
// boom bap y se conserva la base al introducir cada variación del estilo.
let boomBap: [Hit] = eighths.map { ($0, 42) } + [(0,36),(6,36),(8,36),(4,37),(12,37)]
let syncopated: [Hit] = boomBap + [(11,36)]
let withSpace = syncopated.filter { !($0.1 == 42 && [8,10,14].contains($0.0)) }
let withClap = withSpace.filter { !($0.0 == 12 && $0.1 == 37) } + [(12,39)]
let halfTime = withClap.filter { ![37,39].contains($0.1) } + [(8,37),(14,39)]
let answer = halfTime.filter { !($0.0 == 11 && $0.1 == 36) } + [(15,36)]
let phrase = halfTime + shifted(answer, by: 16)
let rollPhrase = phrase + [(13,42),(15,42),(29,42),(31,42)]
let openPhrase = rollPhrase.map { (step, note) in (step, note == 42 && [6,22].contains(step) ? 46 : note) }
let snareAnswer = openPhrase.map { (step, note) in (step, step == 24 && note == 37 ? 38 : note) }
let clapAnswer = snareAnswer + [(11,39),(27,39)]
let returnPhrase = snareAnswer + shifted(clapAnswer.filter { $0.0 < 28 } + [(28,41),(30,48),(31,48)], by: 32)
// La prueba conserva aro/palmada, caja de respuesta, abierto, huecos y ráfagas.
// El fill sustituye el cierre: no apila toms encima de todas las voces.
let fillBar = answer.filter { $0.0 < 12 } + [(12,39),(12,41),(14,48),(15,48)]
let checkpoint = syncopated + shifted(openPhrase.filter { $0.0 < 16 }, by: 16)
    + shifted(clapAnswer.filter { $0.0 >= 16 }.map { ($0.0 - 16,$0.1) }, by: 32) + shifted(fillBar, by: 48)
let exercises = [
    RouteExercise(file: "10_hh_01_boom_bap", title: "Hip-hop 1 · Boom bap con aro", objective: "Sustituye la caja por aro sobre corcheas y bombo sincopado.", difficulty: "rim-orchestration", bpm: 72, bars: 1, notes: boomBap),
    RouteExercise(file: "10_hh_02_bombo_sincopado", title: "Hip-hop 2 · Anticipa el backbeat", objective: "Añade el bombo justo antes del segundo aro sin mover el charles.", difficulty: "sixteenth-kick-anticipation", bpm: 72, bars: 1, notes: syncopated),
    RouteExercise(file: "10_hh_03_silencio", title: "Hip-hop 3 · Silencios sobre la síncopa", objective: "Conserva el bombo anticipado cuando faltan tres corcheas de charles.", difficulty: "hihat-gaps", bpm: 72, bars: 1, notes: withSpace),
    RouteExercise(file: "10_hh_04_aro", title: "Hip-hop 4 · Aro y palmada", objective: "Responde al primer aro con palmada sin perder la síncopa ni los huecos.", difficulty: "clap-orchestration", bpm: 72, bars: 1, notes: withClap),
    RouteExercise(file: "10_hh_05_half_time", title: "Hip-hop 5 · Half-time con respuesta", objective: "Lleva el aro al tercer pulso y deja la palmada como respuesta final.", difficulty: "half-time-placement", bpm: 72, bars: 1, notes: halfTime),
    RouteExercise(file: "10_hh_06_dos_compases", title: "Hip-hop 6 · Pregunta y respuesta", objective: "Alterna la anticipación del primer compás con el bombo de cierre del segundo.", difficulty: "two-bar-kick-answer", bpm: 72, bars: 2, notes: phrase),
    RouteExercise(file: "10_hh_07_charles_16", title: "Hip-hop 7 · Ráfagas de charles", objective: "Añade semicorcheas al cierre sin perder el half-time ni la respuesta de bombo.", difficulty: "hihat-bursts", bpm: 72, bars: 2, notes: rollPhrase),
    RouteExercise(file: "10_hh_09_abierto", title: "Hip-hop 8 · Aperturas sobre las ráfagas", objective: "Abre el charles en el segundo contratiempo conservando el half-time, las ráfagas y la respuesta de bombo.", difficulty: "hiphop-open-hihat", bpm: 72, bars: 2, notes: openPhrase),
    RouteExercise(file: "10_hh_10_caja", title: "Hip-hop 9 · Caja de respuesta", objective: "Responde al aro del primer compás con caja en el segundo sin mover el bombo ni el charles.", difficulty: "half-time-snare-answer", bpm: 72, bars: 2, notes: snareAnswer),
    RouteExercise(file: "10_hh_11_palmada", title: "Hip-hop 10 · Palmada anticipada", objective: "Añade una palmada antes del cuarto pulso conservando las respuestas de aro y caja.", difficulty: "anticipated-clap", bpm: 72, bars: 2, notes: clapAnswer),
    RouteExercise(file: "10_hh_12_retorno", title: "Hip-hop 11 · Cuatro compases con retorno", objective: "Une dos frases conocidas y reserva el fill de toms para preparar la vuelta al inicio.", difficulty: "hiphop-four-bar-return", bpm: 72, bars: 4, notes: returnPhrase),
    RouteExercise(file: "10_hh_08_fill_cierre", title: "Hip-hop 12 · Frase hip-hop completa", objective: "Integra aro, caja, palmada, aperturas, síncopa, silencios y ráfagas antes del fill de toms.", difficulty: "hiphop-phrase-integration", bpm: 72, bars: 4, notes: checkpoint)
]
func vlq(_ value: Int) -> [UInt8] { var v = value; var bytes = [UInt8(v & 0x7F)]; v >>= 7; while v > 0 { bytes.append(UInt8((v & 0x7F) | 0x80)); v >>= 7 }; return bytes.reversed() }
func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16), UInt8(v >> 8), UInt8(v & 0xFF)] }
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
for (index, exercise) in exercises.enumerated() {
    let tempo = 60_000_000 / exercise.bpm; let title = Array(exercise.title.utf8); let ppq = 480
    let bars = exercise.bars
    let notes = exercise.notes
    precondition(notes.allSatisfy { $0.0 >= 0 && $0.0 < bars * 16 }, "Paso fuera de frase: \(exercise.file)")
    precondition(Set(notes.map { "\($0.0):\($0.1)" }).count == notes.count, "Golpe duplicado: \(exercise.file)")
    precondition(Dictionary(grouping: notes, by: { $0.0 }).values.allSatisfy { $0.count <= 2 }, "Tres voces simultáneas: \(exercise.file)")
    var events: [(Int, Int, [UInt8])] = [(0,0,[0xFF,0x03] + vlq(title.count) + title),(0,1,[0xFF,0x51,0x03,UInt8((tempo >> 16) & 0xFF),UInt8((tempo >> 8) & 0xFF),UInt8(tempo & 0xFF)]),(0,2,[0xFF,0x58,0x04,0x04,0x02,0x18,0x08])]
    var metadata = ["xroll/1 id=\(exercise.file)", "xroll/1 chapter=hiphop", "xroll/1 position=\(index + 1)", "xroll/1 objective=\(exercise.objective)", "xroll/1 new-difficulty=\(exercise.difficulty)", "xroll/1 recommended-help=\(index == exercises.count - 1 ? "normal" : "full")"]
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
