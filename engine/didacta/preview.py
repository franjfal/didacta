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

from . import repo as repo_mod


#: Where the generated wrappers go, under the build directory. Not tracked,
#: and safe to delete: every one of them is regenerated on demand.
PREVIEW_DIR = "preview"


def slug(text):
    """A filesystem-safe stem for a preview file."""
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", text).strip("-")
    return cleaned or "unit"


def wrapper_text(reference, title, *, kind=None):
    r"""The smallest document that compiles one unit.

    No title page and no table of contents: this is one unit, and a title page
    in front of a single definition is a page nobody wants to look at. The
    unit's own `\didactatitle` gives it a heading in every profile.

    `\DidactaDocument` is still set, because the profile uses it for the PDF
    metadata and the running head, and a preview whose header says
    `preview-1a2b` would be worse than one that says what it is.
    """
    return "\n".join(
        [
            "%% Vista previa de una unidad. Generado por `didacta preview`;",
            "%% se reescribe en cada compilación y no se versiona.",
            "%%",
            "%% La unidad: %s" % reference,
            "",
            r"\input{didacta-bootstrap}",
            r"\usepackage{didacta}",
            "",
            r"\DidactaDocument{%s}" % (title or reference),
            "",
            r"\begin{document}",
            r"\DidactaUnit{%s}" % reference,
            r"\end{document}",
            "",
        ]
    )


def write_wrapper(root, build_dir, reference, title, *, kind=None):
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
        handle.write(wrapper_text(reference, title, kind=kind))
    return source


def build(engine, root, reference, profile, language, *, title=None,
          kind=None):
    """Compiles one unit in one profile and one language.

    Returns the engine's own `BuildResult`, so a caller gets the same
    diagnostics, the same log parsing and the same PDF path as a document
    build. A preview that reported failures differently would be a second
    thing to learn.
    """
    source = write_wrapper(
        root, engine.build_dir, reference, title or reference, kind=kind
    )
    return engine.build(
        source,
        profile,
        language,
        document_id=os.path.join(PREVIEW_DIR, slug(reference.replace("/", "-"))),
        document_title=title or reference,
        content_root=repo_mod.content_root_for(source, root),
    )


#: Which profile families suit a *unit* of each kind.
#:
#: Deliberately not `profiles.FAMILY_FOR_KIND`, which is keyed by *document*
#: kind. The two vocabularies overlap but are not the same -- a unit kind is
#: `problem`, a document kind is `problems` -- and one map serving both would
#: silently fall through to the default for half the values.
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

    Every profile *works* — that is what one source and 14 outputs means — so
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
        return (family, primary, profile.id)

    wanted.sort(key=rank)
    return wanted
