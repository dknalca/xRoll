import SwiftUI
import XRollCore

struct iOSOptionsView: View {
    @ObservedObject var model: iOSPracticeModel
    @Binding var isPresented: Bool
    @State private var showsKitMix = false

    var body: some View {
        NavigationStack {
            ZStack {
                iOSStudioDesign.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Preferencias que se conservan entre prácticas.")
                            .font(.subheadline).foregroundStyle(iOSStudioDesign.secondary)
                        practiceAudioOptions
                        loopOptionsCard
                        kitMixCard
                        audioRouteCard
                        visualSettings
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Opciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { isPresented = false }
                        .foregroundStyle(iOSStudioDesign.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var practiceAudioOptions: some View {
        iOSStudioPanel {
            Text("REFERENCIA RÍTMICA").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.9).foregroundStyle(iOSStudioDesign.accent)
            Toggle("Metrónomo", isOn: Binding(get: { model.metronomeEnabled }, set: { model.setMetronomeEnabled($0) }))
                .font(.subheadline)
            if model.metronomeEnabled {
                HStack(spacing: 8) {
                    Text("Tono").font(.caption.weight(.semibold)).foregroundStyle(iOSStudioDesign.secondary)
                    Slider(value: Binding(
                        get: { model.metronomePitchSemitones },
                        set: { model.setMetronomePitchSemitones($0) }
                    ), in: -12...24, step: 1)
                    .tint(iOSStudioDesign.accent)
                    .accessibilityLabel("Tono del metrónomo")
                    Text(String(format: "%+.0f semitonos", model.metronomePitchSemitones))
                        .font(.caption2.monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary)
                        .frame(width: 86, alignment: .trailing)
                }
                .disabled(model.isPracticing || model.isPreviewing)
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    Slider(value: Binding(get: { model.metronomeVolume }, set: { model.setMetronomeVolume($0) }), in: 0...1)
                        .tint(iOSStudioDesign.accent)
                        .accessibilityLabel("Volumen del metrónomo")
                    Text("\(Int((model.metronomeVolume * 100).rounded())) %")
                        .font(.caption.monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary).frame(width: 38, alignment: .trailing)
                }
                Button { model.previewMetronome() } label: {
                    Label("Escuchar metrónomo", systemImage: "play.fill")
                        .font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                .disabled(model.isPracticing || model.isPreviewing)
            }
            Text("La claqueta cubre los dos compases de anticipación visual y la práctica. Durante la calibración se reproduce aunque este ajuste esté apagado.")
                .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
            if !model.metronomeStatus.isEmpty {
                Text(model.metronomeStatus).font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
            }
        }
    }

    private var loopOptionsCard: some View {
        iOSStudioPanel {
            Text("ACOMPAÑAMIENTO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.9).foregroundStyle(iOSStudioDesign.accent)
            if model.loopOptions.isEmpty {
                Text(model.loopStatus).font(.caption).foregroundStyle(iOSStudioDesign.secondary)
            } else {
                Toggle("Loop", isOn: Binding(get: { model.loopEnabled }, set: { model.setLoopEnabled($0) }))
                    .font(.subheadline)
                Picker("Loop incluido", selection: Binding(
                    get: { model.loopSelectionChoice },
                    set: { model.setLoopSelectionChoice($0) }
                )) {
                    Text(model.loopSelectionLabel).tag(LoopLibraryCatalog.automaticSelectionID)
                    ForEach(model.loopOptions) { option in
                        Text(option.bpm.map { "\(option.fileName) · \(Int($0.rounded())) BPM" } ?? option.fileName)
                            .tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isPracticing || model.isPreviewing)
                if model.loopEnabled {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                        Slider(value: Binding(get: { model.loopVolume }, set: { model.setLoopVolume($0) }), in: 0...1)
                            .tint(iOSStudioDesign.accent)
                            .accessibilityLabel("Volumen del loop")
                        Text("\(Int((model.loopVolume * 100).rounded())) %")
                            .font(.caption.monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary).frame(width: 38, alignment: .trailing)
                    }
                }
                Text(model.loopStatus).font(.caption).foregroundStyle(iOSStudioDesign.secondary).fixedSize(horizontal: false, vertical: true)
                if !model.loopEnabled {
                    Text("Está desactivado de forma predeterminada; actívalo para oír el acompañamiento.")
                        .font(.caption2).foregroundStyle(iOSStudioDesign.secondary)
                }
                Text("El loop entra desde la cuenta de entrada y continúa durante el ejercicio.")
                    .font(.caption2).foregroundStyle(iOSStudioDesign.muted)
            }
        }
    }

    private var kitMixCard: some View {
        iOSStudioPanel {
            DisclosureGroup(isExpanded: $showsKitMix) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ajusta el nivel de cada sonido sin modificar los archivos del kit.")
                        .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
                    HStack {
                        Spacer()
                        Button("Restablecer mezcla") { model.resetSoundMix() }
                            .font(.caption.bold()).buttonStyle(.bordered).tint(iOSStudioDesign.secondary)
                    }
                    ForEach(model.kitSoundIDs, id: \.self) { soundID in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(model.kitLabel(for: soundID)).font(.caption.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
                                Spacer()
                                Text("\(Int((model.soundVolume(soundID) * 100).rounded())) %")
                                    .font(.caption.monospacedDigit()).foregroundStyle(iOSStudioDesign.secondary)
                            }
                            Slider(value: Binding(
                                get: { model.soundVolume(soundID) },
                                set: { model.setSoundVolume($0, for: soundID) }
                            ), in: 0...1.5)
                            .tint(iOSStudioDesign.accent)
                            .accessibilityLabel("Volumen de \(model.kitLabel(for: soundID))")
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Mezcla del kit", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary)
            }
            .tint(iOSStudioDesign.accent)
        }
    }

    private var audioRouteCard: some View {
        iOSStudioPanel {
            Text("SALIDA DE AUDIO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.9).foregroundStyle(iOSStudioDesign.accent)
            HStack(spacing: 10) {
                Label(model.audioOutputName, systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(iOSStudioDesign.primary).lineLimit(2)
                Spacer()
                iOSAudioRoutePicker()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Elegir salida de audio del sistema")
            }
            Text("La calibración se guarda por entrada y salida. Si cambias de ruta, calibra de nuevo antes de puntuar.")
                .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
        }
    }

    private var visualSettings: some View {
        iOSStudioPanel {
            Text("DIAGNÓSTICO VISUAL").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(iOSStudioDesign.accent)
            Toggle(
                "Anticipar un frame visual (A/B)",
                isOn: Binding(get: { model.predictsVisualFrame }, set: { model.setVisualFramePrediction($0) })
            )
            .font(.subheadline)
            Text("Ajuste experimental de presentación; no cambia el scoring MIDI.")
                .font(.caption).foregroundStyle(iOSStudioDesign.secondary)
        }
    }
}
