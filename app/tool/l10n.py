#!/usr/bin/env python3
"""Las traducciones de la interfaz: sacar las claves, escribir los catálogos
y decir qué falta.

    python3 tool/l10n.py extract    # l10n/keys.json: cada texto y dónde está
    python3 tool/l10n.py build      # l10n/va.json, en.json -> lib/l10n/catalog_*.dart
    python3 tool/l10n.py missing    # qué claves no tienen traducción

La clave de cada texto es el propio texto en castellano (ver
`lib/l10n/tr.dart`). En `l10n/va.json` y `l10n/en.json` cada clave lleva su
traducción, o `null` si no es un texto de la interfaz --una ruta, un trozo de
YAML que se escribe en un fichero-- y no se traduce nunca.

Qué es una clave: el primer argumento de cada `tr(...)`, con sus trozos
pegados, y además los textos de las constantes que se traducen al leerlas
(`TexWord`, `TourStep`, los `enum` con texto…), que en el fuente no llevan
`tr` porque no pueden: son `const`. Esos van en [CONST_TEXTS].
"""

from __future__ import annotations

import json
import os
import re
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(APP, "lib")
L10N = os.path.join(APP, "l10n")
LANGUAGES = ("va", "en")

#: Dónde hay textos constantes que se traducen al leerlos, y cómo
#: reconocerlos: el fichero y una expresión que casa con el literal (el grupo
#: 1 es la cadena entera, con sus comillas).
LIT = r"((?:r?'(?:[^'\\\n]|\\.)*'\s*)+|(?:r?\"(?:[^\"\\\n]|\\.)*\"\s*)+)"
CONST_TEXTS = [
    ("model/tex_vocabulary.dart", r"TexWord\(\s*'[^']*',\s*" + LIT),
    ("ui/tour.dart", r"(?:title|body|chapter):\s*" + LIT),
    ("ui/shortcuts.dart", r"^\s*\w+\(\s*" + LIT),
    ("model/palette.dart", r"^\s*\w+\(" + LIT + r"\)"),
    ("model/tex_wrap.dart", r"(?:label|groupLabel):\s*" + LIT),
    ("model/tex_snippets.dart", r"tooltip:\s*" + LIT),
    ("model/tex_snippets.dart", r"TexPalette\(\s*" + LIT),
    ("model/toolchain.dart", r"(?:what|missing):\s*" + LIT),
    ("model/review.dart", r"'[a-z-]+':\s*" + LIT),
    ("model/tex_check.dart", r"'(?:spanish|galician|catalan|french)':\s*" + LIT),
    ("ui/compare_view.dart", r"ChangedThing\.\w+:\s*" + LIT),
    ("ui/courses_page.dart", r"CoursesView\.\w+:\s*" + LIT),
]


def decode(literal: str) -> str:
    """El valor de uno o varios literales de Dart pegados."""
    out = []
    for match in re.finditer(r"(r?)('''|\"\"\"|'|\")(.*?)\2", literal, re.S):
        raw, _, body = match.groups()
        if raw:
            out.append(body)
            continue
        i = 0
        while i < len(body):
            c = body[i]
            if c == "\\" and i + 1 < len(body):
                n = body[i + 1]
                if n == "n":
                    out.append("\n")
                elif n == "t":
                    out.append("\t")
                elif n == "r":
                    out.append("\r")
                elif n == "u":
                    m = re.match(r"\{([0-9a-fA-F]+)\}|([0-9a-fA-F]{4})",
                                 body[i + 2:])
                    code = m.group(1) or m.group(2)
                    out.append(chr(int(code, 16)))
                    i += 2 + m.end()
                    continue
                elif n == "x":
                    out.append(chr(int(body[i + 2:i + 4], 16)))
                    i += 4
                    continue
                else:
                    out.append(n)
                i += 2
                continue
            out.append(c)
            i += 1
    return "".join(out)


def encode(text: str) -> str:
    """Un literal de Dart que vale [text]."""
    return "'" + (text.replace("\\", "\\\\").replace("'", "\\'")
                  .replace("$", "\\$").replace("\n", "\\n")
                  .replace("\r", "\\r").replace("\t", "\\t")) + "'"


def strip_comments(src: str) -> str:
    """El fuente con los comentarios en blanco (misma longitud), para que
    un `tr('…')` de un comentario no cuente y las líneas no se muevan."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
            continue
        c = src[i]
        if c in "'\"":
            q = c
            triple = src.startswith(q * 3, i)
            quote = q * 3 if triple else q
            raw = i > 0 and src[i - 1] == "r"
            j = i + len(quote)
            while j < n and not src.startswith(quote, j):
                if src[j] == "\\" and not raw:
                    j += 2
                    continue
                j += 1
            j += len(quote)
            out.append(src[i:j])
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


TR_CALL = re.compile(r"(?<![\w.])tr\(\s*" + LIT.replace("\\n]", "]")
                     .replace("[^'\\\\]", "[^'\\\\]"), re.S)


def tr_keys(path: str, src: str):
    clean = strip_comments(src)
    for match in re.finditer(r"(?<![\w.])tr\(\s*", clean):
        j = match.end()
        pieces = []
        while True:
            m = re.match(r"(r?)('''|\"\"\"|'|\")", clean[j:])
            if not m:
                break
            quote = m.group(2)
            k = j + m.end()
            while k < len(clean) and not clean.startswith(quote, k):
                if clean[k] == "\\" and not m.group(1):
                    k += 2
                    continue
                k += 1
            k += len(quote)
            pieces.append(clean[j:k])
            rest = re.match(r"\s*", clean[k:])
            j = k + rest.end()
        if pieces:
            line = src.count("\n", 0, match.start()) + 1
            yield decode("".join(pieces)), line


def extract() -> dict:
    found: dict[str, list[str]] = {}
    for folder, _, files in os.walk(LIB):
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(folder, name)
            relative = os.path.relpath(path, LIB)
            if relative.startswith("l10n/"):
                continue
            with open(path, encoding="utf-8") as handle:
                src = handle.read()
            for key, line in tr_keys(path, src):
                found.setdefault(key, []).append("%s:%d" % (relative, line))
            for file, pattern in CONST_TEXTS:
                if relative != file:
                    continue
                clean = strip_comments(src)
                for match in re.finditer(pattern, clean, re.M):
                    key = decode(match.group(1))
                    line = src.count("\n", 0, match.start(1)) + 1
                    found.setdefault(key, []).append(
                        "%s:%d" % (relative, line))
    return dict(sorted(found.items()))


def load(language: str) -> dict:
    path = os.path.join(L10N, "%s.json" % language)
    if not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def placeholders(text: str) -> set[str]:
    return set(re.findall(r"\{\d+\}", text))


def build() -> int:
    keys = extract()
    problems = 0
    for language in LANGUAGES:
        table = load(language)
        lines = [
            "/// Generado por tool/l10n.py desde l10n/%s.json: no se edita a "
            "mano." % language,
            "library;",
            "",
            "const Map<String, String> %sStrings = {" % language,
        ]
        for key in keys:
            value = table.get(key)
            if value is None:
                continue
            if placeholders(value) != placeholders(key):
                print("%s: los marcadores no cuadran en %r" % (language, key))
                problems += 1
                continue
            lines.append("  %s: %s," % (encode(key), encode(value)))
        lines.append("};")
        target = os.path.join(LIB, "l10n", "catalog_%s.dart" % language)
        with open(target, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    return problems


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "missing"
    if command == "extract":
        keys = extract()
        os.makedirs(L10N, exist_ok=True)
        with open(os.path.join(L10N, "keys.json"), "w",
                  encoding="utf-8") as handle:
            json.dump(keys, handle, ensure_ascii=False, indent=1)
        print("%d claves" % len(keys))
        return 0
    if command == "build":
        return 1 if build() else 0
    if command == "missing":
        keys = extract()
        missing = 0
        for language in LANGUAGES:
            table = load(language)
            absent = [key for key in keys if key not in table]
            missing += len(absent)
            print("%s: %d sin traducir" % (language, len(absent)))
            for key in absent[:20]:
                print("   %r  (%s)" % (key[:70], keys[key][0]))
        return 1 if missing else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
