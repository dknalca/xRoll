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
    private static let keyboardMappingSounds = ["kick", "rim", "snare", "clap", "tom_low", "hihat_closed", "hihat_open", "tom_high", "crash", "ride"]
    @Published var status = "Cargando…"; @Published var active = Set<String>()
    @Published var exercises = [Exercise](); @Published var chosenID = ""; @Published var preview = ""
    @Published var sources = [MIDIEndpointDescription](); @Published var sourceID: MIDIUniqueID?
    @Published var bluetoothMIDIDevices = [BluetoothMIDIDevice](); @Published var bluetoothMIDIStatus = "Bluetooth MIDI aún no preparado."
    @Published var audioOutputs = [AudioOutputDeviceDescription](); @Published var selectedAudioOutputUID: String?
    @Published var mapping = false; @Published var mapMessage = ""
    @Published var selectedLayoutPreset: PadLayoutPreset = .core
    @Published var showingExerciseImporter = false; @Published var exerciseImportMessage = ""
    @Published var keyboardMapping = false; @Published var keyboardMapMessage = ""; @Published private(set) var keyboardKeys = [String: String]()
    @Published var practiceScene: PracticeScene?; @Published var result = ""
    @Published var practiceVisualID = UUID()
    @Published private(set) var isPracticePaused = false
    @Published var previewScene: PracticeScene?
    @Published var progress = ""; @Published var scoreHistory = [Double](); @Published var advice = ""; @Published var calibrationMessage = "Sin calibracion para este perfil."
    @Published var ghostCoachMessage = ""
    @Published var selectedBPM = 80; @Published var selectedRepeats = 8; @Published var recovery = ""; @Published var insights = ""
    @Published var gridGuide: GridGuideSubdivision = .eighth
    @Published var practiceViewZoom: PracticeViewZoom = .standard
    @Published var courseTitleOverride: String?
    @Published var selectedTempoTier = 0
    @Published var practiceFragment = 0
    /// Vacío significa el ritmo completo. Una selección no vacía indica las
    /// voces que toca y puntúa la persona; las demás son acompañamiento.
    @Published var playerSounds = Set<String>()
    @Published var practiceLayer = "all"
    @Published var practiceStepRange: ClosedRange<Int>?
    @Published var transferCheck = false
    @Published var trainingPhase: TrainingPhase = .integrate
    @Published var showsTrainingPhases = false
    /// 0 = guía completa; 1…3 siguen los niveles Gap Metronome del marco D-A-I-T.
    @Published var gapMetronomeLevel = 0
    @Published var practiceHelp: PracticeHelp = .full; @Published var autopilotMessage = ""
    @Published var soundStatistics = [SoundStatistics](); @Published var recentAttempts = [PracticeAttempt](); @Published private(set) var unfilteredRecentAttempts = [PracticeAttempt](); @Published var progressFilter = 0; @Published var exportMessage = ""
    @Published var historicalDiagnostics: HistoricalDiagnostics?
    @Published var masterySeals = [MasterySeal]()
    @Published var lastHitRecords = [HitRecord](); @Published var whaleMessage = ""; @Published var whaleTargetMessage = ""
    @Published var courseLevels = [CourseLevelState](); @Published private(set) var courseEvidence = [CourseAttemptEvidence]()
    @Published var tuning = PracticeTuning()
    @Published var loopEnabled = true; @Published var loopStatus = "Sin loop cargado"; @Published var loopTempo: Double?
    @Published private(set) var loopOptions = [LoopLibraryOption]()
    @Published private(set) var selectedLoopID: String?
    @Published private(set) var loopSelectionIsAutomatic = UserDefaults.standard.object(forKey: "xRoll.loopSelectionAutomatic") as? Bool ?? true
    @Published var metronomeEnabled = true
    @Published var metronomeStatus = "Claqueta sintetizada (independiente de los sonidos del kit)"
    @Published var lastScorePercentage: Double?; @Published var lastScoreStars = 0
    @Published var lastTotalHits = 0; @Published var lastWellTimed = 0; @Published var lastRegular = 0; @Published var lastWrong = 0
    @Published var lastPoints = 0.0; @Published var lastPossiblePoints = 0; @Published var nextExerciseTitle: String?
    @Published private(set) var nextSessionPlan: NextSessionPlan?
    @Published var resultSummary: PracticeResultSummary?
    @Published var microLessonFeedback = ""
    @Published var performanceFeedback = ""
    @Published var showingResults = false
    @Published private(set) var isShowingResultTransition = false
    @Published private(set) var resultTransitionPercentage = 0.0
    @Published var showingPreparation = false
    @Published var showingCalibrationWarning = false
    @Published private(set) var midiDroppedPackets: UInt64 = 0
    private var kit: KitManifest?; private var audio: SampleAudioEngine?; private var gm: KitNoteRouter?; private var liveMIDI: LiveMIDIProcessor?; private var bundledExercises = [Exercise]()
    private var custom: PadMapV2?; private var customRouter: PadMapV2Router?; private var input: MIDIInputSession?
    private var builder: PadMapBuilder?; private var keyboardCapture = [String: String](); private var monitor: Any?
    private let mappingStateLock = NSLock(); private var mappingActiveForMIDI = false
    private var midiRefreshTimer: Timer?
    private var midiSetupMonitor: MIDISetupMonitor?
    private var audioRouteMonitor: AudioRouteMonitor?
    private var activatedBluetoothDeviceID: UUID?
    private lazy var bluetoothMIDI: BluetoothMIDIManager = {
        let manager = BluetoothMIDIManager()
        manager.onUpdate = { [weak self] devices, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.bluetoothMIDIDevices = devices
                self.bluetoothMIDIStatus = message
                if let connected = devices.first(where: { $0.state == .connected }), self.activatedBluetoothDeviceID != connected.id {
                    self.activatedBluetoothDeviceID = connected.id
                    // CoreMIDI registers the endpoint immediately after the BLE
                    // driver is activated. Give it a brief turn before reading
                    // sources, then select it through the usual safe path.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.refreshMIDIDevices() }
                }
            }
        }
        return manager
    }()
    private var practice: PracticeSession?; private var practiceStartHostTime: UInt64 = 0; private var practiceToken = UUID()
    private var lastExerciseScore: ExerciseScore?
    private var lastCorrectivePlan: WhalePlan?
    private enum MicroLessonStage { case suggested, isolating, integrating, completed }
    private var microLessonStage: MicroLessonStage = .completed
    private var microLessonFocusSound: String?
    private var microLessonBaselineAccuracy: Double?
    private var microLessonBaselineExpected = 0
    private var microLessonReturnBPM = 80
    private var microLessonReturnRepeats = 2
    private var performanceTransferActive = false
    private var performanceGuidedBaseline: Double?
    private var performanceGuidedExpected = 0
    private var performanceComparisonAllowed = false
    private var performancePreviousLoopEnabled: Bool?
    private var lastAutopilotRecommendation: AutopilotRecommendation?
    private var previewToken = UUID()
    private var resultTransitionToken = UUID()
    private var progressStore: ProgressStore?; private var calibrationOffset: Double = 0; private var calibrationProfileKey: CalibrationProfileKey?; private var calibrating = false

    init() {
        load()
        let savedBluetoothID = UserDefaults.standard.string(forKey: "xRoll.bluetoothMIDI.deviceID").flatMap(UUID.init(uuidString:))
        bluetoothMIDI.start(preferredDeviceID: savedBluetoothID)
        // CoreMIDI does not reconnect an input port to sources that appear after
        // the port was created. Polling its lightweight source list keeps USB
        // controllers usable when they are plugged in while xRoll is open.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshMIDIDevices(announceChanges: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        midiRefreshTimer = timer
        midiSetupMonitor = try? MIDISetupMonitor { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshMIDIDevices(announceChanges: false)
                // BLE registration sometimes follows its setup notification
                // by a fraction of a second. A second pass avoids requiring a
                // manual refresh or an app relaunch.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.refreshMIDIDevices(announceChanges: false)
                }
            }
        }
        audioRouteMonitor = AudioRouteMonitor { [weak self] in
            self?.refreshAudioOutputs()
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Never consume macOS command shortcuts. In particular, a custom
            // pad assignment on Q must not intercept the standard ⌘Q quit.
            guard !event.modifierFlags.contains(.command) else { return event }
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

    func refreshBluetoothMIDIDevices() { bluetoothMIDI.refresh() }
    func connectBluetoothMIDI(_ device: BluetoothMIDIDevice) {
        UserDefaults.standard.set(device.id.uuidString, forKey: "xRoll.bluetoothMIDI.deviceID")
        bluetoothMIDI.connect(device.id)
    }
    func disconnectBluetoothMIDI() {
        bluetoothMIDI.disconnect()
        UserDefaults.standard.removeObject(forKey: "xRoll.bluetoothMIDI.deviceID")
        activatedBluetoothDeviceID = nil
    }
    var bluetoothMIDIDirectConnectionSupported: Bool { bluetoothMIDI.supportsDirectConnection }
    func openAudioMIDISetup() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")
        if !NSWorkspace.shared.open(url) {
            bluetoothMIDIStatus = "No se pudo abrir Configuración de Audio MIDI. Ábrela desde Aplicaciones > Utilidades."
        }
    }

    var chosen: Exercise? { exercises.first { $0.id == chosenID } }
    var metroChapters: [MetroChapter] {
        guard let graph = try? CourseGraph(exercises: bundledExercises) else { return [] }
        var chapters = [MetroChapter]()
        for node in graph.nodes where !node.metadata.chapter.hasPrefix("fills-") {
            if let index = chapters.firstIndex(where: { $0.id == node.metadata.chapter }) {
                chapters[index] = MetroChapter(id: chapters[index].id, exercises: chapters[index].exercises + [node.exercise])
            } else {
                chapters.append(MetroChapter(id: node.metadata.chapter, exercises: [node.exercise]))
            }
        }
        return chapters
    }
    var courseRecommendation: CourseRecommendation? {
        CourseRecommendationPlanner.recommend(exercises: bundledExercises, courseLevels: courseLevels, evidence: courseEvidence)
    }
    var nextCourseExercise: Exercise? {
        let ordered = metroChapters.flatMap(\.exercises)
        guard let chosenIndex = ordered.firstIndex(where: { $0.id == chosenID }), ordered.indices.contains(chosenIndex + 1) else { return nil }
        return ordered[chosenIndex + 1]
    }
    var canOfferNextCourseExercise: Bool {
        canSuggestProgress && nextCourseExercise != nil
    }
    private var canSuggestProgress: Bool {
        lastScoreStars >= 2 && isFullRhythmSelection && !transferCheck
            && practiceStepRange == nil && practiceFragment == 0
    }
    private var nextTempoLevel: TempoPracticeStep? {
        guard canSuggestProgress, let chosen else { return nil }
        return TempoLadder.steps(for: chosen).first {
            $0.bpm > selectedBPM && !TempoLadder.isPassed($0, exerciseID: chosen.id, evidence: courseEvidence)
        }
    }
    private enum ResultProgressSuggestion {
        case raise(TempoPracticeStep)
        case next(Exercise)
    }
    private var resultProgressSuggestion: ResultProgressSuggestion? {
        guard canSuggestProgress else { return nil }
        if let next = nextCourseExercise, courseRecommendation?.exerciseID != chosen?.id {
            return .next(next)
        }
        if let level = nextTempoLevel { return .raise(level) }
        if let next = nextCourseExercise { return .next(next) }
        return nil
    }
    var alternativeProgressTitle: String? {
        switch resultProgressSuggestion {
        case .next where nextTempoLevel != nil: return "Subir nivel"
        case .raise where canOfferNextCourseExercise: return "Siguiente ejercicio"
        default: return nil
        }
    }
    var loopSelectionChoice: String {
        loopSelectionIsAutomatic ? LoopLibraryCatalog.automaticSelectionID : (selectedLoopID ?? LoopLibraryCatalog.automaticSelectionID)
    }
    var loopSelectionLabel: String {
        guard let option = chosen.flatMap({ LoopLibraryCatalog.recommended(for: $0, targetBPM: Double(selectedBPM), options: loopOptions) }) else {
            return "Automático"
        }
        return "Auto · \(option.fileName) · \(Int((option.bpm ?? 0).rounded())) BPM"
    }
    var canChangeLoopSelection: Bool { practice == nil && practiceScene == nil && previewScene == nil }
    func highestTempoAward(for exercise: Exercise) -> TempoAward? {
        TempoLadder.highestPassedStep(for: exercise, evidence: courseEvidence)?.award
    }
    func openNextCourseExercise() {
        guard canOfferNextCourseExercise, let exercise = nextCourseExercise else { return }
        chooseExercise(exercise)
        showingPreparation = true
    }
    private func raiseTempoLevel() {
        guard let level = nextTempoLevel,
              let tier = tempoPracticeOptions.firstIndex(where: { $0.bpm == level.bpm }) else { return }
        selectTempoTier(tier)
        startGuidedLesson()
        if practice != nil { showingResults = false }
    }
    func performAlternativeProgressAction() {
        switch resultProgressSuggestion {
        case .next: raiseTempoLevel()
        case .raise: openNextCourseExercise()
        case nil: break
        }
    }
    func tempoProgressSummary(for exercise: Exercise) -> String {
        if let state = courseLevels.first(where: { $0.exerciseID == exercise.id }) {
            if case .checkpoint(exerciseID: _) = state.creditSource {
                return "Acreditado por checkpoint"
            }
            if state.status == .mastered, !state.chapterAccredited {
                return "Superado individualmente · capítulo pendiente"
            }
        }
        if let step = TempoLadder.highestPassedStep(for: exercise, evidence: courseEvidence) {
            return "Reto \(step.label) superado · \(step.bpm) BPM · premio: \(step.award.label)"
        }
        if let step = TempoLadder.nextStep(for: exercise, evidence: courseEvidence) {
            return "Te toca: \(step.label) · \(step.bpm) BPM"
        }
        return "Escalera completa"
    }
    var selectedMIDIName: String { sources.first(where: { $0.uniqueID == sourceID })?.name ?? "Sin controlador seleccionado" }
    var hasAssignedPad: Bool {
        guard let sourceID, sources.contains(where: { $0.uniqueID == sourceID }) else { return false }
        return input != nil
    }
    var needsHomeSetup: Bool { !hasAssignedPad || !hasCalibrationForCurrentProfile }
    var hasCalibrationForCurrentProfile: Bool { calibrationProfileKey == profileKey() }
    var midiDiagnostics: String {
        guard tuning.debugEnabled else { return "" }
        return "MIDI: \(midiDroppedPackets) paquetes descartados"
    }
    var currentExerciseTitle: String { courseTitleOverride ?? chosen?.title ?? "Ejercicio" }
    /// Los escalones se derivan del BPM del MIDI seleccionado; un tempo absoluto
    /// no representa la misma dificultad en dos grooves distintos.
    var tempoPracticeOptions: [TempoPracticeStep] {
        chosen.map(TempoLadder.steps(for:)) ?? []
    }
    func selectTempoTier(_ tier: Int) {
        let options = tempoPracticeOptions
        guard options.indices.contains(tier), isTempoTierAvailable(tier) else { return }
        selectedTempoTier = tier
        selectedBPM = options[tier].bpm
        if let exercise = chosen, let repeats = TempoLadder.repeats(for: options[tier], exercise: exercise) {
            selectedRepeats = repeats
        } else if let exercise = chosen {
            selectedRepeats = defaultRepeats(for: exercise)
        }
        if let chosen { updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM) }
        savePreferences()
    }
    /// Las estrellas pertenecen a la combinación ejercicio + tempo. Un buen
    /// resultado en Aprender no acredita Base ni Consolidar.
    func starsForTempoTier(_ tier: Int, exercise: Exercise? = nil) -> Int? {
        guard tempoPracticeOptions.indices.contains(tier), let id = (exercise ?? chosen)?.id else { return nil }
        let bpm = tempoPracticeOptions[tier].bpm
        return courseEvidence
            .filter { $0.exerciseID == id && $0.bpm == bpm }
            .map(\.stars)
            .max()
    }
    func tempoTierStarsLabel(_ tier: Int, exercise: Exercise? = nil) -> String {
        guard let stars = starsForTempoTier(tier, exercise: exercise) else { return "Sin intento" }
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars)
    }
    func tempoTierAwardLabel(_ tier: Int) -> String {
        guard tempoPracticeOptions.indices.contains(tier) else { return "" }
        return tempoPracticeOptions[tier].award.label
    }
    func tempoTierProgressLabel(_ tier: Int, exercise: Exercise? = nil) -> String {
        guard tempoPracticeOptions.indices.contains(tier), let exercise = exercise ?? chosen else { return "Sin intento" }
        let step = tempoPracticeOptions[tier]
        let passes = TempoLadder.passedAttempts(for: step, exerciseID: exercise.id, evidence: courseEvidence)
        return "\(min(passes, step.requiredPasses))/\(step.requiredPasses) a \(Int(step.requiredScore)) %"
    }
    func isTempoTierAvailable(_ tier: Int, exercise: Exercise? = nil) -> Bool {
        let steps = exercise.map(TempoLadder.steps(for:)) ?? tempoPracticeOptions
        return steps.indices.contains(tier)
    }
    var tempoGuidance: String {
        guard let chosen else { return "Elige un ritmo para ver sus retos opcionales de tempo." }
        guard let step = tempoPracticeOptions.first(where: { !TempoLadder.isPassed($0, exerciseID: chosen.id, evidence: courseEvidence) }) else {
            return "Has completado los retos de tempo disponibles para este ritmo."
        }
        return "Reto opcional: \(step.label) a \(step.bpm) BPM. No necesitas superarlo para avanzar en el curso."
    }
    var practiceHelpDescription: String {
        switch practiceHelp {
        case .full:
            return "Completa: muestra todos los golpes del patrón y sus nombres para que puedas seguir la rejilla."
        case .normal:
            return "Normal: conserva todos los golpes y la rejilla, pero oculta los nombres de los pads para que reconozcas cada carril."
        case .reduced:
            return "Reducida: retira los golpes fuertes de charles de la guía; así entrenas el pulso sin depender de cada referencia visual."
        }
    }
    func setPracticeHelp(_ help: PracticeHelp) {
        practiceHelp = help
        UserDefaults.standard.set(help.rawValue, forKey: "xRoll.practiceHelp")
        preview = "Ayuda activa: \(help.label). \(practiceHelpDescription)"
    }
    func setTrainingPhase(_ phase: TrainingPhase) {
        trainingPhase = phase
        preview = "Fase activa: \(phase.label). \(phase.explanation)"
    }
    func setShowsTrainingPhases(_ enabled: Bool) {
        showsTrainingPhases = enabled
        UserDefaults.standard.set(enabled, forKey: "xRoll.showsTrainingPhases")
        if !enabled { trainingPhase = .integrate; transferCheck = false; gapMetronomeLevel = 0 }
    }
    var configuredExercise: Exercise? {
        chosen.map { selected in
            let configured = PracticeConfiguration(exercise: selected, bpm: selectedBPM, repeats: selectedRepeats).applying(to: selected)
            return exerciseForFragment(configured)
        }
    }
    private func exerciseForFragment(_ exercise: Exercise) -> Exercise {
        let notes: [Exercise.Note]
        if let practiceStepRange {
            notes = exercise.notes.filter { practiceStepRange.contains($0.step) }
        } else {
            switch practiceFragment {
            case 1: notes = exercise.notes.filter { $0.step < exercise.grid / 2 }
            case 2: notes = exercise.notes.filter { $0.step >= exercise.grid / 2 }
            default: notes = exercise.notes
            }
        }
        return Exercise(format: exercise.format, id: exercise.id, title: exercise.title, family: exercise.family, level: exercise.level, bpm: exercise.bpm, meter: exercise.meter, bars: exercise.bars, grid: exercise.grid, repeats: exercise.repeats, kit: exercise.kit, loop: exercise.loop, offset: exercise.offset, notes: notes)
    }
    var lessonGoal: String {
        guard let chosen else { return "Elige un nivel para ver el objetivo." }
        if let objective = chosen.metadata?.objective, !objective.isEmpty, objective != chosen.title {
            return objective
        }
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
        let order = ["kick", "rim", "snare", "hihat_closed", "hihat_open", "clap", "tom_low", "tom_high", "crash", "ride"]
        return order.compactMap { sound in
            guard let count = counts[sound] else { return nil }
            return "\(displayName(sound)) ×\(count)"
        }
    }
    var practiceLayerOptions: [String] { ["all"] + Array(Set(configuredExercise?.notes.map(\.sound) ?? [])).sorted() }
    var kitSoundIDs: [String] { kit?.sounds.map(\.id) ?? [] }
    func soundVolume(_ sound: String) -> Double { tuning.soundVolumes[sound] ?? 1 }
    func setSoundVolume(_ volume: Double, for sound: String) {
        tuning.soundVolumes[sound] = min(1.5, max(0, volume))
        audio?.setSoundVolume(Float(soundVolume(sound)), for: sound)
        saveTuning()
    }
    func resetSoundMix() {
        tuning.soundVolumes = [:]
        kitSoundIDs.forEach { audio?.setSoundVolume(1, for: $0) }
        saveTuning()
    }
    var availablePracticeSounds: [String] { practiceLayerOptions.filter { $0 != "all" } }
    var selectedPlayerSounds: Set<String> {
        let available = Set(availablePracticeSounds)
        return playerSounds.isEmpty ? available : playerSounds.intersection(available)
    }
    var isFullRhythmSelection: Bool { selectedPlayerSounds == Set(availablePracticeSounds) }
    var canStartTransferPerformance: Bool {
        isFullRhythmSelection && practiceStepRange == nil && !transferCheck && trainingPhase != .transfer
    }
    var transferPerformanceTitle: String { loopTempo == nil ? "Tocar sin guía visual" : "Tocar con la banda" }
    func selectFullRhythm() {
        playerSounds = []
        practiceLayer = "all"
    }
    func togglePlayerSound(_ sound: String) {
        let all = Set(availablePracticeSounds)
        var selection = selectedPlayerSounds
        if selection.contains(sound) { selection.remove(sound) } else { selection.insert(sound) }
        // La representación vacía mantiene el ajuste "ritmo completo" incluso
        // cuando el ejercicio cambia de sonidos.
        playerSounds = selection == all ? [] : selection
        practiceLayer = selection.count == 1 ? selection.first! : "all"
    }
    func setPlayerSounds(_ sounds: Set<String>) {
        let all = Set(availablePracticeSounds)
        let selection = sounds.intersection(all)
        playerSounds = selection == all ? [] : selection
        practiceLayer = selection.count == 1 ? selection.first! : "all"
    }
    var weakestSoundFeedback: String {
        guard let weakest = soundStatistics.min(by: { $0.accuracy < $1.accuracy }) else { return "Completa una vuelta para recibir una recomendación." }
        return "Repasa \(displayName(weakest.sound)): \(Int(weakest.accuracy.rounded())) % de acierto (\(weakest.missed) fallos)."
    }
    var nextPracticeRecommendation: String {
        guard lastScorePercentage != nil else { return "Empieza por escuchar una demostración guiada." }
        if hasAdvancingCourseRecommendation, let recommendation = courseRecommendation {
            if recommendation.exerciseID == chosen?.id {
                return "Buen trabajo: termina el ritmo completo a su tempo de referencia, \(recommendation.tempoStep.bpm) BPM."
            }
            if let exercise = exercises.first(where: { $0.id == recommendation.exerciseID }) {
                return "Buen trabajo: prueba \(exercise.title)."
            }
        }
        if lastScoreStars >= 2, let nextExerciseTitle { return "Buen trabajo: prueba \(nextExerciseTitle)." }
        return "Repite el mismo nivel enfocándote en el sonido indicado."
    }
    private var hasAdvancingCourseRecommendation: Bool {
        guard lastScoreStars >= 2,
              isFullRhythmSelection,
              practiceStepRange == nil,
              practiceFragment == 0,
              !transferCheck,
              let recommendation = courseRecommendation else { return false }
        return recommendation.exerciseID != chosen?.id || recommendation.tempoStep.bpm > selectedBPM
    }
    var resultDiagnosis: String {
        guard let diagnosis = resultSummary?.diagnosis else { return "Termina una vuelta para obtener un diagnóstico." }
        switch diagnosis {
        case .insufficientEvidence:
            return "No hubo suficientes golpes asociados para evaluar tu timing."
        case .weakSound(let sound, let accuracy, let missed):
            return "\(displayName(sound)) necesita atención: \(Int(accuracy.rounded())) % de acierto y \(missed) fallos."
        case .inconsistent(let spread):
            return "El pulso oscila entre golpes: la dispersión central fue de \(Int(spread.rounded())) ms."
        case .timingBias(let offset):
            return offset < 0
                ? "Los golpes asociados quedaron \(Int(abs(offset).rounded())) ms antes del centro puntuado."
                : "Los golpes asociados quedaron \(Int(offset.rounded())) ms después del centro puntuado."
        case .solid:
            return "Tu pulso está centrado y el patrón se mantiene estable."
        }
    }
    var resultActionTitle: String {
        if microLessonStage == .isolating { return "Volver al groove completo" }
        switch resultProgressSuggestion {
        case .raise: return "Subir nivel"
        case .next: return "Siguiente ejercicio"
        case nil: break
        }
        if hasAdvancingCourseRecommendation, let recommendation = courseRecommendation {
            return recommendation.exerciseID == chosen?.id
                ? "Completar ritmo"
                : "Siguiente ejercicio"
        }
        switch resultSummary?.action {
        case .corrective: return "Repetir ejercicio"
        case .repeatWithAdjustment: return "Aplicar ajuste y repetir"
        case .advance: return "Siguiente ejercicio"
        case .repeatSame: return "Repetir para consolidar"
        case nil: return "Repetir"
        }
    }
    var canStartCorrectivePractice: Bool {
        microLessonStage == .suggested && lastCorrectivePlan != nil && resultSummary != nil
    }
    var correctiveActionReason: String {
        guard let plan = lastCorrectivePlan else { return "" }
        return plan.coachingCue.replacingOccurrences(of: plan.focusSound, with: displayName(plan.focusSound))
    }
    var resultActionReason: String {
        if microLessonStage == .isolating {
            return "Ya has aislado el momento. Ahora toca el patrón completo para probar cómo encaja en el groove."
        }
        switch resultProgressSuggestion {
        case .raise(let level):
            return "Prueba el siguiente escalón, \(level.label) a \(level.bpm) BPM. Este reto es opcional y no cambia lo que ya has acreditado."
        case .next(let exercise):
            return "Prepara «\(exercise.title)». Puedes explorarla sin perder tus premios ni saltarte requisitos del curso."
        case nil: break
        }
        if hasAdvancingCourseRecommendation, let recommendation = courseRecommendation {
            if recommendation.exerciseID == chosen?.id {
                return "Toca el ritmo completo a su tempo de referencia (\(recommendation.tempoStep.bpm) BPM) y alcanza el 70 % para continuar."
            }
            let title = exercises.first(where: { $0.id == recommendation.exerciseID })?.title ?? "el siguiente ejercicio"
            return "Buen trabajo. La siguiente lección es «\(title)». Los retos de velocidad son opcionales."
        }
        switch resultSummary?.action {
        case .corrective: return "Repite el patrón completo para superarlo. Si te ayuda, puedes aislar la parte difícil como opción."
        case .repeatWithAdjustment: return lastAutopilotRecommendation?.message ?? "Repite con más apoyo para centrar el patrón."
        case .advance: return nextExerciseTitle.map { "Este intento permite continuar con \($0)." } ?? "El patrón está listo para avanzar."
        case .repeatSame: return "La configuración actual funciona: otra vuelta ayudará a consolidarla."
        case nil: return "Repite el patrón con la misma configuración."
        }
    }
    var resultTimingMetric: String {
        guard let value = resultSummary?.medianOffsetMilliseconds else { return "Sin datos" }
        if abs(value) < 0.5 { return "Centrado" }
        return String(format: "%.0f ms %@", abs(value), value < 0 ? "antes" : "después")
    }
    var resultConsistencyMetric: String {
        resultSummary?.consistencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "Sin datos"
    }
    func performResultAction() {
        if microLessonStage == .isolating {
            returnToFullGroove()
            return
        }
        switch resultProgressSuggestion {
        case .raise: raiseTempoLevel(); return
        case .next: openNextCourseExercise(); return
        case nil: break
        }
        if hasAdvancingCourseRecommendation {
            followCourseRecommendation()
            return
        }
        switch resultSummary?.action {
        case .corrective: repeatPractice()
        case .repeatWithAdjustment: applyAutopilot(); repeatPractice()
        case .advance: moveToSuggestedExercise()
        case .repeatSame, nil: repeatPractice()
        }
    }
    private func followCourseRecommendation() {
        guard let recommendation = courseRecommendation else { return }
        if recommendation.exerciseID == chosen?.id,
           let tier = tempoPracticeOptions.firstIndex(where: { $0.bpm == recommendation.tempoStep.bpm }) {
            selectTempoTier(tier)
            showingResults = false
            showingPreparation = true
            return
        }
        guard let exercise = exercises.first(where: { $0.id == recommendation.exerciseID }) else { return }
        chooseExercise(exercise)
        showingPreparation = false
        beginPractice(calibration: false)
    }
    var analysisAverageScore: Double? {
        guard !recentAttempts.isEmpty else { return nil }
        return recentAttempts.map(\.score).reduce(0, +) / Double(recentAttempts.count)
    }
    var analysisMostPracticed: String {
        guard let item = Dictionary(grouping: recentAttempts, by: \.exerciseID).max(by: { $0.value.count < $1.value.count }) else { return "Aún no hay intentos." }
        let title = exercises.first(where: { $0.id == item.key })?.title ?? item.key
        return "\(title) · \(item.value.count) intentos"
    }
    var analysisTiming: String {
        let offsets = recentAttempts.compactMap(\.meanOffsetMilliseconds)
        guard !offsets.isEmpty else { return "Aún no hay suficientes golpes medidos." }
        let mean = offsets.reduce(0, +) / Double(offsets.count)
        if mean < -12 { return String(format: "Sueles adelantar %.0f ms", abs(mean)) }
        if mean > 12 { return String(format: "Sueles retrasar %.0f ms", mean) }
        return "Tu pulso medio está centrado"
    }
    var analysisWeakestSound: String {
        var totals: [String: (expected: Int, successful: Int, missed: Int)] = [:]
        for statistic in recentAttempts.flatMap(\.soundStatistics) {
            let current = totals[statistic.sound] ?? (0, 0, 0)
            totals[statistic.sound] = (current.expected + statistic.expected, current.successful + statistic.perfect + statistic.good + statistic.regular, current.missed + statistic.missed)
        }
        guard let weakest = totals.filter({ $0.value.expected > 0 }).min(by: { Double($0.value.successful) / Double($0.value.expected) < Double($1.value.successful) / Double($1.value.expected) }) else {
            return "El detalle por sonido aparecerá tras tus próximas prácticas."
        }
        let accuracy = Double(weakest.value.successful) / Double(weakest.value.expected) * 100
        return "\(displayName(weakest.key)): \(Int(accuracy.rounded())) % · \(weakest.value.missed) fallos"
    }
    fileprivate func name(_ pad: PadPosition) -> String? {
        custom?.pads.first(where: { $0.row == pad.row && $0.column == pad.column })?.sound ?? kit?.sounds.first(where: { $0.gmNote == pad.note })?.id
    }
    fileprivate func midiLabel(for pad: PadPosition) -> String {
        let number = custom?.pads.first(where: { $0.row == pad.row && $0.column == pad.column })?.input.number ?? pad.note
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[number % 12])\(number / 12 - 1) · MIDI \(number)"
    }
    func displayName(_ sound: String?) -> String {
        guard let sound else { return "Libre" }
        return kit?.sounds.first(where: { $0.id == sound })?.label ?? sound.replacingOccurrences(of: "_", with: " ").capitalized
    }
    func selectSource() {
        setMapping(false); builder = nil
        if let sourceID { UserDefaults.standard.set(Int(sourceID), forKey: "xRoll.midiSourceID") }
        else { UserDefaults.standard.removeObject(forKey: "xRoll.midiSourceID") }
        connect()
    }
    func refreshAudioOutputs() {
        audioOutputs = AudioInspector.outputDevices()
        if let selectedAudioOutputUID, !audioOutputs.contains(where: { $0.uid == selectedAudioOutputUID }) {
            let fallbackUID = AudioInspector.defaultOutputDeviceID().flatMap { id in audioOutputs.first(where: { $0.deviceID == id })?.uid }
            self.selectedAudioOutputUID = fallbackUID
            guard let fallback = fallbackUID.flatMap({ uid in audioOutputs.first(where: { $0.uid == uid }) }) else {
                interruptPracticeForRouteChange("La salida de audio se desconectó.")
                status = "No hay salidas de audio disponibles"
                return
            }
            do {
                try withSuspendedMIDIInput {
                    audio?.stopScheduledSounds()
                    audio?.stopLoop()
                    try audio?.setOutputDevice(fallback.deviceID)
                    try restoreSavedAudioBuffer(for: fallback)
                }
                UserDefaults.standard.set(fallback.uid, forKey: "xRoll.audioOutputUID")
                interruptPracticeForRouteChange("La salida cambió a \(fallback.name). El intento no se guardó.")
                loadCalibration()
            } catch {
                interruptPracticeForRouteChange("No se pudo recuperar la salida de audio.")
                status = error.localizedDescription
            }
        }
        guard let selected = audioOutputs.first(where: { $0.uid == selectedAudioOutputUID }) else {
            status = "No hay salidas de audio disponibles"
            return
        }
        status = "Salidas actualizadas: \(selected.name)"
    }

    /// Suspende la entrega MIDI durante una reconfiguración de audio, como exige
    /// docs/ARCHITECTURE.md: el worker de entrada no debe seguir activo mientras
    /// se cambia de salida o de buffer. Al terminar reconecta con `connect()`,
    /// que ya recarga mapa y calibración. El `status` propio lo fija el llamador
    /// después, porque `connect()` escribe el suyo.
    private func withSuspendedMIDIInput(_ body: () throws -> Void) rethrows {
        let wasConnected = input != nil
        input = nil
        defer { if wasConnected { connect() } }
        try body()
    }

    private func interruptPracticeForRouteChange(_ message: String) {
        guard practice != nil else { return }
        practiceToken = UUID()
        previewToken = UUID()
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        practice = nil
        practiceScene = nil
        previewScene = nil
        isPracticePaused = false
        calibrating = false
        showingResults = false
        status = message
    }
    func selectAudioOutput() {
        guard let selected = audioOutputs.first(where: { $0.uid == selectedAudioOutputUID }) else { return }
        do {
            try withSuspendedMIDIInput {
                audio?.stopScheduledSounds()
                audio?.stopLoop()
                try audio?.setOutputDevice(selected.deviceID)
                try restoreSavedAudioBuffer(for: selected)
            }
            UserDefaults.standard.set(selected.uid, forKey: "xRoll.audioOutputUID")
            loadCalibration()
            status = "Salida de audio: \(selected.name)"
        } catch {
            status = error.localizedDescription
        }
    }
    var selectedAudioOutput: AudioOutputDeviceDescription? {
        audioOutputs.first(where: { $0.uid == selectedAudioOutputUID })
    }
    var selectedAudioBuffer: UInt32? {
        selectedAudioOutput.flatMap { AudioInspector.output(deviceID: $0.deviceID).bufferFrameSize }
    }
    var selectedAudioBufferChoices: [UInt32] {
        guard let output = selectedAudioOutput,
              let range = AudioInspector.output(deviceID: output.deviceID).bufferFrameRange else { return [] }
        let common: [UInt32] = [16, 32, 64, 128, 256, 512, 1_024, 2_048, 4_096]
        let current = selectedAudioBuffer.map { [$0] } ?? []
        return Array(Set(common.filter(range.contains) + current)).sorted()
    }
    func setAudioBufferFrames(_ frames: UInt32) {
        guard let output = selectedAudioOutput else { return }
        do {
            try withSuspendedMIDIInput {
                audio?.stopScheduledSounds()
                audio?.stopLoop()
                audio?.stop()
                try AudioInspector.setBufferFrameSize(frames, for: output.deviceID)
                try audio?.start()
            }
            UserDefaults.standard.set(Int(frames), forKey: audioBufferPreferenceKey(for: output.uid))
            loadCalibration()
            status = "Buffer de audio: \(frames). Calibra de nuevo este perfil."
        } catch {
            try? audio?.start()
            status = error.localizedDescription
        }
    }
    private func audioBufferPreferenceKey(for uid: String) -> String { "xRoll.audioBufferFrames.\(uid)" }
    private func savedAudioBufferFrames(for output: AudioOutputDeviceDescription) -> UInt32? {
        guard let value = UserDefaults.standard.object(forKey: audioBufferPreferenceKey(for: output.uid)) as? Int,
              value > 0,
              let range = AudioInspector.output(deviceID: output.deviceID).bufferFrameRange,
              range.contains(UInt32(value)) else { return nil }
        return UInt32(value)
    }
    private func restoreSavedAudioBuffer(for output: AudioOutputDeviceDescription) throws {
        guard let frames = savedAudioBufferFrames(for: output) else { return }
        audio?.stop()
        do {
            try AudioInspector.setBufferFrameSize(frames, for: output.deviceID)
            try audio?.start()
        } catch {
            try? audio?.start()
            throw error
        }
    }
    func refreshMIDIDevices() { refreshMIDIDevices(announceChanges: true) }
    private func refreshMIDIDevices(announceChanges: Bool) {
        midiDroppedPackets = input?.droppedPacketCount ?? 0
        let available = MIDIInspector.sources().map { candidate in
            // A temporary driver label must not erase the name the user chose.
            // The endpoint identifier remains authoritative across refreshes.
            if candidate.name.hasPrefix("Entrada MIDI"), let previous = sources.first(where: { $0.uniqueID == candidate.uniqueID }) { return previous }
            return candidate
        }
        let changed = available != sources
        guard changed || announceChanges else { return }

        let previousID = sourceID
        sources = available

        if let previousID, available.contains(where: { $0.uniqueID == previousID }) {
            if changed { connect() }
        } else if let preferred = preferredMIDISource(in: available) {
            sourceID = preferred.uniqueID
            if let sourceID { UserDefaults.standard.set(Int(sourceID), forKey: "xRoll.midiSourceID") }
            connect()
        } else {
            interruptPracticeForRouteChange("La entrada MIDI se desconectó. El intento no se guardó.")
            sourceID = nil
            input = nil
            custom = nil
            customRouter = nil
            liveMIDI?.setPadRouter(nil)
            setMapping(false)
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
        setMapping(true); mapMessage = "Golpea el pad para bombo."
    }
    func cancelMapping() { setMapping(false); builder = nil; mapMessage = "Asignacion cancelada." }
    func applyLayoutPreset() {
        guard let source = sources.first(where: { $0.uniqueID == sourceID }) else { mapMessage = "Elige una entrada MIDI para guardar el layout."; return }
        guard let custom, custom.device.uid == Int(source.uniqueID ?? 0) else {
            mapMessage = "Primero usa «Empezar asignación» para aprender las notas de tu pad. Así el layout no inventará notas MIDI."
            return
        }
        // SMC-PAD uses the standard 4×4 grid: note 36 in the lower-left
        // corner through note 51 in the upper-right. Build all sixteen
        // physical cells from that fixed matrix so a preset never inherits a
        // partial (ten-pad) educational map or changes note positions.
        let isStandard4x4 = !custom.pads.isEmpty && custom.pads.allSatisfy {
            $0.input.number == 36 + $0.row * 4 + $0.column
        }
        let physical: PadMapV2
        if isStandard4x4 {
            let channel = custom.pads.first?.input.channel ?? 10
            physical = PadLayoutFactory.make(.drumKit, device: .init(name: source.name, uid: Int(source.uniqueID ?? 0)), channel: channel)
            savePhysicalMap(physical)
        } else {
            physical = loadPhysicalMap(sourceID) ?? custom
            if loadPhysicalMap(sourceID) == nil { savePhysicalMap(physical) }
        }
        let map = PadLayoutFactory.applying(selectedLayoutPreset, to: physical)
        save(map)
        mapMessage = isStandard4x4
            ? "Layout aplicado: MIDI 36 (C2) sigue abajo a la izquierda y MIDI 51 sigue arriba a la derecha."
            : "Layout aplicado: se han conservado las notas y canales MIDI de tus pads físicos."
    }
    func useLayout(_ preset: PadLayoutPreset) {
        selectedLayoutPreset = preset
        applyLayoutPreset()
    }
    func restoreCoreLayout() {
        selectedLayoutPreset = .core
        applyLayoutPreset()
    }
    func exportLayout() {
        guard let custom else { mapMessage = "Crea o carga un layout antes de exportarlo."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(custom.id).padmap"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { let data = try JSONEncoder().encode(custom); try data.write(to: url, options: .atomic); self.mapMessage = "Layout exportado." } catch { self.mapMessage = error.localizedDescription }
        }
    }
    func importLayout() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let kit = self.kit else { return }
            do { let map = try PadMapStore.loadV2(at: url, availableSounds: Set(kit.sounds.map(\.id))); self.save(map); self.mapMessage = "Layout importado." } catch { self.mapMessage = "No se pudo importar: \(error.localizedDescription)" }
        }
    }
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
        keyboardMapMessage = "Pulsa la tecla para bombo. Se asignarán los diez sonidos del kit."
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
            previewScene = PracticeScene(timeline: timeline, startHostTime: base, anticipationMilliseconds: timeline.patternDurationMilliseconds, slotBySound: slotsBySound(), soundLabels: soundLabels(), showsSoundLabels: true, gridGuide: gridGuide, viewZoom: practiceViewZoom)
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
    @discardableResult
    func startPractice() -> Bool {
        guard hasCalibrationForCurrentProfile else {
            calibrationMessage = "Calibra esta entrada y salida antes de puntuar."
            showingCalibrationWarning = true
            return false
        }
        beginPractice(calibration: false)
        return practice != nil
    }
    func startGuidedLesson() {
        trainingPhase = .integrate
        transferCheck = false
        gapMetronomeLevel = 0
        practiceStepRange = nil
        selectFullRhythm()
        if startPractice() { showingPreparation = false }
    }
    func repeatPractice() { cancelResultTransition(); showingResults = false; beginPractice(calibration: false) }
    func setRepeats(_ repeats: Int) {
        selectedRepeats = PracticeConfiguration.normalizedRepeats(repeats)
        savePreferences()
    }
    func setGridGuide(_ guide: GridGuideSubdivision) {
        gridGuide = guide
        UserDefaults.standard.set(guide.rawValue, forKey: "xRoll.gridGuide")
        practiceScene?.setGridGuide(guide)
        previewScene?.setGridGuide(guide)
    }
    func setPracticeViewZoom(_ zoom: PracticeViewZoom) {
        practiceViewZoom = zoom
        UserDefaults.standard.set(zoom.rawValue, forKey: "xRoll.practiceViewZoom")
        practiceScene?.setViewZoom(zoom)
        previewScene?.setViewZoom(zoom)
    }
    func restartPractice() {
        guard practice != nil else { return }
        // SpriteView can retain its previous SKScene when only the scene
        // reference changes. A new identity makes the visual transport restart
        // together with audio, score and scheduled notes.
        practiceVisualID = UUID()
        practiceScene = nil
        beginPractice(calibration: calibrating)
    }
    func pausePractice() {
        guard practice != nil, !isPracticePaused else { return }
        practiceToken = UUID()
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        practiceScene?.isPaused = true
        isPracticePaused = true
    }
    func resumePractice() {
        guard practice != nil, isPracticePaused else { return }
        // Reprogramar desde el principio evita mezclar golpes anteriores con un
        // reloj y un acompañamiento cuya fase ya no coinciden tras la pausa.
        practiceVisualID = UUID()
        beginPractice(calibration: calibrating)
    }
    func moveToSuggestedExercise() {
        guard let next = exercises.first(where: { $0.title == nextExerciseTitle }) else { return }
        chosenID = next.id; selectedRepeats = defaultRepeats(for: next); preview = ""
        showingResults = false; showingPreparation = false; savePreferences(); refreshProgress(for: next.id)
        beginPractice(calibration: false)
    }
    func dismissResults() {
        cancelResultTransition()
        showingResults = false
        practiceStepRange = nil; selectFullRhythm(); whaleTargetMessage = ""
        microLessonStage = .completed; microLessonFocusSound = nil; microLessonBaselineAccuracy = nil
        microLessonBaselineExpected = 0; lastCorrectivePlan = nil; microLessonFeedback = ""; performanceFeedback = ""
    }
    /// Persistent navigation must not leave an invisible session, loop or a
    /// delayed finish callback running underneath another screen.
    func leaveActiveScreen() {
        cancelResultTransition()
        practiceToken = UUID(); previewToken = UUID()
        audio?.stopScheduledSounds(); audio?.stopLoop()
        if let previous = performancePreviousLoopEnabled { loopEnabled = previous; performancePreviousLoopEnabled = nil }
        performanceTransferActive = false
        practice = nil; practiceScene = nil; previewScene = nil
        showingResults = false; showingPreparation = false; calibrating = false; isPracticePaused = false
    }
    func toggleLoop() {
        setLoopEnabled(!loopEnabled)
    }
    func setLoopEnabled(_ enabled: Bool) {
        loopEnabled = enabled
        guard enabled else { audio?.stopLoop(); return }
        guard let practice, let exercise = configuredExercise else { return }
        let elapsed = AudioClock.milliseconds(from: practiceStartHostTime, to: AudioGetCurrentHostTime())
        let bar = practice.timeline.barDurationMilliseconds
        let nextBar = max(0, ceil(elapsed / bar) * bar - elapsed)
        do { try audio?.startLoop(atHostTime: AudioClock.hostTime(afterMilliseconds: nextBar), targetBPM: Double(exercise.bpm), volume: Float(tuning.loopVolume)) }
        catch { loopStatus = "Error al iniciar el loop: \(error.localizedDescription)" }
    }
    func setLoopSelection(_ choice: String) {
        if choice == LoopLibraryCatalog.automaticSelectionID {
            loopSelectionIsAutomatic = true
            UserDefaults.standard.set(true, forKey: "xRoll.loopSelectionAutomatic")
            if let chosen { updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM) }
            return
        }
        guard canChangeLoopSelection, let option = loopOptions.first(where: { $0.id == choice }) else { return }
        loopSelectionIsAutomatic = false
        UserDefaults.standard.set(false, forKey: "xRoll.loopSelectionAutomatic")
        UserDefaults.standard.set(choice, forKey: "xRoll.selectedLoopID")
        loadLoop(option)
    }

    func refreshAutomaticLoopForSelection() {
        guard loopSelectionIsAutomatic, let chosen else { return }
        updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM)
    }

    private func updateAutomaticLoopSelection(for exercise: Exercise, targetBPM: Int) {
        guard loopSelectionIsAutomatic,
              let option = LoopLibraryCatalog.recommended(for: exercise, targetBPM: Double(targetBPM), options: loopOptions),
              option.id != selectedLoopID else { return }
        loadLoop(option)
    }

    private func restoreLoopSelection() {
        if loopSelectionIsAutomatic {
            refreshAutomaticLoopForSelection()
        } else if let id = UserDefaults.standard.string(forKey: "xRoll.selectedLoopID"),
                  let option = loopOptions.first(where: { $0.id == id }) {
            loadLoop(option)
        } else {
            loopSelectionIsAutomatic = true
            UserDefaults.standard.set(true, forKey: "xRoll.loopSelectionAutomatic")
            refreshAutomaticLoopForSelection()
        }
    }

    private func loadLoop(_ option: LoopLibraryOption) {
        guard canChangeLoopSelection, let audio else {
            loopStatus = "Detén la práctica antes de cambiar el loop."
            return
        }
        audio.stopLoop()
        do {
            try withSuspendedMIDIInput { try audio.loadLoop(url: option.url) }
            selectedLoopID = option.id
            loopTempo = audio.loopTempo?.bpm
            let tempoLabel = loopTempo.map { " · fuente \(Int($0.rounded())) BPM" } ?? ""
            loopStatus = "\(option.fileName)\(tempoLabel)"
            UserDefaults.standard.set(option.id, forKey: "xRoll.selectedLoopID")
        } catch {
            loopStatus = "No se pudo cargar el loop: \(error.localizedDescription)"
        }
    }
    func startCalibration() {
        calibrationMessage = "Calibración: charles a corcheas a 72 BPM."
        beginPractice(calibration: true)
    }
    private func cancelResultTransition() {
        resultTransitionToken = UUID()
        isShowingResultTransition = false
    }

    private func presentResultTransition(percentage: Double) {
        resultTransitionToken = UUID()
        let token = resultTransitionToken
        resultTransitionPercentage = percentage
        showingResults = false
        withAnimation(.easeInOut(duration: 0.20)) { isShowingResultTransition = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { [weak self] in
            guard let self, self.resultTransitionToken == token else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                self.isShowingResultTransition = false
                self.showingResults = true
            }
        }
    }

    private func beginPractice(calibration: Bool) {
        cancelResultTransition()
        let fullExercise: Exercise
        if calibration {
            // Una única voz constante evita que un patrón complejo introduzca
            // errores de lectura o coordinación en la estimación del desfase.
            guard let exercise = exercises.first(where: { $0.id == "02_sub_02_corcheas" }) else {
                calibrationMessage = "No se encontró el ejercicio de calibración."
                return
            }
            fullExercise = PracticeConfiguration(exercise: exercise, bpm: exercise.bpm, repeats: 8).applying(to: exercise)
        } else {
            guard let exercise = configuredExercise, !exercise.notes.isEmpty else {
                status = "La configuración actual no contiene notas para puntuar."
                return
            }
            fullExercise = exercise
        }
        do { try audio?.start() }
        catch { status = "No se pudo iniciar el audio: \(error.localizedDescription)"; return }
        let exercise: Exercise
        let playerSelection = selectedPlayerSounds
        if calibration || (isFullRhythmSelection && !transferCheck) { exercise = fullExercise }
        else {
            let notes = transferCheck ? fullExercise.notes.filter { $0.sound != "hihat_closed" } : fullExercise.notes.filter { playerSelection.contains($0.sound) }
            guard !notes.isEmpty else { return }
            exercise = Exercise(format: fullExercise.format, id: fullExercise.id, title: fullExercise.title, family: fullExercise.family, level: fullExercise.level, bpm: fullExercise.bpm, meter: fullExercise.meter, bars: fullExercise.bars, grid: fullExercise.grid, repeats: fullExercise.repeats, kit: fullExercise.kit, loop: fullExercise.loop, offset: fullExercise.offset, notes: notes)
        }
        previewToken = UUID()
        previewScene = nil
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        savePreferences()
        calibrating = calibration
        isPracticePaused = false
        let session = PracticeSession(exercise: exercise, calibrationOffsetMilliseconds: calibration ? 0 : calibrationOffset + tuning.manualTimingOffsetMilliseconds, scoringWindows: calibration ? nil : tuning.scoringWindows(bpm: exercise.bpm, grid: exercise.grid))
        // «Anticipación» son compases, no frases enteras. Una frase de
        // redoble puede tener tres compases y no debe convertirse en una
        // espera de seis compases antes de tocar.
        let anticipation = session.timeline.barDurationMilliseconds * Double(tuning.anticipationBars)
        let now = AudioGetCurrentHostTime()
        let start = AudioClock.hostTime(afterMilliseconds: anticipation, from: now)
        practiceVisualID = UUID()
        practice = session; practiceStartHostTime = start; result = ""
        let hiddenGuideNoteIndices = practiceHelp == .reduced
            ? Set(session.timeline.notes.lazy.filter { $0.sound == "hihat_closed" && $0.step.isMultiple(of: 4) }.map(\.index))
            : []
        practiceScene = PracticeScene(timeline: session.timeline, startHostTime: start, anticipationMilliseconds: anticipation, slotBySound: slotsBySound(), soundLabels: soundLabels(), showsSoundLabels: trainingPhase != .transfer && practiceHelp == .full, showsNotes: trainingPhase != .transfer, hiddenGuideNoteIndices: hiddenGuideNoteIndices, emphasizesPlayerNotes: practiceStepRange != nil || !isFullRhythmSelection, playerSounds: isFullRhythmSelection ? nil : playerSelection, gridGuide: gridGuide, viewZoom: practiceViewZoom)
        let isPartialPractice = !isFullRhythmSelection || transferCheck || practiceStepRange != nil
        if !calibration, isPartialPractice {
            let sourceExercise = chosen.map { PracticeConfiguration(exercise: $0, bpm: selectedBPM, repeats: selectedRepeats).applying(to: $0) } ?? fullExercise
            let accompaniment = ExerciseTimeline(exercise: sourceExercise)
            for note in accompaniment.notes where transferCheck ? note.sound == "hihat_closed" : (!isFullRhythmSelection ? !playerSelection.contains(note.sound) : !(practiceStepRange?.contains(note.step) ?? true)) {
                try? audio?.schedule(soundID: note.sound, atHostTime: AudioClock.hostTime(afterMilliseconds: note.timeMilliseconds, from: start))
            }
        }
        let beat = 60_000.0 / Double(exercise.bpm)
        // La claqueta cubre todos los compases de cuenta atrás desde ahora.
        // Así el primer golpe de la frase siempre cae en un inicio de compás.
        let countInStart = 0.0
        let totalMilliseconds = anticipation + session.timeline.patternDurationMilliseconds * Double(exercise.repeats)
        let metronomeBeats = Int(ceil((totalMilliseconds - countInStart) / beat))
        if calibration || metronomeEnabled {
            let clickVolume = calibration ? max(0.65, tuning.countInVolume) : tuning.countInVolume
            for beatIndex in 0...metronomeBeats {
                let countInBeats = Int(anticipation / beat)
                let playedBeat = beatIndex - countInBeats
                let audible: Bool
                if playedBeat < 0 { audible = true }
                else {
                    let bar = playedBeat / 4; let beatInBar = playedBeat % 4
                    switch gapMetronomeLevel {
                    case 1: audible = bar % 4 != 3
                    case 2: audible = bar % 4 < 2
                    case 3: audible = bar % 2 == 0 && beatInBar == 0
                    default: audible = true
                    }
                }
                guard audible else { continue }
                try? audio?.scheduleMetronome(accented: beatIndex.isMultiple(of: 4), atHostTime: AudioClock.hostTime(afterMilliseconds: countInStart + Double(beatIndex) * beat, from: now), volume: Float(clickVolume), pitchCents: Float(tuning.metronomePitchSemitones * 100))
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
    func finishPractice(showsTransition: Bool = true) {
        guard let currentPractice = practice, let exercise = configuredExercise else {
            leaveActiveScreen()
            return
        }
        // Stop every queued click immediately when the player ends a session,
        // including a click scheduled later in the current bar.
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        let score = currentPractice.score
        let completedMicroLessonStage = microLessonStage
        let completedTransferPerformance = performanceTransferActive
        lastExerciseScore = score
        lastHitRecords = HitRecord.records(from: score)
        lastScorePercentage = score.percentage; lastScoreStars = score.stars
        lastTotalHits = score.hits.count
        lastWellTimed = score.perfectCount + score.goodCount
        lastRegular = score.regularCount
        lastWrong = score.misses.count + score.extraCount
        lastPoints = max(0, Double(score.perfectCount) + Double(score.goodCount) * 0.85 + Double(score.regularCount) * 0.7 - Double(score.extraCount) * 0.25)
        lastPossiblePoints = currentPractice.timeline.notes.count
        nextExerciseTitle = nil
        let offset = score.meanOffsetMilliseconds.map { String(format: " · media %.0f ms", $0) } ?? ""
        result = String(format: "Resultado: %.0f %% · %d estrellas · P%d B%d R%d · %d fallos · %d extras%@", score.percentage, score.stars, score.perfectCount, score.goodCount, score.regularCount, score.misses.count, score.extraCount, offset)
        advice = advice(for: score)
        let practiceInsights = PracticeInsights(score: score)
        let median = practiceInsights.medianOffsetMilliseconds.map { String(format: "mediana %.0f ms", $0) } ?? "sin offsets"
        let spread = practiceInsights.medianAbsoluteDeviationMilliseconds.map { String(format: "dispersión %.0f ms", $0) } ?? ""
        insights = "\(practiceInsights.timingLabel) · \(median) \(spread)"
        soundStatistics = practiceInsights.soundStatistics
        if completedMicroLessonStage == .isolating, let focus = microLessonFocusSound,
           let baseline = microLessonBaselineAccuracy,
           let followUp = practiceInsights.soundStatistics.first(where: { $0.sound == focus }) {
            let improvement = followUp.accuracy - baseline
            microLessonFeedback = microLessonBaselineExpected >= 4 && followUp.expected >= 4 && improvement >= 1
                ? "\(displayName(focus)): mejoró \(Int(improvement.rounded())) puntos en esta célula. Ahora prueba el groove completo."
                : "Célula practicada. Aún no hay suficientes golpes comparables para afirmar una mejora; vuelve al groove y escucha cómo encaja."
        } else if completedMicroLessonStage == .integrating,
                  let focus = microLessonFocusSound,
                  let baseline = microLessonBaselineAccuracy,
                  let followUp = practiceInsights.soundStatistics.first(where: { $0.sound == focus }) {
            let improvement = followUp.accuracy - baseline
            microLessonFeedback = microLessonBaselineExpected >= 4 && followUp.expected >= 4 && improvement >= 1
                ? "Lo aplicaste en el groove completo: \(displayName(focus)) mejoró \(Int(improvement.rounded())) puntos."
                : "Has vuelto al patrón completo. Sigue practicando esta entrada con la guía cuando lo necesites."
            microLessonStage = .completed
        }
        if completedTransferPerformance {
            if let baseline = performanceGuidedBaseline,
               performanceGuidedExpected >= 8,
               currentPractice.timeline.notes.count >= 8 {
                let change = score.percentage - baseline
                performanceFeedback = change >= 1
                    ? "Sin guía visual mantuviste el patrón y subiste \(Int(change.rounded())) puntos respecto a la ronda guiada."
                    : change <= -1
                        ? "Ya probaste el patrón sin guía. Puedes volver a la guía completa y repetirlo cuando quieras."
                        : "Mantuviste un resultado similar con menos guía visual. Puedes recuperar la guía en cualquier momento."
            } else {
                performanceFeedback = "Ronda completa sin guía visual. Aún no hay suficientes golpes comparables para valorar una diferencia; puedes volver a la guía cuando quieras."
            }
            performanceTransferActive = false
            if let previous = performancePreviousLoopEnabled {
                loopEnabled = previous
                performancePreviousLoopEnabled = nil
            }
        } else {
            performanceFeedback = ""
        }
        ghostCoachMessage = GhostCoach.cue(score: score, insights: practiceInsights)
        let correctivePlan = chosen.flatMap { WhaleMethod.plan(exercise: $0, score: score) }
        if completedMicroLessonStage != .isolating && completedMicroLessonStage != .integrating {
            lastCorrectivePlan = correctivePlan
            microLessonStage = correctivePlan == nil ? .completed : .suggested
        } else if completedMicroLessonStage == .isolating {
            microLessonStage = .isolating
        }
        whaleMessage = correctivePlan?.message ?? "No hay un error recurrente que aislar ahora."
        let autopilot = PracticeAutopilot.recommend(score: score, insights: practiceInsights, bpm: selectedBPM, repeats: selectedRepeats)
        lastAutopilotRecommendation = autopilot
        autopilotMessage = autopilot.message
        resultSummary = PracticeResultAnalyzer.summarize(score: score, insights: practiceInsights, hasCorrectivePlan: correctivePlan != nil, canAdvance: false)
        // Updating the course can select an exercise. The session must already
        // be closed, otherwise that selection recursively finishes this attempt.
        self.practice = nil; practiceScene = nil; practiceToken = UUID(); isPracticePaused = false
        if calibrating {
            saveCalibration(offsets: score.hits.compactMap(\.offsetMilliseconds))
        } else {
            recordAttempt(exercise: exercise, score: score)
            let canAdvance = isFullRhythmSelection
                && !transferCheck
                && practiceStepRange == nil
                && practiceFragment == 0
                && courseLevels.first(where: { $0.exerciseID == exercise.id })?.chapterAccredited == true
                && nextExerciseTitle != nil
            resultSummary = PracticeResultAnalyzer.summarize(
                score: score,
                insights: practiceInsights,
                hasCorrectivePlan: correctivePlan != nil,
                canAdvance: canAdvance
            )
            if showsTransition { presentResultTransition(percentage: score.percentage) }
            else { showingResults = true }
        }
        calibrating = false
    }
    func applyAutopilot() {
        guard let recommendation = lastAutopilotRecommendation else { return }
        selectedBPM = min(240, max(40, selectedBPM + recommendation.bpmAdjustment))
        selectedRepeats = PracticeConfiguration.normalizedRepeats(recommendation.repeats)
        practiceHelp = recommendation.help
        if let chosen { updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM) }
        savePreferences()
    }
    func startCorrectivePractice() {
        if let plan = lastCorrectivePlan {
            microLessonReturnBPM = selectedBPM
            microLessonReturnRepeats = selectedRepeats
            microLessonFocusSound = plan.focusSound
            if let baseline = soundStatistics.first(where: { $0.sound == plan.focusSound }) {
                microLessonBaselineAccuracy = baseline.accuracy
                microLessonBaselineExpected = baseline.expected
            }
            microLessonFeedback = ""
            microLessonStage = .isolating
            setPlayerSounds([plan.focusSound]); practiceStepRange = plan.stepRange; selectedBPM = plan.bpm; whaleMessage = plan.message
            if let chosen { updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM) }
            whaleTargetMessage = "AHORA TÚ: \(displayName(plan.focusSound)) en la célula difícil. xRoll toca las demás voces como referencia."
        } else if let weakest = soundStatistics.min(by: { $0.accuracy < $1.accuracy }) {
            microLessonReturnBPM = selectedBPM
            microLessonReturnRepeats = selectedRepeats
            microLessonFocusSound = weakest.sound
            microLessonBaselineAccuracy = weakest.accuracy
            microLessonBaselineExpected = weakest.expected
            microLessonFeedback = ""
            microLessonStage = .isolating
            setPlayerSounds([weakest.sound]); practiceStepRange = nil; whaleTargetMessage = "AHORA TÚ: \(displayName(weakest.sound)). xRoll acompaña el resto."
        } else { return }
        trainingPhase = .isolate
        selectedRepeats = 2
        showingResults = false
        beginPractice(calibration: false)
    }
    private func returnToFullGroove() {
        guard microLessonStage == .isolating else { return }
        practiceStepRange = nil
        selectFullRhythm()
        transferCheck = false
        trainingPhase = .integrate
        selectedBPM = microLessonReturnBPM
        if let chosen { updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM) }
        selectedRepeats = microLessonReturnRepeats
        microLessonStage = .integrating
        showingResults = false
        beginPractice(calibration: false)
    }
    func startTransferPerformance() {
        guard chosen != nil else { return }
        performanceComparisonAllowed = loopEnabled
        performanceGuidedBaseline = performanceComparisonAllowed ? lastScorePercentage : nil
        performanceGuidedExpected = lastPossiblePoints
        performancePreviousLoopEnabled = loopEnabled
        if loopTempo != nil { loopEnabled = true }
        performanceTransferActive = true
        selectFullRhythm()
        practiceStepRange = nil
        transferCheck = false
        trainingPhase = .transfer
        showingResults = false
        if !startPractice() {
            performanceTransferActive = false
            if let previous = performancePreviousLoopEnabled { loopEnabled = previous; performancePreviousLoopEnabled = nil }
        }
    }
    func startGuidedPerformance() {
        performanceTransferActive = false
        selectFullRhythm()
        practiceStepRange = nil
        transferCheck = false
        trainingPhase = .integrate
        showingResults = false
        _ = startPractice()
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
            if let selected = audioOutputs.first(where: { $0.uid == selectedAudioOutputUID }) {
                try newAudio.setOutputDevice(selected.deviceID)
                if let frames = savedAudioBufferFrames(for: selected) { try AudioInspector.setBufferFrameSize(frames, for: selected.deviceID) }
            }
            try newAudio.start()
            let router = KitNoteRouter(kit: loaded)
            kit = loaded; audio = newAudio; gm = router; liveMIDI = LiveMIDIProcessor(audio: newAudio, kitRouter: router)
            loadLoop(from: root)
            loadMetronome(from: root)
            progressStore = try ProgressStore(url: applicationSupportURL("progress.sqlite"))
            bundledExercises = try catalog.loadExercises(in: root.appendingPathComponent("data/exercises"), kit: loaded)
            reloadCommunityExercises()
            chosenID = exercises.first?.id ?? ""
            selectedBPM = exercises.first?.bpm ?? 80; selectedRepeats = 8
            loadPreferences()
            if let rawGuide = UserDefaults.standard.object(forKey: "xRoll.gridGuide") as? Int, let guide = GridGuideSubdivision(rawValue: rawGuide) { gridGuide = guide }
            if let rawZoom = UserDefaults.standard.string(forKey: "xRoll.practiceViewZoom"), let zoom = PracticeViewZoom(rawValue: rawZoom) { practiceViewZoom = zoom }
            loadLayoutChoice()
            loadTuning()
            if let rawHelp = UserDefaults.standard.string(forKey: "xRoll.practiceHelp"), let savedHelp = PracticeHelp(rawValue: rawHelp) { practiceHelp = savedHelp }
            showsTrainingPhases = UserDefaults.standard.bool(forKey: "xRoll.showsTrainingPhases")
            restoreLoopSelection()
            kitSoundIDs.forEach { newAudio.setSoundVolume(Float(soundVolume($0)), for: $0) }
            loadKeyboardMap()
            sources = MIDIInspector.sources()
            let savedSourceID = MIDIUniqueID(UserDefaults.standard.integer(forKey: "xRoll.midiSourceID"))
            // The SMC-PAD advertises several CoreMIDI ports. The Bluetooth
            // endpoint is the pad's actual BLE note stream; Master/Private
            // are companion ports and must not silently replace it.
            let bluetoothPad = sources.first(where: { source in
                source.name.localizedCaseInsensitiveContains("smc-pad pocket") && source.name.localizedCaseInsensitiveContains("bluetooth")
            })
            sourceID = bluetoothPad?.uniqueID ?? (sources.contains(where: { $0.uniqueID == savedSourceID })
                ? savedSourceID
                : preferredMIDISource(in: sources)?.uniqueID)
            if let sourceID { UserDefaults.standard.set(Int(sourceID), forKey: "xRoll.midiSourceID") }
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
        var temporaryCopy: URL?
        defer { if let temporaryCopy { try? FileManager.default.removeItem(at: temporaryCopy) } }
        do {
            guard ["mid", "midi"].contains(url.pathExtension.lowercased()) else { throw MIDIExerciseError.invalidFile("elige un archivo .mid o .midi") }
            let directory = applicationSupportURL("community-exercises")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stem = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
            let destination = directory.appendingPathComponent("\(stem.isEmpty ? "ejercicio" : stem)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())")
            try FileManager.default.copyItem(at: url, to: destination)
            temporaryCopy = destination
            let exercise = try MIDIExerciseLoader.load(url: destination, kit: kit, level: bundledExercises.count + 1)
            reloadCommunityExercises()
            temporaryCopy = nil
            let warnings = PedagogicalMIDIValidator.warnings(for: exercise)
            exerciseImportMessage = warnings.isEmpty ? "Importado: \(url.lastPathComponent)." : "Importado: \(url.lastPathComponent). Aviso didáctico: \(warnings.joined(separator: " "))"
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
        if isMappingActiveForMIDI {
            DispatchQueue.main.async { [weak self] in self?.capture(event) }
            return
        }
        guard let liveMIDI else { return }
        do {
            guard let hit = try liveMIDI.process(event) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.presentHit(hit.soundID, position: self.position(for: hit), hostTime: event.hostTime, role: hit.role, padID: hit.padID, velocity: UInt8(clamping: event.velocity))
            }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.status = error.localizedDescription }
        }
    }
    private func loadLoop(from root: URL) {
        let directory = root.appendingPathComponent("Resources/Loops", isDirectory: true)
        loopOptions = LoopLibraryCatalog.discover(in: directory)
        loopStatus = loopOptions.isEmpty ? "No hay loops compatibles incluidos." : "Elige un loop o usa selección automática por estilo y tempo."
    }
    private func loadMetronome(from root: URL) {
        let directory = root.appendingPathComponent("data/metronome", isDirectory: true)
        let accepted = Set(["wav", "aif", "aiff", "caf", "m4a"])
        guard let url = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending })
            .first(where: { accepted.contains($0.pathExtension.lowercased()) }) else {
            metronomeStatus = "Claqueta sintetizada (independiente de los sonidos del kit)"
            return
        }
        do {
            try audio?.loadMetronome(url: url)
            metronomeStatus = "Metrónomo personalizado: \(url.lastPathComponent)"
        } catch {
            metronomeStatus = "No se pudo cargar el metrónomo personalizado: \(error.localizedDescription)"
        }
    }
    func previewMetronome() {
        do {
            try audio?.start()
            try audio?.previewMetronome(volume: Float(tuning.countInVolume), pitchCents: Float(tuning.metronomePitchSemitones * 100))
            metronomeStatus = audio?.metronomeSourceName.map { "Escuchando: \($0)" } ?? "Escuchando metrónomo del kit"
        } catch {
            metronomeStatus = "No se pudo reproducir el metrónomo: \(error.localizedDescription)"
        }
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
        guard let nextSound = Model.keyboardMappingSounds.dropFirst(keyboardCapture.count).first else { return }
        guard keyboardCapture[key] == nil else { keyboardMapMessage = "La tecla (key) ya está asignada. Pulsa otra para (displayName(nextSound))."; return }
        keyboardCapture[key] = nextSound
        let remaining = Model.keyboardMappingSounds.count - keyboardCapture.count
        if remaining == 0 {
            keyboardKeys = keyboardCapture
            saveKeyboardMap()
            keyboardMapping = false
            keyboardCapture = [:]
            keyboardMapMessage = "Teclado guardado. Ya puedes practicar con esas seis teclas."
        } else if let following = Model.keyboardMappingSounds.dropFirst(keyboardCapture.count).first {
            keyboardMapMessage = "\(displayName(nextSound)): \(key). Quedan \(remaining). Pulsa la tecla para \(displayName(following))."
        }
    }
    private func nextPrompt() -> String { builder?.nextStep.map { "Golpea el pad para \($0.sound)." } ?? "" }
    private func mapURL(_ id: Int) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("xRoll/padmaps/\(id).padmap") }
    private func physicalMapURL(_ id: MIDIUniqueID?) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("xRoll/padmaps/\(Int(id ?? 0)).physical.padmap") }
    private func applicationSupportURL(_ file: String) -> URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("xRoll/\(file)") }
    /// Conserva la selección incluso antes de que se aplique. Al aplicar un
    /// layout, el .padmap es la fuente de verdad por dispositivo y también se
    /// sincroniza aquí para que la interfaz se recupere sin parpadeos al abrir.
    func saveLayoutChoice() {
        UserDefaults.standard.set(selectedLayoutPreset.rawValue, forKey: "xRoll.padLayout.preset")
    }
    private func loadLayoutChoice() {
        if let rawPreset = UserDefaults.standard.string(forKey: "xRoll.padLayout.preset"), let preset = PadLayoutPreset(rawValue: rawPreset) {
            selectedLayoutPreset = preset
        }
        UserDefaults.standard.removeObject(forKey: "xRoll.padLayout.orientation")
    }
    private func loadKeyboardMap() {
        let url = applicationSupportURL("keyboard-map.json")
        guard let data = try? Data(contentsOf: url), let map = try? JSONDecoder().decode([String: String].self, from: data), map.count == Model.keyboardMappingSounds.count else { return }
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
        guard let kit else { return }
        let availableSounds = Set(kit.sounds.map(\.id))
        let source = sources.first(where: { $0.uniqueID == id })
        let directURL = mapURL(Int(id))
        var urls = [directURL]
        let directory = directURL.deletingLastPathComponent()
        let olderMaps = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        urls += olderMaps
            .filter { $0.pathExtension == "padmap" && !$0.lastPathComponent.contains(".physical.") && $0 != directURL }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path), let loaded = try? PadMapStore.loadV2(at: url, availableSounds: availableSounds) else { continue }
            // BLE drivers sometimes assign a fresh CoreMIDI unique ID after a
            // reconnection. The user-facing device name is the stable fallback
            // for its saved pad map; once found we migrate it to the new ID.
            guard url == directURL || source.map({ $0.name == loaded.device.name }) == true else { continue }
            let map: PadMapV2
            if loaded.device.uid == Int(id) {
                map = loaded
            } else {
                map = PadMapV2(id: loaded.id, name: loaded.name, preset: loaded.preset, orientation: loaded.orientation, device: .init(name: source?.name ?? loaded.device.name, uid: Int(id)), created: loaded.created, pads: loaded.pads)
                do { try FileManager.default.createDirectory(at: directURL.deletingLastPathComponent(), withIntermediateDirectories: true); try PadMapStore.save(map, to: directURL, availableSounds: availableSounds) }
                catch { status = "No se pudo actualizar el identificador del pad: \(error.localizedDescription)" }
            }
            custom = map
            customRouter = PadMapV2Router(map)
            liveMIDI?.setPadRouter(customRouter)
            // El archivo del pad corresponde al controlador que acabamos de
            // abrir, por lo que prevalece sobre la última selección global.
            // Así la tarjeta marcada describe de verdad el mapa que recibe los
            // golpes MIDI tras reiniciar la aplicación.
            selectedLayoutPreset = map.preset
            saveLayoutChoice()
            return
        }
        custom = nil
        customRouter = nil
        liveMIDI?.setPadRouter(nil)
    }
    private func preferredMIDISource(in available: [MIDIEndpointDescription]) -> MIDIEndpointDescription? {
        available.first(where: { source in
            source.name.localizedCaseInsensitiveContains("smc-pad pocket") && source.name.localizedCaseInsensitiveContains("bluetooth")
        }) ?? available.first(where: { $0.name.localizedCaseInsensitiveContains("Pocket-Private") }) ?? available.first
    }
    private func loadPhysicalMap(_ id: MIDIUniqueID?) -> PadMapV2? {
        guard let kit else { return nil }
        return try? PadMapStore.loadV2(at: physicalMapURL(id), availableSounds: Set(kit.sounds.map(\.id)))
    }
    private func savePhysicalMap(_ map: PadMapV2) {
        guard let kit else { return }
        let url = physicalMapURL(MIDIUniqueID(map.device.uid))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PadMapStore.save(map, to: url, availableSounds: Set(kit.sounds.map(\.id)))
        } catch { mapMessage = "No se pudo preservar el mapa físico: \(error.localizedDescription)" }
    }
    private func save(_ map: PadMap) {
        guard let kit else { return }
        do { let v2 = PadMapV2(migrating: map); let url = mapURL(map.deviceUID); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try PadMapStore.save(v2, to: url, availableSounds: Set(kit.sounds.map(\.id))); savePhysicalMap(v2); custom = v2; customRouter = PadMapV2Router(v2); liveMIDI?.setPadRouter(customRouter); selectedLayoutPreset = v2.preset; saveLayoutChoice(); setMapping(false); builder = nil; mapMessage = "Mapa físico guardado en formato v2." } catch { mapMessage = error.localizedDescription }
    }
    private func save(_ map: PadMapV2) {
        guard let kit else { return }
        do { let url = mapURL(map.device.uid); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try PadMapStore.save(map, to: url, availableSounds: Set(kit.sounds.map(\.id))); custom = map; customRouter = PadMapV2Router(map); liveMIDI?.setPadRouter(customRouter); selectedLayoutPreset = map.preset; saveLayoutChoice(); setMapping(false); builder = nil; mapMessage = "Layout \(map.name) guardado en formato v2." } catch { mapMessage = error.localizedDescription }
    }
    private func trigger(_ pad: PadPosition) { if let sound = name(pad) { play(sound, position: pad, volume: 0.85) } }
    private func position(_ sound: String) -> PadPosition? {
        if let pad = custom?.pads.first(where: { $0.sound == sound }) { return positions.first { $0.row == pad.row && $0.column == pad.column } }
        return kit.flatMap { kit in kit.sounds.first(where: { $0.id == sound }).flatMap { note in positions.first { $0.note == note.gmNote } } }
    }
    private func position(for hit: LiveMIDIHit) -> PadPosition? {
        guard let row = hit.row, let column = hit.column else { return position(hit.soundID) }
        return positions.first { $0.row == row && $0.column == column }
    }
    private func play(_ sound: String, position: PadPosition?, hostTime: UInt64 = AudioGetCurrentHostTime(), volume: Float = 1, role: String? = nil, padID: String? = nil, velocity: UInt8? = nil) {
        guard let audio, !isPracticePaused else { return }
        do {
            try audio.play(soundID: sound, volume: volume)
            presentHit(sound, position: position, hostTime: hostTime, role: role, padID: padID, velocity: velocity)
        } catch { status = error.localizedDescription }
    }
    private func presentHit(_ sound: String, position: PadPosition?, hostTime: UInt64, role: String?, padID: String?, velocity: UInt8?) {
        record(sound, hostTime: hostTime, role: role, padID: padID, velocity: velocity)
        // En práctica el feedback pertenece a SpriteKit; publicar el destello de
        // la rejilla oculta solo invalida SwiftUI sin aportar información visible.
        guard practiceScene == nil, previewScene == nil, let position else { return }
        let key = "\(position.row):\(position.column)"
        let flashDuration = Double(tuning.padFlashMilliseconds) / 1_000
        active.insert(key)
        DispatchQueue.main.asyncAfter(deadline: .now() + flashDuration) { [weak self] in self?.active.remove(key) }
    }
    private var isMappingActiveForMIDI: Bool {
        mappingStateLock.lock()
        defer { mappingStateLock.unlock() }
        return mappingActiveForMIDI
    }
    private func setMapping(_ active: Bool) {
        mappingStateLock.lock()
        mappingActiveForMIDI = active
        mappingStateLock.unlock()
        mapping = active
    }
    private func slotsBySound() -> [String: Int] {
        var result: [String: Int] = [:]
        // The falling-note view has one lane per sound. With duplicate pads,
        // choose the lowest-numbered physical pad as a stable reference while
        // the router/scorer accepts every duplicate pad for that sound.
        for pad in positions.sorted(by: { $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row }) {
            if let sound = name(pad), result[sound] == nil { result[sound] = pad.row * 4 + pad.column }
        }
        return result
    }
    private func soundLabels() -> [String: String] {
        Dictionary(uniqueKeysWithValues: kit?.sounds.map { ($0.id, $0.label) } ?? [])
    }
    private func record(_ sound: String, hostTime: UInt64, role: String? = nil, padID: String? = nil, velocity: UInt8? = nil) {
        guard practice != nil, !isPracticePaused else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isPracticePaused, let current = self.practice else { return }
            guard let judged = current.registerIfScorable(.init(sound: sound, hostTime: hostTime, practiceStartHostTime: self.practiceStartHostTime, role: role, padID: padID, velocity: velocity)) else {
                self.practiceScene?.showWarmupHit(sound: sound)
                return
            }
            guard let offset = judged.offsetMilliseconds else {
                self.practiceScene?.showFeedback(sound: sound, judgement: .extra)
                return
            }
            let feedbackSound = judged.expectedNote?.sound ?? sound
            self.practiceScene?.showFeedback(sound: feedbackSound, judgement: judged.judgement, noteIndex: judged.expectedNote?.index, offsetMilliseconds: offset)
        }
    }
    private func profileKey() -> CalibrationProfileKey {
        let output = selectedAudioOutputUID
            .flatMap { uid in audioOutputs.first(where: { $0.uid == uid }) }
            .map { AudioInspector.output(deviceID: $0.deviceID) }
            ?? AudioInspector.currentOutput()
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
        guard let profiles = try? CalibrationProfileStore.load(from: url), let profile = profiles.first(where: { $0.key == profileKey() }) else { calibrationOffset = 0; calibrationProfileKey = nil; calibrationMessage = "Sin calibración para este perfil."; return }
        calibrationOffset = profile.offsetMilliseconds
        calibrationProfileKey = profile.key
        calibrationMessage = String(format: "Compensación guiada activa: %.0f ms", calibrationOffset)
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
            calibrationProfileKey = profile.key
            calibrationMessage = String(format: "Calibrado: %.0f ms, dispersión %.0f ms", estimate.offsetMilliseconds, estimate.medianAbsoluteDeviationMilliseconds)
        } catch { calibrationMessage = "Calibracion incompleta: \(error.localizedDescription)" }
    }
    private func recordAttempt(exercise: Exercise, score: ExerciseScore) {
        do {
            let soundStatistics = PracticeInsights(score: score).soundStatistics
            let hitRecords = HitRecord.records(from: score)
            let scope: EvaluationScope
            if practiceStepRange != nil { scope = trainingPhase == .isolate ? .corrective : .fragment }
            else if practiceFragment != 0 { scope = .fragment }
            else if !isFullRhythmSelection || transferCheck { scope = .selectedVoices }
            else { scope = .fullPattern }
            let context = TrainingContext(phase: trainingPhase, gapMetronomeLevel: gapMetronomeLevel, showsVisualGuides: trainingPhase != .transfer, evaluationScope: scope, completedBars: exercise.bars * exercise.repeats)
            try progressStore?.record(PracticeAttempt(exerciseID: exercise.id, timestamp: Date(), bpm: exercise.bpm, score: score.percentage, stars: score.stars, perfect: score.perfectCount, good: score.goodCount, regular: score.regularCount, miss: score.misses.count, extra: score.extraCount, meanOffsetMilliseconds: score.meanOffsetMilliseconds, soundStatistics: soundStatistics, hitRecords: hitRecords, trainingContext: context))
            refreshProgress(for: exercise.id)
            refreshRecentAttempts()
            refreshCourseLevels()
            if scope == .fullPattern, score.percentage >= 70, exercise.bpm == 100,
               courseLevels.first(where: { $0.exerciseID == exercise.id })?.chapterAccredited == true {
                result += " · Estación acreditada"
                nextExerciseTitle = courseRecommendation.flatMap { recommendation in
                    exercises.first(where: { $0.id == recommendation.exerciseID })?.title
                }
            }
        } catch { progress = "No se pudo guardar el intento: \(error.localizedDescription)" }
    }
    func chooseExercise(_ exercise: Exercise) {
        cancelResultTransition()
        if practice != nil { finishPractice(showsTransition: false) }
        audio?.stopScheduledSounds(); audio?.stopLoop(); practiceToken = UUID(); previewToken = UUID(); practiceScene = nil; previewScene = nil
        showingResults = false; courseTitleOverride = nil; chosenID = exercise.id; selectedRepeats = defaultRepeats(for: exercise); preview = ""
        microLessonStage = .completed; microLessonFocusSound = nil; microLessonBaselineAccuracy = nil; microLessonBaselineExpected = 0
        lastCorrectivePlan = nil; microLessonFeedback = ""; performanceFeedback = ""
        performanceTransferActive = false; performanceGuidedBaseline = nil; performanceGuidedExpected = 0; performancePreviousLoopEnabled = nil; performanceComparisonAllowed = false
        selectPendingTempo(for: exercise)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        practiceStepRange = nil; selectFullRhythm()
        savePreferences(); refreshProgress(for: exercise.id)
    }
    /// Un escalón exige el mismo alcance y la misma duración que su premio;
    /// dos estrellas en una práctica parcial no lo dan por terminado.
    private func selectPendingTempo(for exercise: Exercise) {
        let steps = TempoLadder.steps(for: exercise)
        guard let step = TempoLadder.nextStep(for: exercise, evidence: courseEvidence) ?? steps.last else { return }
        selectedBPM = step.bpm
        selectedTempoTier = steps.firstIndex(where: { $0.bpm == step.bpm }) ?? 0
        selectedRepeats = TempoLadder.repeats(for: step, exercise: exercise) ?? defaultRepeats(for: exercise)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
    }
    func pendingTempoBPM(for exerciseID: String) -> Int? {
        guard let exercise = exercises.first(where: { $0.id == exerciseID }) else { return nil }
        return (TempoLadder.nextStep(for: exercise, evidence: courseEvidence)
            ?? TempoLadder.steps(for: exercise).last)?.bpm
    }
    func pendingRepeats(for plan: NextSessionPlan) -> Int {
        guard let exercise = exercises.first(where: { $0.id == plan.exerciseID }),
              let bpm = pendingTempoBPM(for: exercise.id) else { return plan.repeats }
        let minimum = TempoLadder.steps(for: exercise).first(where: { $0.bpm == bpm })
            .flatMap { TempoLadder.repeats(for: $0, exercise: exercise) } ?? 1
        return max(plan.repeats, minimum)
    }
    func openPreparation(_ exercise: Exercise? = nil) {
        if let exercise { chooseExercise(exercise) }
        else if let chosen {
            selectPendingTempo(for: chosen)
            updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM)
        }
        guard chosen != nil else { return }
        showingPreparation = true
    }

    func openCheckpointAssessment(_ exercise: Exercise) {
        guard exercise.metadata?.flags.contains("checkpoint") == true else { return }
        chooseExercise(exercise)
        selectedBPM = CourseLessonCriteria.targetBPM(for: exercise)
        selectedTempoTier = tempoPracticeOptions.firstIndex(where: { $0.bpm == selectedBPM }) ?? 0
        selectedRepeats = defaultRepeats(for: exercise)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        trainingPhase = .integrate
        practiceStepRange = nil
        transferCheck = false
        selectFullRhythm()
        savePreferences()
        preview = "Prueba del bloque · ritmo completo a \(selectedBPM) BPM y al menos 70 %."
        showingPreparation = true
    }
    func openNextSession() {
        guard let plan = nextSessionPlan, let exercise = exercises.first(where: { $0.id == plan.exerciseID }) else { return }
        chooseExercise(exercise)
        selectedRepeats = pendingRepeats(for: plan)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        transferCheck = false
        selectFullRhythm()
        savePreferences()
        showingPreparation = true
    }
    func selectPreparationExercise(_ exercise: Exercise) {
        microLessonStage = .completed; microLessonFocusSound = nil; microLessonBaselineAccuracy = nil
        microLessonBaselineExpected = 0; lastCorrectivePlan = nil; microLessonFeedback = ""; performanceFeedback = ""
        courseTitleOverride = nil; chosenID = exercise.id; selectedRepeats = defaultRepeats(for: exercise); preview = ""
        selectPendingTempo(for: exercise)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        practiceStepRange = nil; selectFullRhythm(); savePreferences(); refreshProgress(for: exercise.id)
    }
    /// La portada del curso siempre abre el groove completo del bloque. Sus
    /// capas internas sustituyen a las antiguas tarjetas descompuestas.
    func openCompleteRhythm(_ exercise: Exercise, title: String) {
        leaveActiveScreen()
        microLessonStage = .completed; microLessonFocusSound = nil; microLessonBaselineAccuracy = nil
        microLessonBaselineExpected = 0; lastCorrectivePlan = nil; microLessonFeedback = ""; performanceFeedback = ""
        courseTitleOverride = title; chosenID = exercise.id; selectedRepeats = defaultRepeats(for: exercise); preview = ""; selectFullRhythm()
        selectPendingTempo(for: exercise)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        savePreferences(); refreshProgress(for: exercise.id); showingPreparation = true
    }
    func startFromPreparation() {
        switch trainingPhase {
        case .discover:
            showingPreparation = false
            previewExercise()
        case .isolate:
            if isFullRhythmSelection, let weakest = soundStatistics.min(by: { $0.accuracy < $1.accuracy }) { setPlayerSounds([weakest.sound]) }
            selectedBPM = max(40, Int((Double(selectedBPM) * 0.8).rounded()))
            if let chosen { updateAutomaticLoopSelection(for: chosen, targetBPM: selectedBPM) }
            selectedRepeats = 2
            if startPractice() { showingPreparation = false }
        case .integrate:
            transferCheck = false; selectFullRhythm()
            if startPractice() { showingPreparation = false }
        case .transfer:
            selectFullRhythm(); transferCheck = true
            if startPractice() { showingPreparation = false }
        }
    }
    func dismissPreparation() { showingPreparation = false }
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
        exercises.contains(where: { $0.id == exercise.id })
    }
    /// Mantiene una sesión inicial cerca de ocho compases aunque el archivo
    /// sea una frase de dos, tres o cuatro compases. El selector conserva
    /// potencias de dos para que la duración siga siendo predecible.
    private func defaultRepeats(for exercise: Exercise) -> Int {
        Model.repeatOptions.last(where: { $0 * exercise.bars <= 8 }) ?? 1
    }
    func levelStatus(_ exercise: Exercise) -> String {
        switch courseLevels.first(where: { $0.exerciseID == exercise.id })?.status {
        case .mastered: return "✓"
        case .locked: return "🔒"
        default: return ""
        }
    }
    func chapterIsAccredited(_ exercises: [Exercise]) -> Bool {
        !exercises.isEmpty && exercises.allSatisfy { exercise in
            courseLevels.first(where: { $0.exerciseID == exercise.id })?.chapterAccredited == true
        }
    }
    private func refreshCourseLevels() {
        let attempts = (try? progressStore?.attempts(filter: .init(), limit: 1_000)) ?? []
        courseEvidence = (try? progressStore?.courseEvidence()) ?? []
        if let graph = try? CourseGraph(exercises: bundledExercises) {
            courseLevels = graph.states(evidence: courseEvidence)
        } else {
            courseLevels = CourseProgress.states(exercises: bundledExercises, attempts: attempts)
        }
        if let chosen = chosen, !isAvailable(chosen), let first = exercises.first(where: isAvailable) {
            chosenID = first.id; selectedBPM = first.bpm; selectedRepeats = first.repeats; preview = ""
            savePreferences(); refreshProgress(for: first.id)
        }
        refreshNextSessionPlan()
    }
    private func refreshNextSessionPlan() {
        nextSessionPlan = NextSessionPlanner.plan(exercises: exercises, courseLevels: courseLevels, attempts: unfilteredRecentAttempts, eligibleExerciseIDs: Set(bundledExercises.map(\.id)))
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
        if let tier = tempoPracticeOptions.firstIndex(where: { $0.bpm == selectedBPM }) { selectedTempoTier = tier }
    }
    func saveTuning() { try? PracticeTuningStore.save(tuning, to: applicationSupportURL("tuning.json")) }
    func resetTuning() { tuning = PracticeTuning(); resetSoundMix(); saveTuning() }
    private func loadTuning() {
        let loaded = (try? PracticeTuningStore.load(from: applicationSupportURL("tuning.json"))) ?? PracticeTuning()
        tuning = loaded
    }
    func refreshRecentAttempts() {
        do {
            unfilteredRecentAttempts = try progressStore?.attempts(filter: .init(), limit: 100) ?? []
            let filter: ProgressFilter
            switch progressFilter {
            case 1: filter = .init(maximumScore: 74.999)
            case 2: filter = .init(minimumScore: 70)
            default: filter = .init()
            }
            recentAttempts = try progressStore?.attempts(filter: filter, limit: 1_000) ?? []
            let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
            historicalDiagnostics = HistoricalDiagnosticsBuilder.build(attempts: recentAttempts, exercisesByID: byID)
            if let chosen { masterySeals = MasteryEvaluator.seals(exercise: chosen, attempts: try progressStore?.attempts(filter: .init(exerciseID: chosen.id), limit: 1_000) ?? []) }
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
                VStack(spacing: 4) {
                    Text(model.displayName(name)).font(.subheadline.bold()).lineLimit(1)
                    Text(model.midiLabel(for: pad)).font(.caption2.bold()).opacity(0.76)
                    Text("Tecla \(model.keyboardLabel(for: pad))").font(.caption2).opacity(0.56)
                }
                    .frame(maxWidth: .infinity, minHeight: 76).background(active ? Color.white.opacity(0.95) : padColor(for: name)).foregroundColor(active ? .black : (name == nil ? .white.opacity(0.38) : .white)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Color.white : Color.white.opacity(name == nil ? 0.08 : 0.18), lineWidth: active ? 3 : 1))
                    .accessibilityElement(children: .ignore).accessibilityLabel(name.map { "Pad \($0), tecla \(model.keyboardLabel(for: pad))" } ?? "Pad sin asignar, tecla \(model.keyboardLabel(for: pad))")
            }
        }
    }

    private func padColor(for sound: String?) -> Color {
        switch sound {
        case "kick": return Color(red: 0.05, green: 0.53, blue: 0.57)
        case "rim": return Color(red: 0.55, green: 0.40, blue: 0.18)
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
            .accessibilityLabel("Ejercicio \(exercise.level): \(exercise.title), \(available ? "se puede practicar" : "no disponible en este catálogo")")
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
                                VStack(alignment: .leading, spacing: 4) { Text("LISTO PARA TOCAR").font(.caption.bold()).foregroundColor(.cyan); Text(model.currentExerciseTitle).font(.title2.bold()); Text(model.preview.isEmpty ? "Escucha el patrón o empieza cuando quieras." : model.preview).font(.caption).foregroundColor(.white.opacity(0.58)) }
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
                            Stepper("Tempo", value: $model.selectedBPM, in: 40...240, step: 5).onChange(of: model.selectedBPM) { _ in
                                model.refreshAutomaticLoopForSelection()
                                model.savePreferences()
                            }
                            Divider().overlay(Color.white.opacity(0.16)).padding(.vertical, 5)
                            Text("\(model.selectedRepeats) vueltas").font(.headline)
                            Stepper("Duración", value: Binding(
                                get: { Model.repeatOptions.firstIndex(of: model.selectedRepeats) ?? 0 },
                                set: { model.setRepeats(Model.repeatOptions[$0]) }
                            ), in: 0...(Model.repeatOptions.count - 1))
                            Button("Escuchar y colocar") { model.previewExercise() }.padding(.top, 7)
                            ActionButton("Calibración guiada", prominence: model.hasCalibrationForCurrentProfile ? .secondary : .primary) { model.startCalibration() }
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
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.04, blue: 0.09), Color(red: 0.075, green: 0.025, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DEMOSTRACIÓN GUIADA").font(.caption.bold()).foregroundColor(.cyan)
                        Text(model.currentExerciseTitle).font(.title2.bold())
                        Text("Observa una vuelta: aquí no se puntúa ningún golpe.").font(.caption).foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    ActionButton("Volver", prominence: .secondary) { model.stopPreview() }
                    ActionButton("Empezar a tocar", prominence: .primary) { model.stopPreview(); model.startPractice() }
                }
                SpriteView(scene: scene)
                StagePanel {
                    HStack(spacing: 5) {
                        Text("CÓMO USARLO").font(.caption.bold()).foregroundColor(.cyan)
                        ContextInfoButton(title: "Demostración guiada", detail: "xRoll toca el patrón para que observes los carriles y escuches la relación entre los sonidos. Aquí no tienes que golpear nada ni se registra una puntuación.")
                    }
                    Text("Mira qué carril llega a la línea y escucha cómo encajan los golpes. Cuando lo tengas claro, pulsa Empezar a tocar.")
                        .font(.subheadline).foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(24).foregroundColor(.white)
        }
        .onAppear { scene.setReducesMotion(reducesMotion) }
        .onChange(of: reducesMotion) { scene.setReducesMotion($0) }
    }
}

private struct PracticeRun: View {
    @ObservedObject var model: Model
    let scene: PracticeScene
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("EN DIRECTO").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2).foregroundColor(StudioDesign.accent)
                        Text(model.currentExerciseTitle).font(.headline.weight(.semibold)).foregroundColor(StudioDesign.textPrimary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(model.selectedBPM) BPM · \(model.selectedRepeats) vueltas")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(StudioDesign.textSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(StudioDesign.surfaceRaised, in: Capsule())
                    ActionButton("Pausar", prominence: .secondary) { model.pausePractice() }
                }
                if model.practiceStepRange != nil || !model.isFullRhythmSelection {
                    Text(model.whaleTargetMessage.isEmpty ? "Tú: \(model.selectedPlayerSounds.map(model.displayName).sorted().joined(separator: " y ")) · gris: acompañamiento" : model.whaleTargetMessage)
                        .font(.caption.weight(.semibold)).foregroundColor(StudioDesign.regular).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                ZStack(alignment: .top) {
                    SpriteView(scene: scene).id(model.practiceVisualID)
                    if model.isPracticePaused {
                        ZStack {
                            Color.black.opacity(0.68)
                            VStack(spacing: 14) {
                                Image(systemName: "pause.circle.fill").font(.system(size: 42)).foregroundColor(StudioDesign.accent)
                                Text("Práctica en pausa").font(.title2.bold())
                                Text("Al reanudar, el intento comenzará de nuevo con la cuenta de entrada para mantener audio, notas y puntuación sincronizados.")
                                    .font(.subheadline).foregroundColor(StudioDesign.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                                HStack(spacing: 10) {
                                    ActionButton("Terminar sesión", prominence: .secondary) { model.leaveActiveScreen() }
                                    ActionButton("Reanudar desde el inicio", prominence: .primary) { model.resumePractice() }
                                }
                            }
                            .padding(28)
                            .background(StudioDesign.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(StudioDesign.accent.opacity(0.22), lineWidth: 1))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
        }.foregroundColor(.white)
        .onAppear { scene.setReducesMotion(reducesMotion) }
        .onChange(of: reducesMotion) { scene.setReducesMotion($0) }
    }
}

private struct ProgressHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
        StudioDesign.canvas.ignoresSafeArea()
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Text("Análisis de práctica").font(.largeTitle.bold())
                ContextInfoButton(title: "Análisis de práctica", detail: "Esta pantalla reúne sesiones que ya has terminado. Úsala para descubrir qué repetir; no hace falta interpretar todos los números para avanzar en el curso.")
            }
            Text("Tu resumen de sesiones terminadas: qué practicaste, cómo salió y qué conviene repetir. Los datos aparecen después de completar ejercicios.").foregroundColor(.white.opacity(0.65))
            Picker("Mostrar", selection: $model.progressFilter) { Text("Todos").tag(0); Text("Para consolidar").tag(1); Text("70 % o más").tag(2) }.pickerStyle(.segmented).frame(width: 460).onChange(of: model.progressFilter) { _ in model.refreshRecentAttempts() }
            HStack(spacing: 12) {
                ProgressMetric(title: "INTENTOS", value: "\(model.recentAttempts.count)", detail: "sesiones en el filtro elegido", tint: StudioDesign.accent, info: "Cada intento es un ejercicio que terminaste. Usa el filtro para ver todo, los que conviene consolidar o solo los superados.")
                ProgressMetric(title: "MEDIA", value: model.analysisAverageScore.map { "\(Int($0.rounded())) %" } ?? "—", detail: "media de puntuación", tint: StudioDesign.accent, info: "Es la media de los intentos mostrados, no una nota de nivel. Mira también la tendencia y repite un ritmo si quieres mejorarla.")
                ProgressMetric(title: "PULSO", value: model.analysisTiming, detail: "tendencia de llegada", tint: StudioDesign.regular, info: "Indica si en conjunto sueles golpear antes, centrado o después del pulso. No es un error grave: sirve para decidir qué corregir primero.")
            }
            HStack(spacing: 12) {
                StagePanel { HStack(spacing: 5) { Text("SONIDO A REFORZAR").font(.studioLabel).foregroundColor(StudioDesign.accent); ContextInfoButton(title: "Sonido a reforzar", detail: "Es el sonido con más margen de mejora en tus intentos recientes. Practícalo dentro del ritmo con la opción “Línea de…” en Preparación.") }; Text(model.analysisWeakestSound).font(.title3.bold()); Text("Se calcula con aciertos y fallos de las prácticas registradas desde esta versión.").font(.caption2).foregroundColor(StudioDesign.textSecondary) }
                StagePanel { HStack(spacing: 5) { Text("MÁS PRACTICADO").font(.studioLabel).foregroundColor(StudioDesign.accent); ContextInfoButton(title: "Más practicado", detail: "Es el ejercicio que más has terminado. Alternar un repaso con un ritmo nuevo suele dar mejores resultados que repetir siempre el mismo.") }; Text(model.analysisMostPracticed).font(.title3.bold()).lineLimit(2); Text("Útil para alternar repaso y contenido nuevo.").font(.caption2).foregroundColor(StudioDesign.textSecondary) }
            }
            if let diagnostics = model.historicalDiagnostics, let priority = diagnostics.priority {
                StagePanel {
                    HStack(spacing: 5) { Text("DIAGNÓSTICO HISTÓRICO").font(.studioLabel).foregroundColor(StudioDesign.accent); ContextInfoButton(title: "Diagnóstico histórico", detail: "Busca patrones que se repiten entre sesiones: una subdivisión, una mano o el paso de un sonido a otro. La prioridad es la pista más útil para tu próxima práctica.") }
                    Text("Prioridad: \(priority.label) · \(Int(priority.accuracy.rounded())) % · \(priority.timingLabel)").font(.headline)
                    HStack(spacing: 14) { DiagnosticList(title: "Subdivisión", items: diagnostics.bySubdivision); DiagnosticList(title: "Mano", items: diagnostics.byHand); DiagnosticList(title: "Transición", items: diagnostics.byTransition) }
                }
            }
            HStack(spacing: 10) {
                ActionButton("Exportar CSV") { model.exportProgress(format: "csv") }
                ActionButton("Exportar JSON") { model.exportProgress(format: "json") }
            }
            Text(model.exportMessage).font(.caption).foregroundColor(.white.opacity(0.65))
            StagePanel {
                HStack(spacing: 5) { Text("HISTORIAL RECIENTE").font(.studioLabel).foregroundColor(StudioDesign.accent); ContextInfoButton(title: "Historial reciente", detail: "Cada fila muestra: nombre del ritmo, tempo, puntuación, estrellas y desviación media en milisegundos. Un valor negativo llegó antes; uno positivo, después.") }
                if model.recentAttempts.isEmpty { Text("Aquí aparecerán tus intentos al terminar una práctica.").foregroundColor(.white.opacity(0.65)) }
                else { ForEach(Array(model.recentAttempts.prefix(12).enumerated()), id: \.offset) { _, attempt in HStack { Text(model.exercises.first(where: { $0.id == attempt.exerciseID })?.title ?? attempt.exerciseID).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1); Text("\(attempt.bpm) BPM").frame(width: 70, alignment: .leading); Text(String(format: "%.0f %%", attempt.score)).frame(width: 55, alignment: .leading).foregroundColor(attempt.score >= 70 ? StudioDesign.accent : StudioDesign.regular); Text("★ \(attempt.stars)").frame(width: 40, alignment: .leading); Text(attempt.meanOffsetMilliseconds.map { String(format: "%+.0f ms", $0) } ?? "—").font(.caption).foregroundColor(StudioDesign.textSecondary).frame(width: 58, alignment: .trailing) }.padding(.vertical, 4) } }
            }
            Spacer()
        }.foregroundColor(.white).padding(28).frame(minWidth: 720, minHeight: 520, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct ProgressMetric: View {
    let title: String; let value: String; let detail: String; let tint: Color; let info: String
    var body: some View {
        StagePanel { HStack(spacing: 5) { Text(title).font(.studioLabel).foregroundColor(tint); ContextInfoButton(title: title.capitalized, detail: info) }; Text(value).font(.title3.bold()).lineLimit(2); Text(detail).font(.caption2).foregroundColor(StudioDesign.textSecondary) }
    }
}

private struct DiagnosticList: View {
    let title: String; let items: [HistoricalDiagnostic]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundColor(StudioDesign.textMuted)
            if let item = items.first { Text("\(item.label) · \(Int(item.accuracy.rounded())) %").font(.caption).foregroundColor(StudioDesign.textPrimary); Text(item.timingLabel).font(.caption2).foregroundColor(StudioDesign.textSecondary) }
            else { Text("Aún sin datos").font(.caption).foregroundColor(StudioDesign.textSecondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BluetoothMIDIPanel: View {
    @ObservedObject var model: Model
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Pads Bluetooth MIDI", systemImage: "dot.radiowaves.left.and.right")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                ActionButton("↻ Buscar pads", prominence: .secondary) { model.refreshBluetoothMIDIDevices() }
            }
            Text(model.bluetoothMIDIStatus)
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))

            if !model.bluetoothMIDIDirectConnectionSupported {
                HStack {
                    Text("macOS 12: enlaza el pad en el sistema y luego vuelve aquí.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Spacer()
                    ActionButton("Abrir Audio MIDI Setup", prominence: .secondary) { model.openAudioMIDISetup() }
                }
            }

            if model.bluetoothMIDIDevices.isEmpty {
                Text("Enciende el pad y pulsa Buscar pads. Solo se muestran controladores Bluetooth LE MIDI; no auriculares ni dispositivos de audio.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.58))
            } else {
                ForEach(model.bluetoothMIDIDevices) { device in
                    HStack(spacing: 9) {
                        Image(systemName: device.state == .connected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                            .foregroundColor(device.state == .connected ? StudioDesign.accent : .cyan)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name).font(.subheadline.weight(.semibold))
                            Text(device.state.label).font(.caption2).foregroundColor(.white.opacity(0.58))
                        }
                        Spacer()
                        if device.state == .connected {
                            ActionButton("Desconectar", prominence: .secondary) { model.disconnectBluetoothMIDI() }
                        } else if model.bluetoothMIDIDirectConnectionSupported {
                            ActionButton(device.state == .connecting ? "Conectando…" : "Conectar", prominence: .secondary) { model.connectBluetoothMIDI(device) }
                                .disabled(device.state == .connecting)
                        } else {
                            Text("Conecta en el sistema")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.52))
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Text("Al conectar, espera un instante y selecciónalo arriba en «Entrada MIDI». En macOS 12 abre Audio MIDI Setup, conecta el pad en su ventana Bluetooth MIDI y vuelve a pulsar ↻ Refrescar.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.52))
        }
    }
}

private struct LayoutPresetChooser: View {
    @Binding var selection: PadLayoutPreset
    let onUse: (PadLayoutPreset) -> Void

    private let presets: [(PadLayoutPreset, String, String)] = [
        (.core, "xRoll Core", "Aprendizaje: bombo, caja y charles con espacio alrededor."),
        (.drumKit, "Drum Kit", "Dos bombos, dos cajas y dos charles para tocar más rápido."),
        (.mirror, "Simétrico", "Distribución espejo para alternar manos con comodidad.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(presets, id: \.0) { preset, title, detail in
                let active = selection == preset
                Button { selection = preset; onUse(preset) } label: {
                    HStack(spacing: 12) {
                        LayoutPresetPreview(preset: preset)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.subheadline.bold()).foregroundColor(.white)
                            Text(detail).font(.caption2).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(active ? StudioDesign.accent : StudioDesign.textMuted)
                    }
                    .padding(9)
                    .background(active ? StudioDesign.accent.opacity(0.13) : Color.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(active ? StudioDesign.accent.opacity(0.8) : Color.white.opacity(0.10), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LayoutPresetPreview: View {
    let preset: PadLayoutPreset
    private let columns = Array(repeating: GridItem(.fixed(17), spacing: 2), count: 4)
    private var pads: [String: String] {
        let map = PadLayoutFactory.make(preset, device: .init(name: "Vista", uid: 0))
        return Dictionary(uniqueKeysWithValues: map.pads.map { ("\($0.row):\($0.column)", $0.sound) })
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<16, id: \.self) { index in
                let sound = pads["\(index / 4):\(index % 4)"]
                RoundedRectangle(cornerRadius: 3)
                    .fill(layoutColor(sound).opacity(sound == nil ? 0.16 : 0.92))
                    .frame(width: 17, height: 17)
            }
        }
        .frame(width: 74)
        .accessibilityLabel("Vista 4 por 4 del layout")
    }

    private func layoutColor(_ sound: String?) -> Color {
        switch sound {
        case "kick": return .green
        case "snare", "rim", "clap": return .pink
        case "hihat_closed", "hihat_open", "ride", "crash": return .cyan
        case "tom_low", "tom_high": return .orange
        default: return Color.white
        }
    }
}

private struct MappingHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
        StudioDesign.canvas.ignoresSafeArea()
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Configura tus pads").font(.largeTitle.bold())
                Text("Aprende los 16 pads físicos una vez; después podrás cambiar su distribución sin cambiar sus notas MIDI.").foregroundColor(.white.opacity(0.65))
                StagePanel {
                    Text("1. Selecciona tu dispositivo MIDI o pads").font(.headline)
                    Picker("Entrada MIDI", selection: $model.sourceID) { Text("Sin entrada").tag(MIDIUniqueID?.none); ForEach(model.sources, id: \.uniqueID) { Text($0.name).tag(Optional($0.uniqueID)) } }.onChange(of: model.sourceID) { _ in model.selectSource() }
                    HStack {
                        Text(model.sources.isEmpty ? "No se detecta ningún dispositivo. Conéctalo, espera unos segundos y pulsa Buscar MIDI." : "Elige el dispositivo que quieras usar. Los cambios se detectan al refrescar.")
                            .font(.caption).foregroundColor(.white.opacity(0.65))
                        Spacer()
                        ActionButton("↻ Buscar MIDI", prominence: .secondary) { model.refreshMIDIDevices() }
                    }
                    BluetoothMIDIPanel(model: model, compact: true)
                    Text("2. Pulsa empezar y golpea los 16 pads que te indique xRoll.").font(.headline).padding(.top, 8)
                    ActionButton(model.mapping ? "Cancelar asignación" : "Empezar asignación", prominence: model.mapping ? .secondary : .primary) { model.mapping ? model.cancelMapping() : model.startMapping() }
                        .disabled(model.sourceID == nil)
                        .padding(.top, 4)
                    if model.mapping { Button("Omitir este sonido") { model.skipMappingSound() }.buttonStyle(.borderless).foregroundColor(.cyan) }
                    Text(model.mapMessage.isEmpty ? "La asignación se guarda al terminar. Puedes omitir sonidos que no tenga tu controlador." : model.mapMessage).font(.caption).foregroundColor(.white.opacity(0.65)).padding(.top, 5)
                }
                StagePanel {
                    Text("Layout de pads").font(.headline)
                    Text("Pulsa directamente la tarjeta que quieras usar. Las notas físicas no se mueven.").font(.caption).foregroundColor(.white.opacity(0.65))
                    Text("Entrada activa: \(model.selectedMIDIName)").font(.caption2).foregroundColor(StudioDesign.accent)
                    LayoutPresetChooser(selection: $model.selectedLayoutPreset, onUse: model.useLayout)
                    HStack { ActionButton("Aplicar layout seleccionado", prominence: .secondary) { model.applyLayoutPreset() }; ActionButton("Restaurar xRoll Core", prominence: .quiet) { model.restoreCoreLayout() } }
                    HStack { ActionButton("Importar") { model.importLayout() }; ActionButton("Exportar") { model.exportLayout() } }
                    Text(model.mapMessage.isEmpty ? "Selecciona arriba tu controlador MIDI antes de aplicar un layout." : model.mapMessage).font(.caption2).foregroundColor(.white.opacity(0.70))
                    Text("«Restaurar xRoll Core» devuelve la distribución inicial sin cambiar las notas MIDI de tu controlador.").font(.caption2).foregroundColor(.white.opacity(0.58))
                }
            }
            // Va debajo de los controles: no se recorta al abrir la app en una
            // ventana estrecha y la rejilla conserva celdas cómodas de tocar.
            StagePanel {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Vista del controlador").font(.headline)
                    Text("MIDI 36 (C2) está abajo a la izquierda; MIDI 51 está arriba a la derecha. La rejilla se adapta al ancho disponible.").font(.caption).foregroundColor(.white.opacity(0.65))
                    Grid(model: model).padding(.top, 4)
                }
            }
            StagePanel {
                Text("Teclado del Mac (opcional)").font(.headline)
                Text("Puedes practicar sin controlador. Pulsa una tecla distinta para cada sonido que quieras reasignar.").font(.caption).foregroundColor(.white.opacity(0.65))
                ActionButton(model.keyboardMapping ? "Cancelar teclado" : "Mapear teclado", prominence: model.keyboardMapping ? .secondary : .primary) { model.keyboardMapping ? model.cancelKeyboardMapping() : model.startKeyboardMapping() }
                Text(model.keyboardMapMessage.isEmpty ? "Sin asignación personalizada: se usa la cuadrícula Z–V, A–F, Q–R y 1–4." : model.keyboardMapMessage).font(.caption).foregroundColor(.white.opacity(0.65))
            }
        }.foregroundColor(.white).padding(28).frame(maxWidth: 760, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct AudioLatencyHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        AppMark(size: 52)
                        VStack(alignment: .leading) {
                            Text("Audio y latencia").font(.largeTitle.bold())
                            Text("Elige la salida, equilibra niveles y ajusta la respuesta temporal.").foregroundColor(.white.opacity(0.65))
                        }
                    }
                    StagePanel {
                        HStack {
                            Text("Salida y buffer").font(.headline)
                            Spacer()
                            ActionButton("↻ Refrescar", prominence: .secondary) { model.refreshAudioOutputs() }
                        }
                        Picker("Salida", selection: $model.selectedAudioOutputUID) {
                            ForEach(model.audioOutputs) { output in
                                Text(output.name).tag(Optional(output.uid))
                            }
                        }.onChange(of: model.selectedAudioOutputUID) { _ in model.selectAudioOutput() }
                        if let buffer = model.selectedAudioBuffer, !model.selectedAudioBufferChoices.isEmpty {
                            Picker("Buffer", selection: Binding(
                                get: { Int(model.selectedAudioBuffer ?? buffer) },
                                set: { model.setAudioBufferFrames(UInt32($0)) }
                            )) {
                                ForEach(model.selectedAudioBufferChoices, id: \.self) { frames in
                                    Text("\(frames)").tag(Int(frames))
                                }
                            }
                            Text("Se recuerda por salida de audio. Cambiarlo reinicia el audio y solicita una nueva calibración para este perfil.").font(.caption2).foregroundColor(.white.opacity(0.58))
                        }
                    }
                    StagePanel {
                        Text("Calibración de latencia").font(.headline)
                        Text("Sigue la claqueta durante unos compases. La compensación se guarda para la entrada, salida, frecuencia y buffer actuales.").font(.caption).foregroundColor(.white.opacity(0.65))
                        HStack { ActionButton("Iniciar calibración guiada", prominence: model.hasCalibrationForCurrentProfile ? .secondary : .primary) { model.startCalibration() } }
                        Text(model.calibrationMessage).font(.caption2).foregroundColor(.white.opacity(0.58))
                    }
                    StagePanel {
                        Text("Metrónomo y acompañamiento").font(.headline)
                        Text("Estos niveles se aplican al iniciar o reiniciar el ejercicio.").font(.caption).foregroundColor(.white.opacity(0.65))
                        HStack {
                            Text("Tono del metrónomo")
                            Slider(value: $model.tuning.metronomePitchSemitones, in: -12...24, step: 1)
                            Text(String(format: "%+.0f semitonos", model.tuning.metronomePitchSemitones)).frame(width: 96, alignment: .trailing)
                        }
                        HStack {
                            ActionButton("▶ Escuchar metrónomo", prominence: .secondary) { model.previewMetronome() }
                            Text(model.metronomeStatus).font(.caption2).foregroundColor(.white.opacity(0.58)).lineLimit(2)
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
                    }.onChange(of: model.tuning) { _ in model.saveTuning() }
                    StagePanel {
                        HStack(spacing: 5) {
                            Text("Mezcla del kit").font(.headline)
                            ContextInfoButton(title: "Mezcla del kit", detail: "Los WAV se normalizan al cargarse para que sus picos queden equilibrados. Estos controles ajustan después el volumen de cada sonido sin alterar los archivos originales. Si un crash o tom destaca demasiado, bájalo aquí.")
                            Spacer()
                            ActionButton("Restablecer", prominence: .quiet) { model.resetSoundMix() }
                        }
                        Text("Los cambios se oyen al momento y se guardan para el próximo inicio.").font(.caption).foregroundColor(.white.opacity(0.65))
                        ForEach(model.kitSoundIDs, id: \.self) { sound in
                            HStack(spacing: 10) {
                                Text(model.displayName(sound)).frame(width: 118, alignment: .leading)
                                Slider(value: Binding(get: { model.soundVolume(sound) }, set: { model.setSoundVolume($0, for: sound) }), in: 0...1.5)
                                Text("\(Int(model.soundVolume(sound) * 100)) %").monospacedDigit().frame(width: 46, alignment: .trailing)
                            }
                        }
                    }
                    Spacer()
                }.foregroundColor(.white).padding(30).frame(maxWidth: 760, alignment: .leading)
            }
        }
    }
}

private struct SettingsHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        AppMark(size: 52)
                        VStack(alignment: .leading) {
                            Text("Ajustes").font(.largeTitle.bold())
                            Text("Preferencias de práctica, controlador MIDI y opciones avanzadas.").foregroundColor(.white.opacity(0.65))
                        }
                    }
                    StagePanel {
                        Text("Preferencias de práctica").font(.headline)
                        Toggle("Metrónomo al comenzar", isOn: $model.metronomeEnabled)
                        Toggle("Loop de acompañamiento al comenzar", isOn: Binding(get: { model.loopEnabled }, set: { model.setLoopEnabled($0) }))
                        HStack(spacing: 8) {
                            Text("Ayuda inicial").font(.subheadline.weight(.semibold))
                            ContextInfoButton(title: "Ayuda inicial", detail: "Define la guía usada al abrir una práctica. Completa muestra nombres y todas las referencias; Normal retira los nombres; Reducida elimina algunas referencias de charles para entrenar el pulso.")
                        }
                        HStack(spacing: 8) {
                            ForEach(PracticeHelp.allCases, id: \.self) { help in
                                ActionButton(help.label, prominence: model.practiceHelp == help ? .primary : .secondary) { model.setPracticeHelp(help) }
                            }
                        }
                        Text("Activa ahora: \(model.practiceHelp.label). \(model.practiceHelpDescription)").font(.caption).foregroundColor(.white.opacity(0.65))
                        Toggle("Mostrar entrenamiento avanzado D-A-I-T", isOn: Binding(get: { model.showsTrainingPhases }, set: { model.setShowsTrainingPhases($0) }))
                        Text("Añade las fases Descubrir, Aislar, Integrar y Transferir, las Ayudas, transferencia y Gap Metronome. Déjalo apagado para una preparación más simple.").font(.caption2).foregroundColor(.white.opacity(0.58))
                        Text("El tempo y la duración se guardan desde cada ejercicio.").font(.caption2).foregroundColor(.white.opacity(0.58))
                    }
                    StagePanel {
                        HStack { Text("Controlador MIDI").font(.headline); Spacer(); ActionButton("↻ Refrescar", prominence: .secondary) { model.refreshMIDIDevices() } }
                        Picker("Entrada", selection: $model.sourceID) {
                            Text("Sin entrada MIDI").tag(MIDIUniqueID?.none)
                            ForEach(model.sources, id: \.uniqueID) { source in Text(source.name).tag(Optional(source.uniqueID)) }
                        }.onChange(of: model.sourceID) { _ in model.selectSource() }
                        Text("xRoll escucha únicamente el controlador elegido aquí. La asignación de pads está en «Pads y layout».").font(.caption2).foregroundColor(.white.opacity(0.58))
                    }
                    StagePanel { BluetoothMIDIPanel(model: model) }
                    StagePanel {
                        Text("Ejercicios MIDI comunitarios").font(.headline)
                        Text("Importa un .mid o .midi: se valida con el kit actual y queda guardado localmente.").font(.caption).foregroundColor(.white.opacity(0.65))
                        ActionButton("Importar ejercicio MIDI", prominence: .secondary) { model.showingExerciseImporter = true }.padding(.top, 5)
                        if !model.exerciseImportMessage.isEmpty { Text(model.exerciseImportMessage).font(.caption2).foregroundColor(.white.opacity(0.58)).padding(.top, 3) }
                    }
                    StagePanel {
                        Toggle("Activar Debug", isOn: $model.tuning.debugEnabled).font(.headline)
                        Text("Opciones técnicas para diagnóstico; afectan a la siguiente práctica.").font(.caption).foregroundColor(.white.opacity(0.65))
                        if model.tuning.debugEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider().overlay(Color.white.opacity(0.16))
                                Text(model.midiDiagnostics).font(.caption).foregroundColor(.white.opacity(0.65))
                                Text("Debug está pensado para diagnóstico interno y no modifica la calibración guardada.").font(.caption2).foregroundColor(.orange.opacity(0.8))
                                VStack(alignment: .leading, spacing: 8) {
                                    Stepper("Anticipación: \(model.tuning.anticipationBars) compases", value: $model.tuning.anticipationBars, in: 1...4)
                                    Text("Ventanas de juicio (±ms; solo se pueden estrechar)").font(.caption.bold()).foregroundColor(.white.opacity(0.7))
                                    Stepper("Clavado: ±\(Int(model.tuning.perfectWindowMilliseconds)) ms", value: $model.tuning.perfectWindowMilliseconds, in: 5...35, step: 1)
                                    Stepper("Bien: ±\(Int(model.tuning.goodWindowMilliseconds)) ms", value: $model.tuning.goodWindowMilliseconds, in: 5...65, step: 1)
                                    Stepper("Regular: ±\(Int(model.tuning.regularWindowMilliseconds)) ms", value: $model.tuning.regularWindowMilliseconds, in: 5...95, step: 1)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Stepper("Compensación manual: \(Int(model.tuning.manualTimingOffsetMilliseconds)) ms", value: $model.tuning.manualTimingOffsetMilliseconds, in: -200...200, step: 1)
                                    Stepper("Destello de pad: \(model.tuning.padFlashMilliseconds) ms", value: $model.tuning.padFlashMilliseconds, in: 30...500, step: 10)
                                    ActionButton("Restablecer valores de Debug", prominence: .secondary) { model.resetTuning() }
                                }
                            }
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
    @State private var section = "home"
    @State private var sidebarCollapsed = false
    @State private var showsLaunchBrand = true
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    var body: some View {
        Group {
            if model.isShowingResultTransition {
                PracticeCompletionTransition(percentage: model.resultTransitionPercentage).transition(.opacity)
            } else if let scene = model.previewScene {
                PracticePreview(model: model, scene: scene).transition(.opacity)
            } else if let scene = model.practiceScene {
                PracticeRun(model: model, scene: scene).transition(.opacity)
            } else {
                studioShell.transition(.opacity)
            }
        }
        .background(WindowResizeSupport())
        .frame(minWidth: 960, minHeight: 650)
        .overlay {
            if showsLaunchBrand { XRollLaunchView().transition(.opacity) }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                withAnimation(reducesMotion ? nil : .easeOut(duration: 0.35)) { showsLaunchBrand = false }
            }
        }
        .alert("Calibración pendiente", isPresented: $model.showingCalibrationWarning) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("No has calibrado esta entrada y salida. La práctica puntuada permanece bloqueada hasta completar la calibración guiada.")
        }
    }
    private var studioShell: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack { AppMark(size: 30); if !sidebarCollapsed { Text("xRoll").font(.headline.bold()) }; Spacer(); Button { sidebarCollapsed.toggle() } label: { Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left") }.buttonStyle(.plain).foregroundColor(StudioDesign.textSecondary).help(sidebarCollapsed ? "Desplegar menú" : "Plegar menú") }.padding(.bottom, 18)
                Group { nav("Inicio", "house", "home") }
                Group { sidebarHeading("PRÁCTICA"); nav("Curso", "music.note.list", "course"); nav("Redobles", "music.quarternote.3", "fills") }
                Group { sidebarHeading("ANÁLISIS"); nav("Progreso", "chart.line.uptrend.xyaxis", "progress") }
                Group { sidebarHeading("EQUIPO"); nav("Pads y layout", "square.grid.3x3", "pads"); nav("Audio y latencia", "waveform", "audio"); nav("Ajustes", "gearshape", "settings") }
                Spacer()
                if !sidebarCollapsed { Text(model.status).font(.caption2).foregroundColor(StudioDesign.textSecondary).lineLimit(2) }
            }.foregroundColor(StudioDesign.textPrimary).padding(16).frame(width: sidebarCollapsed ? 64 : 190).background(StudioDesign.surface)
            Divider().overlay(StudioDesign.surfaceHover)
            Group {
                if model.showingResults { ResultsHome(model: model) }
                else if model.showingPreparation { PreparationHome(model: model) }
                else if section == "home" { OnboardingHome(model: model, showPads: { section = "pads" }) }
                else if section == "progress" { ProgressHome(model: model) }
                else if section == "fills" { FillsHome(model: model) }
                else if section == "pads" { MappingHome(model: model) }
                else if section == "audio" { AudioLatencyHome(model: model) }
                else if section == "settings" { SettingsHome(model: model) }
                else { PracticeHome(model: model) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder private func sidebarHeading(_ title: String) -> some View {
        if !sidebarCollapsed { Text(title).font(.studioLabel).foregroundColor(StudioDesign.textMuted).padding(.top, 14) }
        else { Divider().overlay(StudioDesign.surfaceHover).padding(.vertical, 8) }
    }
    private func nav(_ title: String, _ icon: String, _ id: String) -> some View {
        Button { model.leaveActiveScreen(); section = id } label: {
            Group { if sidebarCollapsed { Image(systemName: icon).frame(maxWidth: .infinity) } else { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading) } }
                .font(.subheadline.weight(.medium)).padding(.horizontal, sidebarCollapsed ? 2 : 10).padding(.vertical, 8).background(section == id ? StudioDesign.accent.opacity(0.15) : Color.clear).foregroundColor(section == id ? StudioDesign.accent : StudioDesign.textSecondary).clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).help(title)
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
