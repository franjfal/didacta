"""Los videotutoriales en la web: la galería, la página de cada vídeo y el
recuadro «En vídeo» de las páginas de la documentación.

Es un *hook* de MkDocs, no un plugin: un fichero de este repositorio que
MkDocs ejecuta al construir (`hooks:` en `mkdocs.yml`). No hay nada que
instalar, que es lo que la web se prometió al decir «sin plugins».

De dónde sale cada cosa:

* **`docs/videos/catalogo.yaml`**, escrito a mano a partir del plan: las rutas,
  los 77 vídeos, el índice por pregunta y los perfiles.
* **`docs/videos/<código>/`**, escrito por el estudio de vídeo
  (`videos/hacer.py`) al terminar cada uno: su duración, sus capítulos, su
  transcripción, la miniatura y los subtítulos. Un vídeo **está publicado**
  cuando su carpeta tiene `video.json` y su MP4 se puede servir.
* **`extra.videos.base`**, en `mkdocs.yml`: dónde están los MP4, que es
  `docs/videos/media/` salvo que se diga otra cosa. Si es una ruta de la
  propia web y el fichero no está, el vídeo sale como «Próximamente» en
  lugar de con un reproductor que no carga.

Nada de esto cambia los ficheros de `docs/`: el recuadro «En vídeo» se añade
al construir, a partir del campo `mas` del catálogo. Así una página no hay que
tocarla para que enseñe su vídeo, ni acordarse de quitarlo si el vídeo cambia
de sitio.
"""

from __future__ import annotations

import html
import json
import logging
import posixpath
import re
from pathlib import Path

import yaml
from markdown.extensions.toc import slugify
from mkdocs.structure.files import File
from mkdocs.utils import get_relative_url

log = logging.getLogger("mkdocs.hooks.videos")

# El estado de esta construcción: lo carga `on_config` y lo usan los demás.
catalogo: dict = {}
videos: dict[str, dict] = {}  # código → vídeo, con su ruta y lo publicado
orden: list[str] = []
base_mp4 = ""

PLAY = (
    '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
    '<path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.2-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/></svg>'
)


# --------------------------------------------------------------- cargar ---


def on_config(config):
    global catalogo, videos, orden, base_mp4
    docs = Path(config["docs_dir"])
    catalogo = yaml.safe_load((docs / "videos" / "catalogo.yaml").read_text(encoding="utf-8"))
    ajustes = config["extra"].get("videos", {}) or {}
    base_mp4 = str(ajustes.get("base") or "videos/media/")
    if not base_mp4.endswith("/"):
        base_mp4 += "/"

    videos, orden = {}, []
    for ruta in catalogo["rutas"]:
        for v in ruta["videos"]:
            v = dict(v)
            v["ruta"] = ruta
            v["slug"] = v["codigo"].lower()
            v["url"] = f"videos/{v['slug']}/"
            v["publicado"] = publicado(docs, v)
            videos[v["codigo"]] = v
            orden.append(v["codigo"])

    # El siguiente de cada uno: el de después en el orden del plan, que es
    # el de la primera semana.
    for i, codigo in enumerate(orden):
        videos[codigo]["siguiente"] = orden[i + 1] if i + 1 < len(orden) else None

    # Para las plantillas: la portada pregunta por el A1.
    config["extra"]["didacta_videos"] = {
        c: {"titulo": v["titulo"], "url": v["url"], "duracion": duracion(v["publicado"]["duracion"])}
        for c, v in videos.items()
        if v["publicado"]
    }
    hechos = sum(1 for v in videos.values() if v["publicado"])
    log.info(f"videotutoriales: {hechos} publicados de {len(videos)}")
    return config


def publicado(docs: Path, v: dict) -> dict | None:
    ficha = docs / "videos" / v["slug"] / "video.json"
    if not ficha.exists():
        return None
    datos = json.loads(ficha.read_text(encoding="utf-8"))
    if not es_absoluta(base_mp4) and not (docs / base_mp4 / datos["fichero"]).exists():
        log.info(f"videotutoriales: {v['codigo']} tiene ficha pero no MP4 en {base_mp4}; sale como «Próximamente»")
        return None
    return datos


def es_absoluta(url: str) -> bool:
    return bool(re.match(r"^[a-z]+://", url)) or url.startswith("/")


# ------------------------------------------------------------- ficheros ---


def on_files(files, config):
    # El catálogo es la fuente, no una página ni un fichero que servir.
    for f in list(files):
        if f.src_uri in ("videos/catalogo.yaml",):
            files.remove(f)

    # Una página por vídeo publicado: el reproductor, los capítulos y la
    # transcripción, que es lo que encuentra el buscador.
    for codigo in orden:
        v = videos[codigo]
        if v["publicado"]:
            files.append(File.generated(config, f"videos/{v['slug']}.md", content=pagina_de_video(v, files)))

    # Lo que necesita el reproductor emergente, que se pide al abrirlo.
    datos = {}
    for codigo in orden:
        v = videos[codigo]
        p = v["publicado"]
        if not p:
            continue
        datos[codigo] = {
            "titulo": v["titulo"],
            "ruta": f"{v['ruta']['letra']} · {v['ruta']['titulo']}",
            "pagina": v["url"],
            "mp4": base_mp4 + p["fichero"],
            "portada": f"videos/{v['slug']}/portada.jpg",
            "subtitulos": f"videos/{v['slug']}/es.vtt",
            "capitulos_vtt": f"videos/{v['slug']}/capitulos.vtt",
            "duracion": duracion(p["duracion"]),
            "capitulos": p["capitulos"],
            "siguiente": siguiente_publicado(codigo),
        }
    files.append(File.generated(config, "videos/catalogo.json", content=json.dumps(datos, ensure_ascii=False)))
    return files


def siguiente_publicado(codigo: str) -> dict | None:
    s = videos[codigo]["siguiente"]
    while s and not videos[s]["publicado"]:
        s = videos[s]["siguiente"]
    return {"codigo": s, "titulo": videos[s]["titulo"]} if s else None


# -------------------------------------------------------------- páginas ---


def on_page_markdown(markdown, page, config, files):
    uri = page.file.src_uri
    if uri == "videos/index.md":
        return markdown.replace("<!-- videos:galeria -->", galeria(page, files))
    if page.meta.get("template") == "home.html" or uri.startswith("videos/"):
        return markdown
    return con_recuadros(markdown, page, files)


def con_recuadros(markdown: str, page, files) -> str:
    """El recuadro «En vídeo» debajo del título y, si el catálogo nombra una
    sección, una línea con el vídeo justo debajo de esa sección."""
    uri = page.file.src_uri
    de_la_pagina: list[str] = []
    por_seccion: dict[str, list[str]] = {}
    for codigo in orden:
        v = videos[codigo]
        for m in v.get("mas", []):
            pagina, _, seccion = m["pagina"].partition("#")
            if pagina != uri:
                continue
            if codigo not in de_la_pagina:
                de_la_pagina.append(codigo)
            if seccion:
                por_seccion.setdefault(seccion, []).append(codigo)

    # Las secciones que se nombran tienen que existir, estén publicados o no:
    # un enlace del catálogo a una sección que ya no está es un aviso, que
    # con `--strict` para el despliegue.
    lineas = markdown.split("\n")
    vistas = set()
    en_codigo = False
    salida = []
    titulo_hecho = False
    publicados = [c for c in de_la_pagina if videos[c]["publicado"]]
    for linea in lineas:
        if linea.lstrip().startswith(("```", "~~~")):
            en_codigo = not en_codigo
        salida.append(linea)
        if en_codigo:
            continue
        m = re.match(r"^(#{1,6})\s+(.+?)\s*(\{[^}]*\})?\s*$", linea)
        if not m:
            continue
        if len(m.group(1)) == 1 and not titulo_hecho:
            titulo_hecho = True
            if publicados:
                salida += ["", recuadro(publicados, page), ""]
            continue
        attr = re.search(r"#([\w-]+)", m.group(3) or "")
        ident = attr.group(1) if attr else slugify(re.sub(r"[`*_]", "", m.group(2)), "-")
        vistas.add(ident)
        aqui = [c for c in por_seccion.get(ident, []) if videos[c]["publicado"]]
        if aqui:
            salida += ["", en_linea(aqui, page), ""]
    for seccion, codigos in por_seccion.items():
        if seccion not in vistas:
            log.warning(f"videotutoriales: {', '.join(codigos)} apunta a «{uri}#{seccion}», y esa sección no existe")
    if publicados and not titulo_hecho:
        salida = [recuadro(publicados, page), ""] + salida
    return "\n".join(salida)


def recuadro(codigos: list[str], page) -> str:
    items = "".join(tarjeta_mini(videos[c], page) for c in codigos)
    return (
        '<div class="dv-box" role="region" aria-label="En vídeo">'
        f'<div class="dv-box__label">{PLAY}En vídeo</div>'
        f'<div class="dv-box__list">{items}</div></div>'
    )


def tarjeta_mini(v: dict, page) -> str:
    p = v["publicado"]
    return (
        f'<a class="dv-mini" href="{rel(v["url"], page)}" data-video="{v["codigo"]}">'
        f'<span class="dv-mini__thumb"><img src="{rel(miniatura(v), page)}" alt="" loading="lazy" width="640" height="360">'
        f'<span class="dv-play">{PLAY}</span></span>'
        f'<span class="dv-mini__body"><span class="dv-code">{v["codigo"]}</span>'
        f'<strong>{e(v["titulo"])}</strong><small>{duracion(p["duracion"])}</small></span></a>'
    )


def en_linea(codigos: list[str], page) -> str:
    partes = []
    for c in codigos:
        v = videos[c]
        partes.append(
            f'<a href="{rel(v["url"], page)}" data-video="{c}">{PLAY}'
            f'<span>En vídeo: <strong>{e(v["titulo"])}</strong> · {duracion(v["publicado"]["duracion"])}</span></a>'
        )
    return f'<p class="dv-inline">{"".join(partes)}</p>'


# -------------------------------------------------------------- galería ---


def galeria(page, files) -> str:
    rutas = catalogo["rutas"]
    total_min = sum(v["minutos"] for v in videos.values())
    hechos = [c for c in orden if videos[c]["publicado"]]
    partes: list[str] = []

    partes.append(
        '<div class="dv-doors">'
        + puerta("#empieza-aqui", "rocket", "Empieza aquí", "La ruta del primer día: de instalar Didacta a tu primer PDF.")
        + puerta("#por-pregunta", "question", "Busca por pregunta", "«Quiero hacer un examen», «sale un aviso raro»…")
        + puerta("#segun-lo-que-hagas", "person", "Según lo que hagas", "Das clase, traduces, escribes o coordinas.")
        + "</div>"
    )
    partes.append(
        f'<p class="dv-count">{len(videos)} vídeos en {len(rutas)} rutas, de uno a tres minutos: '
        f"unas {numero(round(total_min / 60 * 2) / 2)} horas en total, aunque nadie los ve todos. "
        f"{'Ya hay ' + str(len(hechos)) + (' publicado' if len(hechos) == 1 else ' publicados') + '; ' if hechos else ''}"
        "los demás van saliendo en este orden.</p>"
    )

    # Empieza aquí: la ruta A, como un camino numerado.
    a = rutas[0]
    minutos_a = sum(v["minutos"] for v in a["videos"])
    partes.append("\n## Empieza aquí {#empieza-aqui}\n")
    partes.append(
        f'<p class="dv-lead"><strong>{e(a["letra"])} · {e(a["titulo"])}</strong> · '
        f"{len(a['videos'])} vídeos · unos {redondo(minutos_a)} minutos. {e(a.get('intro', ''))}</p>"
    )
    partes.append('<ol class="dv-grid dv-grid--path">' + "".join(f"<li>{tarjeta(videos[v['codigo']], page, files)}</li>" for v in a["videos"]) + "</ol>")

    # Por pregunta: el índice de § 6, en pestañas.
    partes.append("\n## Por pregunta {#por-pregunta}\n")
    partes.append('<p class="dv-lead">Cada pregunta, con las palabras de quien la hace.</p>\n')
    for g in catalogo["preguntas"]:
        partes.append(f'=== "{g["grupo"]}"\n')
        partes.append("    | Quiero… | Vídeo |")
        partes.append("    |---|---|")
        for pregunta, codigos in g["filas"]:
            partes.append(f"    | {e(pregunta)} | {' '.join(chip(c, page, files) for c in expandir(codigos))} |")
        partes.append("")

    # Según lo que hagas: § 3.
    partes.append("\n## Según lo que hagas {#segun-lo-que-hagas}\n")
    filas = []
    for p in catalogo["perfiles"]:
        filas.append(
            f'<div class="dv-profile"><strong>{e(p["quien"])}</strong>'
            f'<span class="dv-profile__mira">{mira(p["mira"], page, files)}</span>'
            f'<small>{e(p["tiempo"])}</small></div>'
        )
    partes.append('<div class="dv-profiles">' + "".join(filas) + "</div>")
    partes.append(
        '<p class="dv-lead dv-lead--small">La ruta <a href="#ruta-a">A</a> es de todos, y la '
        '<a href="#ruta-k">K</a>, la de los ajustes, se consulta cuando hace falta.</p>'
    )

    # Todas las rutas: el mapa y, debajo, cada una con sus vídeos.
    partes.append("\n## Todas las rutas {#todas-las-rutas}\n")
    mapa = []
    for r in rutas:
        n = len(r["videos"])
        minutos = sum(v["minutos"] for v in r["videos"])
        hechos_r = sum(1 for v in r["videos"] if videos[v["codigo"]]["publicado"])
        estado = f"{hechos_r} de {n}" if hechos_r else f"{n} vídeos"
        mapa.append(
            f'<a class="dv-route" href="#ruta-{r["letra"].lower()}"><span class="dv-route__letter">{r["letra"]}</span>'
            f'<span class="dv-route__body"><strong>{e(r["titulo"])}</strong><span>{e(r["contesta"])}</span>'
            f"<small>{estado} · unos {redondo(minutos)} min</small></span></a>"
        )
    partes.append('<div class="dv-routes">' + "".join(mapa) + "</div>")
    for r in rutas:
        minutos = sum(v["minutos"] for v in r["videos"])
        partes.append(f'\n### {r["letra"]} · {r["titulo"]} {{#ruta-{r["letra"].lower()}}}\n')
        lead = f"<em>{e(r['contesta'])}</em> · {len(r['videos'])} vídeos · unos {redondo(minutos)} minutos."
        if r.get("intro"):
            lead += f" {e(r['intro'])}"
        partes.append(f'<p class="dv-lead">{lead}</p>')
        partes.append('<div class="dv-grid">' + "".join(tarjeta(videos[v["codigo"]], page, files) for v in r["videos"]) + "</div>")

    return "\n".join(partes) + "\n"


def puerta(href: str, icono: str, titulo: str, texto: str) -> str:
    iconos = {
        "rocket": '<path d="M13 3c3.5 0 6.5 1 7.5 2-1 1-2 4-2 7.5L15 16H8l3.5-3.5C11.5 9 12 5 13 3zM8 16l-3 5 5-3M14.5 7.5a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0"/>',
        "question": '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6V14M12 17.2v.3"/>',
        "person": '<circle cx="12" cy="8" r="3.5"/><path d="M5 20c.8-3.6 3.6-5.5 7-5.5s6.2 1.9 7 5.5"/>',
    }
    return (
        f'<a class="dv-door" href="{href}"><svg viewBox="0 0 24 24" aria-hidden="true">{iconos[icono]}</svg>'
        f"<strong>{e(titulo)}</strong><span>{e(texto)}</span></a>"
    )


def tarjeta(v: dict, page, files) -> str:
    """Una tarjeta de la galería. Publicado: se reproduce al pulsarla (y sin
    JavaScript lleva a su página). Por hacer: dice qué enseñará y enlaza lo
    que ya hay escrito sobre lo mismo."""
    p = v["publicado"]
    marca = f'<span class="dv-tag dv-tag--{v["marca"].lower()}">{e(v["marca"])}</span>' if v.get("marca") else ""
    nota = f'<span class="dv-tag">{e(v["nota"])}</span>' if v.get("nota") and v["nota"] != "Opcional" else ""
    etiquetas = f'<span class="dv-card__tags">{marca}{nota}</span>' if (marca or nota) else ""
    sabras = f'<span class="dv-card__text">Sabrás {e(v["sabras"])}</span>' if v.get("sabras") else ""
    if p:
        return (
            f'<a class="dv-card" href="{rel(v["url"], page)}" data-video="{v["codigo"]}" '
            f'aria-label="Ver el vídeo {v["codigo"]}: {e(v["titulo"])} ({duracion(p["duracion"])})">'
            f'<span class="dv-card__thumb"><img src="{rel(miniatura(v), page)}" alt="" loading="lazy" width="640" height="360">'
            f'<span class="dv-code">{v["codigo"]}</span><span class="dv-time">{duracion(p["duracion"])}</span>'
            f'<span class="dv-play">{PLAY}</span></span>'
            f'<span class="dv-card__body"><span class="dv-card__title">{e(v["titulo"])}</span>{sabras}{etiquetas}</span></a>'
        )
    leer = ""
    if v.get("mas"):
        m = v["mas"][0]
        destino = url_de_pagina(m["pagina"], files)
        if destino:
            leer = f'<a class="dv-card__read" href="{rel(destino, page)}">Mientras tanto, léelo: {e(m["titulo"][:1].upper() + m["titulo"][1:])} →</a>'
    return (
        f'<div class="dv-card dv-card--pronto" id="video-{v["slug"]}">'
        f'<span class="dv-card__thumb"><span class="dv-card__big">{v["codigo"]}</span>'
        f'<span class="dv-card__soon">Próximamente</span><span class="dv-time">~{minutos(v["minutos"])}</span></span>'
        f'<span class="dv-card__body"><span class="dv-card__title">{e(v["titulo"])}</span>{sabras}{etiquetas}{leer}</span></div>'
    )


def chip(codigo: str, page, files) -> str:
    v = videos.get(codigo)
    if not v:
        log.warning(f"videotutoriales: el índice por pregunta nombra «{codigo}», que no está en el catálogo")
        return e(codigo)
    if v["publicado"]:
        return (
            f'<a class="dv-chip" href="{rel(v["url"], page)}" data-video="{codigo}" title="{e(v["titulo"])}">'
            f'{PLAY}{codigo}</a>'
        )
    return f'<a class="dv-chip dv-chip--pronto" href="#ruta-{codigo[0].lower()}" title="{e(v["titulo"])} · próximamente">{codigo}</a>'


def expandir(codigos: list[str]) -> list[str]:
    """«D4–D12» son nueve vídeos."""
    salida = []
    for c in codigos:
        m = re.match(r"^([A-L])(\d+)–\1?(\d+)$", c)
        if m:
            salida += [f"{m.group(1)}{n}" for n in range(int(m.group(2)), int(m.group(3)) + 1)]
        else:
            salida.append(c)
    return salida


def mira(texto: str, page, files) -> str:
    """«A · C1 · C2 · F1–F4»: una ruta entera va al mapa; un vídeo, a su chip."""
    trozos = []
    for t in [x.strip() for x in texto.split("·")]:
        if re.fullmatch(r"[A-L]", t):
            trozos.append(f'<a class="dv-chip dv-chip--ruta" href="#ruta-{t.lower()}">{t}</a>')
        elif t.lower().startswith("todo"):
            # «Todo, y la ruta L»
            trozos.append('<a class="dv-chip dv-chip--ruta" href="#todas-las-rutas">Todas las rutas</a>')
            final = re.search(r"ruta ([A-L])$", t)
            if final:
                trozos.append(f'<a class="dv-chip dv-chip--ruta" href="#ruta-{final.group(1).lower()}">y la {final.group(1)}</a>')
        else:
            trozos += [chip(c, page, files) for c in expandir([t])]
    return " ".join(trozos)


# ---------------------------------------------------- página de un vídeo ---


def pagina_de_video(v: dict, files) -> str:
    p = v["publicado"]
    here = v["url"]
    mp4 = base_mp4 + p["fichero"]
    mp4 = mp4 if es_absoluta(mp4) else get_relative_url(mp4, here)
    r = v["ruta"]
    lineas = [
        "---",
        f"title: {json.dumps(v['codigo'] + ' · ' + v['titulo'], ensure_ascii=False)}",
        f"description: {json.dumps('Vídeo de Didacta. Sabrás ' + v.get('sabras', ''), ensure_ascii=False)}",
        "---",
        "",
        f"# {v['codigo']} · {v['titulo']}",
        "",
        f'<p class="dv-page__meta"><a href="{get_relative_url("videos/", here)}#ruta-{r["letra"].lower()}">'
        f"{r['letra']} · {e(r['titulo'])}</a> · {duracion(p['duracion'])} · con Didacta {e(p.get('version', ''))}</p>",
        "",
        f'<div class="dv-player"><video controls playsinline preload="metadata" poster="portada.jpg">'
        f'<source src="{e(mp4)}" type="video/mp4">'
        '<track kind="subtitles" srclang="es" label="Castellano" src="es.vtt">'
        '<track kind="chapters" srclang="es" label="Capítulos" src="capitulos.vtt">'
        f'<a href="{e(mp4)}">Descargar el vídeo</a></video></div>',
        "",
    ]
    if v.get("sabras"):
        lineas += [f"**Sabrás** {v['sabras']}", ""]
    if v.get("idea"):
        idea = v["idea"][:1].upper() + v["idea"][1:]
        lineas += ['!!! tip "La idea"', "", f"    {idea}", ""]

    lineas += ["## Capítulos", "", '<ol class="dv-chapters">']
    for c in p["capitulos"]:
        lineas.append(f'<li><a href="#t={c["t"]:g}" data-t="{c["t"]}"><span>{duracion(c["t"])}</span>{e(c["titulo"])}</a></li>')
    lineas += ["</ol>", "", "## Transcripción", ""]
    cortes = [c["t"] for c in p["capitulos"]]
    parrafo: list[str] = []
    capitulo_actual = None
    for f in p["transcripcion"]:
        cap = max((c for c in p["capitulos"] if c["t"] <= f["t"] + 0.01), key=lambda c: c["t"], default=None)
        if cap is not capitulo_actual and cortes:
            if parrafo:
                lineas += [" ".join(parrafo), ""]
                parrafo = []
            capitulo_actual = cap
            if cap and cap["t"] > 0:
                lineas += [f'**{e(cap["titulo"])}** <small><a class="dv-t" href="#t={cap["t"]:g}">{duracion(cap["t"])}</a></small>', ""]
        parrafo.append(e(f["texto"]))
    if parrafo:
        lineas += [" ".join(parrafo), ""]

    # Los enlaces de markdown van al fichero, relativos a `videos/`: MkDocs
    # los comprueba y los convierte en la dirección de cada página.
    lineas += ["## Para seguir", ""]
    sig = siguiente_publicado(v["codigo"])
    if v.get("siguiente"):
        s = videos[v["siguiente"]]
        estado = "" if s["publicado"] else " *(próximamente)*"
        destino = f"{s['slug']}.md" if s["publicado"] else f"index.md#ruta-{s['codigo'][0].lower()}"
        lineas.append(f"- **El siguiente:** [{s['codigo']} · {s['titulo']}]({destino}){estado}")
    if sig and sig["codigo"] != v.get("siguiente"):
        lineas.append(f"- **El siguiente ya publicado:** [{sig['codigo']} · {sig['titulo']}]({videos[sig['codigo']]['slug']}.md)")
    for m in v.get("mas", []):
        pagina, _, seccion = m["pagina"].partition("#")
        if pagina != "index.md" and url_de_pagina(pagina, files):
            destino = posixpath.relpath(pagina, "videos") + ("#" + seccion if seccion else "")
            lineas.append(f"- **En la documentación:** [{m['titulo'][:1].upper() + m['titulo'][1:]}]({destino})")
    lineas.append("- **Todos los vídeos:** [la galería](index.md)")
    lineas += ["", f"<small>Grabado el {fecha(p.get('fecha', ''))} con Didacta {e(p.get('version', ''))}. Subtítulos en castellano.</small>", ""]
    return "\n".join(lineas)


# ------------------------------------------------------------ utilidades ---


def url_de_pagina(pagina: str, files) -> str | None:
    f = files.get_file_from_path(pagina.partition("#")[0])
    if f is None:
        log.warning(f"videotutoriales: el catálogo enlaza «{pagina}», que no es ninguna página")
        return None
    return f.url


def miniatura(v: dict) -> str:
    return f"videos/{v['slug']}/miniatura.jpg"


def rel(url: str, page) -> str:
    return get_relative_url(url, page.url)


def duracion(segundos: float) -> str:
    s = int(round(segundos))
    return f"{s // 60}:{s % 60:02d}"


def redondo(x: float) -> int:
    """Al entero más cercano, y los medios hacia arriba: 14,5 minutos son
    «unos 15», como en el plan (`round` de Python daría 14)."""
    return int(x + 0.5)


def numero(x: float) -> str:
    return f"{x:g}".replace(".", ",")


def minutos(m: float) -> str:
    return numero(m) + " min"


def fecha(iso: str) -> str:
    meses = "enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre".split()
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", iso)
    return f"{int(m.group(3))} de {meses[int(m.group(2)) - 1]} de {m.group(1)}" if m else iso


def e(texto: str) -> str:
    return html.escape(str(texto), quote=True)
