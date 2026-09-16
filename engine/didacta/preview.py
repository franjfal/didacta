"""Compiling one unit on its own.

`didacta build` compiles a *document*: a composition of many units with a
title page, a table of contents and a course. That is the right unit of work
for producing what a class is given.

It is the wrong unit of work for the question someone asks while editing:
*«¿cómo queda esto?»* — this one unit, right now, in slides and in book form,
without building a 30-page tema around it.

So this wraps a single unit in the smallest document that will compile it and
hands that to the same engine. Two things follow from doing it this way rather
than with a separate code path:

* **the preamble is exactly the real one.** The preview goes through
  `didacta-bootstrap` and `\\usepackage{didacta}` like any document, so what
  comes out is what the unit will look like inside a tema. A preview built by
  a simplified preamble would be a preview of something else.

* **the preamble is not in the repository.** The generated wrapper lives in
  the build directory, which is not tracked. The `.tex` of a unit stays
  content, which is the whole point.
"""

from __future__ import annotations

import os
import re

from . import profiles as profiles_mod
from . import repo as repo_mod


#: Where the generated wrappers go, under the build directory. Not tracked,
#: and safe to delete: every one of them is regenerated on demand.
PREVIEW_DIR = "preview"


def slug(text):
    """A filesystem-safe stem for a preview file."""
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", text).strip("-")
    return cleaned or "unit"


def wrapper_text(reference, title, *, area=None):
    r"""The smallest document that compiles one unit.

    No title page and no table of contents: this is one unit, and a title page
    in front of a single definition is a page nobody wants to look at. The
    unit's own `\didactatitle` gives it a heading in every profile.

    `\DidactaDocument` is still set, because the profile uses it for the PDF
    metadata and the running head, and a preview whose header says
    `preview-1a2b` would be worse than one that says what it is.

    The include macro follows the *area*: `\DidactaUnit` resolves against
    `content/` and `\DidactaProblem` against `problems/`. Emitting
    `\DidactaUnit` for everything --which is what this did-- made the preview
    of every exercise in the library come out as a page with
    `[ missing: ... ]` on it, and it did so quietly: a reference LaTeX cannot
    resolve is a package warning, so the build still reported `ok`.
    """
    include = (r"\DidactaProblem" if area == repo_mod.PROBLEMS
               else r"\DidactaUnit")
    return "\n".join(
        [
            "%% Vista previa de una unidad. Generado por `didacta preview`;",
            "%% se reescribe en cada compilación y no se versiona.",
            "%%",
            "%% La unidad: %s/%s" % (area or repo_mod.CONTENT, reference),
            "",
            r"\input{didacta-bootstrap}",
            r"\usepackage{didacta}",
            "",
            r"\DidactaDocument{%s}" % (title or reference),
            "",
            r"\begin{document}",
            "%s{%s}" % (include, reference),
            r"\end{document}",
            "",
        ]
    )


def write_wrapper(root, build_dir, reference, title, *, area=None):
    """Writes the wrapper and returns its path.

    One directory per unit, so two previews of different units do not fight
    over the same `.aux`, and so the output of a preview sits next to the
    source that produced it when something goes wrong.
    """
    stem = slug(reference.replace("/", "-"))
    directory = os.path.join(build_dir, PREVIEW_DIR, stem)
    os.makedirs(directory, exist_ok=True)
    source = os.path.join(directory, stem + ".tex")
    with open(source, "w", encoding="utf-8") as handle:
        handle.write(wrapper_text(reference, title, area=area))
    return source


def document_id_for(reference):
    """The engine's document id for a preview of [reference].

    Kept in one place because three things have to agree on it: where the
    wrapper is written, where the output lands, and how the interface asks
    whether an output already exists.
    """
    return os.path.join(PREVIEW_DIR, slug(reference.replace("/", "-")))


def expected_pdf(engine, reference, profile, language, title):
    """Where a preview's PDF *would* be, whether or not it is there.

    The interface needs this to answer a question it asks constantly: «esta
    versión ya está compilada, ¿la abro sin volver a compilar?». It cannot
    work the path out itself -- the file name comes from the profile's own
    naming rules, accents, dropped colons and all -- so it asks here.
    """
    outdir = engine.output_dir(document_id_for(reference), profile.id, language)
    return os.path.join(outdir, profile.output_name(title, language) + ".pdf")


def newest_source(unit):
    """When the unit was last touched, and which file it was.

    Every file in the unit's directory, not just the `.tex` of the language
    being built: a preview in `en` falls back to `es.tex` when there is no
    English, `unit.yaml` changes the title that goes in the running head, and
    a figure is as much a source as the text. Anything in there being newer
    than the PDF means the PDF is out of date.
    """
    newest = 0.0
    culprit = None
    for directory, _, names in os.walk(unit.directory):
        for name in names:
            if name.startswith("."):
                continue
            path = os.path.join(directory, name)
            try:
                when = os.path.getmtime(path)
            except OSError:
                continue
            if when > newest:
                newest = when
                culprit = os.path.relpath(path, unit.directory)
    return newest, culprit


def built(engine, units, all_profiles, languages, title_of):
    """Todo lo que hay compilado, de todas las unidades, de una vez.

    Existe para una pregunta de la biblioteca: al listar dos mil unidades,
    ¿cuáles se pueden ojear ya sin compilar nada? Preguntarlo unidad por
    unidad serían dos mil procesos, así que se pregunta una vez.

    Barato porque se mira primero si la unidad tiene carpeta de salida --un
    `isdir` por unidad-- y solo para las que la tienen se hace el trabajo de
    comprobar ficheros y fechas. En un repositorio donde se han compilado
    veinte, se tocan veinte.
    """
    found = []
    for unit in units:
        # La carpeta del motor, preguntada al motor: `output_dir` cambia las
        # barras por guiones bajos, y repetir esa regla aquí sería tenerla
        # en dos sitios.
        outdir = os.path.dirname(
            engine.output_dir(document_id_for(unit.reference_path), "x", "y"))
        if not os.path.isdir(outdir):
            continue
        wanted = profiles_for(unit.kind, all_profiles)
        record = status(engine, unit, wanted, languages, title_of(unit))
        record["outputs"] = [r for r in record["outputs"] if r["exists"]]
        if record["outputs"]:
            found.append(record)
    return {"units": found}


def document_outputs(engine, course, year, documents, all_profiles,
                     languages=None):
    """Qué hay compilado de cada documento de un curso.

    El equivalente para documentos de [built], y existe por la misma razón:
    la pantalla de un curso quiere saber, de un vistazo, qué se puede abrir
    sin compilar nada. Preguntarlo documento por documento serían tantos
    procesos como documentos.

    Barato igual: un `isdir` por documento, y solo se mira dentro de los que
    tienen carpeta de salida.

    ``languages`` son los idiomas en los que buscar. Sin darlo, solo el del
    documento, que es lo que hacía esto cuando se escribió y lo que sigue
    valiendo para quien pregunte por un documento suelto. Una pantalla que
    ofrece abrir el PDF necesita los de la asignatura: si solo se mira el del
    documento, la versión en valenciano existe en el disco y no hay forma de
    llegar a ella desde la aplicación.
    """
    found = []
    for document in documents:
        wanted = document.profiles or [
            profile.id
            for profile in profiles_mod.default_profiles(
                all_profiles, document.kind
            )
        ]
        outdir = os.path.dirname(
            engine.output_dir("%s@%s/%s" % (course, year, document.id), "x", "y")
        )
        if not os.path.isdir(outdir):
            continue

        # Cuándo se tocó la composición por última vez. Un PDF anterior a su
        # `year.yaml` o a su `.tex` describe un documento que ya no es ese.
        newest = 0.0
        for path in (document.source, os.path.join(
                os.path.dirname(document.source or ""), "year.yaml")):
            if path and os.path.isfile(path):
                newest = max(newest, os.path.getmtime(path))

        records = []
        for name in wanted:
            profile = all_profiles.get(name)
            if profile is None:
                continue
            for language in (languages or [document.language]):
                title = document.title(language)
                path = os.path.join(
                    engine.output_dir(
                        "%s@%s/%s" % (course, year, document.id), name, language
                    ),
                    profile.output_name(title, language) + ".pdf",
                )
                if not os.path.isfile(path):
                    continue
                when = os.path.getmtime(path)
                records.append({
                    "profile": name,
                    "label": profile.label,
                    "family": profile.family,
                    "language": language,
                    "pdf": path,
                    "exists": True,
                    "stale": bool(newest and when < newest),
                    "mtime": when,
                })
        if records:
            found.append({
                "document": document.id,
                "title": document.title(document.language),
                "outputs": records,
            })
    return {"documents": found}


def status(engine, unit, profiles, languages, title):
    """What is already built for this unit, and whether it is still current.

    One record per profile and language, whether the PDF exists or not: an
    interface that only listed what exists could not tell «no compilado» from
    «no ofrecido».
    """
    source_when, culprit = newest_source(unit)
    reference = unit.reference_path

    records = []
    for profile in profiles:
        for language in languages:
            pdf = expected_pdf(engine, reference, profile, language, title)
            exists = os.path.isfile(pdf)
            when = os.path.getmtime(pdf) if exists else None
            records.append(
                {
                    "profile": profile.id,
                    "label": profile.label,
                    "family": profile.family,
                    "language": language,
                    "pdf": pdf,
                    "exists": exists,
                    "mtime": when,
                    # Stale means: the unit was touched after this was built.
                    # A PDF that does not exist is not stale, it is missing --
                    # two different things, and the interface says each
                    # differently.
                    "stale": bool(exists and source_when > (when or 0)),
                }
            )

    return {
        "unit": unit.relpath,
        "reference": reference,
        "sourceMtime": source_when or None,
        "sourceNewest": culprit,
        "outputs": records,
    }


def build(engine, root, reference, profile, language, *, title=None,
          area=None, settings=None):
    """Compiles one unit in one profile and one language.

    Returns the engine's own `BuildResult`, so a caller gets the same
    diagnostics, the same log parsing and the same PDF path as a document
    build. A preview that reported failures differently would be a second
    thing to learn.

    ``settings`` only to find the repository's .bib: a unit that cites has to
    look the same on its own as inside the document that includes it.
    """
    source = write_wrapper(
        root, engine.build_dir, reference, title or reference, area=area
    )
    settings = settings or repo_mod.Settings.load(root)
    return engine.build(
        source,
        profile,
        language,
        document_id=document_id_for(reference),
        document_title=title or reference,
        content_root=repo_mod.content_root_for(source, root),
        bibliography=(
            settings.bibliography if settings.bibliography_path else None
        ),
    )


#: Which profile families suit a *unit* of each kind.
#:
#: Deliberately not `profiles.FAMILY_FOR_KIND`, which is keyed by *document*
#: kind. The two vocabularies overlap but are not the same -- a unit kind is
#: `problem`, a document kind is `problems` -- and one map serving both would
#: silently fall through to the default for half the values.
#: How much of an exercise an output shows, least first. The order the menu
#: is read in: you decide *how much* to give away, not which id to pick.
REVEAL_ORDER = {"statements": 0, "answers": 1, "solutions": 2, "teacher": 3}

UNIT_FAMILIES = {
    "theory": ("slides", "notes"),
    "example": ("slides", "notes"),
    "history": ("slides", "notes"),
    "seminar": ("slides", "notes"),
    "activity": ("slides", "notes"),
    "experiment": ("slides", "notes"),
    "problem": ("problems",),
    "handout": ("handout", "notes"),
    "practical": ("handout", "notes"),
}


def profiles_for(kind, all_profiles):
    """Which profiles are worth offering for a unit of this kind.

    Every profile *works* — that is what one source and 15 outputs means — so
    this is about what to put in a menu, not about what is possible. A
    definition offered as an exam paper is a menu entry nobody reads.

    Slides first, then prose: those are the two that answer «¿cómo queda?»,
    and they are the two the requirement named.
    """
    families = UNIT_FAMILIES.get(kind, ("slides", "notes"))
    wanted = [
        profile
        for profile in all_profiles.values()
        if profile.family in families
    ]
    if not wanted:
        wanted = list(all_profiles.values())

    def rank(profile):
        # The declared family order first: a handout is offered as a handout
        # before it is offered as prose.
        family = families.index(profile.family)
        # Then the plain output of that family before its variants. `book` and
        # `notes` are both plain, and «modo de libro» is one of the two the
        # requirement named, so it is not left behind the teacher variants.
        primary = (
            0
            if profile.id in ("slides", "notes", "book", "handout", "problems")
            else 1
        )
        # Then by how much of an exercise each one shows, so the three levels
        # of a problem sheet come out in the order they are decided in:
        # statements, results, the teacher's copy. Alphabetical order gets
        # this right by luck today; saying it means it stays right.
        return (family, primary, REVEAL_ORDER.get(profile.reveals, 9),
                profile.id)

    wanted.sort(key=rank)
    return wanted
