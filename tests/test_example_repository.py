"""El repositorio de ejemplo que trae la aplicación.

`app/assets/ejemplo/` es lo primero que ve de Didacta alguien que no lo
conoce: la aplicación lo empaqueta y, cuando se pulsa «Probar con un
ejemplo», lo sube tal cual como primer commit de un repositorio nuevo. Así que
tiene que abrir limpio -- sin un solo error en el índice, sin referencias
rotas -- y tiene que seguir enseñando lo que está ahí para enseñar: una
lección reutilizada en dos documentos, traducciones hechas y pendientes, una
lección que el curso no usa.

Nada de esto compila LaTeX: lo que se comprueba es lo que el motor lee.
"""

from __future__ import annotations

import glob
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import compose as compose_mod  # noqa: E402
from didacta import identity as identity_mod  # noqa: E402
from didacta import index as index_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402
from didacta import yamlio  # noqa: E402

EXAMPLE = os.path.join(ROOT, "app", "assets", "ejemplo")
LATEX = os.path.join(ROOT, "latex")

COURSE = "calculo-i"
YEAR = "2026-2027"


class ExampleRepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.settings = repo_mod.Settings.load(EXAMPLE)
        cls.units, cls.unit_errors = repo_mod.scan_units(EXAMPLE, cls.settings)
        cls.courses, cls.course_errors = repo_mod.scan_courses(
            EXAMPLE, cls.settings)
        cls.data = index_mod.build(EXAMPLE, cls.settings, latex_dir=LATEX)
        cls.manifest = cls.data[index_mod.MANIFEST]
        cls.records = {record["path"]: record
                       for record in cls.data[index_mod.UNITS]["units"]}

    def year(self):
        return self.courses[COURSE].years[YEAR]

    def document(self, identifier):
        return next(d for d in self.year().documents if d.id == identifier)

    # -- abre limpio -----------------------------------------------------

    def test_it_is_a_repository_with_its_own_settings(self):
        self.assertEqual(repo_mod.find_root(EXAMPLE), EXAMPLE)
        self.assertEqual(self.settings.name, "Ejemplo de Didacta")
        self.assertEqual(self.settings.languages, ["es", "va", "en"])
        self.assertEqual(self.settings.default_language, "es")

    def test_the_index_has_no_errors(self):
        self.assertEqual(self.unit_errors, [])
        self.assertEqual(self.course_errors, [])
        self.assertEqual(self.manifest["errors"], [])

    def test_no_unit_carries_a_warning(self):
        warned = {path: record["warnings"]
                  for path, record in self.records.items()
                  if record["warnings"]}
        self.assertEqual(warned, {})

    def test_both_yaml_readers_read_every_file_the_same(self):
        # La aplicación puede llevar un Python sin PyYAML, y entonces lee el
        # lector propio del motor. Un fichero que solo entiende uno de los
        # dos abre en una máquina y no en otra.
        paths = glob.glob(os.path.join(EXAMPLE, "**", "*.yaml"),
                          recursive=True)
        self.assertTrue(paths)
        for path in paths:
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            with self.subTest(path=os.path.relpath(path, EXAMPLE)):
                subset = yamlio._loads_subset(text)
                self.assertIsInstance(subset, dict)
                if yamlio._pyyaml is not None:
                    self.assertEqual(subset, yamlio._pyyaml.safe_load(text))

    # -- la asignatura ---------------------------------------------------

    def test_the_course_has_its_year_and_its_documents(self):
        self.assertEqual(set(self.courses), {COURSE})
        course = self.courses[COURSE]
        self.assertEqual(set(course.titles), {"es", "va", "en"})
        self.assertEqual(course.language, "es")
        self.assertEqual(list(course.years), [YEAR])
        self.assertEqual(
            [(d.id, d.kind) for d in self.year().documents],
            [("tema-1", "theory"), ("hoja-1", "problems"),
             ("parcial-1", "exam")],
        )

    def test_every_document_has_its_tex_and_its_titles(self):
        for document in self.year().documents:
            with self.subTest(document=document.id):
                self.assertIsNotNone(document.source)
                self.assertTrue(os.path.isfile(document.source))
                self.assertEqual(set(document.titles), {"es", "va", "en"})

    def test_every_declared_output_is_a_real_profile(self):
        known = profiles_mod.load(LATEX)
        for document in self.year().documents:
            with self.subTest(document=document.id):
                self.assertTrue(document.profiles)
                for name in document.profiles:
                    self.assertIn(name, known)

    def test_the_tex_already_says_what_year_yaml_says(self):
        # Si no, la primera compilación reescribiría el `.tex`, y quien
        # acaba de crear su repositorio de ejemplo se encontraría un cambio
        # sin confirmar que no ha hecho.
        year_path = os.path.join(self.year().directory, repo_mod.YEAR_META)
        for document in self.year().documents:
            with self.subTest(document=document.id):
                result = compose_mod.compose_document(
                    document, year_path, write=False)
                self.assertIsNone(result.refused)
                self.assertFalse(result.changed)

    # -- las lecciones ---------------------------------------------------

    def test_every_referenced_unit_exists_in_the_right_tree(self):
        for document in self.year().documents:
            for step in document.structure:
                if "unit" in step:
                    ref, area = step["unit"], repo_mod.CONTENT
                elif "problem" in step:
                    ref, area = step["problem"], repo_mod.PROBLEMS
                else:
                    continue
                with self.subTest(document=document.id, ref=ref):
                    unit = repo_mod.resolve_unit_ref(ref, self.units, EXAMPLE)
                    self.assertIsNotNone(unit)
                    self.assertEqual(unit.area, area)
                    self.assertEqual(unit.is_problem,
                                     area == repo_mod.PROBLEMS)

    def test_every_prerequisite_is_a_unit_of_the_example(self):
        for unit in self.units.values():
            for prerequisite in unit.prerequisites:
                with self.subTest(unit=unit.relpath, prerequisite=prerequisite):
                    self.assertIsNotNone(repo_mod.resolve_unit_ref(
                        prerequisite, self.units, EXAMPLE))

    def test_every_unit_has_a_stable_id(self):
        for unit in self.units.values():
            with self.subTest(unit=unit.relpath):
                self.assertTrue(identity_mod.is_id(unit.raw.get("id")))

    def test_the_taxonomy_names_every_category_and_topic(self):
        taxonomy = repo_mod.Taxonomy.load(EXAMPLE, self.settings)
        self.assertTrue(taxonomy.declared)
        for unit in self.units.values():
            with self.subTest(unit=unit.relpath):
                category = taxonomy.category(unit.category)
                self.assertIsNotNone(category)
                self.assertIsNotNone(category.topic(unit.topic))

    # -- lo que está ahí para enseñarse ----------------------------------

    def test_a_problem_is_reused_in_the_sheet_and_in_the_exam(self):
        sheet = set(self.document("hoja-1").unit_refs)
        exam = set(self.document("parcial-1").unit_refs)
        self.assertTrue(exam)
        self.assertLessEqual(exam, sheet)

    def test_one_unit_is_in_the_library_and_in_no_document(self):
        unused = [path for path, record in self.records.items()
                  if not record["usedBy"]]
        self.assertEqual(unused, ["content/calculo/limites/concepto-de-limite/historia-del-epsilon"])

    def test_the_translation_queue_has_real_work_in_it(self):
        status = {path: {code: entry["status"]
                         for code, entry in record["languages"].items()}
                  for path, record in self.records.items()}
        # Todo existe en castellano, que es el original.
        self.assertTrue(all(s["es"] == "source" for s in status.values()))
        # Casi todo está en valenciano, y falta algo.
        missing_va = [p for p, s in status.items() if s["va"] == "missing"]
        self.assertTrue(missing_va)
        self.assertLess(len(missing_va), len(status) / 2)
        # Del inglés, casi nada.
        done_en = [p for p, s in status.items() if s["en"] != "missing"]
        self.assertTrue(done_en)
        self.assertLess(len(done_en), len(status) / 2)

    def test_a_valencian_translation_is_missing_in_a_reused_problem(self):
        # Es la que encabeza la cola de Traducción, que se ordena por cuántos
        # documentos usan cada lección.
        record = self.records[
            "problems/calculo/continuidad/bolzano/tres-raices-por-bolzano"]
        self.assertEqual(record["languages"]["va"]["status"], "missing")
        self.assertEqual(len(record["usedBy"]), 2)

    # -- nada derivado dentro de los assets -------------------------------

    def test_nothing_compiled_is_shipped(self):
        self.assertFalse(os.path.exists(
            os.path.join(EXAMPLE, self.settings.build_dir)))

    def test_the_shipped_index_is_current(self):
        # `generated/` va dentro, como en cualquier repositorio de contenido:
        # se versiona. Sin él, el primer índice que hiciera la aplicación
        # dejaría ficheros nuevos sin confirmar en un repositorio recién
        # creado, que es lo último que tiene que ver quien lo prueba. Y tiene
        # que describir lo que hay: uno viejo es una biblioteca que no cuadra
        # con los ficheros. Tras tocar el ejemplo:
        #
        #     cli/didacta --root app/assets/ejemplo index
        self.assertTrue(
            os.path.isdir(os.path.join(EXAMPLE, index_mod.GENERATED)),
            "el ejemplo tiene que llevar generated/",
        )
        self.assertTrue(index_mod.unchanged(EXAMPLE, self.data))


if __name__ == "__main__":
    unittest.main()
