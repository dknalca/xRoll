# xRoll Agent Guide

## Antes de cambiar

- Lee `CLAUDE.md`: es el contrato de producto. Consulta `docs/IMPLEMENTATION_ROADMAP.md` y `docs/RELEASE_CHECKLIST.md` para el estado vigente; `PLAN.md` es histórico.
- xRoll es un entrenador de timing para principiantes, no un DAW ni un secuenciador. No añadas dependencias de ejecución, edición/exportación de audio ni funciones de velocity.
- La calibración guiada no es opcional: conserva el audio como reloj de referencia y no documentes métricas de latencia, FPS o precisión sin una medición reproducible.

## Desarrollo y validación

- Es un único paquete SwiftPM, sin dependencias externas, con mínimo macOS 12: `swift build` y `swift test` son las comprobaciones generales.
- Para el núcleo o los recursos, usa `swift test --filter XRollCoreTests`; los tests cargan el kit y el catálogo incluidos desde la raíz del repositorio.
- Tras cambiar `Resources/` o `data/exercises/`, ejecuta `swift run xroll-preflight`; valida `kit.json`, WAV y ejercicios antes de probar la app.
- Ejecuta la aplicación SwiftUI/SpriteKit con `swift run xroll-pads`. Crea el bundle distribuible con `scripts/build-app.sh`; empaqueta `Resources/` y `data/` en `dist/xRoll.app`.
- Las pruebas de MIDI/audio requieren hardware. Usa `swift run xroll-preflight` para obtener los UID de entrada y limita los diagnósticos internos con `--source <uid>`; no uses `--log-events` durante ellos.

## Arquitectura y contenido

- `Sources/XRollCore` posee recursos, CoreMIDI, AVAudioEngine, reloj, puntuación, calibración y SQLite. `Sources/XRollPads` es la app; `PracticeScene` solo renderiza y no debe asumir lógica de tiempo o scoring.
- Los ejercicios integrados son MIDI en `data/exercises/`. Deben ser 4/4, BPM fijo, usar el kit declarado y sonidos válidos; un nivel introduce una sola dificultad nueva.
- `kit.json` es la fuente de verdad para archivos de audio y notas GM: nunca nombres WAV en código. Los IDs de sonido son los canónicos de `docs/AUDIO.md` y usan minúsculas con guion bajo.
- La disposición visual procede del `.padmap` v2 y conserva las coordenadas físicas. No impongas un orden de pads en la interfaz ni alteres números/canales MIDI al aplicar layouts.
- Si añades audio, registra su autoría y licencia en `Resources/Loops/ATTRIBUTION.md` en el mismo cambio. Código, audio, gráficos y documentación: MIT.

## Convenciones

- Documentación y comentarios en castellano; identificadores de código en inglés.
- Si una decisión de `docs/DECISIONS.md` bloquea el cambio, señálalo explícitamente en lugar de sortearla.
