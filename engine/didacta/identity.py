"""Identidad de contenido y ubicaciones: qué es algo, y dónde aparece.

Didacta nunca guardó contenido dentro de un curso: un `year.yaml` es
selección y orden, y `- unit: analisis/.../supremo` es una **referencia**. La
lección vive una vez y los treinta cursos que la llaman llaman a la misma.
Eso ya era contenido vinculado y no hacía falta inventarlo.

Lo que faltaba, y es lo que hay aquí:

**Una identidad que no sea la ruta.** Una lección declara `id:` en su
`unit.yaml`, y ese id sobrevive a mover la carpeta. La ruta sigue siendo la
dirección --es lo que escribe `\\DidactaUnit` y lo que lee LaTeX-- pero la
identidad es el id, que es lo que permite decir «estas cuatro ubicaciones son
el mismo material» sin que la frase caduque en la primera reorganización.

**Documentos compartidos.** Un tema entero --su título, su tipo, su orden,
sus apartados-- puede vivir en `shared/documents/<id>.yaml` y que varios
cursos lo nombren. Editarlo desde cualquiera de ellos escribe en ese fichero,
así que los demás lo ven en la lectura siguiente. No hay propagación: no hay
nada que propagar.

**El grupo de sincronización no se guarda.** Es el conjunto de ubicaciones
que nombran el mismo id, y se calcula leyendo los ficheros. Una tabla aparte
sería una segunda fuente de verdad, y reconciliarla después de un `git merge`
es exactamente el problema que esto existe para no tener. Como los vínculos
*son* los ficheros, un clon limpio los reconstruye enteros sin más.

**Las líneas se conservan.** Novecientas entradas del repositorio están
comentadas --material que existe y que este año no se da-- y los `# TODO: va`
son la lista de lo que falta por traducir. Mover un documento a un fichero
compartido mueve **sus líneas**, no un volcado de YAML de lo que un lector
entendió. Es la misma regla que en `compose.py` y por la misma razón.
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import uuid

from . import yamlio

#: Dónde viven los documentos compartidos, bajo la raíz del repositorio.
SHARED = "shared"
SHARED_DOCUMENTS = os.path.join(SHARED, "documents")

#: El prefijo de cada clase de id. Un id dice de qué es sin tener que
#: buscarlo: un `d-` en un `unit.yaml` es un error que se ve al leerlo.
UNIT = "u"
DOCUMENT = "d"
FREEZE = "f"

#: Cuántos caracteres del hash. Doce hex son 48 bits: con diez mil unidades
#: la probabilidad de colisión está por debajo de 10^-7, y un id más largo
#: solo hace más incómodo el fichero que lo lleva.
_LENGTH = 12

_ID = re.compile(r"^[udf]-[0-9a-f]{%d}$" % _LENGTH)


class IdentityError(ValueError):
    """Algo del modelo de identidad no cuadra."""


def is_id(value):
    """Si esto tiene la forma de un id de Didacta."""
    return bool(value) and bool(_ID.match(str(value).strip()))


def new_id(prefix):
    """Un id nuevo, sin relación con nada.

    Para contenido que nace ahora: al duplicar, al dividir un grupo. Aleatorio
    y no derivado del contenido porque dos copias del mismo material son dos
    entidades distintas, y ese es justo el punto.
    """
    return "%s-%s" % (prefix, uuid.uuid4().hex[:_LENGTH])


def derived_id(prefix, seed):
    """Un id reproducible a partir de una semilla.

    Existe por la migración. Dos personas que pongan al día el mismo
    repositorio por su cuenta tienen que escribir **los mismos ids**, o el
    merge trae dos identidades para la misma lección y el modelo entero deja
    de sostenerse. Derivarlo de la ruta lo garantiza sin coordinación.

    Después de escrito manda el id, no la ruta: mover la carpeta no lo cambia.
    La ruta solo lo siembra una vez.
    """
    digest = hashlib.sha1(str(seed).encode("utf-8")).hexdigest()
    return "%s-%s" % (prefix, digest[:_LENGTH])


# --------------------------------------------------------------------------
# Los bloques de `documents:` de un `year.yaml`
# --------------------------------------------------------------------------
#
# Por líneas y no reserializando, por lo dicho arriba. Estaba en el CLI y se
# ha traído aquí porque ahora lo usan tres operaciones distintas.


_ITEM_ID = re.compile(r"^  - id:\s*(\S+)\s*$")
_DOCUMENTS_KEY = re.compile(r"^documents:\s*$")


def document_blocks(path):
    """Los bloques de `documents:` de un `year.yaml`, por id, y su orden.

    Un bloque se lleva consigo sus comentarios --el `# TODO: va` que dice qué
    falta por traducir, el `# Migrated from` que dice de dónde salió, las
    entradas comentadas de material que este año no se da-- y todo eso es
    trabajo de alguien que un volcado de YAML tiraría.
    """
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    blocks, order, name, current = {}, [], None, []
    for line in lines:
        match = _ITEM_ID.match(line)
        if match:
            if name:
                blocks[name] = _trim(current)
            name, current = match.group(1), []
            order.append(name)
        elif name is not None and line and not line.startswith(("  ", "\t")):
            # Una clave de primer nivel después de la lista: se acabó.
            blocks[name] = _trim(current)
            name, current = None, []
            continue
        if name is not None:
            current.append(line)
    if name:
        blocks[name] = _trim(current)
    return blocks, order


def _trim(lines):
    while lines and not lines[-1].strip():
        lines.pop()
    return list(lines)


def _documents_region(lines):
    """Dónde empieza y acaba la lista de `documents:`.

    Devuelve `(start, end)`, con `start` la línea de la clave --o None si no
    está-- y `end` el índice detrás del último bloque.
    """
    start = None
    for index, line in enumerate(lines):
        if _DOCUMENTS_KEY.match(line):
            start = index
            break
    if start is None:
        return None, len(lines)

    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if not line.strip() or line.startswith(("  ", "\t")):
            continue
        end = index
        break
    while end > start + 1 and not lines[end - 1].strip():
        end -= 1
    return start, end


def insert_documents(path, blocks):
    """Añade bloques al final de `documents:` de un `year.yaml`.

    Al final y no ordenados: el orden de un curso es el orden en que se da, y
    lo decide quien lo compone. Lo que se copia se pone detrás, que es donde
    no estorba.
    """
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    start, end = _documents_region(lines)
    if start is None:
        while lines and not lines[-1].strip():
            lines.pop()
        lines.extend(["", "documents:"])
        start, end = len(lines) - 1, len(lines)

    body = []
    empty = end == start + 1
    for index, block in enumerate(blocks):
        # Una línea en blanco entre documentos, pero no colgando de
        # `documents:` cuando la lista estaba vacía.
        if index or not empty:
            body.append("")
        body.extend(block)

    out = lines[:end] + body + lines[end:]
    _write_lines(path, out)


def replace_document_block(path, document_id, block):
    """Cambia un bloque de `documents:` por otro, en su sitio.

    En su sitio y no al final: el orden de la lista es el orden del curso, y
    vincular un documento no lo mueve.
    """
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    first, last = _block_span(lines, document_id)
    if first is None:
        raise IdentityError("%s: no hay ningún documento `%s`" % (path, document_id))
    _write_lines(path, lines[:first] + list(block) + lines[last + 1:])


def remove_document_block(path, document_id):
    """Quita un documento de `documents:`, con sus comentarios."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    first, last = _block_span(lines, document_id)
    if first is None:
        raise IdentityError("%s: no hay ningún documento `%s`" % (path, document_id))
    # La línea en blanco que lo separaba del anterior se va con él, o cada
    # borrado deja un hueco que se acumula.
    while first > 0 and not lines[first - 1].strip() and _blank_above_is_ours(lines, first):
        first -= 1
    _write_lines(path, lines[:first] + lines[last + 1:])


def _blank_above_is_ours(lines, first):
    """Si la línea en blanco de encima separa documentos y no la clave."""
    for index in range(first - 1, -1, -1):
        if lines[index].strip():
            return not _DOCUMENTS_KEY.match(lines[index])
    return False


def _block_span(lines, document_id):
    """Las líneas primera y última del bloque de un documento."""
    start, end = _documents_region(lines)
    if start is None:
        return None, None
    first = None
    for index in range(start + 1, end):
        match = _ITEM_ID.match(lines[index])
        if not match:
            continue
        if first is not None:
            return first, _back_to_content(lines, index - 1)
        if match.group(1) == document_id:
            first = index
    if first is None:
        return None, None
    return first, _back_to_content(lines, end - 1)


def _back_to_content(lines, index):
    while index > 0 and not lines[index].strip():
        index -= 1
    return index


def _write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines).rstrip("\n") + "\n")


# --------------------------------------------------------------------------
# Documentos compartidos
# --------------------------------------------------------------------------


_SHARED_HEADER = """\
# Un documento compartido.
#
# Vive aquí y no dentro de un curso porque lo dan varios: cada `year.yaml`
# que lo usa escribe una línea `link:` con el id de abajo y nada más. El
# título, el tipo, los temas y la composición son estos, para todos, así que
# editarlos desde cualquiera de los cursos los cambia en todos --no porque se
# copie nada, sino porque es el mismo fichero.
#
# Para separar uno de los cursos del resto: «Gestionar vinculación» en la
# aplicación, o `didacta split`.
"""


def shared_directory(root):
    return os.path.join(root, SHARED_DOCUMENTS)


def shared_path(root, content_id):
    return os.path.join(shared_directory(root), "%s.yaml" % content_id)


def list_shared(root):
    """Los ids de los documentos compartidos que hay."""
    directory = shared_directory(root)
    if not os.path.isdir(directory):
        return []
    found = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".yaml"):
            found.append(name[: -len(".yaml")])
    return found


def load_shared(root, content_id):
    """Los datos de un documento compartido, o None si no está."""
    path = shared_path(root, content_id)
    if not os.path.isfile(path):
        return None
    data = yamlio.load_file(path)
    if not isinstance(data, dict):
        raise IdentityError("%s: se esperaba un mapa" % path)
    return data


def _dedent(lines, amount):
    """Quita [amount] espacios de sangría, respetando las líneas vacías."""
    out = []
    for line in lines:
        if not line.strip():
            out.append("")
            continue
        take = 0
        while take < amount and take < len(line) and line[take] == " ":
            take += 1
        out.append(line[take:])
    return out


def _indent(lines, amount):
    pad = " " * amount
    return ["" if not line.strip() else pad + line for line in lines]


def share_document(root, year_directory, document_id, content_id=None):
    """Saca un documento del `year.yaml` a `shared/documents/`.

    Devuelve el id de contenido. El curso se queda con la ubicación --su `id`
    local, que es el nombre del `.tex`-- y lo demás se muda entero, con sus
    comentarios: son las líneas que había, no una reserialización.
    """
    year_path = os.path.join(year_directory, "year.yaml")
    blocks, _ = document_blocks(year_path)
    block = blocks.get(document_id)
    if block is None:
        raise IdentityError(
            "%s: no hay ningún documento `%s`" % (year_path, document_id)
        )

    body = _body_of(block)
    if _field(body, "link"):
        raise IdentityError("`%s` ya está vinculado" % document_id)

    content_id = content_id or new_id(DOCUMENT)
    os.makedirs(shared_directory(root), exist_ok=True)
    text = _SHARED_HEADER
    text += "\nid: %s\n\n" % content_id
    text += "\n".join(_dedent(body, 4)).rstrip("\n") + "\n"
    with open(shared_path(root, content_id), "w", encoding="utf-8") as handle:
        handle.write(text)

    replace_document_block(
        year_path,
        document_id,
        _placement_block(document_id, content_id, _notes_of(block)),
    )
    return content_id


def unshare_document(root, year_directory, document_id, *, remove_file=True):
    """Devuelve un documento compartido al `year.yaml` que lo usa.

    Lo contrario de [share_document]: el contenido vuelve a estar escrito
    donde se da, que es como está todo lo que solo se da en un sitio. Un grupo
    de sincronización de uno no es un grupo.
    """
    year_path = os.path.join(year_directory, "year.yaml")
    blocks, _ = document_blocks(year_path)
    block = blocks.get(document_id)
    if block is None:
        raise IdentityError(
            "%s: no hay ningún documento `%s`" % (year_path, document_id)
        )
    content_id = _field(_body_of(block), "link")
    if not content_id:
        raise IdentityError("`%s` no está vinculado" % document_id)

    path = shared_path(root, content_id)
    if not os.path.isfile(path):
        raise IdentityError(
            "`%s` dice llevar `%s`, y ese fichero no está" % (document_id, content_id)
        )
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    body = _indent(_without_header(lines), 4)
    replace_document_block(
        year_path,
        document_id,
        _kept_notes(_notes_of(block)) + ["  - id: %s" % document_id] + body,
    )
    if remove_file:
        os.remove(path)
    return content_id


def clone_shared(root, content_id, new_content_id=None):
    """Una copia de un documento compartido, con identidad propia.

    Lo que hace una división: el contenido de ahora, un id nuevo, y a partir
    de ese momento dos vidas separadas.
    """
    path = shared_path(root, content_id)
    if not os.path.isfile(path):
        raise IdentityError("no hay ningún documento compartido `%s`" % content_id)
    new_content_id = new_content_id or new_id(DOCUMENT)
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    text = _SHARED_HEADER
    text += "\nid: %s\n\n" % new_content_id
    text += "\n".join(_without_header(lines)).rstrip("\n") + "\n"
    with open(shared_path(root, new_content_id), "w", encoding="utf-8") as handle:
        handle.write(text)
    return new_content_id


def relink(year_directory, document_id, content_id):
    """Apunta una ubicación a otro contenido."""
    year_path = os.path.join(year_directory, "year.yaml")
    blocks, _ = document_blocks(year_path)
    block = blocks.get(document_id)
    if block is None:
        raise IdentityError(
            "%s: no hay ningún documento `%s`" % (year_path, document_id)
        )
    replace_document_block(
        year_path,
        document_id,
        _placement_block(document_id, content_id, _notes_of(block)),
    )


def placement_block(document_id, content_id, notes=()):
    """El bloque de `year.yaml` de una ubicación vinculada."""
    return _placement_block(document_id, content_id, list(notes))


def _placement_block(document_id, content_id, notes):
    return list(notes) + [
        "  - id: %s" % document_id,
        "    link: %s" % content_id,
    ]


def _body_of(block):
    """El bloque sin los comentarios de cabecera ni la línea del `id`."""
    for index, line in enumerate(block):
        if _ITEM_ID.match(line):
            return block[index + 1:]
    return list(block)


#: El comentario que escribe el vinculador. Se reconoce para poder quitarlo:
#: dejar «es el mismo tema, no una copia» encima de un tema que acaba de
#: separarse es dejar escrita una mentira, y es la clase de comentario del que
#: alguien se fía tres años después.
_LINK_NOTE = "  # Vinculado desde "


def _kept_notes(notes):
    return [line for line in notes if not line.startswith(_LINK_NOTE)]


def _notes_of(block):
    """Los comentarios que había encima del `- id:`."""
    for index, line in enumerate(block):
        if _ITEM_ID.match(line):
            return block[:index]
    return []


def _without_header(lines):
    """Un fichero compartido sin su cabecera ni su `id:`."""
    out = []
    started = False
    for line in lines:
        if not started:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if re.match(r"^id:\s*", line):
                continue
            started = True
        out.append(line)
    while out and not out[-1].strip():
        out.pop()
    return out


def _field(lines, key):
    """El valor de una clave de primer nivel del cuerpo de un documento."""
    pattern = re.compile(r"^    %s:\s*(.*)$" % re.escape(key))
    for line in lines:
        match = pattern.match(line)
        if match:
            return _scalar(match.group(1))
    return None


def _scalar(text):
    value = text.split("#")[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


# --------------------------------------------------------------------------
# Ubicaciones
# --------------------------------------------------------------------------


class Placement:
    """Dónde aparece un contenido.

    Un documento aparece en `(asignatura, año)`; una lección, dentro de un
    documento y en una posición concreta de su composición, porque la misma
    lección puede estar dos veces en el mismo tema y son dos ubicaciones.
    """

    __slots__ = ("what", "content", "course", "year", "document", "index", "ref",
                 "repo", "directory")

    def __init__(self, what, content, course, year, document,
                 index=None, ref=None, repo="", directory=""):
        self.what = what              # "document" | "unit"
        self.content = content
        self.course = course
        self.year = year
        self.document = document
        self.index = index
        self.ref = ref
        self.repo = repo
        self.directory = directory

    @property
    def key(self):
        if self.what == "document":
            return "%s@%s/%s" % (self.course, self.year, self.document)
        return "%s@%s/%s#%d" % (self.course, self.year, self.document, self.index)

    def as_dict(self):
        out = {
            "what": self.what,
            "content": self.content,
            "course": self.course,
            "year": self.year,
            "document": self.document,
        }
        if self.index is not None:
            out["index"] = self.index
        if self.ref:
            out["ref"] = self.ref
        return out

    def __repr__(self):  # pragma: no cover - para leer un fallo de test
        return "Placement(%s)" % self.key


def document_placements(courses):
    """Todas las ubicaciones de documento que hay, por id de contenido.

    Solo las vinculadas: un documento que solo se da en un sitio no forma
    grupo y no tiene id de contenido, que es lo que evita que compartir sea
    obligatorio para escribir un curso.
    """
    found = {}
    for course in courses.values():
        for year, entry in course.years.items():
            for document in entry.documents:
                if not document.content:
                    continue
                found.setdefault(document.content, []).append(
                    Placement(
                        "document",
                        document.content,
                        course.id,
                        year,
                        document.id,
                        directory=entry.directory,
                    )
                )
    for entries in found.values():
        entries.sort(key=lambda p: (p.course, p.year, p.document))
    return found


def unit_placements(courses, units, root, resolve):
    """Todas las ubicaciones de lección, por id de contenido.

    [resolve] es `repo.resolve_unit_ref`; se pasa en lugar de importarlo para
    no cerrar el círculo de imports entre este módulo y `repo`.
    """
    found = {}
    for course in courses.values():
        for year, entry in course.years.items():
            for document in entry.documents:
                position = 0
                for ref in document.unit_refs or []:
                    unit = resolve(ref, units, root)
                    position += 1
                    if unit is None:
                        continue
                    found.setdefault(unit.id, []).append(
                        Placement(
                            "unit",
                            unit.id,
                            course.id,
                            year,
                            document.id,
                            index=position - 1,
                            ref=ref,
                            directory=entry.directory,
                        )
                    )
    for entries in found.values():
        entries.sort(key=lambda p: (p.course, p.year, p.document, p.index))
    return found


# --------------------------------------------------------------------------
# Repuntar una referencia dentro de una composición
# --------------------------------------------------------------------------


_REFERENCE = re.compile(
    r"^(?P<pad>\s*)(?P<off>#\s*)?-\s+(?P<kind>unit|problem)\s*:\s*(?P<value>.*)$"
)


def repoint_reference(path, document_id, index, new_ref):
    """Cambia la referencia número [index] de una composición.

    [document_id] es None cuando el fichero es un documento compartido, donde
    la composición es la única que hay.

    Por líneas: una entrada comentada cuenta como ubicación --es material que
    existe y que este año no se da-- y reescribir el YAML la perdería.
    """
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    if document_id is None:
        first, last = 0, len(lines) - 1
    else:
        first, last = _block_span(lines, document_id)
        if first is None:
            raise IdentityError(
                "%s: no hay ningún documento `%s`" % (path, document_id)
            )

    position = 0
    for number in range(first, last + 1):
        match = _REFERENCE.match(lines[number])
        if not match:
            continue
        if position == index:
            value, comment = _split_comment(match.group("value"))
            del value
            lines[number] = "%s%s- %s: %s%s" % (
                match.group("pad"),
                match.group("off") or "",
                match.group("kind"),
                new_ref,
                comment,
            )
            _write_lines(path, lines)
            return True
        position += 1
    return False


def _split_comment(text):
    at = text.find(" #")
    if at < 0:
        return text.strip(), ""
    return text[:at].strip(), text[at:]


# --------------------------------------------------------------------------
# Duplicar una lección
# --------------------------------------------------------------------------


def duplicate_unit(root, relpath, settings, new_relpath=None):
    """Una copia independiente de una lección, con id propio.

    Copia la carpeta entera --los idiomas, las figuras, el `unit.yaml`-- y le
    pone un id nuevo. A partir de ahí son dos lecciones y cada una va por su
    lado, que es lo que se pidió al duplicar.
    """
    source = os.path.join(root, relpath)
    if not os.path.isdir(source):
        raise IdentityError("no hay ninguna lección en %s" % relpath)

    new_relpath = new_relpath or _free_path(root, relpath)
    target = os.path.join(root, new_relpath)
    if os.path.exists(target):
        raise IdentityError("%s ya existe" % new_relpath)
    shutil.copytree(source, target)

    identifier = new_id(UNIT)
    meta = os.path.join(target, "unit.yaml")
    if os.path.isfile(meta):
        with open(meta, encoding="utf-8") as handle:
            text = handle.read()
        with open(meta, "w", encoding="utf-8") as handle:
            handle.write(set_unit_id(text, identifier))
    else:
        with open(meta, "w", encoding="utf-8") as handle:
            handle.write("id: %s\n" % identifier)
    return new_relpath, identifier


def _free_path(root, relpath):
    """`content/a/b/c` -> `content/a/b/c-2`, o el primero que esté libre."""
    base = relpath.rstrip("/")
    for number in range(2, 500):
        candidate = "%s-%d" % (base, number)
        if not os.path.exists(os.path.join(root, candidate)):
            return candidate
    raise IdentityError("no queda sitio al lado de %s" % relpath)


_UNIT_ID = re.compile(r"^id:\s*.*$")


def set_unit_id(text, identifier):
    """Escribe el `id:` de un `unit.yaml` sin tocar nada más.

    Por líneas, como todo lo que escribe en un fichero de alguien: un
    `unit.yaml` migrado lleva veinte líneas de comentarios que dicen de dónde
    salió y qué falta por comprobar, y son lo único que queda de eso.
    """
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if _UNIT_ID.match(line):
            lines[index] = "id: %s" % identifier
            return "\n".join(lines)

    # Sin `id:`: delante de todo lo que no sea la cabecera de comentarios, que
    # es donde lo escribe la migración y donde se lee primero.
    at = 0
    for index, line in enumerate(lines):
        if line.strip() and not line.lstrip().startswith("#"):
            at = index
            break
    else:
        at = len(lines)
    lines.insert(at, "id: %s" % identifier)
    if at + 1 < len(lines) and lines[at + 1].strip():
        lines.insert(at + 1, "")
    return "\n".join(lines)
