"""Engine tests: profiles, the content model, log parsing.

Fast, no TeX required. The compilation matrix lives in test_outputs.py.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402
from didacta import yamlio  # noqa: E402

LATEX_DIR = os.path.join(ROOT, "latex")
DEMO = os.path.join(ROOT, "examples", "demo-course")


class ProfileRegistryTests(unittest.TestCase):
    """The registry is parsed from LaTeX, so the parse is load-bearing."""

    @classmethod
    def setUpClass(cls):
        cls.profiles = profiles_mod.load(LATEX_DIR)

    def test_the_documented_profiles_are_all_present(self):
        expected = {
            "slides", "slides-flat", "slides-teacher",
            "notes", "notes-solutions", "notes-teacher", "book", "handout",
            "problems", "problems-answers", "problems-solutions", "problems-teacher",
            "exam", "exam-marking",
        }
        self.assertEqual(set(self.profiles), expected)

    def test_the_doc_comment_is_not_read_as_a_profile(self):
        # The registry documents its own syntax in a comment; without comment
        # stripping the parser reads that line as a profile called `id`.
        self.assertNotIn("id", self.profiles)

    def test_slide_profiles_use_beamer_and_suppress_its_theorems(self):
        for name in ("slides", "slides-flat", "slides-teacher"):
            profile = self.profiles[name]
            self.assertEqual(profile.document_class, "beamer")
            # Without notheorems, beamer's own theorem/definition/lemma/
            # corollary/example/solution collide with Didacta's.
            self.assertIn("notheorems", profile.class_options)

    def test_document_profiles_do_not_use_beamer(self):
        for name in ("notes", "book", "handout", "problems", "exam"):
            self.assertNotEqual(self.profiles[name].document_class, "beamer")

    def test_axes_are_read_correctly(self):
        slides = self.profiles["slides"]
        self.assertTrue(slides.is_slides)
        self.assertTrue(slides.pauses)
        self.assertFalse(slides.is_teacher)
        self.assertFalse(slides.shows_answers)

        flat = self.profiles["slides-flat"]
        self.assertTrue(flat.is_slides)
        self.assertFalse(flat.pauses)

        teacher = self.profiles["problems-teacher"]
        self.assertTrue(teacher.is_teacher)
        self.assertTrue(teacher.shows_answers)
        self.assertTrue(teacher.shows_solutions)

    def test_the_solutions_axis_has_three_distinct_levels(self):
        self.assertFalse(self.profiles["problems"].shows_answers)
        self.assertTrue(self.profiles["problems-answers"].shows_answers)
        self.assertFalse(self.profiles["problems-answers"].shows_solutions)
        self.assertTrue(self.profiles["problems-solutions"].shows_solutions)

    def test_families_group_profiles_sensibly(self):
        self.assertEqual(self.profiles["slides"].family, "slides")
        self.assertEqual(self.profiles["notes"].family, "notes")
        self.assertEqual(self.profiles["problems"].family, "problems")
        self.assertEqual(self.profiles["handout"].family, "handout")
        self.assertEqual(self.profiles["exam"].family, "exam")

    def test_defaults_per_document_kind(self):
        theory = {p.id for p in profiles_mod.default_profiles(self.profiles, "theory")}
        self.assertIn("slides", theory)
        self.assertIn("notes", theory)
        self.assertNotIn("problems", theory)

        problems = {p.id for p in profiles_mod.default_profiles(self.profiles, "problems")}
        self.assertEqual(
            problems,
            {"problems", "problems-answers", "problems-solutions", "problems-teacher"},
        )

    def test_labels_are_derived_and_never_contradict_the_axes(self):
        # Derived rather than stored, so a new profile gets a sensible label
        # for free and the label cannot disagree with what it does.
        self.assertIn("profesor", self.profiles["notes-teacher"].label)
        self.assertIn("sin pausas", self.profiles["slides-flat"].label)
        for profile in self.profiles.values():
            if profile.is_teacher:
                self.assertIn("profesor", profile.label, profile.id)

    def test_pretex_is_the_whole_interface_to_latex(self):
        pretex = self.profiles["slides"].pretex("va", "../../")
        self.assertIn(r"\def\DidactaProfile{slides}", pretex)
        self.assertIn(r"\def\DidactaLanguage{va}", pretex)
        self.assertIn(r"\def\DidactaContentRoot{../../}", pretex)

    def test_output_names_are_readable_and_filesystem_safe(self):
        name = self.profiles["problems-solutions"].output_name(
            "Hoja 1: espacios normados", "es")
        self.assertEqual(name, "Hoja 1 espacios normados - problems-solutions - es")
        for character in ':/\\*?"<>|':
            self.assertNotIn(character, name)

    def test_output_names_keep_accents(self):
        # Accents are meaningful in these titles and every filesystem in use
        # handles them.
        name = self.profiles["notes"].output_name("Anàlisi matemàtica", "va")
        self.assertIn("Anàlisi matemàtica", name)

    def test_an_unknown_axis_value_is_rejected(self):
        with self.assertRaises(profiles_mod.ProfileError):
            profiles_mod.parse(
                r"\DidactaDeclareProfile{x}{article}{}{medium=hologram}")

    def test_an_unknown_axis_name_is_rejected(self):
        with self.assertRaises(profiles_mod.ProfileError):
            profiles_mod.parse(
                r"\DidactaDeclareProfile{x}{article}{}{colour=blue}")

    def test_an_empty_registry_is_rejected(self):
        with self.assertRaises(profiles_mod.ProfileError):
            profiles_mod.parse("% nothing here")


class LogParsingTests(unittest.TestCase):
    """Errors have to point at the content file, not the wrapper."""

    LOG = r"""
This is pdfTeX, Version 3.14
(./tema-1.tex (/opt/didacta/latex/didacta-bootstrap.tex)
(../../../content/analysis/normed-spaces/definition/va.tex
! Undefined control sequence.
l.42 \nosuchcommand
                    {x}
)
LaTeX Warning: Reference `def:normed' on page 2 undefined on input line 55.
Output written on out.pdf (7 pages, 221091 bytes).
"""

    def test_error_is_attributed_to_the_content_file(self):
        diagnostics = build_mod.parse_log(self.LOG)
        errors = [d for d in diagnostics if d.severity == "error"]
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0].line, 42)
        self.assertIn("Undefined control sequence", errors[0].message)
        self.assertIn("va.tex", errors[0].file or "")

    def test_actionable_warnings_are_reported(self):
        diagnostics = build_mod.parse_log(self.LOG)
        warnings = [d for d in diagnostics if d.severity == "warning"]
        self.assertTrue(any("Reference" in d.message for d in warnings))

    def test_noise_is_not_reported(self):
        # An underfull box on a slide is normal; listing them all trains the
        # reader to ignore the list.
        noisy = "Underfull \\hbox (badness 10000) in paragraph at lines 3--4\n"
        self.assertEqual(build_mod.parse_log(noisy), [])

    def test_page_count(self):
        self.assertEqual(build_mod.page_count(self.LOG), 7)
        self.assertIsNone(build_mod.page_count("no output line"))

    def test_page_count_survives_a_wrapped_log_line(self):
        # pdfTeX wraps long lines, so the count may straddle a newline.
        wrapped = "Output written on /very/long/path/out.pdf (12 pa\nges, 1 bytes)."
        self.assertEqual(build_mod.page_count(wrapped), 12)


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.build_dir = tempfile.mkdtemp(prefix="didacta-test-")
        self.engine = build_mod.Engine(LATEX_DIR, self.build_dir)

    def tearDown(self):
        shutil.rmtree(self.build_dir, ignore_errors=True)

    def test_texinputs_puts_didacta_first_and_keeps_the_distribution(self):
        texinputs = self.engine.texinputs()
        self.assertTrue(texinputs.startswith(LATEX_DIR))
        self.assertIn(os.path.join(LATEX_DIR, "lang"), texinputs)
        # A trailing empty entry is required, or the standard search path is
        # replaced rather than extended and nothing is found at all.
        self.assertTrue(texinputs.endswith(os.pathsep) or texinputs.endswith(""))

    def test_every_profile_command_keeps_synctex_and_builds_out_of_tree(self):
        for profile in self.engine.profiles.values():
            command = " ".join(
                self.engine._command("m.tex", "job", "/tmp/out", profile, "es", "../")
            )
            self.assertIn("-synctex=1", command, profile.id)
            self.assertIn("/tmp/out", command, profile.id)
            self.assertNotIn("clean", command, profile.id)

    def test_latexmk_forces_a_run(self):
        # The profile arrives on the command line, so latexmk cannot tell that
        # it differs from last time; without -g it would skip the rebuild.
        command = self.engine._command(
            "m.tex", "job", "/tmp/out", self.engine.profiles["slides"], "es", None)
        self.assertIn("-g", command)

    def test_unknown_profile_and_language_are_refused(self):
        source = os.path.join(DEMO, "courses", "am-iii", "2025-2026", "tema-1.tex")
        with self.assertRaises(build_mod.BuildError):
            self.engine.build(source, "no-such-profile", "es")
        with self.assertRaises(build_mod.BuildError):
            self.engine.build(source, "notes", "fr")

    def test_a_missing_source_is_refused(self):
        with self.assertRaises(build_mod.BuildError):
            self.engine.build("/nonexistent/x.tex", "notes", "es")

    def test_injection_file_carries_the_structure_metadata(self):
        outdir = os.path.join(self.build_dir, "inject")
        os.makedirs(outdir)
        path = self.engine._write_injection(
            outdir, "Tema 1", "title = {Análisis III},\n  code = {34157}")
        self.assertIsNotNone(path)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn(r"\DidactaDocument{Tema 1}", text)
        self.assertIn("Análisis III", text)
        self.assertIn("Do not edit", text)

    def test_no_injection_file_when_there_is_nothing_to_inject(self):
        outdir = os.path.join(self.build_dir, "empty")
        os.makedirs(outdir)
        self.assertIsNone(self.engine._write_injection(outdir, None, None))


class ContentRepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = repo_mod.find_root(DEMO)
        cls.settings = repo_mod.Settings.load(cls.root)
        cls.units, cls.unit_errors = repo_mod.scan_units(cls.root, cls.settings)
        cls.courses, cls.course_errors = repo_mod.scan_courses(cls.root, cls.settings)

    def test_the_example_repository_is_consistent(self):
        self.assertEqual(self.unit_errors, [])
        self.assertEqual(self.course_errors, [])
        for unit in self.units.values():
            self.assertEqual(unit.warnings, [], unit.relpath)

    def test_find_root_walks_up(self):
        deep = os.path.join(DEMO, "content", "analysis", "normed-spaces", "definition")
        self.assertEqual(repo_mod.find_root(deep), self.root)

    def test_no_repository_is_reported_clearly(self):
        with self.assertRaises(repo_mod.RepoError):
            repo_mod.find_root(tempfile.gettempdir())

    def test_units_are_found_by_their_language_files(self):
        # Walking for `<language>.tex` rather than `unit.yaml` means content
        # that has just been migrated, before anyone wrote metadata, is still
        # found and still builds.
        self.assertIn("analysis.normed-spaces.definition", self.units)
        self.assertIn("problems.analysis.normed-spaces.norm-axioms", self.units)

    def test_a_problem_is_classified_as_one(self):
        unit = self.units["problems.analysis.normed-spaces.norm-axioms"]
        self.assertTrue(unit.is_problem)
        self.assertEqual(unit.kind, "problem")

    def test_language_availability_reflects_the_files_on_disk(self):
        unit = self.units["analysis.normed-spaces.definition"]
        self.assertEqual(unit.available_languages, ["es", "va"])
        self.assertEqual(unit.missing_languages, ["en"])
        self.assertTrue(unit.path_for("va").endswith("va.tex"))
        self.assertIsNone(unit.path_for("en"))

    def test_statuses(self):
        statuses = self.units["analysis.normed-spaces.definition"].statuses()
        # The reference language is `source`: it is not a translation of
        # anything, and calling it `reviewed` would claim a review nobody did.
        self.assertEqual(statuses["es"], "reviewed")   # declared explicitly
        self.assertEqual(statuses["va"], "translated")
        self.assertEqual(statuses["en"], "missing")

    def test_outdated_beats_a_declared_status(self):
        entry = repo_mod.LanguageFile(
            "va", "va.tex", exists=True,
            declared_status="reviewed", source_hash="sha256:old")
        self.assertEqual(entry.status("es", "sha256:new"), "outdated")

    def test_a_declared_computed_status_is_rejected(self):
        # `missing` and `outdated` are facts, not declarations; writing them
        # down guarantees they go stale.
        directory = tempfile.mkdtemp(prefix="didacta-unit-")
        try:
            with open(os.path.join(directory, "es.tex"), "w") as handle:
                handle.write("content")
            with open(os.path.join(directory, "unit.yaml"), "w") as handle:
                handle.write("id: x\nlanguages:\n  va: {status: missing}\n")
            parent, name = os.path.split(directory)
            unit = repo_mod.load_unit(parent, name, self.settings)
            self.assertTrue(any("computed" in w for w in unit.warnings))
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_a_unit_with_no_language_file_is_an_error(self):
        directory = tempfile.mkdtemp(prefix="didacta-empty-")
        try:
            with open(os.path.join(directory, "unit.yaml"), "w") as handle:
                handle.write("id: x\n")
            parent, name = os.path.split(directory)
            with self.assertRaises(repo_mod.RepoError):
                repo_mod.load_unit(parent, name, self.settings)
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_titles_fall_back_through_the_languages(self):
        unit = self.units["analysis.normed-spaces.definition"]
        self.assertEqual(unit.title("va"), "Definició i propietats dels espais normats")
        # No English title declared for the induced metric, so it falls back.
        other = self.units["analysis.normed-spaces.induced-metric"]
        self.assertTrue(other.title("en"))

    def test_courses_and_years(self):
        course = self.courses["am-iii"]
        self.assertEqual(course.code, "34157")
        self.assertEqual(course.language, "va")
        self.assertIn("2025-2026", course.years)
        year = course.years["2025-2026"]
        self.assertEqual(len(year.documents), 2)

    def test_a_document_declares_its_own_language(self):
        # The sheet only exists in Castilian, so it builds in Castilian even
        # though the course is taught in Valencian.
        year = self.courses["am-iii"].years["2025-2026"]
        sheet = next(d for d in year.documents if d.id == "hoja-1")
        self.assertEqual(sheet.language, "es")

    def test_course_metadata_is_localised(self):
        course = self.courses["am-iii"]
        keys_es = course.latex_course_keys("es", "2025-2026")
        keys_va = course.latex_course_keys("va", "2025-2026")
        self.assertIn("Análisis Matemático III", keys_es)
        self.assertIn("Anàlisi Matemàtica III", keys_va)
        # Including the group, which is a visible string like any other.
        self.assertIn("Grupo A", keys_es)
        self.assertIn("Grup A", keys_va)

    def test_references_resolve_against_the_content_root(self):
        unit = repo_mod.resolve_unit_ref(
            "analysis/normed-spaces/definition", self.units, self.root)
        self.assertIsNotNone(unit)
        self.assertEqual(unit.id, "analysis.normed-spaces.definition")

    def test_problem_references_resolve_too(self):
        unit = repo_mod.resolve_unit_ref(
            "analysis/normed-spaces/norm-axioms", self.units, self.root)
        self.assertIsNotNone(unit)
        self.assertTrue(unit.is_problem)

    def test_an_unresolvable_reference_returns_none(self):
        self.assertIsNone(
            repo_mod.resolve_unit_ref("nope/not/here", self.units, self.root))

    def test_content_root_is_relative_to_the_document(self):
        # Absolute would break the moment the repository is cloned elsewhere,
        # including in CI.
        source = os.path.join(DEMO, "courses", "am-iii", "2025-2026", "tema-1.tex")
        root = repo_mod.content_root_for(source, DEMO)
        self.assertEqual(root, "../../../")
        self.assertFalse(os.path.isabs(root))

    def test_an_unknown_language_in_settings_is_rejected(self):
        directory = tempfile.mkdtemp(prefix="didacta-settings-")
        try:
            with open(os.path.join(directory, "didacta.yaml"), "w") as handle:
                handle.write("languages: [es, klingon]\n")
            with self.assertRaises(repo_mod.RepoError):
                repo_mod.Settings.load(directory)
        finally:
            shutil.rmtree(directory, ignore_errors=True)

    def test_an_empty_settings_file_still_works(self):
        directory = tempfile.mkdtemp(prefix="didacta-settings-")
        try:
            open(os.path.join(directory, "didacta.yaml"), "w").close()
            settings = repo_mod.Settings.load(directory)
            self.assertEqual(list(settings.languages), ["es", "va", "en"])
            self.assertEqual(settings.default_language, "es")
        finally:
            shutil.rmtree(directory, ignore_errors=True)


class YamlTests(unittest.TestCase):
    def test_reads_the_shapes_the_schemas_use(self):
        data = yamlio.loads(
            "\n".join([
                "name: Demo",
                "languages: [es, va, en]",
                "title:",
                "  es: Uno",
                "  va: U",
                "documents:",
                "  - id: tema-1",
                "    profiles: [slides, notes]",
                "    structure:",
                "      - unit: a/b/c",
                "      - unit: a/b/d",
            ])
        )
        self.assertEqual(data["languages"], ["es", "va", "en"])
        self.assertEqual(data["title"]["va"], "U")
        self.assertEqual(len(data["documents"]), 1)
        self.assertEqual(data["documents"][0]["structure"][1]["unit"], "a/b/d")

    def test_a_quoted_number_stays_a_string(self):
        """Quoting is the only way to say "this is text", so it has to win.

        Found by round-tripping the app's editor through this loader: a tag
        written ``'2025'`` came back as the integer 2025, because the inline
        list parser threw the quotes away before anything looked at them.
        A year or a tag that turns into a number breaks a comparison
        somewhere a long way from the file it came from.
        """
        data = yamlio.loads(
            "\n".join([
                "year: '2025'",
                "tags: [algebra, '2025', '12']",
                "flag: 'true'",
                "empty: 'null'",
                "number: 2025",
                "boolean: true",
                "mixed: [2025, algebra]",
            ])
        )
        self.assertEqual(data["year"], "2025")
        self.assertEqual(data["tags"], ["algebra", "2025", "12"])
        self.assertEqual(data["flag"], "true")
        self.assertEqual(data["empty"], "null")
        # And unquoted still means what it always did.
        self.assertEqual(data["number"], 2025)
        self.assertIs(data["boolean"], True)
        self.assertEqual(data["mixed"], [2025, "algebra"])

    def test_the_escapes_each_quoting_style_has(self):
        data = yamlio.loads(
            "\n".join([
                "single: 'L''Hopital'",
                'double: "con \\"comillas\\""',
                "latex: 'Espacios $\\ell^p$'",
                "inside: [\"a''b\", 'c, d']",
            ])
        )
        self.assertEqual(data["single"], "L'Hopital")
        self.assertEqual(data["double"], 'con "comillas"')
        # A backslash in single quotes is a backslash, which is why the app
        # writes LaTeX in single quotes and not double.
        self.assertEqual(data["latex"], "Espacios $\\ell^p$")
        # A comma inside quotes does not split the list.
        self.assertEqual(data["inside"], ["a''b", "c, d"])

    def test_localised_accepts_a_plain_string(self):
        result = yamlio.localised("One title", ("es", "va", "en"))
        self.assertEqual(result, {"es": "One title", "va": "One title", "en": "One title"})

    def test_localised_rejects_an_unknown_language(self):
        with self.assertRaises(yamlio.YamlError):
            yamlio.localised({"kl": "x"}, ("es", "va", "en"), path="t", key="title")

    def test_a_missing_file_is_reported_with_its_path(self):
        with self.assertRaises(yamlio.YamlError) as caught:
            yamlio.load_file("/nonexistent/unit.yaml")
        self.assertIn("unit.yaml", str(caught.exception))


class LatexPackageTests(unittest.TestCase):
    """Source-level guards on the LaTeX layer."""

    def read(self, name):
        with open(os.path.join(LATEX_DIR, name), encoding="utf-8") as handle:
            return handle.read()

    def test_every_shipped_language_has_a_definition_file(self):
        for code in profiles_mod.LANGUAGES:
            path = os.path.join(LATEX_DIR, "lang", "didacta-lang-%s.def" % code)
            self.assertTrue(os.path.isfile(path), code)

    def test_language_files_define_the_same_set_of_strings(self):
        """A string defined in one language and not another is a hole.

        It surfaces as a blank in the PDF, which is easy to miss and
        embarrassing in a lecture.
        """
        import re

        def names(code):
            text = self.read(os.path.join("lang", "didacta-lang-%s.def" % code))
            return set(re.findall(r"\\def\\(didacta\w+)\{", text))

        reference = names("es")
        self.assertGreater(len(reference), 25)
        for code in ("va", "en"):
            missing = reference - names(code)
            extra = names(code) - reference
            self.assertEqual(missing, set(), "%s is missing %s" % (code, sorted(missing)))
            self.assertEqual(extra, set(), "%s has extra %s" % (code, sorted(extra)))

    def test_legacy_aliases_are_kept(self):
        """Migration is a move, not a rewrite.

        The material being migrated uses these names in hundreds of files.
        """
        formats = self.read("didacta-formats.sty")
        self.assertIn(r"\newcommand{\onlybook}", formats)

        theorems = self.read("didacta-theorems.sty")
        for alias in ("ndefn", "nthrm", "defn", "thrm", "nex", "recipe"):
            self.assertIn("{%s}" % alias, theorems, alias)

        problems = self.read("didacta-problems.sty")
        self.assertIn("{ej}", problems)
        self.assertIn("{shownto}", problems)

    def test_marks_primitive_is_not_overwritten(self):
        # \marks is a TeX primitive; overwriting it breaks output routines in
        # ways that surface much later.
        problems = self.read("didacta-problems.sty")
        self.assertNotIn(r"\newcommand{\marks}", problems)
        self.assertIn(r"\newcommand{\dmarks}", problems)

    def test_the_teacher_channel_is_distinct_from_the_notes_channel(self):
        # In the legacy templates \onlyteacher was defined identically to
        # \onlybook, so it distinguished nothing.
        formats = self.read("didacta-formats.sty")
        self.assertIn("didacta@teacher", formats)
        self.assertIn(
            r"\newcommand{\onlyteacher}[1]{\iftoggle{didacta@teacher}{#1}{}}",
            formats,
        )

    def test_no_non_ctan_package_is_required(self):
        # A system that cannot compile on a clean machine is not a platform.
        banned = (
            "boiboites", "multiaudience", "beamerthemeTorino",
            "beamercolorthemechameleon", "beamerouterthemedecolines",
            "beamerinnerthemefancy", "LaffayetteComicPro",
        )
        for name in sorted(os.listdir(LATEX_DIR)):
            if not name.endswith((".sty", ".tex")):
                continue
            text = self.read(name)
            for package in banned:
                # Mentions in prose comments are fine; a load is not.
                self.assertNotIn(
                    r"\RequirePackage{%s}" % package, text, "%s in %s" % (package, name))
                self.assertNotIn(
                    r"\usepackage{%s}" % package, text, "%s in %s" % (package, name))

    def test_profiles_registry_restores_the_catcode_it_found(self):
        # It is read from the bootstrap (where @ is `other') and again from
        # didacta.sty (where @ is a letter). A blanket \makeatother at the end
        # broke the second caller.
        registry = self.read("didacta-profiles.tex")
        self.assertIn("didacta@profiles@restorecat", registry)
        self.assertNotIn("\n\\makeatother", registry)

    def test_document_profiles_load_beamerarticle_with_notheorems(self):
        # beamerarticle is what makes \begin{frame} work in prose -- the single
        # most important line for having one source.
        main = self.read("didacta.sty")
        self.assertIn(r"\RequirePackage[notheorems]{beamerarticle}", main)

    def test_enumitem_is_not_loaded_for_slides(self):
        # Under beamer it discards the item templates and lists lose their
        # bullets entirely.
        main = self.read("didacta.sty")
        self.assertIn(
            r"\iftoggle{didacta@slides}{}{\RequirePackage{enumitem}}", main)


class ProvidedEnvironmentTests(unittest.TestCase):
    """What the migrator promises a unit can use, Didacta has to supply.

    The two halves drifted twice -- `empheq` and `wrapfigure` were on the
    promised list and no package provided them -- and each time the symptom was
    a migrated unit that simply did not build. Cheap to check here, expensive
    to find by compiling the library.
    """

    #: Environment -> the package that provides it. Only the ones that need a
    #: package: standard LaTeX and Didacta's own are covered elsewhere.
    NEEDS_PACKAGE = {
        "empheq": "empheq",
        "wrapfigure": "wrapfig",
        "multicols": "multicol",
        "tcolorbox": "tcolorbox",
        "tikzpicture": "tikz",
        "axis": "pgfplots",
        "adjustbox": "adjustbox",
        "displayquote": "csquotes",
        "tabularx": "tabularx",
        "longtable": "longtable",
        "tabu": "tabu",
    }

    @classmethod
    def setUpClass(cls):
        cls.sources = {}
        latex = os.path.join(ROOT, "latex")
        for name in sorted(os.listdir(latex)):
            if name.endswith((".sty", ".tex")):
                with open(os.path.join(latex, name), encoding="utf-8") as handle:
                    cls.sources[name] = handle.read()
        cls.all_latex = "\n".join(cls.sources.values())

    def loaded(self, package):
        pattern = re.compile(
            r"\\RequirePackage\s*(?:\[[^\]]*\])?\s*\{([^}]*)\}")
        for match in pattern.finditer(self.all_latex):
            if package in [p.strip() for p in match.group(1).split(",")]:
                return True
        return False

    def test_every_promised_environment_has_its_package(self):
        from didacta import migrate as migrate_mod
        missing = []
        for environment, package in self.NEEDS_PACKAGE.items():
            if environment not in migrate_mod.PROVIDED_ENVIRONMENTS:
                continue
            if not self.loaded(package):
                missing.append("%s needs %s" % (environment, package))
        self.assertEqual(missing, [], "; ".join(missing))

    def test_xcolor_is_loaded_with_table_everywhere(self):
        """An option clash is a hard error, and two files load xcolor.

        `table` is what gives \\rowcolor, which the material uses.
        """
        loads = re.findall(r"\\RequirePackage\s*(\[[^\]]*\])?\s*\{xcolor\}",
                           self.all_latex)
        self.assertTrue(loads, "xcolor is not loaded at all")
        for options in loads:
            self.assertIn("table", options or "",
                          "an xcolor load without `table` clashes with the others")

    def test_the_compatibility_layer_loads_no_new_package(self):
        """D31, asserted.

        `fancybox` and `todonotes` changed the type in every document,
        including ones with no legacy content. A compatibility layer that
        alters correct output is worse than the incompatibility.
        """
        legacy_sty = self.sources.get("didacta-legacy.sty", "")
        self.assertTrue(legacy_sty, "didacta-legacy.sty is missing")
        loads = re.findall(r"\\RequirePackage\s*(?:\[[^\]]*\])?\s*\{([^}]*)\}",
                           legacy_sty)
        names = {p.strip() for group in loads for p in group.split(",")}
        # etoolbox is already a dependency of the rest of Didacta.
        self.assertLessEqual(names, {"etoolbox"}, sorted(names))

    def test_the_tikz_libraries_the_drawings_use_are_loaded(self):
        for library in ("shapes.geometric", "angles", "quotes",
                        "decorations.fractals", "lindenmayersystems"):
            with self.subTest(library=library):
                self.assertIn(library, self.all_latex)


if __name__ == "__main__":
    unittest.main(verbosity=2)
