# Validacion antes del MVP

## Ya automatizado

- `swift build` compila todos los ejecutables y la ventana macOS.
- `swift test` valida recursos, MIDI, mapeos, reloj, puntuacion, calibracion y
  sesiones de practica.
- `swift run xroll-preflight` valida kit, WAV y ejercicios.

## Pendiente en hardware

1. Mapear el M-Vave desde la pestaña **Mapear pads** y reiniciar la app para
   confirmar que carga el mapa guardado.
2. Comprobar teclado, vista previa y los cinco ejercicios con auriculares y con
   la salida Rane.
3. Ejecutar la medicion fisica de latencia descrita en `LATENCY_PROTOCOL.md`.
4. Practicar diez minutos seguidos y confirmar que no hay cortes ni caidas de
   fotogramas perceptibles en la escena SpriteKit.
5. Confirmar la licencia de cada WAV antes de publicar cualquier audio.
