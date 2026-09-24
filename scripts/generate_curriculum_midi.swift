import Foundation
struct E {
 let f:String; let t:String; let bpm:Int; let bars:Int; let n:[(Int,Int)]
 init(f: String, t: String, bpm: Int, bars: Int = 1, n: [(Int, Int)]) {
  self.f = f; self.t = t; self.bpm = bpm; self.bars = bars; self.n = n
 }
}
let q=[0,4,8,12], e=[0,2,4,6,8,10,12,14], s=Array(0...15)
let groove=q.map{($0,42)}+[(0,36),(4,38),(8,36),(12,38)]
let shiftedSnare = e.map { ($0,42) } + [(0,36),(6,38),(8,36),(14,38)]
let doubleKick = e.map { ($0,42) } + [(0,36),(2,36),(4,38),(8,36),(12,38)]
let integratedSubdivision = shiftedSnare
    + shiftedSnare.map { ($0.0 + 16, $0.1) }
    + doubleKick.map { ($0.0 + 32, $0.1) }
    + doubleKick.map { ($0.0 + 48, $0.1) }
let completeGroove = e.map { ($0,42) } + [(0,49),(0,36),(4,38),(6,36),(8,36),(12,39),(14,48)]
let completePhrase = completeGroove
    + completeGroove.map { ($0.0 + 16, $0.1) }
    + completeGroove.map { ($0.0 + 32, $0.1) }
    + completeGroove.map { ($0.0 + 48, $0.1) }
let fundamentalsBar1: [(Int, Int)] = q.map { ($0, 42) } + [(0, 36), (4, 38), (8, 36), (12, 38)]
let fundamentalsBar2: [(Int, Int)] = e.map { ($0 + 16, 42) } + [(16, 36), (20, 38), (24, 36), (26, 36), (28, 38)]
let fundamentalsBar3: [(Int, Int)] = e.map { ($0 + 32, 42) } + [(32, 36), (34, 36), (36, 38), (40, 36), (44, 38)]
let fundamentalsBar4: [(Int, Int)] = e.map { ($0 + 48, 42) } + [(48, 36), (50, 36), (54, 36), (52, 38), (60, 38)]
let fundamentalsCheckpoint = fundamentalsBar1 + fundamentalsBar2 + fundamentalsBar3 + fundamentalsBar4
let subdivisionBar1: [(Int, Int)] = e.map { ($0, 42) } + [(0, 36), (4, 38), (8, 36), (12, 38)]
let subdivisionBar2: [(Int, Int)] = s.map { ($0 + 16, 42) } + [(16, 36), (20, 38), (24, 36), (28, 38)]
let subdivisionBar3: [(Int, Int)] = e.map { ($0 + 32, 42) } + [(32, 36), (38, 36), (36, 38), (44, 38)]
let subdivisionBar4: [(Int, Int)] = e.map { ($0 + 48, 42) } + [(48, 36), (50, 36), (58, 36), (52, 38), (60, 38)]
let subdivisionCheckpoint = subdivisionBar1 + subdivisionBar2 + subdivisionBar3 + subdivisionBar4
let coordinationBar1: [(Int, Int)] = e.map { ($0, 42) } + [(0, 36), (2, 38), (4, 36), (6, 38), (8, 36), (10, 38), (12, 36), (14, 38)]
let coordinationBar2: [(Int, Int)] = q.map { ($0 + 16, 42) } + q.map { ($0 + 16, 36) } + [(20, 38), (28, 38)]
let coordinationBar3: [(Int, Int)] = q.map { ($0 + 32, 42) } + [(32, 36), (36, 38), (40, 36), (44, 38)]
let coordinationBar4: [(Int, Int)] = [(48, 42), (52, 46), (56, 42), (60, 46), (48, 36), (52, 38), (56, 36), (60, 39)]
let coordinationCheckpoint = coordinationBar1 + coordinationBar2 + coordinationBar3 + coordinationBar4
let grooveBar1: [(Int, Int)] = [0, 4, 10].map { ($0, 42) } + [(0, 36), (4, 38), (8, 36), (12, 38)]
let grooveBar2: [(Int, Int)] = e.map { ($0 + 16, 42) } + [(16, 36), (22, 36), (26, 36), (20, 38), (28, 38)]
let grooveBar3: [(Int, Int)] = q.map { ($0 + 32, 42) } + [(32, 36), (36, 38), (38, 39), (40, 36), (44, 38), (46, 39), (44, 41), (46, 48)]
let grooveBar4: [(Int, Int)] = e.map { ($0 + 48, 42) } + [(48, 49), (48, 36), (52, 38), (54, 36), (56, 36), (60, 38), (62, 49)]
let grooveCheckpoint = grooveBar1 + grooveBar2 + grooveBar3 + grooveBar4
let defs:[E] = [
 // Fundamentos parte del I-03 ya dominado: ningún escalón duplica literalmente
 // Iniciación. Cada uno conserva la idea anterior y suma solo una novedad.
 E(f:"01_fund_01_pulso",t:"Fundamentos 1 · Bombo de respuesta",bpm:70,n:[(0,36),(4,38),(8,36),(10,36),(12,38)]), E(f:"01_fund_02_backbeat",t:"Fundamentos 2 · Charles a negras con respuesta",bpm:70,n:q.map{($0,42)}+[(0,36),(4,38),(8,36),(10,36),(12,38)]), E(f:"01_fund_03_charles_negras",t:"Fundamentos 3 · Primera corchea",bpm:70,n:q.map{($0,42)}+[(2,42),(0,36),(4,38),(8,36),(10,36),(12,38)]), E(f:"01_fund_04_charles_corcheas",t:"Fundamentos 4 · Charles a corcheas con respuesta",bpm:70,n:e.map{($0,42)}+[(0,36),(4,38),(6,36),(8,36),(12,38)]), E(f:"01_fund_05_bombo_doble",t:"Fundamentos 5 · Bombo doble de entrada",bpm:70,n:e.map{($0,42)}+[(0,36),(2,36),(4,38),(8,36),(10,36),(12,38)]), E(f:"01_fund_06_control",t:"Fundamentos 6 · Dos respuestas de bombo",bpm:70,n:e.map{($0,42)}+[(0,36),(2,36),(4,38),(6,36),(8,36),(10,36),(12,38)]),
 E(f:"02_sub_01_corchea_aislada",t:"Subdivisión 1 · Entre los pulsos",bpm:72,n:[(2,42),(6,42),(10,42),(14,42)]), E(f:"02_sub_02_corcheas",t:"Subdivisión 2 · Corcheas continuas",bpm:72,n:e.map{($0,42)}), E(f:"02_sub_03_groove",t:"Subdivisión 3 · Groove con respuesta",bpm:72,n:e.map{($0,42)}+[(0,36),(4,38),(8,36),(10,36),(12,38)]), E(f:"02_sub_04_bombo_y",t:"Subdivisión 4 · Bombo en el y",bpm:72,n:e.map{($0,42)}+[(0,36),(6,36),(4,38),(12,38)]), E(f:"02_sub_05_caja_y",t:"Subdivisión 5 · Caja desplazada",bpm:72,n:e.map{($0,42)}+[(0,36),(6,38),(8,36),(14,38)]), E(f:"02_sub_06_16_aislada",t:"Subdivisión 6 · Semicorcheas aisladas",bpm:68,n:[(1,42),(5,42),(9,42),(13,42)]), E(f:"02_sub_07_una_16",t:"Subdivisión 7 · Una semicorchea",bpm:68,n:e.map{($0,42)}+[(0,36),(5,36),(4,38),(12,38)]), E(f:"02_sub_08_consolidacion",t:"Subdivisión 8 · Consolidación",bpm:78,n:e.map{($0,42)}+[(0,36),(5,36),(8,36),(12,38)]), E(f:"02_sub_09_frase_integrada",t:"Subdivisión 9 · Frase integrada",bpm:78,bars:4,n:integratedSubdivision),
 E(f:"03_coord_01_alternancia",t:"Coordinación 1 · Dos manos",bpm:72,n:e.enumerated().map{($0.offset*2,$0.offset.isMultiple(of:2) ? 36:38)}), E(f:"03_coord_02_kick_hh",t:"Coordinación 2 · Bombo y charles",bpm:72,n:q.map{($0,36)}+q.map{($0,42)}), E(f:"03_coord_03_snare_hh",t:"Coordinación 3 · Caja y charles",bpm:72,n:[(4,38),(12,38),(4,42),(12,42)]), E(f:"03_coord_04_parejas",t:"Coordinación 4 · Parejas alternas",bpm:72,n:[(0,36),(0,42),(4,38),(6,42),(8,36),(8,42),(12,38),(14,42)]), E(f:"03_coord_05_abre_cierra",t:"Coordinación 5 · Abre y cierra",bpm:72,n:[(0,42),(4,46),(8,42),(12,46)]), E(f:"03_coord_06_palmada",t:"Coordinación 6 · Refuerza dos y cuatro",bpm:72,n:groove+[(4,39),(12,39)]), E(f:"03_coord_07_repite",t:"Coordinación 7 · Repetición con cierre",bpm:72,n:e.map{($0,42)}+[(0,36),(4,38),(8,36),(10,36),(12,38),(14,39)]), E(f:"03_coord_08_independencia",t:"Coordinación 8 · Prueba",bpm:72,n:e.map{($0,42)}+[(0,36),(6,36),(4,38),(12,39)]),
 E(f:"04_groove_01_silencio",t:"Groove 1 · Valor del silencio",bpm:72,n:[(0,42),(4,42),(10,42)]+[(0,36),(4,38),(8,36),(12,38)]), E(f:"04_groove_02_sincopa",t:"Groove 2 · Bombo sincopado",bpm:72,n:e.map{($0,42)}+[(0,36),(6,36),(10,36),(4,38),(12,38)]), E(f:"04_groove_03_respuesta",t:"Groove 3 · Respuesta de palmada",bpm:72,n:groove+[(6,39),(14,39)]), E(f:"04_groove_04_fill_palmada",t:"Groove 4 · Fill de palmada",bpm:72,n:groove+[(12,39),(14,39)]), E(f:"04_groove_05_toms",t:"Groove 5 · Fill de toms",bpm:72,n:groove+[(12,41),(14,48)]), E(f:"04_groove_06_crash",t:"Groove 6 · Crash de entrada",bpm:72,n:groove+[(0,49)]), E(f:"04_groove_07_completo",t:"Groove 7 · Groove completo",bpm:72,bars:4,n:completePhrase)]
let checkpointOverrides: [String: (bars: Int, hits: [(Int, Int)])] = [
    "01_fund_06_control": (4, fundamentalsCheckpoint),
    "02_sub_09_frase_integrada": (4, subdivisionCheckpoint),
    "03_coord_08_independencia": (4, coordinationCheckpoint),
    "04_groove_07_completo": (4, grooveCheckpoint)
]
func vlq(_ x:Int)->[UInt8]{var v=x;var a=[UInt8(v&127)];v >>= 7;while v>0{a.append(UInt8((v&127)|128));v >>= 7};return a.reversed()};func b16(_ x:Int)->[UInt8]{[UInt8(x>>8),UInt8(x&255)]};func b32(_ x:Int)->[UInt8]{[UInt8(x>>24),UInt8(x>>16),UInt8(x>>8),UInt8(x&255)]}
let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
let firstPrerequisite = [
    "fundamentals": "00_i_03_ritmo_completo",
    "subdivision": "01_fund_06_control",
    "coordination": "02_sub_09_frase_integrada",
    "groove": "03_coord_08_independencia"
]
let checkpointPosition = ["fundamentals": 6, "subdivision": 9, "coordination": 8, "groove": 7]
var previousByChapter = [String: String]()
for x in defs {
    let components = x.f.split(separator: "_")
    let chapter: String
    switch components[1] {
    case "fund": chapter = "fundamentals"
    case "sub": chapter = "subdivision"
    case "coord": chapter = "coordination"
    default: chapter = "groove"
    }
    let position = Int(components[2])!
    let prerequisite = previousByChapter[chapter] ?? firstPrerequisite[chapter]!
    let checkpoint = checkpointPosition[chapter] == position
    let override = checkpointOverrides[x.f]
    let bars = override?.bars ?? x.bars
    let hits = override?.hits ?? x.n
    let ppq = 480, tempo = 60_000_000 / x.bpm, title = Array(x.t.utf8)
    var events: [(Int, Int, [UInt8])] = [
        (0, 0, [255, 3] + vlq(title.count) + title),
        (0, 1, [255, 81, 3, UInt8((tempo >> 16) & 255), UInt8((tempo >> 8) & 255), UInt8(tempo & 255)]),
        (0, 2, [255, 88, 4, 4, 2, 24, 8])
    ]
    var metadata = ["xroll/1 id=\(x.f)", "xroll/1 chapter=\(chapter)", "xroll/1 position=\(position)", "xroll/1 prerequisite=\(prerequisite)", "xroll/1 objective=\(x.t)", "xroll/1 new-difficulty=\(chapter)-\(position)", "xroll/1 recommended-help=full"]
    if checkpoint { metadata.append("xroll/1 flag=checkpoint") }
    for (index, text) in metadata.enumerated() { let bytes = Array(text.utf8); events.append((0, 3 + index, [255, 1] + vlq(bytes.count) + bytes)) }
    for (step, note) in hits { let tick = step * ppq / 4; events.append((tick, 100, [153, UInt8(note), 100])); events.append((tick + 60, 99, [137, UInt8(note), 0])) }
    events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    var track = [UInt8](), last = 0
    for event in events { track += vlq(event.0 - last) + event.2; last = event.0 }
    track += vlq(max(0, ppq * 4 * bars - last)) + [255, 47, 0]
    let midi = Array("MThd".utf8) + b32(6) + b16(0) + b16(1) + b16(ppq) + Array("MTrk".utf8) + b32(track.count) + track
    try Data(midi).write(to: dir.appendingPathComponent(x.f).appendingPathExtension("mid"), options: .atomic)
    previousByChapter[chapter] = x.f
}
