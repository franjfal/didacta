"""CLI tests.

The command-line tool is the whole interface until the app exists, and it had
no coverage at all. These check the parts with logic in them rather than the
printing: the argument surface, and the migration report -- which is the actual
deliverable of a migration, so what it does and does not say matters.

Loaded by path because the script has no `.py` extension, being a command.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

CLI_PATH = os.path.join(ROOT, "cli", "didacta")


def load_cli():
    spec = importlib.util.spec_from_loader(
        "didacta_cli",
        importlib.machinery.SourceFileLoader("didacta_cli", CLI_PATH),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakePlan:
    """Enough of a unit plan for the report."""

    source_root = "/legacy"
    target_root = "/target"
    units = []
    skipped = []
    errors = []
    decisions = []

    def summary(self):
        return {"units": 0, "files": 0, "skipped": 0,
                "byKind": {}, "byLanguages": {}}


class ReportTests(unittest.TestCase):
    """What the migration report says."""

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def report(self, failures=()):
        return self.cli._migration_report(
            FakePlan(), None, "/legacy", "/target", failures)

    def test_the_report_states_the_source_was_not_modified(self):
        """The guarantee is worth saying in the deliverable, not just doing."""
        text = self.report()
        self.assertIn("no se ha", text)
        self.assertIn("modificado", text)

    def test_with_no_failures_there_is_no_failures_section(self):
        self.assertNotIn("no compila", self.report())

    def test_a_failure_is_named_with_its_file_line_and_error(self):
        text = self.report([
            ("am-iii-a/2025-2026/tema-1", "slides",
             "error content/a/b/es.tex:9 Missing $ inserted."),
        ])
        self.assertIn("content/a/b/es.tex:9", text)
        self.assertIn("Missing $ inserted", text)
        self.assertIn("am-iii-a/2025-2026/tema-1", text)
        self.assertIn("slides", text)

    def test_failures_are_grouped_by_the_file_at_fault(self):
        """One unit breaks several documents.

        Measured on 2025-2026: 19 documents fail from 11 units, and the
        bibliography unit accounts for six of them. Listing documents asks the
        author to read the same error six times.
        """
        same = "error content/x/bib/es.tex:4 Undefined control sequence."
        text = self.report([
            ("quimica/2025-2026/t0-bib", "handout", same),
            ("quimica/2025-2026/t1-bib", "handout", same),
            ("quimica/2025-2026/t2-bib", "handout", same),
            ("iowa/2025-2026/first-order", "slides",
             "error content/edos/a/en.tex:109 Arithmetic overflow."),
        ])
        self.assertIn("2 unidad(es), 4 documento(s)", text)
        # The error appears once, not once per document.
        self.assertEqual(text.count("Undefined control sequence"), 1, text)
        self.assertIn("Rompe 3 documento(s)", text)
        for name in ("t0-bib", "t1-bib", "t2-bib"):
            self.assertIn(name, text)

    def test_the_worst_offender_comes_first(self):
        # Ordered by how many documents each fix buys back.
        text = self.report([
            ("a", "slides", "error content/one/es.tex:1 Error one."),
            ("b", "slides", "error content/many/es.tex:1 Error many."),
            ("c", "slides", "error content/many/es.tex:1 Error many."),
        ])
        self.assertLess(text.index("content/many"), text.index("content/one"))

    def test_an_unlocatable_error_is_still_reported(self):
        text = self.report([("doc", "notes", "latexmk died before starting")])
        self.assertIn("sin localizar", text)
        self.assertIn("latexmk died", text)

    def test_the_report_says_the_metadata_was_not_invented(self):
        text = self.report()
        self.assertIn("no la ha inventado", text)


class ArgumentTests(unittest.TestCase):
    """The command surface.

    A flag that silently stops existing is a broken workflow, and these are the
    ones the migration instructions in the docs tell people to type.
    """

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def parse(self, argv):
        try:
            return self.cli.main(argv)
        except SystemExit as exit_code:  # argparse errors exit
            raise AssertionError("argparse rejected %r (exit %s)"
                                 % (argv, exit_code.code))

    def test_migrate_accepts_the_documented_flags(self):
        # Parsed, not run: --apply is absent so nothing is written, and a
        # missing source makes it return before touching anything.
        for extra in ([], ["--verify"], ["--no-courses"],
                      ["--year", "2025-2026"], ["--category", "40functional"],
                      ["--limit", "5"], ["--list"], ["-v"]):
            with self.subTest(extra=extra):
                code = self.parse(["migrate", "/nonexistent", "/target"] + extra)
                # 1 is "that does not look like the legacy repository", which
                # is the check running -- what matters is that it parsed.
                self.assertEqual(code, 1)

    def test_migrate_refuses_to_write_into_its_own_source(self):
        code = self.parse(["migrate", ROOT, ROOT])
        self.assertNotEqual(code, 0)

    def test_every_documented_command_parses(self):
        """`--help` on each: a subcommand that vanished is a broken workflow."""
        for command in ("status", "profiles", "units", "translations",
                        "build", "check", "migrate", "new"):
            with self.subTest(command=command):
                with self.assertRaises(SystemExit) as raised:
                    self.cli.main([command, "--help"])
                # argparse exits 0 after printing help; 2 means it did not
                # recognise the command.
                self.assertEqual(raised.exception.code, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)


class CourseAdminTests(unittest.TestCase):
    """Crear y borrar asignaturas y años.

    Lo que se comprueba es lo que distingue estas órdenes de un `rm -rf`: que
    borrar es un simulacro por defecto y dice qué se va, que crear una
    asignatura copiada no arrastra la procedencia de la original --que deja de
    ser verdad al copiar-- y que duplicar un año copia la estructura y no el
    contenido, que es la razón de que el reparto exista.
    """

    def setUp(self):
        import shutil
        import tempfile

        self.cli = load_cli()
        self.root = tempfile.mkdtemp(prefix="didacta-courses-")
        self.addCleanup(shutil.rmtree, self.root, True)

        os.makedirs(os.path.join(self.root, "content", "a", "b", "c"))
        with open(
            os.path.join(self.root, "content", "a", "b", "c", "es.tex"),
            "w", encoding="utf-8",
        ) as handle:
            handle.write("El contenido.\n")
        with open(
            os.path.join(self.root, "content", "a", "b", "c", "unit.yaml"),
            "w", encoding="utf-8",
        ) as handle:
            handle.write("id: a.b.c\nkind: theory\ntitle:\n  es: Uno\n"
                         "category: a\ntopic: b\nreference: es\n"
                         "languages:\n  es: {status: draft}\n")
        with open(os.path.join(self.root, "didacta.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("name: Prueba\nlanguages: [es, va, en]\n"
                         "default_language: es\nbuild_dir: .build\n")

        self.course_dir = os.path.join(self.root, "courses", "mates")
        os.makedirs(os.path.join(self.course_dir, "2024-2025"))
        with open(os.path.join(self.course_dir, "course.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(
                "# Matemáticas\n#\n"
                "# Migrated from  2024-2025/Mates/classinfo.tex\n#\n"
                "# Lo que no cambia de un año a otro.\n\n"
                "id: mates\ntitle:\n  es: Matemáticas\n\n"
                "# TODO: el código\ncode: null\n\nlanguage: es\n"
            )
        with open(os.path.join(self.course_dir, "2024-2025", "year.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(
                "course: mates\nyear: 2024-2025\nlanguage: es\n\n"
                "documents:\n  - id: tema-1\n    kind: theory\n"
                "    title:\n      es: Tema 1\n"
                "    structure:\n      - unit: a/b/c\n"
            )
        with open(os.path.join(self.course_dir, "2024-2025", "tema-1.tex"),
                  "w", encoding="utf-8") as handle:
            handle.write("% Tema 1 -- 2024-2025\n\\input{didacta-bootstrap}\n")

    def run_cli(self, *args):
        return self.cli.main(["--root", self.root, *args])

    # -- borrar ----------------------------------------------------------

    def test_removing_a_course_is_a_dry_run_by_default(self):
        # Borrar una asignatura quita el único registro de qué se dio y en
        # qué orden. Sin `--apply` no se toca nada.
        self.assertEqual(self.run_cli("remove", "course", "mates"), 0)
        self.assertTrue(os.path.isdir(self.course_dir))

    def test_removing_a_course_with_apply_deletes_it(self):
        self.assertEqual(
            self.run_cli("remove", "course", "mates", "--apply"), 0
        )
        self.assertFalse(os.path.exists(self.course_dir))

    def test_removing_a_course_leaves_the_units_alone(self):
        """Lo que se pierde es la selección, no el material.

        Es la frase que la orden imprime, y tiene que ser verdad: las
        unidades son de `content/`, no de la asignatura.
        """
        self.run_cli("remove", "course", "mates", "--apply")
        self.assertTrue(
            os.path.isfile(
                os.path.join(self.root, "content", "a", "b", "c", "es.tex")
            )
        )

    def test_removing_a_course_that_does_not_exist_fails(self):
        self.assertEqual(self.run_cli("remove", "course", "nada"), 1)

    def test_removing_a_year_leaves_the_course(self):
        self.assertEqual(
            self.run_cli("remove", "year", "mates", "2024-2025", "--apply"), 0
        )
        self.assertFalse(
            os.path.exists(os.path.join(self.course_dir, "2024-2025"))
        )
        self.assertTrue(
            os.path.isfile(os.path.join(self.course_dir, "course.yaml"))
        )

    def test_removing_a_year_that_does_not_exist_fails(self):
        self.assertEqual(
            self.run_cli("remove", "year", "mates", "1999-2000"), 1
        )

    # -- crear -----------------------------------------------------------

    def test_a_new_course_is_created_without_years(self):
        # Una asignatura con un año vacío es un año que alguien tiene que
        # acordarse de rellenar; `new year` ya existe para hacer uno.
        self.assertEqual(self.run_cli("new", "course", "fisica"), 0)
        directory = os.path.join(self.root, "courses", "fisica")
        self.assertTrue(os.path.isfile(os.path.join(directory, "course.yaml")))
        self.assertEqual(os.listdir(directory), ["course.yaml"])

    def test_a_new_course_refuses_an_id_that_is_not_a_directory_name(self):
        # El id es el nombre del directorio y lo que referencia una
        # composición: tiene que sobrevivir a escribirse, ordenarse y a una URL.
        for bad in ("Física", "con espacio", "MATES", "con/barra"):
            self.assertEqual(self.run_cli("new", "course", bad), 1, bad)

    def test_an_id_that_looks_like_a_flag_goes_after_a_double_dash(self):
        """Y hay que pasarlo así, no es un detalle del test.

        `argparse` toma `-empieza-mal` por una opción y sale antes de que la
        validación lo vea. Quien llame a esto con un id que viene de un
        formulario tiene que ponerlo detrás de `--`, y la interfaz lo hace.
        """
        self.assertEqual(
            self.run_cli("new", "course", "--", "-empieza-mal"), 1
        )

    def test_a_new_course_refuses_to_overwrite(self):
        self.assertEqual(self.run_cli("new", "course", "mates"), 1)

    def test_copying_a_course_keeps_the_field_comments(self):
        # Los TODO de los campos son la lista de trabajo, y son la razón de
        # copiar en lugar de empezar de cero.
        self.assertEqual(
            self.run_cli("new", "course", "mates-b", "--from", "mates"), 0
        )
        with open(
            os.path.join(self.root, "courses", "mates-b", "course.yaml"),
            encoding="utf-8",
        ) as handle:
            text = handle.read()
        self.assertIn("# TODO: el código", text)
        self.assertIn("id: mates-b", text)
        self.assertNotIn("id: mates\n", text)

    def test_copying_a_course_drops_a_provenance_that_stopped_being_true(self):
        """La cabecera de la copia decía de qué fichero salió la original.

        Y eso deja de ser verdad en cuanto se copia: `mates-b` no salió de
        `classinfo.tex`, salió de `mates`.
        """
        self.run_cli("new", "course", "mates-b", "--from", "mates")
        with open(
            os.path.join(self.root, "courses", "mates-b", "course.yaml"),
            encoding="utf-8",
        ) as handle:
            text = handle.read()
        self.assertNotIn("Migrated from", text)
        self.assertIn("Copiada de mates", text)

    def test_copying_a_course_can_retitle_it(self):
        self.run_cli("new", "course", "mates-b", "--from", "mates",
                     "--title", "Matemáticas (grupo B)")
        with open(
            os.path.join(self.root, "courses", "mates-b", "course.yaml"),
            encoding="utf-8",
        ) as handle:
            text = handle.read()
        self.assertIn("es: Matemáticas (grupo B)", text)

    def test_copying_a_course_that_does_not_exist_leaves_nothing_behind(self):
        # Ni el directorio a medias: un `courses/x/` vacío rompe el escaneo.
        self.assertEqual(
            self.run_cli("new", "course", "nueva", "--from", "nada"), 1
        )
        self.assertFalse(os.path.exists(os.path.join(self.root, "courses",
                                                     "nueva")))

    # -- duplicar un año -------------------------------------------------

    def test_duplicating_a_year_copies_structure_and_not_content(self):
        self.assertEqual(
            self.run_cli("new", "year", "mates", "2025-2026"), 0
        )
        target = os.path.join(self.course_dir, "2025-2026")
        with open(os.path.join(target, "year.yaml"), encoding="utf-8") as h:
            year = h.read()
        self.assertIn("year: 2025-2026", year)
        self.assertNotIn("year: 2024-2025", year)
        # La unidad se referencia, no se copia: es la razón del reparto.
        self.assertIn("- unit: a/b/c", year)
        self.assertTrue(os.path.isfile(os.path.join(target, "tema-1.tex")))

    def test_duplicating_a_year_updates_the_year_in_the_documents(self):
        self.run_cli("new", "year", "mates", "2025-2026")
        with open(
            os.path.join(self.course_dir, "2025-2026", "tema-1.tex"),
            encoding="utf-8",
        ) as handle:
            self.assertIn("2025-2026", handle.read())

    def test_duplicating_refuses_when_the_year_exists(self):
        self.assertEqual(self.run_cli("new", "year", "mates", "2024-2025"), 1)


class BuildInterfaceTests(unittest.TestCase):
    """Lo que `build` le cuenta a una interfaz.

    Compilar un tema desde la aplicación necesita dos respuestas que antes no
    se podían leer sin adivinar: **qué versiones admite este documento** y
    **cómo ha ido la compilación**. Lo primero no es lo mismo que «qué se va
    a compilar»: un documento declara las suyas en `year.yaml`, pero el mismo
    tema se quiere en libro un día y en diapositivas otro.

    Nada de esto compila de verdad --eso ya está probado en `test_engine`--;
    lo que se comprueba es la forma de lo que sale, que es de lo que depende
    otro programa.
    """

    def setUp(self):
        import shutil
        import tempfile

        self.cli = load_cli()
        self.root = tempfile.mkdtemp(prefix="didacta-build-")
        self.addCleanup(shutil.rmtree, self.root, True)

        os.makedirs(os.path.join(self.root, "content", "a", "b", "c"))
        with open(os.path.join(self.root, "content", "a", "b", "c", "es.tex"),
                  "w", encoding="utf-8") as handle:
            handle.write("El contenido.\n")
        with open(os.path.join(self.root, "content", "a", "b", "c", "unit.yaml"),
                  "w", encoding="utf-8") as handle:
            handle.write("id: a.b.c\nkind: theory\ntitle:\n  es: Uno\n"
                         "category: a\ntopic: b\nreference: es\n"
                         "languages:\n  es: {status: draft}\n")
        with open(os.path.join(self.root, "didacta.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("name: Prueba\nlanguages: [es, va, en]\n"
                         "default_language: es\nbuild_dir: .build\n")

        year_dir = os.path.join(self.root, "courses", "mates", "2024-2025")
        os.makedirs(year_dir)
        with open(os.path.join(self.root, "courses", "mates", "course.yaml"),
                  "w", encoding="utf-8") as handle:
            handle.write("id: mates\ntitle:\n  es: Matemáticas\nlanguage: es\n")
        with open(os.path.join(year_dir, "year.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(
                "course: mates\nyear: 2024-2025\nlanguage: es\n\n"
                "documents:\n  - id: tema-1\n    kind: theory\n"
                "    title:\n      es: Tema 1\n"
                "    profiles: [slides]\n"
                "    structure:\n      - unit: a/b/c\n"
            )
        with open(os.path.join(year_dir, "tema-1.tex"), "w",
                  encoding="utf-8") as handle:
            handle.write("% Tema 1\n\\input{didacta-bootstrap}\n")

    def run_cli(self, *args):
        return self.cli.main(["--root", self.root, *args])

    def capture(self, *args):
        import contextlib
        import io

        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = self.run_cli(*args)
        return code, out.getvalue()

    def test_profiles_lists_every_one_the_kind_admits(self):
        # No solo las que el documento declara: el mismo tema se quiere en
        # libro un día y en diapositivas otro, y la interfaz tiene que poder
        # ofrecerlo sin que nadie edite el YAML.
        code, output = self.capture(
            "build", "mates@2024-2025/tema-1", "--profiles", "--json")
        self.assertEqual(code, 0)
        listed = json.loads(output)
        ids = [entry["profile"] for entry in listed]
        self.assertIn("slides", ids)
        self.assertIn("book", ids)
        self.assertIn("notes", ids)

    def test_profiles_marks_the_document_s_own(self):
        _, output = self.capture(
            "build", "mates@2024-2025/tema-1", "--profiles", "--json")
        listed = {entry["profile"]: entry["default"] for entry in json.loads(output)}
        self.assertTrue(listed["slides"], "la que declara el documento")
        self.assertFalse(listed["book"], "una que no declara")

    def test_profiles_carry_a_readable_name(self):
        # La interfaz enseña «Diapositivas», no `slides-flat`.
        _, output = self.capture(
            "build", "mates@2024-2025/tema-1", "--profiles", "--json")
        labels = {e["profile"]: e["label"] for e in json.loads(output)}
        self.assertEqual(labels["slides"], "Diapositivas")
        self.assertEqual(labels["book"], "Libro")

    def test_profiles_of_a_document_that_is_not_there(self):
        code, output = self.capture(
            "build", "mates@2024-2025/no-existe", "--profiles", "--json")
        self.assertEqual(code, 1)
        self.assertIn("no document matches", output)

    def test_list_as_json_says_what_would_be_built(self):
        code, output = self.capture(
            "build", "mates@2024-2025/tema-1", "--list", "--json")
        self.assertEqual(code, 0)
        jobs = json.loads(output)
        self.assertEqual(
            [(j["profile"], j["language"]) for j in jobs], [("slides", "es")])
        self.assertEqual(jobs[0]["document"], "mates@2024-2025/tema-1")
        self.assertEqual(jobs[0]["label"], "Diapositivas")

    def test_list_as_json_honours_the_chosen_profiles(self):
        _, output = self.capture(
            "build", "mates@2024-2025/tema-1", "--list", "--json",
            "-p", "book", "-l", "va", "-l", "es")
        jobs = json.loads(output)
        self.assertEqual(
            sorted((j["profile"], j["language"]) for j in jobs),
            [("book", "es"), ("book", "va")])

    def test_json_output_is_only_json(self):
        # Al otro lado hay un programa. Una tabla bonita antes del JSON es
        # algo que ese programa tiene que aprender a saltarse, y el día que
        # cambie una palabra se rompe.
        _, output = self.capture(
            "build", "mates@2024-2025/tema-1", "--list", "--json")
        self.assertTrue(output.lstrip().startswith("["), output[:80])
        json.loads(output)

