import AppKit
import SwiftUI
import XRollCore

struct StagePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioDesign.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(StudioDesign.surfaceHover, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
    }
}

/// Ayuda contextual: las explicaciones no deben obligar a un principiante a
/// abandonar la pantalla ni recordar vocabulario de la aplicación.
struct ContextInfoButton: View {
    let title: String
    let detail: String
    @State private var isShowingInfo = false

    var body: some View {
        Button { isShowingInfo.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(StudioDesign.accent)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Qué significa \(title)")
        .accessibilityLabel("Información: \(title)")
        .popover(isPresented: $isShowingInfo, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline).foregroundColor(StudioDesign.textPrimary)
                Text(detail).font(.subheadline).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(width: 300, alignment: .leading)
            .background(StudioDesign.surface)
        }
    }
}

func contextHeading(_ title: String, detail: String) -> some View {
    HStack(spacing: 5) {
        Text(title).font(.headline)
        ContextInfoButton(title: title, detail: detail)
    }
}

struct AppMark: View {
    var size: CGFloat = 34
    var body: some View { XRollBrandMark(size: size) }
}

enum ActionButtonProminence {
    case primary
    case secondary
    case quiet
}

/// Buttons in xRoll never use the system's light macOS button background.  The
/// explicit colours keep their label legible in every dark panel and state.
struct ActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var prominence: ActionButtonProminence = .secondary
    let action: () -> Void

    init(_ title: String, prominence: ActionButtonProminence = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.prominence = prominence
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundColor(labelColor)
                .background(backgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var labelColor: Color {
        prominence == .primary ? StudioDesign.canvas : StudioDesign.textPrimary
    }

    private var backgroundColor: Color {
        switch prominence {
        case .primary: return StudioDesign.accent
        case .secondary: return StudioDesign.surfaceRaised
        case .quiet: return Color.clear
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .primary: return StudioDesign.accent.opacity(0.72)
        case .secondary: return StudioDesign.surfaceHover
        case .quiet: return StudioDesign.textMuted.opacity(0.42)
        }
    }
}

struct PracticeHome: View {
    @ObservedObject var model: Model
    @State private var showingSessionControls = false

    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    PracticeHeader(model: model)
                    HStack(alignment: .top, spacing: 14) {
                        CoursePanel(model: model).frame(minWidth: 440, maxWidth: 560)
                        PlayerColumn(model: model).frame(maxWidth: .infinity)
                        SessionControlRail { showingSessionControls = true }.frame(width: 48)
                    }.padding(.horizontal, 20)
                    PracticeFooter(model: model)
                }
                .padding(.bottom, 12)
            }.foregroundColor(.white)
            if showingSessionControls {
                Color.black.opacity(0.18).ignoresSafeArea().onTapGesture { showingSessionControls = false }
                HStack { Spacer(); SessionColumn(model: model, close: { showingSessionControls = false }).frame(width: 340).padding(.trailing, 18).padding(.top, 74) }
                    .transition(.move(edge: .trailing).combined(with: .opacity)).zIndex(2)
            }
        }
    }
}

struct ResultsHome: View {
    @ObservedObject var model: Model
    @State private var showsEvidence = false
    @State private var showsDetailedAnalysis = false
    @State private var showsTimingDetail = false
    @State private var showsTimingTable = false

    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    AppMark(size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isCheckpointAssessment ? "PRUEBA DEL BLOQUE COMPLETADA" : "EJERCICIO TERMINADO")
                            .font(.studioLabel).foregroundColor(StudioDesign.accent)
                        Text(model.currentExerciseTitle).font(.title.bold()).foregroundColor(.white)
                    }
                }
                if let outcome = model.checkpointAssessmentOutcome {
                    Label(outcome, systemImage: outcome.contains("no superada") ? "arrow.counterclockwise" : "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(outcome.contains("no superada") ? StudioDesign.regular : StudioDesign.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StagePanel {
                    Text("1 · QUÉ PASÓ").font(.studioLabel).foregroundColor(StudioDesign.accent)
                    Text(model.resultDiagnosis).font(.system(size: 25, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int((model.lastScorePercentage ?? 0).rounded())) %").font(.title2.bold()).foregroundColor(StudioDesign.textPrimary)
                        Text(String(repeating: "★", count: model.lastScoreStars) + String(repeating: "☆", count: 3 - model.lastScoreStars)).font(.headline).foregroundColor(StudioDesign.regular)
                        Text(String(format: "%.1f / %d puntos", model.lastPoints, model.lastPossiblePoints)).font(.caption).foregroundColor(StudioDesign.textSecondary)
                    }
                }
                StagePanel {
                    DisclosureGroup("Ver detalles del resultado", isExpanded: $showsEvidence) {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("2 · LA EVIDENCIA").font(.studioLabel).foregroundColor(StudioDesign.accent)
                    HStack(spacing: 18) {
                        diagnosticMetric("Precisión", "\(Int((model.lastScorePercentage ?? 0).rounded())) %")
                        diagnosticMetric("Desvío puntuado", model.resultTimingMetric)
                        diagnosticMetric("Consistencia", model.resultConsistencyMetric)
                    }
                    if !model.lastHitRecords.isEmpty {
                        Button { showsTimingDetail.toggle() } label: {
                            TimingMicroscopeSummary(records: model.lastHitRecords, expanded: showsTimingDetail)
                        }
                        .buttonStyle(.plain)
                        if showsTimingDetail {
                            HStack(spacing: 5) {
                                Text("MICROSCOPIO TEMPORAL").font(.studioLabel).foregroundColor(StudioDesign.accent)
                                ContextInfoButton(title: "Microscopio temporal", detail: "Cada línea es un golpe esperado. El centro es el momento correcto: a la izquierda llegaste antes y a la derecha después. Una X significa que faltó ese golpe.")
                            }
                            Text("Centro = objetivo. Izquierda: antes; derecha: después.").font(.caption2).foregroundColor(StudioDesign.textSecondary)
                            TimingMicroscope(records: model.lastHitRecords)
                            Toggle("Mostrar tabla temporal accesible", isOn: $showsTimingTable)
                            if showsTimingTable { TimingRecordsTable(records: model.lastHitRecords, displayName: model.displayName) }
                        }
                    }
                    DisclosureGroup("Ver análisis completo", isExpanded: $showsDetailedAnalysis) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                ScoreStat("Golpes", value: model.lastTotalHits, color: StudioDesign.textPrimary)
                                ScoreStat("Bien", value: model.lastWellTimed, color: StudioDesign.accent)
                                ScoreStat("Regular", value: model.lastRegular, color: StudioDesign.regular)
                                ScoreStat("Mal", value: model.lastWrong, color: StudioDesign.miss)
                            }
                            if let p95 = model.resultSummary?.percentile95AbsoluteMilliseconds {
                                Text(String(format: "El 95 %% de los golpes asociados quedó dentro de %.0f ms del objetivo.", p95)).font(.caption).foregroundColor(StudioDesign.textSecondary)
                            }
                            if !model.soundStatistics.isEmpty {
                                Text("POR SONIDO").font(.studioLabel).foregroundColor(StudioDesign.textMuted)
                                ForEach(model.soundStatistics.sorted(by: { $0.accuracy < $1.accuracy }), id: \.sound) { statistic in
                                    HStack {
                                        Text(model.displayName(statistic.sound)).frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(Int(statistic.accuracy.rounded())) %").monospacedDigit()
                                        Text("\(statistic.missed) fallos").foregroundColor(StudioDesign.textSecondary).frame(width: 72, alignment: .trailing)
                                    }.font(.caption)
                                }
                            }
                            if !model.masterySeals.isEmpty {
                                Text("SELLOS DE DOMINIO").font(.studioLabel).foregroundColor(StudioDesign.textMuted)
                                HStack(spacing: 8) { ForEach(model.masterySeals, id: \.label) { seal in MasterySealView(seal: seal) } }
                            }
                        }.padding(.top, 10)
                    }
                    }
                }
                }
                StagePanel {
                    Text("3 · QUÉ HACER AHORA").font(.studioLabel).foregroundColor(StudioDesign.accent)
                    if !model.microLessonFeedback.isEmpty {
                        Label(model.microLessonFeedback, systemImage: "sparkles")
                            .font(.subheadline.weight(.medium)).foregroundColor(StudioDesign.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.performanceFeedback.isEmpty {
                        Label(model.performanceFeedback, systemImage: "music.note.list")
                            .font(.subheadline.weight(.medium)).foregroundColor(StudioDesign.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.pulseDriftMessage.isEmpty {
                        Label(model.pulseDriftMessage, systemImage: "metronome.fill")
                            .font(.subheadline.weight(.medium)).foregroundColor(StudioDesign.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let report = model.pulseDriftReport {
                        PulseDriftChart(report: report)
                    }
                    Text(model.resultActionTitle).font(.title2.bold())
                    Text(model.resultActionReason).font(.subheadline).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
                    if model.canStartCorrectivePractice {
                        Text(model.correctiveActionReason).font(.caption).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
                        ActionButton("Practicar la parte difícil", prominence: .secondary) { model.startCorrectivePractice() }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ActionButton(model.resultActionTitle, prominence: .primary) { model.performResultAction() }
                            if let alternative = model.alternativeProgressTitle {
                                ActionButton(alternative, prominence: .secondary) { model.performAlternativeProgressAction() }
                            }
                        }
                        HStack(spacing: 10) {
                            if model.performanceFeedback.isEmpty && model.canStartTransferPerformance {
                                ActionButton(model.transferPerformanceTitle, prominence: .secondary) { model.startTransferPerformance() }
                            } else if !model.performanceFeedback.isEmpty {
                                ActionButton("Volver a la guía completa", prominence: .secondary) { model.startGuidedPerformance() }
                            }
                            if model.resultSummary?.action == .repeatWithAdjustment {
                                ActionButton("Repetir sin ajuste", prominence: .secondary) { model.repeatPractice() }
                            }
                            ActionButton("Volver", prominence: .quiet) { model.dismissResults() }
                        }
                        if model.hasDailyPracticePlanForToday, model.dailyPracticePlan?.currentBlock != nil {
                            ActionButton("Siguiente bloque de la sesión diaria", prominence: .secondary) { model.startNextDailyBlock() }
                            ActionButton("Omitir este bloque", prominence: .quiet) { model.skipNextDailyBlock() }
                        } else if model.dailyPracticeCompletedToday {
                            Text("Sesión diaria completa. Puedes volver mañana para el siguiente repaso.")
                                .font(.caption).foregroundColor(StudioDesign.textSecondary)
                        }
                        if model.pulseTrainingStage != nil {
                            ActionButton("Repetir / avanzar pulso interno", prominence: .secondary) { model.startNextPulseStage() }
                        }
                    }
                }
            }.foregroundColor(.white).padding(32).frame(maxWidth: 760, alignment: .leading)
            }.frame(maxWidth: .infinity)
            .onAppear {
                showsTimingDetail = false
                showsTimingTable = false
                showsEvidence = false
            }
        }
    }
}

private struct TimingMicroscopeSummary: View {
    let records: [HitRecord]
    let expanded: Bool

    var body: some View {
        let expected = records.filter { $0.expectedSound != nil }
        let precise = expected.filter { $0.judgement == .perfect || $0.judgement == .good }.count
        let regular = expected.filter { $0.judgement == .regular }.count
        let missed = expected.filter { $0.judgement == .miss }.count
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg").foregroundColor(StudioDesign.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Detalle temporal").font(.caption.bold()).foregroundColor(StudioDesign.textPrimary)
                Text("\(precise) en tiempo · \(regular) regulares · \(missed) fallos")
                    .font(.caption2).foregroundColor(StudioDesign.textSecondary)
            }
            Spacer()
            HStack(spacing: 3) {
                Capsule().fill(StudioDesign.accent).frame(width: max(6, CGFloat(precise) * 2), height: 5)
                Capsule().fill(StudioDesign.regular).frame(width: max(6, CGFloat(regular) * 2), height: 5)
                Capsule().fill(StudioDesign.miss).frame(width: max(6, CGFloat(missed) * 2), height: 5)
            }
            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.bold()).foregroundColor(StudioDesign.textSecondary)
        }
        .padding(10)
        .background(StudioDesign.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detalle temporal: \(precise) golpes en tiempo, \(regular) regulares y \(missed) fallos. \(expanded ? "Ocultar detalle" : "Mostrar detalle")")
    }
}

private func diagnosticMetric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) { Text(title).font(.studioLabel).foregroundColor(StudioDesign.textMuted); Text(value).font(.caption).foregroundColor(StudioDesign.textPrimary).lineLimit(3) }.frame(maxWidth: .infinity, alignment: .leading)
}

private struct MasterySealView: View {
    let seal: MasterySeal
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(seal.achieved ? "✓ \(seal.label)" : "○ \(seal.label)").font(.caption.bold()).foregroundColor(seal.achieved ? StudioDesign.accent : StudioDesign.textPrimary)
            Text(seal.detail).font(.caption2).foregroundColor(StudioDesign.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(StudioDesign.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimingMicroscope: View {
    let records: [HitRecord]
    var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(records.filter { $0.expectedSound != nil }.prefix(12).enumerated()), id: \.offset) { _, record in
                HStack(spacing: 8) {
                    Text(record.expectedSound ?? record.actualSound ?? "—").font(.caption2).frame(width: 70, alignment: .leading)
                    GeometryReader { proxy in
                        let midpoint = proxy.size.width / 2
                        ZStack(alignment: .leading) {
                            Rectangle().fill(StudioDesign.textMuted.opacity(0.35)).frame(height: 2).position(x: midpoint, y: 10)
                            Rectangle().fill(StudioDesign.textMuted.opacity(0.45)).frame(width: 1, height: 18).position(x: midpoint, y: 10)
                            if let offset = record.offsetMilliseconds {
                                Circle().fill(record.judgement == .perfect || record.judgement == .good ? StudioDesign.accent : StudioDesign.regular).frame(width: 10, height: 10).position(x: midpoint + CGFloat(max(-95, min(95, offset)) / 95) * (midpoint - 8), y: 10)
                            } else { Image(systemName: "xmark.circle.fill").foregroundColor(StudioDesign.miss).position(x: midpoint, y: 10) }
                        }
                    }.frame(height: 20)
                    Text(record.offsetMilliseconds.map { String(format: "%+.0f ms", $0) } ?? "fallo").font(.caption2.monospacedDigit()).foregroundColor(StudioDesign.textSecondary).frame(width: 56, alignment: .trailing)
                }
            }
        }.padding(.top, 2)
    }
}

private struct TimingRecordsTable: View {
    let records: [HitRecord]
    let displayName: (String) -> String

    var body: some View {
        LazyVStack(spacing: 0) {
            HStack {
                Text("Sonido").frame(maxWidth: .infinity, alignment: .leading)
                Text("Juicio").frame(width: 76, alignment: .leading)
                Text("Desvío").frame(width: 72, alignment: .trailing)
            }.font(.caption.bold()).foregroundColor(StudioDesign.textMuted).padding(.vertical, 5)
            ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                HStack {
                    Text(displayName(record.expectedSound ?? record.actualSound ?? "")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(judgementLabel(record.judgement)).frame(width: 76, alignment: .leading)
                    Text(record.offsetMilliseconds.map { String(format: "%+.0f ms", $0) } ?? "No aplica").monospacedDigit().frame(width: 72, alignment: .trailing)
                }.font(.caption).padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription(record))
                Divider().overlay(StudioDesign.surfaceHover)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabla temporal completa")
    }

    private func judgementLabel(_ judgement: RhythmJudgement) -> String {
        switch judgement {
        case .perfect: return "Perfecto"
        case .good: return "Bien"
        case .regular: return "Regular"
        case .miss: return "Fallo"
        case .extra: return "Extra"
        }
    }

    private func accessibilityDescription(_ record: HitRecord) -> String {
        let sound = displayName(record.expectedSound ?? record.actualSound ?? "sonido desconocido")
        guard let offset = record.offsetMilliseconds else { return "\(sound), \(judgementLabel(record.judgement)), sin desvío aplicable" }
        if abs(offset) < 0.5 { return "\(sound), \(judgementLabel(record.judgement)), a tiempo" }
        return "\(sound), \(judgementLabel(record.judgement)), \(Int(abs(offset).rounded())) milisegundos \(offset < 0 ? "antes" : "después")"
    }
}

struct PreparationHome: View {
    @ObservedObject var model: Model
    @State private var showsMoreOptions = false
    private var courseSteps: [Exercise] {
        guard let chapter = model.chosen?.metadata?.chapter else { return [] }
        return model.exercises.filter { $0.metadata?.chapter == chapter }
            .sorted { ($0.metadata?.position ?? 0) < ($1.metadata?.position ?? 0) }
    }
    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            ScrollView {
                preparationContent
            }.frame(maxWidth: .infinity)
        }
    }

    private var preparationContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.isCheckpointAssessment ? "PRUEBA FINAL DEL BLOQUE" : "PREPARACIÓN")
                .font(.studioLabel).foregroundColor(StudioDesign.accent)
            Text(model.currentExerciseTitle).font(.system(size: 30, weight: .bold))
            if model.isCheckpointAssessment {
                checkpointAssessmentPanel
            } else {
                objectivePanel
                tempoLevelSelector
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.trainingPhase == .discover
                         ? "Escucha una vuelta sin puntuación; después vuelve aquí para tocar."
                         : "\(model.trainingPhase.label) · \(model.isFullRhythmSelection ? "Ritmo completo" : "Voces seleccionadas") · Ayuda \(model.practiceHelp.label)")
                        .font(.subheadline).foregroundColor(StudioDesign.textSecondary)
                    Text("Una pista por sonido. Golpea cuando la nota llegue a la línea; los sonidos apagados conservan su sitio.")
                        .font(.caption).foregroundColor(StudioDesign.textSecondary)
                    HStack(spacing: 10) {
                        ActionButton("Escuchar demostración", prominence: .secondary) { model.previewExercise() }
                        ActionButton(model.trainingPhase == .discover ? "Escuchar sin puntuar" : "Empezar práctica", prominence: .primary) { model.startFromPreparation() }
                    }
                    if !model.hasCalibrationForCurrentProfile {
                        HStack {
                            Text("Antes de puntuar, calibra esta entrada y salida. Puedes escuchar la demostración mientras tanto.")
                                .font(.caption).foregroundColor(StudioDesign.textSecondary)
                            ActionButton("Calibrar ahora") { model.startCalibration() }
                        }
                    }
                    if !model.isFullRhythmSelection || model.transferCheck {
                        Text("Esta práctica parcial sirve para aprender; vuelve al ritmo completo para acreditar la lección.")
                            .font(.caption).foregroundColor(StudioDesign.regular)
                    }
                }
                StagePanel {
                    DisclosureGroup(isExpanded: $showsMoreOptions) {
                        VStack(alignment: .leading, spacing: 14) {
                            tempoLadderPanel
                            sessionViewPanel
                            practiceOptionsPanel
                            loopPreparationPanel
                            courseStepsPanel
                        }.padding(.top, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Personalizar o explorar").font(.headline)
                            Text("Primero este ejercicio: tempo, ayudas y voces; después otras lecciones").font(.caption).foregroundColor(StudioDesign.textSecondary)
                        }
                    }
                    .tint(StudioDesign.accent)
                }
            }
            HStack { ActionButton("Volver", prominence: .quiet) { model.dismissPreparation() }; Spacer() }
        }
        .foregroundColor(StudioDesign.textPrimary).padding(36).frame(maxWidth: 720, alignment: .leading)
    }

    private var checkpointAssessmentPanel: some View {
        let targetBPM = model.chosen.map { CourseLessonCriteria.targetBPM(for: $0) } ?? model.selectedBPM
        return StagePanel {
            Text("QUÉ DEMUESTRA").font(.studioLabel).foregroundColor(StudioDesign.accent)
            Text("Resumen del bloque: toca su patrón integrador completo a \(targetBPM) BPM y alcanza el 70 %. Si quedan bloques anteriores pendientes, la prueba queda guardada hasta acreditarlos.")
                .font(.studioBody).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let exercise = model.chosen {
                Text(exercise.metadata?.objective ?? "Combina las habilidades practicadas en este bloque.")
                    .font(.subheadline).foregroundColor(StudioDesign.textSecondary)
                Text("Patrón integrador: \(exercise.title)").font(.caption).foregroundColor(StudioDesign.textSecondary)
                ExercisePatternPreview(exercise: exercise, available: true)
            }
            HStack {
                StudioStatusPill(title: "Ritmo completo")
                StudioStatusPill(title: "\(targetBPM) BPM")
                StudioStatusPill(title: "70 % para aprobar")
            }
            ActionButton("Empezar prueba", prominence: .primary) { model.startGuidedLesson() }
            if !model.hasCalibrationForCurrentProfile {
                HStack {
                    Text("Calibra esta entrada y salida antes de empezar la prueba.")
                        .font(.caption).foregroundColor(StudioDesign.textSecondary)
                    ActionButton("Calibrar ahora") { model.startCalibration() }
                }
            }
        }
    }

    @ViewBuilder private var courseStepsPanel: some View {
        let steps = courseSteps
        if steps.count > 1 {
            StagePanel {
                Text("Otras lecciones de este bloque").font(.headline)
                Text("Puedes explorar cualquier lección. La ruta guiada añade una idea cada vez.").font(.caption).foregroundColor(StudioDesign.textSecondary)
                ForEach(steps, id: \.id) { step in
                    Button { model.selectPreparationExercise(step) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.chosenID == step.id ? "checkmark.circle.fill" : "circle").padding(.top, 4)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(step.title).font(.subheadline.bold()).lineLimit(1)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("\(CourseLessonCriteria.targetBPM(for: step)) BPM").font(.caption.bold())
                                        Text(model.tempoProgressSummary(for: step)).font(.caption2).foregroundColor(StudioDesign.textSecondary)
                                    }
                                }
                                ExercisePatternPreview(exercise: step, available: true)
                                Text("Incluye: \(Array(Set(step.notes.map { model.displayName($0.sound) })).sorted().joined(separator: " · "))").font(.caption2).foregroundColor(StudioDesign.textSecondary)
                            }
                        }
                        .foregroundColor(model.chosenID == step.id ? StudioDesign.accent : StudioDesign.textPrimary).padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var objectivePanel: some View {
        StagePanel {
            Text("Objetivo").font(.headline)
            Text(model.lessonGoal).font(.studioBody).foregroundColor(StudioDesign.textSecondary)
            HStack { StudioStatusPill(title: "\(model.selectedBPM) BPM"); StudioStatusPill(title: "\(model.selectedRepeats) vueltas"); StudioStatusPill(title: model.status, active: model.status.contains("MIDI")) }
        }
    }

    private var tempoLevelSelector: some View {
        StagePanel {
            Text("NIVEL DE TEMPO").font(.studioLabel).foregroundColor(StudioDesign.accent)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(Array(model.tempoPracticeOptions.enumerated()), id: \.offset) { index, step in
                        let selected = model.selectedBPM == step.bpm
                        Button { model.selectTempoTier(index) } label: {
                            VStack(spacing: 2) {
                                Text(step.label).font(.caption.bold()).lineLimit(1)
                                Text("\(step.bpm) BPM").font(.caption2.monospacedDigit())
                            }
                            .frame(minWidth: 78).padding(.horizontal, 5).padding(.vertical, 8)
                            .foregroundColor(selected ? StudioDesign.canvas : StudioDesign.textPrimary)
                            .background(selected ? StudioDesign.accent : StudioDesign.surfaceRaised, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Seleccionar nivel \(step.label), \(step.bpm) BPM")
                    }
                }
            }
            Text("El tempo de aprendizaje basta para avanzar; los niveles más rápidos son retos opcionales.")
                .font(.caption2).foregroundColor(StudioDesign.textSecondary)
        }
    }

    @ViewBuilder
    private var loopPreparationPanel: some View {
        if !model.loopOptions.isEmpty {
            StagePanel {
                HStack {
                    Text("Acompañamiento").font(.headline)
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.loopEnabled }, set: { model.setLoopEnabled($0) }))
                        .labelsHidden()
                }
                Picker("Loop", selection: Binding(get: { model.loopSelectionChoice }, set: { model.setLoopSelection($0) })) {
                    Text(model.loopSelectionLabel).tag(LoopLibraryCatalog.automaticSelectionID)
                    ForEach(model.loopOptions) { option in
                        Text(option.bpm.map { "\(option.fileName) · \(Int($0.rounded())) BPM" } ?? option.fileName)
                            .tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!model.canChangeLoopSelection)
                Text(model.loopStatus).font(.caption2).foregroundColor(StudioDesign.textSecondary).lineLimit(2)
            }
        }
    }

    private var tempoLadderPanel: some View {
        StagePanel {
            Text("Retos opcionales de tempo").font(.headline)
            Text("El curso avanza cuando superas el ritmo completo a su tempo de referencia. Prueba más velocidad cuando te apetezca; no es un requisito.").font(.caption).foregroundColor(StudioDesign.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(model.tempoPracticeOptions.enumerated()), id: \.offset) { index, step in
                    tempoStepButton(index: index, step: step)
                }
            }.padding(.top, 3)
            Text(model.tempoGuidance).font(.caption).foregroundColor(StudioDesign.accent)
        }
    }

    private func tempoStepButton(index: Int, step: TempoPracticeStep) -> some View {
        let stars = model.starsForTempoTier(index)
        let available = model.isTempoTierAvailable(index)
        return Button { model.selectTempoTier(index) } label: {
            VStack(spacing: 3) {
                Text("\(step.label) · \(step.bpm) BPM").font(.subheadline.bold())
                Text(step.minimumBars.map { "\(model.tempoTierProgressLabel(index)) · \($0) compases" } ?? model.tempoTierProgressLabel(index)).font(.caption2)
                    .foregroundColor(stars == nil ? StudioDesign.textMuted : .yellow)
                HStack(spacing: 3) {
                    if case .trophies(let count) = step.award {
                        Text(String(repeating: "🏆", count: count)).font(.caption2)
                    } else {
                        Image(systemName: step.award.symbolName).font(.caption2)
                    }
                    Text("Premio · \(step.award.label)").font(.caption2.bold())
                }.foregroundColor(step.award.symbolName == "star.fill" ? .yellow : StudioDesign.regular)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .foregroundColor(model.selectedBPM == step.bpm ? StudioDesign.canvas : (available ? StudioDesign.textPrimary : StudioDesign.textMuted))
            .background(model.selectedBPM == step.bpm ? StudioDesign.accent : StudioDesign.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.selectedBPM == step.bpm ? StudioDesign.accent : StudioDesign.surfaceHover, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).disabled(!available)
    }

    private var sessionViewPanel: some View {
        StagePanel {
            HStack(spacing: 5) {
                Text("Sesión y vista").font(.headline)
                ContextInfoButton(title: "Sesión y vista", detail: "Configura la práctica antes de entrar en la pantalla de ejecución. Durante el ejercicio estos controles se ocultan para dejar todo el espacio a los carriles.")
            }
            HStack(alignment: .center, spacing: 20) {
                Stepper("Tempo: \(model.selectedBPM) BPM", value: $model.selectedBPM, in: 40...240, step: 5).onChange(of: model.selectedBPM) { _ in
                    model.refreshAutomaticLoopForSelection()
                    model.savePreferences()
                }
                repeatStepper(model: model)
            }
            Toggle("Metrónomo", isOn: $model.metronomeEnabled)
            HStack(spacing: 14) {
                gridGuidePicker
                practiceZoomPicker
            }
            Text("Durante la práctica solo verás el ejercicio, el tempo, la vuelta y la pausa.").font(.caption2).foregroundColor(StudioDesign.textSecondary)
        }
    }

    private var gridGuidePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Rejilla").font(.caption.weight(.semibold)).foregroundColor(StudioDesign.textSecondary)
            Picker("Rejilla", selection: Binding(get: { model.gridGuide }, set: { model.setGridGuide($0) })) { ForEach(GridGuideSubdivision.allCases) { guide in Text(guide.label).tag(guide) } }.pickerStyle(.segmented).labelsHidden()
        }
    }

    private var practiceZoomPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Compases visibles").font(.caption.weight(.semibold)).foregroundColor(StudioDesign.textSecondary)
            Picker("Compases visibles", selection: Binding(get: { model.practiceViewZoom }, set: { model.setPracticeViewZoom($0) })) { ForEach(PracticeViewZoom.allCases) { zoom in Text(zoom.label).tag(zoom) } }.pickerStyle(.segmented).labelsHidden()
        }
    }

    private var practiceOptionsPanel: some View {
        StagePanel {
            VStack(alignment: .leading, spacing: 10) {
                trainingPhaseControls
                practiceSelectionControls
                transferControls
            }
        }
    }

    @ViewBuilder private var trainingPhaseControls: some View {
        if model.showsTrainingPhases {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text("Fase de entrenamiento D-A-I-T").font(.headline)
                    ContextInfoButton(title: "D-A-I-T", detail: "Es una ruta para aprender sin saltos: Descubrir el patrón, Aislar una parte, Integrar el ritmo completo y Transferirlo retirando una guía. Puedes elegir cualquier fase según lo que necesites hoy.")
                }
                HStack(spacing: 8) {
                    ForEach(TrainingPhase.allCases, id: \.self) { phase in
                        ActionButton(phase.label, prominence: model.trainingPhase == phase ? .primary : .secondary) { model.setTrainingPhase(phase) }
                    }
                }
                Text("Activa ahora: \(model.trainingPhase.label). \(model.trainingPhase.explanation)").font(.caption).foregroundColor(StudioDesign.textSecondary)
            }
        }
    }

    private var practiceSelectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prácticas del ritmo").font(.headline).padding(.top, 4)
            Text("Elige el groove completo o una sola línea para practicarla con el resto como acompañamiento.").font(.studioBody).foregroundColor(StudioDesign.textSecondary)
            practiceHelpControls
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text("Qué tocas tú").font(.subheadline.weight(.semibold))
                    ContextInfoButton(title: "Qué tocas tú", detail: "Puedes elegir una o varias líneas. Las seleccionadas son tus notas: aparecen con color vivo y se puntúan. Las que dejes fuera se ven en gris y xRoll las toca como acompañamiento.")
                }
                Text("Selecciona las líneas que vas a tocar. Las apagadas suenan como referencia, pero no tienes que golpearlas.").font(.caption).foregroundColor(StudioDesign.textSecondary)
                HStack(spacing: 8) {
                    ActionButton("Ritmo completo", prominence: model.isFullRhythmSelection ? .primary : .secondary) { model.selectFullRhythm() }
                    Text(model.isFullRhythmSelection ? "Tocas todas las líneas" : "Tocas \(model.selectedPlayerSounds.count) líneas").font(.caption2).foregroundColor(StudioDesign.textSecondary)
                }
                FlowSoundSelection(model: model)
            }
        }
    }

    @ViewBuilder private var practiceHelpControls: some View {
        if model.showsTrainingPhases {
            HStack(spacing: 5) {
                Text("Ayudas").font(.subheadline.weight(.semibold))
                ContextInfoButton(title: "Ayudas", detail: "Completa muestra y suena todo lo necesario. Normal retira parte de la guía. Reducida deja más espacio para que sostengas el ritmo por tu cuenta. Empieza por Completa si es la primera vez.")
            }
            HStack(spacing: 8) {
                ForEach(PracticeHelp.allCases, id: \.self) { help in
                    ActionButton(help.label, prominence: model.practiceHelp == help ? .primary : .secondary) { model.setPracticeHelp(help) }
                }
            }
            Text("Activa ahora: \(model.practiceHelp.label). \(model.practiceHelpDescription)").font(.caption).foregroundColor(StudioDesign.textSecondary)
        }
    }

    @ViewBuilder private var transferControls: some View {
        if model.showsTrainingPhases {
            HStack(spacing: 5) {
                Toggle("Prueba de transferencia", isOn: $model.transferCheck)
                ContextInfoButton(title: "Prueba de transferencia", detail: "Oculta y deja sin puntuar el charles mientras sigue sonando. Sirve para comprobar si puedes conservar el groove sin depender de verlo en pantalla.")
            }
            if model.transferCheck {
                Text("El charles se oye, pero no aparece ni se puntúa: mantén el groove sin perseguirlo visualmente.").font(.caption).foregroundColor(StudioDesign.textSecondary)
            }
            HStack(spacing: 5) {
                Text("Gap Metronome").font(.subheadline.weight(.semibold))
                ContextInfoButton(title: "Gap Metronome", detail: "La claqueta se calla durante algunos compases. Tu trabajo es mantener el pulso interno hasta que vuelva. “3+1” son tres compases con claqueta y uno sin ella.")
            }
            Picker("Gap Metronome", selection: $model.gapMetronomeLevel) { Text("Guía total").tag(0); Text("3+1 compases").tag(1); Text("2+2 compases").tag(2); Text("Pulso ancla").tag(3) }.pickerStyle(.menu).labelsHidden()
            Text("Los huecos de claqueta empiezan después de la cuenta inicial; sirven para medir tu pulso interno.").font(.caption2).foregroundColor(StudioDesign.textSecondary)
        }
    }
}

private struct FlowSoundSelection: View {
    @ObservedObject var model: Model
    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(model.availablePracticeSounds, id: \.self) { sound in
                let selected = model.selectedPlayerSounds.contains(sound)
                Button { model.togglePlayerSound(sound) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        Text(model.displayName(sound)).lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(selected ? StudioDesign.textPrimary : StudioDesign.textMuted)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? StudioDesign.accent.opacity(0.22) : StudioDesign.surfaceRaised.opacity(0.48))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? StudioDesign.accent.opacity(0.75) : StudioDesign.surfaceHover, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(model.displayName(sound)): \(selected ? "la tocas tú" : "acompañamiento de xRoll")")
            }
        }
    }
}

struct OnboardingHome: View {
    @ObservedObject var model: Model
    let showPads: () -> Void
    @State private var quote = DrummerQuote.random()
    var body: some View {
        ZStack { StudioDesign.canvas.ignoresSafeArea(); ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text("INICIO").font(.studioLabel).foregroundColor(StudioDesign.accent)
            if model.needsHomeSetup { setupPanel }
            Text("Tu próxima sesión").font(.system(size: 34, weight: .bold))
            if let plan = model.nextSessionPlan {
                StagePanel {
                    let pendingBPM = model.pendingTempoBPM(for: plan.exerciseID) ?? plan.bpm
                    let repeats = model.pendingRepeats(for: plan)
                    let duration = plan.estimatedDurationMilliseconds * Double(plan.bpm) / Double(pendingBPM)
                        * Double(repeats) / Double(max(1, plan.repeats))
                    Text(planKindLabel(plan.kind)).font(.studioLabel).foregroundColor(StudioDesign.accent)
                    Text(plan.title).font(.system(size: 28, weight: .bold))
                    Text(plan.bpm == pendingBPM ? plan.reason : "Continúa este ritmo en su primer nivel de tempo pendiente.")
                        .font(.studioBody).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        StudioStatusPill(title: "\(pendingBPM) BPM")
                        StudioStatusPill(title: "\(repeats) vueltas")
                        StudioStatusPill(title: estimatedDuration(duration))
                    }
                    ActionButton("Empezar ahora", prominence: .primary) { model.openNextSession() }
                }
            } else {
                StagePanel {
                    Text("Aún no hay una sesión disponible").font(.headline)
                    Text("Carga un ejercicio o revisa el curso para preparar tu primer ritmo.").font(.studioBody).foregroundColor(StudioDesign.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("VOCES DEL RITMO").font(.studioLabel).foregroundColor(StudioDesign.accent)
                Text("«\(quote.text)»").font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text("— \(quote.author)").font(.caption).foregroundColor(StudioDesign.textSecondary)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioDesign.surface, in: RoundedRectangle(cornerRadius: 14))
            Text("La preparación confirma objetivo, ayudas y equipo antes de puntuar.").font(.caption).foregroundColor(StudioDesign.textMuted)
        }.foregroundColor(StudioDesign.textPrimary).padding(36).frame(maxWidth: 900, alignment: .leading) } }
    }

    private var setupPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            if !model.hasAssignedPad {
                StagePanel {
                    Text("EQUIPO").font(.studioLabel).foregroundColor(StudioDesign.accent)
                    Text(model.sources.isEmpty ? "Conecta y asigna tu pad para empezar." : "Elige el controlador que vas a usar.")
                        .font(.caption).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
                    ActionButton("Asignar pad", prominence: .primary) { showPads() }
                }
                .frame(maxWidth: .infinity)
            }
            if !model.hasCalibrationForCurrentProfile {
                StagePanel {
                    Text("CALIBRACIÓN").font(.studioLabel).foregroundColor(StudioDesign.accent)
                    Text("Calibra esta ruta de entrada y audio antes de puntuar.")
                        .font(.caption).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
                    ActionButton("Calibrar ahora", prominence: .primary) { model.startCalibration() }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func estimatedDuration(_ milliseconds: Double) -> String {
        let seconds = max(1, Int((milliseconds / 1_000).rounded()))
        return seconds >= 60 ? "\(seconds / 60) min" : "~\(seconds) s"
    }

    private func planKindLabel(_ kind: NextSessionKind) -> String {
        switch kind {
        case .firstSession: return "PRIMER RITMO"
        case .corrective: return "CORREGIR UNA VOZ"
        case .consolidate: return "CONSOLIDAR"
        case .continueCourse: return "SIGUIENTE ESCALÓN"
        case .review: return "REPASO INTELIGENTE"
        }
    }
}

private struct PracticeHeader: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                AppMark(size: 38)
                Text("xRoll").font(.largeTitle.bold())
                Text("FINGER DRUMMING").font(.studioLabel).foregroundColor(StudioDesign.accent)
            }
            Spacer()
            HStack(spacing: 7) {
                StudioStatusPill(title: model.status, active: model.status.contains("MIDI"))
                ActionButton("↻ MIDI", prominence: .secondary) { model.refreshMIDIDevices() }
            }
        }.padding(.horizontal, 24).padding(.top, 22)
    }
}

private struct CoursePanel: View {
    @ObservedObject var model: Model
    var body: some View {
        RhythmMetroView(model: model)
    }
}

/// Resumen que permite saber dónde está la persona sin abrir cada bloque.
private struct CourseProgressOverview: View {
    @ObservedObject var model: Model
    let exercises: [Exercise]

    private func state(_ exercise: Exercise) -> CourseLevelStatus? {
        model.courseLevels.first(where: { $0.exerciseID == exercise.id })?.status
    }

    var body: some View {
        let mastered = exercises.filter { state($0) == .mastered }.count
        let currentIndex = exercises.firstIndex { state($0) != .mastered }
        let current = currentIndex.flatMap { exercises.indices.contains($0) ? exercises[$0] : nil }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("TU PROGRESO").font(.studioLabel).foregroundColor(StudioDesign.accent)
                Spacer()
                Text("\(mastered) / \(exercises.count) niveles").font(.caption.bold()).foregroundColor(StudioDesign.textPrimary)
            }
            ProgressView(value: Double(mastered), total: Double(max(1, exercises.count))).tint(StudioDesign.accent)
            if let current, let currentIndex {
                Text("Nivel actual \(currentIndex + 1): \(current.title)").font(.caption.bold()).foregroundColor(StudioDesign.textPrimary).lineLimit(1)
            } else {
                Text("Curso consolidado: puedes repasar cualquier bloque o subir el tempo.").font(.caption.bold()).foregroundColor(StudioDesign.accent)
            }
        }
        .padding(10)
        .background(StudioDesign.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct BlockProgressHeader: View {
    @ObservedObject var model: Model
    let block: CourseBlock
    let exercises: [Exercise]

    private func state(_ exercise: Exercise) -> CourseLevelStatus? {
        model.courseLevels.first(where: { $0.exerciseID == exercise.id })?.status
    }

    var body: some View {
        let mastered = exercises.filter { state($0) == .mastered }.count
        let next = exercises.first { state($0) != .mastered }
        let isOpen = next.map { state($0) == .available } ?? false
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(block.title).font(.studioLabel).foregroundColor(StudioDesign.accent)
                Text(block.subtitle).font(.caption2).foregroundColor(StudioDesign.textMuted)
                Spacer()
                Text("\(mastered)/\(exercises.count)").font(.caption.bold()).foregroundColor(StudioDesign.textSecondary)
            }
            ProgressView(value: Double(mastered), total: Double(max(1, exercises.count))).tint(StudioDesign.accent)
            if let next {
                Text(isOpen ? "Siguiente guiada: \(next.title)" : "Puedes explorar el bloque; acredita su checkpoint o supera todos sus ejercicios.")
                    .font(.caption2).foregroundColor(isOpen ? StudioDesign.textSecondary : StudioDesign.textMuted).lineLimit(1)
            } else {
                Text("Bloque acreditado · continúa con la siguiente estación.").font(.caption2).foregroundColor(StudioDesign.accent)
            }
        }
    }
}

/// Ruta específica para aprender cierres sin mezclarla con el curso de
/// grooves. El orden siempre es: gesto aislado, después el mismo gesto dentro
/// de una frase que vuelve a un ritmo conocido.
struct FillsHome: View {
    @ObservedObject var model: Model

    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("REDOBLES Y TRANSICIONES").font(.studioLabel).foregroundColor(StudioDesign.accent)
                            Text("Haz que el ritmo avance").font(.largeTitle.bold())
                            Text("Un redoble es una frase corta que conecta dos partes del ritmo. Primero aprendes el gesto sin acompañamiento; después lo colocas entre dos compases sencillos.")
                                .font(.subheadline).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        AppMark(size: 48)
                    }
                    .padding(.bottom, 4)

                    ForEach(FillType.allCases, id: \.self) { fill in
                        FillTrainingCard(model: model, fill: fill)
                    }
                }
                .foregroundColor(.white)
                .padding(28)
                .frame(maxWidth: 920, alignment: .leading)
            }
        }
    }
}

private enum FillType: CaseIterable {
    case snareEighths, descendingToms, snareSixteenths, linear

    var number: Int {
        switch self { case .snareEighths: return 1; case .descendingToms: return 2; case .snareSixteenths: return 3; case .linear: return 4 }
    }
    var isolatedID: String { String(format: "30_fill_%02d_%@_aislado", number, stem) }
    var grooveID: String { String(format: "30_fill_%02d_%@_groove", number, stem) }
    private var stem: String {
        switch self { case .snareEighths: return "caja_corcheas"; case .descendingToms: return "bajada_toms"; case .snareSixteenths: return "caja_16"; case .linear: return "lineal" }
    }
    var title: String {
        switch self { case .snareEighths: return "Caja a corcheas"; case .descendingToms: return "Bajada de toms"; case .snareSixteenths: return "Caja en semicorcheas"; case .linear: return "Lineal: bombo, caja y toms" }
    }
    var explanation: String {
        switch self {
        case .snareEighths: return "Cuatro golpes de caja, espaciados y fáciles de colocar al final del compás."
        case .descendingToms: return "Desciende del tom agudo al grave: un cierre clásico que suena grande sin correr."
        case .snareSixteenths: return "Ocho golpes de caja más juntos. Mantén todos iguales antes de acelerar."
        case .linear: return "Cada golpe ocupa su sitio: alterna bombo, caja y toms sin que dos sonidos caigan a la vez."
        }
    }
}

private struct FillTrainingCard: View {
    @ObservedObject var model: Model
    let fill: FillType

    private var isolated: Exercise? { model.exercises.first { $0.id == fill.isolatedID } }
    private var groove: Exercise? { model.exercises.first { $0.id == fill.grooveID } }

    var body: some View {
        StagePanel {
            HStack(alignment: .firstTextBaseline) {
                Text("REDOBLE \(fill.number)").font(.studioLabel).foregroundColor(StudioDesign.accent)
                Text(fill.title).font(.title3.bold())
                Spacer()
                if let isolated { Text("\(isolated.bpm) BPM").font(.caption.bold()).foregroundColor(StudioDesign.textSecondary) }
            }
            Text(fill.explanation).font(.subheadline).foregroundColor(StudioDesign.textSecondary)
            HStack(alignment: .top, spacing: 12) {
                fillStep(number: "1", title: "Solo el redoble", detail: "Repite el gesto hasta poder colocarlo sin mirar.", exercise: isolated, action: "Practicar aislado")
                Image(systemName: "arrow.right").foregroundColor(StudioDesign.accent).frame(width: 18)
                fillStep(number: "2", title: "Dentro de un ritmo", detail: "Groove sencillo → redoble → groove con crash de resolución.", exercise: groove, action: "Practicar en contexto")
            }
        }
    }

    @ViewBuilder private func fillStep(number: String, title: String, detail: String, exercise: Exercise?, action: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(number).font(.caption.bold()).foregroundColor(StudioDesign.canvas).frame(width: 20, height: 20).background(StudioDesign.accent).clipShape(Circle())
                Text(title).font(.subheadline.bold())
                Spacer(minLength: 4)
                if let exercise, let award = model.highestTempoAward(for: exercise) {
                    TempoAwardBadge(award: award)
                }
            }
            if let exercise { ExercisePatternPreview(exercise: exercise, available: true) }
            Text(detail).font(.caption2).foregroundColor(StudioDesign.textSecondary).fixedSize(horizontal: false, vertical: true)
            ActionButton(action, prominence: .secondary) { if let exercise { model.openPreparation(exercise) } }
                .disabled(exercise == nil)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioDesign.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private enum CourseBlock: CaseIterable {
    case initiation, fundamentals, subdivision, coordination, grooves, hiphop, rock, funk, blues, jazz, extra
    var title: String { switch self { case .initiation: return "01 · INICIACIÓN"; case .fundamentals: return "02 · FUNDAMENTOS"; case .subdivision: return "03 · SUBDIVISIÓN"; case .coordination: return "04 · COORDINACIÓN"; case .grooves: return "05 · GROOVES"; case .hiphop: return "06 · HIP-HOP"; case .rock: return "07 · ROCK"; case .funk: return "08 · FUNK"; case .blues: return "09 · BLUES / SHUFFLE"; case .jazz: return "10 · JAZZ"; case .extra: return "EXTRAS" } }
    var subtitle: String { switch self { case .initiation: return "Construye el primer ritmo"; case .fundamentals: return "Base y charles"; case .subdivision: return "Pulso interno"; case .coordination: return "Independencia"; case .grooves: return "Variaciones musicales"; case .hiphop: return "Aplicación de estilo"; case .rock: return "Backbeat y fills"; case .funk: return "Síncopa y 16"; case .blues: return "Pulso ternario"; case .jazz: return "Ride y comping"; case .extra: return "Material complementario" } }
    var completeTitle: String { switch self {
    case .initiation: return "I-01 · Tu primer ritmo completo"
    case .fundamentals: return "F-01 · Respuestas de bombo"
    case .subdivision: return "S-01 · Groove entre los pulsos"
    case .coordination: return "C-01 · Independencia en el groove"
    case .grooves: return "G-01 · Groove con variaciones"
    case .hiphop: return "HH-01 · Hip-hop con fill final"
    case .rock: return "R-01 · Rock de resistencia"
    case .funk: return "FK-01 · Funk sincopado"
    case .blues: return "B-01 · Blues con cierre"
    case .jazz: return "J-01 · Jazz con comping"
    case .extra: return "Extra · Ritmo completo"
    } }
    func contains(_ exercise: Exercise) -> Bool {
        switch self {
        case .initiation: return exercise.id.hasPrefix("00_i_")
        case .fundamentals: return exercise.id.hasPrefix("01_fund_")
        case .subdivision: return exercise.id.hasPrefix("02_sub_")
        case .coordination: return exercise.id.hasPrefix("03_coord_")
        case .grooves: return exercise.id.hasPrefix("04_groove_")
        case .hiphop: return exercise.id.hasPrefix("10_hh_") || exercise.id.hasPrefix("hh_")
        case .rock: return exercise.id.hasPrefix("20_rock_")
        case .funk: return exercise.id.hasPrefix("21_funk_")
        case .blues: return exercise.id.hasPrefix("22_blues_")
        case .jazz: return exercise.id.hasPrefix("23_jazz_")
        case .extra: return !exercise.id.hasPrefix("00_i_") && !exercise.id.hasPrefix("01_fund_") && !exercise.id.hasPrefix("02_sub_") && !exercise.id.hasPrefix("03_coord_") && !exercise.id.hasPrefix("04_groove_") && !exercise.id.hasPrefix("10_hh_") && !exercise.id.hasPrefix("hh_") && !exercise.id.hasPrefix("20_rock_") && !exercise.id.hasPrefix("21_funk_") && !exercise.id.hasPrefix("22_blues_") && !exercise.id.hasPrefix("23_jazz_") && !exercise.id.hasPrefix("30_fill_")
        }
    }
}

private struct CompleteRhythmRow: View {
    @ObservedObject var model: Model
    let representative: Exercise
    let title: String
    var body: some View {
        let available = true
        Button { model.openCompleteRhythm(representative, title: title) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "music.note.list").font(.caption.bold()).frame(width: 25, height: 25).background(available ? Color.white.opacity(0.13) : Color.white.opacity(0.05)).clipShape(Circle())
                    Text(title).font(.subheadline.bold()).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                ExercisePatternPreview(exercise: representative, available: available)
                HStack { Text("Completo · 3 tempos · líneas por sonido").font(.caption2).foregroundColor(available ? StudioDesign.textSecondary : StudioDesign.textMuted); Spacer(); Image(systemName: available ? "chevron.right" : "lock.fill").font(.caption2).foregroundColor(available ? StudioDesign.accent : StudioDesign.textMuted) }
            }.padding(12).background(model.chosenID == representative.id ? Color.cyan.opacity(0.18) : StudioDesign.surfaceRaised.opacity(0.52)).overlay(RoundedRectangle(cornerRadius: 10).stroke(model.chosenID == representative.id ? StudioDesign.accent.opacity(0.8) : StudioDesign.surfaceHover, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

struct ExercisePatternPreview: View {
    let exercise: Exercise; let available: Bool
    private let sounds = ["kick", "snare", "hihat_closed", "hihat_open", "rim", "clap", "tom_low", "tom_high", "crash", "ride"]
    var body: some View {
        let active = sounds.filter { sound in exercise.notes.contains(where: { $0.sound == sound }) }
        VStack(alignment: .leading, spacing: 3) {
            ForEach(active, id: \.self) { sound in
                HStack(spacing: 2) {
                    Circle().fill(patternColor(sound).opacity(available ? 1 : 0.3)).frame(width: 5, height: 5)
                    ForEach(0..<exercise.grid, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 1.5).fill(exercise.notes.contains(where: { $0.sound == sound && $0.step % exercise.grid == step }) ? patternColor(sound).opacity(available ? 0.95 : 0.25) : Color.white.opacity(0.07)).frame(maxWidth: .infinity, minHeight: 5, maxHeight: 5)
                    }
                }
            }
        }.frame(height: max(12, CGFloat(active.count) * 8), alignment: .top)
    }
    private func patternColor(_ sound: String) -> Color {
        switch sound { case "kick": return .cyan; case "snare", "clap": return .pink; case "hihat_closed", "hihat_open": return .green; case "rim", "ride", "crash": return .orange; default: return .teal }
    }
}

private struct PlayerColumn: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(spacing: 14) {
            StagePanel {
                Text("CÓMO AVANZAR\n\nCompleta el ritmo entero al tempo de aprendizaje y alcanza el 70 %. Después podrás seguir con la siguiente lección. Tocar más rápido es opcional.")
                    .font(.caption)
                    .foregroundColor(StudioDesign.textPrimary)
            }
            StagePanel {
                Text("EN ESTE NIVEL").font(.caption.bold()).foregroundColor(.cyan)
                Text(model.lessonGoal).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach(model.lessonPattern, id: \.self) { item in
                        Text(item).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(0.10)).clipShape(Capsule())
                    }
                }
                Text("Por vuelta · aprende una idea nueva antes de sumar la siguiente.")
                    .font(.caption2).foregroundColor(.white.opacity(0.58))
            }
            StagePanel { Text("PATRÓN SELECCIONADO").font(.caption.bold()).foregroundColor(.cyan); if let exercise = model.chosen { ExercisePatternPreview(exercise: exercise, available: true) }; Text("La distribución física de los pads está disponible en «Pads y layout».").font(.caption).foregroundColor(StudioDesign.textSecondary) }
        }
    }
}

private struct SessionControlRail: View {
    let open: () -> Void
    var body: some View {
        StagePanel {
            Button(action: open) {
                Image(systemName: "slider.horizontal.3").font(.title3).frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.plain).foregroundColor(StudioDesign.accent).help("Mostrar controles de sesión")
        }
    }
}

private struct SessionColumn: View {
    @ObservedObject var model: Model
    let close: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            StagePanel {
                VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                HStack { Text("SESIÓN").font(.caption.bold()).foregroundColor(.cyan); Spacer(); Button(action: close) { Image(systemName: "sidebar.right") }.buttonStyle(.plain).foregroundColor(StudioDesign.textSecondary).help("Ocultar controles") }
                Text("\(model.selectedBPM) BPM").font(.title.bold()).padding(.top, 4)
                Stepper("Tempo", value: $model.selectedBPM, in: 40...240, step: 5).onChange(of: model.selectedBPM) { _ in model.savePreferences() }
                Divider().overlay(Color.white.opacity(0.16)).padding(.vertical, 5)
                Text("\(model.selectedRepeats) vueltas").font(.headline)
                repeatStepper(model: model)
                Picker("Enfoque", selection: $model.practiceFragment) {
                    Text("Compás completo").tag(0)
                    Text("1ª mitad").tag(1)
                    Text("2ª mitad").tag(2)
                }.pickerStyle(.segmented)
                ActionButton("Escuchar y colocar") { model.previewExercise() }.padding(.top, 7)
                ActionButton("Calibración guiada", prominence: model.hasCalibrationForCurrentProfile ? .secondary : .primary) { model.startCalibration() }
                Text("Ajusta el tiempo de respuesta de este controlador y salida de audio.")
                    .font(.caption2).foregroundColor(.white.opacity(0.58))
                }
                VStack(alignment: .leading, spacing: 7) {
                    Divider().overlay(Color.white.opacity(0.16)).padding(.vertical, 2)
                    Text("ACOMPAÑAMIENTO").font(.caption.bold()).foregroundColor(.cyan)
                    Text(model.loopStatus).font(.caption2).foregroundColor(.white.opacity(0.65)).lineLimit(2)
                    if let sourceTempo = model.loopTempo {
                        Text("Se ajusta de \(Int(sourceTempo.rounded())) a \(model.selectedBPM) BPM al empezar.").font(.caption2).foregroundColor(.white.opacity(0.65))
                    }
                    ActionButton(model.loopEnabled ? "Loop activado" : "Loop desactivado", prominence: model.loopEnabled ? .primary : .secondary) { model.toggleLoop() }
                }
                }
            }
            StagePanel {
                Text("ÚLTIMO INTENTO").font(.caption.bold()).foregroundColor(.cyan)
                if let percentage = model.lastScorePercentage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(percentage.rounded())) %").font(.title.bold()).foregroundColor(percentage >= 70 ? .green : percentage >= 50 ? .yellow : .red)
                            Text(String(repeating: "★", count: model.lastScoreStars) + String(repeating: "☆", count: 3 - model.lastScoreStars)).font(.headline).foregroundColor(.yellow)
                        }
                        Text(String(format: "Puntuación: %.1f / %d", model.lastPoints, model.lastPossiblePoints)).font(.headline)
                        HStack(spacing: 8) {
                            ScoreStat("Golpes", value: model.lastTotalHits, color: .white)
                            ScoreStat("Bien", value: model.lastWellTimed, color: .green)
                            ScoreStat("Regular", value: model.lastRegular, color: .yellow)
                            ScoreStat("Mal", value: model.lastWrong, color: .red)
                        }
                        HStack(spacing: 8) {
                            ActionButton("↻ Repetir", prominence: .secondary) { model.repeatPractice() }
                            if model.nextExerciseTitle != nil {
                                ActionButton("Siguiente", prominence: .primary) { model.moveToSuggestedExercise() }
                            }
                        }
                        if let next = model.nextExerciseTitle { Text("Has conseguido estrellas. Siguiente: \(next)").font(.caption2).foregroundColor(.green) }
                    }.padding(.top, 3)
                }
                Text(model.result.isEmpty ? "Sin intentos todavía" : model.result).font(.caption).padding(.top, 2)
                Text(model.advice).font(.caption2).foregroundColor(.white.opacity(0.58)).padding(.top, 4)
                Text(model.insights).font(.caption2).foregroundColor(.white.opacity(0.58))
                Text(model.weakestSoundFeedback).font(.caption2).foregroundColor(.yellow)
                Text(model.nextPracticeRecommendation).font(.caption2).foregroundColor(.cyan)
            }
        }
    }
}

private func repeatStepper(model: Model) -> some View {
    Stepper("Duración", value: Binding(
        get: { Model.repeatOptions.firstIndex(of: model.selectedRepeats) ?? 0 },
        set: { model.setRepeats(Model.repeatOptions[$0]) }
    ), in: 0...(Model.repeatOptions.count - 1))
}

private struct ScoreStat: View {
    let title: String
    let value: Int
    let color: Color
    init(_ title: String, value: Int, color: Color) { self.title = title; self.value = value; self.color = color }
    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)").font(.headline).foregroundColor(color)
            Text(title).font(.caption2).foregroundColor(.white.opacity(0.62))
        }.frame(maxWidth: .infinity)
    }
}

private struct PracticeFooter: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack {
            Text(model.recovery).font(.caption).foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(model.calibrationMessage).font(.caption).foregroundColor(.white.opacity(0.55))
        }.padding(.horizontal, 24).padding(.bottom, 12)
    }
}

private struct PulseDriftChart: View {
    let report: PulseDriftReport

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DERIVA DURANTE EL SILENCIO").font(.studioLabel).foregroundColor(StudioDesign.textMuted)
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
                    .stroke(StudioDesign.textMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
                        .stroke(StudioDesign.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        let x = width * CGFloat(index) / CGFloat(max(1, points.count - 1))
                        let normalized = CGFloat(point.medianOffsetMilliseconds / extent)
                        let y = height / 2 - normalized * (height * 0.42)
                        Circle().fill(point.metronomeAudible ? StudioDesign.accent : StudioDesign.regular)
                            .frame(width: 6, height: 6).position(x: x, y: y)
                    }
                }
            }
            .frame(height: 72)
            Text("Arriba = retraso · abajo = adelanto · amarillo = silencio del metrónomo")
                .font(.caption2).foregroundColor(StudioDesign.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gráfica de desfase por pulso. El centro representa cero milisegundos; arriba es retraso, abajo adelanto y los puntos amarillos corresponden al silencio del metrónomo.")
    }
}
