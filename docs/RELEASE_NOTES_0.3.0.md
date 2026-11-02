# xRoll 0.3.0

Esta versión amplía la práctica y prepara el port de desarrollo para iPhone y
iPad.

## Novedades

- Escena de práctica SpriteKit con autopista en perspectiva, receptores de pad
  por sonido, feedback de impacto y racha visual.
- Preparación con el siguiente nivel de tempo pendiente y acciones de resultado
  para subir nivel o pasar al siguiente ejercicio.
- Acompañamiento seleccionado automáticamente por estilo y BPM, con selector
  manual; se incluye el loop Hip-hop a 93 BPM.
- Premios de estrellas y trofeos visibles en Curso y Redobles.
- Marca de baquetas, entrada animada y treinta citas de baterías en Inicio.
- Port de desarrollo para iPhone/iPad con selección táctil y MIDI.

## Validación automatizada

- `swift build`
- `swift test --filter XRollCoreTests` — 109 pruebas
- `swift run xroll-preflight`
- `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- Bundle macOS creado con `scripts/build-app.sh`.

SHA-256 de `xRoll-0.3.0-macos.zip`:

```text
c05e861ac09ea23f16af92301dfface60d4dcc9d55aa5cc866555f53d6447f41
```

El borrador permanece sin publicar hasta completar la medición manual de 60 FPS
con la escena de máxima densidad durante diez minutos, según
`docs/RELEASE_CHECKLIST.md`.
