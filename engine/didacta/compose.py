"""La composición de un documento, escrita en su `.tex`.

`year.yaml` es la autoridad: lleva el orden y los apartados en los tres
idiomas (D29). El `.tex` de al lado es lo que lee `pdflatex`, y hasta aquí
nadie escribía el segundo a partir del primero: sólo la migración, una vez.
Así que un apartado añadido desde la aplicación se guardaba en `year.yaml`,
se veía en la pantalla de composición, y no salía en el PDF -- que es un
fallo silencioso, del peor tipo, porque lo que se mira para comprobarlo es
justamente la pantalla que sí lo enseña.

Esto lo escribe. Y lo escribe **sobre el cuerpo y nada más**: el preámbulo,
la portada y cualquier otra cosa que alguien haya puesto en el fichero se
quedan como están. Si en medio de la composición hay LaTeX que la
composición no sabe decir --un `\\clearpage`, un apartado envuelto en un
`\\onlyslides` de los que dejó la migración-- no se toca el fichero y se
dice por qué. Un `.tex` que alguien editó a mano no se sacrifica para que el
motor tenga razón.

**Lo desactivado se conserva desactivado.** Novecientas entradas del
repositorio están comentadas, y cada una registra material que existe y que
este año no se da (D22). En el `year.yaml` son `# - unit: ...` y en el
`.tex` son `%% \\DidactaUnit{...}`; regenerar el cuerpo leyendo sólo lo que
YAML entiende las borraría todas de los masters en la primera compilación.
Por eso aquí el `structure:` se lee por líneas y no con el cargador de YAML.
"""

from __future__ import annotations

import os
import re

from . import profiles
from . import yamlio

#: Las cuatro cosas que puede haber en una composición.
KINDS = ("section", "subsection", "unit", "problem")

#: Una entrada, activa o comentada: `- unit: x`, `# - section:`.
_ENTRY = re.compile(
    r"^(?P<off>#\s*)?-\s+(?P<kind>section|subsection|unit|problem)\s*:"
    r"(?P<value>.*)$"
)

#: Una línea de un título por idiomas: `es: Logaritmos`.
_TITLE = re.compile(r"^(?P<off>#\s*)?(?P<code>[a-z]{2})\s*:(?P<value>.*)$")

#: Un `- id: practica-1` dentro de `documents:`.
_ID = re.compile(r"^-\s+id\s*:\s*(?P<value>.*)$")

#: Lo que este módulo sabe escribir en el cuerpo de un master, para
#: reconocer lo que escribió la vez anterior.
#:
#: `\\section` y `\\subsection` a secas siguen aquí aunque ya no se escriban:
#: son lo que dejó la migración y lo que escribían las versiones anteriores,
#: y sin reconocerlos el cuerpo que tienen los masters de hoy contaría como
#: «LaTeX que la composición no sabe decir» y no se podría poner al día.
_COMPOSED = re.compile(
    r"^\s*(?:%+\s*)?\\(?:section|subsection)\{|"
    r"^\s*(?:%+\s*)?\\Didacta(?:Section|Subsection|Unit|Problem)\{"
)

_BEGIN = re.compile(r"^\s*\\begin\{document\}")
_END = re.compile(r"^\s*\\end\{document\}")


class ComposeError(ValueError):
    pass


class Entry:
    """Una entrada de la composición, como está escrita en el fichero."""

    __slots__ = ("kind", "value", "titles", "enabled")

    def __init__(self, kind, value="", titles=None, enabled=True):
        self.kind = kind
        self.value = value
        self.titles = titles or {}
        self.enabled = enabled

    @property
    def is_heading(self):
        return self.kind in ("section", "subsection")

    def title(self, language):
        """El título en [language], o el que haya.

        Un apartado con título sólo en castellano tiene nombre igualmente, y
        el master en valenciano prefiere ese a un hueco: el PDF con un
        `\\section{}` vacío es peor que el PDF con un encabezado sin traducir,
        y la pantalla de traducción ya dice cuáles faltan.
        """
        if self.value:
            return self.value
        wanted = self.titles.get(language)
        if wanted:
            return wanted
        for code in sorted(self.titles):
            if self.titles[code]:
                return self.titles[code]
        return ""

    def __repr__(self):  # pragma: no cover - para leer un fallo de test
        return "Entry(%s, %r, enabled=%s)" % (self.kind, self.value, self.enabled)


# --------------------------------------------------------------------------
# Leer el `structure:` de un `year.yaml`
# --------------------------------------------------------------------------


def _unquote(text):
    """El valor de un escalar, con las mismas reglas que el resto del motor.

    Por `yamlio` y no quitando las comillas a mano: un título entre comillas
    dobles lleva los escapes de YAML, y `"Densidad de $\\\\mathbb Q$"` escrito
    a pelo en el `.tex` sale como `$\\\\mathbb Q$` -- dos barras, que LaTeX lee
    como un salto de línea y no como una letra.
    """
    value = yamlio._parse_scalar(text.strip())
    return "" if value is None else str(value)


def _strip_comment(text):
    """Quita un comentario de final de línea, respetando las comillas."""
    quote = ""
    for index, char in enumerate(text):
        if quote:
            if char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == "#" and (index == 0 or text[index - 1] in " \t"):
            return text[:index]
    return text


def _indent_of(line):
    return len(line) - len(line.lstrip(" "))


def _uncomment(line):
    """La línea sin su `# ` de desactivada, si lo lleva."""
    stripped = line.lstrip()
    if stripped.startswith("#"):
        return stripped[1:].lstrip()
    return stripped


def entries(text, document_id):
    """Las entradas de la composición de [document_id], en orden.

    Lee el texto del `year.yaml` por líneas en lugar de cargarlo: lo
    comentado no existe para un cargador de YAML, y aquí es la mitad de lo
    que hay que escribir.

    Devuelve `None` cuando el fichero no declara ese documento, que es
    distinto de que lo declare sin composición (lista vacía).
    """
    lines = text.split("\n")
    start = None
    for index, line in enumerate(lines):
        if re.match(r"^documents\s*:", line):
            start = index + 1
            break
    if start is None:
        return None

    found = None
    for index in range(start, len(lines)):
        line = lines[index]
        if line.strip() and _indent_of(line) == 0:
            break  # otra clave de primer nivel: `documents:` se acabó
        match = _ID.match(line.strip())
        if match and _unquote(_strip_comment(match.group("value"))) == document_id:
            found = index
            break
    if found is None:
        return None

    item_indent = _indent_of(lines[found])
    structure = None
    for index in range(found + 1, len(lines)):
        line = lines[index]
        if not line.strip():
            continue
        indent = _indent_of(line)
        if indent <= item_indent and not line.strip().startswith("#"):
            if _ID.match(line.strip()) or indent < item_indent:
                break
        if re.match(r"^structure\s*:", line.strip()) and indent > item_indent:
            structure = index
            break
    if structure is None:
        return []
    return _collect(lines, structure)


def shared_entries(text):
    """Las entradas de la composición de un documento compartido.

    El mismo lector, sobre un fichero donde `structure:` está en el primer
    nivel porque el documento es lo único que hay. Que sean el mismo lector no
    es ahorro: es lo que garantiza que un tema vinculado y uno que no lo está
    se compongan igual, incluidas las novecientas entradas comentadas.
    """
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if _indent_of(line) == 0 and re.match(r"^structure\s*:", line.strip()):
            return _collect(lines, index)
    return []


def _collect(lines, structure):
    """Las entradas que cuelgan de la línea `structure:` número [structure]."""
    body_indent = _indent_of(lines[structure])
    collected = []
    index = structure + 1
    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        if _indent_of(line) <= body_indent:
            break
        match = _ENTRY.match(line.strip())
        if match is None:
            index += 1  # un comentario suelto: la explicación de alguien
            continue

        enabled = match.group("off") is None
        value = _unquote(_strip_comment(match.group("value")))
        entry = Entry(match.group("kind"), value=value, enabled=enabled)

        if not value and entry.is_heading:
            # Un título por idiomas: las líneas de dentro, hasta que la
            # sangría vuelva.
            inner = index + 1
            entry_indent = _indent_of(line)
            while inner < len(lines):
                candidate = lines[inner]
                if not candidate.strip():
                    break
                if _indent_of(candidate) <= entry_indent:
                    break
                title = _TITLE.match(_uncomment(candidate))
                if title is not None:
                    entry.titles[title.group("code")] = _unquote(
                        _strip_comment(title.group("value"))
                    )
                inner += 1
            index = inner
        else:
            index += 1
        collected.append(entry)
    return collected


def read_entries(year_path, document_id):
    """[entries] sobre el fichero, o `None` si no está."""
    if not os.path.isfile(year_path):
        return None
    with open(year_path, encoding="utf-8") as handle:
        return entries(handle.read(), document_id)


def read_shared_entries(path):
    """[shared_entries] sobre el fichero, o `None` si no está."""
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return shared_entries(handle.read())


# --------------------------------------------------------------------------
# Escribirlas en el master
# --------------------------------------------------------------------------


#: El orden en que salen los idiomas de un encabezado. El del registro, para
#: que dos compilaciones del mismo `year.yaml` den el mismo fichero: un orden
#: que dependa del diccionario convierte cualquier compilación en un cambio
#: que revisar.
def _language_order(codes):
    known = [code for code in profiles.LANGUAGES if code in codes]
    return known + sorted(code for code in codes if code not in profiles.LANGUAGES)


def _heading(entry, language):
    """Un apartado o subapartado, en todos los idiomas que tenga.

    `\\DidactaSection` y `\\DidactaSubsection` llevan un título por idioma y
    eligen al compilar, que es la única forma de que el mismo master dé el
    PDF castellano con encabezados castellanos y el valenciano con
    encabezados valencianos. Escribir `\\section{...}` aquí ataba el
    encabezado al idioma del documento, y la compilación en otro idioma
    salía con el contenido traducido y los apartados sin traducir.

    Un apartado escrito como escalar --`- section: Logaritmos`, sin idiomas--
    no tiene nada que elegir, así que se queda con la orden de LaTeX de
    siempre: envolverlo en claves diría que hay una traducción donde no la hay.

    En una sola línea a propósito: el cuerpo se lee y se reescribe por líneas,
    y una orden partida en tres dejaría dos que no reconoce y con las que se
    negaría a tocar el fichero.
    """
    macro = "DidactaSection" if entry.kind == "section" else "DidactaSubsection"
    titles = {code: text for code, text in entry.titles.items() if text}
    if not titles:
        return "\\%s{%s}" % (entry.kind, entry.title(language))
    keys = ", ".join(
        "%s={%s}" % (code, titles[code]) for code in _language_order(titles)
    )
    return "\\%s{%s}" % (macro, keys)


def render(collected, language):
    """El cuerpo del master: las líneas de la composición y nada más.

    Un apartado abre con una línea en blanco delante y un subapartado no,
    que es como quedó el material migrado: la separación marca dónde empieza
    un bloque, y puesta también en los subapartados deja de marcar nada.

    `language` ya sólo decide el título de un encabezado escrito sin idiomas:
    los demás salen con todos, y quien elige es LaTeX. Así el master es el
    mismo para las tres compilaciones y `didacta check` no tiene que preguntar
    «¿al día en qué idioma?».
    """
    out = []
    for entry in collected:
        if entry.is_heading:
            body = _heading(entry, language)
            if out and entry.kind == "section":
                out.append("")
        elif entry.kind == "unit":
            body = "\\DidactaUnit{%s}" % entry.value
        else:
            body = "\\DidactaProblem{%s}" % entry.value
        out.append(body if entry.enabled else "%% " + body)
    return out


def _composed_at(lines, index):
    """Cuántas líneas ocupa la entrada que empieza en [index], o 0 si no hay.

    Una orden de la composición puede estar escrita en varias líneas: el
    ejemplo de `didacta.sty` reparte los tres idiomas de un apartado en tres,
    que es como se lee bien a mano. Contando una sola, las otras dos eran
    «LaTeX que la composición no sabe decir», el fichero no se podía poner al
    día, y el apartado acababa escrito dos veces --una por cada formato-- que
    es lo que le pasó al curso de ejemplo.

    Se cuentan llaves porque es lo que delimita la orden. Un comentario de
    final de línea no cuenta, y una entrada desactivada --`%% \\DidactaUnit`--
    ocupa la suya y nada más, que es como las escribe [render].
    """
    if not _COMPOSED.match(lines[index]):
        return 0
    depth = 0
    for count, line in enumerate(lines[index:], start=1):
        text = _strip_comment(line)
        depth += text.count("{") - text.count("}")
        if depth <= 0:
            return count
    # Llaves sin cerrar hasta el final: se queda con la suya y el que llama
    # dirá que hay algo que no sabe reescribir.
    return 1


def _spans(lines, begin, end):
    """Las líneas de [begin, end) que son composición, por índice."""
    covered = set()
    index = begin
    while index < end:
        span = _composed_at(lines, index)
        if span:
            covered.update(range(index, min(index + span, end)))
            index += span
        else:
            index += 1
    return covered


def _region(lines):
    """Dónde está la composición dentro del fichero.

    Devuelve `(inicio, fin)` como un rango medio abierto sobre [lines], o
    `None` cuando el fichero no tiene `\\begin{document}` ... `\\end{document}`
    donde ponerla. Sin composición escrita todavía, el rango es vacío y cae
    justo antes de `\\end{document}`: un documento recién creado se llena sin
    tener que tratarlo aparte.
    """
    begin = end = None
    for index, line in enumerate(lines):
        if begin is None and _BEGIN.match(line):
            begin = index
        if _END.match(line):
            end = index
    if begin is None or end is None or end <= begin:
        return None

    covered = _spans(lines, begin + 1, end)
    first = min(covered) if covered else None
    last = max(covered) if covered else None
    if first is None:
        # Sin nada escrito: al final del cuerpo, saltando las líneas en
        # blanco que lo cierran para no acumularlas en cada pasada.
        at = end
        while at - 1 > begin and not lines[at - 1].strip():
            at -= 1
        return (at, at)
    return (first, last + 1)


def compose(text, collected, language):
    """El master con su composición al día.

    Devuelve `(texto, motivo)`. Con `motivo` puesto no se ha tocado nada y
    eso es lo que hay que decir: el fichero tiene algo que este módulo no
    sabe reescribir sin perderlo.
    """
    lines = text.split("\n")
    where = _region(lines)
    if where is None:
        return text, ("no tiene un `\\begin{document}` ... `\\end{document}` "
                      "donde escribir la composición")

    start, stop = where
    covered = _spans(lines, start, stop)
    foreign = [
        lines[index].strip()
        for index in range(start, stop)
        if lines[index].strip() and index not in covered
    ]
    if foreign:
        return text, (
            "entre la composición hay LaTeX que `year.yaml` no sabe decir "
            "(%s), así que se deja como está" % foreign[0][:60]
        )

    body = render(collected, language)
    updated = lines[:start] + body + lines[stop:]
    return "\n".join(updated), None


class Composed:
    """Qué le ha pasado al master de un documento."""

    __slots__ = ("document", "path", "changed", "refused")

    def __init__(self, document, path, changed=False, refused=None):
        self.document = document
        self.path = path
        self.changed = changed
        self.refused = refused

    def __bool__(self):
        return self.changed


def compose_document(document, year_path, *, language=None, write=True):
    """Pone al día el `.tex` de un documento a partir de su `year.yaml`.

    `write=False` responde la misma pregunta sin escribir, que es lo que
    necesita `didacta check`: si el PDF que saldría es el que dice la
    composición.
    """
    if not document.source or not os.path.isfile(document.source):
        return Composed(document.id, document.source,
                        refused="no tiene `%s.tex`" % document.id)

    # Un documento vinculado tiene su composición en el fichero compartido, y
    # es la misma para todos los cursos que lo dan. El master de cada uno se
    # sigue escribiendo aparte --cada curso tiene su portada y su año-- y es
    # el cuerpo lo que sale de un solo sitio.
    if getattr(document, "content_path", None):
        collected = read_shared_entries(document.content_path)
        where = os.path.basename(document.content_path)
    else:
        collected = read_entries(year_path, document.id)
        where = os.path.basename(year_path)
    if collected is None:
        return Composed(document.id, document.source,
                        refused="no está en `%s`" % where)

    with open(document.source, encoding="utf-8") as handle:
        before = handle.read()

    updated, refused = compose(before, collected, language or document.language)
    if refused:
        return Composed(document.id, document.source, refused=refused)
    if updated == before:
        return Composed(document.id, document.source)
    if write:
        with open(document.source, "w", encoding="utf-8") as handle:
            handle.write(updated)
    return Composed(document.id, document.source, changed=True)


def compose_year(year, *, write=True):
    """Todos los documentos de un curso académico."""
    year_path = os.path.join(year.directory, "year.yaml")
    return [
        compose_document(document, year_path, write=write)
        for document in year.documents
    ]
