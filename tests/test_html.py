"""Los apuntes en HTML (`didacta html`, `engine/didacta/html.py`).

Lo que más importa es lo primero: **las mismas reglas que el PDF de esa
versión**. Un HTML del estudiante que enseñara una solución o una nota
didáctica sería repartirla sin querer, por la puerta de atrás.
"""

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

from didacta import html as html_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402

LATEX_DIR = os.path.join(ROOT, "latex")
DEMO = os.path.join(ROOT, "examples", "demo-course")
PROFILES = profiles_mod.load(LATEX_DIR)

LESSON = r"""
Texto para todos. \onlyslides{SOLO-DIAPOSITIVAS}\onlynotes{EN-APUNTES}
\onlyteacher{SOLO-PROFESOR}\onlystudent{SOLO-ESTUDIANTE}

\begin{teaching}[Ritmo]NOTA-DIDACTICA\end{teaching}
\begin{commonmistake}ERROR-FRECUENTE\end{commonmistake}
\begin{exercise}Enunciado.
\begin{answer}RESULTADO\end{answer}
\begin{solution}RESOLUCION\end{solution}
\begin{marking}CORRECCION\end{marking}
\end{exercise}
\begin{slidesonly}BLOQUE-DIAPOSITIVAS\end{slidesonly}
"""


def render(profile_id, text=LESSON, language="es"):
    axes = dict(profiles_mod.DEFAULT_AXES)
    axes.update(PROFILES[profile_id].axes)
    return html_mod.convert_unit(
        text, axes, html_mod.language_names(LATEX_DIR, language),
        html_mod.WORDS[language])


class VisibilityTests(unittest.TestCase):
    def test_los_apuntes_del_estudiante_no_llevan_nada_de_mas(self):
        page = render("notes")
        for hidden in ("SOLO-DIAPOSITIVAS", "SOLO-PROFESOR", "NOTA-DIDACTICA",
                       "ERROR-FRECUENTE", "RESULTADO", "RESOLUCION",
                       "CORRECCION", "BLOQUE-DIAPOSITIVAS"):
            self.assertNotIn(hidden, page, hidden)
        for shown in ("Texto para todos", "EN-APUNTES", "SOLO-ESTUDIANTE",
                      "Enunciado"):
            self.assertIn(shown, page, shown)

    def test_con_resultados_solo_los_resultados(self):
        page = render("problems-answers")
        self.assertIn("RESULTADO", page)
        self.assertNotIn("RESOLUCION", page)
        self.assertNotIn("CORRECCION", page)

    def test_la_del_profesor_todo(self):
        page = render("problems-teacher")
        for shown in ("SOLO-PROFESOR", "NOTA-DIDACTICA", "ERROR-FRECUENTE",
                      "RESULTADO", "RESOLUCION", "CORRECCION"):
            self.assertIn(shown, page, shown)
        self.assertNotIn("SOLO-ESTUDIANTE", page)
        # Las diapositivas, en ninguna página: se leen sus apuntes.
        self.assertNotIn("SOLO-DIAPOSITIVAS", page)


class ConversionTests(unittest.TestCase):
    def test_un_teorema_es_una_seccion_con_su_nombre(self):
        page = render("notes", r"\begin{definition}[Norma]Una \keyterm{norma} "
                               r"es.\end{definition}")
        self.assertIn('aria-label="Definición (Norma)"', page)
        self.assertIn("<dfn>norma</dfn>", page)

    def test_las_formulas_van_a_mathjax_escapadas(self):
        page = render("notes", r"Si $x < y$ entonces \[ a \le b \]")
        self.assertIn(r"\(x &lt; y\)", page)
        self.assertIn(r"\[a \le b\]", page)

    def test_las_figuras_llevan_su_texto_alternativo(self):
        page = render("notes", r"\begin{tikzpicture}[alt={Una parábola}]"
                               r"\draw (0,0);\end{tikzpicture}")
        self.assertIn('role="img" aria-label="Una parábola"', page)
        missing = render("notes", r"\begin{tikzpicture}\draw;\end{tikzpicture}")
        self.assertIn("sin descripción", missing)

    def test_las_tildes_de_tex_y_la_puntuacion(self):
        page = render("notes", r"Definici\'on, \c{c}, ``cita'' --- y~ya.")
        self.assertIn("Definición, ç, “cita” — y ya.", page)

    def test_una_orden_desconocida_deja_su_texto(self):
        page = render("notes", r"Hola \miorden{mundo}.")
        self.assertIn("Hola mundo.", page)

    def test_una_barra_al_final_de_una_linea_no_rompe_nada(self):
        render("notes", "Hola \\\nmundo \\")

    def test_un_titulo_con_formula_se_lee_en_texto(self):
        self.assertEqual(html_mod.plain_text(r"Completitud de $\mathbb R$"),
                         "Completitud de ℝ")
        self.assertEqual(html_mod.plain_text(r"Hacia $\pm\infty$"),
                         "Hacia ±∞")


class CommandTests(unittest.TestCase):
    def test_el_curso_de_ejemplo_entero(self):
        work = tempfile.mkdtemp(prefix="didacta-html-")
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "--root",
             DEMO, "html", "am-iii@2025-2026", "-l", "va", "--to", work,
             "--json"],
            capture_output=True, text=True,
        )
        self.assertEqual(done.returncode, 0, done.stderr)
        report = json.loads(done.stdout)
        profiles = {item["profile"] for item in report["written"]}
        # Lo que se reparte, y ni diapositivas ni versiones del profesor.
        self.assertIn("notes", profiles)
        self.assertFalse(any(PROFILES[p].is_slides for p in profiles))
        self.assertFalse(any(PROFILES[p].is_teacher for p in profiles))
        self.assertTrue(report["withheld"])
        path = next(item["path"] for item in report["written"]
                    if item["profile"] == "notes")
        with open(path, encoding="utf-8") as handle:
            page = handle.read()
        self.assertIn('<html lang="ca-ES-valencia">', page)
        self.assertIn("<title>Preliminars: espais normats</title>", page)
        # La lección que no está en valenciano va en su original, y lo dice.
        self.assertIn('lang="es-ES"', page)


if __name__ == "__main__":
    unittest.main()


class ExportTests(unittest.TestCase):
    def test_export_con_html_lo_pone_al_lado_y_en_el_zip(self):
        work = tempfile.mkdtemp(prefix="didacta-export-html-")
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        to = os.path.join(work, "reparto")
        archive = os.path.join(work, "reparto.zip")
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "--root",
             DEMO, "export", "am-iii@2025-2026", "-l", "va", "--html",
             "--to", to, "--zip", archive, "--json"],
            capture_output=True, text=True,
        )
        self.assertEqual(done.returncode, 0, done.stderr)
        report = json.loads(done.stdout)
        pages = [item for item in report["outputs"]
                 if item.get("format") == "html"]
        self.assertTrue(pages)
        # Ni diapositivas ni lo del profesor, en HTML tampoco.
        for item in pages:
            profile = PROFILES[item["profile"]]
            self.assertFalse(profile.is_slides, item)
            self.assertFalse(profile.is_teacher, item)
            self.assertTrue(os.path.isfile(os.path.join(to, item["path"])))
        import zipfile
        with zipfile.ZipFile(archive) as bundle:
            names = bundle.namelist()
        self.assertTrue(any(name.endswith(".html") for name in names))
