"""Derived indices.

An interface has to list thousands of units, filter them and show what uses
what. Doing that by reading the repository means opening every ``unit.yaml``
and every ``year.yaml`` on every page load, which a browser cannot do at all --
it would be one HTTP request per unit against 2147 units.

So the repository gets a generated catalogue: a few JSON files with everything
an interface needs to browse, and nothing it does not. Reading a unit's actual
LaTeX is a separate request, made only when someone opens it.

Three rules this follows, and the reasons:

**Derived, never authoritative.** Delete the whole directory and regenerate it
and the result is byte-identical. Nothing is written here that is not already
in the repository, so there is no second place for a fact to live and go stale
-- which is the same rule as `missing`/`outdated` never being declared.

**Deterministic.** Sorted keys, sorted lists, and no timestamp anywhere -- not
even in the manifest, where one lived briefly and made `--check` report the
index stale immediately after writing it. Two runs over the same content
produce the same bytes, so an index that has drifted shows up as a diff in
review rather than as churn to be ignored, and CI can check freshness by
regenerating and comparing.

**One request per view.** ``units.json`` answers "show me the library" on its
own, including who uses each unit -- computed here by walking the compositions
once, because an interface cannot do that walk itself without reading every
year file.
"""

from __future__ import annotations

import hashlib
import json
import os

from . import profiles as profiles_mod
from . import repo as repo_mod
from . import yamlio

#: Where the generated files go, relative to the repository root.
GENERATED = "generated"

#: Bumped when the shape changes in a way a reader has to know about. An
#: interface that expects 2 and finds 3 should say so rather than misread it.
SCHEMA_VERSION = 1

MANIFEST = "manifest.json"
UNITS = "units.json"
COURSES = "courses.json"
CATEGORIES = "categories.json"


class IndexError_(RuntimeError):
    pass


def build(root, settings=None, latex_dir=None):
    """Compute every index for the repository at ``root``.

    Returns ``{filename: data}``. Writes nothing -- :func:`write` does that --
    so the CLI can show what would change before changing it.
    """
    settings = settings or repo_mod.Settings.load(root)
    units, unit_errors = repo_mod.scan_units(root, settings)
    courses, course_errors = repo_mod.scan_courses(root, settings)
    try:
        taxonomy = repo_mod.Taxonomy.load(root, settings)
        taxonomy_errors = []
    except (repo_mod.RepoError, yamlio.YamlError) as exc:
        taxonomy = repo_mod.Taxonomy()
        taxonomy_errors = [str(exc)]

    profiles = {}
    if latex_dir and os.path.isdir(latex_dir):
        try:
            profiles = profiles_mod.load(latex_dir)
        except Exception:  # noqa: BLE001 - an index without profiles is still useful
            profiles = {}

    usage = _usage(courses, units, root)

    unit_records = [_unit_record(unit, settings, usage) for unit in
                    sorted(units.values(), key=lambda item: item.relpath)]
    course_records = [_course_record(course, settings) for course in
                      sorted(courses.values(), key=lambda item: item.id)]

    return {
        MANIFEST: _manifest(root, settings, unit_records, course_records,
                            profiles,
                            unit_errors + course_errors + taxonomy_errors,
                            taxonomy=taxonomy),
        UNITS: {"schemaVersion": SCHEMA_VERSION, "units": unit_records},
        COURSES: {"schemaVersion": SCHEMA_VERSION, "courses": course_records},
        CATEGORIES: {"schemaVersion": SCHEMA_VERSION,
                     "categories": _categories(unit_records)},
    }


def write(root, data, dry_run=False):
    """Write the indices. Returns the relative paths written or that would be."""
    directory = os.path.join(root, GENERATED)
    written = []
    for name in sorted(data):
        path = os.path.join(directory, name)
        if not dry_run:
            os.makedirs(directory, exist_ok=True)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(dumps(data[name]))
        written.append("%s/%s" % (GENERATED, name))
    return written


def dumps(payload):
    """One canonical serialisation, so a rerun is a no-op in git.

    Sorted keys and a trailing newline; ``ensure_ascii`` off because these
    titles are Valencian and Castilian and escaping them helps nobody reading
    a diff.
    """
    return json.dumps(payload, ensure_ascii=False, indent=2,
                      sort_keys=True) + "\n"


def survey(root, settings):
    """Lo que hay en el disco ahora mismo, a golpe de `stat`.

    La pregunta que contesta es «¿el índice sigue valiendo?», y tiene que ser
    barata porque se hace en cada arranque. Generar el índice para
    compararlo cuesta tres segundos; contar ficheros y mirar fechas, una
    décima: son las dos mil llamadas a `stat` que hace un `walk`, sin abrir
    ni parsear nada.

    Cuenta las unidades y los años, y se queda con la fecha más nueva de
    todo lo que hay debajo --directorios incluidos--. Las dos cosas hacen
    falta: la fecha coge una edición, y el recuento coge lo que una fecha no
    ve. Alguien que mueve `content/` a `content_backup/` deja un índice que
    habla de dos mil unidades que ya no están ahí, y el `content/` vacío que
    queda no es más nuevo que nada.
    """
    newest = 0.0
    units = 0
    years = 0

    for area in (repo_mod.CONTENT, repo_mod.PROBLEMS, repo_mod.COURSES):
        top = os.path.join(root, area)
        if not os.path.isdir(top):
            continue
        for directory, names, files in os.walk(top):
            names[:] = [n for n in names if not n.startswith(".")]
            try:
                when = os.path.getmtime(directory)
            except OSError:
                when = 0.0
            newest = max(newest, when)
            for name in files:
                if name.startswith("."):
                    continue
                if name == repo_mod.UNIT_META:
                    units += 1
                elif name == repo_mod.YEAR_META:
                    years += 1
                try:
                    newest = max(newest, os.path.getmtime(
                        os.path.join(directory, name)))
                except OSError:
                    continue

    return {"units": units, "years": years, "newest": newest or None}


def staleness(root, settings):
    """Si el índice de `generated/` ya no describe lo que hay en el disco.

    Con el motivo en palabras, porque las dos razones se arreglan igual pero
    significan cosas distintas: «has editado algo» y «ya no está lo que el
    índice dice» no son el mismo susto.
    """
    manifest = os.path.join(root, GENERATED, MANIFEST)
    found = survey(root, settings)

    if not os.path.isfile(manifest):
        return {"stale": True, "reason": "no hay índice todavía",
                "disk": found, "indexed": None}

    try:
        with open(manifest, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {"stale": True, "reason": "el índice no se puede leer",
                "disk": found, "indexed": None}

    counts = data.get("counts") or {}
    indexed = {"units": counts.get("units"), "years": counts.get("years"),
               "generated": os.path.getmtime(manifest)}

    if found["units"] != indexed["units"]:
        return {
            "stale": True,
            "reason": "el disco tiene %d unidades y el índice %s"
                      % (found["units"], indexed["units"]),
            "disk": found, "indexed": indexed,
        }
    if found["years"] != indexed["years"]:
        return {
            "stale": True,
            "reason": "el disco tiene %d cursos académicos y el índice %s"
                      % (found["years"], indexed["years"]),
            "disk": found, "indexed": indexed,
        }
    if (found["newest"] or 0) > indexed["generated"]:
        return {
            "stale": True,
            "reason": "se ha editado algo después de generar el índice",
            "disk": found, "indexed": indexed,
        }
    return {"stale": False, "reason": None, "disk": found, "indexed": indexed}


def unchanged(root, data):
    """True when what is on disk already matches ``data`` byte for byte."""
    for name, payload in data.items():
        path = os.path.join(root, GENERATED, name)
        if not os.path.isfile(path):
            return False
        with open(path, encoding="utf-8") as handle:
            if handle.read() != dumps(payload):
                return False
    return True


# --------------------------------------------------------------------------
# Records
# --------------------------------------------------------------------------


def _unit_record(unit, settings, usage):
    """One unit, as an interface needs it.

    Includes the effective translation status per language -- computed, not
    read -- because that is what the library view colours its rows by, and
    computing it per row in a browser would mean hashing every file there.
    """
    reference = unit.languages.get(unit.reference)
    reference_hash = reference.source_hash if reference else None

    languages = {}
    for code in settings.languages:
        entry = unit.languages.get(code)
        if entry is None:
            languages[code] = {"status": "missing", "exists": False}
            continue
        languages[code] = {
            "status": entry.status(unit.reference, reference_hash),
            "exists": bool(entry.exists),
            "bytes": entry.bytes,
        }

    return {
        "id": unit.id,
        "path": unit.relpath,
        "area": unit.relpath.split("/")[0],
        "kind": unit.kind,
        "category": str(unit.category),
        "topic": str(unit.topic),
        # Coerced to text: a folder named `15` gives `topic: 15`, which YAML
        # reads as an integer, and then sorting the category tree compares an
        # int against a string. Everywhere else these are path segments.
        "tags": sorted(str(tag) for tag in (unit.tags or [])),
        "title": {code: unit.titles[code] for code in sorted(unit.titles or {})},
        "reference": unit.reference,
        "languages": languages,
        "prerequisites": sorted(unit.prerequisites or []),
        "objectives": list(unit.objectives or []),
        "durationMinutes": unit.duration_minutes,
        "difficulty": unit.difficulty,
        # Who uses this unit. The reason the index exists at all: an interface
        # cannot answer "is this safe to change?" without it, and answering it
        # means reading every composition in the repository.
        "usedBy": usage.get(unit.relpath, []),
        "warnings": list(unit.warnings or []),
    }


def _course_record(course, settings):
    years = {}
    for year, entry in sorted(course.years.items()):
        years[year] = {
            "year": year,
            "language": entry.language,
            "group": entry.group,
            "documents": [
                {
                    "id": document.id,
                    "kind": document.kind,
                    "language": document.language,
                    "title": {code: document.titles[code]
                              for code in sorted(document.titles or {})},
                    "profiles": list(document.profiles or []),
                    "unitRefs": list(document.unit_refs or []),
                    # La estructura entera, con los apartados. `unitRefs` es
                    # la lista plana de lo que se compila; esto es cómo está
                    # repartido, que es lo que una interfaz enseña para que se
                    # vea dónde empieza cada bloque de un tema.
                    "structure": list(document.structure or []),
                }
                for document in entry.documents
            ],
        }
    return {
        "id": course.id,
        "title": {code: course.titles[code] for code in sorted(course.titles or {})},
        "code": course.code,
        "degree": {code: course.degrees[code]
                   for code in sorted(course.degrees or {})},
        "institution": course.institution,
        "department": {code: course.departments[code]
                       for code in sorted(course.departments or {})},
        "teacher": course.teacher,
        "language": course.language,
        "years": years,
    }


def _usage(courses, units, root):
    """``{unit path: [{course, year, document}]}``.

    Walks every composition once. A reference that resolves to nothing is left
    out rather than recorded against a path that does not exist -- `didacta
    check` is what reports those.
    """
    usage = {}
    for course in courses.values():
        for year, entry in course.years.items():
            for document in entry.documents:
                for ref in document.unit_refs or []:
                    unit = repo_mod.resolve_unit_ref(ref, units, root)
                    if unit is None:
                        continue
                    usage.setdefault(unit.relpath, []).append({
                        "course": course.id,
                        "year": year,
                        "document": document.id,
                    })
    for entries in usage.values():
        entries.sort(key=lambda item: (item["course"], item["year"],
                                       item["document"]))
    return usage


def _categories(unit_records):
    """The category tree, with counts -- enough to draw a filter sidebar."""
    tree = {}
    for record in unit_records:
        category = tree.setdefault(record["category"], {
            "id": record["category"],
            "units": 0,
            "topics": {},
            "kinds": {},
        })
        category["units"] += 1
        category["kinds"][record["kind"]] = \
            category["kinds"].get(record["kind"], 0) + 1
        topic = category["topics"].setdefault(record["topic"], 0)
        category["topics"][record["topic"]] = topic + 1

    out = []
    for category in sorted(tree.values(), key=lambda item: str(item["id"])):
        out.append({
            "id": category["id"],
            "units": category["units"],
            "kinds": dict(sorted(category["kinds"].items())),
            "topics": [{"id": name, "units": category["topics"][name]}
                       for name in sorted(category["topics"], key=str)],
        })
    return out


def _manifest(root, settings, unit_records, course_records, profiles, errors,
              taxonomy=None):
    by_kind = {}
    by_status = {}
    for record in unit_records:
        by_kind[record["kind"]] = by_kind.get(record["kind"], 0) + 1
        for code, entry in record["languages"].items():
            key = "%s:%s" % (code, entry["status"])
            by_status[key] = by_status.get(key, 0) + 1

    documents = sum(len(year["documents"])
                    for course in course_records
                    for year in course["years"].values())

    return {
        "schemaVersion": SCHEMA_VERSION,
        "name": settings.name,
        # No timestamp, deliberately. One was here and it broke the rule this
        # module is built on: with a `generatedAt` in the manifest, two runs
        # over identical content produce different bytes, so `--check` reported
        # the index stale immediately after generating it and every rerun was a
        # diff. When it was generated is what the file's mtime and the commit
        # are for. What a reader actually needs is whether the index matches
        # the content, and that is the hash below.
        "contentHash": content_hash(unit_records, course_records),
        "languages": list(settings.languages),
        "defaultLanguage": settings.default_language,
        "counts": {
            "units": len(unit_records),
            "courses": len(course_records),
            "years": sum(len(course["years"]) for course in course_records),
            "documents": documents,
            "byKind": dict(sorted(by_kind.items())),
            "byLanguageStatus": dict(sorted(by_status.items())),
        },
        "profiles": [
            # Con su nombre legible. Lo deriva el perfil de sus propios ejes,
            # así que ponerlo aquí no es duplicarlo: es lo que evita que una
            # interfaz que lista versiones tenga que inventárselo y acabe
            # enseñando `slides-flat` donde debería decir «Diapositivas (sin
            # pausas)».
            {"id": profile.id, "label": profile.label,
             "family": profile.family,
             "documentClass": profile.document_class}
            for profile in sorted(profiles.values(), key=lambda item: item.id)
        ],
        # La clasificación con la que se etiqueta una unidad, tal como está
        # declarada. Va aquí porque una interfaz que ofrece cambiar la
        # categoría o el tema de un fichero necesita la lista entera, y
        # deducirla de lo que las unidades usan hoy daría una lista que se
        # encoge en cuanto la última unidad de un tema cambia de sitio.
        "taxonomy": (taxonomy or repo_mod.Taxonomy()).as_dict(),
        "blocks": list(repo_mod.BLOCKS),
        "files": sorted([UNITS, COURSES, CATEGORIES]),
        # Whatever `scan_*` complained about, so a reader is not silently
        # served an index built from a repository that does not load cleanly.
        "errors": list(errors),
    }


def content_hash(unit_records, course_records):
    """A hash of what the index describes, ignoring when it was built."""
    digest = hashlib.sha256()
    for payload in (unit_records, course_records):
        digest.update(json.dumps(payload, ensure_ascii=False,
                                 sort_keys=True).encode("utf-8"))
    return digest.hexdigest()[:16]
