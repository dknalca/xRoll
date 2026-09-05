import AVFoundation
import Foundation

public struct RecordingTransient: Equatable {
    public let timeSeconds: Double
    public let amplitude: Float
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
            for channel in 0..<channelCount {
                value = max(value, abs(channels[channel][frame]))
            }
            samples[frame] = value
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
}
