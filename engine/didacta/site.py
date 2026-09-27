"""Una web del curso: los PDF de una asignatura en una página que se publica.

`didacta site curso@año` exporta lo que se reparte --con la misma regla que
`export`: lo del estudiante, salvo que se pida más-- y escribe al lado un
`index.html` que lo enseña por idioma y por tema, con cada versión de cada
documento enlazada. Es una página sola, sin nada que descargar aparte: se
sube tal cual a GitHub Pages, a un servidor de la universidad o a una carpeta
compartida.
"""

from __future__ import annotations

import html
import os
from datetime import date
from urllib.parse import quote

#: Cómo se llama cada idioma en su propio idioma, para las pestañas.
LANGUAGE_NAMES = {
    "es": "Castellano", "va": "Valencià", "ca": "Català", "en": "English",
    "gl": "Galego", "eu": "Euskara", "fr": "Français", "it": "Italiano",
    "pt": "Português", "de": "Deutsch",
}

#: Lo poco que se dice en la página, en su idioma.
WORDS = {
    "es": {"updated": "Actualizado el", "made": "Hecho con Didacta",
           "empty": "Todavía no hay nada publicado."},
    "va": {"updated": "Actualitzat el", "made": "Fet amb Didacta",
           "empty": "Encara no hi ha res publicat."},
    "ca": {"updated": "Actualitzat el", "made": "Fet amb Didacta",
           "empty": "Encara no hi ha res publicat."},
    "en": {"updated": "Updated on", "made": "Made with Didacta",
           "empty": "Nothing published yet."},
}

_STYLE = """
:root { color-scheme: light dark; --bg: #f6f6f3; --card: #ffffff;
  --ink: #1d2320; --muted: #5d665f; --rule: #dfe3dc; --accent: #2f6b3a;
  --accent-ink: #ffffff; }
@media (prefers-color-scheme: dark) { :root { --bg: #121614; --card: #1b201d;
  --ink: #e6ebe6; --muted: #9aa59c; --rule: #2c332e; --accent: #8fd19a;
  --accent-ink: #10331a; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink);
  font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
  sans-serif; }
main { max-width: 860px; margin: 0 auto; padding: 32px 16px 48px; }
header h1 { font-size: 1.7rem; margin: 0 0 4px; letter-spacing: -0.01em; }
header p { margin: 0; color: var(--muted); }
nav { display: flex; gap: 8px; margin: 24px 0 8px; flex-wrap: wrap; }
nav a { padding: 6px 14px; border-radius: 999px; border: 1px solid var(--rule);
  color: var(--ink); text-decoration: none; font-size: 0.95rem; }
nav a:hover, nav a:focus { border-color: var(--accent); }
section.language { margin-top: 16px; }
h2 { font-size: 1.05rem; margin: 28px 0 10px; }
ul.documents { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
ul.documents > li { background: var(--card); border: 1px solid var(--rule);
  border-radius: 10px; padding: 12px 14px; display: flex; flex-wrap: wrap;
  align-items: center; gap: 8px 12px; }
.title { font-weight: 600; flex: 1 1 260px; }
.versions { display: flex; flex-wrap: wrap; gap: 6px; }
.versions a { background: var(--accent); color: var(--accent-ink);
  text-decoration: none; padding: 5px 12px; border-radius: 6px;
  font-size: 0.9rem; font-weight: 600; }
.versions a:hover, .versions a:focus { filter: brightness(1.08); }
footer { margin-top: 40px; color: var(--muted); font-size: 0.85rem; }
""".strip()


def _href(path):
    return "/".join(quote(part) for part in path.split("/"))


def page(course_title, year, languages, groups, subtitle="", today=None):
    """El `index.html`.

    [groups] es, por idioma, la lista de `(tema, [(documento, [(versión,
    ruta)])])` en el orden en que se enseña. [languages] fija el orden de
    las pestañas.
    """
    first = languages[0] if languages else "es"
    words = WORDS.get(first, WORDS["es"])
    when = (today or date.today()).strftime("%d/%m/%Y")
    out = [
        "<!doctype html>",
        '<html lang="%s">' % html.escape(first),
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        "<title>%s · %s</title>" % (html.escape(course_title), html.escape(year)),
        "<style>%s</style>" % _STYLE,
        "</head>",
        "<body>",
        "<main>",
        "<header>",
        "<h1>%s</h1>" % html.escape(course_title),
        "<p>%s</p>" % html.escape(" · ".join(p for p in (year, subtitle) if p)),
        "</header>",
    ]
    shown = [code for code in languages if groups.get(code)]
    if len(shown) > 1:
        out.append('<nav aria-label="Idiomas">')
        for code in shown:
            out.append('<a href="#%s" lang="%s">%s</a>' % (
                code, code, html.escape(LANGUAGE_NAMES.get(code, code))))
        out.append("</nav>")
    if not shown:
        out.append("<p>%s</p>" % html.escape(words["empty"]))
    for code in shown:
        out.append('<section class="language" id="%s" lang="%s">' % (code, code))
        if len(shown) > 1:
            out.append('<h2 class="language-name">%s</h2>'
                       % html.escape(LANGUAGE_NAMES.get(code, code)))
        for theme, documents in groups[code]:
            if theme:
                out.append("<h2>%s</h2>" % html.escape(theme))
            out.append('<ul class="documents">')
            for title, versions in documents:
                out.append("<li>")
                out.append('<span class="title">%s</span>' % html.escape(title))
                out.append('<span class="versions">')
                for label, path in versions:
                    out.append('<a href="%s">%s</a>' % (
                        html.escape(_href(path)), html.escape(label)))
                out.append("</span>")
                out.append("</li>")
            out.append("</ul>")
        out.append("</section>")
    out += [
        "<footer>%s %s · %s</footer>" % (
            html.escape(words["updated"]), when, html.escape(words["made"])),
        "</main>",
        "</body>",
        "</html>",
        "",
    ]
    return "\n".join(out)


def group_outputs(outputs, documents, languages, label_of, loose=()):
    """De lo exportado a lo que enseña la página.

    [outputs] es lo que devuelve `export --json`: cada PDF con su ruta, su
    documento, su versión y su idioma. El tema es la carpeta en la que lo
    dejó `export`, que ya lleva su nombre; la de lo que no es de ningún
    tema --[loose]-- va sin título, que «Sin tema» en una web no dice nada.
    Los documentos, en el orden del curso; las versiones, en el orden en que
    se exportaron.
    """
    order = {document.id: index for index, document in enumerate(documents)}
    by_id = {document.id: document for document in documents}
    groups = {}
    for code in languages:
        themes = {}
        for output in outputs:
            if output["language"] != code:
                continue
            document = by_id.get(output["document"])
            if document is None:
                continue
            parts = output["path"].split("/")
            if len(languages) > 1 and parts and parts[0] == code:
                parts = parts[1:]
            theme = parts[0] if len(parts) > 1 else ""
            if theme in loose:
                theme = ""
            entries = themes.setdefault(theme, {})
            versions = entries.setdefault(document.id, [])
            versions.append((label_of(output["profile"], code), output["path"]))
        ordered = []
        for theme, entries in themes.items():
            documents_in = sorted(entries, key=lambda d: order.get(d, 0))
            ordered.append((theme, [
                (by_id[d].title(code), entries[d]) for d in documents_in
            ]))
        ordered.sort(key=lambda item: min(
            order.get(d, 0) for d in (i for i in themes[item[0]])))
        groups[code] = ordered
    return groups


def write(destination, text):
    path = os.path.join(destination, "index.html")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return path
