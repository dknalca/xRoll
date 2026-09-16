import SwiftUI
import XRollCore

struct MetroChapter: Identifiable {
    let id: String
    let exercises: [Exercise]

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
        default: return id.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    var subtitle: String {
        switch id {
        case "initiation": return "Tu primer groove"
        case "fundamentals": return "Pulso y backbeat"
        case "subdivision": return "Leer entre pulsos"
        case "coordination": return "Independencia"
        case "groove": return "Frases y cierres"
        case "hiphop", "rock", "disco", "funk", "reggae", "dembow", "blues", "jazz", "clave-bossa": return "Aplicación de estilo"
        default: return "Ruta de práctica"
        }
    }
}

struct RhythmMetroView: View {
    @ObservedObject var model: Model

    private func state(for exercise: Exercise) -> CourseLevelStatus {
        model.courseLevels.first(where: { $0.exerciseID == exercise.id })?.status ?? .locked
    }

    private var fastStart: Exercise? {
        model.metroChapters.flatMap(\.exercises).first { $0.metadata?.flags.contains("fast-start") == true }
    }

    private var nextExercise: Exercise? {
        model.metroChapters.flatMap(\.exercises).first { state(for: $0) == .available }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("METRO DEL RITMO").font(.studioLabel).foregroundColor(StudioDesign.accent)
                        Text("Una estación cada vez").font(.largeTitle.bold())
                        Text("Aprende una habilidad, compruébala en el groove completo y abre la siguiente estación.")
                            .font(.subheadline).foregroundColor(StudioDesign.textSecondary)
                    }
                    Spacer()
                    Button("Calentar") { model.chooseWarmup() }
                        .buttonStyle(.bordered).tint(StudioDesign.accent)
                }

                if let nextExercise { MetroNextStation(model: model, exercise: nextExercise, state: state(for: nextExercise)) }
                if let fastStart, state(for: fastStart) != .mastered { MetroFastStart(model: model, exercise: fastStart) }

                MetroTrainLegend(chapterCount: model.metroChapters.count)

                VStack(spacing: 0) {
                    ForEach(Array(model.metroChapters.enumerated()), id: \.element.id) { index, chapter in
                        MetroChapterStation(
                            model: model,
                            chapter: chapter,
                            state: state,
                            index: index,
                            totalCount: model.metroChapters.count,
                            isCurrent: chapter.id == nextExercise?.metadata?.chapter
                        )
                        if index < model.metroChapters.count - 1 {
                            Rectangle().fill(StudioDesign.surfaceHover).frame(width: 2, height: 18)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 23)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .background(StudioDesign.canvas)
        .foregroundColor(StudioDesign.textPrimary)
    }
}

private struct MetroTrainLegend: View {
    let chapterCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tram.fill").foregroundColor(StudioDesign.accent)
            ForEach(0..<min(chapterCount, 10), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2).fill(StudioDesign.surfaceHover).frame(width: 13, height: 10)
            }
            Image(systemName: "minus").foregroundColor(StudioDesign.textMuted)
        }
        .font(.caption)
        .accessibilityHidden(true)
    }
}

private struct MetroNextStation: View {
    @ObservedObject var model: Model
    let exercise: Exercise
    let state: CourseLevelStatus

    var body: some View {
        StagePanel {
            Text("PRÓXIMA ESTACIÓN").font(.studioLabel).foregroundColor(StudioDesign.accent)
            Text(exercise.title).font(.title2.bold())
            Text(exercise.metadata?.objective ?? "Practica el siguiente escalón del curso.")
                .font(.subheadline).foregroundColor(StudioDesign.textSecondary).lineLimit(2)
            ExercisePatternPreview(exercise: exercise, available: state != .locked)
            HStack {
                Text("Nueva dificultad: \(exercise.metadata?.newDifficulty?.replacingOccurrences(of: "-", with: " ") ?? "ritmo")")
                    .font(.caption).foregroundColor(StudioDesign.textSecondary)
                Spacer()
                ActionButton("Preparar", prominence: .primary) { model.openPreparation(exercise) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(StudioDesign.accent.opacity(0.65), lineWidth: 1))
    }
}

private struct MetroFastStart: View {
    @ObservedObject var model: Model
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "forward.fill").foregroundColor(StudioDesign.regular)
            VStack(alignment: .leading, spacing: 3) {
                Text("¿Ya tienes base?").font(.subheadline.bold())
                Text("Prueba \(exercise.title). Si lo completas, abrirás Fundamentos sin acreditar los escalones omitidos.")
                    .font(.caption).foregroundColor(StudioDesign.textSecondary)
            }
            Spacer()
            ActionButton("Probar", prominence: .secondary) { model.openPreparation(exercise) }
        }
        .padding(12).background(StudioDesign.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MetroChapterStation: View {
    @ObservedObject var model: Model
    let chapter: MetroChapter
    let state: (Exercise) -> CourseLevelStatus
    let index: Int
    let totalCount: Int
    let isCurrent: Bool

    var body: some View {
        let completed = chapter.exercises.filter { state($0) == .mastered }.count
        let chapterLocked = chapter.exercises.allSatisfy { state($0) == .locked }
        HStack(alignment: .top, spacing: 12) {
            MetroTrainMarker(
                isCurrent: isCurrent,
                isCompleted: completed == chapter.exercises.count,
                isLocked: chapterLocked,
                isLast: index == totalCount - 1
            )
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.title.uppercased()).font(.studioLabel).foregroundColor(chapterLocked ? StudioDesign.textMuted : StudioDesign.accent)
                        Text(chapter.subtitle).font(.caption).foregroundColor(StudioDesign.textSecondary)
                    }
                    Spacer()
                    Text("\(completed)/\(chapter.exercises.count)").font(.caption.bold()).foregroundColor(StudioDesign.textSecondary)
                }
                ProgressView(value: Double(completed), total: Double(max(1, chapter.exercises.count))).tint(StudioDesign.accent)
                Text(chapterLocked ? "Completa la estación anterior para abrir esta ruta." : "Elige cualquier ritmo desbloqueado para repasarlo o seguir avanzando.")
                    .font(.caption).foregroundColor(chapterLocked ? StudioDesign.textMuted : StudioDesign.textPrimary)
                ForEach(chapter.exercises, id: \.id) { exercise in
                    let exerciseState = state(exercise)
                    Button { model.openPreparation(exercise) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: exerciseState == .mastered ? "checkmark.circle.fill" : "music.note")
                                .foregroundColor(exerciseState == .mastered ? StudioDesign.accent : StudioDesign.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.title).font(.subheadline.bold()).lineLimit(1)
                                Text(exerciseState == .mastered ? "Completado · puedes repasarlo" : "Disponible ahora")
                                    .font(.caption2).foregroundColor(StudioDesign.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundColor(StudioDesign.textMuted)
                        }
                        .padding(9)
                        .background(StudioDesign.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(exerciseState == .locked)
                    .opacity(exerciseState == .locked ? 0.42 : 1)
                }
            }
        }
        .padding(13)
        .background(StudioDesign.surface.opacity(chapterLocked ? 0.55 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MetroTrainMarker: View {
    let isCurrent: Bool
    let isCompleted: Bool
    let isLocked: Bool
    let isLast: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: isCurrent ? 9 : 5)
                    .fill(carColor.opacity(isLocked ? 0.45 : 1))
                    .frame(width: 48, height: 36)
                Image(systemName: symbol)
                    .font(.subheadline.bold())
                    .foregroundColor(isLocked ? StudioDesign.textMuted : StudioDesign.canvas)
            }
            HStack(spacing: 8) {
                Circle().fill(wheelColor).frame(width: 6, height: 6)
                Circle().fill(wheelColor).frame(width: 6, height: 6)
            }
            if isLast {
                Capsule().fill(StudioDesign.textMuted).frame(width: 20, height: 3).padding(.top, 2)
            }
        }
        .frame(width: 48)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        if isCurrent { return "tram.fill" }
        if isCompleted { return "checkmark" }
        return isLocked ? "lock.fill" : "music.note"
    }

    private var carColor: Color {
        if isCurrent { return StudioDesign.accent }
        if isCompleted { return StudioDesign.rightHand }
        return StudioDesign.surfaceHover
    }

    private var wheelColor: Color {
        isLocked ? StudioDesign.textMuted : StudioDesign.textSecondary
    }
}
