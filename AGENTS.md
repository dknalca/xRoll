# xRoll: guía rápida para agentes

## Fuentes de verdad

- Lee `CLAUDE.md` antes de cambiar código. El estado actual y las comprobaciones pendientes están en `docs/IMPLEMENTATION_ROADMAP.md` y `docs/RELEASE_CHECKLIST.md`; `PLAN.md` es histórico.
- Si `docs/DECISIONS.md` bloquea un cambio, señala la decisión y su motivo en vez de sortearla.
- Documentación y comentarios en castellano; identificadores de código en inglés. Reglas de producto, audio y contenido: consulta `CLAUDE.md` y los documentos enlazados allí.

## Build y pruebas (raíz del repo)

- Es un único paquete SwiftPM, sin dependencias externas, con objetivo macOS 12. CI ejecuta `swift build` y después `swift test`.
- Para cambios del núcleo/recursos: `swift test --filter XRollCoreTests`.
- Tras cambiar `Resources/` o `data/exercises/`, ejecuta `swift run xroll-preflight` antes de probar la app.
- App: `swift run xroll-pads`. Bundle local: `scripts/build-app.sh` (reconstruye `dist/xRoll.app`; no reutilices una copia antigua). Las demás CLI y sus opciones están en `README.md`.

## Límites de arquitectura que afectan cambios

- `Sources/XRollCore` contiene el motor y los servicios compartidos; `Sources/XRollPads` contiene la app. `PracticeScene` renderiza estado y emite eventos: no es dueña del reloj ni del scoring.
- En la ruta CoreMIDI, el callback solo encola paquetes en `XRollRealtimeQueue`; el worker los decodifica y distribuye. No añadas logging ni trabajo pesado al callback.
- `MIDINoteOn.hostTime` es el instante de entrada canónico para puntuar. Los golpes vivos se reproducen inmediatamente; solo preview, loop y metrónomo se programan a host time futuro.
- No reconfigures audio mientras el worker MIDI esté activo. Mantén cada `SampleAudioEngine` en un único contexto de control.
- Las pruebas automatizadas no tienen hardware. Para diagnósticos, identifica el UID con `xroll-preflight`, limita la entrada con `--source <uid>` y usa `--check` cuando no deban esperarse golpes. No uses `--log-events` en diagnósticos de latencia; consulta `docs/LATENCY_PROTOCOL.md`.
- No afirmes latencia, FPS o precisión sin una medición reproducible. La validación manual pendiente está en `docs/RELEASE_CHECKLIST.md`.
