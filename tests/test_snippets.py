"""Snippets: lo que la barra del editor envuelve, declarado por el repositorio.

Lo que estas pruebas fijan es lo que hace que un snippet no pueda romper nada:

* un repositorio sin `snippets.yaml` indexa y compila exactamente como antes,
  y el índice lo dice con un None que la aplicación lee como «los de serie»;
* una entrada con solo el id es una referencia a uno de Didacta, y el motor
  la deja pasar tal cual;
* la definición de un snippet llega a **todo** lo que se compila en su
  repositorio, y se compila antes del preámbulo de la plantilla;
* el LaTeX de varias líneas se lee igual con PyYAML que sin él: dentro de un
  bloque `|` una línea que empieza por `#` es LaTeX, no un comentario.

La tercera se comprueba compilando de verdad: una definición que no se lee
produce un «Environment undefined», y eso no lo caza ningún test de
estructura.
"""

from __future__ import annotations

import glob
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import index as index_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402
from didacta import snippets as snippets_mod  # noqa: E402
from didacta import yamlio  # noqa: E402

LATEX_DIR = os.path.join(ROOT, "latex")
DEMO = os.path.join(ROOT, "examples", "demo-course")
CLI_PATH = os.path.join(ROOT, "cli", "didacta")

SNIPPETS = """\
# Los snippets de prueba.
snippets:
  - id: resumen
    label: Resumen
    group: Teoría
    environment: resumen
    environment_aliases: [summary]
    arguments: '[Título]'
    block: true
    definition: |
      \\DidactaNewTheorem{resumen}{Resumen}{didactaThm}
      % un comentario # con almohadilla

      \\newcommand{\\destaca}[1]{\\textbf{#1}}
    sample: |
      Lo esencial, \\destaca{en una caja}.

      # esto es LaTeX, no un comentario de YAML
  - id: theorem
  - id: en-rojo
    label: En rojo
    command: '\\textcolor'
    arguments: '{red}'
"""


def toolchain_available():
    return all(shutil.which(tool) for tool in ("latexmk", "pdflatex"))


def load_cli():
    loader = importlib.machinery.SourceFileLoader("didacta_cli_snippets",
                                                  CLI_PATH)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class LiteralBlockTests(unittest.TestCase):
    """El lector de reserva entiende `|`, y lee lo mismo que PyYAML."""

    def test_the_subset_reader_reads_what_pyyaml_reads(self):
        data = yamlio._loads_subset(SNIPPETS)
        first = data["snippets"][0]
        self.assertEqual(
            first["definition"],
            "\\DidactaNewTheorem{resumen}{Resumen}{didactaThm}\n"
            "% un comentario # con almohadilla\n\n"
            "\\newcommand{\\destaca}[1]{\\textbf{#1}}\n",
        )
        self.assertIn("# esto es LaTeX", first["sample"])
        self.assertEqual(first["label"], "Resumen")
        self.assertEqual(data["snippets"][1], {"id": "theorem"})
        self.assertEqual(data["snippets"][2]["arguments"], "{red}")
        if yamlio._pyyaml is not None:
            self.assertEqual(data, yamlio._pyyaml.safe_load(SNIPPETS))

    def test_chomping(self):
        text = "a: |-\n  uno\n\nb: |+\n  dos\n\nc: |\n  tres\n"
        data = yamlio._loads_subset(text)
        self.assertEqual(data, {"a": "uno", "b": "dos\n\n", "c": "tres\n"})

    def test_a_block_keeps_its_inner_indentation(self):
        text = "x: |\n  \\begin{a}\n    dentro\n  \\end{a}\ny: 2\n"
        data = yamlio._loads_subset(text)
        self.assertEqual(data["x"], "\\begin{a}\n  dentro\n\\end{a}\n")
        self.assertEqual(data["y"], 2)

    def test_an_empty_block_is_an_empty_string(self):
        self.assertEqual(yamlio._loads_subset("x: |\ny: 1\n"),
                         {"x": "", "y": 1})


class LoadTests(unittest.TestCase):

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-snippets-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

    def write(self, text):
        with open(os.path.join(self.root, snippets_mod.SNIPPETS_META), "w",
                  encoding="utf-8") as handle:
            handle.write(text)

    def test_without_a_file_there_is_nothing_declared(self):
        # None, no una lista vacía: sin fichero se ofrecen los de serie.
        self.assertIsNone(snippets_mod.load(self.root))

    def test_an_empty_file_declares_an_empty_list(self):
        self.write("snippets: []\n")
        self.assertEqual(snippets_mod.load(self.root), [])

    def test_entries_keep_only_what_they_say(self):
        self.write(SNIPPETS)
        found = snippets_mod.load(self.root)
        self.assertEqual([each.id for each in found],
                         ["resumen", "theorem", "en-rojo"])
        self.assertEqual(found[1].as_dict(), {"id": "theorem"})
        resumen = found[0].as_dict()
        self.assertEqual(resumen["environmentAliases"], ["summary"])
        self.assertTrue(resumen["block"])
        # El salto que deja `|` al final no se guarda.
        self.assertFalse(resumen["definition"].endswith("\n"))
        # La barra de delante de una orden sobra, y se quita.
        self.assertEqual(found[2].command, "textcolor")

    def test_a_duplicate_id_is_an_error(self):
        self.write("snippets:\n  - id: a\n  - id: a\n")
        with self.assertRaises(snippets_mod.SnippetError):
            snippets_mod.load(self.root)

    def test_an_invalid_environment_name_is_an_error(self):
        self.write("snippets:\n  - id: a\n    environment: 'no vale'\n")
        with self.assertRaises(snippets_mod.SnippetError):
            snippets_mod.load(self.root)

    def test_definitions_are_gathered_in_order(self):
        self.write(SNIPPETS)
        path = os.path.join(self.root, "build", snippets_mod.DEFINITIONS)
        written = snippets_mod.write_definitions(path,
                                                 snippets_mod.load(self.root))
        self.assertEqual(written, path)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn("%% --- resumen", text)
        self.assertIn("\\newcommand{\\destaca}", text)
        self.assertNotIn("theorem", text)

    def test_no_definitions_no_file(self):
        self.write("snippets:\n  - id: theorem\n")
        path = os.path.join(self.root, "build", snippets_mod.DEFINITIONS)
        self.assertIsNone(snippets_mod.write_definitions(
            path, snippets_mod.load(self.root)))
        self.assertFalse(os.path.exists(path))


class IndexTests(unittest.TestCase):
    """Lo que la aplicación lee: el manifiesto."""

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-snippets-index-")
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)
        self.root = os.path.join(self.work, "demo")
        shutil.copytree(DEMO, self.root,
                        ignore=shutil.ignore_patterns(".didacta-build"))

    def manifest(self):
        return index_mod.build(self.root)[index_mod.MANIFEST]

    def test_without_a_file_the_manifest_says_none(self):
        self.assertIsNone(self.manifest()["snippets"])

    def test_the_manifest_lists_the_declared_snippets(self):
        with open(os.path.join(self.root, "snippets.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(SNIPPETS)
        snippets = self.manifest()["snippets"]
        self.assertEqual([each["id"] for each in snippets],
                         ["resumen", "theorem", "en-rojo"])
        self.assertIn("definition", snippets[0])
        json.dumps(snippets)

    def test_a_broken_file_is_an_error_and_not_an_empty_bar(self):
        with open(os.path.join(self.root, "snippets.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("snippets:\n  - label: sin id\n")
        manifest = self.manifest()
        self.assertIsNone(manifest["snippets"])
        self.assertTrue(any("snippets.yaml" in each
                            for each in manifest["errors"]))

    def test_editing_the_file_makes_the_index_stale(self):
        settings = repo_mod.Settings.load(self.root)
        before = index_mod.survey(self.root, settings)["newest"] or 0
        path = os.path.join(self.root, "snippets.yaml")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("snippets: []\n")
        os.utime(path, (before + 10, before + 10))
        self.assertGreater(index_mod.survey(self.root, settings)["newest"],
                           before)


class EngineTests(unittest.TestCase):
    """El motor pasa las definiciones a LaTeX, y solo si las hay."""

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-snippets-engine-")
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)
        self.root = os.path.join(self.work, "demo")
        shutil.copytree(DEMO, self.root,
                        ignore=shutil.ignore_patterns(".didacta-build"))

    def engine(self, **extra):
        settings = repo_mod.Settings.load(self.root)
        return build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(self.root, settings.build_dir),
            settings=settings,
            **extra
        )

    def pretex(self, engine):
        profile = engine.profiles["notes"]
        return engine._pretex(profile, "es", ".")

    def test_without_snippets_nothing_is_passed(self):
        self.assertNotIn("DidactaSnippets", self.pretex(self.engine()))

    def test_the_repository_definitions_are_passed(self):
        with open(os.path.join(self.root, "snippets.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(SNIPPETS)
        self.assertIn("\\def\\DidactaSnippets{", self.pretex(self.engine()))

    def test_an_explicit_list_wins_over_the_repository(self):
        with open(os.path.join(self.root, "snippets.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(SNIPPETS)
        engine = self.engine(snippets=[])
        self.assertNotIn("DidactaSnippets", self.pretex(engine))

    def test_a_broken_file_does_not_stop_the_engine(self):
        with open(os.path.join(self.root, "snippets.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("snippets:\n  - id: a\n  - id: a\n")
        engine = self.engine()
        self.assertEqual(engine.snippets, [])
        self.assertTrue(engine.snippet_errors)

    def test_the_preview_goes_inside_a_frame_on_slides(self):
        text = snippets_mod.preview_text("hola", slides=True)
        self.assertIn("\\begin{frame}\nhola\n\\end{frame}", text)
        self.assertIn("\\begin{frame}[fragile]",
                      snippets_mod.preview_text("\\verb|x|", slides=True))
        framed = "\\begin{frame}{T}\nx\n\\end{frame}"
        self.assertEqual(
            snippets_mod.preview_text(framed, slides=True).count(
                "\\begin{frame}"), 1)
        self.assertIn("\\pagestyle{empty}", snippets_mod.preview_text("x"))


@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class CompilingTests(unittest.TestCase):
    """Compilando de verdad: la definición llega a lo que usa el entorno."""

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-snippets-build-")
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)
        self.root = os.path.join(self.work, "demo")
        shutil.copytree(DEMO, self.root,
                        ignore=shutil.ignore_patterns(".didacta-build"))
        self.source = sorted(glob.glob(
            os.path.join(self.root, "courses", "*", "*", "*.tex")))[0]
        # El primer tema del curso, con un entorno que no define Didacta.
        with open(self.source, encoding="utf-8") as handle:
            text = handle.read()
        text = text.replace(
            "\\end{document}",
            "\\begin{resumen}[Prueba]\\destaca{Hola}\\end{resumen}\n"
            "\\end{document}",
        )
        with open(self.source, "w", encoding="utf-8") as handle:
            handle.write(text)
        self.content_root = os.path.relpath(self.root,
                                            os.path.dirname(self.source))

    def build(self):
        settings = repo_mod.Settings.load(self.root)
        engine = build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(self.root, settings.build_dir),
            engine="pdflatex",
            settings=settings,
        )
        return engine.build(self.source, "notes", "es",
                            content_root=self.content_root)

    def test_without_the_snippet_the_environment_is_undefined(self):
        self.assertFalse(self.build().ok)

    def test_with_the_snippet_it_compiles(self):
        with open(os.path.join(self.root, "snippets.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(SNIPPETS)
        result = self.build()
        self.assertTrue(result.ok, [str(d) for d in result.errors[:3]])

    def test_the_cli_previews_an_unsaved_snippet(self):
        definition = os.path.join(self.work, "def.tex")
        body = os.path.join(self.work, "body.tex")
        with open(definition, "w", encoding="utf-8") as handle:
            handle.write("\\DidactaNewTheorem{resumen}{Resumen}{didactaThm}\n")
        with open(body, "w", encoding="utf-8") as handle:
            handle.write("\\begin{resumen}\nHola.\n\\end{resumen}\n")
        cli = load_cli()
        out = io.StringIO()
        with redirect_stdout(out):
            code = cli.main(["--root", self.root, "snippet-preview",
                             "--definition", definition, "--body", body,
                             "--json"])
        data = json.loads(out.getvalue())
        self.assertEqual(code, 0, data)
        self.assertTrue(data["ok"])
        self.assertTrue(os.path.isfile(data["pdf"]))

    def test_the_cli_takes_the_snippet_as_text(self):
        # Es como la llama la aplicación: con lo que hay en la pantalla, sin
        # escribir ficheros.
        cli = load_cli()
        out = io.StringIO()
        with redirect_stdout(out):
            code = cli.main([
                "--root", self.root, "snippet-preview",
                "--definition-text",
                "\\newcommand{\\rojo}[1]{\\textcolor{red}{#1}}",
                "--body-text", "Esto es \\rojo{rojo}.",
                "-p", "slides", "--json",
            ])
        data = json.loads(out.getvalue())
        self.assertEqual(code, 0, data)
        self.assertTrue(data["slides"])
        self.assertTrue(os.path.isfile(data["pdf"]))

    def test_a_broken_definition_is_reported(self):
        definition = os.path.join(self.work, "def.tex")
        body = os.path.join(self.work, "body.tex")
        with open(definition, "w", encoding="utf-8") as handle:
            handle.write("\\newenvironment{theorem}{}{}\n")
        with open(body, "w", encoding="utf-8") as handle:
            handle.write("Hola.\n")
        cli = load_cli()
        out = io.StringIO()
        with redirect_stdout(out):
            code = cli.main(["--root", self.root, "snippet-preview",
                             "--definition", definition, "--body", body,
                             "--json"])
        data = json.loads(out.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(data["ok"])
        self.assertTrue(any(each["severity"] == "error"
                            for each in data["diagnostics"]))


if __name__ == "__main__":
    unittest.main()
