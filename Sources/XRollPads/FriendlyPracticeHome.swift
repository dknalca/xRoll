import SwiftUI
import XRollCore

struct StagePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.075))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PracticeHome: View {
    @ObservedObject var model: Model

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.05, blue: 0.10), Color(red: 0.08, green: 0.035, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 14) {
                PracticeHeader(model: model)
                HStack(alignment: .top, spacing: 14) {
                    CoursePanel(model: model).frame(width: 225)
                    PlayerColumn(model: model).frame(maxWidth: .infinity)
                    SessionColumn(model: model).frame(width: 245)
                }
                PracticeFooter(model: model)
            }.foregroundColor(.white)
        }
    }
}

private struct PracticeHeader: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Text("xRoll").font(.largeTitle.bold())
                Text("FINGER DRUMMING").font(.caption.bold()).foregroundColor(.cyan)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(model.status.contains("MIDI") ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(model.status).font(.caption.bold()).foregroundColor(.white.opacity(0.76))
            }
        }.padding(.horizontal, 24).padding(.top, 16)
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
                    Button("▶  Empezar") { model.startPractice() }.buttonStyle(.borderedProminent).tint(.cyan).controlSize(.large)
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
                Button("Escuchar y colocar") { model.previewExercise() }.padding(.top, 7)
                Button("Calibrar") { model.startCalibration() }.buttonStyle(.borderless).foregroundColor(.white.opacity(0.74))
            }
            StagePanel {
                Text("ÚLTIMO INTENTO").font(.caption.bold()).foregroundColor(.cyan)
                Text(model.result.isEmpty ? "Sin intentos todavía" : model.result).font(.caption).padding(.top, 5)
                Text(model.advice).font(.caption2).foregroundColor(.white.opacity(0.58)).padding(.top, 4)
                ProgressChart(scores: model.scoreHistory).padding(.top, 6)
            }
        }
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
