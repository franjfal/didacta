"""Migration tests.

Migration touches the author's real material, so the guarantees matter more
than the convenience. Two are asserted above all:

* the source repository is never modified;
* nothing is written without ``--apply``.

The transformation itself is tested on the real legacy shapes -- the ones
measured in the repository, including the inconsistencies -- rather than on
invented input.
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
from didacta import repo as repo_mod  # noqa: E402

#: The legacy repository, if this checkout sits inside one.
LEGACY = os.path.dirname(ROOT)


def legacy_available():
    return os.path.isdir(os.path.join(LEGACY, legacy.CLASSNOTES))


# A legacy content file with the shapes migration has to handle: a standalone
# preamble, relative template imports, boxed environments, \onlybook, \pause,
# \frametitle, and a section the unit should not be declaring.
LEGACY_UNIT = r"""\documentclass[10pt,handout]{beamer}

\usepackage[utf8]{inputenc}
\usepackage[spanish]{babel}

\usepackage{import}
\import{../../../../Files/}{Presentations-template}
\import{../../../../Files/}{Presentations-template(THRMS-CAST)}

\begin{document}

\section{Espacios normados}

\begin{frame}
\frametitle{Definici\'on de espacio normado}

La m\'etrica usual en $\mathbb R$ es $d(x,y) = |x-y|$.

\onlybook{La idea es generalizar las propiedades de esa distancia.}

\begin{ndefn}[Espacio normado]
Un par $(E, \|\cdot\|)$ tal que...
\end{ndefn}

\pause

\begin{nex}
En $\mathbb R^n$...
\end{nex}
\end{frame}

\end{document}
"""

LEGACY_PROBLEM = r"""\documentclass[12pt]{report}
\usepackage[spanish]{babel}
\import{../../../../Files/}{Problems-template}
\import{../../../../Files/}{THRMS-CAST}
\def\CurrentAudience{solution}
\begin{document}

\begin{ej}
Calcula la derivada de $f(x) = x^2$.
\end{ej}\medskip

\begin{shownto}{solution}
\textbf{Soluci\'on:} $f'(x) = 2x$.
\end{shownto}

\end{document}
"""


class TransformTests(unittest.TestCase):
    def setUp(self):
        self.result = migrate.transform_content(
            LEGACY_UNIT, source_path="00classnotes/x/00Presentaciones/y/03CAS-z.tex")

    def test_the_preamble_is_gone(self):
        """The step that removes the most noise.

        Every legacy content file carries a full standalone preamble that
        ``docmute`` existed to discard. Didacta supplies it, so it goes.
        """
        text = self.result.text
        self.assertNotIn(r"\documentclass", text)
        self.assertNotIn(r"\usepackage", text)
        self.assertNotIn("Presentations-template", text)
        self.assertNotIn(r"\begin{document}", text)
        self.assertNotIn(r"\end{document}", text)
        self.assertGreater(self.result.preamble_lines, 5)

    def test_the_content_survives(self):
        text = self.result.text
        self.assertIn(r"La m\'etrica usual", text)
        self.assertIn(r"Un par $(E, \|\cdot\|)$", text)
        self.assertIn(r"En $\mathbb R^n$", text)

    def test_environments_are_renamed(self):
        text = self.result.text
        self.assertIn(r"\begin{definition}[Espacio normado]", text)
        self.assertIn(r"\end{definition}", text)
        self.assertIn(r"\begin{example}", text)
        self.assertNotIn("ndefn", text)
        self.assertNotIn("nex", text)

    def test_macros_are_renamed(self):
        text = self.result.text
        # \onlybook works as an alias, but \onlynotes says what it means.
        self.assertIn(r"\onlynotes{", text)
        self.assertNotIn(r"\onlybook", text)
        self.assertIn(r"\dpause", text)
        # \frametitle vanishes in a document profile, leaving the reader with
        # no heading; \didactatitle becomes a subsection there.
        self.assertIn(r"\didactatitle{", text)
        self.assertNotIn(r"\frametitle", text)

    def test_the_output_is_content_and_nothing_else(self):
        """No provenance header at the top of the `.tex`.

        It used to write three comment lines there, and that was the first
        thing anyone saw on opening a unit to edit it -- above the content, in
        an editor, in 2438 files. The provenance is not lost: `unit.yaml`
        records the same source path and git records the migration commit.
        """
        self.assertNotIn("Migrated from", self.result.text)
        self.assertNotIn("No preamble", self.result.text)
        # And it starts with content, not with a blank line or a rule.
        self.assertTrue(
            self.result.text.startswith("\\section{Espacios normados}"),
            repr(self.result.text[:60]),
        )

    def test_a_unit_declaring_its_own_section_is_flagged(self):
        # A section inside a unit travels with it into every course that
        # reuses it, so it belongs in the composition instead.
        self.assertEqual(self.result.sections, ["Espacios normados"])
        self.assertTrue(
            any("declara su propia sección" in note for note in self.result.notes),
            self.result.notes,
        )

    def test_the_section_is_not_silently_removed(self):
        # Flagged, not deleted: where the heading should go is the author's
        # decision, and quietly dropping it would lose the title.
        self.assertIn(r"\section{Espacios normados}", self.result.text)

    def test_pause_rename_does_not_touch_similar_macros(self):
        result = migrate.transform_content(
            r"\begin{document}\pause \pausecustom \pauses\end{document}")
        self.assertIn(r"\dpause", result.text)
        self.assertIn(r"\pausecustom", result.text)
        self.assertIn(r"\pauses", result.text)


class ProblemTransformTests(unittest.TestCase):
    def setUp(self):
        self.result = migrate.transform_content(LEGACY_PROBLEM)

    def test_the_exercise_is_renamed(self):
        self.assertIn(r"\begin{exercise}", self.result.text)
        self.assertNotIn(r"\begin{ej}", self.result.text)

    def test_the_audience_becomes_a_named_level(self):
        # `shownto{solution}` says who sees it; `solution` says what it is.
        self.assertIn(r"\begin{solution}", self.result.text)
        self.assertIn(r"\end{solution}", self.result.text)
        self.assertNotIn("shownto", self.result.text)

    def test_the_audience_selector_is_dropped(self):
        # \def\CurrentAudience was how the legacy build chose an output; in
        # Didacta the profile does, so a leftover would fight it.
        self.assertNotIn("CurrentAudience", self.result.text)

    def test_the_teacher_audience_becomes_marking(self):
        text = LEGACY_PROBLEM.replace("{solution}", "{profesor}")
        result = migrate.transform_content(text)
        self.assertIn(r"\begin{marking}", result.text)

    def test_the_professor_typo_is_handled(self):
        # 22 uses of `professor` with a doubled s exist in the material.
        text = LEGACY_PROBLEM.replace("{solution}", "{professor}")
        result = migrate.transform_content(text)
        self.assertIn(r"\begin{marking}", result.text)

    def test_an_unknown_audience_is_reported_not_dropped(self):
        text = LEGACY_PROBLEM.replace("{solution}", "{alumnado}")
        result = migrate.transform_content(text)
        self.assertIn("shownto", result.text)
        self.assertTrue(any("audiencia no reconocida" in n for n in result.notes))

    def test_two_audiences_in_one_file_keep_their_own_ends(self):
        """The failure mode of rewriting begins and ends independently.

        A blanket ``\\end{shownto}`` -> ``\\end{solution}`` closes a marking block
        with a solution end: at best a compile error, at worst correction notes
        printed on a student's sheet.
        """
        text = (
            "\\begin{document}\n"
            "\\begin{shownto}{solution}\nS\n\\end{shownto}\n"
            "\\begin{shownto}{profesor}\nM\n\\end{shownto}\n"
            "\\end{document}\n"
        )
        result = migrate.transform_content(text)
        self.assertNotIn("shownto", result.text)
        self.assertIn("\\begin{solution}", result.text)
        self.assertIn("\\begin{marking}", result.text)
        # Each level opens and closes exactly once.
        for level in ("solution", "marking"):
            self.assertEqual(result.text.count("\\begin{%s}" % level), 1)
            self.assertEqual(result.text.count("\\end{%s}" % level), 1)
        # And in the right order, which is what proves the pairing.
        self.assertLess(
            result.text.index("\\end{solution}"),
            result.text.index("\\begin{marking}"),
        )

    def test_a_nested_audience_is_rewritten_too(self):
        text = (
            "\\begin{document}\n"
            "\\begin{shownto}{solution}\nS\n"
            "\\begin{shownto}{profesor}\nM\n\\end{shownto}\n"
            "\\end{shownto}\n"
            "\\end{document}\n"
        )
        result = migrate.transform_content(text)
        self.assertNotIn("shownto", result.text)
        self.assertIn("\\begin{marking}", result.text)
        self.assertTrue(result.text.rstrip().endswith("\\end{solution}"), result.text)

    def test_an_unclosed_block_is_left_alone_and_reported(self):
        text = "\\begin{document}\n\\begin{shownto}{solution}\nS\n\\end{document}\n"
        result = migrate.transform_content(text)
        self.assertIn("shownto", result.text)
        self.assertTrue(any("sin \\end{shownto}" in n for n in result.notes),
                        result.notes)


class SplitTests(unittest.TestCase):
    """Cutting the file at the document delimiters."""

    def test_content_on_the_same_line_as_end_document_survives(self):
        """Three measured files depend on this.

        ``36CAS-Stolz-raices.tex`` ends ``}\\end{document}`` and
        ``01ENG-Metodo-de-inspeccion.tex`` ends ``$$\\end{document}``. Cutting by
        line drops the brace and the display-maths close, so the migrated unit
        is unbalanced and compiles nowhere.
        """
        split = legacy.split_document(
            "\\documentclass{beamer}\n\\begin{document}\ntext\n$$x$$\\end{document}\n")
        self.assertTrue(split.has_document_environment)
        self.assertIn("$$x$$", split.body)
        self.assertNotIn("document", split.body)

    def test_content_on_the_same_line_as_begin_document_survives(self):
        split = legacy.split_document(
            "\\documentclass{a}\n\\begin{document}text\n\\end{document}\n")
        self.assertIn("text", split.body)

    def test_a_commented_out_delimiter_is_ignored(self):
        split = legacy.split_document(
            "%\\begin{document}\n\\begin{document}\nreal\n\\end{document}\n")
        self.assertEqual(split.body.strip(), "real")
        self.assertIn("%", split.preamble)

    def test_an_escaped_percent_does_not_hide_a_delimiter(self):
        # `100\% \begin{document}` is not a comment.
        split = legacy.split_document(
            "\\documentclass{a}\n100\\% \\begin{document}\nreal\n\\end{document}\n")
        self.assertEqual(split.body.strip(), "real")


class FragmentTests(unittest.TestCase):
    def test_a_file_with_no_document_environment_is_kept_whole(self):
        # Some legacy files are fragments included with \input rather than
        # imported. Stripping to a body that does not exist would empty them.
        fragment = "\\begin{frame}\\frametitle{X}\ncontent\n\\end{frame}\n"
        result = migrate.transform_content(fragment)
        self.assertIn("content", result.text)
        self.assertTrue(any("fragmento" in note for note in result.notes))


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class LegacyReadingTests(unittest.TestCase):
    """The conventions, checked against the real material."""

    def test_the_four_language_conventions(self):
        cases = [
            ("03VAL-espacios-normados.tex", "va", "03", "espacios-normados"),
            ("01-CAST-Handout-Calcular_limites.tex", "es", "01", "Handout-Calcular_limites"),
            ("ENG-something.tex", "en", "", "something"),
            ("22-Axiomas-cuerpo.tex", "es", "22", "Axiomas-cuerpo"),
        ]
        for name, language, ordinal, slug in cases:
            with self.subTest(name=name):
                result = legacy.read_name(name)
                self.assertEqual(result.language, language)
                self.assertEqual(result.ordinal, ordinal)
                self.assertEqual(result.slug, slug)

    def test_cas_and_cast_are_the_same_language(self):
        self.assertEqual(legacy.read_name("03CAS-x.tex").language, "es")
        self.assertEqual(legacy.read_name("03CAST-x.tex").language, "es")
        # Longest token first, or CAST reads as CAS with a slug starting `T`.
        self.assertEqual(legacy.read_name("03CAST-x.tex").token, "CAST")

    def test_untokenised_files_are_implicit_castilian(self):
        result = legacy.read_name("22-Axiomas-cuerpo.tex")
        self.assertTrue(result.implicit)
        self.assertEqual(result.language, "es")

    def test_language_variants_group_into_one_unit(self):
        directory = "00classnotes/02Derivacion/00Presentaciones/01Definicion"
        a = legacy.logical_key(directory, legacy.read_name("00CAS-Definicion.tex"))
        b = legacy.logical_key(directory, legacy.read_name("00ENG-Definicion.tex"))
        self.assertEqual(a, b)

    def test_ordering_prefixes_are_dropped_from_identifiers(self):
        self.assertEqual(repo_mod.slugify("40functional"), "functional")
        self.assertEqual(repo_mod.slugify("00 AM III A"), "am-iii-a")
        self.assertEqual(repo_mod.slugify("912Secciones-conicas"), "secciones-conicas")
        # Unless the name is genuinely numeric.
        self.assertEqual(repo_mod.slugify("2026"), "2026")

    def test_kinds_and_topics_come_from_the_folders(self):
        theory = "00classnotes/40functional/00Presentaciones/01Espacios-normados/03VAL-x.tex"
        self.assertEqual(legacy.kind_of(theory), "theory")
        self.assertEqual(legacy.topic_of(theory), "espacios-normados")

        problem = "00classnotes/EDOs/03Problems/practice/11-orde-2-Wronskian/10-ENG-y.tex"
        self.assertEqual(legacy.kind_of(problem), "problem")
        self.assertEqual(legacy.path_tags(problem), ["practice", "orde-2-wronskian"])

    def test_the_handoout_typo_is_tolerated(self):
        # Real folder names in the material misspell it.
        self.assertEqual(
            legacy.kind_of("x/Handoout-Metodo-de-inspeccion/00Notas.tex"), "handout")

    def test_year_directories_keep_their_leading_space(self):
        years = legacy.year_dirs(LEGACY)
        self.assertTrue(years)
        self.assertTrue(any(name.startswith(" ") for name, _ in years))
        self.assertTrue(any(year == "2025-2026" for _, year in years))

    def test_reading_a_non_utf8_file_does_not_raise(self):
        # 44 of the 5529 tracked .tex files are latin-1 leftovers. Being strict
        # here is how a migration run dies two thousand files in.
        paths = legacy.git_files(LEGACY, "*.tex")
        broken = []
        for path in paths:
            try:
                legacy.read_file(LEGACY, path)
            except Exception as exc:  # noqa: BLE001 - that is the point
                broken.append("%s: %r" % (path, exc))
        self.assertEqual(broken, [], "\n".join(broken[:5]))

    def test_classinfo_gives_the_course_language(self):
        path = os.path.join(LEGACY, " 2025-2026", "00 AM III A", "classinfoA.tex")
        if not os.path.isfile(path):
            self.skipTest("reference classinfo not present")
        info = legacy.parse_classinfo(legacy.read_file(LEGACY, os.path.relpath(path, LEGACY)))
        self.assertEqual(info["code"], "34157")
        # The exercise wording is the strongest language signal a course has.
        self.assertEqual(legacy.language_from_classinfo(info), "va")

    def test_accents_are_decoded_in_extracted_titles(self):
        # A library listing showing "Definici\'on" would be a bug.
        self.assertEqual(
            legacy.extract_title(r"\frametitle{Definici\'on de norma}"),
            "Definición de norma",
        )


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class PlanningTests(unittest.TestCase):
    """Planning against the real library."""

    @classmethod
    def setUpClass(cls):
        cls.target = tempfile.mkdtemp(prefix="didacta-plan-")
        cls.plan = migrate.plan_units(LEGACY, cls.target, category="40functional")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.target, ignore_errors=True)

    def test_planning_writes_nothing(self):
        self.assertEqual(os.listdir(self.target), [])

    def test_units_are_found(self):
        self.assertGreater(len(self.plan.units), 100)
        self.assertEqual(self.plan.errors, [])

    def test_every_unit_has_a_reference_language_that_exists(self):
        for unit in self.plan.units:
            self.assertIn(unit.reference, unit.languages, unit.target)

    def test_targets_are_unique(self):
        targets = [unit.relpath for unit in self.plan.units]
        self.assertEqual(len(targets), len(set(targets)), "two units share a target")

    def test_ordering_prefixes_are_gone_from_targets(self):
        for unit in self.plan.units:
            for segment in unit.relpath.split("/"):
                self.assertFalse(
                    segment[:1].isdigit() and any(c.isalpha() for c in segment),
                    "%s keeps an ordering prefix" % unit.relpath,
                )

    def test_problems_go_to_the_problems_tree(self):
        problems = [u for u in self.plan.units if u.kind == "problem"]
        self.assertTrue(problems)
        for unit in problems:
            self.assertTrue(unit.relpath.startswith("problems/"), unit.relpath)

    def test_theory_goes_to_the_content_tree(self):
        theory = [u for u in self.plan.units if u.kind == "theory"]
        self.assertTrue(theory)
        for unit in theory:
            self.assertTrue(unit.relpath.startswith("content/"), unit.relpath)

    def test_every_unit_reports_what_needs_deciding(self):
        # The legacy material records no tags, prerequisites, objectives or
        # duration, so every unit should say so rather than have them invented.
        for unit in self.plan.units:
            self.assertTrue(unit.needs_decision, unit.relpath)

    def test_no_unit_is_overwritten_by_another(self):
        """The bug that would have lost 84 units of real material.

        Dropping the ordering prefix is right, but eight different
        ``Ejercicios.tex`` in one folder then claim the same target and the last
        one written wins. Repo-wide, 66 targets were claimed by 150 units.
        """
        targets = [unit.relpath for unit in self.plan.units]
        self.assertEqual(len(targets), len(set(targets)))

    def test_a_disambiguated_unit_is_asked_to_be_renamed(self):
        # Deterministic and unique is enough to be safe, not enough to be good;
        # the author is the only one who can name these.
        renamed = [u for u in self.plan.units
                   if any("un nombre propio" in d for d in u.needs_decision)]
        for unit in renamed:
            # The old ordinal is what distinguishes them.
            self.assertRegex(unit.relpath.rsplit("/", 1)[-1], r"-[0-9a-z]+$")

    def test_language_distribution_matches_the_measurement(self):
        summary = self.plan.summary()
        self.assertEqual(summary["units"], len(self.plan.units))
        self.assertGreater(sum(summary["byLanguages"].values()), 100)


class VocabularyTests(unittest.TestCase):
    """The three modules that name unit kinds have to agree.

    They drifted once: ``legacy.py`` could emit ``practical`` and
    ``profiles.py`` knew what to build for it, but ``repo.py`` rejected it, so a
    full migration wrote 93 units that the repository model refused to load.
    Nothing caught it until the whole library was migrated, which is too late.
    """

    def test_every_kind_the_legacy_reader_emits_is_a_valid_unit_kind(self):
        for folder, kind in sorted(legacy.KIND_BY_FOLDER.items()):
            with self.subTest(folder=folder):
                self.assertIn(kind, repo_mod.UNIT_KINDS)

    def test_kind_of_never_invents_a_kind(self):
        # Including the fallbacks, which are reached by path substring rather
        # than by a folder in the table.
        paths = [
            "00classnotes/x/00Presentaciones/y/01CAS-a.tex",
            "00classnotes/x/00Prácticas/y/01CAS-a.tex",
            "00classnotes/x/Handoout-z/01CAS-a.tex",
            "00classnotes/x/ejercicios/01CAS-a.tex",
            "00classnotes/x/whatever/01CAS-a.tex",
        ]
        for path in paths:
            with self.subTest(path=path):
                self.assertIn(legacy.kind_of(path), repo_mod.UNIT_KINDS)

    def test_every_kind_can_be_built(self):
        # A kind with no profile family falls back to `notes`, which is a
        # reasonable default but a silent one, so the mapping is asserted for
        # the kinds where the fallback would be wrong.
        from didacta import profiles as profiles_mod
        for kind in ("theory", "problem", "handout", "seminar", "practical"):
            with self.subTest(kind=kind):
                self.assertIn(
                    kind if kind != "problem" else "problems",
                    profiles_mod.FAMILY_FOR_KIND,
                )

    def test_every_family_in_the_kind_map_is_a_real_family(self):
        from didacta import profiles as profiles_mod
        registry = profiles_mod.load(os.path.join(ROOT, "latex"))
        families = {profile.family for profile in registry.values()}
        for kind, wanted in profiles_mod.FAMILY_FOR_KIND.items():
            for family in wanted:
                with self.subTest(kind=kind, family=family):
                    self.assertIn(family, families)


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class WholeLibraryTests(unittest.TestCase):
    """The whole library planned at once.

    Per-category planning cannot see a collision between two categories, and
    the migration is going to be run over everything.
    """

    @classmethod
    def setUpClass(cls):
        cls.target = tempfile.mkdtemp(prefix="didacta-all-")
        cls.plan = migrate.plan_units(LEGACY, cls.target)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.target, ignore_errors=True)

    def test_the_whole_library_maps_to_distinct_targets(self):
        targets = [unit.relpath for unit in self.plan.units]
        collisions = sorted({t for t in targets if targets.count(t) > 1})
        self.assertEqual(collisions, [], "%d targets claimed twice" % len(collisions))

    def test_the_library_is_the_size_it_was_measured_to_be(self):
        # A large change here means the grouping rules moved, which is worth
        # noticing deliberately rather than discovering in a migration run.
        self.assertGreater(len(self.plan.units), 2000)
        self.assertEqual(self.plan.errors, [])

    def test_every_source_file_is_either_planned_or_explicitly_skipped(self):
        """Nothing falls through the cracks silently."""
        planned = set()
        for unit in self.plan.units:
            planned.update(unit.sources.values())
        skipped = {path for path, _reason in self.plan.skipped}
        paths = [p for p in legacy.git_files(LEGACY, legacy.CLASSNOTES + "/**/*.tex",
                                             legacy.CLASSNOTES + "/*.tex")]
        unaccounted = [p for p in paths if p not in planned and p not in skipped]
        self.assertEqual(unaccounted[:10], [], "%d files unaccounted for" % len(unaccounted))

    def test_every_planned_kind_is_one_the_repository_accepts(self):
        """What the full-library run caught: 93 units with a rejected kind."""
        for unit in self.plan.units:
            self.assertIn(unit.kind, repo_mod.UNIT_KINDS, unit.relpath)

    def test_no_target_escapes_the_content_or_problems_tree(self):
        for unit in self.plan.units:
            self.assertIn(unit.relpath.split("/")[0],
                          (repo_mod.CONTENT, repo_mod.PROBLEMS), unit.relpath)
            self.assertNotIn("..", unit.relpath.split("/"), unit.relpath)


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class ApplyTests(unittest.TestCase):
    """Applying, and the guarantee that the source is untouched."""

    @classmethod
    def setUpClass(cls):
        cls.target = tempfile.mkdtemp(prefix="didacta-apply-")
        cls.before = cls._snapshot()
        cls.plan = migrate.plan_units(
            LEGACY, cls.target, category="40functional", limit=12)
        cls.created, cls.problems = migrate.apply_plan(cls.plan, dry_run=False)
        cls.after = cls._snapshot()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.target, ignore_errors=True)

    @classmethod
    def _snapshot(cls):
        """Sizes of every tracked legacy file, to prove nothing changed."""
        entries = []
        for path in legacy.git_files(LEGACY, "00classnotes/*"):
            absolute = os.path.join(LEGACY, path)
            if os.path.isfile(absolute):
                entries.append((path, os.path.getsize(absolute)))
        return sorted(entries)

    def test_the_source_repository_is_untouched(self):
        """The guarantee migration cannot break.

        The legacy material has to keep compiling with its own Makefiles for as
        long as it takes to move everything across.
        """
        self.assertEqual(self.before, self.after)

    def test_no_problems(self):
        self.assertEqual(self.problems, [])

    def test_files_were_written(self):
        self.assertGreater(len(self.created), 12)
        self.assertIn(repo_mod.SETTINGS, self.created)

    def test_every_unit_got_a_metadata_file(self):
        for unit in self.plan.units:
            path = os.path.join(self.target, unit.relpath, "unit.yaml")
            self.assertTrue(os.path.isfile(path), unit.relpath)

    def test_language_files_are_named_by_language(self):
        for unit in self.plan.units:
            for code in unit.languages:
                path = os.path.join(self.target, unit.relpath, "%s.tex" % code)
                self.assertTrue(os.path.isfile(path), path)

    def test_the_result_is_a_valid_didacta_repository(self):
        """The real proof: the output loads as a content repository.

        Anything less and the migration has produced files that only look
        right.
        """
        settings = repo_mod.Settings.load(self.target)
        units, errors = repo_mod.scan_units(self.target, settings)
        self.assertEqual(errors, [])
        self.assertEqual(len(units), len(self.plan.units))
        for unit in units.values():
            self.assertEqual(unit.warnings, [], unit.relpath)

    def test_migrated_units_arrive_as_draft(self):
        # Moved, not reviewed in the new system. Claiming otherwise would be
        # the migration asserting a review that never happened.
        settings = repo_mod.Settings.load(self.target)
        units, _ = repo_mod.scan_units(self.target, settings)
        for unit in units.values():
            for code in unit.available_languages:
                self.assertEqual(
                    unit.languages[code].declared_status, "draft", unit.relpath)

    def test_dry_run_writes_nothing(self):
        empty = tempfile.mkdtemp(prefix="didacta-dry-")
        try:
            plan = migrate.plan_units(LEGACY, empty, category="40functional", limit=5)
            created, problems = migrate.apply_plan(plan, dry_run=True)
            self.assertEqual(problems, [])
            self.assertTrue(created, "a dry run should still report what it would create")
            self.assertEqual(os.listdir(empty), [], "a dry run wrote to disk")
        finally:
            shutil.rmtree(empty, ignore_errors=True)


class EnvironmentTests(unittest.TestCase):
    """Environments the old preambles declared per file.

    These are not aliases: the preamble that declared them is exactly what
    migration deletes, so without the rename the unit does not compile at all.
    ``ejer`` is used 2993 times -- more than every ``ej`` in the library -- and
    it took building everything to find it.
    """

    def transform(self, body):
        return migrate.transform_content(
            "\\begin{document}\n%s\n\\end{document}\n" % body)

    def test_the_per_file_environments_are_renamed(self):
        cases = {
            "ejer": "exercise", "prob": "exercise", "problema": "exercise",
            "ejem": "example", "ejemplo": "example",
            "df": "definition", "definicion": "definition",
            "teo": "theorem", "teorema": "theorem",
            "cuestion": "question", "nota": "remark",
            "recipe": "algorithm",
        }
        for old, new in cases.items():
            with self.subTest(environment=old):
                result = self.transform(
                    "\\begin{%s}texto\\end{%s}" % (old, old))
                self.assertIn("\\begin{%s}" % new, result.text)
                self.assertIn("\\end{%s}" % new, result.text)
                self.assertNotIn("{%s}" % old, result.text)

    def test_a_written_solution_becomes_a_proof_not_a_solution(self):
        """`sol` wrapped \\begin{proof}: prose that was always shown.

        Didacta's `solution` sits behind the solutions axis, so mapping it
        there would quietly drop the content from the student copy -- the
        failure mode the whole answer-level design exists to prevent.
        """
        result = self.transform(r"\begin{sol}La demostración.\end{sol}")
        self.assertIn(r"\begin{proof}", result.text)
        self.assertNotIn("solution", result.text)

    def test_the_starred_form_is_renamed_too(self):
        # `\begin{defn*}` is an unnumbered definition, and Didacta declares
        # `definition*` alongside every theorem environment.
        result = self.transform(r"\begin{defn*}x\end{defn*}")
        self.assertIn(r"\begin{definition*}", result.text)
        self.assertIn(r"\end{definition*}", result.text)

    def test_an_environment_with_no_home_is_reported(self):
        """The safety net.

        A `\begin{X}` Didacta does not provide is a compile error, and a
        compile error found by building 2147 units one day is found too late.
        """
        result = self.transform(r"\begin{Beqnarray*}x\end{Beqnarray*}")
        self.assertTrue(
            any("Didacta no define" in note for note in result.notes),
            result.notes,
        )

    def test_what_didacta_provides_is_not_reported(self):
        for environment in ("theorem", "definition", "exercise", "solution",
                            "itemize", "align*", "tikzpicture", "frame",
                            "tcolorbox", "proof", "algorithm", "notation",
                            "displaystyle"):
            with self.subTest(environment=environment):
                result = self.transform(
                    "\\begin{%s}x\\end{%s}" % (environment, environment))
                self.assertFalse(
                    [n for n in result.notes if "Didacta no define" in n],
                    "%s reported as unknown" % environment,
                )

    def test_every_rename_target_is_an_environment_that_exists(self):
        for target in set(migrate._ENV_RENAMES.values()):
            with self.subTest(target=target):
                self.assertIn(target, migrate.PROVIDED_ENVIRONMENTS)


@unittest.skipUnless(legacy_available(), "the legacy repository is not present")
class FigureTests(unittest.TestCase):
    """Graphics move with their unit, so the reference has to move too.

    710 of the 2147 units reference a graphic. Copying the file and leaving
    ``\includegraphics{img/circle-1}`` behind breaks every one of them.
    """

    @classmethod
    def setUpClass(cls):
        cls.target = tempfile.mkdtemp(prefix="didacta-fig-")
        cls.plan = migrate.plan_units(LEGACY, cls.target)
        cls.with_figures = [u for u in cls.plan.units if u.figures]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.target, ignore_errors=True)

    def test_the_library_really_does_use_figures(self):
        self.assertGreater(len(self.with_figures), 500)

    def test_a_found_figure_is_pointed_at_its_new_home(self):
        unit = next(u for u in self.with_figures
                    if any("/" in reference for reference in u.figures))
        near = sorted(unit.sources.values())[0]
        mapping = migrate.figure_map(LEGACY, unit.figures, near)
        self.assertTrue(mapping)
        for reference, target in mapping.items():
            self.assertTrue(target.startswith("figures/"), target)
            self.assertNotIn("..", target)

    def test_the_rewritten_reference_appears_in_the_migrated_text(self):
        unit = next(u for u in self.with_figures
                    if len(migrate.figure_map(
                        LEGACY, u.figures, sorted(u.sources.values())[0])) > 0)
        near = sorted(unit.sources.values())[0]
        mapping = migrate.figure_map(LEGACY, unit.figures, near)
        result = migrate.transform_content(
            legacy.read_file(LEGACY, near), source_path=near, figures=mapping)
        for target in mapping.values():
            self.assertIn(target, result.text)

    def test_distinct_files_get_distinct_names(self):
        """Otherwise one silently replaces the other in figures/.

        Two references may share a target -- ``\\includegraphics`` takes the
        extension as optional, so one unit writes both ``img/corte1`` and
        ``img/corte1.png`` for one file. What must never share a target is two
        *different* files.
        """
        for unit in self.with_figures:
            targets = [name for _path, name in migrate.figure_targets(LEGACY, unit)]
            self.assertEqual(len(targets), len(set(targets)), unit.relpath)

    def test_one_file_referenced_twice_is_copied_once(self):
        def shares_a_file(unit):
            near = sorted(unit.sources.values())[0]
            found = [migrate._find_figure(LEGACY, near, r) for r in unit.figures]
            found = [path for path in found if path]
            return len(found) > len(set(found))

        unit = next((u for u in self.with_figures if shares_a_file(u)), None)
        if unit is None:
            self.skipTest("no unit refers to one file two ways")
        near = sorted(unit.sources.values())[0]
        mapping = migrate.figure_map(LEGACY, unit.figures, near)
        copies = migrate.figure_targets(LEGACY, unit)
        self.assertLess(len(copies), len(mapping))
        # And both references point at the same copy.
        for reference, target in mapping.items():
            found = migrate._find_figure(LEGACY, near, reference)
            self.assertEqual(
                target, "figures/%s" % dict(copies)[found])

    def test_a_missing_figure_is_reported_and_left_alone(self):
        """Reported rather than rewritten to a file that is not there."""
        mapping = {}
        result = migrate.transform_content(
            "\\begin{document}\n\\includegraphics[width=3cm]{img/nope}\n"
            "\\end{document}\n",
            figures=mapping)
        self.assertIn("{img/nope}", result.text)
        self.assertTrue(any("no se ha encontrado" in n for n in result.notes),
                        result.notes)

    def test_the_optional_argument_survives(self):
        result = migrate.transform_content(
            "\\begin{document}\n"
            "\\includegraphics[width=0.5\\textwidth]{img/a}\n"
            "\\end{document}\n",
            figures={"img/a": "figures/a.pdf"})
        self.assertIn(r"\includegraphics[width=0.5\textwidth]{figures/a.pdf}",
                      result.text)


class LegacyMacroTests(unittest.TestCase):
    """Macros the old preamble supplied.

    Every one of these was found by migrating the library and compiling it, not
    by reading the code. A note in the report is not enough when the result is
    a document that does not build at all.
    """

    def transform(self, body):
        return migrate.transform_content(
            "\\begin{document}\n%s\n\\end{document}\n" % body)

    def test_metadata_macros_are_left_for_didacta_to_define(self):
        """`\\profesor` and friends are aliases now, so the text stays.

        Content across the library builds its own page headers out of them, and
        Didacta holds every value in the language being built. Rewriting would
        mean editing hundreds of files to say the same thing.
        """
        result = self.transform(r"\raisebox{-1mm}{Profesor: \profesor}")
        self.assertIn(r"\profesor", result.text)

    def test_a_macro_didacta_cannot_supply_is_removed(self):
        # \texpath told the old build where to look for files. There is nothing
        # to point it at, and leaving it is an undefined control sequence.
        cleaned, macros = migrate._drop_legacy_macros(r"\nohyphens Derivades")
        self.assertEqual(cleaned, "Derivades")
        self.assertEqual(macros, ["nohyphens"])

    def test_sec_outside_maths_becomes_the_group(self):
        """`(\\sec)` in a header is "Missing $ inserted".

        LaTeX's `\\sec` is the secant; the old templates redefined it as the
        course group. 12 of the 127 documents in 2025-2026 failed on this.
        """
        result = self.transform(r"\raisebox{-1mm}{ \classlong \ (\sec)}")
        self.assertIn(r"\didactaCourseGroup", result.text)
        self.assertNotIn(r"\sec", result.text)

    def test_sec_inside_maths_stays_the_secant(self):
        # 98 uses are the real function, and rewriting those would be wrong.
        for maths in (r"$\tan^2 x + 1 = \sec^2 x$",
                      r"\[ \sec^{2}\theta \]",
                      r"\( 1/\cos = \sec \)"):
            with self.subTest(maths=maths):
                result = self.transform(maths)
                self.assertIn(r"\sec", result.text)
                self.assertNotIn(r"\didactaCourseGroup", result.text)

    def test_the_faq_question_macro_becomes_the_environment(self):
        """They are the same name.

        In LaTeX `\\begin{question}` *is* `\\question`, so the FAQ template's
        macro and Didacta's environment cannot both exist -- loading a package
        that defines the macro fails with "Command \\question already
        defined", which is exactly what happened to 24 outputs.
        """
        result = self.transform(r"\question{¿Cómo se calcula $\int_0^1 x\,dx$?}")
        self.assertIn(r"\begin{question}", result.text)
        self.assertIn(r"\end{question}", result.text)
        self.assertNotIn(r"\question{", result.text)
        # The maths in the argument has to survive the group read.
        self.assertIn(r"$\int_0^1 x\,dx$", result.text)

    def test_the_question_index_is_dropped_and_reported(self):
        result = self.transform(r"\listofquestions" "\n" r"\question{¿Y?}")
        self.assertNotIn("listofquestions", result.text)
        self.assertTrue(any("índice" in note for note in result.notes),
                        result.notes)


class TitleCleaningTests(unittest.TestCase):
    """Reading a title out of legacy LaTeX."""

    def test_a_comment_does_not_eat_the_title(self):
        """One master's title came out as a bare `%`.

        `\\title{\\classlong\\newline%\\medskip\\newline{\\small Órbitas
        planetarias.}}` -- the `%` comments out the rest of its line only, so
        the comments have to go before the newlines are collapsed.
        """
        raw = "\\classlong\\newline%\\medskip\\newline\n{\\small Órbitas planetarias.}"
        self.assertEqual(
            migrate._title_tail(legacy.clean_text(raw)), "Órbitas planetarias")

    def test_an_escaped_percent_is_not_a_comment(self):
        self.assertEqual(legacy.clean_text(r"Un 50\% de acierto"),
                         r"Un 50\% de acierto")


class OutputNameTests(unittest.TestCase):
    """The PDF file name, which is also the latexmk jobname."""

    @classmethod
    def setUpClass(cls):
        from didacta import profiles as profiles_mod
        cls.profile = profiles_mod.load(os.path.join(ROOT, "latex"))["slides"]

    def test_a_percent_is_removed(self):
        """latexmk reads `%` in -jobname as a placeholder and refuses the job.

        The error it prints says nothing about the title it came from, so one
        document with a stray `%` looked like a broken build.
        """
        name = self.profile.output_name("Tema 1 100% dificil", "es")
        self.assertNotIn("%", name)
        self.assertIn("Tema 1 100 dificil", name)

    def test_a_title_that_is_nothing_but_punctuation_still_names_a_file(self):
        name = self.profile.output_name("%", "es")
        self.assertTrue(name.strip())
        self.assertNotIn("%", name)
        self.assertFalse(name.startswith("-"), name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
