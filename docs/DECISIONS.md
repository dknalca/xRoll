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

## D-003 - Velocity leida, no evaluada

Los archivos y eventos MIDI pueden conservar velocity para compatibilidad
futura. Todos los golpes valen igual: la velocity no se usa para sonido,
feedback, requisitos ni puntuacion. Anadir dinamica multiplicaria las variables
que el principiante tiene que controlar a la vez, y el objetivo inicial es
unicamente el tiempo.

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

## D-013 - MIT para todo el proyecto

xRoll usa MIT para código, audio, gráficos y documentación. Es una licencia
permisiva, apta para distribución comercial y para publicar en App Store de
iOS y macOS. Solo exige conservar el aviso de copyright y el texto de licencia.

La procedencia de cada recurso de audio continúa registrada por mantenimiento
técnico, aunque todos los recursos propios se distribuyan bajo MIT.

## D-014 - Un solo kit, nunca importado por el usuario

Un kit para arrancar, dos o tres predefinidos mas adelante. Permitir kits
propios abriria un frente de soporte enorme (formatos, longitudes, niveles
dispares) a cambio de poco valor para el publico objetivo.

## D-015 - Compas de 4/4, BPM nominal fijo y practica temporal configurable

Cada MIDI declara un BPM nominal fijo: es la referencia del contenido, de los
loops compatibles y del dominio. La practica puede usar un BPM temporal sin
modificar el MIDI ni crear un ejercicio nuevo.

Esto permite preparacion manual, Autopilot, Whale y pruebas de elasticidad. La
configuracion temporal no altera el orden curricular ni sustituye el BPM nominal
del ejercicio.

## D-016 - Dieciseis posiciones visuales físicas

La interfaz conserva las dieciseis posiciones del controlador 4x4 aunque el kit
solo tenga diez sonidos. Core repite las voces principales en las seis posiciones
restantes. Comprimir la matriz haría que dos sonidos físicamente separados
apareciesen juntos en pantalla y debilitaría la memoria espacial que se quiere
entrenar.

La contrapartida es una anchura de unos 80 puntos por posicion en la maquina
objetivo. Por eso la ejecucion usa pantalla completa y deja los controles fuera
del area de juego.

## D-017 - Calibracion guiada por ruta completa

La calibracion se guarda por entrada, salida, frecuencia de muestreo y buffer.
Guardar solo el controlador es insuficiente: cambiar de altavoces a auriculares
puede cambiar el desfase aunque el pad siga siendo el mismo.

La prueba guiada compensa el conjunto práctico, incluida la tendencia del
usuario al seguir la claqueta. La aplicación no requiere una medición física;
las herramientas de grabación quedan como diagnóstico interno.

## D-018 - Un nivel introduce una sola dificultad

La progresion no obliga a anadir un sonido en cada nivel. Tambien puede consolidar
un patron o cambiar el tempo, pero solo una de esas cosas a la vez. Un principiante
necesita practicar una coordinacion antes de acumular otra voz encima.

Cada nivel ofrece primero una vuelta de escucha y colocacion sin puntuacion. La
vista previa reduce errores que no son de tiempo, como no recordar que pad o que
mano corresponde.

Como referencia de producto se reviso el enfoque publico de Melodics: contenido
dividido en pasos, practica deliberada y evaluacion inmediata. xRoll adopta para
el MVP los pasos pequeños; tempo automático, modo de espera, rachas y objetivos
diarios quedan fuera del alcance inicial.

Referencias consultadas el 5 de septiembre de 2026:

- https://melodics.com/how-it-works
- https://support.melodics.com/en/articles/6777061-get-started-with-melodics
- https://support.melodics.com/en/articles/8051176-the-melodics-approach

## D-019 - La propuesta es diagnóstico, no solo puntuación

El resultado prioriza precisión, tendencia, consistencia y una recomendación. Las estrellas permanecen como resumen secundario.

## D-020 - La calibración guiada compensa por ruta

La mediana guiada se aplica como `scoringCompensationMs` para la ruta completa.
El sesgo bruto de cada sesión permanece disponible para diagnóstico; no se
presenta como una medición técnica de hardware.

## D-021 - La interfaz sigue «Estudio musical moderno»

Interfaz oscura, profesional y precisa. Azul/naranja Okabe-Ito quedan reservados para manos. Durante la práctica se minimiza todo lo que compita con las notas.

## D-022 - El currículo tiene tronco común y rutas por género

Primero pulso, subdivisión, coordinación, síncopa y fraseo. Después hip-hop, rock, funk, blues/shuffle y jazz. Cada nivel introduce una dificultad principal.

## D-023 - Aprender exige transferencia

Los bloques terminan con ayudas reducidas. Superar siguiendo notas no demuestra que el groove se haya interiorizado.

## D-024 - xRoll ofrece layouts funcionales seleccionables

Core es el predeterminado de iniciación; Drum Kit favorece técnica de batería y
Mirror favorece alternancia. Los tres conservan las notas MIDI físicas del
controlador.

## D-025 - `.padmap` admite varios pads por sonido

La versión 2 separa sonido, posición, rol e input MIDI. Los objetivos pueden dirigirse a cualquier pad del sonido, a un rol o a una posición concreta.

## D-026 - La orientación se retira del producto

La reflexión diestra/zurda no aporta valor al flujo actual y complicaba la
validación de la posición física. Core, Drum Kit y Mirror tienen una única
distribución. El campo histórico de `.padmap` v2 se conserva solo para abrir
mapas ya guardados sin alterar sus notas ni canales MIDI.

## D-027 - MIDI es el único formato de ejercicios

Los ejercicios integrados y los comunitarios son Standard MIDI Files. El
cargador los convierte a un modelo interno validado; los metadatos didácticos
se derivan del ritmo o se incorporarán como extensión de MIDI, nunca como un
catálogo JSON paralelo.

## D-028 - El curso principal sigue una secuencia fija

El curso no abre rutas de género en paralelo. Tras el tronco común, las rutas se
recorren en este orden: Hip-hop, Rock, Disco, Funk, Reggae, Dembow,
Blues/Shuffle, Jazz y Clave/Bossa. Redobles es una ruta técnica transversal que
no bloquea el curso principal.

**Por qué:** el principiante necesita una única próxima estación clara. La
secuencia mantiene primero grooves binarios y coordinación, después síncopa y
espacio, y deja la rejilla ternaria e independencia de jazz para el final.

## D-029 - Progreso solo con evidencia equivalente al objetivo

Un intento se clasifica como ritmo completo, voces seleccionadas, fragmento,
correctivo o histórico desconocido. Solo un ritmo completo puede completar,
dominar, transferir o desbloquear una estación. Whale y las prácticas por voces
son herramientas de aprendizaje, no atajos de progreso.

**Por qué:** una célula aislada o una sola voz puede salir perfecta sin demostrar
que el usuario controla el groove completo.

## D-030 - El curso usa una escalera fija de seis tempos

Todos los ritmos se practican en Aprender (70 BPM, una estrella), Base (85 BPM,
dos estrellas), Consolidar (100 BPM, tres estrellas), Difícil (120 BPM, un
trofeo), Jefe (140 BPM, dos trofeos) y Nivel dios (160 BPM, tres trofeos durante
al menos 16 compases). Un ritmo solo completa su estación al alcanzar
Consolidar con al menos 70 %. Los requisitos para acreditar la estación y avanzar
se detallan en D-031.

**Por qué:** una escala fija hace comprensible el nivel técnico alcanzado en
cualquier estilo y evita que el curso avance por un resultado lento aislado.

## D-031 - Ruta guiada con exploración libre y checkpoints de capítulo

El orden principal del curso sigue siendo la recomendación predeterminada, pero
ningún ejercicio integrado queda bloqueado para practicar. El usuario puede
seleccionar directamente cualquier tempo de la escalera. Sus premios se ganan
solo con evidencia a ese tempo; practicar a 100 BPM no inventa estrellas a 70 ni
a 85 BPM.

Un capítulo se acredita cuando se superan todos sus ejercicios con ritmo
completo a Consolidar (100 BPM, 70 %) o cuando se supera su ejercicio MIDI
marcado `checkpoint` con esos mismos requisitos. El checkpoint debe representar
las habilidades del capítulo y ocupar la última posición del capítulo. Si se
supera por adelantado, la evidencia se conserva, pero la acreditación se activa
cuando se completa la ruta anterior. Los intentos parciales no acreditan ni el
ejercicio ni el capítulo. Los ejercicios de Redobles continúan siendo una ruta
técnica separada.

**Por qué:** un principiante conserva una siguiente acción clara; una persona con
experiencia puede demostrar lo que ya sabe sin tocar cada ejercicio básico. El
progreso acredita ejecución observable y no una autoevaluación subjetiva.

Esta decisión revisa la condición anterior de D-030 que exigía completar cada
ritmo de la estación. Se mantienen la secuencia, los seis tempos, el umbral de
Consolidar y el requisito de 16 compases para Nivel dios.

El MIDI debe declarar un único checkpoint en la última posición de cada
capítulo. Antes de usarlo para acreditar, su patrón se audita para incluir las
habilidades introducidas por el bloque. El validador rechaza checkpoints
ausentes, duplicados o que no estén al final.
