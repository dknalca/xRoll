# Arquitectura

`XRollCore` contiene recursos, MIDI, audio, reloj, puntuacion, calibracion y
SQLite. Los ejecutables de terminal son diagnosticos; `XRollPads` es la app
SwiftUI y SpriteKit.

## Tiempo y concurrencia

- `MIDINoteOn.hostTime` es el instante canónico de entrada. Se conserva hasta
  scoring, calibración e historial; la demora al pasar por la interfaz no forma
  parte del offset.
- El callback de CoreMIDI solo copia paquetes a una cola MPSC preasignada. Un
  worker fuera del callback decodifica eventos. En iOS, `iOSMIDIPlaybackBridge`
  resuelve y reproduce el golpe vivo antes de notificar la interfaz; después
  encola el golpe en `PracticeSessionIngress`. Los descartes por cola llena son
  diagnóstico, no una medida de latencia.
- `PracticeSessionIngress` serializa el scoring fuera de SwiftUI y SpriteKit. Al
  cerrar una generación procesa primero los golpes admitidos y entrega un score
  final estable; eventos tardíos de esa generación se rechazan.
- `SampleAudioEngine` serializa acceso a sus nodos con su cerrojo de control.
  Ningún callback CoreMIDI programa AVAudioEngine directamente y no se
  reconfigura la ruta mientras el worker MIDI está activo.
- La aplicación iPad encola feedback puntuado; `PracticeScene.update(_:)` lo
  consume con el reloj visual del frame. La presentación conserva el `hostTime`
  de entrada y no modifica el scoring.
- Los golpes vivos se reproducen inmediatamente; `hostTime` conserva su
  procedencia temporal y no se usa para programar un buffer en un instante ya
  pasado. Preview, loop y metrónomo sí se programan contra host time futuro.

Para añadir un kit, crea `Resources/Kits/<id>/kit.json`, declara cada WAV y
anota licencia y autor. Para añadir un ejercicio, genera un MIDI consecutivo en
`data/exercises/`: una dificultad nueva por nivel y solo sonidos declarados por
el kit. Ejecuta `swift run xroll-preflight` antes de usarlo.

## Componentes implementados

- `XRollCore`: recursos, reloj, scoring, calibración, sesiones, currículo,
  layouts, persistencia SQLite, diagnóstico y recomendaciones.
- `XRollPads`: aplicación SwiftUI, navegación y coordinación del ciclo de vida.
- `PracticeScene`: render SpriteKit sin lógica de scoring.
- `XRollRealtimeQueue`: cola MPSC usada por la entrada MIDI en tiempo real.

El diagnóstico histórico ya agrupa resultados por voz, mano, rol, pad,
subdivisión, vuelta y transición. No existen targets SwiftPM separados llamados
`XRollUI`, `LayoutEngine`, `DiagnosticEngine` o `RecommendationEngine`.

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

SpriteKit recibe estado de renderizado y emite eventos semánticos. El tiempo,
matching y score permanecen en `XRollCore`; el feedback visual se consume al
inicio de un frame.

## Fuente de verdad del contenido

- MIDI: fuente única de ejercicios integrados y comunitarios. Conserva tempo,
  compás, notas, velocity y detecta rejilla ternaria cuando corresponde.
- `.padmap` v2: layout y entrada física.
- Manifiesto de release: conteos de ejercicios, kits y sonidos.
