"""De un punto del PDF a la línea del fichero que lo escribió.

Cada compilación genera un `.synctex.gz` junto al PDF (`-synctex=1`), y hasta
ahora nadie lo leía. Con él, pulsar una diapositiva lleva a la lección y a la
línea de donde salió: lo que se ve mal se arregla ahí, sin buscarlo.

Se pregunta a `synctex`, que viene con cualquier distribución de TeX: el
formato del fichero es suyo, y la herramienta sabe leer todas sus versiones.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unicodedata


class SyncTexError(Exception):
    """No se pudo preguntar, o no hay dónde."""


def available():
    return shutil.which("synctex") is not None


def edit(pdf, page, x, y):
    """El fichero y la línea del punto ([x], [y]) de la página [page].

    Las coordenadas en puntos PostScript, desde la esquina de **arriba** a la
    izquierda de la página, que es como las pide `synctex`. None si en ese
    punto no hay nada que venga de un fichero --un margen, un fondo--.
    """
    pdf = os.path.abspath(pdf)
    if not os.path.isfile(pdf):
        raise SyncTexError("no existe el PDF: %s" % pdf)
    base = os.path.splitext(pdf)[0]
    if not (os.path.isfile(base + ".synctex.gz")
            or os.path.isfile(base + ".synctex")):
        raise SyncTexError(
            "este PDF no tiene su .synctex.gz: vuelve a compilarlo"
        )
    if not available():
        raise SyncTexError(
            "no se encuentra `synctex`, que viene con la distribución de TeX"
        )
    # Con el nombre y no la ruta: `synctex` separa página, x, y y fichero
    # por los dos puntos, y una ruta de Windows ya lleva uno.
    done = subprocess.run(
        ["synctex", "edit", "-o",
         "%d:%.2f:%.2f:%s" % (page, x, y, os.path.basename(pdf))],
        cwd=os.path.dirname(pdf), capture_output=True, text=True,
        errors="replace", stdin=subprocess.DEVNULL,
    )
    found = {}
    for line in done.stdout.splitlines():
        key, _, value = line.partition(":")
        # El primer resultado: si hay varios, son del mismo sitio.
        if key in ("Input", "Line", "Column") and key not in found:
            found[key] = value
        if key == "SyncTeX result end":
            break
    source = found.get("Input")
    try:
        number = int(found.get("Line", ""))
    except ValueError:
        number = None
    if not source or not number or number < 1:
        return None
    return {"file": os.path.normpath(source), "line": number}


_BEGIN_FRAME = re.compile(r"\\begin\s*\{frame\}")
_END_FRAME = re.compile(r"\\end\s*\{frame\}")
#: `\'{o}`, `\'o`, `\~n`: una letra con tilde escrita a la antigua.
_TEX_ACCENT = re.compile(r"\\[`'^\"~=.]\s*\{?([A-Za-z])\}?")
_WORD = re.compile(r"[^\W\d_]{3,}", re.UNICODE)


def _uncommented(line):
    match = re.search(r"(?<!\\)%", line)
    return line[:match.start()] if match else line


def _words(text):
    """Las palabras de [text], sin tildes ni mayúsculas, como se comparan."""
    text = _TEX_ACCENT.sub(r"\1", text)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    return _WORD.findall(text.lower())


def refine(found, text=None, word=None):
    r"""Afina la línea en una diapositiva.

    beamer lee una diapositiva entera como argumento y la compone al llegar a
    su `\end{frame}`, así que SyncTeX apunta ahí todo lo que tiene dentro.
    Con el texto que había bajo el cursor --[word], la palabra, y [text], su
    línea en el PDF-- se busca entre el `egin{frame}` y el `\end{frame}`
    la línea del fichero que más se le parece. Si nada se parece, el
    `egin{frame}`: mejor el principio de la diapositiva que su final.
    """
    try:
        with open(found["file"], encoding="utf-8", errors="replace") as handle:
            lines = handle.read().split("\n")
    except OSError:
        return found
    end = found["line"]
    if end > len(lines) or not _END_FRAME.search(_uncommented(lines[end - 1])):
        return found
    start = None
    for number in range(end - 1, 0, -1):
        line = _uncommented(lines[number - 1])
        if _BEGIN_FRAME.search(line):
            start = number
            break
        if _END_FRAME.search(line):
            break
    if start is None:
        return found
    wanted = set(_words(text or ""))
    key = set(_words(word or ""))
    best, score = start, 0
    for number in range(start, end):
        present = set(_words(lines[number - 1]))
        points = len(present & wanted) + 3 * len(present & key)
        if points > score:
            best, score = number, points
    found["line"] = best
    found["frame"] = start
    return found


def in_repository(file, root):
    """Dónde está [file] dicho como lo dice el repositorio.

    La ruta desde [root] y, si es el `.tex` de una lección, cuál y en qué
    idioma: lo mismo que `build.locate` hace con los errores.
    """
    # Las dos por su ruta real: en macOS `/tmp` es `/private/tmp`, y
    # `synctex` dice la que usó LaTeX.
    relative = os.path.relpath(
        os.path.realpath(file), os.path.realpath(root)
    ).replace(os.sep, "/")
    if relative.startswith("../"):
        return {}
    where = {"path": relative}
    parts = relative.split("/")
    if (len(parts) >= 3 and parts[0] in ("content", "problems")
            and parts[-1].endswith(".tex")):
        where["unit"] = "/".join(parts[:-1])
        where["language"] = parts[-1][:-len(".tex")]
    return where
