"""Lo que una lección escrita como apuntes necesita para salir en diapositivas.

Las prácticas de un repositorio de problemas se escriben como apuntes, con sus
apartados, y se ponen en diapositivas después. Tres piezas lo hacen posible sin
tocar los apuntes, y es lo que se comprueba aquí con LaTeX de verdad:

* `\\slidetitle{…}` es el título de la diapositiva, y no sale en los apuntes:
  `\\didactatitle` lo convertiría en un subapartado que nunca estuvo ahí;
* `\\paragraph`, que beamer no trae, en una diapositiva es el encabezado en
  negrita de un párrafo, como en los apuntes;
* un apartado sin ninguna diapositiva --los problemas propuestos del final,
  que solo van en los apuntes-- no sale en las diapositivas: ni su portada ni
  su línea en el índice. En los apuntes sale como siempre.

Necesita TeX Live; sin él se salta.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

from test_outputs import pdf_text, toolchain_available  # noqa: E402

SUBTOPIC = os.path.join("content", "calculo", "limites", "concepto-de-limite")

UNIT_YAML = """id: {id}
kind: theory
block: theory
title:
  es: {title}
category: calculo
topic: limites
subtopic: concepto-de-limite
reference: es
languages:
  es: {{status: source}}
"""


@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class SlidesStructureTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.mkdtemp(prefix="didacta-slides-structure-")
        cls.repo = os.path.join(cls.work, "ej")
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"), cls.repo)

        def unit(name, identifier, title, body):
            folder = os.path.join(cls.repo, SUBTOPIC, name)
            os.makedirs(folder)
            with open(os.path.join(folder, "unit.yaml"), "w", encoding="utf-8") as h:
                h.write(UNIT_YAML.format(id=identifier, title=title))
            with open(os.path.join(folder, "es.tex"), "w", encoding="utf-8") as h:
                h.write(body)

        unit("con-diapositiva", "u-5e1f0a000001", "Con diapositiva",
             "\\begin{frame}\\slidetitle{Titulodiapositiva}\n"
             "\\paragraph{Encabezadoparrafo} Textodelparrafo.\n"
             "\\end{frame}\n")
        unit("solo-apuntes", "u-5e1f0a000002", "Solo apuntes",
             "\\begin{notesonly}\nSoloenlosapuntes.\n\\end{notesonly}\n")

        year = os.path.join(cls.repo, "courses", "calculo-i", "2026-2027", "year.yaml")
        with open(year, encoding="utf-8") as h:
            text = h.read()
        anchor = "    structure:\n"
        at = text.index(anchor) + len(anchor)
        text = text[:at] + (
            "      - section:\n          es: Seccionconlecciones\n"
            "      - unit: u-5e1f0a000001\n"
            "      - section:\n          es: Seccionsindiapositivas\n"
            "      - unit: u-5e1f0a000002\n"
        ) + text[at:]
        with open(year, "w", encoding="utf-8") as h:
            h.write(text)

        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "build",
             "calculo-i@2026-2027/tema-1", "-p", "slides", "-p", "notes",
             "-l", "es", "--json"],
            cwd=cls.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )
        start = done.stdout.index("[")
        cls.results = {r["profile"]: r for r in json.loads(done.stdout[start:])}

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def text(self, profile):
        result = self.results[profile]
        self.assertTrue(result["ok"], result["diagnostics"])
        return pdf_text(result["pdf"])

    def test_el_titulo_de_la_diapositiva_solo_en_las_diapositivas(self):
        self.assertIn("Titulodiapositiva", self.text("slides"))
        self.assertNotIn("Titulodiapositiva", self.text("notes"))

    def test_paragraph_tambien_en_beamer(self):
        self.assertIn("Encabezadoparrafo", self.text("slides"))
        self.assertIn("Encabezadoparrafo", self.text("notes"))

    def test_un_apartado_sin_diapositivas_no_sale_en_ellas(self):
        slides = self.text("slides")
        self.assertIn("Seccionconlecciones", slides)
        self.assertNotIn("Seccionsindiapositivas", slides)
        self.assertNotIn("Soloenlosapuntes", slides)

    def test_en_los_apuntes_sale_como_siempre(self):
        notes = self.text("notes")
        self.assertIn("Seccionconlecciones", notes)
        self.assertIn("Seccionsindiapositivas", notes)
        self.assertIn("Soloenlosapuntes", notes)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
