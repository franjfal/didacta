"""`didacta site`: una web del curso con lo que se reparte."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402
from didacta import site  # noqa: E402

COURSE = "calculo-i@2026-2027"


class PageTests(unittest.TestCase):
    def test_lo_que_se_escribe_va_escapado_y_enlazado(self):
        text = site.page(
            "Cálculo <I>", "2026-2027", ["es", "va"],
            {
                "es": [("", [("Tema 1", [("Apuntes", "es/Sin tema/Tema 1 - Apuntes.pdf")])])],
                "va": [("Tema 2", [("Tema 2", [("Apunts", "va/Tema 2/Tema 2 - Apunts.pdf")])])],
            },
            subtitle="Tu nombre", today=date(2026, 9, 27),
        )
        self.assertIn("<title>Cálculo &lt;I&gt; · 2026-2027</title>", text)
        self.assertIn('href="es/Sin%20tema/Tema%201%20-%20Apuntes.pdf"', text)
        self.assertIn('<a href="#va" lang="va">Valencià</a>', text)
        self.assertIn("<h2>Tema 2</h2>", text)
        self.assertIn("27/09/2026", text)
        self.assertIn("prefers-color-scheme: dark", text)
        self.assertIn('name="viewport"', text)

    def test_un_solo_idioma_sin_pestanas(self):
        text = site.page("C", "2026", ["es"], {"es": [("", [("T", [("A", "a.pdf")])])]})
        self.assertNotIn("<nav", text)

    def test_sin_nada_lo_dice(self):
        self.assertIn("Todavía no hay nada publicado", site.page("C", "2026", ["es"], {}))


class SiteCliTests(unittest.TestCase):
    """Con PDF puestos donde los deja el motor, sin compilar."""

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-site-")
        self.addCleanup(shutil.rmtree, self.work, True)
        self.repo = os.path.join(self.work, "ej")
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"), self.repo)
        settings = repo_mod.Settings.load(self.repo)
        courses, _ = repo_mod.scan_courses(self.repo, settings)
        year = courses["calculo-i"].years["2026-2027"]
        engine = build_mod.Engine(
            latex_dir=os.path.join(ROOT, "latex"),
            build_dir=os.path.join(self.repo, settings.build_dir),
            settings=settings,
        )
        profiles = profiles_mod.load(os.path.join(ROOT, "latex"))
        for document in year.documents:
            if document.id != "tema-1":
                continue
            for name in ("slides", "notes", "notes-teacher"):
                for language in ("es", "va"):
                    outdir = engine.output_dir(
                        "%s/%s" % (COURSE, document.id), name, language)
                    os.makedirs(outdir, exist_ok=True)
                    job = profiles[name].output_name(document.title(language), language)
                    with open(os.path.join(outdir, job + ".pdf"), "wb") as handle:
                        handle.write(b"%PDF-1.4")

    def cli(self, *args):
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "site",
             COURSE, "-l", "es", "-l", "va", "--json", *args],
            cwd=self.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )
        return done

    def test_la_web_con_lo_del_estudiante(self):
        done = self.cli()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        report = json.loads(done.stdout)
        self.assertEqual(report["pdfs"], 4)
        # La copia del profesor no sale, y se dice.
        self.assertTrue(any("notes-teacher" in w for w in report["withheld"]))
        index = os.path.join(self.repo, "site", "index.html")
        with open(index, encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn("Cálculo I", text)
        self.assertIn(">Apuntes<", text)
        self.assertIn(">Apunts<", text)
        self.assertNotIn("profesor", text.lower())
        # «Sin tema» no es un título en una web.
        self.assertNotIn("<h2>Sin tema</h2>", text)
        # Cada enlace lleva a un fichero que está.
        import re
        from urllib.parse import unquote
        for href in re.findall(r'<a href="([^"#]+)"', text):
            self.assertTrue(os.path.isfile(os.path.join(
                self.repo, "site", unquote(href))), href)

    def test_se_rehace_entera_y_nunca_pisa_una_carpeta_ajena(self):
        self.assertEqual(self.cli().returncode, 0)
        stale = os.path.join(self.repo, "site", "viejo.pdf")
        open(stale, "wb").close()
        self.assertEqual(self.cli().returncode, 0)
        self.assertFalse(os.path.exists(stale))

        other = os.path.join(self.work, "mia")
        os.makedirs(other)
        open(os.path.join(other, "notas.txt"), "w").close()
        done = self.cli("--to", other)
        self.assertEqual(done.returncode, 1)
        self.assertTrue(os.path.exists(os.path.join(other, "notas.txt")))


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
