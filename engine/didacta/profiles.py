"""Output profiles.

Parsed from ``latex/didacta-profiles.tex``, which stays the single source of
truth. The alternative -- declaring profiles in YAML and generating the LaTeX --
was rejected because it would make the LaTeX layer unusable without the engine,
and compiling a document by hand with a plain ``pdflatex`` call has to keep
working. That is what gives the author a working editor with SyncTeX and no
tooling in the way.

The file's format is deliberately regular so this parser can stay small, and
``tests/test_profiles.py`` asserts the parse against the expected set so a
format change cannot pass unnoticed.
"""

from __future__ import annotations

import os
import re

#: Languages Didacta ships. Adding one means adding a language definition file.
LANGUAGES = ("es", "va", "en")

LANGUAGE_NAMES = {"es": "Castellano", "va": "Valencià", "en": "English"}

#: babel option per language. Valencian uses `catalan`, which is what gives
#: correct hyphenation; the visible strings are Valencian.
BABEL = {"es": "spanish", "va": "catalan", "en": "english"}

_DECLARE = re.compile(
    r"\\DidactaDeclareProfile\s*"
    r"\{(?P<id>[^}]*)\}\s*"
    r"\{(?P<cls>[^}]*)\}\s*"
    r"\{(?P<opts>[^}]*)\}\s*"
    r"\{(?P<axes>(?:[^{}]|\{[^{}]*\})*)\}",
    re.S,
)

#: Default axis values, matching the defaults didacta.sty applies.
DEFAULT_AXES = {
    "medium": "document",
    "detail": "full",
    "audience": "student",
    "solutions": "hidden",
    "pauses": "off",
    "layout": "normal",
}

VALID_AXES = {
    "medium": {"slides", "document"},
    "detail": {"brief", "full"},
    "audience": {"student", "teacher"},
    "solutions": {"hidden", "answers", "full"},
    "pauses": {"on", "off"},
    "layout": {"normal", "compact", "exam"},
    "notes": {"show", "hide"},
}


class ProfileError(ValueError):
    """The profile registry is malformed."""


class Profile:
    """One named output.

    Attributes mirror the axes in ``didacta-profiles.tex``; see that file for
    what each one means.
    """

    __slots__ = ("id", "document_class", "class_options", "axes")

    def __init__(self, id, document_class, class_options, axes):
        self.id = id
        self.document_class = document_class
        self.class_options = class_options
        self.axes = axes

    # -- axes ------------------------------------------------------------

    @property
    def medium(self):
        return self.axes["medium"]

    @property
    def detail(self):
        return self.axes["detail"]

    @property
    def audience(self):
        return self.axes["audience"]

    @property
    def solutions(self):
        return self.axes["solutions"]

    @property
    def is_slides(self):
        return self.medium == "slides"

    @property
    def is_teacher(self):
        return self.audience == "teacher"

    @property
    def shows_answers(self):
        return self.solutions in ("answers", "full")

    @property
    def shows_solutions(self):
        return self.solutions == "full"

    @property
    def pauses(self):
        return self.axes["pauses"] == "on"

    @property
    def reveals(self):
        """How much of an exercise this output shows.

        ``statements`` | ``answers`` | ``solutions`` | ``teacher``, which are
        the three fields of a problem --statement, result, worked solution--
        read as levels: level *n* shows fields 1 to *n*, and the teacher's
        copy adds the marking notes on top.

        Derived rather than declared because it is not a new axis: it is the
        one question a teacher asks of the menu --«does this one have the
        solutions in it?»-- answered from the axes that already decide it.
        """
        if self.is_teacher:
            return "teacher"
        if self.solutions == "full":
            return "solutions"
        if self.solutions == "answers":
            return "answers"
        return "statements"

    @property
    def layout(self):
        return self.axes.get("layout", "normal")

    # -- classification --------------------------------------------------

    @property
    def family(self):
        """Which kind of document this profile is meant for.

        Used to decide which profiles a document offers, so a problem sheet
        does not advertise a slide build.
        """
        if self.is_slides:
            return "slides"
        if self.layout == "exam":
            return "exam"
        if self.id.startswith("problems"):
            return "problems"
        if self.layout == "compact":
            return "handout"
        return "notes"

    @property
    def label(self):
        """A human name, built from the axes rather than stored.

        Deriving it means a new profile gets a sensible label for free, and the
        label can never contradict what the profile actually does.
        """
        if self.is_slides:
            base = "Diapositivas"
            if not self.pauses and not self.is_teacher:
                base += " (sin pausas)"
        elif self.layout == "exam":
            base = "Examen"
        elif self.id.startswith("problems"):
            base = "Hoja de problemas"
        elif self.id == "book":
            base = "Libro"
        elif self.layout == "compact":
            base = "Handout"
        else:
            base = "Apuntes"

        extra = []
        if self.is_teacher:
            extra.append("profesor")
        elif self.solutions == "full":
            extra.append("con soluciones")
        elif self.solutions == "answers":
            # «Resultado» and not «respuesta»: it is the word the editor puts
            # on the field the author fills in, and the two have to be the
            # same word or nobody can tell whether they are the same thing.
            extra.append("con resultados")
        return "%s (%s)" % (base, ", ".join(extra)) if extra else base

    def __repr__(self):  # pragma: no cover - debugging aid
        return "Profile(%r, %s)" % (self.id, self.axes)

    def as_dict(self):
        return {
            "id": self.id,
            "label": self.label,
            "family": self.family,
            "reveals": self.reveals,
            "documentClass": self.document_class,
            "classOptions": self.class_options,
            "axes": dict(self.axes),
        }

    # -- driving LaTeX ---------------------------------------------------

    def pretex(self, language, content_root=None):
        r"""The ``\def`` prologue that selects this profile.

        Injected before ``\input`` so the source file carries no profile of its
        own. This is the whole interface between the engine and LaTeX: two
        definitions and, optionally, where the content lives.
        """
        parts = [
            r"\def\DidactaProfile{%s}" % self.id,
            r"\def\DidactaLanguage{%s}" % language,
        ]
        if content_root:
            parts.append(r"\def\DidactaContentRoot{%s}" % content_root)
        return "".join(parts)

    def output_name(self, document_title, language, include_language=True):
        """The PDF file name for this profile.

        Readable, sortable and unambiguous when a directory holds every output
        of one document: the title first so outputs of the same document group
        together, then the profile, then the language.
        """
        pieces = [document_title.strip(), self.id]
        if include_language:
            pieces.append(language)
        name = " - ".join(p for p in pieces if p)
        # Keep the name filesystem-safe. Accents stay -- they are meaningful in
        # these titles and every filesystem in use handles them. A colon is
        # dropped rather than substituted: "Preliminars: espais normats"
        # becoming "Preliminars- espais normats" reads like a typo.
        #
        # `%` goes for a different reason: latexmk reads it in -jobname as a
        # placeholder and refuses the job, with an error that says nothing
        # about the title it came from.
        name = name.replace(":", "").replace("%", "")
        name = re.sub(r'[/\\*?"<>|]+', "-", name)
        name = re.sub(r"\s{2,}", " ", name).strip(" -")
        # Everything can be stripped away -- a title of "%" leaves nothing --
        # and an empty jobname is a worse failure than a dull one.
        return name or "documento"


def _strip_comments(text):
    r"""Drop LaTeX comments.

    Necessary before matching declarations: the registry documents its own
    syntax in a comment (``%% \DidactaDeclareProfile{id}{class}...``), and
    without this the parser reads that line as a profile called ``id``.
    """
    out = []
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("%"):
            continue
        # An unescaped % starts a comment; \% is a literal percent sign.
        cut = re.search(r"(?<!\\)%", line)
        out.append(line[: cut.start()] if cut else line)
    return "\n".join(out)


def parse(text, path="didacta-profiles.tex"):
    """Parse a profile registry."""
    profiles = {}
    for match in _DECLARE.finditer(_strip_comments(text)):
        identifier = match.group("id").strip()
        axes = dict(DEFAULT_AXES)
        raw = match.group("axes")
        # Strip LaTeX line continuations before splitting on commas.
        raw = re.sub(r"%.*", "", raw)
        for item in raw.split(","):
            item = item.strip()
            if not item:
                continue
            if "=" not in item:
                raise ProfileError("%s: profile %r has axis %r without a value"
                                   % (path, identifier, item))
            key, value = (part.strip() for part in item.split("=", 1))
            if key not in VALID_AXES:
                raise ProfileError(
                    "%s: profile %r sets unknown axis %r (known: %s)"
                    % (path, identifier, key, ", ".join(sorted(VALID_AXES)))
                )
            if value not in VALID_AXES[key]:
                raise ProfileError(
                    "%s: profile %r sets %s=%r (allowed: %s)"
                    % (path, identifier, key, value, ", ".join(sorted(VALID_AXES[key])))
                )
            axes[key] = value

        profiles[identifier] = Profile(
            id=identifier,
            document_class=match.group("cls").strip(),
            class_options=match.group("opts").strip(),
            axes=axes,
        )

    if not profiles:
        raise ProfileError("%s: no profiles found" % path)
    return profiles


def load(latex_dir):
    """Load the registry from a Didacta LaTeX directory."""
    path = os.path.join(latex_dir, "didacta-profiles.tex")
    if not os.path.isfile(path):
        raise ProfileError("no profile registry at %s" % path)
    with open(path, encoding="utf-8") as handle:
        return parse(handle.read(), path=path)


def for_family(profiles, family):
    """Profiles applicable to a document family, in registry order."""
    return [p for p in profiles.values() if p.family == family]


#: Which profile families suit which document kind. A document declares its
#: kind; this decides what the UI offers and what `didacta build` defaults to.
FAMILY_FOR_KIND = {
    "theory": ("slides", "notes"),
    "problems": ("problems",),
    "handout": ("handout",),
    "exam": ("exam",),
    "seminar": ("slides", "notes"),
    "practical": ("handout",),
}


def default_profiles(profiles, kind):
    """Every profile a document of this kind should build by default."""
    families = FAMILY_FOR_KIND.get(kind, ("notes",))
    return [p for p in profiles.values() if p.family in families]
