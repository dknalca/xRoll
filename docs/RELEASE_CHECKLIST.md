# Validación antes de publicar

## Ya automatizado

- `swift build` compila todos los ejecutables y la ventana macOS.
- `swift test` valida recursos, MIDI, mapeos, reloj, puntuacion, calibracion y
  sesiones de practica.
- `swift run xroll-preflight` valida kit, WAV y ejercicios.

## Pendiente en hardware

1. Confirmar tras reiniciar que el M‑Vave conserva el mapa de 16 pads y que
   Core, Drum Kit y Mirror iluminan y reproducen el pad correcto.
2. Comprobar teclado, vista previa y una selección representativa del catálogo
   con auriculares y con la salida Rane.
3. Ejecutar la medicion fisica de latencia descrita en `LATENCY_PROTOCOL.md`.
4. Practicar diez minutos seguidos y confirmar que no hay cortes ni caidas de
   fotogramas perceptibles en la escena SpriteKit.
5. Confirmar la licencia de cada WAV antes de publicar cualquier audio.

## Validación pendiente de producto

- Verificar VoiceOver y Reduce Motion en macOS real.
- Medir 60 FPS con la escena de máxima densidad durante diez minutos.
- Probar Core, Drum Kit y Mirror con controladores reales y conservar presets
  por dispositivo.

## Validación de layouts

- Migración v1→v2 con copia de seguridad.
- Core, Drum Kit y Mirror probados en hardware.
- Duplicados resuelven un único objetivo `any`.
- Roles y pads exactos no se aceptan indistintamente.
- Orientación no corrompe MIDI.
- Cada ejercicio declara requisitos.

## Validación didáctica

- Una dificultad principal nueva por nivel y ayudas reducidas comprobadas.
- Métricas de sesgo y dispersión no se confunden con latencia.
