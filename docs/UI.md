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

La ejecución usa dieciséis posiciones, una por pad físico. Los diez sonidos
ocupan su posición y los seis pads libres se ven como huecos apagados. No se
comprimen, porque hacerlo cambiaria las distancias relativas del controlador.

En los 1280 puntos de ancho logico de la maquina objetivo quedan unos 80 por
posicion. La vista de ejecucion ocupa la pantalla completa y no muestra paneles
laterales; los controles se presentan antes y despues del ejercicio.

**El orden lo dicta el mapeo de pads, no este documento.** La rejilla fisica de
4x4 se aplana asi: fila inferior de izquierda a derecha, luego la siguiente
hacia arriba. Si el usuario remapea, los carriles se reordenan solos.

**Los sonidos que no participan en el ejercicio se muestran apagados, no se
retiran.** Los pads libres tambien conservan su hueco. Retirarlos recolocaria los
demas y cada ejercicio tendria una geometria distinta, que es lo que destruye la
memoria espacial.

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

Orden:
1. diagnóstico en lenguaje claro;
2. precisión, tendencia y consistencia;
3. microscopio temporal;
4. resultado por voz/rol/subdivisión;
5. recomendación y acciones.

## Metro del Ritmo

Los catorce bloques principales son estaciones conectadas por vías. El tren se
sitúa en la parada actual. Curso destaca «Empezar nivel N» o «Preparar reto final».
La estación actual queda abierta; las otras se resumen con su estado y contador.
El reto final de cada estación se señala con una bandera. Los nombres cortos y
la numeración son locales a la estación.

Abrir otra estación permite explorar sus niveles. Los retos de tempo y sus premios
pertenecen al ejercicio; no se confunden con el siguiente nivel del recorrido.
El reto final reúne las habilidades de la estación y usa el tempo de aprendizaje.
Mapa, premios, acciones y celebraciones se renderizan con las mismas vistas
compartidas en Mac e iPhone; cada coordinador adapta únicamente la navegación.

## Layouts

`Equipo → Pads y layout` permite elegir Core, Drum Kit o Mirror. Cada preset
conserva las notas MIDI físicas aprendidas y actualiza la vista 4×4.

El mapa físico conserva sus 16 posiciones en Equipo, pero la práctica muestra una
única pista y un único cuadrado objetivo por sonido. Si hay varios pads para el
bombo, cualquiera sigue resolviendo al mismo sonido y el scoring conserva sus
objetivos por rol/pad; la vista no duplica la nota en cada pad alternativo.
