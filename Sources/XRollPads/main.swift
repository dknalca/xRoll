import AppKit
import AudioToolbox
import Combine
import CoreMIDI
import Foundation
import SwiftUI
import SpriteKit
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

private final class Model: ObservableObject {
    @Published var status = "Cargando…"; @Published var active = Set<String>()
    @Published var exercises = [Exercise](); @Published var chosenID = ""; @Published var preview = ""
    @Published var sources = [MIDIEndpointDescription](); @Published var sourceID: MIDIUniqueID?
    @Published var mapping = false; @Published var mapMessage = ""
    @Published var practiceScene: PracticeScene?; @Published var judgement = ""; @Published var result = ""
    @Published var progress = ""; @Published var scoreHistory = [Double](); @Published var advice = ""; @Published var calibrationMessage = "Sin calibracion para este perfil."
    @Published var selectedBPM = 80; @Published var selectedRepeats = 4; @Published var recovery = ""; @Published var insights = ""
    private var kit: KitManifest?; private var audio: SampleAudioEngine?; private var gm: KitNoteRouter?
    private var custom: PadMap?; private var customRouter: PadMapRouter?; private var input: MIDIInputSession?
    private var builder: PadMapBuilder?; private var monitor: Any?
    private var practice: PracticeSession?; private var practiceStartHostTime: UInt64 = 0; private var practiceToken = UUID()
    private var progressStore: ProgressStore?; private var calibrationOffset: Double = 0; private var calibrating = false

    init() {
        load()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard !event.isARepeat, let key = event.charactersIgnoringModifiers?.uppercased(), let pad = positions.first(where: { $0.key == key }) else { return event }
            self?.trigger(pad); return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    var chosen: Exercise? { exercises.first { $0.id == chosenID } }
    var configuredExercise: Exercise? { chosen.map { PracticeConfiguration(exercise: $0, bpm: selectedBPM, repeats: selectedRepeats).applying(to: $0) } }
    func name(_ pad: PadPosition) -> String? {
        custom?.pads.first(where: { $0.row == pad.row && $0.column == pad.column })?.sound ?? kit?.sounds.first(where: { $0.gmNote == pad.note })?.id
    }
    func selectSource() { mapping = false; builder = nil; connect() }
    func startMapping() {
        guard let source = sources.first(where: { $0.uniqueID == sourceID }) else { mapMessage = "Elige una entrada MIDI."; return }
        builder = PadMapBuilder(device: source.name, deviceUID: Int(source.uniqueID ?? 0), created: ISO8601DateFormatter().string(from: Date()))
        mapping = true; mapMessage = "Golpea el pad para bombo."
    }
    func cancelMapping() { mapping = false; builder = nil; mapMessage = "Asignacion cancelada." }
    func previewExercise() {
        guard let exercise = configuredExercise, let audio else { return }
        do {
            let timeline = ExerciseTimeline(exercise: exercise); let base = AudioClock.hostTime(afterMilliseconds: 500)
            for note in timeline.notes { try audio.schedule(soundID: note.sound, atHostTime: AudioClock.hostTime(afterMilliseconds: note.timeMilliseconds, from: base)) }
            preview = "Reproduciendo \(exercise.title), sin puntuacion."
        } catch { preview = error.localizedDescription }
    }
    func startPractice() { beginPractice(calibration: false) }
    func startCalibration() { beginPractice(calibration: true) }
    private func beginPractice(calibration: Bool) {
        guard let exercise = configuredExercise else { return }
        calibrating = calibration
        let session = PracticeSession(exercise: exercise, calibrationOffsetMilliseconds: calibration ? 0 : calibrationOffset)
        let anticipation = session.timeline.patternDurationMilliseconds * 2
        let now = AudioGetCurrentHostTime()
        let start = AudioClock.hostTime(afterMilliseconds: anticipation, from: now)
        practice = session; practiceStartHostTime = start; judgement = calibration ? "Calibracion: sigue las notas durante todas las vueltas." : "Preparado: dos compases de anticipacion."; result = ""
        practiceScene = PracticeScene(timeline: session.timeline, startHostTime: start, anticipationMilliseconds: anticipation, slotBySound: slotsBySound())
        let beat = 60_000.0 / Double(exercise.bpm)
        let countInStart = anticipation - session.timeline.patternDurationMilliseconds
        if countInStart >= 0 {
            for beatIndex in 0..<4 {
                try? audio?.schedule(soundID: "hihat_closed", atHostTime: AudioClock.hostTime(afterMilliseconds: countInStart + Double(beatIndex) * beat, from: now))
            }
        }
        let token = UUID(); practiceToken = token
        let duration = anticipation + session.timeline.patternDurationMilliseconds * Double(exercise.repeats) + 150
        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 1_000) { [weak self] in
            guard self?.practiceToken == token else { return }; self?.finishPractice()
        }
    }
    func finishPractice() {
        guard let currentPractice = practice, let exercise = configuredExercise else { return }
        let score = currentPractice.score
        let offset = score.meanOffsetMilliseconds.map { String(format: " · media %.0f ms", $0) } ?? ""
        result = String(format: "Resultado: %.0f %% · %d estrellas · P%d B%d R%d · %d fallos · %d extras%@", score.percentage, score.stars, score.perfectCount, score.goodCount, score.regularCount, score.misses.count, score.extraCount, offset)
        advice = advice(for: score)
        insights = PracticeInsights(score: score).timingLabel
        if calibrating {
            saveCalibration(offsets: score.hits.compactMap(\.offsetMilliseconds))
        } else {
            recordAttempt(exercise: exercise, score: score)
        }
        self.practice = nil; practiceScene = nil; practiceToken = UUID()
        calibrating = false
    }
    private func load() {
        let workingRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let bundledRoot = Bundle.main.resourceURL?.appendingPathComponent("ProjectData", isDirectory: true)
        let root = bundledRoot.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Resources/Kits/hiphop_basic/kit.json").path) ? $0 : nil } ?? workingRoot
        let kitDir = root.appendingPathComponent("Resources/Kits/hiphop_basic")
        do {
            let catalog = ResourceCatalog(); let loaded = try catalog.loadKit(at: kitDir.appendingPathComponent("kit.json"))
            let newAudio = SampleAudioEngine(); try newAudio.load(kit: loaded, from: kitDir); try newAudio.start()
            kit = loaded; audio = newAudio; gm = KitNoteRouter(kit: loaded)
            progressStore = try ProgressStore(url: applicationSupportURL("progress.sqlite"))
            exercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: loaded); chosenID = exercises.first?.id ?? ""
            selectedBPM = exercises.first?.bpm ?? 80; selectedRepeats = exercises.first?.repeats ?? 4
            sources = MIDIInspector.sources().filter { $0.uniqueID != nil }
            sourceID = sources.first(where: { $0.name.localizedCaseInsensitiveContains("Pocket-Private") })?.uniqueID ?? sources.first?.uniqueID
            connect()
            recovery = RecoveryAdvisor.assess(missingSamples: catalog.missingSampleFiles(for: loaded, in: kitDir), hasMIDIInput: !sources.isEmpty).message
        } catch { status = "No se pudo iniciar: \(error.localizedDescription)"; recovery = RecoveryAdvisor.assess(missingSamples: [], hasMIDIInput: false, hasAudio: false).message }
    }
    private func connect() {
        input = nil
        guard let sourceID, let endpoint = MIDIInspector.source(withUniqueID: sourceID) else { status = "Teclado listo"; return }
        do {
            let session = try MIDIInputSession { [weak self] event in self?.receive(event) }; try session.connect(source: endpoint); input = session
            loadMap(sourceID); status = "Teclado y MIDI listos"
            loadCalibration()
        } catch { status = error.localizedDescription }
    }
    private func receive(_ event: MIDINoteOn) {
        if mapping { DispatchQueue.main.async { [weak self] in self?.capture(event) }; return }
        guard let sound = customRouter?.soundID(for: event) ?? gm?.soundID(for: event) else { return }
        play(sound, position: position(sound))
    }
    private func capture(_ event: MIDINoteOn) {
        guard var builder else { return }; let result = builder.assign(event); self.builder = builder
        switch result {
        case .assigned(let sound, let remaining): mapMessage = "Asignado \(sound). Quedan \(remaining). \(nextPrompt())"
        case .duplicate(let note, let channel, let sound): mapMessage = "Nota \(note), canal \(channel), ya asignada a \(sound)."
        case .complete(let map): save(map)
        }
    }
    private func nextPrompt() -> String { builder?.nextStep.map { "Golpea el pad para \($0.sound)." } ?? "" }
    private func mapURL(_ id: Int) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("xRoll/padmaps/\(id).padmap") }
    private func applicationSupportURL(_ file: String) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("xRoll/\(file)") }
    private func loadMap(_ id: MIDIUniqueID) {
        guard let kit else { return }; let url = mapURL(Int(id)); guard FileManager.default.fileExists(atPath: url.path) else { custom = nil; customRouter = nil; return }
        do { let map = try PadMapStore.load(at: url, availableSounds: Set(kit.sounds.map(\.id))); custom = map; customRouter = PadMapRouter(padMap: map) } catch { status = "Mapa invalido: \(error.localizedDescription)" }
    }
    private func save(_ map: PadMap) {
        guard let kit else { return }
        do { let url = mapURL(map.deviceUID); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try PadMapStore.save(map, to: url, availableSounds: Set(kit.sounds.map(\.id))); custom = map; customRouter = PadMapRouter(padMap: map); mapping = false; builder = nil; mapMessage = "Mapa guardado." } catch { mapMessage = error.localizedDescription }
    }
    private func trigger(_ pad: PadPosition) { if let sound = name(pad) { play(sound, position: pad) } }
    private func position(_ sound: String) -> PadPosition? {
        if let pad = custom?.pads.first(where: { $0.sound == sound }) { return positions.first { $0.row == pad.row && $0.column == pad.column } }
        return kit.flatMap { kit in kit.sounds.first(where: { $0.id == sound }).flatMap { note in positions.first { $0.note == note.gmNote } } }
    }
    private func play(_ sound: String, position: PadPosition?) {
        guard let audio else { return }; do { try audio.play(soundID: sound); record(sound, hostTime: AudioGetCurrentHostTime()); guard let position else { return }; let key = "\(position.row):\(position.column)"; DispatchQueue.main.async { [weak self] in self?.active.insert(key); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.active.remove(key) } } } catch { status = error.localizedDescription }
    }
    private func slotsBySound() -> [String: Int] {
        var result: [String: Int] = [:]
        for pad in positions { if let sound = name(pad) { result[sound] = pad.row * 4 + pad.column } }
        return result
    }
    private func record(_ sound: String, hostTime: UInt64) {
        guard practice != nil else { return }
        let time = AudioClock.milliseconds(from: practiceStartHostTime, to: hostTime)
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.practice else { return }
            let judged = current.register(.init(sound: sound, timeMilliseconds: time))
            guard let offset = judged.offsetMilliseconds else { self.judgement = "Toque extra"; return }
            let direction = offset < 0 ? "adelantado" : offset > 0 ? "atrasado" : "a tiempo"
            self.judgement = "\(judged.judgement.rawValue.capitalized) · \(Int(abs(offset))) ms \(direction)"
        }
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
        } catch { progress = "No se pudo guardar el intento: \(error.localizedDescription)" }
    }
    func chooseExercise(_ exercise: Exercise) { chosenID = exercise.id; selectedBPM = exercise.bpm; selectedRepeats = exercise.repeats; refreshProgress(for: exercise.id) }
    func chooseWarmup() {
        var summaries: [String: ExerciseProgress] = [:]
        for exercise in exercises { if let item = try? progressStore?.progress(for: exercise.id) { summaries[exercise.id] = item } }
        guard let recommendation = WarmupPlanner.recommend(exercises: exercises, progress: summaries).first,
              let exercise = exercises.first(where: { $0.id == recommendation.exerciseID }) else { return }
        chooseExercise(exercise); preview = "Calentamiento: \(recommendation.reason)."
    }
    private func refreshProgress(for exerciseID: String) {
        do {
            if let current = try progressStore?.progress(for: exerciseID) { progress = String(format: "Progreso: %d intentos · mejor %.0f %% · ultimo %.0f %%", current.attemptCount, current.bestScore, current.latestScore) }
            scoreHistory = try progressStore?.scores(for: exerciseID) ?? []
        } catch { progress = "No se pudo leer el progreso: \(error.localizedDescription)" }
    }
    private func advice(for score: ExerciseScore) -> String {
        if score.extraCount > 0 { return "Consejo: reduce los toques extra y espera a que la nota llegue a la linea." }
        if let offset = score.meanOffsetMilliseconds, offset < -15 { return "Consejo: vas adelantado; deja caer la nota un poco mas." }
        if let offset = score.meanOffsetMilliseconds, offset > 15 { return "Consejo: vas atrasado; prepara el golpe antes." }
        if score.misses.count > 0 { return "Consejo: empieza mas despacio y usa Escuchar y colocar antes de puntuar." }
        return "Consejo: buen control del pulso. Repite el nivel para consolidarlo."
    }
}

private struct Grid: View {
    @ObservedObject var model: Model
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
            ForEach(positions.sorted { $0.row > $1.row || ($0.row == $1.row && $0.column < $1.column) }) { pad in
                let name = model.name(pad); let active = model.active.contains("\(pad.row):\(pad.column)")
                VStack { Text(name ?? "—").font(.headline); Text(pad.key).font(.caption.bold()) }
                    .frame(maxWidth: .infinity, minHeight: 70).background(active ? Color.orange : (name == nil ? Color.gray.opacity(0.2) : Color.blue.opacity(0.75))).foregroundColor(name == nil ? .secondary : .white).clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityElement(children: .ignore).accessibilityLabel(name.map { "Pad \($0), tecla \(pad.key)" } ?? "Pad sin asignar, tecla \(pad.key)")
            }
        }
    }
}

private struct ProgressChart: View {
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

private struct ContentView: View {
    @StateObject private var model = Model()
    var body: some View {
        TabView {
            VStack {
            if let scene = model.practiceScene {
                VStack(spacing: 14) {
                    Text(model.chosen?.title ?? "Practica").font(.title.bold())
                    SpriteView(scene: scene).frame(minWidth: 700, minHeight: 410).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(model.judgement).font(.title3.bold())
                    Button("Terminar") { model.finishPractice() }
                }.padding(24)
            } else {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        Text("xRoll").font(.largeTitle.bold())
                        Text(model.status).foregroundColor(.secondary)
                        Divider()
                        Text("Ejercicios").font(.headline)
                    }
                    ForEach(model.exercises, id: \.id) { exercise in Button("\(exercise.level). \(exercise.title) — \(exercise.bpm) BPM") { model.chooseExercise(exercise) }.buttonStyle(.plain).padding(5).background(model.chosenID == exercise.id ? Color.accentColor.opacity(0.16) : .clear).clipShape(RoundedRectangle(cornerRadius: 5)).accessibilityLabel("Ejercicio \(exercise.level): \(exercise.title), \(exercise.bpm) pulsos por minuto") }
                    Button("Calentamiento recomendado") { model.chooseWarmup() }.padding(.top, 6)
                    HStack {
                        Stepper("BPM \(model.selectedBPM)", value: $model.selectedBPM, in: 40...240, step: 5)
                        Stepper("Vueltas \(model.selectedRepeats)", value: $model.selectedRepeats, in: 1...16)
                    }.font(.footnote).frame(width: 300, alignment: .leading)
                    Button("Escuchar y colocar") { model.previewExercise() }.padding(.top, 10)
                    Button("Empezar practica") { model.startPractice() }.padding(.top, 4)
                    Button("Calibracion guiada") { model.startCalibration() }.padding(.top, 4)
                    VStack(alignment: .leading) {
                        Text(model.preview).font(.footnote).foregroundColor(.secondary).frame(width: 290, alignment: .leading)
                        Text(model.result).font(.footnote).frame(width: 290, alignment: .leading)
                        Text(model.progress).font(.footnote).frame(width: 290, alignment: .leading)
                        Text(model.advice).font(.footnote).foregroundColor(.secondary).frame(width: 290, alignment: .leading)
                        Text(model.calibrationMessage).font(.footnote).foregroundColor(.secondary).frame(width: 290, alignment: .leading)
                        Text(model.insights).font(.footnote).foregroundColor(.secondary).frame(width: 290, alignment: .leading)
                        Text(model.recovery).font(.footnote).foregroundColor(.secondary).frame(width: 290, alignment: .leading)
                    }
                    ProgressChart(scores: model.scoreHistory)
                }.frame(width: 320, alignment: .leading)
                VStack { Text("Pads").font(.title2.bold()); Grid(model: model).frame(width: 390); Text("1–4 / Q–R / A–F / Z–V").font(.footnote).foregroundColor(.secondary) }
            }.padding(30)
            }
            }.tabItem { Text("Practicar") }
            VStack(alignment: .leading, spacing: 18) {
                Text("Asignar pads").font(.largeTitle.bold()); Text("El mapa se guarda para este controlador y la rejilla visual adopta sus posiciones.").foregroundColor(.secondary)
                Picker("Entrada MIDI", selection: $model.sourceID) { Text("Sin entrada").tag(MIDIUniqueID?.none); ForEach(model.sources, id: \.uniqueID) { Text($0.name).tag(Optional($0.uniqueID)) } }.frame(width: 440).onChange(of: model.sourceID) { _ in model.selectSource() }
                Button(model.mapping ? "Cancelar" : "Empezar asignacion") { model.mapping ? model.cancelMapping() : model.startMapping() }.disabled(model.sourceID == nil)
                Text(model.mapMessage).foregroundColor(.secondary); Divider(); Grid(model: model).frame(width: 500)
            }.padding(30).tabItem { Text("Mapear pads") }
        }.frame(minWidth: 760, minHeight: 560)
    }
}

private struct XRollPadsApp: App { var body: some Scene { WindowGroup("xRoll") { ContentView() } } }

XRollPadsApp.main()
