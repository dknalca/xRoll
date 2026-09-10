# Layouts de pads

## Principio

xRoll ofrece layouts predeterminados y uno personalizado. Un layout no es solo una apariencia: determina ergonomía, técnica disponible y relación entre posiciones físicas y objetivos didácticos.

Separar siempre:
1. **layout funcional:** sonido y rol de cada posición;
2. **mapeo MIDI:** mensaje del dispositivo;
3. **objetivo didáctico:** sonido, rol o pad requerido por una nota.

## Presets

### xRoll Core

Predeterminado para iniciación. Un pad por sonido.

```text
Tom alto | Crash    | —         | Ride
—        | Tom medio| HH abierto| —
—        | Tom grave| HH cerrado| —
Bombo    | Aro      | Caja      | Palmada
```

Fortalezas: claridad, memoria espacial, scoring simple y once voces. Limitación: no permite alternar sobre la misma voz.

### Drum Kit

Inspirado en ergonomía de batería y en layouts divulgados por Quest for Groove. Duplica voces nucleares.

```text
Tom grave | Tom medio | Tom alto | Crash
HH cerrado| HH abierto| HH cerrado| Ride
Aro       | Caja      | Caja      | Palmada
Crash     | Bombo     | Bombo     | Ride
```

Favorece técnica de batería, fills, rock, funk, blues y jazz. Requiere many-to-one.

### Mirror

Duplica voces en ambas mitades para alternancia y rudimentos.

```text
Tom alto  | Tom grave | Tom grave | Tom alto
HH abierto| HH cerrado| HH cerrado| HH abierto
Palmada   | Caja      | Caja      | Palmada
Crash     | Bombo     | Bombo     | Ride
```

Favorece rolls, flams, paradiddles y velocidad. Ofrece menos sonidos únicos y no sustituye el desarrollo de independencia por roles.

### Studio / General MIDI

Orden GM 36–51 para interoperar con DAW y MIDI comunitario. Puede presentarse como variante MIDI de Core si ambos mapas visuales coinciden.

## Orientación

Diestra/zurda es una transformación, no un preset duplicado.

```text
columna_nueva = 3 - columna_original
```

Cada preset declara `supports_mirroring`. Studio/GM puede conservar el orden MIDI aunque la técnica se refleje.

## Custom

Flujo:
1. partir de Core, Drum Kit, Mirror, GM o vacío;
2. asignar por drag-and-drop o aprendizaje MIDI;
3. validar sonidos, mensajes, duplicados, choke groups y compatibilidad;
4. probar en sandbox;
5. guardar por dispositivo.

Los duplicados de sonido son válidos y explícitos. Los mensajes MIDI duplicados son conflicto salvo configuración avanzada documentada.

## Selector

Cada tarjeta muestra:
- rejilla 4×4;
- dificultad;
- voces únicas y duplicadas;
- técnica favorecida;
- cursos compatibles;
- botones Probar y Seleccionar.

Estados de compatibilidad:
- compatible;
- compatible con adaptación;
- incompleto;
- no compatible.

## Tipos de objetivo

### Por sonido
Cualquier pad con esa voz es válido. Para grooves e importación MIDI.

### Por rol
Exige `snare_left`, `snare_right`, `kick_left`, etc. Para rudimentos y alternancia.

### Por pad
Exige una posición exacta. Para onboarding y memoria espacial.

## Representación de duplicados

Los 16 carriles físicos permanecen. En el MVP, una nota aparece en el carril recomendado y las alternativas válidas se iluminan. Golpear una alternativa consume el mismo objetivo. Una futura nota puente puede bifurcarse, pero requiere prueba de legibilidad.

## Alcance

MVP:
- Core;
- Drum Kit;
- diestra/zurda;
- custom básico;
- duplicados;
- objetivos por sonido;
- migración `.padmap` v1→v2.

Implementado:
- Mirror;
- objetivos por rol y pad;
- importación/exportación de layouts.

Posterior:
- rudimentos;
- presets verificados por modelo concreto de controlador;
- comparación y catálogo comunitario de layouts.
