# Ejercicios

## Formato activo

Cada ejercicio activo es un Standard MIDI File (`.mid`). El nombre de pista es
el título, el metaevento de tempo fija BPM y las notas GM se convierten a
sonidos del kit. Se admiten rejilla de 16 y, al importar MIDI de tresillos,
rejilla ternaria de 12. La velocity se conserva como metadato para la futura
etapa de articulación; por ahora la puntuación evalúa timing.

No hay formato JSON de ejercicios ni un catálogo alternativo: MIDI es la única
fuente de autoría y distribución. Para crear o compartir un ejercicio consulta
[COMMUNITY_MIDI.md](COMMUNITY_MIDI.md).

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

## Metadatos pedagógicos MIDI

Los ejercicios integrados incorporarán metadatos curriculares como metaeventos
de texto estándar al inicio del MIDI. El espacio de nombres versionado será
`xroll/1`; por ejemplo:

```text
xroll/1 id=02_sub_04_bombo_y
xroll/1 chapter=subdivision
xroll/1 position=4
xroll/1 prerequisite=02_sub_03_groove
xroll/1 objective=Colocar el bombo entre pulsos sin mover la caja
xroll/1 new-difficulty=first-offbeat-kick
xroll/1 recommended-help=full
```

No hay sidecar JSON. Un MIDI comunitario sin estos metadatos sigue siendo válido
y practicable, pero no se incorpora al recorrido oficial.

Una nota puede añadir `target` por sonido, rol o pad según [PADMAP_V2.md](PADMAP_V2.md).

## Redobles y transiciones

La sección **Redobles** es una ruta técnica independiente del curso de
grooves. Cada tipo dispone de dos `.mid`: `A` contiene sólo el gesto y `B` lo
sitúa en una frase de tres compases (groove → redoble → groove con crash).

| Tipo | Idea nueva | Orden |
|---|---|---|
| Caja a corcheas | Cuatro golpes espaciados de caja | Aislado, luego groove |
| Bajada de toms | Tom agudo a tom grave | Aislado, luego groove |
| Caja en semicorcheas | Ocho golpes de caja más densos | Aislado, luego groove |
| Lineal | Bombo, caja y toms sin simultaneidad | Aislado, luego groove |

Estos cuatro patrones siguen formas habituales de redoble: una frase de caja,
un descenso por toms y una figura lineal; se recomienda dominar el ritmo en
caja antes de orquestarlo por el kit. [Basic Fills — Drum Town](https://drum.town/lessons/rock-basic-fills/) y [Linear Fills — Drum Town](https://drum.town/lessons/rock-linear-fills/).

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
