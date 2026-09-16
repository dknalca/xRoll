---
name: xroll-app-architecture
description: Use when changing XRollPads, Model, SwiftUI views, navigation, app state, session orchestration, or boundaries between presentation and XRollCore in xRoll.
---

# Arquitectura de aplicación de xRoll

Lee `AGENTS.md`, `CLAUDE.md` y `docs/ARCHITECTURE.md` antes de cambiar `Sources/XRollPads`.

## Límites de responsabilidad

- `Model` es el coordinador de aplicación: compone servicios, mantiene estado observable y gobierna el ciclo de vida de la sesión. No es un contenedor para lógica de dominio o infraestructura nueva.
- Antes de añadir una responsabilidad a `Model`, comprueba si ya corresponde a `PracticeSession`, `SampleAudioEngine`, `ProgressStore`, `ResourceCatalog`, calibración, layouts o un servicio existente de `XRollCore`.
- Mantén el dominio en `XRollCore`. Esta capa no depende de SwiftUI, AppKit ni SpriteKit.
- Las vistas SwiftUI presentan estado y emiten acciones. No implementan scoring, MIDI, persistencia, carga de recursos ni programación temporal.
- `PracticeScene` renderiza la línea temporal y feedback visual. No debe decidir matching, scoring, calibración ni reglas didácticas.
- Amplía un servicio cohesionado existente antes de crear coordinadores o abstracciones paralelas.

## Tiempo y ciclo de vida

- No muevas callbacks MIDI, scheduling de audio ni trabajo realtime a `Model` o a una vista SwiftUI. El reloj es `AudioClock` y los servicios de CoreMIDI/AVAudioEngine pertenecen a `XRollCore`.
- La navegación debe cerrar una sesión activa: invalida callbacks diferidos y detiene sonidos programados y loop mediante el flujo existente de `leaveActiveScreen()`.
- Si extraes estado o coordinación desde `Model`, conserva la propiedad clara de MIDI, audio, escena, práctica y sus operaciones de parada.
- Evita duplicar transformaciones de ejercicios o políticas de práctica entre vistas y core; ubícalas en el componente que pueda reutilizarse sin presentación.

## Verificación

1. Ejecuta `swift test --filter XRollCoreTests` si cambia comportamiento compartido o de dominio.
2. Ejecuta `swift run xroll-pads` para cambios en sesión, navegación o presentación.
3. Durante una práctica, navega a otra sección y confirma que no queda loop, audio programado, escena ni resultado diferido activo.
4. Revisa que los cambios de UI no introduzcan dependencias de SwiftUI/AppKit/SpriteKit en `Sources/XRollCore`.
