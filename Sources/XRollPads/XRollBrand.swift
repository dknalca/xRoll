import SwiftUI

/// Dos baquetas se cruzan sobre el punto de impacto: la marca representa
/// literalmente el gesto que se practica en xRoll.
struct XRollBrandMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(red: 0.045, green: 0.075, blue: 0.105))
            Circle()
                .stroke(Color(red: 0.25, green: 0.78, blue: 0.76).opacity(0.42), lineWidth: max(1, size * 0.018))
                .frame(width: size * 0.67, height: size * 0.67)
            Capsule()
                .fill(Color(red: 0.85, green: 0.94, blue: 0.96))
                .frame(width: size * 0.10, height: size * 0.62)
                .rotationEffect(.degrees(-44))
            Capsule()
                .fill(Color(red: 0.35, green: 0.88, blue: 0.76))
                .frame(width: size * 0.10, height: size * 0.62)
                .rotationEffect(.degrees(44))
            Circle()
                .fill(Color(red: 0.98, green: 0.77, blue: 0.35))
                .frame(width: size * 0.14, height: size * 0.14)
            Capsule()
                .fill(Color(red: 0.35, green: 0.88, blue: 0.76))
                .frame(width: size * 0.34, height: max(1.5, size * 0.025))
                .offset(y: size * 0.32)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XRollLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.055).ignoresSafeArea()
            VStack(spacing: 18) {
                XRollBrandMark(size: 120)
                    .scaleEffect(appeared || reducesMotion ? 1 : 0.78)
                Text("xRoll")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("ENCUENTRA TU PULSO")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.35, green: 0.88, blue: 0.76))
            }
            .opacity(appeared || reducesMotion ? 1 : 0)
        }
        .onAppear {
            withAnimation(reducesMotion ? nil : .easeOut(duration: 0.5)) { appeared = true }
        }
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct AnimatedScorePercentage: View, Animatable {
    var percentage: Double
    var animatableData: Double {
        get { percentage }
        set { percentage = newValue }
    }

    var body: some View {
        Text("\(Int(percentage.rounded()))%")
            .font(.system(size: 68, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundColor(Color(red: 0.93, green: 0.97, blue: 0.97))
    }
}

/// Transición de presentación después de cerrar y puntuar una sesión.
/// No mantiene viva la sesión ni bloquea el motor de audio.
struct PracticeCompletionTransition: View {
    let percentage: Double
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var animationStarted = false

    private var normalizedScore: CGFloat {
        CGFloat(min(100, max(0, percentage)) / 100)
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.055).ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.06, green: 0.16, blue: 0.20).opacity(0.75), .clear],
                center: .center,
                startRadius: 35,
                endRadius: 430
            )
            .ignoresSafeArea()

            VStack(spacing: 17) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: animationStarted ? normalizedScore : 0)
                        .stroke(
                            AngularGradient(
                                colors: [Color(red: 0.28, green: 0.73, blue: 0.96), Color(red: 0.35, green: 0.88, blue: 0.76)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    XRollBrandMark(size: 78)
                        .scaleEffect(animationStarted || reducesMotion ? 1 : 0.88)
                }
                .frame(width: 144, height: 144)
                .animation(reducesMotion ? nil : .easeOut(duration: 0.82), value: animationStarted)

                Text("EJERCICIO COMPLETADO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundColor(Color(red: 0.35, green: 0.88, blue: 0.76))

                AnimatedScorePercentage(percentage: animationStarted || reducesMotion ? percentage : 0)

                Text("Preparando el resumen de tu sesión")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.58))
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(reducesMotion ? nil : .easeOut(duration: 0.82)) { animationStarted = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ejercicio completado. Resultado: \(Int(percentage.rounded())) por ciento.")
    }
}
