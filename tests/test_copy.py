"""Copiar documentos de un curso a otro.

La operación que hace útil que una unidad no sepa en qué asignatura entra:
dar el Tema 1 otro año es copiar **su composición**, no su material. El curso
de destino referencia las mismas unidades, que siguen siendo una sola.

Lo que se fija aquí, en orden de lo que más duele si se rompe:

* que no se copie contenido, solo referencias;
* que no se pise nada que ya esté en el destino;
* que los comentarios del `year.yaml` --los `# TODO: va`, las entradas
  comentadas de material que este año no se da-- viajen con el documento, que
  es lo que un volcado de YAML se llevaría por delante;
* que un tema copiado se lleve su declaración, o el bloque llegaría deshecho.
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


class Args:
    """Lo que el parser le pasaría al comando."""

    def __init__(self, root, source, target, documents=(), create=False):
        self.root = root
        self.From = source
        self.to = target
        self.documents = list(documents)
        self.create_year = create


class CopyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-copy-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("didacta.yaml", "languages: [es, va]\ndefault_language: es\n")
        self.write("courses/am-i/course.yaml", "id: am-i\ntitle:\n  es: AM I\n")
        self.unit("content/a/b/c")
        self.unit("content/a/b/d")

        self.write(
            "courses/am-i/2022-2023/year.yaml",
            "course: am-i\n"
            "year: 2022-2023\n"
            "language: es\n"
            "\n"
            "documents:\n"
            "  - id: tema-1\n"
            "    kind: theory\n"
            "    themes: [tema-1]\n"
            "    title:\n"
            "      es: Tema 1\n"
            "      # TODO: va\n"
            "    structure:\n"
            "      - unit: a/b/c\n"
            "      # - unit: a/b/d\n"
            "\n"
            "  - id: faq\n"
            "    kind: handout\n"
            "    title:\n"
            "      es: Preguntas\n"
            "    structure: []\n",
        )
        self.write("courses/am-i/2022-2023/tema-1.tex", "% Tema 1, curso 2022-2023\n")
        self.write("courses/am-i/2022-2023/faq.tex", "% FAQ\n")
        self.write(
            "courses/am-i/2022-2023/themes.yaml",
            "themes:\n  - id: tema-1\n    title:\n      es: El número real\n",
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
        return path

    def unit(self, relpath):
        self.write("%s/es.tex" % relpath, "Contenido.\n")
        self.write(
            "%s/unit.yaml" % relpath,
            "id: %s\nkind: theory\ntitle:\n  es: X\n"
            "languages:\n  es: {status: draft}\n"
            % relpath.split("/", 1)[1].replace("/", "."),
        )

    def copy(self, documents=(), source="am-i@2022-2023",
             target="am-i@2026-2027", create=False):
        return self.cli.cmd_copy(
            Args(self.root, source, target, documents, create=create)
        )

    def read(self, relpath):
        with open(os.path.join(self.root, relpath.replace("/", os.sep)),
                  encoding="utf-8") as handle:
            return handle.read()

    def documents_in(self, year):
        courses, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertEqual(errors, [])
        return [d.id for d in courses["am-i"].years[year].documents]

    # -- lo que hace -----------------------------------------------------

    def test_it_copies_what_is_asked_and_nothing_else(self):
        self.assertEqual(self.copy(["tema-1"]), 0)
        self.assertEqual(self.documents_in("2026-2027"), ["tema-1"])
        # Y el origen se queda como estaba: copiar no es mover.
        self.assertEqual(self.documents_in("2022-2023"), ["tema-1", "faq"])

    def test_without_a_list_it_copies_everything(self):
        self.assertEqual(self.copy(), 0)
        self.assertEqual(self.documents_in("2026-2027"), ["tema-1", "faq"])

    def test_the_composition_file_travels(self):
        self.copy(["tema-1"])
        self.assertTrue(
            os.path.isfile(
                os.path.join(self.root, "courses/am-i/2026-2027/tema-1.tex")
            )
        )

    def test_the_year_is_updated_in_the_copy(self):
        # Un documento copiado que sigue diciendo el año viejo en la portada
        # se reparte con la fecha de otro curso.
        self.copy(["tema-1"])
        self.assertIn("2026-2027", self.read("courses/am-i/2026-2027/tema-1.tex"))
        self.assertNotIn("2022-2023", self.read("courses/am-i/2026-2027/tema-1.tex"))



    # -- lo que NO hace --------------------------------------------------

    def test_no_content_is_duplicated(self):
        """El punto entero: la unidad sigue siendo una.

        Si copiar un curso copiara sus unidades, corregir una errata pasaría a
        ser corregirla en cada año en que se dio.
        """
        before = sorted(
            os.path.relpath(os.path.join(base, name), self.root)
            for base, _, names in os.walk(os.path.join(self.root, "content"))
            for name in names
        )
        self.copy()
        after = sorted(
            os.path.relpath(os.path.join(base, name), self.root)
            for base, _, names in os.walk(os.path.join(self.root, "content"))
            for name in names
        )
        self.assertEqual(before, after)

    def test_it_refuses_to_overwrite_what_is_already_there(self):
        self.copy(["tema-1"])
        self.assertEqual(self.copy(["tema-1"]), 1)
        # Y no ha dejado el documento dos veces.
        self.assertEqual(self.documents_in("2026-2027"), ["tema-1"])

    def test_an_unknown_document_is_refused_before_touching_anything(self):
        self.assertEqual(self.copy(["no-existe"]), 1)
        self.assertEqual(self.documents_in("2026-2027"), [])

    def test_copying_a_course_onto_itself_is_refused(self):
        self.assertEqual(
            self.copy(["tema-1"], target="am-i@2022-2023"), 1
        )

    def test_an_unknown_year_is_refused(self):
        # A mano, `am-i@1999-200` es un dedazo mucho más probable que un curso
        # nuevo: crearlo en silencio dejaría basura.
        self.assertEqual(self.copy(["tema-1"], target="am-i@1999-2000"), 1)
        self.assertEqual(self.copy(["tema-1"], source="otra@2022-2023"), 1)

    def test_a_year_that_lives_in_another_repository_can_be_created_here(self):
        """El caso que motiva la bandera.

        Un curso repartido entre repositorios --la teoría en uno, los
        problemas en otro-- existe entero para quien tiene los dos, y este
        comando solo ve el suyo. Que el destino no tenga carpeta aquí no es
        que no exista: es que este repositorio todavía no aportaba nada.

        Y tiene que copiarse **aquí**, no al repositorio de al lado: un
        documento y las unidades que llama viven juntos, o la compilación
        falla para quien solo tenga uno.
        """
        self.assertEqual(
            self.copy(["tema-1"], target="am-i@2030-2031", create=True), 0
        )
        courses, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertEqual(errors, [])
        self.assertEqual(
            [d.id for d in courses["am-i"].years["2030-2031"].documents],
            ["tema-1"],
        )

    # -- lo que se lleva consigo -----------------------------------------

    def test_the_comments_travel_with_the_document(self):
        # Un `# TODO: va` es la lista de lo que falta por traducir, y una
        # entrada comentada es material que este año no se da. Las dos cosas
        # son trabajo de alguien.
        self.copy(["tema-1"])
        copied = self.read("courses/am-i/2026-2027/year.yaml")
        self.assertIn("# TODO: va", copied)
        self.assertIn("# - unit: a/b/d", copied)

    def test_a_copied_theme_brings_its_declaration(self):
        # Sin esto el bloque llega deshecho: la etiqueta viaja con el
        # documento y la declaración se queda, así que el tema no agrupa.
        self.copy(["tema-1"])
        themes = self.read("courses/am-i/2026-2027/themes.yaml")
        self.assertIn("id: tema-1", themes)
        self.assertIn("El número real", themes)

    def test_a_theme_already_declared_is_not_declared_twice(self):
        self.write(
            "courses/am-i/2026-2027/themes.yaml",
            "themes:\n  - id: tema-1\n    title:\n      es: Otro nombre\n",
        )
        self.copy(["tema-1"])
        themes = self.read("courses/am-i/2026-2027/themes.yaml")
        self.assertEqual(themes.count("id: tema-1"), 1)
        self.assertIn("Otro nombre", themes)

    def test_a_document_without_themes_declares_none(self):
        self.copy(["faq"])
        self.assertFalse(
            os.path.isfile(
                os.path.join(self.root, "courses/am-i/2026-2027/themes.yaml")
            )
        )

    def test_the_result_is_a_consistent_repository(self):
        self.copy()
        courses, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertEqual(errors, [])
        units, _ = repo_mod.scan_units(self.root, self.settings)
        for document in courses["am-i"].years["2026-2027"].documents:
            for reference in document.unit_refs:
                self.assertIsNotNone(
                    repo_mod.resolve_unit_ref(reference, units, self.root),
                    reference,
                )




class EmptyYearTests(unittest.TestCase):
    """Un curso académico que se empieza en blanco.

    Existe porque copiar era obligatorio, y hay dos casos en que no se puede o
    no se quiere: la asignatura recién creada, que no tiene de dónde copiar, y
    el año que se compone desde cero -- arrastrar lo del anterior para ir
    borrándolo es más trabajo que empezar vacío.
    """

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-empty-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("didacta.yaml", "languages: [es]\ndefault_language: es\n")
        self.write(
            "courses/am-i/course.yaml",
            "id: am-i\ntitle:\n  es: Análisis Matemático I\nlanguage: es\n",
        )

    def write(self, relpath, text):
        path = os.path.join(self.root, relpath.replace("/", os.sep))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def new_year(self, year, source=None, empty=False):
        class Args:
            root = self.root
            course = "am-i"

        args = Args()
        args.year = year
        args.From = source
        args.empty = empty
        return self.cli.cmd_new_year(args)

    def year_file(self, year):
        with open(
            os.path.join(self.root, "courses", "am-i", year, "year.yaml"),
            encoding="utf-8",
        ) as handle:
            return handle.read()

    def test_a_subject_with_no_years_gets_an_empty_one(self):
        # Sin `--empty` siquiera: no hay de dónde copiar, y pedirle a alguien
        # que copie algo que no existe no es una respuesta.
        self.assertEqual(self.new_year("2026-2027"), 0)
        self.assertIn("year: 2026-2027", self.year_file("2026-2027"))

    def test_empty_asks_for_it_even_when_there_is_something_to_copy(self):
        self.new_year("2025-2026")
        self.write("courses/am-i/2025-2026/tema-1.tex", "% x\n")
        self.assertEqual(self.new_year("2026-2027", empty=True), 0)
        self.assertNotIn("tema-1", self.year_file("2026-2027"))

    def test_an_empty_year_has_the_shape_a_year_has(self):
        self.new_year("2026-2027", empty=True)
        body = self.year_file("2026-2027")
        self.assertIn("course: am-i", body)
        self.assertIn("year: 2026-2027", body)
        self.assertIn("language: es", body)
        self.assertIn("documents:", body)

    def test_an_empty_year_is_a_year_the_engine_reads(self):
        self.new_year("2026-2027", empty=True)
        settings = repo_mod.Settings.load(self.root)
        courses, errors = repo_mod.scan_courses(self.root, settings)
        self.assertEqual(errors, [])
        entry = courses["am-i"].years["2026-2027"]
        self.assertEqual(entry.documents, [])

    def test_empty_and_from_contradict_each_other(self):
        self.new_year("2025-2026")
        self.assertEqual(
            self.new_year("2026-2027", source="2025-2026", empty=True), 1
        )

    def test_it_still_copies_when_asked_to(self):
        # Lo de antes sigue: el caso corriente es repetir el año anterior.
        self.new_year("2025-2026")
        self.write("courses/am-i/2025-2026/tema-1.tex", "% Curso 2025-2026\n")
        self.write(
            "courses/am-i/2025-2026/year.yaml",
            "course: am-i\nyear: 2025-2026\nlanguage: es\n\n"
            "documents:\n  - id: tema-1\n    kind: theory\n    structure: []\n",
        )
        self.assertEqual(self.new_year("2026-2027", source="2025-2026"), 0)
        self.assertIn("tema-1", self.year_file("2026-2027"))


if __name__ == "__main__":
    unittest.main()
