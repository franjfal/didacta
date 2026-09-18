"""Versiones congeladas: los metadatos, que es lo único que Didacta guarda.

Una congelación es un commit con nombre. Lo que se prueba aquí es la mitad
que vive en el repositorio --el `freezes.yaml`-- y las reglas que la hacen
segura:

* que quitarla no toque nada más que su entrada;
* que varias congelaciones puedan apuntar al mismo commit sin estorbarse;
* que un SHA corto no entre: hoy es único y dentro de tres años no lo es;
* que el fichero sobreviva a un clon, que es para lo que está en git.

La otra mitad --abrir un worktree, comparar, restaurar-- habla con git y se
prueba desde la aplicación, que es quien tiene el clon.
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

from didacta import freeze as freeze_mod  # noqa: E402
from didacta import identity as identity_mod  # noqa: E402
from didacta import index as index_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402

A = "4f2c1d9e8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d"
B = "0123456789abcdef0123456789abcdef01234567"


class FreezeCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-freeze-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("didacta.yaml", "languages: [es]\ndefault_language: es\n")
        self.write("courses/am-i/course.yaml", "id: am-i\ntitle:\n  es: AM I\n")
        self.write("content/a/b/c/unit.yaml", "kind: theory\ntitle:\n  es: c\n")
        self.write("content/a/b/c/es.tex", "texto\n")
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
        self.year = os.path.join(self.root, "courses/am-i/2026-2027")

    def write(self, relpath, text):
        path = os.path.join(self.root, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def read(self, relpath):
        with open(os.path.join(self.root, relpath), encoding="utf-8") as handle:
            return handle.read()

    def add(self, name, commit=A, **kwargs):
        return freeze_mod.add(self.year, name=name, commit=commit,
                              course="am-i", year="2026-2027", **kwargs)


class BasicTests(FreezeCase):
    def test_a_course_starts_without_any(self):
        self.assertEqual(freeze_mod.load(self.year), [])

    def test_creating_one_writes_the_file(self):
        entry = self.add("Inicio curso 2026-27")
        self.assertTrue(identity_mod.is_id(entry.id))
        self.assertEqual(entry.commit, A)
        self.assertIn("freezes:", self.read("courses/am-i/2026-2027/freezes.yaml"))

    def test_it_keeps_the_subject_and_the_year(self):
        entry = self.add("Inicio")
        self.assertEqual((entry.course, entry.year), ("am-i", "2026-2027"))

    def test_several_freezes_of_the_same_course(self):
        for name in ("Inicio curso 2026-27", "Antes del primer parcial",
                     "Versión final 2026-27"):
            self.add(name)
        found = freeze_mod.load(self.year, "am-i", "2026-2027")
        self.assertEqual([item.name for item in found],
                         ["Inicio curso 2026-27", "Antes del primer parcial",
                          "Versión final 2026-27"])

    def test_two_freezes_can_point_at_the_same_commit(self):
        """Pasa de verdad: congelar dos veces sin haber tocado nada."""
        self.add("Uno", commit=A)
        self.add("Dos", commit=A)
        found = freeze_mod.load(self.year)
        self.assertEqual({item.commit for item in found}, {A})
        self.assertEqual(len({item.id for item in found}), 2)

    def test_a_short_sha_is_refused(self):
        """Hoy es único; dentro de tres años es una ambigüedad guardada."""
        with self.assertRaises(freeze_mod.FreezeError):
            self.add("Corta", commit=A[:7])

    def test_something_that_is_not_a_sha_is_refused(self):
        with self.assertRaises(freeze_mod.FreezeError):
            self.add("Rama", commit="main")

    def test_a_freeze_needs_a_name(self):
        with self.assertRaises(freeze_mod.FreezeError):
            self.add("   ")

    def test_two_freezes_cannot_share_a_name(self):
        self.add("Inicio")
        with self.assertRaises(freeze_mod.FreezeError):
            self.add("Inicio")

    def test_the_description_is_optional_and_kept(self):
        self.add("Inicio", description="Como se repartió el primer día.")
        self.assertEqual(freeze_mod.load(self.year)[0].description,
                         "Como se repartió el primer día.")

    def test_the_creation_date_carries_its_timezone(self):
        """Una fecha sin zona no ordena entre dos ordenadores."""
        entry = self.add("Inicio")
        self.assertRegex(entry.created, r"[+-]\d{2}:\d{2}$|Z$")


class RemovalTests(FreezeCase):
    def test_removing_one_leaves_the_others(self):
        first = self.add("Uno")
        second = self.add("Dos")
        freeze_mod.remove(self.year, first.id)
        self.assertEqual([item.id for item in freeze_mod.load(self.year)],
                         [second.id])

    def test_removing_one_does_not_touch_the_course(self):
        before = self.read("courses/am-i/2026-2027/year.yaml")
        entry = self.add("Uno")
        freeze_mod.remove(self.year, entry.id)
        self.assertEqual(self.read("courses/am-i/2026-2027/year.yaml"), before)

    def test_removing_one_leaves_another_on_the_same_commit(self):
        first = self.add("Uno", commit=A)
        second = self.add("Dos", commit=A)
        freeze_mod.remove(self.year, first.id)
        kept = freeze_mod.load(self.year)
        self.assertEqual([item.id for item in kept], [second.id])
        self.assertEqual(kept[0].commit, A)

    def test_removing_one_that_is_not_there_says_so(self):
        with self.assertRaises(freeze_mod.FreezeError):
            freeze_mod.remove(self.year, "f-000000000000")

    def test_removing_the_last_one_leaves_a_readable_file(self):
        entry = self.add("Uno")
        freeze_mod.remove(self.year, entry.id)
        self.assertEqual(freeze_mod.load(self.year), [])


class RenameTests(FreezeCase):
    def test_renaming_keeps_the_commit(self):
        entry = self.add("Uno", commit=B)
        freeze_mod.rename(self.year, entry.id, name="Otro nombre")
        found = freeze_mod.load(self.year)[0]
        self.assertEqual(found.name, "Otro nombre")
        self.assertEqual(found.commit, B)

    def test_renaming_onto_a_taken_name_is_refused(self):
        self.add("Uno")
        second = self.add("Dos")
        with self.assertRaises(freeze_mod.FreezeError):
            freeze_mod.rename(self.year, second.id, name="Uno")

    def test_the_description_can_be_changed_on_its_own(self):
        entry = self.add("Uno", description="vieja")
        freeze_mod.rename(self.year, entry.id, description="nueva")
        found = freeze_mod.load(self.year)[0]
        self.assertEqual((found.name, found.description), ("Uno", "nueva"))


class FileTests(FreezeCase):
    def test_the_header_explains_itself_and_survives(self):
        self.add("Uno")
        text = self.read("courses/am-i/2026-2027/freezes.yaml")
        self.assertIn("no borra ningún commit", text)
        self.add("Dos")
        self.assertIn("no borra ningún commit",
                      self.read("courses/am-i/2026-2027/freezes.yaml"))

    def test_a_header_someone_wrote_is_kept(self):
        self.add("Uno")
        path = os.path.join(self.year, "freezes.yaml")
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("# Mis notas sobre esto.\n" + text.split("freezes:")[0]
                         + "freezes:" + text.split("freezes:")[1])
        self.add("Dos")
        self.assertIn("# Mis notas sobre esto.",
                      self.read("courses/am-i/2026-2027/freezes.yaml"))

    def test_a_name_with_a_colon_round_trips(self):
        """`Tema 1: los reales` sin comillas es otra clave de YAML."""
        self.add("Parcial 1: hasta series")
        self.assertEqual(freeze_mod.load(self.year)[0].name,
                         "Parcial 1: hasta series")

    def test_a_broken_file_is_reported_rather_than_guessed_at(self):
        self.write("courses/am-i/2026-2027/freezes.yaml",
                   "freezes:\n  - name: sin commit\n")
        with self.assertRaises(freeze_mod.FreezeError):
            freeze_mod.load(self.year)


class ReadingTests(FreezeCase):
    def test_the_engine_reads_them_with_the_course(self):
        self.add("Inicio curso 2026-27")
        settings = repo_mod.Settings.load(self.root)
        courses, errors = repo_mod.scan_courses(self.root, settings)
        self.assertEqual(errors, [])
        year = courses["am-i"].years["2026-2027"]
        self.assertEqual([item.name for item in year.freezes],
                         ["Inicio curso 2026-27"])

    def test_the_index_publishes_them(self):
        entry = self.add("Inicio curso 2026-27", description="el primer día")
        settings = repo_mod.Settings.load(self.root)
        data = index_mod.build(self.root, settings)
        course = data["courses.json"]["courses"][0]
        found = course["years"]["2026-2027"]["freezes"]
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]["id"], entry.id)
        self.assertEqual(found[0]["commit"], A)
        self.assertEqual(found[0]["description"], "el primer día")

    def test_a_clone_sees_the_same_freezes(self):
        """Para eso están en git y no en una base de datos local."""
        self.add("Inicio curso 2026-27")
        copy = tempfile.mkdtemp(prefix="didacta-freeze-clone-")
        self.addCleanup(shutil.rmtree, copy, ignore_errors=True)
        shutil.rmtree(copy)
        shutil.copytree(self.root, copy)
        found = freeze_mod.load(os.path.join(copy, "courses/am-i/2026-2027"))
        self.assertEqual([item.name for item in found], ["Inicio curso 2026-27"])


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
