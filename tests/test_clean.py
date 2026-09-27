"""`didacta clean`: vaciar la carpeta de compilación, y nada más."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))


class CleanTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-clean-")
        self.addCleanup(shutil.rmtree, self.work, True)
        self.repo = os.path.join(self.work, "ej")
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"), self.repo)
        self.build = os.path.join(self.repo, ".didacta-build")
        for folder, name, size in [
            ("calculo-i@2026-2027_tema-1/slides-es", "Tema 1.pdf", 1000),
            ("calculo-i@2026-2027_tema-1/notes-es", "Tema 1.pdf", 500),
            ("calculo-i@2026-2027_hoja-1/problems-es", "Hoja 1.pdf", 200),
        ]:
            os.makedirs(os.path.join(self.build, folder), exist_ok=True)
            with open(os.path.join(self.build, folder, name), "wb") as handle:
                handle.write(b"x" * size)

    def cli(self, *args):
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "clean",
             "--json", *args],
            cwd=self.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )
        return done.returncode, json.loads(done.stdout)

    def test_el_tamano_sin_borrar_nada(self):
        code, report = self.cli("--size")
        self.assertEqual(code, 0)
        self.assertEqual(report["bytes"], 1700)
        self.assertEqual(report["files"], 3)
        self.assertFalse(report["removed"])
        self.assertTrue(os.path.isdir(self.build))

    def test_vaciarla(self):
        code, report = self.cli()
        self.assertEqual(code, 0)
        self.assertTrue(report["removed"])
        self.assertEqual(report["bytes"], 1700)
        self.assertFalse(os.path.exists(self.build))
        # El material, intacto.
        self.assertTrue(os.path.isdir(os.path.join(self.repo, "content")))
        # Y otra vez no hay nada que hacer.
        code, report = self.cli()
        self.assertEqual((code, report["files"], report["removed"]), (0, 0, False))

    def test_solo_un_documento(self):
        code, report = self.cli("calculo-i@2026-2027/tema-1")
        self.assertEqual(report["bytes"], 1500)
        self.assertFalse(os.path.exists(
            os.path.join(self.build, "calculo-i@2026-2027_tema-1")))
        self.assertTrue(os.path.isdir(
            os.path.join(self.build, "calculo-i@2026-2027_hoja-1")))

    def set_build_dir(self, value):
        path = os.path.join(self.repo, "didacta.yaml")
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if re.search(r"^build_dir:", text, re.M):
            text = re.sub(r"^build_dir:.*$", "build_dir: %s" % value, text,
                          flags=re.M)
        else:
            text += "\nbuild_dir: %s\n" % value
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def test_nunca_la_raiz_ni_fuera_del_repositorio(self):
        for value in (".", "..", "../fuera"):
            self.set_build_dir(value)
            code, report = self.cli()
            self.assertEqual(code, 1, value)
            self.assertIn("no la vacío", report["error"])
        self.assertTrue(os.path.isdir(os.path.join(self.repo, "content")))


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
