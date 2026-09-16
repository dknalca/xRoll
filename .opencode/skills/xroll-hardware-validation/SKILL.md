---
name: xroll-hardware-validation
description: Use when validating MIDI controllers, Bluetooth MIDI, audio outputs, latency, performance, accessibility, or release-blocking manual checks for xRoll.
---

# Validación física de xRoll

Lee `docs/RELEASE_CHECKLIST.md` y `docs/LATENCY_PROTOCOL.md`. Esta skill verifica hardware real; no sustituye pruebas automatizadas por conclusiones de escritorio.

## Preparación

1. Ejecuta `swift build`, `swift test` y `swift run xroll-preflight` desde la raíz.
2. Anota la fuente MIDI, UID, salida de audio, frecuencia y buffer que informa preflight.
3. Selecciona una sola fuente con `--source <uid>` cuando haya más de un controlador.
4. No uses `--log-events` durante una medición de latencia: añade trabajo al callback MIDI.

## Prueba de latencia

- Sigue exactamente `docs/LATENCY_PROTOCOL.md`: 100 golpes aislados, grabación externa sin editar, mismo micrófono para pad y altavoz.
- Conserva el audio original en `data/measurements/` y guarda el informe como `latency_YYYY-MM-DD.md` con perfil, mediana, percentil 95, mínimo, máximo y hash si el audio queda fuera de Git.
- No confundas la latencia de presentación de Core Audio con el resultado extremo a extremo.

## Pruebas de interacción requeridas

- Reinicia la app y confirma persistencia y reconexión de MIDI.
- Comprueba teclado, preview y práctica con las salidas reales previstas.
- Prueba Core, Drum Kit y Mirror: el pad iluminado, el sonido reproducido y el número/canal MIDI físico deben coincidir.
- Ejecuta diez minutos de práctica densa y registra cortes o degradación perceptible de SpriteKit.
- En macOS real, comprueba VoiceOver, Reduce Motion, contraste y teclado.

## Resultado

- Documenta solo observaciones reproducibles, incluidas condiciones y hardware.
- Si falla una prueba de la checklist, no la marques como superada ni la sustituyas por una estimación de software.
