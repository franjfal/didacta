"""Las titulaciones: agrupar asignaturas sin poder romper nada.

Un grado agrupa asignaturas, así que vive en la raíz del repositorio y no
dentro de una. Sigue el patrón de los temas, que es el que sostiene todo lo
que se comparte entre repositorios: **la asignatura nombra el grado y el grado
lo declara quien lo tenga**.

De ahí la propiedad que lo hace aceptable, y que es lo que más se prueba aquí:
una asignatura que nombra un grado que este repositorio no declara **sale
igual**, sin agrupar pero entera. Nadie se queda sin ver su material por no
tener el repositorio donde alguien puso un título.

Y el otro cuidado: el `degree:` que ya había en `course.yaml` es texto que se
imprime en la portada, no un id. Aceptar un id ahí habría convertido un
`degree: Grado en Matemáticas` que existe hoy en una referencia a un grado
llamado así --datos reales, rotos en silencio, por ahorrarse una clave--.
"""

from __future__ import annotations

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

DEMO = os.path.join(ROOT, "examples", "demo-course")

DEGREES = """\
degrees:
  - id: matematicas
    title:
      es: Grado en Matemáticas
      va: Grau en Matemàtiques
    institution: Universitat de València

  - id: fisica
    title:
      es: Grado en Física
"""


class Harness(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="didacta-degrees-")
        self.root = os.path.join(self.tmp, "repo")
        shutil.copytree(DEMO, self.root)
        self.settings = repo_mod.Settings.load(self.root)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_degrees(self, text=DEGREES):
        with open(os.path.join(self.root, "degrees.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(text)

    def course_path(self):
        base = os.path.join(self.root, "courses")
        name = sorted(os.listdir(base))[0]
        return os.path.join(base, name, "course.yaml")

    def set_course(self, **fields):
        """Añade claves al `course.yaml` de la primera asignatura."""
        path = self.course_path()
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for key, value in fields.items():
            text += "\n%s: %s\n" % (key, value)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def courses(self):
        degrees = repo_mod.load_degrees(self.root, self.settings)
        found, errors = repo_mod.scan_courses(self.root, self.settings, degrees)
        self.assertEqual(errors, [])
        return found


class Loading(Harness):
    def test_no_file_means_no_degrees(self):
        # Agrupar por grado es opcional: un repositorio que no lo hace
        # funciona exactamente como antes de que existieran.
        self.assertEqual(repo_mod.load_degrees(self.root, self.settings), {})

    def test_they_come_back_with_their_titles(self):
        self.write_degrees()
        degrees = repo_mod.load_degrees(self.root, self.settings)
        self.assertEqual(sorted(degrees), ["fisica", "matematicas"])
        self.assertEqual(degrees["matematicas"].title("va"),
                         "Grau en Matemàtiques")
        self.assertEqual(degrees["matematicas"].institution,
                         "Universitat de València")

    def test_a_title_falls_back_before_showing_the_id(self):
        self.write_degrees()
        degrees = repo_mod.load_degrees(self.root, self.settings)
        # Sin inglés, se enseña el que haya. Un slug en una lista de grados no
        # le dice nada a nadie.
        self.assertEqual(degrees["fisica"].title("en"), "Grado en Física")

    def test_a_degree_without_an_id_is_refused(self):
        self.write_degrees("degrees:\n  - title:\n      es: Sin id\n")
        with self.assertRaises(repo_mod.RepoError):
            repo_mod.load_degrees(self.root, self.settings)

    def test_two_degrees_with_the_same_id_are_refused(self):
        self.write_degrees(
            "degrees:\n"
            "  - id: uno\n    title:\n      es: Uno\n"
            "  - id: uno\n    title:\n      es: Otro\n"
        )
        with self.assertRaises(repo_mod.RepoError):
            repo_mod.load_degrees(self.root, self.settings)


class Naming(Harness):
    def test_a_course_can_name_its_degree(self):
        self.write_degrees()
        self.set_course(degree_id="matematicas")
        course = next(iter(self.courses().values()))
        self.assertEqual(course.degree, "matematicas")
        self.assertEqual(course.degrees["es"], "Grado en Matemáticas")

    def test_naming_one_nobody_declares_is_not_an_error(self):
        # **La prueba que sostiene el diseño.** La asignatura sale entera; lo
        # único que no pasa es que se agrupe. Quien tenga el repositorio donde
        # está declarado la verá agrupada, y quien no, la verá como siempre.
        self.set_course(degree_id="un-grado-de-otro-repositorio")
        courses = self.courses()
        course = next(iter(courses.values()))

        # El id se conserva, para cuando aparezca el repositorio que lo
        # declara: perderlo obligaría a volver a ponerlo a mano.
        self.assertEqual(course.degree, "un-grado-de-otro-repositorio")
        # Y no se toca nada de lo que la asignatura ya tenía. Aquí eso es el
        # `degree:` escrito a mano del curso de ejemplo: nombrar un grado que
        # no existe no puede borrar el título que ya se imprimía.
        self.assertTrue(course.degrees)
        self.assertTrue(course.years, "la asignatura sigue entera")

    def test_and_the_title_appears_when_the_other_repository_shows_up(self):
        # La otra mitad de lo mismo: en cuanto alguien declara el grado, la
        # asignatura se agrupa sin tocar su `course.yaml`.
        self.set_course(degree_id="matematicas")
        without = next(iter(self.courses().values()))
        self.write_degrees()
        with_registry = next(iter(self.courses().values()))

        self.assertEqual(without.degree, with_registry.degree)
        self.assertEqual(with_registry.degrees["es"], "Grado en Matemáticas")

    def test_a_course_without_a_degree_still_loads(self):
        self.write_degrees()
        course = next(iter(self.courses().values()))
        self.assertIsNone(course.degree)

    def test_the_registry_wins_over_the_text_written_by_hand(self):
        # Con dos títulos para el mismo grado, el que vale es el que comparten
        # los repositorios. `check` avisa de que el texto sobra.
        self.write_degrees()
        self.set_course(degree_id="matematicas")
        path = self.course_path()
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("\ndegree:\n  es: Lo que puso alguien\n")
        course = next(iter(self.courses().values()))
        self.assertEqual(course.degrees["es"], "Grado en Matemáticas")

    def test_the_old_free_text_degree_still_works(self):
        # Es lo que hay hoy en los repositorios de verdad, y no puede dejar de
        # funcionar por añadir un registro.
        path = self.course_path()
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("\ndegree:\n  es: Grado en Matemáticas\n")
        course = next(iter(self.courses().values()))
        self.assertIsNone(course.degree)
        self.assertEqual(course.degrees["es"], "Grado en Matemáticas")

    def test_a_plain_string_degree_is_not_read_as_an_id(self):
        # El fallo que la clave aparte existe para evitar: `degree: Grado en
        # Matemáticas` es un título, no una referencia.
        path = self.course_path()
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("\ndegree: Grado en Matemáticas\n")
        course = next(iter(self.courses().values()))
        self.assertIsNone(course.degree)
        self.assertEqual(course.degrees["es"], "Grado en Matemáticas")


class TheIndex(Harness):
    def test_the_degrees_are_published_for_the_interface(self):
        self.write_degrees()
        self.set_course(degree_id="matematicas")
        data = index_mod.build(self.root, self.settings)
        degrees = data[index_mod.COURSES]["degrees"]
        self.assertEqual([d["id"] for d in degrees], ["fisica", "matematicas"])

        course = data[index_mod.COURSES]["courses"][0]
        self.assertEqual(course["degreeId"], "matematicas")
        self.assertEqual(course["degree"]["es"], "Grado en Matemáticas")

    def test_without_a_file_the_index_still_has_the_key(self):
        # Para que quien lo lee no tenga que distinguir «no hay grados» de
        # «este índice es de antes de que existieran».
        data = index_mod.build(self.root, self.settings)
        self.assertEqual(data[index_mod.COURSES]["degrees"], [])

    def test_a_course_with_no_degree_says_so(self):
        data = index_mod.build(self.root, self.settings)
        self.assertIsNone(data[index_mod.COURSES]["courses"][0]["degreeId"])

    def test_a_broken_degrees_file_is_reported_not_swallowed(self):
        self.write_degrees("degrees: no es una lista\n")
        data = index_mod.build(self.root, self.settings)
        self.assertTrue(data[index_mod.MANIFEST]["errors"])


if __name__ == "__main__":
    unittest.main()
