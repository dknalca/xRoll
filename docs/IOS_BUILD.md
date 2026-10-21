# Compilar xRoll para iOS/iPadOS

## Requisitos

- Xcode 14.2 o posterior con SDK de iOS 16.2 o posterior.
- Para instalación en hardware: iPhone/iPad compatible, cuenta de Apple Developer para firma y un perfil válido (no guardar certificados ni perfiles en el repositorio).
- Deployment target: iOS 16.2. La app se ha instalado en un iPad7,11 con iOS 18.7.10; consulta `docs/IOS_HARDWARE_TESTS.md` para las comprobaciones funcionales que siguen pendientes. La aplicación es universal para iPhone y iPad.

## Proyecto

El proyecto está en `xRoll.xcodeproj` en la raíz del repositorio. Ábrelo en Xcode, selecciona el scheme `xRoll` y un destino iPhone/iPad con iOS 16.2 o posterior. El bundle de la app es `com.alkbit.xroll`, coherente con el bundle macOS. La firma está en modo automático; selecciona localmente tu Team en Signing & Capabilities antes de instalar en hardware. El Team ID y las credenciales no se guardan en el proyecto.

Los kits se copian desde `Resources/Kits/` como `Kits/` y los MIDI desde `data/exercises/` como `exercises/` dentro del bundle. El framework móvil `XRollCore` compila los mismos archivos fuente del target SwiftPM, incluyendo la cola C y el procesador serial de sesiones. `iOS/Assets.xcassets` contiene el icono de iOS y la marca de cabecera. En Equipo se aprende un `.padmap` v2 físico y se aplican Core, Drum Kit o Mirror sin alterar notas/canales; Curso y Progreso consumen `CourseGraph`, `TempoLadder` y SQLite compartidos. Tras cerrar una sesión aparece la opción de compartir la traza temporal JSON (esquema 4); registra por separado MIDI, envío de audio, procesamiento del score, consumo visual del feedback por un frame SpriteKit y el buffer solicitado junto al efectivo. Deployment target: iOS 16.2; familias de dispositivo: iPhone e iPad.

Para volver a generar los PNG del icono opaco y la marca de cabecera desde el dibujo de marca:

```sh
swift scripts/render_ios_app_icon.swift \
  iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
  iOS/Assets.xcassets/BrandMark.imageset/BrandMark.png
```

## Comprobación local

La app y el framework compilan para simulador y destino genérico iOS con `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'platform=iOS Simulator,name=iPhone 14' build` y `xcodebuild -project xRoll.xcodeproj -scheme xRoll -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`. CI ejecuta el segundo comando en cada push a `main` y pull request. `simctl install` y `simctl launch` funcionan en simuladores iOS 16.2. El catálogo integrado actual contiene 117 ejercicios; los recursos se copian desde `data/exercises/`. La comprobación de aprendizaje y puntuación con el M‑Vave sigue pendiente en hardware.

El scoring iOS usa un acumulador incremental y `PracticeSessionIngress` serializa los eventos fuera de SwiftUI. La escena consume el feedback en su ciclo de frame y la traza esquema 4 separa procesamiento, actualización visual y consumo del evento. El audio usa pools acotados de `AVAudioPlayerNode`; las pruebas offline no sustituyen la comprobación acústica en iPhone/iPad con una ruta de audio fija.

### Pruebas de navegación iOS

El scheme compartido `xRoll` incluye `XRollUITests`. Con un simulador instalado:

```sh
xcodebuild -project xRoll.xcodeproj -scheme xRoll \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  -derivedDataPath dist/ios-ui-tests -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Se comprueban diez rutas: siguiente ejercicio, continuar tras aprobar con una
estrella sin opciones de tempo, volver a Curso,
volver a Redobles, preparar/empezar la prueba final y abrir el bloque anterior
pendiente tras una prueba aprobada, y preparar/empezar exactamente la lección
elegida sin una recomendación global competidora. El recorrido añade mapa de la
estación actual, preparación del reto final y celebración con continuación a la
siguiente parada. `CourseRailwayMap.swift` es compartido con macOS. CI elige un iPhone disponible y conserva
el `.xcresult`.

Las fixtures `XROLL_UI_TEST_SCENARIO` solo se compilan con `DEBUG` **y** destino
simulador. Preparan resultados con el scorer real y usan SQLite y perfiles de
calibración en un directorio temporal separado del historial normal. El perfil
sintético permite probar navegación sin hardware: estas pruebas no validan el
procedimiento de calibración, el onset acústico ni la precisión MIDI/táctil.
El IPA Release no incluye esas fixtures.

### Generar un IPA universal para sideloading

Desde la raíz, después de las comprobaciones:

```sh
XROLL_BUILD_NUMBER=2 zsh scripts/build-ios-ipa.sh
```

El script compila Release para dispositivo en `dist/ios-build`, crea
`Payload/xRoll.app` y genera `dist/ios-device/xRoll-unsigned.ipa`. Es un único
IPA arm64 para **iPhone e iPad** (`UIDeviceFamily` 1 y 2), mínimo iOS/iPadOS 16.2.
`XROLL_BUILD_NUMBER` permite distinguir las compilaciones; su valor predeterminado
es 2 y no cambia el número guardado en el proyecto.

El IPA tiene firma ad-hoc, sin perfil de aprovisionamiento ni certificado de
desarrollo. AltStore, SideStore o Sideloadly deben volver a firmarlo al instalar.
El script comprueba firma, arquitectura, integridad ZIP, identificador, familias
de dispositivo y recursos antes de reemplazar el IPA anterior; imprime SHA-256.
El IPA de desarrollo firmado por USB se guarda aparte como `xRoll.ipa`.

El flujo de pruebas del usuario es generar este IPA y entregarlo para instalar
manualmente con Sideloadly. No se intenta instalar directamente en el iPhone.

### Compilar e instalar en un iPad

Instala Xcode y las herramientas de dispositivo (`brew install ideviceinstaller`). Conecta y desbloquea el iPad, y acepta «Confiar en este ordenador». Desde la raíz del repositorio ejecuta:

```sh
scripts/deploy-ipad.sh --team-id <TEAM_ID>
```

El script compila en Release, firma y exporta el IPA de desarrollo, lo instala por USB y guarda una copia en `dist/ios-device/xRoll.ipa`. Indica el Team ID de tu cuenta con `--team-id` o `XROLL_DEVELOPMENT_TEAM`; no se incluye uno fijo en el proyecto. Si hay varios dispositivos conectados, indica el UDID que muestra `idevice_id -l`:

```sh
scripts/deploy-ipad.sh --team-id <TEAM_ID> --udid <UDID>
```

La firma automática requiere una cuenta de Apple Developer configurada en Xcode y un perfil válido que incluya el iPad. El perfil anterior venció el 30 de septiembre de 2026; el 6 de octubre de 2026 Xcode firmó e instaló el bundle actual mediante aprovisionamiento automático. Comprueba que Xcode mantenga un perfil válido antes de los siguientes despliegues. Al terminar, abre xRoll desde la pantalla de inicio del iPad.

### Migrar el historial de una instalación anterior

Al cambiar el identificador de bundle, iOS conserva los datos en contenedores separados. Para trasladar el historial desde `com.example.xroll` a `com.alkbit.xroll`, abre la versión anterior, ve a Progreso, deja los filtros en «Todos», exporta el historial como JSON y guárdalo en Archivos. En la versión nueva, ve a Progreso → «Importar historial JSON» y selecciona ese archivo. La importación conserva la evidencia de curso y omite intentos duplicados si se selecciona el mismo archivo otra vez.

Para depurar en un dispositivo, selecciónalo en Xcode, configura la firma y ejecuta desde el IDE. Xcode 14.2 puede compilar el destino genérico de iOS, pero no incluye el developer disk image del iPadOS 18.7.10 conectado.
