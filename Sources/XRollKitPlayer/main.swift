import CoreMIDI
import Foundation
import XRollCore

let arguments = Array(CommandLine.arguments.dropFirst())
let logEvents = arguments.contains("--log-events")
let sourceArgumentIndex = arguments.firstIndex(of: "--source")
let mapArgumentIndex = arguments.firstIndex(of: "--map")
let sourceID: MIDIUniqueID?
if let sourceArgumentIndex, arguments.indices.contains(sourceArgumentIndex + 1) {
    sourceID = MIDIUniqueID(arguments[sourceArgumentIndex + 1])
} else {
    sourceID = nil
}

let mapURL: URL?
if let mapArgumentIndex, arguments.indices.contains(mapArgumentIndex + 1) {
    mapURL = URL(fileURLWithPath: arguments[mapArgumentIndex + 1])
} else {
    mapURL = nil
}
let unexpectedArguments = arguments.enumerated().filter { index, argument in
    argument != "--log-events" && argument != "--source" && argument != "--map" && index != sourceArgumentIndex.map({ $0 + 1 }) && index != mapArgumentIndex.map({ $0 + 1 })
}
guard unexpectedArguments.isEmpty else {
    fputs("Uso: swift run xroll-play-kit [--source <uid>] [--map <archivo.padmap>] [--log-events]\\n", stderr)
    exit(64)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let kitDirectory = root.appendingPathComponent("Resources/Kits/hiphop_basic", isDirectory: true)
let kitURL = kitDirectory.appendingPathComponent("kit.json")

do {
    let catalog = ResourceCatalog()
    let kit = try catalog.loadKit(at: kitURL)
    let router = KitNoteRouter(kit: kit)
    let padMapRouter = try mapURL.map {
        try PadMapStore.load(at: $0, availableSounds: Set(kit.sounds.map(\.id)))
    }.map(PadMapRouter.init)
    let audio = SampleAudioEngine()
    try audio.load(kit: kit, from: kitDirectory)
    try audio.start()

    let input = try MIDIInputSession { event in
        guard let soundID = padMapRouter?.soundID(for: event) ?? router.soundID(for: event) else {
            if logEvents {
                print("Nota sin asignar: canal \(event.channel), nota \(event.note)")
            }
            return
        }
        do {
            try audio.play(soundID: soundID)
            if logEvents {
                print("\(soundID): canal \(event.channel), nota \(event.note), velocidad \(event.velocity)")
            }
        } catch {
            fputs("Error de audio: \(error.localizedDescription)\\n", stderr)
        }
    }

    if let sourceID {
        guard let source = MIDIInspector.source(withUniqueID: sourceID) else {
            fputs("No existe una fuente MIDI con UID \(sourceID). Usa xroll-preflight para listarlas.\\n", stderr)
            exit(64)
        }
        try input.connect(source: source)
    } else {
        try input.connectAllSources()
    }

    print("Kit \(kit.name) activo\(mapURL == nil ? " con mapa GM" : " con mapa personalizado"). Golpea los pads; Ctrl-C para terminar.")
    if !logEvents {
        print("Usa --log-events solo para comprobar las notas que envia el controlador.")
    }
    RunLoop.current.run()
} catch {
    fputs("No se puede iniciar el kit: \(error.localizedDescription)\\n", stderr)
    exit(1)
}
