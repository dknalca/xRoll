import Foundation

/// Avisos no bloqueantes para ejercicios comunitarios. Un MIDI puede ser
/// reproducible y, aun así, introducir demasiadas dificultades a la vez.
public enum PedagogicalMIDIValidator {
    public static func warnings(for exercise: Exercise) -> [String] {
        var warnings: [String] = []
        let sounds = Set(exercise.notes.map(\.sound))
        let notesByStep = Dictionary(grouping: exercise.notes, by: \.step)
        let densest = notesByStep.values.map(\.count).max() ?? 0
        let sortedSteps = Set(exercise.notes.map(\.step)).sorted()
        let smallestGap = zip(sortedSteps, sortedSteps.dropFirst()).map { $1 - $0 }.min()

        if sounds.count > 3 { warnings.append("Introduce \(sounds.count) sonidos; para principiantes conviene añadir uno por nivel.") }
        if densest > 3 { warnings.append("Hay hasta \(densest) golpes simultáneos; revisa si el patrón es adecuado para el nivel previsto.") }
        if smallestGap == 1 { warnings.append("Incluye semicorcheas; preséntalas después de consolidar corcheas.") }
        if exercise.bpm > 110 { warnings.append("El tempo es \(exercise.bpm) BPM; considera una versión lenta para aprendizaje.") }
        if exercise.bars > 4 { warnings.append("El patrón dura \(exercise.bars) compases; ofrece antes una versión de uno o dos compases.") }
        return warnings
    }
}
