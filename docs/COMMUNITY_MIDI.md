# Ejercicios MIDI de comunidad

xRoll carga ejercicios desde `data/exercises/` en formato Standard MIDI File
(`.mid` o `.midi`). No hace falta ningún JSON propio.

Desde **Curso → MIDI importados → Importar ejercicio .mid**, el archivo se
valida y se copia al almacenamiento local de xRoll. Queda disponible para
práctica libre, sin incorporarse al curso ni alterar sus acreditaciones.

## Reglas del archivo

- Compás 4/4.
- Pulsos por negra (PPQ), no timecode.
- Standard MIDI File tipo 0 o 1, de hasta 32 MB.
- Máximo 256 compases.
- Un único metaevento de tempo, con valor mayor que cero; cambios o eventos
  duplicados se rechazan.
- El primer nombre de pista encontrado proporciona el título; si no existe, se
  usa el nombre del archivo.
- El compás debe permanecer en 4/4; los cambios de compás se rechazan.
- Notas de percusión General MIDI; se aceptan las del kit activo:

| Sonido | Nota GM |
| --- | ---: |
| Bombo | 36 |
| Aro | 37 |
| Caja | 38 |
| Palmada | 39 |
| Charles cerrado | 42 |
| Charles abierto | 46 |
| Tom grave | 41 |
| Tom agudo | 48 |
| Crash | 49 |
| Ride | 51 |

El nombre del archivo identifica el archivo importado, pero no modifica el orden
del curso oficial. Conserva una sola dificultad nueva por nivel si lo publicas
como una progresión propia. Las notas que no pertenezcan al kit hacen que se
rechace el archivo; también se rechazan las notas fuera de rejilla y los archivos
sin notas reproducibles del kit.

## Recomendaciones didácticas

Antes de añadir un sonido, consolida el patrón anterior. Por ejemplo: bombo y
caja, charles a negras, charles a corcheas, acento o fill. Evita introducir
tempo, subdivisión y sonido nuevo en el mismo nivel.

## Publicar

Incluye autor, licencia y una breve descripción junto al archivo en la página o
repositorio donde lo compartas. No distribuyas audio ajeno dentro del MIDI.

## Relación con los ejercicios integrados

Los ejercicios integrados usan el mismo formato MIDI que los comunitarios. La
app los carga desde `data/exercises/`; los ejercicios importados se copian al
almacenamiento local y se muestran en la biblioteca comunitaria, sin desbloqueos
ni requisitos del curso base. No existe un formato alternativo de ejercicios.

## Informe didáctico de importación

xRoll informa ya de polifonía, número de sonidos, semicorcheas, tempo alto y longitud. Un archivo técnicamente válido puede recibir advertencias pedagógicas, pero no se bloquea: el autor conserva la decisión final.
