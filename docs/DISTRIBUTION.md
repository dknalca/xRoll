# Distribución de xRoll

La publicación actual es manual. Las etiquetas `v*` identifican versiones, pero
este repositorio no contiene un flujo de GitHub que ejecute pruebas ni cree un
borrador de release. Las notas se redactan para cada etiqueta.

## Publicación de una versión

1. Ejecuta `swift test`, `swift run xroll-preflight` y `scripts/build-app.sh`.
2. Comprueba que toda muestra nueva está anotada en
   `Resources/Loops/ATTRIBUTION.md` y que su licencia permite la distribución.
3. Crea y sube una etiqueta, por ejemplo `git tag -a v0.1.0 -m 'xRoll 0.1.0'`
   y `git push origin v0.1.0`.
4. Crea el release y adjunta `dist/xRoll.app` o su archivo comprimido cuando
   corresponda.

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
