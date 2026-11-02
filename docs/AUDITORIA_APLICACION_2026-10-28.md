# Auditoría de la aplicación — 28 de octubre de 2026

## Alcance y criterio

Esta revisión amplía `AUDIT_2026-10-25.md` y `REVISION_CODIGO_2026-10-28.md`.
Se inventariaron fuentes, pruebas, recursos, proyecto iOS, scripts y workflows;
se inspeccionaron especialmente entrada y salida de datos, persistencia, curso,
scoring, diagnóstico, calibración, MIDI/audio y los límites de sesión y navegación.
Los 26 archivos Swift de `XRollCore` aparecen mencionados en el proyecto iOS.

Es una revisión sistemática, no una demostración de ausencia de defectos: no se
han recorrido manualmente todas las pantallas, combinaciones de datos ni todas las
rutas de hardware. Se distinguen las reproducciones automatizadas de los riesgos
que siguen necesitando una prueba física o una investigación adicional.

## Hallazgos reproducidos y corregidos

### B-01 — Una importación podía descartar evidencia distinta

`ProgressStore.importAttempts` e `importJSON` consideraban duplicados dos
intentos con el mismo resumen, aunque difirieran su contexto didáctico o sus
registros de golpes. Si el primero era un fragmento y el segundo un ritmo
completo, el segundo se perdía y podía faltar una acreditación curricular.

Ambos importadores buscan candidatos por sus campos indexados y comparan el
intento completo antes de omitirlo. La transacción, el procesamiento incremental
del JSON y la deduplicación al volver a importar la misma copia se mantienen.
La regresión incluye el mismo resumen con distinto alcance y con distintos
registros de golpes, tanto en memoria como en JSON.
El cambio evita nuevas pérdidas al importar, pero no puede reconstruir datos ya
descartados: para recuperarlos hace falta el archivo original. Dos intentos
idénticos en todos sus campos siguen considerándose duplicados; el formato no
incluye un identificador individual persistente que permita distinguirlos.

### B-02 — Mejora de timing declarada con un solo golpe comparable

`CoachingComparison` exigía cuatro oportunidades, pero contaba también los
fallos sin desfase. Con tres fallos y un golpe asociado en cada ronda podía
afirmar una mejora del tiempo basándose en un único valor por ronda. Para
comparar timing ahora se exige el mínimo de golpes asociados en ambas rondas;
la comparación de fallos repetidos sigue usando oportunidades y fallos.

### B-03 — Medianas incorrectas en pulso interno y dominio

`PulseDriftAnalyzer` y `MasteryEvaluator` elegían el valor central superior
cuando había una cantidad par de datos. Por ejemplo, offsets simultáneos de
−20 y +20 ms se interpretaban como +20 ms y podían producir una deriva falsa;
desfases absolutos de 0 y 40 ms podían denegar el sello pese a una mediana de
20 ms. Se comparte el cálculo de mediana también en las comparaciones y el
análisis correctivo. Hay regresiones para deriva y sello.

## Observaciones y límites

- MIDI físico, Bluetooth, cambios de ruta y respuesta acústica requieren los
  dispositivos concretos; una inspección de cola, cerrojos o scheduling y las
  pruebas de PCM no miden latencia extremo a extremo.
- La interfaz macOS no dispone de una suite automatizada equivalente a la de
  navegación iOS. VoiceOver, contraste, giro y Dynamic Type requieren además la
  comprobación manual de `RELEASE_CHECKLIST.md`.
- Los coordinadores de macOS e iOS siguen siendo extensos; la auditoría no los
  ha reestructurado. No se ha hecho fuzzing exhaustivo de todos los archivos MIDI
  ni se han ejecutado todas las combinaciones de entrada, salida y contenido.
- El empaquetado macOS permanece sin firma ni notarización, de acuerdo con D-059.
  No se ha instalado ni publicado una distribución durante esta revisión.

## Comprobaciones

| Comprobación | Resultado |
|---|---|
| `swift build` | Correcto |
| `swift test` | 221 pruebas, cero fallos; incluye exportación y restauración de 100.005 intentos |
| `swift run xroll-preflight` | 129 ejercicios y 10 sonidos válidos; no se detectaron fuentes MIDI |
| Compilación genérica iOS con `CODE_SIGNING_ALLOWED=NO` | Correcta |
| Suite completa `XRollUITests` en iPhone simulado, repetida tras los cambios | 27 pruebas, cero fallos |
| `git diff --check` | Correcto |

El simulador usa perfiles y datos de prueba; no valida calibración física ni
respuesta acústica. No se ha ejecutado la suite completa en iPad, ni pruebas de
fuzzing o sanitizadores en esta ampliación. No se han medido latencia o FPS.
