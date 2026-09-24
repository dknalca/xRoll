# Auditoría del port a iOS/iPadOS

Esta auditoría registra el estado inicial del port; el estado posterior y la
validación vigente están en `docs/IOS_PORT_PROGRESS.md` y
`docs/IOS_HARDWARE_TESTS.md`.

## Entorno comprobado

- Equipo de desarrollo: macOS 12.7.6, Intel.
- Xcode 14.2, Swift 5.7.2, SDK iOS 16.2 y simuladores iOS 16.2.
- El usuario confirma que su dispositivo ejecuta iOS 18 y que no dispone de un Xcode/macOS más reciente. Se fija la app en iOS 16.2; la compilación se realiza con Xcode/SDK iOS 16.2. La ejecución en iOS 18 sigue pendiente de prueba en el dispositivo.
- Rama de trabajo: `feature/ios-port`; el árbol estaba limpio al iniciar la auditoría.

## Arquitectura real

- `XRollCore` reúne dominio y servicios: MIDI, audio, inspección de CoreAudio, recursos, reloj, scoring, calibración y SQLite. No es todavía un módulo de dominio puro. `SystemInspection.swift` ya condiciona CoreAudio HAL a macOS y ofrece la variante de ruta AVAudioSession para iOS.
- `XRollRealtimeQueue` es C11 con atomics: cola acotada de secuencias, productor no bloqueante y contador de descartes; `MIDIInput` conserva el timestamp de cada paquete y decodifica en un worker.
- `XRollPads` es un ejecutable macOS, no un framework de interfaz. `main.swift` contiene `Model` y gran parte de la coordinación; depende de AppKit, ventanas, paneles de archivos y teclado macOS.
- `PracticeScene` es SpriteKit y calcula el tiempo visual desde `AudioClock.currentHostTime`; recibe una línea temporal y feedback del coordinador. Se incluye en el target de app móvil.
- `SampleAudioEngine` usa AVAudioEngine, buffers cargados y pools separados para golpes en vivo y audio programado.
- Los WAV y `kit.json` viven bajo `Resources/Kits`; los MIDI integrados están bajo `data/exercises`. La app macOS los busca en `ProjectData` del bundle o en el directorio de trabajo; la app iOS copia `Kits/` y `exercises/` en la raíz de su bundle.
- `ProgressStore` usa SQLite3 y acepta una URL; crea el directorio padre. Es portable si iOS le proporciona una ruta de Application Support.

## Portabilidad

### A. Reutilizable directamente (compilado para iOS 16.2)

Scoring, sesiones, línea temporal, modelos MIDI, validadores, currículo, mapas, diagnósticos, persistencia SQLite, reloj monotónico y la cola C. Los fuentes compartidos compilan para iOS 16.2 con el SDK disponible.

### B. Reutilizable con integración/adaptación

- `MIDIInput.swift` conserva el timestamp en el callback y entrega en worker. La conexión a fuentes y notificaciones debe comprobarse en iOS, incluyendo APIs CoreMIDI disponibles, permisos/transportes, desconexión y reconexión.
- `SampleAudioEngine.swift` requiere configurar `AVAudioSession` en iOS y gestionar interrupciones/rutas; no debe portarse la selección de dispositivo CoreAudio de macOS.
- `PracticeScene.swift` puede exponerse como `SpriteView`; `GridGuideSubdivision` y `PracticeViewZoom` deben separarse para compartir la escena sin compilar `XRollPads/main.swift`.
- ResourceCatalog y formatos MIDI/kit/mapa son candidatos a reutilización, pero necesitan resolver recursos dentro del bundle en lugar de depender del cwd.

### C. Implementación iOS necesaria

- Aplicación SwiftUI con ciclo de vida móvil, navegación y estados de interrupción/segundo plano.
- Captura multitáctil UIKit/SwiftUI conectada al mismo router y `PracticeSession`; conversión verificada entre `UITouch.timestamp` y Audio Host Time.
- Gestión de `AVAudioSession`, ruta actual y eventos de interrupción.
- Resolución de recursos empaquetados y rutas escribibles en Application Support.
- Presentación/importación documental mediante APIs iOS.

### D. Exclusivo de macOS

- `XRollPads/main.swift` como ejecutable, su `Model` actual y llamadas a AppKit: `NSEvent`, `NSOpenPanel`, `NSSavePanel`, `NSWorkspace`, `NSViewRepresentable`.
- Herramientas CLI interactivas/diagnósticas (`XRollLatency`, `XRollKitPlayer`, `XRollPadMapper`, previsualizador/exportadores) y selección de salida/tamaño de buffer usando CoreAudio HAL.
- `SystemInspection.swift` contiene CoreMIDI portable junto a `CoreAudio` HAL no portable. Hay que dividir/condicionar la inspección, no incluir HAL en el destino iOS.

## Package.swift y recursos

`Package.swift` tiene tools-version 5.7, declara macOS 12 e iOS 16 y mezcla la biblioteca `XRollCore` con ejecutables macOS. No declara recursos SwiftPM: la app macOS empaquetada usa `ProjectData`, mientras el target iOS copia `Resources/Kits` como `Kits/` y `data/exercises` como `exercises/` en el bundle. No se debe copiar una carpeta llamada `Resources` en la raíz del `.app`: Foundation en el Mac la interpreta como disposición de bundle distinta y `simctl install` no encuentra `CFBundleVersion` en el `Info.plist` de la raíz. El proyecto Xcode crea un framework `XRollCore` con los mismos fuentes compartidos y la cola C porque Xcode 14.2 no resolvía el producto local SwiftPM desde este proyecto.

## Riesgos y orden

1. La compilación, instalación y apertura del app y framework están comprobadas en simuladores iOS 16.2 de iPhone 14 e iPad (10.ª generación). La captura de inicio confirma la carga del kit y de 77 ejercicios. Falta validar sesiones y entradas en interfaz y hardware.
2. Separar CoreAudio HAL de tipos comunes de inspección para hacer consumible el core en iOS sin alterar los ejecutables macOS.
3. Mantener el bundle de app Xcode (`xRoll.xcodeproj` en la raíz) y el framework móvil con los fuentes compartidos de `XRollCore`; kits y ejercicios se copian al bundle sin un directorio `Resources` en la raíz.
4. Implementar primero carga de un ejercicio real, sesión, reproducción y scoring compartidos; luego pads multitáctiles con reloj convertido y después CoreMIDI móvil.
5. Validar audio, MIDI físico, calibración y ciclo de vida en hardware; simulador no certifica esas rutas.

Decisiones de producto que condicionan el port: `CLAUDE.md` exige calibración por ruta, posiciones físicas estables y velocity no evaluada; `docs/DECISIONS.md` fija MIDI como formato único de ejercicios y desaconseja añadir grabación/DAW.
