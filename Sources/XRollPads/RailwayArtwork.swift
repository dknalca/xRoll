import SwiftUI

/// Ilustración vectorial propia y estática: no carga imágenes ni comparte reloj
/// con la práctica. El lienzo conserva sus proporciones en teléfono y escritorio.
struct RailwayJourneyArtwork: View {
    let stationNumber: Int
    var completed = false

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 380, size.height / 142)
            context.translateBy(x: (size.width - 380 * scale) / 2, y: (size.height - 142 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let mint = Color(red: 0.388, green: 0.902, blue: 0.745)
            let blue = Color(red: 0.28, green: 0.64, blue: 0.88)
            let gold = Color(red: 1, green: 0.79, blue: 0.32)
            let ink = Color(red: 0.055, green: 0.09, blue: 0.13)
            let trainColor = completed ? gold : mint

            func rectangle(_ rect: CGRect, color: Color, radius: CGFloat = 0) {
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
            }
            func circle(x: CGFloat, y: CGFloat, radius: CGFloat, color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                    width: radius * 2, height: radius * 2)), with: .color(color))
            }

            circle(x: 72, y: 42, radius: 34, color: mint.opacity(0.045))
            circle(x: 72, y: 42, radius: 23, color: mint.opacity(0.06))
            circle(x: 72, y: 42, radius: 13, color: gold.opacity(0.24))

            // Silueta de ciudad y luces: una composición fija, sin ruido aleatorio.
            let buildings: [(CGFloat, CGFloat, CGFloat)] = [(0,24,22),(28,20,38),(52,28,16),
                (86,18,28),(108,27,44),(140,22,26),(168,28,36),(205,22,19),(232,20,32),(352,28,44)]
            for (index, building) in buildings.enumerated() {
                let (x, width, height) = building
                rectangle(CGRect(x: x, y: 104 - height, width: width, height: height),
                    color: blue.opacity(index.isMultiple(of: 2) ? 0.09 : 0.14), radius: 3)
                rectangle(CGRect(x: x + 6, y: 111 - height, width: 3, height: 5), color: mint.opacity(0.18), radius: 1)
            }

            // Traviesas y dos raíles bajo el tren y el andén.
            for x in stride(from: CGFloat(4), through: 376, by: 14) {
                rectangle(CGRect(x: x, y: 109, width: 4, height: 13), color: blue.opacity(0.22), radius: 1)
            }
            rectangle(CGRect(x: 0, y: 109, width: 380, height: 2), color: mint.opacity(0.5), radius: 1)
            rectangle(CGRect(x: 0, y: 117, width: 380, height: 2), color: blue.opacity(0.4), radius: 1)

            // Andén, marquesina y señal de la estación.
            rectangle(CGRect(x: 246, y: 101, width: 112, height: 9), color: blue.opacity(0.5), radius: 3)
            rectangle(CGRect(x: 262, y: 43, width: 4, height: 58), color: mint.opacity(0.65), radius: 2)
            rectangle(CGRect(x: 340, y: 43, width: 4, height: 58), color: mint.opacity(0.65), radius: 2)
            rectangle(CGRect(x: 251, y: 37, width: 104, height: 9), color: mint.opacity(0.75), radius: 4)
            rectangle(CGRect(x: 282, y: 48, width: 45, height: 25), color: ink, radius: 5)
            context.draw(Text("\(stationNumber)").font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(trainColor), at: CGPoint(x: 304, y: 60))
            rectangle(CGRect(x: 287, y: 86, width: 30, height: 4), color: blue.opacity(0.65), radius: 2)
            rectangle(CGRect(x: 290, y: 90, width: 3, height: 11), color: blue.opacity(0.65))
            rectangle(CGRect(x: 311, y: 90, width: 3, height: 11), color: blue.opacity(0.65))

            // Dos vagones con ventanas, unión, ruedas y faro.
            rectangle(CGRect(x: 35, y: 57, width: 84, height: 40), color: trainColor, radius: 10)
            rectangle(CGRect(x: 128, y: 57, width: 88, height: 40), color: trainColor, radius: 10)
            rectangle(CGRect(x: 118, y: 82, width: 12, height: 5), color: blue.opacity(0.75), radius: 2)
            rectangle(CGRect(x: 48, y: 53, width: 56, height: 4), color: trainColor.opacity(0.55), radius: 2)
            rectangle(CGRect(x: 143, y: 53, width: 55, height: 4), color: trainColor.opacity(0.55), radius: 2)
            for x in [CGFloat(44),64,84,138,158,178] {
                rectangle(CGRect(x: x, y: 65, width: 14, height: 15), color: ink, radius: 3)
                rectangle(CGRect(x: x + 2, y: 67, width: 10, height: 3), color: blue.opacity(0.55), radius: 1)
            }
            rectangle(CGRect(x: 103, y: 65, width: 9, height: 27), color: ink.opacity(0.7), radius: 3)
            rectangle(CGRect(x: 197, y: 65, width: 12, height: 17), color: ink, radius: 3)
            rectangle(CGRect(x: 38, y: 86, width: 77, height: 3), color: ink.opacity(0.18), radius: 1)
            rectangle(CGRect(x: 132, y: 86, width: 80, height: 3), color: ink.opacity(0.18), radius: 1)
            for x in [CGFloat(53),101,146,198] {
                circle(x: x, y: 100, radius: 7, color: ink)
                circle(x: x, y: 100, radius: 3, color: blue.opacity(0.75))
            }
            rectangle(CGRect(x: 210, y: 84, width: 4, height: 5), color: .white, radius: 2)

            // Notas y destellos fijos también funcionan con Reduce Motion.
            context.draw(Text("♪").font(.system(size: 22, weight: .bold)).foregroundColor(mint.opacity(0.65)), at: CGPoint(x: 173, y: 27))
            context.draw(Text("♫").font(.system(size: 16, weight: .bold)).foregroundColor(blue.opacity(0.7)), at: CGPoint(x: 222, y: 43))
            if completed {
                for point in [CGPoint(x: 28,y: 28), CGPoint(x: 125,y: 22), CGPoint(x: 240,y: 17), CGPoint(x: 359,y: 29)] {
                    context.draw(Text("✦").font(.system(size: 16, weight: .bold)).foregroundColor(gold), at: point)
                }
            }
        }
        .background(LinearGradient(colors: [Color(red: 0.065, green: 0.14, blue: 0.17),
            Color(red: 0.055, green: 0.08, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Sello decorativo de estación. El nombre y el estado continúan siendo texto
/// accesible: ni el color ni el dibujo sustituyen esa información.
struct RailwayStationEmblem: View {
    let chapter: String
    let completed: Bool

    private var symbol: String {
        switch chapter {
        case "initiation": return "sunrise.fill"
        case "fundamentals": return "metronome.fill"
        case "coordination": return "hand.tap.fill"
        case "subdivision": return "square.grid.2x2.fill"
        case "groove": return "music.note.list"
        case "hiphop": return "headphones"
        case "rock": return "bolt.fill"
        case "disco": return "sparkles"
        case "funk": return "waveform"
        case "reggae": return "sun.max.fill"
        case "dembow": return "waveform.path"
        case "blues": return "music.note"
        case "jazz": return "pianokeys"
        case "jazz-intermediate": return "music.note.list"
        default: return "circle.grid.2x2.fill"
        }
    }

    private var accent: Color {
        if completed { return Color(red: 1, green: 0.79, blue: 0.32) }
        switch chapter {
        case "hiphop", "rock", "dembow": return Color(red: 1, green: 0.55, blue: 0.43)
        case "disco", "funk", "jazz", "jazz-intermediate": return Color(red: 0.70, green: 0.60, blue: 1)
        case "blues", "subdivision": return Color(red: 0.36, green: 0.72, blue: 1)
        default: return Color(red: 0.388, green: 0.902, blue: 0.745)
        }
    }

    var body: some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            .foregroundColor(accent).frame(width: 32, height: 32)
            .background(Circle().fill(accent.opacity(0.12)))
            .overlay(Circle().stroke(accent.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
