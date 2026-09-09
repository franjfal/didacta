"""CLI tests.

The command-line tool is the whole interface until the app exists, and it had
no coverage at all. These check the parts with logic in them rather than the
printing: the argument surface, and the migration report -- which is the actual
deliverable of a migration, so what it does and does not say matters.

Loaded by path because the script has no `.py` extension, being a command.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

CLI_PATH = os.path.join(ROOT, "cli", "didacta")


def load_cli():
    spec = importlib.util.spec_from_loader(
        "didacta_cli",
        importlib.machinery.SourceFileLoader("didacta_cli", CLI_PATH),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakePlan:
    """Enough of a unit plan for the report."""

    source_root = "/legacy"
    target_root = "/target"
    units = []
    skipped = []
    errors = []
    decisions = []

    def summary(self):
        return {"units": 0, "files": 0, "skipped": 0,
                "byKind": {}, "byLanguages": {}}


class ReportTests(unittest.TestCase):
    """What the migration report says."""

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def report(self, failures=()):
        return self.cli._migration_report(
            FakePlan(), None, "/legacy", "/target", failures)

    def test_the_report_states_the_source_was_not_modified(self):
        """The guarantee is worth saying in the deliverable, not just doing."""
        text = self.report()
        self.assertIn("no se ha", text)
        self.assertIn("modificado", text)

    def test_with_no_failures_there_is_no_failures_section(self):
        self.assertNotIn("no compila", self.report())

    def test_a_failure_is_named_with_its_file_line_and_error(self):
        text = self.report([
            ("am-iii-a/2025-2026/tema-1", "slides",
             "error content/a/b/es.tex:9 Missing $ inserted."),
        ])
        self.assertIn("content/a/b/es.tex:9", text)
        self.assertIn("Missing $ inserted", text)
        self.assertIn("am-iii-a/2025-2026/tema-1", text)
        self.assertIn("slides", text)

    def test_failures_are_grouped_by_the_file_at_fault(self):
        """One unit breaks several documents.

        Measured on 2025-2026: 19 documents fail from 11 units, and the
        bibliography unit accounts for six of them. Listing documents asks the
        author to read the same error six times.
        """
        same = "error content/x/bib/es.tex:4 Undefined control sequence."
        text = self.report([
            ("quimica/2025-2026/t0-bib", "handout", same),
            ("quimica/2025-2026/t1-bib", "handout", same),
            ("quimica/2025-2026/t2-bib", "handout", same),
            ("iowa/2025-2026/first-order", "slides",
             "error content/edos/a/en.tex:109 Arithmetic overflow."),
        ])
        self.assertIn("2 unidad(es), 4 documento(s)", text)
        # The error appears once, not once per document.
        self.assertEqual(text.count("Undefined control sequence"), 1, text)
        self.assertIn("Rompe 3 documento(s)", text)
        for name in ("t0-bib", "t1-bib", "t2-bib"):
            self.assertIn(name, text)

    def test_the_worst_offender_comes_first(self):
        # Ordered by how many documents each fix buys back.
        text = self.report([
            ("a", "slides", "error content/one/es.tex:1 Error one."),
            ("b", "slides", "error content/many/es.tex:1 Error many."),
            ("c", "slides", "error content/many/es.tex:1 Error many."),
        ])
        self.assertLess(text.index("content/many"), text.index("content/one"))

    def test_an_unlocatable_error_is_still_reported(self):
        text = self.report([("doc", "notes", "latexmk died before starting")])
        self.assertIn("sin localizar", text)
        self.assertIn("latexmk died", text)

    def test_the_report_says_the_metadata_was_not_invented(self):
        text = self.report()
        self.assertIn("no la ha inventado", text)


class ArgumentTests(unittest.TestCase):
    """The command surface.

    A flag that silently stops existing is a broken workflow, and these are the
    ones the migration instructions in the docs tell people to type.
    """

    @classmethod
    def setUpClass(cls):
        cls.cli = load_cli()

    def parse(self, argv):
        try:
            return self.cli.main(argv)
        except SystemExit as exit_code:  # argparse errors exit
            raise AssertionError("argparse rejected %r (exit %s)"
                                 % (argv, exit_code.code))

    def test_migrate_accepts_the_documented_flags(self):
        # Parsed, not run: --apply is absent so nothing is written, and a
        # missing source makes it return before touching anything.
        for extra in ([], ["--verify"], ["--no-courses"],
                      ["--year", "2025-2026"], ["--category", "40functional"],
                      ["--limit", "5"], ["--list"], ["-v"]):
            with self.subTest(extra=extra):
                code = self.parse(["migrate", "/nonexistent", "/target"] + extra)
                # 1 is "that does not look like the legacy repository", which
                # is the check running -- what matters is that it parsed.
                self.assertEqual(code, 1)

    def test_migrate_refuses_to_write_into_its_own_source(self):
        code = self.parse(["migrate", ROOT, ROOT])
        self.assertNotEqual(code, 0)

    def test_every_documented_command_parses(self):
        """`--help` on each: a subcommand that vanished is a broken workflow."""
        for command in ("status", "profiles", "units", "translations",
                        "build", "check", "migrate", "new"):
            with self.subTest(command=command):
                with self.assertRaises(SystemExit) as raised:
                    self.cli.main([command, "--help"])
                # argparse exits 0 after printing help; 2 means it did not
                # recognise the command.
                self.assertEqual(raised.exception.code, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
