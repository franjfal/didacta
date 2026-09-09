"""Reading the legacy system.

Didacta migrates material from the LaTeX system it replaces. That system has
real conventions -- measured, not guessed -- and this module knows them. It is
strictly read-only: nothing here writes to the source material.

What migration has to handle:

**A unit is a file, not a directory.** ``03VAL-espacios-normados.tex`` sits in a
directory with thirty others. Its language is a token in the name, its ordering
is a numeric prefix, and it has no metadata anywhere.

**Four language conventions, not one.** Measured over the library files::

    {ordinal}{LANG}[-_]{slug}.tex        1762 files   03VAL-espacios-normados
    {ordinal}[-_]{LANG}[-_]{slug}.tex     105 files   01-CAST-Handout-Calcular
    {LANG}[-_]{slug}.tex                   16 files   ENG-something
    (no token at all)                     606 files   22-Axiomas-cuerpo

    CAS 1346 · CAST 95  ->  es       VAL 219  ->  va       ENG 119  ->  en

The 606 untokenised files are implicitly Castilian: 324 declare
``babel[spanish]``, 251 import ``THRMS-CAST``, and none declare Catalan.

**Language lives in the file name, never the preamble.** The preambles are
frequently wrong about their own content -- ``03VAL-*.tex`` declares
``[spanish]{babel}`` over Valencian text. Harmless in the legacy system,
because ``docmute`` discards the preamble on import, but it means the preamble
cannot be trusted and the file name can: the naming rule holds for 1564 of 1565
measured groups.

**Every content file carries a full standalone preamble** that ``docmute``
throws away when the file is imported. Migration deletes it, because Didacta
supplies the preamble. This is the step that removes the most noise.

**Composition is ``\\import{dir}{file}``** -- 13176 uses against 344 ``\\input``
and 51 ``\\include`` -- with ``../../../../`` written by hand at four, five or
six levels depending on the master's depth.
"""

from __future__ import annotations

import hashlib
import os
import re
import subprocess

#: Legacy language token -> Didacta language code. `CAS` and `CAST` are the
#: same language written two ways.
TOKEN_TO_LANG = {"CAS": "es", "CAST": "es", "VAL": "va", "ENG": "en"}

LANGUAGES = ("es", "va", "en")

#: The library root in the legacy repository.
CLASSNOTES = "00classnotes"

#: Shared templates and preamble fragments. Everything here is replaced by
#: Didacta's own LaTeX tree, so nothing under it migrates.
FILES = "Files"


# --------------------------------------------------------------------------
# Language detection
# --------------------------------------------------------------------------


class LegacyName:
    """What a legacy file name tells us.

    Attributes:
        language: Didacta code (``es`` / ``va`` / ``en``).
        implicit: True when no token was present and Castilian was assumed.
        ordinal: the leading digits, kept as a string. Carries the ordering in
            the legacy system; in Didacta ordering moves to the composition.
        slug: the rest of the name, and part of the unit's logical identity.
        token: the raw token found, or None.
    """

    __slots__ = ("language", "implicit", "ordinal", "slug", "token")

    def __init__(self, language, implicit, ordinal, slug, token):
        self.language = language
        self.implicit = implicit
        self.ordinal = ordinal
        self.slug = slug
        self.token = token

    def __repr__(self):  # pragma: no cover - debugging aid
        return "LegacyName(%r, %r, ordinal=%r, slug=%r)" % (
            self.language, self.token, self.ordinal, self.slug)


# Longest token first, so CAST is not read as CAS followed by a slug that
# starts with T.
_TOKENS = "|".join(sorted(TOKEN_TO_LANG, key=len, reverse=True))

_PATTERNS = (
    re.compile(r"^(?P<ord>\d+)[-_](?P<lang>" + _TOKENS + r")[-_](?P<slug>.+)$"),
    re.compile(r"^(?P<ord>\d+)(?P<lang>" + _TOKENS + r")[-_]?(?P<slug>.*)$"),
    re.compile(r"^(?P<lang>" + _TOKENS + r")[-_](?P<slug>.+)$"),
)

# No token: still pull off a leading ordinal, so the logical key groups
# correctly with any translation added later.
_NO_TOKEN = re.compile(r"^(?P<ord>\d+)[-_]?(?P<slug>.*)$")


def read_name(path):
    """Read the language, ordinal and slug out of a legacy file name.

    Accepts a full path; only the base name is inspected.

    >>> read_name("00classnotes/x/03VAL-espacios-normados.tex").language
    'va'
    >>> read_name("22-Axiomas-cuerpo.tex").implicit
    True
    """
    name = path.replace("\\", "/").rsplit("/", 1)[-1]
    if name.lower().endswith(".tex"):
        name = name[:-4]

    for index, pattern in enumerate(_PATTERNS):
        match = pattern.match(name)
        if not match:
            continue
        token_first = index == 2
        token = match.group("lang")
        return LegacyName(
            language=TOKEN_TO_LANG[token],
            implicit=False,
            ordinal="" if token_first else (match.group("ord") or ""),
            slug=match.group("slug") or "",
            token=token,
        )

    match = _NO_TOKEN.match(name)
    if match:
        return LegacyName(
            language="es",
            implicit=True,
            ordinal=match.group("ord") or "",
            slug=match.group("slug") or name,
            token=None,
        )
    return LegacyName(language="es", implicit=True, ordinal="", slug=name, token=None)


def logical_key(directory, name):
    """The key that identifies one logical unit across its languages.

    Two files are the same content in different languages when they share
    directory, ordinal and case-folded slug. Measured to hold for 1564 of 1565
    groups; :func:`fallback_key` reconciles the one exception.
    """
    return (directory, name.ordinal, name.slug.lower())


def fallback_key(directory, name):
    """Directory and slug only, ignoring the ordinal."""
    return (directory, name.slug.lower())


# --------------------------------------------------------------------------
# LaTeX reading
# --------------------------------------------------------------------------

# A `%` starts a comment unless escaped as `\%`. An even run of backslashes
# before it means the backslashes are themselves escaped, so the `%` is live.
_COMMENT = re.compile(r"(?<!\\)(?:\\\\)*%")


def strip_comments(text):
    """Remove LaTeX comments, preserving line structure and escaped ``\\%``."""
    out = []
    for line in text.split("\n"):
        match = _COMMENT.search(line)
        out.append(line[: match.end() - 1] if match else line)
    return "\n".join(out)


def is_commented(line):
    """True when the first non-space character is ``%``."""
    return line.lstrip().startswith("%")


def read_group(text, start):
    """Read one balanced ``{...}`` group at or after ``start``.

    Returns ``(content, index_after)`` or ``(None, start)``. Handles nesting
    and ``\\{`` escapes, which matters because titles contain maths.
    """
    i, n = start, len(text)
    while i < n and text[i] in " \t\r\n":
        i += 1
    if i >= n or text[i] != "{":
        return None, start
    depth, opened = 0, i
    while i < n:
        char = text[i]
        if char == "\\" and i + 1 < n:
            i += 2
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[opened + 1 : i], i + 1
        i += 1
    return None, start


def read_optional(text, start):
    """Read one ``[...]`` optional argument, if present."""
    i, n = start, len(text)
    while i < n and text[i] in " \t":
        i += 1
    if i >= n or text[i] != "[":
        return None, start
    depth, opened = 0, i
    while i < n:
        char = text[i]
        if char == "\\" and i + 1 < n:
            i += 2
            continue
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return text[opened + 1 : i], i + 1
        i += 1
    return None, start


class Inclusion:
    """One inclusion edge in a legacy file."""

    __slots__ = ("kind", "directory", "target", "line", "enabled", "raw")

    def __init__(self, kind, directory, target, line, enabled, raw):
        self.kind = kind
        self.directory = directory
        self.target = target
        self.line = line
        self.enabled = enabled
        self.raw = raw

    def resolve(self, source_path):
        """Repository-relative path this inclusion points at.

        ``\\import`` is relative to the *importing* file's directory, which is
        why the legacy mechanism works for both standalone and composed
        compilation. The ``.tex`` suffix is optional and used inconsistently,
        so it is added when absent.
        """
        target = self.target
        if not target.lower().endswith(".tex"):
            target += ".tex"
        joined = os.path.join(os.path.dirname(source_path), self.directory, target)
        return os.path.normpath(joined)

    @property
    def is_import(self):
        return self.kind in ("import", "subimport")


_IMPORT_CMD = re.compile(r"\\(subimportlevel|subimport|import)\b")
_INPUT_CMD = re.compile(r"\\(input|include)\b")


def find_inclusions(text, include_disabled=True):
    """Every inclusion in ``text``, in source order.

    Scans line by line so line numbers and commented-out state are exact.
    Commented-out imports are deliberately disabled content in this material,
    so they are reported rather than dropped.
    """
    found = []
    for number, line in enumerate(text.split("\n"), start=1):
        enabled = not is_commented(line)
        if not enabled and not include_disabled:
            continue
        probe = line.lstrip()[1:] if not enabled else line

        for match in _IMPORT_CMD.finditer(probe):
            kind = match.group(1)
            position = match.end()
            directory, position = read_group(probe, position)
            target, position = read_group(probe, position)
            if kind == "subimportlevel":
                read_group(probe, position)
                kind = "subimport"
            if directory is None or target is None:
                continue
            found.append(Inclusion(
                kind, directory.strip(), target.strip(), number, enabled, line))

        for match in _INPUT_CMD.finditer(probe):
            target, _ = read_group(probe, match.end())
            if target is None:
                continue
            found.append(Inclusion(
                match.group(1), "", target.strip(), number, enabled, line))
    return found


# --------------------------------------------------------------------------
# Preamble and body
# --------------------------------------------------------------------------

_BEGIN_DOC = re.compile(r"\\begin\s*\{document\}")
_END_DOC = re.compile(r"\\end\s*\{document\}")


class Split:
    """A legacy file cut into preamble, body and epilogue.

    Migration keeps only the body: Didacta supplies the preamble, and the
    ``\\documentclass`` / ``\\usepackage`` / ``\\import{Files/}`` block that every
    content file carries is exactly what ``docmute`` was there to discard.
    """

    __slots__ = ("preamble", "body", "has_document_environment")

    def __init__(self, preamble, body, has_document_environment):
        self.preamble = preamble
        self.body = body
        self.has_document_environment = has_document_environment


def split_document(text):
    """Cut a legacy file at ``\\begin{document}`` and ``\\end{document}``.

    A file with no document environment is already a fragment -- some legacy
    files are included with ``\\input`` rather than imported -- so it is
    returned as body with an empty preamble.
    """
    begin = _uncommented(text, _BEGIN_DOC)
    if begin is None:
        return Split("", text, False)

    # Cut at the character, not at the line. Three measured files close a brace
    # or a display-maths block on the same line as \end{document}, and dropping
    # that line leaves the body unbalanced -- a migration that compiles nowhere.
    end = _uncommented(text, _END_DOC, start=begin.end())
    body_end = end.start() if end is not None else len(text)

    return Split(
        preamble=text[: begin.start()],
        body=text[begin.end() : body_end],
        has_document_environment=True,
    )


def _uncommented(text, pattern, start=0):
    """First match of ``pattern`` that is not inside a comment."""
    for match in pattern.finditer(text, start):
        line_start = text.rfind("\n", 0, match.start()) + 1
        before = text[line_start : match.start()]
        if "%" in _without_escaped_percent(before):
            continue
        return match
    return None


def _without_escaped_percent(text):
    return text.replace("\\%", "")


# --------------------------------------------------------------------------
# Titles
# --------------------------------------------------------------------------

#: Boxed-theorem environments carry their title in an optional argument.
_TITLED_ENVS = (
    "ndefn", "nthrm", "nthm", "nprop", "npro", "nlem", "ncor",
    "nex", "nques", "nrem", "recipe",
)

_TITLE_NOISE = re.compile(
    r"\\(?:vspace|hspace|newline|medskip|smallskip|bigskip|par|noindent"
    r"|,|;|!|quad|qquad)(?:\s*\{[^{}]*\})?"
    # Font switches, which take no argument and only affect how the title was
    # set in the old document: `{\small \chapterTitle}` and `{\sc Tema 1}`
    # appear in 58 masters each.
    r"|\\(?:small|footnotesize|scriptsize|tiny|large|Large|LARGE|huge|Huge"
    r"|normalsize|sc|scshape|bf|bfseries|it|itshape|sf|sffamily|rm|rmfamily"
    r"|tt|ttfamily|em|upshape|mdseries|centering|raggedright|raggedleft)"
    r"(?![a-zA-Z])"
)
_TITLE_MACRO = re.compile(r"\\(?:text(?:bf|it|sf|rm|tt)|emph|mathrm|mbox)\s*\{")

#: The `\'o` style accents that pervade the older files. A library listing
#: showing "Definici\'on" would be a bug, so they are decoded.
_ACCENTS = {
    r"\'a": "á", r"\'e": "é", r"\'i": "í", r"\'o": "ó", r"\'u": "ú",
    r"\'A": "Á", r"\'E": "É", r"\'I": "Í", r"\'O": "Ó", r"\'U": "Ú",
    r"\`a": "à", r"\`e": "è", r"\`i": "ì", r"\`o": "ò", r"\`u": "ù",
    r"\`A": "À", r"\`E": "È", r"\`O": "Ò",
    r'\"u': "ü", r'\"i': "ï", r'\"o': "ö", r'\"a': "ä",
    r"\~n": "ñ", r"\~N": "Ñ", r"\c c": "ç", r"\cc": "ç",
    r"\c{c}": "ç", r"\textperiodcentered ": "·",
}


def clean_text(raw):
    """Reduce a LaTeX fragment to readable text.

    Maths is left intact: ``$\\mathbb R$`` is meaningful and a title is
    displayed as-is.
    """
    # Comments first, and before the newlines are collapsed: a `%` in the
    # middle of a multi-line title comments out the rest of *its* line, and
    # flattening first would let it eat the whole title. Measured: one master
    # writes `\classlong\newline%\medskip\newline{\small Órbitas
    # planetarias.}`, whose title came out as a bare `%`.
    text = strip_comments(raw).replace("\n", " ")
    for pattern, char in _ACCENTS.items():
        text = text.replace("{" + pattern + "}", char).replace(pattern, char)
    text = re.sub(r"\\(?:newline|\\)", " ", text)
    text = _TITLE_NOISE.sub(" ", text)
    for _ in range(4):
        match = _TITLE_MACRO.search(text)
        if not match:
            break
        content, after = read_group(text, match.end() - 1)
        if content is None:
            break
        text = text[: match.start()] + content + text[after:]
    text = _unwrap_plain_groups(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text.strip(" .,:;-")


#: A brace group holding nothing but text: no maths, no macro, no nesting.
#: Removing a font switch leaves its group behind -- ``{\small \chapterTitle}``
#: becomes ``{ \chapterTitle}`` -- and a title displayed with stray braces
#: looks like a bug in the library listing.
_PLAIN_GROUP = re.compile(r"\{([^{}$\\]*)\}")


def _unwrap_plain_groups(text):
    """Unwrap leftover grouping braces, outside maths only.

    Inside maths the braces carry meaning: ``$L^{pq}$`` unwrapped becomes
    ``$L^pq$``, which renders as a different formula.
    """
    out = []
    for span, is_maths in split_maths(text):
        if is_maths:
            out.append(span)
            continue
        for _ in range(4):
            span, count = _PLAIN_GROUP.subn(lambda match: match.group(1), span)
            if not count:
                break
        out.append(span)
    text = "".join(out)

    # A group that wrapped the whole title and still holds a macro: the braces
    # were the font switch's, so they go and the macro stays to be reported.
    stripped = text.strip()
    if (stripped.startswith("{") and stripped.endswith("}")
            and stripped.count("{") == 1 and stripped.count("}") == 1):
        text = stripped[1:-1]
    return text


def split_maths(text):
    """``(span, is_maths)`` pieces, splitting on ``$...$`` and ``\(...\)``.

    An unclosed delimiter makes the rest of the text maths, which is the safe
    way round: it leaves the fragment alone rather than editing formulae.
    """
    spans = []
    i, n = 0, len(text)
    start = 0
    while i < n:
        char = text[i]
        if char == "\\" and i + 1 < n:
            if text[i + 1] in "()[]":
                closing = {"(": "\\)", "[": "\\]"}.get(text[i + 1])
                if closing:
                    end = text.find(closing, i + 2)
                    end = n if end < 0 else end + 2
                    if start < i:
                        spans.append((text[start:i], False))
                    spans.append((text[i:end], True))
                    i = start = end
                    continue
            i += 2
            continue
        if char == "$":
            delimiter = "$$" if text.startswith("$$", i) else "$"
            end = text.find(delimiter, i + len(delimiter))
            end = n if end < 0 else end + len(delimiter)
            if start < i:
                spans.append((text[start:i], False))
            spans.append((text[i:end], True))
            i = start = end
            continue
        i += 1
    if start < n:
        spans.append((text[start:], False))
    return spans


def extract_title(text):
    """Best-effort title for a legacy content file.

    Preference order matches how the material is actually written:
    ``\\frametitle``, then the optional argument of the first boxed theorem,
    then ``\\section``. Returns None when there is nothing, and the caller
    falls back to a humanised slug.
    """
    body = strip_comments(text)

    match = re.search(r"\\frametitle\s*(?:<[^>]*>)?\s*\{", body)
    if match:
        title, _ = read_group(body, match.end() - 1)
        if title and title.strip():
            return clean_text(title)

    for env in _TITLED_ENVS:
        match = re.search(r"\\begin\s*\{" + env + r"\}\s*\[", body)
        if match:
            title, _ = read_optional(body, match.end() - 1)
            if title and title.strip():
                return clean_text(title)

    match = re.search(r"\\(?:sub)*section\*?\s*\{", body)
    if match:
        title, _ = read_group(body, match.end() - 1)
        if title and title.strip():
            return clean_text(title)
    return None


def humanize(slug):
    """A readable fallback title from a file slug."""
    text = re.sub(r"[-_]+", " ", slug).strip()
    text = re.sub(r"\s+", " ", text)
    return (text[0].upper() + text[1:]) if text else ""


# --------------------------------------------------------------------------
# Content signals
# --------------------------------------------------------------------------

_BABEL = re.compile(r"\\usepackage\s*\[([^\]]*)\]\s*\{babel\}")
_AUDIENCE = re.compile(r"\\begin\s*\{shownto\}\s*\{([^}]*)\}")
_GRAPHIC = re.compile(r"\\includegraphics\s*(?:\[[^\]]*\])?\s*\{([^}]*)\}")
_LABEL = re.compile(r"\\label\s*\{([^}]*)\}")

#: Legacy environment names, and what they become in Didacta. Both the boxed
#: (`n`-prefixed) and plain sets map onto the same target, because Didacta
#: chooses the look from the medium rather than the name.
ENVIRONMENT_MAP = {
    "ndefn": "definition", "defn": "definition",
    "nthrm": "theorem", "nthm": "theorem", "thrm": "theorem",
    "nprop": "proposition", "prop": "proposition",
    "npro": "property", "pro": "property",
    "nlem": "lemma", "lem": "lemma",
    "ncor": "corollary", "cor": "corollary",
    "nex": "example", "ex": "example",
    "nques": "question", "ques": "question",
    "nrem": "remark", "rem": "remark",
    "naxioma": "axiom", "axioma": "axiom",
    "recipe": "algorithm",
    "ej": "exercise",
    "nformula": "keyformula",
}


class ContentFacts:
    """What one legacy content file contains."""

    __slots__ = (
        "path", "babel", "title", "frames", "pauses", "has_onlyslides",
        "has_onlybook", "has_onlyteacher", "audiences", "exercises",
        "graphics", "labels", "environments", "body_lines", "hash",
    )

    def __init__(self, **kwargs):
        for slot in self.__slots__:
            setattr(self, slot, kwargs.get(slot))


def read_content(path, text):
    """Parse one legacy content file. Never raises on malformed input."""
    body = strip_comments(text)
    split = split_document(text)

    babel = None
    match = _BABEL.search(body)
    if match:
        babel = [part.strip() for part in match.group(1).split(",") if part.strip()]

    environments = sorted({
        name for name in re.findall(r"\\begin\s*\{([a-zA-Z*]+)\}", body)
        if name in ENVIRONMENT_MAP
    })

    return ContentFacts(
        path=path,
        babel=babel,
        title=extract_title(text),
        frames=len(re.findall(r"\\begin\s*\{frame\}", body)),
        pauses=len(re.findall(r"\\pause\b", body)),
        has_onlyslides=bool(re.search(r"\\onlyslides\b", body)),
        has_onlybook=bool(re.search(r"\\onlybook\b", body)),
        has_onlyteacher=bool(re.search(r"\\onlyteacher\b", body)),
        audiences=sorted({
            audience.strip()
            for group in _AUDIENCE.findall(body)
            for audience in group.split(",")
            if audience.strip()
        }),
        exercises=len(re.findall(r"\\begin\s*\{ej\}", body)),
        graphics=sorted(set(_GRAPHIC.findall(body))),
        labels=sorted(set(_LABEL.findall(body))),
        environments=environments,
        body_lines=len([line for line in split.body.split("\n") if line.strip()]),
        hash=content_hash(text),
    )


def content_hash(text):
    """Stable hash of file content.

    Newlines are normalised because ``.gitattributes`` sets ``* text=auto`` in
    the legacy repository, so git itself normalises on commit.
    """
    if isinstance(text, str):
        data = text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    else:
        data = text
    return "sha256:" + hashlib.sha256(data).hexdigest()


# --------------------------------------------------------------------------
# Course metadata
# --------------------------------------------------------------------------

_CLASSINFO_FIELDS = (
    "profesor", "class", "classlong", "classextralong", "sec",
    "dateshort", "code", "institute", "department",
    "exerciseName", "solutionName",
)

#: The exercise and solution wording in a classinfo file is the strongest
#: language signal a legacy course carries: the author writes it per course.
CLASSINFO_LANGUAGE = {
    "exercici": "va", "solucio": "va", "solució": "va", "resposta": "va",
    "ejercicio": "es", "solucion": "es", "solución": "es", "respuesta": "es",
    "exercise": "en", "solution": "en", "answer": "en",
}


def parse_classinfo(text):
    """Extract course metadata from a legacy ``classinfo*.tex``.

    The file is LaTeX ``\\def`` declarations, not data. In Didacta this becomes
    ``course.yaml``.
    """
    body = strip_comments(text)
    out = {}
    for field in _CLASSINFO_FIELDS:
        pattern = re.compile(
            r"\\(?:def\s*\\%s\b|(?:new|renew|provide)command\s*\*?\s*\{\s*\\%s\s*\})"
            % (field, field)
        )
        match = pattern.search(body)
        if not match:
            continue
        value, _ = read_group(body, match.end())
        if value is not None:
            out[field] = clean_text(value)

    match = re.search(r"\\author\s*\{", body)
    if match:
        value, _ = read_group(body, match.end() - 1)
        if value:
            out.setdefault("profesor", clean_text(value))
    return out


def language_from_classinfo(info):
    """Guess a course's language from its classinfo wording."""
    for field in ("exerciseName", "solutionName"):
        value = (info.get(field) or "").strip().lower()
        if value in CLASSINFO_LANGUAGE:
            return CLASSINFO_LANGUAGE[value]
    return None


# --------------------------------------------------------------------------
# Repository layout
# --------------------------------------------------------------------------

#: Academic-year directories in the legacy repository begin with a space
#: (`" 2025-2026"`). It is deliberate -- it sorts the courses to the top in
#: Finder -- so paths are handled literally and only identifiers normalised.
_YEAR = re.compile(r"^\s*(?P<year>\d{4}-\d{4})\s*$")


def is_year_dir(name):
    return bool(_YEAR.match(name))


def normalise_year(name):
    match = _YEAR.match(name)
    return match.group("year") if match else name.strip()


def year_dirs(root):
    """Academic-year directories, as ``(literal_name, normalised_year)``."""
    out = []
    for name in sorted(os.listdir(root)):
        if os.path.isdir(os.path.join(root, name)) and is_year_dir(name):
            out.append((name, normalise_year(name)))
    return out


def slugify(text):
    """A stable, URL-safe identifier fragment.

    Accents are folded and the numeric ordering prefixes that pervade the
    legacy layout are dropped: ``"00 AM III A"`` -> ``"am-iii-a"``.
    """
    table = {
        "á": "a", "à": "a", "ä": "a", "â": "a", "ã": "a",
        "é": "e", "è": "e", "ë": "e", "ê": "e",
        "í": "i", "ì": "i", "ï": "i", "î": "i",
        "ó": "o", "ò": "o", "ö": "o", "ô": "o", "õ": "o",
        "ú": "u", "ù": "u", "ü": "u", "û": "u",
        "ñ": "n", "ç": "c", "·": "", "'": "", "’": "",
    }
    value = re.sub(r"^\d+\s*", "", str(text).strip()).lower()
    value = "".join(table.get(char, char) for char in value)
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value or "untitled"


def category_of(path):
    """First-level folder under ``00classnotes`` -- the content area."""
    parts = path.replace("\\", "/").split("/")
    return parts[1] if len(parts) >= 2 and parts[0] == CLASSNOTES else None


#: Second-level folders under a category, and what kind of content they hold.
KIND_BY_FOLDER = {
    "00Presentaciones": "theory", "00Presentacion": "theory",
    "01Handouts": "handout", "handouts": "handout",
    "02Class-Activity": "activity", "02Activity": "activity",
    "05Activity": "activity", "05ClassActivity": "activity",
    "03Problems": "problem", "10Problemas": "problem",
    "04Ejemplos-complementarios": "example",
    "04Experiments": "experiment",
    "20Seminarios": "seminar", "20Seminars": "seminar",
    "30History": "history",
    "00Prácticas": "practical",
    "99Material-complementario": "theory",
}


def kind_of(path):
    """The Didacta unit kind for a legacy path."""
    parts = path.replace("\\", "/").split("/")
    for part in parts:
        if part in KIND_BY_FOLDER:
            return KIND_BY_FOLDER[part]
    lowered = path.lower()
    if any(word in lowered for word in ("problem", "problema", "ejercicio")):
        return "problem"
    # `Handoout` with a doubled o appears in several real folder names.
    if "handout" in lowered or "handoout" in lowered:
        return "handout"
    return "theory"


def path_tags(path):
    """The folders between the kind folder and the file.

    The only tag source the legacy layout offers, and a good one: a problem at
    ``EDOs/03Problems/practice/11-orde-2-Wronskian/`` yields ``practice`` and
    ``orde-2-wronskian``, both of which are worth keeping.
    """
    parts = path.replace("\\", "/").split("/")
    if not parts or parts[0] != CLASSNOTES:
        return []
    tags = []
    seen_kind = False
    for part in parts[2:-1]:
        if part in KIND_BY_FOLDER:
            seen_kind = True
            continue
        if not seen_kind:
            continue
        if part in ("img", "images", "animations", "99Notes", "assets", "videos"):
            continue
        tags.append(slugify(part))
    return tags


def topic_of(path):
    """The innermost folder a unit sits in: its topic.

    The innermost rather than the first, because the first is often a grouping
    level (``practice``) and the last is the actual subject.
    """
    tags = path_tags(path)
    return tags[-1] if tags else ""


#: Files that are not content: TikZ fragments under `img/`, template stubs.
def is_asset(path):
    parts = path.replace("\\", "/").split("/")
    if any(part in ("img", "images", "animations", "assets", "videos") for part in parts):
        return True
    return parts[-1] in ("template.tex", "TODO.tex")


def git_files(root, *patterns):
    """Tracked files, so untracked build artefacts never enter a migration.

    The legacy repository has 5428 committed PDFs and 1600-plus ``.aux`` and
    ``.log`` files; walking the tree instead of asking git would sweep them in.
    """
    command = ["git", "-C", root, "ls-files", "-z"]
    command.extend(patterns)
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError("git ls-files failed: %s" % result.stderr.strip())
    return [path for path in result.stdout.split("\0") if path]


def read_file(root, path):
    """Read a legacy file tolerantly.

    44 of the 5529 tracked ``.tex`` files are not valid UTF-8 -- latin-1
    leftovers from closed courses -- so decoding must not be strict. Being
    strict here is how a migration run dies two thousand files in.
    """
    with open(os.path.join(root, path), encoding="utf-8", errors="replace") as handle:
        return handle.read()
