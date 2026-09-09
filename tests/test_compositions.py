"""Composition migration tests.

A legacy master is a preamble plus an ordered list of
``\\import{../../../../00classnotes/...}`` lines. The list is the composition,
and getting it across intact -- in order, with the headings, including what was
commented out -- is what these check.

The interesting cases are all real: import paths whose ``../`` chain is one
level short, folder names whose case does not match the disk, and headings
carrying a macro that only existed in the preamble Didacta deletes.
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

from didacta import legacy  # noqa: E402
from didacta import migrate  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402

LEGACY = os.path.dirname(ROOT)


def legacy_available():
    return os.path.isdir(os.path.join(LEGACY, legacy.CLASSNOTES))


def _read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


class FakeUnit:
    """Enough of a UnitPlan for the index."""

    def __init__(self, relpath, sources):
        self.relpath = relpath
        self.sources = sources
        self.area = relpath.split("/")[0]


UNITS = [
    FakeUnit("content/functional/normados/definicion", {
        "va": "00classnotes/40functional/00Presentaciones/01Normados/03VAL-definicion.tex",
        "es": "00classnotes/40functional/00Presentaciones/01Normados/03CAS-definicion.tex",
    }),
    FakeUnit("content/functional/normados/metrica", {
        "va": "00classnotes/40functional/00Presentaciones/01Normados/05VAL-metrica.tex",
    }),
    FakeUnit("problems/functional/normados/axiomas", {
        "es": "00classnotes/40functional/03Problems/01Normados/02CAS-axiomas.tex",
    }),
]


class IndexTests(unittest.TestCase):
    """Turning a legacy import path into a Didacta reference."""

    def setUp(self):
        self.index = migrate.UnitIndex(UNITS)

    def test_language_variants_collapse_to_one_reference(self):
        """The point of the whole exercise.

        The master imported ``03VAL-definicion``; the composition should say
        ``functional/normados/definicion`` and let the profile pick a language.
        """
        for code in ("VAL", "CAS"):
            path = ("00classnotes/40functional/00Presentaciones/01Normados/"
                    "03%s-definicion.tex" % code)
            with self.subTest(code=code):
                reference, area, _unit, how = self.index.lookup(path)
                self.assertEqual(reference, "functional/normados/definicion")
                self.assertEqual(area, repo_mod.CONTENT)
                self.assertEqual(how, "exact")

    def test_the_extension_is_optional(self):
        # `\import{dir/}{name}` is as common as `{name.tex}`.
        found = self.index.lookup(
            "00classnotes/40functional/00Presentaciones/01Normados/03VAL-definicion")
        self.assertIsNotNone(found)
        self.assertEqual(found[0], "functional/normados/definicion")

    def test_a_case_mismatch_still_resolves(self):
        """``03Bases`` for a folder that is ``03bases`` on disk.

        macOS hides it; git records the real name and Linux would not find the
        file at all. 79 references in the library depend on this.
        """
        found = self.index.lookup(
            "00classnotes/40functional/00Presentaciones/01normados/03val-definicion.tex")
        self.assertIsNotNone(found)
        self.assertEqual(found[0], "functional/normados/definicion")
        self.assertEqual(found[3], "tail", "should be reported as approximate")

    def test_a_short_relative_chain_still_resolves(self):
        """A master whose ``../../../../`` lands inside the year folder.

        The path after ``00classnotes/`` says unambiguously which file was
        meant, so it resolves -- and is flagged, because it only ever worked by
        accident.
        """
        found = self.index.lookup(
            " 2024-2025/00classnotes/40functional/00Presentaciones/01Normados/"
            "05VAL-metrica.tex")
        self.assertIsNotNone(found)
        self.assertEqual(found[0], "functional/normados/metrica")
        self.assertEqual(found[3], "tail")

    def test_a_problem_is_recognised_as_a_problem(self):
        found = self.index.lookup(
            "00classnotes/40functional/03Problems/01Normados/02CAS-axiomas.tex")
        self.assertEqual(found[1], repo_mod.PROBLEMS)

    def test_an_unknown_path_is_not_guessed_at(self):
        self.assertIsNone(self.index.lookup(
            "00classnotes/40functional/00Presentaciones/01Normados/99VAL-nope.tex"))


class IdentityTests(unittest.TestCase):
    """Which folder names a document, and how collisions are broken.

    Both awkward shapes here are real:

    * ``01Tema 1 - .../00Presentacio/`` and ``.../90Contenidos/`` -- one
      chapter, two documents;
    * ``01 - Introduction to ODEs/Introduction to ODEs/`` -- the chapter folder
      and the master folder carry the same name.
    """

    @staticmethod
    def segments(path):
        return migrate._document_identity(path.split("/"))[0]

    def test_a_container_folder_does_not_name_the_document(self):
        self.assertEqual(
            self.segments(" 2025-2026/00 AM III A/01Tema 1 - Preliminars/"
                          "00Presentacio/00Tema-1.tex"),
            ["tema-1-preliminars"],
        )

    def test_a_repeated_folder_name_is_said_once(self):
        # Otherwise: introduction-to-odes-introduction-to-odes.
        self.assertEqual(
            self.segments(" 2025-2026/IOWA/01 - Introduction to ODEs/"
                          "Introduction to ODEs/00Notes.tex"),
            ["introduction-to-odes"],
        )

    def test_the_chapter_is_kept_available_for_disambiguation(self):
        self.assertEqual(
            self.segments(" 2025-2026/IOWA/02 - First-Order Equations/"
                          "Review exercises/00Notes.tex"),
            ["first-order-equations", "review-exercises"],
        )

    def test_a_master_with_no_folder_of_its_own_falls_back_to_its_name(self):
        self.assertEqual(
            self.segments(" 2025-2026/Nau Gran/Seminario 1.tex"),
            ["seminario-1"],
        )

    def _resolve(self, sources):
        documents = []
        for source in sources:
            segments, title = migrate._document_identity(source.split("/"))
            documents.append(migrate.DocumentPlan(
                id=segments[-1], segments=segments, source=source,
                titles={"es": title}))
        migrate._resolve_duplicate_ids(documents)
        return {doc.source: doc.id for doc in documents}

    def test_one_chapter_two_masters_keeps_the_lecture_unqualified(self):
        """The lecture is what the chapter is about; the summary qualifies."""
        ids = self._resolve([
            " 2025-2026/AM/01Tema 1 - Normats/00Presentacio/00Tema-1.tex",
            " 2025-2026/AM/01Tema 1 - Normats/90Contenidos/00Contenidos.tex",
        ])
        self.assertEqual(
            sorted(ids.values()),
            ["tema-1-normats", "tema-1-normats-contenidos"],
        )
        self.assertEqual(
            ids[" 2025-2026/AM/01Tema 1 - Normats/00Presentacio/00Tema-1.tex"],
            "tema-1-normats",
        )

    def test_the_same_subfolder_in_two_chapters_qualifies_both(self):
        """Neither chapter has a better claim to the bare name.

        Letting the first one keep it would make the set read as though one
        chapter were the default.
        """
        ids = self._resolve([
            " 2025-2026/IOWA/01 - Intro/Review exercises/00Notes.tex",
            " 2025-2026/IOWA/02 - First-Order/Review exercises/00Notes.tex",
        ])
        self.assertEqual(
            sorted(ids.values()),
            ["first-order-review-exercises", "intro-review-exercises"],
        )
        self.assertNotIn("review-exercises", ids.values())

    def test_ids_are_unique_even_when_the_path_says_nothing(self):
        ids = self._resolve([
            " 2025-2026/AM/Seminaris/00seminari.tex",
            " 2025-2026/AM/Seminaris/01seminari.tex",
        ])
        self.assertEqual(len(set(ids.values())), 2)

    def test_a_numbered_id_is_reported_as_needing_a_real_one(self):
        documents = []
        for source in (" 2025-2026/AM/Seminaris/00seminari.tex",
                       " 2025-2026/AM/Seminaris/01seminari.tex"):
            segments, title = migrate._document_identity(source.split("/"))
            documents.append(migrate.DocumentPlan(
                id=segments[-1], segments=segments, source=source,
                titles={"es": title}))
        migrate._resolve_duplicate_ids(documents)
        numbered = [d for d in documents if d.id.endswith("-2")]
        self.assertTrue(numbered)
        self.assertTrue(
            any("un id propio" in d for d in numbered[0].needs_decision),
            numbered[0].needs_decision,
        )


class TitleTests(unittest.TestCase):
    """Where a document's title comes from."""

    def test_a_font_switch_does_not_become_part_of_the_title(self):
        # `{\small \chapterTitle}` and `{\sc Tema 1}` appear in 58 masters each.
        self.assertEqual(legacy.clean_text(r"{\sc Tema 1: Nombres reals}"),
                         "Tema 1: Nombres reals")

    def test_maths_in_a_title_survives(self):
        """Braces inside maths carry meaning.

        `$L^{pq}$` unwrapped becomes `$L^pq$`, which renders as a different
        formula -- so the brace stripping has to stop at a `$`.
        """
        for raw in (r"Els espais $L^{p}$",
                    r"Els espais $L^{pq}$ i $\ell^{p}$",
                    r"Un $$x^{2}$$ desplaçat",
                    r"La funció \(f(x)={x^{2}}\) creix"):
            with self.subTest(raw=raw):
                self.assertEqual(legacy.clean_text(raw), raw)

    def test_an_escaped_dollar_does_not_open_maths(self):
        self.assertEqual(legacy.clean_text(r"Preu 50\$ i {grup} de treball"),
                         r"Preu 50\$ i grup de treball")

    def test_only_legacy_preamble_macros_are_reported(self):
        """A heading may legitimately contain maths.

        40 headings carry `\infty`, `\mathbb` and friends; reporting those as
        unexpandable would bury the 17 that really are `\chapterName`.
        """
        self.assertEqual(migrate._leftover_macros(r"Tema 1: \chapterName"),
                         ["chapterName"])
        self.assertEqual(migrate._leftover_macros(r"Sèries $\sum 1/n^\infty$"), [])
        self.assertEqual(migrate._leftover_macros(r"$\mathbb R^n$"), [])

    def test_the_ordering_prefix_is_dropped_from_a_folder_title(self):
        self.assertEqual(migrate._folder_title("01Tema 1 - Preliminars"),
                         "Tema 1 - Preliminars")
        self.assertEqual(migrate._folder_title("03  Espacio euclideo"),
                         "Espacio euclideo")


MASTER = r"""\makeatletter
\@ifundefined{documentclassname}{\documentclass{book}}{%
    \documentclass[\documentclassoptions]{\documentclassname}}
\makeatother
\usepackage[catalan]{babel}
\newcommand{\chapterTitle}{Preliminars: Espais normats}
\title{\classextralong \newline {\small \chapterTitle}}
\usepackage{import}
\import{../../../../Files/}{Presentations-template}
\import{../../}{classinfoA}
\usepackage{docmute}

\begin{document}
\begin{frame}[t,plain]\titlepage\end{frame}
\onlybook{\tableofcontents}

\section{Espais normats}
\import{../../../../00classnotes/40functional/00Presentaciones/01Normados/}{03VAL-definicion.tex}
\import{../../../../00classnotes/40functional/00Presentaciones/01Normados/}{05VAL-metrica}

%\section{Introducció als espais de Hilbert}
%\import{../../../../00classnotes/40functional/00Presentaciones/01Normados/}{30VAL-hilbert}

\end{document}
"""


class StructureTests(unittest.TestCase):
    """Reading one master's composition."""

    def setUp(self):
        self.index = migrate.UnitIndex(UNITS)
        self.structure, self.notes, self.languages = migrate._read_structure(
            MASTER,
            " 2025-2026/00 AM III A/01Tema 1 - Preliminars espais normats/00Presentacio",
            self.index,
        )

    def test_the_order_is_the_order_of_the_source(self):
        """Order *is* the content of a composition."""
        self.assertEqual(
            self.structure[:3],
            [
                ("section", "Espais normats"),
                ("unit", "functional/normados/definicion"),
                ("unit", "functional/normados/metrica"),
            ],
        )

    def test_the_heading_comes_across(self):
        # A \section in a master is exactly where Didacta wants it: in the
        # composition, not in the unit.
        self.assertIn(("section", "Espais normats"), self.structure)

    def test_a_commented_out_section_is_kept_as_a_comment(self):
        self.assertIn(
            ("commented-section", "Introducció als espais de Hilbert"),
            self.structure,
        )

    def test_a_commented_out_import_is_kept_rather_than_dropped(self):
        """668 of these exist across the library.

        Each one records something the author decided to leave out that year,
        which is information the new file should not lose.
        """
        commented = [kind for kind, _ in self.structure if kind.startswith("commented-")]
        self.assertTrue(commented)
        self.assertNotIn(
            ("unit", "functional/normados/hilbert"), self.structure,
            "a commented-out import must not become a live one",
        )

    def test_the_template_import_is_not_a_unit(self):
        # `\import{../../../../Files/}{Presentations-template}` is preamble.
        for _kind, value in self.structure:
            self.assertNotIn("template", str(value).lower())
            self.assertNotIn("classinfo", str(value).lower())

    def test_the_language_is_read_from_the_imported_files(self):
        self.assertEqual(set(self.languages), {"va"})


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class PlanTests(unittest.TestCase):
    """Planning the real 2025-2026 compositions."""

    @classmethod
    def setUpClass(cls):
        cls.target = tempfile.mkdtemp(prefix="didacta-comp-")
        cls.units = migrate.plan_units(LEGACY, cls.target)
        cls.plan = migrate.plan_courses(
            LEGACY, cls.target, cls.units.units, year="2025-2026")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.target, ignore_errors=True)

    def test_planning_writes_nothing(self):
        self.assertEqual(os.listdir(self.target), [])

    def test_the_reference_year_is_found(self):
        # 2025-2026 is the year the whole design was measured against.
        self.assertIn("am-iii-a", self.plan.courses)
        course = self.plan.courses["am-iii-a"]
        self.assertIn("2025-2026", course.years)

    def test_course_metadata_comes_from_classinfo(self):
        course = self.plan.courses["am-iii-a"]
        self.assertEqual(course.code, "34157")
        self.assertEqual(course.language, "va")
        self.assertEqual(course.teacher, "Javier Falcó")
        self.assertEqual(course.institution, "Universitat de València")
        self.assertTrue(course.titles.get("va"))

    def test_the_reference_document_keeps_all_its_units(self):
        """Tema 1 of AM III selected 19 units, in an order that matters."""
        documents = self.plan.courses["am-iii-a"].years["2025-2026"]
        tema1 = next(d for d in documents
                     if d.id == "tema-1-preliminars-espais-normats")
        self.assertEqual(tema1.unit_count, 19)
        self.assertEqual(tema1.language, "va")
        self.assertEqual(tema1.kind, "theory")
        self.assertEqual(tema1.titles["va"], "Preliminars: Espais normats")
        first = [value for kind, value in tema1.structure if kind == "unit"][0]
        self.assertTrue(first.startswith("functional/"), first)

    def test_document_kinds_come_from_where_the_master_sits(self):
        """A seminar and a lecture load the same template.

        Left to the template alone, 49 seminars and 39 practicals would all
        build as lectures.
        """
        documents = self.plan.courses["am-iii-a"].years["2025-2026"]
        kinds = {doc.id: doc.kind for doc in documents}
        self.assertEqual(kinds.get("practica-1"), "practical")
        self.assertEqual(kinds.get("matrices"), "seminar")
        self.assertEqual(kinds.get("tema-2-espais-de-hilbert"), "theory")

    def test_every_kind_is_one_the_build_understands(self):
        for document in self.plan.documents:
            self.assertIn(document.kind, profiles_mod.FAMILY_FOR_KIND,
                          "%s: %s" % (document.id, document.kind))

    def test_two_masters_for_one_chapter_both_survive(self):
        # A chapter has a lecture master and a contents summary; they are two
        # documents, and one must not overwrite the other.
        documents = self.plan.courses["am-iii-a"].years["2025-2026"]
        ids = [doc.id for doc in documents]
        self.assertEqual(len(ids), len(set(ids)), "two documents share an id")
        self.assertIn("tema-1-preliminars-espais-normats", ids)
        self.assertIn("tema-1-preliminars-espais-normats-contenidos", ids)

    def test_almost_everything_resolves(self):
        """The measure of whether the migration is usable.

        Before the forgiving lookup, 201 of 6117 references pointed at nothing.
        What is left should be files that genuinely are not in git.
        """
        totals = self.plan.summary()
        self.assertGreater(totals["references"], 800)
        self.assertLess(totals["unresolved"], 10, "too many dangling references")

    def test_an_unresolved_reference_is_reported_not_hidden(self):
        for document in self.plan.documents:
            if document.unresolved:
                self.assertTrue(
                    any("no apuntan" in d for d in document.needs_decision),
                    document.id,
                )


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class ApplyCourseTests(unittest.TestCase):
    """Writing the compositions, and loading them back."""

    @classmethod
    def setUpClass(cls):
        cls.target = tempfile.mkdtemp(prefix="didacta-comp-apply-")
        cls.units = migrate.plan_units(LEGACY, cls.target)
        migrate.apply_plan(cls.units, dry_run=False)
        cls.plan = migrate.plan_courses(
            LEGACY, cls.target, cls.units.units, year="2025-2026")
        cls.created, cls.problems = migrate.apply_courses(cls.plan, dry_run=False)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.target, ignore_errors=True)

    def test_no_problems(self):
        self.assertEqual(self.problems, [])

    def test_the_repository_loads_as_didacta(self):
        """The only proof that matters: it comes back as a real repository."""
        settings = repo_mod.Settings.load(self.target)
        courses, errors = repo_mod.scan_courses(self.target, settings)
        self.assertEqual(errors, [])
        self.assertIn("am-iii-a", courses)
        year = courses["am-iii-a"].years["2025-2026"]
        self.assertTrue(year.documents)

    def test_every_reference_in_a_composition_points_at_a_real_unit(self):
        settings = repo_mod.Settings.load(self.target)
        units, unit_errors = repo_mod.scan_units(self.target, settings)
        self.assertEqual(unit_errors, [])
        courses, errors = repo_mod.scan_courses(self.target, settings)
        self.assertEqual(errors, [])

        dangling = []
        for course in courses.values():
            for year in course.years.values():
                for document in year.documents:
                    for ref in document.unit_refs:
                        if repo_mod.resolve_unit_ref(ref, units, self.target) is None:
                            dangling.append("%s -> %s" % (document.id, ref))
        self.assertEqual(dangling[:5], [], "%d dangling" % len(dangling))

    def test_every_document_has_a_master_file(self):
        settings = repo_mod.Settings.load(self.target)
        courses, _ = repo_mod.scan_courses(self.target, settings)
        for course in courses.values():
            for year in course.years.values():
                for document in year.documents:
                    self.assertTrue(os.path.isfile(document.source), document.source)

    def test_the_master_is_two_lines_of_setup_plus_the_composition(self):
        """What the migration is for.

        The legacy master was 100+ lines of preamble; what carried meaning was
        the ordered list. The new file should contain the list and almost
        nothing else.
        """
        path = os.path.join(self.target, repo_mod.COURSES, "am-iii-a",
                            "2025-2026", "tema-1-preliminars-espais-normats.tex")
        text = _read(path)
        self.assertIn(r"\input{didacta-bootstrap}", text)
        self.assertIn(r"\usepackage{didacta}", text)
        self.assertEqual(text.count(r"\DidactaUnit{"), 19)
        for gone in (r"\documentclass", r"\import{", "docmute", "THRMS",
                     r"\usepackage[catalan]{babel}"):
            self.assertNotIn(gone, text, "%s survived into the new master" % gone)

    def test_a_heading_reaches_both_the_master_and_the_year_file(self):
        """`year.yaml` is the authority; the master is the fallback.

        The multilingual heading belongs in `year.yaml` -- a heading written in
        one language is how a Valencian heading ends up on a Castilian handout.
        But the master is what `pdflatex` reads, so dropping it from there
        would silently lose every heading the old PDF had. Same split as the
        document title: authority in the structure file, fallback in the .tex.
        """
        text = _read(os.path.join(
            self.target, repo_mod.COURSES, "am-iii-a", "2025-2026",
            "tema-1-preliminars-espais-normats.tex"))
        self.assertIn(r"\section{Espais normats}", text)

        year = _read(os.path.join(self.target, repo_mod.COURSES, "am-iii-a",
                                  "2025-2026", "year.yaml"))
        self.assertIn("- section:", year)
        self.assertIn("Espais normats", year)
        # And with the other languages left to be written, not invented.
        self.assertIn("# TODO: es", year)

    def test_the_heading_level_survives(self):
        """`\\subsection` nests under `\\section`, and the nesting means something.

        Flattening every heading to a section turns "Derivación > Derivadas
        direccionales" into two peers.
        """
        settings = repo_mod.Settings.load(self.target)
        courses, _ = repo_mod.scan_courses(self.target, settings)
        levels = set()
        for course in courses.values():
            for year in course.years.values():
                for document in year.documents:
                    for step in document.structure:
                        if isinstance(step, dict):
                            levels.update(step)
        self.assertIn("section", levels)
        self.assertIn("subsection", levels)

    def test_what_was_commented_out_stays_commented_out(self):
        year = _read(os.path.join(self.target, repo_mod.COURSES, "am-iii-a",
                                  "2025-2026", "year.yaml"))
        self.assertIn("# - unit:", year)

    def test_the_course_code_stays_a_string(self):
        # Read as a number, `34157` stops comparing equal to the string the
        # rest of the system uses.
        settings = repo_mod.Settings.load(self.target)
        courses, _ = repo_mod.scan_courses(self.target, settings)
        self.assertEqual(courses["am-iii-a"].code, "34157")

    def test_missing_metadata_is_marked_todo_rather_than_guessed(self):
        text = _read(os.path.join(self.target, repo_mod.COURSES, "am-iii-a",
                                  "2025-2026", "year.yaml"))
        self.assertIn("# TODO:", text)

    def test_the_source_repository_is_untouched(self):
        sizes = []
        for path in legacy.git_files(LEGACY, "*.tex"):
            absolute = os.path.join(LEGACY, path)
            if os.path.isfile(absolute):
                sizes.append((path, os.path.getsize(absolute)))
        self.assertTrue(sizes)
        # Re-planning after writing must see exactly the same source.
        again = migrate.plan_courses(
            LEGACY, self.target, self.units.units, year="2025-2026")
        self.assertEqual(again.summary(), self.plan.summary())

    def test_a_dry_run_writes_nothing(self):
        empty = tempfile.mkdtemp(prefix="didacta-comp-dry-")
        try:
            plan = migrate.plan_courses(
                LEGACY, empty, self.units.units, year="2025-2026")
            created, problems = migrate.apply_courses(plan, dry_run=True)
            self.assertEqual(problems, [])
            self.assertTrue(created)
            self.assertEqual(os.listdir(empty), [])
        finally:
            shutil.rmtree(empty, ignore_errors=True)


class ReferenceKindTests(unittest.TestCase):
    """Not every mention of the library is a unit reference.

    Measured over the repository: 789 masters use ``\\import``, 4 use
    ``\\input``, 9 only pull a figure out of the library with
    ``\\includegraphics``, and 2 merely mention it in a comment. Reading all
    four the same way produces empty compositions that bury the real ones.
    """

    def kinds(self, text):
        return {kind for kind, _d, _n in migrate._library_references(text)}

    def test_an_import_is_a_unit_reference(self):
        self.assertEqual(
            self.kinds(r"\import{../../00classnotes/x/}{03VAL-y.tex}"),
            {"import"})

    def test_an_input_is_a_unit_reference_too(self):
        # A minority form, but the intent is identical.
        self.assertEqual(
            self.kinds(r"\input{../../00classnotes/x/03VAL-y}"), {"input"})

    def test_a_borrowed_figure_is_not_a_unit_reference(self):
        self.assertEqual(
            self.kinds(r"\includegraphics[width=3cm]{../../00classnotes/x/img/a}"),
            {"graphic"})

    def test_a_mention_is_nothing(self):
        self.assertEqual(self.kinds("% see 00classnotes/x for the original"), set())

    def test_a_path_outside_the_library_is_ignored(self):
        self.assertEqual(self.kinds(r"\import{../../Files/}{Presentations-template}"),
                         set())

    def test_an_input_reference_reaches_the_structure(self):
        index = migrate.UnitIndex(UNITS)
        structure, _notes, _langs = migrate._read_structure(
            "\\input{../../../../00classnotes/40functional/00Presentaciones/"
            "01Normados/03VAL-definicion}\n",
            " 2025-2026/AM/01Tema/00Presentacio",
            index)
        self.assertIn(("unit", "functional/normados/definicion"), structure)

    def test_a_borrowed_figure_is_reported_not_treated_as_a_unit(self):
        index = migrate.UnitIndex(UNITS)
        structure, notes, _langs = migrate._read_structure(
            "\\includegraphics[width=3cm]{../../../../00classnotes/40functional/"
            "img/diagram}\n",
            " 2025-2026/AM/01Tema/00Presentacio",
            index)
        self.assertEqual(structure, [])
        self.assertTrue(
            any("directamente de la biblioteca" in note for note in notes), notes)


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class SkipTests(unittest.TestCase):
    """What is deliberately not made into a composition."""

    @classmethod
    def setUpClass(cls):
        cls.target = tempfile.mkdtemp(prefix="didacta-skip-")
        units = migrate.plan_units(LEGACY, cls.target)
        cls.plan = migrate.plan_courses(LEGACY, cls.target, units.units)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.target, ignore_errors=True)

    def test_a_figure_only_file_is_skipped_with_a_reason(self):
        reasons = [why for _path, why in self.plan.skipped]
        self.assertTrue(reasons)
        self.assertTrue(any("figura" in why for why in reasons), reasons)

    def test_a_master_outside_a_year_is_skipped_rather_than_placed(self):
        # `talks/` holds real material with no academic year in its path.
        # Inventing a year would be worse than saying so.
        self.assertTrue(
            any("curso académico" in why for _p, why in self.plan.skipped))

    def test_nothing_is_skipped_silently(self):
        for path, why in self.plan.skipped:
            self.assertTrue(why and why.strip(), path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
