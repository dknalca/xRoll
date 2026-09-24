# Compilar xRoll para iOS/iPadOS

## Requisitos

- Xcode 14.2 o posterior con SDK de iOS 16.2 o posterior.
- Para instalación en hardware: iPhone/iPad compatible, cuenta de Apple Developer para firma y un perfil válido (no guardar certificados ni perfiles en el repositorio).
- Deployment target: iOS 16.2. La app se ha instalado en un iPad7,11 con iOS 18.7.10; consulta `docs/IOS_HARDWARE_TESTS.md` para las comprobaciones funcionales que siguen pendientes. La aplicación es universal para iPhone y iPad.

## Proyecto

El proyecto está en `xRoll.xcodeproj` en la raíz del repositorio. Ábrelo en Xcode, selecciona el scheme `xRoll` y un destino iPhone/iPad con iOS 16.2 o posterior. El bundle provisional es `com.example.xroll`; cámbialo por el identificador de distribución y selecciona tu Team en Signing & Capabilities antes de instalarlo en hardware. La firma está en modo automático y no se incluyen credenciales.

Los kits se copian desde `Resources/Kits/` como `Kits/` y los MIDI desde `data/exercises/` como `exercises/` dentro del bundle. El framework móvil `XRollCore` compila los mismos archivos fuente del target SwiftPM, incluyendo la cola C. `iOS/Assets.xcassets` contiene el icono de iOS y la marca de cabecera. En Equipo se aprende un `.padmap` v2 físico y se aplican Core, Drum Kit o Mirror sin alterar notas/canales; Curso y Progreso consumen `CourseGraph`, `TempoLadder` y SQLite compartidos. Tras cerrar una sesión aparece la opción de compartir la traza temporal JSON (esquema 2); registra por separado el tiempo CoreMIDI, la llegada al callback y el origen del tiempo efectivo. Deployment target: iOS 16.2; familias de dispositivo: iPhone e iPad.

Para volver a generar los PNG del icono opaco y la marca de cabecera desde el dibujo de marca:

```sh
swift scripts/render_ios_app_icon.swift \
  iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
  iOS/Assets.xcassets/BrandMark.imageset/BrandMark.png
```

## Comprobación local

La máquina tiene Xcode 14.2 / SDK iOS 16.2. La app y el framework compilan para simulador y destino genérico iOS con `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'platform=iOS Simulator,name=iPhone 14' build` y `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`. `simctl install` y `simctl launch` funcionan en simuladores iOS 16.2, donde la pantalla Curso carga los 77 ejercicios. El IPA con curso/layouts está instalado en el iPad iOS 18.7.10; la comprobación de aprendizaje y puntuación con el M‑Vave sigue pendiente en hardware.

### Instalar en un iPad iOS 18 usando el IPA de desarrollo

El Mac tiene un perfil de desarrollo que incluye el UDID del iPad y un certificado coincidente. Para regenerar el archive y exportar el IPA firmado:

```sh
xcodebuild -project xRoll.xcodeproj -scheme xRoll -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/xRoll.xcarchive \
  DEVELOPMENT_TEAM=VDGXRX42BR CODE_SIGN_STYLE=Automatic archive
xcodebuild -exportArchive -archivePath /tmp/xRoll.xcarchive \
  -exportPath /tmp/xRoll-export -exportOptionsPlist iOS/ExportOptions.plist
```

Con el iPad conectado, desbloqueado y con “Confiar en este ordenador” aceptado:

```sh
brew install ideviceinstaller
idevice_id -l
ideviceinstaller -u <UDID> -w install /tmp/xRoll-export/xRoll.ipa
```

`idevicedebug` requiere el developer disk image de iOS, que Xcode 14.2 no incluye para iOS 18.7.10; abre la app tocando su icono en el iPad. El perfil actual vence el 30 de septiembre de 2026 y deberá renovarse para reinstalaciones posteriores.

`xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'generic/platform=iOS Simulator' build`. Para un dispositivo compatible con Xcode 14.2, elige el destino en Xcode, configura firma y ejecuta desde el IDE.
