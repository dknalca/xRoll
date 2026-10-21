import SwiftUI
import XRollCore

/// Mapa, acciones y celebraciones compartidos por macOS e iOS. Los anfitriones
/// solo aportan estado y acciones; el progreso continúa perteneciendo al núcleo.
struct CourseRailwayMap: View {
    let stations: [CourseWorld]
    let evidence: [CourseAttemptEvidence]
    let selectExercise: (Exercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("METRO DEL RITMO").font(.caption.bold()).tracking(1.2).foregroundColor(RailwayColors.accent)
                .accessibilityIdentifier("course.map.title")
            Text("Una estación cada vez").font(.largeTitle.bold())
            Text("Completa los niveles y el reto final para avanzar a la siguiente parada.")
                .font(.subheadline).foregroundColor(RailwayColors.secondary)
            Label("\(stations.filter(\.isCompleted).count) de \(stations.count) estaciones completadas", systemImage: "tram.fill")
                .font(.subheadline.weight(.semibold)).foregroundColor(RailwayColors.accent)

            if let station = stations.first(where: \.isCurrent), let level = station.nextLevel {
                RailwayPanel(highlighted: true) {
                    Text("ESTACIÓN \(station.number) · \(station.title.uppercased())")
                        .font(.caption.bold()).foregroundColor(RailwayColors.accent)
                    Label(level.label, systemImage: level.isBoss ? "flag.checkered" : "tram.fill").font(.title2.bold())
                    Text(level.title).font(.headline)
                    Text(level.isBoss ? "Reúne lo aprendido. Alcanza el 70 % y completa esta estación." : (level.exercise.metadata?.objective ?? "Toca el ritmo completo y mantén el pulso."))
                        .font(.subheadline).foregroundColor(RailwayColors.secondary).fixedSize(horizontal: false, vertical: true)
                    RailwayPrimaryButton(title: level.actionTitle, symbol: level.isBoss ? "flag.checkered" : "play.fill",
                        identifier: "course.next") { selectExercise(level.exercise) }
                }
            } else if !stations.isEmpty {
                RailwayPanel {
                    Label("¡Has llegado al final de la línea!", systemImage: "tram.fill").font(.title2.bold())
                    Text("Todas las estaciones completadas. Puedes volver a tus ritmos favoritos.")
                        .foregroundColor(RailwayColors.secondary)
                }
                .accessibilityIdentifier("course.finished")
            }

            VStack(spacing: 16) {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    RailwayStationCard(station: station, evidence: evidence, selectExercise: selectExercise)
                        .overlay(alignment: .leading) {
                            if index < stations.count - 1 {
                                GeometryReader { geometry in
                                    Path { path in
                                        path.move(to: CGPoint(x: -32, y: 40))
                                        path.addLine(to: CGPoint(x: -32, y: geometry.size.height + 16))
                                    }
                                    .stroke(station.isCompleted ? RailwayColors.accent : RailwayColors.track,
                                        style: StrokeStyle(lineWidth: 3, dash: station.isCompleted ? [] : [5, 5]))
                                }
                                .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            RailwayStopMarker(station: station).offset(x: -54, y: 0)
                        }
                        .padding(.leading, 54)
                }
            }
        }
        .foregroundColor(RailwayColors.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RailwayStationCard: View {
    let station: CourseWorld
    let evidence: [CourseAttemptEvidence]
    let selectExercise: (Exercise) -> Void
    @State private var isExpanded: Bool

    init(station: CourseWorld, evidence: [CourseAttemptEvidence], selectExercise: @escaping (Exercise) -> Void) {
        self.station = station; self.evidence = evidence; self.selectExercise = selectExercise
        _isExpanded = State(initialValue: station.isCurrent)
    }

    var body: some View {
        RailwayPanel(highlighted: station.isCurrent) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 8) {
                    ForEach(station.levels) { level in
                        RailwayLevelRow(level: level,
                            award: TempoLadder.highestPassedStep(for: level.exercise, evidence: evidence)?.award) {
                            selectExercise(level.exercise)
                        }
                    }
                }.padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(station.number) · \(station.title)").font(.headline)
                        Spacer(minLength: 4)
                        Text("\(station.completedLevelCount)/\(station.levels.count)").font(.caption.bold().monospacedDigit())
                    }
                    Text(station.statusLabel).font(.caption).foregroundColor(RailwayColors.secondary)
                        .accessibilityIdentifier("course.station.\(station.id).status")
                    ProgressView(value: Double(station.completedLevelCount), total: Double(max(1, station.levels.count)))
                        .tint(RailwayColors.accent)
                }
            }
            .tint(RailwayColors.accent)
        }
        .onChange(of: station.isCurrent) { isExpanded = $0 }
    }
}

private struct RailwayLevelRow: View {
    let level: CourseWorld.Level
    let award: TempoAward?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: level.isBoss ? "flag.checkered" : (level.isPassed ? "checkmark.circle.fill" : "music.note"))
                    .font(.title3).foregroundColor(level.isNext ? RailwayColors.accent : RailwayColors.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.label.uppercased()).font(.caption.bold()).foregroundColor(RailwayColors.accent)
                    Text(level.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    Text(level.isPassed ? "Superado" : (level.isNext ? "Te toca ahora" : "Por completar"))
                        .font(.caption2).foregroundColor(RailwayColors.secondary)
                }
                Spacer(minLength: 4)
                if let award { TempoAwardBadge(award: award) }
                Image(systemName: "chevron.right").font(.caption).foregroundColor(RailwayColors.secondary)
            }
            .foregroundColor(RailwayColors.primary).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(RailwayColors.raised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(level.isBoss ? RailwayColors.gold : (level.isNext ? RailwayColors.accent : .clear), lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityIdentifier("course.level.\(level.id)")
    }
}

private struct RailwayStopMarker: View {
    let station: CourseWorld

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: station.isCurrent ? 10 : 22)
                .fill(station.isCurrent || station.isCompleted ? RailwayColors.accent : RailwayColors.track)
            if station.isCurrent || station.isCompleted {
                Image(systemName: station.isCurrent ? "tram.fill" : "checkmark")
                    .font(.title3.bold()).foregroundColor(RailwayColors.canvas)
            } else {
                Text("\(station.number)").font(.headline).foregroundColor(RailwayColors.primary)
            }
        }
        .frame(width: 44, height: 44).accessibilityHidden(true)
    }
}

struct CourseStationCompletionBanner: View {
    let completion: CourseWorldVictory
    let stars: Int
    let continueAction: () -> Void

    var body: some View {
        RailwayPanel(highlighted: true) {
            Image(systemName: "tram.fill").font(.system(size: 52)).foregroundColor(RailwayColors.accent)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(completion.title).font(.largeTitle.bold()).accessibilityIdentifier("course.arrival.title")
            Text(completion.message).font(.headline).foregroundColor(RailwayColors.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("course.arrival.message")
            Text(String(repeating: "★", count: max(0, min(3, stars))))
                .font(.largeTitle).foregroundColor(RailwayColors.gold)
            RailwayPrimaryButton(title: completion.actionTitle, symbol: "tram.fill", identifier: "course.arrival.continue", action: continueAction)
        }
        .foregroundColor(RailwayColors.primary)
    }
}

struct CourseLevelPassedBanner: View {
    let reason: String
    let actionTitle: String
    let continueAction: () -> Void
    let returnToMap: () -> Void

    var body: some View {
        RailwayPanel {
            Label("¡Nivel superado!", systemImage: "star.circle.fill").font(.title2.bold()).foregroundColor(RailwayColors.accent)
            Text(reason).font(.subheadline).foregroundColor(RailwayColors.secondary)
            RailwayPrimaryButton(title: actionTitle, symbol: "arrow.right.circle.fill", identifier: "course.continue", action: continueAction)
            Button("Volver al mapa", action: returnToMap)
                .font(.subheadline).buttonStyle(.bordered).tint(RailwayColors.accent)
                .accessibilityIdentifier("result.menu")
        }
        .foregroundColor(RailwayColors.primary)
    }
}

struct TempoAwardBadge: View {
    let award: TempoAward

    var body: some View {
        Group {
            switch award {
            case .stars(let count): Text(String(repeating: "★", count: count))
            case .trophies(let count): Text(String(repeating: "🏆", count: count))
            }
        }
        .font(.caption.bold()).foregroundColor(RailwayColors.gold).accessibilityLabel(award.label)
    }
}

private struct RailwayPrimaryButton: View {
    let title: String
    let symbol: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundColor(RailwayColors.canvas)
                .background(RoundedRectangle(cornerRadius: 10).fill(RailwayColors.accent))
        }
        .buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
}

private struct RailwayPanel<Content: View>: View {
    var highlighted = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(RailwayColors.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(highlighted ? RailwayColors.accent : RailwayColors.track, lineWidth: 1))
    }
}

private enum RailwayColors {
    static let canvas = Color(red: 0.043, green: 0.051, blue: 0.067)
    static let panel = Color(red: 0.067, green: 0.082, blue: 0.106)
    static let raised = Color(red: 0.090, green: 0.110, blue: 0.141)
    static let track = Color(red: 0.20, green: 0.25, blue: 0.30)
    static let primary = Color(red: 0.945, green: 0.953, blue: 0.965)
    static let secondary = Color(red: 0.69, green: 0.74, blue: 0.80)
    static let accent = Color(red: 0.388, green: 0.902, blue: 0.745)
    static let gold = Color(red: 1.0, green: 0.79, blue: 0.32)
}
