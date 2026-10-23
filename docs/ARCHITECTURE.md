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
- La ganancia de cada evento programado queda incorporada en PCM inmutable;
  los nodos de su pool no cambian de volumen por nota. Una caché LRU de 64
  entradas/4 MiB reutiliza segmentos por fuente, frames y ganancia; no participa
  en golpes vivos y se invalida al recargar las fuentes.
- Los golpes vivos se reproducen inmediatamente; `hostTime` conserva su
  procedencia temporal y no se usa para programar un buffer en un instante ya
  pasado. Preview, loop y metrónomo sí se programan contra host time futuro.
- El choke entre repeticiones vivas del mismo sonido consulta el reloj de
  muestras del nodo: no cancela un ataque admitido que aún no llegó al render.
  Abierto/cerrado siguen cortándose entre sí; los relojes inválidos anteriores
  al primer render no se entregan a `playerTime(forNodeTime:)`.

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
Un checkpoint adelantado conserva su evidencia y `CourseGraph.pendingChapter`
identifica el primer bloque anterior pendiente. Las dos interfaces explican su
nombre y permiten abrir una lección pendiente de ese bloque.

`CourseGraph.worlds(evidence:)` proyecta el recorrido de quince estaciones sobre
esos mismos estados; `CourseWorld` conserva su nombre histórico y describe los
niveles locales, reto final y tarea recomendada de cada estación.
Los coordinadores conservan la proyección tras refrescar el historial. La
victoria nueva se obtiene con `worldVictory(completing:previousEvidence:)` después
de guardar el intento. No requiere otra tabla de progreso. Las vistas presentan
el mapa y la celebración; las acreditaciones continúan en el núcleo.
`campaignContinuation(after:evidence:)` decide la continuación de un intento
aprobado de la estación actual, con el mismo 70 % y sin depender de dos estrellas.

`Sources/XRollPads/CourseRailwayMap.swift` se compila tanto en SwiftPM como en el
target iOS. Contiene el mapa ferroviario, los marcadores, los premios y los paneles
de nivel/estación completados. `RhythmMetroView` y `iOSHomeView` aportan los mismos
datos del núcleo y adaptan sus acciones. Los textos de reto y continuación son
compartidos; el historial y el catálogo permanecen en los servicios existentes.

`CourseLessonCriteria.preparationStep` comparte el tempo inicial: una lección
pendiente usa el tempo que acredita su objetivo. `recovery(for:attempt:evidence:)`
describe el apoyo automático del mismo patrón con guía completa, prácticas breves
y retorno de 2–4 BPM al objetivo. Los coordinadores conservan esa sugerencia solo
para el resultado actual y aplican la misma acción en ambas apps. La recuperación
se calcula sobre la lección MIDI original, no sobre su copia ralentizada.
`PracticeConfiguration.calibrationExercise(from:)` aísla el charles del MIDI de
corcheas sin mantener una lección curricular de una sola voz.

La selección de pads táctiles se deriva de los objetivos con
`PadMapV2.practicePads(for:)`, conservando los pads originales y los destinos
exactos por rol/pad. iOS guarda esa selección al comenzar cada sesión, por lo que
no cambia al avanzar de compás. `TouchPadGridLayout` comparte las celdas virtuales
entre dibujo, toques y accesibilidad; no altera las coordenadas físicas de Equipo.
El tamaño del panel depende de las voces y la orientación. Al reconstruir la
escena tras un giro, la etiqueta de racha se desliga de su panel anterior antes
de volver a insertarse, conservando la sesión y evitando un segundo padre SpriteKit.
