"""Lo que entró en un PDF, para saber de verdad si se ha quedado viejo.

Un PDF estaba «viejo» si alguna de sus lecciones tenía una fecha posterior.
Las fechas mienten en los dos sentidos: un `git pull` o un cambio de rama las
pone al día aunque el texto sea el mismo --y entonces todo parece viejo--, y
copiar una carpeta con las fechas conservadas puede dejar un cambio de verdad
con fecha antigua.

Así que, al compilar bien, se apunta junto al PDF la huella (sha256) de cada
fichero que LaTeX leyó --lecciones, figuras, el `.bib`, las plantillas, el
propio Didacta-- según su `.fls`. Viejo es que alguno haya cambiado de
contenido. Para no leer dos mil ficheros cada vez que se pregunta, se apunta
también su fecha y su tamaño: si no han cambiado, no se vuelve a leer.

Una cosa que el `.fls` no dice: los ficheros que LaTeX buscó y **no** estaban.
Una lección compilada en valenciano sin `va.tex` sale con el castellano; si
después aparece la traducción, el PDF se ha quedado viejo sin que cambie nada
de lo que leyó. Por eso se apunta también qué `.tex` había en cada lección.
"""

from __future__ import annotations

import hashlib
import json
import os

#: Junto al PDF, con el mismo nombre.
SUFFIX = ".didacta-inputs.json"

#: Lo que LaTeX escribe y luego vuelve a leer: consecuencia de compilar, no
#: causa, y cambia en cada compilación.
_ITS_OWN = (
    ".aux", ".toc", ".out", ".nav", ".snm", ".vrb", ".bbl", ".bcf", ".blg",
    ".run.xml", ".fls", ".log", ".lof", ".lot", ".idx", ".ind", ".ilg",
    ".synctex.gz", ".fdb_latexmk", ".mw", ".xdv",
)
# Un `.pdf` no: muchas figuras lo son, y el PDF que sale LaTeX no lo lee.


def path_for(pdf):
    return pdf + SUFFIX


def _hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def read_fls(fls_path):
    """Los ficheros que leyó LaTeX, con su ruta absoluta."""
    found = []
    pwd = os.path.dirname(os.path.abspath(fls_path))
    try:
        with open(fls_path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return found
    seen = set()
    for line in lines:
        if line.startswith("PWD "):
            pwd = line[4:].strip()
            continue
        if not line.startswith("INPUT "):
            continue
        path = line[6:].strip()
        if not os.path.isabs(path):
            path = os.path.join(pwd, path)
        path = os.path.normpath(path)
        if path not in seen:
            seen.add(path)
            found.append(path)
    return found


def record(pdf, fls_path, roots, lesson_root=None, quick=False):
    """Apunta la huella de lo que leyó LaTeX para [pdf].

    [roots] son las carpetas cuyo contenido cuenta: el repositorio, la de
    Didacta y las de plantillas. Lo de la distribución de TeX no: cambia al
    actualizar TeX Live, y recompilarlo todo por eso sería avisar de algo que
    no es de nadie. [lesson_root] es la raíz del repositorio, para apuntar
    qué traducciones había en cada lección.

    [quick] es una compilación de una sola pasada: se apunta, y el PDF cuenta
    como viejo aunque nada cambie --el índice y las referencias pueden no
    estar al día--, hasta que se compile entero.
    """
    roots = [os.path.normpath(os.path.abspath(r)) for r in roots if r]
    files = {}
    lessons = {}
    for path in read_fls(fls_path):
        if path.endswith(_ITS_OWN) or not os.path.isfile(path):
            continue
        if not any(path == r or path.startswith(r + os.sep) for r in roots):
            continue
        stat = os.stat(path)
        files[path] = {
            "sha256": _hash(path),
            "mtime": stat.st_mtime,
            "size": stat.st_size,
        }
        if lesson_root and path.endswith(".tex"):
            relative = os.path.relpath(path, lesson_root).replace(os.sep, "/")
            if relative.split("/")[0] in ("content", "problems"):
                directory = os.path.dirname(path)
                lessons[directory] = _translations_in(directory)
    data = {"version": 1, "files": files, "lessons": lessons}
    if quick:
        data["quick"] = True
    with open(path_for(pdf), "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=1, ensure_ascii=False)
    return files


def _translations_in(directory):
    try:
        return sorted(
            name for name in os.listdir(directory) if name.endswith(".tex")
        )
    except OSError:
        return []


def _read(pdf):
    try:
        with open(path_for(pdf), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def is_quick(pdf):
    """Si [pdf] salió de una sola pasada (`--fast`)."""
    data = _read(pdf)
    return bool(data and data.get("quick"))


def is_stale(pdf):
    """Si algo de lo que entró en [pdf] ha cambiado de contenido.

    None si no se sabe --un PDF de antes de esto, o un registro que no se
    puede leer--, y entonces quien pregunta decide por las fechas. Uno de
    una sola pasada, siempre: no es lo que se reparte.
    """
    data = _read(pdf)
    if data is None:
        return None
    files = data.get("files")
    if not isinstance(files, dict):
        return None
    if data.get("quick"):
        return True
    for path, known in files.items():
        try:
            stat = os.stat(path)
        except OSError:
            return True
        if stat.st_size == known.get("size") and stat.st_mtime == known.get("mtime"):
            continue
        if stat.st_size != known.get("size"):
            return True
        try:
            if _hash(path) != known.get("sha256"):
                return True
        except OSError:
            return True
    for directory, names in (data.get("lessons") or {}).items():
        if _translations_in(directory) != names:
            return True
    return False
