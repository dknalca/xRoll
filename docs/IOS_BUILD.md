# Compilar xRoll para iOS/iPadOS

## Requisitos

- Xcode 14.2 o posterior con SDK de iOS 16.2 o posterior.
- Para instalación en hardware: iPhone/iPad compatible, cuenta de Apple Developer para firma y un perfil válido (no guardar certificados ni perfiles en el repositorio).
- Deployment target: iOS 16.2. La app se ha instalado en un iPad7,11 con iOS 18.7.10; consulta `docs/IOS_HARDWARE_TESTS.md` para las comprobaciones funcionales que siguen pendientes. La aplicación es universal para iPhone y iPad.

## Proyecto

El proyecto está en `xRoll.xcodeproj` en la raíz del repositorio. Ábrelo en Xcode, selecciona el scheme `xRoll` y un destino iPhone/iPad con iOS 16.2 o posterior. El bundle provisional es `com.example.xroll`; cámbialo por el identificador de distribución y selecciona tu Team en Signing & Capabilities antes de instalarlo en hardware. La firma está en modo automático y no se incluyen credenciales.

Los kits se copian desde `Resources/Kits/` como `Kits/` y los MIDI desde `data/exercises/` como `exercises/` dentro del bundle. El framework móvil `XRollCore` compila los mismos archivos fuente del target SwiftPM, incluyendo la cola C y el procesador serial de sesiones. `iOS/Assets.xcassets` contiene el icono de iOS y la marca de cabecera. En Equipo se aprende un `.padmap` v2 físico y se aplican Core, Drum Kit o Mirror sin alterar notas/canales; Curso y Progreso consumen `CourseGraph`, `TempoLadder` y SQLite compartidos. Tras cerrar una sesión aparece la opción de compartir la traza temporal JSON (esquema 3); registra por separado MIDI, envío de audio, procesamiento del score y consumo visual del feedback por un frame SpriteKit. Deployment target: iOS 16.2; familias de dispositivo: iPhone e iPad.

Para volver a generar los PNG del icono opaco y la marca de cabecera desde el dibujo de marca:

```sh
swift scripts/render_ios_app_icon.swift \
  iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
  iOS/Assets.xcassets/BrandMark.imageset/BrandMark.png
```

## Comprobación local

La máquina tiene Xcode 14.2 / SDK iOS 16.2. La app y el framework compilan para simulador y destino genérico iOS con `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'platform=iOS Simulator,name=iPhone 14' build` y `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`. `simctl install` y `simctl launch` funcionan en simuladores iOS 16.2, donde la pantalla Curso carga los 77 ejercicios. El IPA con curso/layouts está instalado en el iPad iOS 18.7.10; la comprobación de aprendizaje y puntuación con el M‑Vave sigue pendiente en hardware.

El scoring iOS ahora usa un acumulador incremental y `PracticeSessionIngress` serializa los eventos fuera de SwiftUI. La escena consume el feedback en su ciclo de frame y la traza esquema 3 separa procesamiento, actualización visual y consumo del evento. El audio sigue usando el pool de `AVAudioPlayerNode` como referencia; el mezclador de render alternativo no debe elegirse como predeterminado hasta comparar ambos en el iPad con una ruta de audio fija.

### Compilar e instalar en un iPad

Instala Xcode y las herramientas de dispositivo (`brew install ideviceinstaller`). Conecta y desbloquea el iPad, y acepta «Confiar en este ordenador». Desde la raíz del repositorio ejecuta:

```sh
scripts/deploy-ipad.sh
```

El script compila en Release, firma y exporta el IPA de desarrollo, lo instala por USB y guarda una copia en `dist/ios-device/xRoll.ipa`. Si hay varios dispositivos conectados, indica el UDID que muestra `idevice_id -l`:

```sh
scripts/deploy-ipad.sh --udid <UDID>
```

La firma automática requiere una cuenta de Apple Developer configurada en Xcode y un perfil válido que incluya el iPad. El perfil actual vence el 30 de septiembre de 2026 y deberá renovarse para reinstalaciones posteriores. Al terminar, abre xRoll desde la pantalla de inicio del iPad.

Para depurar en un dispositivo, selecciónalo en Xcode, configura la firma y ejecuta desde el IDE. Xcode 14.2 puede compilar el destino genérico de iOS, pero no incluye el developer disk image del iPadOS 18.7.10 conectado.
