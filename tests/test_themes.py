"""Los temas de un curso: agrupar sin poder romper nada.

Un tema es un bloque de la asignatura --el Tema 1 lleva su teoría, su
práctica, su bibliografía-- y esos ficheros pueden estar en repositorios
distintos. De ahí la forma que tiene esto y que es lo que se fija aquí:

* el documento **nombra** los temas a los que pertenece, en su `year.yaml`;
* el título y el orden los **declara** `themes.yaml`, al lado;
* las dos cosas pueden vivir en repositorios distintos.

Lo que se prueba sobre todo es el caso de la mitad que falta. Quien tenga solo
el repositorio de problemas verá etiquetas que no apuntan a nada, y eso tiene
que quedar exactamente como estaba antes de que los temas existieran: una
lista de documentos. Ni un error, ni una pantalla vacía, ni un fichero que
pedir.
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

from didacta import index as index_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402

CLI_PATH = os.path.join(ROOT, "cli", "didacta")


def load_cli():
    spec = importlib.util.spec_from_loader(
        "didacta_cli",
        importlib.machinery.SourceFileLoader("didacta_cli", CLI_PATH),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Repository(unittest.TestCase):
    """Un curso de mentira, con sus documentos."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-themes-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("didacta.yaml", "languages: [es]\ndefault_language: es\n")
        self.write("courses/am-i/course.yaml", "id: am-i\ntitle:\n  es: AM I\n")
        self.settings = repo_mod.Settings.load(self.root)

    def write(self, relpath, text):
        path = os.path.join(self.root, relpath.replace("/", os.sep))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def year(self, documents, themes=None):
        """Un curso con sus documentos, y sus temas si los declara."""
        body = ["course: am-i", "year: 2026-2027", "language: es", "", "documents:"]
        for identifier, tags in documents:
            body.append("  - id: %s" % identifier)
            body.append("    kind: theory")
            if tags is not None:
                body.append("    themes: [%s]" % ", ".join(tags))
            body.append("    structure: []")
        self.write("courses/am-i/2026-2027/year.yaml", "\n".join(body) + "\n")
        for identifier, _ in documents:
            self.write("courses/am-i/2026-2027/%s.tex" % identifier, "%% doc\n")
        if themes is not None:
            declared = ["themes:"]
            for identifier, title in themes:
                declared.append("  - id: %s" % identifier)
                declared.append("    title:")
                declared.append("      es: %s" % title)
            self.write(
                "courses/am-i/2026-2027/themes.yaml", "\n".join(declared) + "\n"
            )
        courses, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertEqual(errors, [])
        return courses["am-i"].years["2026-2027"]


class DeclaringTests(Repository):
    """Lo que declara `themes.yaml`."""

    def test_a_course_without_the_file_has_no_themes(self):
        # El caso corriente, y el que había hasta ahora: agrupar es opcional.
        entry = self.year([("practica-1", None)])
        self.assertEqual(entry.themes, [])

    def test_the_declared_ones_keep_their_order(self):
        # El orden de la lista es el orden en que se dan, y es lo único que
        # lo decide.
        entry = self.year(
            [("a", ["tema-2"])],
            themes=[("tema-2", "Segundo"), ("tema-1", "Primero")],
        )
        self.assertEqual([t.id for t in entry.themes], ["tema-2", "tema-1"])

    def test_a_theme_carries_its_title(self):
        entry = self.year([("a", ["tema-1"])], themes=[("tema-1", "El número real")])
        self.assertEqual(entry.themes[0].title("es"), "El número real")

    def test_a_theme_without_an_id_is_an_error(self):
        # Sin id no hay nada a lo que apuntar: es un fichero mal escrito, no
        # un caso que haya que tolerar.
        self.write(
            "courses/am-i/2026-2027/themes.yaml",
            "themes:\n  - title:\n      es: Sin id\n",
        )
        self.write(
            "courses/am-i/2026-2027/year.yaml",
            "course: am-i\nyear: 2026-2027\ndocuments: []\n",
        )
        _, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertTrue(any("`id`" in error for error in errors), errors)

    def test_two_themes_with_the_same_id_is_an_error(self):
        self.write(
            "courses/am-i/2026-2027/themes.yaml",
            "themes:\n  - id: tema-1\n  - id: tema-1\n",
        )
        self.write(
            "courses/am-i/2026-2027/year.yaml",
            "course: am-i\nyear: 2026-2027\ndocuments: []\n",
        )
        _, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertTrue(any("duplicate" in error for error in errors), errors)


class TaggingTests(Repository):
    """Lo que nombra el documento."""

    def test_a_document_can_name_several(self):
        entry = self.year([("apendice", ["tema-1", "tema-2"])])
        self.assertEqual(entry.documents[0].themes, ["tema-1", "tema-2"])

    def test_a_document_can_name_none(self):
        entry = self.year([("faq", None)])
        self.assertEqual(entry.documents[0].themes, [])

    def test_naming_a_theme_nobody_declares_is_not_an_error(self):
        """La prueba que sostiene todo lo demás.

        Es lo que ve quien tiene el repositorio de problemas y no el de
        teoría: la práctica nombra un tema del que aquí no hay ni rastro.
        Tiene que cargar igual, porque la declaración puede estar en un
        repositorio que esta persona no tiene y no va a tener.
        """
        entry = self.year([("practica-1", ["tema-1"])])
        self.assertEqual(entry.documents[0].themes, ["tema-1"])
        self.assertEqual(entry.themes, [])

    def test_declaring_a_theme_nobody_names_is_not_an_error_either(self):
        # El caso simétrico: el repositorio de teoría declara los temas del
        # curso entero, y los documentos de algunos están en el otro.
        entry = self.year(
            [("a", ["tema-1"])],
            themes=[("tema-1", "Primero"), ("tema-9", "Noveno")],
        )
        self.assertEqual(len(entry.themes), 2)


class IndexTests(Repository):
    """Lo que llega a la aplicación, que es lo único que ella lee."""

    def test_the_index_carries_both_halves(self):
        self.year(
            [("teoria", ["tema-1"]), ("faq", None)],
            themes=[("tema-1", "El número real")],
        )
        data = index_mod.build(self.root, self.settings)["courses.json"]
        year = data["courses"][0]["years"]["2026-2027"]

        self.assertEqual(
            year["themes"],
            [{"id": "tema-1", "title": {"es": "El número real"}}],
        )
        documents = {doc["id"]: doc for doc in year["documents"]}
        self.assertEqual(documents["teoria"]["themes"], ["tema-1"])
        self.assertEqual(documents["faq"]["themes"], [])

    def test_a_course_without_themes_indexes_an_empty_list(self):
        # Y no la ausencia de la clave: la aplicación lee una lista, y una
        # clave que a veces está y a veces no es una rama de más en cada
        # sitio que la toca.
        self.year([("a", None)])
        data = index_mod.build(self.root, self.settings)["courses.json"]
        year = data["courses"][0]["years"]["2026-2027"]
        self.assertEqual(year["themes"], [])
        self.assertEqual(year["documents"][0]["themes"], [])




class NewThemeTests(unittest.TestCase):
    """Declarar un tema en un curso.

    La mitad que declara. La otra --la etiqueta `themes:` del documento-- la
    escribe la composición, y pueden estar en repositorios distintos: por eso
    esto no comprueba que nadie lo use, y por eso un tema recién declarado sin
    documentos no es un error.
    """

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-theme-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("didacta.yaml", "languages: [es, va]\ndefault_language: es\n")
        self.write(
            "courses/am-i/course.yaml",
            "id: am-i\ntitle:\n  es: AM I\nlanguage: es\n",
        )
        self.write(
            "courses/am-i/2026-2027/year.yaml",
            "course: am-i\nyear: 2026-2027\nlanguage: es\n\ndocuments:\n",
        )
        self.settings = repo_mod.Settings.load(self.root)

    def write(self, relpath, text):
        path = os.path.join(self.root, relpath.replace("/", os.sep))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def new_theme(self, title=None, identifier=None, year="2026-2027"):
        class Args:
            root = self.root
            course = "am-i"
            lang = None

        args = Args()
        args.year = year
        args.title = title
        args.id = identifier
        return self.cli.cmd_new_theme(args)

    def themes(self, year="2026-2027"):
        courses, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertEqual(errors, [])
        return courses["am-i"].years[year].themes

    def test_a_theme_gets_its_id_from_its_title(self):
        # Nadie quiere escribir `tema-1-el-numero-real` a mano, y el que se
        # escribe a mano acaba siendo distinto del que habría salido.
        self.assertEqual(self.new_theme(title="Tema 1: el número real"), 0)
        self.assertEqual([t.id for t in self.themes()], ["tema-1-el-numero-real"])

    def test_the_id_can_be_given(self):
        self.new_theme(title="Tema 1: el número real", identifier="tema-1")
        self.assertEqual([t.id for t in self.themes()], ["tema-1"])

    def test_the_title_is_kept(self):
        self.new_theme(title="Tema 1: el número real", identifier="tema-1")
        self.assertEqual(self.themes()[0].title("es"), "Tema 1: el número real")

    def test_the_other_languages_are_left_as_todo(self):
        # Un título en castellano en el sitio del valenciano diría al sistema
        # entero que está traducido, que es el error que no se puede cometer.
        self.new_theme(title="Tema 1", identifier="tema-1")
        with open(
            os.path.join(self.root, "courses/am-i/2026-2027/themes.yaml"),
            encoding="utf-8",
        ) as handle:
            body = handle.read()
        self.assertIn("# TODO: va", body)

    def test_a_second_theme_goes_after_the_first(self):
        # El orden de la lista es el orden en que se dan.
        self.new_theme(title="Tema 1", identifier="tema-1")
        self.new_theme(title="Tema 2", identifier="tema-2")
        self.assertEqual([t.id for t in self.themes()], ["tema-1", "tema-2"])

    def test_a_repeated_id_is_refused(self):
        self.new_theme(title="Tema 1", identifier="tema-1")
        self.assertEqual(self.new_theme(title="Otro", identifier="tema-1"), 1)
        self.assertEqual(len(self.themes()), 1)

    def test_a_theme_with_no_documents_is_not_an_error(self):
        # Se crea vacío y se le van metiendo documentos: al revés no se puede,
        # porque un documento se crea ya dentro de un tema.
        self.new_theme(title="Tema 1", identifier="tema-1")
        _, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertEqual(errors, [])

    def test_an_unknown_year_is_refused(self):
        self.assertEqual(self.new_theme(title="Tema 1", year="1999-2000"), 1)

    def test_without_a_title_or_an_id_there_is_nothing_to_declare(self):
        self.assertEqual(self.new_theme(), 1)


if __name__ == "__main__":
    unittest.main()
