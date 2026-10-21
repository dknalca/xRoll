# Guía de uso

## Pantallas principales

Estas ilustraciones versionadas resumen las pantallas del flujo. Los textos y
colores siguen la interfaz actual; no contienen datos de usuario ni estado de
un dispositivo concreto.

![Preparación](assets/preparation.svg)

![Práctica](assets/practice.svg)

![Resultado](assets/result.svg)

![Pads y layout](assets/pads-layout.svg)

## Primera sesión

1. Abre `dist/xRoll.app` o ejecuta `swift run xroll-pads` desde la raíz.
2. Conecta el M-Vave antes de abrir la aplicación. Si no aparece, usa
   **Pads y layout** para elegir la entrada y asignar los sonidos que
   tenga tu controlador; puedes omitir los que no uses.
3. En **Curso**, pulsa **Empezar nivel** en la estación actual. El tren marca tu
   parada y las demás estaciones quedan resumidas.
4. Usa **Escuchar y colocar** para oír el patrón. Después pulsa
   **Empezar práctica**. Hay dos compases para prepararse.

## Estaciones y retos finales

El curso tiene catorce estaciones. Cada una contiene niveles y un reto final que
reúne sus ritmos. Al aprobar un nivel de la estación actual con patrón completo y al
menos 70 %, pulsa **Continuar**; al llegar al reto, pulsa **Preparar reto final**.
Su preparación usa el tempo de aprendizaje y el ritmo completo.

Al completar una estación aparece una celebración con las estrellas del intento y
**Siguiente parada**, que abre la primera estación pendiente. El progreso anterior
se conserva. Puedes abrir otra estación para explorar o repetir un nivel conocido.
El mapa, los textos y las acciones son comunes en Mac e iPhone.

## Redobles y transiciones

En **Redobles**, cada idea tiene dos prácticas consecutivas: **Solo el
redoble** para aprender el gesto, y **Dentro de un ritmo** para tocarlo entre
dos grooves sencillos y resolver con crash. La ruta actual incluye caja a
corcheas, bajada de toms, caja en semicorcheas y redoble lineal con bombo.

## Entrenar con D-A-I-T

En Preparación elige la fase que necesitas:

- **Descubrir:** escucha y localiza sin puntuación.
- **Aislar:** al iniciar la práctica reduce el tempo 20 %, usa dos vueltas y
  trabaja una voz.
- **Integrar:** devuelve el patrón completo a su contexto.
- **Transferir:** acompaña el charles sin verlo ni puntuarlo.

El selector **Gap Metronome** retira la claqueta después de la cuenta inicial:
3+1 compases, 2+2 o sólo un pulso ancla. Empieza siempre por guía total.

## Calentamiento y progreso

**Calentamiento recomendado** selecciona un nivel nuevo o un resultado bajo.
Al terminar, xRoll guarda el porcentaje, estrellas, juicios, desfase medio y
estadísticas por sonido. Si aún falta superar el ritmo, la acción principal es
repetirlo; **Practicar la parte difícil** queda como alternativa opcional y
menos destacada.
El gráfico representa, en orden cronológico, los 20 intentos más recientes del
ejercicio elegido.

Las ayudas cambian solo la guía visual: incluso con ayuda **Reducida**, todas
las notas del ritmo completo siguen siendo objetivos puntuables. Puedes
seleccionar cualquier ejercicio y tempo del curso. La acción guiada usa un tempo
de aprendizaje adecuado para la lección; para acreditarla, toca el ritmo completo
y alcanza el 70 %. Los retos de velocidad son opcionales. Si ya conoces un
bloque, puedes hacer su prueba de ritmo completo sin tocar cada ejercicio básico;
una prueba adelantada queda guardada y cuenta cuando la ruta previa esté
superada. Los intentos por voces, fragmento o corrección no acreditan el curso.
En el recorrido, aprobar con una estrella al 70 % ya permite continuar; los retos
de velocidad permanecen disponibles en Preparación.

En cada ejercicio se muestra el premio de tempo más alto conseguido. Cuando ya
se han ganado trofeos, estos sustituyen a las estrellas en la fila. Los ejercicios
MIDI comunitarios se importan desde **Curso → MIDI importados**; su formato y
límites están en [COMMUNITY_MIDI.md](COMMUNITY_MIDI.md).

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
- La calibración reproduce su claqueta de referencia aunque el metrónomo de
  práctica esté desactivado en **Opciones**.

## Accesibilidad

Los pads anuncian su sonido y tecla con VoiceOver. Las formas de las manos en
la práctica diferencian izquierda y derecha además del color.

## Elegir layout

En `Equipo → Pads y layout`:
1. selecciona Core para iniciación, Drum Kit para técnica de batería o Mirror para alternancia;
2. completa el mapeo de los dieciséis pads físicos si el controlador aún no lo conoce;
3. prueba cada celda;
4. confirma que cada pad ilumina y suena en la posición esperada.

Cambiar de layout puede afectar la compatibilidad técnica de algunos ejercicios, pero no borra el progreso musical.

## Cómo leer el resultado

- Precisión: cuántas notas quedaron dentro de ventana.
- Tendencia: dirección y magnitud del sesgo.
- Consistencia: dispersión de golpes.
- Transferencia: diferencia al retirar ayudas.

La acción recomendada es más importante que repetir buscando únicamente una estrella adicional.
