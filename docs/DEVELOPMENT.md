# Desarrollo

## Preparacion actual

El paquete Swift contiene `XRollCore`, que agrupa modelos de recursos y lectura
del sistema, y `xroll-preflight`, un ejecutable de diagnostico. No tiene
dependencias externas y su plataforma minima es macOS 12.

Desde la raiz del repositorio:

```
swift test --filter XRollCoreTests
swift run xroll-preflight
swift run xroll-latency kick
swift run xroll-latency kick --check
```

El segundo comando comprueba tres cosas antes de cualquier prueba musical:

1. Fuentes MIDI visibles para CoreMIDI y su identificador estable.
2. Salida de audio predeterminada, frecuencia, canales, buffer, rango de buffers
   y latencia de presentacion que informa el sistema.
3. Coherencia de `kit.json` y de los ejercicios, y presencia de los WAV del kit.

La latencia de presentacion informada por el sistema no es la latencia total.
`xroll-latency <sound-id>` carga el kit, conecta todas las fuentes MIDI y hace
sonar ese identificador ante cualquier Note On. La medicion de la fase 0 empieza
cuando haya un sample definitivo y un controlador MIDI conectado; se registra
entonces tambien el golpe fisico y el sonido audible en una grabacion externa,
como especifica PLAN.md. El modificador `--log-events` es diagnostico: no se usa
durante la medicion porque escribir en consola anade trabajo al callback MIDI.
El modificador `--check` inicia audio y conecta MIDI para comprobar la
preparacion, y termina sin esperar un golpe.

Si hay varios dispositivos MIDI, se elige solo el controlador objetivo con
`--source <uid>`. El UID aparece entre corchetes al ejecutar `xroll-preflight`.

## Regla de validacion de recursos

Un ejercicio solo es valido si usa el kit declarado, 4/4, pasos dentro de su
rejilla, sonidos del kit y manos `L`, `R` o `null`. Dos notas del mismo sonido no
pueden ocupar el mismo paso, pero dos sonidos distintos si pueden ser simultaneos.
