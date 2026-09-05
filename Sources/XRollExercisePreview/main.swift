import Foundation
import XRollCore

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1 else {
    fputs("Uso: swift run xroll-preview <id-del-ejercicio>\\n", stderr)
    exit(64)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let kitDirectory = root.appendingPathComponent("Resources/Kits/hiphop_basic", isDirectory: true)
let exercisesDirectory = root.appendingPathComponent("data/exercises", isDirectory: true)

do {
    let catalog = ResourceCatalog()
    let kit = try catalog.loadKit(at: kitDirectory.appendingPathComponent("kit.json"))
    let exercises = try catalog.loadExercises(in: exercisesDirectory, kit: kit)
    guard let exercise = exercises.first(where: { $0.id == arguments[0] }) else {
        fputs("No existe el ejercicio \(arguments[0]).\\n", stderr)
        exit(64)
    }

    let audio = SampleAudioEngine()
    try audio.load(kit: kit, from: kitDirectory)
    try audio.start()
    let timeline = ExerciseTimeline(exercise: exercise)
    let startDelayMilliseconds = 500.0
    let baseHostTime = AudioClock.hostTime(afterMilliseconds: startDelayMilliseconds)
    for note in timeline.notes {
        try audio.schedule(
            soundID: note.sound,
            atHostTime: AudioClock.hostTime(afterMilliseconds: note.timeMilliseconds, from: baseHostTime)
        )
    }

    let duration = Double(exercise.repeats) * timeline.patternDurationMilliseconds + startDelayMilliseconds + 1_000
    print("Vista previa: \(exercise.title) a \(exercise.bpm) BPM. Sin puntuacion.")
    RunLoop.current.run(until: Date().addingTimeInterval(duration / 1_000))
} catch {
    fputs("No se pudo reproducir la vista previa: \(error.localizedDescription)\\n", stderr)
    exit(1)
}
