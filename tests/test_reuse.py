"""Contenido vinculado: vincular, mover, duplicar y dividir.

Lo que se fija aquí, en orden de lo que más duele si se rompe:

* que vincular **no copie**: editar desde una ubicación se ve desde las
  demás porque es el mismo fichero, no porque algo lo propague;
* que dividir deje dos grupos que ya no se hablan, sin perder contenido;
* que una división a medias no exista: o se hace entera o no se hace;
* que los comentarios del `year.yaml` --los `# TODO: va`, las entradas
  comentadas de material que este año no se da-- sobrevivan a todas las
  operaciones, que es lo que un volcado de YAML se llevaría por delante;
* que todo esto se pueda reconstruir leyendo el repositorio y nada más.
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

from didacta import compose as compose_mod  # noqa: E402
from didacta import identity as identity_mod  # noqa: E402
from didacta import index as index_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402
from didacta import reuse  # noqa: E402


class RepoCase(unittest.TestCase):
    """Un repositorio pequeño con lo justo para que las operaciones sean reales."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-reuse-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.write("didacta.yaml", "languages: [es, va]\ndefault_language: es\n")
        self.write("courses/am-i/course.yaml", "id: am-i\ntitle:\n  es: AM I\n")
        self.write("courses/mat/course.yaml", "id: mat\ntitle:\n  es: Mates\n")
        self.write("courses/doble/course.yaml", "id: doble\ntitle:\n  es: Doble\n")
        for name in ("a/b/c", "a/b/d", "a/b/e"):
            self.unit(name)

        self.write(
            "courses/am-i/2025-2026/year.yaml",
            "course: am-i\n"
            "year: 2025-2026\n"
            "language: es\n"
            "\n"
            "documents:\n"
            "  - id: series\n"
            "    kind: theory\n"
            "    themes: [t1]\n"
            "    title:\n"
            "      es: Series\n"
            "      # TODO: va\n"
            "    structure:\n"
            "      - section:\n"
            "          es: Primera parte\n"
            "          # TODO: va\n"
            "      - unit: a/b/c\n"
            "      # - unit: a/b/d\n"
            "\n"
            "  - id: suelto\n"
            "    kind: handout\n"
            "    title:\n"
            "      es: Suelto\n"
            "    structure:\n"
            "      - unit: a/b/e\n",
        )
        self.write(
            "courses/am-i/2025-2026/themes.yaml",
            "themes:\n  - id: t1\n    title:\n      es: Tema 1\n",
        )
        self.master("am-i", "2025-2026", "series")
        self.master("am-i", "2025-2026", "suelto")
        for course, year in (("am-i", "2026-2027"), ("mat", "2026-2027"),
                             ("doble", "2026-2027")):
            self.write(
                "courses/%s/%s/year.yaml" % (course, year),
                "course: %s\nyear: %s\nlanguage: es\n\ndocuments:\n"
                % (course, year),
            )

    # -- utilidades --------------------------------------------------------

    def write(self, relpath, text):
        path = os.path.join(self.root, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def read(self, relpath):
        with open(os.path.join(self.root, relpath), encoding="utf-8") as handle:
            return handle.read()

    def edit_shared(self, content, old, new):
        """Un cambio en el fichero compartido, como lo haría el editor."""
        path = identity_mod.shared_path(self.root, content)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn(old, text)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace(old, new))

    def unit(self, name):
        self.write("content/%s/unit.yaml" % name,
                   "kind: theory\ntitle:\n  es: %s\n" % name)
        self.write("content/%s/es.tex" % name, "el texto de %s\n" % name)

    def master(self, course, year, document):
        self.write(
            "courses/%s/%s/%s.tex" % (course, year, document),
            "\\input{didacta-bootstrap}\n"
            "\\usepackage{didacta}\n"
            "\\DidactaDocument{%s %s}\n"
            "\\begin{document}\n"
            "\\DidactaUnit{a/b/c}\n"
            "\\end{document}\n" % (document, year),
        )

    @property
    def settings(self):
        return repo_mod.Settings.load(self.root)

    def courses(self):
        courses, errors = repo_mod.scan_courses(self.root, self.settings)
        self.assertEqual(errors, [], "el repositorio no se lee limpio")
        return courses

    def document(self, course, year, document):
        return next(
            item for item in self.courses()[course].years[year].documents
            if item.id == document
        )

    def link(self, source, target, **kwargs):
        return reuse.link_document(self.root, self.settings, source, target,
                                   **kwargs)


class LinkingTests(RepoCase):
    def test_linking_shares_one_entity_between_two_years(self):
        plan = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        here = self.document("am-i", "2025-2026", "series")
        there = self.document("am-i", "2026-2027", "series")
        self.assertEqual(here.content, plan.content)
        self.assertEqual(there.content, plan.content)

    def test_linking_does_not_copy_the_composition(self):
        """Lo que hace que esto valga: hay un solo sitio donde está escrita."""
        self.link("am-i@2025-2026/series", "am-i@2026-2027")
        year = self.read("courses/am-i/2026-2027/year.yaml")
        self.assertNotIn("unit: a/b/c", year)
        self.assertIn("link: d-", year)

    def test_editing_from_one_place_is_seen_from_the_other(self):
        plan = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        self.edit_shared(plan.content, "  - unit: a/b/c",
                         "  - unit: a/b/c\n  - unit: a/b/e")
        for year in ("2025-2026", "2026-2027"):
            document = self.document("am-i", year, "series")
            self.assertEqual(document.unit_refs, ["a/b/c", "a/b/e"])

    def test_editing_from_the_other_place_is_seen_from_the_first(self):
        """La misma comprobación al revés: no hay un original y una copia."""
        plan = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        self.edit_shared(plan.content, "es: Series", "es: Series numéricas")
        for year in ("2025-2026", "2026-2027"):
            self.assertEqual(
                self.document("am-i", year, "series").titles["es"],
                "Series numéricas",
            )

    def test_it_links_between_two_different_subjects(self):
        plan = self.link("am-i@2025-2026/series", "mat@2026-2027")
        self.assertEqual(
            self.document("mat", "2026-2027", "series").content, plan.content
        )

    def test_a_linked_document_brings_its_theme_declaration(self):
        self.link("am-i@2025-2026/series", "mat@2026-2027")
        declared = repo_mod.load_themes(
            os.path.join(self.root, "courses/mat/2026-2027"), self.settings
        )
        self.assertEqual([theme.id for theme in declared], ["t1"])

    def test_a_linked_document_gets_its_own_master(self):
        """Cada curso tiene su portada y su año; el cuerpo sale de uno solo."""
        self.link("am-i@2025-2026/series", "mat@2026-2027")
        body = self.read("courses/mat/2026-2027/series.tex")
        self.assertIn("2026-2027", body)
        self.assertNotIn("2025-2026", body)

    def test_the_comments_survive_the_move_to_the_shared_file(self):
        """Los `# TODO: va` son la lista de lo que falta por traducir."""
        plan = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        shared = self.read("shared/documents/%s.yaml" % plan.content)
        self.assertIn("# TODO: va", shared)
        self.assertIn("# - unit: a/b/d", shared)

    def test_a_disabled_entry_is_still_a_disabled_entry(self):
        """Material que existe y que este año no se da: se conserva apagado."""
        plan = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        path = identity_mod.shared_path(self.root, plan.content)
        collected = compose_mod.read_shared_entries(path)
        self.assertEqual([(e.kind, e.value, e.enabled) for e in collected],
                         [("section", "", True),
                          ("unit", "a/b/c", True),
                          ("unit", "a/b/d", False)])

    def test_the_other_documents_of_the_year_are_untouched(self):
        before = self.read("courses/am-i/2025-2026/year.yaml")
        self.link("am-i@2025-2026/series", "am-i@2026-2027")
        after = self.read("courses/am-i/2025-2026/year.yaml")
        self.assertIn("- id: suelto", after)
        self.assertIn("- unit: a/b/e", after)
        self.assertEqual(before.count("- id: suelto"), after.count("- id: suelto"))

    def test_linking_onto_a_taken_name_is_refused_before_touching_anything(self):
        self.link("am-i@2025-2026/series", "am-i@2026-2027")
        with self.assertRaises(reuse.ReuseError):
            self.link("am-i@2025-2026/suelto", "am-i@2026-2027", as_id="series")

    def test_a_third_place_joins_the_same_entity(self):
        first = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        second = self.link("am-i@2025-2026/series", "mat@2026-2027")
        self.assertEqual(first.content, second.content)
        places = reuse.document_places(self.courses(), first.content)
        self.assertEqual([place.key for place in places],
                         ["am-i@2025-2026/series",
                          "am-i@2026-2027/series",
                          "mat@2026-2027/series"])


class ComposeTests(RepoCase):
    def test_a_linked_document_composes_its_master_from_the_shared_file(self):
        """Sin esto el PDF de un curso vinculado sale con el cuerpo de antes."""
        plan = self.link("am-i@2025-2026/series", "mat@2026-2027")
        self.edit_shared(plan.content, "  - unit: a/b/c",
                         "  - unit: a/b/c\n  - unit: a/b/e")
        document = self.document("mat", "2026-2027", "series")
        year_path = os.path.join(self.root, "courses/mat/2026-2027/year.yaml")
        result = compose_mod.compose_document(document, year_path)
        self.assertIsNone(result.refused)
        body = self.read("courses/mat/2026-2027/series.tex")
        self.assertIn("\\DidactaUnit{a/b/e}", body)

    def test_a_document_that_is_not_linked_composes_as_it_always_did(self):
        document = self.document("am-i", "2025-2026", "suelto")
        year_path = os.path.join(self.root, "courses/am-i/2025-2026/year.yaml")
        result = compose_mod.compose_document(document, year_path)
        self.assertIsNone(result.refused)
        self.assertIn("\\DidactaUnit{a/b/e}",
                      self.read("courses/am-i/2025-2026/suelto.tex"))


class MoveTests(RepoCase):
    def test_moving_keeps_the_same_number_of_places(self):
        reuse.move_document(self.root, self.settings,
                            "am-i@2025-2026/suelto", "mat@2026-2027")
        courses = self.courses()
        gone = [d.id for d in courses["am-i"].years["2025-2026"].documents]
        arrived = [d.id for d in courses["mat"].years["2026-2027"].documents]
        self.assertNotIn("suelto", gone)
        self.assertIn("suelto", arrived)

    def test_moving_does_not_change_identity(self):
        """Mover una ubicación no vincula ni desvincula nada."""
        plan = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        reuse.move_document(self.root, self.settings,
                            "am-i@2026-2027/series", "doble@2026-2027")
        self.assertEqual(
            self.document("doble", "2026-2027", "series").content, plan.content
        )
        places = reuse.document_places(self.courses(), plan.content)
        self.assertEqual(len(places), 2)

    def test_moving_takes_the_master_with_it(self):
        reuse.move_document(self.root, self.settings,
                            "am-i@2025-2026/suelto", "mat@2026-2027")
        self.assertTrue(os.path.isfile(
            os.path.join(self.root, "courses/mat/2026-2027/suelto.tex")))
        self.assertFalse(os.path.isfile(
            os.path.join(self.root, "courses/am-i/2025-2026/suelto.tex")))

    def test_moving_an_unlinked_document_keeps_its_composition(self):
        reuse.move_document(self.root, self.settings,
                            "am-i@2025-2026/suelto", "mat@2026-2027")
        self.assertEqual(
            self.document("mat", "2026-2027", "suelto").unit_refs, ["a/b/e"])


class SplitTests(RepoCase):
    def four(self):
        """A, B, C y D vinculadas al mismo contenido."""
        plan = self.link("am-i@2025-2026/series", "am-i@2026-2027")
        self.link("am-i@2025-2026/series", "mat@2026-2027")
        self.link("am-i@2025-2026/series", "doble@2026-2027")
        return plan.content

    def test_four_places_share_one_entity(self):
        content = self.four()
        self.assertEqual(len(reuse.document_places(self.courses(), content)), 4)

    def test_splitting_leaves_two_groups(self):
        content = self.four()
        reuse.split_document(
            self.root, self.settings, content,
            [["mat@2026-2027/series", "doble@2026-2027/series"]],
        )
        courses = self.courses()
        first = self.document("am-i", "2025-2026", "series").content
        second = self.document("am-i", "2026-2027", "series").content
        third = self.document("mat", "2026-2027", "series").content
        fourth = self.document("doble", "2026-2027", "series").content
        self.assertEqual(first, content)
        self.assertEqual(second, content)
        self.assertEqual(third, fourth)
        self.assertNotEqual(third, content)
        self.assertEqual(len(reuse.document_places(courses, content)), 2)

    def test_after_the_split_the_first_group_still_syncs(self):
        content = self.four()
        reuse.split_document(
            self.root, self.settings, content,
            [["mat@2026-2027/series", "doble@2026-2027/series"]],
        )
        self.retitle(content, "Series de Fourier")
        for course, year in (("am-i", "2025-2026"), ("am-i", "2026-2027")):
            self.assertEqual(
                self.document(course, year, "series").titles["es"],
                "Series de Fourier",
            )

    def test_after_the_split_the_other_group_does_not_change(self):
        content = self.four()
        reuse.split_document(
            self.root, self.settings, content,
            [["mat@2026-2027/series", "doble@2026-2027/series"]],
        )
        self.retitle(content, "Series de Fourier")
        for course in ("mat", "doble"):
            self.assertEqual(
                self.document(course, "2026-2027", "series").titles["es"],
                "Series",
            )

    def test_the_second_group_syncs_on_its_own(self):
        content = self.four()
        reuse.split_document(
            self.root, self.settings, content,
            [["mat@2026-2027/series", "doble@2026-2027/series"]],
        )
        other = self.document("mat", "2026-2027", "series").content
        self.retitle(other, "Series, otra rama")
        self.assertEqual(
            self.document("doble", "2026-2027", "series").titles["es"],
            "Series, otra rama",
        )
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").titles["es"], "Series"
        )

    def test_splitting_again_gives_three_groups(self):
        """Dividir lo ya dividido: tres ramas, y ninguna se habla con otra."""
        content = self.four()
        reuse.split_document(
            self.root, self.settings, content,
            [["mat@2026-2027/series", "doble@2026-2027/series"]],
        )
        second = self.document("mat", "2026-2027", "series").content
        reuse.split_document(self.root, self.settings, second,
                             [["doble@2026-2027/series"]])

        # am-i x2 siguen juntos; mat y doble quedan solos, y un grupo de uno
        # no es un grupo: su tema vuelve a estar escrito en su curso.
        self.assertEqual(self.document("am-i", "2025-2026", "series").content,
                         content)
        self.assertEqual(self.document("am-i", "2026-2027", "series").content,
                         content)
        self.assertIsNone(self.document("mat", "2026-2027", "series").content)
        self.assertIsNone(self.document("doble", "2026-2027", "series").content)
        self.assertEqual(identity_mod.list_shared(self.root), [content])

        # Y los tres evolucionan por su lado.
        self.retitle(content, "Solo en am-i")
        self.assertEqual(
            self.document("am-i", "2026-2027", "series").titles["es"],
            "Solo en am-i")
        for course in ("mat", "doble"):
            self.assertEqual(
                self.document(course, "2026-2027", "series").titles["es"],
                "Series")

    def test_a_group_of_one_stops_being_shared(self):
        content = self.four()
        reuse.split_document(self.root, self.settings, content,
                             [["doble@2026-2027/series"]])
        document = self.document("doble", "2026-2027", "series")
        self.assertIsNone(document.content)
        self.assertEqual(document.unit_refs, ["a/b/c"])
        self.assertIn("- unit: a/b/c",
                      self.read("courses/doble/2026-2027/year.yaml"))

    def test_an_independent_copy_stops_syncing(self):
        content = self.four()
        reuse.unlink_document(self.root, self.settings, "doble@2026-2027/series")
        self.retitle(content, "Cambiado")
        self.assertEqual(
            self.document("doble", "2026-2027", "series").titles["es"], "Series")

    def test_an_independent_copy_keeps_the_content_it_had(self):
        self.four()
        reuse.unlink_document(self.root, self.settings, "doble@2026-2027/series")
        text = self.read("courses/doble/2026-2027/year.yaml")
        self.assertIn("# TODO: va", text)
        self.assertIn("# - unit: a/b/d", text)

    def test_naming_a_place_twice_is_refused(self):
        content = self.four()
        with self.assertRaises(reuse.ReuseError):
            reuse.split_document(
                self.root, self.settings, content,
                [["mat@2026-2027/series"], ["mat@2026-2027/series"]],
            )

    def test_naming_a_place_that_is_not_in_the_group_is_refused(self):
        content = self.four()
        with self.assertRaises(reuse.ReuseError):
            reuse.split_document(self.root, self.settings, content,
                                 [["am-i@2025-2026/suelto"]])

    def test_a_refused_split_changes_nothing(self):
        """O se hace entera o no se hace: media división no se ve."""
        content = self.four()
        before = {
            path: self.read(path)
            for path in ("courses/am-i/2025-2026/year.yaml",
                         "courses/am-i/2026-2027/year.yaml",
                         "courses/mat/2026-2027/year.yaml",
                         "courses/doble/2026-2027/year.yaml")
        }
        with self.assertRaises(reuse.ReuseError):
            reuse.split_document(
                self.root, self.settings, content,
                [["mat@2026-2027/series", "am-i@2025-2026/suelto"]],
            )
        for path, text in before.items():
            self.assertEqual(self.read(path), text)
        self.assertEqual(len(identity_mod.list_shared(self.root)), 1)

    def test_a_deep_split_duplicates_the_lessons_too(self):
        content = self.four()
        reuse.split_document(
            self.root, self.settings, content,
            [["mat@2026-2027/series", "doble@2026-2027/series"]],
            deep=True,
        )
        theirs = self.document("mat", "2026-2027", "series").unit_refs
        ours = self.document("am-i", "2025-2026", "series").unit_refs
        self.assertNotEqual(theirs, ours)
        self.assertEqual(ours, ["a/b/c"])
        self.assertTrue(os.path.isdir(os.path.join(self.root, "content/a/b/c-2")))

    def test_a_shallow_split_keeps_the_lessons_shared(self):
        """Separar dos temas no quiere decir separar sus cuarenta lecciones."""
        content = self.four()
        reuse.split_document(
            self.root, self.settings, content,
            [["mat@2026-2027/series", "doble@2026-2027/series"]],
        )
        self.assertEqual(
            self.document("mat", "2026-2027", "series").unit_refs, ["a/b/c"])
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").unit_refs, ["a/b/c"])

    def retitle(self, content, title):
        self.edit_shared(content, "  es: Series", "  es: %s" % title)


class UnitSplitTests(RepoCase):
    def setUp(self):
        super().setUp()
        # La misma lección en tres sitios, sin vincular los temas: cada
        # documento tiene su propia composición.
        for course, year, document in (("am-i", "2026-2027", "otro"),
                                       ("mat", "2026-2027", "otro"),
                                       ("doble", "2026-2027", "otro")):
            identity_mod.insert_documents(
                os.path.join(self.root, "courses/%s/%s/year.yaml" % (course, year)),
                [[
                    "  - id: %s" % document,
                    "    kind: theory",
                    "    title:",
                    "      es: Otro",
                    "    structure:",
                    "      - unit: a/b/c",
                ]],
            )
            self.master(course, year, document)

    def unit_id(self):
        units, _ = repo_mod.scan_units(self.root, self.settings)
        return reuse.find_unit(self.root, units, "a/b/c").id

    def test_a_lesson_is_already_shared_by_every_place_that_calls_it(self):
        places = reuse.unit_places(
            self.courses(),
            repo_mod.scan_units(self.root, self.settings)[0],
            self.root,
            self.unit_id(),
        )
        self.assertEqual(
            sorted(place.key for place in places),
            ["am-i@2025-2026/series#0", "am-i@2026-2027/otro#0",
             "doble@2026-2027/otro#0", "mat@2026-2027/otro#0"],
        )

    def test_splitting_a_lesson_gives_the_new_group_a_copy(self):
        reuse.split_unit(self.root, self.settings, "a/b/c",
                         [["mat@2026-2027/otro#0", "doble@2026-2027/otro#0"]])
        self.assertEqual(
            self.document("mat", "2026-2027", "otro").unit_refs, ["a/b/c-2"])
        self.assertEqual(
            self.document("doble", "2026-2027", "otro").unit_refs, ["a/b/c-2"])
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").unit_refs, ["a/b/c"])

    def test_the_copy_has_an_identity_of_its_own(self):
        reuse.split_unit(self.root, self.settings, "a/b/c",
                         [["mat@2026-2027/otro#0"]])
        units, _ = repo_mod.scan_units(self.root, self.settings)
        original = reuse.find_unit(self.root, units, "a/b/c")
        copy = reuse.find_unit(self.root, units, "a/b/c-2")
        self.assertTrue(identity_mod.is_id(copy.id))
        self.assertNotEqual(original.id, copy.id)

    def test_the_copy_carries_the_content_it_had(self):
        reuse.split_unit(self.root, self.settings, "a/b/c",
                         [["mat@2026-2027/otro#0"]])
        self.assertEqual(self.read("content/a/b/c-2/es.tex"),
                         self.read("content/a/b/c/es.tex"))

    def test_editing_the_original_no_longer_reaches_the_copy(self):
        reuse.split_unit(self.root, self.settings, "a/b/c",
                         [["mat@2026-2027/otro#0"]])
        self.write("content/a/b/c/es.tex", "otra cosa\n")
        self.assertEqual(self.read("content/a/b/c-2/es.tex"), "el texto de a/b/c\n")

    def test_two_places_of_one_linked_topic_cannot_be_separated(self):
        """Son la misma línea del mismo fichero: hay que dividir el tema."""
        self.link("am-i@2026-2027/otro", "doble@2026-2027", as_id="linked")
        with self.assertRaises(reuse.ReuseError):
            reuse.split_unit(
                self.root, self.settings, "a/b/c",
                [["doble@2026-2027/linked#0"], ["am-i@2026-2027/otro#0"]],
            )


class IdTests(RepoCase):
    def test_a_repository_without_ids_gets_them(self):
        pending = reuse.unit_ids(self.root, self.settings)
        self.assertEqual(sorted(path for path, _ in pending),
                         ["content/a/b/c", "content/a/b/d", "content/a/b/e"])

    def test_nothing_is_written_until_it_is_applied(self):
        reuse.unit_ids(self.root, self.settings)
        self.assertNotIn("id:", self.read("content/a/b/c/unit.yaml"))

    def test_the_ids_are_the_same_whoever_runs_it(self):
        """Dos personas migrando por su cuenta no pueden crear dos verdades."""
        first = dict(reuse.unit_ids(self.root, self.settings))
        second = dict(reuse.unit_ids(self.root, self.settings))
        self.assertEqual(first, second)

    def test_applying_writes_them_and_keeps_everything_else(self):
        self.write(
            "content/a/b/c/unit.yaml",
            "# Una lección migrada.\n"
            "#\n"
            "# TODO: comprobar el título contra el original.\n"
            "\n"
            "kind: theory\n"
            "title:\n"
            "  es: c\n",
        )
        reuse.unit_ids(self.root, self.settings, apply=True)
        text = self.read("content/a/b/c/unit.yaml")
        self.assertIn("# TODO: comprobar el título contra el original.", text)
        self.assertIn("kind: theory", text)
        self.assertRegex(text, r"(?m)^id: u-[0-9a-f]{12}$")

    def test_running_it_twice_changes_nothing_the_second_time(self):
        reuse.unit_ids(self.root, self.settings, apply=True)
        before = self.read("content/a/b/c/unit.yaml")
        self.assertEqual(reuse.unit_ids(self.root, self.settings), [])
        reuse.unit_ids(self.root, self.settings, apply=True)
        self.assertEqual(self.read("content/a/b/c/unit.yaml"), before)

    def test_the_declared_id_is_the_one_the_engine_uses(self):
        reuse.unit_ids(self.root, self.settings, apply=True)
        units, _ = repo_mod.scan_units(self.root, self.settings)
        unit = units[[k for k in units if units[k].relpath == "content/a/b/c"][0]]
        self.assertTrue(identity_mod.is_id(unit.id))

    def test_a_lesson_keeps_its_id_when_it_moves(self):
        reuse.unit_ids(self.root, self.settings, apply=True)
        units, _ = repo_mod.scan_units(self.root, self.settings)
        before = reuse.find_unit(self.root, units, "a/b/c").id
        shutil.move(os.path.join(self.root, "content/a/b/c"),
                    os.path.join(self.root, "content/a/z"))
        units, _ = repo_mod.scan_units(self.root, self.settings)
        self.assertEqual(reuse.find_unit(self.root, units, "a/z").id, before)


class IndexTests(RepoCase):
    def test_the_index_says_where_a_shared_document_is_given(self):
        plan = self.link("am-i@2025-2026/series", "mat@2026-2027")
        data = index_mod.build(self.root, self.settings)
        shared = {item["id"]: item for item in data["courses.json"]["shared"]}
        self.assertIn(plan.content, shared)
        self.assertTrue(shared[plan.content]["declared"])
        self.assertEqual(
            [(p["course"], p["year"], p["document"])
             for p in shared[plan.content]["placements"]],
            [("am-i", "2025-2026", "series"), ("mat", "2026-2027", "series")],
        )

    def test_a_linked_document_looks_like_any_other_in_the_index(self):
        plan = self.link("am-i@2025-2026/series", "mat@2026-2027")
        data = index_mod.build(self.root, self.settings)
        courses = {item["id"]: item for item in data["courses.json"]["courses"]}
        document = courses["mat"]["years"]["2026-2027"]["documents"][0]
        self.assertEqual(document["title"], {"es": "Series"})
        self.assertEqual(document["unitRefs"], ["a/b/c"])
        self.assertEqual(document["content"], plan.content)

    def test_a_clean_read_rebuilds_the_links_from_the_files_alone(self):
        """Lo que hace que un clon limpio funcione: no hay nada más que leer."""
        plan = self.link("am-i@2025-2026/series", "mat@2026-2027")
        copy = tempfile.mkdtemp(prefix="didacta-clone-")
        self.addCleanup(shutil.rmtree, copy, ignore_errors=True)
        shutil.rmtree(copy)
        shutil.copytree(self.root, copy)
        settings = repo_mod.Settings.load(copy)
        courses, errors = repo_mod.scan_courses(copy, settings)
        self.assertEqual(errors, [])
        places = reuse.document_places(courses, plan.content)
        self.assertEqual([place.key for place in places],
                         ["am-i@2025-2026/series", "mat@2026-2027/series"])


class RestoreDocumentTests(RepoCase):
    """Traer un tema del árbol de otra versión.

    Un tema no es un fichero: su composición vive dentro del `year.yaml` del
    curso, entre las de los demás. Restaurarlo es sustituir su bloque y dejar
    los otros donde estaban, que es lo que separa «restaurar el Tema 3» de
    «volver el curso entero a septiembre».
    """

    def setUp(self):
        super().setUp()
        # Una copia del repositorio tal como está ahora: hace de árbol de la
        # congelación. En la aplicación es un worktree de git; para lo que se
        # prueba aquí, una carpeta con el contenido de entonces es lo mismo.
        self.old = tempfile.mkdtemp(prefix="didacta-old-")
        self.addCleanup(shutil.rmtree, self.old, ignore_errors=True)
        shutil.rmtree(self.old)
        shutil.copytree(self.root, self.old)

    def test_a_topic_comes_back_and_the_others_stay(self):
        self.write(
            "courses/am-i/2025-2026/year.yaml",
            self.read("courses/am-i/2025-2026/year.yaml")
            .replace("      es: Series", "      es: Otra cosa")
            .replace("      - unit: a/b/c", "      - unit: a/b/e"),
        )
        reuse.restore_document(self.root, self.settings, self.old,
                               "am-i", "2025-2026", "series")
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").titles["es"], "Series")
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").unit_refs, ["a/b/c"])
        # El otro documento del año no se ha tocado.
        self.assertEqual(
            self.document("am-i", "2025-2026", "suelto").unit_refs, ["a/b/e"])

    def test_the_comments_come_back_with_it(self):
        # Por líneas y no por substrings: `      # TODO: va` también es el
        # final de `          # TODO: va`, y quitarlo a medias deja un YAML
        # que no se lee -- que es justo lo que este test no está probando.
        kept = [
            line
            for line in self.read("courses/am-i/2025-2026/year.yaml").split("\n")
            if line.strip() not in ("# TODO: va", "# - unit: a/b/d")
        ]
        self.write("courses/am-i/2025-2026/year.yaml", "\n".join(kept))
        reuse.restore_document(self.root, self.settings, self.old,
                               "am-i", "2025-2026", "series")
        text = self.read("courses/am-i/2025-2026/year.yaml")
        self.assertIn("# TODO: va", text)
        self.assertIn("# - unit: a/b/d", text)

    def test_a_topic_that_was_removed_comes_back(self):
        identity_mod.remove_document_block(
            os.path.join(self.root, "courses/am-i/2025-2026/year.yaml"),
            "series")
        reuse.restore_document(self.root, self.settings, self.old,
                               "am-i", "2025-2026", "series")
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").titles["es"], "Series")

    def test_the_master_comes_back_too(self):
        self.write("courses/am-i/2025-2026/series.tex", "otra cosa\n")
        reuse.restore_document(self.root, self.settings, self.old,
                               "am-i", "2025-2026", "series")
        self.assertIn("\\begin{document}",
                      self.read("courses/am-i/2025-2026/series.tex"))

    def test_a_linked_topic_brings_its_shared_file(self):
        """Y se dice, porque eso lo cambia en todos los cursos que lo dan."""
        plan = self.link("am-i@2025-2026/series", "mat@2026-2027")
        old = tempfile.mkdtemp(prefix="didacta-old2-")
        self.addCleanup(shutil.rmtree, old, ignore_errors=True)
        shutil.rmtree(old)
        shutil.copytree(self.root, old)

        self.edit_shared(plan.content, "  es: Series", "  es: Cambiado")
        self.assertEqual(
            self.document("mat", "2026-2027", "series").titles["es"],
            "Cambiado")

        done = reuse.restore_document(self.root, self.settings, old,
                                      "am-i", "2025-2026", "series")
        self.assertEqual(
            self.document("mat", "2026-2027", "series").titles["es"], "Series")
        self.assertTrue(any("vinculado" in note for note in done.notes))

    def test_a_topic_that_never_was_there_is_refused(self):
        with self.assertRaises(reuse.ReuseError):
            reuse.restore_document(self.root, self.settings, self.old,
                                   "am-i", "2025-2026", "no-existe")

    def test_a_year_that_never_was_there_is_refused(self):
        with self.assertRaises(reuse.ReuseError):
            reuse.restore_document(self.root, self.settings, self.old,
                                   "am-i", "1999-2000", "series")


class UseUnitTests(RepoCase):
    """Dar una lección en otro tema, de otra asignatura si hace falta.

    Vinculada por defecto, que es lo que una referencia ha sido siempre: la
    lección vive una vez y los dos temas llaman a la misma.
    """

    def test_it_lands_at_the_end_of_the_composition(self):
        reuse.use_unit(self.root, self.settings, "a/b/e",
                       "am-i@2025-2026/series")
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").unit_refs,
            ["a/b/c", "a/b/e"])

    def test_the_comments_around_it_survive(self):
        reuse.use_unit(self.root, self.settings, "a/b/e",
                       "am-i@2025-2026/series")
        text = self.read("courses/am-i/2025-2026/year.yaml")
        self.assertIn("# TODO: va", text)
        self.assertIn("# - unit: a/b/d", text)

    def test_nothing_is_copied(self):
        before = self.read("content/a/b/e/es.tex")
        reuse.use_unit(self.root, self.settings, "a/b/e",
                       "am-i@2025-2026/series")
        self.assertFalse(os.path.isdir(os.path.join(self.root, "content/a/b/e-2")))
        self.assertEqual(self.read("content/a/b/e/es.tex"), before)

    def test_editing_it_reaches_both_topics(self):
        reuse.use_unit(self.root, self.settings, "a/b/e",
                       "am-i@2025-2026/series")
        units, _ = repo_mod.scan_units(self.root, self.settings)
        places = reuse.unit_places(
            self.courses(), units, self.root,
            reuse.find_unit(self.root, units, "a/b/e").id)
        self.assertEqual(sorted(place.key for place in places),
                         ["am-i@2025-2026/series#1",
                          "am-i@2025-2026/suelto#0"])

    def test_duplicating_gives_it_an_identity_of_its_own(self):
        reuse.use_unit(self.root, self.settings, "a/b/e",
                       "am-i@2025-2026/series", duplicate=True)
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").unit_refs,
            ["a/b/c", "a/b/e-2"])
        units, _ = repo_mod.scan_units(self.root, self.settings)
        original = reuse.find_unit(self.root, units, "a/b/e")
        copy = reuse.find_unit(self.root, units, "a/b/e-2")
        self.assertNotEqual(original.id, copy.id)
        self.assertEqual(self.read("content/a/b/e-2/es.tex"),
                         self.read("content/a/b/e/es.tex"))

    def test_it_reaches_a_topic_in_another_subject(self):
        self.link("am-i@2025-2026/suelto", "mat@2026-2027")
        reuse.use_unit(self.root, self.settings, "a/b/c",
                       "mat@2026-2027/suelto")
        self.assertEqual(
            self.document("mat", "2026-2027", "suelto").unit_refs,
            ["a/b/e", "a/b/c"])

    def test_adding_it_to_a_linked_topic_reaches_every_course(self):
        """Es lo que quiere decir estar vinculado, y se dice al hacerlo."""
        self.link("am-i@2025-2026/series", "mat@2026-2027")
        plan = reuse.use_unit(self.root, self.settings, "a/b/e",
                              "mat@2026-2027/series")
        self.assertEqual(
            self.document("am-i", "2025-2026", "series").unit_refs,
            ["a/b/c", "a/b/e"])
        self.assertTrue(any("vinculado" in note for note in plan.notes))

    def test_a_topic_without_a_composition_gets_one(self):
        identity_mod.insert_documents(
            os.path.join(self.root, "courses/mat/2026-2027/year.yaml"),
            [[
                "  - id: vacio",
                "    kind: theory",
                "    title:",
                "      es: Vacío",
            ]],
        )
        reuse.use_unit(self.root, self.settings, "a/b/c",
                       "mat@2026-2027/vacio")
        self.assertEqual(
            self.document("mat", "2026-2027", "vacio").unit_refs, ["a/b/c"])

    def test_a_topic_that_is_not_there_is_refused(self):
        with self.assertRaises(reuse.ReuseError):
            reuse.use_unit(self.root, self.settings, "a/b/c",
                           "mat@2026-2027/no-existe")

    def test_a_lesson_that_is_not_there_is_refused(self):
        with self.assertRaises(reuse.ReuseError):
            reuse.use_unit(self.root, self.settings, "a/b/no-existe",
                           "am-i@2025-2026/series")


if __name__ == "__main__":  # pragma: no cover
    unittest.main()