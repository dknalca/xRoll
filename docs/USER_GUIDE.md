# Guía de uso

## Primera sesión

1. Abre `dist/xRoll.app` o ejecuta `swift run xroll-pads` desde la raíz.
2. Conecta el M-Vave antes de abrir la aplicación. Si no aparece, usa
   **Pads y layout** para elegir la entrada y asignar los sonidos que
   tenga tu controlador; puedes omitir los que no uses.
3. En **Curso**, elige un bloque y un ejercicio. Ajusta BPM y vueltas si hace falta.
4. Usa **Escuchar y colocar** para oír el patrón. Después pulsa
   **Empezar práctica**. Hay dos compases para prepararse.

## Redobles y transiciones

En **Redobles**, cada idea tiene dos prácticas consecutivas: **Solo el
redoble** para aprender el gesto, y **Dentro de un ritmo** para tocarlo entre
dos grooves sencillos y resolver con crash. La ruta actual incluye caja a
corcheas, bajada de toms, caja en semicorcheas y redoble lineal con bombo.

## Entrenar con D-A-I-T

En Preparación elige la fase que necesitas:

- **Descubrir:** escucha y localiza sin puntuación.
- **Aislar:** reduce el tempo 20 %, usa dos vueltas y trabaja una voz.
- **Integrar:** devuelve el patrón completo a su contexto.
- **Transferir:** acompaña el charles sin verlo ni puntuarlo.

El selector **Gap Metronome** retira la claqueta después de la cuenta inicial:
3+1 compases, 2+2 o sólo un pulso ancla. Empieza siempre por guía total.

## Calentamiento y progreso

**Calentamiento recomendado** selecciona un nivel nuevo o un resultado bajo.
Al terminar, xRoll guarda el porcentaje, estrellas, juicios, desfase medio y
estadísticas por sonido. **Corregir sonido** abre una práctica corta de la voz
con menor acierto; Ghost Coach explica la prioridad.
El gráfico representa los intentos del ejercicio elegido.

Para conservar una copia legible de los datos:

```sh
swift run xroll-export-progress ~/Desktop/progreso.csv
swift run xroll-export-progress ~/Desktop/progreso.json --exercise hh_04 --minimum-score 75
```

La exportación no altera los datos locales.

## Recuperación

- **No suena nada:** comprueba la salida de audio del sistema y reinicia la app.
- **Faltan muestras:** coloca los diez WAV en `Resources/Kits/hiphop_basic/` y
  vuelve a crear la aplicación con `scripts/build-app.sh`.
- **El controlador no responde:** usa el teclado para comprobar la app y vuelve
  a hacer el mapeo del M-Vave.
- **La puntuación parece adelantada o atrasada:** ejecuta **Calibración guiada**
  con la misma salida de audio que usarás al practicar.

## Accesibilidad

Los pads anuncian su sonido y tecla con VoiceOver. Las formas de las manos en
la práctica diferencian izquierda y derecha además del color.

## Elegir layout

En `Equipo → Pads y layout`:
1. selecciona Core para iniciación, Drum Kit para técnica de batería o Mirror para alternancia;
2. elige orientación;
3. prueba cada celda;
4. confirma que cada pad ilumina y suena en la posición esperada.

Cambiar de layout puede afectar la compatibilidad técnica de algunos ejercicios, pero no borra el progreso musical.

## Cómo leer el resultado

- Precisión: cuántas notas quedaron dentro de ventana.
- Tendencia: dirección y magnitud del sesgo.
- Consistencia: dispersión de golpes.
- Transferencia: diferencia al retirar ayudas.

La acción recomendada es más importante que repetir buscando únicamente una estrella adicional.
