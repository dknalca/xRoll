import AVFoundation
import XCTest
@testable import XRollCore

final class ScheduledAudioTests: XCTestCase {
    private final class Fixture {
        let directory: URL
        let engine = AVAudioEngine()
        let audio: SampleAudioEngine
        let format: AVAudioFormat
        let anchor = AudioClock.currentHostTime()
        let kit: KitManifest

        init(renderSampleRate: Double = 44_100) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-scheduled-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sourceFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
            format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: renderSampleRate, channels: 1))
            kit = KitManifest(format: 1, id: "test", name: "Test", sounds: [
                .init(id: "hihat_open", label: "Abierto", file: "open.wav", gmNote: 46, chokeGroup: "hat"),
                .init(id: "hihat_closed", label: "Cerrado", file: "closed.wav", gmNote: 42, chokeGroup: "hat")
            ])
            for sound in kit.sounds {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 32_768))
                buffer.frameLength = buffer.frameCapacity
                let samples = try XCTUnwrap(buffer.floatChannelData)[0]
                for frame in 0..<Int(buffer.frameLength) {
                    samples[frame] = sound.id == "hihat_closed" && frame >= 256 ? 0 : 0.2
                }
                var settings = sourceFormat.settings
                settings[AVLinearPCMIsNonInterleaved] = false
                let file = try AVAudioFile(forWriting: directory.appendingPathComponent(sound.file), settings: settings)
                try file.write(from: buffer)
            }
            let base = anchor
            audio = SampleAudioEngine(engine: engine, scheduledTime: { hostTime in
                let frames = (AudioClock.milliseconds(from: base, to: hostTime) * 44.1).rounded()
                return AVAudioTime(sampleTime: AVAudioFramePosition(frames), atRate: 44_100)
            })
            try audio.load(kit: kit, from: directory)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
            try audio.start()
        }

        deinit {
            audio.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        func time(_ frame: Int) -> UInt64 {
            AudioClock.hostTime(afterMilliseconds: Double(frame) / 44.1, from: anchor)
        }

        func render(_ frames: Int) throws -> [Float] {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
            var samples = [Float]()
            while samples.count < frames {
                let count = AVAudioFrameCount(min(512, frames - samples.count))
                XCTAssertEqual(try engine.renderOffline(count, to: buffer), .success)
                let channel = try XCTUnwrap(buffer.floatChannelData)[0]
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
            return samples
        }
    }

    func testScheduledSixteenthsKeepTheirOwnGainAcrossRepeatedVoiceReuse() throws {
        let fixture = try Fixture()
        let interval = 2_756
        let gains: [Float] = (0..<32).map { [Float(0.2), 0.6, 1][$0 % 3] }
        for (index, gain) in gains.enumerated() {
            if index == 16 { fixture.audio.setSoundVolume(0.5, for: "hihat_open") }
            try fixture.audio.schedule(soundID: "hihat_open", atHostTime: fixture.time(512 + index * interval), volume: gain)
        }
        try fixture.audio.flushScheduledSounds()
        let samples = try fixture.render(512 + gains.count * interval)
        XCTAssertTrue(samples[..<512].allSatisfy { abs($0) < 0.000_01 })
        let reference = (samples[512..<640].map(abs).max() ?? 0) / gains[0]
        XCTAssertGreaterThan(reference, 0.1)
        for (index, gain) in gains.enumerated() {
            let start = 512 + index * interval
            let peak = samples[start..<(start + 128)].map(abs).max() ?? 0
            XCTAssertEqual(peak, reference * gain * (index >= 16 ? 0.5 : 1), accuracy: 0.000_1,
                "La ganancia del golpe \(index) debe ser independiente del último evento de su nodo")
        }
    }

    func testLiveHiHatAttacksAndChokeSurviveSampleRateConversionAndPoolReuse() throws {
        let fixture = try Fixture(renderSampleRate: 48_000)
        // WAV a 44,1 kHz y salida a 48 kHz: se ejercita el conversor que no
        // aparecía en las pruebas anteriores, incluida la rotación de cada pool.
        for interval in [4_500, 3_000] {
            for index in 0..<32 {
                try fixture.audio.play(soundID: index.isMultiple(of: 4) ? "hihat_open" : "hihat_closed")
                let samples = try fixture.render(interval)
                XCTAssertGreaterThan(samples.prefix(512).map(abs).max() ?? 0, 0.1,
                    "Debe sonar cada ataque, también al reutilizar nodos: \(index)")
                let tail = samples.dropFirst(1_024).map(abs).max() ?? 0
                if index.isMultiple(of: 4) { XCTAssertGreaterThan(tail, 0.1) }
                else { XCTAssertLessThan(tail, 0.000_1, "El cerrado debe silenciar la cola del abierto") }
            }
        }
    }

    func testLiveHiHatDoesNotCancelAnAttackAdmittedBeforeTheNextRenderQuantum() throws {
        let fixture = try Fixture()
        try fixture.audio.play(soundID: "hihat_closed")
        let reference = try fixture.render(1_024).prefix(128).map(abs).max() ?? 0
        XCTAssertGreaterThan(reference, 0.01)
        // Simula dos entregas MIDI antes del siguiente render, como puede
        // ocurrir con paquetes agrupados o un buffer efectivo mayor.
        try fixture.audio.play(soundID: "hihat_closed")
        try fixture.audio.play(soundID: "hihat_closed")
        let peak = try fixture.render(1_024).prefix(128).map(abs).max() ?? 0
        XCTAssertEqual(peak, reference * 2, accuracy: 0.000_1,
            "El segundo golpe no puede eliminar un ataque que aún no se ha renderizado")
    }

    func testScheduledOpenClosedAlternationCutsTailsAndCancellationKeepsLiveAudio() throws {
        let fixture = try Fixture()
        let interval = 4_096
        for index in 0..<24 {
            try fixture.audio.schedule(soundID: index.isMultiple(of: 2) ? "hihat_open" : "hihat_closed",
                atHostTime: fixture.time(512 + index * interval))
        }
        try fixture.audio.flushScheduledSounds()
        let samples = try fixture.render(512 + 24 * interval)
        for index in 0..<24 {
            let start = 512 + index * interval
            XCTAssertGreaterThan(samples[start..<(start + 128)].map(abs).max() ?? 0, 0.1)
            let tail = samples[(start + 512)..<(start + interval - 128)].map(abs).max() ?? 0
            if index.isMultiple(of: 2) { XCTAssertGreaterThan(tail, 0.1) }
            else { XCTAssertLessThan(tail, 0.000_01, "La cola del abierto debe acabar al entrar el cerrado") }
        }
        // El último evento queda pendiente hasta flush: cancelar también debe
        // descartarlo, sin desactivar las voces del golpe vivo.
        try fixture.audio.schedule(soundID: "hihat_open", atHostTime: fixture.time(samples.count + 512))
        fixture.audio.stopScheduledSounds()
        try fixture.audio.flushScheduledSounds()
        XCTAssertTrue(try fixture.render(1_024).allSatisfy { abs($0) < 0.000_01 })
        try fixture.audio.play(soundID: "hihat_closed")
        XCTAssertGreaterThan(try fixture.render(512).map(abs).max() ?? 0, 0.1)
    }

    func testPreparedSegmentsAreReusedBoundedAndInvalidatedByKitReload() throws {
        let fixture = try Fixture()
        for index in 0..<32 {
            try fixture.audio.schedule(soundID: "hihat_open", atHostTime: fixture.time(512 + index * 4_096), volume: 0.5)
        }
        try fixture.audio.flushScheduledSounds()
        let reused = fixture.audio.scheduledBufferCacheStatistics
        XCTAssertGreaterThan(reused.hits, 20)
        XCTAssertLessThanOrEqual(reused.count, 3) // Duración repetida ± redondeo y última cola completa.
        fixture.audio.stopScheduledSounds()
        for index in 0..<100 {
            try fixture.audio.schedule(soundID: "hihat_open", atHostTime: fixture.time(512 + index * 4_096), volume: Float(index + 1) / 100)
        }
        try fixture.audio.flushScheduledSounds()
        let bounded = fixture.audio.scheduledBufferCacheStatistics
        XCTAssertLessThanOrEqual(bounded.count, 64)
        XCTAssertLessThanOrEqual(bounded.bytes, 4 * 1_024 * 1_024)
        fixture.audio.stopScheduledSounds()
        // Colas completas con ganancias distintas fuerzan el límite de bytes
        // antes del límite de entradas (32.768 frames Float32 por copia).
        for index in 0..<40 {
            try fixture.audio.schedule(soundID: "hihat_open", atHostTime: fixture.time(512 + index * 65_536),
                volume: Float(index + 1) / 100)
        }
        try fixture.audio.flushScheduledSounds()
        let large = fixture.audio.scheduledBufferCacheStatistics
        XCTAssertLessThan(large.count, 40)
        XCTAssertLessThanOrEqual(large.bytes, 4 * 1_024 * 1_024)
        try fixture.audio.load(kit: fixture.kit, from: fixture.directory)
        XCTAssertEqual(fixture.audio.scheduledBufferCacheStatistics.count, 0)
        XCTAssertEqual(fixture.audio.scheduledBufferCacheStatistics.bytes, 0)
    }

    func testScheduledMetronomeRetainsPerClickVolume() throws {
        let fixture = try Fixture()
        for (index, gain) in [Float(0.2), 0.8, 0.4].enumerated() {
            try fixture.audio.scheduleMetronome(atHostTime: fixture.time(512 + index * 4_096), volume: gain)
        }
        let samples = try fixture.render(512 + 3 * 4_096)
        let peaks = (0..<3).map { index in
            samples[(512 + index * 4_096)..<(512 + index * 4_096 + 1_024)].map(abs).max() ?? 0
        }
        XCTAssertGreaterThan(peaks[0], 0.01)
        XCTAssertEqual(peaks[1] / peaks[0], 4, accuracy: 0.001)
        XCTAssertEqual(peaks[2] / peaks[0], 2, accuracy: 0.001)
    }
}
