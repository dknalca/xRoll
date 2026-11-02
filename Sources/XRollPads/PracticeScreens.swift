import SpriteKit
import SwiftUI

/// Presenta la demostración sin participar en la puntuación ni el transporte.
struct PracticePreview: View {
    @ObservedObject var model: Model
    let scene: PracticeScene
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.04, blue: 0.09), Color(red: 0.075, green: 0.025, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DEMOSTRACIÓN GUIADA").font(.caption.bold()).foregroundColor(.cyan)
                        Text(model.currentExerciseTitle).font(.title2.bold())
                        Text("Observa una vuelta: aquí no se puntúa ningún golpe.").font(.caption).foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    ActionButton("Volver", prominence: .secondary) { model.stopPreview() }
                    ActionButton("Empezar a tocar", prominence: .primary) {
                        model.stopPreview()
                        if model.trainingPhase == .discover { model.setTrainingPhase(.integrate) }
                        model.startDirectFromPreparation()
                    }
                }
                SpriteView(scene: scene)
                StagePanel {
                    HStack(spacing: 5) {
                        Text("CÓMO USARLO").font(.caption.bold()).foregroundColor(.cyan)
                        ContextInfoButton(title: "Demostración guiada", detail: "xRoll toca el patrón para que observes los carriles y escuches la relación entre los sonidos. Aquí no tienes que golpear nada ni se registra una puntuación.")
                    }
                    Text("Mira qué carril llega a la línea y escucha cómo encajan los golpes. Cuando lo tengas claro, pulsa Empezar a tocar.")
                        .font(.subheadline).foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(24).foregroundColor(.white)
        }
        .onAppear { scene.setReducesMotion(reducesMotion) }
        .onChange(of: reducesMotion) { scene.setReducesMotion($0) }
    }
}

/// Presenta la sesión y delega pausa, salida y reanudación en el coordinador.
struct PracticeRun: View {
    @ObservedObject var model: Model
    let scene: PracticeScene
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    private var stageTitle: String {
        guard model.practiceIncludesRehearsal else { return "EN DIRECTO" }
        return model.isRehearsing ? "JUNTOS · SIN PUNTUAR" : "AHORA TÚ · SIGUE EL RITMO"
    }

    private var playerSoundMessage: String {
        guard model.whaleTargetMessage.isEmpty else { return model.whaleTargetMessage }
        let sounds = model.selectedPlayerSounds.map(model.displayName).sorted().joined(separator: " y ")
        return "Tú: \(sounds) · gris: acompañamiento"
    }

    var body: some View {
        ZStack {
            StudioDesign.canvas.ignoresSafeArea()
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stageTitle).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2).foregroundColor(StudioDesign.accent)
                            .accessibilityIdentifier("practice.stage")
                        Text(model.currentExerciseTitle).font(.headline.weight(.semibold)).foregroundColor(StudioDesign.textPrimary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(model.currentPracticeBPM) BPM · \(model.currentPracticeRepeats) vueltas")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(StudioDesign.textSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(StudioDesign.surfaceRaised, in: Capsule())
                    ActionButton("Pausar", prominence: .secondary) { model.pausePractice() }
                }
                if model.isCalibrationPractice {
                    Text(model.equipmentCalibrationPrompt).font(.subheadline.weight(.semibold))
                        .foregroundColor(StudioDesign.accent).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.practiceStepRange != nil || !model.isFullRhythmSelection {
                    Text(playerSoundMessage)
                        .font(.caption.weight(.semibold)).foregroundColor(StudioDesign.regular).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                ZStack(alignment: .top) {
                    SpriteView(scene: scene).id(model.practiceVisualID)
                    if model.isPracticePaused { pauseOverlay }
                }
                .frame(maxHeight: .infinity)
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
        }.foregroundColor(.white)
        .onAppear { scene.setReducesMotion(reducesMotion) }
        .onChange(of: reducesMotion) { scene.setReducesMotion($0) }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.68)
            VStack(spacing: 14) {
                Image(systemName: "pause.circle.fill").font(.system(size: 42)).foregroundColor(StudioDesign.accent)
                Text("Práctica en pausa").font(.title2.bold())
                Text("Al reanudar, el intento comenzará de nuevo con la cuenta de entrada para mantener audio, notas y puntuación sincronizados.")
                    .font(.subheadline).foregroundColor(StudioDesign.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                HStack(spacing: 10) {
                    ActionButton("Terminar sesión", prominence: .secondary) { model.leaveActiveScreen() }
                    ActionButton("Reanudar desde el inicio", prominence: .primary) { model.resumePractice() }
                }
            }
            .padding(28)
            .background(StudioDesign.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(StudioDesign.accent.opacity(0.22), lineWidth: 1))
        }
    }
}
