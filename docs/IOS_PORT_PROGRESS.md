# Estado del port a iOS/iPadOS

## Fases

- [x] Inspección inicial de rama, código, recursos, reloj, MIDI, audio, persistencia y herramienta local.
- [x] Auditoría inicial basada en el código: `docs/IOS_PORT_AUDIT.md`.
- [x] Framework iOS `XRollCore` que compila los mismos fuentes del núcleo junto a `XRollRealtimeQueue.c` mediante bridging header.
- [x] Proyecto Xcode `xRoll.xcodeproj` en la raíz con target universal iPhone/iPad y deployment target 16.2; bundle provisional `com.example.xroll`.
- [x] Flujo prototipo escrito: carga kit y catálogo MIDI del bundle, sesión `PracticeSession`, escena `PracticeScene`, pads UIKit multitáctiles, audio `SampleAudioEngine`, resultado y persistencia `ProgressStore` local.
- [x] Controles iOS para listar, seleccionar y refrescar fuentes CoreMIDI; cada paquete conserva el timestamp CoreMIDI y captura el instante de llegada en el callback para validar y resolver `hostTime` antes de puntuar.
- [x] Búsqueda Bluetooth LE MIDI dentro de la app; comprueba el servicio BLE MIDI, activa CoreMIDI, espera a que `MIDIInspector.device(named:)` localice el dispositivo y transfiere la conexión desde CoreBluetooth.
- [x] Selección/desconexión de fuente Bluetooth/CoreMIDI, preferencia persistida y observación de cambios de fuentes para reconexión.
- [x] Diagnóstico del último Note On (nota, canal y velocity) visible en preparación y sesión, incluso si la nota no se mapea a un sonido.
- [x] Calibración guiada iOS, con cuenta atrás/claqueta programada a hostTime y perfiles separados para entrada táctil/MIDI y ruta de salida.
- [x] Práctica puntuable requiere calibración de ruta, entrada MIDI conectada, mapa físico completo y layout compatible; la calibración siempre programa una claqueta audible, aunque el metrónomo de práctica esté apagado. Un cambio de entrada o ruta durante una sesión la cancela.
- [x] Asistente iOS aprende las 16 notas/canales reales por posición con `PadMapBuilder`, detecta duplicados y persiste el mapa v2 por UID; si el UID BLE cambia, solo migra por nombre cuando la coincidencia es única.
- [x] Core, Drum Kit, Mirror y mapas Custom importados conservan la relación entre posición, nota/canal MIDI y sonidos/roles del mapa; el Custom importado persiste al reiniciar. Sin mapa, la entrada GM es solo prueba de sonido y no puntúa.
- [x] Los 16 pads y carriles representan duplicados; las alternativas por sonido permanecen visibles y el feedback identifica el pad MIDI/táctil real. Los objetivos por rol/pad limitan destinos y se comprueba compatibilidad antes de practicar.
- [x] Curso iOS deriva capítulos, prerrequisitos y estados de `CourseGraph`; ofrece recomendación y escalera `TempoLadder` con los seis tempos establecidos.
- [x] Curso iOS/macOS permite practicar cualquier ejercicio, ofrece un checkpoint de demostración al final de cada capítulo y acredita con ritmo completo a 100 BPM/70 % o al completar el capítulo. Los checkpoints adelantados se guardan y se acreditan al alcanzar la ruta previa; CourseGraph consulta evidencia ligera de todo el historial.
- [x] Intentos iOS guardan estadísticas por sonido y `TrainingContext` de ritmo completo con compases terminados; el progreso usa los mismos criterios de consolidación y los 16 compases de Nivel dios.
- [x] Vista de práctica por fuente: carriles y estado compacto con MIDI; rejilla multitáctil y carriles con entrada táctil, en layouts iPad/iPhone.
- [x] SpriteKit predice la presentación del próximo frame iOS a partir del intervalo de actualización observado; el score sigue usando los hostTime originales.
- [x] A/B para anticipación visual y traza temporal circular de hasta 512 eventos, exportada solo al cerrar/cancelar una sesión.
- [x] La traza v2 registra input/worker/audio/main/frame/objetivo/offset y, para MIDI, el timestamp original, la recepción del callback y la fuente del tiempo efectivo; calibración empareja golpes uno-a-uno fuera de la ventana Regular del scorer.
- [x] Compilación de app y framework para iPhone Simulator iOS 16.2 y destino genérico iOS físico con Xcode 14.2.
- [x] Instalación y apertura con `simctl` en iPhone 14 e iPad (10.ª generación), simuladores iOS 16.2; ambos muestran 77 ejercicios y el kit Hip Hop Basico en la pantalla inicial.
- [x] IPA de desarrollo firmado con la integración BLE/CoreMIDI e instalado por USB en el iPad con `ideviceinstaller`.
- [x] IPA actualizado con Curso, escalera de tempo, persistencia de evidencia, aprendizaje físico y layouts por controlador exportado e instalado por USB en el iPad con `ideviceinstaller`.
- [x] Corregido un cierre al abrir en iOS 18: el informe del iPad mostró agotamiento de pila al resolver el tipo genérico de las pestañas SwiftUI; las pestañas ahora quedan aisladas con `AnyView`. El build actualizado se abrió y permaneció activo en el simulador de iPad iOS 16.2, y el nuevo IPA se instaló por USB.
- [x] Pantalla de práctica simplificada para ampliar los carriles; los controles de pausa/salida y el estado MIDI ocupan una franja compacta. El catálogo de loops ahora recorre subcarpetas y el acompañamiento se programa desde la cuenta de entrada para que suene durante la anticipación.
- [x] La ruta «Redobles» queda separada del curso principal y deriva sus pares aislado/contexto de metadatos MIDI; «Progreso» cuenta solo estaciones principales. Mezcla del kit en iOS permite ajustar y restablecer el volumen por sonido con persistencia local.
- [x] Referencia rítmica iOS añade tono de metrónomo ajustable (−12…+24 semitonos), prueba audible inmediata, volumen y persistencia; el motor conserva ese tono al programar la claqueta.
- [x] Curso con exploración libre: cualquier ejercicio se puede practicar, cada capítulo ofrece un checkpoint MIDI a 100 BPM/70 %, los checkpoints adelantados esperan la ruta previa y el curso calcula acreditaciones con evidencia histórica completa, sin limitarse a los últimos 1.000 intentos.
- [x] Preferencias ocasionales de metrónomo, loop, mezcla, salida y diagnóstico visual reunidas en «Opciones», fuera de Inicio.
- [x] En práctica, la rejilla táctil solo aparece con «Solo táctil»; los eventos de toque también se descartan mientras haya una entrada MIDI seleccionada.
- [x] Los golpes durante la cuenta de entrada se reproducen y resaltan el pad, pero se excluyen del score fuera de la ventana anticipada del primer pulso.
- [x] El metrónomo usa una claqueta sintetizada distinta de HH cerrado, con acento diferenciado en el primer pulso; admite reemplazo opcional por un archivo personalizado.
- [x] Interfaz iOS con paleta oscura del sistema visual, preparación/equipo/calibración, vista de práctica enfocada y resultado diagnóstico.
- [x] Asset catalog iOS con icono de app, marca para cabecera y fondo oscuro de lanzamiento, derivado del símbolo `Resources/AppIcon.svg`.
- [x] Abrir el IPA actualizado en el iPad iOS 18.7.10; el usuario confirma que el loop se oye correctamente durante la práctica.
- [x] Instalar el IPA de desarrollo versión 1.0 actualizado en iPad7,11/iOS 18.7.10 y confirmar `com.example.xroll` con `ideviceinstaller`; probar las nuevas funciones sigue pendiente.
- [x] Proyecto abierto por Xcode desde la ruta raíz esperada y `project.pbxproj` validado con `plutil`.
- [x] `Kits/hiphop_basic/kit.json`, sus WAV y los ejercicios MIDI aparecen en el bundle instalado.
- [x] El catálogo integrado pasa `CourseGraph` en el simulador; los tests Core verifican aprendizaje físico, conservación de notas/canales entre layouts, matching por rol/pad y el mínimo de 16 compases.
- [ ] Validar en dispositivo la conversión UITouch.timestamp → hostTime y la entrada táctil multitáctil.
- [x] Entrada MIDI USB/CoreMIDI y conexión BLE MIDI implementadas en iOS.
- [ ] Validar golpes MIDI Bluetooth reales, reconexión y estabilidad en hardware.

## Verificación disponible

El repositorio conserva macOS 12 como target. La máquina actual es macOS 12.7.6 y tiene Xcode 14.2 / Swift 5.7.2 / SDK iOS 16.2. La app y el framework compilan para simulador y destino genérico iOS con deployment target 16.2. iOS 18.7.10 pudo recibir la app firmada mediante `ideviceinstaller`; Xcode/`idevicedebug` no pueden adjuntarse sin el developer disk image, así que la apertura y el flujo táctil en el iPad se deben comprobar manualmente.

El escáner CoreBluetooth filtra el servicio estándar BLE MIDI. Comprueba la característica MIDI, activa CoreMIDI, espera a que `MIDIInspector.device(named:)` localice el dispositivo y entonces desconecta su objeto CoreBluetooth tal como exige la API de Apple. La fuente de notas se recibe por `MIDIInputSession`. El simulador no ofrece BLE físico; el controlador y el audio MIDI aún requieren prueba en el iPad.

`simctl install` fallaba con `CFBundleVersion` aparentemente ausente aunque el plist lo contenía: el directorio `Resources/` en la raíz del `.app` hacía que `NSBundle` en el host no reconociera su `Info.plist`. Se solucionó empaquetando solo `Kits/` como carpeta raíz y manteniendo `exercises/`; el `Info.plist` explícito está en `iOS/Info.plist`.

La conversión táctil implementada traduce el timestamp monotónico de UIKit desde el `systemUptime` observado a `mach_absolute_time` usando la razón `mach_timebase_info`; la exactitud necesita prueba instrumental en iOS. Con MIDI seleccionado la rejilla táctil no se presenta y el modelo rechaza cualquier evento táctil residual. `PracticeScene` tiene un A/B que avanza la imagen por el intervalo observado entre frames; no cambia el hostTime de scoring ni constituye una medición de latencia. La traza registra el retorno de `play()` como envío al motor, no como sonido audible.

La entrada MIDI mantiene el timestamp del paquete CoreMIDI y toma también `mach_absolute_time()` al copiarlo a la cola. El worker usa el original si es no-cero, no está más de 2 s atrasado ni más de 100 ms adelantado respecto a esa recepción; si no, usa la hora de recepción. Estos límites detectan timestamps evidentemente inválidos y no miden ni garantizan precisión Bluetooth. La traza v2 identifica ambas marcas y `midiTimestampSource` (`coreMIDI` o `callbackFallback`).

## Próximos pasos

1. En Equipo, seleccionar el M‑Vave, aprender sus 16 posiciones y comprobar nota/canal; aplicar Core, Drum Kit y Mirror y confirmar que MIDI no cambia.
2. Calibrar esa ruta; practicar un ejercicio sin acreditarlo, aprobar un checkpoint a 100 BPM/70 % y comprobar que el siguiente capítulo se acredita. Probar también un checkpoint futuro antes de completar los anteriores y seleccionar directamente Nivel dios sin conceder premios de tempos no tocados.
3. Completar Nivel dios con 16 compases y comprobar el trofeo; intentar menos compases y confirmar que no acredita el escalón.
4. Cambiar a un preset sin una voz requerida, confirmar el aviso de incompatibilidad y que no permite puntuar; volver a un preset compatible.
5. Reiniciar y verificar persistencia de UID/layout, historial, nivel curricular y tempo pendiente; probar reconexión BLE y dos controladores con nombres distintos.
6. Probar en ambas orientaciones iPad el flujo táctil, multitáctil y el MIDI; comparar A/B y compartir trazas junto a una grabación pantalla+audio si se mide sincronía.
