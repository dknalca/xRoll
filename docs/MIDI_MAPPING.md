# Mapeo de pads

## Disposicion sugerida

Dos estandares que conviene respetar por defecto.

**Numeros de nota:** el mapa de percusion General MIDI.

**Disposicion fisica:** la convencion MPC, pad inferior izquierdo igual a la nota
36, ascendiendo hacia la derecha y luego hacia arriba.

Las dos juntas dan esta rejilla de 4x4, y encaja de maravilla: la fila inferior
queda con los cuatro sonidos nucleares justo bajo los dedos.

```
   48 tom_high   49 crash      50 (libre)    51 ride
   44 (libre)    45 tom_mid    46 hihat_open 47 (libre)
   40 (libre)    41 tom_low    42 hh_closed  43 (libre)
   36 kick       37 rim        38 snare      39 clap
```

## Asistente de aprendizaje

Los M-Vave se reconfiguran desde su propia aplicacion. Si alguien lo ha tocado,
una asignacion fija deja de funcionar y **el fallo es silencioso**: los pads
suenan mal y el usuario no sabe por que. El asistente cuesta poco y elimina el
problema entero.

Flujo: se ilumina un sonido, el usuario golpea el pad que quiere para el, se
captura y se pasa al siguiente. Con opcion de saltar sonidos que no vaya a usar.

Tres detalles que ahorran soporte:

1. **Detectar duplicados** en el momento, no al guardar. Dos sonidos en el mismo
   pad tiene que avisarse cuando ocurre.
2. **Aceptar Note On con cualquier velocidad mayor que cero.** Note On con
   velocidad cero se trata como Note Off y no produce golpe.
3. **Guardar el canal.** No todos usan el 10.

Los mensajes CC no forman parte del MVP. No se pueden tratar como notas sin
definir umbral y deteccion de flanco, y el controlador objetivo usa notas. El
formato reserva el campo `message` para poder anadirlos en una version posterior.

## Formato .padmap

Extension generica a proposito: atarla a la marca encerraria el formato en un
solo aparato. Es el contenido el que declara para que dispositivo se hizo.

```
{
  "format": 1,
  "device": "M-Vave SMC-Pad",
  "device_uid": 123456,
  "created": "2026-09-01",
  "pads": [
    { "sound": "kick",  "message": "note", "number": 36, "channel": 10, "row": 0, "col": 0 },
    { "sound": "rim",   "message": "note", "number": 37, "channel": 10, "row": 0, "col": 1 },
    { "sound": "snare", "message": "note", "number": 38, "channel": 10, "row": 0, "col": 2 },
    { "sound": "clap",  "message": "note", "number": 39, "channel": 10, "row": 0, "col": 3 }
  ]
}
```

`row` 0 es la fila inferior. `col` 0 es la columna izquierda.

`message` vale `note` en la version 1. `number` es la nota MIDI y deja el formato
preparado para representar otros tipos de mensaje en versiones posteriores sin
usar un campo con un nombre enganoso.

`device` es la etiqueta visible y `device_uid` es el identificador estable de
CoreMIDI. `channel` se guarda en el rango humano 1...16; al leer el byte de estado
MIDI se suma uno al nibble 0...15.

Cada sonido y cada posicion `(row, col)` aparecen como maximo una vez. Tambien es
un duplicado repetir la combinacion `(message, number, channel)`, aunque se haya
elegido otra posicion visual.

## El mapeo manda en la interfaz

**El orden de las dieciseis posiciones en pantalla se deriva de este fichero**,
aplanando la rejilla: fila inferior de izquierda a derecha, luego la siguiente.
Los cinco pads sin sonido conservan un hueco apagado; no se comprimen. Un sonido
omitido durante el asistente queda sin posicion y los ejercicios que lo requieren
se muestran como no disponibles hasta que se asigne.

Si el bombo esta fisicamente abajo a la izquierda y en pantalla aparece en el
centro, el usuario hace una transposicion mental en cada nota, que es
exactamente la carga cognitiva que la memoria espacial deberia eliminar.

El .padmap no es un menu de configuracion: es la fuente de verdad de la
disposicion visual.

## Teclado del portatil

El teclado imita la misma rejilla 4x4 con estas teclas, de arriba abajo:

```
1 2 3 4
Q W E R
A S D F
Z X C V
```

Se ignoran las repeticiones automaticas de tecla. El teclado sirve para probar y
practicar sin controlador, aunque algunos teclados no registran todas las
combinaciones simultaneas y la interfaz debe explicarlo sin convertirlo en un
fallo de puntuacion misterioso.
