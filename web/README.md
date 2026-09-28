# La web de Didacta

Documentación y descargas: <https://franjfal.github.io/didacta/>

[MkDocs Material](https://squidfunk.github.io/mkdocs-material/), sin ningún
plugin. Todo lo que aquí parece uno --las tarjetas, los desplegables, las
pestañas, los iconos-- viene de las extensiones de markdown que Material ya
trae.

## Trabajar en ella

```bash
cd web
pip install -r requirements.txt
mkdocs serve
```

Y en <http://127.0.0.1:8000>, recargándose sola.

## Las dos cosas que no se escriben a mano

**Las capturas de pantalla.** No están versionadas: las pinta la propia
aplicación, con sus datos de prueba, desde su propio código.

```bash
cd app && flutter test tool/generate_screenshots.dart
```

Escribe `web/docs/img/app/*.png`. Una pantalla que cambia deja la captura
vieja, y una captura vieja en la documentación es peor que ninguna: enseña
botones que ya no están. Por eso el despliegue las regenera siempre, y por eso
**no están versionadas**.

La consecuencia práctica: en un clon recién hecho, `mkdocs serve` funciona y
avisa de las imágenes que faltan; `mkdocs build --strict` falla hasta que se
generan. Es el mismo aviso que impide publicar una web con capturas rotas.

**El bloque de descargas.** Sale del release que hay publicado.

```bash
python3 packaging/web.py downloads --repo franjfal/didacta
```

Escribe `web/docs/_snippets/descargas.md`, que la portada y la página de
descarga incluyen con `--8<--`. Sin ningún release publicado escribe un bloque
que lo dice, así que `mkdocs serve` funciona igual.

## Lo que no se copia: se incluye

`docs/AUTHORING.md`, `ARCHITECTURE.md`, `docs/DISTRIBUTION.md` y el
`CHANGELOG.md` viven en el repositorio y los lee quien trabaja en el código.
La web los **incluye** (`pymdownx.snippets`, con `base_path` apuntando fuera
de `docs/`), no los duplica: dos copias de una referencia son una referencia
buena y una vieja, y la vieja siempre es la que alguien está leyendo.

Si cambias uno de esos ficheros, la web cambia con él.

## Los vídeos

La galería de videotutoriales (`/videos/`), la página de cada vídeo --con su
reproductor, sus capítulos y su transcripción, que es lo que encuentra el
buscador-- y el recuadro «En vídeo» de las páginas de la documentación **no se
escriben a mano**: los pinta `hooks/videos.py` al construir. No es un plugin,
es un fichero de este repositorio que MkDocs ejecuta (`hooks:` en
`mkdocs.yml`), así que no hay nada que instalar.

Salen de dos sitios:

- **`docs/videos/catalogo.yaml`**, escrito a mano a partir del
  [plan de videotutoriales](../PLAN-DE-VIDEOTUTORIALES.md): las doce rutas,
  los 77 vídeos, el índice por pregunta y los perfiles. El campo `mas` de cada
  vídeo dice en qué páginas sale --arriba, en el recuadro, y debajo de la
  sección si se nombra una--. Una sección que ya no existe es un aviso, y con
  `--strict`, un despliegue que no sale.
- **Lo que deja el estudio de vídeo** al terminar cada uno
  (`python3 videos/hacer.py A01`): `docs/videos/a1/` con la miniatura, la
  portada, los subtítulos, los capítulos y la transcripción, y el MP4 en
  `docs/videos/media/`. **Un vídeo está publicado cuando tiene las dos
  cosas**; mientras no, la galería lo enseña como «Próximamente», con un
  enlace a lo que ya hay escrito sobre lo mismo.

Los MP4 van en el repositorio, en la versión ligera que prepara el estudio
(unos 4 MB por minuto). Si algún día pesan demasiado para él, se sirven desde
otro sitio cambiando `extra.videos.base` en `mkdocs.yml`, sin tocar nada más.

Todo lo que se pulsa para ver un vídeo --una tarjeta de la galería, el
recuadro de una página, la ventana de la cabecera de la portada-- lo abre
encima de la página (`docs/javascripts/videos.js`), y sin JavaScript lleva a
su página. `…/videos/#video-a1` es el enlace para compartir uno.

## Publicar

Sola: `.github/workflows/site.yml` la construye y la despliega en GitHub Pages
al empujar a `main`, al terminar una publicación y a mano.

Se construye con `--strict`, así que **un enlace roto o una captura que falta
rompen el despliegue** en lugar de publicarse. Una documentación con enlaces
muertos se deja de creer entera.
