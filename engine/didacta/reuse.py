"""Reutilizar contenido: vincular, mover, duplicar y dividir.

Cuatro operaciones que la interfaz tiene que ofrecer por separado porque son
cuatro cosas distintas, y confundirlas es cómo se pierde material:

    mover              cambia de sitio una ubicación
    añadir vinculado   añade otra ubicación al mismo contenido
    duplicar           crea contenido nuevo, con id propio
    dividir            parte un grupo de ubicaciones en varios contenidos

Por dentro son la misma pieza vista desde cuatro sitios --duplicar es dividir
con un grupo de uno-- y están escritas así a propósito: una sola manera de
clonar una entidad y repuntar referencias, y cuatro nombres arriba porque lo
que alguien quiere hacer es distinto en cada caso.

Todo lo de aquí deja el repositorio **entero o intacto**. Se calcula el plan
completo antes de escribir nada, y lo que escribe lo cierra quien llama en un
solo commit. Una división a medias --unas ubicaciones repuntadas y otras
no-- es el peor estado posible, porque no se ve.
"""

from __future__ import annotations

import os
import re
import shutil

from . import compose as compose_mod
from . import identity as identity_mod
from . import repo as repo_mod
from . import yamlio


class ReuseError(ValueError):
    """La operación no se puede hacer, y por qué."""


class Plan:
    """Lo que una operación va a hacer, antes de hacerlo."""

    __slots__ = ("what", "touched", "notes", "content", "created")

    def __init__(self, what, touched=None, notes=None, content=None,
                 created=None):
        self.what = what
        self.touched = list(touched or [])
        self.notes = list(notes or [])
        self.content = content
        self.created = list(created or [])

    def add(self, path):
        if path not in self.touched:
            self.touched.append(path)

    def __repr__(self):  # pragma: no cover - para leer un fallo de test
        return "Plan(%s, %d ficheros)" % (self.what, len(self.touched))


# --------------------------------------------------------------------------
# Nombrar una ubicación
# --------------------------------------------------------------------------

#: `am-i@2026-2027`, `am-i@2026-2027/tema-1`, `am-i@2026-2027/tema-1#3`.
_PLACE = re.compile(
    r"^(?P<course>[^@/#]+)@(?P<year>[^@/#]+)"
    r"(?:/(?P<document>[^@/#]+))?"
    r"(?:#(?P<index>\d+))?$"
)


class Place:
    """Dónde: una asignatura, un año y --si hace falta-- qué hay dentro."""

    __slots__ = ("course", "year", "document", "index")

    def __init__(self, course, year, document=None, index=None):
        self.course = course
        self.year = year
        self.document = document
        self.index = index

    def __str__(self):
        text = "%s@%s" % (self.course, self.year)
        if self.document:
            text += "/%s" % self.document
        if self.index is not None:
            text += "#%d" % self.index
        return text

    __repr__ = __str__


def parse_place(text):
    """`am-i@2026-2027/tema-1#3` partido en sus piezas."""
    match = _PLACE.match((text or "").strip())
    if not match:
        raise ReuseError(
            "%r no nombra una ubicación: se escribe asignatura@año, y con "
            "`/documento` o `/documento#posición` cuando hace falta decir qué "
            "hay dentro" % text
        )
    index = match.group("index")
    return Place(
        match.group("course").strip(),
        match.group("year").strip(),
        (match.group("document") or "").strip() or None,
        int(index) if index is not None else None,
    )


def parse_places(text):
    """Una lista separada por comas."""
    return [parse_place(piece) for piece in str(text).split(",") if piece.strip()]


# --------------------------------------------------------------------------
# Encontrar las cosas
# --------------------------------------------------------------------------


def _year_of(courses, place, *, what="la ubicación"):
    course = courses.get(place.course)
    if course is None:
        raise ReuseError(
            "no existe la asignatura `%s` (%s)" % (place.course, what)
        )
    entry = course.years.get(place.year)
    if entry is None:
        raise ReuseError(
            "`%s` no tiene el curso `%s` (%s)" % (place.course, place.year, what)
        )
    return course, entry


def _document_of(courses, place):
    if not place.document:
        raise ReuseError("`%s` no dice qué documento" % place)
    course, entry = _year_of(courses, place)
    for document in entry.documents:
        if document.id == place.document:
            return course, entry, document
    raise ReuseError(
        "`%s` no está en %s@%s" % (place.document, place.course, place.year)
    )


def _year_path(entry):
    return os.path.join(entry.directory, repo_mod.YEAR_META)


# --------------------------------------------------------------------------
# Ubicaciones de un contenido
# --------------------------------------------------------------------------


def document_places(courses, content_id):
    """Dónde se da un documento compartido."""
    return identity_mod.document_placements(courses).get(content_id, [])


def unit_places(courses, units, root, unit_id):
    """Dónde se usa una lección."""
    return identity_mod.unit_placements(
        courses, units, root, repo_mod.resolve_unit_ref
    ).get(unit_id, [])


def find_unit(root, units, reference):
    """Una lección, nombrada por ruta o por id."""
    unit = repo_mod.resolve_unit_ref(reference, units, root)
    if unit is not None:
        return unit
    for candidate in units.values():
        if candidate.id == reference:
            return candidate
    raise ReuseError("no hay ninguna lección `%s`" % reference)


# --------------------------------------------------------------------------
# El master de un documento
# --------------------------------------------------------------------------


def _copy_master(source_document, source_year, target_entry, target_id):
    """Lleva el `.tex` de un documento a otro curso.

    El cuerpo lo reescribe la composición después; lo que se copia es el
    preámbulo y la portada, que es lo que cada curso tiene suyo. Y el año se
    sustituye donde se vea: un documento copiado que sigue diciendo el año
    viejo en la portada se reparte con la fecha de otro curso.
    """
    target = os.path.join(target_entry.directory, "%s.tex" % target_id)
    if os.path.isfile(target):
        return None
    if not source_document.source or not os.path.isfile(source_document.source):
        return None
    with open(source_document.source, encoding="utf-8") as handle:
        body = handle.read()
    if source_year != target_entry.year:
        body = body.replace(source_year, target_entry.year)
        body = body.replace(source_year.replace("-", "--"),
                            target_entry.year.replace("-", "--"))
    os.makedirs(target_entry.directory, exist_ok=True)
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(body)
    return target


def _copy_themes(source_entry, target_entry, wanted, settings):
    """Lleva al destino las declaraciones de tema que le falten.

    Sin esto, vincular el Tema 1 a otro año deja su documento suelto: la
    etiqueta viaja con el documento y la declaración se queda donde estaba. Un
    tema que nadie declara no agrupa, así que el material se vería --nunca
    desaparece-- pero sin el bloque, que es justo lo que se quería llevar.
    """
    if not wanted:
        return []
    source = repo_mod.load_themes(source_entry.directory, settings)
    if not source:
        return []
    have = {theme.id
            for theme in repo_mod.load_themes(target_entry.directory, settings)}
    missing = [theme for theme in source if theme.id in wanted and theme.id not in have]
    if not missing:
        return []

    path = os.path.join(target_entry.directory, repo_mod.THEMES_META)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as handle:
            text = handle.read().rstrip("\n")
    else:
        text = (
            "# Los temas en que se agrupa el curso.\n"
            "#\n"
            "# Cada documento dice a cuáles pertenece con `themes:` en\n"
            "# `year.yaml`; aquí van su título y su orden. Un tema que nadie\n"
            "# declara no agrupa: el documento sale suelto y no desaparece.\n"
            "\nthemes:"
        )

    body = []
    for theme in missing:
        body.append("  - id: %s" % theme.id)
        body.append("    title:")
        for code in settings.languages:
            if theme.titles.get(code):
                body.append("      %s: %s" % (code, yamlio._fmt(theme.titles[code])))
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text + "\n" + "\n".join(body) + "\n")
    return [theme.id for theme in missing]


# --------------------------------------------------------------------------
# Vincular un documento a otro curso
# --------------------------------------------------------------------------


def link_document(root, settings, source, target, *, as_id=None, courses=None):
    """Añade otra ubicación al mismo documento.

    Después de esto los dos cursos dan **el mismo tema**: editarlo desde
    cualquiera de ellos lo cambia en los dos, porque es un solo fichero y no
    dos que alguien mantiene iguales.

    Si el documento todavía no estaba compartido, esto lo saca a
    `shared/documents/` primero. Es el único momento en que un `year.yaml` de
    los que ya existen cambia de forma, y solo el del documento que se
    vincula.
    """
    courses = courses if courses is not None else _scan(root, settings)
    source = parse_place(str(source))
    target = parse_place(str(target))
    if target.document and not as_id:
        as_id = target.document

    course, entry, document = _document_of(courses, source)
    to_course, to_entry = _year_of(courses, target, what="el destino")
    local_id = as_id or document.id

    if to_entry.directory == entry.directory and local_id == document.id:
        raise ReuseError("el origen y el destino son la misma ubicación")
    if any(item.id == local_id for item in to_entry.documents):
        raise ReuseError(
            "ya hay un documento `%s` en %s@%s. Elige otro nombre con `--as`, "
            "o quítalo allí primero." % (local_id, target.course, target.year)
        )

    plan = Plan("vincular")
    content = document.content
    if not content:
        content = identity_mod.share_document(root, entry.directory, document.id)
        plan.add(_year_path(entry))
        plan.created.append(identity_mod.shared_path(root, content))
    plan.content = content

    identity_mod.insert_documents(
        _year_path(to_entry),
        [identity_mod.placement_block(local_id, content,
                                      notes=_provenance(course, entry, document))],
    )
    plan.add(_year_path(to_entry))

    master = _copy_master(document, entry.year, to_entry, local_id)
    if master:
        plan.created.append(master)
    themes = _copy_themes(entry, to_entry, document.themes, settings)
    if themes:
        plan.add(os.path.join(to_entry.directory, repo_mod.THEMES_META))
        plan.notes.append("temas que se han llevado consigo: %s" % ", ".join(themes))
    return plan


def _provenance(course, entry, document):
    """Un comentario que diga de dónde salió esta ubicación.

    Los `year.yaml` del repositorio están llenos de `# Migrated from` y de
    notas de quien compuso el curso, y son lo que permite entender un fichero
    tres años después. Una ubicación que aparece sin explicación no.
    """
    return [
        "%s%s@%s (%s): es el mismo tema, no una copia."
        % (identity_mod._LINK_NOTE, course.id, entry.year, document.id)
    ]


# --------------------------------------------------------------------------
# Mover una ubicación
# --------------------------------------------------------------------------


def move_document(root, settings, source, target, *, as_id=None, courses=None):
    """Cambia de sitio una ubicación, sin tocar la identidad del contenido.

    Mover no es copiar ni vincular: al acabar hay **las mismas ubicaciones que
    había**, una de ellas en otro sitio. Si el documento estaba vinculado
    sigue vinculado, y si no lo estaba sigue sin estarlo.
    """
    courses = courses if courses is not None else _scan(root, settings)
    source = parse_place(str(source))
    target = parse_place(str(target))
    if target.document and not as_id:
        as_id = target.document

    course, entry, document = _document_of(courses, source)
    to_course, to_entry = _year_of(courses, target, what="el destino")
    local_id = as_id or document.id

    if to_entry.directory == entry.directory and local_id == document.id:
        raise ReuseError("el origen y el destino son la misma ubicación")
    if any(item.id == local_id and item is not document
           for item in to_entry.documents):
        raise ReuseError(
            "ya hay un documento `%s` en %s@%s" % (local_id, target.course, target.year)
        )

    plan = Plan("mover", content=document.content)
    year_path = _year_path(entry)
    blocks, _ = identity_mod.document_blocks(year_path)
    block = blocks[document.id]

    if local_id != document.id:
        block = _renamed(block, local_id)

    identity_mod.remove_document_block(year_path, document.id)
    plan.add(year_path)
    identity_mod.insert_documents(_year_path(to_entry), [block])
    plan.add(_year_path(to_entry))

    # El master se va con la ubicación: es suyo, no del contenido.
    if document.source and os.path.isfile(document.source):
        target_master = os.path.join(to_entry.directory, "%s.tex" % local_id)
        if os.path.abspath(target_master) != os.path.abspath(document.source):
            os.makedirs(to_entry.directory, exist_ok=True)
            shutil.move(document.source, target_master)
            plan.created.append(target_master)
            plan.add(document.source)

    themes = _copy_themes(entry, to_entry, document.themes, settings)
    if themes:
        plan.add(os.path.join(to_entry.directory, repo_mod.THEMES_META))
        plan.notes.append("temas que se han llevado consigo: %s" % ", ".join(themes))
    return plan


def _renamed(block, local_id):
    out = []
    for line in block:
        match = identity_mod._ITEM_ID.match(line)
        out.append("  - id: %s" % local_id if match else line)
    return out


# --------------------------------------------------------------------------
# Dividir un grupo de sincronización
# --------------------------------------------------------------------------


def split_document(root, settings, content_id, groups, *, courses=None,
                   deep=False):
    """Parte un grupo de ubicaciones en varias entidades.

    `A, B, C, D` vinculadas a `X`, y se pide `{A, B}` y `{C, D}`: `A` y `B`
    siguen en `X`; `C` y `D` pasan a `Y`, que es `X` tal como está hoy. Los dos
    grupos siguen sincronizados por dentro y ya no entre sí.

    Un grupo que se queda con **una sola** ubicación deja de ser un grupo, así
    que su contenido vuelve al `year.yaml` donde se da. Un fichero compartido
    que comparte con nadie es una indirección que solo estorba.

    `deep` duplica además cada lección del tema. Apagado por defecto y con
    intención: separar dos temas casi nunca quiere decir separar las cuarenta
    lecciones que llevan dentro, y generar cuarenta identidades que nadie pidió
    es irreversible en la práctica.
    """
    courses = courses if courses is not None else _scan(root, settings)
    existing = document_places(courses, content_id)
    if not existing:
        raise ReuseError(
            "`%s` no lo usa ningún curso de este repositorio" % content_id
        )

    wanted = [[_key(place) for place in parse_places_or_list(group)]
              for group in groups]
    known = {place.key: place for place in existing}
    _check_groups(wanted, known)

    # Lo que nadie nombró se queda donde estaba, con la entidad original. Es
    # lo que hace que «saca esto de aquí» sea una operación de un paso.
    named = {key for group in wanted for key in group}
    staying = [key for key in known if key not in named]

    plan = Plan("dividir", content=content_id)
    final = []
    if staying:
        final.append((content_id, staying))
    for group in wanted:
        if staying or final:
            new_content = identity_mod.clone_shared(root, content_id)
            plan.created.append(identity_mod.shared_path(root, new_content))
        else:
            # Nadie se queda con la original: el primer grupo la hereda.
            new_content = content_id
        final.append((new_content, group))
        for key in group:
            place = known[key]
            identity_mod.relink(place.directory, place.document, new_content)
            plan.add(os.path.join(place.directory, repo_mod.YEAR_META))

    # La rama entera, cuando se pide: antes de deshacer los grupos de uno,
    # porque después ya no hay fichero compartido del que salir.
    if deep:
        plan.notes.extend(
            _split_children(root, settings,
                            [members for _, members in final[1:]], known, plan)
        )

    # Los grupos de uno dejan de serlo.
    for entity, members in final:
        if len(members) != 1:
            continue
        place = known[members[0]]
        identity_mod.unshare_document(root, place.directory, place.document)
        plan.add(os.path.join(place.directory, repo_mod.YEAR_META))
        path = identity_mod.shared_path(root, entity)
        if path in plan.created:
            plan.created.remove(path)
        plan.notes.append(
            "%s se queda solo, así que su tema vuelve a estar escrito en su "
            "curso" % place.key
        )

    plan.notes.insert(0, "%d grupo(s) al acabar" % len(final))
    return plan


def parse_places_or_list(group):
    if isinstance(group, str):
        return parse_places(group)
    return [item if isinstance(item, Place) else parse_place(str(item))
            for item in group]


def _key(place):
    if place.index is not None:
        return "%s@%s/%s#%d" % (place.course, place.year, place.document,
                                place.index)
    return "%s@%s/%s" % (place.course, place.year, place.document)


def _check_groups(groups, known):
    seen = set()
    for group in groups:
        if not group:
            raise ReuseError("un grupo vacío no divide nada")
        for key in group:
            if key not in known:
                raise ReuseError(
                    "`%s` no es una de las ubicaciones de este contenido. "
                    "Las que hay: %s" % (key, ", ".join(sorted(known)))
                )
            if key in seen:
                raise ReuseError(
                    "`%s` está en dos grupos a la vez: una ubicación va a uno"
                    % key
                )
            seen.add(key)


def _split_children(root, settings, groups, known, plan):
    """Duplica también las lecciones, cuando se pide la rama entera.

    Una vez por grupo y no una por ubicación: las ubicaciones de un grupo
    comparten composición --para eso están en el mismo grupo-- así que
    duplicar por cada una daría copias repetidas de lo mismo.
    """
    notes = []
    units, _ = repo_mod.scan_units(root, settings)
    for members in groups:
        place = known[members[0]]
        path, document_id = _composition_of(root, place)
        done = {}
        for index, ref in enumerate(_references_in(path, document_id)):
            unit = repo_mod.resolve_unit_ref(ref, units, root)
            if unit is None:
                continue
            if unit.relpath not in done:
                new_path, _ = identity_mod.duplicate_unit(
                    root, unit.relpath, settings
                )
                done[unit.relpath] = new_path
                plan.created.append(new_path)
            identity_mod.repoint_reference(
                path, document_id, index, _reference_for(done[unit.relpath])
            )
            plan.add(path)
        if done:
            notes.append("%d lección(es) duplicadas con el tema" % len(done))
    return notes


def _content_file_of(root, place, blocks):
    block = blocks.get(place.document)
    if block is None:
        return None
    content = identity_mod._field(identity_mod._body_of(block), "link")
    if not content:
        return None
    path = identity_mod.shared_path(root, content)
    return path if os.path.isfile(path) else None


def _references_in(path, document_id=None):
    """Las referencias de una composición, en orden, comentadas incluidas.

    El mismo lector que la compilación, que es lo que garantiza que las
    posiciones que se nombran aquí sean las que se ven en la pantalla.
    """
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    collected = (compose_mod.shared_entries(text) if document_id is None
                 else (compose_mod.entries(text, document_id) or []))
    return [entry.value for entry in collected if not entry.is_heading]


def _reference_for(relpath):
    """La referencia que escribe una composición: la ruta sin el árbol."""
    parts = relpath.split("/")
    if parts and parts[0] in (repo_mod.CONTENT, repo_mod.PROBLEMS):
        return "/".join(parts[1:])
    return relpath


def unlink_document(root, settings, place, *, courses=None):
    """Hace independiente una ubicación: copia propia, identidad propia.

    Es dividir con un grupo de uno, y está escrito así: una sola manera de
    clonar una entidad, para que no haya dos que puedan comportarse distinto.
    """
    courses = courses if courses is not None else _scan(root, settings)
    place = parse_place(str(place))
    course, entry, document = _document_of(courses, place)
    if not document.content:
        raise ReuseError(
            "`%s` no está vinculado: ya es suyo y de nadie más" % place
        )
    return split_document(root, settings, document.content, [[place]],
                          courses=courses)


# --------------------------------------------------------------------------
# Dividir un grupo de lecciones
# --------------------------------------------------------------------------


def split_unit(root, settings, reference, groups, *, courses=None, units=None):
    """Parte las ubicaciones de una lección en varias lecciones.

    Una lección ya era contenido vinculado: las treinta composiciones que la
    llaman llaman a la misma. Dividir es lo que faltaba -- que unas cuantas
    sigan con la de siempre y el resto pase a una copia con vida propia.
    """
    if units is None:
        units, _ = repo_mod.scan_units(root, settings)
    courses = courses if courses is not None else _scan(root, settings)

    unit = find_unit(root, units, reference)
    existing = unit_places(courses, units, root, unit.id)
    known = {place.key: place for place in existing}

    wanted = [[_key(place) for place in parse_places_or_list(group)]
              for group in groups]
    _check_groups(wanted, known)
    _check_separable(root, wanted, known)

    plan = Plan("dividir lección", content=unit.id)
    for group in wanted:
        new_path, new_id = identity_mod.duplicate_unit(root, unit.relpath, settings)
        plan.created.append(new_path)
        reference_text = _reference_for(new_path)
        for key in group:
            place = known[key]
            path, document_id = _composition_of(root, place)
            identity_mod.repoint_reference(path, document_id, place.index,
                                           reference_text)
            plan.add(path)
        plan.notes.append(
            "%s -> %s (%d ubicación(es))" % (unit.relpath, new_path, len(group))
        )
    return plan


def duplicate_unit_at(root, settings, reference, place, *, courses=None,
                      units=None):
    """Una copia independiente de una lección en una ubicación concreta."""
    return split_unit(root, settings, reference, [[place]],
                      courses=courses, units=units)


def _check_separable(root, groups, known):
    """Que los grupos se puedan separar de verdad.

    Dos ubicaciones de un **tema vinculado** son la misma línea del mismo
    fichero: separar la lección en una y no en la otra no es algo que se
    pueda escribir, y hacer como que sí dejaría las dos cambiadas y el aviso
    sin dar. Para eso está dividir el tema primero.
    """
    seen = {}
    for number, group in enumerate(groups):
        for key in group:
            place = known[key]
            where = _composition_of(root, place)
            first = seen.setdefault((where, place.index), number)
            if first != number:
                raise ReuseError(
                    "`%s` comparte composición con otra ubicación de un grupo "
                    "distinto: su tema está vinculado, así que las dos son la "
                    "misma línea. Divide antes el tema." % key
                )


def _composition_of(root, place):
    """El fichero donde está escrita la composición de una ubicación.

    El `year.yaml` del curso, o el fichero compartido cuando el tema está
    vinculado -- que es la diferencia que hace que repuntar una referencia en
    un tema compartido la repunte para todos los cursos que lo dan, que es
    exactamente lo que quiere decir estar vinculado.
    """
    year_path = os.path.join(place.directory, repo_mod.YEAR_META)
    blocks, _ = identity_mod.document_blocks(year_path)
    shared = _content_file_of(root, place, blocks)
    if shared:
        return shared, None
    return year_path, place.document


def _scan(root, settings):
    courses, errors = repo_mod.scan_courses(root, settings)
    if errors:
        raise ReuseError(
            "el repositorio no se lee limpio, así que no se toca:\n  %s"
            % "\n  ".join(errors)
        )
    return courses


# --------------------------------------------------------------------------
# Poner ids a un repositorio que no los tiene
# --------------------------------------------------------------------------


def unit_ids(root, settings, *, apply=False):
    """Escribe un `id:` en cada `unit.yaml` que no lo declare.

    Derivado de la ruta con un hash, y eso importa: dos personas que pongan al
    día el mismo repositorio por su cuenta escriben **los mismos ids**, así que
    el merge no tiene nada que resolver. Después manda el id y no la ruta, así
    que mover la carpeta ya no lo cambia.

    No mueve nada, no renombra nada y no toca el contenido. Con `apply=False`
    dice qué escribiría.
    """
    units, _ = repo_mod.scan_units(root, settings)
    pending = []
    for unit in sorted(units.values(), key=lambda item: item.relpath):
        declared = (unit.raw or {}).get("id")
        if identity_mod.is_id(declared):
            continue
        pending.append((unit.relpath,
                        identity_mod.derived_id(identity_mod.UNIT, unit.relpath)))

    if not apply:
        return pending

    for relpath, identifier in pending:
        path = os.path.join(root, relpath, repo_mod.UNIT_META)
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
        else:
            text = ""
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(identity_mod.set_unit_id(text, identifier))
    return pending

# --------------------------------------------------------------------------
# Traer un tema de otra versión del repositorio
# --------------------------------------------------------------------------


def restore_document(root, settings, source_dir, course, year, document,
                     courses=None):
    """Devuelve un tema al estado que tiene en otro árbol.

    [source_dir] es la raíz de un repositorio de contenido parado en otro
    commit: el árbol de una versión congelada. De ahí salen **las líneas** de
    su entrada en `year.yaml`, su master y, si estaba vinculado, el fichero
    compartido que daba.

    Un tema no es un fichero, así que restaurarlo no es copiar uno: su
    composición vive dentro del `year.yaml` del curso, entre las de los demás
    temas. Se sustituye su bloque y se dejan los otros donde están -- que es
    lo que separa «restaurar el Tema 3» de «volver el curso entero a
    septiembre».
    """
    courses = courses if courses is not None else _scan(root, settings)
    target_year = os.path.join(root, repo_mod.COURSES, course, year)
    year_path = os.path.join(target_year, repo_mod.YEAR_META)
    if not os.path.isfile(year_path):
        raise ReuseError("aquí no hay ningún curso %s@%s" % (course, year))

    source_year = os.path.join(source_dir, repo_mod.COURSES, course, year)
    source_path = os.path.join(source_year, repo_mod.YEAR_META)
    if not os.path.isfile(source_path):
        raise ReuseError(
            "en esa versión no había ningún curso %s@%s" % (course, year)
        )

    blocks, _ = identity_mod.document_blocks(source_path)
    block = blocks.get(document)
    if block is None:
        raise ReuseError(
            "en esa versión, %s@%s no llevaba ningún «%s»"
            % (course, year, document)
        )

    plan = Plan("restaurar tema")
    here, _ = identity_mod.document_blocks(year_path)
    if document in here:
        identity_mod.replace_document_block(year_path, document, block)
    else:
        # Se había quitado del curso: vuelve al final, que es donde va lo que
        # se añade. El orden de los demás no se toca.
        identity_mod.insert_documents(year_path, [block])
    plan.add(year_path)

    master = os.path.join(source_year, "%s.tex" % document)
    if os.path.isfile(master):
        shutil.copyfile(master, os.path.join(target_year, "%s.tex" % document))
        plan.add(os.path.join(target_year, "%s.tex" % document))

    # El fichero compartido, cuando el tema estaba vinculado. Se trae entero:
    # el tema **es** ese fichero, y restaurarlo sin él restauraría una línea
    # que apunta a otra cosa.
    content = identity_mod._field(identity_mod._body_of(block), "link")
    if content:
        origin = identity_mod.shared_path(source_dir, content)
        if os.path.isfile(origin):
            os.makedirs(identity_mod.shared_directory(root), exist_ok=True)
            shutil.copyfile(origin, identity_mod.shared_path(root, content))
            plan.add(identity_mod.shared_path(root, content))
            plan.notes.append(
                "el tema estaba vinculado, así que vuelve también el fichero "
                "compartido: esto lo cambia en todos los cursos que lo dan"
            )
    return plan

# --------------------------------------------------------------------------
# Dar una lección en otro tema
# --------------------------------------------------------------------------


def use_unit(root, settings, reference, place, *, duplicate=False,
             courses=None, units=None):
    """Añade una lección a la composición de otro tema.

    Vinculada por defecto, que es lo que una referencia ha sido siempre: la
    lección vive una vez y los dos temas llaman a la misma, así que corregir
    una errata sigue siendo corregirla en un sitio.

    Con `duplicate`, una copia con identidad propia: dos lecciones, cada una
    por su lado. Es lo que se quiere cuando el tema de la otra asignatura va a
    divergir, y es una decisión que hay que tomar **al añadirla**, no después.
    """
    if units is None:
        units, _ = repo_mod.scan_units(root, settings)
    courses = courses if courses is not None else _scan(root, settings)

    unit = find_unit(root, units, reference)
    place = parse_place(str(place))
    course, entry, document = _document_of(courses, place)

    plan = Plan("dar la lección", content=unit.id)
    relpath = unit.relpath
    if duplicate:
        relpath, _ = identity_mod.duplicate_unit(root, unit.relpath, settings)
        plan.created.append(relpath)
        plan.notes.append(
            "%s -> %s: son dos lecciones a partir de ahora"
            % (unit.relpath, relpath)
        )

    where = identity_mod.Placement(
        "unit", unit.id, place.course, place.year, document.id,
        directory=entry.directory,
    )
    path, document_id = _composition_of(root, where)
    keyword = "problem" if unit.is_problem else "unit"
    _append_reference(path, document_id, keyword, _reference_for(relpath))
    plan.add(path)
    if path != os.path.join(entry.directory, repo_mod.YEAR_META):
        plan.notes.append(
            "el tema está vinculado, así que la lección entra en todos los "
            "cursos que lo dan"
        )
    return plan


def _append_reference(path, document_id, keyword, reference):
    """Escribe `- unit: ref` al final de una composición, por líneas.

    Al final y no ordenado: el orden de un tema es el orden en que se da, y lo
    decide quien lo compone. Y por líneas, como todo lo que escribe en un
    fichero de alguien: las entradas comentadas y los `# TODO: va` que hay en
    medio son trabajo que un volcado de YAML se llevaría.
    """
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    if document_id is None:
        first, last = 0, len(lines) - 1
    else:
        first, last = identity_mod._block_span(lines, document_id)
        if first is None:
            raise ReuseError(
                "%s: no hay ningún documento `%s`" % (path, document_id)
            )

    # Dónde acaba la composición, y con qué sangría se escriben sus entradas.
    at = None
    indent = None
    for number in range(first, last + 1):
        line = lines[number]
        if re.match(r"^\s*structure\s*:\s*$", line):
            at = number
            indent = (len(line) - len(line.lstrip())) + 2
            continue
        if at is None:
            continue
        if not line.strip():
            continue
        if (len(line) - len(line.lstrip())) < indent:
            break
        at = number

    if at is None:
        # El tema no tenía composición todavía: se le pone la clave.
        field = 4 if document_id is not None else 0
        lines.insert(last + 1, "%sstructure:" % (" " * field))
        at = last + 1
        indent = field + 2

    lines.insert(at + 1, "%s- %s: %s" % (" " * indent, keyword, reference))
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines).rstrip("\n") + "\n")
