"""Las fuentes que el material cita.

Esto existe por un fallo concreto: el análisis bibliográfico de un tema --que
es material de curso como cualquier otro, y dice dónde está demostrado cada
resultado-- no compilaba. Escribía `\\cites[Theorem 1.1.1]{Abbott}[Chapter
3]{Tao}`, que es biblatex, y Didacta no cargaba biblatex: el error era
«Undefined control sequence» en la primera línea de la unidad, que no dice
nada de lo que falta, y aparecía compilando.

Lo que se fija aquí es dónde vive el `.bib`, cuándo se carga y qué avisa
`check` antes de que nadie compile.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402

CLI_PATH = os.path.join(ROOT, "cli", "didacta")
LATEX_DIR = os.path.join(ROOT, "latex")


def load_cli():
    spec = importlib.util.spec_from_loader(
        "didacta_cli",
        importlib.machinery.SourceFileLoader("didacta_cli", CLI_PATH),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Repository(unittest.TestCase):
    """Un repositorio de mentira, con una unidad que cita."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-bib-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.settings_text("languages: [es]\ndefault_language: es\n")

    def settings_text(self, text):
        with open(os.path.join(self.root, "didacta.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(text)
        self.settings = repo_mod.Settings.load(self.root)
        return self.settings

    def bib(self, text, name="shared/bibliography.bib"):
        path = os.path.join(self.root, name.replace("/", os.sep))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def unit(self, relpath, tex):
        directory = os.path.join(self.root, "content", relpath)
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "es.tex"), "w", encoding="utf-8") as h:
            h.write(tex)
        with open(os.path.join(directory, "unit.yaml"), "w", encoding="utf-8") as h:
            h.write("id: %s\nkind: theory\ntitle:\n  es: X\n"
                    "languages:\n  es: {status: draft}\n"
                    % relpath.replace("/", "."))


class WhereItLivesTests(Repository):
    """Dónde está el .bib, que es lo único que hay que decidir."""

    def test_the_convention_needs_no_configuration(self):
        # `shared/` es donde el modelo pone lo que no es de ninguna unidad, y
        # el mismo libro lo citan el tema 1 y el tema 6.
        self.assertEqual(self.settings.bibliography, "shared/bibliography.bib")

    def test_without_the_file_there_is_no_bibliography(self):
        # Y eso no es un error: casi ningún tema cita.
        self.assertIsNone(self.settings.bibliography_path)

    def test_with_the_file_there_is(self):
        self.bib("@book{Tao, title = {Analysis I}}\n")
        settings = repo_mod.Settings.load(self.root)
        self.assertIsNotNone(settings.bibliography_path)

    def test_another_name_is_declared_once(self):
        self.bib("@book{Tao, title = {Analysis I}}\n", "shared/analisis.bib")
        settings = self.settings_text(
            "languages: [es]\nbibliography: shared/analisis.bib\n"
        )
        self.assertEqual(settings.bibliography, "shared/analisis.bib")
        self.assertIsNotNone(settings.bibliography_path)

    def test_outside_the_repository_is_refused(self):
        # Una ruta que se sale del repositorio compila aquí y no en la máquina
        # de al lado, que es la peor clase de fallo.
        with self.assertRaises(repo_mod.RepoError):
            self.settings_text("languages: [es]\nbibliography: ../otro.bib\n")


class ReadingCitationsTests(unittest.TestCase):
    """Qué claves cita un `.tex`."""

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def test_a_plain_citation(self):
        self.assertEqual(
            self.cli.cited_keys(r"se encuentra en \cite[Sección 2.1]{Tao}."),
            ["Tao"],
        )

    def test_a_multiple_citation_gives_every_key(self):
        # `\cites` toma una lista de longitud libre, y es justo la que no
        # compilaba: leerla entera es lo que permite avisar de la que falta.
        self.assertEqual(
            self.cli.cited_keys(
                r"en \cites[Theorem 1.1.1]{Abbott}[páginas 25-26]{Spivak}"
                r"[Proposition 4.4.4]{Tao} mientras"
            ),
            ["Abbott", "Spivak", "Tao"],
        )

    def test_several_keys_in_one_group(self):
        self.assertEqual(
            self.cli.cited_keys(r"\cite{Abbott, Tao}"), ["Abbott", "Tao"]
        )

    def test_prose_without_citations_has_none(self):
        self.assertEqual(self.cli.cited_keys("Un texto cualquiera."), [])


class CheckTests(Repository):
    """Lo que `didacta check` dice antes de que nadie compile.

    El sitio donde tiene que aparecer: una clave sin entrada es una cita que
    en el PDF sale como `[?]` delante de treinta alumnos, y compilando el
    error no dice qué falta.
    """

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def warnings(self):
        units, _ = repo_mod.scan_units(self.root, self.settings)
        return self.cli.bibliography_warnings(self.root, self.settings, units)

    def test_citing_without_a_bibliography_is_reported(self):
        self.unit("a/b/c", r"Como en \cite{Tao}.")
        messages = self.warnings()
        self.assertEqual(len(messages), 1)
        self.assertIn("Tao", messages[0])
        self.assertIn("shared/bibliography.bib", messages[0])

    def test_a_key_that_is_not_in_the_bib_is_reported(self):
        self.bib("@book{Tao, title = {Analysis I}}\n")
        self.settings_text("languages: [es]\n")
        self.unit("a/b/c", r"Como en \cites[1]{Tao}[2]{Abbott}.")
        messages = self.warnings()
        self.assertEqual(len(messages), 1)
        self.assertIn("Abbott", messages[0])
        self.assertNotIn("`Tao`", messages[0])

    def test_everything_cited_is_quiet(self):
        self.bib("@book{Tao,\n  title = {Analysis I},\n}\n"
                 "@article{Weiss, title = {The real numbers}}\n")
        self.settings_text("languages: [es]\n")
        self.unit("a/b/c", r"Como en \cite{Tao} y \cite{Weiss}.")
        self.assertEqual(self.warnings(), [])

    def test_a_unit_that_does_not_cite_is_quiet(self):
        self.unit("a/b/c", "Prosa sin citas.")
        self.assertEqual(self.warnings(), [])


class BuildTests(unittest.TestCase):
    """Cómo llega el .bib a LaTeX.

    Relativo a la raíz, como las unidades: el documento no contiene ninguna
    ruta, y por eso el repositorio se puede clonar en otro sitio.
    """

    def setUp(self):
        self.build_dir = tempfile.mkdtemp(prefix="didacta-bib-build-")
        self.addCleanup(shutil.rmtree, self.build_dir, ignore_errors=True)
        self.engine = build_mod.Engine(LATEX_DIR, self.build_dir)
        self.profile = profiles_mod.load(LATEX_DIR)["notes"]

    def command(self, bibliography=None):
        return " ".join(self.engine._command(
            "doc.tex", "doc", self.build_dir, self.profile, "es",
            "../../", None, bibliography,
        ))

    def test_it_travels_as_a_definition(self):
        self.assertIn(
            r"\def\DidactaBibliographyFile{shared/bibliography.bib}",
            self.command("shared/bibliography.bib"),
        )

    def test_without_one_nothing_is_passed(self):
        # Un documento que no cita no tiene por qué arrastrar biblatex ni la
        # pasada de biber que viene con él.
        self.assertNotIn("DidactaBibliographyFile", self.command())


if __name__ == "__main__":
    unittest.main()
