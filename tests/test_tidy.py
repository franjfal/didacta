"""Tests for stripping the migration header.

This edits 2438 tracked files in one command, so what matters is not that it
removes the header -- that is the easy half -- but that it removes **only**
the header. A tool that eats somebody's own comment while tidying is worse
than the header it was removing.
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "engine"))

from didacta import tidy  # noqa: E402


MIGRATED = """\
% Migrated from 00classnotes/Algebra/00Presentaciones/02Determinantes/92CAS-x.tex
%
% No preamble: Didacta supplies it.
%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%


\\begin{frame}
\\didactatitle{Aplicaciones}
El contenido.
\\end{frame}
"""


class StripTests(unittest.TestCase):
    def test_removes_the_header_the_migrator_wrote(self):
        out = tidy.strip_header(MIGRATED)
        self.assertTrue(out.startswith("\\begin{frame}"), repr(out[:40]))
        self.assertNotIn("Migrated from", out)
        self.assertNotIn("No preamble", out)
        self.assertNotIn("%%%%", out)
        # And the content is untouched, to the byte.
        self.assertEqual(
            out,
            "\\begin{frame}\n\\didactatitle{Aplicaciones}\nEl contenido.\n"
            "\\end{frame}\n",
        )

    def test_removes_the_short_form_without_rules(self):
        # Some files had the provenance and no rule lines.
        out = tidy.strip_header(
            "% Migrated from a/b/c.tex\n"
            "%\n"
            "% No preamble: Didacta supplies it.\n"
            "\n"
            "El contenido.\n"
        )
        self.assertEqual(out, "El contenido.\n")

    def test_is_idempotent(self):
        # It will be run again, by someone who does not remember whether it
        # was run before.
        once = tidy.strip_header(MIGRATED)
        self.assertEqual(tidy.strip_header(once), once)

    def test_leaves_a_file_with_no_header_alone(self):
        text = "\\begin{definition}\nUna norma.\n\\end{definition}\n"
        self.assertEqual(tidy.strip_header(text), text)

    def test_leaves_a_hand_written_comment_alone(self):
        """The important one.

        A `.tex` that opens with somebody's own comment is not a migrated
        header, and guessing which comments are noise is how a tool eats
        someone's notes. Only a file whose first line is the provenance is
        touched at all.
        """
        text = (
            "% ojo: esta unidad se da antes que la anterior\n"
            "%\n"
            "% No preamble: Didacta supplies it.\n"
            "\n"
            "El contenido.\n"
        )
        self.assertEqual(tidy.strip_header(text), text)

    def test_leaves_a_comment_inside_the_content_alone(self):
        out = tidy.strip_header(
            "% Migrated from a/b/c.tex\n"
            "\n"
            "\\begin{frame}\n"
            "% este ejemplo va con la figura de al lado\n"
            "El contenido.\n"
            "\\end{frame}\n"
        )
        self.assertIn("% este ejemplo va con la figura", out)
        self.assertTrue(out.startswith("\\begin{frame}"))

    def test_a_percent_in_the_content_is_not_a_header(self):
        # `50\%` opens no header, and a file that begins with maths must not
        # lose its first line.
        text = "El $50\\%$ de los casos.\n"
        self.assertEqual(tidy.strip_header(text), text)

    def test_leading_blank_lines_before_the_header_are_handled(self):
        out = tidy.strip_header("\n\n% Migrated from a.tex\n\nHola.\n")
        self.assertEqual(out, "Hola.\n")

    def test_an_empty_file_survives(self):
        self.assertEqual(tidy.strip_header(""), "")
        self.assertEqual(tidy.strip_header("\n\n"), "\n\n")


class TidyTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-tidy-")
        self.unit = os.path.join(self.root, "content", "a", "b", "c")
        os.makedirs(self.unit)
        self.tex = os.path.join(self.unit, "es.tex")
        with open(self.tex, "w", encoding="utf-8") as handle:
            handle.write(MIGRATED)
        # A file outside the content trees, which must not be touched.
        os.makedirs(os.path.join(self.root, "courses", "x", "2025-2026"))
        self.document = os.path.join(
            self.root, "courses", "x", "2025-2026", "tema-1.tex"
        )
        with open(self.document, "w", encoding="utf-8") as handle:
            handle.write(MIGRATED)

    def test_a_dry_run_writes_nothing(self):
        result = tidy.tidy(self.root)
        self.assertEqual(result.changed, 1)
        self.assertGreater(result.bytes_removed, 0)
        with open(self.tex, encoding="utf-8") as handle:
            self.assertIn("Migrated from", handle.read())

    def test_apply_writes(self):
        tidy.tidy(self.root, apply=True)
        with open(self.tex, encoding="utf-8") as handle:
            self.assertTrue(handle.read().startswith("\\begin{frame}"))

    def test_only_the_content_trees(self):
        """A document's own header is a different thing.

        `courses/*/*/tema-1.tex` explains what the legacy master was and why
        the composition now lives in `year.yaml`, which is worth reading and
        is seen once per document rather than on every unit anyone edits.
        """
        tidy.tidy(self.root, apply=True)
        with open(self.document, encoding="utf-8") as handle:
            self.assertIn("Migrated from", handle.read())

    def test_counts_what_was_already_clean(self):
        tidy.tidy(self.root, apply=True)
        again = tidy.tidy(self.root, apply=True)
        self.assertEqual(again.changed, 0)
        self.assertEqual(again.unchanged, 1)


if __name__ == "__main__":
    unittest.main()
