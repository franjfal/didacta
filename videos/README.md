# Los videotutoriales de Didacta

El estudio donde se hacen los vídeos del
[plan de videotutoriales](../PLAN-DE-VIDEOTUTORIALES.md). Todo corre en local,
con herramientas libres y sin ningún servicio de pago: se hace un vídeo, o los
setenta y siete, con la misma orden.

```bash
python3 videos/hacer.py preparar      # una vez por máquina
python3 videos/hacer.py A01           # el vídeo A01, entero
```

Sale a `videos/salida/`: el MP4 (1080p, con los subtítulos y los capítulos
dentro), los subtítulos sueltos en `.vtt` y `.srt`, los capítulos en texto para
la descripción y una imagen de portada.

**Y a la web, en el mismo paso.** En `web/docs/videos/a1/` deja la miniatura,
la portada, los subtítulos, los capítulos y la transcripción, y en
`web/docs/videos/media/` un MP4 más ligero (~4 MB por minuto; el texto de un
PDF se sigue leyendo). Con eso el vídeo aparece en la galería de
videotutoriales, en su página y en el recuadro «En vídeo» de las páginas de la
documentación que nombra el catálogo, sin tocar nada más. Cómo se pinta todo
eso lo cuenta «Los vídeos» en [`web/README.md`](../web/README.md).

## Rehacer un vídeo cuando cambia la aplicación

**Se vuelve a ejecutar la misma orden.** Nada de un vídeo apunta a un píxel ni a
un segundo escritos a mano, y por eso se puede rehacer sin tocarlo:

- **Las pantallas no se graban: las pinta la propia aplicación.**
  `app/tool/shots_video.dart` abre Didacta de verdad --con git, el motor y el
  repositorio de ejemplo, el mismo que crea «Probar con un ejemplo»-- y
  fotografía cada pantalla que pide el vídeo. Junto a cada captura escribe
  **dónde está cada cosa**: la pestaña «compilar», la fila de «Álgebra de
  límites», el aviso de guardado. Si mañana la pestaña se mueve, la cámara, el
  recuadro y el cursor van a donde esté.
- **Los PDF se compilan con el motor de ahora**, y la página y las zonas se
  buscan por su texto («desde *Nota didáctica* hasta *la pizarra.*»).
- **El montaje se engancha a la voz**, no al reloj: «cuando dice *este
  párrafo*». Si una frase cambia, lo que se ve la sigue.

`hacer.py` se salta lo que ya está al día: las capturas solo se vuelven a
sacar si ha cambiado `app/lib`, el ejemplo o la lista de capturas; los PDF, si
ha cambiado el LaTeX, el motor o el ejemplo; y la voz solo dice las frases que
no había dicho ya. Para forzar un paso: `--rehacer capturas,pdf`.

Si una pantalla cambia tanto que una zona ya no existe --otro nombre, otro
botón--, el arnés lo dice al capturar («sin zona "compilar"») y el montaje falla
diciendo cuál. Se arregla en el `capturas.json` del vídeo, no en el montaje.

## Un vídeo por dentro

Cada vídeo es una carpeta con tres ficheros:

| Fichero | Qué es |
| --- | --- |
| `guion.yaml` | Lo que se dice, escena a escena y frase a frase, y los PDF que salen. De aquí salen la voz y los subtítulos. |
| `capturas.json` | Qué pantallas se fotografían, qué se pulsa en cada una y qué zonas interesan. Lo lee el arnés de Flutter. |
| `escenas.js` | El montaje: qué se ve mientras se dice cada frase. |

Y el estudio, común a todos:

| | |
| --- | --- |
| `hacer.py` | La orden: capturas, PDF, voz, tiempos, imagen, sonido y subtítulos. |
| `estudio/estudio.css` | La identidad: los colores de la aplicación y de los PDF, Inter y JetBrains Mono. |
| `estudio/estudio.js` | El motor: cada fotograma se calcula a partir del tiempo, así que sale igual cada vez. Ventana de la aplicación, cámara, recuadros, cursor, hojas de PDF, la marca. |
| `estudio/grabar.mjs` | Pinta cada fotograma en Chrome sin ventana y se lo pasa a ffmpeg. |
| `herramientas/voz.py` | La locución, con caché y control de calidad. |
| `herramientas/casting.py` | Cómo se eligió la voz (ver abajo). |
| `herramientas/acento.py` | Mide si la voz distingue la «z» de la «s». |
| `herramientas/pdf.py` | Compila, busca la página y mide las zonas. |

Para mirar un fotograma sin hacer el vídeo entero:

```bash
python3 videos/hacer.py A01 --fotos 4,20,47.5
```

deja los PNG en `videos/.build/A01-…/fotos/`.

## La voz

Es **Qwen3-TTS** (Apache 2.0), en local, en precisión completa. No es la voz de
nadie: el modelo de diseño de voz la inventó a partir de una descripción --un
profesor universitario de Madrid, barítono, serio pero dinámico-- y cada frase
de cada vídeo se dice **clonando esa muestra**, `voz/narrador.wav`. Así suena
igual en el primer vídeo y en el último, y en uno que se rehaga dentro de un
año.

La muestra salió de un **casting** medido, porque nadie puede escuchar treinta
candidatas con criterio:

```bash
python3 videos/hacer.py voz narrador
```

prueba varias descripciones y semillas y mide en cada una:

- **el acento**: si distingue «hace», «lección» o «fácil» (/θ/, un soplo sin
  silbido) de «paso» o «más» (/s/, un silbido fuerte). Es el rasgo que mejor
  separa el castellano de España del de América, y se mide en decibelios:
  calibrado con dos voces de referencia leyendo el mismo texto, la de España
  da +12 dB y la de México −1;
- **la altura y el movimiento del tono**: un barítono ronda los 100-130 Hz, y
  entre 6 y 11 semitonos de recorrido es una voz viva sin ser teatral;
- **el ritmo**, en palabras por minuto;
- **la fidelidad**: Whisper la transcribe y se compara con el texto;
- **la naturalidad**: UTMOS, un modelo abierto que predice la nota que pondrían
  oyentes de verdad.

Gana la más natural de las que pasan todo. Las tres mejores quedan en
`voz/candidatas/` para escucharlas; cambiar de voz es copiar la que se prefiera
encima de `voz/narrador.wav`, y los vídeos se vuelven a locutar solos.

Cada frase de un vídeo pasa además por Whisper al locutarse: si lo que se oye
no es lo que dice el guion --una palabra saltada, otra repetida--, se vuelve a
decir con otra semilla. Lo que se escribe de una manera y se dice de otra
(«LaTeX», «látex») está en `voz/pronunciacion.yaml`.

## Lo que hace falta

- Python 3.10 o posterior, Node y ffmpeg.
- Flutter, para las capturas (el mismo que compila la aplicación).
- Ghostscript y una distribución de TeX, para los PDF (los mismos que usa
  Didacta).
- Google Chrome: `playwright-core` usa el que ya hay, sin descargar otro.
- Unos 12 GB de disco para los modelos (se descargan la primera vez).

Un Mac con Apple Silicon locuta en la GPU; un vídeo de dos minutos son unos
cinco minutos de voz la primera vez y nada las siguientes, y la imagen, unos
tres.
