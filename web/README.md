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

## Publicar

Sola: `.github/workflows/site.yml` la construye y la despliega en GitHub Pages
al empujar a `main`, al terminar una publicación y a mano.

Se construye con `--strict`, así que **un enlace roto o una captura que falta
rompen el despliegue** en lugar de publicarse. Una documentación con enlaces
muertos se deja de creer entera.
