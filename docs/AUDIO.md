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
    snare.wav
    clap.wav
    hihat_closed.wav
    hihat_open.wav
    crash.wav
```

Minusculas, guion bajo, sin acentos ni espacios.

El kit inicial incluye solo esos seis sonidos. Los demas identificadores se
anadiran cuando existan sus WAV y ejercicios que los necesiten.

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

Los WAV definitivos los aporta el propietario del proyecto. La fase 0 no empieza
hasta disponer al menos de un sample que cumpla estos requisitos, porque medir
con un sonido provisional haria que la puerta de latencia no representase la app
que se va a distribuir.

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

## Loops de acompanamiento

Van en `Resources/Loops/`, con este nombre:

```
nombre_XXXbpm.wav

boom_bap_085bpm.wav
soul_loop_090bpm.wav
dusty_keys_100bpm.wav
```

**El BPM va relleno a tres digitos.** Sin relleno, el orden alfabetico coloca
`100bpm` antes que `85bpm` y el desplegable sale desordenado.

Requisitos:

- **Recortado exacto al compas.** Ni silencio delante ni cola sobrante. Un loop
  con 20 ms de mas se desfasa 20 ms en cada vuelta y a la cuarta ya esta peleado
  con la rejilla.
- **Bucle sin clic**, empalmando en cruce por cero.
- 4/4.

Los compases no se declaran en el nombre: la app los calcula con la duracion y
el BPM y **avisa al cargar si el resultado no da un numero entero de compases**.
El nombre queda simple y los errores se cazan solos.

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
