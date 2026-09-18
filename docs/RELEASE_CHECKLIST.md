# Validación antes de publicar

## Ya automatizado

- `swift build` compila todos los ejecutables y la ventana macOS.
- `swift test` valida recursos, MIDI, mapeos, reloj, puntuacion, calibracion y
  sesiones de practica.
- `swift run xroll-preflight` valida kit, WAV y ejercicios.

## Completado en hardware

- Reconexión MIDI y layouts Core, Drum Kit y Mirror comprobados en controlador
  real.
- Teclado, vista previa y práctica comprobados en hardware.
- Diez minutos de práctica densa sin cortes ni tirones perceptibles.
- VoiceOver, Reduce Motion, contraste y teclado comprobados en macOS.
- Autoría y licencia MIT documentadas para seis WAV del kit.
- Calibración guiada comprobada para la ruta de uso actual.

## Pendiente en hardware

- Calibrar de nuevo si cambia la ruta de uso: entrada, salida, frecuencia o
  buffer.

## Diferido para distribución

- Completar la autoría y licencia de `rim.wav`, `tom_lo.wav`, `tom_hi.wav` y
  `ride.wav` en `Resources/Loops/ATTRIBUTION.md` antes de empaquetar o publicar.
- Confirmar la licencia de cada loop distribuido antes de empaquetar o publicar.

## Validación pendiente de producto

- Medir 60 FPS con la escena de máxima densidad durante diez minutos.

## Validación de layouts

- Migración v1→v2 con copia de seguridad.
- Duplicados resuelven un único objetivo `any`.
- Roles y pads exactos no se aceptan indistintamente.
- Orientación no corrompe MIDI.
- Cada ejercicio declara requisitos.

## Validación didáctica

- Una dificultad principal nueva por nivel y ayudas reducidas comprobadas.
- Métricas de sesgo y dispersión no se confunden con latencia.
