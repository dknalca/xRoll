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
| `leftHand` | `#0072B2` | Mano izquierda |
| `rightHand` | `#E69F00` | Mano derecha |
| `perfect` | `#63E6BE` | Juicio perfecto |
| `good` | `#74C0FC` | Juicio bueno |
| `regular` | `#FFD43B` | Juicio regular |
| `miss` | `#FF6B6B` | Fallo |

Azul y naranja de manos no se usan como colores globales de acción.

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
Ruta por capítulos. La cabecera muestra nivel actual y niveles dominados; cada
bloque muestra su progreso, el siguiente escalón y una puerta al ritmo
completo. Las voces aisladas viven dentro de Preparación.

### Preparación
Objetivo, tempo, vueltas, ayudas, duración y estado compacto del equipo. Una acción principal.

### Práctica
Solo nombre, BPM, vuelta y pausa. Sin score cambiante ni estrellas. Carriles inactivos atenuados; feedback junto a la línea de golpe; movimiento gobernado por audio.

### Resultado
Jerarquía: diagnóstico, precisión, tendencia, consistencia, microscopio temporal y recomendación. Las estrellas son secundarias.

### Progreso
Barras de habilidad y una métrica temporal seleccionable. Evitar radar chart y gráficos superpuestos.

## Movimiento

| Acción | Duración |
|---|---:|
| Hover | 80–120 ms |
| Selección | 140–180 ms |
| Expandir panel | 180–240 ms |
| Navegación | 220–280 ms |

Las notas se mueven linealmente respecto al reloj musical. `Reduce Motion` elimina desplazamientos ornamentales.

## Accesibilidad

- Contraste mínimo 4.5:1 para texto normal.
- Forma y color para manos.
- Icono y texto para juicios.
- Navegación por teclado y VoiceOver.
- Tooltips en controles solo-icono.
- Alternativa tabular al microscopio.
- Modos: color + forma, forma de alto contraste, etiquetas L/R.

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
