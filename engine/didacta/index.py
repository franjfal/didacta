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

from . import identity as identity_mod
from . import profiles as profiles_mod
from . import repo as repo_mod
from . import templates as templates_mod
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
    try:
        degrees = repo_mod.load_degrees(root, settings)
        degree_errors = []
    except (repo_mod.RepoError, yamlio.YamlError) as exc:
        degrees = {}
        degree_errors = [str(exc)]
    courses, course_errors = repo_mod.scan_courses(root, settings, degrees)
    try:
        taxonomy = repo_mod.Taxonomy.load(root, settings)
        taxonomy_errors = []
    except (repo_mod.RepoError, yamlio.YamlError) as exc:
        taxonomy = repo_mod.Taxonomy()
        taxonomy_errors = [str(exc)]
    try:
        declared_templates = templates_mod.load(root, settings)
        template_errors = []
    except (templates_mod.TemplateError, yamlio.YamlError) as exc:
        declared_templates = []
        template_errors = [str(exc)]

    profiles = {}
    if latex_dir and os.path.isdir(latex_dir):
        try:
            profiles = profiles_mod.load(latex_dir)
        except Exception:  # noqa: BLE001 - an index without profiles is still useful
            profiles = {}

    # Un `freezes.yaml` roto no impide abrir el curso, pero tiene que
    # contarse: sin esto el único síntoma es una lista de congelaciones vacía,
    # que es indistinguible de un curso que nadie congeló.
    freeze_errors = [
        "%s: %s" % (year.id, message)
        for course in courses.values()
        for year in course.years.values()
        for message in year.freeze_errors
    ]

    usage = _usage(courses, units, root)

    unit_records = [_unit_record(unit, settings, usage) for unit in
                    sorted(units.values(), key=lambda item: item.relpath)]
    course_records = [_course_record(course, settings) for course in
                      sorted(courses.values(), key=lambda item: item.id)]

    return {
        MANIFEST: _manifest(root, settings, unit_records, course_records,
                            profiles,
                            unit_errors + course_errors + taxonomy_errors
                            + degree_errors + template_errors + freeze_errors,
                            taxonomy=taxonomy, templates=declared_templates),
        UNITS: {"schemaVersion": SCHEMA_VERSION, "units": unit_records},
        COURSES: {
            "schemaVersion": SCHEMA_VERSION,
            # Los documentos compartidos que hay en este repositorio, con las
            # ubicaciones que los dan. Se publica calculado y no se guarda en
            # ninguna parte: el grupo de sincronización **es** el conjunto de
            # ubicaciones que nombran el mismo id, y una lista aparte sería
            # una segunda verdad que puede contradecir a los ficheros --que es
            # exactamente lo que hay que reconciliar después de un merge.
            "shared": _shared(root, courses),
            # Las titulaciones que **este** repositorio declara. La interfaz
            # junta las de todos los que tenga abiertos; una que no declara
            # nadie no agrupa nada, y sus asignaturas salen sueltas.
            "degrees": [degree.as_dict()
                        for degree in sorted(degrees.values(),
                                             key=lambda d: d.id)],
            "courses": course_records,
        },
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

    Los ficheros de la raíz cuentan también, y no por completitud: lo que hay
    en `didacta.yaml`, `taxonomy.yaml`, `degrees.yaml` y `templates.yaml`
    **sale en el índice** --los idiomas del repositorio, las categorías, los
    bloques, las titulaciones, las plantillas-- y no está debajo de ninguno de
    los tres directorios. Sin mirarlos, añadir un idioma y regenerar no
    cambiaba nada, porque el índice no se daba por viejo.
    """
    newest = 0.0
    units = 0
    years = 0
    shared = 0

    for name in (repo_mod.SETTINGS, repo_mod.TAXONOMY, repo_mod.DEGREES_META,
                 templates_mod.TEMPLATES_META):
        try:
            newest = max(newest, os.path.getmtime(os.path.join(root, name)))
        except OSError:
            continue

    # Y los temas compartidos, que están fuera de los tres árboles de abajo
    # y **salen en el índice**: su título, su tipo, sus temas y su composición
    # son los del tema para todos los cursos que lo dan. Sin mirarlos, editar
    # uno y regenerar no cambiaba nada, porque el índice no se daba por viejo.
    for area in (repo_mod.CONTENT, repo_mod.PROBLEMS, repo_mod.COURSES,
                 identity_mod.SHARED):
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
                elif (name.endswith(".yaml")
                      and os.path.basename(directory) == "documents"):
                    shared += 1
                try:
                    newest = max(newest, os.path.getmtime(
                        os.path.join(directory, name)))
                except OSError:
                    continue

    return {"units": units, "years": years, "shared": shared,
            "newest": newest or None}


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
               "shared": counts.get("shared"),
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
    # Solo cuando el índice lo dice. Uno escrito antes de que existieran los
    # temas compartidos no lleva la cuenta, y compararla contra cero diría que
    # está viejo siempre.
    if (indexed["shared"] is not None
            and found["shared"] != indexed["shared"]):
        return {
            "stale": True,
            "reason": "el disco tiene %d tema(s) compartido(s) y el índice %s"
                      % (found["shared"], indexed["shared"]),
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
        # Solo cuando esta apagado. Lo normal no se escribe: el indice lo lee
        # un navegador y repetir `"indent": true` en cada idioma de cada
        # unidad es peso por decir lo que ya se sabe.
        if not entry.indent:
            languages[code]["indent"] = False

    return {
        "id": unit.id,
        "path": unit.relpath,
        "area": unit.relpath.split("/")[0],
        "kind": unit.kind,
        # De qué parte de la asignatura. Distinto del kind: el kind dice qué
        # es el fichero y el bloque, de qué parte forma parte. Una explicación
        # teórica dentro de una práctica de problemas es las dos cosas.
        "block": unit.block,
        # En qué plantillas se compila esta lección. Vacía quiere decir «las
        # de su bloque», que es el caso de casi todas.
        "templates": list(unit.templates),
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
            # Los temas que **este** repositorio declara para este curso. La
            # interfaz junta los de todos los que tenga abiertos; un tema que
            # no declara nadie no agrupa nada, y sus documentos salen sueltos.
            "themes": [theme.as_dict() for theme in entry.themes],
            # Las versiones congeladas de este curso: un commit con nombre
            # cada una. Van en el índice porque la lista se enseña al lado del
            # curso y leer un `freezes.yaml` por año desde la interfaz sería
            # abrir doscientos ficheros para pintar una pantalla.
            "freezes": [item.as_dict() for item in entry.freezes],
            "documents": [
                {
                    "id": document.id,
                    "kind": document.kind,
                    "language": document.language,
                    "title": {code: document.titles[code]
                              for code in sorted(document.titles or {})},
                    "profiles": list(document.profiles or []),
                    # A qué temas pertenece, por id. Puede ser más de uno, y
                    # pueden ser ids que este repositorio no declara.
                    "themes": list(document.themes or []),
                    # De qué entidad de contenido es esta ubicación.
                    # Vacío en un documento que solo se da aquí: no forma
                    # grupo, así que no necesita identidad aparte, y eso es lo
                    # que evita que compartir sea obligatorio para escribir un
                    # curso.
                    "content": document.content,
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
        # En qué idiomas se da. Declarados o, si no, los del repositorio: la
        # interfaz necesita saber de cuáles hablar en **esta** asignatura, no
        # en el repositorio entero.
        "languages": course.taught_in(settings),
        "title": {code: course.titles[code] for code in sorted(course.titles or {})},
        "code": course.code,
        # El id de la titulación, que es lo que agrupa y lo que se filtra.
        # Null cuando la asignatura no dice a cuál pertenece.
        "degreeId": course.degree,
        # Y su título, que es lo que se imprime. Puede venir del registro de
        # grados o escrito a mano en `course.yaml`, y a quien lee el índice le
        # da igual: lo que necesita es el texto.
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
                for position, ref in enumerate(document.unit_refs or []):
                    unit = repo_mod.resolve_unit_ref(ref, units, root)
                    if unit is None:
                        continue
                    usage.setdefault(unit.relpath, []).append({
                        "course": course.id,
                        "year": year,
                        "document": document.id,
                        # Qué posición ocupa dentro de la composición. Hace
                        # falta porque la misma lección puede estar dos veces
                        # en el mismo tema, y entonces son dos ubicaciones:
                        # separar una de la otra sin poder nombrarlas sería
                        # adivinar cuál se tocaba.
                        "index": position,
                        # Cómo está escrita la referencia. La ruta y el id
                        # nombran la misma lección, y quien vaya a reescribir
                        # la línea necesita saber cuál de las dos hay.
                        "ref": ref,
                    })
    for entries in usage.values():
        entries.sort(key=lambda item: (item["course"], item["year"],
                                       item["document"], item["index"]))
    return usage


def _shared(root, courses):
    """Los documentos compartidos y dónde se dan."""
    placements = identity_mod.document_placements(courses)
    found = []
    for content_id in sorted(set(identity_mod.list_shared(root))
                             | set(placements)):
        data = None
        try:
            data = identity_mod.load_shared(root, content_id)
        except identity_mod.IdentityError:
            data = None
        found.append({
            "id": content_id,
            # Que el fichero esté **aquí**. Puede estar en el repositorio de
            # al lado, y entonces esto es False y el documento sale vacío
            # hasta que se abra el otro: es el mismo trato que un tema que
            # declara otro repositorio, y nunca desaparece un curso por eso.
            "declared": data is not None,
            "title": (data or {}).get("title") or {},
            "kind": (data or {}).get("kind") or "",
            "placements": [item.as_dict()
                           for item in placements.get(content_id, [])],
        })
    return found


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
              taxonomy=None, templates=()):
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
        # A cuáles se PUEDE traducir, con el nombre que usa quien los habla.
        # Lo de arriba es a cuáles se traduce aquí, que es otra cosa: la
        # aplicación necesita las dos para ofrecer el idioma que todavía no se
        # usa sin inventarse una lista propia que se quede vieja.
        "availableLanguages": [
            {"code": code, "name": name}
            for code, name, _ in profiles_mod.LANGUAGE_REGISTRY
        ],
        "defaultLanguage": settings.default_language,
        "counts": {
            "units": len(unit_records),
            "courses": len(course_records),
            "years": sum(len(course["years"]) for course in course_records),
            "documents": documents,
            # Los temas compartidos que hay. Se cuenta porque la comprobación
            # de «¿sigue valiendo el índice?» lo mira: uno nuevo no cambia
            # ningún `year.yaml` --lo que cambia es una línea `link:`-- pero
            # sí cambia lo que el índice describe.
            "shared": len(identity_mod.list_shared(root)),
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
        # Con los bloques dentro, que es donde se declaran: un bloque es una
        # clasificación de la unidad, como la categoría y el tema. Estaban
        # aparte, en una lista de dos que escribía el motor, y por eso no se
        # podían ni renombrar ni añadir.
        "taxonomy": (taxonomy or repo_mod.Taxonomy()).as_dict(),
        # Las plantillas que **este** repositorio declara. La aplicación junta
        # las de todos los que tenga abiertos, igual que con los bloques: la
        # teoría y los problemas están repartidos, y el bloque de uno puede
        # compilarse con la plantilla que declara el otro.
        "templates": [template.as_dict() for template in templates],
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
