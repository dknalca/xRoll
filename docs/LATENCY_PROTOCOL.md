# Protocolo de latencia

Este documento mide el recorrido completo, no solo el tiempo que informa
AVAudioEngine. La primera medicion usa el perfil que se ha comprobado en esta
maquina el 5 de septiembre de 2026:

| Elemento | Valor |
|---|---|
| Entrada MIDI | SMC-PAD Pocket-Private |
| UID MIDI | `803015744` |
| Salida | Rane Seventy-Two Audio |
| Frecuencia | 48.000 Hz |
| Buffer | 512 fotogramas |
| Sample | `kick.wav` |

Si se cambia cualquiera de esos elementos, se crea una medicion nueva. No se
mezclan resultados de perfiles distintos.

## Preparacion

1. Conectar los altavoces a la Rane y dejar el volumen a un nivel audible y
   estable.
2. Colocar el microfono del movil a la misma distancia del pad que se golpea y
   del altavoz que reproduce el bombo. Asi el tiempo que tarda el aire en llegar
   al microfono se compensa entre ambos sonidos.
3. Abrir una grabadora que permita exportar el audio sin editarlo.
4. En la raiz del proyecto, iniciar la prueba:

   ```
   swift run xroll-latency kick --source 803015744
   ```

   No se usa `--log-events`: escribir en consola altera el callback MIDI.

## Grabacion

1. Empezar a grabar con el movil.
2. Dar 100 golpes aislados sobre el mismo pad, separados aproximadamente medio
   segundo. No hace falta tocar a tempo; se mide la separacion entre el ruido
   fisico del golpe y el bombo reproducido.
3. Detener primero la prueba con `Ctrl-C` y despues la grabacion.
4. Copiar el archivo original a `data/measurements/` sin recortarlo ni
   normalizarlo.

## Analisis y resultado

Para cada golpe se mide en la forma de onda:

```
latencia = inicio audible del bombo - inicio audible del golpe en el pad
```

El comando siguiente enumera los inicios principales de los bombos como ayuda
para localizar cada pareja en la grabacion; no decide por si solo el inicio del
golpe fisico:

```
swift run xroll-analyse-recording data/measurements/<grabacion.mov>
```

Se registran los 100 valores, su mediana, percentil 95, minimo y maximo. El
resultado pasa la puerta del proyecto si la mediana es de 15 ms o menos, el
percentil 95 de 20 ms o menos y no hubo cortes durante la prueba.

El resultado se guarda en `data/measurements/latency_YYYY-MM-DD.md` junto con el
archivo de audio original. Si el archivo es demasiado grande para el repositorio,
se conserva fuera de Git pero se indica su ubicacion y hash en el informe.
