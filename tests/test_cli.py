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

    def without_tex(self):
        """Un PATH sin latexmk ni pdflatex, como el de una máquina limpia."""
        import contextlib

        @contextlib.contextmanager
        def hidden():
            before = os.environ.get("PATH", "")
            os.environ["PATH"] = os.pathsep.join(
                part for part in before.split(os.pathsep)
                if not os.path.exists(os.path.join(part, "latexmk"))
                and not os.path.exists(os.path.join(part, "pdflatex"))
            )
            try:
                yield
            finally:
                os.environ["PATH"] = before

        return hidden()

    def test_asking_what_exists_does_not_need_a_tex_distribution(self):
        """Preguntar no es compilar.

        `--profiles` dice qué versiones admite un documento y `--list` dice
        cuáles saldrían: las dos responden con lo que hay en el repositorio y
        ninguna toca LaTeX. Estaban las dos detrás de la comprobación del
        sistema, así que en una máquina sin TeX la aplicación no podía ni
        enseñar qué versiones existen --información que está en un `year.yaml`
        y en ningún programa que haya que instalar--.
        """
        with self.without_tex():
            doc = "mates@2024-2025/tema-1"
            self.assertEqual(self.run_cli("build", doc, "--profiles"), 0)
            self.assertEqual(self.run_cli("build", doc, "--list"), 0)
            # Y en JSON, que es como lo pide la aplicación.
            self.assertEqual(self.run_cli("build", doc, "--list", "--json"), 0)

    def test_but_compiling_without_one_still_refuses(self):
        """Lo otro sí: compilar sin TeX no se puede, y se dice."""
        with self.without_tex():
            self.assertEqual(self.run_cli("build", "mates@2024-2025/tema-1"), 2)

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

    def test_progress_parses_on_the_commands_that_compile(self):
        """La bandera existe donde compila algo, y en ningún sitio más.

        `preview` y `build` son las dos órdenes que lanzan LaTeX y por tanto
        las dos que tienen algo que contar mientras tanto. Que una de ellas
        deje de aceptarla deja a la aplicación sin terminal y sin decir nada:
        el JSON seguiría llegando igual.
        """
        for command in ("build", "preview"):
            with self.subTest(command=command):
                with self.assertRaises(SystemExit) as raised:
                    self.cli.main([command, "--help"])
                self.assertEqual(raised.exception.code, 0)
        self.assertEqual(
            self.run_cli("build", "mates@2024-2025/tema-1",
                         "--list", "--json", "--progress"),
            0,
        )

    def test_progress_goes_to_stderr_so_the_json_stays_readable(self):
        """Las dos corrientes, una para cada lector.

        Por la salida estándar habla el motor con el programa que lo llamó y
        por la de error, con quien está mirando. Si el progreso se colara en
        la primera, la aplicación tendría que aprender a saltárselo -- y lo
        que la aplicación hace es justo enseñarlo aparte.
        """
        import contextlib
        import io

        args = ["--root", self.root, "build", "mates@2024-2025/tema-1",
                "--json", "--progress"]
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.cli.main(args)

        printed = out.getvalue().strip()
        if printed:
            # Sin TeX no llega a compilar y no imprime nada; con TeX imprime
            # el informe, y tiene que seguir siendo JSON y nada más.
            self.assertTrue(printed.startswith(("[", "{")), printed[:80])
            json.loads(printed)
        self.assertNotIn("=== ", printed)



class ExportTests(unittest.TestCase):
    """Lo que se reparte al exportar un curso.

    Una carpeta exportada acaba en el aula virtual. Antes salía todo lo que
    estuviera compilado, y eso incluye la plantilla de corrección del examen
    y las copias del profesor: nadie las pedía, pero estaban ahí. Ahora sale
    lo del estudiante salvo que se pida más, y lo que se queda fuera se dice.
    """

    PROFILES = ["slides", "handout-answers", "notes-solutions",
                "slides-teacher"]

    # El mismo repositorio de juguete que los de compilar, sin sus tests.
    run_cli = BuildInterfaceTests.run_cli
    capture = BuildInterfaceTests.capture

    def setUp(self):
        BuildInterfaceTests.setUp(self)
        year = os.path.join(self.root, "courses", "mates", "2024-2025",
                            "year.yaml")
        with open(year, encoding="utf-8") as handle:
            text = handle.read()
        with open(year, "w", encoding="utf-8") as handle:
            handle.write(text.replace(
                "profiles: [slides]",
                "profiles: [%s]" % ", ".join(self.PROFILES)))
        # PDF de mentira donde los dejaría una compilación: exportar solo
        # copia, así que no hace falta TeX para probarlo.
        all_profiles = self.cli.profiles_mod.load(self.cli.LATEX_DIR)
        engine = self.cli.build_mod.Engine(
            latex_dir=self.cli.LATEX_DIR,
            build_dir=os.path.join(self.root, ".build"),
            template_dirs=[self.root],
            settings=self.cli.repo_mod.Settings.load(self.root),
        )
        for name in self.PROFILES:
            folder = engine.output_dir("mates@2024-2025/tema-1", name, "es")
            os.makedirs(folder, exist_ok=True)
            pdf = all_profiles[name].output_name("Tema 1", "es") + ".pdf"
            with open(os.path.join(folder, pdf), "wb") as handle:
                handle.write(b"%PDF-1.4\n")
        self.to = os.path.join(self.root, "reparto")

    def export(self, *extra):
        code, output = self.capture(
            "export", "mates@2024-2025", "--to", self.to, "-l", "es",
            "--json", *extra)
        self.assertEqual(code, 0, output)
        return json.loads(output)

    def profiles_in(self, report):
        return sorted(output["profile"] for output in report["outputs"])

    def test_by_default_only_what_a_student_may_see(self):
        report = self.export()
        self.assertEqual(self.profiles_in(report),
                         ["handout-answers", "slides"])
        self.assertEqual(
            sorted(report["withheld"]),
            ["tema-1 · notes-solutions · es", "tema-1 · slides-teacher · es"])
        self.assertEqual(report["missing"], [])

    def test_the_solutions_have_to_be_asked_for(self):
        report = self.export("--reveal-up-to", "solutions")
        self.assertEqual(self.profiles_in(report),
                         ["handout-answers", "notes-solutions", "slides"])
        self.assertEqual(report["withheld"],
                         ["tema-1 · slides-teacher · es"])

    def test_the_teacher_s_copies_too(self):
        report = self.export("--reveal-up-to", "teacher")
        self.assertEqual(self.profiles_in(report),
                         sorted(self.PROFILES))
        self.assertEqual(report["withheld"], [])

    def test_withheld_is_not_missing(self):
        # Lo que se deja fuera a propósito no es «sin compilar»: mezclarlo
        # haría creer que falta compilar la plantilla de corrección.
        report = self.export()
        self.assertTrue(all("teacher" not in name and "solutions" not in name
                            for name in report["missing"]))

    def test_the_way_the_app_asks_for_one_document(self):
        # Los posicionales juntos detrás de `--`. Con el curso delante de las
        # opciones y los documentos detrás, argparse rechazaba los segundos,
        # y exportar desde la aplicación fallaba siempre.
        code, output = self.capture(
            "export", "--to", self.to, "--language", "es",
            "--reveal-up-to", "answers", "--json",
            "--", "mates@2024-2025", "tema-1")
        self.assertEqual(code, 0, output)
        self.assertEqual(len(json.loads(output)["copied"]), 2)

    def test_nothing_withheld_ends_up_in_the_folder(self):
        self.export()
        found = []
        for _, _, files in os.walk(self.to):
            found.extend(files)
        self.assertFalse([name for name in found
                          if "profesor" in name or "soluciones" in name],
                         found)

    def test_the_names_are_said_in_the_language_of_the_export(self):
        # «Tema 1 - Diapositivas.pdf» y no «Tema 1 - slides - es.pdf»: lo lee
        # un estudiante, y el idioma ya lo dice la carpeta.
        report = self.export("--reveal-up-to", "teacher")
        names = sorted(os.path.basename(path) for path in report["copied"])
        self.assertIn("Tema 1 - Diapositivas.pdf", names)
        self.assertIn("Tema 1 - Diapositivas (profesor).pdf", names)
        self.assertIn("Tema 1 - Apuntes (con soluciones).pdf", names)
        self.assertFalse([name for name in names if " - es" in name], names)

    def test_a_zip_with_everything_for_the_virtual_classroom(self):
        import zipfile

        archive = os.path.join(self.root, "Mates 2024-2025.zip")
        report = self.export("--zip", archive)
        self.assertEqual(report["zip"], archive)
        with zipfile.ZipFile(archive) as opened:
            self.assertEqual(sorted(opened.namelist()),
                             sorted(path.replace(os.sep, "/")
                                    for path in report["copied"]))
        # Una segunda pasada --otro repositorio de la misma asignatura-- se
        # añade sin repetir; sin `--zip-append`, se rehace.
        self.export("--zip", archive, "--zip-append",
                    "--reveal-up-to", "teacher")
        with zipfile.ZipFile(archive) as opened:
            self.assertEqual(len(opened.namelist()), len(self.PROFILES))
        self.export("--zip", archive)
        with zipfile.ZipFile(archive) as opened:
            self.assertEqual(len(opened.namelist()), 2)


class StaleDocumentTests(unittest.TestCase):
    """Cuándo `built` da por viejo el PDF de un documento.

    Antes solo miraba la composición --el `.tex` del documento y el
    `year.yaml`--, así que corregir una lección dejaba el PDF del tema que la
    lleva «al día» y se podía proyectar el de antes sin que nada lo dijera. Lo
    que se comprueba es que las lecciones cuentan, en su idioma y con sus
    figuras, y que lo que no cambia el PDF no lo deja viejo.
    """

    run_cli = BuildInterfaceTests.run_cli
    capture = BuildInterfaceTests.capture

    def setUp(self):
        BuildInterfaceTests.setUp(self)
        self.lesson = os.path.join(self.root, "content", "a", "b", "c")
        year = os.path.join(self.root, "courses", "mates", "2024-2025")
        all_profiles = self.cli.profiles_mod.load(self.cli.LATEX_DIR)
        engine = self.cli.build_mod.Engine(
            latex_dir=self.cli.LATEX_DIR,
            build_dir=os.path.join(self.root, ".build"),
            template_dirs=[self.root],
            settings=self.cli.repo_mod.Settings.load(self.root),
        )
        folder = engine.output_dir("mates@2024-2025/tema-1", "slides", "es")
        os.makedirs(folder, exist_ok=True)
        self.pdf = os.path.join(
            folder, all_profiles["slides"].output_name("Tema 1", "es") + ".pdf")
        with open(self.pdf, "wb") as handle:
            handle.write(b"%PDF-1.4\n")

        # Todo lo de antes, de hace una hora; el PDF, de hace media.
        self.before = 1_700_000_000
        for directory in (self.lesson, year):
            for name in os.listdir(directory):
                os.utime(os.path.join(directory, name),
                         (self.before, self.before))
        os.utime(self.pdf, (self.before + 1800, self.before + 1800))

    def later(self, path):
        """Como si se hubiera guardado después de compilar."""
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if not os.path.exists(path):
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("x\n")
        os.utime(path, (self.before + 3600, self.before + 3600))

    def stale(self):
        code, output = self.capture("built", "mates@2024-2025", "--json")
        self.assertEqual(code, 0, output)
        outputs = json.loads(output)["documents"][0]["outputs"]
        return [o["stale"] for o in outputs if o["language"] == "es"][0]

    def test_recien_compilado_esta_al_dia(self):
        self.assertFalse(self.stale())

    def test_corregir_una_leccion_lo_deja_viejo(self):
        self.later(os.path.join(self.lesson, "es.tex"))
        self.assertTrue(self.stale())

    def test_una_figura_nueva_tambien(self):
        self.later(os.path.join(self.lesson, "figures", "norma.pdf"))
        self.assertTrue(self.stale())

    def test_otro_idioma_de_la_leccion_no(self):
        # El PDF en castellano no lleva el valenciano.
        self.later(os.path.join(self.lesson, "va.tex"))
        self.assertFalse(self.stale())

    def test_aprobar_una_traduccion_no(self):
        # `unit.yaml` cambia de estado, no de texto: el PDF es el mismo.
        self.later(os.path.join(self.lesson, "unit.yaml"))
        self.assertFalse(self.stale())

    def test_una_leccion_llamada_por_id_tambien_cuenta(self):
        year = os.path.join(self.root, "courses", "mates", "2024-2025",
                            "year.yaml")
        with open(year, encoding="utf-8") as handle:
            text = handle.read()
        with open(year, "w", encoding="utf-8") as handle:
            handle.write(text.replace("- unit: a/b/c", "- unit: a.b.c"))
        os.utime(year, (self.before, self.before))
        self.later(os.path.join(self.lesson, "es.tex"))
        self.assertTrue(self.stale())

    def test_la_composicion_sigue_contando(self):
        self.later(os.path.join(self.root, "courses", "mates", "2024-2025",
                                "year.yaml"))
        self.assertTrue(self.stale())


class DuplicateUnitTests(unittest.TestCase):
    """`new unit --from`: una lección que empieza siendo una copia de otra.

    Lo que importa es que sean dos lecciones --id propio, carpeta propia-- y
    que el título nuevo quede puesto en su idioma sin tocar los demás ni el
    resto del `unit.yaml`.
    """

    def setUp(self):
        import shutil
        import tempfile

        self.cli = load_cli()
        self.root = tempfile.mkdtemp(prefix="didacta-duplicate-")
        self.addCleanup(shutil.rmtree, self.root, True)
        self.source = os.path.join(self.root, "content", "a", "b", "c")
        os.makedirs(os.path.join(self.source, "figures"))
        self.write("es.tex", "%% Uno\n\\begin{frame}\n\\didactatitle{Uno}\n"
                   "Texto.\n\\end{frame}\n")
        self.write("va.tex", "\\didactatitle{U}\nText.\n")
        self.write("figures/f.pdf", "pdf")
        self.write("unit.yaml",
                   "# Uno\n\n# Un comentario que no se pierde.\n"
                   "id: a.b.c\nkind: theory\ntitle:\n  es: Uno\n  va: U\n\n"
                   "category: a\ntopic: b\nreference: es\n"
                   "languages:\n  es: {status: draft}\n"
                   "  va: {status: translated}\n")
        with open(os.path.join(self.root, "didacta.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("name: Prueba\nlanguages: [es, va, en]\n"
                         "default_language: es\nbuild_dir: .build\n")

    def write(self, name, text):
        with open(os.path.join(self.source, name), "w",
                  encoding="utf-8") as handle:
            handle.write(text)

    def read(self, *parts):
        with open(os.path.join(self.root, *parts), encoding="utf-8") as handle:
            return handle.read()

    def run_cli(self, *args):
        return self.cli.main(["--root", self.root, *args])

    def test_copia_la_carpeta_con_un_id_nuevo(self):
        self.assertEqual(
            self.run_cli("new", "unit", "--from", "content/a/b/c",
                         "--title", "Dos", "--", "a/b/dos"), 0)
        copy = ("content", "a", "b", "dos")
        self.assertTrue(os.path.isfile(os.path.join(self.root, *copy,
                                                    "figures", "f.pdf")))
        meta = self.read(*copy, "unit.yaml")
        self.assertNotIn("id: a.b.c", meta)
        self.assertRegex(meta, r"(?m)^id: u-[0-9a-f]+$")
        # La original, intacta.
        self.assertIn("id: a.b.c", self.read("content", "a", "b", "c",
                                             "unit.yaml"))

    def test_el_titulo_nuevo_en_su_idioma_y_nada_mas(self):
        self.run_cli("new", "unit", "--from", "content/a/b/c",
                     "--title", "Dos: la vuelta", "--", "a/b/dos")
        meta = self.read("content", "a", "b", "dos", "unit.yaml")
        self.assertIn('  es: "Dos: la vuelta"\n  va: U\n', meta)
        self.assertTrue(meta.startswith("# Dos: la vuelta\n"))
        self.assertIn("# Un comentario que no se pierde.", meta)
        self.assertIn("va: {status: translated}", meta)
        tex = self.read("content", "a", "b", "dos", "es.tex")
        self.assertIn("\\didactatitle{Dos: la vuelta}", tex)
        self.assertTrue(tex.startswith("%% Dos: la vuelta\n"))
        self.assertIn("\\didactatitle{U}",
                      self.read("content", "a", "b", "dos", "va.tex"))

    def test_por_id_tambien(self):
        self.assertEqual(
            self.run_cli("new", "unit", "--from", "a.b.c", "--", "a/b/tres"), 0)
        self.assertIn("es: Uno", self.read("content", "a", "b", "tres",
                                          "unit.yaml"))

    def test_no_pisa_lo_que_ya_hay(self):
        self.assertEqual(
            self.run_cli("new", "unit", "--from", "content/a/b/c", "--",
                         "a/b/c"), 1)

    def test_una_leccion_que_no_existe(self):
        self.assertEqual(
            self.run_cli("new", "unit", "--from", "content/x/y/z", "--",
                         "a/b/dos"), 1)


class TitleEditingTests(unittest.TestCase):
    """Los dos editores por líneas que usa `new unit --from`."""

    def setUp(self):
        from didacta import identity

        self.identity = identity

    def test_un_titulo_en_bloque_se_edita_en_su_sitio(self):
        text = "title:\n  es: Uno\n  va: U\n\ncategory: a\n"
        self.assertEqual(
            self.identity.set_unit_title(text, "va", "Dos"),
            "title:\n  es: Uno\n  va: Dos\n\ncategory: a\n")

    def test_un_idioma_que_no_tenia_titulo_se_anade(self):
        text = "title:\n  es: Uno\ncategory: a\n"
        self.assertEqual(
            self.identity.set_unit_title(text, "en", "One"),
            "title:\n  es: Uno\n  en: One\ncategory: a\n")

    def test_un_escalar_se_reescribe_en_bloque_sin_perder_los_demas(self):
        text = "title: Uno\ncategory: a\n"
        self.assertEqual(
            self.identity.set_unit_title(text, "es", "Dos",
                                         {"es": "Uno", "va": "Uno"}),
            "title:\n  es: Dos\n  va: Uno\ncategory: a\n")

    def test_sin_titulo_va_delante_de_la_categoria(self):
        self.assertEqual(
            self.identity.set_unit_title("id: x\ncategory: a\n", "es", "Uno"),
            "id: x\ntitle:\n  es: Uno\n\ncategory: a\n")

    def test_las_barras_de_latex_se_escapan(self):
        self.assertIn(
            'es: "El espacio \\\\(L^p\\\\)"',
            self.identity.set_unit_title("title:\n  es: X\n", "es",
                                         "El espacio \\(L^p\\)"))

    def test_el_tex_solo_donde_aparece_tal_cual(self):
        retitle = self.identity.retitle_tex
        self.assertEqual(
            retitle("\\begin{exercise}[Uno]\nUno.\n", "Uno", "Dos"),
            "\\begin{exercise}[Dos]\nUno.\n")
        self.assertEqual(retitle("Sin título.\n", "Uno", "Dos"),
                         "Sin título.\n")


class MoveUnitCliTests(unittest.TestCase):
    """`move --unit`: la orden, con el `.tex` del documento puesto al día."""

    def setUp(self):
        import shutil
        import tempfile

        self.cli = load_cli()
        self.root = tempfile.mkdtemp(prefix="didacta-move-")
        self.addCleanup(shutil.rmtree, self.root, True)
        files = {
            "didacta.yaml": "name: P\nlanguages: [es]\ndefault_language: es\n",
            "content/a/b/c/unit.yaml": "kind: theory\ntitle:\n  es: C\n",
            "content/a/b/c/es.tex": "texto\n",
            "courses/m/course.yaml": "id: m\ntitle:\n  es: M\n",
            "courses/m/2025-2026/year.yaml":
                "course: m\nyear: 2025-2026\nlanguage: es\n\n"
                "documents:\n  - id: t1\n    kind: theory\n"
                "    title:\n      es: T1\n    structure:\n"
                "      - unit: a/b/c\n",
            "courses/m/2025-2026/t1.tex":
                "\\input{didacta-bootstrap}\n\\usepackage{didacta}\n"
                "\\DidactaDocument{T1}\n\\begin{document}\n"
                "\\DidactaUnit{a/b/c}\n\\end{document}\n",
        }
        for relpath, text in files.items():
            path = os.path.join(self.root, relpath)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)

    def read(self, relpath):
        with open(os.path.join(self.root, relpath), encoding="utf-8") as handle:
            return handle.read()

    def test_mueve_y_recompone(self):
        self.assertEqual(
            self.cli.main(["--root", self.root, "move", "--unit", "a/b/c",
                           "--to", "a/nuevo/c"]), 0)
        self.assertIn("- unit: a/nuevo/c",
                      self.read("courses/m/2025-2026/year.yaml"))
        master = self.read("courses/m/2025-2026/t1.tex")
        self.assertIn("a/nuevo/c", master)
        self.assertNotIn("{a/b/c}", master)

    def test_sin_from_ni_unit(self):
        self.assertEqual(
            self.cli.main(["--root", self.root, "move", "--to", "m@2026-2027"]),
            1)
