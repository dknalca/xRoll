# Inicio y trabajo evitable durante la práctica

## Cambios

- **Referencia inicial opcional (D-060):** interruptor persistente en Preparación
  y Ajustes/Opciones, apagado por defecto. Se conserva la escucha manual.
- **Reintentos sin escucha repetida:** repetir, reiniciar y reanudar mantienen
  la cuenta de entrada, pero no la demostración del intento anterior. El token
  o generación anterior sigue invalidado antes del nuevo intento.
- **Duraciones sin expandir notas:** `ExerciseTiming` comparte la misma aritmética
  de compás/patrón entre timeline y referencia. Preparar la referencia deja de
  crear y ordenar dos arrays de notas solo para consultar duraciones.
- **Reserva de almacenamiento:** `ExerciseTimeline` reserva la capacidad conocida
  de notas × repeticiones antes de rellenar su array.
- **Ordenación por patrón:** la timeline ordena una sola vuelta, después de aplicar
  el offset, y la expande sin ordenar otra vez todas las repeticiones. Para los
  ejercicios validados, cada nota pertenece a su frase y las vueltas no se solapan.
  Se mantienen los índices originales y el desempate por índice de notas simultáneas.
  Una sesión de una sola vuelta reutiliza directamente el patrón ordenado.
- **Cierre y recomendación sin timelines auxiliares:** `PracticeCompletion` y
  `NextSessionPlanner` consultan `ExerciseTiming` sin generar notas para calcular
  compases completados o duración estimada.
- **Sin acompañamiento vacío en iOS:** cuando el ejercicio completo y el puntuado
  contienen las mismas notas, no se construye otra timeline ni se recorren todas
  sus repeticiones para terminar programando cero notas de acompañamiento.
- **Actualización táctil agrupada:** `TouchGridView.configure` actualiza el callback
  siempre, pero reconstruye accesibilidad una sola vez si cambian pads/etiquetas.
  No solicita redibujado si SwiftUI solo entrega un callback/estado nuevo sin
  cambiar pads, etiquetas o columnas. Los toques y el fin de su destello, el giro
  y los cambios de tamaño de texto siguen invalidando la presentación.

## Límites

No se han modificado el callback CoreMIDI, el motor de audio, la admisión serial,
la compensación ni las reglas de scoring. Los cambios reducen operaciones
identificadas en el código; no equivalen a una medición de CPU, memoria, latencia
o FPS. Siguen pendientes los perfiles de Instruments y las comprobaciones
acústicas/visuales en hardware de `RELEASE_CHECKLIST.md`.

## Verificación

`PracticeStartupTests` compara las duraciones, notas expandidas y fronteras de la
referencia con los cálculos anteriores, incluyendo rejillas 12/16, varios tempos,
frases largas, 16 repeticiones y límites de cuenta de entrada. La suite UI añade
apagado persistente, escucha manual con la preferencia apagada y reanudación sin
reactivar la referencia antigua. Las fixtures no validan calibración física.

Verificado en esta pasada: compilación macOS y arranque básico, compilación
genérica iOS sin firma, `swift test` (227 pruebas sin fallos), preflight (129
ejercicios y 10 sonidos) y `git diff --check`. La comprobación de la preferencia
y los reintentos pasó en la suite completa de 30 pruebas de interfaz iOS. Tras el
último ajuste de redibujado por cambio de tamaño se repitieron los cinco casos de
preferencia/reinicio/escucha explícita, giro y ocho pads: todos pasaron. No es una
medición de rendimiento ni una validación de hardware.

### Ampliación: construcción de timelines y cálculos de duración

`TimelineConstructionTests` conserva el algoritmo anterior como oráculo y compara
el array completo, incluidos tiempos, índices, pasos, manos, destinos y velocity.
Recorre las 129 lecciones con 1/4/16 vueltas y offsets 0/1/último paso; añade casos
de rejilla 12/16, notas desordenadas y simultáneas, patrón vacío y cero vueltas.
`PracticeStartupTests` comprueba también fronteras exactas de cierre de compás y
duraciones de recomendación. No se modifican las reglas ni las ventanas de score.

La ampliación pasa 232 pruebas con `swift test` y compila tanto en SwiftPM como
en el destino genérico iOS. También pasa la suite completa de 30 pruebas de
interfaz en el simulador iOS, sobre esta misma versión del núcleo.
