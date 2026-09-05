# Ejercicios

## Formato

```
{
  "format": 1,
  "id":       identificador estable, no se cambia nunca
  "title":    nombre visible
  "family":   agrupacion, por ejemplo "hiphop_boombap"
  "level":    posicion en la escalera
  "bpm":      fijo
  "meter":    [4, 4]
  "bars":     compases del patron
  "grid":     subdivisiones por compas, 16 es semicorcheas
  "repeats":  vueltas, 4 en los basicos
  "kit":      carpeta del kit
  "loop":     nombre del loop, o null para claqueta sola
  "offset":   entrada desplazada en pasos, 0 por defecto (futurible)
  "notes": [
    { "step": indice en la rejilla, "sound": id canonico, "hand": "L", "R" o null }
  ]
}
```

`step` va de 0 a `bars * grid - 1`. En una rejilla de 16 y un compas, el primer
tiempo es 0, el segundo 4, el tercero 8 y el cuarto 12.

`offset` esta reservado para la variante de **entrada desplazada**: empezar el
patron por el segundo tiempo o por la contra en vez de por el principio. La
sonoridad cambia por completo y es un ejercicio excelente. No se implementa
todavia pero el campo existe para no romper ficheros mas adelante.

## Progresion por escalera

Cada nivel introduce **una sola dificultad** y conserva lo aprendido. Puede ser
un sonido nuevo, un cambio de patron o un cambio de tempo; nunca se cambian dos
variables en el mismo salto. Esto permite consolidar una coordinacion antes de
anadir otra voz.

| Nivel | Dificultad nueva | Resultado |
|---|---|---|
| 1 | Bombo y caja | El esqueleto |
| 2 | Charles cerrado | Ya es un groove |
| 3 | Bombo desplazado | Consolida el groove clasico |
| 4 | Charles abierto | Respiracion |
| 5 | Palmada | Refuerzo del backbeat |
| 6 | Bombo a contratiempo | Independencia en semicorcheas |
| 7 | Fill de palmada | Relleno antes del cierre |
| 8 | Subida a 90 BPM | Consolidación del groove |

## Reparto de manos

Los ficheros de ejemplo usan este criterio: **bombo mano izquierda, caja mano
derecha, y el charles con la mano que quede libre.**

Cuando el bombo y el charles caen a la vez, el charles va con la derecha. Cuando
la caja y el charles coinciden, el charles va con la izquierda. Los charles
sueltos alternan entre si, aunque un golpe simultaneo puede obligar a repetir una
mano entre dos corcheas consecutivas.

No es la unica digitacion valida, pero es consistente y se puede aprender sin
pensar, que es lo que necesita un principiante.

## Al escribir ejercicios nuevos

- Una sola dificultad nueva por nivel.
- El nivel 1 de cada familia tiene que poder completarlo alguien que no ha
  tocado nunca.
- Tempos iniciales entre 70 y 90. Es donde vive el hip hop y donde hay margen
  para pensar.
- Comprobar que la subdivision mas corta no estrecha las ventanas de juicio mas
  de la cuenta. Ver el recorte en docs/SCORING.md.
