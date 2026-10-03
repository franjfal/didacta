"""Revisar lo que hay escrito: `didacta check` con sus hallazgos."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import review  # noqa: E402

LESSONS = os.path.join("content", "calculo", "limites")
ALGEBRA = os.path.join(LESSONS, "calculo-de-limites", "algebra-de-limites")
DEFINITION = os.path.join(LESSONS, "concepto-de-limite", "definicion-de-limite")


class ReviewTests(unittest.TestCase):
    """Con una copia del repositorio de ejemplo, estropeada a propósito."""

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-review-")
        self.addCleanup(shutil.rmtree, self.work, True)
        self.repo = os.path.join(self.work, "ej")
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"), self.repo)

    def append(self, relative, text):
        with open(os.path.join(self.repo, relative), "a", encoding="utf-8") as handle:
            handle.write("\n" + text + "\n")

    def lines_of(self, relative):
        with open(os.path.join(self.repo, relative), encoding="utf-8") as handle:
            return handle.read().count("\n")

    def check(self, *args, code=None):
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "check",
             "--json", *args],
            cwd=self.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )
        if code is not None:
            self.assertEqual(done.returncode, code, done.stderr[-800:])
        return json.loads(done.stdout)

    def found(self, report, check):
        return [f for f in report["findings"] if f["check"] == check]

    def test_el_ejemplo_esta_limpio(self):
        report = self.check(code=0)
        self.assertTrue(report["ok"])
        self.assertEqual(
            [f for f in report["findings"] if f["check"] != "structure"], [])
        self.assertIn("babel", report["checks"])
        self.assertEqual(report["titles"]["figures"], "Figuras que faltan")

    def test_una_orden_del_castellano_en_el_valenciano(self):
        va = os.path.join(ALGEBRA, "va.tex")
        self.append(va, r"\sptext{a} y \lsc{b}")
        # En el castellano sí existe: ahí no es nada.
        self.append(os.path.join(ALGEBRA, "es.tex"), r"\sptext{a}")
        report = self.check(code=1)
        found = self.found(report, "babel")
        self.assertEqual(len(found), 2)
        self.assertEqual(found[0]["language"], "va")
        self.assertEqual(found[0]["unit"], "content/calculo/limites/calculo-de-limites/algebra-de-limites")
        self.assertEqual(found[0]["line"], self.lines_of(va))
        self.assertIn(r"\sptext", found[0]["message"])
        self.assertEqual(found[0]["severity"], "error")

    def test_un_entorno_que_no_define_nadie(self):
        es = os.path.join(ALGEBRA, "es.tex")
        self.append(es, "\n".join([
            r"\newenvironment{mio}{}{}",
            r"\begin{mio}\end{mio}",
            r"\begin{nthrm}x\end{nthrm}",       # un alias de Didacta
            r"\begin{definition*}x\end{definition*}",
            r"\begin{rcases*}x\end{rcases*}",
            r"% \begin{comentado}",
            r"\begin{inventado}x\end{inventado}",
            r"\begin{inventado}otra vez\end{inventado}",
        ]))
        found = self.found(self.check(code=1), "environments")
        self.assertEqual(len(found), 1)
        self.assertIn("inventado", found[0]["message"])
        self.assertEqual(found[0]["line"], self.lines_of(es) - 1)

    def test_los_entornos_de_los_snippets_valen(self):
        with open(os.path.join(self.repo, "snippets.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("snippets:\n  - id: resumen\n    environment: resumen\n"
                         "    definition: '\\newenvironment{resumen}{}{}'\n")
        self.append(os.path.join(ALGEBRA, "es.tex"), r"\begin{resumen}x\end{resumen}")
        self.assertEqual(self.found(self.check(), "environments"), [])

    def test_una_figura_que_no_esta(self):
        figures = os.path.join(self.repo, ALGEBRA, "figures")
        os.makedirs(figures)
        open(os.path.join(figures, "si.pdf"), "wb").close()
        self.append(os.path.join(ALGEBRA, "es.tex"), "\n".join([
            r"\includegraphics[width=3cm]{figures/si}",
            r"\includegraphics{figures/no-existe.png}",
        ]))
        found = self.found(self.check(code=1), "figures")
        self.assertEqual(len(found), 1)
        self.assertIn("figures/no-existe.png", found[0]["message"])

    def test_etiquetas_repetidas_y_referencias_sin_destino(self):
        self.append(os.path.join(ALGEBRA, "es.tex"), "\n".join([
            r"\label{eq:repetida}",
            r"\ref{nada} y \eqref{eq:repetida} y \ref{diapositiva}",
        ]))
        self.append(os.path.join(DEFINITION, "es.tex"), "\n".join([
            r"\label{eq:repetida}",
            r"\begin{frame}[fragile,label=diapositiva]\end{frame}",
        ]))
        found = self.found(self.check(code=0), "labels")
        messages = [f["message"] for f in found]
        self.assertTrue(any("repetida" in m and "eq:repetida" in m for m in messages))
        self.assertTrue(any(r"\ref{nada}" in m and "??" in m for m in messages))
        # La de una diapositiva vale en el documento en castellano; en el
        # inglés no, que su definición no la lleva.
        self.assertFalse(any("diapositiva" in m and "Tema 1" in m
                             for m in messages))
        self.assertTrue(any("diapositiva" in m and "Unit 1" in m
                            for m in messages))
        self.assertTrue(all(f["document"] == "calculo-i@2026-2027/tema-1"
                            for f in found if "nada" in f["message"]))

    def test_una_traduccion_desactualizada(self):
        path = os.path.join(self.repo, ALGEBRA, "unit.yaml")
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace(
                "va: {status: translated}",
                "va: {status: translated, source_hash: 'sha256:0000000000000000'}"))
        found = self.found(self.check(), "outdated")
        self.assertEqual([f["language"] for f in found], ["va"])
        self.assertEqual(found[0]["unit"], "content/calculo/limites/calculo-de-limites/algebra-de-limites")

    def test_estricto_los_avisos_tambien_fallan(self):
        self.append(os.path.join(ALGEBRA, "es.tex"), r"\ref{nada}")
        self.assertTrue(self.check(code=0)["ok"])
        self.assertFalse(self.check("--strict", code=1)["ok"])

    def test_solo_lo_que_se_va_a_exportar(self):
        self.append(os.path.join(ALGEBRA, "es.tex"), r"\sptext{a}")
        self.append(os.path.join(ALGEBRA, "va.tex"), r"\sptext{a}")
        # La hoja de problemas no lleva esa lección.
        report = self.check("--in", "calculo-i@2026-2027/hoja-1")
        self.assertEqual(self.found(report, "babel"), [])
        report = self.check("--in", "calculo-i@2026-2027")
        self.assertEqual(len(self.found(report, "babel")), 1)

    def test_las_opcionales_solo_si_se_piden(self):
        self.append(os.path.join(ALGEBRA, "va.tex"), r"$0.5$ y $0{,}25$ y $x^2+1$")
        self.assertEqual(self.found(self.check(), "decimals"), [])
        report = self.check("--with", "decimals,formulas,unused")
        self.assertEqual(len(self.found(report, "decimals")), 1)
        self.assertEqual(len(self.found(report, "formulas")), 1)
        unused = self.found(report, "unused")
        self.assertIn("content/calculo/limites/concepto-de-limite/historia-del-epsilon",
                      [f["unit"] for f in unused])
        self.assertEqual(unused[0]["severity"], "info")

    def test_lo_que_el_pdf_accesible_no_puede_leer(self):
        self.append(os.path.join(ALGEBRA, "va.tex"),
                    "\\includegraphics{a.png}\n"
                    "\\includegraphics[alt={Un punt}]{b.png}\n"
                    "\\begin{tikzpicture}[scale=2]\\end{tikzpicture}\n"
                    "\\begin{enumerate}[<+->]\\item a\\end{enumerate}\n")
        self.assertEqual(self.found(self.check(), "accessible"), [])
        found = self.found(self.check("--with", "accessible"), "accessible")
        warnings = [f for f in found if f["severity"] == "warning"]
        infos = [f for f in found if f["severity"] == "info"]
        # La imagen sin alt y el dibujo; la que lo tiene, no.
        self.assertEqual(len(warnings), 2)
        self.assertIn("dibujo", warnings[1]["message"])
        # La lista con las pausas de las diapositivas.
        self.assertEqual(len(infos), 1)
        self.assertIn("[<+->]", infos[0]["message"])

    def test_una_comprobacion_que_no_existe(self):
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "check",
             "--with", "ortografia"],
            cwd=self.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )
        self.assertEqual(done.returncode, 2)
        self.assertIn("ortografia", done.stdout)


class PureTests(unittest.TestCase):
    def test_teoremas_con_estrella_y_alias(self):
        found = review.defined_environments([
            r"\DidactaNewTheorem{teorema}{\x}{c}",
            r"\didacta@alias{nthrm}{theorem}",
            r"\NewEnviron{solo}{}",
        ])
        self.assertEqual(found, {"teorema", "teorema*", "nthrm", "solo"})

    def test_lo_de_didacta_se_lee_de_su_arbol(self):
        found = review.latex_environments(os.path.join(ROOT, "latex"))
        for name in ("theorem", "theorem*", "teaching", "exercise", "nthrm"):
            self.assertIn(name, found)


def _latexmk():
    return shutil.which("latexmk") is not None


@unittest.skipUnless(_latexmk(), "hace falta latexmk")
class OverflowTests(unittest.TestCase):
    """Lo que se sale, leído de la última compilación."""

    def test_la_diapositiva_que_se_sale_en_el_ultimo_pdf(self):
        work = tempfile.mkdtemp(prefix="didacta-review-real-")
        self.addCleanup(shutil.rmtree, work, True)
        repo = os.path.join(work, "ej")
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"), repo)
        lesson = os.path.join(repo, ALGEBRA, "es.tex")
        with open(lesson, encoding="utf-8") as handle:
            before = handle.read().count("\n")
        with open(lesson, "a", encoding="utf-8") as handle:
            handle.write("\n".join(
                ["", r"\begin{frame}", r"\didactatitle{Demasiado}"]
                + [r"Una línea más.\par" for _ in range(40)]
                + [r"\end{frame}", ""]))

        def cli(*args):
            return subprocess.run(
                [sys.executable, os.path.join(ROOT, "cli", "didacta"), *args],
                cwd=repo, capture_output=True, text=True,
                env=dict(os.environ, NO_COLOR="1"),
            )

        done = cli("build", "calculo-i@2026-2027/tema-1", "-p", "slides",
                   "-l", "es")
        self.assertEqual(done.returncode, 0, done.stdout[-800:])
        report = json.loads(cli("check", "--json").stdout)
        [slide] = [f for f in report["findings"] if f["check"] == "overflow"]
        self.assertEqual(slide["unit"], "content/calculo/limites/calculo-de-limites/algebra-de-limites")
        self.assertEqual(slide["language"], "es")
        self.assertEqual(slide["line"], before + 2)
        self.assertEqual(slide["document"], "calculo-i@2026-2027/tema-1")


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
