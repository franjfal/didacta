"""Diapositivas que se salen por abajo y líneas que se salen por la derecha."""

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

from didacta import build as build_mod  # noqa: E402

LESSON = "../../../content/a/b/c/es.tex"

#: Como lo escribe beamer: una diapositiva con tres capas que se sale en sus
#: tres páginas, detectado en el `\end{frame}` de la lección.
SLIDES_LOG = "\n".join([
    "This is pdfTeX, Version 3.14",
    "(./didacta-main.tex (/usr/share/texmf/tex/latex/beamer/beamer.cls)"
    "(/usr/share/texmf/tex/latex/base/size11.clo)",
    "(%s" % LESSON,
    "(/usr/share/texmf/tex/latex/amsfonts/umsa.fd",
    "File: umsa.fd 2013/01/14 v3.01 AMS symbols A",
    ")",
    "[1",
    "",
    "]",
    "Overfull \\vbox (59.90372pt too high) detected at line 12",
    " []",
    "",
    "[2]",
    "Overfull \\vbox (59.90372pt too high) detected at line 12",
    " []",
    "",
    "[3]",
    "Overfull \\vbox (19.05pt too high) detected at line 12",
    " []",
    "",
    "Overfull \\vbox (3.94133pt too high) detected at line 20",
    " []",
    "",
    ")",
    ")",
    "Output written on out.pdf (3 pages, 1 bytes).",
])


class ParseTests(unittest.TestCase):
    def slides(self, log=SLIDES_LOG):
        return [d for d in build_mod.parse_log(log, ("vbox",)) if d.code]

    def test_una_diapositiva_que_se_sale_es_un_aviso_con_sus_paginas(self):
        [slide] = self.slides()
        self.assertEqual(slide.severity, "warning")
        self.assertEqual(slide.code, "overfull-slide")
        self.assertEqual(slide.file, LESSON)
        self.assertEqual(slide.line, 12)
        self.assertEqual(slide.points, 59.9)
        self.assertEqual(slide.times, 3)
        self.assertEqual(slide.message,
                         "La diapositiva se sale por abajo 60 pt (en 3 páginas)")

    def test_lo_de_menos_de_cinco_puntos_no_se_dice(self):
        # La de la línea 20 se pasa 3,9 pt: no se ve, y avisar de ella
        # enseñaría a no leer la lista.
        self.assertEqual([d.line for d in self.slides()], [12])

    def test_poco_mas_de_cinco_lleva_decimal(self):
        log = SLIDES_LOG.replace("59.90372pt", "5.09pt").replace("19.05pt", "5.2pt")
        [slide] = self.slides(log)
        self.assertEqual(slide.message,
                         "La diapositiva se sale por abajo 5,2 pt (en 3 páginas)")

    def test_sin_pedirlo_no_se_avisa(self):
        self.assertEqual([d for d in build_mod.parse_log(SLIDES_LOG) if d.code], [])

    def test_as_dict_lo_lleva(self):
        [slide] = self.slides()
        data = slide.as_dict()
        self.assertEqual(data["code"], "overfull-slide")
        self.assertEqual(data["points"], 59.9)
        self.assertEqual(data["times"], 3)
        self.assertEqual(data["line"], 12)

    def test_una_linea_que_se_sale_solo_si_se_pide(self):
        log = "\n".join([
            "(./didacta-main.tex (%s" % LESSON,
            "Overfull \\hbox (26.29pt too wide) in paragraph at lines 7--9",
            "[]\\T1/cmr/m/n/10 un intervalo (a",
            " []",
            "",
            "Overfull \\hbox (1.2pt too wide) in paragraph at lines 11--11",
            "[]\\T1/cmr/m/n/10 casi nada",
            "",
            "))",
        ])
        self.assertEqual([d for d in build_mod.parse_log(log, ("vbox",)) if d.code],
                         [])
        [line] = [d for d in build_mod.parse_log(log, ("hbox",)) if d.code]
        self.assertEqual(line.code, "overfull-line")
        self.assertEqual(line.file, LESSON)
        self.assertEqual(line.line, 7)
        self.assertEqual(line.message, "Una línea se sale por la derecha 26 pt")

    def test_un_parrafo_que_acaba_fuera_de_la_leccion_es_de_la_leccion(self):
        # La última línea de la lección no cierra el párrafo; lo cierra quien
        # la incluyó, y TeX avisa con la lección ya cerrada: `lines 49--13`.
        log = "\n".join([
            "(./didacta-main.tex (%s" % LESSON,
            "(/t/ursfs.fd",
            "File: ursfs.fd",
            "))",
            "Overfull \\hbox (219.08pt too wide) in paragraph at lines 49--13",
            "[] ",
            " []",
            "",
            ")",
        ])
        [line] = [d for d in build_mod.parse_log(log, ("hbox",)) if d.code]
        self.assertEqual(line.file, LESSON)
        self.assertEqual(line.line, 49)

    def test_los_parentesis_de_una_caja_no_descuadran_la_pila(self):
        # El texto compuesto de una caja es texto: `(a` no abre nada. Antes
        # se contaba, y el error de después se culpaba a quien no era.
        log = "\n".join([
            "(./didacta-main.tex (%s" % LESSON,
            "Overfull \\hbox (26.29pt too wide) in paragraph at lines 7--9",
            "[]\\T1/cmr/m/n/10 un intervalo ((((a",
            "",
            ")",
            "(../../../content/x/y/z/es.tex",
            "! Undefined control sequence.",
            "l.3 \\foo",
        ])
        [error] = [d for d in build_mod.parse_log(log) if d.severity == "error"]
        self.assertEqual(error.file, "../../../content/x/y/z/es.tex")

    def test_abrir_y_cerrar_en_la_misma_linea(self):
        # `(a.sty)(b.sty` deja abierto solo b. Contando paréntesis por línea
        # se quedaban los dos, y la pila acababa en un paquete de TikZ.
        log = "\n".join([
            "(./didacta-main.tex (/t/a.sty)(%s" % LESSON,
            "(/t/pgf.code.tex)(/t/tcb.code.tex",
            ")",
            "[1]",
            "Overfull \\vbox (12pt too high) detected at line 4",
            " []",
            "",
        ])
        [slide] = self.slides(log)
        self.assertEqual(slide.file, LESSON)


class FrameStartTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="didacta-overfull-")
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.tex = os.path.join(self.dir, "es.tex")
        with open(self.tex, "w", encoding="utf-8") as handle:
            handle.write("\n".join([
                "\\begin{frame}",            # 1
                "Una",                       # 2
                "\\end{frame}",              # 3
                "",                          # 4
                "\\begin{frame}",            # 5
                "% \\begin{frame} comentado",  # 6
                "Mucho texto",               # 7
                "\\end{frame}",              # 8
                "\\DidactaContents",         # 9
            ]) + "\n")

    def moved(self, line):
        diagnostic = build_mod.Diagnostic(
            "warning", "", file="es.tex", line=line, code="overfull-slide",
            points=10.0,
        )
        build_mod.frame_starts([diagnostic], self.dir)
        return diagnostic.line

    def test_del_end_al_begin_de_su_diapositiva(self):
        self.assertEqual(self.moved(8), 5)
        self.assertEqual(self.moved(3), 1)

    def test_si_no_hay_frame_se_queda_donde_estaba(self):
        # El índice: lo compone una orden, sin `\begin{frame}` a la vista.
        self.assertEqual(self.moved(9), 9)

    def test_una_linea_que_se_sale_no_se_mueve(self):
        diagnostic = build_mod.Diagnostic(
            "warning", "", file="es.tex", line=8, code="overfull-line",
            points=10.0,
        )
        build_mod.frame_starts([diagnostic], self.dir)
        self.assertEqual(diagnostic.line, 8)


def _latexmk():
    return shutil.which("latexmk") is not None


@unittest.skipUnless(_latexmk(), "hace falta latexmk")
class RealBuildTests(unittest.TestCase):
    """Con el repositorio de ejemplo y LaTeX de verdad."""

    UNIT = "calculo/limites/calculo-de-limites/algebra-de-limites"

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-overfull-real-")
        self.addCleanup(shutil.rmtree, self.work, True)
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"),
                        os.path.join(self.work, "ej"))
        self.repo = os.path.join(self.work, "ej")
        self.lesson = os.path.join(self.repo, "content", self.UNIT, "es.tex")
        with open(self.lesson, encoding="utf-8") as handle:
            self.before = handle.read().count("\n")
        with open(self.lesson, "a", encoding="utf-8") as handle:
            handle.write("\n".join([
                "",
                "\\begin{frame}",
                "\\didactatitle{Demasiado}",
                *["Una línea más de las que caben.\\par" for _ in range(40)],
                "\\end{frame}",
                "",
                "\\begin{notesonly}",
                "\\noindent\\rule{1.5\\textwidth}{1pt}",
                "\\end{notesonly}",
                "",
            ]))

    def preview(self, *args):
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "preview",
             self.UNIT, "--json", *args],
            cwd=self.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )
        self.assertEqual(done.returncode, 0, done.stderr[-800:])
        data = json.loads(done.stdout[done.stdout.index("{"):])
        [result] = data["results"]
        return [d for d in result["diagnostics"] if d.get("code")]

    def test_la_diapositiva_que_se_sale_lleva_a_su_leccion_y_su_frame(self):
        [slide] = self.preview("-p", "slides")
        self.assertEqual(slide["code"], "overfull-slide")
        self.assertEqual(slide["unit"], "content/" + self.UNIT)
        self.assertEqual(slide["language"], "es")
        # La línea del `\begin{frame}` añadido, no la de su `\end{frame}`.
        self.assertEqual(slide["line"], self.before + 2)
        self.assertGreater(slide["points"], 5)

    def test_las_lineas_de_los_apuntes_solo_si_se_piden(self):
        self.assertEqual(self.preview("-p", "notes"), [])
        [line] = self.preview("-p", "notes", "--overfull-lines")
        self.assertEqual(line["code"], "overfull-line")
        self.assertEqual(line["unit"], "content/" + self.UNIT)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
