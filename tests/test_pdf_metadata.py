"""Los PDF dicen qué son: título, autor, asignatura e idioma.

Salían con `/Title()` vacío y sin idioma, que es lo que enseña un lector de
PDF en la barra, lo que indexa un buscador y lo que necesita un lector de
pantalla para pronunciar bien. Y con la letra en Latin Modern, que es la
misma que Computer Modern en vectorial: sin ella, en una máquina sin cm-super,
el texto sale en mapas de bits.

Se comprueba compilando de verdad y leyendo el PDF: el catálogo va dentro de
flujos comprimidos, así que se descomprimen para buscar.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import preview as preview_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402
from didacta import snippets as snippets_mod  # noqa: E402

LATEX_DIR = os.path.join(ROOT, "latex")
DEMO = os.path.join(ROOT, "examples", "demo-course")


def toolchain_available():
    return all(shutil.which(tool) for tool in ("latexmk", "pdflatex"))


def pdf_text(path):
    """El PDF con sus flujos descomprimidos, para buscar en él."""
    with open(path, "rb") as handle:
        data = handle.read()
    chunks = [data]
    for match in re.finditer(rb"stream\r?\n(.*?)endstream", data, re.S):
        try:
            chunks.append(zlib.decompress(match.group(1)))
        except zlib.error:
            continue
    return b"\n".join(chunks)


@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class PdfMetadataTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.mkdtemp(prefix="didacta-pdf-meta-")
        cls.root = os.path.join(cls.work, "demo")
        shutil.copytree(DEMO, cls.root,
                        ignore=shutil.ignore_patterns(".didacta-build"))
        settings = repo_mod.Settings.load(cls.root)
        engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(cls.root, settings.build_dir),
            engine="pdflatex",
            settings=settings,
        )
        cls.result = preview_mod.build(
            engine, cls.root, "analysis/normed-spaces/induced-metric",
            "notes", "va", title="La mètrica induïda", settings=settings,
        )
        cls.pdf = pdf_text(cls.result.pdf) if cls.result.pdf else b""

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def test_it_compiles(self):
        self.assertTrue(self.result.ok,
                        [str(d) for d in self.result.errors[:3]])

    def test_the_title_is_the_document(self):
        title = re.search(rb"/Title\s*\(([^)]*)\)", self.pdf)
        self.assertIsNotNone(title)
        self.assertNotEqual(title.group(1), b"")

    def test_the_language_is_said(self):
        self.assertIn(b"/Lang(ca-ES-valencia)", self.pdf.replace(b" ", b""))

    def test_the_fonts_are_latin_modern(self):
        self.assertIn(b"LMRoman", self.pdf)
        self.assertNotIn(b"/Type3", self.pdf)

    def test_the_viewer_shows_the_title_and_not_the_file_name(self):
        self.assertIn(b"/DisplayDocTitle true", self.pdf)

    def test_without_accessible_it_is_not_tagged(self):
        self.assertNotIn(b"/StructTreeRoot", self.pdf)


def accessible_toolchain():
    return toolchain_available() and shutil.which("lualatex") is not None


@unittest.skipUnless(accessible_toolchain(), "latexmk and lualatex are required")
class AccessiblePdfTests(unittest.TestCase):
    """`build --accessible`: lo que no son diapositivas, etiquetado.

    Con el árbol de estructura, PDF/UA-2, el idioma y el texto alternativo de
    las figuras --que se añade aquí a una lección, con una imagen y un dibujo
    de TikZ, para ver que llega--. Y las diapositivas, sin etiquetar: beamer
    no lo admite todavía.
    """

    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.mkdtemp(prefix="didacta-pdf-tagged-")
        cls.root = os.path.join(cls.work, "demo")
        shutil.copytree(DEMO, cls.root,
                        ignore=shutil.ignore_patterns(".didacta-build"))
        unit = os.path.join(cls.root, "content", "analysis", "normed-spaces",
                            "induced-metric")
        png = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01"
               b"\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00"
               b"\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x03\x01\x01\x00"
               b"\xc9\xfe\x92\xef\x00\x00\x00\x00IEND\xaeB`\x82")
        with open(os.path.join(unit, "punt.png"), "wb") as handle:
            handle.write(png)
        with open(os.path.join(unit, "va.tex"), "a", encoding="utf-8") as handle:
            handle.write(
                "\n\\includegraphics[width=1cm,alt={Un punt vermell}]{punt.png}\n"
                "\\begin{tikzpicture}[alt={Una circumferència de radi u}]"
                "\\draw (0,0) circle (1);\\end{tikzpicture}\n")
        settings = repo_mod.Settings.load(cls.root)
        engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(cls.root, settings.build_dir),
            settings=settings,
            accessible=True,
        )
        cls.notes = preview_mod.build(
            engine, cls.root, "analysis/normed-spaces/induced-metric",
            "notes", "va", title="La mètrica induïda", settings=settings,
        )
        cls.slides = preview_mod.build(
            engine, cls.root, "analysis/normed-spaces/induced-metric",
            "slides", "va", title="La mètrica induïda", settings=settings,
        )
        cls.pdf = pdf_text(cls.notes.pdf) if cls.notes.pdf else b""

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def test_the_notes_compile(self):
        self.assertTrue(self.notes.ok, [str(d) for d in self.notes.errors[:3]])

    def test_the_notes_are_tagged_pdf_ua(self):
        self.assertIn(b"/StructTreeRoot", self.pdf)
        self.assertIn(b"pdfuaid:part>2<", self.pdf)
        self.assertIn(b"/Lang (ca-ES-valencia)", self.pdf)

    def test_the_figures_carry_their_alternative_text(self):
        # En UTF-16 con BOM: «Un punt» y «Una circ».
        self.assertEqual(self.pdf.count(b"/Alt <FEFF0055006E"), 2)

    def test_the_slides_are_not_tagged(self):
        self.assertTrue(self.slides.ok, [str(d) for d in self.slides.errors[:3]])
        self.assertNotIn(b"/StructTreeRoot", pdf_text(self.slides.pdf))



@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class FallbackLanguageTests(unittest.TestCase):
    """Una lección que no existe en el idioma que se compila sale en su
    original, no en el primero de una lista fija."""

    def test_the_fallback_is_the_units_own_original(self):
        work = tempfile.mkdtemp(prefix="didacta-fallback-")
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        root = os.path.join(work, "demo")
        shutil.copytree(DEMO, root,
                        ignore=shutil.ignore_patterns(".didacta-build"))
        unit = os.path.join(root, "content", "analysis", "normed-spaces",
                            "induced-metric")
        with open(os.path.join(unit, "unit.yaml"), encoding="utf-8") as handle:
            meta = handle.read()
        meta = re.sub(r"(?m)^reference:.*$", "reference: en", meta)
        if "reference:" not in meta:
            meta += "\nreference: en\n"
        with open(os.path.join(unit, "unit.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(meta)
        with open(os.path.join(unit, "en.tex"), "w", encoding="utf-8") as handle:
            handle.write("The original, in English.\n")
        for extra in ("fr.tex",):
            path = os.path.join(unit, extra)
            if os.path.exists(path):
                os.remove(path)

        settings = repo_mod.Settings.load(root)
        engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(root, settings.build_dir),
            engine="pdflatex",
            settings=settings,
        )
        result = preview_mod.build(
            engine, root, "analysis/normed-spaces/induced-metric", "notes",
            "fr", title="La métrique", settings=settings,
        )
        self.assertTrue(result.ok, [str(d) for d in result.errors[:3]])
        with open(result.log, encoding="utf-8", errors="replace") as handle:
            log = handle.read()
        self.assertIn("using `en' instead", log.replace("\n", ""))


# Cada caso compara lo escrito con lo que tendría que salir, y deja la
# respuesta en el registro. Con la anchura y con la profundidad: el punto y la
# coma son igual de anchos, pero la coma baja de la línea. El espacio antes de
# %, con un margen: el castellano lo pone con el de las fórmulas, que difiere
# del de texto en unos pocos puntos de escala.
_DECIMAL_PROBE = r"""
\newcommand{\probe}[3]{%
  \sbox0{$#2$}\sbox2{$#3$}%
  \typeout{DIDACTA-PROBE #1: \ifdim\wd0=\wd2 \ifdim\dp0=\dp2 same\else
    differs\fi\else differs\fi}}
\probe{number}{3.14}{3{,}14}
\probe{letters}{a.b}{a\mathchar"013A b}
\probe{end}{a.}{a\mathchar"013A}
\probe{delimiter}{\left. a \right|}{\left. a \right|}
\sbox0{25\%}\sbox2{25\,\char`\%}%
\dimen0=\dimexpr\wd0-\wd2\relax \ifdim\dimen0<0pt \dimen0=-\dimen0 \fi
\typeout{DIDACTA-PROBE percent: \ifdim\dimen0<0.1pt same\else differs\fi}
"""


@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class DecimalCommaTests(unittest.TestCase):
    """«3,14» y «25 %» en todos los idiomas que lo escriben así: el castellano
    y el gallego ya lo hacían con babel; los demás, no."""

    def probe(self, language):
        work = tempfile.mkdtemp(prefix="didacta-decimal-")
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        root = os.path.join(work, "demo")
        shutil.copytree(DEMO, root,
                        ignore=shutil.ignore_patterns(".didacta-build"))
        settings = repo_mod.Settings.load(root)
        engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(root, settings.build_dir),
            engine="pdflatex",
            settings=settings,
        )
        source = snippets_mod.write_preview(engine.build_dir, _DECIMAL_PROBE)
        result = engine.build(source, "notes", language,
                              document_id=snippets_mod.PREVIEW_DIR,
                              document_title="Vista previa")
        self.assertTrue(result.ok, [str(d) for d in result.errors[:3]])
        with open(result.log, encoding="utf-8", errors="replace") as handle:
            log = handle.read()
        return dict(re.findall(r"DIDACTA-PROBE (\w+): (\w+)", log))

    def test_every_language_but_english_writes_a_decimal_comma(self):
        # Con una sola coma y un solo espacio: el castellano y el gallego ya
        # lo hacían con babel, y no se les suma otro.
        expected = {
            "es": ("same", "same"), "gl": ("same", "same"),
            "va": ("same", "same"), "ca": ("same", "same"),
            "fr": ("same", "same"), "de": ("same", "same"),
            "it": ("same", "differs"), "pt": ("same", "differs"),
            "eu": ("same", "differs"), "en": ("differs", "differs"),
        }
        for language, (number, percent) in expected.items():
            with self.subTest(language=language):
                found = self.probe(language)
                self.assertEqual(found["number"], number)
                self.assertEqual(found["percent"], percent)

    def test_a_dot_between_letters_stays_a_dot(self):
        found = self.probe("va")
        self.assertEqual(found["letters"], "same")
        self.assertEqual(found["end"], "same")
        self.assertEqual(found["delimiter"], "same")

if __name__ == "__main__":
    unittest.main()


@unittest.skipUnless(accessible_toolchain(), "latexmk and lualatex are required")
class UntaggableTests(unittest.TestCase):
    """Lo que el etiquetado de LaTeX todavía no admite --aquí, una lista con
    `label=(\\alph*)` de enumitem-- sale sin etiquetar y lo dice, en lugar de
    no salir: encender los PDF accesibles no puede dejar a nadie sin sus
    apuntes."""

    def test_sale_sin_etiquetar_y_lo_dice(self):
        work = tempfile.mkdtemp(prefix="didacta-untaggable-")
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        root = os.path.join(work, "demo")
        shutil.copytree(DEMO, root,
                        ignore=shutil.ignore_patterns(".didacta-build"))
        unit = os.path.join(root, "content", "analysis", "normed-spaces",
                            "induced-metric")
        with open(os.path.join(unit, "va.tex"), "a", encoding="utf-8") as handle:
            handle.write("\n\\begin{enumerate}[label=(\\alph*)]\n"
                         "\\item u\n\\item dos\n\\end{enumerate}\n")
        settings = repo_mod.Settings.load(root)
        engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(root, settings.build_dir),
            settings=settings,
            accessible=True,
        )
        result = preview_mod.build(
            engine, root, "analysis/normed-spaces/induced-metric", "notes",
            "va", title="La mètrica induïda", settings=settings,
        )
        self.assertTrue(result.ok, [str(d) for d in result.errors[:3]])
        self.assertFalse(result.tagged)
        self.assertNotIn(b"/StructTreeRoot", pdf_text(result.pdf))
        self.assertEqual(result.diagnostics[0].code, "untagged")
        self.assertIn("sin etiquetar", result.diagnostics[0].message)
