import AppKit
import AudioToolbox
import Combine
import CoreMIDI
import Foundation
import SwiftUI
import SpriteKit
import UniformTypeIdentifiers
import XRollCore

private struct PadPosition: Identifiable {
    let note: Int; let key: String; let row: Int; let column: Int
    var id: Int { note }
}

private let positions = [
    PadPosition(note: 48, key: "1", row: 3, column: 0), PadPosition(note: 49, key: "2", row: 3, column: 1), PadPosition(note: 50, key: "3", row: 3, column: 2), PadPosition(note: 51, key: "4", row: 3, column: 3),
    PadPosition(note: 44, key: "Q", row: 2, column: 0), PadPosition(note: 45, key: "W", row: 2, column: 1), PadPosition(note: 46, key: "E", row: 2, column: 2), PadPosition(note: 47, key: "R", row: 2, column: 3),
    PadPosition(note: 40, key: "A", row: 1, column: 0), PadPosition(note: 41, key: "S", row: 1, column: 1), PadPosition(note: 42, key: "D", row: 1, column: 2), PadPosition(note: 43, key: "F", row: 1, column: 3),
    PadPosition(note: 36, key: "Z", row: 0, column: 0), PadPosition(note: 37, key: "X", row: 0, column: 1), PadPosition(note: 38, key: "C", row: 0, column: 2), PadPosition(note: 39, key: "V", row: 0, column: 3)
]

final class Model: ObservableObject {
    static let repeatOptions = [1, 2, 4, 8, 16]
    @Published var status = "Cargando…"; @Published var active = Set<String>()
    @Published var exercises = [Exercise](); @Published var chosenID = ""; @Published var preview = ""
    @Published var sources = [MIDIEndpointDescription](); @Published var sourceID: MIDIUniqueID?
    @Published var audioOutputs = [AudioOutputDeviceDescription](); @Published var selectedAudioOutputUID: String?
    @Published var mapping = false; @Published var mapMessage = ""
    @Published var showingExerciseImporter = false; @Published var exerciseImportMessage = ""
    @Published var keyboardMapping = false; @Published var keyboardMapMessage = ""; @Published private(set) var keyboardKeys = [String: String]()
    @Published var practiceScene: PracticeScene?; @Published var judgement = ""; @Published var result = ""
    @Published var previewScene: PracticeScene?
    @Published var progress = ""; @Published var scoreHistory = [Double](); @Published var advice = ""; @Published var calibrationMessage = "Sin calibracion para este perfil."
    @Published var selectedBPM = 80; @Published var selectedRepeats = 4; @Published var recovery = ""; @Published var insights = ""
    @Published var practiceFragment = 0
    @Published var soundStatistics = [SoundStatistics](); @Published var recentAttempts = [PracticeAttempt](); @Published var progressFilter = 0; @Published var exportMessage = ""
    @Published var courseLevels = [CourseLevelState]()
    @Published var tuning = PracticeTuning()
    @Published var loopEnabled = true; @Published var loopStatus = "Sin loop cargado"; @Published var loopTempo: Double?
    @Published var metronomeEnabled = true
    @Published var liveTotalHits = 0; @Published var liveWellTimed = 0; @Published var liveRegular = 0; @Published var liveWrong = 0; @Published var livePercentage = 0.0
    @Published var lastScorePercentage: Double?; @Published var lastScoreStars = 0
    @Published var lastTotalHits = 0; @Published var lastWellTimed = 0; @Published var lastRegular = 0; @Published var lastWrong = 0
    @Published var lastPoints = 0.0; @Published var lastPossiblePoints = 0; @Published var nextExerciseTitle: String?
    @Published var showingResults = false
    private var kit: KitManifest?; private var audio: SampleAudioEngine?; private var gm: KitNoteRouter?; private var bundledExercises = [Exercise]()
    private var custom: PadMap?; private var customRouter: PadMapRouter?; private var input: MIDIInputSession?
    private var builder: PadMapBuilder?; private var keyboardCapture = [String: String](); private var monitor: Any?
    private var midiRefreshTimer: Timer?
    private var practice: PracticeSession?; private var practiceStartHostTime: UInt64 = 0; private var practiceToken = UUID()
    private var previewToken = UUID()
    private var progressStore: ProgressStore?; private var calibrationOffset: Double = 0; private var calibrating = false

    init() {
        load()
        // CoreMIDI does not reconnect an input port to sources that appear after
        // the port was created. Polling its lightweight source list keeps USB
        // controllers usable when they are plugged in while xRoll is open.
        midiRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshMIDIDevices(announceChanges: false)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard !event.isARepeat, let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return event }
            if self?.keyboardMapping == true { self?.captureKeyboardKey(key); return nil }
            if let sound = self?.keyboardKeys[key] { self?.play(sound, position: self?.position(sound), volume: 0.85); return nil }
            guard self?.keyboardKeys.isEmpty ?? true, let pad = positions.first(where: { $0.key == key }) else { return event }
            self?.trigger(pad); return nil
        }
    }
    deinit {
        midiRefreshTimer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    var chosen: Exercise? { exercises.first { $0.id == chosenID } }
    var configuredExercise: Exercise? {
        chosen.map { selected in
            let configured = PracticeConfiguration(exercise: selected, bpm: selectedBPM, repeats: selectedRepeats).applying(to: selected)
            return exerciseForFragment(configured)
        }
    }
    private func exerciseForFragment(_ exercise: Exercise) -> Exercise {
        let notes: [Exercise.Note]
        switch practiceFragment {
        case 1: notes = exercise.notes.filter { $0.step < exercise.grid / 2 }
        case 2: notes = exercise.notes.filter { $0.step >= exercise.grid / 2 }
        default: notes = exercise.notes
        }
        return Exercise(format: exercise.format, id: exercise.id, title: exercise.title, family: exercise.family, level: exercise.level, bpm: exercise.bpm, meter: exercise.meter, bars: exercise.bars, grid: exercise.grid, repeats: exercise.repeats, kit: exercise.kit, loop: exercise.loop, offset: exercise.offset, notes: notes)
    }
    var lessonGoal: String {
        guard let chosen else { return "Elige un nivel para ver el objetivo." }
        let currentSounds = Set(chosen.notes.map(\.sound))
        let previousSounds = exercises.first(where: { $0.level == chosen.level - 1 }).map { Set($0.notes.map(\.sound)) } ?? []
        let introduced = currentSounds.subtracting(previousSounds)
        if !introduced.isEmpty {
            return "Nueva habilidad: añade \(introduced.map(displayName).sorted().joined(separator: " y "))."
        }
        return "Objetivo: mantén el pulso mientras cambia el patrón de bombo y caja."
    }
    var lessonPattern: [String] {
        guard let chosen else { return [] }
        let counts = Dictionary(grouping: chosen.notes, by: \.sound).mapValues(\.count)
        let order = ["kick", "snare", "hihat_closed", "hihat_open", "clap", "tom_low", "tom_high", "crash", "ride"]
        return order.compactMap { sound in
            guard let count = counts[sound] else { return nil }
            return "\(displayName(sound)) ×\(count)"
        }
    }
    var weakestSoundFeedback: String {
        guard let weakest = soundStatistics.min(by: { $0.accuracy < $1.accuracy }) else { return "Completa una vuelta para recibir una recomendación." }
        return "Repasa \(displayName(weakest.sound)): \(Int(weakest.accuracy.rounded())) % de acierto (\(weakest.missed) fallos)."
    }
    var nextPracticeRecommendation: String {
        guard let score = lastScorePercentage else { return "Empieza por escuchar una demostración guiada." }
        if score >= 70, let nextExerciseTitle { return "Buen trabajo: prueba \(nextExerciseTitle)." }
        return "Repite el mismo nivel enfocándote en el sonido indicado."
    }
    fileprivate func name(_ pad: PadPosition) -> String? {
        custom?.pads.first(where: { $0.row == pad.row && $0.column == pad.column })?.sound ?? kit?.sounds.first(where: { $0.gmNote == pad.note })?.id
    }
    func displayName(_ sound: String?) -> String {
        guard let sound else { return "Libre" }
        return kit?.sounds.first(where: { $0.id == sound })?.label ?? sound.replacingOccurrences(of: "_", with: " ").capitalized
    }
    func selectSource() {
        mapping = false; builder = nil
        if let sourceID { UserDefaults.standard.set(Int(sourceID), forKey: "xRoll.midiSourceID") }
        else { UserDefaults.standard.removeObject(forKey: "xRoll.midiSourceID") }
        connect()
    }
    func refreshAudioOutputs() {
        audioOutputs = AudioInspector.outputDevices()
        if let selectedAudioOutputUID, !audioOutputs.contains(where: { $0.uid == selectedAudioOutputUID }) {
            self.selectedAudioOutputUID = AudioInspector.defaultOutputDeviceID().flatMap { id in audioOutputs.first(where: { $0.deviceID == id })?.uid }
        }
        guard let selected = audioOutputs.first(where: { $0.uid == selectedAudioOutputUID }) else {
            status = "No hay salidas de audio disponibles"
            return
        }
        status = "Salidas actualizadas: \(selected.name)"
    }
    func selectAudioOutput() {
        guard let selected = audioOutputs.first(where: { $0.uid == selectedAudioOutputUID }) else { return }
        do {
            audio?.stopScheduledSounds()
            audio?.stopLoop()
            try audio?.setOutputDevice(selected.deviceID)
            UserDefaults.standard.set(selected.uid, forKey: "xRoll.audioOutputUID")
            loadCalibration()
            status = "Salida de audio: \(selected.name)"
        } catch {
            status = error.localizedDescription
        }
    }
    func refreshMIDIDevices() { refreshMIDIDevices(announceChanges: true) }
    private func refreshMIDIDevices(announceChanges: Bool) {
        let available = MIDIInspector.sources().filter { $0.uniqueID != nil }
        let changed = available != sources
        guard changed || announceChanges else { return }

        let previousID = sourceID
        sources = available

        if let previousID, available.contains(where: { $0.uniqueID == previousID }) {
            if changed { connect() }
        } else if let preferred = available.first(where: { $0.name.localizedCaseInsensitiveContains("Pocket-Private") }) ?? available.first {
            sourceID = preferred.uniqueID
            connect()
        } else {
            sourceID = nil
            input = nil
            custom = nil
            customRouter = nil
            mapping = false
            builder = nil
            calibrationOffset = 0
            loadCalibration()
            status = "Teclado listo · sin MIDI conectado"
        }

        guard announceChanges else { return }
        if let selected = sources.first(where: { $0.uniqueID == sourceID }) {
            status = "MIDI actualizado: \(selected.name)"
        } else {
            status = "No hay fuentes MIDI conectadas"
        }
    }
    func startMapping() {
        guard let source = sources.first(where: { $0.uniqueID == sourceID }) else { mapMessage = "Elige una entrada MIDI."; return }
        builder = PadMapBuilder(device: source.name, deviceUID: Int(source.uniqueID ?? 0), created: ISO8601DateFormatter().string(from: Date()))
        mapping = true; mapMessage = "Golpea el pad para bombo."
    }
    func cancelMapping() { mapping = false; builder = nil; mapMessage = "Asignacion cancelada." }
    func skipMappingSound() {
        guard var builder, let result = builder.skip() else { return }
        self.builder = builder
        switch result {
        case .skipped(let sound, let remaining): mapMessage = "Omitido \(displayName(sound)). Quedan \(remaining). \(nextPrompt())"
        case .complete(let map): save(map)
        default: break
        }
    }
    func startKeyboardMapping() {
        keyboardMapping = true; keyboardCapture = [:]
        keyboardMapMessage = "Pulsa la tecla para bombo. Se asignarán seis sonidos."
    }
    func cancelKeyboardMapping() { keyboardMapping = false; keyboardCapture = [:]; keyboardMapMessage = "Asignación de teclado cancelada." }
    fileprivate func keyboardLabel(for pad: PadPosition) -> String {
        guard !keyboardKeys.isEmpty, let sound = name(pad) else { return pad.key }
        return keyboardKeys.first(where: { $0.value == sound })?.key ?? "—"
    }
    func previewExercise() {
        guard let selected = chosen, let audio else { return }
        do {
            audio.stopScheduledSounds()
            audio.stopLoop()
            let exercise = PracticeConfiguration(exercise: selected, bpm: selectedBPM, repeats: 1).applying(to: selected)
            let timeline = ExerciseTimeline(exercise: exercise)
            let base = AudioClock.hostTime(afterMilliseconds: 700)
            for note in timeline.notes { try audio.schedule(soundID: note.sound, atHostTime: AudioClock.hostTime(afterMilliseconds: note.timeMilliseconds, from: base)) }
            previewScene = PracticeScene(timeline: timeline, startHostTime: base, anticipationMilliseconds: timeline.patternDurationMilliseconds, slotBySound: slotsBySound(), soundLabels: soundLabels())
            preview = "Mira y escucha una vuelta. No se puntúa."
            let token = UUID(); previewToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + (700 + timeline.patternDurationMilliseconds + 250) / 1_000) { [weak self] in
                guard self?.previewToken == token else { return }
                self?.previewScene = nil
            }
        } catch { preview = error.localizedDescription }
    }
    func stopPreview() {
        previewToken = UUID()
        previewScene = nil
        audio?.stopScheduledSounds()
    }
    func startPractice() { beginPractice(calibration: false) }
    func repeatPractice() { showingResults = false; beginPractice(calibration: false) }
    func setRepeats(_ repeats: Int) {
        selectedRepeats = PracticeConfiguration.normalizedRepeats(repeats)
        savePreferences()
    }
    func restartPractice() {
        guard practice != nil else { return }
        beginPractice(calibration: calibrating)
    }
    func moveToSuggestedExercise() {
        guard let next = exercises.first(where: { $0.title == nextExerciseTitle }) else { return }
        chosenID = next.id; selectedBPM = next.bpm; selectedRepeats = next.repeats; preview = ""
        showingResults = false; savePreferences(); refreshProgress(for: next.id)
    }
    func dismissResults() { showingResults = false }
    func toggleLoop() {
        setLoopEnabled(!loopEnabled)
    }
    func setLoopEnabled(_ enabled: Bool) {
        loopEnabled = enabled
        guard enabled else { audio?.stopLoop(); return }
        guard let practice, let exercise = configuredExercise else { return }
        let elapsed = AudioClock.milliseconds(from: practiceStartHostTime, to: AudioGetCurrentHostTime())
        let bar = practice.timeline.patternDurationMilliseconds
        let nextBar = max(0, ceil(elapsed / bar) * bar - elapsed)
            do { try audio?.startLoop(atHostTime: AudioClock.hostTime(afterMilliseconds: nextBar), targetBPM: Double(exercise.bpm), volume: Float(tuning.loopVolume)) }
        catch { loopStatus = "Error al iniciar el loop: \(error.localizedDescription)" }
    }
    func startCalibration() { beginPractice(calibration: true) }
    private func beginPractice(calibration: Bool) {
        guard let exercise = configuredExercise else { return }
        previewToken = UUID()
        previewScene = nil
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        savePreferences()
        calibrating = calibration
        let session = PracticeSession(exercise: exercise, calibrationOffsetMilliseconds: calibration ? 0 : calibrationOffset + tuning.manualTimingOffsetMilliseconds, scoringWindows: calibration ? nil : tuning.scoringWindows)
        let anticipation = session.timeline.patternDurationMilliseconds * Double(tuning.anticipationBars)
        let now = AudioGetCurrentHostTime()
        let start = AudioClock.hostTime(afterMilliseconds: anticipation, from: now)
        practice = session; practiceStartHostTime = start; judgement = calibration ? "Calibracion: sigue las notas durante todas las vueltas." : "Preparado: dos compases de anticipacion."; result = ""
        liveTotalHits = 0; liveWellTimed = 0; liveRegular = 0; liveWrong = 0; livePercentage = 0
        practiceScene = PracticeScene(timeline: session.timeline, startHostTime: start, anticipationMilliseconds: anticipation, slotBySound: slotsBySound(), soundLabels: soundLabels())
        let beat = 60_000.0 / Double(exercise.bpm)
        let countInStart = max(0, anticipation - session.timeline.patternDurationMilliseconds)
        let totalMilliseconds = anticipation + session.timeline.patternDurationMilliseconds * Double(exercise.repeats)
        let metronomeBeats = Int(ceil((totalMilliseconds - countInStart) / beat))
        if metronomeEnabled {
            for beatIndex in 0...metronomeBeats {
                // A clap on the first beat makes the pulse distinguishable from
                // the closed hi-hats in the exercise and accompaniment.
                let sound = beatIndex.isMultiple(of: 4) ? "clap" : "hihat_closed"
                try? audio?.scheduleMetronome(soundID: sound, atHostTime: AudioClock.hostTime(afterMilliseconds: countInStart + Double(beatIndex) * beat, from: now), volume: Float(tuning.countInVolume), pitchCents: Float(tuning.metronomePitchSemitones * 100))
            }
        }
        if loopEnabled && !calibration {
            do { try audio?.startLoop(atHostTime: start, targetBPM: Double(exercise.bpm), volume: Float(tuning.loopVolume)) }
            catch { loopStatus = "Error al iniciar el loop: \(error.localizedDescription)" }
        }
        let token = UUID(); practiceToken = token
        let duration = anticipation + session.timeline.patternDurationMilliseconds * Double(exercise.repeats) + 150
        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 1_000) { [weak self] in
            guard self?.practiceToken == token else { return }; self?.finishPractice()
        }
    }
    func finishPractice() {
        guard let currentPractice = practice, let exercise = configuredExercise else { return }
        // Stop every queued click immediately when the player ends a session,
        // including a click scheduled later in the current bar.
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        let score = currentPractice.score
        lastScorePercentage = score.percentage; lastScoreStars = score.stars
        lastTotalHits = score.hits.count
        lastWellTimed = score.perfectCount + score.goodCount
        lastRegular = score.regularCount
        lastWrong = score.misses.count + score.extraCount
        lastPoints = Double(score.perfectCount) + Double(score.goodCount) * 0.85 + Double(score.regularCount) * 0.7
        lastPossiblePoints = currentPractice.timeline.notes.count
        nextExerciseTitle = score.stars >= 1 ? exercises.first(where: { $0.level == exercise.level + 1 })?.title : nil
        let offset = score.meanOffsetMilliseconds.map { String(format: " · media %.0f ms", $0) } ?? ""
        result = String(format: "Resultado: %.0f %% · %d estrellas · P%d B%d R%d · %d fallos · %d extras%@", score.percentage, score.stars, score.perfectCount, score.goodCount, score.regularCount, score.misses.count, score.extraCount, offset)
        advice = advice(for: score)
        let practiceInsights = PracticeInsights(score: score)
        insights = practiceInsights.timingLabel
        soundStatistics = practiceInsights.soundStatistics
        // Updating the course can select an exercise. The session must already
        // be closed, otherwise that selection recursively finishes this attempt.
        self.practice = nil; practiceScene = nil; practiceToken = UUID()
        if calibrating {
            saveCalibration(offsets: score.hits.compactMap(\.offsetMilliseconds))
        } else {
            recordAttempt(exercise: exercise, score: score)
            showingResults = true
        }
        calibrating = false
    }
    private func load() {
        let workingRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let bundledRoot = Bundle.main.resourceURL?.appendingPathComponent("ProjectData", isDirectory: true)
        let root = bundledRoot.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json").path) ? $0 : nil } ?? workingRoot
        let kitDir = root.appendingPathComponent("Resources/Kits/hiphop_basic")
        do {
            let catalog = ResourceCatalog(); let loaded = try catalog.loadKit(at: kitDir.appendingPathComponent("kit.json"))
            let newAudio = SampleAudioEngine(); try newAudio.load(kit: loaded, from: kitDir)
            audioOutputs = AudioInspector.outputDevices()
            let savedOutputUID = UserDefaults.standard.string(forKey: "xRoll.audioOutputUID")
            let defaultOutputUID = AudioInspector.defaultOutputDeviceID().flatMap { id in audioOutputs.first(where: { $0.deviceID == id })?.uid }
            selectedAudioOutputUID = audioOutputs.contains(where: { $0.uid == savedOutputUID }) ? savedOutputUID : defaultOutputUID
            if let selected = audioOutputs.first(where: { $0.uid == selectedAudioOutputUID }) { try newAudio.setOutputDevice(selected.deviceID) }
            try newAudio.start()
            kit = loaded; audio = newAudio; gm = KitNoteRouter(kit: loaded)
            loadLoop(from: root)
            progressStore = try ProgressStore(url: applicationSupportURL("progress.sqlite"))
            bundledExercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: loaded)
            reloadCommunityExercises()
            chosenID = exercises.first?.id ?? ""
            selectedBPM = exercises.first?.bpm ?? 80; selectedRepeats = exercises.first?.repeats ?? 4
            loadPreferences()
            loadTuning()
            loadKeyboardMap()
            sources = MIDIInspector.sources().filter { $0.uniqueID != nil }
            let savedSourceID = MIDIUniqueID(UserDefaults.standard.integer(forKey: "xRoll.midiSourceID"))
            sourceID = sources.contains(where: { $0.uniqueID == savedSourceID })
                ? savedSourceID
                : sources.first(where: { $0.name.localizedCaseInsensitiveContains("Pocket-Private") })?.uniqueID ?? sources.first?.uniqueID
            connect()
            refreshRecentAttempts()
            refreshCourseLevels()
            recovery = RecoveryAdvisor.assess(missingSamples: catalog.missingSampleFiles(for: loaded, in: kitDir), hasMIDIInput: !sources.isEmpty).message
        } catch { status = "No se pudo iniciar: \(error.localizedDescription)"; recovery = RecoveryAdvisor.assess(missingSamples: [], hasMIDIInput: false, hasAudio: false).message }
    }
    func importCommunityExercise(from url: URL) {
        guard let kit else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            guard ["mid", "midi"].contains(url.pathExtension.lowercased()) else { throw MIDIExerciseError.invalidFile("elige un archivo .mid o .midi") }
            let directory = applicationSupportURL("community-exercises")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stem = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
            let destination = directory.appendingPathComponent("\(stem.isEmpty ? "ejercicio" : stem)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())")
            try FileManager.default.copyItem(at: url, to: destination)
            _ = try MIDIExerciseLoader.load(url: destination, kit: kit, level: bundledExercises.count + 1)
            reloadCommunityExercises()
            exerciseImportMessage = "Importado: \(url.lastPathComponent)."
        } catch { exerciseImportMessage = "No se pudo importar: \(error.localizedDescription)" }
    }
    private func reloadCommunityExercises() {
        guard let kit else { exercises = bundledExercises; return }
        let directory = applicationSupportURL("community-exercises")
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let imported = urls.filter { ["mid", "midi"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }.enumerated().compactMap { index, url in
            try? MIDIExerciseLoader.load(url: url, kit: kit, level: bundledExercises.count + index + 1)
        }
        exercises = bundledExercises + imported
    }
    private func connect() {
        input = nil
        guard let sourceID, let endpoint = MIDIInspector.source(withUniqueID: sourceID) else { status = "Teclado listo"; return }
        do {
            let session = try MIDIInputSession { [weak self] event in self?.receive(event) }
            try session.connect(source: endpoint)
            input = session
            loadMap(sourceID)
            status = "Teclado y MIDI listos"
            loadCalibration()
        } catch { status = error.localizedDescription }
    }
    private func receive(_ event: MIDINoteOn) {
        if mapping { DispatchQueue.main.async { [weak self] in self?.capture(event) }; return }
        guard let sound = customRouter?.soundID(for: event) ?? gm?.soundID(for: event) else { return }
        // CoreMIDI invokes this callback on its own thread. AVAudioPlayerNode
        // and the observable UI state must be touched from the main queue.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.play(sound, position: self.position(sound), volume: VelocityCurve.gain(for: UInt8(clamping: event.velocity)))
        }
    }
    private func loadLoop(from root: URL) {
        let loopDirectory = root.appendingPathComponent("Resources/Loops", isDirectory: true)
        guard let url = try? FileManager.default.contentsOfDirectory(at: loopDirectory, includingPropertiesForKeys: nil)
            .first(where: { ["wav", "aif", "aiff", "m4a"].contains($0.pathExtension.lowercased()) }) else { return }
        do {
            guard let audio else { return }
            try audio.loadLoop(url: url)
            loopTempo = audio.loopTempo?.bpm
            if let tempo = loopTempo { loopStatus = "\(url.deletingPathExtension().lastPathComponent) · detectado a \(Int(tempo.rounded())) BPM" }
        } catch { loopStatus = "No se pudo cargar el loop: \(error.localizedDescription)" }
    }
    private func capture(_ event: MIDINoteOn) {
        guard var builder else { return }; let result = builder.assign(event); self.builder = builder
        switch result {
        case .assigned(let sound, let remaining): mapMessage = "Asignado \(sound). Quedan \(remaining). \(nextPrompt())"
        case .skipped: break
        case .duplicate(let note, let channel, let sound): mapMessage = "Nota \(note), canal \(channel), ya asignada a \(sound)."
        case .complete(let map): save(map)
        }
    }
    private func captureKeyboardKey(_ key: String) {
        guard let nextSound = PadMapBuilder.suggestedSteps.dropFirst(keyboardCapture.count).first?.sound else { return }
        guard keyboardCapture[key] == nil else { keyboardMapMessage = "La tecla (key) ya está asignada. Pulsa otra para (displayName(nextSound))."; return }
        keyboardCapture[key] = nextSound
        let remaining = PadMapBuilder.suggestedSteps.count - keyboardCapture.count
        if remaining == 0 {
            keyboardKeys = keyboardCapture
            saveKeyboardMap()
            keyboardMapping = false
            keyboardCapture = [:]
            keyboardMapMessage = "Teclado guardado. Ya puedes practicar con esas seis teclas."
        } else if let following = PadMapBuilder.suggestedSteps.dropFirst(keyboardCapture.count).first {
            keyboardMapMessage = "\(displayName(nextSound)): \(key). Quedan \(remaining). Pulsa la tecla para \(displayName(following.sound))."
        }
    }
    private func nextPrompt() -> String { builder?.nextStep.map { "Golpea el pad para \($0.sound)." } ?? "" }
    private func mapURL(_ id: Int) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("xRoll/padmaps/\(id).padmap") }
    private func applicationSupportURL(_ file: String) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("xRoll/\(file)") }
    private func loadKeyboardMap() {
        let url = applicationSupportURL("keyboard-map.json")
        guard let data = try? Data(contentsOf: url), let map = try? JSONDecoder().decode([String: String].self, from: data), map.count == PadMapBuilder.suggestedSteps.count else { return }
        keyboardKeys = map
    }
    private func saveKeyboardMap() {
        let url = applicationSupportURL("keyboard-map.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(keyboardKeys).write(to: url, options: .atomic)
        } catch { keyboardMapMessage = "No se pudo guardar el teclado: \(error.localizedDescription)" }
    }
    private func loadMap(_ id: MIDIUniqueID) {
        guard let kit else { return }; let url = mapURL(Int(id)); guard FileManager.default.fileExists(atPath: url.path) else { custom = nil; customRouter = nil; return }
        do { let map = try PadMapStore.load(at: url, availableSounds: Set(kit.sounds.map(\.id))); custom = map; customRouter = PadMapRouter(padMap: map) } catch { status = "Mapa invalido: \(error.localizedDescription)" }
    }
    private func save(_ map: PadMap) {
        guard let kit else { return }
        do { let url = mapURL(map.deviceUID); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try PadMapStore.save(map, to: url, availableSounds: Set(kit.sounds.map(\.id))); custom = map; customRouter = PadMapRouter(padMap: map); mapping = false; builder = nil; mapMessage = "Mapa guardado." } catch { mapMessage = error.localizedDescription }
    }
    private func trigger(_ pad: PadPosition) { if let sound = name(pad) { play(sound, position: pad, volume: 0.85) } }
    private func position(_ sound: String) -> PadPosition? {
        if let pad = custom?.pads.first(where: { $0.sound == sound }) { return positions.first { $0.row == pad.row && $0.column == pad.column } }
        return kit.flatMap { kit in kit.sounds.first(where: { $0.id == sound }).flatMap { note in positions.first { $0.note == note.gmNote } } }
    }
    private func play(_ sound: String, position: PadPosition?, volume: Float = 1) {
        guard let audio else { return }; do { try audio.play(soundID: sound, volume: volume); record(sound, hostTime: AudioGetCurrentHostTime()); guard let position else { return }; let key = "\(position.row):\(position.column)"; let flashDuration = Double(tuning.padFlashMilliseconds) / 1_000; DispatchQueue.main.async { [weak self] in self?.active.insert(key); DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) { self?.active.remove(key) } } } catch { status = error.localizedDescription }
    }
    private func slotsBySound() -> [String: Int] {
        var result: [String: Int] = [:]
        for pad in positions { if let sound = name(pad) { result[sound] = pad.row * 4 + pad.column } }
        return result
    }
    private func soundLabels() -> [String: String] {
        Dictionary(uniqueKeysWithValues: kit?.sounds.map { ($0.id, $0.label) } ?? [])
    }
    private func record(_ sound: String, hostTime: UInt64) {
        guard practice != nil else { return }
        let time = AudioClock.milliseconds(from: practiceStartHostTime, to: hostTime)
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.practice else { return }
            let judged = current.register(.init(sound: sound, timeMilliseconds: time))
            guard let offset = judged.offsetMilliseconds else {
                self.judgement = "Toque extra"
                self.practiceScene?.showFeedback(sound: sound, judgement: .extra)
                self.updateLiveStatistics(current.score)
                return
            }
            let direction = offset < 0 ? "adelantado" : offset > 0 ? "atrasado" : "a tiempo"
            self.judgement = "\(judged.judgement.rawValue.capitalized) · \(Int(abs(offset))) ms \(direction)"
            let feedbackSound = judged.expectedNote?.sound ?? sound
            self.practiceScene?.showFeedback(sound: feedbackSound, judgement: judged.judgement)
            self.updateLiveStatistics(current.score)
        }
    }
    private func updateLiveStatistics(_ score: ExerciseScore) {
        liveTotalHits = score.hits.count
        liveWellTimed = score.perfectCount + score.goodCount
        liveRegular = score.regularCount
        liveWrong = score.extraCount
        livePercentage = score.percentage
    }
    private func profileKey() -> CalibrationProfileKey {
        let output = AudioInspector.currentOutput()
        return CalibrationProfileKey(
            inputKind: sourceID == nil ? .keyboard : .midi,
            inputIdentifier: sourceID.map(String.init) ?? "keyboard",
            outputIdentifier: output.deviceUID ?? output.deviceName ?? "default",
            sampleRate: output.sampleRate,
            bufferFrames: Int(output.bufferFrameSize ?? 0)
        )
    }
    private func loadCalibration() {
        let url = applicationSupportURL("calibration.json")
        guard let profiles = try? CalibrationProfileStore.load(from: url), let profile = profiles.first(where: { $0.key == profileKey() }) else { calibrationOffset = 0; calibrationMessage = "Sin calibracion para este perfil."; return }
        calibrationOffset = profile.offsetMilliseconds
        calibrationMessage = String(format: "Compensacion activa: %.0f ms", calibrationOffset)
    }
    private func saveCalibration(offsets: [Double]) {
        do {
            let estimate = try CalibrationEstimator.estimate(rawOffsetsMilliseconds: offsets)
            let profile = CalibrationProfile(key: profileKey(), estimate: estimate)
            let url = applicationSupportURL("calibration.json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var profiles = (try? CalibrationProfileStore.load(from: url)) ?? []
            profiles.removeAll { $0.key == profile.key }; profiles.append(profile)
            try CalibrationProfileStore.save(profiles, to: url)
            calibrationOffset = profile.offsetMilliseconds
            calibrationMessage = String(format: "Calibrado: %.0f ms, dispersion %.0f ms", estimate.offsetMilliseconds, estimate.medianAbsoluteDeviationMilliseconds)
        } catch { calibrationMessage = "Calibracion incompleta: \(error.localizedDescription)" }
    }
    private func recordAttempt(exercise: Exercise, score: ExerciseScore) {
        do {
            try progressStore?.record(PracticeAttempt(exerciseID: exercise.id, timestamp: Date(), bpm: exercise.bpm, score: score.percentage, stars: score.stars, perfect: score.perfectCount, good: score.goodCount, regular: score.regularCount, miss: score.misses.count, extra: score.extraCount, meanOffsetMilliseconds: score.meanOffsetMilliseconds))
            refreshProgress(for: exercise.id)
            refreshRecentAttempts()
            refreshCourseLevels()
            if score.percentage >= 70,
               let next = exercises.first(where: { $0.level == exercise.level + 1 }), isAvailable(next) {
                result += " · Nivel \(next.level) desbloqueado"
            }
        } catch { progress = "No se pudo guardar el intento: \(error.localizedDescription)" }
    }
    func chooseExercise(_ exercise: Exercise) {
        guard isAvailable(exercise) else { return }
        if practice != nil { finishPractice() }
        audio?.stopScheduledSounds(); audio?.stopLoop(); practiceToken = UUID(); previewToken = UUID(); practiceScene = nil; previewScene = nil
        showingResults = false; chosenID = exercise.id; selectedBPM = exercise.bpm; selectedRepeats = exercise.repeats; preview = ""
        savePreferences(); refreshProgress(for: exercise.id)
    }
    func chooseWarmup() {
        var summaries: [String: ExerciseProgress] = [:]
        for exercise in exercises { if let item = try? progressStore?.progress(for: exercise.id) { summaries[exercise.id] = item } }
        guard let recommendation = WarmupPlanner.recommend(exercises: exercises.filter(isAvailable), progress: summaries).first,
              let exercise = exercises.first(where: { $0.id == recommendation.exerciseID }) else { return }
        chooseExercise(exercise); preview = "Calentamiento: \(recommendation.reason)."
    }
    private func refreshProgress(for exerciseID: String) {
        do {
            if let current = try progressStore?.progress(for: exerciseID) { progress = String(format: "Progreso: %d intentos · mejor %.0f %% · ultimo %.0f %%", current.attemptCount, current.bestScore, current.latestScore) }
            scoreHistory = try progressStore?.scores(for: exerciseID) ?? []
        } catch { progress = "No se pudo leer el progreso: \(error.localizedDescription)" }
    }
    func isAvailable(_ exercise: Exercise) -> Bool {
        if exercise.family == "midi" { return true }
        return courseLevels.first(where: { $0.exerciseID == exercise.id })?.status != .locked
    }
    func levelStatus(_ exercise: Exercise) -> String {
        switch courseLevels.first(where: { $0.exerciseID == exercise.id })?.status {
        case .mastered: return "✓"
        case .locked: return "🔒"
        default: return ""
        }
    }
    private func refreshCourseLevels() {
        var summaries: [String: ExerciseProgress] = [:]
        for exercise in exercises { if let item = try? progressStore?.progress(for: exercise.id) { summaries[exercise.id] = item } }
        courseLevels = CourseProgress.states(exercises: exercises, progress: summaries)
        if let chosen = chosen, !isAvailable(chosen), let first = exercises.first(where: isAvailable) {
            chosenID = first.id; selectedBPM = first.bpm; selectedRepeats = first.repeats; preview = ""
            savePreferences(); refreshProgress(for: first.id)
        }
    }
    func savePreferences() {
        let preferences = PracticePreferences(exerciseID: chosenID, bpm: selectedBPM, repeats: selectedRepeats)
        try? PracticePreferencesStore.save(preferences, to: applicationSupportURL("practice-preferences.json"))
    }
    private func loadPreferences() {
        guard let preferences = try? PracticePreferencesStore.load(from: applicationSupportURL("practice-preferences.json")) else { return }
        if let id = preferences.exerciseID, exercises.contains(where: { $0.id == id }) { chosenID = id }
        if let bpm = preferences.bpm { selectedBPM = min(240, max(40, bpm)) }
        if let repeats = preferences.repeats { selectedRepeats = PracticeConfiguration.normalizedRepeats(repeats) }
    }
    func saveTuning() { try? PracticeTuningStore.save(tuning, to: applicationSupportURL("tuning.json")) }
    func resetTuning() { tuning = PracticeTuning(); saveTuning() }
    private func loadTuning() {
        var loaded = (try? PracticeTuningStore.load(from: applicationSupportURL("tuning.json"))) ?? PracticeTuning()
        if !loaded.debugEnabled && loaded.regularWindowMilliseconds < 120 { loaded.regularWindowMilliseconds = 120 }
        tuning = loaded
    }
    func refreshRecentAttempts() {
        do {
            let filter: ProgressFilter
            switch progressFilter {
            case 1: filter = .init(maximumScore: 74.999)
            case 2: filter = .init(minimumScore: 70)
            default: filter = .init()
            }
            recentAttempts = try progressStore?.attempts(filter: filter, limit: 50) ?? []
        } catch { exportMessage = "No se pudo leer el historial: \(error.localizedDescription)" }
    }
    func exportProgress(format: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "xroll-progreso.\(format)"
        if let type = UTType(filenameExtension: format) { panel.allowedContentTypes = [type] }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let filter: ProgressFilter
                switch self.progressFilter {
                case 1: filter = .init(maximumScore: 74.999)
                case 2: filter = .init(minimumScore: 70)
                default: filter = .init()
                }
                if format == "csv" { try self.progressStore?.exportCSV(to: url, filter: filter) }
                else { try self.progressStore?.exportJSON(to: url, filter: filter) }
                self.exportMessage = "Exportado en \(url.lastPathComponent)."
            } catch { self.exportMessage = "No se pudo exportar: \(error.localizedDescription)" }
        }
    }
    private func advice(for score: ExerciseScore) -> String {
        if score.extraCount > 0 { return "Consejo: reduce los toques extra y espera a que la nota llegue a la linea." }
        if let offset = score.meanOffsetMilliseconds, offset < -15 { return "Consejo: vas adelantado; deja caer la nota un poco mas." }
        if let offset = score.meanOffsetMilliseconds, offset > 15 { return "Consejo: vas atrasado; prepara el golpe antes." }
        if score.misses.count > 0 { return "Consejo: empieza mas despacio y usa Escuchar y colocar antes de puntuar." }
        return "Consejo: buen control del pulso. Repite el nivel para consolidarlo."
    }
}

struct Grid: View {
    @ObservedObject var model: Model
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
            ForEach(positions.sorted { $0.row > $1.row || ($0.row == $1.row && $0.column < $1.column) }) { pad in
                let name = model.name(pad); let active = model.active.contains("\(pad.row):\(pad.column)")
                VStack(spacing: 5) { Text(model.displayName(name)).font(.subheadline.bold()).lineLimit(1); Text(model.keyboardLabel(for: pad)).font(.caption.bold()).opacity(0.65) }
                    .frame(maxWidth: .infinity, minHeight: 76).background(active ? Color.white.opacity(0.95) : padColor(for: name)).foregroundColor(active ? .black : (name == nil ? .white.opacity(0.38) : .white)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Color.white : Color.white.opacity(name == nil ? 0.08 : 0.18), lineWidth: active ? 3 : 1))
                    .accessibilityElement(children: .ignore).accessibilityLabel(name.map { "Pad \($0), tecla \(model.keyboardLabel(for: pad))" } ?? "Pad sin asignar, tecla \(model.keyboardLabel(for: pad))")
            }
        }
    }

    private func padColor(for sound: String?) -> Color {
        switch sound {
        case "kick": return Color(red: 0.05, green: 0.53, blue: 0.57)
        case "snare": return Color(red: 0.82, green: 0.28, blue: 0.45)
        case "clap": return Color(red: 0.93, green: 0.48, blue: 0.15)
        case "hihat_closed", "hihat_open": return Color(red: 0.18, green: 0.39, blue: 0.76)
        case "tom_low", "tom_high": return Color(red: 0.18, green: 0.64, blue: 0.50)
        case "crash": return Color(red: 0.49, green: 0.28, blue: 0.77)
        case "ride": return Color(red: 0.67, green: 0.45, blue: 0.16)
        default: return Color.white.opacity(0.07)
        }
    }
}

struct ProgressChart: View {
    let scores: [Double]
    var body: some View {
        Canvas { context, size in
            guard scores.count > 1 else { return }
            var line = Path()
            for (index, score) in scores.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(scores.count - 1)
                let y = size.height * (1 - CGFloat(min(100, max(0, score)) / 100))
                index == 0 ? line.move(to: CGPoint(x: x, y: y)) : line.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(line, with: .color(.accentColor), lineWidth: 2)
        }
        .frame(width: 280, height: 55)
        .overlay(Text(scores.count > 1 ? "Evolucion" : "La grafica aparece desde el segundo intento").font(.caption).foregroundColor(.secondary), alignment: .bottomLeading)
    }
}

private struct Panel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct LegacyStagePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.075))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#if false
private struct ExerciseCard: View {
    @ObservedObject var model: Model
    let exercise: Exercise
    var body: some View {
        let available = model.isAvailable(exercise)
        Button { model.chooseExercise(exercise) } label: {
            HStack(spacing: 10) {
                Text(model.levelStatus(exercise).isEmpty ? "\(exercise.level)" : model.levelStatus(exercise))
                    .font(.headline).frame(width: 28, height: 28).background(available ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.16)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.title).font(.subheadline.bold()).lineLimit(1)
                    Text(available ? "\(exercise.bpm) BPM · \(exercise.repeats) vueltas" : "Supera el nivel anterior").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }.padding(10).background(model.chosenID == exercise.id ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!available)
            .accessibilityLabel("Ejercicio \(exercise.level): \(exercise.title), \(available ? "disponible" : "bloqueado")")
    }
}

private struct PracticeHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.05, blue: 0.10), Color(red: 0.08, green: 0.035, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    HStack(spacing: 10) { Text("xRoll").font(.largeTitle.bold()); Text("FINGER DRUMMING").font(.caption.bold()).foregroundColor(Color.cyan) }
                    Spacer()
                    HStack(spacing: 7) { Circle().fill(model.status.contains("MIDI") ? Color.green : Color.orange).frame(width: 8, height: 8); Text(model.status).font(.caption.bold()).foregroundColor(.white.opacity(0.76)) }
                }.padding(.horizontal, 24).padding(.top, 16)
                HStack(alignment: .top, spacing: 14) {
                    StagePanel {
                        HStack { Text("CURSO").font(.caption.bold()).foregroundColor(.cyan); Spacer(); Button("Calentar") { model.chooseWarmup() }.buttonStyle(.borderless).foregroundColor(.white) }
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(model.exercises, id: \.id) { exercise in
                                    let available = model.isAvailable(exercise)
                                    Button { model.chooseExercise(exercise) } label: {
                                        HStack(spacing: 9) {
                                            Text(model.levelStatus(exercise).isEmpty ? "\(exercise.level)" : model.levelStatus(exercise)).font(.caption.bold()).frame(width: 25, height: 25).background(available ? Color.white.opacity(0.13) : Color.white.opacity(0.05)).clipShape(Circle())
                                            VStack(alignment: .leading, spacing: 2) { Text(exercise.title.replacingOccurrences(of: "Boom bap ", with: "")).font(.caption.bold()).lineLimit(1); Text(available ? "\(exercise.bpm) BPM" : "BLOQUEADO").font(.caption2).foregroundColor(.white.opacity(0.5)) }
                                            Spacer()
                                        }.padding(8).background(model.chosenID == exercise.id ? Color.cyan.opacity(0.18) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 9))
                                    }.buttonStyle(.plain).disabled(!available)
                                }
                            }
                        }
                    }.frame(width: 225)
                    VStack(spacing: 14) {
                        StagePanel {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) { Text("LISTO PARA TOCAR").font(.caption.bold()).foregroundColor(.cyan); Text(model.chosen?.title ?? "Elige un nivel").font(.title2.bold()); Text(model.preview.isEmpty ? "Escucha el patrón o empieza cuando quieras." : model.preview).font(.caption).foregroundColor(.white.opacity(0.58)) }
                                Spacer()
                                Button("▶  Empezar") { model.startPractice() }.buttonStyle(.borderedProminent).tint(.cyan).controlSize(.large)
                            }
                        }
                        StagePanel {
                            HStack { Text("TU CONTROLADOR").font(.caption.bold()).foregroundColor(.cyan); Spacer(); Text("4 × 4").font(.caption).foregroundColor(.white.opacity(0.5)) }
                            Grid(model: model).padding(.top, 12)
                            Text("Bombo, caja y palmada abajo. Charles y crash encima.").font(.caption).foregroundColor(.white.opacity(0.55)).padding(.top, 8)
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        StagePanel {
                            Text("SESIÓN").font(.caption.bold()).foregroundColor(.cyan)
                            Text("\(model.selectedBPM) BPM").font(.title.bold()).padding(.top, 4)
                            Stepper("Tempo", value: $model.selectedBPM, in: 40...240, step: 5).onChange(of: model.selectedBPM) { _ in model.savePreferences() }
                            Divider().overlay(Color.white.opacity(0.16)).padding(.vertical, 5)
                            Text("\(model.selectedRepeats) vueltas").font(.headline)
                            Stepper("Duración", value: Binding(
                                get: { Model.repeatOptions.firstIndex(of: model.selectedRepeats) ?? 0 },
                                set: { model.setRepeats(Model.repeatOptions[$0]) }
                            ), in: 0...(Model.repeatOptions.count - 1))
                            Button("Escuchar y colocar") { model.previewExercise() }.padding(.top, 7)
                            ActionButton("Calibración guiada", prominence: .secondary) { model.startCalibration() }
                        }
                        StagePanel {
                            Text("ÚLTIMO INTENTO").font(.caption.bold()).foregroundColor(.cyan)
                            Text(model.result.isEmpty ? "Sin intentos todavía" : model.result).font(.caption).padding(.top, 5)
                            Text(model.advice).font(.caption2).foregroundColor(.white.opacity(0.58)).padding(.top, 4)
                            ProgressChart(scores: model.scoreHistory).padding(.top, 6)
                        }
                    }.frame(width: 245)
                }.padding(.horizontal, 20)
                HStack { Text(model.recovery).font(.caption).foregroundColor(.white.opacity(0.55)); Spacer(); Text(model.calibrationMessage).font(.caption).foregroundColor(.white.opacity(0.55)) }.padding(.horizontal, 24).padding(.bottom, 12)
            }.foregroundColor(.white)
        }
    }
}

#endif

private struct PracticePreview: View {
    @ObservedObject var model: Model
    let scene: PracticeScene

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.04, blue: 0.09), Color(red: 0.075, green: 0.025, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DEMOSTRACIÓN GUIADA").font(.caption.bold()).foregroundColor(.cyan)
                        Text(model.chosen?.title ?? "Práctica").font(.title2.bold())
                        Text("Observa una vuelta: aquí no se puntúa ningún golpe.").font(.caption).foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    ActionButton("Volver", prominence: .secondary) { model.stopPreview() }
                    ActionButton("Empezar a tocar", prominence: .primary) { model.stopPreview(); model.startPractice() }
                }
                SpriteView(scene: scene)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15), lineWidth: 1))
                StagePanel {
                    Text("CÓMO USARLO").font(.caption.bold()).foregroundColor(.cyan)
                    Text("Mira qué carril llega a la línea y escucha cómo encajan los golpes. Cuando lo tengas claro, pulsa Empezar a tocar.")
                        .font(.subheadline).foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(24).foregroundColor(.white)
        }
    }
}

private struct PracticeRun: View {
    @ObservedObject var model: Model
    let scene: PracticeScene
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.04, blue: 0.09), Color(red: 0.075, green: 0.025, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        AppMark(size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EN PRÁCTICA").font(.caption.bold()).foregroundColor(.cyan)
                            Text(model.chosen?.title ?? "Práctica").font(.title2.bold()).foregroundColor(.white)
                        }
                    }
                    Spacer()
                    Text("\(model.selectedBPM) BPM · \(model.selectedRepeats) vueltas").font(.subheadline.bold()).foregroundColor(.white.opacity(0.75))
                    ActionButton("↻ Reiniciar", prominence: .primary) { model.restartPractice() }
                    ActionButton("Terminar", prominence: .secondary) { model.finishPractice() }
                }
                HStack(alignment: .top, spacing: 16) {
                    ZStack(alignment: .bottom) {
                        SpriteView(scene: scene).clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(spacing: 3) {
                            Text(model.judgement).font(.title3.bold())
                            Text("Golpea cuando la nota llegue a la línea").font(.caption).foregroundColor(.white.opacity(0.62))
                        }.frame(maxWidth: .infinity).padding(.vertical, 13).background(Color.black.opacity(0.66))
                    }.overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    VStack(spacing: 12) {
                        StagePanel {
                            Text("CONTROLES").font(.caption.bold()).foregroundColor(.cyan)
                            Toggle("Metrónomo", isOn: $model.metronomeEnabled).toggleStyle(.switch)
                            Toggle("Loop acompañamiento", isOn: Binding(get: { model.loopEnabled }, set: { model.setLoopEnabled($0) })).toggleStyle(.switch)
                            Divider().overlay(Color.white.opacity(0.15))
                            Stepper("Tempo: \(model.selectedBPM) BPM", value: $model.selectedBPM, in: 40...240, step: 5)
                            Stepper("Duración: \(model.selectedRepeats) vueltas", value: Binding(
                                get: { Model.repeatOptions.firstIndex(of: model.selectedRepeats) ?? 0 },
                                set: { model.setRepeats(Model.repeatOptions[$0]) }
                            ), in: 0...(Model.repeatOptions.count - 1))
                            Text("Tempo, duración y metrónomo se aplican al reiniciar.").font(.caption2).foregroundColor(.white.opacity(0.58))
                        }
                        StagePanel {
                            Text("EN TIEMPO REAL").font(.caption.bold()).foregroundColor(.cyan)
                            Text("\(Int(model.livePercentage.rounded())) %").font(.largeTitle.bold()).foregroundColor(model.livePercentage >= 70 ? .green : model.livePercentage >= 50 ? .yellow : .white)
                            HStack(spacing: 8) {
                                PracticeLiveStat("Golpes", value: model.liveTotalHits, color: .white)
                                PracticeLiveStat("Bien", value: model.liveWellTimed, color: .green)
                                PracticeLiveStat("Reg.", value: model.liveRegular, color: .yellow)
                                PracticeLiveStat("Mal", value: model.liveWrong, color: .red)
                            }
                        }
                    }.frame(width: 260)
                }.frame(maxHeight: .infinity)
            }.padding(24)
        }.foregroundColor(.white)
    }
}

private struct PracticeLiveStat: View {
    let title: String; let value: Int; let color: Color
    init(_ title: String, value: Int, color: Color) { self.title = title; self.value = value; self.color = color }
    var body: some View {
        VStack(spacing: 1) { Text("\(value)").font(.headline).foregroundColor(color); Text(title).font(.caption2).foregroundColor(.white.opacity(0.6)) }
            .frame(maxWidth: .infinity)
    }
}

private struct ProgressHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
        Color(red: 0.035, green: 0.05, blue: 0.10).ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
            Text("Progreso").font(.largeTitle.bold())
            Text("Revisa tus intentos y guarda una copia cuando quieras.").foregroundColor(.white.opacity(0.65))
            Picker("Mostrar", selection: $model.progressFilter) { Text("Todos").tag(0); Text("Para consolidar").tag(1); Text("70 % o más").tag(2) }.pickerStyle(.segmented).frame(width: 460).onChange(of: model.progressFilter) { _ in model.refreshRecentAttempts() }
            HStack(spacing: 10) {
                ActionButton("Exportar CSV") { model.exportProgress(format: "csv") }
                ActionButton("Exportar JSON") { model.exportProgress(format: "json") }
            }
            Text(model.exportMessage).font(.caption).foregroundColor(.white.opacity(0.65))
            StagePanel {
                if model.recentAttempts.isEmpty { Text("Aquí aparecerán tus intentos al terminar una práctica.").foregroundColor(.white.opacity(0.65)) }
                else { ForEach(Array(model.recentAttempts.prefix(12).enumerated()), id: \.offset) { _, attempt in HStack { Text(attempt.exerciseID).frame(width: 180, alignment: .leading); Text("\(attempt.bpm) BPM").frame(width: 80, alignment: .leading); Text(String(format: "%.0f %%", attempt.score)).frame(width: 70, alignment: .leading); Text("★ \(attempt.stars)") }.padding(.vertical, 3) } }
            }
            Spacer()
        }.foregroundColor(.white).padding(28).frame(minWidth: 720, minHeight: 520, alignment: .topLeading)
        }
    }
}

private struct MappingHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
        Color(red: 0.035, green: 0.05, blue: 0.10).ignoresSafeArea()
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Configura tus pads").font(.largeTitle.bold())
                Text("Asigna los sonidos que uses siguiendo la misma posición que ves en tu controlador.").foregroundColor(.white.opacity(0.65))
                StagePanel {
                    Text("1. Elige el M‑Vave").font(.headline)
                    Picker("Entrada MIDI", selection: $model.sourceID) { Text("Sin entrada").tag(MIDIUniqueID?.none); ForEach(model.sources, id: \.uniqueID) { Text($0.name).tag(Optional($0.uniqueID)) } }.onChange(of: model.sourceID) { _ in model.selectSource() }
                    HStack {
                        Text(model.sources.isEmpty ? "Conecta un controlador MIDI por USB." : "Los dispositivos conectados se detectan automáticamente.")
                            .font(.caption).foregroundColor(.white.opacity(0.65))
                        Spacer()
                        ActionButton("↻ Buscar MIDI", prominence: .secondary) { model.refreshMIDIDevices() }
                    }
                    Text("2. Pulsa empezar y golpea el pad que te indique xRoll.").font(.headline).padding(.top, 8)
                    ActionButton(model.mapping ? "Cancelar asignación" : "Empezar asignación", prominence: model.mapping ? .secondary : .primary) { model.mapping ? model.cancelMapping() : model.startMapping() }
                        .disabled(model.sourceID == nil)
                        .padding(.top, 4)
                    if model.mapping { Button("Omitir este sonido") { model.skipMappingSound() }.buttonStyle(.borderless).foregroundColor(.cyan) }
                    Text(model.mapMessage.isEmpty ? "La asignación se guarda al terminar. Puedes omitir sonidos que no tenga tu controlador." : model.mapMessage).font(.caption).foregroundColor(.white.opacity(0.65)).padding(.top, 5)
                }
                StagePanel {
                    Text("3. Teclado del Mac").font(.headline)
                    Text("Puedes practicar sin controlador. Pulsa una tecla distinta para cada sonido que quieras reasignar.").font(.caption).foregroundColor(.white.opacity(0.65))
                    ActionButton(model.keyboardMapping ? "Cancelar teclado" : "Mapear teclado", prominence: model.keyboardMapping ? .secondary : .primary) { model.keyboardMapping ? model.cancelKeyboardMapping() : model.startKeyboardMapping() }
                    Text(model.keyboardMapMessage.isEmpty ? "Sin asignación personalizada: se usa la cuadrícula Z–V, A–F, Q–R y 1–4." : model.keyboardMapMessage).font(.caption).foregroundColor(.white.opacity(0.65))
                }
                StagePanel { Text("Orden recomendado").font(.headline); Text("Abajo: bombo · caja · palmada\nCentro: tom grave · charles\nArriba: tom agudo · crash · ride").font(.subheadline).padding(.top, 4) }
            }.frame(width: 390)
            StagePanel { VStack(alignment: .leading) { Text("Vista del controlador").font(.headline); Text("La esquina inferior izquierda es el bombo.").font(.caption).foregroundColor(.white.opacity(0.65)); Grid(model: model).frame(width: 390).padding(.top, 10) } }
        }.foregroundColor(.white).padding(28).frame(minWidth: 820, minHeight: 560, alignment: .topLeading)
        }
    }
}

private struct SettingsHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.05, blue: 0.10).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        AppMark(size: 52)
                        VStack(alignment: .leading) {
                            Text("Ajustes").font(.largeTitle.bold())
                            Text("Preferencias de práctica y afinado técnico.").foregroundColor(.white.opacity(0.65))
                        }
                    }
                    StagePanel {
                        Text("Práctica").font(.headline)
                        Text("BPM y vueltas se guardan desde la pantalla de práctica.").font(.caption).foregroundColor(.white.opacity(0.65))
                        HStack {
                            Text("Tono del metrónomo")
                            Slider(value: $model.tuning.metronomePitchSemitones, in: -12...24, step: 1)
                            Text(String(format: "%+.0f semitonos", model.tuning.metronomePitchSemitones)).frame(width: 96, alignment: .trailing)
                        }
                        HStack {
                            Text("Volumen metrónomo")
                            Slider(value: $model.tuning.countInVolume, in: 0...1)
                            Text("\(Int(model.tuning.countInVolume * 100)) %").frame(width: 42, alignment: .trailing)
                        }
                        HStack {
                            Text("Volumen loop")
                            Slider(value: $model.tuning.loopVolume, in: 0...1)
                            Text("\(Int(model.tuning.loopVolume * 100)) %").frame(width: 42, alignment: .trailing)
                        }
                        Text("Se aplica al iniciar o reiniciar el ejercicio.").font(.caption2).foregroundColor(.white.opacity(0.58))
                    }.onChange(of: model.tuning) { _ in model.saveTuning() }
                    StagePanel {
                        HStack {
                            Text("Salida de audio").font(.headline)
                            Spacer()
                            ActionButton("↻ Refrescar", prominence: .secondary) { model.refreshAudioOutputs() }
                        }
                        Picker("Salida", selection: $model.selectedAudioOutputUID) {
                            ForEach(model.audioOutputs) { output in
                                Text(output.name).tag(Optional(output.uid))
                            }
                        }.onChange(of: model.selectedAudioOutputUID) { _ in model.selectAudioOutput() }
                        Text("Conecta una interfaz y pulsa Refrescar para usarla en xRoll.").font(.caption2).foregroundColor(.white.opacity(0.58))
                    }
                    StagePanel {
                        HStack {
                            Text("Controlador MIDI").font(.headline)
                            Spacer()
                            ActionButton("↻ Refrescar", prominence: .secondary) { model.refreshMIDIDevices() }
                        }
                        Picker("Entrada", selection: $model.sourceID) {
                            Text("Sin entrada MIDI").tag(MIDIUniqueID?.none)
                            ForEach(model.sources, id: \.uniqueID) { source in
                                Text(source.name).tag(Optional(source.uniqueID))
                            }
                        }.onChange(of: model.sourceID) { _ in model.selectSource() }
                        Text("xRoll escucha únicamente el controlador elegido aquí.").font(.caption2).foregroundColor(.white.opacity(0.58))
                    }
                    StagePanel {
                        Text("Ejercicios MIDI comunitarios").font(.headline)
                        Text("Importa un .mid o .midi: se valida con el kit actual y queda guardado localmente.").font(.caption).foregroundColor(.white.opacity(0.65))
                        ActionButton("Importar ejercicio MIDI", prominence: .secondary) { model.showingExerciseImporter = true }.padding(.top, 5)
                        if !model.exerciseImportMessage.isEmpty { Text(model.exerciseImportMessage).font(.caption2).foregroundColor(.white.opacity(0.58)).padding(.top, 3) }
                    }
                    StagePanel {
                        Toggle("Activar Debug", isOn: $model.tuning.debugEnabled).font(.headline)
                        Text("Se guardan localmente y afectan a la siguiente práctica.").font(.caption).foregroundColor(.white.opacity(0.65))
                        if model.tuning.debugEnabled {
                            Divider().overlay(Color.white.opacity(0.16))
                            Stepper("Anticipación: \(model.tuning.anticipationBars) compases", value: $model.tuning.anticipationBars, in: 1...4)
                            Stepper("Perfecto: \(Int(model.tuning.perfectWindowMilliseconds)) ms", value: $model.tuning.perfectWindowMilliseconds, in: 5...100, step: 1)
                            Stepper("Bien: \(Int(model.tuning.goodWindowMilliseconds)) ms", value: $model.tuning.goodWindowMilliseconds, in: 5...150, step: 1)
                            Stepper("Regular: \(Int(model.tuning.regularWindowMilliseconds)) ms", value: $model.tuning.regularWindowMilliseconds, in: 5...250, step: 1)
                            Stepper("Compensación manual: \(Int(model.tuning.manualTimingOffsetMilliseconds)) ms", value: $model.tuning.manualTimingOffsetMilliseconds, in: -200...200, step: 1)
                            HStack { Text("Volumen de cuenta"); Slider(value: $model.tuning.countInVolume, in: 0...1); Text("\(Int(model.tuning.countInVolume * 100)) %").frame(width: 42, alignment: .trailing) }
                            Stepper("Destello de pad: \(model.tuning.padFlashMilliseconds) ms", value: $model.tuning.padFlashMilliseconds, in: 30...500, step: 10)
                            ActionButton("Restablecer valores de Debug", prominence: .secondary) { model.resetTuning() }
                        }
                    }.onChange(of: model.tuning) { _ in model.saveTuning() }
                    Spacer()
                }.foregroundColor(.white).padding(30).frame(maxWidth: 760, alignment: .leading)
            }
        }.fileImporter(isPresented: $model.showingExerciseImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { model.importCommunityExercise(from: url) }
            case .failure(let error): model.exerciseImportMessage = "No se pudo abrir el archivo: \(error.localizedDescription)"
            }
        }
    }
}

private struct ContentView: View {
    @StateObject private var model = Model()
    @State private var section = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                AppMark(size: 26)
                Text("xRoll").font(.headline.bold()).padding(.trailing, 12)
                navigationButton("Practicar", index: 0)
                navigationButton("Progreso", index: 1)
                navigationButton("Mapear pads", index: 2)
                navigationButton("Ajustes", index: 3)
                Spacer()
            }.foregroundColor(.white).padding(.horizontal, 18).padding(.vertical, 9).background(Color(red: 0.025, green: 0.035, blue: 0.075))
            Divider().overlay(Color.white.opacity(0.12))
            Group {
                if section == 0 { if let scene = model.previewScene { PracticePreview(model: model, scene: scene) } else if let scene = model.practiceScene { PracticeRun(model: model, scene: scene) } else if model.showingResults { ResultsHome(model: model) } else { PracticeHome(model: model) } }
                else if section == 1 { ProgressHome(model: model) }
                else if section == 2 { MappingHome(model: model) }
                else { SettingsHome(model: model) }
            }
        }.background(WindowResizeSupport()).frame(minWidth: 960, minHeight: 650)
    }

    private func navigationButton(_ title: String, index: Int) -> some View {
        Button(title) { section = index }
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6)
            .background(section == index ? Color.accentColor.opacity(0.18) : Color.clear)
            .foregroundColor(.white.opacity(section == index ? 1 : 0.72)).clipShape(Capsule())
    }
}

private struct WindowResizeSupport: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 960, height: 650)
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }
}

private struct XRollPadsApp: App { var body: some Scene { WindowGroup("xRoll") { ContentView() } } }

XRollPadsApp.main()
