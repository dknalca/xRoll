# Guía de uso

## Primera sesión

1. Abre `dist/xRoll.app` o ejecuta `swift run xroll-pads` desde la raíz.
2. Conecta el M-Vave antes de abrir la aplicación. Si no aparece, usa la
   pestaña **Mapear pads** para elegir la entrada y asignar los seis sonidos.
3. En **Practicar**, elige un ejercicio. Ajusta BPM y vueltas si hace falta.
4. Usa **Escuchar y colocar** para oír el patrón. Después pulsa
   **Empezar práctica**. Hay dos compases para prepararse.

## Calentamiento y progreso

**Calentamiento recomendado** selecciona un nivel nuevo o un resultado bajo.
Al terminar, xRoll guarda el porcentaje, estrellas, juicios y desfase medio.
El gráfico representa los intentos del ejercicio elegido.

Para conservar una copia legible de los datos:

```sh
swift run xroll-export-progress ~/Desktop/progreso.csv
swift run xroll-export-progress ~/Desktop/progreso.json --exercise hh_04 --minimum-score 75
```

La exportación no altera los datos locales.

## Recuperación

- **No suena nada:** comprueba la salida de audio del sistema y reinicia la app.
- **Faltan muestras:** coloca los seis WAV en `Resources/Kits/hiphop_basic/` y
  vuelve a crear la aplicación con `scripts/build-app.sh`.
- **El controlador no responde:** usa el teclado para comprobar la app y vuelve
  a hacer el mapeo del M-Vave.
- **La puntuación parece adelantada o atrasada:** ejecuta **Calibración guiada**
  con la misma salida de audio que usarás al practicar.

## Accesibilidad

Los pads anuncian su sonido y tecla con VoiceOver. Las formas de las manos en
la práctica diferencian izquierda y derecha además del color.
