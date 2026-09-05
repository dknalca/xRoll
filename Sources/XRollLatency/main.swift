import CoreMIDI
import Foundation
import XRollCore

let arguments = Array(CommandLine.arguments.dropFirst())
let logEvents = arguments.contains("--log-events")
let checkOnly = arguments.contains("--check")
let sourceArgumentIndex = arguments.firstIndex(of: "--source")
let sourceID: MIDIUniqueID?
if let sourceArgumentIndex, arguments.indices.contains(sourceArgumentIndex + 1) {
    sourceID = MIDIUniqueID(arguments[sourceArgumentIndex + 1])
} else {
    sourceID = nil
}
let soundArguments = arguments.enumerated().compactMap { index, argument -> String? in
    if argument == "--log-events" || argument == "--check" || argument == "--source" || index == sourceArgumentIndex.map({ $0 + 1 }) {
        return nil
    }
    return argument
}
guard soundArguments.count == 1 else {
    fputs("Uso: swift run xroll-latency <sound-id> [--source <uid>] [--check] [--log-events]\n", stderr)
    exit(64)
}

let soundID = soundArguments[0]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let kitDirectory = root.appendingPathComponent("Resources/Kits/hiphop_basic", isDirectory: true)
let kitURL = kitDirectory.appendingPathComponent("kit.json")

do {
    let catalog = ResourceCatalog()
    let kit = try catalog.loadKit(at: kitURL)
    guard kit.sounds.contains(where: { $0.id == soundID }) else {
        fputs("El sonido \(soundID) no existe en el kit.\n", stderr)
        exit(64)
    }

    let audio = SampleAudioEngine()
    try audio.load(kit: kit, from: kitDirectory)
    try audio.start()

    let input = try MIDIInputSession { event in
        do {
            try audio.play(soundID: soundID)
            if logEvents {
                print("Note On: canal \(event.channel), nota \(event.note), velocidad \(event.velocity), host \(event.hostTime)")
            }
        } catch {
            fputs("Error de audio: \(error.localizedDescription)\n", stderr)
        }
    }
    if let sourceID {
        guard let source = MIDIInspector.source(withUniqueID: sourceID) else {
            fputs("No existe una fuente MIDI con UID \(sourceID). Usa xroll-preflight para listarlas.\n", stderr)
            exit(64)
        }
        try input.connect(source: source)
    } else {
        try input.connectAllSources()
    }

    if checkOnly {
        print("Prueba preparada: audio iniciado y fuentes MIDI conectadas.")
        exit(0)
    }

    print("Prueba de latencia activa con \(soundID). Golpea cualquier pad; Ctrl-C para terminar.")
    if logEvents {
        print("El registro de eventos anade trabajo al callback MIDI; no lo uses al medir latencia.")
    }
    RunLoop.current.run()
} catch {
    fputs("No se puede iniciar la prueba: \(error.localizedDescription)\n", stderr)
    exit(1)
}
