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

struct AppMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23))
    }
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

    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            VStack(spacing: 20) {
                AppMark(size: 62)
                Text("Ejercicio terminado").font(.largeTitle.bold()).foregroundColor(.white)
                Text(model.chosen?.title ?? "Práctica").font(.title3).foregroundColor(.white.opacity(0.72))
                StagePanel {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("\(Int((model.lastScorePercentage ?? 0).rounded())) %").font(.studioMetric).foregroundColor((model.lastScorePercentage ?? 0) >= 70 ? StudioDesign.accent : (model.lastScorePercentage ?? 0) >= 50 ? StudioDesign.regular : StudioDesign.miss)
                        Text(String(repeating: "★", count: model.lastScoreStars) + String(repeating: "☆", count: 3 - model.lastScoreStars)).font(.title).foregroundColor(.yellow)
                    }
                    Text(String(format: "Puntuación: %.1f / %d", model.lastPoints, model.lastPossiblePoints)).font(.title3.bold())
                    HStack(spacing: 18) {
                        ScoreStat("Golpes", value: model.lastTotalHits, color: .white)
                        ScoreStat("Bien", value: model.lastWellTimed, color: .green)
                        ScoreStat("Regular", value: model.lastRegular, color: .yellow)
                        ScoreStat("Mal", value: model.lastWrong, color: .red)
                    }.padding(.vertical, 5)
                    Text(model.advice).font(.subheadline).foregroundColor(.white.opacity(0.72))
                    Text(model.weakestSoundFeedback).font(.subheadline).foregroundColor(.yellow)
                    Text(model.nextPracticeRecommendation).font(.subheadline).foregroundColor(.cyan)
                    if !model.ghostCoachMessage.isEmpty { Text(model.ghostCoachMessage).font(.caption).foregroundColor(StudioDesign.textSecondary) }
                }.frame(maxWidth: 560)
                StagePanel {
                    Text("DIAGNÓSTICO").font(.studioLabel).foregroundColor(StudioDesign.accent)
                    HStack { diagnosticMetric("Precisión", "\(Int((model.lastScorePercentage ?? 0).rounded())) %"); diagnosticMetric("Tendencia", model.insights.isEmpty ? "Sin datos" : model.insights); diagnosticMetric("Prioridad", model.weakestSoundFeedback) }
                    if !model.autopilotMessage.isEmpty { Text("Autopilot: \(model.autopilotMessage)").font(.caption).foregroundColor(StudioDesign.textSecondary); ActionButton("Aplicar recomendación", prominence: .secondary) { model.applyAutopilot() } }
                }.frame(maxWidth: 700)
                if let next = model.nextExerciseTitle {
                    Text("Has conseguido estrellas. Puedes pasar a: \(next)").font(.headline).foregroundColor(.green)
                }
                HStack(spacing: 12) {
                    ActionButton("↻ Repetir", prominence: .secondary) { model.repeatPractice() }
                    if !model.soundStatistics.isEmpty { ActionButton("Corregir sonido", prominence: .secondary) { model.startCorrectivePractice() } }
                    if model.nextExerciseTitle != nil { ActionButton("Siguiente ejercicio", prominence: .primary) { model.moveToSuggestedExercise() } }
                    ActionButton("Volver", prominence: .quiet) { model.dismissResults() }
                }
            }.foregroundColor(.white).padding(32).frame(maxWidth: 700)
        }
    }
}

private func diagnosticMetric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) { Text(title).font(.studioLabel).foregroundColor(StudioDesign.textMuted); Text(value).font(.caption).foregroundColor(StudioDesign.textPrimary).lineLimit(3) }.frame(maxWidth: .infinity, alignment: .leading)
}

struct PreparationHome: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("PREPARACIÓN").font(.studioLabel).foregroundColor(StudioDesign.accent)
                Text(model.chosen?.title ?? "Ejercicio").font(.system(size: 30, weight: .bold))
                StagePanel {
                    Text("Objetivo").font(.headline)
                    Text(model.lessonGoal).font(.studioBody).foregroundColor(StudioDesign.textSecondary)
                    HStack { StudioStatusPill(title: "\(model.selectedBPM) BPM"); StudioStatusPill(title: "\(model.selectedRepeats) vueltas"); StudioStatusPill(title: model.status, active: model.status.contains("MIDI")) }
                }
                StagePanel {
                    Text("Antes de puntuar").font(.headline)
                    Text("Escucha una vuelta y comprueba la colocación de las manos. Puedes ajustar tempo, duración y ayudas desde esta sesión.").font(.studioBody).foregroundColor(StudioDesign.textSecondary)
                    Picker("Ayudas", selection: $model.practiceHelp) { ForEach(PracticeHelp.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    Text(model.practiceHelpDescription).font(.caption).foregroundColor(StudioDesign.textSecondary)
                    Picker("Capa", selection: $model.practiceLayer) { ForEach(model.practiceLayerOptions, id: \.self) { sound in Text(sound == "all" ? "Patrón completo" : model.displayName(sound)).tag(sound) } }.pickerStyle(.menu)
                    Toggle("Prueba de transferencia", isOn: $model.transferCheck)
                    if model.transferCheck { Text("El charles se oye, pero no aparece ni se puntúa: mantén el groove sin perseguirlo visualmente.").font(.caption).foregroundColor(StudioDesign.textSecondary) }
                    HStack { ActionButton("Escuchar y colocar", prominence: .secondary) { model.dismissPreparation(); model.previewExercise() }; ActionButton("Empezar práctica", prominence: .primary) { model.startFromPreparation() } }
                }
                HStack { ActionButton("Volver", prominence: .quiet) { model.dismissPreparation() }; Spacer() }
            }.foregroundColor(StudioDesign.textPrimary).padding(36).frame(maxWidth: 720, alignment: .leading)
        }
    }
}

struct OnboardingHome: View {
    @ObservedObject var model: Model
    let showPads: () -> Void
    let showAudio: () -> Void
    var body: some View {
        ZStack { StudioDesign.canvas.ignoresSafeArea(); VStack(alignment: .leading, spacing: 18) {
            Text("I-00 · CONOCE TU INSTRUMENTO").font(.studioLabel).foregroundColor(StudioDesign.accent)
            Text("Prepara tu espacio para tocar").font(.system(size: 32, weight: .bold))
            Text("Comprueba controlador, sonido y colocación antes del primer ejercicio puntuado.").font(.studioBody).foregroundColor(StudioDesign.textSecondary)
            HStack(spacing: 14) {
                StagePanel { Text("1 · Controlador").font(.headline); StudioStatusPill(title: model.sources.isEmpty ? "Sin MIDI" : "MIDI detectado", active: !model.sources.isEmpty); ActionButton("Mapear pads") { showPads() } }
                StagePanel { Text("2 · Audio").font(.headline); StudioStatusPill(title: model.audioOutputs.isEmpty ? "Sin salida" : "Salida lista", active: !model.audioOutputs.isEmpty); ActionButton("Revisar audio") { showAudio() } }
                StagePanel { Text("3 · Pulso").font(.headline); Text(model.calibrationMessage).font(.caption).foregroundColor(StudioDesign.textSecondary); ActionButton("Calibración guiada", prominence: .primary) { model.startCalibration() } }
            }
            StagePanel { Text("Localizador 4×4").font(.headline); Text("Toca cualquier pad: se iluminará en la rejilla de curso. Identifica Bombo, Aro, Caja y Charles antes de continuar.").font(.studioBody).foregroundColor(StudioDesign.textSecondary) }
            Spacer()
        }.foregroundColor(StudioDesign.textPrimary).padding(36).frame(maxWidth: 900, alignment: .leading) }
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
        StagePanel {
            HStack {
                Text("CURSO").font(.caption.bold()).foregroundColor(.cyan)
                Spacer()
                Button("Calentar") { model.chooseWarmup() }.buttonStyle(.borderless).foregroundColor(.white)
            }
            Text("Ruta ordenada por bloques. Cada tarjeta muestra de un vistazo qué sonidos entran y cómo respira el compás.").font(.caption).foregroundColor(StudioDesign.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(CourseBlock.allCases, id: \.self) { block in
                        let exercises = model.exercises.filter { block.contains($0) }
                        if !exercises.isEmpty {
                            let mastered = exercises.filter { model.levelStatus($0) == "✓" }.count
                            HStack { Text(block.title).font(.studioLabel).foregroundColor(StudioDesign.accent); Text(block.subtitle).font(.caption2).foregroundColor(StudioDesign.textMuted); Spacer(); Text("\(mastered)/\(exercises.count)").font(.caption.bold()).foregroundColor(mastered == exercises.count ? StudioDesign.accent : StudioDesign.textSecondary) }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                                ForEach(exercises, id: \.id) { CourseRow(model: model, exercise: $0) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private enum CourseBlock: CaseIterable {
    case initiation, fundamentals, subdivision, coordination, grooves, hiphop, rock, funk, blues, jazz, extra
    var title: String { switch self { case .initiation: return "01 · INICIACIÓN"; case .fundamentals: return "02 · FUNDAMENTOS"; case .subdivision: return "03 · SUBDIVISIÓN"; case .coordination: return "04 · COORDINACIÓN"; case .grooves: return "05 · GROOVES"; case .hiphop: return "06 · HIP-HOP"; case .rock: return "07 · ROCK"; case .funk: return "08 · FUNK"; case .blues: return "09 · BLUES / SHUFFLE"; case .jazz: return "10 · JAZZ"; case .extra: return "EXTRAS" } }
    var subtitle: String { switch self { case .initiation: return "Construye el primer ritmo"; case .fundamentals: return "Base y charles"; case .subdivision: return "Pulso interno"; case .coordination: return "Independencia"; case .grooves: return "Variaciones musicales"; case .hiphop: return "Aplicación de estilo"; case .rock: return "Backbeat y fills"; case .funk: return "Síncopa y 16"; case .blues: return "Pulso ternario"; case .jazz: return "Ride y comping"; case .extra: return "Material complementario" } }
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
        case .extra: return !exercise.id.hasPrefix("00_i_") && !exercise.id.hasPrefix("01_fund_") && !exercise.id.hasPrefix("02_sub_") && !exercise.id.hasPrefix("03_coord_") && !exercise.id.hasPrefix("04_groove_") && !exercise.id.hasPrefix("10_hh_") && !exercise.id.hasPrefix("hh_") && !exercise.id.hasPrefix("20_rock_") && !exercise.id.hasPrefix("21_funk_") && !exercise.id.hasPrefix("22_blues_") && !exercise.id.hasPrefix("23_jazz_")
        }
    }
}

private struct CourseRow: View {
    @ObservedObject var model: Model
    let exercise: Exercise
    var body: some View {
        let available = model.isAvailable(exercise)
        Button { model.openPreparation(exercise) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(model.levelStatus(exercise).isEmpty ? "\(exercise.level)" : model.levelStatus(exercise)).font(.caption.bold()).frame(width: 25, height: 25).background(available ? Color.white.opacity(0.13) : Color.white.opacity(0.05)).clipShape(Circle())
                    Text(exercise.title.replacingOccurrences(of: "Boom bap ", with: "")).font(.caption.bold()).lineLimit(1)
                    Spacer()
                }
                ExercisePatternPreview(exercise: exercise, available: available)
                HStack { Text(available ? "\(exercise.bpm) BPM · \(exercise.repeats) vueltas" : "BLOQUEADO").font(.caption2).foregroundColor(available ? StudioDesign.textSecondary : StudioDesign.textMuted); Spacer(); Image(systemName: available ? "play.fill" : "lock.fill").font(.caption2).foregroundColor(available ? StudioDesign.accent : StudioDesign.textMuted) }
            }.padding(10).background(model.chosenID == exercise.id ? Color.cyan.opacity(0.18) : StudioDesign.surfaceRaised.opacity(0.52)).overlay(RoundedRectangle(cornerRadius: 10).stroke(model.chosenID == exercise.id ? StudioDesign.accent.opacity(0.8) : StudioDesign.surfaceHover, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!available)
    }
}

private struct ExercisePatternPreview: View {
    let exercise: Exercise; let available: Bool
    private let sounds = ["kick", "snare", "hihat_closed", "hihat_open", "rim", "clap", "tom_low", "tom_high", "crash", "ride"]
    var body: some View {
        let active = sounds.filter { sound in exercise.notes.contains(where: { $0.sound == sound }) }
        VStack(alignment: .leading, spacing: 3) {
            ForEach(active.prefix(3), id: \.self) { sound in
                HStack(spacing: 2) {
                    Circle().fill(patternColor(sound).opacity(available ? 1 : 0.3)).frame(width: 5, height: 5)
                    ForEach(0..<16, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 1.5).fill(exercise.notes.contains(where: { $0.sound == sound && $0.step % 16 == step }) ? patternColor(sound).opacity(available ? 0.95 : 0.25) : Color.white.opacity(0.07)).frame(maxWidth: .infinity, minHeight: 5, maxHeight: 5)
                    }
                }
            }
        }.frame(height: max(12, CGFloat(min(active.count, 3)) * 8), alignment: .top)
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
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LISTO PARA TOCAR").font(.caption.bold()).foregroundColor(.cyan)
                        Text(model.chosen?.title ?? "Elige un nivel").font(.title2.bold())
                        Text(model.preview.isEmpty ? "Escucha el patrón o empieza cuando quieras." : model.preview).font(.caption).foregroundColor(.white.opacity(0.58))
                    }
                    Spacer()
                    ActionButton("Comenzar", prominence: .primary) { model.openPreparation() }
                }
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
                ActionButton("Calibración guiada", prominence: .secondary) { model.startCalibration() }
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
