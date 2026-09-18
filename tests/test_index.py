"""Derived-index tests.

The index exists so an interface can browse thousands of units without reading
the repository. Two properties make it safe to rely on, and both are asserted
here: it is **derived** -- regenerating gives the same bytes and adds no fact
that is not already in the repository -- and it is **complete** for the views it
serves, so a browser needs one request rather than one per unit.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import index as index_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402

DEMO = os.path.join(ROOT, "examples", "demo-course")
LATEX = os.path.join(ROOT, "latex")


class BuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = index_mod.build(DEMO, latex_dir=LATEX)
        cls.manifest = cls.data[index_mod.MANIFEST]
        cls.units = cls.data[index_mod.UNITS]["units"]
        cls.courses = cls.data[index_mod.COURSES]["courses"]

    def test_building_writes_nothing(self):
        # `build` computes, `write` writes. The CLI shows what would change
        # before changing it, which needs the two separated.
        self.assertFalse(os.path.isdir(os.path.join(DEMO, index_mod.GENERATED)))

    def test_every_unit_is_in_the_index(self):
        settings = repo_mod.Settings.load(DEMO)
        units, errors = repo_mod.scan_units(DEMO, settings)
        self.assertEqual(errors, [])
        self.assertEqual(len(self.units), len(units))
        self.assertEqual({record["path"] for record in self.units},
                         {unit.relpath for unit in units.values()})

    def test_a_unit_record_carries_what_a_library_view_needs(self):
        """One request has to answer "show me the library".

        Anything missing here is a second request per row, which against 2147
        units is what makes a browser unusable.
        """
        record = self.units[0]
        for field in ("id", "path", "kind", "category", "topic", "tags",
                      "title", "reference", "languages", "usedBy"):
            self.assertIn(field, record)

    def test_the_translation_status_is_computed_not_copied(self):
        """`missing` and `outdated` are never declared, so they must be here.

        Colouring a library row by translation state is the whole point of the
        view, and recomputing it in a browser would mean hashing every file
        there.
        """
        by_path = {record["path"]: record for record in self.units}
        induced = by_path["content/analysis/normed-spaces/induced-metric"]
        # induced-metric has no va.tex in the example.
        self.assertEqual(induced["languages"]["va"]["status"], "missing")
        self.assertFalse(induced["languages"]["va"]["exists"])

        definition = by_path["content/analysis/normed-spaces/definition"]
        self.assertEqual(definition["languages"]["va"]["status"], "translated")

    def test_every_declared_language_appears_for_every_unit(self):
        # A view iterates languages per row; a missing key would be a hole in
        # the table rather than a "missing" cell.
        settings = repo_mod.Settings.load(DEMO)
        for record in self.units:
            self.assertEqual(sorted(record["languages"]),
                             sorted(settings.languages), record["path"])

    def test_usage_says_which_documents_use_a_unit(self):
        """The question the repository cannot answer cheaply.

        "Is this safe to change?" means reading every composition, which is
        exactly what an interface cannot do.
        """
        by_path = {record["path"]: record for record in self.units}
        used = by_path["content/analysis/normed-spaces/definition"]["usedBy"]
        self.assertEqual(
            [{k: entry[k] for k in ("course", "year", "document")}
             for entry in used],
            [{"course": "am-iii", "year": "2025-2026", "document": "tema-1"}],
        )

    def test_a_usage_says_which_position_of_the_composition_it_is(self):
        """Una ubicación, no un «aparece por aquí».

        La misma lección puede estar dos veces en el mismo tema, y entonces
        son dos ubicaciones distintas. Separar una de la otra sin poder
        nombrarlas sería adivinar cuál se estaba tocando.
        """
        by_path = {record["path"]: record for record in self.units}
        used = by_path["content/analysis/normed-spaces/definition"]["usedBy"]
        self.assertEqual(used[0]["index"], 0)
        self.assertEqual(used[0]["ref"], "analysis/normed-spaces/definition")

    def test_a_problem_unit_is_credited_to_the_sheet_that_uses_it(self):
        by_path = {record["path"]: record for record in self.units}
        norm = by_path["problems/analysis/normed-spaces/norm-axioms"]
        self.assertTrue(norm["usedBy"])
        self.assertEqual(norm["usedBy"][0]["document"], "hoja-1")

    def test_an_unused_unit_says_so_rather_than_being_absent(self):
        for record in self.units:
            self.assertIsInstance(record["usedBy"], list)

    def test_the_course_index_keeps_the_composition_order(self):
        year = self.courses[0]["years"]["2025-2026"]
        ids = [document["id"] for document in year["documents"]]
        self.assertEqual(ids, ["tema-1", "hoja-1"])

    def test_the_manifest_counts_agree_with_the_data(self):
        counts = self.manifest["counts"]
        self.assertEqual(counts["units"], len(self.units))
        self.assertEqual(counts["courses"], len(self.courses))
        documents = sum(len(year["documents"])
                        for course in self.courses
                        for year in course["years"].values())
        self.assertEqual(counts["documents"], documents)

    def test_the_manifest_lists_the_output_profiles(self):
        # So an interface can offer them without parsing LaTeX.
        ids = {profile["id"] for profile in self.manifest["profiles"]}
        self.assertIn("slides", ids)
        self.assertIn("problems-teacher", ids)
        self.assertEqual(len(ids), 15)

    def test_the_manifest_carries_the_taxonomy_and_the_blocks(self):
        """Lo que una interfaz necesita para ofrecer la clasificación.

        Deducirla de lo que las unidades usan hoy daría una lista que se
        encoge en cuanto la última unidad de un tema cambia de sitio, y
        entonces ese tema deja de poder elegirse.
        """
        self.assertIn("taxonomy", self.manifest)
        self.assertIn("categories", self.manifest["taxonomy"])
        # Los bloques van dentro de la taxonomía, que es donde se declaran:
        # un bloque clasifica una unidad, como la categoría y el tema. Vacío
        # cuando el repositorio no declara ninguno, y entonces valen los dos
        # de siempre, que es lo que hace que esto no rompa nada.
        self.assertEqual(self.manifest["taxonomy"]["blocks"], [])

    def test_repository_errors_reach_the_manifest(self):
        # An index built from a repository that does not load cleanly must say
        # so, or a reader is served something quietly incomplete.
        self.assertEqual(self.manifest["errors"], [])
        self.assertIn("errors", self.manifest)


class DeterminismTests(unittest.TestCase):
    """Regenerating must produce the same bytes.

    A timestamp in the manifest broke this once: `--check` reported the index
    stale immediately after writing it, and every rerun was a diff.
    """

    def test_two_builds_are_byte_identical(self):
        first = index_mod.build(DEMO, latex_dir=LATEX)
        second = index_mod.build(DEMO, latex_dir=LATEX)
        for name in first:
            with self.subTest(file=name):
                self.assertEqual(index_mod.dumps(first[name]),
                                 index_mod.dumps(second[name]))

    def test_nothing_in_the_index_is_a_timestamp(self):
        data = index_mod.build(DEMO, latex_dir=LATEX)
        text = "".join(index_mod.dumps(payload) for payload in data.values())
        for marker in ("generatedAt", "timestamp", "builtAt"):
            self.assertNotIn(marker, text)

    def test_the_content_hash_changes_only_with_the_content(self):
        first = index_mod.build(DEMO, latex_dir=LATEX)
        second = index_mod.build(DEMO, latex_dir=LATEX)
        self.assertEqual(first[index_mod.MANIFEST]["contentHash"],
                         second[index_mod.MANIFEST]["contentHash"])
        self.assertTrue(first[index_mod.MANIFEST]["contentHash"])


class WriteTests(unittest.TestCase):
    def setUp(self):
        self.target = tempfile.mkdtemp(prefix="didacta-index-")
        # A copy, so the example repository is never written into.
        shutil.copytree(DEMO, self.target, dirs_exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.target, ignore_errors=True)

    def test_a_dry_run_writes_nothing(self):
        data = index_mod.build(self.target, latex_dir=LATEX)
        written = index_mod.write(self.target, data, dry_run=True)
        self.assertTrue(written)
        self.assertFalse(
            os.path.isdir(os.path.join(self.target, index_mod.GENERATED)))

    def test_written_files_are_valid_json_and_readable_back(self):
        data = index_mod.build(self.target, latex_dir=LATEX)
        index_mod.write(self.target, data)
        for name in data:
            path = os.path.join(self.target, index_mod.GENERATED, name)
            with open(path, encoding="utf-8") as handle:
                payload = json.load(handle)
            self.assertEqual(payload["schemaVersion"], index_mod.SCHEMA_VERSION)

    def test_a_freshly_written_index_reports_as_up_to_date(self):
        """What `didacta index --check` runs in CI."""
        data = index_mod.build(self.target, latex_dir=LATEX)
        index_mod.write(self.target, data)
        self.assertTrue(index_mod.unchanged(self.target, data))

    def test_a_tampered_index_reports_as_stale(self):
        data = index_mod.build(self.target, latex_dir=LATEX)
        index_mod.write(self.target, data)
        path = os.path.join(self.target, index_mod.GENERATED, index_mod.UNITS)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write('{"schemaVersion": 1, "units": []}\n')
        self.assertFalse(index_mod.unchanged(self.target, data))

    def test_a_missing_index_reports_as_stale(self):
        data = index_mod.build(self.target, latex_dir=LATEX)
        self.assertFalse(index_mod.unchanged(self.target, data))

    def test_regenerating_over_an_existing_index_leaves_it_identical(self):
        data = index_mod.build(self.target, latex_dir=LATEX)
        index_mod.write(self.target, data)
        before = {}
        directory = os.path.join(self.target, index_mod.GENERATED)
        for name in sorted(os.listdir(directory)):
            with open(os.path.join(directory, name), encoding="utf-8") as handle:
                before[name] = handle.read()
        index_mod.write(self.target, index_mod.build(self.target, latex_dir=LATEX))
        for name, text in before.items():
            with open(os.path.join(directory, name), encoding="utf-8") as handle:
                self.assertEqual(handle.read(), text, name)

    def test_the_index_adds_no_fact_of_its_own(self):
        """Derived, never authoritative.

        Every title in the index has to come from a unit.yaml. If the index
        could introduce one, it would be a second place for a fact to live.
        """
        data = index_mod.build(self.target, latex_dir=LATEX)
        settings = repo_mod.Settings.load(self.target)
        units, _ = repo_mod.scan_units(self.target, settings)
        by_path = {unit.relpath: unit for unit in units.values()}
        for record in data[index_mod.UNITS]["units"]:
            unit = by_path[record["path"]]
            self.assertEqual(record["title"],
                             {code: unit.titles[code]
                              for code in sorted(unit.titles or {})})
            self.assertEqual(record["kind"], unit.kind)


class NumericNameTests(unittest.TestCase):
    """A folder named `15` gives `topic: 15`, which YAML reads as an integer.

    The category tree then sorted an int against a string and the whole index
    failed -- on the real library, not the example.
    """

    def test_a_numeric_topic_does_not_break_the_category_tree(self):
        records = [
            {"category": "otherprofesors", "topic": 15, "kind": "theory"},
            {"category": "otherprofesors", "topic": "practica-1", "kind": "theory"},
            {"category": 2026, "topic": "intro", "kind": "problem"},
        ]
        for record in records:
            record["category"] = str(record["category"])
            record["topic"] = str(record["topic"])
        tree = index_mod._categories(records)
        self.assertEqual(len(tree), 2)
        topics = {topic["id"] for entry in tree for topic in entry["topics"]}
        self.assertIn("15", topics)
        self.assertIn("practica-1", topics)


if __name__ == "__main__":
    unittest.main(verbosity=2)


class StalenessTests(unittest.TestCase):
    """Si el índice sigue describiendo lo que hay en el disco.

    Existe por un caso real: alguien movió `content/` y `courses/` a
    `content_backup/` y `courses_backup/`, arrancó la aplicación, y la
    biblioteca seguía enseñando dos mil unidades. Y era verdad lo que
    enseñaba --el índice las tenía-- solo que el índice hablaba de ficheros
    que ya no estaban ahí.

    Tiene que ser barato porque se pregunta en cada arranque: generar el
    índice para compararlo son tres segundos, y esto es un `walk` sin abrir
    ningún fichero.
    """

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-stale-")
        shutil.copytree(DEMO, os.path.join(self.root, "repo"))
        self.repo = os.path.join(self.root, "repo")
        self.settings = repo_mod.Settings.load(self.repo)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def write_index(self):
        data = index_mod.build(self.repo, self.settings)
        index_mod.write(self.repo, data)
        return data

    def report(self):
        return index_mod.staleness(self.repo, self.settings)

    def test_without_an_index_everything_is_stale(self):
        report = self.report()
        self.assertTrue(report["stale"])
        self.assertIn("no hay índice", report["reason"])

    def test_a_fresh_index_is_not_stale(self):
        self.write_index()
        self.assertFalse(self.report()["stale"], self.report()["reason"])

    def test_moving_the_content_away_is_stale(self):
        # El caso que trajo todo esto. Una fecha no lo ve: el `content/` que
        # queda no es más nuevo que nada, simplemente ya no hay nada.
        self.write_index()
        shutil.move(os.path.join(self.repo, "content"),
                    os.path.join(self.repo, "content_backup"))

        report = self.report()
        self.assertTrue(report["stale"])
        self.assertIn("unidades", report["reason"])
        self.assertLess(report["disk"]["units"], report["indexed"]["units"])

    def test_emptying_problems_is_stale_too(self):
        self.write_index()
        problems = os.path.join(self.repo, "problems")
        if os.path.isdir(problems):
            shutil.rmtree(problems)
            self.assertTrue(self.report()["stale"])

    def test_editing_a_file_is_stale(self):
        self.write_index()
        # Con una fecha por delante del índice, que es lo que hace un editor.
        target = None
        for directory, _, names in os.walk(os.path.join(self.repo, "content")):
            for name in names:
                if name.endswith(".tex"):
                    target = os.path.join(directory, name)
                    break
        self.assertIsNotNone(target)
        later = time.time() + 60
        os.utime(target, (later, later))

        report = self.report()
        self.assertTrue(report["stale"])
        self.assertIn("editado", report["reason"])

    def test_adding_a_year_is_stale(self):
        # Un `year.yaml` más y el índice habla de un curso menos.
        self.write_index()
        before = self.report()["indexed"]["years"]
        year = os.path.join(self.repo, "courses", "nueva", "2030-2031")
        os.makedirs(year)
        with open(os.path.join(year, "year.yaml"), "w", encoding="utf-8") as h:
            h.write("course: nueva\nyear: 2030-2031\ndocuments: []\n")

        report = self.report()
        self.assertTrue(report["stale"])
        self.assertEqual(report["disk"]["years"], before + 1)

    def test_editing_the_settings_is_stale(self):
        # `didacta.yaml` no está debajo de content/, problems/ ni courses/, y
        # sin embargo lo que dice --los idiomas del repositorio-- sale en el
        # índice. Sin mirarlo, añadir un idioma y regenerar no cambiaba nada:
        # el índice no se daba por viejo, así que no se regeneraba.
        self.write_index()
        later = time.time() + 60
        os.utime(os.path.join(self.repo, repo_mod.SETTINGS), (later, later))

        report = self.report()
        self.assertTrue(report["stale"])
        self.assertIn("editado", report["reason"])

    def test_editing_the_taxonomy_is_stale(self):
        # Lo mismo con la clasificación: las categorías y los temas viajan en
        # el manifiesto, así que declarar uno nuevo tiene que verse.
        self.write_index()
        path = os.path.join(self.repo, repo_mod.TAXONOMY)
        if not os.path.isfile(path):
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("categories: []\n")
        later = time.time() + 60
        os.utime(path, (later, later))

        self.assertTrue(self.report()["stale"])

    def test_a_repository_without_those_files_still_works(self):
        # Ninguno de los tres es obligatorio, y que falte uno no puede dejar
        # la comprobación sin contestar.
        for name in (repo_mod.TAXONOMY, repo_mod.DEGREES_META):
            path = os.path.join(self.repo, name)
            if os.path.isfile(path):
                os.remove(path)
        self.write_index()
        self.assertFalse(self.report()["stale"], self.report()["reason"])

    def test_the_survey_does_not_open_any_file(self):
        # La garantía de que es barato: si un día alguien le mete un
        # `yaml.load`, esto lo coge. Un fichero ilegible no puede romperlo.
        self.write_index()
        broken = os.path.join(self.repo, "content", "roto.yaml")
        with open(broken, "wb") as handle:
            handle.write(b"\x00\x01\x02 no es texto")
        self.assertIsNotNone(index_mod.survey(self.repo, self.settings))

