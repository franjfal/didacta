"""Revisar el material: lo que compila, o casi, y está mal.

`didacta check` miraba la estructura --que cada referencia exista, que la
clasificación apunte a algo--; esto mira **lo que hay escrito**, que es donde
están los fallos que se descubren delante de la clase: una orden que solo
existe en castellano copiada en el valenciano, un entorno que no define
nadie, una figura que no está, un `\\ref` que sale como «??», una diapositiva
cortada, una traducción que se ha quedado atrás.

Cada hallazgo dice dónde está --la lección, el idioma, la línea-- para que la
aplicación lleve allí de un clic, como con los errores de compilar.
"""

from __future__ import annotations

import os
import re
import subprocess

from . import build as build_mod
from . import profiles as profiles_mod
from . import repo as repo_mod
from . import spelling as spelling_mod

#: Lo que se comprueba siempre.
DEFAULT_CHECKS = ("babel", "environments", "figures", "labels", "overflow",
                  "outdated")

#: Lo que se pide: ayuda a unos y estorba a otros.
OPTIONAL_CHECKS = ("formulas", "unused", "overfull-lines", "decimals",
                   "spelling", "accessible")

#: Cómo se llama cada comprobación, para quien lee el informe.
TITLES = {
    "structure": "El repositorio",
    "babel": "Órdenes de otro idioma",
    "environments": "Entornos que no define nadie",
    "figures": "Figuras que faltan",
    "labels": "Etiquetas repetidas y referencias sin destino",
    "overflow": "Diapositivas que se salen",
    "outdated": "Traducciones desactualizadas",
    "formulas": "Fórmulas distintas entre idiomas",
    "unused": "Lecciones sin usar",
    "overfull-lines": "Líneas que se salen en los apuntes",
    "decimals": "Coma y punto decimal mezclados",
    "spelling": "Palabras que el diccionario no conoce",
    "accessible": "Lo que el PDF accesible no puede leer",
}


class Finding:
    """Una cosa que mirar, con dónde está."""

    __slots__ = ("check", "severity", "message", "path", "line", "unit",
                 "language", "document")

    def __init__(self, check, severity, message, path=None, line=None,
                 unit=None, language=None, document=None):
        self.check = check
        self.severity = severity
        self.message = message
        self.path = path
        self.line = line
        self.unit = unit
        self.language = language
        self.document = document

    def as_dict(self):
        data = {"check": self.check, "severity": self.severity,
                "message": self.message}
        for key in ("path", "line", "unit", "language", "document"):
            value = getattr(self, key)
            if value:
                data[key] = value
        return data

    def __str__(self):
        where = self.path or ""
        if self.line:
            where += ":%d" % self.line
        return "%s %s" % (where, self.message) if where else self.message


# --------------------------------------------------------------------------
# Leer LaTeX sin compilarlo
# --------------------------------------------------------------------------

#: Donde lo de dentro no es LaTeX, y no cuenta.
_VERBATIM = ("verbatim", "verbatim*", "lstlisting", "minted", "comment")


def _uncomment(line):
    match = re.search(r"(?<!\\)%", line)
    return line[:match.start()] if match else line


def _lines(text):
    """Las líneas sin comentarios, con su número, saltando lo literal."""
    inside = None
    for number, raw in enumerate(text.split("\n"), start=1):
        line = _uncomment(raw)
        if inside:
            if re.search(r"\\end\{%s\}" % re.escape(inside), line):
                inside = None
            continue
        for name in _VERBATIM:
            if "\\begin{%s}" % name in line:
                inside = name
                break
        yield number, line


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


# --------------------------------------------------------------------------
# Órdenes de un solo idioma
# --------------------------------------------------------------------------

#: El paquete de babel de cada idioma de Didacta.
BABEL_OF = {
    "es": "spanish", "va": "catalan", "ca": "catalan", "gl": "galician",
    "en": "english", "fr": "french", "it": "italian", "pt": "portuguese",
    "de": "ngerman", "eu": "basque",
}

#: Las órdenes que define un idioma de babel y ningún otro de los que usa
#: Didacta, leídas de sus `.ldf`. Las funciones del castellano --`\sen`,
#: `\tg`-- no: las define `didacta.sty` en todos los idiomas. La misma lista
#: que usa el editor para avisar mientras se escribe.
BABEL_ONLY = {
    "sptext": {"spanish", "galician"},
    "lsc": {"spanish", "galician"},
    "dotlessi": {"spanish", "galician"},
    "decimalcomma": {"spanish", "galician"},
    "decimalpoint": {"spanish", "galician"},
    "accentedoperators": {"spanish", "galician"},
    "unaccentedoperators": {"spanish", "galician"},
    "spanishoperators": {"spanish"},
    "spanishdeactivate": {"spanish"},
    "spanishdecimal": {"spanish"},
    "lgem": {"catalan"},
    "Lgem": {"catalan"},
    "og": {"french"},
    "fg": {"french"},
    "ier": {"french"},
    "iere": {"french"},
    "ieme": {"french"},
    "iemes": {"french"},
    "bsc": {"french"},
    "nombre": {"french"},
}

_BABEL_NAME = {"spanish": "castellano", "galician": "gallego",
               "catalan": "catalán y valenciano", "french": "francés"}


def _babel(file, language, where):
    babel = BABEL_OF.get(language)
    if babel is None:
        return
    for number, line in _lines(file):
        for name in re.findall(r"\\([A-Za-z]+)", line):
            owners = BABEL_ONLY.get(name)
            if owners and babel not in owners:
                names = " ni ".join(sorted({_BABEL_NAME.get(o, o) for o in owners}))
                yield where(
                    "babel", "error",
                    "\\%s solo existe en %s: en este idioma no compila"
                    % (name, names),
                    number,
                )


# --------------------------------------------------------------------------
# Entornos
# --------------------------------------------------------------------------

#: Los de LaTeX y de los paquetes que carga Didacta, que no están en su
#: árbol de LaTeX.
STANDARD_ENVIRONMENTS = {
    # LaTeX
    "abstract", "array", "center", "description", "document", "enumerate",
    "eqnarray", "eqnarray*", "equation", "equation*", "figure", "figure*",
    "flushleft", "flushright", "itemize", "list", "minipage", "picture",
    "quotation", "quote", "tabbing", "table", "table*", "tabular",
    "tabular*", "thebibliography", "titlepage", "trivlist", "verse",
    "verbatim", "verbatim*", "displaymath", "math", "filecontents",
    # amsmath, mathtools, empheq
    "align", "align*", "alignat", "alignat*", "aligned", "alignedat",
    "bmatrix", "Bmatrix", "cases", "dcases", "dcases*", "rcases", "rcases*",
    "flalign", "flalign*", "gather", "gather*", "gathered", "matrix",
    "multline", "multline*", "pmatrix", "smallmatrix", "split", "subequations",
    "vmatrix", "Vmatrix", "empheq", "psmallmatrix", "bsmallmatrix",
    "multlined", "cases*", "subarray",
    # amsthm
    "proof",
    # beamer
    "frame", "block", "alertblock", "exampleblock", "columns", "column",
    "overlayarea", "overprint", "onlyenv", "altenv", "actionenv", "visibleenv",
    "uncoverenv", "invisibleenv", "semiverbatim", "beamercolorbox",
    "beamerboxesrounded", "structureenv", "alertenv",
    # tikz, pgfplots
    "tikzpicture", "scope", "axis", "semilogxaxis", "semilogyaxis",
    "loglogaxis", "polaraxis", "groupplot",
    # graphicx, wrapfig, caption, multicol, tcolorbox, csquotes, booktabs
    "wrapfigure", "wraptable", "subfigure", "subtable", "multicols",
    "multicols*", "tcolorbox", "displayquote",
    # hyperref, enumitem
    "Form",
}

_DEFINES = re.compile(
    r"\\(?:newenvironment|renewenvironment|provideenvironment|NewEnviron|"
    r"RenewEnviron|NewDocumentEnvironment|RenewDocumentEnvironment|"
    r"DeclareDocumentEnvironment|ProvideDocumentEnvironment|newtcolorbox|"
    r"renewtcolorbox|NewTColorBox|DeclareTColorBox|newtcbtheorem|newtheorem|"
    r"newtheorem\*|declaretheorem|newmdenv|DidactaNewTheorem|"
    r"didacta@alias|newlist)\*?\s*(?:\[[^\]]*\])?\s*\{([^{}\s]+)\}"
)


def defined_environments(texts):
    """Los entornos que definen [texts]; un teorema de Didacta, con su `*`."""
    found = set()
    for text in texts:
        for match in _DEFINES.finditer(text):
            name = match.group(1)
            found.add(name)
            if match.group(0).startswith(("\\DidactaNewTheorem",
                                          "\\newtcbtheorem")):
                found.add(name + "*")
    return found


def latex_environments(latex_dir):
    """Los que define el árbol de LaTeX de Didacta."""
    texts = []
    for folder, _dirs, files in os.walk(latex_dir):
        for name in files:
            if name.endswith((".sty", ".tex", ".def", ".cls")):
                text = _read(os.path.join(folder, name))
                if text:
                    texts.append(text)
    return defined_environments(texts)


def _environments(file, known, where):
    local = defined_environments([file])
    reported = set()
    for number, line in _lines(file):
        for name in re.findall(r"\\begin\s*\{([^{}\s]+)\}", line):
            if name in known or name in local or name in reported:
                continue
            reported.add(name)
            yield where(
                "environments", "error",
                "\\begin{%s}: no lo define nadie, ni LaTeX, ni Didacta, ni "
                "los snippets del repositorio" % name,
                number,
            )


# --------------------------------------------------------------------------
# Figuras
# --------------------------------------------------------------------------

_GRAPHICS = re.compile(r"\\includegraphics\s*(?:\[[^\]]*\])?\s*\{([^{}]+)\}")
_EXTENSIONS = (".pdf", ".png", ".jpg", ".jpeg", ".eps")


def _figures(file, directory, where):
    for number, line in _lines(file):
        for name in _GRAPHICS.findall(line):
            name = name.strip()
            if "\\" in name or "#" in name:
                continue  # una macro: no se sabe qué fichero es
            path = os.path.join(directory, name)
            candidates = [path] if os.path.splitext(name)[1] else [
                path + ext for ext in _EXTENSIONS]
            if not any(os.path.isfile(c) for c in candidates):
                yield where(
                    "figures", "error",
                    "no está la figura %s" % name, number,
                )


# --------------------------------------------------------------------------
# Texto alternativo
# --------------------------------------------------------------------------

#: Una figura y sus opciones: `\includegraphics[...]{...}` o
#: `\begin{tikzpicture}[...]`. Las opciones, hasta el primer `]` que cierra:
#: dentro puede haber llaves, pero no otro `]` sin llaves.
_ALT_FIGURES = re.compile(
    r"\\(?:includegraphics|begin\{tikzpicture\})\s*(\[(?:[^\[\]{}]|\{[^{}]*\})*\])?")
_ALT_KEY = re.compile(r"(?:^|[\[,\s])alt\s*=")

#: Una lista con opciones: `\begin{enumerate}[a)]`, `[<+->]`, `[label=…]`.
_LIST_OPTIONS = re.compile(
    r"\\begin\{(enumerate|itemize|description)\}\s*\[([^\]]*)\]")


def _accessible(file, where):
    """Lo que impide o estropea el PDF accesible (`build --accessible`).

    Las figuras sin texto alternativo: lo que un lector de pantalla lee en
    lugar del dibujo; sin él, el dibujo es un hueco. Solo avisa: una figura
    que no dice nada --un adorno-- no lo necesita.

    Y las listas con opciones: el etiquetado de LaTeX todavía no las admite, y
    el documento que las lleva sale sin etiquetar. `[<+->]` son las pausas de
    las diapositivas, que en los apuntes no hacen nada: en una lección se
    escribe `\\dpause` o se ponen en los `\\item`.
    """
    for number, line in _lines(file):
        for match in _LIST_OPTIONS.finditer(line):
            options = match.group(2).strip()
            if options.startswith("<"):
                hint = ("[%s] es de las diapositivas: en unos apuntes no "
                        "hace nada" % options)
            else:
                hint = "las opciones de una lista, [%s]" % options
            yield where(
                "accessible", "info",
                "%s: el etiquetado de LaTeX todavía no las admite, y el "
                "documento sale sin etiquetar" % hint,
                number,
            )
        for match in _ALT_FIGURES.finditer(line):
            options = match.group(1) or ""
            if not _ALT_KEY.search(options):
                kind = ("el dibujo" if "tikzpicture" in match.group(0)
                        else "la figura")
                yield where(
                    "accessible", "warning",
                    "%s no tiene texto alternativo: alt={…} en sus opciones "
                    "es lo que lee un lector de pantalla" % kind,
                    number,
                )


# --------------------------------------------------------------------------
# Decimales
# --------------------------------------------------------------------------

_POINT = re.compile(r"(?<![\d.])\d+\.\d+(?![\d.])")
_COMMA = re.compile(r"(?<!\d)\d+(?:\{,\}|,)\d+")


def _math_bits(line):
    return re.findall(r"\$([^$]+)\$", line)


def _decimals(file, where):
    points, commas = [], []
    for number, line in _lines(file):
        for bit in _math_bits(line):
            if _POINT.search(bit):
                points.append(number)
            if _COMMA.search(bit) and "{,}" in bit:
                commas.append(number)
    if points and commas:
        yield where(
            "decimals", "warning",
            "mezcla punto decimal (línea %d) y coma decimal (línea %d)"
            % (points[0], commas[0]),
            points[0],
        )


# --------------------------------------------------------------------------
# Fórmulas
# --------------------------------------------------------------------------

_TEXT_IN_MATH = re.compile(
    r"\\(?:text|textrm|textit|textbf|mbox|mathrm\{\\text)\s*\{[^{}]*\}")


def _formulas(text):
    """Las fórmulas de un fichero, sin espacios y sin el texto que llevan.

    Las de uno o dos símbolos no: «la función» en un idioma es «$f$» en
    otro, y eso no es una fórmula distinta.
    """
    found = []
    body = "\n".join(line for _n, line in _lines(text))
    for match in re.finditer(
            r"\$\$(.+?)\$\$|\\\[(.+?)\\\]|(?<!\\)\$(.+?)(?<!\\)\$",
            body, re.S):
        formula = next(g for g in match.groups() if g is not None)
        formula = re.sub(r"\s+", "", _TEXT_IN_MATH.sub("", formula))
        if len(formula) > 3:
            found.append(formula)
    return found


# --------------------------------------------------------------------------
# Revisar
# --------------------------------------------------------------------------

def review(root, settings, units, courses, *, latex_dir, engine=None,
           all_profiles=None, documents=None, checks=None, snippets=()):
    """Todo lo que encuentra, en el orden de [DEFAULT_CHECKS].

    [documents] limita la revisión a esos documentos --`curso@año/doc`--
    y a sus lecciones: es lo que se mira antes de exportar. Sin ella, el
    repositorio entero. [checks], cuáles; sin ella, las de siempre.
    [engine] hace falta para mirar los registros de la última compilación.
    """
    checks = set(checks or DEFAULT_CHECKS)
    findings = []

    chosen = _documents_in(courses, documents)
    if documents is None:
        lessons = list(units.values())
    else:
        seen = {}
        for _course, _year, document in chosen:
            for ref in document.unit_refs:
                unit = repo_mod.resolve_unit_ref(ref, units, root)
                if unit is not None:
                    seen[unit.relpath] = unit
        lessons = list(seen.values())

    known = None
    if "environments" in checks:
        known = set(STANDARD_ENVIRONMENTS) | latex_environments(latex_dir)
        for snippet in snippets or ():
            known.update(snippet.names)

    # La prosa de cada idioma, junta: hunspell se lanza una vez por idioma y
    # no una por fichero.
    prose = {}

    for unit in sorted(lessons, key=lambda u: u.relpath):
        for code, entry in sorted(unit.languages.items()):
            if not entry.exists:
                continue
            text = _read(entry.path)
            if text is None:
                continue
            path = _relative(entry.path, root)

            # Todo atado al fichero de ahora, también la lección: la
            # ortografía lo llama después del bucle, cuando `unit` ya es otra.
            def where(check, severity, message, line=None, _code=code,
                      _path=path, _unit=unit.relpath):
                return Finding(check, severity, message, path=_path, line=line,
                               unit=_unit, language=_code)

            if "babel" in checks:
                findings.extend(_babel(text, code, where))
            if "environments" in checks:
                findings.extend(_environments(text, known, where))
            if "figures" in checks:
                findings.extend(_figures(text, unit.directory, where))
            if "decimals" in checks:
                findings.extend(_decimals(text, where))
            if "accessible" in checks:
                findings.extend(_accessible(text, where))
            if "spelling" in checks:
                for number, line in spelling_mod.prose_lines(text):
                    prose.setdefault(code, []).append((where, number, line))
        if "formulas" in checks:
            findings.extend(_formula_differences(unit, root))

    if "spelling" in checks:
        findings.extend(_spelling(prose, root))
    if "labels" in checks:
        findings.extend(_labels(chosen, units, root, settings))
    if "outdated" in checks:
        findings.extend(_outdated(chosen, units, root, settings))
    if "unused" in checks and documents is None:
        findings.extend(_unused(units, courses, root))
    if engine is not None and all_profiles is not None:
        wanted = {"vbox"} if "overflow" in checks else set()
        if "overfull-lines" in checks:
            wanted.add("hbox")
        if wanted:
            findings.extend(_overflow(chosen, engine, all_profiles, root,
                                      settings, wanted))
    return findings


def _spelling(prose, root):
    """Las palabras que el diccionario de cada idioma no conoce, por línea.

    Sin hunspell, o sin el diccionario de un idioma, se dice una vez y no es
    un aviso del material: es lo que hay en esta máquina.
    """
    if not prose:
        return
    hunspell = spelling_mod.program()
    if not hunspell:
        yield Finding(
            "spelling", "info",
            "para mirar la ortografía hace falta hunspell, que no está: %s"
            % spelling_mod.HOW_TO_INSTALL,
        )
        return
    found = spelling_mod.available(hunspell)
    known = spelling_mod.known_words(root)
    names = {code: name for code, name, _ in profiles_mod.LANGUAGE_REGISTRY}
    for code in sorted(prose):
        dictionary = spelling_mod.dictionary_for(code, found)
        if dictionary is None:
            yield Finding(
                "spelling", "info",
                "hunspell no tiene diccionario de %s (%s): esas lecciones no "
                "se han mirado"
                % (names.get(code, code),
                   ", ".join(spelling_mod.DICTIONARIES.get(code, (code,)))),
                language=code,
            )
            continue
        entries = prose[code]
        try:
            answers = spelling_mod.misspelled(
                hunspell, dictionary, [line for _w, _n, line in entries])
        except (OSError, subprocess.SubprocessError) as error:
            # Un hunspell que no arranca o que no acaba: se dice, y los demás
            # idiomas se miran igual.
            yield Finding("spelling", "info",
                          "hunspell no ha podido mirar %s: %s"
                          % (names.get(code, code), error), language=code)
            continue
        for (where, number, _line), words in zip(entries, answers):
            wrong = []
            for word, suggestions in words:
                if word in known or word.lower() in known:
                    continue
                if suggestions:
                    wrong.append("«%s» (¿%s?)" % (word, suggestions[0]))
                else:
                    wrong.append("«%s»" % word)
            if wrong:
                yield where("spelling", "warning", ", ".join(wrong), number)


def _relative(path, root):
    return os.path.relpath(path, root).replace(os.sep, "/")


def _reference(course, year, document):
    # `year.id` ya es `curso@año`.
    return "%s/%s" % (year.id, document.id)


def _documents_in(courses, wanted):
    wanted = None if wanted is None else set(wanted)
    found = []
    for course in courses.values():
        for year in course.years.values():
            for document in year.documents:
                reference = _reference(course, year, document)
                if wanted is None or reference in wanted or year.id in wanted:
                    found.append((course, year, document))
    return found


def _lesson_file(unit, language):
    """El fichero de [unit] que entra en un documento en [language]."""
    entry = unit.languages.get(language)
    if entry is not None and entry.exists:
        return language, entry.path
    entry = unit.languages.get(unit.reference)
    if entry is not None and entry.exists:
        return unit.reference, entry.path
    return None, None


_LABEL = re.compile(r"\\label\s*\{([^{}]+)\}")
#: La de una diapositiva: `\begin{frame}[label=algebra]` también se puede
#: citar con `\ref`.
_FRAME_LABEL = re.compile(r"\\begin\s*\{frame\}\s*\[[^\]]*\blabel\s*=\s*([^,\]\s]+)")
_REF = re.compile(
    r"\\(?:ref|eqref|pageref|autoref|cref|Cref|nameref|vref)\s*\{([^{}]+)\}")


def _labels(chosen, units, root, settings):
    for course, year, document in chosen:
        reference = _reference(course, year, document)
        for language in course.taught_in(settings):
            labels = {}
            refs = []
            texts = []
            if document.source:
                texts.append((None, None, document.source))
            for ref in document.unit_refs:
                unit = repo_mod.resolve_unit_ref(ref, units, root)
                if unit is None:
                    continue
                code, path = _lesson_file(unit, language)
                if path:
                    texts.append((unit, code, path))
            for unit, code, path in texts:
                text = _read(path) or ""
                for number, line in _lines(text):
                    for key in _LABEL.findall(line) + _FRAME_LABEL.findall(line):
                        labels.setdefault(key, []).append(
                            (unit, code, path, number))
                    for keys in _REF.findall(line):
                        for key in keys.split(","):
                            refs.append((key.strip(), unit, code, path, number))
            for key, places in labels.items():
                if len(places) < 2:
                    continue
                unit, code, path, number = places[1]
                first = places[0]
                yield Finding(
                    "labels", "warning",
                    "\\label{%s} repetida: ya está en %s, línea %d; los \\ref "
                    "irán a una de las dos" % (
                        key, _relative(first[2], root), first[3]),
                    path=_relative(path, root), line=number,
                    unit=unit.relpath if unit else None, language=code,
                    document=reference,
                )
            for key, unit, code, path, number in refs:
                if key in labels:
                    continue
                yield Finding(
                    "labels", "warning",
                    "\\ref{%s} no tiene destino en %s: saldrá como «??»"
                    % (key, document.title(language)),
                    path=_relative(path, root), line=number,
                    unit=unit.relpath if unit else None, language=code,
                    document=reference,
                )


def _outdated(chosen, units, root, settings):
    reported = set()
    for course, _year, document in chosen:
        for language in course.taught_in(settings):
            for ref in document.unit_refs:
                unit = repo_mod.resolve_unit_ref(ref, units, root)
                if unit is None or language == unit.reference:
                    continue
                key = (unit.relpath, language)
                if key in reported:
                    continue
                if unit.statuses().get(language) != "outdated":
                    continue
                reported.add(key)
                entry = unit.languages[language]
                yield Finding(
                    "outdated", "warning",
                    "«%s» en %s se ha quedado atrás del original: el "
                    "original cambió después de traducirlo"
                    % (unit.title(language), language),
                    path=_relative(entry.path, root), unit=unit.relpath,
                    language=language,
                )


def _unused(units, courses, root):
    used = set()
    for course in courses.values():
        for year in course.years.values():
            for document in year.documents:
                for ref in document.unit_refs:
                    unit = repo_mod.resolve_unit_ref(ref, units, root)
                    if unit is not None:
                        used.add(unit.relpath)
    for unit in sorted(units.values(), key=lambda u: u.relpath):
        if unit.relpath not in used:
            yield Finding(
                "unused", "info",
                "«%s» no la usa ningún documento" % unit.title(unit.reference),
                unit=unit.relpath, language=unit.reference,
            )


def _formula_differences(unit, root):
    reference = unit.languages.get(unit.reference)
    if reference is None or not reference.exists:
        return
    original = set(_formulas(_read(reference.path) or ""))
    for code, entry in sorted(unit.languages.items()):
        if code == unit.reference or not entry.exists:
            continue
        translated = set(_formulas(_read(entry.path) or ""))
        missing = sorted(original - translated)
        extra = sorted(translated - original)
        if not missing and not extra:
            continue
        parts = []
        if missing:
            parts.append("falta %s" % missing[0][:60])
        if extra:
            parts.append("sobra %s" % extra[0][:60])
        count = len(missing) + len(extra)
        yield Finding(
            "formulas", "warning",
            "las fórmulas no son las mismas que en %s: %s%s"
            % (unit.reference, "; ".join(parts),
               " (y %d más)" % (count - len(parts)) if count > len(parts) else ""),
            path=_relative(entry.path, root), unit=unit.relpath, language=code,
        )


def _overflow(chosen, engine, all_profiles, root, settings, wanted):
    """Lo que se salía en la última compilación de cada documento.

    Una vez por sitio: la misma diapositiva se sale en las diapositivas, en
    las de sin pausas y en las del profesor, y en cada documento que lleva la
    lección. Se dice la que más se sale y en cuántas versiones.
    """
    places = {}
    for course, year, document in chosen:
        reference = _reference(course, year, document)
        names = document.profiles or [
            profile.id for profile in
            profiles_mod.default_profiles(all_profiles, document.kind)
        ]
        for name in names:
            profile = all_profiles.get(name)
            if profile is None:
                continue
            kinds = ("vbox",) if profile.family == "slides" else ("hbox",)
            kinds = tuple(k for k in kinds if k in wanted)
            if not kinds:
                continue
            for language in course.taught_in(settings):
                title = document.title(language)
                outdir = engine.output_dir(reference, name, language)
                log = os.path.join(outdir,
                                   profile.output_name(title, language) + ".log")
                text = _read(log)
                if not text:
                    continue
                source_dir = os.path.dirname(document.source or root)
                content_root = os.path.relpath(root, source_dir)
                found = [d for d in build_mod.parse_log(text, kinds) if d.code]
                build_mod.frame_starts(found, source_dir)
                build_mod.locate(found, source_dir, content_root)
                for diagnostic in found:
                    key = (diagnostic.path or diagnostic.file, diagnostic.line,
                           diagnostic.language, diagnostic.code)
                    known = places.get(key)
                    if known is None:
                        places[key] = [diagnostic, reference, {profile.label}]
                        continue
                    known[2].add(profile.label)
                    if diagnostic.points > known[0].points:
                        known[0], known[1] = diagnostic, reference
    for diagnostic, reference, labels in places.values():
        versions = (sorted(labels)[0] if len(labels) == 1
                    else "%d versiones" % len(labels))
        yield Finding(
            "overflow" if diagnostic.code == "overfull-slide"
            else "overfull-lines",
            "warning",
            "%s, en %s (última compilación)" % (diagnostic.message, versions),
            path=diagnostic.path, line=diagnostic.line,
            unit=diagnostic.unit, language=diagnostic.language,
            document=reference,
        )
