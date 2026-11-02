import SwiftUI
import XRollCore

/// Convierte los desfases en posiciones sin intervenir en su cálculo musical.
private struct DriftChartLayout {
    let count: Int
    let width: CGFloat
    let height: CGFloat
    let extent: Double

    func position(index: Int, offset: Double) -> CGPoint {
        let x = width * CGFloat(index) / CGFloat(max(1, count - 1))
        let y = height / 2 - CGFloat(offset / extent) * (height * 0.42)
        return CGPoint(x: x, y: y)
    }
}

struct iOSPulseDriftChart: View {
    let report: PulseDriftReport

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DERIVA DURANTE EL SILENCIO")
                .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8)
                .foregroundStyle(iOSStudioDesign.secondary)
            GeometryReader { geometry in
                let points = report.points
                let layout = DriftChartLayout(count: points.count, width: max(1, geometry.size.width),
                    height: max(1, geometry.size.height),
                    extent: max(40, points.map { abs($0.medianOffsetMilliseconds) }.max() ?? 40))
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: layout.height / 2))
                        path.addLine(to: CGPoint(x: layout.width, y: layout.height / 2))
                    }
                    .stroke(iOSStudioDesign.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if points.count > 1 {
                        Path { path in
                            for (index, point) in points.enumerated() {
                                let position = layout.position(index: index, offset: point.medianOffsetMilliseconds)
                                if index == 0 { path.move(to: position) }
                                else { path.addLine(to: position) }
                            }
                        }
                        .stroke(iOSStudioDesign.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Circle().fill(point.metronomeAudible ? iOSStudioDesign.accent : iOSStudioDesign.regular)
                            .frame(width: 6, height: 6)
                            .position(layout.position(index: index, offset: point.medianOffsetMilliseconds))
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
