"""Un servidor MCP sobre un espacio de trabajo de Didacta.

Para delegar en un LLM parte de lo que se hace a mano: leer una asignatura,
buscar en la biblioteca, traducir una unidad, corregir una errata en las
cuarenta que la repiten. Un modelo que puede *leer* el repositorio propone
cambios a ciegas y hay que aplicarlos a mano; uno que puede leerlo y escribirlo
hace el trabajo y deja el resultado donde se ve, en un fichero y en un commit.

Por qué vive aquí y no en la aplicación. El motor ya es la autoridad sobre lo
que hay en un repositorio --qué es una unidad, qué idiomas tiene, qué cuenta
como pendiente-- y esas respuestas no pueden depender de quién pregunte. Un
servidor que se contestara a sí mismo esas preguntas sería un segundo Didacta
con sus propias ideas, y el día que discreparan nadie sabría cuál manda.

**Qué NO hace, y es deliberado.** No toca git: no hace commit, ni trae, ni
envía. Escribe ficheros, y quien decide qué se envía a GitHub es la persona,
desde la aplicación, viendo el diff. Un modelo que puede publicar es un modelo
que puede publicar un error en el material de un curso que se está dando.

Tampoco lee credenciales. No hay token, ni clave de traducción, ni nada de
`Ajustes` en este proceso; lo único que recibe son rutas de repositorios. Lo
que no está en el proceso no se puede filtrar por una herramienta mal escrita.

El protocolo es JSON-RPC 2.0, escrito a mano por lo mismo que el YAML de este
motor: son cuatro métodos --`initialize`, `tools/list`, `tools/call`, `ping`--
y una dependencia más es una dependencia que hay que tener instalada en cada
máquina donde alguien compile un tema.
"""

from __future__ import annotations

import json
import os
import time

from . import build as build_mod
from . import repo as repo_mod
from . import yamlio

#: La versión del protocolo que esto habla. La manda el cliente en
#: `initialize` y se le devuelve; si pide otra, se le da esta y él decide.
PROTOCOL_VERSION = "2025-06-18"

SERVER_NAME = "didacta"
SERVER_VERSION = "1.0"


class McpError(Exception):
    """Lo que una herramienta no puede hacer, dicho para el modelo.

    Con el mensaje pensado para que quien lo lea sea un modelo que va a
    reintentar: qué pasó y qué tendría que haber mandado, no un rastro de
    pila.
    """

    def __init__(self, message, code=-32000):
        super().__init__(message)
        self.message = message
        self.code = code


class Repository:
    """Un repositorio abierto, con su raíz y si se puede escribir en él.

    La escritura se declara aquí y no se deduce de los permisos del sistema
    de ficheros: se puede tener permiso de escritura sobre el clon del
    material de otra persona y no tener ningún derecho a cambiarlo.
    """

    def __init__(self, root, writable=False, label=None):
        self.root = os.path.abspath(root)
        self.writable = writable
        self.label = label or os.path.basename(self.root)
        self.settings = repo_mod.Settings.load(self.root)

    @property
    def id(self):
        return self.label

    def resolve(self, relative):
        """Una ruta de dentro, comprobada.

        La comprobación que importa de todo este fichero: lo que llega es
        texto de un modelo, y `../../../.ssh/id_rsa` es una ruta relativa
        perfectamente válida. Se normaliza y se exige que siga cayendo bajo la
        raíz; si no, no se abre.
        """
        if os.path.isabs(relative):
            raise McpError("la ruta tiene que ser relativa al repositorio: %r"
                           % relative)
        full = os.path.normpath(os.path.join(self.root, relative))
        if full != self.root and not full.startswith(self.root + os.sep):
            raise McpError("%r se sale del repositorio" % relative)
        return full


class Journal:
    """Lo que el servidor va haciendo, para que se pueda mirar.

    Una línea de JSON por llamada, a un flujo aparte. La aplicación lo lee y
    lo enseña: un servidor que trabaja sobre los ficheros de alguien sin que
    se pueda ver qué toca es un servidor en el que no hay razón para confiar.

    En stderr y no en un fichero: el proceso lo lanza la aplicación, así que
    ya tiene el flujo en la mano, y un fichero habría que decidir dónde
    ponerlo, cuándo rotarlo y quién lo borra.
    """

    def __init__(self, sink=None):
        self._sink = sink

    def record(self, **fields):
        if self._sink is None:
            return
        fields.setdefault("at", time.time())
        try:
            self._sink(json.dumps(fields, ensure_ascii=False))
        except (TypeError, ValueError):
            # Un apunte que no se puede serializar no puede tumbar la llamada
            # que lo produjo: se pierde la línea, no el trabajo.
            pass


class Tool:
    """Una herramienta: lo que el modelo ve y lo que se ejecuta."""

    def __init__(self, name, title, description, schema, handler,
                 writes=False):
        self.name = name
        self.title = title
        self.description = description
        self.schema = schema
        self.handler = handler
        #: Si modifica el repositorio. Lo usa la interfaz para enseñarlas
        #: aparte, y el servidor para negarlas en un repositorio de solo
        #: lectura antes de llegar al disco.
        self.writes = writes

    def as_dict(self):
        return {
            "name": self.name,
            "title": self.title,
            "description": self.description,
            "inputSchema": self.schema,
            "annotations": {
                "title": self.title,
                "readOnlyHint": not self.writes,
                # Nada de esto borra nada: escribir un `.tex` que ya existe lo
                # cambia, y el repositorio es git, así que se recupera.
                "destructiveHint": False,
                "openWorldHint": False,
            },
        }


def text(value):
    """El resultado de una herramienta, como MCP lo espera."""
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False, indent=2)
    return {"content": [{"type": "text", "text": value}]}


# --------------------------------------------------------------------------
# El espacio de trabajo
# --------------------------------------------------------------------------

class Workspace:
    """Los repositorios abiertos, y las preguntas que se hacen sobre ellos.

    Cachea lo escaneado por repositorio porque un modelo hace diez llamadas
    seguidas y rastrear dos mil unidades cada vez convierte una conversación
    en una espera. Se invalida al escribir, que es cuando puede haber
    cambiado algo.
    """

    def __init__(self, repositories):
        if not repositories:
            raise ValueError("un espacio de trabajo sin repositorios")
        self.repositories = list(repositories)
        self._units = {}
        self._courses = {}

    def by_id(self, identifier):
        if identifier is None and len(self.repositories) == 1:
            return self.repositories[0]
        for repository in self.repositories:
            if repository.id == identifier:
                return repository
        raise McpError(
            "no hay ningún repositorio %r; hay: %s"
            % (identifier, ", ".join(r.id for r in self.repositories))
        )

    def writable(self, identifier):
        repository = self.by_id(identifier)
        if not repository.writable:
            raise McpError(
                "%s es de solo lectura: no se puede escribir en material que "
                "no es tuyo" % repository.id
            )
        return repository

    def units(self, repository):
        if repository.id not in self._units:
            found, _ = repo_mod.scan_units(repository.root, repository.settings)
            self._units[repository.id] = found
        return self._units[repository.id]

    def courses(self, repository):
        if repository.id not in self._courses:
            found, _ = repo_mod.scan_courses(
                repository.root, repository.settings)
            self._courses[repository.id] = found
        return self._courses[repository.id]

    def forget(self, repository):
        """Después de escribir: lo cacheado ya no describe lo que hay."""
        self._units.pop(repository.id, None)
        self._courses.pop(repository.id, None)


# --------------------------------------------------------------------------
# Leer
# --------------------------------------------------------------------------

def _repository_dict(repository):
    return {
        "id": repository.id,
        "name": repository.settings.name,
        "writable": repository.writable,
        "languages": list(repository.settings.languages),
        "defaultLanguage": repository.settings.default_language,
    }


def tool_list_repositories(workspace, arguments):
    return text({
        "repositories": [
            _repository_dict(r) for r in workspace.repositories
        ],
        "note": (
            "Una asignatura puede estar repartida entre repositorios. Un "
            "documento y las unidades que llama tienen que estar en el "
            "mismo: la compilación resuelve las rutas bajo una sola raíz."
        ),
    })


def tool_list_courses(workspace, arguments):
    wanted = arguments.get("repository")
    found = []
    for repository in workspace.repositories:
        if wanted and repository.id != wanted:
            continue
        for course in workspace.courses(repository).values():
            found.append({
                "repository": repository.id,
                "id": course.id,
                "title": dict(course.titles or {}),
                "languages": course.taught_in(repository.settings),
                "code": course.code,
                "teacher": course.teacher,
                "years": [
                    {
                        "year": year.year,
                        "language": year.language,
                        "group": year.group,
                        "documents": len(year.documents),
                        "themes": [theme.id for theme in year.themes],
                    }
                    for year in course.years.values()
                ],
            })
    found.sort(key=lambda item: (item["id"], item["repository"]))
    return text({"courses": found})


def _year_of(workspace, repository, course_id, year_id):
    course = workspace.courses(repository).get(course_id)
    if course is None:
        raise McpError(
            "%s no tiene la asignatura %r; hay: %s"
            % (repository.id, course_id,
               ", ".join(sorted(workspace.courses(repository))))
        )
    year = course.years.get(year_id)
    if year is None:
        raise McpError(
            "%s no tiene el curso %r; hay: %s"
            % (course_id, year_id, ", ".join(sorted(course.years)))
        )
    return course, year


def tool_read_course(workspace, arguments):
    repository = workspace.by_id(arguments.get("repository"))
    course, year = _year_of(
        workspace, repository, arguments["course"], arguments["year"])
    return text({
        "repository": repository.id,
        "course": course.id,
        "title": dict(course.titles or {}),
        "year": year.year,
        "language": year.language,
        "themes": [
            {"id": theme.id, "title": dict(theme.titles or {})}
            for theme in year.themes
        ],
        "documents": [
            {
                "id": document.id,
                "kind": document.kind,
                "title": dict(document.titles or {}),
                "language": document.language,
                "themes": list(document.themes or []),
                "profiles": list(document.profiles or []),
                # Las unidades que compone, en orden. Es lo que un modelo
                # necesita para saber qué leer después.
                "units": list(document.unit_refs or []),
            }
            for document in year.documents
        ],
    })


def _unit_dict(unit, settings):
    # El estado lo calcula la unidad, no este fichero: «traducido» y
    # «desactualizado» dependen del hash del original, y tener esa regla en
    # dos sitios es tener dos respuestas para la misma pregunta.
    statuses = unit.statuses()
    return {
        "id": unit.id,
        "path": unit.relpath,
        "reference": unit.reference,
        "kind": unit.kind,
        "block": unit.block,
        "category": unit.category,
        "topic": unit.topic,
        "tags": list(unit.tags or []),
        "title": dict(unit.titles or {}),
        "languages": {
            code: {"exists": entry.exists, "status": statuses.get(code)}
            for code, entry in unit.languages.items()
        },
    }


def tool_search_units(workspace, arguments):
    needle = (arguments.get("query") or "").strip().lower()
    category = arguments.get("category")
    topic = arguments.get("topic")
    tag = arguments.get("tag")
    missing = arguments.get("missingLanguage")
    limit = min(int(arguments.get("limit") or 50), 200)

    found = []
    for repository in workspace.repositories:
        if arguments.get("repository") and \
                repository.id != arguments["repository"]:
            continue
        for unit in workspace.units(repository).values():
            if category and unit.category != category:
                continue
            if topic and unit.topic != topic:
                continue
            if tag and tag not in (unit.tags or []):
                continue
            if missing and missing not in unit.missing_languages:
                continue
            if needle:
                haystack = " ".join([
                    unit.relpath,
                    " ".join(unit.titles.values()),
                    " ".join(unit.tags or []),
                ]).lower()
                if needle not in haystack:
                    continue
            record = _unit_dict(unit, repository.settings)
            record["repository"] = repository.id
            found.append(record)

    found.sort(key=lambda item: item["path"])
    return text({
        "total": len(found),
        "shown": min(len(found), limit),
        "units": found[:limit],
    })


def tool_read_unit(workspace, arguments):
    repository = workspace.by_id(arguments.get("repository"))
    unit = _unit_at(workspace, repository, arguments["path"])
    language = arguments.get("language") or unit.reference

    entry = unit.languages.get(language)
    if entry is None or not entry.exists:
        raise McpError(
            "%s no tiene %s; tiene: %s"
            % (unit.relpath, language,
               ", ".join(unit.available_languages) or "ningún idioma")
        )
    with open(os.path.join(repository.root, entry.path), encoding="utf-8") as f:
        body = f.read()

    record = _unit_dict(unit, repository.settings)
    record["repository"] = repository.id
    record["language"] = language
    record["text"] = body
    return text(record)


def _unit_at(workspace, repository, path):
    units = workspace.units(repository)
    cleaned = (path or "").strip().strip("/")
    for unit in units.values():
        if unit.relpath == cleaned or unit.id == cleaned:
            return unit
    # Una referencia de composición (`analisis/reales/supremo`) sin el árbol
    # delante: es la forma en que se escriben en `year.yaml`, así que es la
    # que un modelo va a mandar después de leer un curso.
    resolved = repo_mod.resolve_unit_ref(cleaned, units, repository.root)
    if resolved is not None:
        return resolved
    raise McpError(
        "no hay ninguna unidad %r en %s. Las rutas son las de "
        "`search_units`, como `content/analisis/reales/supremo`."
        % (path, repository.id)
    )


def tool_translation_status(workspace, arguments):
    language = arguments["language"]
    limit = min(int(arguments.get("limit") or 50), 500)

    pending = []
    for repository in workspace.repositories:
        if arguments.get("repository") and \
                repository.id != arguments["repository"]:
            continue
        if language not in repository.settings.languages:
            continue
        for unit in workspace.units(repository).values():
            entry = unit.languages.get(language)
            if entry is not None and entry.exists:
                continue
            pending.append({
                "repository": repository.id,
                "path": unit.relpath,
                "reference": unit.reference,
                "title": unit.title(),
            })

    pending.sort(key=lambda item: item["path"])
    return text({
        "language": language,
        "total": len(pending),
        "shown": min(len(pending), limit),
        "units": pending[:limit],
    })


# --------------------------------------------------------------------------
# Escribir
#
# Todo lo de aquí abajo toca ficheros de alguien. Tres reglas, y ninguna es
# negociable por conveniencia de una herramienta:
#
#   1. Solo en un repositorio declarado como escribible.
#   2. Solo dentro de su raíz, con la ruta normalizada y comprobada.
#   3. Nunca git. Escribir un fichero se ve en el diff y se puede deshacer;
#      publicar, no.
# --------------------------------------------------------------------------

def _write(path, body):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Con salto final: un `.tex` sin él es una línea que el siguiente diff
    # marca entera aunque nadie la haya tocado.
    if not body.endswith("\n"):
        body += "\n"
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)
    return len(body)


def tool_write_unit(workspace, arguments):
    repository = workspace.writable(arguments.get("repository"))
    language = arguments["language"]
    if language not in repository.settings.languages:
        raise McpError(
            "%s no se traduce a %s; se traduce a: %s"
            % (repository.id, language,
               ", ".join(repository.settings.languages))
        )

    unit = _unit_at(workspace, repository, arguments["path"])
    target = repository.resolve("%s/%s.tex" % (unit.relpath, language))
    existed = os.path.isfile(target)
    written = _write(target, arguments["text"])
    workspace.forget(repository)

    return text({
        "repository": repository.id,
        "path": "%s/%s.tex" % (unit.relpath, language),
        "created": not existed,
        "bytes": written,
        "note": (
            "Escrito en disco, sin commit. Se ve en la aplicación y se envía "
            "desde allí, que es donde alguien mira el diff antes de publicar."
        ),
    })


#: La plantilla de una unidad nueva. Deliberadamente mínima: lo que hace falta
#: para que compile y para que se encuentre.
NEW_UNIT_YAML = """\
# %(title)s
kind: %(kind)s
block: %(block)s
title:
  %(language)s: %(quoted)s
%(pending)sreference: %(language)s
"""


def tool_create_unit(workspace, arguments):
    repository = workspace.writable(arguments.get("repository"))
    area = arguments.get("area") or repo_mod.CONTENT
    if area not in (repo_mod.CONTENT, repo_mod.PROBLEMS):
        raise McpError("el área es `content` o `problems`, no %r" % area)

    language = arguments.get("language") or repository.settings.default_language
    if language not in repository.settings.languages:
        raise McpError(
            "%s no se traduce a %s" % (repository.id, language))

    wanted = (arguments["path"] or "").strip()
    if os.path.isabs(wanted):
        # Quitarle la barra y seguir la convertiría en `content/etc/didacta`,
        # que está dentro del repositorio y no es lo que nadie quiso decir.
        # Un modelo que manda una ruta absoluta está confundido, y crearle
        # algo en un sitio raro esconde la confusión.
        raise McpError(
            "la ruta tiene que ser relativa al área, no absoluta: %r" % wanted)
    relpath = "%s/%s" % (area, wanted.strip("/"))
    directory = repository.resolve(relpath)
    if os.path.isdir(directory) and os.listdir(directory):
        raise McpError(
            "ya hay algo en %s. Para cambiar una unidad que existe, "
            "`write_unit`." % relpath
        )

    title = arguments["title"]
    pending = "".join(
        "  # TODO: %s\n" % code
        for code in repository.settings.languages
        if code != language
    )
    meta = NEW_UNIT_YAML % {
        "title": title,
        "kind": arguments.get("kind") or "theory",
        "block": arguments.get("block") or "theory",
        "language": language,
        "quoted": yamlio._fmt(title),
        "pending": pending,
    }
    _write(os.path.join(directory, "unit.yaml"), meta)
    _write(os.path.join(directory, "%s.tex" % language), arguments["text"])
    workspace.forget(repository)

    return text({
        "repository": repository.id,
        "path": relpath,
        "reference": "/".join(relpath.split("/")[1:]),
        "files": ["unit.yaml", "%s.tex" % language],
        "note": (
            "Existe, pero todavía no la usa nadie: una unidad entra en un "
            "documento por su `year.yaml`, y eso se hace desde la aplicación."
        ),
    })


def tool_set_unit_metadata(workspace, arguments):
    repository = workspace.writable(arguments.get("repository"))
    unit = _unit_at(workspace, repository, arguments["path"])
    path = repository.resolve("%s/unit.yaml" % unit.relpath)

    data = yamlio.load_file(path) if os.path.isfile(path) else {}
    data = dict(data or {})

    titles = arguments.get("title")
    if titles:
        merged = dict(data.get("title") or {})
        for code, value in titles.items():
            if code not in repository.settings.languages:
                raise McpError("%s no se traduce a %s" % (repository.id, code))
            if (value or "").strip():
                merged[code] = value.strip()
            else:
                merged.pop(code, None)
        if not merged:
            raise McpError("una unidad sin título en ningún idioma")
        data["title"] = merged

    for key in ("kind", "block", "category", "topic"):
        if arguments.get(key):
            data[key] = arguments[key]
    if arguments.get("tags") is not None:
        data["tags"] = list(arguments["tags"])

    _write(path, yamlio.dumps(data))
    workspace.forget(repository)
    return text({
        "repository": repository.id,
        "path": "%s/unit.yaml" % unit.relpath,
        "title": dict(data.get("title") or {}),
        "warning": (
            "`unit.yaml` se ha vuelto a escribir entero: los comentarios que "
            "tuviera no están. Para el texto usa `write_unit`, que respeta el "
            "fichero."
        ),
    })


# --------------------------------------------------------------------------
# Comprobar y compilar
# --------------------------------------------------------------------------

def tool_check(workspace, arguments):
    """Que el modelo pueda comprobar su propio trabajo."""
    found = []
    for repository in workspace.repositories:
        if arguments.get("repository") and \
                repository.id != arguments["repository"]:
            continue
        _, unit_errors = repo_mod.scan_units(
            repository.root, repository.settings)
        _, course_errors = repo_mod.scan_courses(
            repository.root, repository.settings)
        units = workspace.units(repository)
        broken = []
        for course in workspace.courses(repository).values():
            for year in course.years.values():
                for document in year.documents:
                    for ref in document.unit_refs or []:
                        if repo_mod.resolve_unit_ref(
                                ref, units, repository.root) is None:
                            broken.append({
                                "course": course.id,
                                "year": year.year,
                                "document": document.id,
                                "reference": ref,
                            })
        found.append({
            "repository": repository.id,
            "errors": list(unit_errors) + list(course_errors),
            "brokenReferences": broken,
            "ok": not (unit_errors or course_errors or broken),
        })
    return text({"repositories": found})


def tool_build_document(workspace, arguments, latex_dir=None):
    """Compila **un** documento, en un perfil y un idioma.

    Uno y no un curso entero a propósito: un curso son cuarenta salidas y
    media hora, y una llamada de herramienta que tarda media hora es una
    conversación colgada. Esto existe para lo que hace falta de verdad
    --comprobar que una traducción recién escrita sigue compilando-- y eso
    son unos segundos.
    """
    if latex_dir is None:
        raise McpError("este servidor se lanzó sin LaTeX: no puede compilar")
    repository = workspace.by_id(arguments.get("repository"))
    course, year = _year_of(
        workspace, repository, arguments["course"], arguments["year"])

    document = next(
        (d for d in year.documents if d.id == arguments["document"]), None)
    if document is None:
        raise McpError(
            "%s@%s no tiene el documento %r; hay: %s"
            % (course.id, year.year, arguments["document"],
               ", ".join(d.id for d in year.documents))
        )

    engine = build_mod.Engine(
        latex_dir=latex_dir,
        build_dir=os.path.join(repository.root, repository.settings.build_dir),
    )
    language = arguments.get("language") or document.language
    profile = arguments.get("profile") or (document.profiles or ["notes"])[0]

    try:
        result = engine.build(
            document.source, profile, language,
            bibliography=repository.settings.bibliography_path,
        )
    except build_mod.BuildError as exc:
        raise McpError("no compila: %s" % exc)

    return text({
        "repository": repository.id,
        "document": document.id,
        "profile": profile,
        "language": language,
        "ok": bool(result.ok),
        "pages": result.pages,
        "pdf": result.pdf,
        "seconds": round(result.seconds, 1),
        # Los diagnósticos de LaTeX, que es lo que un modelo necesita para
        # arreglar lo que acaba de escribir. Recortados: un log de LaTeX son
        # cinco mil líneas y casi todas son nombres de fuentes.
        "diagnostics": [
            {
                "severity": d.severity,
                "message": d.message,
                "file": d.file,
                "line": d.line,
            }
            for d in (result.diagnostics or [])[:20]
        ],
    })


# --------------------------------------------------------------------------
# El catálogo de herramientas
#
# Las descripciones son para un modelo, no para una página de manual: dicen
# cuándo usar cada una y qué NO hace, porque lo segundo es lo que evita que
# intente algo que no puede y se invente el resultado.
# --------------------------------------------------------------------------

def _string(description, **extra):
    field = {"type": "string", "description": description}
    field.update(extra)
    return field


def build_tools(latex_dir=None):
    repository_field = _string(
        "El repositorio. Con uno solo abierto se puede omitir; "
        "`list_repositories` los enumera."
    )

    tools = [
        Tool(
            "list_repositories", "Repositorios abiertos",
            "Qué repositorios de contenido hay abiertos, en cuáles se puede "
            "escribir y a qué idiomas se traduce cada uno. Empieza por aquí: "
            "el resto de herramientas piden un repositorio.",
            {"type": "object", "properties": {}},
            tool_list_repositories,
        ),
        Tool(
            "list_courses", "Asignaturas",
            "Las asignaturas y sus cursos académicos, con sus idiomas y "
            "cuántos documentos tiene cada año. Una misma asignatura puede "
            "salir en dos repositorios: está repartida, y es normal.",
            {
                "type": "object",
                "properties": {"repository": repository_field},
            },
            tool_list_courses,
        ),
        Tool(
            "read_course", "Un curso académico",
            "Los temas y los documentos de un curso, con las unidades que "
            "compone cada documento y en qué orden. Es el mapa de lo que se "
            "da: de aquí salen las rutas para `read_unit`.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "course": _string("Id de la asignatura, p. ej. `am-i`."),
                    "year": _string("Curso académico, p. ej. `2026-2027`."),
                },
                "required": ["course", "year"],
            },
            tool_read_course,
        ),
        Tool(
            "search_units", "Buscar en la biblioteca",
            "Busca unidades por texto, categoría, tema, etiqueta o por el "
            "idioma que les falta. Una unidad es un trozo reutilizable de "
            "material --una definición, un teorema, un ejercicio-- y la misma "
            "puede estar en varias asignaturas: corregir una errata aquí la "
            "corrige en todas.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "query": _string("Texto libre: ruta, título o etiqueta."),
                    "category": _string("Filtra por categoría."),
                    "topic": _string("Filtra por tema de la taxonomía."),
                    "tag": _string("Filtra por etiqueta."),
                    "missingLanguage": _string(
                        "Solo las que NO tienen este idioma. Es la forma de "
                        "encontrar qué hay que traducir."
                    ),
                    "limit": {
                        "type": "integer",
                        "description": "Cuántas devolver (máximo 200).",
                    },
                },
            },
            tool_search_units,
        ),
        Tool(
            "read_unit", "Leer una unidad",
            "El LaTeX de una unidad en un idioma, con sus metadatos. Para "
            "traducir, lee primero el idioma de referencia: es el original, y "
            "el que dice qué hay que decir.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "path": _string(
                        "`content/analisis/reales/supremo`, o la referencia "
                        "sin el árbol como aparece en un documento."
                    ),
                    "language": _string(
                        "Por defecto, el idioma de referencia de la unidad."
                    ),
                },
                "required": ["path"],
            },
            tool_read_unit,
        ),
        Tool(
            "translation_status", "Qué falta por traducir",
            "Las unidades que no tienen todavía un idioma. La lista de "
            "trabajo de una traducción, ordenada por ruta.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "language": _string("El idioma que falta, p. ej. `va`."),
                    "limit": {"type": "integer"},
                },
                "required": ["language"],
            },
            tool_translation_status,
        ),
        Tool(
            "write_unit", "Escribir una unidad",
            "Escribe el LaTeX de una unidad en un idioma; si ese idioma no "
            "existía, lo crea. Es la herramienta de traducir y la de corregir."
            "\n\nDeja el fichero escrito, **sin commit**: quien decide qué se "
            "publica es la persona, desde la aplicación, viendo el diff. "
            "Conserva la estructura del original --los entornos, las "
            "etiquetas de `\\label`, las fórmulas-- o las referencias del "
            "tema dejan de resolver.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "path": _string("La unidad, como en `read_unit`."),
                    "language": _string("En qué idioma se escribe."),
                    "text": _string("El LaTeX completo del fichero."),
                },
                "required": ["path", "language", "text"],
            },
            tool_write_unit,
            writes=True,
        ),
        Tool(
            "create_unit", "Crear una unidad",
            "Una unidad nueva: su carpeta, su `unit.yaml` y su primer `.tex`. "
            "Queda creada pero no la usa nadie todavía; meterla en un "
            "documento se hace desde la aplicación, donde se ve el orden.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "path": _string(
                        "Ruta dentro del área, p. ej. "
                        "`analisis/reales/densidad-de-Q`."
                    ),
                    "area": _string(
                        "`content` para teoría, `problems` para ejercicios.",
                        enum=[repo_mod.CONTENT, repo_mod.PROBLEMS],
                    ),
                    "title": _string("El título, en el idioma que se escribe."),
                    "text": _string("El LaTeX de la unidad."),
                    "language": _string("Por defecto, el del repositorio."),
                    "kind": _string("`theory`, `example`, `problem`…"),
                    "block": _string("El bloque al que pertenece."),
                },
                "required": ["path", "title", "text"],
            },
            tool_create_unit,
            writes=True,
        ),
        Tool(
            "set_unit_metadata", "Metadatos de una unidad",
            "Cambia el título por idioma, la categoría, el tema o las "
            "etiquetas de una unidad.\n\nReescribe `unit.yaml` entero, así "
            "que los comentarios que tuviera se pierden. Para el texto usa "
            "`write_unit`, que no toca el resto del fichero.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "path": _string("La unidad, como en `read_unit`."),
                    "title": {
                        "type": "object",
                        "description":
                            "Título por idioma. Un valor vacío lo quita.",
                        "additionalProperties": {"type": "string"},
                    },
                    "kind": _string("El tipo de unidad."),
                    "block": _string("El bloque."),
                    "category": _string("La categoría."),
                    "topic": _string("El tema de la taxonomía."),
                    "tags": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Sustituye las etiquetas enteras.",
                    },
                },
                "required": ["path"],
            },
            tool_set_unit_metadata,
            writes=True,
        ),
        Tool(
            "check", "Comprobar el repositorio",
            "Valida lo que hay: metadatos que no se leen y documentos que "
            "llaman a unidades que no existen. Rápido. Úsalo después de "
            "escribir, antes de dar nada por hecho.",
            {
                "type": "object",
                "properties": {"repository": repository_field},
            },
            tool_check,
        ),
    ]

    if latex_dir:
        tools.append(Tool(
            "build_document", "Compilar un documento",
            "Compila **un** documento en un perfil y un idioma, y devuelve "
            "los errores de LaTeX si los hay. Para comprobar que lo que "
            "acabas de escribir sigue compilando.\n\nUno solo: un curso "
            "entero son cuarenta salidas y media hora. Eso se hace desde la "
            "aplicación, que enseña por dónde va.",
            {
                "type": "object",
                "properties": {
                    "repository": repository_field,
                    "course": _string("Id de la asignatura."),
                    "year": _string("Curso académico."),
                    "document": _string("Id del documento."),
                    "profile": _string("Por defecto, el primero suyo."),
                    "language": _string("Por defecto, el del documento."),
                },
                "required": ["course", "year", "document"],
            },
            lambda workspace, arguments: tool_build_document(
                workspace, arguments, latex_dir=latex_dir),
        ))

    return {tool.name: tool for tool in tools}


#: Lo que el servidor le dice al modelo nada más conectarse.
#:
#: Las reglas que no se deducen leyendo el repositorio, y que son justo las que
#: rompen una asignatura si se ignoran.
INSTRUCTIONS = """\
Didacta es un sistema de material docente en LaTeX. El material se reparte en
unidades --una definición, un teorema, un ejercicio-- que se reutilizan entre
asignaturas: corregir una errata en una unidad la corrige en todos los cursos
que la usan.

Cómo está organizado:

  * el **idioma es el nombre del fichero**: `es.tex`, `va.tex`, `en.tex` en la
    carpeta de la unidad. Que falte uno quiere decir que no está traducida;
  * un **documento** (un tema, una hoja de problemas) no tiene texto propio:
    es una composición que nombra unidades en orden, en el `year.yaml` de su
    curso;
  * los **temas** agrupan documentos y se declaran aparte.

Dos reglas que no se ven leyendo un fichero:

  1. Un documento y las unidades que llama viven en el **mismo repositorio**.
     LaTeX resuelve las rutas bajo una sola raíz, así que un documento que
     llama a una unidad de otro repositorio compila en la máquina que tiene
     los dos abiertos y no compila en la de quien solo tiene uno.
  2. Lo que se escribe aquí **no se publica**. Queda en disco; la persona lo
     ve en la aplicación y decide qué enviar. No hay ninguna herramienta que
     haga commit, y no es un olvido.

Al traducir: conserva la estructura del original. Las fórmulas, los entornos y
sobre todo las claves de `\\label`, `\\ref` y `\\cite` no se traducen --son
identificadores, no palabras--, y traducir una rompe todas las referencias del
tema en silencio. Traduce la prosa y deja la sintaxis donde estaba.
"""


# --------------------------------------------------------------------------
# El protocolo
# --------------------------------------------------------------------------

class Server:
    """Un servidor MCP sobre un espacio de trabajo.

    Sin transporte: recibe peticiones ya decodificadas y devuelve respuestas.
    Así lo mismo sirve por stdio --cuando lo lanza un cliente-- que por HTTP
    --cuando lo lanza la aplicación-- y los tests no necesitan ni un proceso
    ni un puerto.
    """

    def __init__(self, workspace, latex_dir=None, journal=None):
        self.workspace = workspace
        self.tools = build_tools(latex_dir)
        self.journal = journal or Journal()
        #: Quién se ha conectado, si lo ha dicho. Para poder enseñarlo.
        self.client = None
        self.calls = 0

    # -- despacho ----------------------------------------------------------

    def handle(self, request):
        """Una petición JSON-RPC. Devuelve la respuesta, o None si es aviso.

        Un aviso --una petición sin `id`-- no se contesta nunca, ni siquiera
        para decir que no se entendió: es lo que dice JSON-RPC y lo que
        esperan los clientes, que se quedan colgados si les llega una
        respuesta que no pidieron.
        """
        if not isinstance(request, dict):
            return _error(None, -32600, "una petición es un objeto JSON")

        identifier = request.get("id")
        method = request.get("method")
        params = request.get("params") or {}
        notification = "id" not in request

        try:
            if method == "initialize":
                result = self._initialize(params)
            elif method == "tools/list":
                result = {
                    "tools": [
                        self.tools[name].as_dict() for name in self.tools
                    ]
                }
            elif method == "tools/call":
                result = self._call(params)
            elif method == "ping":
                result = {}
            elif method in ("notifications/initialized", "notifications/cancelled"):
                return None
            else:
                if notification:
                    return None
                return _error(identifier, -32601, "no existe el método %r" % method)
        except McpError as exc:
            if notification:
                return None
            return _error(identifier, exc.code, exc.message)
        except Exception as exc:  # pragma: no cover - red de seguridad
            # Una herramienta que revienta no puede tumbar el servidor: el
            # modelo está a mitad de una tarea y lo que necesita es el error,
            # no un socket cerrado.
            self.journal.record(event="crash", error=str(exc))
            if notification:
                return None
            return _error(identifier, -32603, "fallo interno: %s" % exc)

        if notification:
            return None
        return {"jsonrpc": "2.0", "id": identifier, "result": result}

    def _initialize(self, params):
        info = params.get("clientInfo") or {}
        self.client = info.get("name") or "desconocido"
        self.journal.record(
            event="connected",
            client=self.client,
            version=info.get("version"),
        )
        return {
            # La que pida el cliente si la conocemos, y si no la nuestra: es
            # lo que dice la especificación, y negociar a la baja es mejor que
            # negarse a hablar.
            "protocolVersion": params.get("protocolVersion") or PROTOCOL_VERSION,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            "instructions": INSTRUCTIONS,
        }

    def _call(self, params):
        name = params.get("name")
        arguments = params.get("arguments") or {}
        tool = self.tools.get(name)
        if tool is None:
            # Error de protocolo y no resultado con `isError`: lo dice MCP, y
            # tiene sentido --que la herramienta no exista es un fallo del
            # cliente, no del trabajo--. El mensaje lleva la lista dentro,
            # que es lo que permite al modelo corregirse al verlo.
            self.journal.record(event="call", tool=name, ok=False,
                                error="no existe esa herramienta")
            raise McpError(
                "no existe la herramienta %r; hay: %s"
                % (name, ", ".join(self.tools)),
                code=-32602,
            )

        started = time.time()
        try:
            result = tool.handler(self.workspace, arguments)
        except McpError as exc:
            self.calls += 1
            self.journal.record(
                event="call", tool=name, ok=False,
                ms=int((time.time() - started) * 1000),
                arguments=_summarise(arguments), error=exc.message,
            )
            # Un error de herramienta va **dentro** del resultado, no como
            # error de JSON-RPC: es algo que el modelo puede leer y corregir,
            # y un error de protocolo lo esconde del modelo.
            out = text("Error: %s" % exc.message)
            out["isError"] = True
            return out
        except KeyError as exc:
            self.calls += 1
            message = "falta el argumento %s" % exc
            self.journal.record(
                event="call", tool=name, ok=False,
                ms=int((time.time() - started) * 1000), error=message,
            )
            out = text("Error: %s" % message)
            out["isError"] = True
            return out

        self.calls += 1
        self.journal.record(
            event="call", tool=name, ok=True, writes=tool.writes,
            ms=int((time.time() - started) * 1000),
            arguments=_summarise(arguments),
        )
        return result


def _summarise(arguments):
    """Los argumentos, sin el cuerpo de un fichero.

    Un `write_unit` lleva el `.tex` entero dentro: apuntarlo en el registro
    llenaría la pantalla de la aplicación con el texto de una unidad cada vez
    que se escribe una. Lo que hace falta ver es qué se tocó, no con qué.
    """
    out = {}
    for key, value in (arguments or {}).items():
        if isinstance(value, str) and len(value) > 120:
            out[key] = "%s… (%d caracteres)" % (value[:60], len(value))
        else:
            out[key] = value
    return out


def _error(identifier, code, message):
    return {
        "jsonrpc": "2.0",
        "id": identifier,
        "error": {"code": code, "message": message},
    }


# --------------------------------------------------------------------------
# Transportes
# --------------------------------------------------------------------------

def serve_stdio(server, stdin, stdout):
    """Una línea de JSON por mensaje, que es lo que MCP usa sobre stdio.

    Para clientes que lanzan el servidor ellos mismos. Nada se escribe en
    stdout que no sea una respuesta: ahí hay un programa esperando JSON, y una
    traza suelta le rompe la sesión. El registro va por stderr.
    """
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except ValueError:
            stdout.write(json.dumps(_error(None, -32700, "JSON ilegible")) + "\n")
            stdout.flush()
            continue
        response = server.handle(request)
        if response is None:
            continue
        stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
        stdout.flush()
    return 0


def http_handler_class(server):
    """El manejador HTTP, construido alrededor de un servidor ya montado."""
    from http.server import BaseHTTPRequestHandler

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _send(self, status, payload, content_type="application/json"):
            body = payload.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type + "; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):  # noqa: N802 - lo nombra la biblioteca
            # Para poder comprobar desde la aplicación que está vivo sin
            # hablar el protocolo.
            if self.path in ("/health", "/"):
                self._send(200, json.dumps({
                    "server": SERVER_NAME,
                    "version": SERVER_VERSION,
                    "protocol": PROTOCOL_VERSION,
                    "tools": sorted(server.tools),
                    "repositories": [
                        _repository_dict(r) for r in server.workspace.repositories
                    ],
                    "calls": server.calls,
                    "client": server.client,
                }, ensure_ascii=False))
                return
            self._send(404, json.dumps({"error": "no hay nada en %s" % self.path}))

        def _body(self):
            """El cuerpo de la petición, venga como venga.

            Con `Content-Length` o troceado. Lo segundo hace falta porque no
            todos los clientes miden el cuerpo antes de mandarlo --el
            `HttpClient` de Dart no lo hace-- y sin esto se leen cero bytes,
            el JSON no se entiende y la llamada falla diciendo que el JSON es
            ilegible, que manda a buscar el problema al sitio equivocado.
            """
            if (self.headers.get("Transfer-Encoding") or "").lower() == "chunked":
                chunks = []
                while True:
                    line = self.rfile.readline().strip()
                    if not line:
                        break
                    try:
                        size = int(line.split(b";")[0], 16)
                    except ValueError:
                        break
                    if size == 0:
                        self.rfile.readline()
                        break
                    chunks.append(self.rfile.read(size))
                    self.rfile.readline()
                return b"".join(chunks)
            length = int(self.headers.get("Content-Length") or 0)
            return self.rfile.read(length) if length else b""

        def do_POST(self):  # noqa: N802
            raw = self._body()
            try:
                request = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                self._send(400, json.dumps(_error(None, -32700, "JSON ilegible")))
                return

            # Un lote: JSON-RPC lo permite y algún cliente lo usa al arrancar.
            if isinstance(request, list):
                out = [r for r in (server.handle(item) for item in request)
                       if r is not None]
                self._send(200, json.dumps(out, ensure_ascii=False))
                return

            response = server.handle(request)
            if response is None:
                # Un aviso no se contesta. 202 y cuerpo vacío es lo que dice
                # el transporte HTTP de MCP.
                self.send_response(202)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._send(200, json.dumps(response, ensure_ascii=False))

        def log_message(self, *args):
            # Silencio: el registro de esto es el diario, que dice qué
            # herramienta se llamó, no qué byte llegó por el socket.
            pass

    return Handler


def serve_http(server, host="127.0.0.1", port=0, on_ready=None):
    """En local y nada más.

    A `127.0.0.1` a propósito y sin opción de cambiarlo: esto escribe en los
    ficheros de alguien sin pedir contraseña, y un servidor así escuchando en
    la red de un departamento es una mala tarde.
    """
    from http.server import ThreadingHTTPServer

    httpd = ThreadingHTTPServer((host, port), http_handler_class(server))
    if on_ready is not None:
        on_ready(httpd.server_address[1])
    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()
    return 0
