# xRoll 0.4.0

Esta versión mejora el recorrido guiado, hace opcional la demostración inicial y
reduce trabajo redundante al preparar y representar la práctica en macOS e iOS.

## Novedades

- La vuelta de referencia inicial ahora es optativa, se recuerda entre sesiones
  y está apagada por defecto. Reiniciar o reanudar no vuelve a reproducirla; las
  acciones explícitas para escuchar una demostración siguen disponibles.
- Se amplía y organiza el curso por estaciones y rutas de género, con retos,
  recomendaciones y continuidad compartidos entre macOS e iOS.
- La práctica táctil muestra los pads activos del ejercicio y conserva sus
  controles accesibles; Equipo mantiene el mapa físico de 16 posiciones.
- Se simplifican los componentes de práctica y se reducen ordenaciones,
  timelines auxiliares y redibujados que no eran necesarios.
- Se refuerzan la lectura de metadatos MIDI, la validación curricular, el
  historial y los diagnósticos con regresiones específicas.

## Validación automatizada

- `swift build`
- `swift test` — 232 pruebas
- `swift run xroll-preflight` — catálogo, kit y recursos validados
- Compilación Release macOS con `scripts/build-app.sh`
- Compilación universal iOS y verificación del IPA de sideloading
- `XRollUITests` — 30 pruebas de navegación en simulador iOS

## Distribución

- macOS: app sin firma ni notarización, de acuerdo con D-059. Autoriza esta copia
  puntualmente con Gatekeeper; no desactives la protección global.
- iPhone/iPad: IPA universal arm64 sin perfil de desarrollo; Sideloadly, AltStore
  o SideStore debe firmarlo al instalarlo.

La validación manual de MIDI/Bluetooth, accesibilidad en hardware, referencia
inicial y rendimiento visual sigue descrita en `docs/RELEASE_CHECKLIST.md`. La
automatización y las compilaciones no sustituyen esas comprobaciones.
