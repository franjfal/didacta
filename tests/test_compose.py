"""Tests de la composición escrita en el `.tex`.

El fallo que existe este módulo para que no vuelva: un subapartado añadido
desde la aplicación se guardaba en `year.yaml`, se veía en la pantalla de
composición y no salía en el PDF, porque lo que compila `pdflatex` es el
`.tex` de al lado y nadie lo escribía.

Lo que hay que comprobar no es que lo escriba --eso es la mitad fácil-- sino
que escriba **sólo** eso: el preámbulo se queda, lo comentado se queda
comentado, los escapes de YAML no se cuelan en el LaTeX, y un fichero con
algo que la composición no sabe decir no se toca.
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "engine"))

from didacta import compose  # noqa: E402


YEAR = """\
course: am-i
year: 2026-2027
language: es

documents:
  - id: practica-1
    kind: practical
    title:
      es: "Práctica 1"
    structure:
      - section:
          es: Los naturales
          # TODO: va
      - unit: analisis/induccion/principio
      # - unit: analisis/induccion/apartada
      - section:
          es: "Apéndice: lo que hará falta"
      - subsection:
          es: Logaritmos
      - unit: analisis/apendice/logaritmos
      - subsection:
          es: Trigonometría
      - unit: analisis/apendice/trigonometria
  - id: practica-2
    kind: practical
    title:
      es: "Práctica 2"
    structure:
      - unit: analisis/otra/cosa
"""

MASTER = """\
% Práctica 1
%
% La selección y el orden viven en year.yaml.

\\input{didacta-bootstrap}
\\usepackage{didacta}

\\DidactaCourse{
  title = {Análisis Matemático I},
}
\\DidactaDocument{Práctica 1}

\\begin{document}
\\DidactaTitlePage
\\DidactaContents

\\section{Los naturales}
\\DidactaUnit{analisis/induccion/principio}

\\section{Apéndice: lo que hará falta}
\\DidactaUnit{analisis/apendice/logaritmos}
\\DidactaUnit{analisis/apendice/trigonometria}
\\end{document}
"""


class EntryTests(unittest.TestCase):
    def test_reads_the_order_with_headings_and_subheadings(self):
        found = compose.entries(YEAR, "practica-1")
        self.assertEqual(
            [(e.kind, e.title("es")) for e in found if e.is_heading],
            [
                ("section", "Los naturales"),
                ("section", "Apéndice: lo que hará falta"),
                ("subsection", "Logaritmos"),
                ("subsection", "Trigonometría"),
            ],
        )

    def test_keeps_what_is_commented_out(self):
        found = compose.entries(YEAR, "practica-1")
        off = [e for e in found if not e.enabled]
        self.assertEqual([e.value for e in off], ["analisis/induccion/apartada"])

    def test_reads_only_the_document_asked_for(self):
        found = compose.entries(YEAR, "practica-2")
        self.assertEqual([e.value for e in found], ["analisis/otra/cosa"])

    def test_a_document_that_is_not_there_is_not_an_empty_one(self):
        self.assertIsNone(compose.entries(YEAR, "practica-9"))
        self.assertEqual(compose.entries(YEAR.replace(
            "      - unit: analisis/otra/cosa", ""), "practica-2"), [])

    def test_a_title_in_quotes_keeps_its_latex(self):
        # `"Densidad de $\\mathbb Q$"` en YAML es una barra, no dos. Con dos,
        # LaTeX lee un salto de línea en medio de un encabezado.
        text = YEAR.replace("          es: Logaritmos",
                            '          es: "Densidad de $\\\\mathbb Q$"')
        found = compose.entries(text, "practica-1")
        titles = [e.title("es") for e in found if e.kind == "subsection"]
        self.assertIn("Densidad de $\\mathbb Q$", titles)

    def test_falls_back_to_a_title_in_another_language(self):
        found = compose.entries(YEAR, "practica-1")
        heading = next(e for e in found if e.is_heading)
        self.assertEqual(heading.title("va"), "Los naturales")


class RenderTests(unittest.TestCase):
    def test_writes_each_kind_with_its_macro(self):
        found = compose.entries(YEAR, "practica-1")
        body = compose.render(found, "es")
        self.assertIn("\\section{Los naturales}", body)
        self.assertIn("\\subsection{Logaritmos}", body)
        self.assertIn("\\DidactaUnit{analisis/apendice/logaritmos}", body)

    def test_what_is_off_stays_off(self):
        body = compose.render(compose.entries(YEAR, "practica-1"), "es")
        self.assertIn("%% \\DidactaUnit{analisis/induccion/apartada}", body)

    def test_a_blank_line_opens_a_section_and_not_a_subsection(self):
        body = compose.render(compose.entries(YEAR, "practica-1"), "es")
        at = body.index("\\section{Apéndice: lo que hará falta}")
        self.assertEqual(body[at - 1], "")
        self.assertNotEqual(body[body.index("\\subsection{Logaritmos}") - 1], "")


class ComposeTests(unittest.TestCase):
    def test_adds_the_subheadings_the_composition_gained(self):
        out, why = compose.compose(MASTER, compose.entries(YEAR, "practica-1"), "es")
        self.assertIsNone(why)
        self.assertIn("\\subsection{Logaritmos}", out)
        self.assertIn("\\subsection{Trigonometría}", out)

    def test_leaves_the_preamble_and_the_cover_alone(self):
        out, _ = compose.compose(MASTER, compose.entries(YEAR, "practica-1"), "es")
        self.assertIn("\\input{didacta-bootstrap}", out)
        self.assertIn("\\DidactaCourse{", out)
        self.assertIn("\\DidactaTitlePage", out)
        self.assertIn("\\DidactaContents", out)
        self.assertTrue(out.rstrip().endswith("\\end{document}"))

    def test_running_it_twice_changes_nothing_the_second_time(self):
        once, _ = compose.compose(MASTER, compose.entries(YEAR, "practica-1"), "es")
        twice, _ = compose.compose(once, compose.entries(YEAR, "practica-1"), "es")
        self.assertEqual(once, twice)

    def test_an_empty_body_gets_the_composition(self):
        empty = MASTER.split("\\section{Los naturales}")[0] + "\\end{document}\n"
        out, why = compose.compose(empty, compose.entries(YEAR, "practica-1"), "es")
        self.assertIsNone(why)
        self.assertIn("\\DidactaUnit{analisis/induccion/principio}", out)
        self.assertLess(out.index("\\DidactaContents"),
                        out.index("\\section{Los naturales}"))

    def test_refuses_a_body_with_latex_the_composition_cannot_say(self):
        # La migración dejó apartados envueltos en `\onlyslides{...}` porque
        # `year.yaml` no sabe decir «sólo en diapositivas». Reescribir el
        # cuerpo los borraría, así que no se reescribe.
        hand = MASTER.replace(
            "\\DidactaUnit{analisis/apendice/logaritmos}",
            "\\onlyslides{\\section{Sólo proyectado}}\n"
            "\\DidactaUnit{analisis/apendice/logaritmos}",
        )
        out, why = compose.compose(hand, compose.entries(YEAR, "practica-1"), "es")
        self.assertEqual(out, hand)
        self.assertIn("onlyslides", why)

    def test_refuses_a_file_with_nowhere_to_write(self):
        out, why = compose.compose("% sólo un comentario\n", [], "es")
        self.assertEqual(out, "% sólo un comentario\n")
        self.assertIn("begin{document}", why)


class OnDiskTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.year_path = os.path.join(self.tmp, "year.yaml")
        self.master = os.path.join(self.tmp, "practica-1.tex")
        with open(self.year_path, "w", encoding="utf-8") as handle:
            handle.write(YEAR)
        with open(self.master, "w", encoding="utf-8") as handle:
            handle.write(MASTER)

    def _document(self):
        class Fake:
            id = "practica-1"
            language = "es"
        fake = Fake()
        fake.source = self.master
        return fake

    def _read(self):
        with open(self.master, encoding="utf-8") as handle:
            return handle.read()

    def test_writes_the_master_and_says_so(self):
        result = compose.compose_document(self._document(), self.year_path)
        self.assertTrue(result.changed)
        self.assertIn("\\subsection{Logaritmos}", self._read())

    def test_write_false_answers_without_touching_the_file(self):
        result = compose.compose_document(
            self._document(), self.year_path, write=False)
        self.assertTrue(result.changed)
        self.assertEqual(self._read(), MASTER)

    def test_a_master_already_at_the_day_is_not_rewritten(self):
        compose.compose_document(self._document(), self.year_path)
        again = compose.compose_document(self._document(), self.year_path)
        self.assertFalse(again.changed)
        self.assertIsNone(again.refused)


if __name__ == "__main__":
    unittest.main()
