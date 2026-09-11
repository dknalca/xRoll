# Documentación de xRoll

Esta carpeta contiene la especificación de producto, experiencia, contenido didáctico y arquitectura técnica de xRoll.

## Norte de producto

xRoll no pretende ser únicamente un juego de ritmo. Su propuesta es diagnosticar **por qué** un groove falla y recomendar qué practicar después.

> Escuchar → comprender → tocar → diagnosticar → corregir → transferir.

## Índice

### Producto y decisiones
- [PRODUCT_VISION.md](PRODUCT_VISION.md): visión, principios y roadmap.
- [DECISIONS.md](DECISIONS.md): registro de decisiones y motivos.
- [ARCHITECTURE.md](ARCHITECTURE.md): arquitectura funcional y técnica.
- [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md): fases recomendadas.

### Experiencia e interfaz
- [UI.md](UI.md): comportamiento general de interfaz.
- [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md): lenguaje visual «Estudio musical moderno».
- [USER_GUIDE.md](USER_GUIDE.md): guía de uso.

### Currículo
- [PEDAGOGY_AND_TRAINING.md](PEDAGOGY_AND_TRAINING.md): marco didáctico y
  requisitos del motor de entrenamiento; fuente de verdad pedagógica.
- [CURRICULUM.md](CURRICULUM.md): programa completo y rutas por género.
- [INITIATION.md](INITIATION.md): bloque «De cero a tu primer groove».
- [EXERCISES.md](EXERCISES.md): formato y validación de ejercicios.
- [SCORING.md](SCORING.md): puntuación y diagnóstico temporal.

### Pads, MIDI y audio
- [PAD_LAYOUTS.md](PAD_LAYOUTS.md): presets, orientación y editor custom.
- [PADMAP_V2.md](PADMAP_V2.md): modelo many-to-one y migración.
- [MIDI_MAPPING.md](MIDI_MAPPING.md): MIDI y aprendizaje del controlador.
- [AUDIO.md](AUDIO.md): muestras, kits y loops.
- [LATENCY_PROTOCOL.md](LATENCY_PROTOCOL.md): protocolo físico de latencia.

### Desarrollo y distribución
- [DEVELOPMENT.md](DEVELOPMENT.md)
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)
- [DISTRIBUTION.md](DISTRIBUTION.md)
- [COMMUNITY_MIDI.md](COMMUNITY_MIDI.md)

## Fuentes de verdad

Para evitar contradicciones:

1. Las decisiones vigentes están en `DECISIONS.md`.
2. El marco didáctico vigente está en `PEDAGOGY_AND_TRAINING.md`.
3. Todos los ejercicios activos, integrados y comunitarios, son Standard MIDI
   Files. El cargador los convierte al modelo interno; no existe un segundo
   catálogo ni formato histórico distribuido.
4. El layout describe funciones físicas; el mapeo MIDI describe los mensajes del dispositivo.
5. La latencia técnica y el sesgo humano se almacenan por separado.
6. El catálogo activo contiene 56 ejercicios MIDI: tronco común, Hip-hop,
   Rock, Funk, Blues/Shuffle y Jazz. El test de recursos verifica el conteo.
