# Verificación en hardware iOS

El IPA de desarrollo versión 1.0 anterior se instaló por USB en un iPad7,11 con iPadOS 18.7.10; `ideviceinstaller` confirmó el bundle histórico `com.example.xroll`. En ese build se abrió la app, se cargó el curso y el usuario confirmó que el loop suena durante la práctica. El 6 de octubre de 2026 también se instaló en ese iPad el bundle actual `com.alkbit.xroll`, incluida la compilación con las correcciones de la auditoría. Las casillas marcadas abajo pertenecen a la versión histórica; hay que repetirlas en la compilación actual antes de validar sus funciones. Los cambios posteriores del árbol de trabajo requieren una instalación nueva antes de validar su comportamiento físico.

El perfil de desarrollo anterior venció el 30 de septiembre de 2026. El despliegue del 6 de octubre firmó e instaló el bundle actual mediante aprovisionamiento automático; comprueba la vigencia del perfil antes de futuros despliegues. No se almacenan Team ID ni credenciales de firma en el repositorio.

Xcode 14.2 detecta el iPad, pero no tiene el developer disk image para depurarlo desde el IDE; `idevicedebug` tampoco puede iniciarlo. Los simuladores no emulan Bluetooth MIDI físico.

La conexión de los pads mediante un cable Lightning–USB‑C directo no los hizo aparecer en CoreMIDI. En iPad con Lightning, repetir la prueba con un adaptador Lightning a USB para cámara; algunos controladores requieren además alimentación externa.

## Pendientes

- [ ] En la versión 1.0 (build 2), completar y repetir una prueba final: preparación identificada por bloque, objetivo y miniatura del patrón integrador, tempo de aprendizaje y ritmo completo.
- [ ] Tras aprobar un checkpoint, comprobar que Inicio y Resultados sugieren el siguiente bloque pendiente; tras repasar un bloque cerrado, no deben regresar a sus lecciones.
- [ ] Completar el último ejercicio de un bloque sin acreditarlo y comprobar que «Siguiente ejercicio» no salta al siguiente bloque. La exploración manual desde Curso sigue disponible.
- [ ] Desde Resultados, usar «Siguiente ejercicio» y «Subir nivel»: deben entrar directamente en la cuenta atrás. «Ajustar práctica» abre preparación; «Volver al menú» regresa a Curso o Redobles según el ejercicio.
- [ ] En la compilación actual, anotar en cada ruta el buffer de E/S solicitado y el efectivo que muestra Opciones y guarda la traza; repetir con altavoz y auriculares.
- [ ] Con salida física, grabar 100 golpes aislados y comparar el inicio acústico de la claqueta neutra, la claqueta con tono alterado y los samples; conservar el audio original y resumir mediana y percentil 95.
- [ ] Hacer redobles rápidos del mismo sonido y alternar charles abierto/cerrado; verificar que el re-disparo no acumula colas, no hace clics audibles y el acompañamiento conserva sus notas futuras.
- [ ] Interrumpir el audio con una llamada/alarma, cambiar de salida y volver a primer plano; comprobar que el motor se reactiva, informa el buffer efectivo y permite empezar una sesión nueva sin reiniciar la app.
- [x] Firmar, exportar e instalar el bundle actual `com.alkbit.xroll` por USB; comprobar su identificador con `ideviceinstaller`.
- [ ] Repetir en el bundle actual las comprobaciones funcionales aplicables de esta lista.
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
- [ ] Comprobar que los bordes de los pads inferiores continúan la fuga de los carriles y conservan legibles los nombres en vertical y horizontal.
- [ ] Encadenar al menos 60 golpes Perfect/Good: comprobar pulsación de fondo desde 20, mayor brillo en 40 y 60, y reinicio al recibir Regular, Extra o Miss; repetir con Reduce Motion.
- [ ] Con el mismo ejercicio/ruta, comparar A/B «Anticipar un frame visual», calibrando antes de cada sesión.
- [ ] Compartir la traza JSON; para observar el sonido real, grabar pantalla y click/audio en la misma toma. El retorno de `play()` no es onset acústico.
- [ ] Completar y cerrar una sesión MIDI, después repetir la calibración y la sesión con pads táctiles.
- [ ] En Curso, abrir y practicar un ejercicio marcado como pendiente sin acreditar; comprobar que la vía guiada sigue recomendando un siguiente paso.
- [ ] Probar cualquier tempo directamente, superar una lección a su tempo de aprendizaje/70 % y confirmar que el reto opcional no bloquea el siguiente paso ni concede premios de tempos no tocados.
- [ ] Probar un checkpoint de capítulo posterior antes de acreditar los anteriores: guardar la evidencia y comprobar que el avance se activa solo al completar la ruta previa.
- [ ] Comprobar que Nivel dios exige 16 compases y que un intento más corto no otorga el trofeo ni modifica los desbloqueos.
- [ ] Instalar, abrir y cerrar la aplicación en un iPhone físico.
- [ ] En un iPhone SE, revisar Inicio en vertical: equipo y calibración se apilan y las tarjetas se pueden desplazar sin quedar cortadas.
- [ ] En iPhone vertical y horizontal, practicar con pads táctiles: escena, rejilla 4×4, BPM, pausa y terminar caben; los 16 pads conservan posición y son cómodos de tocar.
- [ ] Girar el iPhone durante una práctica y comprobar que la sesión, el reloj y el mapeo continúan sin reiniciarse.
- [ ] En iPhone vertical y horizontal, comprobar que aprendizaje del mapa y vista previa permiten llegar a todas sus acciones sin controles tapados.
- [ ] Cargar ejercicio MIDI y kit incluidos; completar una sesión y comprobar scoring/progreso.
- [ ] Golpes táctiles individuales, consecutivos y multitáctiles en ambas orientaciones.
- [ ] Conectar/desconectar y reconectar controlador USB MIDI compatible.
- [ ] Conectar/desconectar controlador Bluetooth MIDI compatible.
- [ ] Probar altavoz, auriculares cableados e interfaz externa; interrupciones y retorno a primer plano.
- [ ] Ejecutar calibración para cada ruta de entrada/salida y comprobar persistencia entre ejecuciones.
- [ ] Sesión prolongada, accesibilidad, cambios de tamaño/orientación y recuperación tras interrupción.

Cada casilla debe marcarse solo después de registrar dispositivo, versión de iOS, ruta utilizada, pasos y resultado observado.

El perfil de desarrollo usado por la versión histórica caducó el 30 de septiembre de 2026. La compilación actual se instaló con aprovisionamiento automático el 6 de octubre; verifica la vigencia del perfil antes de reinstalar.
