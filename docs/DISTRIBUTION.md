# Distribución de xRoll

El código se publica con etiquetas `v*`. GitHub ejecuta las pruebas en macOS y
crea un borrador de release con las notas de `docs/RELEASE_NOTES_0.1.0.md`.

## Publicación de una versión

1. Ejecuta `swift test`, `swift run xroll-preflight` y `scripts/build-app.sh`.
2. Comprueba que toda muestra nueva está anotada en
   `Resources/Loops/ATTRIBUTION.md`. Los seis WAV de `hiphop_basic` ya están
   confirmados como grabaciones originales del autor bajo CC BY-SA 4.0.
3. Crea y sube una etiqueta, por ejemplo `git tag -a v0.1.0 -m 'xRoll 0.1.0'`
   y `git push origin v0.1.0`.
4. Revisa el borrador creado por GitHub y publícalo cuando corresponda.

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
publica la versión. El flujo de GitHub no firma ni notariza, porque esas
credenciales no se almacenan en el repositorio.
