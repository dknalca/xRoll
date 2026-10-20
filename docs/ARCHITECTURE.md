# Arquitectura

`XRollCore` contiene recursos, MIDI, audio, reloj, puntuacion, calibracion y
SQLite. Los ejecutables de terminal son diagnosticos; `XRollPads` es la app
SwiftUI y SpriteKit.

## Tiempo y concurrencia

- `MIDINoteOn.hostTime` es el instante canónico de entrada. Se conserva hasta
  scoring, calibración e historial; la demora al pasar por la interfaz no forma
  parte del offset.
- El callback de CoreMIDI solo copia paquetes a una cola MPSC preasignada. Un
  worker fuera del callback decodifica eventos. En ambas plataformas se resuelve
  y reproduce el golpe vivo, y se admite en `PracticeSessionIngress` desde ese
  worker antes de notificar la interfaz. Los descartes por cola llena
  son diagnóstico, no una medida de latencia.
- `PracticeSessionIngress` serializa el scoring fuera de SwiftUI y SpriteKit. Al
  cerrar una generación procesa primero los golpes admitidos y entrega un score
  final estable; eventos tardíos de esa generación se rechazan.
- La admisión de host time conserva reloj y generación bajo un mismo cerrojo;
  los eventos anteriores al arranque no entran en una sesión reiniciada. La
  interfaz solo consume resultados inmutables y descarta feedback de generaciones
  anteriores, también al pausar, navegar o cambiar de ruta.
- macOS recoge las asociaciones brutas de calibración en el procesador serial,
  sin limitarse a las ventanas del scorer. La calibración usa siempre guía
  visible y claqueta continua, independientemente de las ayudas de práctica.
- `SampleAudioEngine` serializa acceso a sus nodos con su cerrojo de control.
  Ningún callback CoreMIDI programa AVAudioEngine directamente y no se
  reconfigura la ruta mientras el worker MIDI está activo.
- Las notas programadas usan voces separadas de los golpes vivos. El charles
  conserva el choke de articulación tanto en golpes vivos como en preview y
  acompañamiento: las voces vivas se paran inmediatamente; los golpes futuros se
  preparan con la cola recortada al siguiente evento del grupo para mantener cada
  inicio en su host time sin superponer colas ni acumular buffers.
- La aplicación iPad encola feedback puntuado; `PracticeScene.update(_:)` lo
  consume con el reloj visual del frame. La presentación conserva el `hostTime`
  de entrada y no modifica el scoring.
- Los golpes vivos rotan por un pool acotado; el motor conserva una única voz
  activa por sonido o grupo y corta solo la anterior. El nodo elegido para el
  ataque nuevo no pasa por `stop()` en esa llamada. Las pruebas de PCM usan el
  mismo motor con renderizado manual, sin conectar una salida física.
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

La selección de mitades de una frase y el cálculo de compases completados se
comparten en `PracticeConfiguration` y `PracticeCompletion`. Cambiar de ejercicio
abandona el intento activo; una interrupción no acredita duración ni currículo.
La escena actualiza las formas animadas de racha solo al cambiar su fase y limita
las partículas a hitos de racha; los impactos y el feedback temporal permanecen
en cada golpe.

La continuación de Resultados y la recomendación curricular pertenecen a
`CourseRecommendationPlanner`: respetan el orden topológico de los estados de
`CourseGraph`, omiten bloques acreditados y no cruzan un bloque pendiente.
Los coordinadores de macOS e iOS seleccionan esa tarea y arrancan directamente
la práctica guiada. La preparación de una prueba final es una acción distinta:
presenta el objetivo y el patrón integrador antes de empezar.
