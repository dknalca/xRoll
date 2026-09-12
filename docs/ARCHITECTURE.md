# Arquitectura

`XRollCore` contiene recursos, MIDI, audio, reloj, puntuacion, calibracion y
SQLite. Los ejecutables de terminal son diagnosticos; `XRollPads` es la app
SwiftUI y SpriteKit.

## Tiempo y concurrencia

- `MIDINoteOn.hostTime` es el instante canónico de entrada. Se conserva hasta
  scoring, calibración e historial; la demora al pasar por la interfaz no forma
  parte del offset.
- El callback de CoreMIDI solo copia paquetes a una cola MPSC preasignada. Un
  worker fuera del callback decodifica eventos y llama a sus consumidores. Los
  descartes por cola llena son diagnóstico, no una medida de latencia.
- `SampleAudioEngine` se confina a un único contexto de control por instancia.
  La app lo usa en main; las herramientas CLI lo preparan antes de conectar MIDI
  y su worker de entrada emite los golpes vivos. No se reconfigura audio mientras
  ese worker está activo.
- Los golpes vivos se reproducen inmediatamente; `hostTime` conserva su
  procedencia temporal y no se usa para programar un buffer en un instante ya
  pasado. Preview, loop y metrónomo sí se programan contra host time futuro.

Para añadir un kit, crea `Resources/Kits/<id>/kit.json`, declara cada WAV y
anota licencia y autor. Para añadir un ejercicio, genera un MIDI consecutivo en
`data/exercises/`: una dificultad nueva por nivel y solo sonidos declarados por
el kit. Ejecuta `swift run xroll-preflight` antes de usarlo.

## Módulos objetivo

- `XRollCore`: recursos, reloj, scoring, calibración, sesiones, currículo y compatibilidad.
- `XRollUI`: tokens y componentes SwiftUI.
- `XRollPads`: aplicación y navegación.
- `PracticeScene`: render SpriteKit sin lógica de scoring.
- `LayoutEngine`: presets, `.padmap` v2, orientación, roles y resolución de entradas.
- `DiagnosticEngine`: métricas por voz y sesgo temporal persistidas por intento;
  el desglose por rol, subdivisión, vuelta y transición es la siguiente capa.
- `RecommendationEngine`: reglas de siguiente microtarea.

## Estado de práctica

```swift
enum PracticePhase {
    case preparing
    case preview
    case countIn
    case playing
    case paused
    case completing
    case finished(SessionResult)
}
```

SpriteKit recibe estado de renderizado y emite eventos semánticos. El tiempo, matching y score permanecen en `XRollCore`.

## Fuente de verdad del contenido

- MIDI: fuente única de ejercicios integrados y comunitarios. Conserva tempo,
  compás, notas, velocity y detecta rejilla ternaria cuando corresponde.
- `.padmap` v2: layout y entrada física.
- Manifiesto de release: conteos de ejercicios, kits y sonidos.
