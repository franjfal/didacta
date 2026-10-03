"""Los apuntes en HTML: una página que se lee con un lector de pantalla, se
agranda sin perder nada y se traduce con el navegador.

El PDF etiquetado (`build --accessible`) es la mitad de la accesibilidad; la
otra es un HTML, que es lo que piden los servicios de accesibilidad de las
universidades porque se adapta a quien lo lee --tamaño, contraste, voz-- y no
al revés.

**Didacta lo escribe ella misma**, sin tex4ht, pandoc ni LaTeXML: los dos
primeros no están en el ordenador de cada profesor o no aguantan el LaTeX de
Didacta, y el tercero es otra instalación. Lo que sí sabe Didacta es su propio
vocabulario --qué entornos y qué órdenes lleva una lección-- y eso es lo que
se traduce aquí:

* la **composición** del documento: sus apartados y sus lecciones, en orden;
* cada lección con sus **entornos como secciones con nombre** («Definición»,
  «Teorema», «Demostración»), sus listas, su énfasis y sus términos;
* las **fórmulas** tal cual, para MathJax, que las dibuja y las lee en voz
  alta;
* las **figuras con su texto alternativo** (`alt={…}`), y las imágenes que un
  navegador sabe enseñar, copiadas al lado.

**Con las mismas reglas que el PDF de esa versión**: lo del profesor, las
soluciones, las diapositivas y el detalle se ven o no según el perfil, igual
que en LaTeX (`latex/didacta-formats.sty`). Un HTML que enseñara lo que el
PDF esconde sería una manera de repartir soluciones sin querer.

Lo que no sabe traducir no lo inventa: una orden desconocida deja su texto, un
entorno desconocido su contenido, y un dibujo sin texto alternativo lo dice.
"""

from __future__ import annotations

import html as html_mod
import os
import re
import shutil
import unicodedata

from . import profiles as profiles_mod
from . import repo as repo_mod

#: Lo que un navegador sabe enseñar tal cual.
WEB_IMAGES = (".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp")

#: Por dónde se busca una figura sin extensión, en el orden de LaTeX.
_IMAGE_TRIES = (".pdf", ".png", ".jpg", ".jpeg", ".svg")

#: Los entornos de tipo teorema, con el nombre de su rótulo en el fichero de
#: idioma (`\didactaTheoremName`), y sus nombres de antes.
THEOREMS = {
    "theorem": "Theorem", "definition": "Definition",
    "proposition": "Proposition", "lemma": "Lemma", "corollary": "Corollary",
    "property": "Property", "example": "Example", "question": "Question",
    "remark": "Remark", "axiom": "Axiom", "algorithm": "Algorithm",
    "notation": "Notation",
}
ALIASES = {
    "ndefn": "definition", "nthrm": "theorem", "nthm": "theorem",
    "nprop": "proposition", "npro": "property", "nlem": "lemma",
    "ncor": "corollary", "nex": "example", "nques": "question",
    "nrem": "remark", "naxioma": "axiom", "recipe": "algorithm",
    "defn": "definition", "thrm": "theorem", "prop": "proposition",
    "pro": "property", "lem": "lemma", "cor": "corollary", "ex": "example",
    "ques": "question", "rem": "remark", "axioma": "axiom", "ej": "exercise",
}

#: Los entornos de fórmulas, que van enteros a MathJax.
MATH_ENVIRONMENTS = {
    "equation", "equation*", "align", "align*", "gather", "gather*",
    "multline", "multline*", "eqnarray", "eqnarray*", "flalign", "flalign*",
    "alignat", "alignat*", "displaymath", "math",
}

#: Órdenes que no dejan nada en una página: espacios, saltos, etiquetas.
_DROP = {
    "dpause", "pause", "noindent", "centering", "clearpage", "newpage",
    "medskip", "smallskip", "bigskip", "vfill", "hfill", "par", "indent",
    "raggedright", "raggedleft", "small", "footnotesize", "scriptsize",
    "tiny", "large", "Large", "LARGE", "huge", "Huge", "normalsize",
    "bfseries", "itshape", "rmfamily", "sffamily", "ttfamily", "normalfont",
    "maketitle", "tableofcontents", "DidactaContents", "DidactaTitlePage",
    "protect", "relax", "null", "displaystyle", "linebreak", "nolinebreak",
    "allowbreak", "frenchspacing", "hline", "toprule", "midrule",
    "bottomrule", "selectlanguage",
}
#: Y las que se llevan también su argumento.
_DROP_WITH_ARGUMENT = {
    "label", "index", "vspace", "vspace*", "hspace", "hspace*", "phantom",
    "hphantom", "vphantom", "setlength", "addtolength", "setcounter",
    "addtocounter", "thispagestyle", "pagestyle", "usetikzlibrary",
    "pgfplotsset", "tikzset", "addplot", "didactaresetproblems",
    "didactaprofilebanner", "selectlanguage", "rule", "cline",
}

#: Lo que se escribe con una orden y se lee como un carácter.
_SYMBOLS = {
    "ldots": "…", "dots": "…", "textellipsis": "…", "S": "§", "P": "¶",
    "LaTeX": "LaTeX", "TeX": "TeX", "textbackslash": "\\", "textbar": "|",
    "textless": "<", "textgreater": ">", "guillemotleft": "«",
    "guillemotright": "»", "og": "«", "fg": "»", "euro": "€",
    "textdegree": "°", "copyright": "©", "textregistered": "®", "&": "&",
    "%": "%", "_": "_", "#": "#", "$": "$", "{": "{", "}": "}", " ": " ",
    ",": "\u2009", ";": " ", ":": " ", "!": "", "/": "", "-": "",
    "quad": "\u2003", "qquad": "\u2003\u2003", "textendash": "–",
    "textemdash": "—", "i": "ı", "ss": "ß", "o": "ø", "O": "Ø", "aa": "å",
    "AA": "Å", "ae": "æ", "AE": "Æ", "l": "ł", "L": "Ł", "oe": "œ",
    "OE": "Œ", "textquestiondown": "¿", "textexclamdown": "¡",
}

#: Las tildes de TeX, a combinar con la letra: \'a, \`e, \"u, \~n, \^o, \c c.
_ACCENTS = {"'": "\u0301", "`": "\u0300", '"': "\u0308", "~": "\u0303",
            "^": "\u0302", "c": "\u0327", "=": "\u0304", ".": "\u0307",
            "u": "\u0306", "v": "\u030C", "H": "\u030B", "k": "\u0328"}

#: Lo que se dice en la página en su idioma, además de lo del fichero de
#: idioma de LaTeX.
WORDS = {
    "es": {"drawing": "Dibujo", "noalt": "un dibujo sin descripción; está en "
           "el PDF", "image": "Figura", "contents": "Contenidos",
           "made": "Hecho con Didacta", "missing": "Esta lección todavía no "
           "está en este idioma: va en su original.", "footnote": "Nota"},
    "va": {"drawing": "Dibuix", "noalt": "un dibuix sense descripció; és en "
           "el PDF", "image": "Figura", "contents": "Continguts",
           "made": "Fet amb Didacta", "missing": "Aquesta lliçó encara no "
           "està en aquest idioma: va en l'original.", "footnote": "Nota"},
    "ca": {"drawing": "Dibuix", "noalt": "un dibuix sense descripció; és al "
           "PDF", "image": "Figura", "contents": "Continguts",
           "made": "Fet amb Didacta", "missing": "Aquesta lliçó encara no "
           "és en aquesta llengua: va en l'original.", "footnote": "Nota"},
    "en": {"drawing": "Drawing", "noalt": "a drawing without a description; "
           "it is in the PDF", "image": "Figure", "contents": "Contents",
           "made": "Made with Didacta", "missing": "This lesson is not in "
           "this language yet: it is in its original.", "footnote": "Note"},
}

#: Los códigos de idioma para el atributo `lang`, como en el PDF.
BCP47 = {"es": "es-ES", "va": "ca-ES-valencia", "ca": "ca-ES", "gl": "gl-ES",
         "eu": "eu-ES", "en": "en", "fr": "fr-FR", "de": "de-DE",
         "it": "it-IT", "pt": "pt-PT"}

#: Las funciones que el castellano llama \sen, \tg…, para MathJax. Las de
#: cada idioma están en su fichero de LaTeX; aquí van las de siempre, que son
#: las que escribe una lección.
MATH_MACROS = {
    "sen": r"\operatorname{sen}", "tg": r"\operatorname{tg}",
    "arcsen": r"\operatorname{arcsen}", "arctg": r"\operatorname{arctg}",
    "cotg": r"\operatorname{cotg}", "cosec": r"\operatorname{cosec}",
    "senh": r"\operatorname{senh}", "tgh": r"\operatorname{tgh}",
    "R": r"\mathbb{R}", "N": r"\mathbb{N}", "Z": r"\mathbb{Z}",
    "Q": r"\mathbb{Q}", "C": r"\mathbb{C}", "K": r"\mathbb{K}",
}


class HtmlError(ValueError):
    """No se puede escribir el HTML: el documento no está, o no es de nadie."""


# --------------------------------------------------------------------------
# Lo que dice el fichero de idioma de LaTeX
# --------------------------------------------------------------------------

_DEF_NAME = re.compile(r"\\def\\didacta(\w+)Name\{((?:[^{}]|\{[^{}]*\})*)\}")


def language_names(latex_dir, language):
    """Los rótulos de [language] --«Teorema», «Demostración»--, del fichero
    de idioma de LaTeX: los mismos que dice el PDF."""
    names = {}
    for code in ("es", language):
        path = os.path.join(latex_dir, "lang", "didacta-lang-%s.def" % code)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for key, value in _DEF_NAME.findall(text):
            names[key] = plain_text(value)
    return names


def plain_text(tex):
    """Un trozo de TeX sin órdenes: para un rótulo, un título, un atributo.

    Las fórmulas, también en texto: un `aria-label` lo lee en voz alta un
    lector de pantalla, y «barra, mathbb, R» no es «ℝ»."""
    converter = _Converter(axes=dict(profiles_mod.DEFAULT_AXES), names={},
                           words=WORDS["es"], images=None)
    rendered = converter.inline(tex)
    rendered = re.sub(
        r'<span class="math">\\\((.*?)\\\)</span>',
        lambda match: math_plain(html_mod.unescape(match.group(1))),
        rendered, flags=re.S)
    return html_mod.unescape(re.sub(r"<[^>]+>", "", rendered)).strip()


#: Lo que una fórmula corta dice en texto.
_MATH_SYMBOLS = {
    "infty": "∞", "pm": "±", "mp": "∓", "Rightarrow": "⇒",
    "Longrightarrow": "⟹", "Leftarrow": "⇐", "Longleftarrow": "⟸",
    "Leftrightarrow": "⇔", "Longleftrightarrow": "⟺", "iff": "⟺",
    "to": "→", "rightarrow": "→", "mapsto": "↦", "leq": "≤", "le": "≤",
    "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "in": "∈", "notin": "∉",
    "subset": "⊂", "subseteq": "⊆", "cup": "∪", "cap": "∩", "cdot": "·",
    "times": "×", "forall": "∀", "exists": "∃", "emptyset": "∅",
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
    "varepsilon": "ε", "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ",
    "theta": "θ", "varphi": "φ", "phi": "φ", "omega": "ω", "Delta": "Δ",
    "Sigma": "Σ", "Omega": "Ω", "sum": "∑", "int": "∫", "sqrt": "√",
    "partial": "∂", "nabla": "∇", "approx": "≈", "equiv": "≡",
    "ldots": "…", "cdots": "⋯", "dots": "…",
}
_BLACKBOARD = {"R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "K": "𝕂"}


def math_plain(tex):
    """Una fórmula corta, en texto: `\\mathbb R` es «ℝ», `\\pm\\infty` «±∞»."""
    tex = re.sub(r"\\mathbb\s*\{?\s*([A-Z])\s*\}?",
                 lambda m: _BLACKBOARD.get(m.group(1), m.group(1)), tex)
    tex = re.sub(r"\\(?:text|mathrm|operatorname|mathit|mathbf)\s*\{([^{}]*)\}",
                 r"\1", tex)
    tex = re.sub(r"\\([A-Za-z]+)",
                 lambda m: _MATH_SYMBOLS.get(m.group(1), ""), tex)
    tex = tex.replace("{", "").replace("}", "").replace("\\", "")
    return re.sub(r"\s+", " ", tex).strip()


# --------------------------------------------------------------------------
# Leer TeX
# --------------------------------------------------------------------------


def strip_comments(text):
    """Sin comentarios: todo lo que va detrás de un `%` que no es `\\%`."""
    out = []
    for line in text.split("\n"):
        cut = None
        index = 0
        while index < len(line):
            char = line[index]
            if char == "\\":
                index += 2
                continue
            if char == "%":
                cut = index
                break
            index += 1
        if cut is None:
            out.append(line)
        elif cut == 0 or line[:cut].strip():
            # Un % al final de una línea con texto junta las dos líneas, como
            # en TeX; uno al principio borra la línea entera.
            out.append(line[:cut] + ("\u0000" if line[:cut].strip() else ""))
    return "\n".join(out).replace("\u0000\n", "").replace("\u0000", "")


def _group(text, start, open_="{", close="}"):
    """El contenido del grupo que abre en [start] y dónde acaba."""
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == open_:
            depth += 1
        elif char == close:
            depth -= 1
            if depth == 0:
                return text[start + 1:index], index + 1
        index += 1
    return text[start + 1:], len(text)


def _skip_spaces(text, index):
    while index < len(text) and text[index] in " \t\n":
        index += 1
    return index


def _optional(text, index):
    """Un `[…]` en [index], si lo hay: (contenido o None, dónde sigue)."""
    at = _skip_spaces(text, index)
    if at < len(text) and text[at] == "[":
        depth = 0
        braces = 0
        cursor = at
        while cursor < len(text):
            char = text[cursor]
            if char == "\\":
                cursor += 2
                continue
            if char == "{":
                braces += 1
            elif char == "}":
                braces -= 1
            elif braces == 0 and char == "[":
                depth += 1
            elif braces == 0 and char == "]":
                depth -= 1
                if depth == 0:
                    return text[at + 1:cursor], cursor + 1
            cursor += 1
    return None, index


def _mandatory(text, index):
    """Un `{…}` en [index], o el siguiente carácter: (contenido, dónde sigue)."""
    at = _skip_spaces(text, index)
    if at < len(text) and text[at] == "{":
        return _group(text, at)
    if at < len(text) and text[at] == "\\":
        match = re.match(r"\\([A-Za-z]+|[\s\S])", text[at:])
        if match is None:
            return "", at + 1
        return match.group(0), at + match.end()
    if at < len(text):
        return text[at], at + 1
    return "", at


def _environment_end(text, name, start):
    """Dónde acaba el entorno [name] cuyo cuerpo empieza en [start]:
    (cuerpo, dónde sigue), contando los que se abren dentro."""
    opener = "\\begin{%s}" % name
    closer = "\\end{%s}" % name
    depth = 1
    index = start
    while True:
        next_open = text.find(opener, index)
        next_close = text.find(closer, index)
        if next_close < 0:
            return text[start:], len(text)
        if 0 <= next_open < next_close:
            depth += 1
            index = next_open + len(opener)
            continue
        depth -= 1
        if depth == 0:
            return text[start:next_close], next_close + len(closer)
        index = next_close + len(closer)


def alt_of(options):
    """El `alt={…}` de unas opciones, o None."""
    if not options:
        return None
    match = re.search(r"(?:^|,)\s*alt\s*=\s*", options)
    if not match:
        return None
    rest = options[match.end():]
    if rest.startswith("{"):
        value, _ = _group(rest, 0)
    else:
        value = rest.split(",", 1)[0]
    return value.strip()


# --------------------------------------------------------------------------
# Convertir
# --------------------------------------------------------------------------


class _Converter:
    """TeX de una lección a HTML, con las reglas de visibilidad de un perfil."""

    def __init__(self, axes, names, words, images, unit_dir=None):
        self.axes = axes
        self.names = names
        self.words = words
        #: Dónde copiar las imágenes, o None para no copiar ninguna.
        self.images = images
        self.unit_dir = unit_dir
        self.footnotes = []

    # -- qué se ve --------------------------------------------------------

    @property
    def teacher(self):
        return self.axes.get("audience") == "teacher"

    @property
    def answers(self):
        return self.axes.get("solutions") in ("answers", "full")

    @property
    def solutions(self):
        return self.axes.get("solutions") == "full"

    @property
    def full(self):
        return self.axes.get("detail", "full") == "full"

    # -- bloques ----------------------------------------------------------

    def blocks(self, text):
        """TeX con párrafos: párrafos, apartados, listas, fórmulas…"""
        out = []
        paragraph = []

        def flush():
            body = "".join(paragraph).strip()
            paragraph.clear()
            if body:
                out.append("<p>%s</p>" % body)

        for kind, piece in self._pieces(text):
            if kind == "text":
                parts = re.split(r"\n[ \t]*\n", piece)
                for number, part in enumerate(parts):
                    if number:
                        flush()
                    paragraph.append(self.inline(part))
            elif kind == "inline":
                paragraph.append(piece)
            else:
                flush()
                out.append(piece)
        flush()
        return "\n".join(out)

    def _pieces(self, text):
        """(tipo, trozo): «text» es TeX por convertir en línea, «inline» HTML
        que va dentro de un párrafo y «block» HTML que lo corta."""
        index = 0
        buffer = []
        while index < len(text):
            char = text[index]
            if char == "\\":
                match = re.match(r"\\([A-Za-z]+\*?|[\s\S])", text[index:])
                if match is None:  # una barra al final del todo
                    index += 1
                    continue
                name = match.group(1)
                after = index + match.end()
                result = self._block_command(name, text, after)
                if result is not None:
                    kind, piece, after = result
                    if buffer:
                        yield "text", "".join(buffer)
                        buffer = []
                    yield kind, piece
                    index = after
                    continue
                buffer.append(text[index:after])
                index = after
                continue
            if text.startswith("$$", index):
                end = text.find("$$", index + 2)
                end = len(text) if end < 0 else end
                if buffer:
                    yield "text", "".join(buffer)
                    buffer = []
                yield "block", self._display(text[index + 2:end])
                index = end + 2
                continue
            buffer.append(char)
            index += 1
        if buffer:
            yield "text", "".join(buffer)

    def _block_command(self, name, text, after):
        """Lo que corta un párrafo: entornos, apartados, `\\[`. None si no."""
        if name == "[":
            end = text.find("\\]", after)
            end = len(text) if end < 0 else end
            return "block", self._display(text[after:end]), end + 2
        if name == "begin":
            env, at = _mandatory(text, after)
            env = env.strip()
            body, rest = _environment_end(text, env, at)
            return self._environment(env, body, rest)
        if name in ("section", "section*", "subsection", "subsection*",
                    "subsubsection", "subsubsection*", "paragraph",
                    "didactatitle", "chapter", "chapter*"):
            _, at = _optional(text, after)
            title, rest = _mandatory(text, at)
            level = {"chapter": 2, "section": 3, "didactatitle": 4,
                     "subsection": 4, "subsubsection": 5,
                     "paragraph": 6}[name.rstrip("*")]
            return "block", "<h%d>%s</h%d>" % (
                level, self.inline(title), level), rest
        visible = self._visibility(name)
        if visible is not None:
            body, rest = _mandatory(text, after)
            if name == "bymedium":
                # \bymedium{diapositiva}{apuntes}: en una página, lo segundo.
                second, rest = _mandatory(text, rest)
                return "inline", self.blocks(second) if "\n\n" in second \
                    else self.inline(second), rest
            if not visible:
                return "inline", "", rest
            if "\n\n" in body or "\\begin" in body:
                return "block", self.blocks(body), rest
            return "inline", self.inline(body), rest
        return None

    def _visibility(self, name):
        """Si se ve lo que envuelve \\[name]{…}: True, False o None si no es
        una orden de visibilidad."""
        table = {
            "onlynotes": True, "onlybook": True, "onlyslides": False,
            # El título de una diapositiva: en los apuntes no hay diapositiva.
            "slidetitle": False,
            "onlyteacher": self.teacher, "onlystudent": not self.teacher,
            "onlyfull": self.full, "onlybrief": not self.full,
            "slidesandteacher": self.teacher, "notesandteacher": True,
            "everywhere": True, "bymedium": True, "timing": self.teacher,
        }
        return table.get(name)

    def _environment(self, env, body, rest):
        env = ALIASES.get(env, env)
        hidden = {
            "slidesonly": False, "notesonly": True,
            "teacheronly": self.teacher, "studentonly": not self.teacher,
            "fullonly": self.full, "teaching": self.teacher,
            "commonmistake": self.teacher, "answer": self.answers,
            "solution": self.solutions,
            "marking": self.teacher and self.solutions, "hint": False,
        }
        if env in hidden and not hidden[env]:
            return "block", "", rest
        if env in ("slidesonly", "notesonly", "teacheronly", "studentonly",
                   "fullonly", "frame", "block", "columns", "column",
                   "didactaunit", "minipage", "multicols", "flushleft",
                   "flushright", "document", "otherlanguage"):
            body = self._drop_arguments(env, body)
            return "block", self.blocks(body), rest
        if env in MATH_ENVIRONMENTS or env == "keyformula":
            if env in ("math",):
                return "inline", self._inline_math(body), rest
            tex = body if env in ("equation", "equation*", "displaymath",
                                  "keyformula") else \
                "\\begin{%s}%s\\end{%s}" % (env, body, env)
            css = ' class="key"' if env == "keyformula" else ""
            return "block", self._display(tex, css), rest
        if env in ("itemize", "enumerate", "description"):
            _, body = self._leading_optional(body)
            return "block", self._list(env, body), rest
        if env in THEOREMS or env.rstrip("*") in THEOREMS:
            base = env.rstrip("*")
            title, body = self._leading_optional(body)
            label = self.names.get(THEOREMS[base], base.capitalize())
            return "block", self._titled(
                "theorem %s" % base, label, title, body), rest
        if env == "proof":
            title, body = self._leading_optional(body)
            label = self.inline(title) if title else self.names.get(
                "Proof", "Demostración")
            return "block", (
                '<section class="proof" aria-label="%s"><h5>%s</h5>%s'
                '<p class="qed" aria-hidden="true">∎</p></section>' % (
                    html_mod.escape(plain_text(label), quote=True), label,
                    self.blocks(body))), rest
        if env == "exercise":
            title, body = self._leading_optional(body)
            return "block", self._titled(
                "exercise", self.names.get("Exercise", "Ejercicio"),
                title, body), rest
        if env in ("answer", "solution", "marking", "hint"):
            label = self.names.get(env.capitalize(), env.capitalize())
            return "block", self._titled(env, label, None, body,
                                         tag="aside"), rest
        if env in ("teaching", "commonmistake"):
            title, body = self._leading_optional(body)
            label = self.names.get(
                "TeachingNote" if env == "teaching" else "CommonMistake",
                "Nota didáctica")
            return "block", self._titled(
                "teacher", label, title, body, tag="aside"), rest
        if env in ("objectives", "prerequisites", "summary"):
            label = self.names.get(env.capitalize(), env.capitalize())
            return "block", self._titled(env, label, None, body,
                                         tag="aside"), rest
        if env == "keypoint":
            title, body = self._leading_optional(body)
            return "block", self._titled("keypoint", "", title, body,
                                         tag="aside"), rest
        if env == "center":
            return "block", '<div class="center">%s</div>' % self.blocks(
                body), rest
        if env in ("quote", "quotation"):
            return "block", "<blockquote>%s</blockquote>" % self.blocks(
                body), rest
        if env in ("figure", "figure*", "wrapfigure", "table", "table*"):
            _, body = self._leading_optional(body)
            if env == "wrapfigure":
                _, body = self._leading_group(body)
            return "block", self._float(body), rest
        if env in ("tikzpicture", "pgfpicture"):
            options, _ = self._leading_optional(body)
            return "block", self._drawing(alt_of(options)), rest
        if env in ("tabular", "tabular*", "array", "tabularx"):
            if env in ("tabular*", "tabularx"):
                _, body = self._leading_group(body)
            _, body = self._leading_optional(body)
            _, body = self._leading_group(body)
            return "block", self._table(body), rest
        if env in ("verbatim", "lstlisting", "minted"):
            return "block", "<pre><code>%s</code></pre>" % html_mod.escape(
                body.strip("\n")), rest
        if env in ("thebibliography",):
            return "block", "", rest
        # Uno que no se conoce: su contenido, que es lo que hay que leer.
        _, body = self._leading_optional(body)
        return "block", '<div class="%s">%s</div>' % (
            html_mod.escape(env, quote=True), self.blocks(body)), rest

    @staticmethod
    def _leading_optional(body):
        options, after = _optional(body, 0)
        if options is None:
            return None, body
        return options, body[after:]

    @staticmethod
    def _leading_group(body):
        at = _skip_spaces(body, 0)
        if at < len(body) and body[at] == "{":
            content, after = _group(body, at)
            return content, body[after:]
        return None, body

    def _drop_arguments(self, env, body):
        """Lo que un entorno lleva de argumentos y no es contenido."""
        if env in ("minipage", "column"):
            _, body = self._leading_optional(body)
            _, body = self._leading_group(body)
        elif env in ("multicols", "otherlanguage"):
            _, body = self._leading_group(body)
        elif env in ("frame", "columns"):
            _, body = self._leading_optional(body)
            # `\begin{frame}{Título}` escribe el título de la diapositiva: en
            # la página es un encabezado, como `\didactatitle`.
            at = _skip_spaces(body, 0)
            if env == "frame" and at < len(body) and body[at] == "{":
                title, after = _group(body, at)
                body = "\\didactatitle{%s}%s" % (title, body[after:])
        return body

    def _titled(self, css, label, title, body, tag="section"):
        heading = label
        named = label
        if title:
            heading = "%s <span class=\"title\">(%s)</span>" % (
                label, self.inline(title)) if label else self.inline(title)
            named = "%s (%s)" % (label, plain_text(title)) if label \
                else plain_text(title)
        aria = ' aria-label="%s"' % html_mod.escape(named, quote=True) \
            if named else ""
        head = "<h5>%s</h5>" % heading if heading else ""
        return '<%s class="%s"%s>%s%s</%s>' % (
            tag, css, aria, head, self.blocks(body), tag)

    def _list(self, env, body):
        tag = {"itemize": "ul", "enumerate": "ol", "description": "dl"}[env]
        # Dónde empieza cada \\item de este nivel, sin contar los de las
        # listas de dentro.
        starts = []
        depth = 0
        index = 0
        while index < len(body):
            if body.startswith("\\begin{", index):
                depth += 1
            elif body.startswith("\\end{", index):
                depth -= 1
            elif depth == 0 and re.match(r"\\item(?![A-Za-z])", body[index:]):
                starts.append(index)
            index += 1
        rendered = []
        for number, start in enumerate(starts):
            end = starts[number + 1] if number + 1 < len(starts) else len(body)
            label, after = _optional(body, start + len("\\item"))
            text = self.blocks(body[after:end])
            if text.count("<p>") == 1 and text.startswith("<p>") and \
                    text.endswith("</p>"):
                text = text[3:-4]
            if tag == "dl":
                rendered.append("<dt>%s</dt><dd>%s</dd>" % (
                    self.inline(label or ""), text))
            else:
                rendered.append("<li>%s</li>" % text)
        return "<%s>%s</%s>" % (tag, "".join(rendered), tag)

    def _float(self, body):
        caption = re.search(r"\\caption\s*(?:\[[^\]]*\])?\s*\{", body)
        text = body
        caption_html = ""
        if caption:
            content, after = _group(body, caption.end() - 1)
            caption_html = "<figcaption>%s</figcaption>" % self.inline(content)
            text = body[:caption.start()] + body[after:]
        return "<figure>%s%s</figure>" % (self.blocks(text), caption_html)

    def _drawing(self, alt):
        if alt:
            return ('<figure class="drawing" role="img" aria-label="%s">'
                    '<p><span class="what">%s:</span> %s</p></figure>' % (
                        html_mod.escape(plain_text(alt), quote=True),
                        self.words["drawing"], self.inline(alt)))
        return ('<figure class="drawing missing"><p><span class="what">%s:'
                '</span> %s.</p></figure>' % (self.words["drawing"],
                                              self.words["noalt"]))

    def _table(self, body):
        rows = []
        for row in re.split(r"\\\\(?:\[[^\]]*\])?", body):
            row = re.sub(r"\\(hline|toprule|midrule|bottomrule)\b", "", row)
            row = re.sub(r"\\cline\{[^}]*\}", "", row)
            if not row.strip():
                continue
            cells = [cell for cell in re.split(r"(?<!\\)&", row)]
            rows.append("<tr>%s</tr>" % "".join(
                "<td>%s</td>" % self.inline(cell.strip()) for cell in cells))
        return "<table>%s</table>" % "".join(rows)

    # -- fórmulas ---------------------------------------------------------

    @staticmethod
    def _display(tex, css=""):
        return '<div class="math"%s>\\[%s\\]</div>' % (
            css, html_mod.escape(tex.strip(), quote=False))

    @staticmethod
    def _inline_math(tex):
        return '<span class="math">\\(%s\\)</span>' % html_mod.escape(
            tex, quote=False)

    # -- en línea ---------------------------------------------------------

    def inline(self, text):
        """TeX sin párrafos: énfasis, términos, fórmulas en línea…"""
        out = []
        index = 0
        while index < len(text):
            char = text[index]
            if char == "$":
                end = text.find("$", index + 1)
                while end > 0 and text[end - 1] == "\\":
                    end = text.find("$", end + 1)
                end = len(text) if end < 0 else end
                out.append(self._inline_math(text[index + 1:end]))
                index = end + 1
                continue
            if char == "\\":
                match = re.match(r"\\([A-Za-z]+\*?|[\s\S])", text[index:])
                if match is None:
                    index += 1
                    continue
                name = match.group(1)
                after = index + match.end()
                piece, after = self._command(name, text, after)
                out.append(piece)
                index = after
                continue
            if char in "{}":
                index += 1
                continue
            if char == "~":
                out.append("\u00a0")
                index += 1
                continue
            if text.startswith("---", index):
                out.append("—")
                index += 3
                continue
            if text.startswith("--", index):
                out.append("–")
                index += 2
                continue
            if text.startswith("``", index):
                out.append("“")
                index += 2
                continue
            if text.startswith("''", index):
                out.append("”")
                index += 2
                continue
            if text.startswith("<<", index):
                out.append("«")
                index += 2
                continue
            if text.startswith(">>", index):
                out.append("»")
                index += 2
                continue
            if char == "\n":
                out.append(" ")
                index += 1
                continue
            out.append(html_mod.escape(char, quote=False))
            index += 1
        return re.sub(r"[ \t]{2,}", " ", "".join(out))

    def _command(self, name, text, after):
        """Una orden en línea: (HTML, dónde sigue)."""
        if name == "(":
            end = text.find("\\)", after)
            end = len(text) if end < 0 else end
            return self._inline_math(text[after:end]), end + 2
        if name in _ACCENTS and (not name.isalpha() or (
                after < len(text) and text[after] in "{ ")):
            letter, rest = _mandatory(text, after)
            letter = letter.replace("\\i", "i").replace("\\j", "j")
            return unicodedata.normalize(
                "NFC", letter + _ACCENTS[name]), rest
        if name in _SYMBOLS:
            return html_mod.escape(_SYMBOLS[name], quote=False), after
        if name == "\\":
            _, rest = _optional(text, after)
            return "<br>", rest
        if name in ("newline", "linebreak"):
            return "<br>", after
        if name in _DROP:
            return "", after
        if name in _DROP_WITH_ARGUMENT:
            _, rest = _optional(text, after)
            _, rest = _mandatory(text, rest)
            if name in ("setlength", "addtolength", "setcounter",
                        "addtocounter", "rule"):
                _, rest = _mandatory(text, rest)
            return "", rest
        visible = self._visibility(name)
        if visible is not None:
            body, rest = _mandatory(text, after)
            if name == "bymedium":
                second, rest = _mandatory(text, rest)
                return self.inline(second), rest
            return (self.inline(body) if visible else ""), rest
        wrap = {
            "textbf": "strong", "emph": "em", "textit": "em", "textsl": "em",
            "keyterm": "dfn", "texttt": "code", "underline": "u",
            "hl": "mark", "textsc": "span", "textsf": "span",
            "textrm": "span", "textup": "span", "textnormal": "span",
            "mbox": "span", "text": "span", "term": "dfn",
        }
        if name in wrap:
            body, rest = _mandatory(text, after)
            tag = wrap[name]
            return "<%s>%s</%s>" % (tag, self.inline(body), tag), rest
        if name in ("url",):
            body, rest = _mandatory(text, after)
            url = html_mod.escape(body.strip(), quote=True)
            return '<a href="%s">%s</a>' % (url, url), rest
        if name == "href":
            url, rest = _mandatory(text, after)
            label, rest = _mandatory(text, rest)
            return '<a href="%s">%s</a>' % (
                html_mod.escape(url.strip(), quote=True),
                self.inline(label)), rest
        if name in ("cite", "cites", "parencite", "textcite", "autocite",
                    "footcite", "citep", "citet"):
            return self._cite(text, after)
        if name in ("ref", "eqref", "pageref", "autoref", "cref", "Cref"):
            _, rest = _mandatory(text, after)
            return "", rest
        if name == "footnote":
            _, rest = _optional(text, after)
            body, rest = _mandatory(text, rest)
            return ' <span class="footnote">(%s)</span>' % self.inline(
                body), rest
        if name == "includegraphics":
            options, rest = _optional(text, after)
            name_, rest = _mandatory(text, rest)
            return self._image(name_.strip(), alt_of(options)), rest
        if name in ("item",):
            _, rest = _optional(text, after)
            return "", rest
        if name in ("DidactaUnit", "DidactaProblem", "input", "include"):
            _, rest = _mandatory(text, after)
            return "", rest
        if name in ("frametitle", "framesubtitle", "caption"):
            _, rest = _optional(text, after)
            body, rest = _mandatory(text, rest)
            return "<strong>%s</strong>" % self.inline(body), rest
        # Una orden que no se conoce: se quita, y lo que lleve entre llaves
        # se deja, que suele ser lo que se quería leer.
        _, rest = _optional(text, after)
        at = _skip_spaces(text, rest)
        pieces = []
        while at < len(text) and text[at] == "{":
            body, rest = _group(text, at)
            pieces.append(self.inline(body))
            at = rest
            if text[at:at + 1] != "{":
                break
        if pieces:
            return " ".join(pieces), rest
        return "", after

    def _cite(self, text, after):
        parts = []
        rest = after
        while True:
            first, at = _optional(text, rest)
            second, at = _optional(text, at)
            at2 = _skip_spaces(text, at)
            if at2 < len(text) and text[at2] == "{":
                keys, rest = _group(text, at2)
                note = second if second is not None else first
                label = ", ".join(key.strip() for key in keys.split(","))
                if note:
                    label += ", " + plain_text(note)
                parts.append(label)
                if text[rest:rest + 1] not in "[{":
                    break
            else:
                break
        return '<cite>[%s]</cite>' % html_mod.escape("; ".join(parts),
                                                    quote=False), rest

    def _image(self, name, alt):
        """Una imagen: la que un navegador sabe enseñar se copia al lado; la
        que no --un PDF-- deja su descripción."""
        path = self._find_image(name)
        described = html_mod.escape(plain_text(alt), quote=True) if alt else ""
        if path and self.images is not None and \
                os.path.splitext(path)[1].lower() in WEB_IMAGES:
            os.makedirs(self.images, exist_ok=True)
            target = os.path.join(self.images, _image_name(path))
            if not os.path.exists(target):
                shutil.copyfile(path, target)
            src = "%s/%s" % (os.path.basename(self.images),
                             os.path.basename(target))
            return '<img src="%s" alt="%s">' % (
                html_mod.escape(src, quote=True), described)
        if alt:
            return '<span class="image" role="img" aria-label="%s">[%s: %s]' \
                   '</span>' % (described, self.words["image"],
                                self.inline(alt))
        return '<span class="image missing">[%s: %s]</span>' % (
            self.words["image"], self.words["noalt"])

    def _find_image(self, name):
        if not self.unit_dir or "\\" in name or "#" in name:
            return None
        base = os.path.join(self.unit_dir, name)
        if os.path.splitext(name)[1] and os.path.isfile(base):
            return base
        for ext in _IMAGE_TRIES:
            if os.path.isfile(base + ext):
                return base + ext
        return None


def _image_name(path):
    """Un nombre que no choca con el de otra lección: la ruta, aplanada."""
    parent = os.path.basename(os.path.dirname(path))
    return "%s-%s" % (parent, os.path.basename(path))


# --------------------------------------------------------------------------
# El documento
# --------------------------------------------------------------------------


def convert_unit(text, axes, names, words, images=None, unit_dir=None):
    """El HTML de una lección: su TeX, visto como lo ve [axes]."""
    converter = _Converter(axes, names, words, images, unit_dir)
    return converter.blocks(strip_comments(text))


def _unit_html(unit, language, axes, names, words, images, root):
    entry = unit.languages.get(language)
    used = language
    note = ""
    if entry is None or not entry.exists:
        used = unit.reference
        entry = unit.languages.get(used)
        note = '<p class="note">%s</p>' % words["missing"]
    if entry is None or not entry.exists:
        return ""
    with open(os.path.join(root, entry.path), encoding="utf-8") as handle:
        text = handle.read()
    body = convert_unit(text, axes, names, words, images,
                        os.path.join(root, unit.relpath))
    lang = ' lang="%s"' % BCP47.get(used, used) if used != language else ""
    return '<section class="unit" id="%s"%s>%s%s</section>' % (
        html_mod.escape(unit.relpath.replace("/", "-"), quote=True), lang,
        note, body)


def render_document(root, settings, course, year, document, profile,
                    language, latex_dir, units, images=None):
    """La página de un documento en [profile] y [language]."""
    axes = dict(profiles_mod.DEFAULT_AXES)
    axes.update(profile.axes)
    axes["medium"] = "document"
    words = WORDS.get(language, WORDS["es"])
    names = language_names(latex_dir, language)
    # Los títulos de los apartados, como el resto: con sus fórmulas para
    # MathJax.
    headings = _Converter(axes, names, words, None)
    sections = []
    contents = []
    for entry in document.structure:
        if "section" in entry or "subsection" in entry:
            kind = "section" if "section" in entry else "subsection"
            titles = entry[kind]
            title = titles.get(language) or next(
                (t for t in titles.values() if t), "") \
                if isinstance(titles, dict) else str(titles)
            anchor = "s%d" % (len(sections) + 1)
            level = 2 if kind == "section" else 3
            sections.append('<h%d id="%s">%s</h%d>' % (
                level, anchor, headings.inline(title), level))
            if kind == "section":
                contents.append('<li><a href="#%s">%s</a></li>' % (
                    anchor, html_mod.escape(plain_text(title))))
            continue
        ref = entry.get("unit") or entry.get("problem")
        if not ref:
            continue
        unit = repo_mod.resolve_unit_ref(ref, units, root)
        if unit is None:
            continue
        sections.append(_unit_html(unit, language, axes, names, words,
                                   images, root))
    title = document.title(language)
    course_title = course.title(language) if hasattr(course, "title") else ""
    index = ('<nav aria-label="%s"><h2>%s</h2><ol>%s</ol></nav>' % (
        words["contents"], words["contents"], "".join(contents))
        if len(contents) > 1 else "")
    return _PAGE.format(
        lang=BCP47.get(language, language),
        title=html_mod.escape(plain_text(title)),
        course=html_mod.escape("%s · %s" % (plain_text(course_title), year)),
        profile=html_mod.escape(profile.label_in(language)),
        index=index,
        body="\n".join(section for section in sections if section),
        made=words["made"],
        style=_STYLE,
        macros=_mathjax_macros(),
    )


def _mathjax_macros():
    return ", ".join('%s: "%s"' % (name, value.replace("\\", "\\\\"))
                     for name, value in sorted(MATH_MACROS.items()))


_STYLE = """
:root { color-scheme: light dark; --bg: #f6f6f3; --card: #ffffff;
  --ink: #1d2320; --muted: #5d665f; --rule: #dfe3dc; --accent: #2f6b3a;
  --tint: #edf3ea; --teacher: #8a4b12; --teacher-tint: #fbf1e6; }
@media (prefers-color-scheme: dark) { :root { --bg: #16191a; --card: #1e2223;
  --ink: #e6e9e5; --muted: #a2aba3; --rule: #333a36; --accent: #8fcf99;
  --tint: #1f2b22; --teacher: #f0b178; --teacher-tint: #2c2218; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink);
  font: 1.0625rem/1.65 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 46rem; margin: 0 auto; padding: 2rem 1rem 4rem; }
header p { color: var(--muted); margin: 0; }
h1 { font-size: 2rem; line-height: 1.2; margin: .2rem 0 1.5rem; }
h2 { margin-top: 2.5rem; border-bottom: 1px solid var(--rule); }
h3, h4 { margin-top: 2rem; }
section.theorem, section.exercise, aside { background: var(--card);
  border: 1px solid var(--rule); border-left: 4px solid var(--accent);
  border-radius: 8px; padding: .6rem 1rem; margin: 1.2rem 0; }
section.theorem h5, section.exercise h5, aside h5, section.proof h5 {
  margin: .2rem 0 .4rem; font-size: 1rem; }
section.proof { margin: 1rem 0; }
section.proof h5 { font-style: italic; font-weight: 600; }
.qed { text-align: right; margin: 0; }
aside.teacher, aside.marking { border-left-color: var(--teacher);
  background: var(--teacher-tint); }
.title { font-weight: normal; }
dfn { font-style: normal; font-weight: 700; }
mark { background: var(--tint); color: inherit; }
.math { overflow-x: auto; }
.math.key { background: var(--tint); border-radius: 8px; padding: .2rem 1rem; }
figure { margin: 1.2rem 0; }
figure.drawing { border: 1px dashed var(--rule); border-radius: 8px;
  padding: .4rem 1rem; }
.what, .image { color: var(--muted); }
img { max-width: 100%; height: auto; }
table { border-collapse: collapse; margin: 1rem 0; }
td { border: 1px solid var(--rule); padding: .2rem .6rem; }
.note { color: var(--muted); font-style: italic; }
nav ol { padding-left: 1.2rem; }
a { color: var(--accent); }
footer { color: var(--muted); font-size: .875rem; margin-top: 3rem; }
"""

_PAGE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{style}</style>
<script>
window.MathJax = {{
  tex: {{ macros: {{ {macros} }} }},
  options: {{ enableMenu: true }}
}};
</script>
<script defer src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
</head>
<body>
<main>
<header>
<p>{course}</p>
<h1>{title}</h1>
<p>{profile}</p>
</header>
{index}
{body}
<footer>{made}</footer>
</main>
</body>
</html>
"""


def write_document(root, settings, course, year, document, profile, language,
                   latex_dir, units, to, name=None):
    """Escribe la página en [to]/[name].html, con sus imágenes al lado en
    [to]/imagenes. Devuelve la ruta."""
    os.makedirs(to, exist_ok=True)
    images = os.path.join(to, "imagenes")
    page = render_document(root, settings, course, year, document, profile,
                           language, latex_dir, units, images=images)
    name = name or profile.output_name(document.title(language), language)
    path = os.path.join(to, name + ".html")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(page)
    return path
