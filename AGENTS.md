# xRoll: instrucciones para agentes

## Fuentes de verdad

- Lee `CLAUDE.md` antes de cambiar código y consulta `docs/IMPLEMENTATION_ROADMAP.md` y `docs/RELEASE_CHECKLIST.md` para el estado y las comprobaciones pendientes.
- Si `docs/DECISIONS.md` bloquea un cambio, señala la decisión y su motivo en vez de sortearla. Reglas de producto adicionales: `CLAUDE.md` y los documentos que referencia.
- Documentación y comentarios en castellano; identificadores de código en inglés.

## Build y pruebas (raíz del repo)

- El paquete SwiftPM no tiene dependencias externas. CI ejecuta, en orden, `swift build` y `swift test`; para el núcleo usa `swift test --filter XRollCoreTests`.
- Tras cambiar `Resources/` o `data/exercises/`, ejecuta `swift run xroll-preflight` antes de probar la app.
- App macOS: `swift run xroll-pads`. Bundle local: `scripts/build-app.sh`; reconstruye `dist/xRoll.app` y reemplaza sus recursos empaquetados.
- La app iOS se compila desde `xRoll.xcodeproj` (scheme `xRoll`), compartiendo las fuentes del núcleo; consulta `docs/IOS_BUILD.md` para comandos, firma e instalación.
- Las CLI y sus opciones están en `README.md`. Las pruebas automatizadas no requieren hardware; los diagnósticos MIDI sí.

## Límites de arquitectura que afectan cambios

- `Sources/XRollCore` contiene motor y servicios; `Sources/XRollPads` contiene la app macOS y su entrada (`main.swift`). `PracticeScene` presenta estado y emite eventos: no es dueña del reloj ni del scoring.
- En la ruta CoreMIDI, el callback solo encola paquetes en `XRollRealtimeQueue`; el worker los decodifica y distribuye. No añadas logging ni trabajo pesado al callback.
- `MIDINoteOn.hostTime` es el instante de entrada canónico para puntuar. Los golpes vivos se reproducen inmediatamente; solo preview, loop y metrónomo se programan a host time futuro.
- No reconfigures audio mientras el worker MIDI esté activo. Mantén cada `SampleAudioEngine` en un único contexto de control.
- Para diagnóstico con hardware, identifica el UID con `xroll-preflight` y limita la entrada con `--source <uid>`; usa `--check` cuando no deban esperarse golpes. No uses `--log-events` al medir latencia; sigue `docs/LATENCY_PROTOCOL.md`.
- No afirmes latencia, FPS o precisión sin una medición reproducible. Las pruebas manuales pendientes están en `docs/RELEASE_CHECKLIST.md`.
