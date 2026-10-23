# Interfaz

## Notacion

Notas que viajan por una autopista trapezoidal hacia una línea de golpe fija,
cerca del borde inferior. La coordenada temporal permanece lineal; la perspectiva
solo estrecha la pista y escala las notas hacia el horizonte.

**Perspectiva suave.** La justa para dar profundidad y anticipacion. Una fuga
dramatica convierte la parte alta de la pantalla en papilla, porque la
perspectiva comprime el tiempo al fondo y las notas lejanas se apelotonan justo
donde quieres leer subdivisiones.

**Marcas de pulso y subdivisión** siguen la geometría de la pista. La distancia
temporal entre marcas no cambia con la perspectiva: el ojo puede leer "justo
después del tercer tiempo" sin estimar píxeles.

**Anticipacion: dos compases.**

## Carriles

La autopista muestra un carril por sonido presente en la sesión. Los sonidos que
no participan no ocupan espacio: al haber menos carriles son más anchos y las
notas se leen antes. La distribución se fija al preparar la práctica y se
mantiene durante toda la frase, incluidos los compases en los que un sonido
guarda silencio.

La pista permanece centrada y tiene un ancho máximo según sus voces, medido en
la línea de golpe: 320/400 pt para una/dos, 600/720 pt para tres/cuatro y
800/880/960/1.000 pt para cinco a ocho. Nunca supera el 92 % del ancho disponible.
Ampliar la ventana por encima de ese límite añade márgenes oscuros, no estira los
carriles. La altura y la anticipación temporal no cambian.

Notas y receptores usan la misma proyección: los receptores se estrechan con la
pista, mientras las notas tienen un tamaño base máximo de 44 × 34 pt y se reducen
si falta espacio en el carril. La decoración lateral ocupa solo una franja tenue
de hasta 96 pt junto a la autopista; con margen suficiente el indicador de vuelta
queda fuera de los carriles.

**El orden lo dicta el mapeo de pads, no este documento.** La rejilla fisica de
4x4 se aplana asi: fila inferior de izquierda a derecha, luego la siguiente
hacia arriba. Si el usuario remapea, los carriles se reordenan solos.

Los receptores mantienen el nombre del sonido junto a la línea de golpe. Si el
carril es ancho se usa el nombre completo del kit; en frases con muchas voces se
abrevia para conservar la legibilidad.

Esto solo afecta a la escena de práctica. La rejilla física de Equipo conserva
sus 16 posiciones y el mapeo MIDI no cambia (D-033, D-048). Un golpe extra en un
pad fuera de la frase sigue mostrando el juicio, aunque no tenga carril.

## Avisos de cambio

Antes de una variación importante aparece un aviso breve sobre la autopista y
una banda de color cruza la rejilla en el momento del cambio:

- «Entra …» cuando aparece por primera vez un sonido nuevo tras el compás inicial;
  la banda apunta a su primer golpe real, no al comienzo del compás.
- «Se acerca el cierre» antes del último compás de la última vuelta.
- «Última vuelta» al empezar la repetición final.

Solo se muestra un aviso a la vez: primero el cambio más próximo y, si coincide
en el tiempo, la entrada de un sonido tiene prioridad sobre el cierre.
El aviso anticipa como máximo 2,4 segundos y nunca repite la
misma indicación en cada vuelta. Es una ayuda visual: no altera notas, matching
ni puntuación. Un sonido que regresa tras un silencio no genera otra entrada.
En Transferir se ocultan las entradas y sus nombres; se mantienen los avisos
de cierre y última vuelta.

## Identidad visual de las notas

| Sonido | Color de referencia |
|---|---|---|
| Bombo | Azul `#26B8FF` |
| Caja | Coral `#FF5E7A` |
| Charles cerrado | Verde `#59DB9E` |
| Charles abierto | Turquesa `#45C7D1` |

Cada nota, carril y receptor comparte el acento del sonido. La silueta es común:
la práctica no marca mano izquierda/derecha ni imprime L/R sobre las notas.
El mapa de colores canónico está en `GameplayVisualTheme.soundAccent(_:)`.

Las etiquetas de sonido en los receptores y la posición fija del carril refuerzan
el color. El juicio usa una capa aparte y nunca cambia el color de identidad de
la nota.

Reparto de responsabilidades:

- **Carril** indica que sonido.
- **Color compartido** identifica el sonido en la nota, el carril y el receptor.

## Cuenta de entrada

Un compas audible.

**Cuidado con la sincronia:** si la anticipacion son dos compases y la cuenta
dura uno, las notas tendrian que aparecer antes de que empiece la cuenta. Si no,
la primera nota entra sin preaviso y se falla siempre.

**El desplazamiento visual arranca dos compases antes de la primera nota, y la
cuenta audible suena durante el ultimo.** Asi el principio se ve venir con la
misma anticipacion que todo lo demas.

## Escuchar y colocar

Antes de puntuar, el usuario puede reproducir una vuelta completa en modo previo.
La app toca el patron, mueve las mismas notas e ilumina las posiciones que se
deben golpear, pero no registra puntuacion. La pantalla indica la colocacion de
las manos y permite repetir o empezar. En el primer intento de cada nivel esta
pantalla se abre automaticamente; despues sigue disponible como opcion.

## Retroalimentacion

- Destello de juicio en la linea de golpe, con el color del juicio.
- Etiqueta e icono de juicio; el color nunca es la unica senal.
- Flecha izquierda si el golpe fue adelantado y derecha si fue atrasado, junto
  con el desvio en milisegundos.
- El golpe pulsa el receptor y puede emitir un anillo y pocas partículas dentro
  de la zona de pads; los efectos no desplazan la línea ni las notas pendientes.
- Los aciertos consecutivos Perfect/Good hacen respirar los carriles activos y
  animan las separaciones como ondas progresivamente más rápidas e intensas.
- Al terminar: puntuacion sobre el total posible, estrellas, y el desvio medio
  redactado en lenguaje llano.

El color de sonido permanece en la nota. El juicio se presenta en una capa
separada para no confundir identidad de sonido con precisión temporal.

## Rendimiento

La vista de notas va en SpriteKit para reducir el riesgo de redibujar muchas
vistas SwiftUI en la grafica Intel integrada de la maquina de referencia. La fase
3 debe verificar 60 fps estables en esa maquina; hasta medirlos son un objetivo,
no un resultado.

El reloj musical se toma **del motor de audio**, nunca de un temporizador de
interfaz. Un temporizador de interfaz deriva, y en cuatro vueltas la deriva ya
es audible.

## Teclado de repuesto

El teclado del portatil funciona como pads. Sirve para desarrollar sin hardware
y para que alguien pruebe la app sin comprar nada. Su calibracion de latencia se
guarda por separado.

## Dirección visual vigente

La especificación detallada está en [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md). La experiencia se organiza alrededor de Inicio, Curso, Preparación, Práctica, Resultado, Progreso y Equipo.

Durante la ejecución solo se muestran nombre, BPM, vuelta y pausa. El score acumulado y las estrellas no compiten con la siguiente nota.

## Resultado diagnóstico

Al completar una estación nueva, la celebración encabeza Resultado: tren,
estrellas del intento, siguiente parada y «Siguiente parada». Al finalizar
la línea ofrece «Ver mi recorrido». Los detalles siguen consultables debajo.
La celebración usa elementos estáticos y no añade movimiento obligatorio.
Una lección completa pendiente que cuesta ofrece apoyo automático del mismo
patrón con guía completa, menos repeticiones y cuatro BPM menos. Un buen intento
lento propone acercarse al objetivo en pasos de 2–4 BPM; no se sustituye por un
salto al siguiente premio de velocidad. La acreditación sigue ligada al tempo
objetivo y al 70 %, y las prácticas parciales conservan su flujo específico.

Orden:
1. diagnóstico en lenguaje claro;
2. precisión, tendencia y consistencia;
3. microscopio temporal;
4. resultado por voz/rol/subdivisión;
5. recomendación y acciones.

## Metro del Ritmo

Los quince bloques principales son estaciones conectadas por vías. El tren se
sitúa en la parada actual. Curso destaca «Empezar nivel N» o «Preparar reto final».
La estación actual queda abierta; las otras se resumen con su estado y contador.
El reto final de cada estación se señala con una bandera. Los nombres cortos y
la numeración son locales a la estación.

Abrir otra estación permite explorar sus niveles. Los retos de tempo y sus premios
pertenecen al ejercicio; no se confunden con el siguiente nivel del recorrido.
El reto final reúne las habilidades de la estación y usa el tempo de aprendizaje.
Mapa, premios, acciones y celebraciones se renderizan con las mismas vistas
compartidas en Mac e iPhone; cada coordinador adapta únicamente la navegación.

### Ilustraciones ferroviarias

La tarjeta del siguiente nivel incluye una escena vectorial de dos vagones,
ciudad, vías y andén con el número de estación. Cada parada tiene un pequeño
distintivo musical; al completarla, la escena usa acentos dorados y destellos.
Los paneles destacados añaden un degradado suave para separar sus planos.

Los dibujos viven en `RailwayArtwork.swift`, compartido entre macOS e iOS.
Son estáticos, no reciben toques y se ocultan a VoiceOver: nombre, progreso y
acciones siguen siendo texto accesible. No añaden controles ni aparecen sobre
la escena de práctica.

## Layouts

### Práctica táctil iOS

Sin controlador MIDI se muestran solo los botones de los sonidos que debe tocar
el usuario. Cada sonido ocupa un botón salvo objetivos explícitos por rol/pad.
La selección incluye todos los compases de la sesión y permanece fija al tocar;
en calibración se muestra solo el charles. Los nombres salen del kit.

La rejilla es virtual y compacta: ajusta filas y columnas, amplía la última fila
incompleta y reduce la altura del panel cuando hay pocas voces. En horizontal,
una a tres voces usan una columna lateral más estrecha para devolver anchura al
escenario. Dibujo, toques y marcos de VoiceOver comparten la misma geometría.
Esto no transforma el mapa físico de Equipo ni la entrada MIDI (D-048).

`Equipo → Pads y layout` permite elegir Core, Drum Kit o Mirror. Cada preset
conserva las notas MIDI físicas aprendidas y actualiza la vista 4×4.

El mapa físico conserva sus 16 posiciones en Equipo, pero la práctica muestra una
única pista y un único cuadrado objetivo por sonido. Si hay varios pads para el
bombo, cualquiera sigue resolviendo al mismo sonido y el scoring conserva sus
objetivos por rol/pad; la vista no duplica la nota en cada pad alternativo.
