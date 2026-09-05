# xRoll

Entrenador de finger drumming para macOS. Notas que caen por carriles, tu golpeas
los pads al ritmo, la app puntua la precision temporal.

Este fichero es el contrato de trabajo. Leelo entero antes de tocar codigo.

## Que es y que no es

**Es** un entrenador de tiempo para pads. El usuario ve venir las notas, las
golpea, y recibe una puntuacion basada en lo cerca que estuvo de la rejilla.

**No es** un secuenciador, ni un sampler, ni un DAW. No graba, no exporta audio,
no edita patrones. Si una funcion no ayuda a alguien a tocar mas a tiempo, no va.

**Publico objetivo:** principiante absoluto. El autor de este proyecto no sabe
tocar bateria. Todo el diseno debe asumir que el usuario tampoco.

## Reglas duras

1. **Cero dependencias externas en tiempo de ejecucion.** Ni Ableton, ni un
   navegador, ni una fuente de sonido del sistema. Se abre la app y funciona.
   Los samples viajan dentro del binario.

2. **La latencia es el rasgo principal del producto.** Objetivo: 15 ms desde el
   golpe fisico hasta el sonido. Por encima de 20 ms el usuario aprende a
   destiempo y la app hace mas dano que bien. Cualquier decision tecnica que
   comprometa esto se rechaza, por comoda que sea.

3. **La calibracion guiada es obligatoria, no opcional.** Con ventanas de
   +/- 35 ms, un desfase sin compensar de 20 ms se come dos tercios de la ventana
   perfecta y el usuario cree que toca mal cuando toca bien.

4. **Las posiciones no se mueven nunca.** El bombo esta siempre en el mismo sitio,
   en todos los ejercicios y niveles. Lo que cambia es que sonidos estan activos,
   no donde estan. La memoria espacial es la habilidad que se entrena; recolocar
   elementos la destruye.

5. **El orden de las posiciones sale del mapeo de pads.** No se decide en el
   codigo de la interfaz. Si el usuario remapea, las posiciones se reordenan
   solas y los huecos fisicos no se comprimen. Ver docs/MIDI_MAPPING.md.

6. **Nada de velocity.** Todos los golpes valen igual. Esta en la lista de
   futuribles y ahi se queda de momento.

## Entorno

| | |
|---|---|
| Maquina | MacBook Pro 2015, Intel |
| Sistema | macOS 12 |
| Objetivo de despliegue | macOS 12.0 |
| Lenguaje | Swift |
| Interfaz | SwiftUI |
| Vista de notas | SpriteKit |
| Audio | AVAudioEngine |
| Entrada | CoreMIDI, USB |
| Persistencia | SQLite |
| Controlador | M-Vave SMC-Pad Pocket, 4x4, por cable |

La grafica de esa maquina es Intel integrada. La vista de notas va en SpriteKit
para reducir el riesgo de redibujar decenas de vistas SwiftUI a 60 fps. El
rendimiento se valida en la maquina objetivo antes de darlo por conseguido.

## Licencias

- **Codigo: GPL-3.0-or-later.** Copyleft deliberado: un fork no puede cerrarse.
  Sin CLA, las contribuciones entran bajo la misma licencia automaticamente.
- **Audio, graficos y documentacion: CC BY-SA 4.0.** Son obras separadas y la
  licencia del codigo no las cubre.

Toda pieza de audio anadida al repositorio debe registrarse en
Resources/Loops/ATTRIBUTION.md en el mismo commit. Sin excepciones: reconstruir
la procedencia meses despues es imposible.

## Estructura

```
xRoll/
  CLAUDE.md              este fichero
  PLAN.md                fases y estado
  README.md              cara publica
  LICENSE
  docs/
    DECISIONS.md         registro de decisiones con su porque
    AUDIO.md             formato de samples y loops, esquema de kit.json
    SCORING.md           ventanas, estrellas, calibracion
    UI.md                carriles, colores, formas, perspectiva
    MIDI_MAPPING.md      mapa GM, disposicion, asistente, formato .padmap
    EXERCISES.md         formato de ejercicio y progresion por escalera
  Resources/
    Kits/hiphop_basic/   kit.json y los wav
    Loops/               loops de acompanamiento y ATTRIBUTION.md
  data/
    exercises/           ficheros de ejercicio en json
```

## Convenciones

- Identificadores de sonido en minusculas con guion bajo. La lista canonica esta
  en docs/AUDIO.md y no se inventa nada fuera de ella.
- Ningun nombre de fichero de audio aparece jamas en el codigo. Todo sale de
  kit.json o del nombre del loop. Anadir un kit debe ser soltar una carpeta.
- Documentacion y comentarios en castellano. Identificadores de codigo en ingles.
- Compas de 4/4 unicamente. Un BPM fijo por ejercicio.

## Como trabajar aqui

**No inventes mediciones.** Si un numero de latencia, de fps o de precision
aparece en un documento, tiene que venir de una ejecucion real cuya salida se
pueda ensenar. Un dato plausible pero inventado es peor que ninguno, porque se
construyen decisiones encima.

**Consulta PLAN.md antes de empezar** y respeta la fase en curso. Las fases estan
ordenadas para que cada una valide un riesgo antes de que la siguiente construya
sobre el.

**Si una decision de docs/DECISIONS.md te estorba, dilo** en vez de rodearla.
Estan escritas con su motivo justamente para poder revisarlas cuando el motivo
deje de aplicar.
