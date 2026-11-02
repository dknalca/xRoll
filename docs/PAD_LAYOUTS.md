# Layouts de pads

Un layout asigna sonido y, cuando procede, rol técnico a cada posición física.
Las notas y el canal MIDI se aprenden una vez por controlador y no cambian al
elegir un layout.

## Presets disponibles

### xRoll Core

Es el punto de partida para iniciación. Conserva las posiciones principales y
repite bombo, caja y charles para que los 16 pads tengan una función.

```text
Tom agudo       | Crash            | Crash            | Ride
Charles cerrado | Charles cerrado  | Charles abierto  | Charles abierto
Bombo           | Tom grave        | Charles cerrado  | Caja
Bombo           | Aro              | Caja             | Palmada
```

### Drum Kit

Duplica bombo, caja y charles para aproximarse a la ergonomía de una batería.

```text
Tom grave       | Tom grave       | Tom agudo       | Crash
Charles cerrado | Charles abierto | Charles cerrado | Ride
Aro             | Caja            | Caja            | Palmada
Crash           | Bombo           | Bombo           | Ride
```

### Mirror

Distribución simétrica para alternar manos y practicar rudimentos.

```text
Tom agudo       | Tom grave       | Tom grave       | Tom agudo
Charles abierto | Charles cerrado | Charles cerrado | Charles abierto
Palmada         | Caja            | Caja            | Palmada
Crash           | Bombo           | Bombo           | Ride
```

## Objetivos de ejercicio

En la práctica táctil iOS se proyectan solo los objetivos activos sobre una
rejilla virtual compacta. Los destinos por sonido comparten un botón; los de rol
o pad mantienen las alternativas exactas. Se conservan IDs, roles y entradas
MIDI originales, sin cambiar las matrices físicas descritas arriba (D-048).

- **Sonido:** acepta cualquier pad que reproduzca la voz solicitada.
- **Rol:** exige un rol técnico, por ejemplo una caja izquierda o derecha.
- **Pad:** exige una posición física concreta.

Drum Kit y Mirror permiten duplicados; el motor acepta las alternativas válidas
cuando el objetivo es por sonido.

## Límites actuales

La interfaz ofrece solo Core, Drum Kit y Mirror. El formato `.padmap` v2 puede
leer layouts importados y conserva soporte de migración, pero no hay editor
Custom en la aplicación actual.
