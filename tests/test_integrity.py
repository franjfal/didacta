"""Las comprobaciones que evitan que el modelo se rompa en silencio.

Nada de esto se ve mirando un fichero: son las preguntas que solo tienen
respuesta leyendo el repositorio entero, y son justo las que rompen sin dar
ningún síntoma hasta que alguien intenta compilar tres meses después.

Se prueban contra `didacta check` de verdad, con el proceso: lo que importa
no es que una función devuelva una lista, sino que **alguien lo lea** en la
salida, y el formato de la salida es parte de eso.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
CLI = os.path.join(ROOT, "cli", "didacta")


def check(where):
    environment = dict(os.environ)
    environment["NO_COLOR"] = "1"
    result = subprocess.run(
        [sys.executable, CLI, "check"], cwd=where, env=environment,
        capture_output=True, text=True,
    )
    return result.returncode, result.stdout


class IntegrityTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-check-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("didacta.yaml", "languages: [es]\ndefault_language: es\n")
        self.write("courses/am-i/course.yaml", "id: am-i\ntitle:\n  es: AM I\n")
        for name in ("a/b/c", "a/b/d"):
            self.write("content/%s/unit.yaml" % name,
                       "id: u-%s\nkind: theory\ntitle:\n  es: %s\n"
                       % ("0" * 11 + name[-1], name))
            self.write("content/%s/es.tex" % name, "texto\n")
        self.write(
            "courses/am-i/2026-2027/year.yaml",
            "course: am-i\nyear: 2026-2027\nlanguage: es\n\n"
            "documents:\n"
            "  - id: tema-1\n"
            "    kind: theory\n"
            "    title:\n"
            "      es: Tema 1\n"
            "    structure:\n"
            "      - unit: a/b/c\n",
        )
        self.write(
            "courses/am-i/2026-2027/tema-1.tex",
            "\\input{didacta-bootstrap}\n\\usepackage{didacta}\n"
            "\\begin{document}\n\\DidactaUnit{a/b/c}\n\\end{document}\n",
        )

    def write(self, relpath, text):
        path = os.path.join(self.root, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def read(self, relpath):
        with open(os.path.join(self.root, relpath), encoding="utf-8") as handle:
            return handle.read()

    def test_a_healthy_repository_is_consistent(self):
        code, output = check(self.root)
        self.assertEqual(code, 0, output)
        self.assertIn("repository is consistent", output)

    def test_two_lessons_with_the_same_id_is_an_error(self):
        """Dos entidades compartiendo identidad: a partir de ahí, «esto dónde
        más está» contesta cualquier cosa."""
        self.write("content/a/b/d/unit.yaml",
                   "id: u-00000000000c\nkind: theory\ntitle:\n  es: d\n")
        code, output = check(self.root)
        self.assertEqual(code, 1)
        self.assertIn("duplicate unit id `u-00000000000c`", output)
        self.assertIn("content/a/b/c", output)
        self.assertIn("content/a/b/d", output)

    def test_a_link_to_a_content_that_is_not_there_is_an_error(self):
        self.write(
            "courses/am-i/2026-2027/year.yaml",
            "course: am-i\nyear: 2026-2027\nlanguage: es\n\n"
            "documents:\n"
            "  - id: tema-1\n"
            "    link: d-aaaaaaaaaaaa\n",
        )
        code, output = check(self.root)
        self.assertEqual(code, 1)
        self.assertIn("d-aaaaaaaaaaaa", output)
        self.assertIn("si está en otro repositorio, ábrelo", output)

    def test_two_documents_with_the_same_id_in_one_year_is_an_error(self):
        """Los dos compilan al mismo `.tex`: uno se escribe encima del otro."""
        self.write(
            "courses/am-i/2026-2027/year.yaml",
            self.read("courses/am-i/2026-2027/year.yaml")
            + "\n"
            "  - id: tema-1\n"
            "    kind: handout\n"
            "    title:\n"
            "      es: Otro tema 1\n"
            "    structure:\n"
            "      - unit: a/b/d\n",
        )
        code, output = check(self.root)
        self.assertEqual(code, 1)
        self.assertIn("está declarado 2 veces", output)

    def test_a_shared_file_that_links_further_is_an_error(self):
        """Un tema compartido es el final de la cadena, no otro eslabón: sin
        esto, un fichero editado a mano podría cerrar un ciclo."""
        self.write("shared/documents/d-bbbbbbbbbbbb.yaml",
                   "id: d-bbbbbbbbbbbb\nlink: d-cccccccccccc\nkind: theory\n")
        code, output = check(self.root)
        self.assertEqual(code, 1)
        self.assertIn("es el final de la cadena", output)

    def test_a_shared_file_whose_name_and_id_disagree_is_an_error(self):
        self.write("shared/documents/d-bbbbbbbbbbbb.yaml",
                   "id: d-dddddddddddd\nkind: theory\n")
        code, output = check(self.root)
        self.assertEqual(code, 1)
        self.assertIn("el nombre del fichero y el id tienen que ser el mismo",
                      output)

    def test_a_shared_file_nobody_gives_is_only_a_warning(self):
        """No rompe nada: casi siempre es el resto de una división."""
        self.write("shared/documents/d-eeeeeeeeeeee.yaml",
                   "id: d-eeeeeeeeeeee\nkind: theory\ntitle:\n  es: Suelto\n")
        code, output = check(self.root)
        self.assertEqual(code, 0)
        self.assertIn("no lo da ningún curso", output)

    def test_a_group_of_one_is_pointed_out_but_is_not_an_error(self):
        self.write("shared/documents/d-ffffffffffff.yaml",
                   "id: d-ffffffffffff\nkind: theory\ntitle:\n  es: Tema 1\n"
                   "structure:\n  - unit: a/b/c\n")
        self.write(
            "courses/am-i/2026-2027/year.yaml",
            "course: am-i\nyear: 2026-2027\nlanguage: es\n\n"
            "documents:\n"
            "  - id: tema-1\n"
            "    link: d-ffffffffffff\n",
        )
        code, output = check(self.root)
        self.assertEqual(code, 0)
        self.assertIn("un grupo de uno no es un grupo", output)

    def test_lessons_without_an_id_are_pointed_out(self):
        self.write("content/a/b/d/unit.yaml",
                   "kind: theory\ntitle:\n  es: d\n")
        code, output = check(self.root)
        self.assertEqual(code, 0)
        self.assertIn("sin id estable", output)
        self.assertIn("didacta ids --apply", output)

    def test_a_broken_freeze_is_reported_rather_than_guessed_at(self):
        self.write("courses/am-i/2026-2027/freezes.yaml",
                   "freezes:\n  - id: f-000000000001\n    name: Rota\n"
                   "    commit: main\n")
        code, output = check(self.root)
        self.assertEqual(code, 1)
        self.assertIn("SHA de 40 caracteres", output)

    def test_a_broken_freeze_does_not_take_the_course_down(self):
        """Es metadatos sobre commits, no el material.

        Un fichero mal escrito a mano tiene que dejar la asignatura entera sin
        abrir tan poco como un tema que declara otro repositorio. Antes se
        llevaba por delante el escaneo completo, y la aplicación se quedaba
        sin catálogo por una línea.
        """
        self.write("courses/am-i/2026-2027/freezes.yaml",
                   "freezes:\n  - id: f-000000000001\n    name: Rota\n"
                   "    commit: main\n")
        environment = dict(os.environ)
        environment["NO_COLOR"] = "1"
        result = subprocess.run(
            [sys.executable, CLI, "status"], cwd=self.root, env=environment,
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("am-i", result.stdout)

    def test_two_freezes_with_the_same_id_is_an_error(self):
        sha = "a" * 40
        self.write(
            "courses/am-i/2026-2027/freezes.yaml",
            "freezes:\n"
            "  - id: f-000000000001\n    name: Una\n    commit: %s\n"
            "  - id: f-000000000001\n    name: Otra\n    commit: %s\n"
            % (sha, sha),
        )
        # Error y no aviso: la segunda es inalcanzable --abrirla abre la
        # primera-- y quitarla se llevaría las dos.
        code, output = check(self.root)
        self.assertEqual(code, 1)
        self.assertIn("dos congelaciones con el id", output)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
