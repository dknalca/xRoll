import AVFoundation
import AVKit
import AudioToolbox
import Charts
import CoreMIDI
import SpriteKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XRollCore

private struct iOSRegisteredHit {
    let scoredHit: ScoredPadHit
    let calibrationAssociation: CalibrationHitAssociation?
}

private struct iOSPracticeInputContext {
    let feedbackID: String
    let source: PracticeTraceInput
    let inputHostTime: UInt64
    let workerHostTime: UInt64?
    let audioSubmissionStartHostTime: UInt64?
    let audioSubmissionReturnHostTime: UInt64?
    let audioSubmissionError: String?
    let soundID: String?
    let role: String?
    let padID: String?
    let midiEvent: MIDINoteOn?
    let touchTimestampSeconds: Double?
}

private final class iOSMIDIMappingGate {
    private let lock = NSLock()
    private var active = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func setActive(_ value: Bool) {
        lock.lock()
        active = value
        lock.unlock()
    }
}

/// El callback MIDI llama a este puente en su worker, nunca al modelo SwiftUI.
/// Resolver, reproducir y admitir el golpe para scoring ocurre antes de notificar
/// a la interfaz; solo la presentación del resultado llega al hilo principal.
private final class iOSMIDIPlaybackBridge {
    private let liveMIDI: LiveMIDIProcessor
    private let audio: SampleAudioEngine
    private let mappingGate: iOSMIDIMappingGate
    private let sessionIngress: PracticeSessionIngress
    private let onMappingEvent: (MIDINoteOn) -> Void
    private let onDelivery: (iOSPracticeInputContext, UUID?, PracticeSessionProcessingResult?) -> Void

    init(
        liveMIDI: LiveMIDIProcessor,
        audio: SampleAudioEngine,
        mappingGate: iOSMIDIMappingGate,
        sessionIngress: PracticeSessionIngress,
        onMappingEvent: @escaping (MIDINoteOn) -> Void,
        onDelivery: @escaping (iOSPracticeInputContext, UUID?, PracticeSessionProcessingResult?) -> Void
    ) {
        self.liveMIDI = liveMIDI
        self.audio = audio
        self.mappingGate = mappingGate
        self.sessionIngress = sessionIngress
        self.onMappingEvent = onMappingEvent
        self.onDelivery = onDelivery
    }

    func receive(_ event: MIDINoteOn) {
        guard !mappingGate.isActive else {
            onMappingEvent(event)
            return
        }
        let workerHostTime = AudioClock.currentHostTime()
        let hit = liveMIDI.resolve(event)
        var audioStart: UInt64?
        var audioReturn: UInt64?
        var audioError: String?
        if let hit {
            audioStart = AudioClock.currentHostTime()
            do { try audio.play(soundID: hit.soundID) }
            catch { audioError = error.localizedDescription }
            audioReturn = AudioClock.currentHostTime()
        }

        let context = iOSPracticeInputContext(
            feedbackID: UUID().uuidString,
            source: .midi,
            inputHostTime: event.hostTime,
            workerHostTime: workerHostTime,
            audioSubmissionStartHostTime: audioStart,
            audioSubmissionReturnHostTime: audioReturn,
            audioSubmissionError: audioError,
            soundID: hit?.soundID,
            role: hit?.role,
            padID: hit?.padID,
            midiEvent: event,
            touchTimestampSeconds: nil
        )
        guard let hit else {
            onDelivery(context, nil, nil)
            return
        }

        let admittedGeneration = sessionIngress.submit(
            sound: hit.soundID,
            hostTime: event.hostTime,
            role: hit.role,
            padID: hit.padID,
            velocity: UInt8(clamping: event.velocity)
        ) { generation, result in
            self.onDelivery(context, generation, result)
        }
        if admittedGeneration == nil { onDelivery(context, nil, nil) }
    }
}

private struct iOSScorePoint: Identifiable {
    let id: Int
    let attemptNumber: Int
    let score: Double
}

enum iOSMainTab: Hashable {
    case practice
    case course
    case fills
    case layouts
    case progress
}

struct iOSCourseChapter: Identifiable {
    let id: String
    let exercises: [Exercise]
    var checkpointExercise: Exercise? { exercises.first { $0.metadata?.flags.contains("checkpoint") == true } }
    var title: String {
        switch id {
        case "initiation": return "Iniciación"
        case "fundamentals": return "Fundamentos"
        case "subdivision": return "Subdivisión"
        case "coordination": return "Coordinación"
        case "groove": return "Groove y fraseo"
        case "hiphop": return "Hip-hop"
        case "rock": return "Rock"
        case "disco": return "Disco"
        case "funk": return "Funk"
        case "reggae": return "Reggae"
        case "dembow": return "Dembow"
        case "blues": return "Blues / Shuffle"
        case "jazz": return "Jazz"
        case "clave-bossa": return "Clave / Bossa"
        case "fills": return "Redobles y transiciones"
        default: return id.capitalized
        }
    }
}

struct iOSFillPair: Identifiable {
    let chapter: String
    let number: Int
    let isolated: Exercise?
    let inContext: Exercise?

    var id: String { chapter }
    var title: String {
        switch number {
        case 1: return "Caja a corcheas"
        case 2: return "Bajada de toms"
        case 3: return "Caja en semicorcheas"
        default: return "Lineal: bombo, caja y toms"
        }
    }
    var explanation: String {
        switch number {
        case 1: return "Cuatro golpes de caja, espaciados y fáciles de colocar al final del compás."
        case 2: return "Desciende del tom agudo al grave: un cierre clásico que suena grande sin correr."
        case 3: return "Ocho golpes de caja más juntos. Mantén todos iguales antes de acelerar."
        default: return "Cada golpe ocupa su sitio: alterna bombo, caja y toms sin que dos sonidos caigan a la vez."
        }
    }
}

@main
struct XRolliOSApp: App {
    var body: some Scene {
        WindowGroup { iOSHomeView() }
    }
}

@MainActor
final class iOSPracticeModel: ObservableObject {
    private static let preferredIOBufferDuration = 256.0 / 44_100.0

    @Published private(set) var exercises: [Exercise] = []
    @Published private(set) var communityExercises = [Exercise]()
    @Published private(set) var exerciseImportMessage = ""
    @Published var selectedExerciseID = ""
    @Published private(set) var status = "Cargando ejercicios y kit…"
    @Published private(set) var audioConfigurationStatus = "Configuración de audio pendiente."
    @Published private(set) var isPracticing = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var previewScene: PracticeScene?
    @Published private(set) var showsResult = false
    @Published private(set) var isCheckpointAssessment = false
    @Published private(set) var isShowingResultTransition = false
    @Published private(set) var resultTransitionPercentage = 0.0
    @Published var selectedTab: iOSMainTab = .practice
    @Published private(set) var scoreText = ""
    @Published private(set) var lastCompletedExerciseTitle = ""
    @Published private(set) var completedScore: ExerciseScore?
    @Published private(set) var resultInsights: PracticeInsights?
    @Published private(set) var resultSummary: PracticeResultSummary?
    @Published private(set) var resultDiagnosisText = ""
    @Published private(set) var resultActionReason = ""
    @Published private(set) var ghostCoachCue = ""
    @Published private(set) var resultHitRecords = [HitRecord]()
    @Published private(set) var resultIsPartial = false
    @Published private(set) var resultCompletedBars = 0
    @Published private(set) var lastHit = "Toca un pad para probar el sonido."
    @Published private(set) var lastMIDINote = "Aún no han llegado golpes MIDI."
    @Published private(set) var calibrationStatus = "Calibración pendiente para esta ruta."
    @Published private(set) var calibrationHitCount = 0
    @Published private(set) var isCalibrating = false
    @Published private(set) var predictsVisualFrame = UserDefaults.standard.object(forKey: "xRoll.ios.predictVisualFrame") as? Bool ?? false
    @Published private(set) var timingTraceURL: URL?
    @Published private(set) var timingTraceMessage = ""
    @Published private(set) var scene: PracticeScene?
    @Published private(set) var midiSources: [MIDIEndpointDescription] = []
    @Published var selectedMIDISourceID: MIDIUniqueID?
    @Published private(set) var midiStatus = "Solo pads táctiles"
    @Published private(set) var bluetoothMIDIDevices: [BluetoothMIDIDevice] = []
    @Published private(set) var bluetoothMIDIStatus = "Buscando Bluetooth MIDI…"
    @Published private(set) var selectedLayoutPreset: PadLayoutPreset = .core
    @Published private(set) var layoutStatus = "Aprende las 16 posiciones del controlador para activar la práctica puntuable."
    @Published private(set) var isLearningPadMap = false
    @Published private(set) var mappingAssignedCount = 0
    @Published private(set) var mappingMessage = ""
    @Published private(set) var courseLevels = [CourseLevelState]()
    @Published private(set) var courseEvidence = [CourseAttemptEvidence]()
    @Published private(set) var recentAttempts = [PracticeAttempt]()
    @Published var selectedProgressExerciseID = ""
    @Published var minimumProgressScore = 0.0
    @Published private(set) var courseStatus = ""
    @Published private(set) var fillRouteStatus = ""
    @Published private(set) var selectedBPM = 70
    @Published private(set) var selectedRepeats = 1
    @Published var trainingPhase: TrainingPhase = .integrate
    @Published var practiceHelp: PracticeHelp = .full
    @Published private(set) var selectedPracticeSounds = Set<String>()
    @Published private(set) var practiceFragment = 0
    @Published var gapMetronomeLevel = 0
    @Published private(set) var isPracticePaused = false
    @Published var metronomeEnabled = UserDefaults.standard.object(forKey: "xRoll.ios.metronomeEnabled") as? Bool ?? true
    @Published var metronomeVolume = UserDefaults.standard.object(forKey: "xRoll.ios.metronomeVolume") as? Double ?? 0.65
    @Published var metronomePitchSemitones = UserDefaults.standard.object(forKey: "xRoll.ios.metronomePitchSemitones") as? Double ?? 0
    @Published var metronomeStatus = ""
    @Published private(set) var loopOptions = [LoopLibraryOption]()
    @Published var selectedLoopID: String?
    @Published private(set) var loopSelectionIsAutomatic = UserDefaults.standard.object(forKey: "xRoll.ios.loopSelectionAutomatic") as? Bool
        ?? (UserDefaults.standard.string(forKey: "xRoll.ios.selectedLoop") == nil)
    @Published var loopEnabled = UserDefaults.standard.object(forKey: "xRoll.ios.loopEnabled") as? Bool ?? false
    @Published var loopVolume = UserDefaults.standard.object(forKey: "xRoll.ios.loopVolume") as? Double ?? 0.55
    @Published private(set) var loopStatus = "No hay un loop cargado."
    @Published private(set) var soundVolumes = [String: Double]()
    @Published private(set) var mapTransferMessage = ""
    @Published private(set) var mapExportURL: URL?
    @Published private(set) var pendingMapImportName = ""
    @Published var isWaitingToConfirmMapImport = false
    @Published private(set) var progressExportURL: URL?
    @Published private(set) var progressImportMessage = ""
    @Published private(set) var coachingGoals = [CoachingGoal]()
    @Published private(set) var coachingFeedback = ""
    @Published private(set) var canReturnToFullGroove = false
    @Published private(set) var dailyPracticePlan: DailyPracticePlan?
    @Published private(set) var dailyPracticeMessage = ""
    @Published private(set) var pulseTrainingStage: PulseTrainingStage?
    @Published private(set) var pulseDriftMessage = ""
    @Published private(set) var pulseDriftReport: PulseDriftReport?

    private var kit: KitManifest?
    private var bundledExercises = [Exercise]()
    private var audio: SampleAudioEngine?
    private var audioSessionConfigured = false
    private var ioBufferPreferenceError: String?
    private var padMap: PadMapV2?
    private var touchPhysicalMap: PadMapV2?
    private var physicalMIDIMap: PadMapV2?
    private var courseGraph: CourseGraph?
    private var session: PracticeSession?
    private let sessionIngress = PracticeSessionIngress()
    private var presentedSessionGeneration: UUID?
    private var discardingPracticeGeneration: UUID?
    private var activeExercise: Exercise?
    private var activeFullPatternExercise: Exercise?
    private var activeEvaluationScope: EvaluationScope = .fullPattern
    private var activeTrainingPhase: TrainingPhase = .integrate
    private var activeGapMetronomeLevel = 0
    private var activeShowsVisualGuides = true
    private var correctiveStepRange: ClosedRange<Int>?
    private var correctivePlan: WhalePlan?
    private var coachingRecommendation: CoachingRecommendation?
    private var coachingBaselineAttempt: PracticeAttempt?
    private enum CoachingFlowStage { case none, suggested, isolating, integrating }
    private var coachingFlowStage: CoachingFlowStage = .none
    private var activeDailyBlockID: UUID?
    private var previousPulseLoopEnabled: Bool?
    private var activePracticeConditions: PracticeConditions?
    private var autopilotRecommendation: AutopilotRecommendation?
    private var pausedExercise: Exercise?
    private var pausedFullPatternExercise: Exercise?
    private var pausedEvaluationScope: EvaluationScope = .fullPattern
    private var pausedCalibration = false
    private var pausedScoringOffset = 0.0
    private var pausedCalibrationProfileKey: CalibrationProfileKey?
    private var activeExpectedNotesBySound = [String: [ScheduledExerciseNote]]()
    private var startHostTime: UInt64 = 0
    private var finishTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var resultTransitionTask: Task<Void, Never>?
    private var previewToken = UUID()
    private let touchClock = TouchHostClock()
    private var progressStore: ProgressStore?
    private var midiInput: MIDIInputSession?
    private var connectedMIDISourceID: MIDIUniqueID?
    private var connectedMIDISourceEndpoint: MIDIEndpointRef?
    private var hasExplicitMIDISourceSelection = false
    private var midiSetupMonitor: MIDISetupMonitor?
    private var liveMIDI: LiveMIDIProcessor?
    private var audioRouteObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var calibrationProfile: CalibrationProfile?
    private var calibrationOffsetMilliseconds = 0.0
    private var calibrationTargetSounds = Set<String>()
    private var calibrationHitTimesBySound = [String: [Double]]()
    private var calibrationTraceMatchersBySound = [String: CalibrationMatcher]()
    private let timingTrace = PracticeTimingTraceBuffer()
    private var timingTraceSessionID = UUID()
    private var activeCalibrationProfileKey: CalibrationProfileKey?
    private var activeScoringCompensationMilliseconds = 0.0
    private var padMapBuilder: PadMapBuilder?
    private var pendingImportedMap: PadMapV2?
    private let midiMappingGate = iOSMIDIMappingGate()
    private var mappingStartHostTime: UInt64 = 0
    private lazy var bluetoothMIDI: BluetoothMIDIManager = {
        let manager = BluetoothMIDIManager()
        manager.onUpdate = { [weak self] devices, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.bluetoothMIDIDevices = devices
                self.bluetoothMIDIStatus = message
                self.updateMIDISources()
            }
        }
        return manager
    }()

    var selectedExercise: Exercise? { exercises.first { $0.id == selectedExerciseID } }
    var selectedPracticeTitle: String {
        guard isCheckpointAssessment, let exercise = selectedExercise else { return selectedExercise?.title ?? "Práctica" }
        let chapter = courseChapters.first { $0.id == exercise.metadata?.chapter }?.title ?? "bloque"
        return "Prueba final · \(chapter)"
    }
    var hasDailyPracticePlanForToday: Bool { dailyPracticePlan.map { Calendar.current.isDateInToday($0.day) } ?? false }
    var dailyPracticeCompletedToday: Bool { hasDailyPracticePlanForToday && dailyPracticePlan?.isComplete == true }
    var pads: [PadMapV2.Pad] { padMap?.pads.sorted { $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row } ?? [] }
    var usesTouchInput: Bool { selectedMIDISourceID == nil }
    var hasLearnedPhysicalPadMap: Bool { physicalMIDIMap?.pads.count == 16 }
    var hasCustomImportedMap: Bool { !usesTouchInput && physicalMIDIMap?.preset == .custom }
    var needsEquipmentSetup: Bool {
        !usesTouchInput && (midiInput == nil || !hasLearnedPhysicalPadMap)
    }
    var needsHomeSetup: Bool { needsEquipmentSetup || !hasCalibrationForCurrentRoute }
    var canScoreSelectedExercise: Bool {
        guard let exercise = selectedExercise else { return false }
        return canScore(exercise)
    }
    func canScore(_ exercise: Exercise) -> Bool {
        guard hasCalibrationForCurrentRoute, isExerciseAvailable(exercise) else { return false }
        if usesTouchInput { return true }
        guard midiInput != nil, hasLearnedPhysicalPadMap else { return false }
        return isLayoutCompatible(with: exercise)
    }
    var tempoSteps: [TempoPracticeStep] { selectedExercise.map(TempoLadder.steps(for:)) ?? [] }
    var loopSelectionChoice: String {
        loopSelectionIsAutomatic ? LoopLibraryCatalog.automaticSelectionID : (selectedLoopID ?? LoopLibraryCatalog.automaticSelectionID)
    }
    var loopSelectionLabel: String {
        guard let option = selectedExercise.flatMap({ LoopLibraryCatalog.recommended(for: $0, targetBPM: Double(selectedBPM), options: loopOptions) }) else {
            return "Automático"
        }
        return "Auto · \(option.fileName) · \(Int((option.bpm ?? 0).rounded())) BPM"
    }
    var courseRecommendation: CourseRecommendation? {
        guard courseGraph != nil else { return nil }
        return CourseRecommendationPlanner.recommend(exercises: bundledExercises, courseLevels: courseLevels, evidence: courseEvidence)
    }
    var canStartCorrectivePractice: Bool { !resultIsPartial && resultSummary != nil && correctivePlan != nil }
    private var nextTempoLevel: TempoPracticeStep? {
        guard !resultIsPartial, (completedScore?.stars ?? 0) >= 2,
              activeEvaluationScope == .fullPattern, let exercise = selectedExercise else { return nil }
        return TempoLadder.steps(for: exercise).first {
            $0.bpm > selectedBPM && !TempoLadder.isPassed($0, exerciseID: exercise.id, evidence: courseEvidence)
        }
    }
    private enum ResultProgressSuggestion {
        case raise(TempoPracticeStep)
        case next(Exercise)
    }
    private var resultProgressSuggestion: ResultProgressSuggestion? {
        guard !resultIsPartial, (completedScore?.stars ?? 0) >= 2,
              activeEvaluationScope == .fullPattern else { return nil }
        if let next = nextCourseExercise, courseRecommendation?.exerciseID != selectedExercise?.id {
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
    var displayedResultActionReason: String {
        switch resultProgressSuggestion {
        case .raise(let level):
            return "Prepara el siguiente escalón: \(level.label), \(level.bpm) BPM. Es un reto opcional."
        case .next(let exercise):
            return "Prepara «\(exercise.title)». Puedes explorarlo sin saltarte los requisitos del curso."
        case nil: return resultActionReason
        }
    }
    var resultActionTitle: String {
        switch resultProgressSuggestion {
        case .raise: return "Subir nivel"
        case .next: return "Siguiente ejercicio"
        case nil: break
        }
        switch resultSummary?.action {
        case .corrective: return "Repetir ejercicio"
        case .repeatWithAdjustment: return "Aplicar ajuste y repetir"
        case .advance: return "Siguiente paso del curso"
        case .repeatSame: return "Repetir para consolidar"
        case nil: return "Repetir ritmo"
        }
    }
    var courseChapters: [iOSCourseChapter] {
        guard let courseGraph else { return [] }
        var chapters = [iOSCourseChapter]()
        for node in courseGraph.nodes where !node.metadata.chapter.hasPrefix("fills-") {
            let chapter = node.metadata.chapter
            if let index = chapters.firstIndex(where: { $0.id == chapter }) {
                chapters[index] = iOSCourseChapter(id: chapter, exercises: chapters[index].exercises + [node.exercise])
            } else {
                chapters.append(iOSCourseChapter(id: chapter, exercises: [node.exercise]))
            }
        }
        return chapters
    }
    var nextCourseExercise: Exercise? {
        CourseRecommendationPlanner.nextExercise(after: selectedExerciseID, exercises: bundledExercises,
            courseLevels: courseLevels, evidence: courseEvidence)
    }
    var canOfferNextCourseExercise: Bool {
        (completedScore?.stars ?? 0) >= 2
            && !resultIsPartial
            && activeEvaluationScope == .fullPattern
            && nextCourseExercise != nil
    }
    func startNextCourseExercise() {
        guard canOfferNextCourseExercise, let exercise = nextCourseExercise else { return }
        selectExerciseForPractice(exercise.id, returnTo: .course)
        showsResult = false
        startGuidedLesson()
    }
    private func raiseTempoLevel() {
        guard let level = nextTempoLevel,
              let index = tempoSteps.firstIndex(where: { $0.bpm == level.bpm }) else { return }
        selectTempoStep(index)
        isCheckpointAssessment = false
        startGuidedLesson()
    }
    func performAlternativeProgressAction() {
        switch resultProgressSuggestion {
        case .next: raiseTempoLevel()
        case .raise: startNextCourseExercise()
        case nil: break
        }
    }
    func highestTempoAward(for exercise: Exercise) -> TempoAward? {
        TempoLadder.highestPassedStep(for: exercise, evidence: courseEvidence)?.award
    }
    var fillPairs: [iOSFillPair] {
        let exercisesByChapter = Dictionary(grouping: bundledExercises.compactMap { exercise -> (String, Exercise)? in
            guard let metadata = exercise.metadata, metadata.chapter.hasPrefix("fills-") else { return nil }
            return (metadata.chapter, exercise)
        }, by: \.0)
        return exercisesByChapter.keys.sorted().compactMap { chapter in
            guard let number = Int(chapter.replacingOccurrences(of: "fills-", with: "")) else { return nil }
            let exercises = exercisesByChapter[chapter, default: []].map(\.1)
            return iOSFillPair(
                chapter: chapter,
                number: number,
                isolated: exercises.first(where: { $0.metadata?.position == 1 }),
                inContext: exercises.first(where: { $0.metadata?.position == 2 })
            )
        }
    }
    var mainCourseLevels: [CourseLevelState] {
        let mainExerciseIDs = Set(bundledExercises.compactMap { exercise -> String? in
            guard let chapter = exercise.metadata?.chapter, !chapter.hasPrefix("fills-") else { return nil }
            return exercise.id
        })
        return courseLevels.filter { mainExerciseIDs.contains($0.exerciseID) }
    }
    var kitSoundIDs: [String] { kit?.sounds.map(\.id) ?? [] }
    var learnedPadsForPreview: [PadMapV2.Pad] {
        usesTouchInput ? (padMap?.pads ?? []) : (physicalMIDIMap?.pads ?? [])
    }
    var activeLayoutPads: [PadMapV2.Pad] { padMap?.pads ?? [] }
    var activeBPM: Int { activeExercise?.bpm ?? selectedBPM }
    var mappingNextStep: PadMapCaptureStep? { padMapBuilder?.nextStep }
    var mappingAssignedPads: [PadMapV2.Pad] { padMapBuilder?.assignedPads ?? [] }
    var selectedExerciseDurationMilliseconds: Double {
        guard let exercise = selectedExercise else { return 0 }
        let configured = PracticeConfiguration(exercise: exercise, bpm: selectedBPM, repeats: selectedRepeats).applying(to: exercise)
        return ExerciseTimeline(exercise: configured).patternDurationMilliseconds * Double(configured.repeats)
    }
    var audioOutputName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Salida predeterminada"
    }

    func layoutCompatibilityMessageForUI(_ exercise: Exercise) -> String? { layoutCompatibilityMessage(for: exercise) }

    func kitLabel(for soundID: String) -> String {
        kit?.sounds.first(where: { $0.id == soundID })?.label ?? soundID
    }

    func layoutPreview(for preset: PadLayoutPreset) -> [PadMapV2.Pad] {
        let base = usesTouchInput ? touchPhysicalMap : (physicalMIDIMap ?? padMap)
        guard let base else { return [] }
        return PadLayoutFactory.applying(preset, to: base).pads
    }

    init() { load() }

    private func load() {
        do {
            try configureAudioSession()
            let bundle = Bundle.main
            guard let kitURL = bundle.url(forResource: "kit", withExtension: "json", subdirectory: "Kits/hiphop_basic"),
                  let exerciseDirectory = bundle.url(forResource: "exercises", withExtension: nil) else {
                throw AppError.resourcesMissing
            }
            let catalog = ResourceCatalog()
            let loadedKit = try catalog.loadKit(at: kitURL)
            let engine = SampleAudioEngine()
            try engine.load(kit: loadedKit, from: kitURL.deletingLastPathComponent())
            let savedVolumes = UserDefaults.standard.dictionary(forKey: "xRoll.ios.soundVolumes") as? [String: Double] ?? [:]
            soundVolumes = savedVolumes
            for sound in loadedKit.sounds { engine.setSoundVolume(Float(savedVolumes[sound.id] ?? 1), for: sound.id) }
            loadLoopLibrary(bundle: Bundle.main)
            try engine.start()
            let loadedExercises = try catalog.loadExercises(in: exerciseDirectory, kit: loadedKit)
            let touchMap = PadLayoutFactory.make(.core, device: .init(name: "xRoll Touch", uid: 0))
            try touchMap.validate(availableSounds: Set(loadedKit.sounds.map(\.id)))
            let router = KitNoteRouter(kit: loadedKit)
            let touchRouter = PadMapV2Router(touchMap)
            kit = loadedKit
            audio = engine
            liveMIDI = LiveMIDIProcessor(audio: engine, kitRouter: router, padRouter: touchRouter)
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("xRoll", isDirectory: true)
            progressStore = try ProgressStore(url: supportDirectory.appendingPathComponent("progress.sqlite"))
            coachingGoals = (try? progressStore?.loadTrainingState([CoachingGoal].self, forKey: "coaching-goals")) ?? []
            dailyPracticePlan = try? progressStore?.loadTrainingState(DailyPracticePlan.self, forKey: "daily-practice-plan")
            metronomeVolume = UserDefaults.standard.object(forKey: "xRoll.ios.metronomeVolume") as? Double ?? 0.65
            loopEnabled = UserDefaults.standard.object(forKey: "xRoll.ios.loopEnabled") as? Bool ?? false
            loopVolume = UserDefaults.standard.object(forKey: "xRoll.ios.loopVolume") as? Double ?? 0.55
            touchPhysicalMap = touchMap
            selectedLayoutPreset = savedLayoutPreset(for: nil)
            padMap = PadLayoutFactory.applying(selectedLayoutPreset, to: touchMap)
            liveMIDI?.setPadRouter(PadMapV2Router(padMap ?? touchMap))
            exercises = loadedExercises
            bundledExercises = loadedExercises
            courseGraph = try? CourseGraph(exercises: loadedExercises)
            reloadCommunityExercises()
            selectedExerciseID = loadedExercises.first?.id ?? ""
            if let exercise = selectedExercise {
                selectedBPM = CourseLessonCriteria.targetBPM(for: exercise)
                selectedRepeats = PracticeConfiguration.normalizedRepeats(exercise.repeats)
            }
            status = "\(loadedExercises.count) ejercicios · \(loadedKit.name)"
            refreshCourseProgress()
            if let exercise = selectedExercise { selectPendingTempo(for: exercise) }
            loadPracticePreferences()
            restoreLoopSelection()
            loadTrainingPreferences()
            observeAudioRouteChanges()
            beginMIDIMonitoring()
            loadCalibrationForCurrentRoute()
            loadMetronomePreferences()
        } catch {
            status = "No se pudo iniciar: \(error.localizedDescription)"
        }
    }

    var hasCalibrationForCurrentRoute: Bool {
        calibrationProfile?.key == currentCalibrationProfileKey()
    }

    func startPractice() {
        cancelResultTransition()
        // La finalización procesa el score en una cola serial y publica el
        // resultado un turno después. No admitas otra sesión hasta que esa
        // generación haya cerrado, o se perdería su resultado al cambiar el ID.
        guard session == nil, presentedSessionGeneration == nil, !isPracticing, !isPracticePaused else { return }
        guard let exercise = selectedExercise else { return }
        if trainingPhase == .discover {
            previewExercise()
            return
        }
        guard usesTouchInput || midiInput != nil else {
            layoutStatus = "Conecta la entrada MIDI seleccionada antes de empezar."
            selectedTab = .layouts
            return
        }
        guard isExerciseAvailable(exercise) else {
            courseStatus = "Este ritmo no está disponible en el catálogo integrado actual."
            selectedTab = .course
            return
        }
        guard usesTouchInput || hasLearnedPhysicalPadMap else {
            layoutStatus = "Aprende primero las 16 posiciones del controlador para practicar con puntuación."
            selectedTab = .layouts
            return
        }
        if let incompatibility = layoutCompatibilityMessage(for: exercise) {
            layoutStatus = incompatibility
            selectedTab = .layouts
            return
        }
        guard hasCalibrationForCurrentRoute else {
            calibrationStatus = "Calibra la entrada y la salida antes de puntuar."
            return
        }
        guard startAudioEngine() else { return }
        // Activar la sesión puede cambiar frecuencia o buffer. La compensación
        // anterior no es válida para puntuar con una ruta efectiva distinta.
        guard hasCalibrationForCurrentRoute else {
            calibrationStatus = "La configuración efectiva de audio cambió. Calibra esta ruta antes de puntuar."
            return
        }
        stopPreview()
        var sessionBPM = selectedBPM
        var sessionRepeats = selectedRepeats
        var selectedSounds = selectedPracticeSounds.isEmpty ? Set(exercise.notes.map(\.sound)) : selectedPracticeSounds
        if trainingPhase == .isolate {
            if selectedPracticeSounds.isEmpty {
                let weakest = recentAttempts.first?.soundStatistics.min(by: { $0.accuracy < $1.accuracy })?.sound
                    ?? exercise.notes.first?.sound
                if let weakest { selectedPracticeSounds = [weakest]; selectedSounds = [weakest] }
            }
            sessionBPM = max(40, Int((Double(selectedBPM) * 0.8).rounded()))
            sessionRepeats = 2
        } else if trainingPhase == .integrate && selectedPracticeSounds.isEmpty {
            selectAllPracticeSounds()
        }
        if trainingPhase == .transfer {
            selectedPracticeSounds = []
            practiceFragment = 0
            selectedSounds = Set(exercise.notes.map(\.sound))
        }

        let fullPatternExercise = PracticeConfiguration(exercise: exercise, bpm: sessionBPM, repeats: sessionRepeats).applying(to: exercise)
        let scoredNotes = PracticeConfiguration.notes(in: fullPatternExercise, fragment: practiceFragment, stepRange: correctiveStepRange)
            .filter { selectedSounds.contains($0.sound) }
        guard !scoredNotes.isEmpty else {
            courseStatus = "Esa selección no contiene golpes puntuables. Elige otra voz o fragmento."
            return
        }
        let scoredExercise = Exercise(
            format: fullPatternExercise.format,
            id: fullPatternExercise.id,
            title: fullPatternExercise.title,
            family: fullPatternExercise.family,
            level: fullPatternExercise.level,
            bpm: fullPatternExercise.bpm,
            meter: fullPatternExercise.meter,
            bars: fullPatternExercise.bars,
            grid: fullPatternExercise.grid,
            repeats: fullPatternExercise.repeats,
            kit: fullPatternExercise.kit,
            loop: fullPatternExercise.loop,
            offset: fullPatternExercise.offset,
            notes: scoredNotes,
            metadata: fullPatternExercise.metadata
        )
        let fullSoundSet = Set(fullPatternExercise.notes.map(\.sound))
        let scope: EvaluationScope
        if correctiveStepRange != nil { scope = .corrective }
        else if practiceFragment != 0 { scope = .fragment }
        else if trainingPhase == .isolate && selectedSounds.count == 1 { scope = .corrective }
        else if selectedSounds != fullSoundSet { scope = .selectedVoices }
        else { scope = .fullPattern }
        beginPractice(
            exercise: scoredExercise,
            calibration: false,
            offsetMilliseconds: calibrationOffsetMilliseconds,
            fullPatternExercise: fullPatternExercise,
            evaluationScope: scope
        )
        correctiveStepRange = nil
    }

    func startGuidedLesson() {
        trainingPhase = .integrate
        UserDefaults.standard.set(TrainingPhase.integrate.rawValue, forKey: "xRoll.ios.trainingPhase")
        gapMetronomeLevel = 0
        practiceFragment = 0
        correctiveStepRange = nil
        selectAllPracticeSounds()
        startPractice()
    }

    var canPreviewSelectedExercise: Bool {
        guard let exercise = selectedExercise, isExerciseAvailable(exercise) else { return false }
        if !usesTouchInput && (midiInput == nil || !hasLearnedPhysicalPadMap) { return false }
        return isLayoutCompatible(with: exercise)
    }

    func previewExercise() {
        guard let exercise = selectedExercise, canPreviewSelectedExercise else {
            layoutStatus = "Conecta y aprende el controlador, o elige un layout compatible, para escuchar y colocar este ritmo."
            if !usesTouchInput { selectedTab = .layouts }
            return
        }
        stopPreview()
        finishTask?.cancel()
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        guard startAudioEngine() else { return }

        let configured = PracticeConfiguration(exercise: exercise, bpm: selectedBPM, repeats: 1).applying(to: exercise)
        let timeline = ExerciseTimeline(exercise: configured)
        let leadMilliseconds = timeline.barDurationMilliseconds * 2
        let now = AudioClock.hostTime(afterMilliseconds: 40)
        let start = AudioClock.hostTime(afterMilliseconds: leadMilliseconds, from: now)
        let lanes = slotsBySound()
        let labels = Dictionary(uniqueKeysWithValues: kit?.sounds.map { ($0.id, $0.label) } ?? [])
        previewScene = PracticeScene(
            timeline: timeline,
            startHostTime: start,
            anticipationMilliseconds: leadMilliseconds,
            slotBySound: lanes,
            soundLabels: labels,
            showsSoundLabels: true,
            predictsPresentationFrame: predictsVisualFrame
        )
        for note in timeline.notes {
            do {
                try audio?.schedule(
                    soundID: note.sound,
                    atHostTime: AudioClock.hostTime(afterMilliseconds: note.timeMilliseconds, from: start)
                )
            } catch {
                status = "No se pudo preparar la escucha: \(error.localizedDescription)"
                stopPreview()
                return
            }
        }
        do { try audio?.flushScheduledSounds() }
        catch {
            status = "No se pudo preparar el choke del acompañamiento: \(error.localizedDescription)"
            stopPreview()
            return
        }
        scheduleMetronome(timeline: timeline, repeats: 1, leadMilliseconds: leadMilliseconds, from: now, gapLevel: 0)
        if loopEnabled {
            do {
                guard audio?.loopTempo != nil else { throw SampleAudioEngineError.loopNotLoaded }
                try audio?.startLoop(atHostTime: now, targetBPM: Double(configured.bpm), volume: Float(loopVolume))
                loopStatus = "Acompañamiento programado desde la cuenta de entrada."
            } catch {
                loopStatus = "No se pudo iniciar el acompañamiento: \(error.localizedDescription)"
            }
        }
        isPreviewing = true
        previewToken = UUID()
        let token = previewToken
        let duration = leadMilliseconds + timeline.patternDurationMilliseconds + 500
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000))
            guard !Task.isCancelled, let self, self.previewToken == token else { return }
            self.stopPreview()
        }
    }

    func startScoredPracticeAfterPreview() {
        if trainingPhase == .discover { setTrainingPhase(.integrate) }
        stopPreview()
        startPractice()
    }

    func stopPreview() {
        previewToken = UUID()
        previewTask?.cancel()
        previewTask = nil
        guard isPreviewing || previewScene != nil else { return }
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        previewScene = nil
        isPreviewing = false
    }

    func setSelectedRepeats(_ value: Int) {
        guard let exercise = selectedExercise else { return }
        let normalized = PracticeConfiguration.normalizedRepeats(value)
        let currentStep = TempoLadder.steps(for: exercise).first(where: { $0.bpm == selectedBPM })
        let requiredRepeats = currentStep.flatMap { TempoLadder.repeats(for: $0, exercise: exercise) } ?? 1
        selectedRepeats = max(normalized, requiredRepeats)
        savePracticePreferences()
    }

    func setSelectedBPM(_ value: Int) {
        selectedBPM = min(240, max(40, value))
        if let exercise = selectedExercise {
            if let step = TempoLadder.steps(for: exercise).first(where: { $0.bpm == selectedBPM }),
               let minimum = TempoLadder.repeats(for: step, exercise: exercise) {
                selectedRepeats = max(selectedRepeats, minimum)
            }
            updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        }
        savePracticePreferences()
    }

    var availablePracticeSounds: [String] {
        let available = Set(selectedExercise?.notes.map(\.sound) ?? [])
        return kit?.sounds.map(\.id).filter { available.contains($0) } ?? available.sorted()
    }

    var isFullRhythmSelection: Bool {
        selectedPracticeSounds.isEmpty || selectedPracticeSounds == Set(availablePracticeSounds)
    }

    func setGapMetronomeLevel(_ level: Int) {
        gapMetronomeLevel = min(3, max(0, level))
        UserDefaults.standard.set(gapMetronomeLevel, forKey: "xRoll.ios.gapMetronomeLevel")
    }

    func setTrainingPhase(_ phase: TrainingPhase) {
        trainingPhase = phase
        UserDefaults.standard.set(phase.rawValue, forKey: "xRoll.ios.trainingPhase")
        if phase == .transfer {
            selectAllPracticeSounds()
            practiceFragment = 0
        }
    }

    func setPracticeHelp(_ help: PracticeHelp) {
        practiceHelp = help
        UserDefaults.standard.set(help.rawValue, forKey: "xRoll.ios.practiceHelp")
    }

    func togglePracticeSound(_ sound: String) {
        let available = Set(availablePracticeSounds)
        guard available.contains(sound) else { return }
        var selection = selectedPracticeSounds.isEmpty ? available : selectedPracticeSounds
        if selection.contains(sound) { selection.remove(sound) }
        else { selection.insert(sound) }
        selectedPracticeSounds = selection == available ? [] : selection
    }

    func selectAllPracticeSounds() {
        selectedPracticeSounds = []
    }

    func setPracticeFragment(_ fragment: Int) {
        practiceFragment = min(2, max(0, fragment))
    }

    private func loadTrainingPreferences() {
        if let phase = UserDefaults.standard.string(forKey: "xRoll.ios.trainingPhase").flatMap(TrainingPhase.init(rawValue:)) {
            trainingPhase = phase
        }
        if let help = UserDefaults.standard.string(forKey: "xRoll.ios.practiceHelp").flatMap(PracticeHelp.init(rawValue:)) {
            practiceHelp = help
        }
        gapMetronomeLevel = min(3, max(0, UserDefaults.standard.integer(forKey: "xRoll.ios.gapMetronomeLevel")))
    }

    func setMetronomeEnabled(_ enabled: Bool) {
        metronomeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "xRoll.ios.metronomeEnabled")
        metronomeStatus = enabled ? "Se programará al iniciar la práctica." : "Metrónomo desactivado."
    }

    func setMetronomeVolume(_ volume: Double) {
        metronomeVolume = min(1, max(0, volume))
        UserDefaults.standard.set(metronomeVolume, forKey: "xRoll.ios.metronomeVolume")
    }

    func setMetronomePitchSemitones(_ semitones: Double) {
        metronomePitchSemitones = min(24, max(-12, semitones.rounded()))
        UserDefaults.standard.set(metronomePitchSemitones, forKey: "xRoll.ios.metronomePitchSemitones")
    }

    func previewMetronome() {
        guard !isPracticing, !isPreviewing else {
            metronomeStatus = "Detén la sesión para probar el metrónomo."
            return
        }
        guard let audio, startAudioEngine() else { return }
        do {
            try audio.previewMetronome(
                volume: Float(metronomeVolume),
                pitchCents: Float(metronomePitchSemitones * 100)
            )
            metronomeStatus = audio.metronomeSourceName.map { "Prueba: \($0)" } ?? "Prueba del sonido de claqueta del kit."
        } catch {
            metronomeStatus = "No se pudo reproducir el metrónomo: \(error.localizedDescription)"
        }
    }

    func setLoopEnabled(_ enabled: Bool) {
        guard loopOptions.contains(where: { $0.id == selectedLoopID }) else {
            loopEnabled = false
            loopStatus = "No hay un loop cargado para esta app."
            return
        }
        loopEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "xRoll.ios.loopEnabled")
        if !enabled { audio?.stopLoop() }
        loopStatus = enabled ? "El acompañamiento se iniciará con la próxima práctica." : "Acompañamiento desactivado."
    }

    func setLoopVolume(_ volume: Double) {
        loopVolume = min(1, max(0, volume))
        UserDefaults.standard.set(loopVolume, forKey: "xRoll.ios.loopVolume")
    }

    func setLoopSelectionChoice(_ choice: String) {
        if choice == LoopLibraryCatalog.automaticSelectionID {
            loopSelectionIsAutomatic = true
            UserDefaults.standard.set(true, forKey: "xRoll.ios.loopSelectionAutomatic")
            if let exercise = selectedExercise { updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM) }
        } else {
            selectLoop(choice)
        }
    }

    func selectLoop(_ id: String) {
        guard !isPracticing, !isPreviewing, loopOptions.contains(where: { $0.id == id }) else {
            loopStatus = "Detén la práctica antes de cambiar el loop."
            return
        }
        loopSelectionIsAutomatic = false
        UserDefaults.standard.set(false, forKey: "xRoll.ios.loopSelectionAutomatic")
        UserDefaults.standard.set(id, forKey: "xRoll.ios.selectedLoop")
        loadLoopOption(id)
    }

    private func restoreLoopSelection() {
        guard !loopOptions.isEmpty else { return }
        if loopSelectionIsAutomatic {
            if let exercise = selectedExercise { updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM) }
        } else if let id = UserDefaults.standard.string(forKey: "xRoll.ios.selectedLoop"), loopOptions.contains(where: { $0.id == id }) {
            loadLoopOption(id)
        } else {
            loopSelectionIsAutomatic = true
            UserDefaults.standard.set(true, forKey: "xRoll.ios.loopSelectionAutomatic")
            if let exercise = selectedExercise { updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM) }
        }
    }

    private func updateAutomaticLoopSelection(for exercise: Exercise, targetBPM: Int) {
        guard loopSelectionIsAutomatic,
              let option = LoopLibraryCatalog.recommended(for: exercise, targetBPM: Double(targetBPM), options: loopOptions),
              selectedLoopID != option.id else { return }
        loadLoopOption(option.id)
    }

    private func loadLoopOption(_ id: String) {
        guard !isPracticing, !isPreviewing,
              let option = loopOptions.first(where: { $0.id == id }) else {
            loopStatus = "Detén la práctica antes de cambiar el loop."
            return
        }
        let reconnectSource = midiInput == nil ? nil : connectedMIDISourceID
        midiInput = nil
        connectedMIDISourceID = nil
        connectedMIDISourceEndpoint = nil
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        do {
            try audio?.loadLoop(url: option.url)
            selectedLoopID = option.id
            if !loopSelectionIsAutomatic {
                UserDefaults.standard.set(option.id, forKey: "xRoll.ios.selectedLoop")
            }
            loopStatus = option.bpm.map { String(format: "\(option.fileName) · fuente %.0f BPM", $0) } ?? option.fileName
        } catch {
            loopStatus = "No se pudo cargar el loop: \(error.localizedDescription)"
        }
        if let reconnectSource { connectMIDISource(reconnectSource) }
    }

    private func loadLoopLibrary(bundle: Bundle) {
        guard let directory = bundle.url(forResource: "Loops", withExtension: nil) else {
            loopOptions = []
            loopStatus = "No hay loops incluidos en esta app."
            return
        }
        loopOptions = LoopLibraryCatalog.discover(in: directory)
        guard !loopOptions.isEmpty else {
            loopStatus = "No hay loops compatibles incluidos."
            return
        }
        loopStatus = "Selecciona un loop para el acompañamiento."
    }

    private func startAudioEngine() -> Bool {
        do {
            try withSuspendedMIDIInput {
                try configureAudioSession()
                try audio?.start()
            }
            refreshAudioConfigurationStatus()
            if !hasCalibrationForCurrentRoute { loadCalibrationForCurrentRoute() }
            return audio != nil
        } catch {
            status = "No se pudo iniciar el audio: \(error.localizedDescription)"
            return false
        }
    }

    private func configureAudioSession(reapplyPreference: Bool = false) throws {
        try withSuspendedMIDIInput {
            try applyAudioSessionConfiguration(reapplyPreference: reapplyPreference)
        }
    }

    /// El cierre de MIDIInputSession espera al worker de entrega. La ruta no
    /// se reconfigura mientras puede estar reproduciendo un golpe vivo.
    private func withSuspendedMIDIInput(_ operation: () throws -> Void) rethrows {
        let reconnectSource = midiInput == nil ? nil : connectedMIDISourceID
        midiInput = nil
        connectedMIDISourceID = nil
        connectedMIDISourceEndpoint = nil
        defer {
            if let reconnectSource { connectMIDISource(reconnectSource) }
        }
        try operation()
    }

    private func applyAudioSessionConfiguration(reapplyPreference: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if !audioSessionConfigured || reapplyPreference || ioBufferPreferenceError != nil {
            if session.category != .playback || session.mode != .default {
                try session.setCategory(.playback, mode: .default)
            }
            do {
                try session.setPreferredIOBufferDuration(Self.preferredIOBufferDuration)
                ioBufferPreferenceError = nil
            } catch {
                // El sistema puede rechazar la preferencia para una ruta concreta;
                // se conserva su buffer efectivo y la app sigue reproduciendo.
                ioBufferPreferenceError = error.localizedDescription
            }
            audioSessionConfigured = true
        }
        try session.setActive(true)
        refreshAudioConfigurationStatus()
    }

    private func refreshAudioConfigurationStatus() {
        let session = AVAudioSession.sharedInstance()
        let requestedMilliseconds = Self.preferredIOBufferDuration * 1_000
        let effectiveMilliseconds = session.ioBufferDuration * 1_000
        let effectiveFrames = Int((session.ioBufferDuration * session.sampleRate).rounded())
        let preference = ioBufferPreferenceError.map { " · preferencia no aplicada: \($0)" } ?? ""
        audioConfigurationStatus = String(
            format: "Buffer solicitado %.2f ms · efectivo %.2f ms (%d frames) · %.0f Hz%@",
            requestedMilliseconds,
            effectiveMilliseconds,
            effectiveFrames,
            session.sampleRate,
            preference
        )
    }

    private func handleAudioInterruption() {
        stopPreview()
        if isPracticing {
            cancelActivePractice(message: "El audio se interrumpió; el intento se canceló y no cuenta para el curso.")
        }
        if isPracticePaused { discardPausedPractice() }
        status = "El audio se interrumpió. Cuando vuelva la salida, comprueba la ruta y calibra si cambió."
    }

    func handleAppBecameInactive() {
        if isLearningPadMap { cancelPadMapping() }
        stopPreview()
        if isPracticing { cancelActivePractice(message: "La app pasó a segundo plano; el intento se canceló y no cuenta para el curso.") }
        if isPracticePaused { discardPausedPractice() }
    }

    private func loadMetronomePreferences() {
        if let enabled = UserDefaults.standard.object(forKey: "xRoll.ios.metronomeEnabled") as? Bool {
            metronomeEnabled = enabled
        }
        if let volume = UserDefaults.standard.object(forKey: "xRoll.ios.metronomeVolume") as? Double {
            metronomeVolume = min(1, max(0, volume))
        }
        if let pitch = UserDefaults.standard.object(forKey: "xRoll.ios.metronomePitchSemitones") as? Double {
            metronomePitchSemitones = min(24, max(-12, pitch))
        }
    }

    func startGuidedCalibration() {
        guard usesTouchInput || midiInput != nil else {
            calibrationStatus = "Conecta la entrada MIDI seleccionada antes de calibrar."
            selectedTab = .layouts
            return
        }
        guard let exercise = exercises.first(where: { $0.id == "02_sub_02_corcheas" }) else {
            calibrationStatus = "No se encontró el ejercicio MIDI de calibración."
            return
        }
        let calibrationExercise = PracticeConfiguration(exercise: exercise, bpm: exercise.bpm, repeats: 8).applying(to: exercise)
        guard startAudioEngine() else { return }
        calibrationTargetSounds = Set(calibrationExercise.notes.map(\.sound))
        calibrationStatus = "Sigue dos compases de cuenta atrás y toca cada nota de charles."
        beginPractice(exercise: calibrationExercise, calibration: true, offsetMilliseconds: 0)
    }

    func setVisualFramePrediction(_ enabled: Bool) {
        guard predictsVisualFrame != enabled else { return }
        predictsVisualFrame = enabled
        UserDefaults.standard.set(enabled, forKey: "xRoll.ios.predictVisualFrame")
        scene?.setPredictsPresentationFrame(enabled)
    }

    func returnToPreparation() {
        cancelResultTransition()
        if let exercise = selectedExercise {
            if isCheckpointAssessment {
                selectedBPM = CourseLessonCriteria.targetBPM(for: exercise)
                selectedRepeats = PracticeConfiguration.normalizedRepeats(exercise.repeats)
            } else {
                selectPendingTempo(for: exercise)
            }
            savePracticePreferences()
        }
        showsResult = false
    }

    func returnToCourseMenu() {
        cancelResultTransition()
        activeDailyBlockID = nil
        coachingFlowStage = .none
        coachingBaselineAttempt = nil
        canReturnToFullGroove = false
        correctiveStepRange = nil
        practiceFragment = 0
        selectedPracticeSounds = []
        showsResult = false
        selectedTab = selectedExercise?.metadata?.chapter.hasPrefix("fills-") == true ? .fills : .course
        isCheckpointAssessment = false
    }

    func repeatLastExercise() {
        cancelResultTransition()
        showsResult = false
        startPractice()
    }

    func selectCourseExercise(_ exerciseID: String) {
        selectExerciseForPractice(exerciseID, returnTo: .course)
    }

    func selectFillExercise(_ exerciseID: String) {
        selectExerciseForPractice(exerciseID, returnTo: .fills)
    }

    func selectCourseCheckpoint(_ exerciseID: String) {
        guard let checkpoint = courseGraph?.node(for: exerciseID),
              checkpoint.metadata.flags.contains("checkpoint"),
              let exercise = exercises.first(where: { $0.id == exerciseID }) else { return }
        selectExerciseForPractice(exerciseID, returnTo: .course)
        isCheckpointAssessment = true
        selectedBPM = CourseLessonCriteria.targetBPM(for: exercise)
        selectedRepeats = PracticeConfiguration.normalizedRepeats(exercise.repeats)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        trainingPhase = .integrate
        practiceFragment = 0
        selectedPracticeSounds = []
        correctiveStepRange = nil
        UserDefaults.standard.set(TrainingPhase.integrate.rawValue, forKey: "xRoll.ios.trainingPhase")
        courseStatus = "Prueba del bloque: ritmo completo a \(selectedBPM) BPM y al menos 70 %."
        selectedTab = .practice
        savePracticePreferences()
    }

    private func selectExerciseForPractice(_ exerciseID: String, returnTo tab: iOSMainTab) {
        guard let exercise = exercises.first(where: { $0.id == exerciseID }) else { return }
        isCheckpointAssessment = false
        activeDailyBlockID = nil
        coachingFlowStage = .none
        coachingBaselineAttempt = nil
        canReturnToFullGroove = false
        coachingFeedback = ""
        selectedExerciseID = exercise.id
        selectPendingTempo(for: exercise)
        if tab == .fills { fillRouteStatus = "" } else { courseStatus = "" }
        selectedTab = .practice
        savePracticePreferences()
    }

    private func selectPendingTempo(for exercise: Exercise) {
        let steps = TempoLadder.steps(for: exercise)
        guard let step = TempoLadder.nextStep(for: exercise, evidence: courseEvidence) ?? steps.last else { return }
        selectedBPM = step.bpm
        selectedRepeats = TempoLadder.repeats(for: step, exercise: exercise)
            ?? PracticeConfiguration.normalizedRepeats(exercise.repeats)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
    }

    func soundVolume(_ soundID: String) -> Double { soundVolumes[soundID] ?? 1 }

    func setSoundVolume(_ volume: Double, for soundID: String) {
        guard kitSoundIDs.contains(soundID) else { return }
        let normalized = min(1.5, max(0, volume))
        soundVolumes[soundID] = normalized
        audio?.setSoundVolume(Float(normalized), for: soundID)
        UserDefaults.standard.set(soundVolumes, forKey: "xRoll.ios.soundVolumes")
    }

    func resetSoundMix() {
        soundVolumes.removeAll()
        for soundID in kitSoundIDs { audio?.setSoundVolume(1, for: soundID) }
        UserDefaults.standard.removeObject(forKey: "xRoll.ios.soundVolumes")
    }

    func selectTempoStep(_ index: Int) {
        guard let exercise = selectedExercise, tempoSteps.indices.contains(index) else { return }
        guard isTempoStepAvailable(index, for: exercise) else {
            courseStatus = "Ese tempo no está disponible para este ritmo."
            return
        }
        let step = tempoSteps[index]
        selectedBPM = step.bpm
        selectedRepeats = TempoLadder.repeats(for: step, exercise: exercise)
            ?? PracticeConfiguration.normalizedRepeats(exercise.repeats)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        savePracticePreferences()
    }

    func isTempoStepAvailable(_ index: Int, for exercise: Exercise? = nil) -> Bool {
        guard let exercise = exercise ?? selectedExercise else { return false }
        let steps = TempoLadder.steps(for: exercise)
        guard steps.indices.contains(index) else { return false }
        return steps.indices.contains(index)
    }

    func passedCount(for exercise: Exercise, step: TempoPracticeStep) -> Int {
        TempoLadder.passedAttempts(for: step, exerciseID: exercise.id, evidence: courseEvidence)
    }

    func courseState(for exercise: Exercise) -> CourseLevelStatus? {
        courseLevels.first(where: { $0.exerciseID == exercise.id })?.status
    }

    func courseLevelState(for exercise: Exercise) -> CourseLevelState? {
        courseLevels.first(where: { $0.exerciseID == exercise.id })
    }

    func isExerciseAvailable(_ exercise: Exercise) -> Bool {
        exercises.contains(where: { $0.id == exercise.id })
    }

    func startRecommendedSession() {
        guard let recommendation = courseRecommendation,
              let exercise = exercises.first(where: { $0.id == recommendation.exerciseID }) else { return }
        selectExerciseForPractice(exercise.id, returnTo: .course)
        selectedBPM = recommendation.tempoStep.bpm
        selectedRepeats = TempoLadder.repeats(for: recommendation.tempoStep, exercise: exercise)
            ?? PracticeConfiguration.normalizedRepeats(exercise.repeats)
        updateAutomaticLoopSelection(for: exercise, targetBPM: selectedBPM)
        selectedTab = .practice
        savePracticePreferences()
        startGuidedLesson()
    }

    func startPadMapping() {
        guard !usesTouchInput, let source = midiSources.first(where: { $0.uniqueID == selectedMIDISourceID }),
              let sourceID = source.uniqueID, midiInput != nil else {
            layoutStatus = "Selecciona primero el controlador MIDI que quieres aprender."
            return
        }
        guard !isPracticing else {
            layoutStatus = "Termina la sesión actual antes de aprender el controlador."
            return
        }
        cancelPadMapping()
        padMapBuilder = PadMapBuilder(
            device: source.name,
            deviceUID: Int(sourceID),
            created: ISO8601DateFormatter().string(from: Date())
        )
        mappingAssignedCount = 0
        mappingMessage = "Golpea el pad físico que se ilumina en la rejilla. El orden empieza abajo a la izquierda."
        isLearningPadMap = true
        mappingStartHostTime = AudioClock.currentHostTime()
        setMIDIMapCaptureActive(true)
        selectedTab = .layouts
    }

    func cancelPadMapping() {
        setMIDIMapCaptureActive(false)
        padMapBuilder = nil
        isLearningPadMap = false
        mappingAssignedCount = 0
    }

    func selectLayout(_ preset: PadLayoutPreset) {
        if preset == .custom && (usesTouchInput || physicalMIDIMap?.preset != .custom) {
            layoutStatus = "Importa un mapa personalizado antes de seleccionar Custom."
            return
        }
        if !usesTouchInput && !hasLearnedPhysicalPadMap {
            layoutStatus = "Aprende las 16 posiciones MIDI antes de aplicar un layout."
            return
        }
        selectedLayoutPreset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: layoutPreferenceKey(for: selectedMIDISourceID))
        applyActiveLayout()
        layoutStatus = "Layout \(padMap?.name ?? preset.rawValue) aplicado; las notas y canales físicos se mantienen."
    }

    var selectedExerciseAttempts: [PracticeAttempt] {
        filteredProgressAttempts.filter { selectedProgressExerciseID.isEmpty || $0.exerciseID == selectedProgressExerciseID }.reversed()
    }

    var filteredProgressAttempts: [PracticeAttempt] {
        minimumProgressScore <= 0 ? recentAttempts : recentAttempts.filter { $0.score >= minimumProgressScore }
    }

    var historicalDiagnostics: HistoricalDiagnostics? {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return HistoricalDiagnosticsBuilder.build(attempts: selectedExerciseAttempts, exercisesByID: byID)
    }

    var masterySeals: [MasterySeal] {
        guard let exercise = exercises.first(where: { $0.id == selectedProgressExerciseID }) else { return [] }
        return MasteryEvaluator.seals(exercise: exercise, attempts: selectedExerciseAttempts)
    }

    func selectProgressExercise(_ exerciseID: String) {
        guard exercises.contains(where: { $0.id == exerciseID }) else { return }
        selectedProgressExerciseID = exerciseID
    }

    func setMinimumProgressScore(_ score: Double) {
        minimumProgressScore = [0, 50, 70, 90].contains(score) ? score : 0
    }

    func prepareProgressExport(format: String) {
        guard let progressStore else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xroll-progress-\(UUID().uuidString.lowercased()).\(format)")
        let filter = ProgressFilter(
            exerciseID: selectedProgressExerciseID.isEmpty ? nil : selectedProgressExerciseID,
            minimumScore: minimumProgressScore > 0 ? minimumProgressScore : nil
        )
        do {
            if format == "csv" { try progressStore.exportCSV(to: url, filter: filter) }
            else { try progressStore.exportJSON(to: url, filter: filter) }
            progressExportURL = url
            status = "Exportación de progreso preparada."
        } catch {
            progressExportURL = nil
            status = "No se pudo exportar el progreso: \(error.localizedDescription)"
        }
    }

    func importProgress(from url: URL) {
        progressImportMessage = ""
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let attempts = try decoder.decode([PracticeAttempt].self, from: data)
            guard !attempts.isEmpty else {
                progressImportMessage = "El archivo no contiene intentos de práctica."
                return
            }
            guard let progressStore else {
                progressImportMessage = "El historial todavía no está disponible."
                return
            }
            let importedCount = try progressStore.importAttempts(attempts)
            refreshCourseProgress()
            progressImportMessage = importedCount == 0
                ? "No había intentos nuevos; este historial ya estaba importado."
                : "Se importaron \(importedCount) intentos."
        } catch {
            progressImportMessage = "No se pudo importar el historial: \(error.localizedDescription)"
        }
    }

    func preparePadMapExport() {
        guard let padMap, !usesTouchInput, hasLearnedPhysicalPadMap else {
            mapTransferMessage = "Conecta un controlador y aprende sus 16 pads antes de exportar un mapa."
            mapExportURL = nil
            return
        }
        let safeName = padMap.name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).padmap")
        do {
            try PadMapStore.save(padMap, to: url, availableSounds: Set(kit?.sounds.map(\.id) ?? []))
            mapExportURL = url
            mapTransferMessage = "Layout \(padMap.name) listo para compartir."
        } catch {
            mapExportURL = nil
            mapTransferMessage = "No se pudo exportar el layout: \(error.localizedDescription)"
        }
    }

    func importPadMap(from url: URL) {
        guard !usesTouchInput, selectedMIDISourceID != nil, let kit else {
            mapTransferMessage = "Selecciona primero el controlador al que aplicarás el mapa."
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let map = try PadMapStore.loadV2(at: url, availableSounds: Set(kit.sounds.map(\.id)))
            guard map.pads.count == 16 else { throw AppError.incompletePadMap }
            pendingImportedMap = map
            pendingMapImportName = map.name
            isWaitingToConfirmMapImport = true
            mapTransferMessage = "Revisa el nombre y confirma antes de reemplazar el mapa guardado de este controlador."
        } catch {
            mapTransferMessage = "No se pudo importar el mapa: \(error.localizedDescription)"
        }
    }

    func confirmPadMapImport() {
        guard let imported = pendingImportedMap,
              let sourceID = selectedMIDISourceID,
              let source = midiSources.first(where: { $0.uniqueID == sourceID }) else { return }
        let rebound = PadMapV2(
            id: imported.id,
            name: imported.name,
            preset: .custom,
            orientation: imported.orientation,
            device: .init(name: source.name, uid: Int(sourceID)),
            created: imported.created,
            pads: imported.pads
        )
        do {
            try savePhysicalPadMap(rebound)
            physicalMIDIMap = rebound
            selectedLayoutPreset = rebound.preset
            UserDefaults.standard.set(rebound.preset.rawValue, forKey: layoutPreferenceKey(for: sourceID))
            applyActiveLayout()
            layoutStatus = "Layout \(padMap?.name ?? rebound.name) importado y aplicado."
            mapTransferMessage = layoutStatus
            isWaitingToConfirmMapImport = false
            pendingImportedMap = nil
        } catch {
            mapTransferMessage = "No se pudo guardar el mapa importado: \(error.localizedDescription)"
        }
    }

    func cancelPadMapImport() {
        isWaitingToConfirmMapImport = false
        pendingImportedMap = nil
        mapTransferMessage = "Importación cancelada; el mapa actual se conserva."
    }

    func reloadCommunityExercises() {
        guard let kit else { return }
        let directory = applicationSupportDirectory.appendingPathComponent("community-exercises", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded = [Exercise]()
        var knownIDs = Set(bundledExercises.map(\.id))
        for (index, url) in files.filter({ ["mid", "midi"].contains($0.pathExtension.lowercased()) })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).enumerated() {
            guard let exercise = try? MIDIExerciseLoader.load(url: url, kit: kit, level: bundledExercises.count + index + 1),
                  knownIDs.insert(exercise.id).inserted else { continue }
            loaded.append(exercise)
        }
        communityExercises = loaded
        exercises = bundledExercises + loaded
    }

    func importCommunityExercise(from url: URL) {
        guard let kit else { exerciseImportMessage = "El kit no está disponible."; return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard ["mid", "midi"].contains(url.pathExtension.lowercased()) else {
            exerciseImportMessage = "Selecciona un archivo MIDI .mid o .midi."
            return
        }
        let directory = applicationSupportDirectory.appendingPathComponent("community-exercises", isDirectory: true)
        var temporaryCopy: URL?
        defer { if let temporaryCopy { try? FileManager.default.removeItem(at: temporaryCopy) } }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stem = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
            let destination = directory.appendingPathComponent("\(stem.isEmpty ? "exercise" : stem)-\(UUID().uuidString.prefix(8)).\(url.pathExtension.lowercased())")
            try FileManager.default.copyItem(at: url, to: destination)
            temporaryCopy = destination
            let exercise = try MIDIExerciseLoader.load(url: destination, kit: kit, level: bundledExercises.count + communityExercises.count + 1)
            guard !exercises.contains(where: { $0.id == exercise.id }) else {
                throw AppError.duplicateExercise(exercise.id)
            }
            reloadCommunityExercises()
            temporaryCopy = nil
            selectedExerciseID = exercise.id
            selectedBPM = exercise.bpm
            selectedRepeats = PracticeConfiguration.normalizedRepeats(exercise.repeats)
            selectedTab = .practice
            exerciseImportMessage = "Importado: \(exercise.title). Queda disponible en MIDI importados, fuera del curso oficial."
        } catch {
            exerciseImportMessage = "No se pudo importar el MIDI: \(error.localizedDescription)"
        }
    }

    private func beginPractice(
        exercise: Exercise,
        calibration: Bool,
        offsetMilliseconds: Double,
        fullPatternExercise: Exercise? = nil,
        evaluationScope: EvaluationScope = .fullPattern
    ) {
        finishTask?.cancel()
        stopPreview()
        let practice = PracticeSession(exercise: exercise, calibrationOffsetMilliseconds: offsetMilliseconds)
        let timeline = practice.timeline
        if calibration {
            let targetsBySound = Dictionary(grouping: timeline.notes, by: \.sound)
            calibrationTraceMatchersBySound = Dictionary(uniqueKeysWithValues: targetsBySound.map { sound, notes in
                (sound, CalibrationMatcher(targetTimesMilliseconds: notes.map(\.timeMilliseconds)))
            })
        } else {
            calibrationTraceMatchersBySound.removeAll(keepingCapacity: true)
        }
        let anticipationMilliseconds = timeline.barDurationMilliseconds * 2
        let now = AudioClock.hostTime(afterMilliseconds: 40)
        let start = AudioClock.hostTime(afterMilliseconds: anticipationMilliseconds, from: now)
        let generation = UUID()
        sessionIngress.begin(practice, generation: generation, startHostTime: start)
        session = practice
        presentedSessionGeneration = generation
        activeExercise = exercise
        activeFullPatternExercise = fullPatternExercise
        activeEvaluationScope = calibration ? .fullPattern : evaluationScope
        activeTrainingPhase = calibration ? .integrate : trainingPhase
        activeGapMetronomeLevel = calibration ? 0 : gapMetronomeLevel
        activeShowsVisualGuides = calibration || (trainingPhase != .transfer && practiceHelp != .reduced)
        activeCalibrationProfileKey = currentCalibrationProfileKey()
        activePracticeConditions = calibration ? nil : PracticeConditions(
            bpm: exercise.bpm,
            repeats: exercise.repeats,
            selectedSounds: Set(exercise.notes.map(\.sound)),
            stepRange: correctiveStepRange,
            gapMetronomeLevel: activeGapMetronomeLevel,
            metronomeEnabled: metronomeEnabled,
            loopEnabled: loopEnabled,
            loopIdentifier: selectedLoopID,
            showsVisualGuides: activeShowsVisualGuides,
            visualGuideLevel: practiceHelp.rawValue,
            calibrationProfileKey: activeCalibrationProfileKey
        )
        activeExpectedNotesBySound = Dictionary(grouping: timeline.notes, by: \.sound)
        activeScoringCompensationMilliseconds = offsetMilliseconds
        timingTrace.reset()
        timingTraceSessionID = UUID()
        timingTraceURL = nil
        timingTraceMessage = ""
        showsResult = false
        completedScore = nil
        resultInsights = nil
        resultSummary = nil
        resultDiagnosisText = ""
        resultActionReason = ""
        ghostCoachCue = ""
        resultHitRecords = []
        resultIsPartial = false
        resultCompletedBars = 0
        startHostTime = start
        isPracticing = true
        isCalibrating = calibration
        calibrationHitCount = 0
        calibrationHitTimesBySound.removeAll(keepingCapacity: true)
        if !calibration { calibrationTargetSounds.removeAll(keepingCapacity: true) }
        scoreText = ""
        let lanes = slotsBySound()
        let labels = Dictionary(uniqueKeysWithValues: kit?.sounds.map { ($0.id, $0.label) } ?? [])
        let hiddenGuideNoteIndices = !calibration && practiceHelp == .reduced
            ? Set(timeline.notes.lazy.filter { $0.sound == "hihat_closed" && $0.step.isMultiple(of: 4) }.map(\.index))
            : []
        let playerSounds = exercise.notes.map(\.sound)
        let isPartialSelection = activeEvaluationScope != .fullPattern
        let practiceScene = PracticeScene(
            timeline: timeline,
            startHostTime: start,
            anticipationMilliseconds: anticipationMilliseconds,
            slotBySound: lanes,
            soundLabels: labels,
            showsSoundLabels: calibration || practiceHelp == .full,
            showsNotes: calibration || trainingPhase != .transfer,
            hiddenGuideNoteIndices: hiddenGuideNoteIndices,
            emphasizesPlayerNotes: isPartialSelection,
            playerSounds: isPartialSelection ? Set(playerSounds) : nil,
            predictsPresentationFrame: predictsVisualFrame
        )
        let traceBuffer = timingTrace
        practiceScene.onFeedbackConsumed = { feedbackID, consumedHostTime in
            traceBuffer.markVisualFeedbackConsumed(feedbackID: feedbackID, hostTime: consumedHostTime)
        }
        scene = practiceScene
        if let fullPatternExercise, !calibration {
            let playerNoteKeys = Set(exercise.notes.map { "\($0.step):\($0.sound)" })
            for note in ExerciseTimeline(exercise: fullPatternExercise).notes
            where !playerNoteKeys.contains("\(note.step):\(note.sound)") {
                try? audio?.schedule(soundID: note.sound, atHostTime: AudioClock.hostTime(afterMilliseconds: note.timeMilliseconds, from: start))
            }
            try? audio?.flushScheduledSounds()
        }
        if !calibration, loopEnabled {
            do {
                guard audio?.loopTempo != nil else { throw SampleAudioEngineError.loopNotLoaded }
                try audio?.startLoop(atHostTime: now, targetBPM: Double(exercise.bpm), volume: Float(loopVolume))
                loopStatus = "Acompañamiento programado desde la cuenta de entrada."
            } catch {
                loopStatus = "No se pudo iniciar el acompañamiento: \(error.localizedDescription)"
            }
        }
        scheduleMetronome(
            timeline: timeline,
            repeats: exercise.repeats,
            leadMilliseconds: anticipationMilliseconds,
            from: now,
            gapLevel: activeGapMetronomeLevel,
            calibrationReference: calibration
        )
        finishTask = Task { [weak self] in
            let duration = anticipationMilliseconds + timeline.patternDurationMilliseconds * Double(exercise.repeats) + 200
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000))
            guard !Task.isCancelled else { return }
            self?.finishPractice()
        }
    }

    private func scheduleMetronome(timeline: ExerciseTimeline, repeats: Int, leadMilliseconds: Double, from firstClickHostTime: UInt64, gapLevel: Int, calibrationReference: Bool = false) {
        guard metronomeEnabled || calibrationReference else { return }
        let clickVolume = calibrationReference ? max(0.65, metronomeVolume) : metronomeVolume
        let beatMilliseconds = timeline.barDurationMilliseconds / 4
        let durationMilliseconds = leadMilliseconds + timeline.patternDurationMilliseconds * Double(repeats)
        let beatCount = Int(ceil(durationMilliseconds / beatMilliseconds))
        for beatIndex in 0...beatCount {
            let countInBeats = Int(leadMilliseconds / beatMilliseconds)
            let playedBeat = beatIndex - countInBeats
            let audible: Bool
            if playedBeat < 0 { audible = true }
            else { audible = GapMetronomePattern.isAudible(bar: playedBeat / 4, beat: playedBeat % 4, level: gapLevel) }
            guard audible else { continue }
            let clickHostTime = AudioClock.hostTime(afterMilliseconds: Double(beatIndex) * beatMilliseconds, from: firstClickHostTime)
            do {
                try audio?.scheduleMetronome(
                    accented: beatIndex.isMultiple(of: 4),
                    atHostTime: clickHostTime,
                    volume: Float(clickVolume),
                    pitchCents: Float(metronomePitchSemitones * 100)
                )
            } catch {
                metronomeStatus = "No se pudo programar el metrónomo: \(error.localizedDescription)"
                return
            }
        }
        metronomeStatus = calibrationReference
            ? "Claqueta de calibración programada con volumen de referencia."
            : "Metrónomo programado · volumen \(Int((metronomeVolume * 100).rounded())) %."
    }

    func registerPad(id: String, touchTimestamp: TimeInterval) {
        guard usesTouchInput else { return }
        guard let pad = pads.first(where: { $0.id == id }) else { return }
        let hostTime = touchClock.hostTime(forUptimeTimestamp: touchTimestamp)
        let audioSubmissionStart = AudioClock.currentHostTime()
        var audioSubmissionReturn: UInt64?
        var audioSubmissionError: String?
        do { try audio?.play(soundID: pad.sound) }
        catch {
            audioSubmissionError = error.localizedDescription
            status = "Error de audio: \(error.localizedDescription)"
        }
        audioSubmissionReturn = AudioClock.currentHostTime()
        lastHit = kit?.sounds.first(where: { $0.id == pad.sound })?.label ?? pad.sound
        submitPracticeInput(
            .init(
                feedbackID: UUID().uuidString,
                source: .touch,
                inputHostTime: hostTime,
                workerHostTime: nil,
                audioSubmissionStartHostTime: audioSubmissionStart,
                audioSubmissionReturnHostTime: audioSubmissionReturn,
                audioSubmissionError: audioSubmissionError,
                soundID: pad.sound,
                role: pad.role,
                padID: pad.id,
                midiEvent: nil,
                touchTimestampSeconds: touchTimestamp
            ),
            hit: TimedPadHit(sound: pad.sound, hostTime: hostTime, practiceStartHostTime: startHostTime, role: pad.role, padID: pad.id, velocity: 96)
        )
    }

    func selectMIDISource(_ sourceID: MIDIUniqueID?) {
        hasExplicitMIDISourceSelection = true
        guard selectedMIDISourceID != sourceID else { return }
        if isLearningPadMap { cancelPadMapping() }
        if isPracticePaused { discardPausedPractice() }
        if isPracticing { cancelActivePractice(message: "Cambió la entrada MIDI; se canceló la sesión para proteger el score.") }
        selectedMIDISourceID = sourceID
        if let sourceID {
            UserDefaults.standard.set(Int(sourceID), forKey: "xRoll.ios.midiSourceID")
        } else {
            UserDefaults.standard.removeObject(forKey: "xRoll.ios.midiSourceID")
        }
        midiInput = nil
        connectedMIDISourceID = nil
        connectedMIDISourceEndpoint = nil
        activateLayoutForCurrentInput()
        loadCalibrationForCurrentRoute()
        guard let sourceID else {
            midiStatus = "Solo pads táctiles"
            return
        }
        connectMIDISource(sourceID)
    }

    func refreshMIDISources() {
        updateMIDISources()
    }

    func refreshBluetoothMIDI() {
        bluetoothMIDI.refresh()
    }

    func connectBluetoothMIDI(_ deviceID: UUID) {
        UserDefaults.standard.set(deviceID.uuidString, forKey: "xRoll.ios.bluetoothMIDI.deviceID")
        bluetoothMIDI.connect(deviceID)
    }

    func disconnectBluetoothMIDI() {
        bluetoothMIDI.disconnect()
        UserDefaults.standard.removeObject(forKey: "xRoll.ios.bluetoothMIDI.deviceID")
    }

    var selectedMIDISourceName: String? {
        midiSources.first(where: { $0.uniqueID == selectedMIDISourceID })?.name
    }

    private func beginMIDIMonitoring() {
        midiSetupMonitor = try? MIDISetupMonitor { [weak self] in
            DispatchQueue.main.async { self?.updateMIDISources() }
        }
        let preferredDeviceID = UserDefaults.standard.string(forKey: "xRoll.ios.bluetoothMIDI.deviceID")
            .flatMap(UUID.init(uuidString:))
        bluetoothMIDI.start(preferredDeviceID: preferredDeviceID)
        updateMIDISources()
    }

    private func updateMIDISources() {
        let previousSelection = selectedMIDISourceID
        let refreshedSources = MIDIInspector.sources()
        midiSources = refreshedSources
        let availableIDs = refreshedSources.compactMap(\.uniqueID)

        if let selectedMIDISourceID, !availableIDs.contains(selectedMIDISourceID) {
            midiInput = nil
            connectedMIDISourceID = nil
            connectedMIDISourceEndpoint = nil
            self.selectedMIDISourceID = nil
        }

        if selectedMIDISourceID == nil,
           UserDefaults.standard.object(forKey: "xRoll.ios.midiSourceID") != nil {
            let savedID = MIDIUniqueID(UserDefaults.standard.integer(forKey: "xRoll.ios.midiSourceID"))
            if availableIDs.contains(savedID) { selectedMIDISourceID = savedID }
        }
        if selectedMIDISourceID == nil && !hasExplicitMIDISourceSelection {
            selectedMIDISourceID = refreshedSources.first(where: { $0.uniqueID != nil })?.uniqueID
        }

        if previousSelection != selectedMIDISourceID {
            if isPracticePaused { discardPausedPractice() }
            if isPracticing { cancelActivePractice(message: "Cambió la entrada MIDI; se canceló la sesión para proteger el score.") }
            if isLearningPadMap { cancelPadMapping() }
            activateLayoutForCurrentInput()
            loadCalibrationForCurrentRoute()
        }

        guard let sourceID = selectedMIDISourceID else {
            midiInput = nil
            connectedMIDISourceID = nil
            connectedMIDISourceEndpoint = nil
            midiStatus = refreshedSources.isEmpty
                ? "Sin entrada MIDI; puedes usar los pads táctiles"
                : "Las entradas MIDI detectadas no tienen identificador seleccionable"
            return
        }
        guard let endpoint = MIDIInspector.source(withUniqueID: sourceID) else {
            midiInput = nil
            connectedMIDISourceID = nil
            connectedMIDISourceEndpoint = nil
            midiStatus = "La entrada MIDI seleccionada se desconectó"
            return
        }
        if connectedMIDISourceID == sourceID,
           connectedMIDISourceEndpoint != endpoint,
           isPracticing {
            cancelActivePractice(message: "Se reconectó la fuente MIDI; se canceló la sesión para proteger el score.")
        }
        if connectedMIDISourceID != sourceID || connectedMIDISourceEndpoint != endpoint || midiInput == nil {
            connectMIDISource(sourceID)
        }
    }

    private func connectMIDISource(_ sourceID: MIDIUniqueID) {
        guard let endpoint = MIDIInspector.source(withUniqueID: sourceID) else {
            midiInput = nil
            connectedMIDISourceID = nil
            connectedMIDISourceEndpoint = nil
            midiStatus = "La entrada MIDI seleccionada se desconectó"
            return
        }
        guard let liveMIDI, let audio else {
            midiStatus = "El motor de audio no está preparado para la entrada MIDI."
            return
        }
        do {
            let bridge = iOSMIDIPlaybackBridge(
                liveMIDI: liveMIDI,
                audio: audio,
                mappingGate: midiMappingGate,
                sessionIngress: sessionIngress,
                onMappingEvent: { [weak self] event in
                    DispatchQueue.main.async { [weak self] in self?.captureMappingEvent(event) }
                },
                onDelivery: { [weak self] context, generation, processingResult in
                    DispatchQueue.main.async { [weak self] in
                        self?.handleResolvedMIDI(
                            context,
                            generation: generation,
                            processingResult: processingResult
                        )
                    }
                }
            )
            let session = try MIDIInputSession { event in bridge.receive(event) }
            try session.connect(source: endpoint)
            midiInput = session
            connectedMIDISourceID = sourceID
            connectedMIDISourceEndpoint = endpoint
            midiStatus = "MIDI conectado: \(selectedMIDISourceName ?? "Controlador")"
        } catch {
            midiInput = nil
            connectedMIDISourceID = nil
            connectedMIDISourceEndpoint = nil
            midiStatus = "No se pudo conectar MIDI: \(error.localizedDescription)"
        }
    }

    private func handleResolvedMIDI(
        _ context: iOSPracticeInputContext,
        generation: UUID?,
        processingResult: PracticeSessionProcessingResult?
    ) {
        if let generation, let processingResult {
            guard presentedSessionGeneration == generation else { return }
            deliverPracticeInput(context, generation: generation, processingResult: processingResult)
            return
        }
        if let event = context.midiEvent {
            lastMIDINote = "Nota \(event.note) · canal \(event.channel) · velocity \(event.velocity)"
        }
        if let soundID = context.soundID {
            lastHit = kit?.sounds.first(where: { $0.id == soundID })?.label ?? soundID
        }
        if let audioSubmissionError = context.audioSubmissionError {
            status = "Error al reproducir MIDI: \(audioSubmissionError)"
        }
    }

    private func submitPracticeInput(_ context: iOSPracticeInputContext, hit: TimedPadHit) {
        let admittedGeneration = sessionIngress.submit(hit) { [weak self] generation, processingResult in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentedSessionGeneration == generation else { return }
                self.deliverPracticeInput(context, generation: generation, processingResult: processingResult)
            }
        }
        guard admittedGeneration != nil else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let event = context.midiEvent {
                    self.lastMIDINote = "Nota \(event.note) · canal \(event.channel) · velocity \(event.velocity)"
                }
                if let soundID = context.soundID {
                    self.lastHit = self.kit?.sounds.first(where: { $0.id == soundID })?.label ?? soundID
                }
                if let error = context.audioSubmissionError { self.status = "Error al reproducir MIDI: \(error)" }
            }
            return
        }
    }

    private func deliverPracticeInput(_ context: iOSPracticeInputContext, generation: UUID, processingResult: PracticeSessionProcessingResult) {
        guard presentedSessionGeneration == generation else { return }
        let discarding = discardingPracticeGeneration == generation
        let mainDeliveryHostTime = AudioClock.currentHostTime()
        let visualSnapshot = scene?.visualClockSnapshot
        if let event = context.midiEvent {
            lastMIDINote = "Nota \(event.note) · canal \(event.channel) · velocity \(event.velocity)"
        }
        if let error = context.audioSubmissionError {
            status = "Error al reproducir MIDI: \(error)"
        }
        if let soundID = context.soundID {
            lastHit = kit?.sounds.first(where: { $0.id == soundID })?.label ?? soundID
        }

        var calibrationAssociation: CalibrationHitAssociation?
        if !discarding, let sound = context.soundID, isCalibrating, calibrationTargetSounds.contains(sound) {
            let rawTimeMilliseconds = AudioClock.milliseconds(from: startHostTime, to: context.inputHostTime)
            calibrationHitTimesBySound[sound, default: []].append(rawTimeMilliseconds)
            calibrationHitCount += 1
            if var matcher = calibrationTraceMatchersBySound[sound] {
                calibrationAssociation = matcher.associateHit(atMilliseconds: rawTimeMilliseconds)
                calibrationTraceMatchersBySound[sound] = matcher
            }
        }
        let result = processingResult.scoredHit
        let registration = result.map { iOSRegisteredHit(scoredHit: $0, calibrationAssociation: calibrationAssociation) }
        if !discarding, let result {
            for missedNote in processingResult.expiredMisses {
                scene?.showFeedback(sound: missedNote.sound, judgement: .miss, noteIndex: missedNote.index)
            }
            if let offset = result.offsetMilliseconds {
                scene?.showFeedback(feedbackID: context.feedbackID, sound: result.expectedNote?.sound ?? context.soundID ?? "", judgement: result.judgement, noteIndex: result.expectedNote?.index, offsetMilliseconds: offset, occurredAtHostTime: context.inputHostTime)
            } else {
                scene?.showFeedback(feedbackID: context.feedbackID, sound: context.soundID ?? "", judgement: .extra, occurredAtHostTime: context.inputHostTime)
            }
        } else if !discarding, let soundID = context.soundID {
            scene?.showWarmupHit(feedbackID: context.feedbackID, sound: soundID)
        }
        recordTimingSample(
            source: context.source,
            feedbackID: context.feedbackID,
            inputHostTime: context.inputHostTime,
            workerHostTime: context.workerHostTime,
            audioSubmissionStartHostTime: context.audioSubmissionStartHostTime,
            audioSubmissionReturnHostTime: context.audioSubmissionReturnHostTime,
            sessionProcessingStartHostTime: processingResult.startedHostTime,
            sessionProcessingEndHostTime: processingResult.completedHostTime,
            audioSubmissionError: context.audioSubmissionError,
            mainDeliveryHostTime: mainDeliveryHostTime,
            visualSnapshot: visualSnapshot,
            scoredHit: registration?.scoredHit,
            calibrationAssociation: registration?.calibrationAssociation,
            soundID: context.soundID,
            midiEvent: context.midiEvent,
            touchTimestampSeconds: context.touchTimestampSeconds
        )
    }

    func stopPractice() {
        if isPracticePaused {
            discardPausedPractice()
            return
        }
        if isCalibrating {
            cancelActivePractice(message: "Calibración cancelada; todavía no se guardó un perfil.")
            return
        }
        finishTask?.cancel()
        finishPractice()
    }

    func pausePractice() {
        guard isPracticing, let activeExercise else { return }
        finishTask?.cancel()
        finishTask = nil
        if presentedSessionGeneration != nil {
            sessionIngress.cancel { _ in }
            presentedSessionGeneration = nil
        }
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        pausedExercise = activeExercise
        pausedFullPatternExercise = activeFullPatternExercise
        pausedEvaluationScope = activeEvaluationScope
        pausedCalibration = isCalibrating
        pausedScoringOffset = activeScoringCompensationMilliseconds
        pausedCalibrationProfileKey = activeCalibrationProfileKey
        session = nil
        self.activeExercise = nil
        activeFullPatternExercise = nil
        activeExpectedNotesBySound.removeAll(keepingCapacity: true)
        scene = nil
        isPracticing = false
        isCalibrating = false
        isPracticePaused = true
        calibrationHitTimesBySound.removeAll(keepingCapacity: true)
        calibrationTraceMatchersBySound.removeAll(keepingCapacity: true)
    }

    func resumePracticeFromPause() {
        guard isPracticePaused, let pausedExercise else { return }
        guard pausedCalibrationProfileKey == currentCalibrationProfileKey(),
              pausedCalibration || hasCalibrationForCurrentRoute else {
            discardPausedPractice()
            calibrationStatus = "La ruta de práctica cambió o ya no está calibrada. Calibra de nuevo antes de puntuar."
            return
        }
        guard startAudioEngine() else { return }
        let exercise = pausedExercise
        let fullPatternExercise = pausedFullPatternExercise
        let scope = pausedEvaluationScope
        let calibration = pausedCalibration
        let offset = pausedScoringOffset
        clearPausedPractice()
        beginPractice(
            exercise: exercise,
            calibration: calibration,
            offsetMilliseconds: offset,
            fullPatternExercise: fullPatternExercise,
            evaluationScope: scope
        )
    }

    private func discardPausedPractice() {
        let wasCalibration = pausedCalibration
        clearPausedPractice()
        if wasCalibration { calibrationStatus = "Calibración cancelada; todavía no se guardó un perfil." }
    }

    private func clearPausedPractice() {
        isPracticePaused = false
        pausedExercise = nil
        pausedFullPatternExercise = nil
        pausedCalibration = false
        pausedScoringOffset = 0
        pausedCalibrationProfileKey = nil
    }

    func performResultAction() {
        switch resultProgressSuggestion {
        case .raise: raiseTempoLevel(); return
        case .next: startNextCourseExercise(); return
        case nil: break
        }
        switch resultSummary?.action {
        case .corrective:
            repeatLastExercise()
        case .repeatWithAdjustment:
            applyAutopilotAdjustment()
            repeatLastExercise()
        case .advance:
            startRecommendedSession()
        case .repeatSame, nil:
            repeatLastExercise()
        }
    }

    private func applyAutopilotAdjustment() {
        guard let recommendation = autopilotRecommendation else { return }
        selectedBPM = min(240, max(40, selectedBPM + recommendation.bpmAdjustment))
        selectedRepeats = PracticeConfiguration.normalizedRepeats(recommendation.repeats)
        practiceHelp = recommendation.help
        UserDefaults.standard.set(practiceHelp.rawValue, forKey: "xRoll.ios.practiceHelp")
        savePracticePreferences()
    }

    func startCorrectivePractice() {
        guard let plan = correctivePlan, selectedExercise != nil else {
            repeatLastExercise()
            return
        }
        coachingBaselineAttempt = ((try? progressStore?.attempts(filter: .init(exerciseID: selectedExercise?.id), limit: 100)) ?? [])
            .first(where: { $0.trainingContext.evaluationScope == .fullPattern && $0.trainingContext.practiceConditions != nil })
        coachingFlowStage = .isolating
        canReturnToFullGroove = false
        coachingFeedback = ""
        trainingPhase = .isolate
        selectedPracticeSounds = [plan.focusSound]
        practiceFragment = 0
        correctiveStepRange = plan.stepRange
        selectedRepeats = 2
        showsResult = false
        startPractice()
    }

    func returnToFullGroove() {
        guard coachingFlowStage == .isolating, let exercise = selectedExercise,
              let conditions = coachingBaselineAttempt?.trainingContext.practiceConditions else { return }
        trainingPhase = .integrate
        selectedPracticeSounds = []
        practiceFragment = 0
        correctiveStepRange = nil
        selectedBPM = conditions.bpm
        selectedRepeats = conditions.repeats
        gapMetronomeLevel = conditions.gapMetronomeLevel
        metronomeEnabled = conditions.metronomeEnabled
        loopEnabled = conditions.loopEnabled
        practiceHelp = conditions.visualGuideLevel.flatMap(PracticeHelp.init(rawValue:))
            ?? (conditions.showsVisualGuides ? .full : .reduced)
        canReturnToFullGroove = false
        coachingFlowStage = .integrating
        showsResult = false
        selectedExerciseID = exercise.id
        startPractice()
    }

    func startPulseTraining() {
        guard let exercise = selectedExercise else { return }
        let attempts = (try? progressStore?.attempts(filter: .init(exerciseID: exercise.id), limit: 100)) ?? recentAttempts
        pulseTrainingStage = PulseTrainingPlan.nextStage(after: attempts, exerciseID: exercise.id, exercise: exercise)
        if previousPulseLoopEnabled == nil { previousPulseLoopEnabled = loopEnabled }
        loopEnabled = false
        UserDefaults.standard.set(false, forKey: "xRoll.ios.loopEnabled")
        metronomeEnabled = true
        trainingPhase = pulseTrainingStage?.phase ?? .integrate
        gapMetronomeLevel = pulseTrainingStage?.gapMetronomeLevel ?? 0
        practiceHelp = pulseTrainingStage?.showsVisualGuides == true ? .full : .normal
        selectedPracticeSounds = []
        practiceFragment = 0
        correctiveStepRange = nil
        selectedTab = .practice
        showsResult = false
        pulseDriftMessage = ""
    }

    func startNextPulseStage() { startPulseTraining() }

    func startDailyPractice() {
        let today = Calendar.current.startOfDay(for: Date())
        var plan = dailyPracticePlan
        if plan?.day != today {
            let attempts = (try? progressStore?.attempts(limit: 100)) ?? recentAttempts
            plan = DailyPracticePlanner.makePlan(exercises: bundledExercises, attempts: attempts, dueGoals: coachingGoals,
                                                preferredChallengeExerciseID: courseRecommendation?.exerciseID, now: Date())
        }
        guard var plan, let block = plan.currentBlock else {
            dailyPracticePlan = plan
            dailyPracticeMessage = plan?.isComplete == true ? "Sesión diaria completada por hoy." : "No hay ejercicios disponibles para preparar la sesión."
            return
        }
        plan.markStarted()
        dailyPracticePlan = plan
        try? progressStore?.saveTrainingState(plan, forKey: "daily-practice-plan")
        prepareDailyBlock(block)
    }

    func startNextDailyBlock() {
        guard var plan = dailyPracticePlan, let block = plan.currentBlock else {
            dailyPracticeMessage = "Sesión diaria completada por hoy."
            return
        }
        plan.markStarted()
        dailyPracticePlan = plan
        try? progressStore?.saveTrainingState(plan, forKey: "daily-practice-plan")
        prepareDailyBlock(block)
    }

    func skipNextDailyBlock() {
        guard var plan = dailyPracticePlan, let block = plan.currentBlock else { return }
        _ = plan.completeBlock(block.id, skipped: true)
        dailyPracticePlan = plan
        dailyPracticeMessage = plan.isComplete ? "Rutina diaria finalizada; bloque omitido." : "Bloque omitido. Puedes continuar con el siguiente."
        try? progressStore?.saveTrainingState(plan, forKey: "daily-practice-plan")
    }

    private func prepareDailyBlock(_ block: DailyPracticeBlock) {
        guard bundledExercises.contains(where: { $0.id == block.exerciseID }) else {
            dailyPracticeMessage = "El ejercicio de esta sesión ya no está disponible."
            return
        }
        selectExerciseForPractice(block.exerciseID, returnTo: .practice)
        activeDailyBlockID = block.id
        selectedBPM = block.bpm
        selectedRepeats = block.repeats
        trainingPhase = block.phase
        gapMetronomeLevel = block.gapMetronomeLevel
        metronomeEnabled = block.metronomeEnabled
        loopEnabled = block.loopEnabled
        if let loopIdentifier = block.loopIdentifier { loadLoopOption(loopIdentifier) }
        selectedPracticeSounds = []
        practiceFragment = 0
        correctiveStepRange = nil
        showsResult = false
        dailyPracticeMessage = "\(block.title): \(block.reason)"
        courseStatus = dailyPracticeMessage
        savePracticePreferences()
    }

    private func completeActiveDailyBlock(score: ExerciseScore, exercise: Exercise) {
        guard let blockID = activeDailyBlockID, var plan = dailyPracticePlan,
              let block = plan.blocks.first(where: { $0.id == blockID }), plan.completeBlock(blockID) else { return }
        if block.kind == .review, let sound = block.focusedSound,
           let index = coachingGoals.firstIndex(where: { $0.exerciseID == exercise.id && $0.recommendation.sound == sound && $0.state != .confirmed }) {
            if let baseline = coachingGoals[index].baselineConditions, let activePracticeConditions,
               baseline.isComparableForRetention(to: activePracticeConditions) {
                let outcome = CoachingAnalyzer.reviewOutcome(for: coachingGoals[index].recommendation, score: score)
                if outcome != .insufficientEvidence {
                    coachingGoals[index].recordReview(successful: outcome == .resolved)
                    try? progressStore?.saveTrainingState(coachingGoals, forKey: "coaching-goals")
                }
            }
        }
        dailyPracticePlan = plan
        activeDailyBlockID = nil
        dailyPracticeMessage = plan.isComplete ? "Sesión diaria completada. Buen trabajo." : "Bloque terminado. Continúa con el siguiente cuando quieras."
        try? progressStore?.saveTrainingState(plan, forKey: "daily-practice-plan")
    }

    private func saveCoachingGoal(exerciseID: String, recommendation: CoachingRecommendation, conditions: PracticeConditions?) {
        guard !coachingGoals.contains(where: {
            $0.exerciseID == exerciseID && $0.recommendation.sound == recommendation.sound
                && $0.recommendation.step == recommendation.step && $0.state != .confirmed
        }) else { return }
        coachingGoals.append(CoachingGoal(exerciseID: exerciseID, recommendation: recommendation, baselineConditions: conditions))
        try? progressStore?.saveTrainingState(coachingGoals, forKey: "coaching-goals")
    }

    private func coachingComparisonMessage(_ comparison: CoachingComparison, sound: String) -> String {
        switch comparison.outcome {
        case .improved: return "\(kitLabel(for: sound)): mejora observada al volver al groove. El repaso queda programado para otro día."
        case .similar: return "\(kitLabel(for: sound)): resultado similar. Puedes repetir cuando quieras."
        case .declined: return "\(kitLabel(for: sound)): todavía necesita práctica; prueba otra vuelta con la guía."
        case .insufficientEvidence: return "Aún no hay suficientes golpes comparables para valorar \(kitLabel(for: sound))."
        case .conditionsDiffer: return "Las condiciones cambiaron; no comparamos estas rondas como una mejora."
        }
    }

    private func diagnosisText(for diagnosis: PracticeResultDiagnosis?) -> String {
        guard let diagnosis else { return "Completa una sesión para ver qué ocurrió." }
        switch diagnosis {
        case .insufficientEvidence:
            return "No hubo suficientes golpes asociados para evaluar el timing."
        case .weakSound(let sound, let accuracy, let missed):
            return "\(kitLabel(for: sound)) necesita atención: \(Int(accuracy.rounded())) % de acierto y \(missed) fallos."
        case .inconsistent(let spread):
            return "El pulso varía entre golpes: dispersión central de \(Int(spread.rounded())) ms."
        case .timingBias(let offset):
            return offset < 0
                ? "Tus golpes asociados quedaron \(Int(abs(offset).rounded())) ms antes del centro puntuado."
                : "Tus golpes asociados quedaron \(Int(offset.rounded())) ms después del centro puntuado."
        case .solid:
            return "Tu pulso está centrado y el patrón se mantiene estable."
        }
    }

    private func actionReason(for action: PracticeResultAction?) -> String {
        switch action {
        case .corrective:
            return correctivePlan?.message ?? "Repite el patrón completo para superarlo. También puedes aislar la parte difícil como ayuda."
        case .repeatWithAdjustment:
            return autopilotRecommendation?.message ?? "Repite con más apoyo para centrar el patrón."
        case .advance:
            return courseRecommendation.flatMap { recommendation in
                exercises.first(where: { $0.id == recommendation.exerciseID }).map { "Has consolidado este ritmo. Sigue con \($0.title)." }
            } ?? "Has consolidado el ritmo; el curso no tiene otra estación disponible."
        case .repeatSame:
            return "El resultado es sólido: repite el mismo escalón para consolidarlo."
        case nil:
            return "Repite el patrón con la misma configuración."
        }
    }

    private func cancelResultTransition() {
        resultTransitionTask?.cancel()
        resultTransitionTask = nil
        isShowingResultTransition = false
    }

    private func presentResultTransition(percentage: Double) {
        resultTransitionTask?.cancel()
        resultTransitionPercentage = percentage
        showsResult = false
        withAnimation(.easeInOut(duration: 0.20)) { isShowingResultTransition = true }
        resultTransitionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                self.isShowingResultTransition = false
                self.showsResult = true
            }
            self.resultTransitionTask = nil
        }
    }

    private func finishPractice() {
        guard isPracticing, session != nil, activeExercise != nil,
              presentedSessionGeneration != nil else { return }
        isPracticing = false
        finishTask?.cancel()
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        let finishHostTime = AudioClock.currentHostTime()
        sessionIngress.finish { [weak self] finishedGeneration, score in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentedSessionGeneration == finishedGeneration,
                      let score else { return }
                self.completePractice(
                    score,
                    finishHostTime: finishHostTime,
                    generation: finishedGeneration
                )
            }
        }
    }

    private func completePractice(
        _ score: ExerciseScore,
        finishHostTime: UInt64,
        generation: UUID
    ) {
        guard presentedSessionGeneration == generation,
              let session,
              let exercise = activeExercise else { return }
        let elapsedMilliseconds = AudioClock.milliseconds(from: startHostTime, to: finishHostTime)
        let completion = PracticeCompletion(exercise: exercise, elapsedMilliseconds: elapsedMilliseconds)
        let totalBars = completion.totalBars
        let didCompleteWholePattern = completion.isComplete
        resultCompletedBars = completion.completedBars
        resultIsPartial = !isCalibrating && !didCompleteWholePattern
        saveTimingTrace(outcome: isCalibrating ? "calibration-completed" : (didCompleteWholePattern ? "completed" : "abandoned"))
        if isCalibrating {
            saveCalibration(rawOffsetsMilliseconds: associatedCalibrationOffsets(in: session.timeline))
        } else if didCompleteWholePattern {
            lastCompletedExerciseTitle = selectedPracticeTitle
            completedScore = score
            resultInsights = PracticeInsights(score: score)
            resultHitRecords = HitRecord.records(from: score)
            scoreText = "Resultado: \(Int(score.percentage.rounded())) % · \(score.stars) estrellas · \(score.perfectCount) perfectos, \(score.goodCount) bien, \(score.regularCount) casi, \(score.misses.count) fallos"
            let attempt = PracticeAttempt(
                exerciseID: exercise.id,
                timestamp: Date(),
                bpm: exercise.bpm,
                score: score.percentage,
                stars: score.stars,
                perfect: score.perfectCount,
                good: score.goodCount,
                regular: score.regularCount,
                miss: score.misses.count,
                extra: score.extraCount,
                meanOffsetMilliseconds: score.meanOffsetMilliseconds,
                soundStatistics: PracticeInsights(score: score).soundStatistics,
                hitRecords: HitRecord.records(from: score),
                trainingContext: TrainingContext(
                    phase: activeTrainingPhase,
                    gapMetronomeLevel: activeGapMetronomeLevel,
                    showsVisualGuides: activeShowsVisualGuides,
                    evaluationScope: didCompleteWholePattern ? activeEvaluationScope : .fragment,
                    completedBars: resultCompletedBars,
                    practiceConditions: activePracticeConditions
                )
            )
            do { try progressStore?.record(attempt) }
            catch { status = "Sesión finalizada; no se pudo guardar el progreso: \(error.localizedDescription)" }
            refreshCourseProgress()
            let insights = PracticeInsights(score: score)
            let isFullPatternResult = didCompleteWholePattern && activeEvaluationScope == .fullPattern
            let newRecommendation = isFullPatternResult
                ? CoachingAnalyzer.recommendation(exercise: activeFullPatternExercise ?? exercise, score: score)
                : nil
            if coachingFlowStage == .integrating, let baseline = coachingBaselineAttempt,
               let recommendation = coachingRecommendation {
                let comparison = CoachingComparison.compare(baseline: baseline, followUp: attempt, recommendation: recommendation)
                coachingFeedback = coachingComparisonMessage(comparison, sound: recommendation.sound)
                coachingFlowStage = .none
                coachingBaselineAttempt = nil
            } else if coachingFlowStage == .isolating {
                canReturnToFullGroove = didCompleteWholePattern
            } else {
                coachingRecommendation = newRecommendation
                correctivePlan = newRecommendation.map { WhaleMethod.plan(exercise: activeFullPatternExercise ?? exercise, recommendation: $0) }
                coachingFlowStage = newRecommendation == nil ? .none : .suggested
                if let newRecommendation, isFullPatternResult {
                    saveCoachingGoal(exerciseID: exercise.id, recommendation: newRecommendation,
                                     conditions: attempt.trainingContext.practiceConditions)
                }
            }
            if activeGapMetronomeLevel > 0 && isFullPatternResult {
                let report = PulseDriftAnalyzer.analyze(records: HitRecord.records(from: score),
                    barDurationMilliseconds: session.timeline.barDurationMilliseconds, gapLevel: activeGapMetronomeLevel)
                pulseDriftReport = report
                switch report.trend {
                case .stable: pulseDriftMessage = "Durante el silencio mantuviste el pulso estable."
                case .early: pulseDriftMessage = "Durante el silencio tendiste a adelantarte. Repite este nivel antes de avanzar."
                case .late: pulseDriftMessage = "Durante el silencio tendiste a retrasarte. Repite este nivel antes de avanzar."
                case .insufficientEvidence: pulseDriftMessage = "Aún faltan golpes durante el silencio para valorar la deriva."
                }
            } else { pulseDriftMessage = ""; pulseDriftReport = nil }
            completeActiveDailyBlock(score: score, exercise: exercise)
            autopilotRecommendation = PracticeAutopilot.recommend(score: score, insights: insights, bpm: exercise.bpm, repeats: exercise.repeats)
            let nextRecommendation = courseRecommendation
            let canAdvance = activeEvaluationScope == .fullPattern
                && courseState(for: exercise) == .mastered
                && courseLevelState(for: exercise)?.chapterAccredited == true
                && nextRecommendation != nil
                && nextRecommendation?.exerciseID != exercise.id
            resultSummary = PracticeResultAnalyzer.summarize(
                score: score,
                insights: insights,
                hasCorrectivePlan: correctivePlan != nil,
                canAdvance: canAdvance
            )
            resultDiagnosisText = diagnosisText(for: resultSummary?.diagnosis)
            resultActionReason = actionReason(for: resultSummary?.action)
            ghostCoachCue = activeEvaluationScope == .fullPattern ? GhostCoach.cue(score: score, insights: insights) : "La práctica parcial no se usa para recomendar progreso curricular."
            presentResultTransition(percentage: score.percentage)
        } else {
            lastCompletedExerciseTitle = selectedPracticeTitle
            completedScore = nil
            resultInsights = nil
            resultSummary = nil
            resultHitRecords = []
            scoreText = "Sesión interrumpida en \(resultCompletedBars) de \(totalBars) compases. No se puntuó ni se guardó como intento."
            showsResult = true
        }
        if let previousLoop = previousPulseLoopEnabled {
            loopEnabled = previousLoop
            UserDefaults.standard.set(loopEnabled, forKey: "xRoll.ios.loopEnabled")
            previousPulseLoopEnabled = nil
        }
        self.session = nil
        presentedSessionGeneration = nil
        activeExercise = nil
        activeFullPatternExercise = nil
        activePracticeConditions = nil
        activeDailyBlockID = nil
        clearPausedPractice()
        activeExpectedNotesBySound.removeAll(keepingCapacity: true)
        scene = nil
        isCalibrating = false
        calibrationTargetSounds.removeAll(keepingCapacity: true)
        calibrationHitTimesBySound.removeAll(keepingCapacity: true)
        calibrationTraceMatchersBySound.removeAll(keepingCapacity: true)
    }

    private func cancelActivePractice(message: String) {
        finishTask?.cancel()
        audio?.stopScheduledSounds()
        audio?.stopLoop()
        if let previousLoop = previousPulseLoopEnabled {
            loopEnabled = previousLoop
            UserDefaults.standard.set(loopEnabled, forKey: "xRoll.ios.loopEnabled")
            previousPulseLoopEnabled = nil
        }
        scene = nil
        isPracticing = false
        showsResult = false
        resultIsPartial = false
        calibrationStatus = message
        guard let generation = presentedSessionGeneration else {
            saveTimingTrace(outcome: "cancelled")
            clearCancelledPracticeState()
            return
        }
        discardingPracticeGeneration = generation
        sessionIngress.cancel { [weak self] cancelledGeneration in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentedSessionGeneration == cancelledGeneration else { return }
                self.saveTimingTrace(outcome: "cancelled")
                self.clearCancelledPracticeState()
            }
        }
    }

    private func clearCancelledPracticeState() {
        session = nil
        presentedSessionGeneration = nil
        discardingPracticeGeneration = nil
        activeExercise = nil
        activeFullPatternExercise = nil
        activePracticeConditions = nil
        activeDailyBlockID = nil
        clearPausedPractice()
        activeExpectedNotesBySound.removeAll(keepingCapacity: true)
        isCalibrating = false
        calibrationTargetSounds.removeAll(keepingCapacity: true)
        calibrationHitTimesBySound.removeAll(keepingCapacity: true)
        calibrationTraceMatchersBySound.removeAll(keepingCapacity: true)
    }

    private func associatedCalibrationOffsets(in timeline: ExerciseTimeline) -> [Double] {
        let targetsBySound = Dictionary(grouping: timeline.notes, by: \.sound)
        var associations = [CalibrationHitAssociation]()
        for (sound, hitTimes) in calibrationHitTimesBySound {
            guard let targets = targetsBySound[sound] else { continue }
            var matcher = CalibrationMatcher(targetTimesMilliseconds: targets.map(\.timeMilliseconds))
            for hitTime in hitTimes.sorted() {
                if let association = matcher.associateHit(atMilliseconds: hitTime) {
                    associations.append(association)
                }
            }
        }
        return associations.sorted { $0.targetTimeMilliseconds < $1.targetTimeMilliseconds }
            .map(\.rawOffsetMilliseconds)
    }

    private func recordTimingSample(
        source: PracticeTraceInput,
        feedbackID: String,
        inputHostTime: UInt64,
        workerHostTime: UInt64?,
        audioSubmissionStartHostTime: UInt64?,
        audioSubmissionReturnHostTime: UInt64?,
        sessionProcessingStartHostTime: UInt64,
        sessionProcessingEndHostTime: UInt64,
        audioSubmissionError: String?,
        mainDeliveryHostTime: UInt64,
        visualSnapshot: SceneVisualClockSnapshot?,
        scoredHit: ScoredPadHit?,
        calibrationAssociation: CalibrationHitAssociation?,
        soundID: String?,
        midiEvent: MIDINoteOn?,
        touchTimestampSeconds: Double?
    ) {
        guard presentedSessionGeneration != nil else { return }
        let inputElapsedMilliseconds = AudioClock.milliseconds(from: startHostTime, to: inputHostTime)
        let nearestExpectedNote = soundID.flatMap { sound in
            activeExpectedNotesBySound[sound].flatMap {
                nearestNote(to: inputElapsedMilliseconds, in: $0)
            }
        }
        let nearestExpectedTargetHostTime = nearestExpectedNote.map {
            AudioClock.hostTime(afterMilliseconds: $0.timeMilliseconds, from: startHostTime)
        }
        let targetHostTime = scoredHit?.expectedNote.map {
            AudioClock.hostTime(afterMilliseconds: $0.timeMilliseconds, from: startHostTime)
        }
        timingTrace.append(PracticeTimingSample(
            input: source,
            inputHostTime: inputHostTime,
            workerHostTime: workerHostTime,
            audioSubmissionStartHostTime: audioSubmissionStartHostTime,
            audioSubmissionReturnHostTime: audioSubmissionReturnHostTime,
            sessionProcessingStartHostTime: sessionProcessingStartHostTime,
            sessionProcessingEndHostTime: sessionProcessingEndHostTime,
            audioSubmissionError: audioSubmissionError,
            mainDeliveryHostTime: mainDeliveryHostTime,
            visualUpdateHostTime: visualSnapshot?.renderHostTime,
            estimatedPresentationHostTime: visualSnapshot?.estimatedPresentationHostTime,
            frameIntervalMilliseconds: visualSnapshot?.frameIntervalMilliseconds,
            visualPredictionMilliseconds: visualSnapshot?.predictedLeadMilliseconds,
            feedbackID: feedbackID,
            visualFeedbackConsumedHostTime: nil,
            targetHostTime: targetHostTime,
            expectedNoteTimeMilliseconds: scoredHit?.expectedNote?.timeMilliseconds,
            nearestExpectedTargetHostTime: nearestExpectedTargetHostTime,
            nearestExpectedTargetTimeMilliseconds: nearestExpectedNote?.timeMilliseconds,
            scoredOffsetMilliseconds: scoredHit?.offsetMilliseconds,
            calibrationHitTimeMilliseconds: isCalibrating && calibrationTargetSounds.contains(soundID ?? "")
                ? inputElapsedMilliseconds
                : nil,
            calibrationTargetTimeMilliseconds: calibrationAssociation?.targetTimeMilliseconds,
            rawCalibrationOffsetMilliseconds: calibrationAssociation?.rawOffsetMilliseconds,
            judgement: scoredHit?.judgement.rawValue,
            soundID: soundID,
            midiNote: midiEvent?.note,
            midiChannel: midiEvent?.channel,
            midiVelocity: midiEvent?.velocity,
            midiCoreMIDIHostTime: midiEvent?.coreMIDIHostTime,
            midiCallbackHostTime: midiEvent?.callbackHostTime,
            midiTimestampSource: midiEvent?.timestampSource,
            sourceIdentifier: source == .midi ? selectedMIDISourceID.map(String.init) : "touchscreen",
            touchTimestampSeconds: touchTimestampSeconds
        ))
    }

    private func nearestNote(to timeMilliseconds: Double, in notes: [ScheduledExerciseNote]) -> ScheduledExerciseNote? {
        guard !notes.isEmpty else { return nil }
        var lowerBound = 0
        var upperBound = notes.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if notes[middle].timeMilliseconds < timeMilliseconds { lowerBound = middle + 1 }
            else { upperBound = middle }
        }
        let previous = lowerBound > 0 ? notes[lowerBound - 1] : nil
        let next = lowerBound < notes.count ? notes[lowerBound] : nil
        switch (previous, next) {
        case let (previous?, next?):
            return abs(timeMilliseconds - previous.timeMilliseconds) <= abs(next.timeMilliseconds - timeMilliseconds) ? previous : next
        case let (previous?, nil):
            return previous
        case let (nil, next?):
            return next
        case (nil, nil):
            return nil
        }
    }

    private func slotsBySound() -> [String: Int] {
        let orderedPads = pads.sorted { $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row }
        // La práctica dibuja un carril por sonido, aunque el mapa físico tenga
        // varios pads que produzcan esa misma voz. La entrada y el score siguen
        // resolviendo cada pad por separado fuera de esta distribución visual.
        var primarySlots = [String: Int]()
        for pad in orderedPads where primarySlots[pad.sound] == nil {
            primarySlots[pad.sound] = pad.row * 4 + pad.column
        }
        return primarySlots
    }

    private func saveTimingTrace(outcome: String) {
        guard let exercise = activeExercise else { return }
        let samples = timingTrace.snapshot()
        guard !samples.isEmpty,
              let calibrationKey = activeCalibrationProfileKey,
              let calibrationURL else { return }
        do {
            let directory = calibrationURL.deletingLastPathComponent().appendingPathComponent("timing-traces", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("session-\(timingTraceSessionID.uuidString.lowercased()).json")
            let calibrationTargets: [String: [Double]]
            if isCalibrating, let session {
                calibrationTargets = Dictionary(grouping: session.timeline.notes, by: \.sound)
                    .mapValues { $0.map(\.timeMilliseconds) }
            } else {
                calibrationTargets = [:]
            }
            let document = PracticeTimingTraceDocument(
                schemaVersion: 4,
                capturedAt: Date(),
                sessionID: timingTraceSessionID.uuidString,
                exerciseID: exercise.id,
                bpm: exercise.bpm,
                isCalibration: isCalibrating,
                outcome: outcome,
                inputKind: calibrationKey.inputKind.rawValue,
                inputIdentifier: calibrationKey.inputIdentifier,
                outputIdentifier: calibrationKey.outputIdentifier,
                scoringCompensationMilliseconds: activeScoringCompensationMilliseconds,
                calibrationTargetTimesMillisecondsBySound: calibrationTargets,
                predictsVisualFrame: predictsVisualFrame,
                requestedIOBufferDurationMilliseconds: Self.preferredIOBufferDuration * 1_000,
                sampleRate: calibrationKey.sampleRate,
                bufferFrames: calibrationKey.bufferFrames,
                totalEventCount: timingTrace.totalEventCount,
                truncatedEventCount: max(0, timingTrace.totalEventCount - samples.count),
                midiDroppedPacketCount: midiInput?.droppedPacketCount ?? 0,
                droppedVisualFeedbackCount: scene?.droppedVisualFeedbackEvents ?? 0,
                samples: samples
            )
            try timingTrace.export(document, to: url)
            pruneTimingTraces(in: directory, keeping: url, maximumCount: 20)
            timingTraceURL = url
            timingTraceMessage = "Traza de sincronía guardada (\(samples.count) eventos)."
        } catch {
            timingTraceURL = nil
            timingTraceMessage = "No se pudo guardar la traza: \(error.localizedDescription)"
        }
    }

    private func pruneTimingTraces(in directory: URL, keeping currentURL: URL, maximumCount: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let olderTraces = files.filter {
            $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("session-") && $0 != currentURL
        }
        let newestFirst = olderTraces.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if lhsDate == rhsDate { return lhs.lastPathComponent > rhs.lastPathComponent }
            return lhsDate > rhsDate
        }
        let olderTraceLimit = max(0, maximumCount - 1)
        for url in newestFirst.dropFirst(olderTraceLimit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private var calibrationURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("xRoll", isDirectory: true)
            .appendingPathComponent("calibration.json")
    }

    private func currentCalibrationProfileKey() -> CalibrationProfileKey {
        let route = AVAudioSession.sharedInstance()
        let output = route.currentRoute.outputs.first
        let sampleRate = route.sampleRate
        return CalibrationProfileKey(
            inputKind: selectedMIDISourceID == nil ? .touch : .midi,
            inputIdentifier: selectedMIDISourceID.map(String.init) ?? "touchscreen",
            outputIdentifier: output?.uid ?? output?.portName ?? "default",
            sampleRate: sampleRate,
            bufferFrames: Int((route.ioBufferDuration * sampleRate).rounded())
        )
    }

    private func observeAudioRouteChanges() {
        audioRouteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stopPreview()
                if self.isPracticePaused { self.discardPausedPractice() }
                if self.isPracticing {
                    self.cancelActivePractice(message: "Cambió la ruta de audio; calibra esta ruta antes de puntuar.")
                }
                do { try self.configureAudioSession(reapplyPreference: true) }
                catch { self.audioConfigurationStatus = "No se pudo reconfigurar el audio: \(error.localizedDescription)" }
                self.loadCalibrationForCurrentRoute()
            }
        }
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            if type == .began {
                DispatchQueue.main.async { [weak self] in self?.handleAudioInterruption() }
                return
            }
            guard type == .ended else { return }
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard options.contains(.shouldResume) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                do {
                    try self.withSuspendedMIDIInput {
                        try self.configureAudioSession(reapplyPreference: true)
                        try self.audio?.start()
                    }
                    self.loadCalibrationForCurrentRoute()
                } catch {
                    self.audioConfigurationStatus = "No se pudo reanudar el audio: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadCalibrationForCurrentRoute() {
        let key = currentCalibrationProfileKey()
        guard let calibrationURL,
              let profiles = try? CalibrationProfileStore.load(from: calibrationURL),
              let profile = profiles.first(where: { $0.key == key }) else {
            calibrationProfile = nil
            calibrationOffsetMilliseconds = 0
            calibrationStatus = "Calibración pendiente para esta entrada y salida."
            return
        }
        calibrationProfile = profile
        calibrationOffsetMilliseconds = profile.scoringCompensationMilliseconds
        calibrationStatus = String(format: "Calibrada · compensación %.0f ms · dispersión %.0f ms", profile.offsetMilliseconds, profile.medianAbsoluteDeviationMilliseconds)
    }

    private func saveCalibration(rawOffsetsMilliseconds: [Double]) {
        do {
            let estimate = try CalibrationEstimator.estimate(rawOffsetsMilliseconds: rawOffsetsMilliseconds)
            let profile = CalibrationProfile(key: currentCalibrationProfileKey(), estimate: estimate)
            guard let calibrationURL else { throw AppError.calibrationStorageUnavailable }
            try FileManager.default.createDirectory(at: calibrationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var profiles = (try? CalibrationProfileStore.load(from: calibrationURL)) ?? []
            profiles.removeAll { $0.key == profile.key }
            profiles.append(profile)
            try CalibrationProfileStore.save(profiles, to: calibrationURL)
            calibrationProfile = profile
            calibrationOffsetMilliseconds = profile.scoringCompensationMilliseconds
            calibrationStatus = String(format: "Calibrada · compensación %.0f ms · dispersión %.0f ms", estimate.offsetMilliseconds, estimate.medianAbsoluteDeviationMilliseconds)
            scoreText = "Calibración completada con \(estimate.acceptedHitCount) golpes válidos."
        } catch {
            calibrationProfile = nil
            calibrationOffsetMilliseconds = 0
            calibrationStatus = "Calibración incompleta: \(error.localizedDescription)"
            scoreText = calibrationStatus
        }
    }

    private func setMIDIMapCaptureActive(_ active: Bool) {
        midiMappingGate.setActive(active)
    }

    private func captureMappingEvent(_ event: MIDINoteOn) {
        guard isLearningPadMap,
              event.callbackHostTime >= mappingStartHostTime,
              var builder = padMapBuilder,
              builder.nextStep != nil else { return }
        let result = builder.assign(event)
        switch result {
        case .assigned(let sound, let remaining), .skipped(let sound, let remaining):
            padMapBuilder = builder
            mappingAssignedCount = builder.assignedCount
            let label = kit?.sounds.first(where: { $0.id == sound })?.label ?? sound
            mappingMessage = "\(label) · nota \(event.note), canal \(event.channel) aprendidos. Quedan \(remaining) posiciones."
        case .duplicate(let note, let channel, let existingSound):
            padMapBuilder = builder
            let label = kit?.sounds.first(where: { $0.id == existingSound })?.label ?? existingSound
            mappingMessage = "Nota \(note), canal \(channel) ya asignados a \(label). Golpea el pad físico iluminado."
        case .complete(let physicalMap):
            padMapBuilder = nil
            isLearningPadMap = false
            setMIDIMapCaptureActive(false)
            mappingAssignedCount = physicalMap.pads.count
            do {
                try savePhysicalPadMap(physicalMap)
                physicalMIDIMap = physicalMap
                selectedLayoutPreset = .core
                UserDefaults.standard.set(PadLayoutPreset.core.rawValue, forKey: layoutPreferenceKey(for: selectedMIDISourceID))
                applyActiveLayout()
                layoutStatus = "Mapa completo · xRoll Core aplicado. Las 16 notas y canales quedaron guardados."
                mappingMessage = layoutStatus
            } catch {
                physicalMIDIMap = nil
                liveMIDI?.setPadRouter(nil)
                layoutStatus = "No se pudo guardar el mapa: \(error.localizedDescription)"
                mappingMessage = layoutStatus
            }
        }
        if case .assigned = result, let next = builder.nextStep {
            let nextLabel = kit?.sounds.first(where: { $0.id == next.sound })?.label ?? next.sound
            mappingMessage += " Siguiente: \(nextLabel), fila \(next.row + 1), columna \(next.column + 1)."
        }
        if case .skipped = result, let next = builder.nextStep {
            let nextLabel = kit?.sounds.first(where: { $0.id == next.sound })?.label ?? next.sound
            mappingMessage += " Siguiente: \(nextLabel), fila \(next.row + 1), columna \(next.column + 1)."
        }
    }

    private var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("xRoll", isDirectory: true)
    }

    private var padMapsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("padmaps", isDirectory: true)
    }

    private func physicalPadMapURL(for uid: Int) -> URL {
        padMapsDirectory.appendingPathComponent("\(uid).physical.padmap")
    }

    private func layoutPreferenceKey(for sourceID: MIDIUniqueID?) -> String {
        "xRoll.ios.layout.\(sourceID.map(String.init) ?? "touchscreen")"
    }

    private func savedLayoutPreset(for sourceID: MIDIUniqueID?) -> PadLayoutPreset {
        guard let raw = UserDefaults.standard.string(forKey: layoutPreferenceKey(for: sourceID)),
              let preset = PadLayoutPreset(rawValue: raw) else { return .core }
        return preset
    }

    private func savePhysicalPadMap(_ physicalMap: PadMapV2) throws {
        guard physicalMap.pads.count == 16, let kit else { throw AppError.incompletePadMap }
        try FileManager.default.createDirectory(at: padMapsDirectory, withIntermediateDirectories: true)
        try PadMapStore.save(
            physicalMap,
            to: physicalPadMapURL(for: physicalMap.device.uid),
            availableSounds: Set(kit.sounds.map(\.id))
        )
    }

    private func loadPhysicalPadMap(for source: MIDIEndpointDescription) -> PadMapV2? {
        guard let sourceID = source.uniqueID, let kit else { return nil }
        let availableSounds = Set(kit.sounds.map(\.id))
        let directURL = physicalPadMapURL(for: Int(sourceID))
        if let map = try? PadMapStore.loadV2(at: directURL, availableSounds: availableSounds), map.pads.count == 16 {
            return map
        }
        let storedMaps = (try? FileManager.default.contentsOfDirectory(at: padMapsDirectory, includingPropertiesForKeys: nil)) ?? []
        let namedMatches = storedMaps
            .filter { $0.lastPathComponent.hasSuffix(".physical.padmap") && $0 != directURL }
            .compactMap { try? PadMapStore.loadV2(at: $0, availableSounds: availableSounds) }
            .filter { $0.pads.count == 16 && $0.device.name == source.name }
        guard namedMatches.count == 1, let old = namedMatches.first else { return nil }
        let rekeyed = PadMapV2(
            id: old.id,
            name: old.name,
            preset: old.preset,
            device: .init(name: source.name, uid: Int(sourceID)),
            created: old.created,
            pads: old.pads
        )
        try? PadMapStore.save(rekeyed, to: directURL, availableSounds: availableSounds)
        return rekeyed
    }

    private func activateLayoutForCurrentInput() {
        guard let touchPhysicalMap else { return }
        if usesTouchInput {
            physicalMIDIMap = nil
            selectedLayoutPreset = savedLayoutPreset(for: nil)
            padMap = PadLayoutFactory.applying(selectedLayoutPreset, to: touchPhysicalMap)
            if let padMap { liveMIDI?.setPadRouter(PadMapV2Router(padMap)) }
            layoutStatus = "Pads táctiles · layout \(padMap?.name ?? "xRoll Core")."
            return
        }
        guard let source = midiSources.first(where: { $0.uniqueID == selectedMIDISourceID }),
              let sourceID = source.uniqueID else {
            physicalMIDIMap = nil
            liveMIDI?.setPadRouter(nil)
            layoutStatus = "Esperando la entrada MIDI seleccionada."
            return
        }
        physicalMIDIMap = loadPhysicalPadMap(for: source)
        selectedLayoutPreset = savedLayoutPreset(for: sourceID)
        if let physicalMIDIMap {
            padMap = PadLayoutFactory.applying(selectedLayoutPreset, to: physicalMIDIMap)
            if let padMap { liveMIDI?.setPadRouter(PadMapV2Router(padMap)) }
            layoutStatus = "\(source.name) · \(padMap?.name ?? "xRoll Core") · 16 pads aprendidos."
        } else {
            padMap = PadLayoutFactory.make(.core, device: .init(name: source.name, uid: Int(sourceID)))
            liveMIDI?.setPadRouter(nil)
            layoutStatus = "Controlador sin aprender · la vista previa GM solo sirve para probar sonidos; aprende las 16 posiciones para puntuar."
        }
    }

    private func applyActiveLayout() {
        guard let kit else { return }
        let physicalMap = usesTouchInput ? touchPhysicalMap : physicalMIDIMap
        guard let physicalMap else { return }
        let applied = selectedLayoutPreset == .custom ? physicalMap : PadLayoutFactory.applying(selectedLayoutPreset, to: physicalMap)
        do {
            try applied.validate(availableSounds: Set(kit.sounds.map(\.id)))
            padMap = applied
            liveMIDI?.setPadRouter(PadMapV2Router(applied))
        } catch {
            layoutStatus = "El layout no es compatible con este kit: \(error.localizedDescription)"
        }
    }

    private func isLayoutCompatible(with exercise: Exercise) -> Bool {
        layoutCompatibilityMessage(for: exercise) == nil
    }

    private func layoutCompatibilityMessage(for exercise: Exercise) -> String? {
        guard let padMap else { return "No hay un layout activo para esta entrada." }
        let sounds = Set(padMap.pads.map(\.sound))
        if let missing = Set(exercise.notes.map(\.sound)).subtracting(sounds).sorted().first {
            return "Falta \(kitLabel(for: missing)) en \(padMap.name). Elige un layout compatible en Equipo."
        }
        for note in exercise.notes {
            guard let target = note.target else { continue }
            switch target.type {
            case .any:
                continue
            case .role:
                guard padMap.pads.contains(where: { $0.sound == note.sound && $0.role == target.value }) else {
                    return "\(kitLabel(for: note.sound)) no tiene el rol \(target.value ?? "solicitado") en \(padMap.name)."
                }
            case .pad:
                guard padMap.pads.contains(where: { $0.sound == note.sound && $0.id == target.value }) else {
                    return "El objetivo físico \(target.value ?? "solicitado") no existe en \(padMap.name)."
                }
            }
        }
        return nil
    }

    private func refreshCourseProgress() {
        guard let progressStore else { return }
        do {
            recentAttempts = try progressStore.attempts(filter: .init(), limit: 1_000)
            courseEvidence = try progressStore.courseEvidence()
            courseLevels = courseGraph?.states(evidence: courseEvidence) ?? []
            if let exercise = selectedExercise, !isExerciseAvailable(exercise),
             let next = courseGraph?.nodes.first(where: { isExerciseAvailable($0.exercise) })?.exercise {
                selectedExerciseID = next.id
                selectPendingTempo(for: next)
                savePracticePreferences()
            }
            courseStatus = courseGraph == nil ? "No se pudo leer el currículo integrado de los MIDI." : ""
        } catch {
            courseStatus = "No se pudo cargar el progreso: \(error.localizedDescription)"
        }
    }

    private func savePracticePreferences() {
        let preferences = PracticePreferences(exerciseID: selectedExerciseID, bpm: selectedBPM, repeats: selectedRepeats)
        try? PracticePreferencesStore.save(preferences, to: applicationSupportDirectory.appendingPathComponent("practice-preferences.json"))
    }

    private func loadPracticePreferences() {
        let url = applicationSupportDirectory.appendingPathComponent("practice-preferences.json")
        guard let preferences = try? PracticePreferencesStore.load(from: url) else { return }
        if let id = preferences.exerciseID,
           let savedExercise = exercises.first(where: { $0.id == id }),
           isExerciseAvailable(savedExercise) {
            selectedExerciseID = id
        }
        guard let exercise = selectedExercise else { return }
        selectPendingTempo(for: exercise)
        let steps = TempoLadder.steps(for: exercise)
        let selectedStep = steps.first(where: { $0.bpm == selectedBPM })
        selectedRepeats = selectedStep.flatMap { TempoLadder.repeats(for: $0, exercise: exercise) }
            ?? PracticeConfiguration.normalizedRepeats(preferences.repeats ?? exercise.repeats)
    }

    private func lockReason(for exercise: Exercise) -> String {
        guard let node = courseGraph?.node(for: exercise.id) else { return "Este ritmo no forma parte del currículo integrado." }
        if let prerequisite = node.metadata.prerequisites.first(where: { prerequisiteID in
            courseLevels.first(where: { $0.exerciseID == prerequisiteID })?.status != .mastered
        }) {
            let title = courseGraph?.node(for: prerequisite)?.exercise.title ?? prerequisite
            return "Supera primero «\(title)» a su tempo de referencia (70 % o más)."
        }
        return "Supera las lecciones anteriores a su tempo de referencia para abrir esta ruta."
    }

    private enum AppError: LocalizedError {
        case resourcesMissing
        case calibrationStorageUnavailable
        case incompletePadMap
        case loopUnavailable
        case duplicateExercise(String)

        var errorDescription: String? {
            switch self {
            case .resourcesMissing:
                return "No se encontraron los recursos del kit o los ejercicios dentro del bundle."
            case .calibrationStorageUnavailable:
                return "No se pudo crear la ubicación local para guardar la calibración."
            case .incompletePadMap:
                return "El mapa físico debe contener las 16 posiciones antes de guardarse."
            case .loopUnavailable:
                return "El loop seleccionado ya no está dentro del bundle de la app."
            case .duplicateExercise(let id):
                return "El MIDI ya está importado (\(id))."
            }
        }
    }
}

/// Convierte el reloj monotónico de UITouch (segundos desde el arranque) a la
/// escala hostTime de AudioToolbox usando un par de anclas capturado al golpear.
private struct TouchHostClock {
    func hostTime(forUptimeTimestamp timestamp: TimeInterval) -> UInt64 {
        let currentUptime = ProcessInfo.processInfo.systemUptime
        let currentHostTime = AudioClock.currentHostTime()
        let delta = timestamp - currentUptime
        let nanoseconds = Int64((delta * 1_000_000_000).rounded())
        return AudioClock.hostTime(offsetByNanoseconds: nanoseconds, from: currentHostTime)
    }
}

enum iOSStudioDesign {
    static let canvas = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let surface = Color(red: 0.071, green: 0.082, blue: 0.102)
    static let raised = Color(red: 0.098, green: 0.114, blue: 0.137)
    static let border = Color(red: 0.125, green: 0.145, blue: 0.176)
    static let primary = Color(red: 0.945, green: 0.953, blue: 0.961)
    static let secondary = Color(red: 0.639, green: 0.671, blue: 0.710)
    static let muted = Color(red: 0.427, green: 0.459, blue: 0.502)
    static let accent = Color(red: 0.388, green: 0.902, blue: 0.745)
    static let leftHand = Color(red: 0, green: 0.447, blue: 0.698)
    static let rightHand = Color(red: 0.902, green: 0.624, blue: 0)
    static let regular = Color(red: 1, green: 0.831, blue: 0.231)
    static let miss = Color(red: 1, green: 0.420, blue: 0.420)
}

struct iOSStudioPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(iOSStudioDesign.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(iOSStudioDesign.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct iOSHomeView: View {
    @StateObject private var model = iOSPracticeModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var showsLaunchBrand = true
    @State private var homeQuote = DrummerQuote.random()
    @State private var showsTrainingOptions = false
    @State private var showsTempoChallenges = false
    @State private var isShowingOptions = false
    @State private var isImportingPadMap = false
    @State private var isImportingCommunityMIDI = false
    @State private var isImportingProgress = false
    @State private var showsScoreDetails = false
    @State private var showsTimingMicroscope = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [iOSStudioDesign.canvas, Color(red: 0.055, green: 0.071, blue: 0.094)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                NavigationStack {
                    Group {
                        if model.isShowingResultTransition {
                            PracticeCompletionTransition(percentage: model.resultTransitionPercentage).transition(.opacity)
                        } else if model.isLearningPadMap {
                            mappingLayout(for: geometry.size)
                        } else if model.isPreviewing {
                            previewLayout(for: geometry.size)
                        } else if model.isPracticePaused {
                            pausedPracticeLayout
                        } else if model.isPracticing {
                            practiceLayout(for: geometry.size)
                        } else if model.showsResult {
                            resultLayout.transition(.opacity)
                        } else {
                            mainTabs(for: geometry.size)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar(.hidden, for: .navigationBar)
                    .onChange(of: scenePhase) { phase in
                        if phase != .active { model.handleAppBecameInactive() }
                        synchronizeIdleTimer()
                    }
                    .onChange(of: model.isPracticing || model.isPreviewing || model.isLearningPadMap) { _ in
                        synchronizeIdleTimer()
                    }
                    .onChange(of: model.showsResult) { isShowingResult in
                        if isShowingResult { showsTimingMicroscope = false }
                    }
                    .fileImporter(isPresented: $isImportingPadMap, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                        if case .success(let urls) = result, let url = urls.first { model.importPadMap(from: url) }
                    }
                    .fileImporter(isPresented: $isImportingCommunityMIDI, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                        if case .success(let urls) = result, let url = urls.first { model.importCommunityExercise(from: url) }
                    }
                    .fileImporter(isPresented: $isImportingProgress, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                        if case .success(let urls) = result, let url = urls.first { model.importProgress(from: url) }
                    }
                    .confirmationDialog(
                        "¿Aplicar \(model.pendingMapImportName) a este controlador?",
                        isPresented: $model.isWaitingToConfirmMapImport,
                        titleVisibility: .visible
                    ) {
                        Button("Reemplazar mapa de este controlador", role: .destructive) { model.confirmPadMapImport() }
                        Button("Cancelar", role: .cancel) { model.cancelPadMapImport() }
                    } message: {
                        Text("Se cambiarán sus sonidos y roles, pero se conservarán las 16 notas y canales MIDI del archivo.")
                    }
                }
            }
        }
        .overlay {
            if showsLaunchBrand { XRollLaunchView().transition(.opacity) }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                withAnimation(reducesMotion ? nil : .easeOut(duration: 0.35)) { showsLaunchBrand = false }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            synchronizeIdleTimer()
            model.scene?.setReducesMotion(reducesMotion)
            model.previewScene?.setReducesMotion(reducesMotion)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: reducesMotion) {
            model.scene?.setReducesMotion($0)
            model.previewScene?.setReducesMotion($0)
        }
        .sheet(isPresented: $isShowingOptions) {
            iOSOptionsView(model: model, isPresented: $isShowingOptions)
        }
    }

    private func synchronizeIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
            && (model.isPracticing || model.isPreviewing || model.isLearningPadMap)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            XRollBrandMark(size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("xRoll").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.primary)
                Text("ESTUDIO DE RITMO").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(iOSStudioDesign.accent)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.usesTouchInput ? iOSStudioDesign.regular : iOSStudioDesign.accent).frame(width: 7, height: 7)
                Text(model.usesTouchInput ? "TÁCTIL" : "MIDI").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(iOSStudioDesign.raised, in: Capsule())
            Button { isShowingOptions = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
            .accessibilityLabel("Opciones")
        }
    }

    private func mainTabs(for size: CGSize) -> some View {
        TabView(selection: $model.selectedTab) {
            AnyView(practiceHome(for: size))
                .tabItem { Label("Inicio", systemImage: "house.fill") }
                .tag(iOSMainTab.practice)
            AnyView(courseLayout)
                .tabItem { Label("Curso", systemImage: "music.note.list") }
                .tag(iOSMainTab.course)
            AnyView(fillsLayout)
                .tabItem { Label("Redobles", systemImage: "music.quarternote.3") }
                .tag(iOSMainTab.fills)
            AnyView(layoutsLayout)
                .tabItem { Label("Equipo", systemImage: "square.grid.3x3") }
                .tag(iOSMainTab.layouts)
            AnyView(progressLayout)
                .tabItem { Label("Progreso", systemImage: "chart.bar.fill") }
                .tag(iOSMainTab.progress)
        }
        .tint(iOSStudioDesign.accent)
    }

    @ViewBuilder
    private func practiceHome(for size: CGSize) -> some View {
        let usesWideCards = size.width >= 760 && size.height >= 700
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                brandHeader
                    .padding(.bottom, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text("INICIO · PREPARACIÓN").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(iOSStudioDesign.accent)
                    Text("Una sesión con propósito").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.primary)
                    Text(model.status).font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                }
                if model.needsHomeSetup {
                    if usesWideCards {
                        HStack(alignment: .top, spacing: 12) {
                            if model.needsEquipmentSetup { equipmentSummaryCard }
                            if !model.hasCalibrationForCurrentRoute { calibrationCard }
                        }
                    } else {
                        VStack(spacing: 12) {
                            if model.needsEquipmentSetup { equipmentSummaryCard }
                            if !model.hasCalibrationForCurrentRoute { calibrationCard }
                        }
                    }
                }
                iOSStudioPanel {
                    Text("VOCES DEL RITMO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                    Text("«\(homeQuote.text)»").font(.headline).foregroundStyle(iOSStudioDesign.primary).fixedSize(horizontal: false, vertical: true)
                    Text("— \(homeQuote.author)").font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                }
                if usesWideCards {
                    HStack(alignment: .top, spacing: 16) {
                        if !model.isCheckpointAssessment { recommendationCard }
                        exercisePreparation
                    }
                } else {
                    if !model.isCheckpointAssessment { recommendationCard }
                    exercisePreparation
                }
                iOSStudioPanel {
                    Text("SESIÓN DIARIA · UNOS CINCO MINUTOS")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                    if model.hasDailyPracticePlanForToday, let plan = model.dailyPracticePlan, !plan.blocks.isEmpty {
                        Text("\(plan.completedBlockCount) completados · \(plan.skippedBlockCount) omitidos de \(plan.blocks.count) · \(max(1, (plan.estimatedSeconds + 59) / 60)) min estimados")
                            .font(.headline).foregroundStyle(iOSStudioDesign.primary)
                        if let next = plan.currentBlock {
                            Text("Siguiente: \(next.title) · \(next.reason)")
                                .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                        }
                    } else {
                        Text("Empieza con un patrón conocido, repasa una habilidad, prueba un reto y termina con el groove completo.")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                    }
                    Button { model.startDailyPractice() } label: {
                        Label(model.dailyPracticeCompletedToday ? "Sesión completada" : (model.hasDailyPracticePlanForToday ? "Continuar mi sesión" : "Preparar sesión"), systemImage: "calendar.badge.clock")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas)
                    .disabled(model.dailyPracticeCompletedToday)
                    if model.hasDailyPracticePlanForToday, model.dailyPracticePlan?.currentBlock != nil {
                        Button("Omitir este bloque") { model.skipNextDailyBlock() }
                            .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                    }
                    if !model.dailyPracticeMessage.isEmpty {
                        Text(model.dailyPracticeMessage).font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    }
                    Button { model.startPulseTraining() } label: {
                        Label("Entrenar pulso interno", systemImage: "metronome.fill")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                    if let stage = model.pulseTrainingStage {
                        Text(stage.title + ": " + stage.explanation).font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    }
                }
                Text(model.needsHomeSetup
                     ? "Completa los pasos de configuración de arriba para habilitar la práctica puntuada."
                     : "Todo listo. Sigue las notas que bajan hacia la línea de golpe y toca al ritmo.")
                    .font(.caption).foregroundStyle(iOSStudioDesign.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 3)
            }
            .frame(maxWidth: 1_180)
            .padding(.horizontal, usesWideCards ? 28 : 16)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var recommendationCard: some View {
        iOSStudioPanel {
            HStack(spacing: 7) {
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(iOSStudioDesign.accent)
                Text("TU SIGUIENTE PASO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.9).foregroundStyle(iOSStudioDesign.accent)
            }
            if let recommendation = model.courseRecommendation,
               let exercise = model.exercises.first(where: { $0.id == recommendation.exerciseID }) {
                Text(exercise.title).font(.title3.bold()).foregroundStyle(iOSStudioDesign.primary).fixedSize(horizontal: false, vertical: true)
                Text("Ritmo completo · \(recommendation.tempoStep.bpm) BPM · 70 % para avanzar")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(iOSStudioDesign.secondary)
                Text(exercise.metadata?.objective ?? "Completa el ritmo con una sola dificultad nueva.")
                    .font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    model.startRecommendedSession()
                } label: {
                    Label("Empezar siguiente paso", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(model.canScore(exercise) ? iOSStudioDesign.canvas : iOSStudioDesign.secondary)
                        .background(model.canScore(exercise) ? iOSStudioDesign.accent : iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!model.canScore(exercise))
                if !model.hasCalibrationForCurrentRoute {
                    Label("Calibra esta ruta desde Inicio antes de puntuar.", systemImage: "waveform.path")
                        .font(.caption).foregroundStyle(iOSStudioDesign.regular)
                } else if !model.usesTouchInput && !model.hasLearnedPhysicalPadMap {
                    Label("Aprende las 16 posiciones en Equipo para activar el score.", systemImage: "square.grid.3x3")
                        .font(.caption).foregroundStyle(iOSStudioDesign.regular)
                } else if let incompatibility = model.layoutCompatibilityMessageForUI(exercise) {
                    Label(incompatibility, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(iOSStudioDesign.regular)
                }
            } else {
                Text("Has recorrido los escalones disponibles. Repasa un ritmo dominado o continúa con la ruta de redobles.")
                    .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
            }
            Button("Explorar el curso") { model.selectedTab = .course }
                .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).tint(iOSStudioDesign.accent)
        }
    }

    private var equipmentSummaryCard: some View {
        iOSStudioPanel {
            Text("EQUIPO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
            Label(model.usesTouchInput ? "Pads táctiles" : (model.selectedMIDISourceName ?? "Entrada MIDI"),
                  systemImage: model.usesTouchInput ? "hand.tap" : "pianokeys")
                .font(.headline).foregroundStyle(iOSStudioDesign.primary).fixedSize(horizontal: false, vertical: true)
            Text(model.usesTouchInput ? "Elige Core, Drum Kit o Mirror para cambiar la función de los pads en pantalla." : model.layoutStatus)
                .font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Pads, layouts y entrada MIDI") { model.selectedTab = .layouts }
                .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
        }
    }

    private var courseLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brandHeader
                VStack(alignment: .leading, spacing: 4) {
                    Text("RUTA DE APRENDIZAJE").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(iOSStudioDesign.accent)
                    Text("Curso").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.primary)
                    Text("Puedes practicar cualquier ritmo. Supera cada lección a su tempo de referencia o demuestra el bloque completo.")
                        .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                }
                recommendationCard
                if !model.courseStatus.isEmpty {
                    iOSStudioPanel {
                        Label(model.courseStatus, systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.regular).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(model.courseChapters) { chapter in
                    iOSCourseChapterPanel(
                        chapter: chapter,
                        states: Dictionary(uniqueKeysWithValues: model.courseLevels.map { ($0.exerciseID, $0) }),
                        evidence: model.courseEvidence,
                        selectedExerciseID: model.selectedExerciseID,
                        expandsInitially: chapter.exercises.contains(where: { model.courseState(for: $0) == .available }),
                        selectExercise: { model.selectCourseExercise($0) },
                        selectCheckpoint: { model.selectCourseCheckpoint($0) }
                    )
                }
                iOSStudioPanel {
                    Text("MIDI IMPORTADOS").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                    Text("Tus archivos MIDI se validan y pueden practicarse, pero no cambian el recorrido oficial ni sus desbloqueos.")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    Button("Importar ejercicio .mid") { isImportingCommunityMIDI = true }
                        .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
                    if !model.exerciseImportMessage.isEmpty {
                        Text(model.exerciseImportMessage).font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(model.communityExercises, id: \.id) { exercise in
                        Button { model.selectCourseExercise(exercise.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.title).font(.subheadline.bold()).foregroundStyle(iOSStudioDesign.primary).multilineTextAlignment(.leading)
                                    Text("MIDI comunitario · \(exercise.bpm) BPM · \(exercise.notes.count) notas")
                                        .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(iOSStudioDesign.accent)
                            }
                            .padding(10).background(iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 1_060)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var fillsLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brandHeader
                VStack(alignment: .leading, spacing: 5) {
                    Text("RUTA TÉCNICA TRANSVERSAL").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(iOSStudioDesign.accent)
                    Text("Redobles y transiciones").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.primary)
                    Text("Aprende primero el gesto aislado y después colócalo al final de un groove. Esta ruta es independiente y no bloquea el curso principal.")
                        .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !model.fillRouteStatus.isEmpty {
                    iOSStudioPanel {
                        Label(model.fillRouteStatus, systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.regular).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.fillPairs.isEmpty {
                    iOSStudioPanel {
                        Text("No hay ejercicios de redobles en el bundle.").font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                    }
                } else {
                    ForEach(model.fillPairs) { pair in fillTrainingCard(pair) }
                }
            }
            .frame(maxWidth: 1_060)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func fillTrainingCard(_ pair: iOSFillPair) -> some View {
        iOSStudioPanel {
            HStack(spacing: 8) {
                Text("REDOBLE \(pair.number)").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(iOSStudioDesign.accent)
                Text(pair.title).font(.headline).foregroundStyle(iOSStudioDesign.primary)
                Spacer()
                if let isolated = pair.isolated { Text("\(isolated.bpm) BPM").font(.caption.bold()).foregroundStyle(iOSStudioDesign.secondary) }
            }
            Text(pair.explanation).font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                fillStepPanel(number: "1", title: "Solo el redoble", detail: "Aprende el gesto antes de integrarlo.", exercise: pair.isolated)
                fillStepPanel(number: "2", title: "Dentro de un ritmo", detail: "Practícalo entre el groove y su resolución.", exercise: pair.inContext)
            }
        }
    }

    private func fillStepPanel(number: String, title: String, detail: String, exercise: Exercise?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(title, systemImage: number == "1" ? "1.circle.fill" : "2.circle.fill")
                    .font(.caption.bold()).foregroundStyle(iOSStudioDesign.accent)
                Spacer(minLength: 4)
                if let exercise, let award = model.highestTempoAward(for: exercise) {
                    iOSCourseAwardBadge(award: award)
                }
            }
            if let exercise {
                iOSExercisePattern(exercise: exercise)
                    .padding(8).background(iOSStudioDesign.canvas, in: RoundedRectangle(cornerRadius: 8))
                Text(detail).font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
                iOSCourseExerciseRow(
                    exercise: exercise,
                    state: model.courseLevelState(for: exercise),
                    evidence: model.courseEvidence,
                    isSelected: model.selectedExerciseID == exercise.id,
                    showsAward: false,
                    selectExercise: { model.selectFillExercise($0) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9).background(iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 9))
    }

    private var layoutsLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brandHeader
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONTROLADOR Y DISPOSICIÓN").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(iOSStudioDesign.accent)
                    Text("Equipo").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.primary)
                    Text("Aprende las notas MIDI físicas una sola vez. Los layouts cambian el sonido y el rol, no la posición ni el canal.")
                        .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                }
                midiSetupControls
                layoutConfigurationCard
                if !model.mappingMessage.isEmpty {
                    iOSStudioPanel {
                        Text(model.mappingMessage).font(.subheadline).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                timingTraceSection
            }
            .frame(maxWidth: 1_060)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var layoutConfigurationCard: some View {
        iOSStudioPanel {
            HStack(spacing: 8) {
                Image(systemName: model.usesTouchInput ? "hand.tap" : "square.grid.3x3.fill")
                    .foregroundStyle(model.hasLearnedPhysicalPadMap || model.usesTouchInput ? iOSStudioDesign.accent : iOSStudioDesign.regular)
                Text("MAPA FÍSICO · 16 POSICIONES").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(iOSStudioDesign.accent)
            }
            Text(model.usesTouchInput ? "Layout táctil: \(model.selectedLayoutPreset.rawValue)" : (model.hasLearnedPhysicalPadMap ? "Mapa MIDI aprendido" : "Falta aprender el controlador"))
                .font(.headline).foregroundStyle(iOSStudioDesign.primary)
            if model.usesTouchInput {
                Text("La rejilla táctil ya tiene 16 posiciones. Puedes elegir una disposición funcional.")
                    .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
            } else if model.hasLearnedPhysicalPadMap {
                Text(model.layoutStatus).font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                iOSPadMapGrid(pads: model.activeLayoutPads, showsMIDI: true)
                    .frame(maxWidth: 520).aspectRatio(1, contentMode: .fit)
            } else {
                Text("La entrada aún puede probar sonidos GM, pero xRoll no afirmará qué posición física golpeaste ni permitirá puntuar hasta aprender el mapa.")
                    .font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                Button { model.startPadMapping() } label: {
                    Label("Aprender los 16 pads", systemImage: "viewfinder")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(iOSStudioDesign.canvas).background(iOSStudioDesign.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(iOSStudioDesign.border).frame(height: 1)
                Text("LAYOUT FUNCIONAL").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(iOSStudioDesign.secondary)
                ForEach([PadLayoutPreset.core, .drumKit, .mirror], id: \.self) { preset in
                    layoutPresetRow(preset)
                }
                if model.hasCustomImportedMap {
                    layoutPresetRow(.custom)
                }
                if !model.usesTouchInput && model.hasLearnedPhysicalPadMap {
                    Button("Reaprender las 16 posiciones") { model.startPadMapping() }
                        .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                }
                if model.selectedLayoutPreset == .custom {
                    Label("Layout Custom importado", systemImage: "square.grid.3x3.fill")
                        .font(.caption.bold()).foregroundStyle(iOSStudioDesign.accent)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(iOSStudioDesign.border).frame(height: 1)
                Text("MAPAS PORTABLES").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(iOSStudioDesign.secondary)
                HStack(spacing: 8) {
                    Button("Importar .padmap") { isImportingPadMap = true }
                        .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
                        .disabled(model.usesTouchInput || model.selectedMIDISourceID == nil)
                    Button("Preparar exportación") { model.preparePadMapExport() }
                        .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                        .disabled(model.usesTouchInput || !model.hasLearnedPhysicalPadMap)
                }
                if let mapExportURL = model.mapExportURL {
                    ShareLink(item: mapExportURL, preview: SharePreview("Layout xRoll \(model.selectedLayoutPreset.rawValue)")) {
                        Label("Compartir mapa .padmap", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
                }
                if !model.mapTransferMessage.isEmpty {
                    Text(model.mapTransferMessage).font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func layoutPresetRow(_ preset: PadLayoutPreset) -> some View {
        let isSelected = model.selectedLayoutPreset == preset
        let canSelect = preset == .custom
            ? model.hasCustomImportedMap
            : (model.usesTouchInput || model.hasLearnedPhysicalPadMap)
        let title: String
        let detail: String
        switch preset {
        case .core:
            title = "xRoll Core"
            detail = "Posiciones iniciales; conserva los huecos y duplica los sonidos principales."
        case .drumKit:
            title = "Drum Kit"
            detail = "Distribución funcional inspirada en una batería."
        case .mirror:
            title = "Mirror"
            detail = "Disposición simétrica para alternar manos."
        case .custom:
            title = "Custom"
            detail = "Mapa importado; conserva los sonidos y roles del archivo."
        }
        return Button { model.selectLayout(preset) } label: {
            HStack(spacing: 12) {
                iOSPadMapGrid(pads: model.layoutPreview(for: preset), showsMIDI: false)
                    .frame(width: 68, height: 68)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.subheadline.bold()).foregroundStyle(iOSStudioDesign.primary)
                        if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(iOSStudioDesign.accent) }
                    }
                    Text(detail).font(.caption).foregroundStyle(iOSStudioDesign.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? iOSStudioDesign.raised : iOSStudioDesign.canvas, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(isSelected ? iOSStudioDesign.accent : iOSStudioDesign.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
        .opacity(canSelect ? 1 : 0.55)
    }

    private var progressLayout: some View {
        let displayedAttempts = model.selectedExerciseAttempts
        let chartPoints = Array(displayedAttempts.suffix(20).enumerated()).map {
            iOSScorePoint(id: $0.offset, attemptNumber: $0.offset + 1, score: $0.element.score)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brandHeader
                VStack(alignment: .leading, spacing: 4) {
                    Text("EVIDENCIA ACUMULADA").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(iOSStudioDesign.accent)
                    Text("Progreso").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.primary)
                }
                let mastered = model.mainCourseLevels.filter { $0.status == .mastered }.count
                let played = Set(model.filteredProgressAttempts.map(\.exerciseID)).count
                iOSStudioPanel {
                    HStack(spacing: 10) {
                progressMetric("Lecciones superadas", value: "\(mastered) / \(model.mainCourseLevels.count)")
                        progressMetric("Practicados", value: "\(played)")
                        progressMetric("Intentos", value: "\(model.filteredProgressAttempts.count)")
                    }
                    ProgressView(value: Double(mastered), total: Double(max(1, model.mainCourseLevels.count)))
                        .tint(iOSStudioDesign.accent)
                        Text("Una lección se supera con el ritmo completo a su tempo de referencia y al menos 70 %.")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                }
                iOSStudioPanel {
                    Text("FILTRAR EVIDENCIA").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                    Picker("Ritmo", selection: Binding(get: { model.selectedProgressExerciseID }, set: { model.selectProgressExercise($0) })) {
                        Text("Todos los ritmos").tag("")
                        ForEach(model.exercises, id: \.id) { exercise in Text(exercise.title).tag(exercise.id) }
                    }
                    .pickerStyle(.menu).tint(iOSStudioDesign.primary)
                    Picker("Puntuación mínima", selection: Binding(get: { model.minimumProgressScore }, set: { model.setMinimumProgressScore($0) })) {
                        Text("Todas").tag(0.0)
                        Text("50 % o más").tag(50.0)
                        Text("70 % o más").tag(70.0)
                        Text("90 % o más").tag(90.0)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        Button("Exportar CSV") { model.prepareProgressExport(format: "csv") }
                            .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                        Button("Exportar JSON") { model.prepareProgressExport(format: "json") }
                            .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                        if let progressExportURL = model.progressExportURL {
                            ShareLink(item: progressExportURL) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
                                .accessibilityLabel("Compartir exportación")
                        }
                    }
                    Button("Importar historial JSON") { isImportingProgress = true }
                        .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
                    if !model.progressImportMessage.isEmpty {
                        Text(model.progressImportMessage)
                            .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Para migrar intentos desde una instalación anterior, expórtalos allí como JSON y elige aquí el archivo.")
                        .font(.caption2).foregroundStyle(iOSStudioDesign.muted)
                }
                recommendationCard
                if !model.selectedProgressExerciseID.isEmpty {
                    iOSStudioPanel {
                        Text("TENDENCIA DE PUNTUACIÓN").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                        if chartPoints.isEmpty {
                            Text("Aún no hay intentos completos para este ritmo.").font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                        } else {
                            Chart(chartPoints) { point in
                                LineMark(x: .value("Intento", point.attemptNumber), y: .value("Puntuación", point.score))
                                    .foregroundStyle(iOSStudioDesign.accent)
                                PointMark(x: .value("Intento", point.attemptNumber), y: .value("Puntuación", point.score))
                                    .foregroundStyle(iOSStudioDesign.accent)
                            }
                            .chartYScale(domain: 0...100)
                            .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 70, 100]) }
                            .frame(height: 180)
                            .accessibilityLabel("Tendencia de puntuación de los últimos intentos")
                        }
                        Text("Cada punto representa la puntuación de un intento completo.")
                            .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    }
                }
                if let diagnostics = model.historicalDiagnostics {
                    iOSStudioPanel {
                        Text("ANÁLISIS POR SONIDO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                        if diagnostics.bySound.isEmpty {
                            Text("No hay suficientes eventos históricos detallados.").font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                        } else {
                            ForEach(diagnostics.bySound.filter { $0.expected > 0 }, id: \.label) { item in
                                HStack {
                                    Text(model.kitLabel(for: item.label)).font(.caption.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
                                    Spacer()
                                    Text("\(Int(item.accuracy.rounded())) % · \(item.missed) fallos")
                                        .font(.caption.monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary)
                                    if let median = item.medianOffsetMilliseconds {
                                        Text(String(format: "%+.0f ms", median)).font(.caption2.monospacedDigit()).foregroundStyle(iOSStudioDesign.accent)
                                    }
                                }
                            }
                        }
                    }
                }
                if !model.masterySeals.isEmpty {
                    iOSStudioPanel {
                        Text("SELLOS DE DOMINIO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                        ForEach(Array(model.masterySeals.enumerated()), id: \.offset) { _, seal in
                            Label("\(seal.label) · \(seal.detail)", systemImage: seal.achieved ? "checkmark.seal.fill" : "seal")
                                .font(.caption).foregroundStyle(seal.achieved ? iOSStudioDesign.accent : iOSStudioDesign.secondary)
                        }
                    }
                }
                iOSStudioPanel {
                    Text("INTENTOS RECIENTES").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                    if displayedAttempts.isEmpty {
                        Text("Cuando termines tu primera práctica, aquí aparecerán el ritmo, el tempo y el resultado.")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                    } else {
                        ForEach(displayedAttempts.suffix(20).indices.reversed(), id: \.self) { index in
                            recentAttemptRow(displayedAttempts[index])
                        }
                    }
                }
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func progressMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(iOSStudioDesign.primary)
            Text(title).font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 9))
    }

    private func recentAttemptRow(_ attempt: PracticeAttempt) -> some View {
        let title = model.exercises.first(where: { $0.id == attempt.exerciseID })?.title ?? attempt.exerciseID
        let passedStep = model.exercises.first(where: { $0.id == attempt.exerciseID })
            .flatMap { TempoLadder.highestPassedStep(for: $0, evidence: model.courseEvidence) }
        return Button { model.selectCourseExercise(attempt.exerciseID) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary).lineLimit(2)
                    Text("\(attempt.bpm) BPM · \(attempt.timestamp, style: .date)")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                }
                Spacer()
                if let passedStep { Text(passedStep.label).font(.caption2.bold()).foregroundStyle(iOSStudioDesign.accent) }
                Text("\(Int(attempt.score.rounded())) %").font(.headline.monospacedDigit()).foregroundStyle(iOSStudioDesign.primary)
            }
            .padding(.vertical, 8)
            Rectangle().fill(iOSStudioDesign.border).frame(height: 1)
        }
        .buttonStyle(.plain)
    }

    private func mappingLayout(for size: CGSize) -> some View {
        let horizontalPadding: CGFloat = size.width < 400 ? 12 : 18
        let gridSide = max(0, min(520, size.width - horizontalPadding * 2, size.height * 0.50))
        return ScrollView {
            VStack(spacing: 14) {
                brandHeader
                iOSStudioPanel {
                    Text("APRENDIZAJE DEL CONTROLADOR").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                    if let step = model.mappingNextStep {
                        Text("Pad \(model.mappingAssignedCount + 1) de 16").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(iOSStudioDesign.primary)
                        Text("Golpea la posición física de la rejilla que está iluminada.")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                        let label = model.kitLabel(for: step.sound)
                        Text("\(label) · fila \(step.row + 1), columna \(step.column + 1)")
                            .font(.title3.bold()).foregroundStyle(iOSStudioDesign.primary)
                        iOSPadMapGrid(pads: model.mappingAssignedPads, highlightedRow: step.row, highlightedColumn: step.column, showsMIDI: true)
                            .frame(width: gridSide, height: gridSide)
                        ProgressView(value: Double(model.mappingAssignedCount), total: 16).tint(iOSStudioDesign.accent)
                    }
                    Text(model.mappingMessage).font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Cancelar aprendizaje") {
                        model.cancelPadMapping()
                        model.selectedTab = .layouts
                    }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                }
                .frame(maxWidth: 560)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 8).padding(.bottom, 16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var exercisePreparation: some View {
        iOSStudioPanel {
            Text(model.isCheckpointAssessment ? "PRUEBA FINAL DEL BLOQUE" : "PREPARACIÓN").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
            if let exercise = model.selectedExercise {
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.selectedPracticeTitle).font(.title3.bold()).foregroundStyle(iOSStudioDesign.primary).fixedSize(horizontal: false, vertical: true)
                    if model.isCheckpointAssessment {
                        Text("Resumen del bloque: combina sus habilidades en un patrón completo. Consigue al menos el 70 % al tempo de aprendizaje para acreditarlo. Si quedan bloques anteriores pendientes, el resultado se conserva hasta completarlos.")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("Patrón integrador: \(exercise.title)")
                            .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    }
                    Text(exercise.metadata?.objective ?? "Toca el ritmo completo y mantén el pulso.")
                        .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        metricPill("\(model.selectedBPM) BPM")
                        metricPill("\(exercise.bars) compases")
                        metricPill("\(exercise.notes.count) notas")
                    }
                    if !model.isCheckpointAssessment { tempoLevelSelector(for: exercise) }
                    iOSExercisePattern(exercise: exercise).padding(.top, 2)
                    Text("\(model.selectedRepeats) vueltas · \(durationLabel(model.selectedExerciseDurationMilliseconds)) · \(model.trainingPhase.label)")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    Text("Una pista por sonido. Golpea cuando la nota llegue a la línea.")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    if let incompatibility = model.layoutCompatibilityMessageForUI(exercise) {
                        Label(incompatibility, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(iOSStudioDesign.regular).fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.courseStatus.isEmpty {
                        Text(model.courseStatus).font(.caption).foregroundStyle(iOSStudioDesign.regular).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("El curso integrado no se pudo cargar.").foregroundStyle(iOSStudioDesign.secondary)
            }

            Button {
                model.previewExercise()
            } label: {
                Label("Escuchar y colocar", systemImage: "ear.and.waveform")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
            .disabled(!model.canPreviewSelectedExercise)

            Button {
                model.startPractice()
            } label: {
                Label(model.isCheckpointAssessment ? "Empezar prueba final" : "Empezar práctica", systemImage: model.canScoreSelectedExercise ? "play.fill" : "lock.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(canStartSelectedActivity ? iOSStudioDesign.canvas : iOSStudioDesign.secondary)
                    .background(canStartSelectedActivity ? iOSStudioDesign.accent : iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(iOSStudioDesign.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!canStartSelectedActivity)

            if model.needsEquipmentSetup {
                Button("Configurar controlador en Equipo") { model.selectedTab = .layouts }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
            } else if !model.hasCalibrationForCurrentRoute {
                Text("Puedes escuchar sin puntuar. Para empezar la práctica, calibra esta entrada y salida.")
                    .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                Button("Calibrar ahora") { model.startGuidedCalibration() }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
            }

            if let exercise = model.selectedExercise, !model.isCheckpointAssessment {
                tempoLadder(for: exercise)
                trainingOptions(for: exercise)
                DisclosureGroup("Acompañamiento") { loopPreparationControls.padding(.top, 8) }
                    .tint(iOSStudioDesign.accent)
                Button("Elegir otro ritmo") { model.selectedTab = .course }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
            }
        }
    }

    private var canStartSelectedActivity: Bool {
        model.canScoreSelectedExercise
    }

    private func trainingOptions(for exercise: Exercise) -> some View {
        iOSStudioPanel {
            DisclosureGroup(isExpanded: $showsTrainingOptions) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Descubrir, aislar, integrar y transferir describen qué quieres aprender; una práctica parcial no desbloquea el curso.")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(TrainingPhase.allCases, id: \.self) { phase in
                                Button(phase.label) { model.setTrainingPhase(phase) }
                                    .font(.caption.bold())
                                    .foregroundStyle(model.trainingPhase == phase ? iOSStudioDesign.canvas : iOSStudioDesign.primary)
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(model.trainingPhase == phase ? iOSStudioDesign.accent : iOSStudioDesign.raised, in: Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Text(model.trainingPhase.explanation).font(.caption).foregroundStyle(iOSStudioDesign.secondary)

                    Text("AYUDAS VISUALES").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(iOSStudioDesign.secondary)
                    HStack(spacing: 7) {
                        ForEach(PracticeHelp.allCases, id: \.self) { help in
                            Button(help.label) { model.setPracticeHelp(help) }
                                .font(.caption.bold())
                                .foregroundStyle(model.practiceHelp == help ? iOSStudioDesign.canvas : iOSStudioDesign.primary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(model.practiceHelp == help ? iOSStudioDesign.accent : iOSStudioDesign.raised, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }

                    if model.trainingPhase == .isolate || model.trainingPhase == .integrate {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("QUÉ TOCAS TÚ").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(iOSStudioDesign.secondary)
                                Spacer()
                                Button("Ritmo completo") { model.selectAllPracticeSounds() }
                                    .font(.caption.bold()).foregroundStyle(iOSStudioDesign.accent)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 7)], alignment: .leading, spacing: 7) {
                                ForEach(model.availablePracticeSounds, id: \.self) { sound in
                                    let isSelected = model.selectedPracticeSounds.isEmpty || model.selectedPracticeSounds.contains(sound)
                                    Button { model.togglePracticeSound(sound) } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            Text(model.kitLabel(for: sound)).lineLimit(1)
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isSelected ? iOSStudioDesign.primary : iOSStudioDesign.muted)
                                        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(isSelected ? iOSStudioDesign.raised : iOSStudioDesign.canvas, in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if model.trainingPhase == .isolate || model.practiceFragment != 0 {
                        Picker("Fragmento", selection: Binding(get: { model.practiceFragment }, set: { model.setPracticeFragment($0) })) {
                            Text("Ritmo completo").tag(0)
                            Text("Primera mitad").tag(1)
                            Text("Segunda mitad").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("GAP METRONOME").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(iOSStudioDesign.secondary)
                        Picker("Silencios de claqueta", selection: Binding(get: { model.gapMetronomeLevel }, set: { model.setGapMetronomeLevel($0) })) {
                            Text("Siempre").tag(0)
                            Text("3 + 1").tag(1)
                            Text("2 + 2").tag(2)
                            Text("Pulso ancla").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }
                    .disabled(model.trainingPhase != .integrate && model.trainingPhase != .transfer)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("Entrenamiento, voces y ayudas").font(.subheadline.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
                    Spacer()
                    Text(model.trainingPhase.label).font(.caption.bold()).foregroundStyle(iOSStudioDesign.accent)
                }
            }
            .tint(iOSStudioDesign.accent)
        }
    }

    private func previewLayout(for size: CGSize) -> some View {
        let sceneHeight = max(112, size.height - 230)
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                XRollBrandMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ESCUCHAR Y COLOCAR").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                    Text(model.selectedExercise?.title ?? "Vista previa").font(.subheadline.bold()).foregroundStyle(iOSStudioDesign.primary).lineLimit(1)
                }
                Spacer()
                Button("Detener") { model.stopPreview() }.buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
            }
            if let previewScene = model.previewScene {
                SpriteView(scene: previewScene)
                    .frame(maxWidth: 1_200)
                    .frame(height: sceneHeight)
                    .background(iOSStudioDesign.canvas)
                    .onAppear { previewScene.setReducesMotion(reducesMotion) }
                    .onChange(of: reducesMotion) { previewScene.setReducesMotion($0) }
            }
            iOSStudioPanel {
                Label("Una vuelta de escucha · no se puntúa ni cuenta para el curso", systemImage: "headphones")
                    .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                if size.width < 390 {
                    VStack(spacing: 8) {
                        Button("Repetir escucha") { model.previewExercise() }
                            .buttonStyle(.bordered).tint(iOSStudioDesign.secondary).frame(maxWidth: .infinity)
                        Button("Empezar práctica") { model.startScoredPracticeAfterPreview() }
                            .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas).frame(maxWidth: .infinity)
                            .disabled(!model.canScoreSelectedExercise)
                    }
                } else {
                    HStack {
                        Button("Repetir escucha") { model.previewExercise() }.buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                        Spacer(minLength: 8)
                        Button("Empezar práctica") { model.startScoredPracticeAfterPreview() }
                            .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas)
                            .disabled(!model.canScoreSelectedExercise)
                    }
                }
            }
            .frame(maxWidth: 1_200)
        }
        .padding(.horizontal, size.width < 400 ? 8 : 14).padding(.top, 6).padding(.bottom, 8)
        .frame(maxWidth: 1_300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pausedPracticeLayout: some View {
        ScrollView {
            VStack(spacing: 18) {
                brandHeader
                iOSStudioPanel {
                    Label("Práctica en pausa", systemImage: "pause.circle.fill")
                        .font(.title2.bold()).foregroundStyle(iOSStudioDesign.accent)
                    Text("Para conservar la fase exacta de audio y scoring, al continuar la vuelta empieza de nuevo desde el principio.")
                        .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { model.resumePracticeFromPause() } label: {
                        Label("Reiniciar la vuelta", systemImage: "arrow.clockwise")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas)
                    Button("Descartar sesión") { model.stopPractice() }
                        .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                }
                .frame(maxWidth: 560)
            }
            .padding(16).frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func tempoLadder(for exercise: Exercise) -> some View {
        DisclosureGroup(isExpanded: $showsTempoChallenges) {
            VStack(alignment: .leading, spacing: 7) {
            Stepper(
                "Tempo de práctica · \(model.selectedBPM) BPM",
                value: Binding(get: { model.selectedBPM }, set: { model.setSelectedBPM($0) }),
                in: 40...240,
                step: 5
            )
            .font(.caption.weight(.semibold))
            Text("La lección se supera al tocar el ritmo completo a \(CourseLessonCriteria.targetBPM(for: exercise)) BPM y alcanzar el 70 %. Estos retos de velocidad son opcionales.")
                .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
            Text("\(model.selectedRepeats) vueltas · los retos también exigen el ritmo completo")
                .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
            if let selectedStep = TempoLadder.steps(for: exercise).first(where: { $0.bpm == model.selectedBPM }),
               let minimum = TempoLadder.repeats(for: selectedStep, exercise: exercise) {
                Text("Este escalón necesita al menos \(minimum) vueltas para completar \(selectedStep.minimumBars ?? 0) compases.")
                    .font(.caption2).foregroundStyle(iOSStudioDesign.regular)
            }
            HStack(spacing: 6) {
                let selectedStep = TempoLadder.steps(for: exercise).first(where: { $0.bpm == model.selectedBPM })
                let minimumRepeats = selectedStep.flatMap { TempoLadder.repeats(for: $0, exercise: exercise) } ?? 1
                ForEach([1, 2, 4, 8, 16], id: \.self) { repeats in
                    Button("\(repeats)") { model.setSelectedRepeats(repeats) }
                        .font(.caption.bold().monospacedDigit())
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(model.selectedRepeats == repeats ? iOSStudioDesign.canvas : iOSStudioDesign.primary)
                        .background(model.selectedRepeats == repeats ? iOSStudioDesign.accent : iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 8))
                        .buttonStyle(.plain)
                        .disabled(repeats < minimumRepeats)
                }
            }
            Text("Duración estimada: \(durationLabel(model.selectedExerciseDurationMilliseconds))")
                .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
            }
        } label: {
            Label("Retos opcionales de tempo", systemImage: "speedometer")
                .font(.subheadline.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
        }
        .tint(iOSStudioDesign.accent)
    }

    private func tempoLevelSelector(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NIVEL DE TEMPO").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(iOSStudioDesign.accent)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array(TempoLadder.steps(for: exercise).enumerated()), id: \.offset) { index, step in
                        let selected = model.selectedBPM == step.bpm
                        let passed = TempoLadder.isPassed(step, exerciseID: exercise.id, evidence: model.courseEvidence)
                        Button { model.selectTempoStep(index) } label: {
                            VStack(spacing: 2) {
                                Text(step.label).font(.caption.bold()).lineLimit(1)
                                Text("\(step.bpm) BPM").font(.caption2.monospacedDigit())
                                if passed, case .trophies(let count) = step.award {
                                    Text(String(repeating: "🏆", count: count)).font(.caption2)
                                }
                            }
                            .frame(minWidth: 82).padding(.horizontal, 6).padding(.vertical, 8)
                            .foregroundStyle(selected ? iOSStudioDesign.canvas : iOSStudioDesign.primary)
                            .background(selected ? iOSStudioDesign.accent : iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Seleccionar nivel \(step.label), \(step.bpm) BPM")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var loopPreparationControls: some View {
        if !model.loopOptions.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Acompañamiento", isOn: Binding(get: { model.loopEnabled }, set: { model.setLoopEnabled($0) }))
                    .font(.subheadline.weight(.semibold)).tint(iOSStudioDesign.accent)
                Picker("Loop", selection: Binding(get: { model.loopSelectionChoice }, set: { model.setLoopSelectionChoice($0) })) {
                    Text(model.loopSelectionLabel).tag(LoopLibraryCatalog.automaticSelectionID)
                    ForEach(model.loopOptions) { option in
                        Text(option.bpm.map { "\(option.fileName) · \(Int($0.rounded())) BPM" } ?? option.fileName)
                            .tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isPracticing || model.isPreviewing)
                Text(model.loopStatus).font(.caption2).foregroundStyle(iOSStudioDesign.secondary).lineLimit(2)
            }
        }
    }

    private func durationLabel(_ milliseconds: Double) -> String {
        let totalSeconds = max(1, Int(ceil(milliseconds / 1_000)))
        if totalSeconds >= 60 { return "~\(totalSeconds / 60) min \(totalSeconds % 60) s" }
        return "~\(totalSeconds) s"
    }

    private var calibrationCard: some View {
        iOSStudioPanel {
            HStack(spacing: 8) {
                Image(systemName: model.hasCalibrationForCurrentRoute ? "checkmark.circle.fill" : "waveform.path")
                    .foregroundStyle(model.hasCalibrationForCurrentRoute ? iOSStudioDesign.accent : iOSStudioDesign.regular)
                Text("CALIBRACIÓN").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
            }
            Text(model.calibrationStatus).font(.subheadline).foregroundStyle(iOSStudioDesign.primary).fixedSize(horizontal: false, vertical: true)
            Text("Se guarda para la combinación de entrada, salida de audio y ruta actual.")
                .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
            Button(model.hasCalibrationForCurrentRoute ? "Recalibrar esta ruta" : "Calibrar entrada y salida") {
                model.startGuidedCalibration()
            }
            .buttonStyle(.bordered)
            .tint(iOSStudioDesign.accent)
        }
    }

    private var midiSetupControls: some View {
        iOSStudioPanel {
            Text("EQUIPO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
            Text("Entrada").font(.caption.bold()).foregroundStyle(iOSStudioDesign.secondary)
            Picker("Entrada MIDI", selection: Binding(
                get: { model.selectedMIDISourceID },
                set: { model.selectMIDISource($0) }
            )) {
                Text("Solo táctil").tag(nil as MIDIUniqueID?)
                ForEach(Array(model.midiSources.enumerated()), id: \.offset) { item in
                    let source = item.element
                    if let sourceID = source.uniqueID { Text(source.name).tag(sourceID as MIDIUniqueID?) }
                }
            }
            .pickerStyle(.menu)
            .tint(iOSStudioDesign.primary)

            HStack(spacing: 10) {
                Label(model.midiStatus, systemImage: model.usesTouchInput ? "hand.tap" : "pianokeys")
                    .font(.caption).foregroundStyle(iOSStudioDesign.secondary).lineLimit(2)
                Spacer(minLength: 2)
                Button("Buscar") { model.refreshMIDISources() }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
            }
            Text("USB-MIDI en iPad con Lightning requiere un adaptador Lightning a USB para cámara; algunos pads necesitan alimentación externa. Conecta el controlador y pulsa Buscar.")
                .font(.caption2).foregroundStyle(iOSStudioDesign.muted).fixedSize(horizontal: false, vertical: true)

            Menu {
                Button("Buscar dispositivos Bluetooth MIDI") { model.refreshBluetoothMIDI() }
                ForEach(model.bluetoothMIDIDevices) { device in
                    if device.state == .connected {
                        Button("Desconectar \(device.name)") { model.disconnectBluetoothMIDI() }
                    } else {
                        Button("\(device.name) · \(device.state.label)") { model.connectBluetoothMIDI(device.id) }
                    }
                }
            } label: {
                Label(model.bluetoothMIDIStatus, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11).background(iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    @ViewBuilder
    private var timingTraceSection: some View {
        if !model.timingTraceMessage.isEmpty {
            iOSStudioPanel {
                Label("DIAGNÓSTICO DE SESIÓN", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(iOSStudioDesign.accent)
                Text(model.timingTraceMessage).font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                if let timingTraceURL = model.timingTraceURL {
                    ShareLink(item: timingTraceURL, preview: SharePreview("Traza de sincronía xRoll")) {
                        Label("Compartir traza temporal", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .tint(iOSStudioDesign.accent)
                }
            }
        }
    }

    private var resultLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                brandHeader
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.resultIsPartial ? "SESIÓN INTERRUMPIDA" : "SESIÓN TERMINADA").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(model.resultIsPartial ? iOSStudioDesign.regular : iOSStudioDesign.accent)
                    Text(model.lastCompletedExerciseTitle).font(.title2.bold()).foregroundStyle(iOSStudioDesign.primary).fixedSize(horizontal: false, vertical: true)
                }
                if model.resultIsPartial {
                    iOSStudioPanel {
                        Label("\(model.resultCompletedBars) compases completados", systemImage: "pause.circle")
                            .font(.headline).foregroundStyle(iOSStudioDesign.primary)
                        Text(model.scoreText).font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                        Button { model.repeatLastExercise() } label: {
                            Label("Repetir el ritmo completo", systemImage: "arrow.clockwise")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas)
                    }
                }
                if let score = model.completedScore {
                    iOSStudioPanel {
                        Text("RESULTADO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(Int(score.percentage.rounded())) %")
                                .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(iOSStudioDesign.primary)
                            Text(String(repeating: "★", count: score.stars) + String(repeating: "☆", count: 3 - score.stars))
                                .font(.title3.bold()).foregroundStyle(iOSStudioDesign.regular)
                        }
                        Text("\(score.hits.count) golpes registrados · \(score.misses.count) notas sin golpear")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                        DisclosureGroup("Ver detalles del resultado", isExpanded: $showsScoreDetails) {
                            VStack(spacing: 8) {
                                Rectangle().fill(iOSStudioDesign.border).frame(height: 1)
                                HStack(spacing: 6) {
                                    resultMetric("Perfectos", value: score.perfectCount, color: iOSStudioDesign.accent)
                                    resultMetric("Bien", value: score.goodCount, color: iOSStudioDesign.leftHand)
                                    resultMetric("Casi", value: score.regularCount, color: iOSStudioDesign.regular)
                                    resultMetric("Fallos", value: score.misses.count + score.extraCount, color: iOSStudioDesign.miss)
                                }
                            }.padding(.top, 8)
                        }
                        .font(.subheadline.weight(.semibold)).tint(iOSStudioDesign.accent)
                    }

                    if let insights = model.resultInsights {
                        iOSStudioPanel {
                            Text("EVIDENCIA TEMPORAL").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                            Text(insights.timingLabel).font(.headline).foregroundStyle(iOSStudioDesign.primary)
                            HStack(spacing: 8) {
                                metricPill(insights.medianOffsetMilliseconds.map { String(format: "Mediana %+.0f ms", $0) } ?? "Sin golpes asociados")
                                metricPill(insights.medianAbsoluteDeviationMilliseconds.map { String(format: "Dispersión %.0f ms", $0) } ?? "Sin dispersión")
                            }
                            Text("La mediana resume la tendencia; la dispersión indica cuánto varían tus golpes.")
                                .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                        }
                    }
                    if !model.resultHitRecords.isEmpty {
                        iOSStudioPanel {
                            DisclosureGroup(isExpanded: $showsTimingMicroscope) {
                                iOSMiniTimingMap(records: model.resultHitRecords, labelForSound: { model.kitLabel(for: $0) })
                                    .padding(.top, 8)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("MICROSCOPIO TEMPORAL")
                                        .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1)
                                        .foregroundStyle(iOSStudioDesign.accent)
                                    Spacer()
                                    Text(showsTimingMicroscope ? "Ocultar" : "\(model.resultHitRecords.count) golpes · Ver detalle")
                                        .font(.caption2.weight(.medium)).foregroundStyle(iOSStudioDesign.secondary)
                                }
                            }
                            .tint(iOSStudioDesign.accent)
                        }
                    }
                }
                if !model.resultIsPartial, model.resultSummary != nil {
                    resultActionPanel
                } else if model.resultIsPartial {
                    iOSStudioPanel {
                        Text("SIGUIENTE PASO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
                        Text("Termina el ritmo completo para obtener una evaluación y avanzar en el curso.")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                        Button { model.repeatLastExercise() } label: {
                            Label("Repetir el ritmo completo", systemImage: "arrow.clockwise")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas)
                        Button("Volver al menú") { model.returnToCourseMenu() }
                            .buttonStyle(.bordered).tint(iOSStudioDesign.primary)
                    }
                }
                timingTraceSection
            }
            .frame(maxWidth: 850)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var resultActionPanel: some View {
        iOSStudioPanel {
            resultActionSummary
            resultPrimaryActions
            resultCoachingActions
            resultRoutineActions
        }
    }

    private var resultActionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUÉ PASÓ").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
            Text(model.resultDiagnosisText).font(.headline).foregroundStyle(iOSStudioDesign.primary).fixedSize(horizontal: false, vertical: true)
            Text(model.displayedResultActionReason).font(.subheadline).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.coachingFeedback.isEmpty {
                Label(model.coachingFeedback, systemImage: "sparkles")
                    .font(.subheadline.weight(.medium)).foregroundStyle(iOSStudioDesign.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.pulseDriftMessage.isEmpty {
                Label(model.pulseDriftMessage, systemImage: "metronome.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(iOSStudioDesign.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let report = model.pulseDriftReport {
                iOSPulseDriftChart(report: report)
            }
            if !model.ghostCoachCue.isEmpty {
                Text(model.ghostCoachCue).font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resultPrimaryActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.performResultAction() } label: {
                Label(model.resultActionTitle, systemImage: "arrow.right.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas)
            if let alternative = model.alternativeProgressTitle {
                Button(alternative) { model.performAlternativeProgressAction() }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
            }
            Button("Ajustar práctica") { model.returnToPreparation() }
                .buttonStyle(.bordered).tint(iOSStudioDesign.primary)
            Button("Volver al menú") { model.returnToCourseMenu() }
                .buttonStyle(.bordered).tint(iOSStudioDesign.primary)
        }
    }

    @ViewBuilder
    private var resultCoachingActions: some View {
        if model.canStartCorrectivePractice {
            Button { model.startCorrectivePractice() } label: {
                Label("Practicar la parte difícil", systemImage: "scope")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
        }
        if model.canReturnToFullGroove {
            Button { model.returnToFullGroove() } label: {
                Label("Volver al groove completo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
        }
    }

    @ViewBuilder
    private var resultRoutineActions: some View {
        if model.hasDailyPracticePlanForToday, model.dailyPracticePlan?.currentBlock != nil {
            Button("Siguiente bloque de mi sesión diaria") { model.startNextDailyBlock() }
                .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
            Button("Omitir este bloque") { model.skipNextDailyBlock() }
                .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
        } else if model.dailyPracticeCompletedToday {
            Text("Sesión diaria completa. El próximo repaso quedará para otro día.")
                .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
        }
        if model.pulseTrainingStage != nil {
            Button("Repetir / avanzar pulso interno") { model.startNextPulseStage() }
                .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
        }
    }

    @ViewBuilder
    private func practiceLayout(for size: CGSize) -> some View {
        let horizontalPadding: CGFloat = size.width < 400 ? 6 : 10
        let bodyHeight = max(0, size.height - 52)
        let isLandscape = size.width > size.height * 1.25
        let touchSideBySide = model.usesTouchInput && (size.width >= 760 || isLandscape)

        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(model.isCalibrating ? "Calibración" : model.selectedPracticeTitle)
                    .font(.subheadline.bold()).foregroundStyle(iOSStudioDesign.primary).lineLimit(1).minimumScaleFactor(0.78)
                Spacer(minLength: 3)
                if model.selectedExercise != nil { metricPill("\(model.activeBPM) BPM") }
                if !model.isCalibrating {
                    Button { model.pausePractice() } label: {
                        Image(systemName: "pause.fill").frame(width: 34, height: 32)
                    }
                    .buttonStyle(.bordered).tint(iOSStudioDesign.accent)
                    .accessibilityLabel("Pausar práctica")
                }
                Button { model.stopPractice() } label: {
                    Image(systemName: "xmark").frame(width: 34, height: 32)
                }
                .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                .accessibilityLabel(model.isCalibrating ? "Cancelar calibración" : "Terminar práctica")
            }
            .frame(height: 36)

            if touchSideBySide {
                let padSize = max(0, min(340, bodyHeight - 36, size.width - horizontalPadding * 2 - 280))
                HStack(spacing: 8) {
                    practiceScene(height: bodyHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                    touchPracticeControls(padSize: padSize)
                        .frame(width: padSize + 12, height: bodyHeight)
                }
                .frame(height: bodyHeight)
            } else if model.usesTouchInput {
                let padSize = max(0, min(320, size.width - horizontalPadding * 2 - 12, bodyHeight * 0.40, bodyHeight - 206))
                let controlsHeight = padSize + 36
                let sceneHeight = max(160, bodyHeight - controlsHeight - 6)
                VStack(spacing: 6) {
                    practiceScene(height: sceneHeight)
                    touchPracticeControls(padSize: padSize)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: bodyHeight)
            } else {
                VStack(spacing: 6) {
                    practiceScene(height: max(120, bodyHeight - 38))
                    midiPracticeStatus
                }
                .frame(height: bodyHeight)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 4).padding(.bottom, 6)
        .frame(maxWidth: 1_300, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func practiceScene(height: CGFloat) -> some View {
        if let scene = model.scene {
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: height)
                .background(iOSStudioDesign.canvas)
                .onAppear { scene.setReducesMotion(reducesMotion) }
                .onChange(of: reducesMotion) { scene.setReducesMotion($0) }
        }
    }

    private var midiPracticeStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: "pianokeys").foregroundStyle(iOSStudioDesign.accent)
            Text(model.selectedMIDISourceName ?? "MIDI")
                .foregroundStyle(iOSStudioDesign.primary).lineLimit(1)
            Spacer(minLength: 4)
            Text(model.isCalibrating ? "\(model.calibrationHitCount) golpes" : model.lastMIDINote)
                .font(.caption.monospaced()).foregroundStyle(iOSStudioDesign.secondary).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10).frame(height: 32)
        .background(iOSStudioDesign.surface, in: RoundedRectangle(cornerRadius: 9))
    }

    private func touchPracticeControls(padSize: CGFloat) -> some View {
        VStack(spacing: 4) {
            PadTouchGrid(pads: model.pads) { padID, timestamp in
                model.registerPad(id: padID, touchTimestamp: timestamp)
            }
            .frame(width: padSize, height: padSize)
            Text(model.isCalibrating ? "\(model.calibrationHitCount) golpes" : model.lastHit)
                .font(.caption2).foregroundStyle(iOSStudioDesign.secondary).lineLimit(1)
        }
        .frame(width: padSize + 12, height: padSize + 36)
        .background(iOSStudioDesign.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func resultMetric(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(iOSStudioDesign.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 9))
    }

    private func metricPill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(iOSStudioDesign.primary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(iOSStudioDesign.raised, in: Capsule())
    }
}

private struct iOSExercisePattern: View {
    let exercise: Exercise
    private let soundOrder = ["kick", "snare", "hihat_closed", "hihat_open", "rim", "clap", "tom_low", "tom_high", "crash", "ride"]

    var body: some View {
        let activeSounds = soundOrder.filter { sound in exercise.notes.contains(where: { $0.sound == sound }) }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(activeSounds, id: \.self) { sound in
                HStack(spacing: 4) {
                    Circle().fill(color(for: sound)).frame(width: 6, height: 6)
                    ForEach(0..<exercise.grid, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(exercise.notes.contains(where: { $0.sound == sound && $0.step % exercise.grid == step }) ? color(for: sound) : iOSStudioDesign.border)
                            .frame(maxWidth: .infinity, minHeight: 7, maxHeight: 7)
                    }
                }
            }
        }
        .accessibilityLabel("Vista previa del patrón")
    }

    private func color(for sound: String) -> Color {
        switch sound {
        case "kick", "tom_low", "tom_high": return iOSStudioDesign.leftHand
        case "snare", "rim", "clap": return iOSStudioDesign.rightHand
        default: return iOSStudioDesign.accent
        }
    }
}

private struct iOSPadMapGrid: View {
    let pads: [PadMapV2.Pad]
    var highlightedRow: Int?
    var highlightedColumn: Int?
    var showsMIDI: Bool

    init(pads: [PadMapV2.Pad], highlightedRow: Int? = nil, highlightedColumn: Int? = nil, showsMIDI: Bool) {
        self.pads = pads
        self.highlightedRow = highlightedRow
        self.highlightedColumn = highlightedColumn
        self.showsMIDI = showsMIDI
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array((0..<4).reversed()), id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { column in
                        padCell(row: row, column: column)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rejilla física de pads de cuatro por cuatro")
    }

    private func padCell(row: Int, column: Int) -> some View {
        let pad = pads.first(where: { $0.row == row && $0.column == column })
        let isHighlighted = row == highlightedRow && column == highlightedColumn
        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHighlighted ? iOSStudioDesign.accent.opacity(0.27) : (pad == nil ? iOSStudioDesign.canvas : iOSStudioDesign.raised))
            VStack(spacing: 2) {
                Text(pad.map(shortName(for:)) ?? (isHighlighted ? "GOLPEA" : "—"))
                    .font(.system(size: showsMIDI ? 8 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isHighlighted ? iOSStudioDesign.accent : (pad == nil ? iOSStudioDesign.muted : color(for: pad!.sound)))
                    .lineLimit(1).minimumScaleFactor(0.65)
                if showsMIDI, let pad {
                    Text("\(pad.input.number) · \(pad.input.channel)")
                        .font(.system(size: 6, weight: .medium, design: .monospaced))
                        .foregroundStyle(iOSStudioDesign.secondary).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(2)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isHighlighted ? iOSStudioDesign.accent : iOSStudioDesign.border, lineWidth: isHighlighted ? 2 : 1))
        .accessibilityLabel(pad.map { "Fila \($0.row + 1), columna \($0.column + 1), \(shortName(for: $0)), nota MIDI \($0.input.number), canal \($0.input.channel)" }
            ?? "Fila \(row + 1), columna \(column + 1), sin asignar")
    }

    private func shortName(for pad: PadMapV2.Pad) -> String {
        switch pad.sound {
        case "kick": return "BOMBO"
        case "snare": return "CAJA"
        case "hihat_closed": return "HH CERR."
        case "hihat_open": return "HH AB."
        case "tom_low": return "TOM G."
        case "tom_high": return "TOM A."
        case "crash": return "CRASH"
        case "ride": return "RIDE"
        case "clap": return "PALM."
        case "rim": return "ARO"
        default: return pad.sound.uppercased()
        }
    }

    private func color(for sound: String) -> Color {
        switch sound {
        case "kick", "tom_low", "tom_high": return iOSStudioDesign.leftHand
        case "snare", "rim", "clap": return iOSStudioDesign.rightHand
        default: return iOSStudioDesign.accent
        }
    }
}

private struct iOSCourseChapterPanel: View {
    let chapter: iOSCourseChapter
    let states: [String: CourseLevelState]
    let evidence: [CourseAttemptEvidence]
    let selectedExerciseID: String
    let selectExercise: (String) -> Void
    let selectCheckpoint: (String) -> Void
    @State private var isExpanded: Bool

    init(chapter: iOSCourseChapter, states: [String: CourseLevelState], evidence: [CourseAttemptEvidence], selectedExerciseID: String, expandsInitially: Bool, selectExercise: @escaping (String) -> Void, selectCheckpoint: @escaping (String) -> Void) {
        self.chapter = chapter
        self.states = states
        self.evidence = evidence
        self.selectedExerciseID = selectedExerciseID
        self.selectExercise = selectExercise
        self.selectCheckpoint = selectCheckpoint
        _isExpanded = State(initialValue: expandsInitially)
    }

    private var masteredCount: Int {
        chapter.exercises.filter { states[$0.id]?.status == .mastered }.count
    }

    private var isAccredited: Bool {
        chapter.exercises.allSatisfy { states[$0.id]?.chapterAccredited == true }
    }

    var body: some View {
        iOSStudioPanel {
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(spacing: 8) {
                        ForEach(chapter.exercises, id: \.id) { exercise in
                            iOSCourseExerciseRow(
                                exercise: exercise,
                                state: states[exercise.id],
                                evidence: evidence,
                                isSelected: selectedExerciseID == exercise.id,
                                selectExercise: selectExercise
                            )
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(chapter.title).font(.headline).foregroundStyle(iOSStudioDesign.primary)
                            Spacer()
                            Text(isAccredited ? "Acreditado" : "\(masteredCount) / \(chapter.exercises.count)")
                                .font(.caption.bold().monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary)
                        }
                        ProgressView(value: Double(masteredCount), total: Double(max(1, chapter.exercises.count)))
                            .tint(iOSStudioDesign.accent)
                    }
                }
                if let checkpoint = chapter.checkpointExercise {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Prueba del bloque · tempo de aprendizaje · ritmo completo · 70 %")
                                .font(.caption.bold()).foregroundStyle(iOSStudioDesign.accent)
                            Text("Acredita el capítulo sin completar cada ejercicio básico. Los checkpoints futuros guardan su resultado y se activan al acreditar la ruta previa.")
                                .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
                        }
                        Spacer(minLength: 4)
                        Button { selectCheckpoint(checkpoint.id) } label: {
                            Label("Hacer prueba", systemImage: "forward.fill")
                                .font(.caption.bold()).padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent).tint(iOSStudioDesign.accent).foregroundStyle(iOSStudioDesign.canvas)
                    }
                    .padding(10).background(iOSStudioDesign.raised, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }
}

private struct iOSCourseExerciseRow: View {
    let exercise: Exercise
    let state: CourseLevelState?
    let evidence: [CourseAttemptEvidence]
    let isSelected: Bool
    var showsAward = true
    let selectExercise: (String) -> Void

    private var status: CourseLevelStatus { state?.status ?? .locked }
    private var tempoStep: TempoPracticeStep? { TempoLadder.nextStep(for: exercise, evidence: evidence) }

    var body: some View {
        Button { selectExercise(exercise.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: status == .mastered ? "checkmark.circle.fill" : (status == .available ? "play.circle.fill" : "music.note"))
                    .font(.subheadline).foregroundStyle(status == .mastered ? iOSStudioDesign.accent : (status == .available ? iOSStudioDesign.secondary : iOSStudioDesign.muted))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(exercise.title).font(.subheadline.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
                        Spacer(minLength: 4)
                        if showsAward, let award = TempoLadder.highestPassedStep(for: exercise, evidence: evidence)?.award {
                            iOSCourseAwardBadge(award: award)
                        }
                        if let score = state?.bestScore {
                            Text("\(Int(score.rounded())) %").font(.caption.bold().monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary)
                        }
                    }
                    Text(exercise.metadata?.objective ?? "\(exercise.bpm) BPM · \(exercise.bars) compases")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 7) {
                        Text(statusLabel).foregroundStyle(status == .mastered ? iOSStudioDesign.accent : iOSStudioDesign.secondary)
                        if let tempoStep { Text("· \(tempoStep.label) · \(tempoStep.bpm) BPM").foregroundStyle(iOSStudioDesign.secondary) }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
            }
            .padding(11)
            .background(isSelected ? iOSStudioDesign.raised : iOSStudioDesign.canvas, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? iOSStudioDesign.accent : iOSStudioDesign.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Selecciona y practica este ritmo. La acreditación curricular tiene requisitos propios.")
    }

    private var statusLabel: String {
        if case .checkpoint(exerciseID: _) = state?.creditSource {
            return "Acreditado por checkpoint"
        }
        switch status {
        case .locked: return "Puedes practicar · pendiente de acreditar"
        case .available: return "Siguiente recomendado"
        case .mastered: return state?.chapterAccredited == true ? "Acreditado" : "Superado · capítulo pendiente"
        }
    }
}

private struct iOSCourseAwardBadge: View {
    let award: TempoAward

    var body: some View {
        HStack(spacing: 3) {
            switch award {
            case .stars(let count):
                Text(String(repeating: "★", count: count))
            case .trophies(let count):
                Text(String(repeating: "🏆", count: count))
            }
        }
        .font(.caption.bold())
        .foregroundStyle(isTrophy ? iOSStudioDesign.regular : .yellow)
        .accessibilityLabel(award.label)
    }

    private var isTrophy: Bool {
        if case .trophies = award { return true }
        return false
    }
}

private struct iOSMiniTimingMap: View {
    let records: [HitRecord]
    let labelForSound: (String) -> String

    private var displayedRecords: [HitRecord] { Array(records.prefix(24)) }
    private var scaleMilliseconds: Double {
        max(35, displayedRecords.compactMap { $0.offsetMilliseconds.map(abs) }.max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Centro = objetivo · izquierda = antes · derecha = después")
                .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
            ForEach(Array(displayedRecords.enumerated()), id: \.offset) { _, record in
                HStack(spacing: 8) {
                    Text(labelForSound(record.expectedSound ?? record.actualSound ?? "Sonido"))
                        .font(.caption2.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
                        .lineLimit(1).frame(width: 74, alignment: .leading)
                    GeometryReader { geometry in
                        let middle = geometry.size.width / 2
                        ZStack {
                            Rectangle().fill(iOSStudioDesign.border).frame(height: 2)
                            Rectangle().fill(iOSStudioDesign.muted).frame(width: 1, height: 15).position(x: middle, y: 9)
                            if let offset = record.offsetMilliseconds {
                                Circle()
                                    .fill(color(for: record.judgement))
                                    .frame(width: 9, height: 9)
                                    .position(x: middle + CGFloat(max(-1, min(1, offset / scaleMilliseconds))) * max(0, middle - 5), y: 9)
                            } else if record.judgement == .miss {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(iOSStudioDesign.miss)
                                    .position(x: middle, y: 9)
                            } else {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(iOSStudioDesign.miss)
                                    .position(x: middle, y: 9)
                            }
                        }
                    }
                    .frame(height: 18)
                    if let offset = record.offsetMilliseconds {
                        Text(String(format: "%+.0f", offset))
                            .font(.caption2.monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary)
                            .frame(width: 43, alignment: .trailing)
                    } else {
                        Text(record.judgement == .miss ? "FALTA" : "EXTRA")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(iOSStudioDesign.miss)
                            .frame(width: 43, alignment: .trailing)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(record))
            }
            if records.count > displayedRecords.count {
                Text("Se muestran los primeros \(displayedRecords.count) eventos; el JSON conserva la sesión completa.")
                    .font(.caption2).foregroundStyle(iOSStudioDesign.muted)
            }
        }
    }

    private func color(for judgement: RhythmJudgement) -> Color {
        switch judgement {
        case .perfect: return iOSStudioDesign.accent
        case .good: return iOSStudioDesign.leftHand
        case .regular: return iOSStudioDesign.regular
        case .miss, .extra: return iOSStudioDesign.miss
        }
    }

    private func accessibilityLabel(_ record: HitRecord) -> String {
        let sound = labelForSound(record.expectedSound ?? record.actualSound ?? "Sonido")
        guard let offset = record.offsetMilliseconds else {
            return record.judgement == .miss ? "\(sound), falta el golpe esperado" : "\(sound), golpe extra"
        }
        return "\(sound), \(Int(offset.rounded())) milisegundos \(offset < 0 ? "antes" : "después")"
    }
}

struct iOSAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.activeTintColor = UIColor(red: 0.388, green: 0.902, blue: 0.745, alpha: 1)
        picker.tintColor = UIColor(red: 0.639, green: 0.671, blue: 0.710, alpha: 1)
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

private struct PadTouchGrid: UIViewRepresentable {
    let pads: [PadMapV2.Pad]
    let onHit: (String, TimeInterval) -> Void

    func makeUIView(context: Context) -> TouchGridView {
        let view = TouchGridView()
        view.onHit = onHit
        view.pads = pads
        return view
    }

    func updateUIView(_ view: TouchGridView, context: Context) {
        view.onHit = onHit
        view.pads = pads
        view.setNeedsDisplay()
    }
}

private final class TouchGridAccessibilityElement: UIAccessibilityElement {
    var activatePad: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let activatePad else { return false }
        activatePad()
        return true
    }
}

private final class TouchGridView: UIView {
    var pads: [PadMapV2.Pad] = [] {
        didSet {
            if oldValue != pads { updateAccessibilityElements() }
        }
    }
    var onHit: ((String, TimeInterval) -> Void)?
    private var accessibilityPadElements = [String: TouchGridAccessibilityElement]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isOpaque = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateAccessibilityFrames()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let width = bounds.width / 4
        let height = bounds.height / 4
        for pad in pads {
            let frame = CGRect(x: CGFloat(pad.column) * width + 3,
                               y: CGFloat(3 - pad.row) * height + 3,
                               width: max(1, width - 6),
                               height: max(1, height - 6))
            let isActive = activePadTokens[pad.id] != nil
            let soundColor = UIColor(cgColor: GameplayVisualTheme.soundAccent(pad.sound).cgColor)
            let padColor = isActive
                ? soundColor
                : UIColor(red: 0.075, green: 0.094, blue: 0.118, alpha: 1)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: min(10, frame.height * 0.12))
            context.setFillColor(padColor.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
            context.setStrokeColor((isActive ? UIColor.white : soundColor).withAlphaComponent(isActive ? 0.82 : 0.52).cgColor)
            context.setLineWidth(isActive ? 1.5 : 1)
            context.addPath(path.cgPath)
            context.strokePath()
            let face = UIBezierPath(roundedRect: frame.insetBy(dx: 4, dy: 4), cornerRadius: min(7, frame.height * 0.10))
            context.setFillColor(UIColor(cgColor: GameplayVisualTheme.padFace.cgColor).withAlphaComponent(isActive ? 0.42 : 1).cgColor)
            context.addPath(face.cgPath)
            context.fillPath()
            let cap = CGRect(x: frame.minX + 9, y: frame.minY + 6, width: max(2, frame.width - 18), height: 3)
            context.setFillColor(soundColor.withAlphaComponent(isActive ? 1 : 0.75).cgColor)
            context.fill(cap)

            var symbolTransform = CGAffineTransform(translationX: frame.midX, y: frame.midY - 7)
            let symbol = GameplayVisualTheme.padSymbolPath(for: pad.sound).copy(using: &symbolTransform)
            if let symbol {
                context.setStrokeColor(soundColor.cgColor)
                context.setLineWidth(1.6)
                context.addPath(symbol)
                context.strokePath()
            }
            let label = pad.sound.replacingOccurrences(of: "_", with: " ").uppercased()
            var fontSize = min(CGFloat(13), max(CGFloat(8), width / 7))
            let maximumLabelWidth = max(1, frame.width - 8)
            while fontSize > 8 && (label as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)]).width > maximumLabelWidth {
                fontSize -= 1
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(isActive ? 1 : 0.88)
            ]
            let text = label as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY + 8 - size.height / 2), withAttributes: attributes)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            let column = min(3, max(0, Int(point.x / max(1, bounds.width) * 4)))
            let row = 3 - min(3, max(0, Int(point.y / max(1, bounds.height) * 4)))
            if let pad = pads.first(where: { $0.row == row && $0.column == column }) {
                activate(pad, at: touch.timestamp)
            }
        }
    }

    private func updateAccessibilityElements() {
        accessibilityPadElements = Dictionary(uniqueKeysWithValues: pads.map { pad in
            let element = TouchGridAccessibilityElement(accessibilityContainer: self)
            let soundName = pad.sound.replacingOccurrences(of: "_", with: " ")
            element.accessibilityLabel = "\(soundName), fila \(pad.row + 1), columna \(pad.column + 1)"
            element.accessibilityHint = "Toca dos veces para golpear este pad."
            element.accessibilityTraits = .button
            element.activatePad = { [weak self] in
                self?.activate(pad, at: ProcessInfo.processInfo.systemUptime)
            }
            return (pad.id, element)
        })
        accessibilityElements = pads.compactMap { accessibilityPadElements[$0.id] }
        updateAccessibilityFrames()
    }

    private func updateAccessibilityFrames() {
        let width = bounds.width / 4
        let height = bounds.height / 4
        for pad in pads {
            accessibilityPadElements[pad.id]?.accessibilityFrameInContainerSpace = CGRect(
                x: CGFloat(pad.column) * width,
                y: CGFloat(3 - pad.row) * height,
                width: width,
                height: height
            )
        }
    }

    private func activate(_ pad: PadMapV2.Pad, at timestamp: TimeInterval) {
        let visualToken = UUID()
        activePadTokens[pad.id] = visualToken
        setNeedsDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(110)) { [weak self] in
            guard let self, self.activePadTokens[pad.id] == visualToken else { return }
            self.activePadTokens.removeValue(forKey: pad.id)
            self.setNeedsDisplay()
        }
        onHit?(pad.id, timestamp)
    }

    private var activePadTokens = [String: UUID]()
}

private struct iOSPulseDriftChart: View {
    let report: PulseDriftReport

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DERIVA DURANTE EL SILENCIO")
                .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8)
                .foregroundStyle(iOSStudioDesign.secondary)
            GeometryReader { geometry in
                let points = report.points
                let width = max(1, geometry.size.width)
                let height = max(1, geometry.size.height)
                let extent = max(40, points.map { abs($0.medianOffsetMilliseconds) }.max() ?? 40)
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addLine(to: CGPoint(x: width, y: height / 2))
                    }
                    .stroke(iOSStudioDesign.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if points.count > 1 {
                        Path { path in
                            for (index, point) in points.enumerated() {
                                let x = width * CGFloat(index) / CGFloat(points.count - 1)
                                let normalized = CGFloat(point.medianOffsetMilliseconds / extent)
                                let y = height / 2 - normalized * (height * 0.42)
                                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(iOSStudioDesign.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let x = width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                        let normalized = CGFloat(point.medianOffsetMilliseconds / extent)
                        let y = height / 2 - normalized * (height * 0.42)
                        Circle().fill(point.metronomeAudible ? iOSStudioDesign.accent : iOSStudioDesign.regular)
                            .frame(width: 6, height: 6).position(x: x, y: y)
                    }
                }
            }
            .frame(height: 72)
            Text("Arriba = retraso · abajo = adelanto · amarillo = silencio del metrónomo")
                .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gráfica de desfase por pulso. El centro representa cero milisegundos; arriba es retraso, abajo adelanto y los puntos amarillos corresponden al silencio del metrónomo.")
    }
}
