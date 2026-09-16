---
name: xroll-practice-engine
description: Use when changing scoring, calibration, ExerciseTimeline, PracticeSession, practice flow, diagnostics, progress, or SpriteKit practice feedback in xRoll.
---

# Motor de práctica de xRoll

Lee `CLAUDE.md`, `docs/SCORING.md`, `docs/DECISIONS.md` y `docs/PEDAGOGY_AND_TRAINING.md` antes de cambiar comportamiento de práctica.

## Límites de responsabilidad

- `XRollCore` posee timeline, matching, scoring, calibración, sesiones, diagnóstico y SQLite.
- `XRollPads` coordina la sesión: configuración didáctica, anticipación, acompañamiento, metrónomo, loop, persistencia de preferencias y navegación.
- `PracticeScene` solo representa el estado temporal y el feedback. No coloques scoring, matching, compensación ni reglas didácticas dentro de SpriteKit.
- La app usa un `Model` observable como coordinador; al extraer responsabilidad de él, conserva explícitamente el ciclo de vida que detiene sesiones, buffers y callbacks al salir de una pantalla.

## Reglas de producto

- El usuario es principiante: mantiene los cuatro juicios y el feedback accionable de adelantado o atrasado.
- La calibración guiada es obligatoria antes de puntuar y se guarda por perfil completo de entrada, salida, frecuencia y buffer.
- No confundas sesgo del usuario con latencia técnica. No publiques números de precisión, FPS o latencia sin una ejecución reproducible.
- Los ejercicios pueden transportar velocity MIDI para compatibilidad e inspección, pero no la conviertas en objetivo, requisito, juicio ni variable de scoring hasta que exista una decisión de producto que lo autorice.
- Mantén la puntuación determinista: una nota consume como máximo un golpe; golpes sobrantes y fallos siguen siendo distinguibles.

## Verificación

1. Añade o ajusta pruebas deterministas en `Tests/XRollCoreTests` para cambios del núcleo.
2. Ejecuta `swift test --filter XRollCoreTests` y después `swift test`.
3. Si cambias visualización, prueba `swift run xroll-pads`; comprueba que abandonar práctica cancela sonidos programados, loop y callbacks retrasados.
4. Si cambia calibración o score, revisa los casos de simultaneidad, golpes extra, fallos, compensación y ventanas por subdivisión.
