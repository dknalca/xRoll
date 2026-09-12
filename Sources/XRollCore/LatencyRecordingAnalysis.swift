import AVFoundation
import Foundation

public struct RecordingTransient: Equatable {
    public let timeSeconds: Double
    public let amplitude: Float
}

public struct LatencyMeasurement: Equatable {
    public let pad: RecordingTransient
    public let sound: RecordingTransient
    public let milliseconds: Double
}

public struct LatencyMeasurementSummary: Equatable {
    public let count: Int
    public let medianMilliseconds: Double
    public let percentile95Milliseconds: Double
    public let minimumMilliseconds: Double
    public let maximumMilliseconds: Double
}

public enum RecordingAnalysisError: LocalizedError {
    case unsupportedFormat
    case recordingTooLong

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "La grabacion no se puede convertir a PCM flotante."
        case .recordingTooLong:
            return "La grabacion supera el limite de fotogramas analizable."
        }
    }
}

public enum LatencyRecordingAnalysis {
    public static func monoSamples(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        guard file.length <= AVAudioFramePosition(UInt32.max) else {
            throw RecordingAnalysisError.recordingTooLong
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw RecordingAnalysisError.unsupportedFormat
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw RecordingAnalysisError.unsupportedFormat
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var samples = Array(repeating: Float.zero, count: frameCount)
        for frame in 0..<frameCount {
            var value: Float = 0
            for channel in 0..<channelCount { value += channels[channel][frame] }
            samples[frame] = value / Float(channelCount)
        }
        return (samples, buffer.format.sampleRate)
    }

    public static func transients(
        in samples: [Float],
        sampleRate: Double,
        thresholdRatio: Float = 0.12,
        minimumSeparationMilliseconds: Double = 2
    ) -> [RecordingTransient] {
        guard let maximum = samples.max(), maximum > 0, sampleRate > 0 else { return [] }
        let threshold = maximum * thresholdRatio
        let separation = max(1, Int(sampleRate * minimumSeparationMilliseconds / 1_000))
        var result: [RecordingTransient] = []
        var index = 1

        while index + 1 < samples.count {
            guard samples[index] >= threshold,
                  samples[index] >= samples[index - 1],
                  samples[index] >= samples[index + 1] else {
                index += 1
                continue
            }

            let end = min(samples.count, index + separation)
            let localPeak = samples[index..<end].enumerated().max { $0.element < $1.element }
            let peakIndex = index + (localPeak?.offset ?? 0)
            result.append(RecordingTransient(
                timeSeconds: Double(peakIndex) / sampleRate,
                amplitude: samples[peakIndex]
            ))
            index = peakIndex + separation
        }
        return result
    }

    public static func primaryOnsets(
        in samples: [Float],
        sampleRate: Double,
        thresholdRatio: Float = 0.16,
        envelopeMilliseconds: Double = 1,
        minimumSeparationMilliseconds: Double = 200
    ) -> [RecordingTransient] {
        guard let maximum = samples.max(), maximum > 0, sampleRate > 0 else { return [] }

        let windowSize = max(1, Int(sampleRate * envelopeMilliseconds / 1_000))
        let separation = max(1, Int(minimumSeparationMilliseconds / envelopeMilliseconds))
        let threshold = maximum * thresholdRatio
        var envelope: [(sample: Int, amplitude: Float)] = []
        var start = 0

        while start < samples.count {
            let end = min(samples.count, start + windowSize)
            let peak = samples[start..<end].max() ?? 0
            envelope.append((sample: start, amplitude: peak))
            start = end
        }

        var result: [RecordingTransient] = []
        var index = 1
        while index < envelope.count {
            guard envelope[index].amplitude >= threshold,
                  envelope[index - 1].amplitude < threshold else {
                index += 1
                continue
            }

            result.append(RecordingTransient(
                timeSeconds: Double(envelope[index].sample) / sampleRate,
                amplitude: envelope[index].amplitude
            ))
            index += separation
        }
        return result
    }

    /// Separa el golpe físico grave de una señal de prueba aguda. El filtrado es
    /// bidireccional para no desplazar los onsets por fase del filtro.
    public static func splitBandMeasurements(
        in samples: [Float],
        sampleRate: Double,
        lowPassCutoffHz: Double = 700,
        highPassCutoffHz: Double = 1_800,
        minimumLatencyMilliseconds: Double = 2,
        maximumLatencyMilliseconds: Double = 100
    ) -> (padOnsets: [RecordingTransient], soundOnsets: [RecordingTransient], measurements: [LatencyMeasurement]) {
        guard sampleRate > 0, !samples.isEmpty else { return ([], [], []) }
        let low = zeroPhaseLowPass(samples, sampleRate: sampleRate, cutoffHz: lowPassCutoffHz)
        let highLowPass = zeroPhaseLowPass(samples, sampleRate: sampleRate, cutoffHz: highPassCutoffHz)
        let high = zip(samples, highLowPass).map(-)
        let separation = max(200, maximumLatencyMilliseconds * 2)
        let pads = bandOnsets(low, sampleRate: sampleRate, minimumSeparationMilliseconds: separation)
        // El click puede llegar pocos milisegundos después del impacto físico;
        // no se aplica la separación entre golpes a la banda aguda.
        let sounds = bandOnsets(high, sampleRate: sampleRate, minimumSeparationMilliseconds: 2)
        return (pads, sounds, pair(padOnsets: pads, soundOnsets: sounds, minimumLatencyMilliseconds: minimumLatencyMilliseconds, maximumLatencyMilliseconds: maximumLatencyMilliseconds))
    }

    public static func pair(
        padOnsets: [RecordingTransient],
        soundOnsets: [RecordingTransient],
        minimumLatencyMilliseconds: Double = 2,
        maximumLatencyMilliseconds: Double = 100
    ) -> [LatencyMeasurement] {
        let minimum = minimumLatencyMilliseconds / 1_000
        let maximum = maximumLatencyMilliseconds / 1_000
        var soundIndex = 0
        var result: [LatencyMeasurement] = []
        for pad in padOnsets {
            while soundIndex < soundOnsets.count, soundOnsets[soundIndex].timeSeconds < pad.timeSeconds + minimum {
                soundIndex += 1
            }
            guard soundIndex < soundOnsets.count else { break }
            let sound = soundOnsets[soundIndex]
            let delay = sound.timeSeconds - pad.timeSeconds
            guard delay <= maximum else { continue }
            result.append(.init(pad: pad, sound: sound, milliseconds: delay * 1_000))
            soundIndex += 1
        }
        return result
    }

    public static func summary(of measurements: [LatencyMeasurement]) -> LatencyMeasurementSummary? {
        let values = measurements.map(\.milliseconds).sorted()
        guard let minimum = values.first, let maximum = values.last else { return nil }
        let median = percentile(values, fraction: 0.5)
        let percentile95 = percentile(values, fraction: 0.95)
        return .init(count: values.count, medianMilliseconds: median, percentile95Milliseconds: percentile95, minimumMilliseconds: minimum, maximumMilliseconds: maximum)
    }

    private static func bandOnsets(_ samples: [Float], sampleRate: Double, minimumSeparationMilliseconds: Double) -> [RecordingTransient] {
        let envelope = samples.map(abs)
        guard let maximum = envelope.max(), maximum > 0 else { return [] }
        let threshold = maximum * 0.18
        let separation = max(1, Int(sampleRate * minimumSeparationMilliseconds / 1_000))
        var result: [RecordingTransient] = []
        var index = 1
        while index < envelope.count {
            guard envelope[index] >= threshold, envelope[index - 1] < threshold else {
                index += 1
                continue
            }
            let end = min(envelope.count, index + separation)
            let peak = envelope[index..<end].enumerated().max { $0.element < $1.element }
            let peakIndex = index + (peak?.offset ?? 0)
            result.append(.init(timeSeconds: Double(index) / sampleRate, amplitude: envelope[peakIndex]))
            index = end
        }
        return result
    }

    private static func zeroPhaseLowPass(_ samples: [Float], sampleRate: Double, cutoffHz: Double) -> [Float] {
        guard cutoffHz > 0, cutoffHz < sampleRate / 2 else { return samples }
        let forward = onePoleLowPass(samples, sampleRate: sampleRate, cutoffHz: cutoffHz)
        return Array(onePoleLowPass(forward.reversed(), sampleRate: sampleRate, cutoffHz: cutoffHz).reversed())
    }

    private static func onePoleLowPass<S: Sequence>(_ samples: S, sampleRate: Double, cutoffHz: Double) -> [Float] where S.Element == Float {
        let alpha = Float(exp(-2 * Double.pi * cutoffHz / sampleRate))
        var previous: Float = 0
        return samples.map { sample in
            previous = (1 - alpha) * sample + alpha * previous
            return previous
        }
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double {
        let position = max(0, min(Double(values.count - 1), fraction * Double(values.count - 1)))
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let weight = position - Double(lower)
        return values[lower] + (values[upper] - values[lower]) * weight
    }
}
