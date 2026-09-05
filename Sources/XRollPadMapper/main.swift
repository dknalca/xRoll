import CoreMIDI
import Foundation
import XRollCore

let arguments = Array(CommandLine.arguments.dropFirst())
let sourceIndex = arguments.firstIndex(of: "--source")
let outputIndex = arguments.firstIndex(of: "--output")
guard let sourceIndex, arguments.indices.contains(sourceIndex + 1),
      let outputIndex, arguments.indices.contains(outputIndex + 1) else {
    fputs("Uso: swift run xroll-map-pads --source <uid> --output <archivo.padmap>\\n", stderr)
    exit(64)
}

guard let sourceID = MIDIUniqueID(arguments[sourceIndex + 1]) else {
    fputs("El UID MIDI debe ser un numero entero.\\n", stderr)
    exit(64)
}
let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
let allowedIndexes = Set([sourceIndex, sourceIndex + 1, outputIndex, outputIndex + 1])
guard arguments.indices.allSatisfy(allowedIndexes.contains) else {
    fputs("Uso: swift run xroll-map-pads --source <uid> --output <archivo.padmap>\\n", stderr)
    exit(64)
}

guard let source = MIDIInspector.source(withUniqueID: sourceID) else {
    fputs("No existe una fuente MIDI con UID \(sourceID). Usa xroll-preflight para listarlas.\\n", stderr)
    exit(64)
}

let deviceName = MIDIInspector.sources().first(where: { $0.uniqueID == sourceID })?.name ?? "Controlador MIDI"
let formatter = ISO8601DateFormatter()
let lock = NSLock()
var builder = PadMapBuilder(device: deviceName, deviceUID: Int(sourceID), created: formatter.string(from: Date()))
let availableSounds = Set(PadMapBuilder.suggestedSteps.map(\.sound))

func printNextStep() {
    if let step = builder.nextStep {
        print("Golpea el pad para \(step.sound) (posicion \(step.row),\(step.column)).")
    }
}

do {
    let input = try MIDIInputSession { event in
        lock.lock()
        let result = builder.assign(event)
        lock.unlock()

        switch result {
        case .assigned(let sound, let remaining):
            print("Asignado \(sound): nota \(event.note), canal \(event.channel). Quedan \(remaining).")
            printNextStep()
        case .duplicate(let note, let channel, let existingSound):
            print("La nota \(note), canal \(channel), ya corresponde a \(existingSound). Golpea otro pad.")
        case .complete(let map):
            do {
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PadMapStore.save(map, to: outputURL, availableSounds: availableSounds)
                print("Mapa guardado en \(outputURL.path).")
                exit(0)
            } catch {
                fputs("No se pudo guardar el mapa: \(error.localizedDescription)\\n", stderr)
                exit(1)
            }
        }
    }
    try input.connect(source: source)
    print("Asistente de mapeo para \(deviceName).")
    printNextStep()
    RunLoop.current.run()
} catch {
    fputs("No se pudo iniciar el asistente: \(error.localizedDescription)\\n", stderr)
    exit(1)
}
