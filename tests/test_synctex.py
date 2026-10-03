"""De un punto del PDF a la lección y la línea que lo escribieron."""

from __future__ import annotations

import gzip
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
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import synctex  # noqa: E402

FRAME = "\n".join([
    "% una lección",                    # 1
    r"\begin{frame}",                   # 2
    r"\didactatitle{Qué son}",          # 3
    r"\begin{definition}",              # 4
    r"Ciencia deductiva que estudia",   # 5
    r"\end{definition}",                # 6
    r"Una funci\'{o}n continua",        # 7
    r"% \end{frame} comentado",         # 8
    r"\end{frame}",                     # 9
    "",                                 # 10
    r"Texto fuera de una diapositiva",  # 11
])


class RefineTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="didacta-synctex-")
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.tex = os.path.join(self.dir, "es.tex")
        with open(self.tex, "w", encoding="utf-8") as handle:
            handle.write(FRAME)

    def at(self, line, **text):
        return synctex.refine({"file": self.tex, "line": line}, **text)

    def test_la_palabra_lleva_a_su_linea_dentro_de_la_diapositiva(self):
        # beamer apunta todo al `\end{frame}`; la palabra dice cuál.
        found = self.at(9, word="deductiva",
                        text="Ciencia deductiva que estudia las propiedades")
        self.assertEqual(found["line"], 5)
        self.assertEqual(found["frame"], 2)

    def test_sin_tildes_y_con_las_de_tex(self):
        self.assertEqual(self.at(9, word="Función", text="Una función")["line"], 7)

    def test_si_nada_se_parece_el_principio_de_la_diapositiva(self):
        self.assertEqual(self.at(9)["line"], 2)
        self.assertEqual(self.at(9, word="Weierstrass")["line"], 2)

    def test_fuera_de_una_diapositiva_no_se_toca(self):
        # En unos apuntes SyncTeX ya es exacto.
        found = self.at(11, word="deductiva")
        self.assertEqual(found["line"], 11)
        self.assertNotIn("frame", found)

    def test_en_el_repositorio(self):
        root = self.dir
        lesson = os.path.join(root, "content", "a", "b", "va.tex")
        self.assertEqual(synctex.in_repository(lesson, root), {
            "path": "content/a/b/va.tex",
            "unit": "content/a/b",
            "language": "va",
        })
        document = os.path.join(root, "courses", "m", "2025", "tema-1.tex")
        self.assertEqual(synctex.in_repository(document, root),
                         {"path": "courses/m/2025/tema-1.tex"})
        self.assertEqual(synctex.in_repository("/usr/share/x.sty", root), {})

    def test_sin_pdf_o_sin_synctex_lo_dice(self):
        with self.assertRaises(synctex.SyncTexError):
            synctex.edit(os.path.join(self.dir, "no.pdf"), 1, 10, 10)
        pdf = os.path.join(self.dir, "a.pdf")
        with open(pdf, "wb") as handle:
            handle.write(b"%PDF")
        with self.assertRaisesRegex(synctex.SyncTexError, "synctex"):
            synctex.edit(pdf, 1, 10, 10)


def _tools():
    return shutil.which("latexmk") and shutil.which("synctex")


@unittest.skipUnless(_tools(), "hace falta latexmk y synctex")
class RealBuildTests(unittest.TestCase):
    """Con el repositorio de ejemplo, LaTeX y SyncTeX de verdad."""

    UNIT = "content/calculo/limites/calculo-de-limites/algebra-de-limites"

    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.mkdtemp(prefix="didacta-synctex-real-")
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"),
                        os.path.join(cls.work, "ej"))
        cls.repo = os.path.join(cls.work, "ej")
        done = cls.cli("build", "calculo-i@2026-2027/tema-1", "-p", "notes",
                       "-p", "slides", "-l", "es", "--json")
        assert done.returncode == 0, done.stderr[-800:]
        cls.results = {
            r["profile"]: r["pdf"]
            for r in json.loads(done.stdout[done.stdout.index("["):])
        }

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, True)

    @classmethod
    def cli(cls, *args):
        return subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), *args],
            cwd=cls.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )

    def point_of(self, pdf, line):
        """Dónde pone el PDF la línea [line] de la lección, según SyncTeX."""
        with gzip.open(os.path.splitext(pdf)[0] + ".synctex.gz", "rt",
                       encoding="utf-8", errors="replace") as handle:
            inputs = re.findall(r"^Input:\d+:(.*)$", handle.read(), re.M)
        [recorded] = [i for i in inputs
                      if i.endswith("algebra-de-limites/es.tex")]
        done = subprocess.run(
            ["synctex", "view", "-i", "%d:0:%s" % (line, recorded),
             "-o", os.path.basename(pdf)],
            cwd=os.path.dirname(pdf), capture_output=True, text=True,
        )
        values = dict(re.findall(r"^(Page|h|v):([\d.]+)$", done.stdout, re.M))
        return int(values["Page"]), float(values["h"]) + 2, float(values["v"]) - 2

    def ask(self, pdf, point, *extra):
        page, x, y = point
        done = self.cli("synctex", pdf, "--page", str(page), "--x", str(x),
                        "--y", str(y), "--json", *extra)
        self.assertEqual(done.returncode, 0, done.stderr[-800:])
        return json.loads(done.stdout)["found"]

    def test_en_los_apuntes_la_linea_de_la_leccion(self):
        found = self.ask(self.results["notes"],
                         self.point_of(self.results["notes"], 11))
        self.assertEqual(found["unit"], self.UNIT)
        self.assertEqual(found["language"], "es")
        self.assertEqual(found["path"], self.UNIT + "/es.tex")
        self.assertIn(found["line"], (10, 11))

    def test_en_las_diapositivas_con_la_palabra(self):
        pdf = self.results["slides"]
        point = self.point_of(pdf, 11)
        found = self.ask(pdf, point)
        self.assertEqual(found["unit"], self.UNIT)
        # Sin palabra, el principio de la diapositiva.
        self.assertEqual(found["line"], found["frame"])
        found = self.ask(pdf, point, "--word", "entonces",
                         "--text", "Si lim f(x) = L y lim g(x) = M, entonces")
        self.assertEqual(found["line"], 11)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
