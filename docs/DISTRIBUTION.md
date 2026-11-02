# Distribución de xRoll

La integración continua compila y prueba los cambios de `main` y los pull
requests, incluida una compilación genérica iOS sin firma. Al publicar una
etiqueta `v*`, GitHub Actions vuelve a ejecutar los chequeos, valida los recursos
y compila iOS antes de crear un borrador de release con notas generadas. El bundle
de macOS se distribuye deliberadamente sin firma ni notarización (D-059). El IPA
de iOS y sus requisitos de instalación son independientes de Gatekeeper.

## Publicación de una versión

1. Ejecuta `swift build`, `swift test` y `swift run xroll-preflight`.
2. Ejecuta `scripts/build-app.sh` y prueba `dist/xRoll.app`. Para validar un
   bundle sin reemplazar esa copia local, define `XROLL_APP_OUTPUT` con otra
   ruta, por ejemplo `XROLL_APP_OUTPUT=/tmp/xRoll-audit.app scripts/build-app.sh`.
3. Comprueba que toda muestra nueva está anotada en
   `Resources/Loops/ATTRIBUTION.md` y que su licencia permite la distribución.
4. Integra el commit de release en `main`; después crea y sube una etiqueta,
   por ejemplo `git tag -a v0.4.0 -m 'xRoll 0.4.0'` y
   `git push origin v0.4.0`.
5. Revisa y publica el borrador de GitHub Actions; adjunta `dist/xRoll.app` o su
   archivo comprimido cuando corresponda.

## Primera apertura de la app macOS sin firma

Al no estar firmada ni notarizada, Gatekeeper pedirá autorizar xRoll la primera
vez. Autoriza solo esta aplicación; no desactives Gatekeeper globalmente.

En macOS 12:

1. En Finder, localiza `xRoll.app` y haz Control-clic sobre la aplicación.
2. Elige **Abrir** y vuelve a pulsar **Abrir** en el aviso de Gatekeeper.
3. Si no aparece esa opción, intenta abrirla una vez; después ve a **Preferencias
   del Sistema → Seguridad y privacidad → General** y pulsa **Abrir igualmente**
   para xRoll. Confirma la acción en el diálogo siguiente.

En versiones recientes de macOS, la opción equivalente está en **Ajustes del
Sistema → Privacidad y seguridad → Seguridad → Abrir igualmente**. Puede ser
necesario intentar abrir la app antes de que aparezca el botón.

Una vez autorizada esa copia de xRoll, ábrela normalmente desde Finder. Si se
descarga una versión nueva, macOS puede volver a solicitar autorización.

## Distribución de iOS

La compilación genérica iOS de CI no lleva firma. El IPA de sideloading se genera
localmente con `scripts/build-ios-ipa.sh` y su firma ad-hoc se reemplaza al
instalarlo con Sideloadly/AltStore. Este flujo corresponde al requisito de
instalación de iOS; no implica firmar ni notarizar la app macOS.
