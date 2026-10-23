# Sistema visual — Estudio musical moderno

## Dirección

Interfaz oscura, elegante y precisa, inspirada en software de producción y hardware de pads. Debe sentirse como un instrumento, no como un menú ni como un arcade.

- Fuera de la práctica: estudio y control.
- Durante la práctica: concentración y ritmo.
- Después: diagnóstico y siguiente acción.

## Paleta

| Token | Hex / valor | Uso |
|---|---|---|
| `canvas` | `#0B0D10` | Fondo principal |
| `surface` | `#12151A` | Paneles |
| `surfaceRaised` | `#191D23` | Selección y modales |
| `surfaceHover` | `#20252D` | Hover |
| `textPrimary` | `#F1F3F5` | Texto principal |
| `textSecondary` | `#A3ABB5` | Texto secundario |
| `textMuted` | `#6D7580` | Metadatos |
| `accent` | `#63E6BE` | Acción principal |
| `perfect` | `#63E6BE` | Juicio perfecto |
| `good` | `#74C0FC` | Juicio bueno |
| `regular` | `#FFD43B` | Juicio regular |
| `miss` | `#FF6B6B` | Fallo |

En el gameplay, `GameplayVisualTheme.soundAccent(_:)` es la fuente de verdad del
color por sonido. Nota, carril y receptor comparten ese color; no se codifica la
mano con forma, color o letras.

## Tipografía

- Títulos: SF Pro Display.
- Interfaz: SF Pro Text.
- BPM, offsets y métricas: SF Mono.

| Uso | Tamaño orientativo |
|---|---:|
| Hero | 34–40 pt |
| Título de pantalla | 26–30 pt |
| Título de panel | 17–19 pt |
| Cuerpo | 14–15 pt |
| Etiqueta | 12–13 pt |
| Métrica principal | 32–48 pt |

## Espaciado y forma

Base de 4 pt: `4, 8, 12, 16, 24, 32, 48`.

Radios:
- controles: 8 pt;
- paneles: 14 pt;
- hero: 18 pt.

Las superficies se separan por luminancia, borde de un píxel y sombra suave. Evitar blur y glassmorphism indiscriminados.

## Navegación

Barra lateral:

```text
PRÁCTICA
  Inicio
  Curso
  Redobles
ANÁLISIS
  Progreso
EQUIPO
  Pads y layout
  Audio y latencia
  Ajustes
```

## Pantallas principales

### Inicio
Responde «¿qué debería practicar ahora?». Incluye recomendación principal, motivo, duración, continuidad del curso y problema que necesita atención.

### Curso
Metro del Ritmo de quince estaciones conectadas por vías. El tren identifica la
parada actual. La cabecera destaca «Empezar nivel N» o «Preparar reto final»; la
estación actual se abre y las demás quedan resumidas. Los niveles tienen numeración
local y el reto de estación se señala con una bandera. Mapa, premios y acciones
se presentan con la misma vista compartida en macOS e iOS.

### Preparación
Objetivo, tempo, vueltas, ayudas, duración y estado compacto del equipo. Una acción principal.
Una lección pendiente se abre a su tempo de aprendizaje, con el criterio visible
de ritmo completo y 70 %. Los seis retos de velocidad quedan dentro de las
opciones plegadas; no compiten con empezar el ritmo.

### Práctica
Solo nombre, BPM, vuelta y pausa; tras cinco aciertos aparece una racha compacta. Sin score cambiante ni estrellas. La escena SpriteKit ocupa el escenario principal: autopista trapezoidal de profundidad suave, slots físicos fijos, receptores en el plano de impacto y feedback en una banda separada debajo de los pads. El acompañamiento se selecciona por estilo/BPM y puede cambiarse en Preparación. El movimiento temporal sigue gobernado por el reloj de audio.

Los tokens, la proyección y los efectos SpriteKit viven en `Sources/XRollPads/GameplayVisualSystem.swift`; `PracticeScene` compone la presentación sin tomar decisiones de timing o scoring. Fuera de la autopista hay pistas de circuito impreso, ramas y vías ordenadas con la misma perspectiva que la carretera; se crean solo al reconstruir la escena. Las notas y los receptores inferiores siguen la misma proyección y punto de fuga. Las rachas Perfect/Good aumentan gradualmente la respiración de los carriles activos y la intensidad/frecuencia de onda de las separaciones. Desde 20 golpes seguidos el fondo pulsa; se ilumina más al llegar a 40 y 60. Es una recompensa visual únicamente: al reiniciar la racha, la escena vuelve a la calma.

La marca `XRollBrandMark` representa dos baquetas cruzadas sobre el impacto. Al abrir la app, `XRollLaunchView` presenta brevemente esa marca y atenúa su salida; `Reduce Motion` evita la escala animada. En Inicio se muestra una de las diez citas registradas con fuentes en `docs/DRUMMER_QUOTES.md`.

### Resultado
Al completar una estación nueva, jerarquía de celebración: tren, parada completada,
estrellas y «Siguiente parada» hacia la primera estación pendiente. Al terminar
la línea se ofrece «Ver mi recorrido». El diagnóstico y los detalles permanecen
debajo de la celebración.

Al aprobar un nivel de la estación actual con ritmo completo y 70 %, aparece
«Continuar» o «Preparar reto final», con «Volver al mapa» como salida secundaria.
La continuación normal arranca el siguiente nivel; el reto abre su preparación.
Los retos de velocidad se eligen desde Preparación. Fuera de esta continuación
del recorrido se mantiene el resultado diagnóstico con precisión, tendencia,
consistencia y herramientas de práctica opcionales.

Si un patrón completo pendiente necesita apoyo, el panel compartido ofrece
«Reintentar» con guía completa y un tempo algo menor. Tras un buen intento lento,
«Continuar» aumenta 2–4 BPM hacia el objetivo conservando el mismo ejercicio.
El título es «Vamos paso a paso» o «¡Buen ritmo!», sin anunciar un nivel superado
hasta que se cumpla su criterio real. La acción no pide configurar un rescate.

### Progreso
Barras de habilidad y una métrica temporal seleccionable. Evitar radar chart y gráficos superpuestos.

## Movimiento

| Acción | Duración |
|---|---:|
| Hover | 80–120 ms |
| Selección | 140–180 ms |
| Expandir panel | 180–240 ms |
| Navegación | 220–280 ms |
| Fin de ejercicio → resultado | 1,05 s | Porcentaje animado en una pantalla de transición |

Las notas se mueven linealmente respecto al reloj musical. Su contorno se calcula para cada carril a partir de los mismos bordes proyectados de la pista; al viajar se escala uniformemente con la profundidad para conservar la inclinación de esos lados. `Reduce Motion` conserva el recorrido y elimina partículas y desplazamientos ornamentales del feedback.

## Accesibilidad

- Contraste mínimo 4.5:1 para texto normal.
- Forma y color para manos.
- Icono y texto para juicios.
- Navegación por teclado y VoiceOver.
- Tooltips en controles solo-icono.
- Alternativa tabular al microscopio.
- Modos: color por sonido, contorno de alto contraste y etiquetas de sonido.

## Componentes SwiftUI

```text
XRollUI/
  Foundation/
    XRollColors.swift
    XRollTypography.swift
    XRollSpacing.swift
    XRollMotion.swift
    XRollShapes.swift
  Components/
    StudioPanel.swift
    PrimaryButton.swift
    MetricCard.swift
    StatusPill.swift
    ExerciseCard.swift
    EquipmentStatus.swift
    SkillBar.swift
    PadGrid.swift
```

SwiftUI controla navegación y pantallas. SpriteKit controla carriles, notas, rejilla, línea de golpe y feedback de alta frecuencia. El scoring permanece en `XRollCore`.
