"""Tests for compiling one unit on its own.

The question this feature answers is the one asked while editing: «¿cómo queda
esto?» -- this unit, now, as a slide and as prose. So what the tests have to
establish is that the preview goes through the *real* preamble (a preview of a
simplified document is a preview of something else), that the generated
wrapper never lands in the repository, and that it actually compiles.
"""

import os
import re
import shutil
import sys
import time
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import preview as preview_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402

LATEX_DIR = os.path.join(ROOT, "latex")
DEMO = os.path.join(ROOT, "examples", "demo-course")


def toolchain_available():
    return all(shutil.which(tool) for tool in ("latexmk", "pdflatex"))


def pdf_letters(path):
    """Letters from a PDF's content streams. Crude, dependency-free."""
    with open(path, "rb") as handle:
        data = handle.read()
    text = b""
    for match in re.finditer(rb"stream\r?\n(.*?)endstream", data, re.S):
        try:
            text += zlib.decompress(match.group(1))
        except Exception:
            continue
    return re.sub(rb"[^A-Za-z]", b"", text).decode("latin-1")


class WrapperTests(unittest.TestCase):
    def test_the_wrapper_is_a_real_didacta_document(self):
        """Through `didacta-bootstrap`, like anything else.

        This is the point of generating a wrapper instead of writing a
        simplified preamble: what comes out is what the unit will look like
        inside a tema. A preview built by different means previews something
        that does not exist.
        """
        text = preview_mod.wrapper_text("analysis/normed/definition", "Normas")
        self.assertIn(r"\input{didacta-bootstrap}", text)
        self.assertIn(r"\usepackage{didacta}", text)
        self.assertIn(r"\DidactaUnit{analysis/normed/definition}", text)
        self.assertIn(r"\DidactaDocument{Normas}", text)
        # No documentclass: the class comes from the profile, as always.
        self.assertNotIn(r"\documentclass", text)

    def test_a_problem_is_included_from_the_problems_tree(self):
        """The macro follows the area, not the kind.

        `\\DidactaUnit` resolves against `content/` and `\\DidactaProblem`
        against `problems/`. Emitting the first for everything made the
        preview of every exercise in the library come out as a page with
        `[ missing: ... ]` on it -- and quietly, because an unresolved
        reference is a warning and the build still reported `ok`.
        """
        problem = preview_mod.wrapper_text(
            "analysis/normed/axioms", "Axiomas", area="problems")
        self.assertIn(r"\DidactaProblem{analysis/normed/axioms}", problem)
        self.assertNotIn(r"\DidactaUnit", problem)

        theory = preview_mod.wrapper_text(
            "analysis/normed/definition", "Definición", area="content")
        self.assertIn(r"\DidactaUnit{analysis/normed/definition}", theory)
        self.assertNotIn(r"\DidactaProblem", theory)

        # Sin decir nada, contenido: es donde vive la mayoría.
        self.assertIn(r"\DidactaUnit", preview_mod.wrapper_text("a/b/c", "Uno"))

    def test_the_area_decides_and_not_the_declared_kind(self):
        # Una unidad puede vivir en `problems/` y declarar otro kind; lo que
        # LaTeX tiene que resolver es el fichero, que está donde está.
        units, errors = repo_mod.scan_units(DEMO, repo_mod.Settings.load(DEMO))
        self.assertFalse(errors, errors)
        areas = {u.area for u in units.values()}
        self.assertEqual(areas, {"content", "problems"})
        for unit in units.values():
            self.assertEqual(unit.area, unit.relpath.split("/")[0])

    def test_no_title_page_for_one_unit(self):
        # A title page in front of a single definition is a page nobody wants
        # to look at.
        text = preview_mod.wrapper_text("a/b/c", "Uno")
        self.assertNotIn(r"\DidactaTitlePage", text)
        self.assertNotIn(r"\DidactaContents", text)

    def test_it_says_it_is_generated(self):
        # It lands in a build directory somebody will eventually open.
        text = preview_mod.wrapper_text("a/b/c", "Uno")
        self.assertIn("Generado", text)
        self.assertIn("no se versiona", text)

    def test_the_wrapper_goes_in_the_build_directory(self):
        """Never in the repository.

        The preamble is needed to compile and has no business being visible in
        the library -- which was the requirement, in those words.
        """
        root = tempfile.mkdtemp(prefix="didacta-preview-")
        try:
            build_dir = os.path.join(root, ".didacta-build")
            source = preview_mod.write_wrapper(
                root, build_dir, "analysis/normed/definition", "Normas"
            )
            self.assertTrue(source.startswith(build_dir), source)
            self.assertTrue(os.path.isfile(source))
            # And nothing was written next to the content.
            self.assertEqual(
                sorted(os.listdir(root)), [".didacta-build"]
            )
        finally:
            shutil.rmtree(root)

    def test_a_reference_with_slashes_becomes_one_directory(self):
        self.assertEqual(
            preview_mod.slug("analysis/normed/definition".replace("/", "-")),
            "analysis-normed-definition",
        )
        # And anything hostile to a filesystem is flattened.
        self.assertEqual(preview_mod.slug("a b/c:d"), "a-b-c-d")
        self.assertEqual(preview_mod.slug(""), "unit")


class ProfileChoiceTests(unittest.TestCase):
    def setUp(self):
        self.profiles = profiles_mod.load(LATEX_DIR)

    def test_theory_offers_slides_first_and_book_among_the_prose(self):
        # «tanto cómo queda en la versión del modo de presentación como cómo
        # queda en la versión de modo de libro»: both, and slides first
        # because it is the one people look at.
        offered = [p.id for p in preview_mod.profiles_for("theory", self.profiles)]
        self.assertEqual(offered[0], "slides")
        self.assertIn("book", offered)
        self.assertIn("notes", offered)
        # `book` before the variants nobody asked for.
        self.assertLess(offered.index("book"), offered.index("notes-teacher"))
        # And not offered as an exam paper.
        self.assertNotIn("exam", offered)

    def test_a_problem_is_offered_as_a_problem_sheet(self):
        offered = [p.id for p in preview_mod.profiles_for("problem", self.profiles)]
        self.assertEqual(offered[0], "problems")
        self.assertIn("problems-teacher", offered)
        self.assertNotIn("slides", offered)

    def test_the_three_levels_come_out_in_the_order_they_are_decided(self):
        """Statements, then results, then the teacher's copy.

        The menu is read as «how much do I give away», so it has to be
        ordered by that and not by whatever the ids sort as.
        """
        for kind in ("problem", "practical"):
            offered = preview_mod.profiles_for(kind, self.profiles)
            levels = [p.reveals for p in offered
                      if p.family in ("problems", "handout")]
            self.assertEqual(levels, ["statements", "answers", "teacher"], kind)

    def test_a_handout_leads_with_handout(self):
        offered = [p.id for p in preview_mod.profiles_for("handout", self.profiles)]
        self.assertEqual(offered[0], "handout")

    def test_an_unknown_kind_still_offers_something(self):
        """A kind this map has not heard of must not produce an empty menu.

        `UNIT_KINDS` grows; a menu that silently empties when it does is worse
        than one that offers slides and prose.
        """
        offered = preview_mod.profiles_for("notation", self.profiles)
        self.assertTrue(offered)
        self.assertEqual(offered[0].id, "slides")

    def test_the_unit_map_is_keyed_by_unit_kinds(self):
        """Not by document kinds, which is a different vocabulary.

        `problem` is a unit kind and `problems` is a document kind. One map
        serving both would fall through to the default for half the values.
        """
        for kind in preview_mod.UNIT_FAMILIES:
            self.assertIn(kind, repo_mod.UNIT_KINDS, kind)


class StatusTests(unittest.TestCase):
    """Lo que ya está compilado, y si sigue valiendo.

    Es la pregunta que evita compilar de nuevo para mirar algo que ya está
    hecho, y la que avisa de lo contrario: que lo que está hecho ya no
    corresponde al fichero.
    """

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-status-")
        shutil.copytree(DEMO, os.path.join(self.root, "repo"))
        self.repo = os.path.join(self.root, "repo")
        self.profiles = profiles_mod.load(LATEX_DIR)
        self.engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(self.root, "build"),
        )
        settings = repo_mod.Settings.load(self.repo)
        units, _ = repo_mod.scan_units(self.repo, settings)
        self.unit = next(
            u for u in units.values()
            if u.reference_path == "analysis/normed-spaces/definition"
        )

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def report(self, profiles=("slides",), languages=("es",)):
        return preview_mod.status(
            self.engine,
            self.unit,
            [self.profiles[p] for p in profiles],
            list(languages),
            "Definición",
        )

    def fake_pdf(self, profile="slides", language="es", when=None):
        """Escribe un PDF donde el motor lo pondría, sin compilar."""
        path = preview_mod.expected_pdf(
            self.engine,
            self.unit.reference_path,
            self.profiles[profile],
            language,
            "Definición",
        )
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(b"%PDF-1.5\n")
        if when is not None:
            os.utime(path, (when, when))
        return path

    def test_a_record_per_profile_and_language(self):
        # Aunque no exista: una interfaz que solo listara lo que hay no
        # podría distinguir «sin compilar» de «no se ofrece».
        report = self.report(profiles=("slides", "book"), languages=("es", "va"))
        self.assertEqual(len(report["outputs"]), 4)
        self.assertEqual(
            {(r["profile"], r["language"]) for r in report["outputs"]},
            {("slides", "es"), ("slides", "va"),
             ("book", "es"), ("book", "va")},
        )
        for record in report["outputs"]:
            self.assertFalse(record["exists"])
            self.assertFalse(record["stale"])
            self.assertIsNone(record["mtime"])

    def test_the_path_is_the_one_the_engine_would_write(self):
        """Y no una que la interfaz adivine.

        El nombre del fichero sale de las reglas del perfil --el título
        primero, los dos puntos fuera-- y reimplementarlas en Dart sería una
        segunda copia que se desincroniza.
        """
        expected = self.fake_pdf()
        record = self.report()["outputs"][0]
        self.assertEqual(record["pdf"], expected)
        self.assertTrue(record["exists"])
        self.assertFalse(record["stale"])

    def test_a_source_newer_than_the_pdf_is_stale(self):
        # El caso que importa: se compiló, se editó, y lo compilado ya no es
        # lo que dice el fichero.
        self.fake_pdf(when=time.time() - 600)
        tex = os.path.join(self.unit.directory, "es.tex")
        os.utime(tex, None)
        record = self.report()["outputs"][0]
        self.assertTrue(record["exists"])
        self.assertTrue(record["stale"])
        self.assertEqual(report_source(self.report()), "es.tex")

    def test_a_pdf_that_does_not_exist_is_missing_and_not_stale(self):
        # Dos cosas distintas, y la interfaz dice cada una de otra forma.
        record = self.report()["outputs"][0]
        self.assertFalse(record["exists"])
        self.assertFalse(record["stale"])

    def test_any_file_of_the_unit_counts_as_a_source(self):
        """No solo el `.tex` del idioma que se compila.

        Una vista previa en `en` sin inglés se compila del `es.tex`,
        `unit.yaml` cambia el título que va en la cabecera, y una figura es
        tan origen como el texto.
        """
        self.fake_pdf(when=time.time() - 600)
        figure = os.path.join(self.unit.directory, "figura.pdf")
        with open(figure, "wb") as handle:
            handle.write(b"x")
        self.assertTrue(self.report()["outputs"][0]["stale"])
        self.assertEqual(report_source(self.report()), "figura.pdf")

    def test_a_pdf_newer_than_everything_is_current(self):
        self.fake_pdf(when=time.time() + 60)
        self.assertFalse(self.report()["outputs"][0]["stale"])

    def test_the_report_names_what_was_touched_last(self):
        # «Está desactualizado» sin decir por qué obliga a mirar el
        # directorio a mano.
        self.fake_pdf()
        report = self.report()
        self.assertIn(report["sourceNewest"], os.listdir(self.unit.directory))
        self.assertIsNotNone(report["sourceMtime"])


def report_source(report):
    return report["sourceNewest"]


@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class CompileTests(unittest.TestCase):
    """One unit, actually compiled, in the two profiles that were asked for."""

    @classmethod
    def setUpClass(cls):
        cls.root = tempfile.mkdtemp(prefix="didacta-preview-build-")
        shutil.copytree(DEMO, os.path.join(cls.root, "repo"))
        cls.repo = os.path.join(cls.root, "repo")
        cls.profiles = profiles_mod.load(LATEX_DIR)
        cls.engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(cls.root, "build"),
        )

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def build(self, profile):
        return preview_mod.build(
            self.engine,
            self.repo,
            "analysis/normed-spaces/definition",
            self.profiles[profile],
            "es",
            title="Definición de espacio normado",
            area="content",
        )

    def test_one_unit_compiles_as_slides(self):
        result = self.build("slides")
        self.assertTrue(result.ok, [str(d) for d in result.errors])
        self.assertTrue(os.path.isfile(result.pdf))
        self.assertGreaterEqual(result.pages, 1)
        # The unit's own content, not a title page.
        self.assertIn("normado", pdf_letters(result.pdf).lower())

    def test_the_same_unit_compiles_as_a_book(self):
        result = self.build("book")
        self.assertTrue(result.ok, [str(d) for d in result.errors])
        self.assertTrue(os.path.isfile(result.pdf))
        self.assertIn("normado", pdf_letters(result.pdf).lower())

    def test_the_two_outputs_do_not_overwrite_each_other(self):
        slides = self.build("slides")
        book = self.build("book")
        self.assertNotEqual(slides.pdf, book.pdf)
        self.assertTrue(os.path.isfile(slides.pdf))
        self.assertTrue(os.path.isfile(book.pdf))

    def test_nothing_was_written_into_the_repository(self):
        """The whole reason the wrapper is generated elsewhere."""
        before = set()
        for directory, _, names in os.walk(self.repo):
            for name in names:
                before.add(os.path.join(directory, name))
        self.build("notes")
        after = set()
        for directory, _, names in os.walk(self.repo):
            for name in names:
                after.add(os.path.join(directory, name))
        self.assertEqual(before, after)

    def test_a_problem_preview_carries_the_problem(self):
        """El fallo que esto viene a impedir, compilado de verdad.

        La vista previa de cualquier ejercicio de la biblioteca salía como una
        página con `[ missing: ... ]`, y el motor decía `ok`: una referencia
        que LaTeX no resuelve es un aviso, no un error. Así que la única
        comprobación que sirve es mirar dentro del PDF.
        """
        result = preview_mod.build(
            self.engine,
            self.repo,
            "analysis/normed-spaces/norm-axioms",
            self.profiles["problems"],
            "es",
            title="Axiomas de norma",
            area="problems",
        )
        self.assertTrue(result.ok, [str(d) for d in result.errors])
        text = pdf_letters(result.pdf)
        self.assertNotIn("missing", text.lower())
        # Una palabra del enunciado, para que la prueba no pase con una página
        # en blanco.
        self.assertIn("normas", text.lower())

    def test_a_missing_unit_is_marked_in_the_pdf_rather_than_failing(self):
        """The build succeeds, and says what is missing where it is missing.

        Deliberate, and `didacta.sty` explains why in the code: "silently
        skipping is how you end up standing in front of a class with a hole in
        the deck". So a preview of a reference that does not resolve is not an
        error -- it is a PDF with `[ missing: ... ]` in it and a warning in the
        log, which is strictly more useful than a build that refuses.
        """
        result = preview_mod.build(
            self.engine,
            self.repo,
            "analysis/no/such-unit",
            self.profiles["notes"],
            "es",
            title="No existe",
            area="content",
        )
        self.assertTrue(result.ok, [str(d) for d in result.errors])
        self.assertIn("missing", pdf_letters(result.pdf).lower())
        self.assertTrue(
            any("no/such-unit" in str(d) or "such" in str(d)
                for d in result.warnings),
            [str(d) for d in result.warnings],
        )


if __name__ == "__main__":
    unittest.main()


class BuiltTests(unittest.TestCase):
    """Todo lo compilado, de una vez.

    La biblioteca lista dos mil unidades y necesita saber cuáles se pueden
    ojear ya. Preguntarlo unidad por unidad serían dos mil procesos, así que
    esto contesta por todas; lo que hay que demostrar es que contesta lo
    mismo que preguntar de una en una, y que no se inventa lo que no está.
    """

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-built-")
        shutil.copytree(DEMO, os.path.join(self.root, "repo"))
        self.repo = os.path.join(self.root, "repo")
        self.profiles = profiles_mod.load(LATEX_DIR)
        self.engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(self.root, "build"),
        )
        settings = repo_mod.Settings.load(self.repo)
        self.units, _ = repo_mod.scan_units(self.repo, settings)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def unit(self, reference):
        return next(u for u in self.units.values()
                    if u.reference_path == reference)

    def fake_pdf(self, unit, profile="slides", language="es", when=None):
        path = preview_mod.expected_pdf(
            self.engine, unit.reference_path, self.profiles[profile],
            language, unit.titles.get(unit.reference) or unit.id)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(b"%PDF-1.5\n")
        if when is not None:
            os.utime(path, (when, when))
        return path

    def report(self, languages=("es", "va")):
        return preview_mod.built(
            self.engine, self.units.values(), self.profiles, list(languages),
            lambda u: u.titles.get(u.reference) or u.id)

    def test_nothing_compiled_is_an_empty_answer(self):
        # Y no una lista de dos mil «no». La biblioteca pregunta «cuáles
        # puedo ojear», no «cuáles no».
        self.assertEqual(self.report()["units"], [])

    def test_a_compiled_unit_appears_with_its_pdf(self):
        unit = self.unit("analysis/normed-spaces/definition")
        path = self.fake_pdf(unit)

        report = self.report()
        self.assertEqual(len(report["units"]), 1)
        record = report["units"][0]
        self.assertEqual(record["unit"], unit.relpath)
        self.assertEqual([o["pdf"] for o in record["outputs"]], [path])
        self.assertEqual(record["outputs"][0]["profile"], "slides")

    def test_only_what_exists(self):
        # Lo contrario que `status`, y a propósito: ahí la pregunta es «qué
        # se ofrece», aquí «qué hay».
        unit = self.unit("analysis/normed-spaces/definition")
        self.fake_pdf(unit, profile="slides", language="es")
        record = self.report()["units"][0]
        self.assertTrue(all(o["exists"] for o in record["outputs"]))
        self.assertEqual(len(record["outputs"]), 1)

    def test_it_says_which_ones_went_stale(self):
        # Es lo que evita enseñar como previo un PDF que ya no corresponde al
        # fichero.
        unit = self.unit("analysis/normed-spaces/definition")
        self.fake_pdf(unit, when=1)
        record = self.report()["units"][0]
        self.assertTrue(record["outputs"][0]["stale"])

    def test_two_units_are_two_records(self):
        first = self.unit("analysis/normed-spaces/definition")
        second = next(u for u in self.units.values()
                      if u.reference_path != first.reference_path)
        self.fake_pdf(first)
        self.fake_pdf(second)
        report = self.report()
        self.assertEqual(
            {r["unit"] for r in report["units"]},
            {first.relpath, second.relpath})

    def test_it_agrees_with_asking_one_by_one(self):
        # La propiedad que importa: preguntar por todas tiene que dar lo
        # mismo que preguntar por una, o la biblioteca enseñaría una cosa y
        # la pantalla de la unidad otra.
        unit = self.unit("analysis/normed-spaces/definition")
        self.fake_pdf(unit, profile="slides", language="es")

        one = preview_mod.status(
            self.engine, unit,
            preview_mod.profiles_for(unit.kind, self.profiles),
            ["es", "va"], unit.titles.get(unit.reference) or unit.id)
        many = self.report()["units"][0]

        self.assertEqual(
            [o for o in one["outputs"] if o["exists"]], many["outputs"])

