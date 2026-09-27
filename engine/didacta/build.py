"""The build engine.

Turns one source document into any number of PDFs. This is the part of Didacta
that earns its keep, so a few decisions are worth stating up front.

**Out-of-tree by default.** Auxiliaries and PDFs go to a build directory, never
next to the source. Building in place is how a content repository ends up with
thousands of committed ``.aux`` and ``.log`` files, which is exactly the state
the legacy repository is in.

**SyncTeX always on.** Clicking in the PDF has to jump to the source line. It
is a hard requirement, not a nicety, so it is not a flag.

**latexmk, not a hand-rolled loop.** Cross-references, the table of contents and
the total slide count all need two or three passes, and latexmk already knows
when it has converged. Reimplementing that is a way to ship subtly wrong page
counts.

**One profile, one directory.** Two profiles of the same document share a job
name only by accident; keeping their auxiliaries apart means a parallel build
cannot corrupt itself, and a failed profile leaves the others intact.
"""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from . import inputs as inputs_mod
from . import profiles as profiles_mod
from . import snippets as snippets_mod
from . import templates as templates_mod
from . import yamlio

#: El idioma original en un `unit.yaml`: `reference: va`.
_REFERENCE = re.compile(r"^reference:\s*['\"]?([a-z]{2})['\"]?\s*$", re.M)


class BuildError(RuntimeError):
    pass


#: Los compiladores en marcha, para poder pararlos.
_running = set()

#: En POSIX cada compilador arranca en su propio grupo de procesos: latexmk
#: lanza pdflatex, biber y makeindex, y parar solo a latexmk los dejaría
#: huérfanos escribiendo en la carpeta de salida. Con un grupo se paran todos
#: de una vez.
_OWN_GROUP = os.name == "posix"


def default_workers():
    """Cuántas compilaciones a la vez, si no se dice: min(4, núcleos / 2).

    La mitad de los núcleos y no todos: cada LaTeX come uno entero y bastante
    memoria, y el ordenador tiene que seguir sirviendo para otra cosa mientras
    compila un curso. Y no más de cuatro, que a partir de ahí lo que se gana es
    poco y lo que se pierde, el disco.
    """
    return max(1, min(4, (os.cpu_count() or 2) // 2))


def stop_all():
    """Para todo lo que se esté compilando, con sus hijos.

    Lo llama el manejador de SIGTERM de la orden `didacta`: es lo que hace la
    aplicación al pulsar «Detener».
    """
    for process in list(_running):
        try:
            if _OWN_GROUP:
                os.killpg(process.pid, signal.SIGTERM)
            else:
                process.kill()
        except (ProcessLookupError, PermissionError, OSError):
            pass


# --------------------------------------------------------------------------
# Log parsing
# --------------------------------------------------------------------------


class Diagnostic:
    """One problem LaTeX reported, located well enough to jump to."""

    __slots__ = (
        "severity", "file", "line", "message", "context",
        "path", "unit", "language", "code", "points", "times",
    )

    def __init__(self, severity, message, file=None, line=None, context=None,
                 code=None, points=None, times=1):
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.context = context
        #: Qué es, para quien lo lea con un programa: `overfull-slide` (una
        #: diapositiva que se sale por abajo) u `overfull-line` (una línea que
        #: se sale por la derecha). None en lo demás.
        self.code = code
        #: Cuánto se sale, en puntos, y cuántas veces lo dijo LaTeX: una
        #: diapositiva con cinco capas se sale en sus cinco páginas.
        self.points = points
        self.times = times
        # Dónde está, dicho como lo dice el repositorio y no el log: la ruta
        # desde la raíz y, si es el `.tex` de una lección, cuál y en qué
        # idioma. Lo pone `locate`, que es quien sabe dónde está la raíz.
        self.path = None
        self.unit = None
        self.language = None

    def __str__(self):
        where = self.file or ""
        if self.line:
            where += ":%d" % self.line
        head = "%s %s %s" % (self.severity, where, self.message) if where else \
               "%s %s" % (self.severity, self.message)
        # "Undefined control sequence" says nothing on its own; the context is
        # where the offending macro's name appears.
        if self.context:
            head += "  <- %s" % self.context[:120]
        return head

    def as_dict(self):
        data = {"severity": self.severity, "message": self.message}
        if self.file:
            data["file"] = self.file
        if self.line:
            data["line"] = self.line
        if self.context:
            data["context"] = self.context
        if self.path:
            data["path"] = self.path
        if self.unit:
            data["unit"] = self.unit
            data["language"] = self.language
        if self.code:
            data["code"] = self.code
            data["points"] = self.points
            data["times"] = self.times
        return data


def locate(diagnostics, source_dir, content_root):
    """Dice de qué lección y de qué idioma es cada diagnóstico.

    El log nombra los ficheros como los abrió LaTeX, relativos a la carpeta
    del documento: `../../../content/a/b/c/es.tex`. Eso no se puede pulsar.
    Con la raíz del repositorio --[content_root], relativa a esa carpeta-- se
    convierte en `content/a/b/c/es.tex`, y de ahí en la lección `content/a/b/c`
    en `es`, que es a donde la aplicación lleva al pulsar el error.
    """
    if content_root is None:
        return diagnostics
    root = os.path.normpath(os.path.join(source_dir, content_root))
    for diagnostic in diagnostics:
        if not diagnostic.file:
            continue
        full = diagnostic.file
        if not os.path.isabs(full):
            full = os.path.join(source_dir, full)
        relative = os.path.relpath(os.path.normpath(full), root).replace(os.sep, "/")
        if relative.startswith("../"):
            continue
        diagnostic.path = relative
        parts = relative.split("/")
        if (len(parts) >= 3 and parts[0] in ("content", "problems")
                and parts[-1].endswith(".tex")):
            diagnostic.unit = "/".join(parts[:-1])
            diagnostic.language = parts[-1][:-len(".tex")]
    return diagnostics


#: El nombre que sigue a un `(` cuando LaTeX abre un fichero. Uno con
#: espacios --`(./Teorema de Bolzano - slides - es.aux)`-- no se reconoce, y
#: no hace falta: cuenta como un paréntesis más, que es lo que importa para
#: no descuadrar la pila. Los que se culpan de algo no llevan espacios.
_FILE_AT = re.compile(
    r"(?:\./)?([^()\s]+\.(?:tex|sty|def|cls|cfg|fd|clo|ldf))(?=[\s()]|$)"
)

#: Lo que TeX dice de una caja, seguido de la caja misma hasta una línea en
#: blanco. Lo de dentro es texto compuesto --`[]\T1/cmr/m/n/10 en (a,b`--, y
#: sus paréntesis no abren ni cierran ningún fichero.
_BOX = re.compile(r"^(?:Overfull|Underfull|Tight|Loose) \\[hv]box")
_OVERFULL_VBOX = re.compile(
    r"^Overfull \\vbox \((?P<points>[\d.]+)pt too high\) "
    r"(?:detected at line (?P<line>\d+)|has occurred while \\output is active)"
)
_OVERFULL_HBOX = re.compile(
    r"^Overfull \\hbox \((?P<points>[\d.]+)pt too wide\) "
    r"(?:in (?:paragraph|alignment) at lines (?P<first>\d+)--(?P<last>\d+)"
    r"|detected at line (?P<line>\d+)"
    r"|has occurred while \\output is active)"
)

#: Desde cuánto se avisa de que algo se sale. Menos no se ve: el 80 % de las
#: diapositivas del repositorio real se pasan unas décimas o tres puntos, y
#: avisar de todas enseñaría a no mirar la lista.
OVERFULL_POINTS = 5.0


def _track(line, stack, closed=None):
    """Abre y cierra ficheros en [stack] según los paréntesis de [line].

    En orden, carácter a carácter: `(fichero.sty)(otro.sty` abre dos y cierra
    uno. Contar los `(` y los `)` de la línea entera --como se hacía-- deja
    abierto lo que ya se cerró, y a partir de ahí se culpa de todo a un
    paquete de TikZ. Un `(` que no abre un fichero entra como None, para que
    su `)` no cierre el que sí lo es. Lo que se cierra va a [closed].
    """
    index = 0
    while index < len(line):
        char = line[index]
        if char == "(":
            opened = _FILE_AT.match(line, index + 1)
            if opened:
                stack.append(opened.group(1))
                index = opened.end()
                continue
            stack.append(None)
        elif char == ")" and stack:
            name = stack.pop()
            if closed is not None and name:
                closed.append(name)
        index += 1


#: Un error con `-file-line-error`: `./ruta/es.tex:42: Undefined control
#: sequence.` Con el fichero y la línea dichos por TeX, sin tener que
#: deducirlos contando paréntesis --que un `(` en un mensaje descuadra--.
_FILE_LINE_ERROR = re.compile(
    r"^(?:\./)?(?P<file>[^:\s][^:]*\.(?:tex|sty|def|cls|ldf)):(?P<line>\d+): "
    r"(?P<message>.*)$"
)
_UNDEFINED = re.compile(r"(Reference|Citation) [`']([^']*)' on page")

#: Warnings worth showing. LaTeX emits many that nobody can act on -- an
#: underfull box on a slide is normal -- and surfacing all of them trains the
#: reader to ignore the list.
_INTERESTING_WARNINGS = (
    "Reference",
    "Citation",
    "There were undefined",
    "Label(s) may have changed",
    "No positions in optional float specifier",
    "Marginpar on page",
)

#: Didacta's own warnings are always shown, whatever they say.
#:
#: They were being filtered by the list above, which was a real gap: "no `va`
#: version of this unit, using `es` instead" and "no version of unit X in any
#: language" are the most actionable messages a build produces -- they name a
#: translation that is missing and a reference that does not resolve -- and
#: they were being dropped while `Marginpar on page` was kept.
_OURS = "Package didacta Warning:"


def parse_log(text, overfull=()):
    """Extract diagnostics from a LaTeX log.

    Tracks the file-open stack so an error gets attributed to the content file
    that caused it rather than to the wrapper. That attribution is the whole
    point: an error reported against a generated wrapper is useless.

    [overfull] dice de qué cajas que se salen avisar: `"vbox"`, una
    diapositiva que no cabe --lo que en unos apuntes pasa página y en una
    diapositiva se corta--, y `"hbox"`, una línea que se sale del margen.
    Solo las de más de [OVERFULL_POINTS].
    """
    diagnostics = []
    lines = text.split("\n")
    stack = []
    in_box = False
    # Una diapositiva con capas se sale en cada una de sus páginas, con el
    # mismo fichero y la misma línea: un aviso con cuántas, no cinco.
    boxes = {}
    # El último fichero del autor que se cerró: un párrafo que empieza al
    # final de una lección lo termina quien la incluyó, y TeX avisa cuando
    # la lección ya no está abierta.
    closed = []

    for index, line in enumerate(lines):
        if in_box:
            in_box = bool(line.strip())
            continue
        if _BOX.match(line):
            in_box = True
            _box_warning(line, stack, overfull, boxes, diagnostics, closed)
            continue
        popped = []
        _track(line, stack, popped)
        closed.extend(
            name for name in popped if not name.lower().endswith(_MACHINERY)
        )
        del closed[:-1]
        current = next((name for name in reversed(stack) if name), None)

        located = _FILE_LINE_ERROR.match(line)
        if line.startswith("! ") or located:
            message = (located.group("message") if located else line[2:]).strip()
            number = int(located.group("line")) if located else None
            context = []
            for follow in lines[index + 1 : index + 10]:
                match = re.match(r"^l\.(\d+)\s*(.*)$", follow)
                if match:
                    number = number or int(match.group(1))
                    if match.group(2).strip():
                        context.append(match.group(2).strip())
                    break
                stripped = follow.strip()
                if not stripped:
                    continue
                if stripped.startswith("<"):
                    # `<argument> Tema 3: \chapterName` -- what was being
                    # expanded, which for an undefined control sequence is the
                    # only place the macro's name appears.
                    _tag, _, rest = stripped.partition(">")
                    if rest.strip():
                        context.append(rest.strip())
                    continue
                context.append(stripped)

            # El fichero que dice TeX, si lo dice y no es un paquete; si no, el
            # de la pila, como antes.
            blamed = located.group("file") if located else None
            if blamed is None or blamed.lower().endswith(_MACHINERY):
                blamed = _blame(stack, number) or blamed
            diagnostics.append(
                Diagnostic(
                    "error",
                    message,
                    file=blamed,
                    line=number,
                    context=" ".join(context[:2]) or None,
                )
            )
        elif "LaTeX Warning:" in line or ("Package" in line and "Warning:" in line):
            after = line.split("Warning:", 1)[1].strip()
            ours = _OURS in line
            if ours or any(marker in after for marker in _INTERESTING_WARNINGS):
                diagnostics.append(
                    Diagnostic(
                        "warning",
                        after,
                        # Our own warnings name the unit in the message, which
                        # is more use than a path -- and the file the log
                        # happens to be inside when the warning fires is the
                        # generated injection file, which is nobody's problem.
                        file=None if ours else current,
                    )
                )

    for diagnostic in boxes.values():
        diagnostic.message = _box_message(diagnostic)
    return diagnostics


def _box_warning(line, stack, overfull, boxes, diagnostics, closed=()):
    """Apunta una caja que se sale, si es de las que se avisan."""
    kind = None
    crossed = False
    if "vbox" in overfull:
        match = _OVERFULL_VBOX.match(line)
        if match:
            kind, number = "overfull-slide", match.group("line")
    if kind is None and "hbox" in overfull:
        match = _OVERFULL_HBOX.match(line)
        if match:
            kind = "overfull-line"
            number = match.group("first") or match.group("line")
            # `at lines 49--13`: empezó en la línea 49 de un fichero y acabó
            # en la 13 de otro. Dentro de uno las líneas no van hacia atrás.
            last = match.group("last")
            crossed = bool(match.group("first") and last
                           and int(last) < int(match.group("first")))
    if kind is None:
        return
    points = float(match.group("points"))
    if points <= OVERFULL_POINTS:
        return
    number = int(number) if number else None
    # Del autor aunque la caja se cierre dentro de un paquete: beamer compone
    # la diapositiva al leer el `\end{frame}` de la lección.
    blamed = _blame(stack, number, author=True)
    if crossed and closed:
        blamed = closed[-1]
    key = (kind, blamed, number)
    known = boxes.get(key)
    if known is None:
        known = boxes[key] = Diagnostic(
            "warning", "", file=blamed, line=number, code=kind,
            points=round(points, 1), times=1,
        )
        diagnostics.append(known)
    else:
        known.points = max(known.points, round(points, 1))
        known.times += 1


def _box_message(diagnostic):
    points = diagnostic.points
    amount = ("%.1f" % points).replace(".", ",") if points < 10 else "%.0f" % points
    if diagnostic.code == "overfull-slide":
        message = "La diapositiva se sale por abajo %s pt" % amount
        if diagnostic.times > 1:
            message += " (en %d páginas)" % diagnostic.times
    else:
        message = "Una línea se sale por la derecha %s pt" % amount
        if diagnostic.times > 1:
            message += " (%d veces)" % diagnostic.times
    return message


def frame_starts(diagnostics, source_dir):
    r"""Lleva cada diapositiva que se sale a la línea de su `egin{frame}`.

    LaTeX dice la línea en la que compuso la página, que en beamer es la del
    `\end{frame}`: abrir la lección ahí enseña el final de lo que no cabe, y
    lo que hay que ver es desde dónde empieza.
    """
    for diagnostic in diagnostics:
        if diagnostic.code != "overfull-slide" or not diagnostic.file:
            continue
        if not diagnostic.line:
            continue
        path = diagnostic.file
        if not os.path.isabs(path):
            path = os.path.join(source_dir, path)
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().split("\n")
        except OSError:
            continue
        for number in range(min(diagnostic.line, len(lines)), 0, -1):
            text = _uncommented(lines[number - 1])
            if _BEGIN_FRAME.search(text):
                diagnostic.line = number
                break
            if number < diagnostic.line and _END_FRAME.search(text):
                # El final de la anterior: esta empezaba en otro fichero.
                break
    return diagnostics


_BEGIN_FRAME = re.compile(r"\\begin\s*\{frame\}")
_END_FRAME = re.compile(r"\\end\s*\{frame\}")


def _uncommented(line):
    """La línea sin su comentario: lo que va tras un `%` sin escapar."""
    match = re.search(r"(?<!\\)%", line)
    return line[:match.start()] if match else line


#: A package or class, as opposed to a file the author wrote.
_MACHINERY = (".sty", ".cls", ".def", ".cfg", ".fd", ".clo", ".ldf", ".tex.gz")


def _blame(stack, number, author=False):
    """Which open file an error belongs to.

    A line number in the log comes from the input LaTeX is reading, and errors
    routinely surface deep inside a package: hyperref expands a heading to
    build the PDF bookmark, so a bad macro in a `\section` is reported against
    `nameref.sty`. Blaming the package sends the author to read TeX Live.

    So when the innermost open file is machinery, walk out to the nearest file
    that is not -- the author's document, or a unit it included. Without a
    line number the innermost file is taken as is, unless [author] asks for
    the author's file regardless.
    """
    named = [name for name in stack if name]
    if not named:
        return None
    if number is None and not author:
        return named[-1]
    for name in reversed(named):
        if not name.lower().endswith(_MACHINERY):
            return name
    return named[-1]


def page_count(log_text):
    """Pages written, from the log rather than by reparsing the PDF."""
    match = re.search(r"Output written on .*?\((\d+) pages?", log_text.replace("\n", ""))
    return int(match.group(1)) if match else None


# --------------------------------------------------------------------------
# Result
# --------------------------------------------------------------------------


class BuildResult:
    __slots__ = (
        "document",
        "profile",
        "language",
        "ok",
        "pdf",
        "log",
        "pages",
        "seconds",
        "diagnostics",
        "command",
        "quick",
        "tagged",
    )

    def __init__(self, document, profile, language, ok, pdf=None, log=None,
                 pages=None, seconds=0.0, diagnostics=None, command=None,
                 quick=False, tagged=False):
        self.document = document
        self.profile = profile
        self.language = language
        self.ok = ok
        self.pdf = pdf
        self.log = log
        self.pages = pages
        self.seconds = seconds
        self.diagnostics = diagnostics or []
        self.command = command
        #: Una sola pasada (`--fast`): el índice, las referencias y el total
        #: de diapositivas pueden no estar al día.
        self.quick = quick
        #: Si el PDF salió etiquetado (`--accessible`).
        self.tagged = tagged

    @property
    def errors(self):
        return [d for d in self.diagnostics if d.severity == "error"]

    @property
    def warnings(self):
        return [d for d in self.diagnostics if d.severity == "warning"]

    def as_dict(self):
        data = {
            "document": self.document,
            "profile": self.profile,
            "language": self.language,
            "ok": self.ok,
            "pdf": self.pdf,
            "pages": self.pages,
            "seconds": round(self.seconds, 1),
            "diagnostics": [d.as_dict() for d in self.diagnostics],
        }
        if self.quick:
            data["quick"] = True
        if self.tagged:
            data["tagged"] = True
        return data


# --------------------------------------------------------------------------
# Engine
# --------------------------------------------------------------------------


class Engine:
    """Compiles documents.

    ``latex_dir`` is Didacta's own LaTeX tree; it goes on ``TEXINPUTS`` so a
    content repository never contains a relative path to it. That single change
    removes the ``../../../../Files/`` chains the legacy layout needed, which
    had to be written with a different number of levels depending on where the
    document happened to sit.
    """

    def __init__(self, latex_dir, build_dir, engine="latexmk", verbose=False,
                 on_output=None, template_dirs=(), settings=None,
                 snippets=None, overfull_lines=False, accessible=False):
        self.latex_dir = os.path.abspath(latex_dir)
        self.build_dir = os.path.abspath(build_dir)
        self.engine = engine
        self.verbose = verbose
        #: Called with every line LaTeX writes, as it writes it.
        #:
        #: Exists because a build is the one thing Didacta does that takes
        #: long enough for silence to be a bug: a spinner says «wait», and
        #: the terminal says which file, which pass and which package is
        #: taking the time. Without this the caller only ever saw the parsed
        #: diagnostics, which is the summary of a run it never got to watch.
        self.on_output = on_output
        self.profiles = profiles_mod.load(self.latex_dir)

        #: Si avisar de las líneas que se salen por la derecha en lo que no
        #: son diapositivas. Apagado de salida: en unos apuntes muchas se
        #: salen a propósito --una figura a 1,2 veces el ancho--, y avisar de
        #: todas taparía lo demás. De las diapositivas que se salen por abajo
        #: se avisa siempre: eso se corta al proyectar.
        self.overfull_lines = overfull_lines

        #: PDF accesibles: lo que no son diapositivas, etiquetado y con
        #: LuaLaTeX. Ver `tagged` y `latex/didacta-bootstrap.tex`. Apagado de
        #: salida: compila más despacio y pide el LaTeX de 2025 o posterior.
        self.accessible = accessible

        #: Las plantillas de los directorios abiertos, por encima del registro
        #: que trae Didacta: una plantilla con el mismo id **sustituye** a la
        #: salida de serie. Así se puede cambiar el margen de los apuntes sin
        #: tocar el programa, y quien no declare ninguna compila como siempre.
        #:
        #: Varios directorios porque la teoría y los problemas viven en
        #: repositorios distintos, y el bloque de uno puede usar la plantilla
        #: que declara el otro. Gana el primero que la declare.
        self.template_dirs = [os.path.abspath(d) for d in template_dirs or ()]
        self.templates = templates_mod.load_many(template_dirs, settings)
        for template in self.templates:
            self.profiles[template.id] = template
        self._declared = None

        #: Los snippets del repositorio que se compila, para que LaTeX conozca
        #: los entornos que definen. Los de **este** repositorio y no los de
        #: los demás abiertos, al revés que las plantillas: un snippet se
        #: ofrece donde se declara, y el material que lo usa vive ahí.
        #:
        #: Una lista explícita manda sobre el repositorio: la vista previa
        #: compila la definición que se está escribiendo, no la guardada.
        #: Un `snippets.yaml` roto no para la compilación --puede que nadie
        #: use lo que define--, pero se dice.
        self.snippet_errors = []
        if snippets is not None:
            self.snippets = list(snippets)
        elif settings is not None and getattr(settings, "root", None):
            try:
                self.snippets = snippets_mod.load(settings.root) or []
            except (snippets_mod.SnippetError, yamlio.YamlError) as exc:
                self.snippets = []
                self.snippet_errors.append(str(exc))
        else:
            self.snippets = []
        self._defined = None
        self._settings = settings
        self._references = None

    #: Con varias compilaciones a la vez, cada línea lleva delante de cuál es
    #: --`[slides · es]`--, o el registro sería cuatro LaTeX hablando a la vez.
    _local = threading.local()
    _emitting = threading.Lock()

    def say(self, line):
        """Emit one line of progress, if anybody is listening."""
        if self.on_output:
            self._emit(line)

    def _emit(self, line):
        prefix = getattr(self._local, "prefix", "")
        with self._emitting:
            self.on_output(prefix + line)

    def snippet_definitions(self):
        r"""El fichero con lo que definen los snippets, o None si no definen nada.

        Una vez por motor, como las declaraciones de las plantillas.
        """
        if self._defined is None:
            for message in self.snippet_errors:
                self.say("--- snippets: %s" % message)
            self._defined = snippets_mod.write_definitions(
                os.path.join(self.build_dir, snippets_mod.DEFINITIONS),
                self.snippets,
            ) or ""
        return self._defined or None

    def unit_references(self):
        r"""El fichero con el idioma original de las lecciones que no lo tienen
        en castellano, o None si no hay ninguna.

        Es lo que usa LaTeX para elegir el idioma de reserva de una lección
        que no existe en el que se compila: primero su original, que es de
        donde se tradujeron las demás. Se lee del `reference:` de cada
        `unit.yaml` con una expresión y no con el lector de YAML: son dos mil
        ficheros y lo único que hace falta es una línea.
        """
        if self._references is None:
            self._references = ""
            root = getattr(self._settings, "root", None) if self._settings else None
            found = []
            for area in ("content", "problems"):
                top = os.path.join(root, area) if root else None
                if not top or not os.path.isdir(top):
                    continue
                for directory, names, files in os.walk(top):
                    names[:] = [n for n in names if not n.startswith(".")]
                    if "unit.yaml" not in files:
                        continue
                    try:
                        with open(os.path.join(directory, "unit.yaml"),
                                  encoding="utf-8") as handle:
                            match = _REFERENCE.search(handle.read())
                    except OSError:
                        continue
                    if match and match.group(1) != "es":
                        relative = os.path.relpath(directory, root)
                        found.append((relative.replace(os.sep, "/"),
                                      match.group(1)))
            if found:
                path = os.path.join(self.build_dir, "units", "references.tex")
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write("%% Generado por Didacta: el idioma original "
                                 "de cada lección que no es el castellano.\n")
                    for relative, language in sorted(found):
                        handle.write("\\DidactaUnitReference{%s}{%s}\n"
                                     % (relative, language))
                self._references = path
        return self._references or None

    # -- environment -----------------------------------------------------

    def texinputs(self):
        """``TEXINPUTS`` with Didacta's LaTeX tree ahead of the distribution.

        The trailing empty entry is required: without it the standard search
        path is replaced rather than extended, and nothing at all is found.
        """
        existing = os.environ.get("TEXINPUTS", "")
        parts = [
            self.latex_dir,
            os.path.join(self.latex_dir, "lang"),
            os.path.join(self.latex_dir, "themes"),
        ]
        return os.pathsep.join([p for p in parts if os.path.isdir(p)] + [existing])

    def environment(self):
        env = dict(os.environ)
        env["TEXINPUTS"] = self.texinputs()
        # Long lines in the log keep file paths on one line, which is what the
        # log parser needs to attribute an error to a file.
        env["max_print_line"] = "10000"
        env["error_line"] = "254"
        env["half_error_line"] = "238"
        return env

    def available(self):
        """Whether the toolchain is present, with a message when it is not."""
        tools = [self.engine, "pdflatex"]
        if self.accessible:
            tools.append("lualatex")
        missing = [tool for tool in tools if shutil.which(tool) is None]
        if missing:
            return False, "not installed: %s" % ", ".join(missing)
        return True, None

    def declarations(self):
        r"""El fichero que le dice a LaTeX qué plantillas hay.

        Se escribe una vez por motor y no una por salida: son las mismas
        quince líneas para las treinta compilaciones de un curso.

        None cuando no hay ninguna declarada, y entonces el arranque de LaTeX
        no lee nada y todo compila con el registro de serie -- que es lo que
        hace que esto no pueda romper un repositorio que no usa plantillas.
        """
        if self._declared is None:
            self._declared = templates_mod.write_declarations(
                os.path.join(self.build_dir, templates_mod.DECLARATIONS),
                self.templates,
            ) or ""
        return self._declared or None

    # -- building --------------------------------------------------------

    def output_dir(self, document_id, profile_id, language):
        return os.path.join(
            self.build_dir,
            document_id.replace("/", "_"),
            "%s-%s" % (profile_id, language),
        )

    def build(self, source, profile, language, *, document_id=None,
              document_title=None, content_root=None, keep_aux=True,
              course_keys=None, bibliography=None, tagging=True):
        """Compile one source file in one profile and one language.

        ``source`` is the path to the document's ``.tex``. ``content_root`` is
        where units live, relative to the source's directory -- passed in so
        the document does not have to know. ``bibliography`` is the .bib
        relative to the repository root, for the same reason.

        ``document_title`` and ``course_keys`` come from the structure files,
        and are written to an injection file in the output directory rather
        than squeezed onto the command line. Command-line ``\def`` with braces
        and accents in it is a quoting problem waiting to happen; a file is not.
        """
        if isinstance(profile, str):
            if profile not in self.profiles:
                raise BuildError(
                    "unknown profile %r (known: %s)"
                    % (profile, ", ".join(sorted(self.profiles)))
                )
            profile = self.profiles[profile]
        if language not in profiles_mod.LANGUAGES:
            raise BuildError(
                "unknown language %r (known: %s)"
                % (language, ", ".join(profiles_mod.LANGUAGES))
            )

        source = os.path.abspath(source)
        if not os.path.isfile(source):
            raise BuildError("no such document: %s" % source)

        source_dir = os.path.dirname(source)
        source_name = os.path.basename(source)
        document_id = document_id or os.path.splitext(source_name)[0]
        title = document_title or os.path.splitext(source_name)[0]

        outdir = self.output_dir(document_id, profile.id, language)
        os.makedirs(outdir, exist_ok=True)

        job = profile.output_name(title, language)
        inject = self._write_injection(outdir, title, course_keys)
        tagged = tagging and self.tagged(profile)
        self._write_wrapper(
            outdir,
            self._pretex(profile, language, content_root, inject, bibliography,
                         tagged=tagged),
            source_name,
        )
        command = self._command(
            source_name, job, outdir, profile, language, content_root, inject,
            bibliography, tagged=tagged,
        )

        if self.verbose:
            print("  $ " + " ".join(command))

        quick = self.engine != "latexmk"
        if quick:
            # latexmk apunta en su `.fdb_latexmk` lo que leyó y lo que salió;
            # una pasada suelta cambia el PDF sin que él se entere, y la
            # siguiente compilación entera podría darlo por bueno. Sin el
            # fichero, la siguiente compila.
            try:
                os.remove(os.path.join(outdir, job + ".fdb_latexmk"))
            except OSError:
                pass

        # Qué se está compilando, antes de compilarlo. Un watcher que sólo ve
        # la salida de LaTeX no sabe de cuál de las nueve versiones que pidió
        # es lo que está leyendo.
        self.say("=== %s · %s · %s" % (document_id, profile.id, language))
        self.say("$ " + " ".join(command))

        started = time.time()
        returncode, output = self._execute(command, source_dir)
        elapsed = time.time() - started

        pdf = os.path.join(outdir, job + ".pdf")
        log = os.path.join(outdir, job + ".log")
        log_text = ""
        if os.path.isfile(log):
            with open(log, encoding="utf-8", errors="replace") as handle:
                log_text = handle.read()

        if profile.family == "slides":
            overfull = ("vbox",)
        elif self.overfull_lines:
            overfull = ("hbox",)
        else:
            overfull = ()
        diagnostics = parse_log(log_text, overfull) if log_text else []
        frame_starts(diagnostics, source_dir)
        locate(diagnostics, source_dir, content_root)
        ok = os.path.isfile(pdf) and returncode == 0

        if not ok and not any(d.severity == "error" for d in diagnostics):
            # latexmk failed without LaTeX reporting anything: a missing
            # binary, a permissions problem, a killed process. Surface its own
            # message rather than an empty error list.
            detail = output.strip()
            diagnostics.append(
                Diagnostic("error", detail[-400:] or "%s failed" % self.engine)
            )

        if ok:
            # Lo que entró en este PDF, con su huella: es lo que dice después
            # si se ha quedado viejo, sin fiarse de las fechas.
            fls = os.path.join(outdir, job + ".fls")
            if os.path.isfile(fls):
                root = (os.path.normpath(os.path.join(source_dir, content_root))
                        if content_root is not None else source_dir)
                try:
                    inputs_mod.record(
                        pdf, fls,
                        [root, self.latex_dir, outdir, *self.template_dirs],
                        lesson_root=root,
                        quick=quick,
                    )
                except OSError:
                    pass

        if tagged and not ok:
            # Lo que no se deja etiquetar sale sin etiquetar, y se dice. El
            # etiquetado de LaTeX todavía no admite todo --muchas claves de
            # `enumitem`, algunos paquetes--, y encender los PDF accesibles no
            # puede dejar a nadie sin sus apuntes.
            first = next((d for d in diagnostics if d.severity == "error"),
                         None)
            self.say("--- no se ha podido etiquetar; sin etiquetar")
            plain = self.build(
                source, profile, language, document_id=document_id,
                document_title=document_title, content_root=content_root,
                keep_aux=keep_aux, course_keys=course_keys,
                bibliography=bibliography, tagging=False,
            )
            plain.diagnostics.insert(0, Diagnostic(
                "warning",
                "No se ha podido sacar etiquetado (PDF accesible), así que "
                "sale sin etiquetar%s." % (
                    ": %s" % first.message.strip() if first else ""),
                file=first.file if first else None,
                line=first.line if first else None,
                code="untagged",
            ))
            plain.seconds += elapsed
            return plain

        if not keep_aux and ok:
            self._prune_aux(outdir, job)

        pages = page_count(log_text)
        # Cómo acabó, en la misma corriente que la salida de LaTeX. El
        # resultado estructurado llega después y por otro sitio; quien está
        # mirando el terminal tiene que poder leer aquí que terminó.
        self.say("--- %s · %s%.1fs" % (
            "ok" if ok else "FAIL",
            "%d pages · " % pages if pages else "",
            elapsed,
        ))
        if ok and pdf:
            self.say("--- %s" % pdf)
        for diagnostic in diagnostics:
            if diagnostic.severity == "error" or diagnostic.code:
                self.say("--- %s" % diagnostic)

        return BuildResult(
            document=document_id,
            profile=profile.id,
            language=language,
            ok=ok,
            pdf=pdf if os.path.isfile(pdf) else None,
            log=log if os.path.isfile(log) else None,
            pages=pages,
            seconds=elapsed,
            diagnostics=diagnostics,
            command=command,
            quick=quick,
            tagged=tagged and ok,
        )

    # -- running the compiler -------------------------------------------

    def _execute(self, command, cwd):
        """Run the compiler, and return ``(returncode, combined output)``.

        Streamed line by line when somebody is listening, captured in one go
        when nobody is. The difference matters: a build takes tens of seconds
        and the output is the only thing that says what it is doing, so
        handing it over after the fact is handing over a transcript of a wait
        that already happened.
        """
        env = self.environment()
        if self.on_output is None:
            process = subprocess.Popen(
                command, cwd=cwd, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
                text=True, errors="replace",
                start_new_session=_OWN_GROUP,
            )
            _running.add(process)
            try:
                out, err = process.communicate()
            finally:
                _running.discard(process)
            return process.returncode, (err or out or "")
        if os.name == "posix":
            return self._stream_pty(command, cwd, env)
        return self._stream_pipe(command, cwd, env)

    def _stream_pty(self, command, cwd, env):
        """Stream through a pseudo-terminal, so the output arrives as it happens.

        A plain pipe would be simpler and would be wrong for the purpose. TeX
        writes through the C library, which block-buffers when its output is
        not a terminal: the reader gets 4 KB at a time, so a progress view
        built on a pipe shows nothing for ten seconds and then everything at
        once. Down a pty TeX line-buffers, which is what «in real time»
        actually requires.

        Only on POSIX, because that is where `pty` exists; Windows falls back
        to the pipe and to its buffering.
        """
        import errno
        import pty

        primary, secondary = pty.openpty()
        try:
            process = subprocess.Popen(
                command, cwd=cwd, env=env,
                stdout=secondary, stderr=secondary,
                # Sin entrada: en `nonstopmode` LaTeX no pregunta, pero si
                # alguna vez lo hiciera, en un pty no llega el fin de fichero
                # y la compilación se quedaría esperando para siempre.
                stdin=subprocess.DEVNULL,
                close_fds=True,
                start_new_session=_OWN_GROUP,
            )
        finally:
            os.close(secondary)
        _running.add(process)

        collected = []
        pending = ""
        try:
            while True:
                try:
                    chunk = os.read(primary, 8192)
                except OSError as exc:
                    # El hijo cerró su extremo: así acaba una lectura de pty,
                    # y no es un error.
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                text = chunk.decode("utf-8", "replace")
                collected.append(text)
                pending += text
                *lines, pending = pending.split("\n")
                for line in lines:
                    self._emit(line.rstrip("\r"))
        finally:
            os.close(primary)
            _running.discard(process)
        if pending.strip():
            self._emit(pending.rstrip("\r"))
        process.wait()
        return process.returncode, "".join(collected)

    def _stream_pipe(self, command, cwd, env):
        """Stream through a pipe. Whatever buffering the compiler decides."""
        process = subprocess.Popen(
            command, cwd=cwd, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True, errors="replace", bufsize=1,
            start_new_session=_OWN_GROUP,
        )
        _running.add(process)
        collected = []
        try:
            for line in process.stdout:
                line = line.rstrip("\n").rstrip("\r")
                collected.append(line)
                self._emit(line)
        finally:
            _running.discard(process)
        process.stdout.close()
        process.wait()
        return process.returncode, "\n".join(collected)

    def _write_injection(self, outdir, document_title, course_keys):
        """Write the metadata the structure files know, for LaTeX to \input.

        Returns the path, or None when there is nothing to inject.
        """
        pieces = []
        if course_keys:
            pieces.append("\\DidactaCourse{\n  %s,\n}" % course_keys.rstrip(", "))
        if document_title:
            pieces.append("\\DidactaDocument{%s}" % document_title)
        if not pieces:
            return None

        path = os.path.join(outdir, "didacta-inject.tex")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(
                "%% Generated by Didacta. Do not edit.\n"
                "%% Course and document metadata for this build, taken from\n"
                "%% course.yaml and year.yaml so the source file does not have\n"
                "%% to repeat it in every language.\n"
                + "\n".join(pieces) + "\n"
            )
        return path

    #: El fichero que se compila de verdad, en la carpeta de salida: las
    #: definiciones del perfil y del repositorio, y detrás el documento.
    WRAPPER = "didacta-main.tex"

    def tagged(self, profile):
        """Si [profile] sale etiquetado: con PDF accesibles, todo lo que no
        es beamer. Las diapositivas no, porque el etiquetado de LaTeX todavía
        no admite beamer; lo accesible de una clase son sus apuntes."""
        return self.accessible and profile.document_class != "beamer"

    def _pretex(self, profile, language, content_root, inject=None,
                bibliography=None, tagged=None):
        """Lo que va delante del documento: perfil, idioma, plantillas, etc."""
        pretex = profile.pretex(language, content_root)
        # Lo primero: el arranque lo mira antes de la clase.
        if self.tagged(profile) if tagged is None else tagged:
            pretex = "\\def\\DidactaTagged{}" + pretex
        # Las declaraciones de las plantillas, antes que nada: el arranque las
        # lee para saber qué clase de documento pedir.
        declared = self.declarations()
        if declared:
            pretex += "\\def\\DidactaTemplates{%s}" % os.path.abspath(declared)
        # Y el preámbulo de la que se está compilando, si lo tiene. Lo lee
        # `didacta.sty` al final del suyo, así que puede redefinir lo que
        # Didacta acaba de definir.
        preamble = getattr(profile, "preamble", None)
        if preamble:
            pretex += "\\def\\DidactaPreamble{%s}" % os.path.abspath(preamble)
        # Lo que definen los snippets del repositorio. Lo lee `didacta.sty`
        # justo antes del preámbulo de la plantilla.
        defined = self.snippet_definitions()
        if defined:
            pretex += "\\def\\DidactaSnippets{%s}" % os.path.abspath(defined)
        # El original de cada lección que no lo tiene en castellano, para el
        # idioma de reserva.
        references = self.unit_references()
        if references:
            pretex += ("\\def\\DidactaUnitReferences{%s}"
                       % os.path.abspath(references))
        if bibliography:
            # Relativa a la raíz, como las unidades: el paquete la compone con
            # \DidactaContentRoot, así que el documento no lleva ninguna ruta.
            pretex += "\\def\\DidactaBibliographyFile{%s}" % bibliography
        if inject:
            # Absolute: the working directory is the source's directory, not
            # the output directory.
            pretex += "\\def\\DidactaInjectFile{%s}" % os.path.abspath(inject)
        return pretex

    def _write_wrapper(self, outdir, pretex, source_name):
        """Escribe el `.tex` que se compila: el pretex y el documento.

        En un fichero y no en la orden, que es donde iba: latexmk decide si
        hay que compilar mirando si ha cambiado alguno de los ficheros que
        leyó, y lo que llega por la orden no lo ve. Por eso se forzaba cada
        compilación con `-g`, y un curso entero se recompilaba cada vez aunque
        no hubiera cambiado nada. Escrito aquí, un perfil distinto es un
        fichero distinto y latexmk lo nota; y si todo sigue igual, no compila.

        Se reescribe solo si cambia, para no tocar su fecha por nada.
        """
        path = os.path.join(outdir, self.WRAPPER)
        body = (
            "%% Generado por Didacta: no se edita. Lo que va delante del\n"
            "%% documento --perfil, idioma, plantillas-- y el documento.\n"
            + pretex + "\n"
            + "\\input{%s}\n" % source_name
        )
        try:
            with open(path, encoding="utf-8") as handle:
                if handle.read() == body:
                    return path
        except OSError:
            pass
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body)
        return path

    def _command(self, source_name, job, outdir, profile, language,
                 content_root, inject=None, bibliography=None, tagged=None):
        """La orden que compila. El documento y su pretex van en el `.tex`
        de la carpeta de salida (ver `_write_wrapper`); aquí solo se nombra."""
        wrapper = os.path.join(os.path.abspath(outdir), self.WRAPPER)
        # El PDF etiquetado necesita LuaLaTeX: pdfTeX no sabe escribir el
        # árbol de estructura entero.
        if tagged is None:
            tagged = self.tagged(profile)
        tex = "lualatex" if tagged else "pdflatex"
        if self.engine == "latexmk":
            # Sin `-g`: latexmk compila solo si ha cambiado algo de lo que
            # leyó la vez anterior --una lección, una figura, el perfil--, que
            # es lo que hace que recompilar un curso sin cambios no cueste.
            inner = (
                tex + " %O -interaction=nonstopmode -synctex=1 "
                "-file-line-error %S"
            )
            return [
                "latexmk", "-lualatex" if tex == "lualatex" else "-pdf",
                "-interaction=nonstopmode",
                "-jobname=" + job,
                "-outdir=" + outdir,
                "-%s=%s" % (tex, inner),
                wrapper,
            ]

        # Bare pdflatex, for a quick single pass when cross-references and the
        # slide total do not matter yet.
        return [
            tex,
            "-interaction=nonstopmode",
            "-synctex=1",
            "-file-line-error",
            # El `.fls`, como lo pide latexmk: es lo que dice qué entró en el
            # PDF, y sin él se apuntaría lo de la compilación anterior.
            "-recorder",
            "-jobname=" + job,
            "-output-directory=" + outdir,
            wrapper,
        ]

    #: Auxiliaries worth deleting after a successful build. The PDF and the log
    #: stay: the log is what the UI reports from, and SyncTeX is what makes the
    #: PDF clickable.
    AUX_SUFFIXES = (
        ".aux", ".toc", ".out", ".nav", ".snm", ".vrb",
        ".fls", ".fdb_latexmk", ".bbl", ".blg", ".bcf", ".run.xml",
    )

    def _prune_aux(self, outdir, job):
        for suffix in self.AUX_SUFFIXES:
            path = os.path.join(outdir, job + suffix)
            if os.path.isfile(path):
                try:
                    os.remove(path)
                except OSError:
                    pass

    # -- batches ---------------------------------------------------------

    def build_many(self, jobs, on_result=None, workers=1):
        """Run a list of ``(source, profile, language, kwargs)`` jobs.

        Con [workers] a la vez. Se puede porque cada salida tiene su propia
        carpeta --sus auxiliares, su log, su PDF--, así que dos compilaciones
        del mismo documento en dos versiones no se tocan. Los resultados
        vuelven en el orden de [jobs], acaben en el orden que acaben;
        [on_result] se llama según acaba cada una.
        """
        workers = max(1, int(workers or 1))
        if workers == 1 or len(jobs) < 2:
            results = []
            for job in jobs:
                result = self._build_job(job)
                results.append(result)
                if on_result:
                    on_result(result)
            return results

        # Lo que se calcula una vez por motor, antes de repartir: si no, dos
        # hilos escribirían a la vez el mismo fichero de definiciones.
        self.declarations()
        self.snippet_definitions()
        results = [None] * len(jobs)
        reporting = threading.Lock()

        def run(index, job):
            _source, profile, language, _extra = job
            name = profile if isinstance(profile, str) else profile.id
            self._local.prefix = "[%s · %s] " % (name, language)
            try:
                result = self._build_job(job)
            finally:
                self._local.prefix = ""
            with reporting:
                results[index] = result
                if on_result:
                    on_result(result)

        with ThreadPoolExecutor(max_workers=workers) as pool:
            for future in [pool.submit(run, index, job)
                           for index, job in enumerate(jobs)]:
                future.result()
        return results

    def _build_job(self, job):
        source, profile, language, extra = job
        try:
            return self.build(source, profile, language, **extra)
        except BuildError as exc:
            self.say("--- FAIL %s" % exc)
            return BuildResult(
                document=extra.get("document_id") or os.path.basename(source),
                profile=profile if isinstance(profile, str) else profile.id,
                language=language,
                ok=False,
                diagnostics=[Diagnostic("error", str(exc))],
            )

    def clean(self, document_id=None):
        """Remove build output. Never touches the content repository."""
        target = self.build_dir
        if document_id:
            target = os.path.join(self.build_dir, document_id.replace("/", "_"))
        if os.path.isdir(target):
            shutil.rmtree(target)
            return target
        return None
