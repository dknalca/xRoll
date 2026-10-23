import Foundation

typealias Hit = (Int, Int)
struct Lesson {
    let id: String
    let title: String
    let objective: String
    let hits: [Hit]
    var bars = 1
}
let q = [0,4,8,12]
let e = [0,2,4,6,8,10,12,14]
func phrase(_ bars: [[Hit]]) -> [Hit] {
    bars.enumerated().flatMap { bar, notes in notes.map { ($0.0 + bar * 16, $0.1) } }
}
func replace(_ notes: [Hit], sound: Int, with replacement: Int, at step: Int) -> [Hit] {
    notes.map { ($0.0, $0.0 == step && $0.1 == sound ? replacement : $0.1) }
}

// Fundamentos continúa el groove de corcheas de Iniciación, sin volver a un
// esqueleto de dos voces. Cada paso conserva el patrón y cambia una idea.
let foundationBase: [Hit] = e.map { ($0,42) } + [(0,36),(8,36),(10,36),(4,38),(12,38)]
let foundationSnare = foundationBase + [(6,38)]
let foundationDouble = foundationSnare + [(2,36)]
let foundationSpace = foundationDouble.filter { !($0.1 == 42 && [2,10].contains($0.0)) }
let foundationFinish = foundationSpace.filter { !($0.0 == 6 && $0.1 == 38) } + [(14,38)]

// Coordinación trabaja parejas y alternancia sobre el mismo groove completo.
let coordinationSpace = foundationFinish.filter { !($0.1 == 42 && [4,12].contains($0.0)) }
let coordinationPairs = foundationFinish.filter { !($0.1 == 42 && [0,8].contains($0.0)) }
let coordinationAnswer = coordinationPairs + [(6,36)]
let coordinationOpen = replace(coordinationAnswer, sound: 42, with: 46, at: 14)
let coordinationClap = replace(coordinationOpen, sound: 38, with: 39, at: 12)
let coordinationPickup = coordinationClap + [(15,39)]

// Subdivisión conserva las voces aprendidas. La lección de corcheas también
// aporta el motor MIDI del que la calibración aísla únicamente el charles.
let subdivisionOffbeats = coordinationPickup.filter { !($0.1 == 42 && [4,12].contains($0.0)) }
let subdivisionClosedMotor = subdivisionOffbeats.filter { ![42,46].contains($0.1) } + e.map { ($0,42) }
let subdivisionMotor = replace(subdivisionClosedMotor, sound: 42, with: 46, at: 14)
let subdivisionKick = subdivisionMotor.filter { !($0.0 == 8 && $0.1 == 36) && !($0.0 == 14 && $0.1 == 46) } + [(14,36)]
let subdivisionShifted = subdivisionKick.filter { !($0.0 == 4 && $0.1 == 38) && !($0.0 == 6 && $0.1 == 42) } + [(6,38)]
let subdivisionSixteenth = subdivisionShifted + [(5,42)]
let subdivisionKickSixteenth = subdivisionSixteenth.filter { !($0.0 == 10 && $0.1 == 36) } + [(11,36)]
let subdivisionBurst = subdivisionKickSixteenth + [(9,42),(13,42)]

// Fraseo añade respuestas y orquesta un mismo cierre antes de integrarlo.
let grooveSpace = subdivisionBurst.filter { !($0.0 == 9 && $0.1 == 42) }
let grooveSyncopated = grooveSpace.filter { !($0.0 == 2 && $0.1 == 36) } + [(3,36)]
let grooveClapAnswer = grooveSyncopated + [(7,39)]
let grooveClapFill = grooveClapAnswer.filter { $0.0 < 12 } + [(12,39),(14,39)]
let grooveTomFill = grooveClapFill.filter { $0.0 < 12 } + [(12,48),(14,41)]
let grooveCrash = replace(grooveTomFill, sound: 42, with: 49, at: 0)

let lessons: [Lesson] = [
    .init(id: "01_fund_01_pulso", title: "Fundamentos 1 · Bombo de respuesta", objective: "Conserva el groove de corcheas y añade un bombo en tres y.", hits: foundationBase),
    .init(id: "01_fund_02_backbeat", title: "Fundamentos 2 · Caja de respuesta", objective: "Añade una caja en dos y sin mover las otras voces.", hits: foundationSnare),
    .init(id: "01_fund_03_charles_negras", title: "Fundamentos 3 · Bombo doble de entrada", objective: "Añade un bombo en uno y manteniendo las respuestas anteriores.", hits: foundationDouble),
    .init(id: "01_fund_04_charles_corcheas", title: "Fundamentos 4 · Espacio entre respuestas", objective: "Retira dos charles entre pulsos y conserva las respuestas de bombo y caja.", hits: foundationSpace),
    .init(id: "01_fund_05_bombo_doble", title: "Fundamentos 5 · Caja de enlace", objective: "Lleva la caja de respuesta de dos y a cuatro y sin cambiar el bombo.", hits: foundationFinish),
    .init(id: "01_fund_06_control", title: "Fundamentos 6 · Frase de respuestas", objective: "Une los patrones conocidos en cuatro compases sin cambiar su pulso.", hits: phrase([foundationBase,foundationSnare,foundationDouble,foundationFinish]), bars: 4),

    .init(id: "03_coord_01_alternancia", title: "Coordinación 1 · Caja entre charles", objective: "Retira el charles de dos y cuatro para alternarlo con la caja, manteniendo el groove.", hits: coordinationSpace),
    .init(id: "03_coord_02_kick_hh", title: "Coordinación 2 · Cambia de pareja", objective: "Lleva el charles a la caja y deja solos los bombos de uno y tres.", hits: coordinationPairs),
    .init(id: "03_coord_03_snare_hh", title: "Coordinación 3 · Respuesta entre parejas", objective: "Añade bombo en dos y sin alterar las parejas de caja y charles.", hits: coordinationAnswer),
    .init(id: "03_coord_04_parejas", title: "Coordinación 4 · Apertura de cierre", objective: "Sustituye el último charles cerrado por abierto; conserva las demás voces.", hits: coordinationOpen),
    .init(id: "03_coord_05_abre_cierra", title: "Coordinación 5 · Abre y cierra en frase", objective: "Alterna un compás con apertura y otro con cierre conservando bombo y caja.", hits: phrase([coordinationOpen,coordinationAnswer]), bars: 2),
    .init(id: "03_coord_06_palmada", title: "Coordinación 6 · Palmada de respuesta", objective: "Sustituye la caja de cuatro por palmada sin sumar una tercera voz.", hits: coordinationClap),
    .init(id: "03_coord_07_repite", title: "Coordinación 7 · Palmada de enlace", objective: "Añade una palmada al último paso para anticipar la vuelta.", hits: coordinationPickup),
    .init(id: "03_coord_08_independencia", title: "Coordinación 8 · Frase de independencia", objective: "Une alternancia, parejas, aperturas y palmada en una frase ya preparada.", hits: phrase([coordinationSpace,coordinationPairs,coordinationOpen,coordinationPickup]), bars: 4),

    .init(id: "02_sub_01_corchea_aislada", title: "Subdivisión 1 · Contratiempos en contexto", objective: "Deja los charles entre pulsos conservando bombo, caja y palmada.", hits: subdivisionOffbeats),
    .init(id: "02_sub_02_corcheas", title: "Subdivisión 2 · Corcheas sobre las respuestas", objective: "Completa el motor de corcheas sin retirar las respuestas de bombo, caja y palmada.", hits: subdivisionClosedMotor),
    .init(id: "02_sub_03_groove", title: "Subdivisión 3 · Abierto sobre el motor", objective: "Sustituye el último charles por abierto, conservando las corcheas y el resto del groove.", hits: subdivisionMotor),
    .init(id: "02_sub_04_bombo_y", title: "Subdivisión 4 · Bombo en cuatro y", objective: "Desplaza el bombo de tres al y de cuatro; el abierto cede para tocar bombo y caja juntos.", hits: subdivisionKick),
    .init(id: "02_sub_05_caja_y", title: "Subdivisión 5 · Caja desplazada", objective: "Lleva la caja de dos al y; el charles cede cuando coincide la pareja de bombo y caja.", hits: subdivisionShifted),
    .init(id: "02_sub_06_16_aislada", title: "Subdivisión 6 · Primera semicorchea de charles", objective: "Añade un charles en el paso intermedio antes de la caja desplazada.", hits: subdivisionSixteenth),
    .init(id: "02_sub_07_una_16", title: "Subdivisión 7 · Bombo en semicorchea", objective: "Retrasa un paso el bombo de tres y, manteniendo el patrón conocido.", hits: subdivisionKickSixteenth),
    .init(id: "02_sub_08_consolidacion", title: "Subdivisión 8 · Ráfaga corta de charles", objective: "Añade dos semicorcheas de charles sin acelerar ni cambiar el bombo.", hits: subdivisionBurst),
    .init(id: "02_sub_09_frase_integrada", title: "Subdivisión 9 · Frase integrada", objective: "Une corcheas, caja desplazada y ráfagas cortas sin novedades en el cierre.", hits: phrase([subdivisionClosedMotor,subdivisionMotor,subdivisionShifted,subdivisionBurst]), bars: 4),

    .init(id: "04_groove_01_silencio", title: "Groove 1 · Respiración de charles", objective: "Deja un hueco en la ráfaga conocida sin perder el resto del ritmo.", hits: grooveSpace),
    .init(id: "04_groove_02_sincopa", title: "Groove 2 · Anticipación de bombo", objective: "Desplaza un paso el segundo bombo para anticipar el pulso siguiente.", hits: grooveSyncopated),
    .init(id: "04_groove_03_respuesta", title: "Groove 3 · Respuesta de palmada", objective: "Añade una palmada después de la caja desplazada.", hits: grooveClapAnswer),
    .init(id: "04_groove_04_fill_palmada", title: "Groove 4 · Cierre de palmada", objective: "Sustituye el último pulso por dos palmadas y vuelve al groove.", hits: grooveClapFill),
    .init(id: "04_groove_05_toms", title: "Groove 5 · El mismo cierre en toms", objective: "Lleva las dos palmadas al tom agudo y grave sin cambiar su ritmo.", hits: grooveTomFill),
    .init(id: "04_groove_06_crash", title: "Groove 6 · Crash de entrada", objective: "Sustituye el primer charles por crash y conserva el cierre de toms.", hits: grooveCrash),
    .init(id: "04_groove_07_completo", title: "Groove 7 · Frase completa", objective: "Integra respiración, síncopa, palmada y cierre con crash en cuatro compases conocidos.", hits: phrase([grooveSpace,grooveClapAnswer,grooveClapFill,grooveCrash]), bars: 4)
]

func chapter(for id: String) -> String {
    switch id.split(separator: "_")[1] {
    case "fund": return "fundamentals"
    case "coord": return "coordination"
    case "sub": return "subdivision"
    default: return "groove"
    }
}
let chapterCounts = Dictionary(grouping: lessons, by: { chapter(for: $0.id) }).mapValues(\.count)
let firstPrerequisite = ["fundamentals": "00_i_03_ritmo_completo", "coordination": "01_fund_06_control",
    "subdivision": "03_coord_08_independencia", "groove": "02_sub_09_frase_integrada"]
func vlq(_ value: Int) -> [UInt8] {
    var value = value; var bytes = [UInt8(value & 127)]; value >>= 7
    while value > 0 { bytes.append(UInt8((value & 127) | 128)); value >>= 7 }
    return bytes.reversed()
}
func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }
func be32(_ value: Int) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value & 255)] }
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
var previousByChapter = [String: String]()
var positionByChapter = [String: Int]()
for lesson in lessons {
    let chapter = chapter(for: lesson.id)
    let position = positionByChapter[chapter, default: 0] + 1
    let prerequisite = previousByChapter[chapter] ?? firstPrerequisite[chapter]!
    precondition(lesson.hits.allSatisfy { $0.0 >= 0 && $0.0 < lesson.bars * 16 }, lesson.id)
    precondition(Set(lesson.hits.map { "\($0.0):\($0.1)" }).count == lesson.hits.count, lesson.id)
    precondition(Dictionary(grouping: lesson.hits, by: { $0.0 }).values.allSatisfy { $0.count <= 2 }, lesson.id)
    let bpm = chapter == "fundamentals" ? 70 : 72
    let title = Array(lesson.title.utf8); let tempo = 60_000_000 / bpm
    var events: [(Int, Int, [UInt8])] = [(0,0,[255,3] + vlq(title.count) + title),
        (0,1,[255,81,3,UInt8((tempo >> 16) & 255),UInt8((tempo >> 8) & 255),UInt8(tempo & 255)]),
        (0,2,[255,88,4,4,2,24,8])]
    var metadata = ["xroll/1 id=\(lesson.id)", "xroll/1 chapter=\(chapter)", "xroll/1 position=\(position)",
        "xroll/1 prerequisite=\(prerequisite)", "xroll/1 objective=\(lesson.objective)",
        "xroll/1 new-difficulty=\(chapter)-\(position)", "xroll/1 recommended-help=full"]
    if position == chapterCounts[chapter] { metadata.append("xroll/1 flag=checkpoint") }
    for (index, text) in metadata.enumerated() { let bytes = Array(text.utf8); events.append((0,3 + index,[255,1] + vlq(bytes.count) + bytes)) }
    for (step,note) in lesson.hits { let tick = step * 120; events.append((tick,100,[153,UInt8(note),100])); events.append((tick + 60,99,[137,UInt8(note),0])) }
    events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    var track = [UInt8](); var previous = 0
    for event in events { track += vlq(event.0 - previous) + event.2; previous = event.0 }
    track += vlq(max(0, 1_920 * lesson.bars - previous)) + [255,47,0]
    let midi = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(480) + Array("MTrk".utf8) + be32(track.count) + track
    try Data(midi).write(to: directory.appendingPathComponent(lesson.id + ".mid"), options: .atomic)
    previousByChapter[chapter] = lesson.id; positionByChapter[chapter] = position
}
