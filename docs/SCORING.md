# Puntuacion

## Ventanas de juicio

Medidas desde el instante exacto de la rejilla, ya compensada la latencia.

| Juicio | Ventana | Valor por nota |
|---|---|---|
| Perfecto | +/- 35 ms | 1,0 |
| Bien | +/- 65 ms | 0,7 |
| Regular | +/- 95 ms | 0,4 |
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

## Toques de mas

Cada golpe que no corresponde a ninguna nota de la rejilla resta el equivalente
a media nota perfecta. Un golpe suelto no arruina el ejercicio, pero martillear
los pads no puede salir rentable.

Un golpe dentro de la ventana de una nota que **ya fue golpeada** cuenta como
toque de mas, no como segundo intento.

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

`obtenido` es la suma de los valores por nota y cada toque de mas penaliza 0,5.
`posible` es el numero de notas del ejercicio, contando todas las vueltas. Se
muestra el resultado neto junto al total alcanzable, ademas del porcentaje.

El resultado se limita al intervalo de 0 a 100. Los toques de mas nunca producen
una puntuacion negativa.

## Estrellas

| Estrellas | Umbral |
|---|---|
| 3 | 90 % o mas |
| 2 | 75 % o mas |
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

Esta prueba mide la compensacion practica del conjunto, incluida la tendencia
del usuario al seguir la claqueta; no pretende sustituir la medida fisica de la
fase 0. Si los golpes tienen demasiada dispersion para dar una compensacion
fiable, se explica el problema y se repite. El umbral de dispersion se fija con
pruebas reales, no por intuicion.

Se guarda por perfil completo: tipo e identificador estable de entrada,
identificador de salida, frecuencia de muestreo y tamano de buffer. El teclado
del portatil es una entrada propia. Si cambia cualquiera de esos datos, el
perfil deja de aplicarse y se solicita una nueva calibracion.

## Historial

SQLite, una fila por intento:

```
id  exercise_id  timestamp  bpm  score  stars  perfect  good  regular  miss  extra  mean_offset_ms
```

Con eso salen el contador de veces realizadas, la mejor puntuacion y la curva de
progreso. `mean_offset_ms` permite ademas ensenar si alguien esta corrigiendo su
tendencia a adelantarse, que es informacion mas util que la puntuacion.
