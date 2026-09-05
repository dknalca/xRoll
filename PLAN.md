# Plan de xRoll

Cada fase termina en algo que se puede ejecutar y comprobar. No se pasa de fase
con la anterior a medias.

**Alcance del MVP:** fases 0 a 5 inclusive. Las fases 6 y 7 son ampliaciones
posteriores y no condicionan la primera version util.

## Fase 0 - Puerta de latencia

**El riesgo que mata el proyecto se mide primero.** Si esta maquina con este
controlador no baja de 20 ms, todo lo demas sobra.

- Proyecto Swift minimo: AVAudioEngine reproduciendo un sample al recibir una
  nota MIDI.
- Medir el recorrido completo: golpe en el pad hasta sonido audible.
- Probar varios tamanos de buffer y anotar el mas bajo que aguanta sin cortes.
- Hacer la prueba con el sample definitivo aportado para el kit, conectado por
  USB y usando la salida de audio realmente elegida para tocar. La primera
  medicion se hara con la Rane Seventy-Two conectada a 48 kHz y 512 fotogramas.

La medida extremo a extremo se obtiene con una grabacion externa que recoja en
la misma pista el golpe fisico sobre el pad y el sonido del Mac. La medida
interna desde la llegada del MIDI hasta el render de audio se conserva como
diagnostico, pero no sustituye a la medida fisica.

**Criterio de paso:** en una serie de 100 golpes, mediana de 15 ms o menos,
percentil 95 de 20 ms o menos y diez minutos de uso sin cortes. Si la mediana
queda entre 15 y 20 ms se continua dejando constancia. Por encima de 20 ms hay
que parar y replantear antes de escribir una linea mas.

**Entregable:** un numero medido, con el metodo descrito y la salida real.
El protocolo y la plantilla de resultados estan en docs/LATENCY_PROTOCOL.md.

## Fase 1 - Entrada y sonido

- Enumerar dispositivos CoreMIDI y abrir el SMC-Pad por USB.
- Reproducir el sample correcto al recibir cada nota.
- Teclado del portatil como pads de repuesto, para poder trabajar sin hardware.
- Carga de kit.json y de los wav.
- Salida mediante el dispositivo predeterminado de macOS. Altavoces internos y
  auriculares por cable son las rutas del MVP; cada una se calibra por separado.

**Criterio de paso:** golpeas y suena, con teclado y con pads.

## Fase 2 - Mapeo

- Menu de asignacion con la disposicion sugerida por defecto.
- Asistente de aprendizaje: se ilumina un sonido, golpeas el pad que le toca.
- Deteccion de duplicados en el momento.
- Guardar y cargar ficheros .padmap.
- El MVP acepta mensajes Note On. Los mensajes CC quedan fuera hasta que un
  controlador objetivo demuestre que son necesarios.

**Criterio de paso:** un usuario con los pads reconfigurados de fabrica puede
dejarlos funcionando en menos de un minuto.

## Fase 3 - Motor de tiempo y notacion

- Reloj musical estable, con el audio como referencia y nunca un temporizador de
  interfaz.
- Vista SpriteKit de notas cayendo, perspectiva suave, lineas de pulso y
  subdivision.
- Anticipacion de dos compases. El desplazamiento arranca dos compases antes de
  la primera nota y la cuenta audible suena durante el ultimo.
- Claqueta con cuenta de entrada de un compas.
- Pantalla previa "Escuchar y colocar": reproduce una vuelta sin puntuacion,
  ilumina las notas y permite repetirla antes de empezar.

**Criterio de paso:** un ejercicio se reproduce entero, a tiempo, sin deriva a
lo largo de cuatro vueltas.

## Fase 4 - Puntuacion

- Ventanas de juicio, con recorte automatico segun la subdivision.
- Penalizacion de toques de mas.
- Indicacion de adelantado o atrasado en cada golpe.
- Estrellas y porcentaje sobre el total posible.
- Calibracion guiada tras elegir entrada, mapeo y salida de audio.

**Criterio de paso:** el mismo ejercicio tocado deliberadamente pronto, tarde y
a tiempo produce los tres juicios esperados.

## Fase 5 - Contenido (cierre del MVP)

- Familia de ejercicios de hip hop con progresion por escalera.
- Suficientes niveles para llevar a alguien de cero a un groove completo.
- Cada nivel introduce una sola dificultad: un sonido, un cambio de patron o un
  cambio de tempo. Antes de evaluar, el usuario puede escuchar el nivel.

**Criterio de paso:** alguien que no sabe tocar completa el nivel 1 sin ayuda.

## Fase 6 - Progreso

- SQLite, una fila por intento.
- Contador de veces realizadas, mejor puntuacion, curva de progreso.

**Criterio de paso:** se ve la mejora entre el primer intento y el decimo.

## Fase 7 - Acompanamiento

- Carga de loops desde carpeta, emparejados por BPM.
- Mezcla con la claqueta, volumen independiente.
- Validacion al cargar: aviso si el loop no da un numero entero de compases.

**Criterio de paso:** cuatro vueltas del loop sin desfase audible.

## Futuribles

Ideas aceptadas que no entran todavia. No condicionan el diseno actual salvo
donde se indica.

- **Modo calentamiento.** Repaso de los ejercicios ya dominados con variantes.
- **Variantes de ejercicio.** Cambios de tempo, cambios de tono, y sobre todo
  **entrada desplazada**: empezar el patron por el segundo tiempo o por la
  contra en lugar de por el principio. La sonoridad cambia por completo y es un
  ejercicio excelente. El formato de ejercicio ya reserva sitio para esto.
- **Duracion configurable.** Desplegable en vez de cuatro vueltas fijas.
- **Canciones con stems.** Importar una cancion, retirar el stem de bateria y
  sustituirlo por una pista MIDI que sirva de patron a imitar. BPM fijo.
- **Mas kits predefinidos.** Dos o tres. Nunca importados por el usuario.
- **Velocity.** Ejercicios de dinamica y golpes fantasma.
- **Bluetooth.**
- **Mensajes MIDI CC como pads.** Se anaden cuando exista un controlador objetivo
  que los necesite; requieren umbral y deteccion de flanco propios.
- **Separacion de stems en la propia app.** Muy lejano.
