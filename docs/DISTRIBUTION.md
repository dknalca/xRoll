# Distribución de xRoll

La integración continua compila y prueba los cambios de `main` y los pull
requests. Al publicar una etiqueta `v*`, GitHub Actions vuelve a ejecutar los
chequeos, valida los recursos y crea un borrador de release con notas generadas;
la distribución firmada de macOS y el IPA de iOS siguen siendo operaciones
locales.

## Publicación de una versión

1. Ejecuta `swift build`, `swift test` y `swift run xroll-preflight`.
2. Ejecuta `scripts/build-app.sh` y prueba `dist/xRoll.app`. Para validar un
   bundle sin reemplazar esa copia local, define `XROLL_APP_OUTPUT` con otra
   ruta, por ejemplo `XROLL_APP_OUTPUT=/tmp/xRoll-audit.app scripts/build-app.sh`.
3. Comprueba que toda muestra nueva está anotada en
   `Resources/Loops/ATTRIBUTION.md` y que su licencia permite la distribución.
4. Crea y sube una etiqueta, por ejemplo `git tag -a v0.1.0 -m 'xRoll 0.1.0'`
   y `git push origin v0.1.0`.
5. Revisa y publica el borrador de GitHub Actions; adjunta `dist/xRoll.app` o su
   archivo comprimido cuando corresponda.

## Firma y notarización

Para entregar la aplicación sin avisos de Gatekeeper hace falta una cuenta
Apple Developer y un certificado `Developer ID Application`. No se guarda
ninguna identidad, contraseña ni token en este repositorio.

Con la identidad instalada en el llavero, firma el bundle local:

```sh
codesign --force --deep --options runtime --sign 'Developer ID Application: TU NOMBRE' dist/xRoll.app
ditto -c -k --sequesterRsrc --keepParent dist/xRoll.app dist/xRoll.zip
xcrun notarytool submit dist/xRoll.zip --keychain-profile xroll-notary --wait
xcrun stapler staple dist/xRoll.app
```

La cuenta de Apple y el perfil `xroll-notary` solo se configuran en el Mac que
publica la versión. No se almacenan credenciales de firma o notarización en el
repositorio.
