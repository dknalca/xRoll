# Puntuacion

## Ventanas de juicio

Medidas desde el instante exacto de la rejilla, ya compensada la latencia.

| Juicio | Ventana | Valor por nota |
|---|---|---|
| Perfecto | +/- 35 ms | 1,0 |
| Bien | +/- 65 ms | 0,85 |
| Regular | +/- 95 ms | 0,70 |
| Fallo | mas alla | 0,0 |

Regular existe para que un principiante no se lleve cero constantemente.

## Recorte por subdivision

**La ventana Regular se recorta al 45 % de la subdivision mas corta del
ejercicio.**

A 100 BPM una semicorchea dura 150 ms, asi que +/- 95 ms permitiria que un golpe
estuviese mas cerca de la casilla vecina que de la suya y el juicio seria
ambiguo. Con el recorte, en ejercicios lentos se disfruta de la ventana ancha y
en los rapidos se estrecha sola.

```
limite = 0.45 * (60000 / bpm / (subdivisiones_por_negra))
regular = min(95, limite)
bien    = min(65, regular)
perfecto= min(35, bien)
```

Este cálculo se aplica en cada sesión a partir del BPM y la rejilla del
ejercicio. Los ajustes de depuración solo pueden estrechar estas ventanas, nunca
ampliarlas por encima de este límite seguro.

## Toques de mas

Cada golpe que no corresponde a ninguna nota de la rejilla resta 0,25 puntos.
Un golpe suelto no arruina el ejercicio, pero martillear
los pads no puede salir rentable.

Un golpe dentro de la ventana de una nota que **ya fue golpeada** cuenta como
toque de mas, no como segundo intento.

Durante los compases de entrada se pueden probar los pads: esos golpes se
reproducen y dan feedback visual, pero no se guardan ni penalizan. La excepción
es un golpe suficientemente anticipado para quedar dentro de la ventana Regular
del primer pulso; así se conserva el scoring normal de una entrada adelantada.

## Asociacion entre golpes y notas

- Un golpe se asocia a la nota pendiente del mismo sonido mas cercana en el
  tiempo, siempre que este dentro de la ventana Regular.
- Cada nota solo puede consumir un golpe y cada golpe solo puede consumir una
  nota. Las notas simultaneas de sonidos distintos se resuelven por separado.
- Una nota pasa a Fallo cuando termina su ventana Regular sin golpe asociado.
- En un empate exacto se elige la nota anterior, para que el resultado sea
  determinista.

## Puntuacion final

```
puntuacion = (obtenido - penalizaciones) / posible * 100
```

`obtenido` es la suma de los valores por nota y cada toque de más penaliza 0,25.
`posible` es el numero de notas del ejercicio, contando todas las vueltas. Se
muestra el resultado neto junto al total alcanzable, ademas del porcentaje.

El resultado se limita al intervalo de 0 a 100. Los toques de mas nunca producen
una puntuacion negativa.

## Estrellas

| Estrellas | Umbral |
|---|---|
| 3 | 90 % o mas |
| 2 | 70 % o mas |
| 1 | 50 % o mas |

Una estrella al 50 y no al 60 es deliberado: el principiante honesto se lleva
algo.

## Adelantado o atrasado

**Cada golpe informa de su direccion**, no solo de su juicio. Los principiantes
casi nunca fallan al azar: van sistematicamente adelantados o atrasados.

- Por golpe: el signo del desvio, visible en el momento.
- Al terminar: el desvio medio de los golpes asociados. Fallos y toques de mas
  no tienen un desvio comparable y se excluyen. Un mensaje del tipo
  "de media vas 28 ms adelantado" vale mas que la puntuacion, porque es
  accionable.

## Calibracion guiada

**Obligatoria antes del primer ejercicio puntuado, y accesible despues desde
ajustes.** El orden inicial es: elegir entrada, mapear pads, elegir salida y
calibrar.

Con ventanas de +/- 35 ms, un desfase sin compensar de 20 ms desplaza todos los
golpes y se come dos tercios de la ventana perfecta. El usuario deduce que toca
mal cuando toca bien. Es el fallo silencioso que arruina los juegos de ritmo mal
hechos.

Procedimiento: claqueta constante, el usuario acompana durante unos ocho
compases, se descartan los primeros y se toma la **mediana** del desvio, no la
media, para que un golpe perdido no contamine el resultado. Ese valor se resta
de todas las mediciones posteriores.

El desvio bruto se define como `instante_del_golpe - instante_objetivo`: positivo
significa atrasado y negativo, adelantado. El desvio puntuado es
`desvio_bruto - compensacion_del_perfil`.

Esta prueba mide la compensación práctica del conjunto, incluida la tendencia
del usuario al seguir la claqueta, y aplica su mediana al scoring de esa ruta.
Si los golpes tienen demasiada dispersión para dar una compensación fiable, se
explica el problema y se repite. El umbral de dispersión se fija con pruebas
reales, no por intuición.

Se guarda por perfil completo: tipo e identificador estable de entrada,
identificador de salida, frecuencia de muestreo y tamano de buffer. El teclado
del portatil es una entrada propia. Si cambia cualquiera de esos datos, el
perfil deja de aplicarse y se solicita una nueva calibracion.

## Historial

SQLite, una fila por intento, con estadísticas agregadas y el vector de
eventos de la sesión:

```
id  exercise_id  timestamp  bpm  score  stars  perfect  good  regular  miss  extra  mean_offset_ms  sound_stats_json  hit_records_json  training_context_json
```

Con eso salen el contador de veces realizadas, la mejor puntuacion y la curva de
progreso. `mean_offset_ms` permite ademas ensenar si alguien esta corrigiendo su
tendencia a adelantarse, que es informacion mas util que la puntuacion.

`hit_records_json` conserva, en orden temporal, un `HitRecord` por golpe o
fallo: objetivo (sonido, paso, tiempo, mano, destino y velocity), ejecución
(sonido, tiempo, rol, pad y velocity) y su juicio/desvío. Los fallos no llevan
ejecución y los extras no llevan objetivo. Así una sesión puede reconstruirse y
analizarse sin SpriteKit; los historiales anteriores siguen siendo válidos y se
leen con una colección de eventos vacía.

`training_context_json` acompaña a los intentos nuevos con fase D-A-I-T, nivel
de Gap Metronome y estado de guía visual. Permite evaluar maestría sin inferir
la intención de una pantalla o una versión concreta de la interfaz.

## Diagnóstico robusto

Además de `mean_offset_ms`, las nuevas sesiones guardan el resultado por sonido.
En cada resultado se calculan mediana, dispersión y percentil 95 para mostrar
una recomendación, y Ghost Coach combina el sonido más débil con el sesgo.
El registro detallado se agrupa en Análisis por sonido, mano, rol, pad,
subdivisión, vuelta y transición. La prioridad combina precisión y cantidad de
evidencia; pocas notas no se presentan como una conclusión fuerte.

La media no se utiliza sola: errores positivos y negativos pueden cancelarse.

## Latencia y sesgo

```text
offset_bruto = golpe - objetivo
offset_puntuado = offset_bruto - scoringCompensationMs
sesgo_observado = mediana(offset_bruto)
```

La compensación guiada se guarda por ruta; el sesgo observado sigue disponible
para diagnóstico de la sesión.

## Matching

La asociación es greedy y determinista: cada golpe se compara con la nota
pendiente más cercana del mismo sonido dentro de la ventana Regular. En un
empate exacto se consume la nota anterior. Las ventanas recortadas evitan que
notas consecutivas de la misma voz compartan una zona ambigua.

`PracticeSession` conserva un acumulador incremental para entradas con
`hostTime` cronológico: indexa objetivos por sonido y busca solo las notas de la
ventana temporal del golpe. Si llega una marca temporal anterior al máximo visto,
reconstruye las asociaciones con el scorer batch de referencia; la ruta de audio
no espera esa reconstrucción. `PracticeSessionIngress` mantiene cada sesión en
una cola serial y cierra con una barrera antes de producir el resultado final.

## Simultaneidad

Los objetivos simultáneos de sonidos distintos se puntúan de forma individual.
La separación entre impactos no forma parte todavía de la puntuación ni del
historial.

## Layouts duplicados

Un objetivo `any` acepta cualquier pad que resuelva el sonido. Un objetivo de rol o pad exige coincidencia técnica, aunque el audio producido sea el mismo.
