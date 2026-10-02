# Verificación en hardware iOS

El IPA de desarrollo versión 1.0 está instalado por USB en un iPad7,11 con iPadOS 18.7.10; `ideviceinstaller` confirmó el bundle `com.example.xroll`. En ese build se abrió la app, se cargó el curso y el usuario confirmó que el loop suena durante la práctica. Las casillas marcadas abajo registran pruebas de ese build; las demás siguen pendientes. Los cambios posteriores del árbol de trabajo requieren una instalación nueva antes de validar su comportamiento físico.

Xcode 14.2 detecta el iPad, pero no tiene el developer disk image para depurarlo desde el IDE; `idevicedebug` tampoco puede iniciarlo. Los simuladores no emulan Bluetooth MIDI físico.

La conexión de los pads mediante un cable Lightning–USB‑C directo no los hizo aparecer en CoreMIDI. En iPad con Lightning, repetir la prueba con un adaptador Lightning a USB para cámara; algunos controladores requieren además alimentación externa.

## Pendientes

- [x] Instalar xRoll iOS 16.2 en el iPad iOS 18.7.10 con `ideviceinstaller`.
- [x] Instalar el IPA 1.0 actualizado y confirmar el bundle `com.example.xroll` con `ideviceinstaller`.
- [x] Abrir la versión corregida desde el iPad y comprobar que permanece abierta y carga el curso.
- [x] En Preparación, elegir un loop de la biblioteca, activar «Loop» y comprobar que se oye desde la cuenta de entrada durante la práctica.
- [ ] En Redobles, practicar un gesto aislado y su versión dentro de un groove; verificar que completar esa ruta no altera los desbloqueos principales.
- [ ] Ajustar y restablecer el volumen de un sonido en «Mezcla del kit»; comprobar el cambio audible inmediato y su persistencia al reiniciar.
- [ ] Probar la claqueta desde «Escuchar metrónomo», cambiar su tono y volumen, iniciar una práctica y confirmar que conserva los ajustes.
- [ ] Durante los compases de entrada, golpear pads y confirmar reproducción/realce visual, sin extras ni penalización en el resultado.
- [ ] Abrir «Opciones» desde el engranaje y confirmar que mezcla, metrónomo, loop y diagnóstico visual están fuera de Inicio.
- [ ] Cerrar Koala y sus conexiones; en xRoll tocar «Bluetooth MIDI» → «Buscar dispositivos Bluetooth MIDI».
- [ ] Conectar el M‑Vave, esperar confirmación de CoreMIDI y seleccionarlo en «Entrada MIDI».
- [ ] En Equipo, aprender las 16 posiciones; anotar las notas/canales capturados y comprobar que el mapa se recupera tras cerrar y abrir la app.
- [ ] Aplicar Core, Drum Kit y Mirror; verificar que el 4×4 conserva posición, nota y canal, mientras cambia sonido/rol.
- [ ] Importar un `.padmap` con sonidos/roles distintos de Core, confirmar su aplicación y comprobar que conserva esas asignaciones tras reiniciar y alternar Custom/Core.
- [ ] Calibrar la ruta MIDI elegida antes de puntuar.
- [ ] Apagar el metrónomo en Opciones y calibrar; comprobar que la claqueta obligatoria sigue sonando.
- [ ] Revisar la traza de calibración: comparar `midiCoreMIDIHostTime`, `midiCallbackHostTime`, `inputHostTime` y `midiTimestampSource`; confirmar que el tiempo efectivo avanza y que timestamps inválidos usan `callbackFallback`.
- [ ] Golpear el controlador: confirmar reproducción del sample, actividad de pad y resultado de score; anotar ejercicio y comportamiento.
- [ ] En una toma que incluya pantalla y pads, comprobar que cada impacto gráfico aparece en el siguiente frame y que la marca de desfase queda antes/después de la línea según el golpe.
- [ ] Comparar en la traza `inputHostTime`, inicio/fin de procesamiento de sesión y `visualFeedbackConsumedHostTime`; los timestamps de scoring deben permanecer ligados al evento MIDI original.
- [ ] Confirmar que, con entrada MIDI seleccionada, no se muestra la rejilla táctil y la práctica usa el área para los carriles y el estado compacto del controlador.
- [ ] Revisar icono, marca de cabecera y paleta oscura en preparación, práctica, resultado y pantalla de lanzamiento; repetir en iPad vertical y horizontal.
- [ ] Con el mismo ejercicio/ruta, comparar A/B «Anticipar un frame visual», calibrando antes de cada sesión.
- [ ] Compartir la traza JSON; para observar el sonido real, grabar pantalla y click/audio en la misma toma. El retorno de `play()` no es onset acústico.
- [ ] Completar y cerrar una sesión MIDI, después repetir la calibración y la sesión con pads táctiles.
- [ ] En Curso, abrir y practicar un ejercicio marcado como pendiente sin acreditar; comprobar que la vía guiada sigue recomendando un siguiente paso.
- [ ] Probar cualquier tempo directamente, superar una lección a su tempo de aprendizaje/70 % y confirmar que el reto opcional no bloquea el siguiente paso ni concede premios de tempos no tocados.
- [ ] Probar un checkpoint de capítulo posterior antes de acreditar los anteriores: guardar la evidencia y comprobar que el avance se activa solo al completar la ruta previa.
- [ ] Comprobar que Nivel dios exige 16 compases y que un intento más corto no otorga el trofeo ni modifica los desbloqueos.
- [ ] Instalar, abrir y cerrar la aplicación en un iPhone físico.
- [ ] Cargar ejercicio MIDI y kit incluidos; completar una sesión y comprobar scoring/progreso.
- [ ] Golpes táctiles individuales, consecutivos y multitáctiles en ambas orientaciones.
- [ ] Conectar/desconectar y reconectar controlador USB MIDI compatible.
- [ ] Conectar/desconectar controlador Bluetooth MIDI compatible.
- [ ] Probar altavoz, auriculares cableados e interfaz externa; interrupciones y retorno a primer plano.
- [ ] Ejecutar calibración para cada ruta de entrada/salida y comprobar persistencia entre ejecuciones.
- [ ] Sesión prolongada, accesibilidad, cambios de tamaño/orientación y recuperación tras interrupción.

Cada casilla debe marcarse solo después de registrar dispositivo, versión de iOS, ruta utilizada, pasos y resultado observado.

El perfil de desarrollo que se usó está asociado al iPad y caduca el 30 de septiembre de 2026; para reinstalar más adelante habrá que renovar el perfil de desarrollo.
