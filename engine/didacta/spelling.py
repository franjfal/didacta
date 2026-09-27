"""La ortografía de lo que se escribe, con hunspell si está.

Una comprobación que se pide (`didacta check --with spelling`) y no de las de
siempre, por dos razones. La primera, que necesita algo que el motor no trae:
un corrector y un diccionario por idioma. Didacta no los lleva dentro --un
diccionario son megas, y el que ya tiene cada uno en su sistema es el que
conoce sus palabras-- así que usa `hunspell`, que es el de LibreOffice y
Firefox, si está instalado. Si no está, lo dice y sigue: no es un error del
material.

La segunda, que en un material de matemáticas el diccionario no conoce la
mitad de lo que se escribe --«Hahn», «Banach», «seminorma»--. Para eso está
`shared/palabras.txt`: una palabra por línea, las que son buenas aunque el
diccionario no lo sepa, para todos los idiomas del repositorio.

Lo que se le da a hunspell es **la prosa**: sin las fórmulas, sin las
órdenes de LaTeX, sin las etiquetas ni las rutas. Lo que se equivoca ahí lo
dice LaTeX al compilar.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unicodedata

#: Los diccionarios que sirven para cada idioma de Didacta, del mejor al peor.
#: Son los nombres con que los instalan LibreOffice y los paquetes de cada
#: sistema; el valenciano tiene el suyo, y si no está sirve el catalán.
DICTIONARIES = {
    "es": ("es_ES", "es_ANY", "es"),
    "va": ("ca_ES-valencia", "ca-valencia", "ca_ES", "ca"),
    "ca": ("ca_ES", "ca"),
    "gl": ("gl_ES", "gl"),
    "eu": ("eu_ES", "eu"),
    "en": ("en_US", "en_GB", "en"),
    "fr": ("fr_FR", "fr"),
    "de": ("de_DE", "de_DE_frami", "de"),
    "it": ("it_IT", "it"),
    "pt": ("pt_PT", "pt_BR", "pt"),
}

#: Las palabras buenas que el diccionario no conoce, relativo a la raíz.
WORDS_FILE = os.path.join("shared", "palabras.txt")

#: Cómo se instala, para decirlo cuando no está.
HOW_TO_INSTALL = (
    "en macOS, brew install hunspell y los diccionarios de LibreOffice en "
    "~/Library/Spelling; en Debian o Ubuntu, sudo apt install hunspell "
    "hunspell-es hunspell-ca hunspell-en-us"
)


def program():
    """El hunspell que se usa: el de `DIDACTA_HUNSPELL`, o el del PATH.

    Si `DIDACTA_HUNSPELL` dice uno que no es un programa, no hay ninguno: lo
    que se pidió manda, y buscar otro por detrás escondería la errata.
    """
    chosen = os.environ.get("DIDACTA_HUNSPELL")
    if chosen:
        return chosen if os.access(chosen, os.X_OK) else None
    return shutil.which("hunspell")


def available(hunspell):
    """Los diccionarios que encuentra [hunspell], por nombre.

    `hunspell -D` los lista en la salida de error, entre «AVAILABLE
    DICTIONARIES» y «LOADED DICTIONARY», con su ruta sin extensión. Sin nada
    en la entrada termina en cuanto los ha dicho.
    """
    try:
        done = subprocess.run(
            [hunspell, "-D"], stdin=subprocess.DEVNULL, capture_output=True,
            text=True, errors="replace", timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    found = {}
    listing = False
    for line in (done.stderr + "\n" + done.stdout).splitlines():
        if line.startswith("AVAILABLE DICTIONARIES"):
            listing = True
            continue
        if line.startswith(("LOADED DICTIONARY", "SEARCH PATH")):
            listing = False
            continue
        if listing and line.strip():
            path = line.strip()
            found.setdefault(os.path.basename(path), path)
    return found


def dictionary_for(language, found):
    """El diccionario de [found] para [language], o None."""
    for name in DICTIONARIES.get(language, (language,)):
        if name in found:
            return found[name]
    return None


def known_words(root):
    """Las palabras de `shared/palabras.txt`, sin los comentarios."""
    path = os.path.join(root, WORDS_FILE)
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        return set()
    words = set()
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            words.add(line)
    return words


# --------------------------------------------------------------------------
# La prosa de un fichero
# --------------------------------------------------------------------------

#: Donde lo de dentro es una fórmula o un dibujo, y no se lee.
_NOT_PROSE_ENVIRONMENTS = (
    "equation", "equation*", "align", "align*", "alignat", "alignat*",
    "gather", "gather*", "multline", "multline*", "flalign", "flalign*",
    "eqnarray", "eqnarray*", "displaymath", "math", "empheq", "tikzpicture",
    "tikzcd", "CD", "axis", "verbatim", "verbatim*", "lstlisting", "minted",
    "comment",
)

#: Órdenes cuyo argumento no es prosa: una etiqueta, una ruta, un color.
_NO_PROSE_ARGUMENT = re.compile(
    r"\\(?:label|ref|eqref|pageref|autoref|cref|Cref|nameref|cite[a-z]*|"
    r"nocite|includegraphics|input|include|import|subimport|href|url|"
    r"usepackage|RequirePackage|hspace|vspace|hskip|vskip|color|textcolor|"
    r"colorbox|setlength|addtolength|setcounter|addtocounter|definecolor|"
    r"newcommand|renewcommand|providecommand|DeclareMathOperator|"
    r"begin|end|resizebox|scalebox|rule|raisebox|makebox|framebox|"
    r"parbox|column|multicolumn|multirow|addlinespace)\*?"
    r"(?:\s*\[[^\]]*\])*(?:\s*\{[^{}]*\})?"
)

#: Las opciones de estos entornos son ajustes, no un título. El título de un
#: frame o de un bloque, entre llaves, sí es prosa, y se queda.
_OPTIONS_ARE_SETTINGS = re.compile(
    r"\\begin\s*\{(?:frame|figure|table|columns|itemize|enumerate|"
    r"description|center|tcolorbox|block)\}"
    r"(?:\s*<[^>]*>)?(?:\s*\[[^\]]*\])*"
)

#: Y en estos, también las llaves: el ancho de una columna, las de una tabla.
_ARGUMENTS_ARE_SETTINGS = re.compile(
    r"\\begin\s*\{(?:tabular\*?|tabularx|array|minipage|column|wrapfigure)\}"
    r"(?:\s*\[[^\]]*\])*(?:\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})*"
)

#: Las fórmulas, aunque ocupen varias líneas: `\[ … \]` con la fórmula en
#: las de en medio es lo normal en unos apuntes.
_MATH = re.compile(
    r"\$\$.*?\$\$|\\\[.*?\\\]|\\\(.*?\\\)|(?<!\\)\$(?:\\.|[^$\\])+?\$",
    re.S)
_ENVIRONMENT = re.compile(
    r"\\begin\s*\{(%s)\}.*?\\end\s*\{\1\}"
    % "|".join(re.escape(name) for name in _NOT_PROSE_ENVIRONMENTS),
    re.S)
#: `\vskip 3pt`, `\\[4pt]`: una medida no es una palabra.
_DIMENSION = re.compile(
    r"-?\d*\.?\d+\s*(?:pt|cm|mm|em|ex|in|bp|pc|mu|sp)(?![^\W\d_])")
_COMMAND = re.compile(r"\\[A-Za-z@]+\*?|\\.")
_PUNCTUATION = re.compile(r"[{}\[\]~&_^#]")


def _uncomment(line):
    match = re.search(r"(?<!\\)%", line)
    return line[:match.start()] if match else line


#: Los acentos escritos a la manera de LaTeX, que en el material migrado son
#: la mitad: `composici\'{o}n` es «composición», y sin esto llegaba a
#: hunspell como «composici» y una «n» suelta.
_ACCENT = re.compile(
    r"\\([\'`\"~^])\s*(?:\{\s*(\\i|[A-Za-z])\s*\}|(\\i(?![A-Za-z])|[A-Za-z]))")
_CEDILLA = re.compile(r"\\c\s*\{\s*([cC])\s*\}|\\c\s+([cC])")
_COMBINING = {"'": "\u0301", "`": "\u0300", '"': "\u0308", "~": "\u0303",
              "^": "\u0302"}


def _accents(text):
    def accent(match):
        letter = match.group(2) or match.group(3)
        letter = "i" if letter == "\\i" else letter
        return unicodedata.normalize("NFC", letter + _COMBINING[match.group(1)])

    def cedilla(match):
        return unicodedata.normalize(
            "NFC", (match.group(1) or match.group(2)) + "\u0327")

    return _CEDILLA.sub(cedilla, _ACCENT.sub(accent, text))


def _blank(match):
    """Lo que se quita, cambiado por sus saltos de línea: los números de línea
    de lo que queda siguen siendo los del fichero."""
    return " " + "\n" * match.group(0).count("\n")


def prose_lines(text):
    """(número de línea, prosa) de cada línea de [text] que tiene algo que leer.

    La prosa es lo que queda al quitar los comentarios, las fórmulas, los
    entornos que no son texto y las órdenes; el texto de dentro de una orden
    --`\\emph{así}`, el título de `\\begin{theorem}[Hahn-Banach]`-- se queda.
    """
    body = "\n".join(_uncomment(line) for line in text.split("\n"))
    body = _accents(body)
    body = _ENVIRONMENT.sub(_blank, body)
    body = _MATH.sub(_blank, body)
    for number, line in enumerate(body.split("\n"), start=1):
        line = _ARGUMENTS_ARE_SETTINGS.sub(" ", line)
        line = _OPTIONS_ARE_SETTINGS.sub(" ", line)
        line = _NO_PROSE_ARGUMENT.sub(" ", line)
        line = _DIMENSION.sub(" ", line)
        line = _COMMAND.sub(" ", line)
        line = _PUNCTUATION.sub(" ", line)
        line = re.sub(r"\s+", " ", line).strip()
        if re.search(r"[^\W\d_]{2,}", line):
            yield number, line


# --------------------------------------------------------------------------
# Preguntarle a hunspell
# --------------------------------------------------------------------------

def misspelled(hunspell, dictionary, lines):
    """Lo que [dictionary] no conoce de cada una de [lines], en su orden.

    Una lista por línea, con `(palabra, sugerencias)`. Es el protocolo de
    ispell, `hunspell -a`: una línea de cabecera y, por cada línea que
    entra, una por palabra que no conoce --`&` con sugerencias, `#` sin
    ellas-- y una en blanco al final. El `!` del principio le quita lo que
    dice de las palabras buenas, y el `^` delante de cada línea evita que
    una que empiece por `*` o `@` se lea como una orden.
    """
    result = [[] for _ in lines]
    if not lines:
        return result
    text = "!\n" + "".join("^%s\n" % line for line in lines)
    done = subprocess.run(
        [hunspell, "-a", "-i", "UTF-8", "-d", dictionary],
        input=text, capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=300,
    )
    index = 0
    for raw in done.stdout.splitlines():
        if raw.startswith("@(#)"):
            continue
        if index >= len(lines):
            break
        if not raw.strip():
            index += 1
            continue
        if raw[0] not in "&#":
            continue
        head, _, tail = raw.partition(":")
        parts = head.split()
        if len(parts) < 2:
            continue
        suggestions = [each.strip() for each in tail.split(",") if each.strip()]
        result[index].append((parts[1], suggestions))
    return result
