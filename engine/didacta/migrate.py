"""Migration from the legacy system into a Didacta content repository.

Reads the old layout, writes the new one. Two rules it never breaks:

**The source is never modified.** Migration reads the legacy repository and
writes a separate content repository. Nothing is moved, renamed or deleted in
place, so the existing material keeps compiling with its own Makefiles for as
long as it needs to.

**Nothing is written without ``--apply``.** The default is a plan: what would
be created, what would be transformed, and -- most importantly -- what needs a
human decision.

What is mechanical:

1. group files into logical units by ``(directory, ordinal, slug)``;
2. one directory per unit, files renamed ``es.tex`` / ``va.tex`` / ``en.tex``;
3. **delete the preamble** -- the ``\\documentclass`` / ``\\usepackage`` /
   ``\\import{Files/}`` block that ``docmute`` existed to discard. This removes
   the most noise of any single step;
4. rewrite ``\\import{../../../../00classnotes/...}`` as ``\\DidactaUnit{...}``;
5. rename legacy environments and macros where the alias is worse than the
   real name;
6. copy figures alongside their unit.

What is not, and is reported instead of invented: the title in each language,
the tags beyond what the folder says, the prerequisites, the objectives and the
estimated duration. The legacy material records none of it, and guessing would
put wrong metadata in front of a reader with the authority of having been
written down.
"""

from __future__ import annotations

import os
import re
import shutil

from . import legacy
from . import repo as repo_mod

#: Where a legacy kind lands in the new layout.
AREA_FOR_KIND = {
    "problem": repo_mod.PROBLEMS,
}


class MigrationError(RuntimeError):
    pass


# --------------------------------------------------------------------------
# Transforming one content file
# --------------------------------------------------------------------------

#: Macros that only made sense inside a legacy preamble. Any that survive into
#: a body are dropped: Didacta sets them itself.
_DROP_LINES = re.compile(
    r"^\s*\\(?:documentclass|usepackage|import\s*\{[^}]*Files/?[^}]*\}"
    r"|makeatletter|makeatother|texpath|def\\CurrentAudience|SetNewAudience"
    r"|newcommand\{\\chapterTitle\}|title\{|author\{|date\{|subimport\s*\{\})"
)

#: Legacy environment renames.
#:
#: The first group has a Didacta alias already, so renaming is about leaving
#: content that reads well. The second group does not: those environments were
#: declared in each file's own preamble -- the preamble migration deletes -- so
#: without the rename the unit does not compile at all. ``ejer`` alone is used
#: 2993 times, more than every ``ej`` in the library.
#:
#: Every target below is read off the legacy ``\newtheorem`` that declared it,
#: not guessed: ``\newtheorem{ejer}[theorem]{\bf{Ejercicio}}`` is an exercise,
#: ``\newtheorem{recipe}{Algoritmo}`` is an algorithm.
_ENV_RENAMES = {
    # Aliased in didacta-theorems.sty.
    "ndefn": "definition", "nthrm": "theorem", "nthm": "theorem",
    "nprop": "proposition", "npro": "property", "nlem": "lemma",
    "ncor": "corollary", "nex": "example", "nques": "question",
    "nrem": "remark", "naxioma": "axiom",
    "defn": "definition", "thrm": "theorem", "prop": "proposition",
    "pro": "property", "lem": "lemma", "cor": "corollary",
    "ex": "example", "ques": "question", "rem": "remark", "axioma": "axiom",
    "ej": "exercise",
    "nformula": "keyformula",

    # Declared per-file in the old preambles, so these must be renamed.
    "ejer": "exercise", "prob": "exercise", "problema": "exercise",
    "ejem": "example", "ejemplo": "example", "ejemplos": "example",
    "df": "definition", "definicion": "definition", "definicio": "definition",
    "teo": "theorem", "teorema": "theorem",
    "cuestion": "question", "questio": "question", "quest": "question",
    "nota": "remark", "note": "remark",
    "recipe": "algorithm",
    # `sol` wrapped \begin{proof}: prose that was always shown. Mapping it to
    # Didacta's `solution` would move it behind the solutions axis and drop it
    # from the student copy, so it becomes a proof, which is what it was.
    "sol": "proof",
}

#: Macros the material uses whose package Didacta does not load, and the
#: package each needs. Found by migrating the library and compiling it.
#:
#: Not loaded on purpose (D31): `animate` changes how the PDF is written, and
#: a compatibility layer that alters correct output is worse than the
#: incompatibility. So these are reported and the author decides.
UNSUPPORTED_MACROS = {
    "animategraphics": "animate",
    "animateinline": "animate",
    "movie": "multimedia",
}

#: Environments a migrated unit can rely on: Didacta's own, plus what the
#: packages it loads provide, plus standard LaTeX.
#:
#: It has to be exactly that and no more. `empheq` and `wrapfigure` were on
#: this list before any package provided them, and the only symptom was a
#: migrated unit that would not build. `tabu`, `tabularx`, `longtable` and
#: `adjustbox` were on it too and nothing in the material uses them, so they
#: are gone rather than pulled in on spec -- a promise here means Didacta
#: really does supply it. A test in test_engine.py checks the pairing.
#:
#: Anything else came from a per-file preamble that no longer exists, so it is
#: reported. This is the safety net that turns "it does not compile" into a
#: line in the report -- `ejer` was found this way, by building everything.
PROVIDED_ENVIRONMENTS = frozenset("""
theorem definition proposition lemma corollary property example question
remark axiom algorithm notation exercise hint answer solution marking
keyformula proof
document itemize enumerate description figure table tabular
array center flushleft flushright quote quotation quoting verse
verbatim lstlisting minipage picture list trivlist thebibliography titlepage
equation displaymath eqnarray math align alignat gather multline split
subequations cases dcases rcases aligned gathered alignedat empheq flalign
smallmatrix matrix pmatrix bmatrix Bmatrix vmatrix Vmatrix
frame columns column block exampleblock alertblock overprint onlyenv only
uncoverenv visibleenv altenv actionenv overlayarea
tikzpicture axis semilogxaxis semilogyaxis loglogaxis groupplot scope
pgfonlayer tcolorbox multicols wrapfigure subfigure landscape
displayquote comment abstract
""".split()) | frozenset("""
displaystyle textstyle scriptstyle scriptscriptstyle
""".split())
#: The size declarations above are used as environments in 20 files -- `$...
#: \begin{displaystyle}...\end{displaystyle}...$` -- and LaTeX accepts it, so
#: they belong on the list rather than in the report.

#: Macro renames.
_MACRO_RENAMES = {
    r"\onlybook": r"\onlynotes",
    r"\pause": r"\dpause",
}


#: Legacy `multiaudience` audiences and the answer level each becomes. The
#: names come from the two templates that declare them: `Problems-template`
#: declares `solution` and `profesor`, `Extra-examples-template` declares
#: `professor` and `student` -- so the same audience is spelled both ways in
#: the same library and both have to be handled.
_AUDIENCE_LEVELS = {
    "solution": "solution",
    "profesor": "marking",
    "professor": "marking",
}

_SHOWNTO = re.compile(r"\\begin\s*\{shownto\}\s*\{([^}]*)\}")
_SHOWNTO_ANY = re.compile(r"\\(begin|end)\s*\{shownto\}")


def _rewrite_audiences(body):
    """Turn ``\\begin{shownto}{x}`` blocks into Didacta's named levels.

    Each block's own ``\\end{shownto}`` is rewritten, tracking nesting, because
    substituting begins and ends independently would mismatch them in any file
    that uses two different audiences -- and a mismatch is a compile error at
    best and content shown to the wrong reader at worst.
    """
    notes = []
    renamed = {}
    unknown = set()
    out = []
    i = 0

    while True:
        match = _SHOWNTO.search(body, i)
        if match is None:
            out.append(body[i:])
            break

        audience = match.group(1).strip()
        level = _AUDIENCE_LEVELS.get(audience.lower())
        out.append(body[i : match.start()])

        if level is None:
            unknown.add(audience)
            out.append(match.group(0))
            i = match.end()
            continue

        end = _matching_end(body, match.end())
        if end is None:
            notes.append(
                "un \\begin{shownto}{%s} se queda sin \\end{shownto}; se ha "
                "dejado como estaba" % audience
            )
            out.append(match.group(0))
            i = match.end()
            continue

        inner_start, inner_end, after = end
        # Recurse: a nested block is a different audience and needs rewriting
        # too, and its own \end must not be mistaken for this one's.
        inner, inner_notes, inner_renamed = _rewrite_audiences(
            body[inner_start:inner_end])
        notes.extend(inner_notes)
        renamed.update(inner_renamed)
        out.append("\\begin{%s}" % level)
        out.append(inner)
        out.append("\\end{%s}" % level)
        renamed[audience] = level
        i = after

    if unknown:
        notes.append(
            "audiencia no reconocida en \\begin{shownto}: %s; el alias sigue "
            "funcionando, pero hay que decidir a qué nivel de respuesta "
            "corresponde (hint, answer, solution o marking)"
            % ", ".join("`%s`" % name for name in sorted(unknown))
        )

    return "".join(out), notes, renamed


_SEC = re.compile(r"\\sec(?![a-zA-Z])")


def _rewrite_sec(body):
    """``(text, count)`` with the non-maths ``\sec`` turned into the group."""
    out = []
    count = 0
    for span, is_maths in legacy.split_maths(body):
        if is_maths:
            out.append(span)
            continue
        span, found = _SEC.subn(r"\\didactaCourseGroup", span)
        count += found
        out.append(span)
    return "".join(out), count


_QUESTION = re.compile(r"\\question\s*(?=\{)")


def _rewrite_question(body):
    """``(text, count)`` with the FAQ macro turned into the environment."""
    out = []
    i = 0
    count = 0
    while True:
        match = _QUESTION.search(body, i)
        if match is None:
            out.append(body[i:])
            break
        content, after = legacy.read_group(body, match.end())
        if content is None:
            out.append(body[i:match.end()])
            i = match.end()
            continue
        out.append(body[i:match.start()])
        out.append("\\begin{question}%s\\end{question}" % content)
        count += 1
        i = after
    return "".join(out), count


def _rewrite_listofquestions(body):
    """Drop `\\listofquestions`: nothing generates that index any more."""
    return re.subn(r"\\listofquestions(?![a-zA-Z])\s*", "", body)


def _matching_end(body, start):
    """Locate the ``\\end{shownto}`` that closes the block opened before ``start``.

    Returns ``(inner_start, inner_end, index_after_end)``, or None.
    """
    depth = 1
    i = start
    while True:
        match = _SHOWNTO_ANY.search(body, i)
        if match is None:
            return None
        if match.group(1) == "begin":
            depth += 1
            i = match.end()
            continue
        depth -= 1
        if depth == 0:
            return start, match.start(), match.end()
        i = match.end()


class Transform:
    """The result of transforming one legacy file, with what it changed."""

    __slots__ = ("text", "notes", "preamble_lines", "renamed", "sections")

    def __init__(self, text, notes, preamble_lines, renamed, sections=None):
        self.text = text
        self.notes = notes
        self.preamble_lines = preamble_lines
        self.renamed = renamed
        #: Section titles the unit declares itself, which belong in the
        #: composition instead.
        self.sections = sections or []


#: ``\includegraphics``, with its optional argument and possible star.
_GRAPHIC = re.compile(
    r"(\\includegraphics\s*\*?\s*(?:\[[^\]]*\])?\s*)\{([^{}]*)\}")


def transform_content(text, *, rename_environments=True, source_path="",
                      figures=None):
    """Turn one legacy content file into a Didacta unit file.

    Returns the new text plus notes about anything a human should look at.
    """
    notes = []
    split = legacy.split_document(text)
    body = split.body if split.has_document_environment else text
    preamble_lines = len(split.preamble.split("\n")) if split.preamble else 0

    if not split.has_document_environment:
        # 305 units are like this, and it is the shape Didacta wants: content
        # with no preamble. Worth saying only because nothing was deleted.
        notes.append(
            "ya era un fragmento sin preámbulo, así que se ha copiado tal cual"
        )

    # Drop preamble leftovers that occasionally appear after \begin{document}.
    kept = []
    dropped = 0
    for line in body.split("\n"):
        if _DROP_LINES.match(line):
            dropped += 1
            continue
        kept.append(line)
    if dropped:
        notes.append("se han eliminado %d línea(s) de preámbulo que estaban en el cuerpo"
                     % dropped)
    body = "\n".join(kept)

    renamed = {}
    if rename_environments:
        for legacy_name, new_name in _ENV_RENAMES.items():
            # The starred form too: `\begin{defn*}` is an unnumbered
            # definition, and Didacta declares `definition*` alongside every
            # theorem environment.
            pattern = re.compile(
                r"\\(begin|end)\s*\{" + re.escape(legacy_name) + r"(\*?)\}")
            body, count = pattern.subn(
                lambda match, target=new_name:
                    "\\%s{%s%s}" % (match.group(1), target, match.group(2)),
                body,
            )
            if count:
                renamed[legacy_name] = new_name

    # `shownto` audiences become the named levels, which say what they hold.
    body, audience_notes, audiences = _rewrite_audiences(body)
    for legacy_audience, new_name in sorted(audiences.items()):
        renamed["shownto{%s}" % legacy_audience] = new_name
    notes.extend(audience_notes)

    for legacy_macro, new_macro in _MACRO_RENAMES.items():
        pattern = re.compile(re.escape(legacy_macro) + r"(?![a-zA-Z])")
        body, count = pattern.subn(new_macro.replace("\\", "\\\\"), body)
        if count:
            renamed[legacy_macro] = new_macro

    # A frame title becomes \didactatitle, which is a frame title on slides and
    # a subsection heading in prose. Written as \frametitle it simply vanishes
    # from the notes, leaving the reader without a heading.
    body, titles = re.subn(r"\\frametitle\s*\{", r"\\didactatitle{", body)
    if titles:
        renamed[r"\frametitle"] = r"\didactatitle"

    # A unit that declares its own \section cannot be reordered or reused in
    # another course without dragging the heading with it. In Didacta sections
    # live in the composition. Measured on the functional-analysis category: 59
    # of 140 migrated files do this, so it is worth reporting precisely rather
    # than in the aggregate.
    sections = []
    for match in re.finditer(r"\\(sub)*section\*?\s*\{", body):
        title, _ = legacy.read_group(body, match.end() - 1)
        if title:
            sections.append(legacy.clean_text(title))
    if sections:
        notes.append(
            "declara su propia sección: %s. En Didacta las secciones van en la "
            "composición, así que conviene moverla a year.yaml y borrarla de "
            "aquí; si no, el encabezado viaja con la unidad a cada asignatura "
            "que la reutilice" % ", ".join("`%s`" % s for s in sections[:4])
        )

    # Macros whose package Didacta does not load. Reported rather than
    # provided: `animate` and the legacy tikz styles change how the PDF is
    # produced, and D31 says the compatibility layer must not do that.
    unsupported = sorted({
        name for name in _MACRO.findall(body)
        if name in UNSUPPORTED_MACROS
    })
    if unsupported:
        notes.append(
            "usa %s, que necesita un paquete que Didacta no carga (%s). Hay "
            "que decidir si se carga en el repositorio o se sustituye el "
            "contenido"
            % (", ".join("`\\%s`" % name for name in unsupported),
               ", ".join(sorted({UNSUPPORTED_MACROS[n] for n in unsupported})))
        )

    # Bibliography material. `\cite` degrades to a `[?]` and a warning, so it
    # compiles; `\cites` is biblatex-only and does not.
    if re.search(r"\\cites(?![a-zA-Z])", body):
        notes.append(
            "usa `\\cites` de biblatex, y Didacta todavía no tiene "
            "bibliografía: ni recurso, ni estilo, ni `.bib` en el modelo de "
            "contenido. La unidad no compila hasta que exista, o hasta que se "
            "reescriban las citas"
        )
    elif re.search(r"\\cite(?![a-zA-Z])", body):
        notes.append(
            "cita con `\\cite`, y Didacta todavía no tiene bibliografía: la "
            "cita saldrá como `[?]` con un aviso, no como la referencia"
        )

    # A tikz style the old templates declared, not a package.
    if re.search(r"highlight\s+on\s*=", body):
        notes.append(
            "usa el estilo tikz `highlight on`, que declaraba la plantilla "
            "antigua; sin él el `tikzpicture` no compila"
        )

    # Anything still unaccounted for came from the deleted preamble. Left
    # alone it is a compile error, and a compile error found by building 2147
    # units one day is a compile error found too late.
    orphans = sorted({
        match.group(1)
        for match in re.finditer(r"\\begin\s*\{([A-Za-z@]+\*?)\}", body)
        if match.group(1).rstrip("*") not in PROVIDED_ENVIRONMENTS
    })
    if orphans:
        notes.append(
            "usa entorno(s) que Didacta no define y que declaraba el preámbulo "
            "borrado: %s. Hay que decidir a qué entorno de Didacta corresponden "
            "o declararlos en el repositorio; tal como está no compila"
            % ", ".join("`%s`" % name for name in orphans[:6])
        )

    # `\question{X}` -> `\begin{question}X\end{question}`. Read the balanced
    # group rather than matching braces with a regex: the arguments contain
    # maths, and `{...}` inside would end the match early.
    body, dropped_index = _rewrite_listofquestions(body)
    if dropped_index:
        notes.append(
            "se ha quitado `\\listofquestions`: era el índice que generaba la "
            "plantilla FAQ y Didacta no lo tiene"
        )
    body, questions = _rewrite_question(body)
    if questions:
        renamed["\\question"] = "question"
        notes.append(
            "usaba %d vez(ces) `\\question{...}` de la plantilla FAQ, que en "
            "Didacta es un entorno con el mismo nombre, así que se ha "
            "reescrito como `\\begin{question}`. Lo que no viaja es el índice "
            "de preguntas (`\\listofquestions`), que ya no se genera"
            % questions
        )

    # `\sec` is LaTeX's secant, and the old templates redefined it as the
    # course group -- so the material uses it both ways, 98 times as the secant
    # and 58 in a page header. Didacta will not break the maths, which leaves
    # the header uses as "Missing $ inserted" unless they are rewritten here.
    body, secants = _rewrite_sec(body)
    if secants:
        renamed["\\sec"] = "\\didactaCourseGroup"
        notes.append(
            "usaba \\sec %d vez(ces) fuera de modo matemático, donde el "
            "sistema antiguo lo había redefinido como el grupo; se ha "
            "cambiado por `\\didactaCourseGroup`. Dentro de las matemáticas "
            "se ha dejado, porque ahí es la secante" % secants
        )

    if re.search(r"\\onlyteacher\b", body):
        notes.append(
            "usa \\onlyteacher, que en las plantillas antiguas estaba definido "
            "igual que \\onlybook y por tanto no distinguía nada; hay que "
            "comprobar si el contenido es guía didáctica (mantener "
            "\\onlyteacher) o simplemente prosa para los apuntes (cambiar a "
            "\\onlynotes)"
        )

    # Figures are copied next to their unit, so the reference has to follow
    # them. 710 of the 2147 units reference a graphic, and leaving the old
    # relative path behind would break every one of them.
    if figures is not None:
        unresolved = []

        def relocate(match):
            reference = match.group(2).strip()
            target = figures.get(reference)
            if target is None:
                unresolved.append(reference)
                return match.group(0)
            return "%s{%s}" % (match.group(1), target)

        body, moved = _GRAPHIC.subn(relocate, body)
        if moved and figures:
            renamed["\\includegraphics"] = "figures/"
        if unresolved:
            notes.append(
                "no se ha encontrado %d figura(s), así que su ruta se ha dejado "
                "como estaba y no compilará: %s"
                % (len(unresolved),
                   ", ".join("`%s`" % name for name in sorted(set(unresolved))[:4]))
            )
    elif re.search(r"\\includegraphics", body):
        notes.append("referencia figuras; hay que revisar las rutas tras la copia")

    if re.search(r"\\input\s*\{|\\include\s*\{", body):
        notes.append("usa \\input o \\include; si apunta a contenido reutilizable, "
                     "reescribirlo como \\DidactaUnit")

    header = (
        "%% Migrated from %s\n"
        "%%\n"
        "%% No preamble: Didacta supplies it.\n" % source_path
        if source_path else ""
    )
    return Transform(
        text=header + body.strip("\n") + "\n",
        notes=notes,
        preamble_lines=preamble_lines,
        renamed=renamed,
        sections=sections,
    )


# --------------------------------------------------------------------------
# Planning
# --------------------------------------------------------------------------


class UnitPlan:
    """One legacy logical unit, and where it is going."""

    __slots__ = (
        "target", "area", "kind", "category", "topic", "tags", "sources",
        "reference", "title", "figures", "notes", "needs_decision",
        "ordinal", "source_dir",
    )

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        for slot in ("tags", "figures", "notes", "needs_decision"):
            if getattr(self, slot) is None:
                setattr(self, slot, [])
        if self.sources is None:
            self.sources = {}

    @property
    def relpath(self):
        return "%s/%s" % (self.area, self.target)

    @property
    def languages(self):
        return sorted(self.sources)


class Plan:
    """Everything a migration would do."""

    def __init__(self, source_root, target_root):
        self.source_root = source_root
        self.target_root = target_root
        self.units = []
        self.skipped = []
        self.errors = []

    @property
    def decisions(self):
        """Units carrying something a human has to decide."""
        return [unit for unit in self.units if unit.needs_decision]

    def summary(self):
        by_kind = {}
        by_language = {}
        for unit in self.units:
            by_kind[unit.kind] = by_kind.get(unit.kind, 0) + 1
            key = "+".join(unit.languages)
            by_language[key] = by_language.get(key, 0) + 1
        return {
            "units": len(self.units),
            "files": sum(len(u.sources) for u in self.units),
            "byKind": by_kind,
            "byLanguages": by_language,
            "needDecision": len(self.decisions),
            "skipped": len(self.skipped),
            "errors": len(self.errors),
        }


def plan_units(source_root, target_root, *, category=None, limit=None):
    """Work out how the legacy library maps onto Didacta units.

    Reads only; produces a plan.
    """
    plan = Plan(source_root, target_root)

    patterns = [legacy.CLASSNOTES + "/**/*.tex", legacy.CLASSNOTES + "/*.tex"]
    try:
        paths = legacy.git_files(source_root, *patterns)
    except RuntimeError as exc:
        plan.errors.append(str(exc))
        return plan

    groups = {}
    for path in paths:
        if legacy.is_asset(path):
            plan.skipped.append((path, "asset or template, not content"))
            continue
        if category and legacy.category_of(path) != category:
            continue
        directory = os.path.dirname(path)
        name = legacy.read_name(path)
        groups.setdefault(legacy.logical_key(directory, name), {})[name.language] = (
            path, name)

    # Reconcile the measured case where the ordinals disagree between
    # languages: merge groups sharing directory and slug when neither already
    # covers the other's language.
    by_fallback = {}
    for key in list(groups):
        directory, _ordinal, slug = key
        by_fallback.setdefault((directory, slug), []).append(key)
    for keys in by_fallback.values():
        if len(keys) < 2:
            continue
        keys.sort(key=lambda item: item[1])
        primary = keys[0]
        for other in keys[1:]:
            if set(groups[primary]) & set(groups[other]):
                continue
            groups[primary].update(groups.pop(other))

    for key in sorted(groups):
        directory, ordinal, slug = key
        variants = groups[key]
        unit = _plan_one(source_root, directory, ordinal, slug, variants)
        if unit is not None:
            plan.units.append(unit)
        if limit and len(plan.units) >= limit:
            break

    _disambiguate(plan.units)
    return plan


def _disambiguate(units):
    """Make every target path unique.

    Dropping the ordering prefix is right -- in Didacta order lives in the
    composition -- but it makes distinct units collide whenever the legacy name
    carried no meaning beyond its number. Measured on the full library: 66
    targets are claimed by 150 units, the worst being eight different
    ``Ejercicios.tex`` in one folder. Left alone, the later unit would silently
    overwrite the earlier one and 84 units of real material would be lost, so
    this is a correctness fix, not tidiness.

    Nothing is guessed from the content. The ordinal is put back, then the
    distinguishing source folder, then a counter -- and every affected unit is
    told to pick a real name.
    """
    by_target = {}
    for unit in units:
        by_target.setdefault(unit.relpath, []).append(unit)

    for group in by_target.values():
        if len(group) < 2:
            continue

        group.sort(key=lambda unit: (unit.ordinal or "", unit.source_dir))
        taken = set()
        for unit in group:
            base = unit.target
            for candidate in _candidates(unit, base):
                if candidate not in taken:
                    break
            taken.add(candidate)
            unit.target = candidate
            unit.needs_decision.append(
                "un nombre propio: `%s` lo comparten %d unidades distintas, así "
                "que se ha desambiguado a `%s` con el número de orden antiguo. "
                "Los ficheros originales son %s"
                % (
                    base.rsplit("/", 1)[-1],
                    len(group),
                    candidate.rsplit("/", 1)[-1],
                    ", ".join("`%s`" % path for path in sorted(unit.sources.values())),
                )
            )


def _candidates(unit, base):
    """Names to try for a colliding unit, least ugly first."""
    if unit.ordinal:
        yield "%s-%s" % (base, unit.ordinal)
    # The folder above the unit's own, when it is what actually differs: the
    # same `integrals` lives under both 30History and 40Bibliography.
    parent = os.path.basename(os.path.dirname(unit.source_dir))
    if parent:
        slug = repo_mod.slugify(parent)
        if slug:
            yield "%s-%s" % (base, slug)
            if unit.ordinal:
                yield "%s-%s-%s" % (base, slug, unit.ordinal)
    counter = 2
    while True:
        yield "%s-%d" % (base, counter)
        counter += 1


def _plan_one(source_root, directory, ordinal, slug, variants):
    any_path, any_name = variants[sorted(variants)[0]]
    kind = legacy.kind_of(any_path)
    area = AREA_FOR_KIND.get(kind, repo_mod.CONTENT)

    category = legacy.category_of(any_path) or "uncategorised"
    tags = legacy.path_tags(any_path)
    topic = tags[-1] if tags else "general"

    # The target path: category / topic / unit. The ordinal is dropped -- in
    # Didacta ordering lives in the composition, not in the file name.
    target = "%s/%s/%s" % (
        repo_mod.slugify(category), repo_mod.slugify(topic), repo_mod.slugify(slug))

    # Reference language: whichever exists first in es -> va -> en order.
    reference = next((code for code in legacy.LANGUAGES if code in variants), None)
    if reference is None:
        return None

    titles = {}
    notes = []
    decisions = []
    figures = set()

    # Read every language first: the figure map has to cover the whole unit
    # before any file is transformed, because they all land in one figures/.
    sources = {}
    for code, (path, _name) in sorted(variants.items()):
        text = legacy.read_file(source_root, path)
        sources[code] = (path, text)
        facts = legacy.read_content(path, text)
        if facts.title:
            titles[code] = facts.title
        figures.update(facts.graphics)

    near = sources[sorted(sources)[0]][0]
    graphics = figure_map(source_root, figures, near)

    own_sections = []
    for code in sorted(sources):
        path, text = sources[code]
        # Planned, not just applied, so `migrate` without --apply already
        # reports everything a human has to decide.
        result = transform_content(text, source_path=path, figures=graphics)
        for section in result.sections:
            if section not in own_sections:
                own_sections.append(section)
        notes.extend("%s: %s" % (code, note) for note in result.notes)

    if own_sections:
        decisions.append(
            "dónde va su sección, que ahora declara ella misma: %s"
            % ", ".join("`%s`" % title for title in own_sections[:4])
        )

    if not titles:
        decisions.append("no se ha podido extraer ningún título; hay que "
                         "escribir uno por idioma")
    else:
        for code in variants:
            if code not in titles:
                decisions.append(
                    "sin título en `%s`; heredará el de otro idioma" % code)

    # Metadata the legacy system simply does not record.
    decisions.append(
        ("etiquetas más allá de `%s`, prerrequisitos, objetivos y duración"
         % ", ".join(tags)) if tags
        else "etiquetas, prerrequisitos, objetivos y duración")

    if any_name.implicit:
        notes.append(
            "el nombre del fichero no lleva token de idioma; se ha tratado como "
            "castellano, que es lo que indica cada caso medido"
        )

    return UnitPlan(
        target=target,
        area=area,
        kind=kind,
        category=repo_mod.slugify(category),
        topic=repo_mod.slugify(topic),
        tags=tags,
        sources={code: path for code, (path, _n) in variants.items()},
        reference=reference,
        title=titles,
        figures=sorted(figures),
        notes=notes,
        needs_decision=decisions,
        ordinal=ordinal,
        source_dir=directory,
    )


# --------------------------------------------------------------------------
# Compositions
# --------------------------------------------------------------------------
#
# A legacy master is a document: a preamble, a title, and an ordered list of
# `\import{../../../../00classnotes/...}` lines with `\section` headings
# between them. Everything except the ordered list is boilerplate Didacta
# supplies, so migrating a master means keeping the list -- and the headings,
# which is where the sections these files declare are supposed to live.
#
# Measured over the repository: 437 masters, 4012 unit references, 435 of them
# importing a `classinfo` file for the course metadata, and 668 references
# commented out. Those 668 are editorial history -- what the author chose to
# leave out that year -- so they are carried across as comments rather than
# dropped.

#: `\import{dir}{file}` and `\subimport{dir}{file}` -- 13176 uses.
_IMPORT = re.compile(r"\\(sub)?import\s*\{([^{}]*)\}\s*\{([^{}]*)\}")

#: `\input{path}` and `\include{path}`. A minority form -- 36 references into
#: the library against several thousand `\import` -- but a unit reference all
#: the same, and ignoring it leaves those compositions short.
_INPUT = re.compile(r"\\(?:input|include)\s*\{([^{}]*)\}")

#: A figure pulled straight out of the library by a master. 177 of these
#: exist. They are not unit references and must not be read as such, but they
#: do need saying: the file they point at is not where they will look for it.
_MASTER_GRAPHIC = re.compile(
    r"\\includegraphics\s*\*?\s*(?:\[[^\]]*\])?\s*\{([^{}]*)\}")


def _library_references(text):
    """Every path in ``text`` that points into the legacy library.

    ``(kind, directory, name)`` triples, where kind is ``import``, ``input`` or
    ``graphic``. Used both to decide whether a file is a composition at all and
    to read the composition itself.
    """
    out = []
    for match in _IMPORT.finditer(text):
        if legacy.CLASSNOTES in match.group(2):
            out.append(("import", match.group(2), match.group(3)))
    for match in _INPUT.finditer(text):
        if legacy.CLASSNOTES in match.group(1):
            directory, _, name = match.group(1).rpartition("/")
            out.append(("input", directory, name))
    for match in _MASTER_GRAPHIC.finditer(text):
        if legacy.CLASSNOTES in match.group(1):
            directory, _, name = match.group(1).rpartition("/")
            out.append(("graphic", directory, name))
    return out

#: A heading in a master, wherever on the line it sits. Anchoring it to the
#: start of the line missed three real shapes: an indented ``\section``, a
#: heading followed by an import on the same line, and a heading wrapped in
#: ``\onlyslides{...}`` so that it appears in one medium only.
_MASTER_SECTION = re.compile(r"\\(?P<level>sub)*section\*?\s*\{")

#: Legacy medium macros and their Didacta names. Only ``\onlybook`` changed.
_MEDIUM_MACROS = {"onlybook": "onlynotes"}

#: A heading wrapped in a medium conditional. ``year.yaml`` has no way to say
#: "this heading only on slides", so these stay in the master and are reported.
_CONDITIONAL = re.compile(
    r"\\(only(?:slides|book|notes|teacher|student|full|brief))\s*\{\s*$")

#: Which legacy preamble template means which kind of document. A document
#: kind is a key of `profiles.FAMILY_FOR_KIND`, not a unit kind: it decides
#: which profiles the document builds by default.
KIND_BY_TEMPLATE = (
    ("Problems-template", "problems"),
    # Extra examples carry answer levels, like a problem sheet.
    ("Extra-examples-template", "problems"),
    ("FAQ-template", "handout"),
    ("Handouts-template", "handout"),
    ("Book-template", "theory"),
    ("Presentations-template", "theory"),
)

#: Folder names in a master's path that say what kind of document it is. The
#: path is a stronger signal than the template, because a seminar and a lecture
#: are both built from Presentations-template.
KIND_BY_MASTER_FOLDER = {
    "seminarios": "seminar", "seminaris": "seminar", "seminars": "seminar",
    "seminario": "seminar", "seminari": "seminar", "seminar": "seminar",
    "practicas": "practical", "practiques": "practical",
    "practica": "practical", "practicals": "practical",
    "examen": "exam", "examenes": "exam", "exams": "exam", "exam": "exam",
    "examens": "exam", "examenes-online": "exam",
    "problemas": "problems", "problems": "problems", "problemes": "problems",
    "review-exercises": "problems", "review-practice": "problems",
    "contenidos": "handout", "contents": "handout", "continguts": "handout",
    "handouts": "handout", "faq": "handout",
}

#: Folders inside a document directory that hold the master rather than being
#: the document. The document is named by the folder above them.
_MASTER_FOLDERS = {
    "presentacio", "presentacion", "presentaciones", "presentacions",
    "presentation", "presentations",
    "contenidos", "continguts", "contents",
    "notas", "notes", "info",
}


class DocumentPlan:
    """One legacy master, and the Didacta document it becomes."""

    __slots__ = (
        "course", "year", "id", "segments", "titles", "kind", "language",
        "structure", "source", "notes", "needs_decision",
    )

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        for slot in ("structure", "notes", "needs_decision", "segments"):
            if getattr(self, slot) is None:
                setattr(self, slot, [])
        if self.titles is None:
            self.titles = {}

    @property
    def unit_count(self):
        return sum(1 for kind, _ in self.structure if kind in ("unit", "problem"))

    @property
    def unresolved(self):
        return [value for kind, value in self.structure if kind == "unresolved"]


class CoursePlan:
    """One subject, with the years of it that exist."""

    __slots__ = ("id", "titles", "code", "degrees", "institution",
                 "departments", "teacher", "language", "group", "years",
                 "source", "notes")

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))
        for slot in ("titles", "degrees", "departments"):
            if getattr(self, slot) is None:
                setattr(self, slot, {})
        if self.years is None:
            self.years = {}
        if self.notes is None:
            self.notes = []


class CoursePlanSet:
    """Every composition a migration would create."""

    def __init__(self, source_root, target_root):
        self.source_root = source_root
        self.target_root = target_root
        self.courses = {}
        self.skipped = []
        self.errors = []

    @property
    def documents(self):
        return [doc for course in self.courses.values()
                for docs in course.years.values() for doc in docs]

    @property
    def decisions(self):
        return [doc for doc in self.documents if doc.needs_decision]

    def summary(self):
        documents = self.documents
        return {
            "courses": len(self.courses),
            "years": sum(len(c.years) for c in self.courses.values()),
            "documents": len(documents),
            "references": sum(d.unit_count for d in documents),
            "unresolved": sum(len(d.unresolved) for d in documents),
        }


class UnitIndex:
    """Legacy source path -> Didacta reference, from a unit plan.

    A composition names a unit without its language (``functional/x/y``); the
    legacy master named a specific language variant, so every variant maps to
    the same reference. That collapse is the point of the whole exercise.

    Lookup is deliberately forgiving, because the legacy import paths are not
    reliable and the intent is never in doubt:

    * the extension is optional in ``\\import``;
    * a master's ``../../../../`` chain is sometimes one level short, so the
      path resolves inside the academic-year folder instead of at the root --
      it works only because ``import`` searches from the importing file;
    * the case does not always match the folder on disk (``03Bases`` for
      ``03bases``), which passes unnoticed on macOS and would break a Linux
      build.

    In every one of those the part of the path from ``00classnotes/`` onwards
    says exactly which file was meant, so that is what is matched on.
    """

    def __init__(self, units):
        self.exact = {}
        self.by_tail = {}
        for unit in units:
            reference = "/".join(unit.relpath.split("/")[1:])
            entry = (reference, unit.area, unit)
            for source in unit.sources.values():
                self.exact[source] = entry
                self.by_tail.setdefault(_tail(source).lower(), entry)

    def lookup(self, path):
        """``(reference, area, unit, how)``, or None."""
        entry = self.exact.get(path) or self.exact.get(path + ".tex")
        if entry is not None:
            return entry + ("exact",)
        for candidate in (_tail(path).lower(), _tail(path).lower() + ".tex"):
            entry = self.by_tail.get(candidate)
            if entry is not None:
                return entry + ("tail",)
        return None

    def __len__(self):
        return len(self.exact)


def _tail(path):
    """The part of a path from ``00classnotes/`` onwards."""
    normalised = path.replace("\\", "/")
    marker = legacy.CLASSNOTES + "/"
    index = normalised.rfind(marker)
    if index < 0:
        return normalised
    return normalised[index + len(marker):]


def unit_index(units):
    return UnitIndex(units)


def plan_courses(source_root, target_root, units, *, year=None):
    """Work out how the legacy masters map onto Didacta compositions.

    Reads only. ``units`` is the unit plan, needed to turn a legacy file path
    into the reference the migrated unit will answer to.
    """
    plan = CoursePlanSet(source_root, target_root)
    index = UnitIndex(units)

    try:
        paths = legacy.git_files(source_root, "*.tex")
    except RuntimeError as exc:
        plan.errors.append(str(exc))
        return plan

    years = dict(legacy.year_dirs(source_root))

    masters = []
    for path in paths:
        top = path.replace("\\", "/").split("/")[0]
        if top in (legacy.CLASSNOTES, "Files", "didacta"):
            continue
        text = legacy.read_file(source_root, path)
        if legacy.CLASSNOTES not in text:
            continue
        references = _library_references(text)
        if not any(kind in ("import", "input") for kind, _d, _n in references):
            # A file whose only tie to the library is a figure, or a mention in
            # a comment, is not a composition. Calling it one produces an empty
            # document and buries the real ones.
            plan.skipped.append((
                path,
                "menciona la biblioteca pero no incluye ninguna unidad"
                if not references else
                "solo saca una figura de la biblioteca, no incluye unidades",
            ))
            continue
        masters.append((path, text))

    classinfos = {}

    for path, text in masters:
        parts = path.replace("\\", "/").split("/")
        academic_year = years.get(parts[0])
        if academic_year is None:
            plan.skipped.append((
                path,
                "no está bajo un curso académico, así que no se sabe a qué año "
                "pertenece; hay que colocarlo a mano",
            ))
            continue
        if year and academic_year != year:
            continue
        if len(parts) < 3:
            plan.skipped.append((path, "no está dentro de una asignatura"))
            continue

        subject_dir = parts[1]
        course_id = repo_mod.slugify(subject_dir)
        course = plan.courses.get(course_id)
        if course is None:
            course = _plan_course(source_root, parts[0], subject_dir, course_id,
                                  classinfos)
            plan.courses[course_id] = course

        document = _plan_document(source_root, path, text, parts, index,
                                  course, academic_year)
        course.years.setdefault(academic_year, []).append(document)

    for course in plan.courses.values():
        for documents in course.years.values():
            _resolve_duplicate_ids(documents)
            documents.sort(key=lambda doc: doc.source)

    return plan


def _plan_course(source_root, year_dir, subject_dir, course_id, cache):
    """Course metadata, read from the subject's ``classinfo`` file."""
    directory = "%s/%s" % (year_dir, subject_dir)
    info = {}
    source = None
    try:
        names = sorted(os.listdir(os.path.join(source_root, directory)))
    except OSError:
        names = []
    for name in names:
        if name.startswith("classinfo") and name.endswith(".tex"):
            source = "%s/%s" % (directory, name)
            if source in cache:
                info = cache[source]
            else:
                info = legacy.parse_classinfo(legacy.read_file(source_root, source))
                cache[source] = info
            break

    language = legacy.language_from_classinfo(info) if info else None
    # `\classlong` is the real title; the folder name is the fallback, and it
    # carries the ordering prefix the folder listing needed.
    title = (info.get("classlong") or info.get("class")
             or _folder_title(subject_dir))

    notes = []
    if source is None:
        notes.append(
            "no se ha encontrado classinfo*.tex, así que los metadatos de la "
            "asignatura (código, titulación, departamento) hay que escribirlos"
        )

    # `classextralong` is the long title with the degree appended after a
    # \newline; that is where the degree comes from when it is recorded at all.
    degree = None
    extra = info.get("classextralong") or ""
    if extra:
        tail = re.split(r"\s*\(", extra, 1)
        if len(tail) == 2:
            degree = tail[1].rstrip(") ").strip()

    return CoursePlan(
        id=course_id,
        titles={language or "es": title} if title else {},
        code=info.get("code"),
        degrees={language or "es": degree} if degree else {},
        institution=info.get("institute"),
        departments={language or "es": info["department"]}
        if info.get("department") else {},
        teacher=info.get("profesor"),
        language=language,
        group=info.get("sec"),
        years={},
        source=source,
        notes=notes,
    )


#: 84 masters write their title as `\\input{../chapterName.txt}`, and 48 of
#: those files exist. The file holds the title, so it is read rather than
#: reported as a macro that could not be expanded.
_TITLE_INPUT = re.compile(r"\\input\s*\{([^}]+)\}")


def _title_from_input(source_root, master_dir, value):
    """Follow an ``\\input`` in a title and return what the file says."""
    match = _TITLE_INPUT.search(value or "")
    if match is None:
        return None
    relative = os.path.normpath(
        os.path.join(master_dir, match.group(1).strip())).replace("\\", "/")
    try:
        content = legacy.read_file(source_root, relative)
    except OSError:
        return None
    lines = [line.strip() for line in content.split("\n") if line.strip()]
    if not lines:
        return None
    return legacy.clean_text(lines[0])


def _plan_document(source_root, path, text, parts, index, course, academic_year):
    """One master: its id, title, language, kind and ordered structure."""
    notes = []
    decisions = []

    structure, structure_notes, languages = _read_structure(
        text, os.path.dirname(path), index)
    notes.extend(structure_notes)

    kind = _kind_of_master(text, parts)
    segments, title_from_path = _document_identity(parts)

    # The title, in order of how much the source actually says.
    title = None
    master_dir = os.path.dirname(path)
    match = re.search(r"\\newcommand\s*\{\\chapterTitle\}\s*\{", text)
    if match:
        value, _ = legacy.read_group(text, match.end() - 1)
        if value:
            title = (_title_from_input(source_root, master_dir, value)
                     or legacy.clean_text(value))
    if not title:
        match = re.search(r"^\s*\\title\s*\{", text, re.M)
        if match:
            value, _ = legacy.read_group(text, match.end() - 1)
            # A legacy \title is usually the course name plus the chapter, so
            # only the part that is not already the course name is a title.
            title = (_title_from_input(source_root, master_dir, value or "")
                     or _title_tail(legacy.clean_text(value or "")))
    if not title:
        title = title_from_path
        notes.append(
            "el título sale del nombre de la carpeta; el fichero no lo declara"
        )

    language = _dominant(languages) or course.language or "es"
    distinct = {code for code in languages if code}
    if len(distinct) > 1:
        decisions.append(
            "en qué idioma va este documento: importa unidades en %s, y un "
            "documento de Didacta se compila en un solo idioma"
            % ", ".join("`%s`" % code for code in sorted(distinct))
        )

    title, macros = _drop_legacy_macros(title)
    if macros:
        decisions.append(
            "el título llevaba %s, macro(s) que Didacta no puede suministrar. "
            "Se han quitado porque dejarlas no compila, así que hay que "
            "escribir el título real"
            % ", ".join("`\\%s`" % name for name in macros)
        )
    if not title:
        title = title_from_path

    unresolved = [value for kind_, value in structure if kind_ == "unresolved"]
    if unresolved:
        decisions.append(
            "%d referencia(s) que no apuntan a ninguna unidad migrada: %s"
            % (len(unresolved), ", ".join("`%s`" % ref for ref in unresolved[:3]))
        )

    if not any(kind_ in ("unit", "problem") for kind_, _ in structure):
        notes.append(
            "no importa ninguna unidad migrada, así que la composición queda vacía"
        )

    return DocumentPlan(
        course=course.id,
        year=academic_year,
        id=segments[-1],
        segments=segments,
        titles={language: title},
        kind=kind,
        language=language,
        structure=structure,
        source=path,
        notes=notes,
        needs_decision=decisions,
    )


#: Legacy metadata macros Didacta defines as aliases onto its own course and
#: document data (see the "Legacy metadata names" block in didacta.sty). These
#: are left alone: content across the library builds its own page headers out
#: of them, and they now expand to the right value in the language being built.
LEGACY_ALIASED_MACROS = frozenset((
    "chapterName", "chapterTitle", "class", "classlong", "classextralong",
    "classshort", "profesor", "professor", "dateshort", "code",
    "institute", "department", "exerciseName", "solutionName",
))

#: Legacy macros with no Didacta equivalent, because they were about how the
#: old build found and configured its files rather than about the material.
#: Left in place they are an undefined control sequence -- and hyperref expands
#: a heading to make the PDF bookmark, so one in a ``\section`` fails the whole
#: document rather than one line.
LEGACY_UNSUPPORTED_MACROS = frozenset((
    "documentclassname", "documentclassoptions", "texpath", "nohyphens",
))

#: Both, for reporting.
LEGACY_PREAMBLE_MACROS = LEGACY_ALIASED_MACROS | LEGACY_UNSUPPORTED_MACROS

_MACRO = re.compile(r"\\([a-zA-Z@]+)")


def _leftover_macros(value):
    """Legacy-preamble macros still present in a piece of text."""
    return sorted({name for name in _MACRO.findall(value or "")
                   if name in LEGACY_PREAMBLE_MACROS})


def _drop_legacy_macros(value):
    """``(text, macros)`` with the unsupportable macros taken out.

    Only the ones Didacta cannot supply. The metadata names stay: they are
    aliases now, so ``\section{Tema 1: \chapterName}`` expands to the
    document title, which is what the author meant by it.

    What is left of the text is kept -- ``Tema 1`` is a usable heading, and
    better than nothing while the author writes the real one.
    """
    macros = sorted({name for name in _MACRO.findall(value or "")
                     if name in LEGACY_UNSUPPORTED_MACROS})
    if not macros:
        return value, []
    out = _MACRO.sub(
        lambda match: "" if match.group(1) in LEGACY_UNSUPPORTED_MACROS
        else match.group(0),
        value or "")
    out = re.sub(r"\s+", " ", out).strip(" \t:;,-\u2013\u2014")
    return out, macros


def _read_structure(text, master_dir, index):
    """The ordered composition: headings, units, and what was commented out.

    Read in source order, because order *is* the content of a composition. Each
    line is scanned for headings and imports together and emitted by position,
    since five masters put a ``\\subsection`` and the ``\\import`` it introduces
    on one line -- treating the heading as consuming the line dropped the unit.

    A commented-out entry is kept as a comment: 668 imports and 74 headings are
    commented out across the library, and each one records something the author
    chose to leave out that year.
    """
    structure = []
    notes = []
    languages = []
    approximate = 0
    conditional = []
    borrowed = []
    stripped = set()
    emptied = []

    for line in text.split("\n"):
        commented = legacy.is_commented(line)
        events = []

        for match in _MASTER_SECTION.finditer(line):
            brace = line.find("{", match.end() - 1)
            if brace < 0:
                continue
            title, _after = legacy.read_group(line, brace)
            if not title:
                continue
            wrapper = _CONDITIONAL.search(line[: match.start()])
            # `\subsection` nests under `\section`, and the nesting carries
            # meaning: "Derivación" contains "Derivadas direccionales".
            level = "subsection" if match.group("level") else "section"
            cleaned, macros = _drop_legacy_macros(legacy.clean_text(title))
            if macros:
                stripped.update(macros)
            if not cleaned:
                # Nothing left but the macro: there is no heading to write.
                emptied.append(macros)
                continue
            events.append((match.start(), level, cleaned,
                           wrapper.group(1) if wrapper else None))

        for match in _IMPORT.finditer(line):
            directory, name = match.group(2), match.group(3)
            if legacy.CLASSNOTES not in directory:
                continue
            events.append((match.start(), "import",
                           _resolve_import(master_dir, directory, name), None))

        for match in _INPUT.finditer(line):
            if legacy.CLASSNOTES not in match.group(1):
                continue
            directory, _, name = match.group(1).rpartition("/")
            events.append((match.start(), "import",
                           _resolve_import(master_dir, directory, name), None))

        for match in _MASTER_GRAPHIC.finditer(line):
            if legacy.CLASSNOTES in match.group(1):
                borrowed.append(match.group(1))

        for _position, kind, value, wrapper in sorted(events):
            if kind in ("section", "subsection"):
                if wrapper:
                    # Only meaningful in one medium, which `year.yaml` cannot
                    # express. Kept in the master so the PDF is unchanged, and
                    # recorded so the author can promote it.
                    conditional.append((value, wrapper))
                    structure.append(
                        ("conditional-" + kind, (wrapper, value)))
                    continue
                structure.append(
                    ("commented-" + kind if commented else kind, value))
                continue

            found = index.lookup(value)
            if found is None:
                structure.append(
                    ("commented-unresolved" if commented else "unresolved", value))
                continue
            reference, area, _unit, how = found
            if how == "tail":
                approximate += 1
            entry = "problem" if area == repo_mod.PROBLEMS else "unit"
            structure.append(
                ("commented-" + entry if commented else entry, reference))
            if not commented:
                info = legacy.read_name(os.path.basename(value))
                languages.append(None if info.implicit else info.language)

    if borrowed:
        notes.append(
            "saca %d figura(s) directamente de la biblioteca (%s); tras la "
            "migración esas rutas no existen, así que la figura tiene que ir "
            "en la unidad que la usa o en un directorio compartido"
            % (len(borrowed),
               ", ".join("`%s`" % os.path.basename(name)
                         for name in sorted(set(borrowed))[:3]))
        )

    if conditional:
        notes.append(
            "tiene %d encabezado(s) que solo salen en un medio (%s); "
            "`year.yaml` no sabe expresar eso, así que hay que decidir si el "
            "apartado va en los dos o se queda en el `.tex`"
            % (len(conditional),
               ", ".join("`\\%s{%s}`" % (wrapper, title)
                         for title, wrapper in conditional[:3]))
        )

    if stripped:
        notes.append(
            "algún encabezado llevaba %s, macro(s) del preámbulo antiguo que "
            "Didacta no puede suministrar. Se han quitado del texto, porque "
            "hyperref expande el encabezado para el marcador del PDF y una "
            "macro indefinida ahí tumba el documento entero; hay que escribir "
            "el encabezado real"
            % ", ".join("`\\%s`" % name for name in sorted(stripped))
        )
    if emptied:
        notes.append(
            "%d encabezado(s) no eran más que una macro del preámbulo antiguo, "
            "así que no queda texto y se han quitado" % len(emptied)
        )

    unresolved = [value for kind, value in structure if kind == "unresolved"]
    if unresolved:
        notes.append(
            "%d importación(es) apuntan a ficheros que no están en el "
            "repositorio git (sin seguimiento, borrados o mal escritos)"
            % len(unresolved)
        )
    if approximate:
        notes.append(
            "%d importación(es) no coincidían exactamente con la ruta del "
            "fichero (mayúsculas distintas o un ../ de menos) y se han "
            "resuelto por el nombre; funcionaban en macOS pero no en Linux"
            % approximate
        )
    return structure, notes, languages


def _resolve_import(master_dir, directory, name):
    """The repository-relative path a master's ``\\import`` points at."""
    joined = os.path.join(master_dir, directory, name)
    return os.path.normpath(joined).replace("\\", "/")


def _kind_of_master(text, parts):
    """The document kind, from where the master sits and what it loads.

    The path wins: a seminar and a lecture both load Presentations-template, so
    the template alone would call every seminar a lecture and build the wrong
    set of profiles for 49 of them.
    """
    for part in reversed(parts[2:-1]):
        kind = KIND_BY_MASTER_FOLDER.get(repo_mod.slugify(part))
        if kind:
            return kind
    for template, kind in KIND_BY_TEMPLATE:
        if template in text:
            return kind
    return "theory"


def _document_identity(parts):
    """``(segments, title)`` for a master, from where it sits.

    The folders below the subject, outermost first, with the ones that merely
    hold a master dropped: ``01Tema 1 - .../00Presentacio/00Tema-1.tex`` gives
    ``["tema-1-preliminars-espais-normats"]``.

    A list rather than a name, because the innermost folder is often not
    unique. Two real shapes force this:

    * a chapter folder and the master folder inside it carry the same name
      (``01 - Introduction to ODEs/Introduction to ODEs/00Notes.tex``), which
      must not become ``introduction-to-odes-introduction-to-odes``;
    * every chapter has its own ``Review exercises`` folder, so the innermost
      name alone collides across chapters and the chapter has to come back in.

    The caller takes the innermost segment and works outwards only as far as
    uniqueness requires.
    """
    segments = []
    for part in parts[2:-1]:
        slug = repo_mod.slugify(part)
        if not slug or slug in _MASTER_FOLDERS:
            continue
        # A chapter whose master folder repeats its name says it once.
        if segments and segments[-1] == slug:
            continue
        segments.append(slug)

    if not segments:
        stem = os.path.splitext(parts[-1])[0]
        segments = [repo_mod.slugify(stem) or "documento"]
        return segments, _folder_title(stem)

    # The title names the document, so it comes from the folder the id does.
    titles = [part for part in parts[2:-1]
              if repo_mod.slugify(part) == segments[-1]]
    return segments, _folder_title(titles[-1] if titles else segments[-1])


def _folder_title(name):
    """A readable title from a folder name.

    Keeps the punctuation the author wrote -- ``Tema 1 - Preliminars espais
    normats`` reads as a title -- and drops only the ordering prefix, which is
    what the folder listing needed and the document does not.
    """
    stripped = re.sub(r"^\d+[\s_.-]*", "", name)
    if not re.search(r"[A-Za-zÀ-ÿ]", stripped):
        stripped = name
    stripped = re.sub(r"\s+", " ", stripped.replace("_", " ")).strip(" -–—")
    return (stripped[0].upper() + stripped[1:]) if stripped else ""


def _title_tail(value):
    """Drop the course name a legacy ``\\title`` prepends to the real title."""
    value = re.sub(r"\\class\w*", "", value or "")
    value = re.sub(r"\\chapterTitle", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip(" \t\n-\u2013\u2014:")


def _dominant(values):
    counts = {}
    for value in values:
        if value:
            counts[value] = counts.get(value, 0) + 1
    if not counts:
        return None
    return max(sorted(counts), key=lambda key: counts[key])


def _resolve_duplicate_ids(documents):
    """Give every document in a year a distinct id.

    The innermost folder is the natural id. When it is not unique, the path
    already holds what distinguishes them, and which part depends on why they
    collided:

    * **the same chapter, twice.** A chapter with a lecture master in
      ``00Presentacio`` and a summary in ``90Contenidos`` -- the chapter is the
      lecture, and the summary is a variant of it, so the lecture keeps
      ``tema-1`` and the summary becomes ``tema-1-contenidos``.
    * **different chapters, same subfolder name.** Every chapter has its own
      ``Review exercises``. Neither has a better claim to the bare name, so
      *all* of them take the chapter:
      ``first-order-differential-equations-review-exercises``. Letting the
      first one keep the plain id would make the set read as though one chapter
      were the default.

    Only when the path says nothing at all does a number appear, and that is
    reported as needing a real id.
    """
    groups = {}
    for document in documents:
        groups.setdefault(_last_segment(document), []).append(document)

    for group in groups.values():
        distinct_paths = {tuple(document.segments) for document in group}
        # More than one path means the bare name belongs to none of them.
        qualify_all = len(distinct_paths) > 1

        # Non-container masters first: within one chapter the lecture is the
        # document the chapter is about, so it keeps the shorter id.
        ordered = sorted(
            group,
            key=lambda doc: (bool(_master_folder_suffix(doc)), doc.source),
        )
        taken = set()
        for document in ordered:
            for candidate, meaningful in _id_candidates(document, qualify_all):
                if candidate not in taken:
                    break
            if not meaningful:
                document.needs_decision.append(
                    "un id propio: `%s` lo usan varios documentos del mismo "
                    "curso y no hay nada en la ruta que los distinga, así que "
                    "este ha quedado como `%s`"
                    % (_last_segment(document), candidate)
                )
            taken.add(candidate)
            document.id = candidate

    # The groups were independent, so a qualified id could in principle land
    # on another group's name. Cheap to check, and silent data loss otherwise.
    _break_remaining_ties(documents)


def _last_segment(document):
    return (document.segments or [document.id])[-1]


def _id_candidates(document, qualify_all=False):
    """``(id, meaningful)`` pairs to try for a document, best first."""
    segments = document.segments or [document.id]
    suffix = _master_folder_suffix(document)

    if not qualify_all:
        yield segments[-1], True
        if suffix and suffix != segments[-1]:
            yield "%s-%s" % (segments[-1], suffix), True

    # Work outwards through the path: the chapter, then the one above it.
    for depth in range(2, len(segments) + 1):
        yield "-".join(segments[-depth:]), True
        if suffix:
            yield "-".join(segments[-depth:]) + "-" + suffix, True

    if qualify_all and suffix:
        yield "%s-%s" % (segments[-1], suffix), True

    counter = 2
    while True:
        yield "%s-%d" % (segments[-1], counter), False
        counter += 1


def _break_remaining_ties(documents):
    seen = {}
    for document in sorted(documents, key=lambda doc: doc.source):
        if document.id not in seen:
            seen[document.id] = document
            continue
        base, counter = document.id, 2
        while "%s-%d" % (base, counter) in seen:
            counter += 1
        document.id = "%s-%d" % (base, counter)
        document.needs_decision.append(
            "un id propio: `%s` ya estaba ocupado, así que este ha quedado "
            "como `%s`" % (base, document.id)
        )
        seen[document.id] = document


def _master_folder_suffix(document):
    """The folder holding the master, when it qualifies the document.

    ``.../01Tema 1 - .../90Contenidos/00Contenidos.tex`` -> ``contenidos``: a
    summary of that chapter rather than the chapter itself.

    Empty when the folder is the document -- either a bare
    ``00Presentacio`` that carries no meaning, or a folder whose name is
    already the document's own (``01 - Introduction to ODEs/Introduction to
    ODEs/``), which is the lecture master and not a qualified variant of it.
    """
    parent = os.path.basename(os.path.dirname(document.source.replace("\\", "/")))
    slug = repo_mod.slugify(parent)
    if not slug or slug in ("presentacion", "presentacio", "presentation"):
        return ""
    if document.segments and slug == document.segments[-1]:
        return ""
    return slug

# --------------------------------------------------------------------------
# Applying
# --------------------------------------------------------------------------

UNIT_META = """# {title}
#
# Migrated from:
{sources}
#
# The fields marked TODO are the ones the legacy material did not record.
# Filling them in is what makes this unit safe to reuse elsewhere.

id: {identifier}
kind: {kind}

title:
{titles}
category: {category}
topic: {topic}
tags: [{tags}]

reference: {reference}

# Only languages that exist are listed; absence is what `missing` means.
languages:
{languages}
# TODO: what this unit assumes, and what a student can do after it.
prerequisites: []
objectives: []

duration_minutes: null
difficulty: null
"""


def apply_plan(plan, *, dry_run=True, on_unit=None):
    """Create the Didacta content repository described by ``plan``.

    Returns ``(created, problems)``. With ``dry_run`` nothing is written.
    """
    created = []
    problems = []

    if not dry_run:
        os.makedirs(plan.target_root, exist_ok=True)
        settings = os.path.join(plan.target_root, repo_mod.SETTINGS)
        if not os.path.isfile(settings):
            with open(settings, "w", encoding="utf-8") as handle:
                handle.write(_SETTINGS_TEMPLATE)
            created.append(repo_mod.SETTINGS)

    for unit in plan.units:
        directory = os.path.join(plan.target_root, unit.relpath)
        try:
            files = _apply_unit(plan, unit, directory, dry_run=dry_run)
            created.extend(files)
            if on_unit:
                on_unit(unit, files)
        except (OSError, MigrationError) as exc:
            problems.append("%s: %s" % (unit.relpath, exc))

    return created, problems


_SETTINGS_TEMPLATE = """# A Didacta content repository, created by migration.

name: Teaching material
languages: [es, va, en]
default_language: es
build_dir: .didacta-build
"""


def _apply_unit(plan, unit, directory, *, dry_run):
    files = []

    if not dry_run:
        os.makedirs(directory, exist_ok=True)

    near = next(iter(sorted(unit.sources.values())))
    graphics = figure_map(plan.source_root, unit.figures, near)

    for code, source in sorted(unit.sources.items()):
        text = legacy.read_file(plan.source_root, source)
        # Notes were already collected during planning; re-adding them here
        # would double every entry in the report.
        result = transform_content(text, source_path=source, figures=graphics)
        target = os.path.join(directory, "%s.tex" % code)
        if not dry_run:
            with open(target, "w", encoding="utf-8") as handle:
                handle.write(result.text)
        files.append(os.path.relpath(target, plan.target_root))

    meta_path = os.path.join(directory, "unit.yaml")
    if not dry_run:
        with open(meta_path, "w", encoding="utf-8") as handle:
            handle.write(_render_meta(unit))
    files.append(os.path.relpath(meta_path, plan.target_root))

    # Figures live with their unit, so moving the unit moves them, and the
    # references in the .tex were rewritten to match.
    for found, name in figure_targets(plan.source_root, unit):
        target = os.path.join(directory, "figures", name)
        if not dry_run:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(os.path.join(plan.source_root, found), target)
        files.append(os.path.relpath(target, plan.target_root))

    return files


def figure_map(source_root, references, near):
    """``{legacy reference: new reference}`` for one unit's graphics.

    Everything lands in the unit's own ``figures/`` directory, so moving the
    unit moves its figures.

    Keyed by the file each reference resolves to, not by the reference, because
    the same file is often referred to two ways: ``\includegraphics`` takes the
    extension as optional, and one unit writes both ``img/corte1`` and
    ``img/corte1.png``. Those are one figure and must not be copied twice under
    two names.

    Two genuinely different files can still share a base name, and then the old
    folder goes into the new name -- otherwise one silently replaces the other.

    ``near`` is any of the unit's legacy source paths: graphics are referenced
    relative to the file that includes them.
    """
    by_source = {}
    taken = set()

    for reference in sorted(references):
        found = _find_figure(source_root, near, reference)
        if found is None:
            continue
        if found in by_source:
            continue
        for name in _figure_names(found):
            if name not in taken:
                break
        taken.add(name)
        by_source[found] = "figures/%s" % name

    mapping = {}
    for reference in references:
        found = _find_figure(source_root, near, reference)
        if found is not None and found in by_source:
            mapping[reference] = by_source[found]
    return mapping


def _figure_names(found):
    """Names to try for a copied figure, least surprising first."""
    name = os.path.basename(found)
    yield name
    stem, extension = os.path.splitext(name)
    folder = repo_mod.slugify(os.path.basename(os.path.dirname(found)))
    if folder:
        yield "%s-%s%s" % (folder, stem, extension)
    counter = 2
    while True:
        yield "%s-%d%s" % (stem, counter, extension)
        counter += 1


def figure_targets(source_root, unit):
    """``[(legacy path, name under figures/)]`` for the files to copy.

    One entry per file, however many references point at it.
    """
    near = sorted(unit.sources.values())[0]
    mapping = figure_map(source_root, unit.figures, near)
    out = {}
    for reference, target in sorted(mapping.items()):
        found = _find_figure(source_root, near, reference)
        if found is not None:
            out[found] = os.path.basename(target)
    return sorted(out.items())


def _find_figure(source_root, near, reference):
    """Locate a figure a legacy unit refers to.

    Graphics are referenced without an extension and relative to the importing
    file, so several candidates have to be tried. ``near`` is the legacy path
    of the file doing the including.
    """
    # A handful of references are written `/img/flecha` or `./img/flecha`.
    # The leading slash is a slip -- there is no such absolute path, and the
    # legacy build found the file only because `import` searched from the
    # importing file -- so it is treated as relative.
    reference = reference.strip().lstrip("/")
    if reference.startswith("./"):
        reference = reference[2:]

    base = os.path.dirname(near)
    stem = reference
    for candidate_dir in (base, os.path.join(base, "img"), os.path.dirname(base)):
        for extension in ("", ".pdf", ".png", ".jpg", ".jpeg", ".eps"):
            candidate = os.path.normpath(os.path.join(candidate_dir, stem + extension))
            if os.path.isfile(os.path.join(source_root, candidate)):
                return candidate
    return None


def _render_meta(unit):
    identifier = "%s.%s.%s" % (unit.category, unit.topic,
                               os.path.basename(unit.target))
    if unit.area == repo_mod.PROBLEMS:
        identifier = "problems." + identifier

    title = unit.title.get(unit.reference) or legacy.humanize(
        os.path.basename(unit.target))

    titles = "".join(
        "  %s: %s\n" % (code, _quote(unit.title[code]))
        for code in legacy.LANGUAGES if code in unit.title
    )
    if not titles:
        titles = "  # TODO: no title could be extracted from the source\n" \
                 "  %s: %s\n" % (unit.reference, _quote(title))

    languages = "".join(
        # Everything arrives as `draft`: it has been moved, not reviewed in the
        # new system. Claiming otherwise would be the migration asserting a
        # review that never happened.
        "  %s: {status: draft}\n" % code for code in sorted(unit.sources)
    )

    sources = "".join("#   %s\n" % path for _, path in sorted(unit.sources.items()))

    return UNIT_META.format(
        title=title,
        sources=sources.rstrip("\n"),
        identifier=identifier,
        kind=unit.kind,
        titles=titles,
        category=unit.category,
        topic=unit.topic,
        tags=", ".join(unit.tags),
        reference=unit.reference,
        languages=languages,
    )


def _quote(text):
    """Quote a YAML scalar when it needs it.

    Backslashes are escaped because a double-quoted YAML scalar treats them as
    escapes, and a title that still carries a LaTeX macro would otherwise
    become `\c` -- an invalid escape, or worse a valid one meaning something
    else.
    """
    text = "" if text is None else str(text)
    if re.match(r"^[A-Za-z0-9À-ÿ][^:#\n\\\"]*$", text):
        return text
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % escaped


# --------------------------------------------------------------------------
# Applying compositions
# --------------------------------------------------------------------------

COURSE_META = """# {title}
#
# Migrated from {source}
#
# Metadata that does not change from year to year. The selection and order of
# content lives in the per-year files next to this one.

id: {identifier}
title:
{titles}{code}{degrees}{institution}{departments}{teacher}
# The language this subject is taught in. Sets the default for every document
# in it; an individual document may override.
language: {language}
"""

YEAR_META = """# {course} -- {year}
#
# Selection, order and structure. No content: every entry below is a reference
# into content/ or problems/. A new academic year copies this file and edits
# the list.
#
# Migrated from {sources}

course: {identifier}
year: {year}{group}
language: {language}

documents:
{documents}"""

DOCUMENT_MASTER = """% {title}
%
% Migrated from {source}
%
% The legacy master was {legacy_lines} lines: a documentclass incantation, a
% preamble, four \\import calls with ../../../../ paths and the theorem
% template chosen by hand for this language. What was worth keeping was the
% ordered list of units, and that now lives in year.yaml.

\\input{{didacta-bootstrap}}
\\usepackage{{didacta}}

%% Course metadata, the title and the section headings come from course.yaml
%% and year.yaml, in whichever language is being built. What is written in this
%% file is only a fallback, so that opening it and pressing compile still
%% produces the document it produced before.
\\DidactaCourse{{
  title   = {{{course_title}}},
  teacher = {{{teacher}}},
}}
\\DidactaDocument{{{title}}}

\\begin{{document}}
\\DidactaTitlePage
\\DidactaContents

{body}
\\end{{document}}
"""


def apply_courses(plan, *, dry_run=True):
    """Create the compositions described by ``plan``.

    Returns ``(created, problems)``. With ``dry_run`` nothing is written.
    """
    created = []
    problems = []

    for course in sorted(plan.courses.values(), key=lambda item: item.id):
        directory = os.path.join(plan.target_root, repo_mod.COURSES, course.id)
        try:
            if not dry_run:
                os.makedirs(directory, exist_ok=True)
            relative = "%s/%s/course.yaml" % (repo_mod.COURSES, course.id)
            if not dry_run:
                _write(os.path.join(directory, "course.yaml"),
                       _render_course(course))
            created.append(relative)

            for year in sorted(course.years):
                documents = course.years[year]
                year_dir = os.path.join(directory, year)
                if not dry_run:
                    os.makedirs(year_dir, exist_ok=True)
                    _write(os.path.join(year_dir, "year.yaml"),
                           _render_year(course, year, documents))
                created.append("%s/%s/%s/year.yaml"
                               % (repo_mod.COURSES, course.id, year))

                for document in documents:
                    name = "%s.tex" % document.id
                    if not dry_run:
                        _write(os.path.join(year_dir, name),
                               _render_master(plan, course, document))
                    created.append("%s/%s/%s/%s"
                                   % (repo_mod.COURSES, course.id, year, name))
        except OSError as exc:
            problems.append("%s: %s" % (course.id, exc))

    return created, problems


def _write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def _render_course(course):
    def block(values, key, todo):
        if not values:
            return "\n# TODO: %s\n%s:\n" % (todo, key)
        lines = "".join("  %s: %s\n" % (code, _quote(value))
                        for code, value in sorted(values.items()) if value)
        return "\n%s:\n%s" % (key, lines)

    titles = "".join("  %s: %s\n" % (code, _quote(value))
                     for code, value in sorted(course.titles.items()) if value)
    if not titles:
        titles = "  # TODO: no se ha podido leer el título de la asignatura\n"

    return COURSE_META.format(
        title=next(iter(course.titles.values()), course.id),
        source=course.source or "(sin classinfo)",
        identifier=course.id,
        titles=titles,
        code="\ncode: \"%s\"\n" % course.code if course.code
        else "\n# TODO: el código de la asignatura\ncode: null\n",
        degrees=block(course.degrees, "degree", "la titulación"),
        institution="\ninstitution: %s\n" % _quote(course.institution)
        if course.institution else "",
        departments=block(course.departments, "department", "el departamento"),
        teacher="\nteacher: %s\n" % _quote(course.teacher)
        if course.teacher else "",
        language=course.language or "es",
    )


def _render_year(course, year, documents):
    sources = ", ".join(
        sorted({os.path.dirname(os.path.dirname(doc.source)) for doc in documents})[:3]
    )
    group = ""
    if course.group:
        group = "\ngroup: %s" % _quote(course.group)

    blocks = []
    for document in documents:
        blocks.append(_render_document_entry(course, document))

    return YEAR_META.format(
        course=next(iter(course.titles.values()), course.id),
        year=year,
        sources=sources or "(varias carpetas)",
        identifier=course.id,
        group=group,
        language=course.language or "es",
        documents="\n".join(blocks),
    )


def _render_document_entry(course, document):
    lines = ["  - id: %s" % document.id]
    lines.append("    kind: %s" % document.kind)
    if document.language and document.language != (course.language or "es"):
        lines.append("    language: %s" % document.language)
    lines.append("    title:")
    for code, value in sorted(document.titles.items()):
        lines.append("      %s: %s" % (code, _quote(value)))
    for code in legacy.LANGUAGES:
        if code not in document.titles:
            lines.append("      # TODO: %s" % code)

    lines.append("    # Migrated from %s" % document.source)
    for note in document.notes:
        lines.append("    # nota: %s" % note)
    for decision in document.needs_decision:
        lines.append("    # TODO: %s" % decision)

    lines.append("    structure:")
    body = _render_structure(document, indent="      ")
    lines.append(body if body.strip() else
                 "      # TODO: esta composición quedó vacía")
    return "\n".join(lines) + "\n"


def _render_structure(document, indent):
    """The ordered structure, with what was commented out kept as comments."""
    lines = []
    for kind, value in document.structure:
        if kind in ("section", "subsection"):
            lines.append("%s- %s:" % (indent, kind))
            lines.append("%s    %s: %s" % (indent, document.language, _quote(value)))
            for code in legacy.LANGUAGES:
                if code != document.language:
                    lines.append("%s    # TODO: %s" % (indent, code))
        elif kind in ("commented-section", "commented-subsection"):
            lines.append("%s# %s desactivado: %s"
                         % (indent, kind.split("-", 1)[1], value))
        elif kind in ("conditional-section", "conditional-subsection"):
            wrapper, title = value
            lines.append(
                "%s# %s solo en un medio (\\%s), así que sigue en el .tex: %s"
                % (indent, kind.split("-", 1)[1], wrapper, title))
        elif kind in ("unit", "problem"):
            lines.append("%s- %s: %s" % (indent, kind, value))
        elif kind in ("commented-unit", "commented-problem"):
            # 668 of these exist. Each one records something the author chose
            # to leave out that year, which is worth keeping.
            lines.append("%s# - %s: %s" % (indent, kind.split("-", 1)[1], value))
        elif kind == "unresolved":
            lines.append("%s# TODO: no migrada: %s" % (indent, value))
        elif kind == "commented-unresolved":
            lines.append("%s# desactivada y no migrada: %s" % (indent, value))
    return "\n".join(lines)


def _render_master(plan, course, document):
    try:
        legacy_lines = len(
            legacy.read_file(plan.source_root, document.source).split("\n"))
    except OSError:
        legacy_lines = 0

    body = []
    for kind, value in document.structure:
        if kind in ("section", "subsection"):
            # In the language the old master was written in. `year.yaml` holds
            # it in every language and is the authority; this is the fallback
            # that keeps `pdflatex` on this file alone producing the document
            # it produced before, headings included.
            body.append("\\%s{%s}" % (kind, value))
        elif kind in ("commented-section", "commented-subsection"):
            body.append("%% \\%s{%s}" % (kind.split("-", 1)[1], value))
        elif kind in ("conditional-section", "conditional-subsection"):
            wrapper, title = value
            body.append("\\%s{\\%s{%s}}"
                        % (_MEDIUM_MACROS.get(wrapper, wrapper),
                           kind.split("-", 1)[1], title))
        elif kind == "unit":
            body.append("\\DidactaUnit{%s}" % value)
        elif kind == "problem":
            body.append("\\DidactaProblem{%s}" % value)
        elif kind in ("commented-unit", "commented-problem"):
            macro = ("DidactaUnit" if kind.endswith("unit") else "DidactaProblem")
            body.append("%% \\%s{%s}" % (macro, value))

    title = next(iter(document.titles.values()), document.id)
    return DOCUMENT_MASTER.format(
        title=title,
        source=document.source,
        legacy_lines=legacy_lines,
        course_title=next(iter(course.titles.values()), course.id),
        teacher=course.teacher or "",
        body="\n".join(body) if body else
        "%% TODO: esta composición quedó vacía al migrar",
    )
