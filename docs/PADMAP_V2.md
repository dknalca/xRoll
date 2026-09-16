# `.padmap` versión 2

## Motivo

La versión 1 imponía un único pad por sonido. Drum Kit y Mirror necesitan varios pads que disparen la misma voz. V2 modela una relación many-to-one y separa sonido, posición, rol y entrada MIDI.

## Ejemplo

```json
{
  "format": 2,
  "id": "drum_kit_right",
  "name": "Drum Kit",
  "preset": "drum_kit",
  "orientation": "right_handed",
  "device": {
    "name": "M-Vave SMC-Pad",
    "uid": 123456
  },
  "pads": [
    {
      "id": "r0c1",
      "row": 0,
      "col": 1,
      "sound": "kick",
      "role": "kick_left",
      "input": {
        "message": "note",
        "number": 36,
        "channel": 10
      }
    },
    {
      "id": "r0c2",
      "row": 0,
      "col": 2,
      "sound": "kick",
      "role": "kick_right",
      "input": {
        "message": "note",
        "number": 37,
        "channel": 10
      }
    }
  ]
}
```

`row` 0 es la fila inferior. `channel` usa 1…16.

## Reglas

- `id` de pad y `(row,col)` son únicos.
- Un mensaje `(message,number,channel)` aparece una vez.
- Un sonido puede aparecer en varios pads.
- Un rol, si existe, es único dentro del layout.
- Un sonido debe existir en el kit activo.
- Dos sonidos del mismo `choke_group` mantienen la regla de corte del kit.

## Objetivos de ejercicio

```json
{"sound":"kick","target":{"type":"any"}}
```

```json
{"sound":"kick","target":{"type":"role","value":"kick_left"}}
```

```json
{"sound":"kick","target":{"type":"pad","value":"r0c1"}}
```

En ejercicios v1, una nota sin `target` se interpreta como `any`.

## Migración v1 → v2

1. Conservar dispositivo, fecha, fila, columna, mensaje, número y canal.
2. Crear `id` con `r{row}c{col}`.
3. Mover MIDI dentro de `input`.
4. Establecer `preset: custom` si no puede inferirse.
5. Establecer `orientation: right_handed` solo como valor de compatibilidad.
6. Dejar `role: null`.
7. Guardar copia del v1 hasta confirmar que v2 carga correctamente.

## Persistencia

El perfil se identifica por:
- layout funcional;
- UID de dispositivo;
- mapeo MIDI.

El campo histórico `orientation` puede existir en un archivo v2 anterior. xRoll
lo conserva al leerlo, pero ya no lo muestra ni transforma layouts con él.

Cambiar notas MIDI no debería alterar el layout pedagógico. Cambiar layout sí puede cambiar compatibilidad de cursos.
