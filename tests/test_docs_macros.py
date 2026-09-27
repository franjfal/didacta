"""Lo que la documentación enseña a escribir existe de verdad.

La guía de la web enseñaba `\\begin{problem}`, `\\hint{…}` o `\\didactafigure`,
y ninguno de los tres existe: quien copiaba el ejemplo de la documentación no
compilaba. Esto lee los bloques ```latex de la documentación y comprueba cada
entorno y cada orden de Didacta contra lo que definen los `.sty`, para que la
próxima vez que cambie un nombre la documentación no se quede atrás en
silencio.

Sin TeX: solo lee ficheros.
"""

from __future__ import annotations

import glob
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LATEX = os.path.join(ROOT, "latex")

#: Lo que no define Didacta y se puede usar igual: LaTeX, beamer, amsmath,
#: tikz. Una lista corta a propósito; si la documentación empieza a enseñar
#: otro entorno de un paquete, se añade aquí sabiendo que existe.
STANDARD_ENVIRONMENTS = {
    "document", "itemize", "enumerate", "description", "frame", "block",
    "columns", "column", "equation", "equation*", "align", "align*",
    "gather", "gather*", "multline", "split", "aligned", "cases", "matrix",
    "pmatrix", "bmatrix", "vmatrix", "array", "tabular", "figure", "table",
    "center", "flushleft", "flushright", "minipage", "quote", "verbatim",
    "tikzpicture", "axis", "CD", "wrapfigure", "subfigure",
    "thebibliography",
}

_DEFINED_ENVIRONMENT = re.compile(
    r"\\(?:re)?newenvironment\{([^}#]+)\}"
    r"|\\NewEnviron\{([^}#]+)\}"
    r"|\\NewDocumentEnvironment\{([^}#]+)\}"
    r"|\\newtcolorbox\{([^}#]+)\}"
    r"|\\didacta@alias\{([^}#]+)\}"
)
_THEOREM = re.compile(r"\\DidactaNewTheorem\{([^}#]+)\}")
_DEFINED_COMMAND = re.compile(
    r"\\(?:(?:re)?newcommand|providecommand|DeclareRobustCommand"
    r"|NewDocumentCommand)\*?\{?\\([A-Za-z@]+)"
    r"|\\(?:g|e|x)?def\\([A-Za-z@]+)"
    r"|\\let\\([A-Za-z@]+)"
)


def _latex_sources():
    patterns = ("*.sty", "*.tex", os.path.join("lang", "*.def"))
    for pattern in patterns:
        for path in glob.glob(os.path.join(LATEX, pattern)):
            with open(path, encoding="utf-8") as handle:
                yield handle.read()


def defined():
    environments, commands, theorems = set(), set(), set()
    for text in _latex_sources():
        for match in _DEFINED_ENVIRONMENT.finditer(text):
            environments.add(next(group for group in match.groups() if group))
        for match in _THEOREM.finditer(text):
            theorems.add(match.group(1))
        for match in _DEFINED_COMMAND.finditer(text):
            commands.add(next(group for group in match.groups() if group))
    # Cada teorema viene con su versión sin numerar.
    environments |= theorems | {name + "*" for name in theorems}
    return environments, commands


def documented():
    """(fichero, bloque) de cada ```latex de la documentación."""
    files = sorted(
        glob.glob(os.path.join(ROOT, "web", "docs", "**", "*.md"),
                  recursive=True)
        + glob.glob(os.path.join(ROOT, "docs", "*.md"))
        + [os.path.join(ROOT, "README.md")]
    )
    for path in files:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for block in re.findall(r"```latex\n(.*?)```", text, re.S):
            yield os.path.relpath(path, ROOT), block


class DocumentedMacroTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.environments, cls.commands = defined()

    def test_the_parser_sees_what_didacta_defines(self):
        # Si esto falla, el test de abajo no está comprobando nada.
        for name in ("exercise", "hint", "answer", "theorem", "definition*",
                     "keypoint", "ndefn"):
            self.assertIn(name, self.environments)
        for name in ("didactatitle", "DidactaUnit", "dmarks", "sen"):
            self.assertIn(name, self.commands)

    def test_every_environment_in_the_docs_exists(self):
        wrong = []
        for where, block in documented():
            for name in re.findall(r"\\begin\{([^}]+)\}", block):
                if name not in self.environments | STANDARD_ENVIRONMENTS:
                    wrong.append("%s: \\begin{%s}" % (where, name))
        self.assertEqual(wrong, [], "\n".join(wrong))

    def test_every_didacta_command_in_the_docs_exists(self):
        wrong = []
        for where, block in documented():
            for name in re.findall(r"\\([A-Za-z@]+)", block):
                if name.lower().startswith("didacta") and name not in self.commands:
                    wrong.append("%s: \\%s" % (where, name))
        self.assertEqual(wrong, [], "\n".join(wrong))

    def test_no_environment_is_written_as_a_command(self):
        # `\hint{…}` en lugar de `\begin{hint}…\end{hint}`: se lee bien y no
        # compila.
        wrong = []
        for where, block in documented():
            for name in re.findall(r"\\([A-Za-z]+)\s*\{", block):
                if (name in self.environments and name not in self.commands
                        and name not in ("begin", "end")):
                    wrong.append("%s: \\%s{…}" % (where, name))
        self.assertEqual(wrong, [], "\n".join(wrong))


if __name__ == "__main__":
    unittest.main()
