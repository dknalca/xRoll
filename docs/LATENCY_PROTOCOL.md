# Protocolo de latencia

Este documento mide el recorrido completo, no solo el tiempo que informa
AVAudioEngine. Cada resultado identifica su propia entrada MIDI, salida,
frecuencia, buffer y sample; no se mezclan perfiles distintos.

## Preparacion

1. En Ajustes, elegir la salida de audio y el buffer que se van a medir. Cambiar
   cualquiera de los dos invalida la calibracion y crea un perfil distinto.
2. Conectar los altavoces a la salida elegida y dejar el volumen a un nivel audible
   y estable.
3. Colocar el microfono del movil a la misma distancia del pad que se golpea y
   del altavoz que reproduce el bombo. Asi el tiempo que tarda el aire en llegar
   al microfono se compensa entre ambos sonidos.
4. Abrir una grabadora que permita exportar el audio sin editarlo.
5. En la raiz del proyecto, iniciar la prueba:

   ```
    swift run xroll-preflight
    swift run xroll-latency kick --source <uid-del-controlador>
    ```

    No se usa `--log-events`: escribir en consola altera el callback MIDI.

    Si el golpe físico y el sample se solapan en el micrófono del móvil, usa el
    click agudo de diagnóstico, que se reproduce directamente sin `TimePitch`:

    ```
    swift run xroll-latency rim --test-click --source <uid-del-controlador>
    ```

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

    Para una toma con `--test-click`, el modo por bandas separa el impacto grave
    del pad y la señal aguda, empareja cada par y calcula sus estadísticos:

    ```
    swift run xroll-analyse-recording data/measurements/<grabacion.mov> --split-bands
    ```

Se registran los 100 valores, su mediana, percentil 95, minimo y maximo. El
resultado pasa la puerta del proyecto si la mediana es de 15 ms o menos, el
percentil 95 de 20 ms o menos y no hubo cortes durante la prueba.

El resultado se guarda en `data/measurements/latency_YYYY-MM-DD.md` junto con el
archivo de audio original. El informe incluye perfil, mediana, percentil 95,
mínimo, máximo, ubicación del audio y hash si queda fuera de Git.
