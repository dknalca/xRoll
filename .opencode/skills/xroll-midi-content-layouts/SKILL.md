---
name: xroll-midi-content-layouts
description: Use when changing MIDI exercises, kit.json, pad maps, PadMapV2, layouts, controller mappings, curriculum generators, or sound identifiers in xRoll.
---

# Contenido MIDI y layouts de xRoll

Lee `docs/AUDIO.md`, `docs/EXERCISES.md`, `docs/MIDI_MAPPING.md`, `docs/PADMAP_V2.md`, `docs/PAD_LAYOUTS.md` y `docs/DECISIONS.md` antes de modificar contenido o mapeos.

## Fuentes de verdad

- Los ejercicios integrados son archivos `.mid` o `.midi` en `data/exercises/`; no crees un catálogo JSON paralelo.
- `kit.json` declara los archivos WAV y sus notas GM. Ningún nombre de WAV debe aparecer en código.
- Los IDs de sonido son los canónicos de `docs/AUDIO.md`: minúsculas y guion bajo.
- `.padmap` v2 separa sonido, posición física, rol e input MIDI. Un layout puede reasignar sonido y rol, pero conserva número y canal MIDI físicos.

## Reglas didácticas y de layout

- Un ejercicio integrado debe usar 4/4, BPM fijo, kit declarado, sonidos válidos y pasos dentro de la rejilla detectada.
- Cada nivel introduce una sola dificultad principal. Revisa la progresión del catálogo, no solo la validez técnica del archivo nuevo.
- Conserva los huecos y coordenadas físicas; no comprimas la matriz visual ni impongas una secuencia fija de pads en la UI.
- Los objetivos `any`, por rol y por pad tienen semánticas diferentes. Los duplicados son válidos solo cuando el objetivo lo permite; una entrada MIDI física sigue siendo única.
- MIDI velocity puede leerse y preservarse, pero no debe alterar requisitos ni puntuación de ejercicios todavía.

## Verificación

1. Regenera el MIDI con el script curricular correspondiente si el contenido procede de un generador; no edites su salida y generador de forma divergente.
2. Ejecuta `swift run xroll-preflight` tras cambiar `data/exercises/`, `Resources/` o `kit.json`.
3. Ejecuta `swift test --filter XRollCoreTests` para validar catálogo, rutas y layouts.
4. Para un controlador real, descubre el UID con preflight y usa `swift run xroll-map-pads --source <uid> --output <archivo.padmap>` antes de afirmar compatibilidad.
