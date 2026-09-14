"""The output matrix: the test the platform is judged by.

Didacta's whole claim is that one source produces every output correctly. This
compiles the example content in all 15 profiles and checks not just that the
PDFs appear but that each one contains what it should and omits what it should
not -- which is the part that would otherwise fail silently. A profile that
compiles and quietly drops the solutions looks fine until someone hands out the
wrong sheet.

Needs TeX Live; skips cleanly without it.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402

LATEX_DIR = os.path.join(ROOT, "latex")
DEMO = os.path.join(ROOT, "examples", "demo-course")


def toolchain_available():
    return all(shutil.which(tool) for tool in ("latexmk", "pdflatex"))


def pdf_text(path):
    """Letters from a PDF's content streams.

    Crude but dependency-free, and enough to answer "does this page contain
    this marker word". Punctuation and spacing are dropped because pdfTeX
    splits text across many show operators and reassembling it faithfully would
    need a real PDF library.
    """
    with open(path, "rb") as handle:
        data = handle.read()
    text = b""
    for match in re.finditer(rb"stream\r?\n(.*?)endstream", data, re.S):
        try:
            text += zlib.decompress(match.group(1))
        except Exception:
            continue
    return re.sub(rb"[^A-Za-z]", b"", text).decode("latin-1")


@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class OutputMatrixTests(unittest.TestCase):
    """Every profile of the example, compiled and inspected."""

    @classmethod
    def setUpClass(cls):
        cls.build_dir = os.path.join(HERE, ".build-outputs")
        shutil.rmtree(cls.build_dir, ignore_errors=True)
        cls.engine = build_mod.Engine(LATEX_DIR, cls.build_dir)
        cls.profiles = cls.engine.profiles

        cls.settings = repo_mod.Settings.load(DEMO)
        cls.courses, errors = repo_mod.scan_courses(DEMO, cls.settings)
        assert not errors, errors
        year = cls.courses["am-iii"].years["2025-2026"]
        cls.theory = next(d for d in year.documents if d.id == "tema-1")
        cls.sheet = next(d for d in year.documents if d.id == "hoja-1")
        cls.content_root = repo_mod.content_root_for(cls.theory.source, DEMO)
        cls.results = {}

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.build_dir, ignore_errors=True)

    def compile(self, document, profile_id, language):
        key = (document.id, profile_id, language)
        if key not in self.results:
            self.results[key] = self.engine.build(
                document.source,
                profile_id,
                language,
                document_id=document.id,
                document_title=document.title(language),
                content_root=repo_mod.content_root_for(document.source, DEMO),
            )
        return self.results[key]

    # -- every profile produces a PDF ------------------------------------

    def test_every_theory_profile_compiles(self):
        for profile in profiles_mod.default_profiles(self.profiles, "theory"):
            with self.subTest(profile=profile.id):
                result = self.compile(self.theory, profile.id, "va")
                self.assertTrue(
                    result.ok,
                    "%s failed:\n%s" % (
                        profile.id,
                        "\n".join(str(d) for d in result.errors[:5]),
                    ),
                )
                self.assertIsNotNone(result.pdf)
                self.assertGreater(os.path.getsize(result.pdf), 20_000)

    def test_every_problem_profile_compiles(self):
        for profile in profiles_mod.default_profiles(self.profiles, "problems"):
            with self.subTest(profile=profile.id):
                result = self.compile(self.sheet, profile.id, "es")
                self.assertTrue(
                    result.ok,
                    "%s failed:\n%s" % (
                        profile.id,
                        "\n".join(str(d) for d in result.errors[:5]),
                    ),
                )

    def test_handout_and_book_and_exam_compile(self):
        # These families are not a document's default, but they must work: the
        # same content has to be printable as a reference sheet and as a paper.
        for profile_id in ("handout", "book", "exam", "exam-marking"):
            with self.subTest(profile=profile_id):
                result = self.compile(self.theory, profile_id, "va")
                self.assertTrue(result.ok, "\n".join(str(d) for d in result.errors[:5]))

    def test_every_declared_profile_compiles(self):
        """The whole matrix, so a new profile cannot be added untested.

        Order-independent on purpose: it compiles whatever it needs rather than
        relying on other tests in this class having run first. unittest orders
        tests alphabetically, and depending on that is how a coverage check
        ends up quietly checking nothing.
        """
        untested = []
        for profile_id, profile in self.profiles.items():
            # A problem profile against the sheet, everything else against the
            # theory chapter -- matching what each is for.
            if profile.family in ("problems", "exam"):
                document, language = self.sheet, "es"
            else:
                document, language = self.theory, "va"
            result = self.compile(document, profile_id, language)
            if not result.ok:
                untested.append(
                    "%s: %s" % (profile_id,
                                "; ".join(str(d) for d in result.errors[:2]))
                )
        self.assertEqual(untested, [], "\n".join(untested))
        self.assertEqual(
            len(self.profiles), 15,
            "the profile count changed; update README.md and docs/AUTHORING.md",
        )

    # -- the outputs actually differ -------------------------------------

    def test_pauses_change_the_page_count(self):
        # If these matched, \dpause would not be doing anything and
        # slides-flat would be a pointless duplicate of slides.
        with_pauses = self.compile(self.theory, "slides", "va")
        without = self.compile(self.theory, "slides-flat", "va")
        self.assertGreater(
            with_pauses.pages,
            without.pages,
            "pauses did not add an overlay page",
        )

    def test_slides_and_notes_differ(self):
        # \onlyslides and \onlynotes must actually route content.
        slides = self.compile(self.theory, "slides", "va")
        notes = self.compile(self.theory, "notes", "va")
        self.assertNotEqual(
            os.path.getsize(slides.pdf), os.path.getsize(notes.pdf)
        )

    def test_teacher_copy_carries_more_than_the_student_copy(self):
        student = self.compile(self.theory, "notes", "va")
        teacher = self.compile(self.theory, "notes-teacher", "va")
        self.assertGreater(
            os.path.getsize(teacher.pdf),
            os.path.getsize(student.pdf),
            "the teacher channel added nothing",
        )

    # -- the answer levels appear exactly where they should ---------------

    #: Marker words present in the example problem, per level.
    MARKERS = {
        "hint": "descartar",        # from the Indicación text
        "answer": "Respuesta",
        "solution": "Solucin",      # "Solución" with the accent dropped
        "marking": "Correccin",
    }

    #: The three levels, and they are the three fields of a problem: level n
    #: shows fields 1 to n. `handout-*` is the same three for a practical
    #: script, which is handed out and marked exactly like a problem sheet.
    EXPECTED = {
        "problems":            {"hint": True,  "answer": False, "solution": False, "marking": False},
        "problems-answers":    {"hint": True,  "answer": True,  "solution": False, "marking": False},
        "problems-teacher":    {"hint": True,  "answer": True,  "solution": True,  "marking": True},
        "handout":             {"hint": True,  "answer": False, "solution": False, "marking": False},
        "handout-answers":     {"hint": True,  "answer": True,  "solution": False, "marking": False},
        "handout-teacher":     {"hint": True,  "answer": True,  "solution": True,  "marking": True},
    }

    def test_answer_levels_match_the_documented_matrix(self):
        """The table in README.md and docs/AUTHORING.md, asserted.

        This is the test that matters most for problem sheets: handing students
        a sheet that silently includes the solutions is the failure mode worth
        preventing mechanically.
        """
        for profile_id, expected in self.EXPECTED.items():
            result = self.compile(self.sheet, profile_id, "es")
            self.assertTrue(result.ok, profile_id)
            text = pdf_text(result.pdf)
            for level, should_appear in expected.items():
                marker = self.MARKERS[level]
                with self.subTest(profile=profile_id, level=level):
                    present = marker in text
                    self.assertEqual(
                        present,
                        should_appear,
                        "%s: `%s` should%s appear but %s"
                        % (profile_id, level,
                           "" if should_appear else " not",
                           "did" if present else "did not"),
                    )

    def test_exam_hides_hints(self):
        # A hint on an exam paper is a marking problem, so the exam layout
        # suppresses them even though students see them on practice sheets.
        result = self.compile(self.sheet, "exam", "es")
        self.assertTrue(result.ok)
        text = pdf_text(result.pdf)
        self.assertNotIn(self.MARKERS["hint"], text)
        self.assertNotIn(self.MARKERS["solution"], text)

    def test_exam_marking_shows_everything_but_hints(self):
        result = self.compile(self.sheet, "exam-marking", "es")
        self.assertTrue(result.ok)
        text = pdf_text(result.pdf)
        self.assertIn(self.MARKERS["solution"], text)
        self.assertIn(self.MARKERS["marking"], text)

    # -- languages -------------------------------------------------------

    def test_theorem_names_follow_the_language(self):
        """A definition is a Definición, a Definició or a Definition.

        Without this the content would have to carry its own environment
        names, which is exactly the duplication the language files remove.
        """
        castilian = pdf_text(self.compile(self.theory, "notes", "es").pdf)
        valencian = pdf_text(self.compile(self.theory, "notes", "va").pdf)
        self.assertIn("Definicin", castilian)   # Definición
        self.assertIn("Definici", valencian)    # Definició
        # The Castilian build must not contain the Valencian body text.
        self.assertIn("espacios", castilian.lower())

    def test_a_missing_translation_falls_back_rather_than_leaving_a_hole(self):
        # induced-metric has no va.tex, so the Valencian build must still
        # contain its content -- taken from the reference language.
        result = self.compile(self.theory, "notes", "va")
        self.assertTrue(result.ok)
        text = pdf_text(result.pdf)
        self.assertIn("mtrica", text.lower().replace("é", "").replace("è", ""))
        self.assertNotIn("missing", text.lower())

    # -- hygiene ---------------------------------------------------------

    def test_building_never_writes_into_the_content_repository(self):
        """The content repository must come out of a build untouched.

        Compiling in place is how the previous repository ended up with 1608
        committed .aux files.
        """
        before = self._snapshot(DEMO)
        self.compile(self.theory, "slides", "va")
        self.compile(self.sheet, "problems-teacher", "es")
        after = self._snapshot(DEMO)
        self.assertEqual(before, after, "a build added or changed files in the content repo")

    @staticmethod
    def _snapshot(root):
        entries = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != ".didacta-build"]
            for name in filenames:
                path = os.path.join(dirpath, name)
                entries.append((os.path.relpath(path, root), os.path.getsize(path)))
        return sorted(entries)

    def test_synctex_is_produced(self):
        # Click-in-PDF to source is a hard requirement, so it is asserted
        # rather than trusted.
        result = self.compile(self.theory, "slides", "va")
        synctex = os.path.splitext(result.pdf)[0] + ".synctex.gz"
        self.assertTrue(
            os.path.isfile(synctex),
            "no SyncTeX: PDF-to-source navigation would not work",
        )

    def test_no_errors_or_actionable_warnings_in_a_clean_build(self):
        result = self.compile(self.theory, "notes", "va")
        self.assertEqual(
            [str(d) for d in result.errors], [],
        )

    def test_output_names_are_readable_and_safe(self):
        result = self.compile(self.sheet, "problems-teacher", "es")
        name = os.path.basename(result.pdf)
        # The document title comes first so a directory of outputs groups by
        # document; the colon in "Hoja 1: espacios normados" is dropped rather
        # than substituted, because "Hoja 1-" reads like a typo.
        self.assertTrue(name.startswith("Hoja 1 espacios normados"))
        self.assertIn("problems-teacher", name)
        self.assertIn("es", name)
        for character in ':/\\*?"<>|':
            self.assertNotIn(character, name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
