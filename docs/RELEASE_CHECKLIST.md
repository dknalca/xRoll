# Validación antes de publicar

## Ya automatizado

- `swift build` compila todos los ejecutables y la ventana macOS.
- `swift test` valida recursos, MIDI, mapeos, reloj, puntuacion, calibracion y
  sesiones de practica.
- `swift run xroll-preflight` valida kit, WAV y ejercicios; devuelve error si
  falta cualquier sample obligatorio.
- CI compila el target genérico iOS con firma desactivada; la firma del dispositivo
  depende de la cuenta y el perfil local de Apple Developer.
- Las regresiones de continuación recorren todos los checkpoints del catálogo
  real. Las pruebas de audio offline inspeccionan 96 golpes rápidos renderizados,
  choke abierto/cerrado, aislamiento de otros sonidos y reinicio del motor.
- `zsh scripts/build-ios-ipa.sh` compila Release universal iPhone/iPad y verifica
  estructura ZIP, firma ad-hoc, arquitectura arm64, familias y recursos del IPA.
- Las pruebas de PCM programado comprueban ganancia por golpe/claqueta, ataques
  tras reutilizar nodos, choke, cancelación y límites/reutilización de la caché.
- Regresiones de contenido: las diez rutas de género conservan en el cierre
  sus voces y posiciones rítmicas, y no exigen tres golpes simultáneos. Hip-hop
  y Jazz intermedio tienen 12 lecciones; las demás rutas tienen 8. Reggae contiene grooves en todos sus compases.
  Las frases no multiplican la duración inicial. Los umbrales de estrellas se
  comprueban antes del redondeo y después de penalizar golpes extra.
- `XRollUITests` comprueba catorce rutas de navegación en simulador; CI conserva su
  resultado. Los resultados sintéticos no validan calibración ni latencia física.
- El recorrido se comprueba con una única estación actual y un reto final por
  estación; solo celebra acreditaciones nuevas de patrón completo y se reconstruye
  al reabrir SQLite. Las pruebas UI cubren mapa ferroviario, preparación del reto
  y celebración → siguiente parada. Ambas apps compilan la misma vista compartida.
- La proyección táctil prueba selección de sonidos, deduplicación, objetivos por
  rol/pad y voces disponibles de todo el catálogo en Core, Drum Kit y Mirror.
  Las regresiones UI comprueban dos botones grandes, ocho voces, sus zonas de
  toque y el giro a horizontal sin cerrar la app.
- La progresión comprueba que todas las lecciones pendientes se preparan a un
  tempo acreditable, que el apoyo vuelve al objetivo sin saltos mayores de cuatro
  BPM ni premios ficticios y que la calibración sigue siendo un charles regular.
   El tronco común conserva grooves y sus cierres no introducen células inéditas.
- Las regresiones de avisos comprueban entradas al golpe real, silencios y
  retornos de voces ya conocidas. Un resultado corto a 160 BPM mantiene pendiente
  el reto de 16 compases, sin conceder premios de otros tempos.
- El historial conserva timestamps subsegundo al exportar/restaurar y revierte
  importaciones con valores escalares inválidos. Un catálogo MIDI vacío produce
  un error recuperable. El pulso interno distingue contratiempos audibles de
  golpes dentro del silencio de la claqueta.

## Completado en hardware

- Reconexión MIDI y layouts Core, Drum Kit y Mirror comprobados en controlador
  real.
- Teclado, vista previa y práctica comprobados en hardware.
- Diez minutos de práctica densa sin cortes ni tirones perceptibles.
- VoiceOver, Reduce Motion, contraste y teclado comprobados en macOS.
- Licencias de los WAV distribuidos confirmadas como propias.
- Licencias de los loops distribuidos confirmadas como propias.
- Calibración guiada comprobada para la ruta de uso actual.
- Cierre, reinicio y navegación durante la práctica comprobados con entrada MIDI;
  no quedan resultados ni feedback de sesiones anteriores.
- Calibración macOS comprobada después de Transferir, ayuda Reducida y Gap
  Metronome; conserva notas visibles y claqueta continua.
- Las mitades de frases de varios compases aíslan la mitad correcta en macOS e
  iOS.
- La práctica interrumpida no crea intentos completos ni concede premios de
  duración.
- Preparación, demostración, regreso a Preparación y comienzo de práctica
  comprobados en macOS; se conservan las opciones elegidas.
- Preparación comprobada en iPhone vertical e iPad; acciones, duración y acceso a
  calibración permanecen legibles.
- Core, Drum Kit y Mirror comprobados en macOS e iOS: un carril por sonido, sin
  huecos por pads duplicados, con feedback común y orden estable.

## Pendiente en hardware

- Calibrar de nuevo si cambia la ruta de uso: entrada, salida, frecuencia o
  buffer.
- Repetir, reiniciar y reanudar en macOS con una ruta sin calibrar debe solicitar
  calibración; en iOS, comprobar también el buffer/frecuencia efectivos después
  de reactivar audio desde pausa.

## Validación pendiente de producto

- Recorrer Fundamentos → Coordinación → Subdivisión → Groove con una persona
  principiante y otra con experiencia; valorar continuidad, dificultad y interés.
  Comprobar el reintento con guía y retorno gradual al tempo objetivo en hardware.
- En iPhone/iPad táctil, comprobar tamaños y legibilidad con una, dos y ocho voces,
  giro durante la práctica, calibración de charles y práctica por voces. Equipo
  debe mantener las 16 posiciones; los pads no deben cambiar durante una frase.
- En macOS, redimensionar la práctica con una, tres y ocho voces: la autopista
  sigue centrada, deja de ensancharse al alcanzar su límite y mantiene notas,
  receptores, feedback y rejilla alineados. Repetir en iPad y ventana estrecha.
- Comprobar el recorrido en Mac e iPhone/iPad: vías, tren, legibilidad de las
  estaciones y niveles, reto final y continuación a la parada correcta con el
  historial real. El lenguaje y las acciones deben coincidir entre plataformas.
- Revisar ilustraciones y distintivos en pantallas pequeñas y con texto grande;
  confirmar que no tapan el botón principal y que la decoración no recibe toques
  ni añade elementos de navegación a VoiceOver.
- Repetir en iPhone/iPad las rutas de Resultados y la preparación de checkpoint
  indicadas en `docs/IOS_HARDWARE_TESTS.md`; la compilación no verifica su interacción.
- Seleccionar una lección posterior desde Curso y confirmar que Preparación
  muestra su nivel y arranca ese mismo ritmo, sin ofrecer «Empezar siguiente paso».
- Repetir charles vivo por MIDI con la salida Bluetooth del caso reportado:
  comprobar semicorcheas, golpes agrupados y abierto/cerrado con el nuevo choke
  que protege ataques pendientes. PCM offline no confirma esa ruta física.
- Medir 60 FPS con la escena de máxima densidad durante diez minutos.
- En el ejercicio de semicorcheas de charles cerrado, confirmar a 160 BPM y
  también al tempo máximo que cada ataque se reproduce de inmediato, corta la
  cola del charles anterior y no se retrasa; comprobar práctica MIDI, demostración
  y preview en hardware.

## Distribución firmada

- Firmar y notarizar el bundle macOS con una identidad Developer ID antes de
  publicar el release o distribuir la aplicación por cualquier canal.
- Confirmar un perfil de desarrollo iOS válido antes de cada despliegue en
  hardware; el 6 de octubre de 2026 se instaló el bundle actual con firma
  automática en el iPad de prueba.

## Validación de layouts

- Migración v1→v2 con copia de seguridad.
- Duplicados resuelven un único objetivo `any`.
- Roles y pads exactos no se aceptan indistintamente.
- Orientación no corrompe MIDI.
- Cada ejercicio declara requisitos.

## Validación didáctica

- Una dificultad principal nueva por nivel y ayudas reducidas comprobadas.
- Métricas de sesgo y dispersión no se confunden con latencia.
- El coaching solo afirma mejora en un retorno al groove con condiciones
  equivalentes; un repaso insuficiente no se registra como fallo de retención.
- El pulso interno avanza tras dos rondas equivalentes y los silencios/análisis
  se comprueban en ejecución con los niveles 1–3.
- La rutina diaria se retoma tras cerrar la app; omitir un bloque no lo acredita y
  los repasos vencidos aparecen en la siguiente sesión diaria.
