import Foundation
import XRollCore

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let kitDirectory = root.appendingPathComponent("Resources/Kits/hiphop_basic", isDirectory: true)
let kitURL = kitDirectory.appendingPathComponent("kit.json")
let exercisesDirectory = root.appendingPathComponent("data/exercises", isDirectory: true)
let catalog = ResourceCatalog()

print("xRoll preflight")
print("Directorio: \(root.path)")

let midiSources = MIDIInspector.sources()
if midiSources.isEmpty {
    print("MIDI: no hay fuentes conectadas.")
} else {
    print("MIDI:")
    midiSources.forEach { source in
        let id = source.uniqueID.map(String.init) ?? "sin identificador"
        print("  - \(source.name) [\(id)]")
    }
}

let audio = AudioInspector.currentOutput()
let device = audio.deviceID.map(String.init) ?? "sin dispositivo predeterminado"
let buffer = audio.bufferFrameSize.map(String.init) ?? "sin dato de buffer"
let bufferRange = audio.bufferFrameRange.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "sin rango de buffer"
let name = audio.deviceName ?? "sin nombre"
let uid = audio.deviceUID ?? "sin UID"
print("Audio: \(name) [\(uid)], dispositivo \(device), \(audio.sampleRate) Hz, \(audio.channelCount) canales, buffer \(buffer) fotogramas (rango \(bufferRange)), latencia de presentacion \(audio.outputLatency * 1_000) ms")

do {
    let kit = try catalog.loadKit(at: kitURL)
    let exercises = try catalog.loadExercises(in: exercisesDirectory, kit: kit)
    print("Recursos: kit \(kit.id), \(kit.sounds.count) sonidos, \(exercises.count) ejercicios validos.")

    let missingFiles = catalog.missingSampleFiles(for: kit, in: kitDirectory)
    if missingFiles.isEmpty {
        let audio = SampleAudioEngine()
        try audio.load(kit: kit, from: kitDirectory)
        print("Samples: todos presentes y legibles; listos para la prueba de latencia.")
    } else {
        print("Samples: faltan \(missingFiles.count) WAV. La medicion de la fase 0 queda pendiente.")
    }
} catch {
    fputs("Error de recursos: \(error.localizedDescription)\n", stderr)
    exit(1)
}
