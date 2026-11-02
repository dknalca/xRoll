# Revisión adicional de código — 29 de octubre de 2026

## Estado del alcance

Esta pasada continúa `AUDITORIA_APLICACION_2026-10-28.md`, pero **no está
completa archivo por archivo**. La inspección comprende flujos de los
coordinadores macOS e iOS, límites de sesión y navegación, y partes del núcleo,
SpriteKit, herramientas y automatización. Algunas lecturas extensas quedaron
truncadas; no se cuentan como una inspección línea por línea completa.

Se han revisado en esta pasada, entre otros, `Sources/XRollCore/AudioClock.swift`,
`KitNoteRouter.swift`, `LatencyRecordingAnalysis.swift`, `LiveMIDIProcessor.swift`,
`PracticeSessionProcessor.swift`, `CurriculumValidation.swift`,
`PedagogicalMIDIValidator.swift`, `MIDIExerciseMetadata.swift`,
`PadMapBuilder.swift`, `PracticeSession.swift`, `TuningSettings.swift` y
`Calibration.swift`, además de `LoopPlayback.swift`, `PadMap.swift` y
`PadMapV2.swift`, `MIDIExercise.swift`, `MIDIInput.swift` y `ResourceModels.swift`,
`Sources/XRollRealtimeQueue/XRollRealtimeQueue.c` y su cabecera, y
los ejecutables `XRollRecordingAnalysis`, `XRollExercisePreview`,
`XRollKitPlayer`, `XRollLatency`, `XRollPadMapper` y `XRollProgressExport`.
Se leyeron también `DrummerQuotes.swift`, `RhythmMetroView.swift`,
`StudioDesign.swift`, `RailwayArtwork.swift` y `XRollBrand.swift`.
También se inspeccionaron tramos de
`Sources/XRollPads/FriendlyPracticeHome.swift` y `PracticeScene.swift`, sin
terminar su lectura completa. Quedan por contrastar exhaustivamente todas las
fuentes, pruebas, scripts, configuración y recursos, incluyendo las partes
truncadas de los coordinadores y archivos largos. El inventario no equivale a
haber revisado cada archivo ni a probar todas sus combinaciones.

## Hallazgos de esta pasada

- **Análisis de grabaciones:** `primaryOnsets` y `transients` usaban muestras
  positivas en vez de magnitudes. Una señal con transitorios exclusivamente
  negativos no producía detecciones; invertir la polaridad podía alterar el
  resultado. Ambos detectores comparan ahora magnitudes y devuelven amplitudes
  positivas. La regresión reproduce el fallo con señales de polaridad opuesta.
  Es una herramienta de diagnóstico offline, no la ruta de audio en directo;
  la prueba no valida medidas reales de latencia.
- **Mensajes del mapeo de teclado macOS:** se corrigió la interpolación de la
  tecla y el sonido cuando hay una tecla duplicada, y el texto final indica diez
  teclas en lugar de seis. No se ha realizado una prueba manual de esa pantalla.
- **Mensajes de CLI:** preview, reproductor de kit y mapeador imprimían `\n`
  literal en mensajes de error. Se corrigieron los escapes y se comprobaron las
  salidas de uso de los tres ejecutables y su código de salida, sin hardware.

## Comprobaciones de esta pasada

- `swift build` y la compilación genérica iOS sin firma han terminado correctamente.
- La regresión de polaridad y los dos casos existentes de transitorios y onsets
  pasaron por separado. Se verificaron los tres mensajes de uso de CLI.
- `git diff --check` pasó. AddressSanitizer ejecutó las 15 pruebas de
  `AuditRegressionTests` sin fallos; no es una ejecución de toda la suite.
- `swift test`: 222 pruebas sin fallos. La ejecución comenzó antes de corregir
  los mensajes de las CLI; esos mensajes se verificaron por separado.

## Limitaciones

No se ha validado MIDI o Bluetooth físico, latencia extremo a extremo, FPS,
respuesta acústica, accesibilidad real ni todas las combinaciones de dispositivo.
La revisión estática y las pruebas automatizadas no demuestran ausencia de
defectos. Las comprobaciones manuales siguen en `RELEASE_CHECKLIST.md`.
