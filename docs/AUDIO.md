# Audio

## Identificadores canonicos de sonido

Estos once son el catalogo canonico. No se inventan otros sin actualizar este
documento. Cada kit puede incluir un subconjunto, pero un ejercicio solo puede
usar sonidos presentes en el kit que declara.

| id | Etiqueta | Nota GM |
|---|---|---|
| `kick` | Bombo | 36 |
| `rim` | Aro | 37 |
| `snare` | Caja | 38 |
| `clap` | Palmada | 39 |
| `tom_low` | Tom grave | 41 |
| `hihat_closed` | Charles cerrado | 42 |
| `tom_mid` | Tom medio | 45 |
| `hihat_open` | Charles abierto | 46 |
| `tom_high` | Tom agudo | 48 |
| `crash` | Crash | 49 |
| `ride` | Ride | 51 |

Los numeros son el mapa de percusion General MIDI, que es el que respeta casi
todo el mundo. `clap` y `rim` estan incluidos porque en hip hop aparecen bastante
mas que los toms o el ride: un boom bap tipico es bombo, caja, charles, palmada
y aro.

## Estructura de un kit

```
Resources/Kits/hiphop_basic/
    kit.json
    kick.wav
    rim.wav
    snare.wav
    clap.wav
    hihat_closed.wav
    hihat_open.wav
    tom_lo.wav
    tom_hi.wav
    crash.wav
    ride.wav
```

Minusculas, guion bajo, sin acentos ni espacios.

El kit inicial distribuye diez voces: `kick`, `rim`, `snare`, `clap`, `tom_low`,
`hihat_closed`, `hihat_open`, `tom_high`, `crash` y `ride`. El identificador
canónico `tom_mid` no forma parte todavía de este kit.

**Ningun nombre de fichero aparece en el codigo.** El codigo lee kit.json. Anadir
un kit debe consistir en soltar una carpeta.

## Requisitos de los samples

- 44,1 o 48 kHz, en PCM de 16/24 bits o Float32. El motor convierte todos los
  formatos admitidos a su mezcla interna; no se da por hecho que los WAV tengan
  la misma profundidad de bits.
- **Sin silencio al principio.** Recortado al primer cruce por cero. Cualquier
  silencio inicial se convierte en latencia percibida que despues no hay forma
  de compensar, porque es indistinguible de la latencia real del sistema.
- One-shots con la cola completa. No cortar la caida del crash ni del ride.
- Normalizados entre si, para que ningun pad suene desproporcionado.
- Grupo de silenciado en los charles: el cerrado corta al abierto, como en una
  bateria real.

Los WAV definitivos los aporta el propietario del proyecto. Un sample provisional
no debe llegar a distribuirse: su silencio inicial o su nivel pueden deteriorar
la respuesta percibida y el equilibrio del kit.

## Licencia de los samples

Es la trampa clasica de una app de bateria abierta: los samples de packs
comerciales casi nunca se pueden redistribuir, y publicar el repositorio es
redistribuirlos.

Lo que sirve:

- **Freesound.org filtrando por CC0.** La fuente mas solida.
- Grabarlos uno mismo.
- **Generarlos por codigo.** Un 808 es una sinusoide con envolvente de tono y una
  caja es ruido con envolvente. Para hip hop no es un sucedaneo, es el sonido
  correcto, y resuelve licencia y tamano de binario de una vez.

Aviso: CC0 es una **renuncia, no una garantia de titularidad**. Si alguien subio
un loop que contenia material ajeno, su CC0 no lo limpia.

## Loops de acompañamiento

Van en `Resources/Loops/`, con BPM al final del nombre. El detector acepta dos
o tres dígitos y no distingue mayúsculas:

```
nombre 90bpm.wav
boom_bap_085bpm.wav
piano 88bpm.wav
```

Se puede incluir el estilo en el nombre (`Bass Hiphop 93bpm.wav`): la selección
automática usa ese marcador de estilo y después prefiere el loop cuyo BPM está
más cerca del tempo de práctica. El usuario puede elegir otro loop desde
Preparación. Si no hay loop con el estilo del ejercicio, se usa el genérico más
cercano por BPM.

Requisitos:

- **Recortado exacto al compas.** Ni silencio delante ni cola sobrante. Un loop
  con 20 ms de mas se desfasa 20 ms en cada vuelta y a la cuarta ya esta peleado
  con la rejilla.
- **Bucle sin clic**, empalmando en cruce por cero.
- 4/4.

Los compases no se declaran en el nombre. Antes de distribuir un loop, verifica
manualmente que su duración y BPM corresponden a un número entero de compases;
la app detecta el BPM por el nombre, pero todavía no valida esa duración.

## Esquema de kit.json

```
{
  "format": 1,
  "id": "hiphop_basic",
  "name": "Hip Hop Basico",
  "sounds": [
    {
      "id":          identificador canonico de la tabla de arriba
      "label":       nombre visible
      "file":        fichero wav dentro de la carpeta del kit
      "gm_note":     nota General MIDI sugerida por defecto
      "choke_group": grupo de silenciado, o null
    }
  ]
}
```

Dos sonidos con el mismo `choke_group` se cortan mutuamente.
