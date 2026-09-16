---
name: xroll-release-assets
description: Use when adding WAV or loop assets, packaging xRoll.app, preparing a release, editing release workflows, or checking attribution and distribution requirements.
---

# Recursos y publicación de xRoll

Lee `docs/AUDIO.md`, `Resources/Loops/ATTRIBUTION.md`, `docs/DISTRIBUTION.md` y `docs/RELEASE_CHECKLIST.md` antes de cambiar recursos distribuibles o publicación.

## Recursos

- Código, audio, gráficos y documentación se distribuyen bajo MIT.
- Todo audio añadido requiere autoría, origen y licencia en `Resources/Loops/ATTRIBUTION.md` en el mismo cambio.
- Un kit se declara con `Resources/Kits/<id>/kit.json`; el manifiesto, no el código, relaciona IDs de sonido y WAV.
- Los samples deben cumplir los requisitos técnicos de `docs/AUDIO.md`, incluido no tener silencio inicial y conservar la cola necesaria.
- No afirmes que un recurso puede redistribuirse sin una licencia verificable.

## Empaquetado y automatización

- El bundle se crea con `scripts/build-app.sh`. Empaqueta `Resources/` y `data/` bajo `dist/xRoll.app/Contents/Resources/ProjectData`.
- Prueba la app empaquetada, no solo `swift run xroll-pads`, cuando cambien rutas, recursos o carga de bundle.
- `.github/workflows/ci.yml` ejecuta `swift build` y `swift test` en macOS. El flujo de tag crea un borrador de release; no firma ni notariza el bundle.
- La firma y notarización requieren una identidad local de Apple Developer y un perfil de llavero; no introduzcas credenciales en el repositorio.

## Verificación antes de publicar

1. Ejecuta `swift test`.
2. Ejecuta `swift run xroll-preflight`.
3. Ejecuta `scripts/build-app.sh` y abre `dist/xRoll.app`.
4. Comprueba atribuciones y completa los bloqueos manuales de `docs/RELEASE_CHECKLIST.md`.
5. Redacta notas de release para la versión real; no reutilices una plantilla de una versión anterior.
