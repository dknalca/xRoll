# Estado de implementación

## Completado en código

- Metro del Ritmo de catorce estaciones en Curso de macOS/iOS: vías y tren en la
  parada actual, niveles locales y reto final de estación. El checkpoint usa
  su preparación y tempo de aprendizaje desde el mapa y desde Resultados.
- Mapa, acciones, premios y celebraciones compartidos en `CourseRailwayMap.swift`
  entre ambas apps. Una estación recién completada muestra tren, estrellas y
  «Siguiente parada». La proyección conserva el historial y está cubierta por
  pruebas de 70 %, práctica parcial, retos futuros, repetición y reapertura.
- Catálogo activo MIDI con 117 ejercicios sin patrones duplicados;
  la versión archivada se conserva fuera del catálogo activo.
- Revisión de géneros: Hip-hop, Rock y Funk conservan las habilidades al añadir
  variaciones; Jazz diferencia su ride del shuffle y Reggae ofrece grooves
  completos de dos compases desde el inicio y una frase final de cuatro.
- Ampliación de 40 lecciones: Hip-hop tiene 12; Rock, Disco, Funk, Reggae,
  Dembow, Blues, Jazz y Clave/Bossa tienen 8 cada uno. Los checkpoints integran
  las voces y posiciones rítmicas enseñadas y todas las rutas de género limitan
  la simultaneidad a dos sonidos. Los IDs históricos y sus registros se conservan.
- Duración MIDI inicial ajustada a unos ocho compases totales, sin multiplicar
  las frases por ocho vueltas. Preparación iOS centrada en la lección elegida,
  con nivel preparado, mejor nivel superado y duración total.
- Estrellas de intentos nuevos a 70/80/90 %; curso y retos de tempo siguen
  aprobándose con 70 %. Los resultados anteriores conservan sus estrellas.
- Choke vivo protege ataques del mismo sonido admitidos antes del siguiente
  render. Pruebas PCM cubren lotes y conversión 44,1→48 kHz; pendiente confirmar
  los cortes reportados en MIDI con salida Bluetooth de iPhone/iPad.
- Curso por bloques: iniciación, fundamentos, coordinación, subdivisión,
  grooves, Hip-hop, Rock, Funk, Blues/Shuffle, Jazz, Disco, Reggae, Dembow y
  Clave/Bossa.
- Preparación, ayudas completa/normal/reducida, capas, transferencia y ruta
  rápida de ritmo completo; las ayudas no alteran los objetivos puntuables.
- Escena SpriteKit, score no punitivo, reinicio rápido, duración 1/2/4/8/16 y
  cajones plegables de navegación/sesión.
- Entrada MIDI seleccionable y refrescable; salida de audio seleccionable;
  metrónomo, loop, compensación y calibración guiada.
- `.padmap` v2, Core, Drum Kit, Mirror, importación/exportación y
  objetivos por sonido/rol/pad.
- Historial SQLite, análisis por sonido, tendencia temporal, ejercicio más
  repetido, Autopilot, práctica correctiva y Ghost Coach básico; la gráfica usa
  los 20 intentos más recientes.
- Importación MIDI comunitaria con validación técnica, BPM fijo y avisos
  pedagógicos.
- Lectura de velocity y detección de rejilla ternaria de 12 pasos en MIDI.
- Rejilla ternaria nativa en las miniaturas y el generador curricular.
- Diagnóstico histórico derivado de `HitRecord` por mano, rol, pad,
  subdivisión, vuelta y transición; microscopio objetivo/ejecución.
- Rescate Whale: aislamiento de micro-célula alrededor de un error, tempo al
  80 % y acompañamiento del resto del compás.
- Microlección con instrucción concreta para la subdivisión detectada, práctica
  aislada y retorno al groove completo; las comparaciones solo afirman mejora
  cuando hay suficientes golpes comparables.
- Transferencia desde resultados con patrón completo, guía visual retirada y
  acción para volver a tocar con guía; mantiene el scoring de ritmo completo y
  solo compara rondas con condiciones equivalentes.
- Conservación de velocity MIDI para compatibilidad futura y cuatro sellos de
  dominio: precisión, elasticidad, pulso interno y memoria.
- Curso guiado con exploración libre, checkpoints MIDI por capítulo y evidencia
  curricular consultada sobre el historial completo; los tempo-awards siguen
  perteneciendo solo al tempo realmente superado.
- Continuación compartida por orden topológico: no vuelve a bloques acreditados
  ni atraviesa bloques pendientes. Resultados encadena la práctica directamente;
  la prueba final presenta primero su resumen y patrón integrador.
- Audio vivo con rotación acotada y choke de la voz activa anterior, cubierto por
  pruebas de PCM offline; validación acústica iPhone/iPad aún pendiente.
- Audio programado y claqueta con ganancia inmutable por evento; segmentos
  recortados reutilizables en caché LRU de 64 entradas/4 MiB y pruebas de PCM
  para ráfagas, alternancia de charles, cancelación y reutilización de nodos.
- Los resultados de checkpoint adelantado identifican el primer bloque pendiente
  y permiten abrirlo conservando la evidencia. Diez pruebas UI cubren las rutas
  de Resultados, preparación y recorrido ferroviario en el simulador iOS.
- Resultado ofrece una vía opcional al siguiente ejercicio tras dos estrellas en
  ritmo completo, sin acreditar ni saltar requisitos del curso. Las filas del
  curso muestran el premio más alto ganado; los trofeos sustituyen visualmente a
  las estrellas anteriores.
- El coaching correctivo exige errores repetidos en el mismo sonido y paso; la
  comparación al volver al groove solo se hace con condiciones completas
  equivalentes. Los objetivos se conservan en SQLite y se vuelven a comprobar
  con repasos espaciados.
- Pulso interno ofrece cinco etapas de retirada de ayudas. Cada etapa requiere
  dos intentos equivalentes; las etapas con silencios también requieren deriva
  estable. El resultado muestra desfase por pulso y distingue los silencios.
- La sesión diaria breve combina entrada conocida, repaso vencido, reto curricular
  e integración; conserva bloques completados, omitidos y pendientes para poder
  retomarla durante el mismo día.

## Próxima capa técnica

- Presets específicos por modelo de controlador, respaldados por pruebas reales.
- Análisis fino de ghost notes y articulación cuando haya ejercicios MIDI que
  definan esas expectativas de forma consistente.

## Validación manual obligatoria antes de publicar

- Medir 60 FPS con la escena de máxima densidad durante diez minutos.

## Validación manual completada

- Reconexión MIDI, Core, Drum Kit y Mirror comprobados en hardware.
- Diez minutos de práctica densa sin cortes ni tirones perceptibles.
- VoiceOver, Reduce Motion, contraste y teclado comprobados en macOS.
- Licencias de los WAV distribuidos confirmadas como propias.
- Licencias de los loops distribuidos confirmadas como propias.
- Calibración guiada comprobada para la ruta de uso actual.
