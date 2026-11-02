# Guía de lectura del código

Esta guía es un mapa para empezar a leer xRoll; las reglas y decisiones completas
están en `CLAUDE.md`, `AGENTS.md`, `docs/ARCHITECTURE.md` y `docs/DECISIONS.md`.

## Dónde empieza cada parte

| Si quieres entender… | Empieza por… |
|---|---|
| El arranque y las ventanas de macOS | `Sources/XRollPads/main.swift`: `XRollPadsApp`, `ContentView` y `Model` |
| Demostración y pantalla de práctica en macOS | `Sources/XRollPads/PracticeScreens.swift`: `PracticePreview` y `PracticeRun` |
| La app de iPhone/iPad | `iOS/XRolliOSApp.swift`: `XRolliOSApp` e `iOSPracticeModel` |
| Los pads táctiles de práctica | `iOS/TouchPadLayout.swift` (geometría) e `iOS/PadTouchGrid.swift` (dibujo, toque y accesibilidad) |
| La gráfica de deriva en resultados iOS | `iOS/PulseDriftChart.swift` |
| Las pantallas compartidas del curso | `Sources/XRollPads/CourseRailwayMap.swift` |
| Los sonidos y ejercicios disponibles | `Resources/Kits/`, `data/exercises/`, `ResourceModels.swift` y `MIDIExercise.swift` |
| Las reglas del catálogo curricular | `Sources/XRollCore/CurriculumValidation.swift` |
| Los metadatos curriculares dentro del MIDI | `Sources/XRollCore/MIDIExerciseMetadata.swift` |
| Las notas y el feedback que se ven | `Sources/XRollPads/PracticeScene.swift` |
| El historial y su exportación | `Sources/XRollCore/ProgressStore.swift` |

`Sources/XRollCore` contiene las reglas y los servicios compartidos. Las vistas
presentan información y solicitan acciones al coordinador de su plataforma; no
deciden por su cuenta cómo se puntúa una nota. Algunas fuentes de `XRollPads`
también se compilan en iOS mediante la lista explícita del proyecto Xcode.

## Qué ocurre cuando alguien toca

1. El ejercicio MIDI se carga con `MIDIExerciseLoader` y se valida contra el
   kit. Cada nota indica sonido y paso musical; el tempo y el compás vienen del
   archivo. `ExerciseTimeline` convierte esos pasos en tiempos y repeticiones.
2. El coordinador crea una `PracticeSession` con la configuración y el perfil
   de calibración de la ruta actual. Puede haber una vuelta de referencia y una
   cuenta antes del tramo puntuable: no acreditan golpes ni compases.
3. En MIDI, el callback de `MIDIInput.swift` encola paquetes; un worker los
   decodifica. `LiveMIDIProcessor` resuelve el sonido con el mapa y lo reproduce
   sin esperar a la interfaz. La entrada conserva su `hostTime` original.
4. `PracticeSessionIngress` admite el golpe con el reloj y la generación de la
   sesión; `PracticeSessionProcessor` lo procesa en su cola serial. La
   compensación calibrada se resta al desfase, y `RhythmScorer` decide el juicio.
5. La interfaz recibe el resultado y `PracticeScene` dibuja notas y feedback.
   Los carriles son los sonidos activos del ejercicio; la rejilla física de
   Equipo conserva sus 16 posiciones.
6. Al finalizar, la barrera de admisión procesa los golpes ya aceptados antes de
   devolver la puntuación. Salir o cancelar invalida la generación y detiene el
   audio programado. Un intento interrumpido no acredita duración completa.

Los pads táctiles y el teclado usan su propia entrada, pero desembocan en la
misma lógica de sesión y puntuación. La reproducción en vivo es inmediata;
referencia, metrónomo y loop se programan para instantes futuros.

### Para seguir una entrada concreta

- **MIDI:** busca `midiReadProc` y `MIDIEventDelivery` en `MIDIInput.swift`;
  después `LiveMIDIProcessor.resolve` y la llamada a `PracticeSessionIngress.submit`
  en el coordinador de la plataforma. CoreMIDI entrega mensajes completos por
  paquete, excepto fragmentos SysEx; no se comparte estado MIDI entre fuentes.
- **Toque iOS:** `TouchGridView` en `iOS/PadTouchGrid.swift` entrega el instante del toque a `registerPad`.
  `TouchHostClock` lo convierte al reloj de audio; después `submitPracticeInput`
  usa ese instante para admitirlo en la generación actual. La reproducción del
  sonido ocurre antes de esperar al resultado del scorer.
- **Finalización o interrupción:** en macOS sigue `finishPractice` y
  `leaveActiveScreen` en `main.swift`; en iOS, `finishPractice`, `pausePractice`
  y `cancelActivePractice` en `XRolliOSApp.swift`. Finalizar y cancelar no son
  equivalentes: solo una sesión cuya duración se ha completado puede acreditar
  el intento, y los callbacks tardíos no deben reabrirla.

## Cómo leer el resultado y el progreso

- `RhythmScoring.swift` distingue golpes asociados, fallos y toques extra; una
  nota consume como máximo un golpe. Velocity se conserva, pero no se puntúa.
- `PracticeTools.swift` y `TrainingDiagnostics.swift` construyen resúmenes y
  recomendaciones a partir de los resultados, no de la animación.
- `ProgressStore.swift` guarda intentos en SQLite. Las lecturas y exportaciones
  de la interfaz usan conexiones propias en segundo plano; la importación JSON
  es transaccional y no reemplaza parcialmente el historial si falla. El ID de
  ejercicio no admite caracteres nulos: la API C de SQLite los truncaría.
- `CourseGraph.swift` y los criterios de `PracticeTools.swift` proyectan el
  recorrido ferroviario desde la evidencia. Las rutas de género usan el tempo
  fijo de su MIDI; los premios no cambian ese tempo.

## Antes de cambiar algo

Consulta las decisiones vigentes: D-033/D-034 y D-052 para carriles y feedback,
D-046 para el curso, D-048 para pads táctiles, D-057 para Inicio/Equipo y D-058
para tempos. No traslades lógica de puntuación a SpriteKit ni añadas trabajo
pesado al callback MIDI. Si se modifica la ruta de audio, suspende antes la
entrada MIDI y conserva la sincronización del motor.

Desde la raíz, `swift build`, `swift test` y `swift run xroll-preflight`
comprueban compilación, núcleo y recursos. La compilación de SwiftPM no verifica
el destino iOS: su comando y las pruebas de simulador están en `docs/IOS_BUILD.md`.
Ninguna prueba automatizada sustituye las comprobaciones físicas pendientes de
`docs/RELEASE_CHECKLIST.md`.
