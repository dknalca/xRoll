---
name: xroll-realtime-audio-midi
description: Use when changing AVAudioEngine, Core Audio, CoreMIDI, Bluetooth MIDI, AudioClock, SampleAudioEngine, MIDIInput, device selection, or latency tools in xRoll.
---

# Audio y MIDI realtime de xRoll

Lee `AGENTS.md`, `CLAUDE.md`, `docs/LATENCY_PROTOCOL.md` y `docs/SCORING.md` antes de cambiar la ruta temporal.

## Arquitectura que se debe conservar

- `AudioClock` convierte el host time de Core Audio y es el reloj común para audio programado, práctica y SpriteKit. No sustituyas esta referencia por `Timer`, `Date` ni un reloj de interfaz.
- `SampleAudioEngine` posee el único `AVAudioEngine`: buffers PCM, voces de cada sample, loop y metrónomo. No hay un callback de render propio de xRoll.
- Los golpes en vivo usan `play(soundID:)`; la preescucha, acompañamiento y metrónomo se programan mediante `AVAudioTime(hostTime:)`.
- `MIDIInputSession` recibe `MIDINoteOn` desde CoreMIDI; conserva `hostTime`, canal, nota y velocity. `PadMapV2Router` tiene prioridad sobre el fallback GM.
- La app mueve los eventos MIDI a la cola principal antes de tocar estado SwiftUI, SpriteKit y nodos de audio. Si se cambia ese límite, documenta el contexto de ejecución y demuestra que no degrada el timing.

## Reglas de tiempo y concurrencia

- Trata `midiReadProc` como una ruta sensible a tiempo: no añadas logging, I/O, trabajo pesado, espera ni asignaciones evitables en el callback.
- No supongas que `SampleAudioEngine` es seguro para llamadas concurrentes. Mantén una única política explícita de acceso al modificar sus nodos o estado mutable.
- Conserva la política de voces: un golpe reciente interrumpe una cola o cola larga anterior; no puede quedar en espera detrás de un sample sostenido.
- No presentes `presentationLatency` como latencia total. La latencia extremo a extremo se obtiene solo con el protocolo de grabación física.
- Al tocar selección de salida, reconexión MIDI o perfiles de calibración, revisa que entrada, salida, frecuencia y buffer sigan identificando el mismo perfil.

## Verificación

1. Ejecuta `swift test --filter XRollCoreTests`.
2. Ejecuta `swift run xroll-preflight` para comprobar recursos, salida y UID de fuentes MIDI.
3. Para pruebas físicas, usa `swift run xroll-latency <sound-id> --source <uid>`; nunca `--log-events` durante una medición.
4. Si cambian timing, callback, buffer, dispositivo o scheduling, sigue `docs/LATENCY_PROTOCOL.md` y registra una medición reproducible antes de afirmar resultados.
