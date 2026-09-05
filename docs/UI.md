# Interfaz

## Notacion

Notas cayendo en vertical hacia una linea de golpe situada cerca del borde
inferior, pero no pegada: hace falta hueco para ver la nota aterrizar y su
destello de juicio.

**Perspectiva suave.** La justa para dar profundidad y anticipacion. Una fuga
dramatica convierte la parte alta de la pantalla en papilla, porque la
perspectiva comprime el tiempo al fondo y las notas lejanas se apelotonan justo
donde quieres leer subdivisiones.

**Lineas de pulso y subdivision** cruzando todos los carriles. Son lo que
neutraliza esa compresion: con la rejilla dibujada, el ojo lee "justo despues del
tercer tiempo" en lugar de "a treinta y ocho pixeles".

**Anticipacion: dos compases.**

## Carriles

La ejecucion usa dieciseis posiciones, una por pad fisico. Los once sonidos
ocupan su posicion y los cinco pads libres se ven como huecos apagados. No se
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

## Manos

| Mano | Forma | Color |
|---|---|---|
| Izquierda | Circulo | Azul `#0072B2` |
| Derecha | Cuadrado | Naranja `#E69F00` |

Dos formas y las mas distintas posibles: a sesenta pixeles y en movimiento el
ojo lee siluetas, no vertices, y un pentagono se lee como un circulo.

La paleta es Okabe-Ito, distinguible en todos los tipos de daltonismo. **El color
nunca va solo**: siempre acompanado de la forma. Entre un 5 y un 8 por ciento de
los hombres tiene alguna deficiencia de vision del color, y la codificacion
redundante lo resuelve a coste cero.

Reparto de responsabilidades, que conviene no mezclar:

- **Carril** indica que sonido.
- **Forma y color juntos** indican que mano.

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
- Al terminar: puntuacion sobre el total posible, estrellas, y el desvio medio
  redactado en lenguaje llano.

El color de mano permanece en la nota. El juicio se presenta en una capa
separada para que el naranja de la mano derecha no pueda confundirse con un
golpe adelantado, convencion que usan otras aplicaciones.

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
