import Foundation

typealias Hit = (Int, Int)
struct Definition {
    let id: String
    let title: String
    let bpm: Int
    let grid: Int
    let bars: Int
    let hits: [Hit]
    let objective: String
    let difficulty: String
    let checkpoint: Bool

    init(id: String, title: String, bpm: Int, grid: Int = 16, bars: Int = 1,
         hits: [Hit], objective: String, difficulty: String, checkpoint: Bool = false) {
        self.id = id; self.title = title; self.bpm = bpm; self.grid = grid
        self.bars = bars; self.hits = hits; self.objective = objective
        self.difficulty = difficulty; self.checkpoint = checkpoint
    }
}

let e = [0, 2, 4, 6, 8, 10, 12, 14]
let tripletEighths = [0, 2, 3, 5, 6, 8, 9, 11]
func shifted(_ hits: [Hit], by steps: Int) -> [Hit] { hits.map { ($0.0 + steps, $0.1) } }
func phrase(_ bars: [[Hit]], grid: Int = 16) -> [Hit] {
    bars.enumerated().flatMap { shifted($0.element, by: $0.offset * grid) }
}
func voice(_ hits: [Hit], from source: Int, to destination: Int, at steps: [Int]? = nil) -> [Hit] {
    hits.map { (step, note) in
        (step, note == source && (steps?.contains(step) ?? true) ? destination : note)
    }
}
func ending(_ hits: [Hit], from step: Int, with fill: [Hit]) -> [Hit] {
    hits.filter { $0.0 < step } + shifted(fill, by: step)
}
// Si coinciden bombo y aro/caja, cede el motor de platos: como máximo dos
// sonidos simultáneos, sin perder ninguna nota de la célula principal.
func withMotor(_ rhythm: [Hit], steps: [Int], sound: Int = 42) -> [Hit] {
    rhythm + steps.filter { step in rhythm.filter { $0.0 == step }.count < 2 }.map { ($0, sound) }
}

// Rock: anticipación → crash → fill → ride → doble → apertura → contraste.
let rockBar = e.map { ($0,42) } + [(0,36),(4,38),(6,36),(8,36),(12,38),(14,36)]
let rockPhrase = phrase([rockBar, rockBar + [(15,36)]])
let rockCrash = voice(rockPhrase, from: 42, to: 49, at: [0])
let rockFill = ending(rockCrash, from: 28, with: [(0,48),(1,48),(2,41),(3,41)])
let rockRide = voice(rockCrash, from: 42, to: 51)
let rockDouble = rockRide + [(18,36)]
let rockOpen = voice(rockDouble, from: 51, to: 46, at: [6,14,22,30])
let rockContrast = rockOpen + shifted(ending(rockDouble, from: 28, with: [(0,48),(1,48),(2,41),(3,41)]), by: 32)
let rockCheckpoint = rockCrash + shifted(rockDouble, by: 32) + shifted(rockOpen, by: 64)
    + shifted(ending(rockOpen, from: 28, with: [(0,48),(1,48),(2,41),(3,41)]), by: 96)

// Disco: las negras del bombo continúan bajo las variaciones del charles.
let disco = [0,2,6,8,10,14].map { ($0,42) } + [(0,36),(4,36),(8,36),(12,36),(4,38),(12,38)]
let discoOpen = voice(disco, from: 42, to: 46, at: [14])
let discoOffbeats = voice(discoOpen, from: 42, to: 46, at: [2,6,10])
let discoClap = voice(discoOffbeats, from: 38, to: 39, at: [12])
let discoLink = discoClap + [(15,36)]
let discoSpace = discoLink.filter { !($0.1 == 46 && [6,14].contains($0.0)) }
let discoPhrase = phrase([discoLink, discoSpace])
let discoFillBar = discoSpace.filter { $0.0 < 12 } + [(12,36),(12,48),(14,41),(15,36),(15,38)]
let discoFill = phrase([discoLink, discoFillBar])
let discoCheckpoint = phrase([disco, discoOffbeats, discoLink, discoFillBar])

// Funk: la síncopa de bombo sigue presente al retirar/orquestar otras voces.
let funkBase = Array(0..<16).map { ($0,42) } + [(0,36),(3,36),(4,38),(8,36),(11,36),(12,38)]
let funkSpace = funkBase.filter { !($0.1 == 42 && [4,12].contains($0.0)) }
let funkDisplaced = funkSpace.filter { !($0.0 == 12 && $0.1 == 38) } + [(14,38)]
let funkClap = voice(funkDisplaced, from: 38, to: 39, at: [14])
let funkOpen = voice(funkClap, from: 42, to: 46, at: [6,14])
let funkRim = voice(funkOpen, from: 38, to: 37, at: [4])
let funkFillBar = ending(funkRim, from: 12, with: [(0,36),(1,38),(2,48),(3,41)])
let funkLinear = phrase([funkRim, funkFillBar])
let funkCheckpoint = phrase([funkBase, funkDisplaced, funkOpen, funkFillBar])

// Reggae: grooves completos desde el primer paso; one drop, rockers y
// steppers se distinguen por el bombo, manteniendo el resto de la frase.
let reggaeOneDrop = [0,2,4,6,10,12,14].map { ($0,42) } + [(8,36),(6,37),(8,37),(14,37)]
let reggaeAnswer = reggaeOneDrop.filter { !($0.0 == 14 && $0.1 == 37) } + [(15,37)]
let reggaePhrase = phrase([reggaeOneDrop, reggaeAnswer])
let reggaeOpen = voice(reggaePhrase, from: 42, to: 46, at: [6,14,22,30])
let reggaeRim = reggaeOpen + [(29,37)]
let reggaeClap = voice(reggaeRim, from: 37, to: 39, at: [24])
let reggaeTom = voice(reggaeClap, from: 42, to: 48, at: [28])
let reggaeRockers = reggaeTom + [(0,36),(16,36)]
let reggaeSteppers = reggaeRockers + [(4,36),(12,36),(20,36),(28,36)]
let reggaeClosingBar = voice(reggaeSteppers.filter { $0.0 >= 16 }.map { ($0.0 - 16,$0.1) }, from: 46, to: 41, at: [14])
let reggaeCheckpoint = phrase([
    reggaeOneDrop,
    reggaeTom.filter { $0.0 >= 16 }.map { ($0.0 - 16,$0.1) },
    reggaeRockers.filter { $0.0 < 16 },
    reggaeClosingBar
])

// Dembow: célula estable y respuesta en el segundo compás, antes de sumar voces.
let dembowRhythm: [Hit] = [(0,36),(6,36),(12,36),(4,38),(10,38)]
let dembowBase = phrase([withMotor(dembowRhythm, steps: [0,4,8,12]),
    withMotor(dembowRhythm + [(15,36)], steps: [0,4,8,12])])
let dembowEighths = phrase([withMotor(dembowRhythm, steps: e), withMotor(dembowRhythm + [(15,36)], steps: e)])
let dembowClap = voice(dembowEighths, from: 38, to: 39, at: [26])
let dembowOpen = voice(dembowClap, from: 42, to: 46, at: [14,30])
let dembowKick = dembowOpen + [(3,36),(19,36)]
let dembowRoll = dembowKick + [(29,42),(31,42)]
let dembowFill = ending(dembowRoll, from: 28, with: [(0,38),(1,36),(2,48),(3,41)])
let dembowCheckpoint = phrase([
    dembowEighths.filter { $0.0 < 16 },
    dembowKick.filter { $0.0 < 16 },
    dembowRoll.filter { $0.0 >= 16 }.map { ($0.0 - 16,$0.1) },
    dembowFill.filter { $0.0 >= 16 }.map { ($0.0 - 16,$0.1) }
])

// Blues: la longitud de doce compases es una forma musical, no doce copias.
let bluesBase = tripletEighths.map { ($0,42) } + [(0,36),(3,38),(6,36),(9,38)]
let bluesResponse = tripletEighths.map { ($0,42) } + [(0,36),(3,38),(8,36),(9,38),(11,41)]
let bluesRide = voice(bluesBase, from: 42, to: 51)
let bluesRidePhrase = phrase([bluesRide, bluesRide, bluesRide, bluesRide + [(11,41)]], grid: 12)
let bluesKick = bluesRide + [(5,36)]
let bluesRim = voice(bluesKick, from: 38, to: 37, at: [9])
let bluesReply = bluesRim.filter { !($0.0 == 5 && $0.1 == 36) } + [(11,36)]
let bluesDialogue = phrase([bluesRim, bluesReply], grid: 12)
let bluesFillBar = ending(bluesReply, from: 9, with: [(0,38),(1,48),(2,41)])
let bluesFill = phrase([bluesRim, bluesFillBar], grid: 12)
let bluesCheckpoint = phrase([bluesBase,bluesResponse,bluesRide,bluesKick,
    bluesRim,bluesReply,bluesRide,bluesFillBar,bluesKick,bluesRim,bluesReply,bluesFillBar], grid: 12)

// Jazz: ride largo-corto y comping, no shuffle continuo con otro timbre.
let jazzRide = [0,3,5,6,9,11].map { ($0,51) }
let jazzBase = jazzRide + [(3,38),(9,38)]
let jazzWithKick = jazzBase + [(0,36),(6,36)]
let jazzComping = jazzRide + [(0,36),(6,36),(2,38),(8,38)]
let jazzKick = jazzComping + [(11,36)]
let jazzRim = voice(jazzKick, from: 38, to: 37, at: [8])
let jazzAnswer = jazzRim.filter { !($0.0 == 2 && $0.1 == 38) } + [(5,38)]
let jazzDialogue = phrase([jazzRim, jazzAnswer], grid: 12)
let jazzFillBar = ending(jazzAnswer, from: 9, with: [(0,51),(1,48),(2,41)])
let jazzFill = phrase([jazzRim, jazzFillBar], grid: 12)
let jazzCheckpoint = phrase([jazzWithKick,jazzKick,jazzRim,jazzFillBar], grid: 12)

// Jazz intermedio: conserva el swing aprendido y suma una coordinación
// principal por lección. El charles en 2/4 se toca con pads, no con pedal.
let jazzIntermediateBase = phrase([jazzKick, jazzAnswer], grid: 12)
let jazzTimeA = jazzKick + [(3,42),(9,42)]
let jazzTimeB = jazzAnswer + [(3,42),(9,42)]
let jazzTimekeeping = phrase([jazzTimeA, jazzTimeB], grid: 12)
let jazzInside = jazzTimeA.filter { $0.1 != 38 } + [(1,38),(7,38)]
let jazzInsidePhrase = phrase([jazzTimeA, jazzInside], grid: 12)
let jazzKickComp = jazzInside.filter { !($0.0 == 6 && $0.1 == 36) } + [(8,36)]
let jazzKickDialogue = phrase([jazzInside, jazzKickComp], grid: 12)
let jazzRimDialogue = voice(jazzKickDialogue, from: 38, to: 37, at: [7,19])
let jazzOpenDialogue = voice(jazzRimDialogue, from: 42, to: 46, at: [9,21])
let jazzRideGaps = jazzOpenDialogue.filter { !($0.1 == 51 && [5,17].contains($0.0)) }
let jazzIntermediateFill = ending(jazzRideGaps, from: 21, with: [(0,38),(1,48),(2,41)])
let jazzFourBarPhrase = jazzRideGaps + shifted(jazzIntermediateFill, by: 24)
let jazzTradingFillA = jazzRide + [(0,36),(2,38),(4,48),(7,41),(10,38)]
let jazzTradingFillB = jazzRide + [(0,36),(2,38),(4,41),(7,48),(10,38)]
let jazzTradingClose = ending(jazzTradingFillB, from: 9, with: [(0,38),(1,48),(2,41)])
let jazzTradingFours = jazzFourBarPhrase + shifted(phrase([
    jazzTradingFillA,jazzTradingFillB,jazzTradingFillA,jazzTradingClose], grid: 12), by: 48)
let jazzIntermediateCheckpoint = phrase([
    jazzTimeA,jazzTimeB,jazzInside,jazzKickComp,
    jazzOpenDialogue.filter { $0.0 < 12 },
    jazzRideGaps.filter { $0.0 >= 12 }.map { ($0.0 - 12,$0.1) },
    jazzTradingFillA,jazzTradingClose
], grid: 12)

// Clave de son 3-2/2-3 y bossa: las células siempre tienen acompañamiento.
let claveThreeTwo: [Hit] = [(0,37),(6,37),(12,37),(20,37),(24,37)]
let claveTwoThree: [Hit] = [(4,37),(8,37),(16,37),(22,37),(28,37)]
let bossaBass: [Hit] = [0,6,8,14,16,22,24,30].map { ($0,36) }
let twoBarEighths = e + e.map { $0 + 16 }
let claveThreeTwoGroove = withMotor(bossaBass + claveThreeTwo, steps: twoBarEighths)
let claveTwoThreeGroove = withMotor(bossaBass + claveTwoThree, steps: twoBarEighths)
let claveRide = voice(claveTwoThreeGroove, from: 42, to: 51)
let bossaRim: [Hit] = [(0,37),(6,37),(12,37),(20,37),(26,37)]
let bossaGroove = withMotor(bossaBass + bossaRim, steps: twoBarEighths)
let bossaOpen = voice(bossaGroove, from: 42, to: 46, at: [14,30])
let bossaAnticipation = bossaOpen + [(13,36),(29,36)]
let bossaFill = ending(bossaAnticipation, from: 28, with: [(0,37),(1,48),(2,36),(2,41),(3,37)])
let claveCheckpoint = claveThreeTwoGroove + shifted(claveRide, by: 32) + shifted(bossaFill, by: 64)

// Los IDs históricos no se renumeran. El orden se escribe en position y
// prerequisite; la prueba histórica conserva su ID y queda al final del bloque.
let definitions: [Definition] = [
    .init(id: "20_rock_01_backbeat", title: "Rock 01 · Backbeat con anticipación", bpm: 78, bars: 2, hits: rockPhrase, objective: "Sostén el backbeat y anticipa con bombo la vuelta de cada dos compases.", difficulty: "kick-anticipation"),
    .init(id: "20_rock_02_crash", title: "Rock 02 · Entrada con crash", bpm: 78, bars: 2, hits: rockCrash, objective: "Sustituye el primer charles por crash conservando los bombos anticipados.", difficulty: "crash-entry"),
    .init(id: "20_rock_03_fill", title: "Rock 03 · Fill de toms", bpm: 78, bars: 2, hits: rockFill, objective: "Sustituye el último pulso por un descenso de toms y vuelve al crash.", difficulty: "tom-ending"),
    .init(id: "20_rock_05_ride", title: "Rock 04 · Groove de ride", bpm: 78, bars: 2, hits: rockRide, objective: "Lleva el motor al ride conservando el crash y las anticipaciones.", difficulty: "ride-orchestration"),
    .init(id: "20_rock_06_bombo_doble", title: "Rock 05 · Bombo doble de respuesta", bpm: 78, bars: 2, hits: rockDouble, objective: "Añade un bombo de respuesta en el segundo compás sin mover el ride.", difficulty: "second-bar-double-kick"),
    .init(id: "20_rock_07_abierto", title: "Rock 06 · Aperturas sobre el ride", bpm: 78, bars: 2, hits: rockOpen, objective: "Alterna ride y aperturas de charles manteniendo el doble de bombo.", difficulty: "ride-open-hihat"),
    .init(id: "20_rock_08_contraste", title: "Rock 07 · Dos frases contrastadas", bpm: 78, bars: 4, hits: rockContrast, objective: "Une dos frases conocidas y reserva el descenso de toms para el último pulso.", difficulty: "four-bar-contrast"),
    .init(id: "20_rock_04_resistencia", title: "Rock 08 · Ocho compases con desarrollo", bpm: 78, bars: 8, hits: rockCheckpoint, objective: "Integra crash, ride, dobles, aperturas y fill a lo largo de ocho compases.", difficulty: "rock-integration", checkpoint: true),

    .init(id: "21_funk_01_16", title: "Funk 01 · Semicorcheas sobre síncopas", bpm: 68, hits: funkBase, objective: "Mantén semicorcheas continuas sobre los bombos que anticipan la caja.", difficulty: "sixteenths-over-syncopation"),
    .init(id: "21_funk_02_silencio", title: "Funk 02 · Huecos en el backbeat", bpm: 68, hits: funkSpace, objective: "Retira el charles de dos y cuatro sin perder las síncopas de bombo.", difficulty: "backbeat-gaps"),
    .init(id: "21_funk_03_sincopa", title: "Funk 03 · Caja a contratiempo", bpm: 68, hits: funkDisplaced, objective: "Desplaza la segunda caja al y conservando los huecos y los bombos anticipados.", difficulty: "offbeat-snare"),
    .init(id: "21_funk_05_palmada", title: "Funk 04 · Palmada a contratiempo", bpm: 68, hits: funkClap, objective: "Responde a la primera caja con palmada en el contratiempo final.", difficulty: "offbeat-clap"),
    .init(id: "21_funk_06_abierto", title: "Funk 05 · Abierto entre semicorcheas", bpm: 68, hits: funkOpen, objective: "Abre dos charles sin interrumpir el resto de semicorcheas ni la palmada.", difficulty: "sixteenth-hihat-openings"),
    .init(id: "21_funk_07_aro", title: "Funk 06 · Respuesta de aro", bpm: 68, hits: funkRim, objective: "Sustituye la primera caja por aro conservando síncopas y aperturas.", difficulty: "rim-response"),
    .init(id: "21_funk_08_lineal", title: "Funk 07 · Cierre lineal en contexto", bpm: 68, bars: 2, hits: funkLinear, objective: "Conecta el groove completo con un cierre de bombo, caja y toms sin simultaneidad.", difficulty: "linear-ending"),
    .init(id: "21_funk_04_clap", title: "Funk 08 · Frase funk completa", bpm: 68, bars: 4, hits: funkCheckpoint, objective: "Integra motor de semicorcheas, silencios, caja desplazada, palmada, aro y cierre lineal.", difficulty: "funk-integration", checkpoint: true),

    .init(id: "22_blues_01_shuffle", title: "Blues 01 · Shuffle", bpm: 66, grid: 12, hits: bluesBase, objective: "Mantén la pareja larga-corta del shuffle sobre bombo y caja.", difficulty: "shuffle-grid"),
    .init(id: "22_blues_02_respuesta", title: "Blues 02 · Respuesta ternaria", bpm: 66, grid: 12, hits: bluesResponse, objective: "Responde con bombo y tom grave en los últimos tresillos del compás.", difficulty: "triplet-response"),
    .init(id: "22_blues_03_frase", title: "Blues 03 · Shuffle de ride", bpm: 66, grid: 12, bars: 4, hits: bluesRidePhrase, objective: "Sostén el shuffle en el ride y usa el tom grave para cerrar cuatro compases.", difficulty: "shuffle-ride-phrase"),
    .init(id: "22_blues_05_bombo", title: "Blues 04 · Bombo en tresillo", bpm: 66, grid: 12, hits: bluesKick, objective: "Añade un bombo en el último tresillo del segundo pulso sin mover el ride.", difficulty: "triplet-kick"),
    .init(id: "22_blues_06_aro", title: "Blues 05 · Aro en el shuffle", bpm: 66, grid: 12, hits: bluesRim, objective: "Lleva el segundo backbeat al aro y conserva el bombo ternario.", difficulty: "shuffle-rim"),
    .init(id: "22_blues_07_dialogo", title: "Blues 06 · Pregunta y respuesta ternaria", bpm: 66, grid: 12, bars: 2, hits: bluesDialogue, objective: "Alterna la respuesta del bombo entre el segundo y el cuarto pulso de dos compases.", difficulty: "triplet-kick-dialogue"),
    .init(id: "22_blues_08_fill", title: "Blues 07 · Fill ternario integrado", bpm: 66, grid: 12, bars: 2, hits: bluesFill, objective: "Sustituye el último pulso de la respuesta por caja, tom agudo y tom grave.", difficulty: "triplet-tom-fill"),
    .init(id: "22_blues_04_cierre", title: "Blues 08 · Forma de doce compases", bpm: 66, grid: 12, bars: 12, hits: bluesCheckpoint, objective: "Recorre tres grupos distintos de cuatro compases con shuffle, aro, respuestas y fills.", difficulty: "twelve-bar-integration", checkpoint: true),

    .init(id: "23_jazz_01_ride", title: "Jazz básico 01 · Ride de swing", bpm: 64, grid: 12, hits: jazzBase, objective: "Pasa del shuffle continuo a la figura de ride con espacios y caja en dos y cuatro.", difficulty: "jazz-ride"),
    .init(id: "23_jazz_02_dos_cuatro", title: "Jazz básico 02 · Bombo bajo el ride", bpm: 64, grid: 12, hits: jazzWithKick, objective: "Añade bombo en uno y tres sin alterar el ride ni la caja.", difficulty: "ride-kick-coordination"),
    .init(id: "23_jazz_03_comping", title: "Jazz básico 03 · Comping de caja", bpm: 64, grid: 12, hits: jazzComping, objective: "Anticipa con caja los pulsos dos y cuatro mientras mantienes ride y bombo.", difficulty: "snare-comping"),
    .init(id: "23_jazz_05_bombo", title: "Jazz básico 04 · Bombo de respuesta", bpm: 64, grid: 12, hits: jazzKick, objective: "Añade la respuesta de bombo al último tresillo sin perder el comping de caja.", difficulty: "jazz-kick-answer"),
    .init(id: "23_jazz_06_aro", title: "Jazz básico 05 · Comping de aro", bpm: 64, grid: 12, hits: jazzRim, objective: "Alterna caja y aro en las anticipaciones bajo la misma figura de ride.", difficulty: "rim-comping"),
    .init(id: "23_jazz_07_dialogo", title: "Jazz básico 06 · Dos compases dialogados", bpm: 64, grid: 12, bars: 2, hits: jazzDialogue, objective: "Contesta a la primera anticipación de caja desde el último tresillo del segundo pulso.", difficulty: "comping-dialogue"),
    .init(id: "23_jazz_08_fill", title: "Jazz básico 07 · Cierre ternario de toms", bpm: 64, grid: 12, bars: 2, hits: jazzFill, objective: "Conecta el comping con ride, tom agudo y tom grave al cierre de la frase.", difficulty: "jazz-triplet-ending"),
    .init(id: "23_jazz_04_frase", title: "Jazz básico 08 · Reto de swing", bpm: 64, grid: 12, bars: 4, hits: jazzCheckpoint, objective: "Integra backbeat, comping, respuesta de bombo, aro y cierre sin perder el ride.", difficulty: "jazz-integration", checkpoint: true),

    .init(id: "28_jazz_01_continuidad", title: "Jazz intermedio 01 · Continuidad de swing", bpm: 72, grid: 12, bars: 2, hits: jazzIntermediateBase, objective: "Consolida el diálogo de caja, aro y bombo del curso básico a 72 BPM.", difficulty: "swing-consolidation-tempo"),
    .init(id: "28_jazz_02_charles", title: "Jazz intermedio 02 · Charles en dos y cuatro", bpm: 72, grid: 12, bars: 2, hits: jazzTimekeeping, objective: "Añade el charles cerrado en dos y cuatro sin mover el ride ni las respuestas de caja y bombo.", difficulty: "hihat-two-and-four"),
    .init(id: "28_jazz_03_tresillo", title: "Jazz intermedio 03 · Caja en tresillos interiores", bpm: 72, grid: 12, bars: 2, hits: jazzInsidePhrase, objective: "En el segundo compás, lleva la caja al tresillo interior de uno y tres manteniendo ride y charles.", difficulty: "inside-triplet-comping"),
    .init(id: "28_jazz_04_bombo", title: "Jazz intermedio 04 · Comping de bombo", bpm: 72, grid: 12, hits: jazzKickComp, objective: "Desplaza el segundo bombo al último tresillo de tres sin cambiar las otras voces.", difficulty: "kick-comping-displacement"),
    .init(id: "28_jazz_05_dialogo", title: "Jazz intermedio 05 · Diálogo entre bombo y caja", bpm: 72, grid: 12, bars: 2, hits: jazzKickDialogue, objective: "Alterna las dos posiciones del bombo sobre la caja interior y el charles en dos y cuatro.", difficulty: "kick-snare-dialogue"),
    .init(id: "28_jazz_06_aro", title: "Jazz intermedio 06 · Aro dentro del comping", bpm: 72, grid: 12, bars: 2, hits: jazzRimDialogue, objective: "Responde a la primera caja con aro en el tresillo interior del tercer pulso.", difficulty: "inside-rim-comping"),
    .init(id: "28_jazz_07_apertura", title: "Jazz intermedio 07 · Apertura en cuatro", bpm: 72, grid: 12, bars: 2, hits: jazzOpenDialogue, objective: "Abre el charles en cuatro y ciérralo en el siguiente dos sin perder el comping.", difficulty: "jazz-open-hihat"),
    .init(id: "28_jazz_08_espacio", title: "Jazz intermedio 08 · Espacio en el ride", bpm: 72, grid: 12, bars: 2, hits: jazzRideGaps, objective: "Deja en silencio una nota de ride en cada compás y conserva el resto de la coordinación.", difficulty: "ride-gap-independence"),
    .init(id: "28_jazz_09_fill", title: "Jazz intermedio 09 · Fill y vuelta al swing", bpm: 72, grid: 12, bars: 2, hits: jazzIntermediateFill, objective: "Sustituye el último pulso por caja y toms y regresa al groove sin perder el tiempo uno.", difficulty: "triplet-fill-return"),
    .init(id: "28_jazz_10_frase", title: "Jazz intermedio 10 · Frase de cuatro compases", bpm: 72, grid: 12, bars: 4, hits: jazzFourBarPhrase, objective: "Une dos diálogos conocidos y coloca el fill solo al final de la frase.", difficulty: "four-bar-jazz-phrasing"),
    .init(id: "28_jazz_11_trading", title: "Jazz intermedio 11 · Trading fours", bpm: 72, grid: 12, bars: 8, hits: jazzTradingFours, objective: "Alterna cuatro compases de groove con cuatro de respuestas de caja y toms, conservando la referencia del ride.", difficulty: "trading-fours"),
    .init(id: "28_jazz_12_reto", title: "Jazz intermedio 12 · Reto de independencia", bpm: 72, grid: 12, bars: 8, hits: jazzIntermediateCheckpoint, objective: "Integra swing, charles en dos y cuatro, comping interior, aperturas, silencios y respuestas de toms en ocho compases.", difficulty: "intermediate-jazz-integration", checkpoint: true),

    .init(id: "24_disco_01_pulso", title: "Disco 01 · Bombo a negras", bpm: 80, hits: disco, objective: "Mantén cuatro bombos por compás con caja en dos y cuatro sin apilar tres voces.", difficulty: "four-on-the-floor"),
    .init(id: "24_disco_02_abierto", title: "Disco 02 · Charles abierto", bpm: 80, hits: discoOpen, objective: "Abre el último contratiempo sin retirar el bombo a negras.", difficulty: "last-offbeat-opening"),
    .init(id: "24_disco_04_contratiempos", title: "Disco 03 · Aperturas encadenadas", bpm: 80, hits: discoOffbeats, objective: "Abre los cuatro contratiempos y ciérralos en la siguiente entrada del charles.", difficulty: "continuous-offbeat-openings"),
    .init(id: "24_disco_05_palmada", title: "Disco 04 · Palmada en cuatro", bpm: 80, hits: discoClap, objective: "Responde a la caja con palmada manteniendo bombo y aperturas.", difficulty: "disco-clap"),
    .init(id: "24_disco_06_enlace", title: "Disco 05 · Bombo de enlace", bpm: 80, hits: discoLink, objective: "Anticipa el siguiente compás con un bombo de semicorchea tras el último abierto.", difficulty: "disco-kick-pickup"),
    .init(id: "24_disco_07_respiracion", title: "Disco 06 · Dos compases de respiración", bpm: 80, bars: 2, hits: discoPhrase, objective: "Conserva las negras del bombo mientras el segundo compás deja dos aperturas en silencio.", difficulty: "disco-hihat-space"),
    .init(id: "24_disco_08_fill", title: "Disco 07 · Fill sin perder el pulso", bpm: 80, bars: 2, hits: discoFill, objective: "Cierra con toms y caja manteniendo el bombo de cuatro y su enlace final.", difficulty: "disco-fill-over-pulse"),
    .init(id: "24_disco_03_frase", title: "Disco 08 · Frase disco completa", bpm: 80, bars: 4, hits: discoCheckpoint, objective: "Une pulso continuo, aperturas, palmada, bombo de enlace y fill en cuatro compases.", difficulty: "disco-integration", checkpoint: true),

    .init(id: "25_reggae_01_one_drop", title: "Reggae 01 · One drop con respuesta", bpm: 68, bars: 2, hits: reggaePhrase, objective: "Mantén charles y aro a contratiempo, apoya bombo y aro en tres y anticipa la vuelta del segundo compás.", difficulty: "one-drop-dialogue"),
    .init(id: "25_reggae_02_skank", title: "Reggae 02 · Aperturas a contratiempo", bpm: 68, bars: 2, hits: reggaeOpen, objective: "Abre el charles en los contratiempos sin perder el one drop ni la respuesta de aro.", difficulty: "reggae-open-hihat"),
    .init(id: "25_reggae_04_aro", title: "Reggae 03 · Respuesta de aro en semicorcheas", bpm: 68, bars: 2, hits: reggaeRim, objective: "Añade una semicorchea de aro en la respuesta del segundo compás.", difficulty: "reggae-rim-sixteenths"),
    .init(id: "25_reggae_05_palmada", title: "Reggae 04 · One drop con palmada", bpm: 68, bars: 2, hits: reggaeClap, objective: "Cambia el aro de tres por palmada solo en el segundo compás y conserva el bombo.", difficulty: "one-drop-clap"),
    .init(id: "25_reggae_06_tom", title: "Reggae 05 · Tom de respuesta", bpm: 68, bars: 2, hits: reggaeTom, objective: "Lleva el comienzo del cierre al tom agudo sin cambiar el resto del one drop.", difficulty: "reggae-tom-answer"),
    .init(id: "25_reggae_07_rockers", title: "Reggae 06 · Rockers", bpm: 68, bars: 2, hits: reggaeRockers, objective: "Añade bombo en uno para pasar de one drop a rockers sobre la misma frase.", difficulty: "rockers-kick"),
    .init(id: "25_reggae_08_steppers", title: "Reggae 07 · Steppers", bpm: 68, bars: 2, hits: reggaeSteppers, objective: "Completa las cuatro negras del bombo sin mover aro, palmada, aperturas ni respuesta.", difficulty: "steppers-kick"),
    .init(id: "25_reggae_03_frase", title: "Reggae 08 · Frase reggae completa", bpm: 68, bars: 4, hits: reggaeCheckpoint, objective: "Une one drop, respuesta, palmada, rockers y steppers con un cierre de toms.", difficulty: "reggae-integration", checkpoint: true),

    .init(id: "26_dembow_01_base", title: "Dembow 01 · Base con respuesta", bpm: 88, bars: 2, hits: dembowBase, objective: "Mantén la célula de dembow y anticipa la vuelta con bombo en el segundo compás.", difficulty: "dembow-dialogue"),
    .init(id: "26_dembow_02_charles", title: "Dembow 02 · Charles a corcheas", bpm: 88, bars: 2, hits: dembowEighths, objective: "Completa las corcheas del charles sin perder el enlace de bombo.", difficulty: "dembow-eighths"),
    .init(id: "26_dembow_04_palmada", title: "Dembow 03 · Palmada de respuesta", bpm: 88, bars: 2, hits: dembowClap, objective: "Responde a la caja con palmada en el segundo compás.", difficulty: "dembow-clap"),
    .init(id: "26_dembow_05_abierto", title: "Dembow 04 · Aperturas de cierre", bpm: 88, bars: 2, hits: dembowOpen, objective: "Abre el último charles de cada compás conservando la caja desplazada.", difficulty: "dembow-openings"),
    .init(id: "26_dembow_06_bombo", title: "Dembow 05 · Bombo intercalado", bpm: 88, bars: 2, hits: dembowKick, objective: "Anticipa la primera caja con bombo de semicorchea sin cambiar las demás voces.", difficulty: "dembow-kick-sixteenth"),
    .init(id: "26_dembow_07_rafaga", title: "Dembow 06 · Ráfaga de respuesta", bpm: 88, bars: 2, hits: dembowRoll, objective: "Añade dos semicorcheas de charles alrededor de la última apertura del segundo compás.", difficulty: "dembow-hihat-burst"),
    .init(id: "26_dembow_08_lineal", title: "Dembow 07 · Redoble lineal", bpm: 88, bars: 2, hits: dembowFill, objective: "Cambia el último pulso por caja, bombo y toms antes de volver al patrón completo.", difficulty: "dembow-linear-fill"),
    .init(id: "26_dembow_03_frase", title: "Dembow 08 · Frase dembow completa", bpm: 88, bars: 4, hits: dembowCheckpoint, objective: "Integra la célula de dembow, palmada, aperturas, bombos intercalados, ráfaga y fill.", difficulty: "dembow-integration", checkpoint: true),

    .init(id: "27_clave_01_tres_dos", title: "Clave 01 · Son 3-2 con acompañamiento", bpm: 72, bars: 2, hits: claveThreeTwoGroove, objective: "Toca la clave de son 3-2 sobre una base completa de bombo y charles.", difficulty: "son-three-two"),
    .init(id: "27_clave_02_dos_tres", title: "Clave 02 · Son 2-3 con acompañamiento", bpm: 72, bars: 2, hits: claveTwoThreeGroove, objective: "Invierte los lados de la clave manteniendo la base de bombo y el motor de corcheas.", difficulty: "son-two-three"),
    .init(id: "27_clave_04_ride", title: "Clave 03 · Clave sobre ride", bpm: 72, bars: 2, hits: claveRide, objective: "Lleva las corcheas al ride sin desplazar la clave 2-3.", difficulty: "clave-ride"),
    .init(id: "27_clave_05_bossa", title: "Clave 04 · Bossa de aro", bpm: 72, bars: 2, hits: bossaGroove, objective: "Toca la célula de aro de bossa con bombo en uno, tres y sus anticipaciones.", difficulty: "bossa-rim-pattern"),
    .init(id: "27_clave_06_abierto", title: "Clave 05 · Bossa con aperturas", bpm: 72, bars: 2, hits: bossaOpen, objective: "Abre el charles al final de cada compás conservando bombo y aro de bossa.", difficulty: "bossa-openings"),
    .init(id: "27_clave_07_bombo", title: "Clave 06 · Bombo anticipado", bpm: 72, bars: 2, hits: bossaAnticipation, objective: "Añade una semicorchea de bombo antes de cada cierre sin mover las aperturas.", difficulty: "bossa-kick-anticipation"),
    .init(id: "27_clave_08_cierre", title: "Clave 07 · Turnaround de toms", bpm: 72, bars: 2, hits: bossaFill, objective: "Conecta la bossa con un cierre de aro y toms que conserva el último bombo.", difficulty: "bossa-turnaround"),
    .init(id: "27_clave_03_bossa", title: "Clave 08 · Son y bossa en contexto", bpm: 72, bars: 6, hits: claveCheckpoint, objective: "Enlaza son 3-2, son 2-3 sobre ride y bossa con aperturas y turnaround.", difficulty: "clave-bossa-integration", checkpoint: true)
]

func vlq(_ value: Int) -> [UInt8] { var value = value; var bytes = [UInt8(value & 127)]; value >>= 7; while value > 0 { bytes.append(UInt8(value & 127) | 128); value >>= 7 }; return bytes.reversed() }
func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }
func be32(_ value: Int) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value & 255)] }
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/exercises")
let chapterByPrefix = ["20": "rock", "21": "funk", "22": "blues", "23": "jazz", "24": "disco", "25": "reggae", "26": "dembow", "27": "clave-bossa", "28": "jazz-intermediate"]
let firstPrerequisite = [
    "rock": "10_hh_08_fill_cierre", "disco": "20_rock_04_resistencia",
    "funk": "24_disco_03_frase", "reggae": "21_funk_04_clap",
    "dembow": "25_reggae_03_frase", "blues": "26_dembow_03_frase",
    "jazz": "22_blues_04_cierre", "jazz-intermediate": "23_jazz_04_frase", "clave-bossa": "28_jazz_12_reto"
]
var previousByChapter = [String: String]()
var positionByChapter = [String: Int]()
for item in definitions {
    let chapter = chapterByPrefix[String(item.id.split(separator: "_")[0])]!
    let position = positionByChapter[chapter, default: 0] + 1
    let prerequisite = previousByChapter[chapter] ?? firstPrerequisite[chapter]!
    precondition(item.hits.allSatisfy { $0.0 >= 0 && $0.0 < item.bars * item.grid }, "Paso fuera de frase: \(item.id)")
    precondition(Set(item.hits.map { "\($0.0):\($0.1)" }).count == item.hits.count, "Golpe duplicado: \(item.id)")
    precondition(Dictionary(grouping: item.hits, by: { $0.0 }).values.allSatisfy { $0.count <= 2 }, "Tres voces simultáneas: \(item.id)")
    let title = Array(item.title.utf8); let tempo = 60_000_000 / item.bpm
    var events: [(Int, Int, [UInt8])] = [(0,0,[255,3] + vlq(title.count) + title),
        (0,1,[255,81,3,UInt8((tempo >> 16) & 255),UInt8((tempo >> 8) & 255),UInt8(tempo & 255)]),
        (0,2,[255,88,4,4,2,24,8])]
    var metadata = ["xroll/1 id=\(item.id)", "xroll/1 chapter=\(chapter)", "xroll/1 position=\(position)",
        "xroll/1 prerequisite=\(prerequisite)", "xroll/1 objective=\(item.objective)",
        "xroll/1 new-difficulty=\(item.difficulty)", "xroll/1 recommended-help=\(item.checkpoint ? "normal" : "full")"]
    if item.checkpoint { metadata.append("xroll/1 flag=checkpoint") }
    for (index, text) in metadata.enumerated() { let bytes = Array(text.utf8); events.append((0, 3 + index, [255,1] + vlq(bytes.count) + bytes)) }
    for (step, note) in item.hits { let tick = step * 1_920 / item.grid; events.append((tick,100,[153,UInt8(note),100])); events.append((tick + 60,99,[137,UInt8(note),0])) }
    events.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    var track = [UInt8](); var previous = 0
    for event in events { track += vlq(event.0 - previous) + event.2; previous = event.0 }
    track += vlq(max(0, 1_920 * item.bars - previous)) + [255,47,0]
    let bytes = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(480) + Array("MTrk".utf8) + be32(track.count) + track
    try Data(bytes).write(to: directory.appendingPathComponent(item.id + ".mid"), options: .atomic)
    previousByChapter[chapter] = item.id
    positionByChapter[chapter] = position
}
