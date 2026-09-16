# Diagnóstico interno de audio y MIDI

`xroll-latency` y `xroll-analyse-recording` son herramientas internas para
investigar una ruta concreta de audio y MIDI. No forman parte de la aplicación,
no generan perfiles importables y no son un requisito de publicación.

## Uso

Primero identifica las rutas disponibles:

```
swift run xroll-preflight
```

Después puedes escuchar un sonido asociado a una sola entrada MIDI:

```
swift run xroll-latency kick --source <uid-del-controlador>
```

El click de diagnóstico evita la ruta `TimePitch`:

```
swift run xroll-latency rim --test-click --source <uid-del-controlador>
```

No uses `--log-events` durante estas comprobaciones: escribir en consola añade
trabajo a la ruta MIDI.

## Análisis de grabaciones

El analizador enumera inicios de transitorios de una grabación externa:

```
swift run xroll-analyse-recording <grabacion.mov>
```

Con una toma que use `--test-click`, el modo por bandas separa el impacto grave
del pad y la señal aguda:

```
swift run xroll-analyse-recording <grabacion.mov> --split-bands
```

Los resultados de estas herramientas sirven para depuración técnica. La
calibración usada por xRoll es la prueba guiada, guardada por entrada, salida,
frecuencia y buffer.
