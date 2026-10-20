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

## Validación pendiente de producto

- Repetir en iPhone/iPad las rutas de Resultados y la preparación de checkpoint
  indicadas en `docs/IOS_HARDWARE_TESTS.md`; la compilación no verifica su interacción.
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
