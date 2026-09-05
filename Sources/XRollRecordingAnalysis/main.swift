import Foundation
import XRollCore

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1 else {
    fputs("Uso: swift run xroll-analyse-recording <grabacion.mov|m4a|wav>\n", stderr)
    exit(64)
}

let url = URL(fileURLWithPath: arguments[0])
do {
    let recording = try LatencyRecordingAnalysis.monoSamples(from: url)
    let onsets = LatencyRecordingAnalysis.primaryOnsets(
        in: recording.samples,
        sampleRate: recording.sampleRate
    )
    let duration = Double(recording.samples.count) / recording.sampleRate
    print("Grabacion: \(String(format: "%.3f", duration)) s, \(Int(recording.sampleRate)) Hz")
    print("Inicios principales detectados: \(onsets.count)")
    print("inicio_ms,amplitud")
    onsets.forEach {
        print("\(String(format: "%.3f", $0.timeSeconds * 1_000)),\(String(format: "%.5f", $0.amplitude))")
    }
} catch {
    fputs("No se puede analizar la grabacion: \(error.localizedDescription)\n", stderr)
    exit(1)
}
