# Ejercicios

## Formato activo

Cada ejercicio activo es un Standard MIDI File (`.mid`). El nombre de pista es
el título, el metaevento de tempo fija BPM y las notas GM se convierten a
sonidos del kit. Se admiten rejilla de 16 y, al importar MIDI de tresillos,
rejilla ternaria de 12. La velocity se conserva como metadato para la futura
etapa de articulación; por ahora la puntuación evalúa timing.

El antiguo esquema JSON siguiente queda sólo como referencia del modelo interno,
no como formato de autoría ni catálogo activo.

```
{
  "format": 1,
  "id":       identificador estable, no se cambia nunca
  "title":    nombre visible
  "family":   agrupacion, por ejemplo "hiphop_boombap"
  "level":    posicion en la escalera
  "bpm":      fijo
  "meter":    [4, 4]
  "bars":     compases del patron
  "grid":     subdivisiones por compas, 16 es semicorcheas
  "repeats":  vueltas, 8 por defecto
  "kit":      carpeta del kit
  "loop":     nombre del loop, o null para claqueta sola
  "offset":   entrada desplazada en pasos, 0 por defecto
  "notes": [
    { "step": indice en la rejilla, "sound": id canonico, "hand": "L", "R" o null }
  ]
}
```

`step` va de 0 a `bars * grid - 1`. En una rejilla de 16 y un compas, el primer
tiempo es 0, el segundo 4, el tercero 8 y el cuarto 12.

`offset` aplica una **entrada desplazada**: el patrón empieza en el paso indicado
en vez de hacerlo en el primer tiempo. El valor debe estar dentro de la rejilla;
si una nota se desplaza más allá del final del compás, vuelve al principio.

## Progresion por escalera

Cada nivel introduce **una sola dificultad** y conserva lo aprendido. Puede ser
un sonido nuevo, un cambio de patron o un cambio de tempo; nunca se cambian dos
variables en el mismo salto. Esto permite consolidar una coordinacion antes de
anadir otra voz.

| Nivel | Dificultad nueva | Resultado |
|---|---|---|
| 1 | Bombo y caja | El esqueleto |
| 2 | Charles cerrado | Ya es un groove |
| 3 | Bombo desplazado | Consolida el groove clasico |
| 4 | Charles abierto | Respiracion |
| 5 | Palmada | Refuerzo del backbeat |
| 6 | Bombo a contratiempo | Independencia en semicorcheas |
| 7 | Fill de palmada | Relleno antes del cierre |
| 8 | Subida a 90 BPM | Consolidación del groove |
| 9 | Entrada a contratiempo | Leer el mismo patrón desde otra posición |
| 10 | Charles en semicorcheas | Control de subdivisión |
| 11 | Subida a 100 BPM | Mantener precisión al acelerar |
| 12 | Crash de entrada | Acento y comienzo del compás |

## Reparto de manos

Los ficheros de ejemplo usan este criterio: **bombo mano izquierda, caja mano
derecha, y el charles con la mano que quede libre.**

Cuando el bombo y el charles caen a la vez, el charles va con la derecha. Cuando
la caja y el charles coinciden, el charles va con la izquierda. Los charles
sueltos alternan entre si, aunque un golpe simultaneo puede obligar a repetir una
mano entre dos corcheas consecutivas.

No es la unica digitacion valida, pero es consistente y se puede aprender sin
pensar, que es lo que necesita un principiante.

## Al escribir ejercicios nuevos

- Una sola dificultad nueva por nivel.
- El nivel 1 de cada familia tiene que poder completarlo alguien que no ha
  tocado nunca.
- Tempos iniciales entre 70 y 90. Es donde vive el hip hop y donde hay margen
  para pensar.
- Comprobar que la subdivision mas corta no estrecha las ventanas de juicio mas
  de la cuenta. Ver el recorte en docs/SCORING.md.

## Metadatos pedagógicos futuros

Los metadatos enriquecidos aún no se escriben en los MIDI activos. Si se añade
un sidecar comunitario en el futuro, podrá contener:

```json
{
  "chapter": "subdivision",
  "skills": {"pulse": 0.3, "eighth_notes": 0.5, "syncopation": 1.0},
  "new_difficulty": "first_offbeat_kick",
  "prerequisites": ["foundation_2_03"],
  "learning_objective": "Colocar el bombo entre pulsos sin mover la caja",
  "recommended_help": "full",
  "mastery": {
    "minimum_score": 80,
    "maximum_absolute_bias_ms": 25,
    "maximum_dispersion_ms": 35,
    "required_attempts": 2
  }
}
```

Una nota puede añadir `target` por sonido, rol o pad según [PADMAP_V2.md](PADMAP_V2.md).

## Compatibilidad de layout

```json
{
  "required_sounds": ["kick", "snare", "hihat_closed"],
  "required_roles": [],
  "recommended_layouts": ["xroll_core", "drum_kit"]
}
```

Estados: compatible, compatible con adaptación, incompleto y no compatible.

## Currículo

La progresión completa está en [CURRICULUM.md](CURRICULUM.md) y el primer bloque en [INITIATION.md](INITIATION.md).
