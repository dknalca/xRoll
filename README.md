# xRoll

Entrenador de finger drumming para macOS.

Las notas caen por carriles hacia una linea de golpe. Tu las tocas en los pads.
xRoll te dice con cuanta precision lo hiciste y si vas adelantado o atrasado.

Pensado para quien empieza de cero.

## Estado

En desarrollo temprano. Ver PLAN.md.

## Desarrollo

El nucleo actual es un paquete Swift sin dependencias externas. Desde la raiz del
repositorio:

```
swift test --filter XRollCoreTests
swift run xroll-preflight
swift run xroll-latency kick
swift run xroll-latency kick --check
swift run xroll-latency kick --source <uid-del-m-vave>
swift run xroll-play-kit --source <uid-del-m-vave>
swift run xroll-play-kit --source <uid-del-m-vave> --map mi-mvave.padmap
swift run xroll-pads
swift run xroll-map-pads --source <uid-del-m-vave> --output data/padmaps/mi-mvave.padmap
swift run xroll-preview hh_01_bombo_caja
```

El diagnostico enumera las fuentes MIDI, informa de la salida de audio y valida
el kit y los ejercicios. `xroll-latency` conecta todas las fuentes MIDI al sonido
indicado y sirve para la medicion fisica de la fase 0. No se puede ejecutar hasta
incorporar los WAV definitivos.

`xroll-play-kit` usa el mapa GM del `kit.json`: bombo 36, caja 38, palmada 39,
charles cerrado 42, charles abierto 46 y crash 49. Para descubrir las notas de
un controlador que se haya reconfigurado, se inicia una vez con `--log-events`.
Un `.padmap` valida que cada sonido, posicion y nota/canal solo aparezcan una vez.
`xroll-map-pads` crea ese archivo guiando seis golpes: bombo, caja, palmada,
charles cerrado, charles abierto y crash.

`xroll-pads` abre la ventana principal. La pestaña **Practicar** permite elegir
un ejercicio, escucharlo sin puntuacion y tocar los seis sonidos con el M-Vave o
con la rejilla de teclado documentada en `docs/MIDI_MAPPING.md`. La pestaña
**Mapear pads** captura seis golpes, guarda el `.padmap` en Application Support
y hace que la rejilla siga las posiciones fisicas guardadas.

La puntuacion y la calibracion viven en el nucleo. La calibracion descarta los
cuatro primeros golpes, usa la mediana del resto y se guarda por perfil completo:
entrada, salida, frecuencia y tamano de buffer.

`xroll-preview` reproduce todas las vueltas de un ejercicio sin puntuar. Sus
notas se programan contra el reloj de audio, con medio segundo de margen antes
del primer golpe.

Desde **Practicar**, `Empezar practica` abre la rejilla de dieciseis carriles.
Las notas llegan a la linea de golpe tras dos compases de anticipacion. Cada
golpe muestra Perfecto, Bien, Regular o Toque extra, junto con su desviacion y
si llego adelantado o atrasado; al terminar se muestra porcentaje y estrellas.

## Requisitos

- macOS 12 o superior
- Un controlador de pads MIDI por USB. Desarrollado contra un M-Vave SMC-Pad
  Pocket de 4x4, pero el asistente de mapeo acepta cualquiera.
- Tambien se puede tocar con el teclado del portatil.

## Caracteristicas

- Notacion vertical con anticipacion de dos compases y vista previa del patron
- Indicacion de que mano usar, reforzada con forma ademas de color
- Puntuacion con cuatro niveles de juicio y sistema de tres estrellas
- Aviso de si el golpe llego pronto o tarde
- Historial de intentos y curva de progreso
- Calibracion guiada por cada combinacion de entrada y salida
- Progresion por escalera: cada nivel introduce una sola dificultad

## Licencias

- **Codigo: GPL-3.0-or-later.** Cualquier obra derivada debe seguir siendo
  libre. Un fork no puede cerrarse.
- **Audio, graficos y documentacion: CC BY-SA 4.0.**

La procedencia de cada pieza de audio esta en `Resources/Loops/ATTRIBUTION.md`.

## Contribuir

Las contribuciones se entienden licenciadas bajo la licencia del proyecto. No
hay CLA que firmar. Es deliberado: menos friccion para quien aporta, y la
garantia de que el proyecto no puede relicenciarse a algo cerrado mas adelante.

## Validacion

La comprobacion automatizada y los pasos que requieren el Mac, M-Vave y salida
de audio estan en `docs/RELEASE_CHECKLIST.md`.
