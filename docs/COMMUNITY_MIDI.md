# Ejercicios MIDI de comunidad

xRoll carga ejercicios desde `data/exercises/` en formato Standard MIDI File
(`.mid` o `.midi`). No hace falta ningún JSON propio.

Desde la app, abre **Ajustes → Ejercicios MIDI comunitarios → Importar ejercicio
MIDI**. El archivo se valida y se copia al almacenamiento local de xRoll; queda
disponible en el curso sin bloquearse por el progreso del curso base.

## Reglas del archivo

- Compás 4/4.
- Pulsos por negra (PPQ), no timecode.
- Una pista con nombre: ese nombre se muestra como título del ejercicio.
- Metaevento de tempo. Si falta, xRoll usa 80 BPM.
- Notas de percusión General MIDI; se aceptan las del kit activo:

| Sonido | Nota GM |
| --- | ---: |
| Bombo | 36 |
| Caja | 38 |
| Palmada | 39 |
| Charles cerrado | 42 |
| Charles abierto | 46 |
| Tom grave | 41 |
| Tom agudo | 48 |
| Crash | 49 |
| Ride | 51 |

El nombre del archivo determina el orden del curso. Usa prefijos como
`01_bombo_caja.mid`, `02_charles_negras.mid` y conserva una sola dificultad
nueva por nivel. Las notas que no pertenezcan al kit se ignoran; si no queda
ninguna nota compatible el archivo se rechaza.

## Recomendaciones didácticas

Antes de añadir un sonido, consolida el patrón anterior. Por ejemplo: bombo y
caja, charles a negras, charles a corcheas, acento o fill. Evita introducir
tempo, subdivisión y sonido nuevo en el mismo nivel.

## Publicar

Incluye autor, licencia y una breve descripción junto al archivo en la página o
repositorio donde lo compartas. No distribuyas audio ajeno dentro del MIDI.
