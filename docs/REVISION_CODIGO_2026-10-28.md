# Revisión de código — 28 de octubre de 2026

## Alcance

Revisión dirigida de carga MIDI, puntuación y diagnóstico histórico, junto con
lectura de los límites entre práctica, audio, MIDI y presentación. No es una
auditoría exhaustiva de todos los archivos ni una validación con controlador
físico. Se conservaron los cambios que ya estaban sin confirmar en el repositorio.

## Hallazgos corregidos

1. **Un golpe en el primer instante de un compás podía quedar fuera del patrón.**
   `MIDIExerciseLoader` calculaba los compases redondeando hacia arriba el último
   tick. Si un Note On y el final de pista coincidían en el límite del compás,
   ese tick se trataba como final exclusivo y el paso siguiente fallaba la
   validación. Ahora se distingue el final de la pista del paso cuantizado de la
   última nota. Las pruebas cubren el límite exacto, el redondeo cercano y un
   final de pista que no debe crear un compás vacío.
2. **La mediana histórica podía indicar una dirección incorrecta.** Con un
   número par de desfases se elegía el valor central superior, no la mediana de
   ambos valores centrales. Por ejemplo, −20 y +20 ms producían «retrasado» en
   vez de «centrado». Se usa la mediana compartida y se añadió una regresión.
3. **El diagnóstico de transiciones recorría repetidamente golpes extra.** Se
   sustituyó la búsqueda del siguiente objetivo por un recorrido inverso que
   ignora extras y conserva la misma secuencia de transiciones. La prueba cubre
   extras entre dos objetivos y después del último.

## Comprensibilidad y mantenimiento

- `docs/GUIA_LECTURA_CODIGO.md` explica por dónde empezar y cómo pasa un golpe
  desde la entrada hasta la puntuación y el historial.
- `docs/ARCHITECTURE.md` ya no presenta `PracticePhase` como un enum existente:
  las fases son conceptuales y los coordinadores usan indicadores y tokens.
- Los comentarios nuevos explican los límites de compás, la mediana y el orden
  temporal del scorer, en lugar de repetir lo que indican los identificadores.
- `Sources/XRollPads/main.swift` e `iOS/XRolliOSApp.swift` siguen siendo
  coordinadores extensos. Conviene extraer responsabilidades de forma gradual,
  con pruebas de navegación y ciclo de sesión; no se ha intentado una
  reestructuración general durante esta revisión.

## Verificación y límites

- `swift test`: 214 pruebas, cero fallos.
- `swift run xroll-preflight`: 129 ejercicios válidos y 10 sonidos legibles.
- Compilación genérica iOS con `CODE_SIGNING_ALLOWED=NO`: correcta.
- No se han medido FPS ni latencia y no se han repetido las comprobaciones
  físicas de MIDI, Bluetooth, accesibilidad o calibración. Siguen en
  `docs/RELEASE_CHECKLIST.md`.

## Ampliación: historial, sesión y ruta MIDI/audio

Se revisaron la validación y el rollback de importaciones, el cierre serial de
sesión, la entrada táctil iOS y la ruta MIDI desde CoreMIDI hasta el worker.
La inspección también abarcó los límites de audio programado y los cambios de
ruta en los coordinadores. No equivale a recorrer cada interacción de las dos
apps ni a una prueba acústica o de controlador real.

### Hallazgos adicionales corregidos

1. **Identificadores con un NUL podían truncarse en SQLite.** La API C recibe
   el ID como cadena terminada en cero; un historial importado con `audit\u0000otro`
   se guardaba como `audit`. Ahora la validación rechaza ese identificador antes
   de escribir. La prueba cubre guardado individual, importación en memoria,
   JSON incremental y rollback completo. La misma restricción se aplica al
   cargar un ejercicio MIDI, para no aceptar uno cuyo progreso no pueda guardarse.
2. **El toque iOS no usaba la misma barrera temporal que MIDI.** El golpe
   táctil se convertía antes de entrar en `PracticeSessionIngress` mediante la
   variante que no recibe `hostTime`. Ahora se entrega el reloj original a la
   variante que comprueba la generación y convierte el tiempo bajo el mismo
   cerrojo; un toque anterior al reinicio no entra en la sesión nueva. El audio
   vivo sigue reproduciéndose antes de admitir el golpe. La prueba de núcleo
   comprueba rechazo de un toque anterior y conservación de pad, rol y velocity.

### Límites y observaciones

- El callback MIDI sigue encolando paquetes sin decodificar ni hacer I/O. Según
  el contrato de `MIDIPacket` de CoreMIDI, los mensajes son completos por
  paquete salvo SysEx; no se introdujo estado compartido entre fuentes.
- No se ha cambiado el scheduling, la selección de salida ni el choke del
  motor de audio. Las pruebas PCM no demuestran el comportamiento acústico de
  Bluetooth ni el tiempo extremo a extremo.
- La admisión temporal táctil está cubierta en el núcleo; la precisión del
  reloj táctil en un dispositivo físico sigue sin medirse en esta revisión.

### Comprobaciones de la ampliación

- `swift test`: 217 pruebas, cero fallos.
- `swift build` y `swift test --filter XRollCoreTests`: correctos; el filtro
  ejecutó 217 pruebas, sin fallos.
- Compilación genérica iOS con `CODE_SIGNING_ALLOWED=NO`: correcta.
- Cuatro pruebas XCUITest seleccionadas en simulador iOS: cero fallos. Cubren
  Equipo y calibración, el paso de vuelta acompañada a práctica puntuable,
  la interrupción durante la referencia y los pads táctiles tras girar la pantalla.
- `swift run xroll-preflight`: 129 ejercicios y 10 sonidos válidos; no se
  detectó ninguna fuente MIDI durante la ejecución.
- Las comprobaciones físicas de la checklist siguen pendientes. La compilación
  y las pruebas automatizadas no demuestran latencia, FPS ni respuesta acústica.
