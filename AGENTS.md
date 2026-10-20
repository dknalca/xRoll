# xRoll: instrucciones para agentes

## Fuentes del proyecto

- Antes de tocar código, lee `CLAUDE.md` y consulta `docs/IMPLEMENTATION_ROADMAP.md`, `docs/RELEASE_CHECKLIST.md` y `docs/DECISIONS.md`; no rodees una decisión sin explicar por qué dejó de aplicar.
- Revisa las decisiones posteriores que sustituyan reglas antiguas: D-033/D-034 cambian el gameplay a una pista por sonido, sin indicación de manos; la rejilla física de Equipo conserva sus 16 posiciones.
- Documentación y comentarios en castellano; identificadores en inglés.

## Build y pruebas (desde la raíz)

- SwiftPM requiere macOS 12+ y no tiene dependencias externas. CI ejecuta `swift build`, `swift test` y `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`, en ese orden.
- Solo hay un target de pruebas, `XRollCoreTests`: `swift test --filter XRollCoreTests`. Para un caso concreto: `swift test --filter ResourceModelsTests/testLoadsTheBundledMIDIExerciseCatalog`.
- Tras cambiar `Resources/` o `data/exercises/`, ejecuta `swift run xroll-preflight` antes de probar la app.
- Ejecuta las CLI y `swift run xroll-pads` desde la raíz: buscan `Resources/` y `data/` en el directorio de ejecución, no en recursos SwiftPM. `scripts/build-app.sh` reconstruye `dist/xRoll.app` y reemplaza sus recursos empaquetados.
- iOS usa `xRoll.xcodeproj`, scheme `xRoll` y deployment target 16.2 (SwiftPM declara 16). Comandos de simulador, firma e instalación: `docs/IOS_BUILD.md`.
- Las opciones de las CLI están en `README.md`. Las pruebas automatizadas no requieren hardware; los diagnósticos MIDI físicos sí.

## Límites que afectan cambios

- `Sources/XRollCore` contiene dominio y servicios; `Sources/XRollPads/main.swift` coordina macOS e `iOS/XRolliOSApp.swift` coordina iOS. `PracticeScene` presenta la línea temporal y feedback; reloj, matching y scoring pertenecen al núcleo.
- iOS compila las mismas fuentes del núcleo y algunas de `XRollPads` mediante listas explícitas en `xRoll.xcodeproj/project.pbxproj`; al añadir o retirar fuentes compartidas, actualiza también esas listas. `swift build` no comprueba el target iOS.
- `PracticeSessionIngress` serializa el scoring fuera de la interfaz; al cerrar una generación, procesa primero los golpes admitidos y rechaza los tardíos. Conserva esa barrera al cambiar el ciclo de sesión.
- El callback `midiReadProc` solo encola paquetes; decodificación y consumidores corren fuera de él. No añadas logging, I/O, espera ni trabajo pesado o asignaciones evitables al callback.
- `MIDINoteOn.hostTime` es el instante de entrada canónico para puntuar. Los golpes vivos se reproducen inmediatamente; preview, loop y metrónomo usan programación a host time futuro.
- Suspende la entrada MIDI antes de reconfigurar audio. `SampleAudioEngine` serializa sus nodos y estado mutable; conserva una política explícita de acceso al modificarlo.
- Para diagnóstico MIDI con hardware, identifica el UID con `xroll-preflight` y usa `--source <uid>`; usa `--check` si no se esperan golpes. Al medir latencia no uses `--log-events`; sigue `docs/LATENCY_PROTOCOL.md`.
- No afirmes latencia, FPS ni precisión sin medición reproducible. Las comprobaciones manuales pendientes están en `docs/RELEASE_CHECKLIST.md`.

## Contenido

- Los ejercicios integrados y comunitarios son MIDI; no añadas un catálogo JSON paralelo. Los metadatos curriculares viajan en el MIDI y los valida `CurriculumValidator`; consulta `docs/EXERCISES.md`.
- Los sonidos y WAV se resuelven desde `kit.json`, sin nombres de audio en código. Registra todo audio añadido en `Resources/Loops/ATTRIBUTION.md` en el mismo commit.
