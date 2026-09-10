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
SHARED = "shared"
SETTINGS = "didacta.yaml"

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
# Settings
# --------------------------------------------------------------------------


class Settings:
    """A content repository's own configuration.

    Everything here has a working default, so a repository with an empty
    ``didacta.yaml`` still builds.
    """

    __slots__ = ("root", "name", "languages", "default_language", "build_dir", "raw")

    def __init__(self, root, name=None, languages=None, default_language="es",
                 build_dir=".didacta-build", raw=None):
        self.root = root
        self.name = name or os.path.basename(root)
        self.languages = languages or list(profiles_mod.LANGUAGES)
        self.default_language = default_language
        self.build_dir = build_dir
        self.raw = raw or {}

    @classmethod
    def load(cls, root):
        path = os.path.join(root, SETTINGS)
        data = yamlio.load_file(path) if os.path.isfile(path) else {}
        languages = data.get("languages") or list(profiles_mod.LANGUAGES)
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
        return cls(
            root=root,
            name=data.get("name"),
            languages=languages,
            default_language=default,
            build_dir=data.get("build_dir") or ".didacta-build",
            raw=data,
        )


# --------------------------------------------------------------------------
# Units
# --------------------------------------------------------------------------


class LanguageFile:
    """One language of a unit."""

    __slots__ = ("language", "path", "exists", "declared_status", "source_hash", "bytes")

    def __init__(self, language, path, exists, declared_status=None,
                 source_hash=None, bytes=0):
        self.language = language
        self.path = path
        self.exists = exists
        self.declared_status = declared_status
        self.source_hash = source_hash
        self.bytes = bytes

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
        "id", "kind", "directory", "relpath", "titles", "category", "topic",
        "tags", "reference", "languages", "prerequisites", "objectives",
        "duration_minutes", "difficulty", "parts", "marks", "raw", "warnings",
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

    def title(self, language=None):
        """A title, preferring the requested language then the reference."""
        for code in (language, self.reference, "es", "va", "en"):
            if code and self.titles.get(code):
                return self.titles[code]
        return slugify(os.path.basename(self.directory)).replace("-", " ").capitalize()

    @property
    def available_languages(self):
        return [c for c in profiles_mod.LANGUAGES
                if c in self.languages and self.languages[c].exists]

    @property
    def missing_languages(self):
        return [c for c in profiles_mod.LANGUAGES
                if c not in self.languages or not self.languages[c].exists]

    def path_for(self, language):
        entry = self.languages.get(language)
        return entry.path if entry and entry.exists else None

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
    meta_path = os.path.join(directory, "unit.yaml")
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

    identifier = data.get("id") or ".".join(
        p for p in parts[1:] if p
    ).replace("/", ".")

    titles = yamlio.localised(data.get("title"), settings.languages,
                              path=meta_path, key="title")

    declared = data.get("languages") or {}
    if declared and not isinstance(declared, dict):
        raise RepoError("%s: `languages` should be a mapping" % meta_path)

    languages = {}
    for code in profiles_mod.LANGUAGES:
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
        )

    present = [c for c in profiles_mod.LANGUAGES if languages[c].exists]
    if not present:
        raise RepoError("%s: no language files (expected es.tex, va.tex or en.tex)" % directory)

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
            if not any("%s.tex" % code in filenames for code in profiles_mod.LANGUAGES):
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


class Document:
    """One compilable document inside a course year."""

    __slots__ = ("id", "course", "year", "kind", "titles", "source", "profiles",
                 "structure", "unit_refs", "language", "raw")

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        if self.structure is None:
            self.structure = []
        if self.unit_refs is None:
            self.unit_refs = []
        if self.profiles is None:
            self.profiles = []

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
        }


class CourseYear:
    """One academic year of a course."""

    __slots__ = ("course", "year", "group", "language", "directory", "documents", "raw")

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        if self.documents is None:
            self.documents = []

    @property
    def id(self):
        return "%s@%s" % (self.course, self.year)


class Course:
    """A subject, across every year it has run."""

    __slots__ = ("id", "titles", "code", "degrees", "institution", "departments",
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


def load_course(root, course_dir, settings):
    """Read one course directory, including every year in it."""
    directory = os.path.join(root, COURSES, course_dir)
    meta_path = os.path.join(directory, "course.yaml")
    data = yamlio.load_file(meta_path) if os.path.isfile(meta_path) else {}

    course = Course(
        id=data.get("id") or slugify(course_dir),
        titles=yamlio.localised(data.get("title"), settings.languages,
                                path=meta_path, key="title"),
        code=data.get("code"),
        degrees=yamlio.localised(data.get("degree"), settings.languages,
                                 path=meta_path, key="degree"),
        institution=data.get("institution"),
        departments=yamlio.localised(data.get("department"), settings.languages,
                                     path=meta_path, key="department"),
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
    meta_path = os.path.join(directory, "year.yaml")
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
                raw=item,
            )
        )
    return entry


def scan_courses(root, settings):
    """Every course in the repository."""
    base = os.path.join(root, COURSES)
    courses = {}
    errors = []
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
