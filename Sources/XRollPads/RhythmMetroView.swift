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

    private var recommendation: CourseRecommendation? {
        model.courseRecommendation
    }

    private var nextExercise: Exercise? {
        guard let recommendation else { return nil }
        return model.metroChapters.flatMap(\.exercises).first { $0.id == recommendation.exerciseID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("METRO DEL RITMO").font(.studioLabel).foregroundColor(StudioDesign.accent)
                        Text("Una estación cada vez").font(.largeTitle.bold())
                        Text("Sigue la ruta recomendada o explora cualquier ejercicio. Para avanzar, supera el ritmo completo a su tempo de referencia.")
                            .font(.subheadline).foregroundColor(StudioDesign.textSecondary)
                    }
                    Spacer()
                    Button("Calentar") { model.chooseWarmup() }
                        .buttonStyle(.bordered).tint(StudioDesign.accent)
                }

                if let recommendation, let nextExercise {
                    MetroNextStation(model: model, exercise: nextExercise, recommendation: recommendation)
                }
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
                            isCurrent: chapter.exercises.contains { $0.id == recommendation?.exerciseID }
                        )
                        if index < model.metroChapters.count - 1 {
                            MetroRouteSegment(isCompleted: chapter.exercises.allSatisfy { state(for: $0) == .mastered })
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

private struct MetroRouteSegment: View {
    let isCompleted: Bool

    var body: some View {
        if isCompleted {
            Rectangle().fill(StudioDesign.accent.opacity(0.8)).frame(width: 3, height: 20)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 23)
        } else {
            Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .foregroundColor(StudioDesign.textMuted).frame(width: 2, height: 20)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 23)
        }
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
    let recommendation: CourseRecommendation

    var body: some View {
        StagePanel {
            Text("TE TOCA AHORA · NIVEL \(recommendation.courseLevel)").font(.studioLabel).foregroundColor(StudioDesign.accent)
            Text(exercise.title).font(.title2.bold())
            Text(exercise.metadata?.objective ?? "Toca el ritmo completo y mantén el pulso.")
                .font(.subheadline).foregroundColor(StudioDesign.textSecondary).lineLimit(2)
            ExercisePatternPreview(exercise: exercise, available: true)
            HStack {
                Text("Ritmo completo · \(recommendation.tempoStep.bpm) BPM · 70 % para avanzar")
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
                Text("Si ya conoces el ritmo, tócalo completo a su tempo de referencia y alcanza el 70 %. Así puedes empezar más adelante.")
                    .font(.caption).foregroundColor(StudioDesign.textSecondary)
            }
            Spacer()
            ActionButton("Ya conozco este ritmo", prominence: .secondary) { model.openCheckpointAssessment(exercise) }
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
        let chapterAccredited = model.chapterIsAccredited(chapter.exercises)
        let checkpoint = chapter.exercises.first { $0.metadata?.flags.contains("checkpoint") == true }
        HStack(alignment: .top, spacing: 12) {
            if isCurrent {
                Color.clear.frame(width: 48)
            } else {
                MetroTrainMarker(
                    isCurrent: false,
                    isCompleted: chapterAccredited,
                    isLocked: false,
                    isLast: index == totalCount - 1
                )
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.title.uppercased()).font(.studioLabel).foregroundColor(chapterAccredited ? StudioDesign.accent : StudioDesign.textPrimary)
                        Text(chapter.subtitle).font(.caption).foregroundColor(StudioDesign.textSecondary)
                    }
                    Spacer()
                    Text(chapterAccredited ? "ACREDITADO" : "\(completed)/\(chapter.exercises.count)")
                        .font(.caption.bold()).foregroundColor(chapterAccredited ? StudioDesign.accent : StudioDesign.textSecondary)
                }
                ProgressView(value: Double(completed), total: Double(max(1, chapter.exercises.count))).tint(StudioDesign.accent)
                Text(chapterAccredited ? "Puedes repasar estos ejercicios o subir el tempo." : "Todos los ritmos se pueden practicar. Acredita la estación con el checkpoint o supera cada ejercicio.")
                    .font(.caption).foregroundColor(StudioDesign.textSecondary)
                if let checkpoint, !chapterAccredited {
                    MetroCheckpointAction(model: model, exercise: checkpoint)
                }
                ForEach(Array(chapter.exercises.enumerated()), id: \.element.id) { item in
                    MetroExerciseRow(
                        model: model,
                        exercise: item.element,
                        state: state(item.element),
                        chapterAccredited: chapterAccredited,
                        isCurrent: isCurrent,
                        index: item.offset,
                        count: chapter.exercises.count
                    )
                }
            }
        }
        .padding(13)
        .background(StudioDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MetroCheckpointAction: View {
    @ObservedObject var model: Model
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 8) {
            ActionButton("Hacer prueba del bloque", prominence: .secondary) {
                model.openCheckpointAssessment(exercise)
            }
            Text("Ritmo completo · tempo de referencia · ≥70 %")
                .font(.caption2).foregroundColor(StudioDesign.textSecondary)
        }
    }
}

private struct MetroExerciseRow: View {
    @ObservedObject var model: Model
    let exercise: Exercise
    let state: CourseLevelStatus
    let chapterAccredited: Bool
    let isCurrent: Bool
    let index: Int
    let count: Int

    private var progressLabel: String {
        let levelState = model.courseLevels.first(where: { $0.exerciseID == exercise.id })
        if case .checkpoint(let checkpointID) = levelState?.creditSource {
            return "Acreditado por checkpoint · \(checkpointID)"
        }
        if state == .locked { return "Puedes practicar · pendiente de acreditar" }
        if state == .mastered && !chapterAccredited { return "Superado individualmente · capítulo pendiente" }
        if state == .mastered { return "Acreditado" }
        return model.tempoProgressSummary(for: exercise)
    }

    var body: some View {
        HStack(spacing: 8) {
            if isCurrent {
                MetroChapterTrainSegment(
                    state: state,
                    isCurrent: exercise.id == model.courseRecommendation?.exerciseID,
                    hasPrevious: index > 0,
                    hasNext: index < count - 1
                )
            }
            Button { model.openPreparation(exercise) } label: {
                HStack(spacing: 9) {
                    Image(systemName: state == .mastered ? "checkmark.circle.fill" : "music.note")
                        .foregroundColor(state == .mastered ? StudioDesign.accent : StudioDesign.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nivel \(exercise.level) · \(exercise.title)").font(.subheadline.bold()).lineLimit(1)
                        Text(progressLabel).font(.caption2).foregroundColor(StudioDesign.textSecondary)
                    }
                    Spacer()
                    if let award = model.highestTempoAward(for: exercise) {
                        TempoAwardBadge(award: award)
                    }
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundColor(StudioDesign.textMuted)
                }
                .padding(9).background(StudioDesign.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
}

struct TempoAwardBadge: View {
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
        .foregroundColor(isTrophy ? StudioDesign.regular : .yellow)
        .accessibilityLabel(award.label)
    }

    private var isTrophy: Bool {
        if case .trophies = award { return true }
        return false
    }
}

private struct MetroChapterTrainSegment: View {
    let state: CourseLevelStatus
    let isCurrent: Bool
    let hasPrevious: Bool
    let hasNext: Bool

    var body: some View {
        VStack(spacing: 0) {
            routeLine(visible: hasPrevious, solid: state == .mastered || isCurrent)
            ZStack {
                RoundedRectangle(cornerRadius: isCurrent ? 8 : 4)
                    .fill(vehicleColor)
                    .frame(width: 30, height: isCurrent ? 34 : 24)
                Image(systemName: vehicleSymbol)
                    .font(isCurrent ? .subheadline.bold() : .caption.bold())
                    .foregroundColor(isCurrent || state == .mastered ? StudioDesign.canvas : StudioDesign.textMuted)
            }
            if isCurrent {
                HStack(spacing: 7) {
                    Circle().fill(StudioDesign.textSecondary).frame(width: 5, height: 5)
                    Circle().fill(StudioDesign.textSecondary).frame(width: 5, height: 5)
                }.padding(.top, 3)
            }
            routeLine(visible: hasNext, solid: state == .mastered && !isCurrent)
        }
        .frame(width: 30)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func routeLine(visible: Bool, solid: Bool) -> some View {
        if visible {
            if solid {
                Rectangle().fill(StudioDesign.accent.opacity(0.8)).frame(width: 2, height: 12)
            } else {
                Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .foregroundColor(StudioDesign.textMuted).frame(width: 2, height: 12)
            }
        } else {
            Color.clear.frame(width: 2, height: 12)
        }
    }

    private var vehicleSymbol: String {
        if isCurrent { return "tram.fill" }
        if state == .mastered { return "checkmark" }
        return state == .locked ? "lock.fill" : "music.note"
    }

    private var vehicleColor: Color {
        if isCurrent { return StudioDesign.accent }
        if state == .mastered { return StudioDesign.accent }
        return StudioDesign.surfaceHover
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
        if isCompleted { return StudioDesign.accent }
        return StudioDesign.surfaceHover
    }

    private var wheelColor: Color {
        isLocked ? StudioDesign.textMuted : StudioDesign.textSecondary
    }
}
