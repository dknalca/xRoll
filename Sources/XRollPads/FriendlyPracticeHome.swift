import AppKit
import SwiftUI
import XRollCore

struct StagePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
        prominence == .primary ? Color(red: 0.02, green: 0.07, blue: 0.11) : .white
    }

    private var backgroundColor: Color {
        switch prominence {
        case .primary: return Color(red: 0.10, green: 0.76, blue: 0.95)
        case .secondary: return Color.white.opacity(0.13)
        case .quiet: return Color.clear
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .primary: return Color.white.opacity(0.22)
        case .secondary: return Color.white.opacity(0.25)
        case .quiet: return Color.white.opacity(0.18)
        }
    }
}

struct PracticeHome: View {
    @ObservedObject var model: Model

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.05, blue: 0.10), Color(red: 0.08, green: 0.035, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ScrollView {
                VStack(spacing: 16) {
                    PracticeHeader(model: model)
                    HStack(alignment: .top, spacing: 14) {
                        CoursePanel(model: model).frame(width: 225)
                        PlayerColumn(model: model).frame(maxWidth: .infinity)
                        SessionColumn(model: model).frame(width: 245)
                    }.padding(.horizontal, 20)
                    PracticeFooter(model: model)
                }
                .padding(.bottom, 12)
            }.foregroundColor(.white)
        }
    }
}

struct ResultsHome: View {
    @ObservedObject var model: Model

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.05, blue: 0.10), Color(red: 0.08, green: 0.035, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 20) {
                AppMark(size: 62)
                Text("Ejercicio terminado").font(.largeTitle.bold()).foregroundColor(.white)
                Text(model.chosen?.title ?? "Práctica").font(.title3).foregroundColor(.white.opacity(0.72))
                StagePanel {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("\(Int((model.lastScorePercentage ?? 0).rounded())) %").font(.system(size: 52, weight: .bold)).foregroundColor((model.lastScorePercentage ?? 0) >= 75 ? .green : (model.lastScorePercentage ?? 0) >= 50 ? .yellow : .red)
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
                }.frame(maxWidth: 560)
                if let next = model.nextExerciseTitle {
                    Text("Has conseguido estrellas. Puedes pasar a: \(next)").font(.headline).foregroundColor(.green)
                }
                HStack(spacing: 12) {
                    ActionButton("↻ Repetir", prominence: .secondary) { model.repeatPractice() }
                    if model.nextExerciseTitle != nil { ActionButton("Siguiente ejercicio", prominence: .primary) { model.moveToSuggestedExercise() } }
                    ActionButton("Volver", prominence: .quiet) { model.dismissResults() }
                }
            }.foregroundColor(.white).padding(32).frame(maxWidth: 700)
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
                Text("FINGER DRUMMING").font(.caption.bold()).foregroundColor(.cyan)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(model.status.contains("MIDI") ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(model.status).font(.caption.bold()).foregroundColor(.white.opacity(0.76))
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
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.exercises, id: \.id) { CourseRow(model: model, exercise: $0) }
                }
            }
        }
    }
}

private struct CourseRow: View {
    @ObservedObject var model: Model
    let exercise: Exercise
    var body: some View {
        let available = model.isAvailable(exercise)
        Button { model.chooseExercise(exercise) } label: {
            HStack(spacing: 9) {
                Text(model.levelStatus(exercise).isEmpty ? "\(exercise.level)" : model.levelStatus(exercise))
                    .font(.caption.bold()).frame(width: 25, height: 25)
                    .background(available ? Color.white.opacity(0.13) : Color.white.opacity(0.05)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.title.replacingOccurrences(of: "Boom bap ", with: "")).font(.caption.bold()).lineLimit(1)
                    Text(available ? "\(exercise.bpm) BPM" : "BLOQUEADO").font(.caption2).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }.padding(8).background(model.chosenID == exercise.id ? Color.cyan.opacity(0.18) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).disabled(!available)
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
                    ActionButton("▶  Empezar", prominence: .primary) { model.startPractice() }
                }
            }
            StagePanel {
                HStack { Text("TU CONTROLADOR").font(.caption.bold()).foregroundColor(.cyan); Spacer(); Text("4 × 4").font(.caption).foregroundColor(.white.opacity(0.5)) }
                Grid(model: model).padding(.top, 12)
                Text("Bombo, caja y palmada abajo. Charles y crash encima.").font(.caption).foregroundColor(.white.opacity(0.55)).padding(.top, 8)
            }
        }
    }
}

private struct SessionColumn: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(spacing: 14) {
            StagePanel {
                Text("SESIÓN").font(.caption.bold()).foregroundColor(.cyan)
                Text("\(model.selectedBPM) BPM").font(.title.bold()).padding(.top, 4)
                Stepper("Tempo", value: $model.selectedBPM, in: 40...240, step: 5).onChange(of: model.selectedBPM) { _ in model.savePreferences() }
                Divider().overlay(Color.white.opacity(0.16)).padding(.vertical, 5)
                Text("\(model.selectedRepeats) vueltas").font(.headline)
                Stepper("Duración", value: $model.selectedRepeats, in: 1...16).onChange(of: model.selectedRepeats) { _ in model.savePreferences() }
                ActionButton("Escuchar y colocar") { model.previewExercise() }.padding(.top, 7)
                ActionButton("Calibrar", prominence: .quiet) { model.startCalibration() }
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
            StagePanel {
                Text("ÚLTIMO INTENTO").font(.caption.bold()).foregroundColor(.cyan)
                if let percentage = model.lastScorePercentage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(percentage.rounded())) %").font(.title.bold()).foregroundColor(percentage >= 75 ? .green : percentage >= 50 ? .yellow : .red)
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
            }
        }
    }
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
