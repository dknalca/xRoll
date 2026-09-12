import Foundation
import XRollCore

let arguments = Array(CommandLine.arguments.dropFirst())
let splitBands = arguments.contains("--split-bands")
let paths = arguments.filter { $0 != "--split-bands" }
guard paths.count == 1 else {
    fputs("Uso: swift run xroll-analyse-recording <grabacion.mov|m4a|wav> [--split-bands]\n", stderr)
    exit(64)
}

let url = URL(fileURLWithPath: paths[0])
do {
    let recording = try LatencyRecordingAnalysis.monoSamples(from: url)
    let duration = Double(recording.samples.count) / recording.sampleRate
    print("Grabacion: \(String(format: "%.3f", duration)) s, \(Int(recording.sampleRate)) Hz")
    if splitBands {
        let result = LatencyRecordingAnalysis.splitBandMeasurements(in: recording.samples, sampleRate: recording.sampleRate)
        print("Onsets pad graves: \(result.padOnsets.count)")
        print("Onsets señal aguda: \(result.soundOnsets.count)")
        print("pad_onsets_ms: \(result.padOnsets.map { String(format: "%.3f", $0.timeSeconds * 1_000) }.joined(separator: ","))")
        print("sound_onsets_ms: \(result.soundOnsets.map { String(format: "%.3f", $0.timeSeconds * 1_000) }.joined(separator: ","))")
        print("Pares pad->sonido: \(result.measurements.count)")
        print("pad_ms,sonido_ms,latencia_ms")
        result.measurements.forEach {
            print("\(String(format: "%.3f", $0.pad.timeSeconds * 1_000)),\(String(format: "%.3f", $0.sound.timeSeconds * 1_000)),\(String(format: "%.3f", $0.milliseconds))")
        }
        if let summary = LatencyRecordingAnalysis.summary(of: result.measurements) {
            print("Resumen: n=\(summary.count), mediana=\(String(format: "%.3f", summary.medianMilliseconds)) ms, p95=\(String(format: "%.3f", summary.percentile95Milliseconds)) ms, mínimo=\(String(format: "%.3f", summary.minimumMilliseconds)) ms, máximo=\(String(format: "%.3f", summary.maximumMilliseconds)) ms")
        }
    } else {
        let onsets = LatencyRecordingAnalysis.primaryOnsets(in: recording.samples, sampleRate: recording.sampleRate)
        print("Inicios principales detectados: \(onsets.count)")
        print("inicio_ms,amplitud")
        onsets.forEach {
            print("\(String(format: "%.3f", $0.timeSeconds * 1_000)),\(String(format: "%.5f", $0.amplitude))")
        }
    }
} catch {
    fputs("No se puede analizar la grabacion: \(error.localizedDescription)\n", stderr)
    exit(1)
}
