"""The content repository.

Didacta defines the layout a content repository has, rather than inferring one.
That is the main difference from the material this platform replaces, where the
layout had to be reverse-engineered from 5529 files and where the same
information lived in a folder name, a Makefile variable and a LaTeX ``\\def``.

    <content-repo>/
      didacta.yaml                      the repository's own settings
      content/<category>/<topic>/<unit>/
          unit.yaml                     metadata: title, tags, languages, status
          es.tex  va.tex  en.tex        one file per language, same content
          figures/                      assets belonging to this unit
      problems/<category>/<topic>/<unit>/
          unit.yaml
          es.tex  va.tex  en.tex        statement + answer + solution + marking
      courses/<course>/
          course.yaml                   what does not change between years
          <year>/
            year.yaml                   selection, order, structure
            <document>.tex              the composition
      shared/                           logos, bibliography, styles

Three properties this layout has and the legacy one did not:

**A unit is a directory.** Its languages, its metadata and its figures move
together. Renaming or moving a unit is one operation, and nothing outside it
has to be told.

**Language is a file name, not a naming convention.** ``va.tex`` rather than
``03VAL-espacios-normados.tex``. The ordinal that used to carry ordering lives
in the composition, where ordering belongs -- so reordering a chapter no longer
means renaming files.

**Compositions hold references, not paths.** ``analysis/normed-spaces/definition``
resolves against the content root, so no document contains ``../../../../``.
"""

from __future__ import annotations

import os
import re

from . import profiles as profiles_mod
from . import yamlio

CONTENT = "content"
PROBLEMS = "problems"
COURSES = "courses"

#: Los ficheros que hacen que un directorio sea una unidad, una asignatura o
#: un curso académico. Con nombre porque no solo los lee el escáner: contar
#: cuántos hay es como se sabe, sin abrir ninguno, si el índice sigue
#: describiendo lo que hay en el disco.
UNIT_META = "unit.yaml"
COURSE_META = "course.yaml"
YEAR_META = "year.yaml"
#: Los temas en que se agrupa un curso. Opcional, y a propósito: un curso sin
#: este fichero es un curso cuyos documentos salen en una lista, que es lo que
#: eran todos hasta ahora.
THEMES_META = "themes.yaml"

#: Las titulaciones del repositorio. En la raíz y no dentro de una
#: asignatura: un grado agrupa asignaturas, así que no puede vivir en una.
DEGREES_META = "degrees.yaml"
SHARED = "shared"
SETTINGS = "didacta.yaml"
TAXONOMY = "taxonomy.yaml"

#: Dónde se buscan las fuentes que el material cita, cuando `didacta.yaml` no
#: dice otra cosa. En `shared/` porque no son de ninguna unidad: el mismo
#: libro lo citan el análisis bibliográfico del tema 1 y el del tema 6.
DEFAULT_BIBLIOGRAPHY = "shared/bibliography.bib"

#: Los dos bloques en que se parte una asignatura. No es lo mismo que el
#: `kind` de una unidad: el kind dice qué es el fichero --una explicación, un
#: ejemplo, un ejercicio-- y el bloque dice de qué parte de la asignatura
#: forma parte. Una explicación teórica dentro de una práctica de problemas
#: es `kind: theory` y `block: problems`, y las dos cosas son ciertas a la vez.
BLOCKS = ("theory", "problems")

#: Kinds a unit may declare.
UNIT_KINDS = (
    "theory",       # the substance of a lecture
    "problem",      # an exercise with answers
    "handout",      # a one-page reference
    "activity",     # something students do in class
    "example",      # a worked example kept separate for reuse
    "experiment",   # a physical or computational demonstration
    "history",      # historical context
    "seminar",      # longer-form material
    "practical",    # a lab or computer session with a worksheet
)

#: Translation states. `missing` and `outdated` are computed, never declared:
#: the first from whether the file exists, the second by comparing hashes.
#: Writing either one down would guarantee it goes stale.
DECLARABLE_STATUSES = ("draft", "translated", "reviewed", "source")
ALL_STATUSES = DECLARABLE_STATUSES + ("missing", "outdated")


class RepoError(ValueError):
    pass


def find_root(start=None):
    """Locate a content repository by walking up for ``didacta.yaml``."""
    path = os.path.abspath(start or os.getcwd())
    while True:
        if os.path.isfile(os.path.join(path, SETTINGS)):
            return path
        parent = os.path.dirname(path)
        if parent == path:
            raise RepoError(
                "no Didacta content repository here (looked for %s upwards from %s)"
                % (SETTINGS, start or os.getcwd())
            )
        path = parent


def slugify(text):
    """A stable identifier fragment.

    Leading ordering prefixes are dropped: the legacy layout puts them on
    almost every folder to force Finder's sort order (``40functional``,
    ``00 AM III A``, ``912Secciones-conicas``), and they carry no meaning worth
    keeping in an identifier. Dropped only when letters remain, so a name that
    is genuinely numeric survives.
    """
    table = {
        "á": "a", "à": "a", "ä": "a", "â": "a", "ã": "a",
        "é": "e", "è": "e", "ë": "e", "ê": "e",
        "í": "i", "ì": "i", "ï": "i", "î": "i",
        "ó": "o", "ò": "o", "ö": "o", "ô": "o", "õ": "o",
        "ú": "u", "ù": "u", "ü": "u", "û": "u",
        "ñ": "n", "ç": "c", "·": "", "'": "", "’": "",
    }
    value = str(text).strip().lower()
    value = "".join(table.get(ch, ch) for ch in value)
    stripped = re.sub(r"^\d+[\s_-]*", "", value)
    if re.search(r"[a-z]", stripped):
        value = stripped
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value or "untitled"


# --------------------------------------------------------------------------
# Taxonomy
# --------------------------------------------------------------------------


class Topic:
    """One topic of one category: a stable id and a name per language."""

    __slots__ = ("id", "titles", "raw")

    def __init__(self, id, titles=None, raw=None):
        self.id = id
        self.titles = titles or {}
        self.raw = raw or {}

    def title(self, language=None):
        """The name to show, falling back to the id rather than to nothing."""
        if language and self.titles.get(language):
            return self.titles[language]
        for value in self.titles.values():
            if value:
                return value
        return self.id

    def as_dict(self):
        return {"id": self.id, "title": dict(self.titles)}


class Category:
    """One category, with the topics declared inside it."""

    __slots__ = ("id", "titles", "topics", "raw")

    def __init__(self, id, titles=None, topics=None, raw=None):
        self.id = id
        self.titles = titles or {}
        self.topics = topics or []
        self.raw = raw or {}

    def title(self, language=None):
        if language and self.titles.get(language):
            return self.titles[language]
        for value in self.titles.values():
            if value:
                return value
        return self.id

    def topic(self, topic_id):
        for topic in self.topics:
            if topic.id == topic_id:
                return topic
        return None

    def as_dict(self):
        return {
            "id": self.id,
            "title": dict(self.titles),
            "topics": [t.as_dict() for t in self.topics],
        }


class Taxonomy:
    """What a unit can be classified as.

    Declared in ``taxonomy.yaml`` rather than read off the folder names, and
    that is the whole point: a topic has an **id**, which is what a unit
    stores, and a **name**, which is what a person reads. Renaming a topic
    edits one line here and nothing else in the repository changes -- with the
    name in the path, renaming meant moving every unit that carried it and
    fixing every composition that referenced them.

    A repository with no ``taxonomy.yaml`` gets an empty one, and everything
    keeps working: the ids are then simply unchecked.
    """

    __slots__ = ("categories", "declared", "raw")

    def __init__(self, categories=None, declared=False, raw=None):
        self.categories = categories or []
        #: Whether the file exists. Without it nothing is validated, because
        #: a repository that has not declared its taxonomy is not a
        #: repository whose every unit is misclassified.
        self.declared = declared
        self.raw = raw or {}

    @classmethod
    def load(cls, root, settings=None):
        path = os.path.join(root, TAXONOMY)
        if not os.path.isfile(path):
            return cls()
        data = yamlio.load_file(path) or {}
        if not isinstance(data, dict):
            raise RepoError("%s: expected a mapping" % path)
        declared = data.get("categories") or []
        if not isinstance(declared, list):
            raise RepoError("%s: `categories` should be a list" % path)

        languages = (settings.languages if settings
                     else list(profiles_mod.DEFAULT_LANGUAGES))
        categories = []
        seen = set()
        for item in declared:
            if not isinstance(item, dict):
                raise RepoError("%s: each category should be a mapping" % path)
            identifier = item.get("id")
            if not identifier:
                raise RepoError("%s: a category is missing its `id`" % path)
            if identifier in seen:
                raise RepoError("%s: duplicate category `%s`" % (path, identifier))
            seen.add(identifier)

            topics = []
            topic_ids = set()
            for entry in (item.get("topics") or []):
                if not isinstance(entry, dict):
                    raise RepoError(
                        "%s: each topic of `%s` should be a mapping"
                        % (path, identifier)
                    )
                topic_id = entry.get("id")
                if not topic_id:
                    raise RepoError(
                        "%s: a topic of `%s` is missing its `id`"
                        % (path, identifier)
                    )
                if topic_id in topic_ids:
                    raise RepoError(
                        "%s: duplicate topic `%s` in `%s`"
                        % (path, topic_id, identifier)
                    )
                topic_ids.add(topic_id)
                topics.append(Topic(
                    id=topic_id,
                    titles=yamlio.localised(entry.get("title"), languages,
                                            path=path, key="title"),
                    raw=entry,
                ))

            categories.append(Category(
                id=identifier,
                titles=yamlio.localised(item.get("title"), languages,
                                        path=path, key="title"),
                topics=topics,
                raw=item,
            ))
        return cls(categories=categories, declared=True, raw=data)

    def category(self, category_id):
        for category in self.categories:
            if category.id == category_id:
                return category
        return None

    def as_dict(self):
        return {"categories": [c.as_dict() for c in self.categories]}


# --------------------------------------------------------------------------
# Settings
# --------------------------------------------------------------------------


class Settings:
    """A content repository's own configuration.

    Everything here has a working default, so a repository with an empty
    ``didacta.yaml`` still builds.
    """

    __slots__ = ("root", "name", "languages", "default_language", "build_dir",
                 "bibliography", "raw")

    def __init__(self, root, name=None, languages=None, default_language="es",
                 build_dir=".didacta-build", bibliography=None, raw=None):
        self.root = root
        self.name = name or os.path.basename(root)
        self.languages = languages or list(profiles_mod.DEFAULT_LANGUAGES)
        self.default_language = default_language
        self.build_dir = build_dir
        #: El .bib, relativo a la raíz. Declararlo es opcional: la convención
        #: es `shared/bibliography.bib`, y el paquete la prueba por su cuenta.
        self.bibliography = bibliography or DEFAULT_BIBLIOGRAPHY
        self.raw = raw or {}

    @property
    def bibliography_path(self):
        """Dónde está el .bib, o None si el repositorio no tiene."""
        path = os.path.join(self.root, self.bibliography.replace("/", os.sep))
        return path if os.path.isfile(path) else None

    @classmethod
    def load(cls, root):
        path = os.path.join(root, SETTINGS)
        data = yamlio.load_file(path) if os.path.isfile(path) else {}
        languages = data.get("languages") or list(profiles_mod.DEFAULT_LANGUAGES)
        unknown = [code for code in languages if code not in profiles_mod.LANGUAGES]
        if unknown:
            raise RepoError(
                "%s: unknown language(s) %s; Didacta ships %s"
                % (path, unknown, ", ".join(profiles_mod.LANGUAGES))
            )
        default = data.get("default_language") or languages[0]
        if default not in languages:
            raise RepoError(
                "%s: default_language `%s` is not in languages %s"
                % (path, default, languages)
            )
        bibliography = data.get("bibliography") or DEFAULT_BIBLIOGRAPHY
        if os.path.isabs(bibliography) or bibliography.startswith(".."):
            raise RepoError(
                "%s: `bibliography` has to be inside the repository, and `%s` "
                "is not" % (path, bibliography)
            )
        return cls(
            root=root,
            name=data.get("name"),
            languages=languages,
            default_language=default,
            build_dir=data.get("build_dir") or ".didacta-build",
            bibliography=bibliography,
            raw=data,
        )


# --------------------------------------------------------------------------
# Units
# --------------------------------------------------------------------------


class LanguageFile:
    """One language of a unit."""

    __slots__ = ("language", "path", "exists", "declared_status", "source_hash",
                 "bytes", "indent")

    def __init__(self, language, path, exists, declared_status=None,
                 source_hash=None, bytes=0, indent=True):
        self.language = language
        self.path = path
        self.exists = exists
        self.declared_status = declared_status
        self.source_hash = source_hash
        self.bytes = bytes
        #: Si este fichero se re-sangra al guardarlo.
        #:
        #: Por idioma y no por unidad porque el motivo para apagarlo vive en un
        #: fichero concreto: un `\verbatim` mal cerrado, una tabla alineada a
        #: mano, un bloque generado por otra herramienta. Que la version
        #: castellana necesite quedarse quieta no dice nada de la inglesa.
        self.indent = indent

    def status(self, reference_language, reference_hash):
        """The effective state of this language.

        `outdated` wins over anything declared: a translation whose original
        has moved on is behind, whatever the metadata still claims.
        """
        if not self.exists:
            return "missing"
        if self.language == reference_language:
            return self.declared_status if self.declared_status in (
                "draft", "reviewed", "source") else "source"
        if self.source_hash and reference_hash and self.source_hash != reference_hash:
            return "outdated"
        if self.declared_status in DECLARABLE_STATUSES and self.declared_status != "source":
            return self.declared_status
        return "translated"


class Unit:
    """One reusable piece of content: a directory with a unit.yaml."""

    __slots__ = (
        "id", "kind", "block", "directory", "relpath", "titles", "category",
        "topic", "tags", "reference", "languages", "prerequisites",
        "objectives", "duration_minutes", "difficulty", "parts", "marks",
        "raw", "warnings",
    )

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        for slot in ("tags", "prerequisites", "objectives", "warnings"):
            if getattr(self, slot) is None:
                setattr(self, slot, [])
        if self.languages is None:
            self.languages = {}
        if self.titles is None:
            self.titles = {}
        if self.parts is None:
            self.parts = {}

    @property
    def is_problem(self):
        return self.kind == "problem"

    @property
    def area(self):
        """The tree this unit lives in: ``content`` or ``problems``.

        Storage, not meaning. It used to be both --the tree decided which
        block a unit belonged to-- and that is what `block` says now, in the
        unit's own metadata. Kept because LaTeX still resolves a reference
        against a tree and the engine has to know which one holds the file.
        """
        parts = self.relpath.split("/")
        return parts[0] if len(parts) > 1 else CONTENT

    def title(self, language=None):
        """A title, preferring the requested language then the reference."""
        for code in (language, self.reference, "es", "va", "en"):
            if code and self.titles.get(code):
                return self.titles[code]
        return slugify(os.path.basename(self.directory)).replace("-", " ").capitalize()

    @property
    def available_languages(self):
        return [c for c, entry in self.languages.items() if entry.exists]

    @property
    def missing_languages(self):
        # Sobre los idiomas del repositorio, que son los que alguien se ha
        # comprometido a traducir. Los demás no faltan: no se esperan.
        return [c for c, entry in self.languages.items() if not entry.exists]

    def path_for(self, language):
        entry = self.languages.get(language)
        return entry.path if entry and entry.exists else None

    @property
    def area(self):
        """The tree this unit lives in: ``content`` or ``problems``.

        Not the same question as ``kind``. The kind is what the unit *is* and
        is declared; the area is where its file *is* and is a fact about the
        disk. LaTeX resolves a reference against one tree or the other, so it
        is the area that has to decide the macro -- a unit under ``problems/``
        that declares ``kind: theory`` still has to be looked up in
        ``problems/``.
        """
        parts = self.relpath.split("/")
        return parts[0] if len(parts) > 1 else CONTENT

    @property
    def reference_path(self):
        """The path a composition writes: the relpath without its area.

        `content/analysis/normed/definition` is referenced as
        `analysis/normed/definition`, because the LaTeX side appends the tree
        itself and a composition should not have to know which one.
        """
        parts = self.relpath.split("/")
        return "/".join(parts[1:]) if len(parts) > 1 else self.relpath

    def statuses(self, reference_hash=None):
        """Effective status per language."""
        return {
            code: entry.status(self.reference, reference_hash)
            for code, entry in self.languages.items()
        }

    def as_dict(self):
        return {
            "id": self.id,
            "kind": self.kind,
            "block": self.block,
            "path": self.relpath,
            "title": self.titles,
            "category": self.category,
            "topic": self.topic,
            "tags": self.tags,
            "reference": self.reference,
            "languages": {
                code: {"exists": entry.exists, "path": entry.path,
                       "declaredStatus": entry.declared_status}
                for code, entry in sorted(self.languages.items())
            },
            "prerequisites": self.prerequisites,
            "objectives": self.objectives,
            "durationMinutes": self.duration_minutes,
            "difficulty": self.difficulty,
            "parts": self.parts,
            "warnings": self.warnings,
        }


def load_unit(root, relpath, settings):
    """Read one unit directory."""
    directory = os.path.join(root, relpath)
    meta_path = os.path.join(directory, UNIT_META)
    warnings = []

    data = yamlio.load_file(meta_path) if os.path.isfile(meta_path) else {}
    if not isinstance(data, dict):
        raise RepoError("%s: expected a mapping" % meta_path)
    if not os.path.isfile(meta_path):
        warnings.append("no unit.yaml; metadata inferred from the path")

    parts = relpath.replace("\\", "/").split("/")
    area = parts[0] if parts else CONTENT
    inferred_category = parts[1] if len(parts) > 2 else ""
    inferred_topic = parts[2] if len(parts) > 3 else ""

    kind = data.get("kind") or ("problem" if area == PROBLEMS else "theory")
    if kind not in UNIT_KINDS:
        raise RepoError(
            "%s: unknown kind `%s` (known: %s)" % (meta_path, kind, ", ".join(UNIT_KINDS))
        )

    # Qué parte de la asignatura. Declarado; si no lo está, se hereda del
    # árbol, que es lo que decidía esto antes de que fuese un campo.
    block = data.get("block") or ("problems" if area == PROBLEMS else "theory")
    if block not in BLOCKS:
        raise RepoError(
            "%s: unknown block `%s` (known: %s)"
            % (meta_path, block, ", ".join(BLOCKS))
        )

    identifier = data.get("id") or ".".join(
        p for p in parts[1:] if p
    ).replace("/", ".")

    titles = yamlio.localised(data.get("title"), settings.languages,
                              path=meta_path, key="title")

    declared = data.get("languages") or {}
    if declared and not isinstance(declared, dict):
        raise RepoError("%s: `languages` should be a mapping" % meta_path)

    languages = {}
    for code in settings.languages:
        entry = declared.get(code) or {}
        if isinstance(entry, str):
            entry = {"status": entry}
        status = entry.get("status")
        if status is not None and status not in ALL_STATUSES:
            raise RepoError(
                "%s: language `%s` has unknown status `%s` (known: %s)"
                % (meta_path, code, status, ", ".join(ALL_STATUSES))
            )
        if status in ("missing", "outdated"):
            warnings.append(
                "language %s declares status `%s`, which is computed; ignoring it"
                % (code, status)
            )
            status = None
        indent = entry.get("indent")
        if indent is not None and not isinstance(indent, bool):
            raise RepoError(
                "%s: language `%s` has `indent: %s`; it should be true or false"
                % (meta_path, code, indent)
            )
        file_path = os.path.join(relpath, "%s.tex" % code)
        absolute = os.path.join(root, file_path)
        exists = os.path.isfile(absolute)
        languages[code] = LanguageFile(
            language=code,
            path=file_path,
            exists=exists,
            declared_status=status,
            source_hash=entry.get("source_hash"),
            bytes=os.path.getsize(absolute) if exists else 0,
            indent=True if indent is None else indent,
        )

    present = [c for c, entry in languages.items() if entry.exists]
    if not present:
        raise RepoError(
            "%s: no language files (expected %s)"
            % (directory, ", ".join("%s.tex" % c for c in settings.languages))
        )

    reference = data.get("reference")
    if reference and reference not in present:
        warnings.append(
            "reference language `%s` has no file; using `%s`" % (reference, present[0])
        )
        reference = None
    reference = reference or present[0]

    return Unit(
        id=identifier,
        kind=kind,
        block=block,
        directory=directory,
        relpath=relpath,
        titles=titles,
        category=data.get("category") or inferred_category,
        topic=data.get("topic") or inferred_topic,
        tags=[str(t) for t in (data.get("tags") or [])],
        reference=reference,
        languages=languages,
        prerequisites=[str(p) for p in (data.get("prerequisites") or [])],
        objectives=[str(o) for o in (data.get("objectives") or [])],
        duration_minutes=data.get("duration_minutes"),
        difficulty=data.get("difficulty"),
        parts=data.get("parts") or {},
        marks=data.get("marks"),
        raw=data,
        warnings=warnings,
    )


def scan_units(root, settings, area=None):
    """Find every unit directory under content/ and problems/.

    A unit is a directory holding at least one ``<language>.tex``. Walking for
    that rather than for ``unit.yaml`` means content that has just been
    migrated, before anyone has written metadata, is still found and still
    builds.
    """
    areas = [area] if area else [CONTENT, PROBLEMS]
    units = {}
    errors = []

    for current_area in areas:
        base = os.path.join(root, current_area)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")
                           and d not in ("figures", "assets", "img")]
            if not any("%s.tex" % code in filenames
                       for code in settings.languages):
                continue
            relpath = os.path.relpath(dirpath, root).replace(os.sep, "/")
            try:
                unit = load_unit(root, relpath, settings)
            except RepoError as exc:
                errors.append(str(exc))
                continue
            if unit.id in units:
                errors.append(
                    "duplicate unit id `%s`: %s and %s"
                    % (unit.id, units[unit.id].relpath, unit.relpath)
                )
                continue
            units[unit.id] = unit

    return units, errors


# --------------------------------------------------------------------------
# Courses
# --------------------------------------------------------------------------


class Theme:
    """Un tema del curso: el bloque bajo el que se agrupan sus documentos.

    El Tema 1 lleva su teoría, su práctica, su análisis bibliográfico y su
    marco histórico, y esos ficheros pueden estar en repositorios distintos
    --la teoría en uno, los problemas en otro--. Por eso el tema es una cosa
    aparte y no un campo del documento: **el documento dice a qué temas
    pertenece y el tema lo declara quien lo tenga.**

    De ahí la propiedad que lo hace útil: es no destructivo. Un documento que
    nombra un tema que no está declarado en ningún repositorio abierto sale
    suelto, como salía antes de que existieran los temas. Nadie se queda sin
    ver su material por no tener el repositorio donde alguien puso un título.

    No es el `topic` de `taxonomy.yaml`, aunque se parezcan: aquel clasifica
    una unidad por área de conocimiento, y lo comparten varias asignaturas;
    este ordena un curso concreto, y su orden es el orden en que se da.
    """

    __slots__ = ("id", "titles", "raw")

    def __init__(self, id, titles=None, raw=None):
        self.id = id
        self.titles = titles or {}
        self.raw = raw or {}

    def title(self, language=None):
        """El nombre que se enseña, cayendo al id antes que a nada."""
        if language and self.titles.get(language):
            return self.titles[language]
        for value in self.titles.values():
            if value:
                return value
        return self.id

    def as_dict(self):
        return {"id": self.id, "title": dict(self.titles)}


def load_themes(directory, settings):
    """Los temas declarados junto a un `year.yaml`.

    Lista vacía cuando no hay fichero, que es el caso corriente: agrupar es
    opcional.
    """
    path = os.path.join(directory, THEMES_META)
    if not os.path.isfile(path):
        return []
    data = yamlio.load_file(path) or {}
    if not isinstance(data, dict):
        raise RepoError("%s: expected a mapping" % path)
    declared = data.get("themes") or []
    if not isinstance(declared, list):
        raise RepoError("%s: `themes` should be a list" % path)

    themes = []
    seen = set()
    for item in declared:
        if not isinstance(item, dict):
            raise RepoError("%s: each theme should be a mapping" % path)
        identifier = item.get("id")
        if not identifier:
            raise RepoError("%s: a theme is missing its `id`" % path)
        if identifier in seen:
            raise RepoError("%s: duplicate theme `%s`" % (path, identifier))
        seen.add(identifier)
        themes.append(Theme(
            id=identifier,
            titles=yamlio.localised(item.get("title"), settings.languages,
                                    path=path, key="title"),
            raw=item,
        ))
    return themes


class Degree:
    """Una titulación: el grado o el máster en que se da una asignatura.

    Existe por lo mismo que [Theme] y sigue el mismo patrón, que es el que
    sostiene todo lo que se comparte entre repositorios: **la asignatura dice a
    qué grado pertenece y el grado lo declara quien lo tenga**. Así una
    asignatura repartida entre el repositorio de teoría y el de problemas
    nombra el mismo grado desde los dos, y basta con que uno de los dos lo
    declare.

    Y por eso es no destructivo. Una asignatura que nombra un grado que no
    declara ningún repositorio abierto sale igual que antes de que existieran
    los grados: sin agrupar, pero entera. Nadie se queda sin ver su material
    por no tener el repositorio donde alguien puso un título.

    No es lo mismo que el `degree:` que ya había en `course.yaml`. Aquel es el
    texto que se imprime en la portada --«Grado en Matemáticas»-- y sigue
    valiendo; esto es una entidad con id, que se puede filtrar y que dos
    repositorios reconocen como la misma. Una asignatura puede tener los dos:
    manda el id, y `check` avisa de que el texto sobra.
    """

    __slots__ = ("id", "titles", "institution", "raw")

    def __init__(self, id, titles=None, institution=None, raw=None):
        self.id = id
        self.titles = titles or {}
        self.institution = institution
        self.raw = raw or {}

    def title(self, language=None):
        """El nombre que se enseña, cayendo al id antes que a nada."""
        if language and self.titles.get(language):
            return self.titles[language]
        for value in self.titles.values():
            if value:
                return value
        return self.id

    def as_dict(self):
        return {
            "id": self.id,
            "title": dict(self.titles),
            "institution": self.institution,
        }


def load_degrees(root, settings):
    """Las titulaciones que declara este repositorio.

    Diccionario vacío cuando no hay fichero, que es el caso corriente: agrupar
    por grado es opcional, y un repositorio que no lo hace funciona igual que
    antes.
    """
    path = os.path.join(root, DEGREES_META)
    if not os.path.isfile(path):
        return {}
    data = yamlio.load_file(path) or {}
    if not isinstance(data, dict):
        raise RepoError("%s: expected a mapping" % path)
    declared = data.get("degrees") or []
    if not isinstance(declared, list):
        raise RepoError("%s: `degrees` should be a list" % path)

    degrees = {}
    for item in declared:
        if not isinstance(item, dict):
            raise RepoError("%s: each degree should be a mapping" % path)
        identifier = item.get("id")
        if not identifier:
            raise RepoError("%s: a degree is missing its `id`" % path)
        if identifier in degrees:
            raise RepoError("%s: duplicate degree `%s`" % (path, identifier))
        degrees[identifier] = Degree(
            id=identifier,
            titles=yamlio.localised(item.get("title"), settings.languages,
                                    path=path, key="title"),
            institution=item.get("institution"),
            raw=item,
        )
    return degrees


class Document:
    """One compilable document inside a course year."""

    __slots__ = ("id", "course", "year", "kind", "titles", "source", "profiles",
                 "structure", "unit_refs", "language", "themes", "raw")

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        if self.structure is None:
            self.structure = []
        if self.unit_refs is None:
            self.unit_refs = []
        if self.profiles is None:
            self.profiles = []
        if self.themes is None:
            self.themes = []

    def title(self, language=None):
        for code in (language, self.language, "es", "va", "en"):
            if code and (self.titles or {}).get(code):
                return self.titles[code]
        return self.id

    def as_dict(self):
        return {
            "id": self.id,
            "course": self.course,
            "year": self.year,
            "kind": self.kind,
            "title": self.titles,
            "source": self.source,
            "profiles": self.profiles,
            "language": self.language,
            "unitRefs": self.unit_refs,
            "structure": self.structure,
            "themes": list(self.themes),
        }


class CourseYear:
    """One academic year of a course."""

    __slots__ = ("course", "year", "group", "language", "directory", "documents",
                 "themes", "raw")

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        if self.documents is None:
            self.documents = []
        if self.themes is None:
            self.themes = []

    @property
    def id(self):
        return "%s@%s" % (self.course, self.year)


class Course:
    """A subject, across every year it has run."""

    __slots__ = ("id", "titles", "code", "degree", "degrees", "institution",
                 "departments", "languages",
                 "teacher", "language", "directory", "years", "raw")

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        if self.years is None:
            self.years = {}

    def title(self, language=None):
        for code in (language, self.language, "es", "va", "en"):
            if code and (self.titles or {}).get(code):
                return self.titles[code]
        return self.id

    def taught_in(self, settings):
        """Los idiomas de esta asignatura.

        Declarados en `course.yaml` cuando la asignatura no se da en todos los
        del repositorio, que es lo corriente: el repositorio ofrece castellano,
        valenciano e inglés, y el doble grado se da solo en castellano. Sin
        declararlos, los del repositorio, que es como se comportaba esto antes
        de que se pudiera decir.
        """
        return list(self.languages) if self.languages else list(settings.languages)

    def latex_course_keys(self, language, year=None):
        r"""The ``\DidactaCourse`` key list for this course.

        Lets the engine inject course metadata into a generated wrapper, so a
        document does not have to repeat it. A hand-written document may still
        call ``\DidactaCourse`` itself.
        """
        pairs = [
            ("title", self.title(language)),
            ("subtitle", (self.degrees or {}).get(language, "")),
            ("code", self.code or ""),
            ("teacher", self.teacher or ""),
            ("institution", self.institution or ""),
            ("department", (self.departments or {}).get(language, "")),
        ]
        if year is not None:
            entry = self.years.get(year)
            pairs.append(("year", year))
            if entry and entry.group:
                group = entry.group
                if isinstance(group, dict):
                    group = group.get(language) or next(iter(group.values()), "")
                pairs.append(("group", group))
        return ",\n  ".join("%s = {%s}" % (k, v) for k, v in pairs if v)


def _course_languages(data, settings, path):
    """Los idiomas que declara un `course.yaml`, si los declara.

    Tienen que estar entre los del repositorio: una asignatura no puede darse
    en un idioma que el repositorio no mantiene, porque no habría dónde poner
    su `.tex`.
    """
    declared = data.get("languages")
    if declared is None:
        return []
    if not isinstance(declared, list):
        raise RepoError("%s: `languages` should be a list" % path)
    codes = [str(code) for code in declared]
    unknown = [code for code in codes if code not in settings.languages]
    if unknown:
        raise RepoError(
            "%s: la asignatura dice darse en %s, y el repositorio solo "
            "mantiene %s" % (path, unknown, ", ".join(settings.languages))
        )
    return codes


def load_course(root, course_dir, settings):
    """Read one course directory, including every year in it."""
    directory = os.path.join(root, COURSES, course_dir)
    meta_path = os.path.join(directory, COURSE_META)
    data = yamlio.load_file(meta_path) if os.path.isfile(meta_path) else {}

    course = Course(
        id=data.get("id") or slugify(course_dir),
        titles=yamlio.localised(data.get("title"), settings.languages,
                                path=meta_path, key="title"),
        code=data.get("code"),
        # A qué titulación pertenece, por id. Clave aparte de `degree:` y no
        # la misma: aquella lleva el texto que se imprime en la portada, y
        # aceptar ahí un id convertiría un `degree: Grado en Matemáticas` que
        # ya existe en una referencia a un grado llamado así. Datos reales,
        # rotos en silencio, por ahorrarse una línea.
        degree=(str(data["degree_id"]).strip()
                if data.get("degree_id") else None),
        degrees=yamlio.localised(data.get("degree"), settings.languages,
                                 path=meta_path, key="degree"),
        institution=data.get("institution"),
        departments=yamlio.localised(data.get("department"), settings.languages,
                                     path=meta_path, key="department"),
        languages=_course_languages(data, settings, meta_path),
        teacher=data.get("teacher"),
        language=data.get("language") or settings.default_language,
        directory=directory,
        years={},
        raw=data,
    )

    for name in sorted(os.listdir(directory)):
        year_dir = os.path.join(directory, name)
        if not os.path.isdir(year_dir) or not re.match(r"^\d{4}-\d{4}$", name):
            continue
        course.years[name] = load_year(root, course, name, year_dir, settings)
    return course


def load_year(root, course, year, directory, settings):
    """Read one academic year: its selection, order and documents."""
    meta_path = os.path.join(directory, YEAR_META)
    data = yamlio.load_file(meta_path) if os.path.isfile(meta_path) else {}

    entry = CourseYear(
        course=course.id,
        year=year,
        # Localisable like every other visible string: "Grup A" on a Valencian
        # sheet and "Grupo A" on a Castilian one is the whole point.
        group=yamlio.localised(data.get("group"), settings.languages,
                               path=meta_path, key="group")
        if isinstance(data.get("group"), dict) else data.get("group"),
        language=data.get("language") or course.language,
        directory=directory,
        documents=[],
        # Los temas los declara `themes.yaml`, al lado y aparte: el fichero es
        # opcional, y el que lo tiene no tiene por qué ser el mismo que tiene
        # los documentos.
        themes=load_themes(directory, settings),
        raw=data,
    )

    declared = data.get("documents") or []
    if declared and not isinstance(declared, list):
        raise RepoError("%s: `documents` should be a list" % meta_path)

    for item in declared:
        if not isinstance(item, dict):
            raise RepoError("%s: each document should be a mapping" % meta_path)
        identifier = item.get("id")
        if not identifier:
            raise RepoError("%s: a document is missing its `id`" % meta_path)

        source = os.path.join(directory, "%s.tex" % identifier)
        structure = item.get("structure") or []
        unit_refs = [
            step["unit"] if "unit" in step else step["problem"]
            for step in structure
            if isinstance(step, dict) and ("unit" in step or "problem" in step)
        ]

        entry.documents.append(
            Document(
                id=identifier,
                course=course.id,
                year=year,
                kind=item.get("kind") or "theory",
                titles=yamlio.localised(item.get("title"), settings.languages,
                                        path=meta_path, key="title"),
                source=source if os.path.isfile(source) else None,
                profiles=[str(p) for p in (item.get("profiles") or [])],
                structure=structure,
                unit_refs=unit_refs,
                language=item.get("language") or entry.language,
                # A qué temas pertenece. Una lista porque un documento puede
                # estar en varios --un apéndice que sirve a dos temas-- y
                # porque un id que nadie declara no es un error: se ignora, y
                # el documento sale suelto.
                themes=[str(t) for t in (item.get("themes") or [])],
                raw=item,
            )
        )
    return entry


def scan_courses(root, settings, degrees=None):
    """Every course in the repository.

    ``degrees`` son las titulaciones declaradas, para poner a cada asignatura
    el título del grado que nombra. Sin ellas se leen del repositorio; se
    pasan ya cargadas cuando quien llama las necesita también para otra cosa,
    que es lo que evita leer el mismo fichero dos veces.
    """
    base = os.path.join(root, COURSES)
    courses = {}
    errors = []
    if degrees is None:
        try:
            degrees = load_degrees(root, settings)
        except (RepoError, yamlio.YamlError) as exc:
            errors.append(str(exc))
            degrees = {}
    if not os.path.isdir(base):
        return courses, errors
    for name in sorted(os.listdir(base)):
        if name.startswith(".") or not os.path.isdir(os.path.join(base, name)):
            continue
        try:
            course = load_course(root, name, settings)
        except (RepoError, yamlio.YamlError) as exc:
            errors.append(str(exc))
            continue
        # El título del grado, si lo nombra y alguien lo declara.
        #
        # El registro manda sobre el `degree:` escrito a mano, que pasa a ser
        # un resto: con dos títulos para el mismo grado, el que vale es el que
        # comparten los repositorios. `check` dice cuáles siguen llevando el
        # texto viejo para poder quitarlo.
        #
        # Un grado que no declara nadie **no es un error**: la asignatura sale
        # sin agrupar, como salía antes de que existieran los grados, y quien
        # tenga el repositorio donde está declarado la verá agrupada.
        if course.degree:
            declared = degrees.get(course.degree)
            if declared is not None and declared.titles:
                course.degrees = dict(declared.titles)
        courses[course.id] = course
    return courses, errors


# --------------------------------------------------------------------------
# Resolving references
# --------------------------------------------------------------------------


def resolve_unit_ref(ref, units, root):
    """Turn a composition reference into a unit.

    A reference is a path relative to the content root, e.g.
    ``analysis/normed-spaces/definition``. Falls back to matching by unit id,
    so a composition can name either.
    """
    candidates = [
        "%s/%s" % (CONTENT, ref.strip("/")),
        "%s/%s" % (PROBLEMS, ref.strip("/")),
        ref.strip("/"),
    ]
    by_path = {unit.relpath: unit for unit in units.values()}
    for candidate in candidates:
        if candidate in by_path:
            return by_path[candidate]
    if ref in units:
        return units[ref]
    dotted = ref.strip("/").replace("/", ".")
    if dotted in units:
        return units[dotted]
    return None


def content_root_for(document_source, root):
    """The ``\\DidactaContentRoot`` value for a document.

    The *repository root*, relative to the document's directory. The LaTeX side
    appends ``content/`` or ``problems/`` itself, so a composition writes
    ``analysis/normed-spaces/definition`` and nothing about where the trees sit.

    Relative rather than absolute, because an absolute path breaks the moment
    the repository is cloned somewhere else -- including in CI.
    """
    relative = os.path.relpath(root, os.path.dirname(document_source))
    return relative.replace(os.sep, "/").rstrip("/") + "/"
