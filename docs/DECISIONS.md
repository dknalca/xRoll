# Decisiones

Cada entrada lleva su motivo. Sirven para poder revisarlas el dia que el motivo
deje de aplicar, no para grabarlas en piedra.

## D-001 - El nombre es xRoll

Un roll es un rudimento real, palabra de una silaba que se entiende sin saber de
bateria. Ademas *piano roll* es exactamente la notacion que usa la app: notas
cayendo por carriles. El nombre describe la tecnica y la interfaz a la vez.

Se comprobaron colisiones: existe un token de criptomoneda homonimo y una marca
de maquinaria de carpinteria "X-Roll", con guion y en otro sector. En software
musical, nada.

## D-002 - Solo pads, no bateria real

El objetivo es finger drumming. No hay que modelar el comportamiento de una
bateria acustica: ni pedal de charles, ni rebote, ni posicion del golpe en el
parche. Simplifica enormemente el motor de audio y es lo que el usuario tiene.

## D-003 - Sin velocity

Todos los golpes valen igual. Anadir dinamica multiplicaria las variables que el
principiante tiene que controlar a la vez, y el objetivo inicial es unicamente
el tiempo. Queda como futurible para ejercicios de dinamica.

## D-004 - Posicion fija, visibilidad variable

Los sonidos que no participan en el ejercicio se muestran apagados, no
desaparecen. Si desaparecieran, los demas se recolocarian y cada ejercicio
tendria una geometria distinta.

**Por que:** la memoria espacial es la habilidad que se entrena. Mover los
elementos entre ejercicios la destruye, que es exactamente lo contrario de lo
que la app deberia hacer.

## D-005 - El orden de las posiciones deriva del mapeo de pads

La rejilla fisica de 4x4 se aplana a dieciseis posiciones: fila inferior de
izquierda a derecha, luego la siguiente. Si el usuario remapea sus pads, las
posiciones se reordenan solas. Los pads libres conservan un hueco apagado.

**Por que:** si el bombo esta abajo a la izquierda en el pad y en el centro de
la pantalla, el usuario hace una transposicion mental en cada nota. Esa carga
cognitiva es justo la que la memoria espacial deberia eliminar.

## D-006 - Notacion vertical con perspectiva suave

Notas cayendo hacia una linea de golpe, con profundidad ligera para anticipar
los cambios.

**El riesgo:** la perspectiva comprime el tiempo al fondo, y las notas lejanas se
apelotonan justo donde quieres leer subdivisiones.

**La mitigacion:** perspectiva contenida, nunca una fuga dramatica, y lineas de
pulso y subdivision cruzando los carriles. Con la rejilla dibujada el ojo lee
"justo despues del tercer tiempo" en vez de "a treinta y ocho pixeles", y la
compresion deja de importar.

## D-007 - Circulo y cuadrado, no pentagono y circulo

Dos formas, las mas distintas posibles: circulo para la mano izquierda, cuadrado
para la derecha.

**Por que:** a sesenta pixeles y en movimiento el ojo lee siluetas, no vertices.
Un pentagono se lee como un circulo. La distincion tiene que sobrevivir al
tamano y a la velocidad reales.

## D-008 - Paleta Okabe-Ito

Azul #0072B2 para la izquierda, naranja #E69F00 para la derecha. Diseñada para
ser distinguible en todos los tipos de daltonismo. El color siempre va reforzado
por la forma: la codificacion redundante es la buena practica, y entre un 5 y un
8 por ciento de los hombres tiene alguna deficiencia de vision del color.

## D-009 - Cuatro niveles de juicio, no tres

Perfecto, Bien, Regular, Fallo. Regular existe especificamente para que un
principiante no se lleve cero constantemente en sus primeras sesiones.

Y una estrella se consigue al 50 por ciento, no al 60, por el mismo motivo.

## D-010 - Se indica si el golpe llego pronto o tarde

**Por que:** los principiantes casi nunca fallan al azar, van sistematicamente
adelantados o atrasados. "Regular" a secas es un reproche. "Regular, vas 40 ms
adelantado" es una instruccion. Cuesta practicamente nada y cambia por completo
la sensacion de usar la app.

## D-011 - La calibracion de latencia es obligatoria

Con ventanas de +/- 35 ms, un desfase de 20 ms sin compensar desplaza todos los
golpes sistematicamente y se come dos tercios de la ventana perfecta. El usuario
concluye que toca mal cuando en realidad toca bien. Es el fallo silencioso que
arruina los juegos de ritmo mal hechos.

## D-012 - El MVP arranca solo con claqueta

Los loops de acompanamiento entran en la fase 7, cuando el motor de puntuacion
ya funcione. Se descarto sintetizar acompanamientos provisionales: no es
dificil, pero un groove de referencia con mal feel ensena mal, y ademas se
tiraria entero. Una claqueta no puede sonar mal.

El MVP termina al completar la fase 5. El historial y los loops son ampliaciones
posteriores: ayudan a practicar, pero no son necesarios para validar que entrada,
audio, notacion, puntuacion y progresion de ejercicios forman un entrenador util.

## D-013 - GPL-3.0-or-later para el codigo, CC BY-SA 4.0 para el resto

Los requisitos eran: abierta, poca friccion para quien contribuya, y que un fork
no pueda cerrarla. El copyleft es lo unico que cumple el tercero. Sin CLA se
cumple el segundo.

La contrapartida asumida: sin CLA el proyecto **nunca** podra relicenciarse, ni
siquiera para abrirlo mas. Se acepta a proposito.

La distribucion sera por DMG o Homebrew, no por la Mac App Store, cuyas
condiciones son incompatibles con la GPL. No es una perdida porque no estaba en
los planes.

El audio y los graficos son obras separadas y la licencia del codigo no las
cubre. CC BY-SA es ademas la eleccion coherente con las dos procedencias
posibles: un loop CC0 puede ponerse bajo BY-SA, y uno que ya venia BY-SA debe
mantenerse asi.

## D-014 - Un solo kit, nunca importado por el usuario

Un kit para arrancar, dos o tres predefinidos mas adelante. Permitir kits
propios abriria un frente de soporte enorme (formatos, longitudes, niveles
dispares) a cambio de poco valor para el publico objetivo.

## D-015 - Compas de 4/4 y un BPM fijo por ejercicio

Con BPM fijo el loop de acompanamiento encaja exacto y suena perfecto. Permitir
un rango obligaria a estirar el audio con la degradacion consiguiente. Para
cambiar de tempo se sale y se elige otro ejercicio.

## D-016 - Dieciseis posiciones visuales, incluidos los huecos

La interfaz conserva las dieciseis posiciones del controlador 4x4 aunque el kit
solo tenga once sonidos. Comprimir los cinco pads libres haria que dos sonidos
fisicamente separados apareciesen juntos en pantalla y debilitaria la memoria
espacial que se quiere entrenar.

La contrapartida es una anchura de unos 80 puntos por posicion en la maquina
objetivo. Por eso la ejecucion usa pantalla completa y deja los controles fuera
del area de juego.

## D-017 - Calibracion guiada por ruta completa

La calibracion se guarda por entrada, salida, frecuencia de muestreo y buffer.
Guardar solo el controlador es insuficiente: cambiar de altavoces a auriculares
puede cambiar el desfase aunque el pad siga siendo el mismo.

La prueba de usuario compensa el conjunto practico y puede contener su tendencia
personal al seguir la claqueta. La medicion fisica de la fase 0 sigue siendo la
puerta objetiva de latencia.

## D-018 - Un nivel introduce una sola dificultad

La progresion no obliga a anadir un sonido en cada nivel. Tambien puede consolidar
un patron o cambiar el tempo, pero solo una de esas cosas a la vez. Un principiante
necesita practicar una coordinacion antes de acumular otra voz encima.

Cada nivel ofrece primero una vuelta de escucha y colocacion sin puntuacion. La
orientacion previa reduce errores que no son de tiempo, como no recordar que pad
o que mano corresponde.

Como referencia de producto se reviso el enfoque publico de Melodics: orientacion
previa, contenido dividido en pasos, practica deliberada y evaluacion inmediata.
xRoll adopta para el MVP la orientacion y los pasos pequenos; tempo automatico,
modo de espera, rachas y objetivos diarios quedan fuera del alcance inicial.

Referencias consultadas el 5 de septiembre de 2026:

- https://melodics.com/how-it-works
- https://support.melodics.com/en/articles/6777061-get-started-with-melodics
- https://support.melodics.com/en/articles/8051176-the-melodics-approach
