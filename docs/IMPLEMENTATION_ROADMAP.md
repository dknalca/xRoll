# Estado de implementación

## Completado en código

- Catálogo activo MIDI con 64 ejercicios sin variantes duplicadas;
  la versión archivada se conserva fuera del catálogo activo.
- Curso por bloques: iniciación, fundamentos, subdivisión, coordinación,
  grooves, Hip-hop, Rock, Funk, Blues/Shuffle y Jazz.
- Preparación, ayudas completa/normal/reducida, capas, transferencia y ruta
  rápida de ritmo completo.
- Escena SpriteKit, score no punitivo, reinicio rápido, duración 1/2/4/8/16 y
  cajones plegables de navegación/sesión.
- Entrada MIDI seleccionable y refrescable; salida de audio seleccionable;
  metrónomo, loop, compensación y calibración guiada.
- `.padmap` v2, Core, Drum Kit, Mirror, orientación, importación/exportación y
  objetivos por sonido/rol/pad.
- Historial SQLite, análisis por sonido, tendencia temporal, ejercicio más
  repetido, Autopilot, práctica correctiva y Ghost Coach básico.
- Importación MIDI comunitaria con validación técnica y avisos pedagógicos.
- Lectura de velocity y detección de rejilla ternaria de 12 pasos en MIDI.
- Rejilla ternaria nativa en las miniaturas y el generador curricular.
- Diagnóstico histórico derivado de `HitRecord` por mano, rol, pad,
  subdivisión, vuelta y transición; microscopio objetivo/ejecución.
- Rescate Whale: aislamiento de micro-célula alrededor de un error, tempo al
  80 % y acompañamiento del resto del compás.
- Conservación de velocity MIDI para compatibilidad futura y cuatro sellos de
  dominio: precisión, elasticidad, pulso interno y memoria.

## Próxima capa técnica

- Presets específicos por modelo de controlador, respaldados por pruebas reales.
- Análisis fino de ghost notes y articulación cuando haya ejercicios MIDI que
  definan esas expectativas de forma consistente.

## Validación manual obligatoria antes de publicar

- Latencia física con el protocolo documentado, controlador y salida reales.
- Reconexión MIDI, Core/Drum Kit/Mirror y selección de interfaz en hardware.
- Diez minutos de práctica densa sin cortes y comprobación de 60 FPS.
- VoiceOver, Reduce Motion, contraste y teclado en macOS.
- Licencias de cada WAV y loop distribuido.
