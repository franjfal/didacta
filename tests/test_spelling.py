"""La ortografía en «Revisar»: `didacta check --with spelling`.

Sin el hunspell de verdad, que no tiene por qué estar donde se pasan los
tests: uno de mentira que habla el mismo protocolo (`hunspell -D` y
`hunspell -a`) y que solo no conoce las palabras que se le dicen. Lo que se
comprueba aquí es lo de Didacta --qué se le da a leer, cómo se lee lo que
contesta, qué se hace con las palabras del repositorio-- y no si hunspell
sabe castellano.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import spelling  # noqa: E402

ALGEBRA = os.path.join("content", "calculo", "limites", "calculo-de-limites",
                       "algebra-de-limites")

#: Un hunspell de mentira. Tiene diccionario de castellano y de catalán --el
#: valenciano cae en él--, y no de inglés. No conoce las palabras de WRONG, y
#: sugiere lo que dice ahí.
FAKE = textwrap.dedent('''\
    import re, sys
    WRONG = {"conjunot": "conjunto", "tambien": "también", "Banach": None,
             "fucnió": "funció"}
    args = sys.argv[1:]
    if "-D" in args:
        sys.stderr.write(
            "SEARCH PATH:\\n.:/usr/share/hunspell\\n"
            "AVAILABLE DICTIONARIES (path is not mandatory for -d option):\\n"
            "/usr/share/hunspell/es_ES\\n/usr/share/hunspell/ca_ES\\n"
            "LOADED DICTIONARY:\\n/usr/share/hunspell/es_ES.aff\\n")
        sys.exit(0)
    sys.stdout.write("@(#) International Ispell Version 3.2.06 "
                     "(but really Hunspell 1.7.2)\\n")
    terse = False
    for line in sys.stdin.read().split("\\n"):
        if line == "!":
            terse = True
            continue
        if not line.startswith("^"):
            continue
        text = line[1:]
        for match in re.finditer(r"[^\\W\\d_]+", text):
            word = match.group(0)
            if word in WRONG:
                if WRONG[word]:
                    sys.stdout.write("& %s 1 %d: %s\\n"
                                     % (word, match.start(), WRONG[word]))
                else:
                    sys.stdout.write("# %s %d\\n" % (word, match.start()))
            elif not terse:
                sys.stdout.write("*\\n")
        sys.stdout.write("\\n")
''')


class ProseTests(unittest.TestCase):
    """Lo que se le da a leer: la prosa, y nada más."""

    def prose(self, text):
        return [line for _n, line in spelling.prose_lines(text)]

    def test_las_formulas_no_se_leen(self):
        self.assertEqual(
            self.prose(r"Sea $\conjunot x$ un número y \[ \lim f \] otro."),
            ["Sea un número y otro."])

    def test_ni_los_entornos_de_formulas_ni_lo_que_llevan_dentro(self):
        text = "\n".join([
            "Antes.",
            r"\begin{align}",
            r"  f(x) &= \text{conjunot} \\",
            r"\end{align}",
            "Después.",
        ])
        self.assertEqual(self.prose(text), ["Antes.", "Después."])

    def test_ni_etiquetas_ni_referencias_ni_rutas(self):
        text = (r"Ver \ref{thm:conjunot} y \cite[p.~3]{Banach}, con "
                r"\includegraphics[width=3cm]{figuras/conjunot.pdf}.")
        prose = " ".join(self.prose(text))
        self.assertNotIn("conjunot", prose)
        self.assertNotIn("Banach", prose)
        self.assertIn("Ver", prose)

    def test_lo_de_dentro_de_una_orden_de_texto_se_queda(self):
        prose = " ".join(self.prose(
            r"\begin{theorem}[Hahn-Banach] Es \emph{importante}."))
        self.assertIn("Hahn-Banach", prose)
        self.assertIn("importante", prose)
        self.assertNotIn("theorem", prose)
        self.assertNotIn("emph", prose)

    def test_el_titulo_de_un_frame_si_y_sus_opciones_no(self):
        prose = " ".join(self.prose(r"\begin{frame}[fragile]{Límites}"))
        self.assertIn("Límites", prose)
        self.assertNotIn("fragile", prose)

    def test_las_llaves_de_una_tabla_no_son_prosa(self):
        prose = " ".join(self.prose(r"\begin{tabular}{lcr} Uno & dos \\"))
        self.assertNotIn("lcr", prose)
        self.assertIn("Uno dos", prose)

    def test_los_acentos_de_latex_son_letras(self):
        # En el material migrado son la mitad, y partían la palabra en dos.
        self.assertEqual(
            self.prose(r"La composici\'{o}n, f\'isica, l\'{\i}mite, ni\~no, "
                       r"ling\"{u}\'istica y \c{c}a."),
            ["La composición, física, límite, niño, lingüística y ça."])

    def test_ni_medidas(self):
        self.assertEqual(self.prose(r"Uno \vskip 3pt dos \\[4pt] tres."),
                         ["Uno dos tres."])

    def test_una_formula_de_varias_lineas_se_salta_entera(self):
        text = "\n".join(["Sea", r"\[", r"  \int_a^b f(x)\,dx", r"\]", "fin."])
        self.assertEqual(list(spelling.prose_lines(text)),
                         [(1, "Sea"), (5, "fin.")])

    def test_los_comentarios_no(self):
        self.assertEqual(self.prose("Bien. % conjunot"), ["Bien."])

    def test_cada_linea_con_su_numero(self):
        found = list(spelling.prose_lines("Uno.\n\n$x$\nDos."))
        self.assertEqual(found, [(1, "Uno."), (4, "Dos.")])


class FakeHunspell(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-spelling-")
        self.addCleanup(shutil.rmtree, self.work, True)
        self.hunspell = os.path.join(self.work, "hunspell")
        with open(self.hunspell, "w", encoding="utf-8") as handle:
            handle.write("#!%s\n%s" % (sys.executable, FAKE))
        os.chmod(self.hunspell, os.stat(self.hunspell).st_mode | stat.S_IEXEC)


class ProtocolTests(FakeHunspell):
    """Leer lo que contesta hunspell."""

    def test_los_diccionarios_que_tiene(self):
        found = spelling.available(self.hunspell)
        self.assertEqual(sorted(found), ["ca_ES", "es_ES"])
        # El valenciano cae en el catalán; el inglés no tiene.
        self.assertTrue(spelling.dictionary_for("va", found).endswith("ca_ES"))
        self.assertIsNone(spelling.dictionary_for("en", found))

    def test_cada_palabra_en_su_linea_con_su_sugerencia(self):
        answers = spelling.misspelled(
            self.hunspell, "es_ES",
            ["Todo bien.", "Un conjunot y tambien.", "Banach."])
        self.assertEqual(answers[0], [])
        self.assertEqual(answers[1], [("conjunot", ["conjunto"]),
                                      ("tambien", ["también"])])
        # Sin sugerencias también se dice.
        self.assertEqual(answers[2], [("Banach", [])])

    def test_una_linea_que_empieza_como_una_orden_no_lo_es(self):
        # `*`, `@`, `+`, `-`, `~` al principio son órdenes de ispell.
        answers = spelling.misspelled(
            self.hunspell, "es_ES", ["*conjunot", "@tambien"])
        self.assertEqual([len(each) for each in answers], [1, 1])


class CheckTests(FakeHunspell):
    """`didacta check --with spelling`, sobre el repositorio de ejemplo."""

    def setUp(self):
        super().setUp()
        self.repo = os.path.join(self.work, "ej")
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"),
                        self.repo)

    def append(self, relative, text):
        with open(os.path.join(self.repo, relative), "a",
                  encoding="utf-8") as handle:
            handle.write("\n" + text + "\n")

    def lines_of(self, relative):
        with open(os.path.join(self.repo, relative), encoding="utf-8") as handle:
            return handle.read().count("\n")

    def check(self, *args, hunspell=None):
        done = subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), "check",
             "--json", *args],
            cwd=self.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1",
                     DIDACTA_HUNSPELL=hunspell or self.hunspell),
        )
        return json.loads(done.stdout)

    def found(self, report, severity="warning"):
        return [f for f in report["findings"]
                if f["check"] == "spelling" and f["severity"] == severity]

    def test_sin_pedirla_no_se_mira(self):
        self.append(os.path.join(ALGEBRA, "es.tex"), "Un conjunot.")
        self.assertEqual(self.found(self.check()), [])

    def test_la_palabra_con_su_leccion_su_idioma_y_su_linea(self):
        es = os.path.join(ALGEBRA, "es.tex")
        self.append(es, "Un conjunot de puntos.")
        found = self.found(self.check("--with", "spelling"))
        self.assertEqual(len(found), 1, found)
        self.assertEqual(found[0]["unit"],
                         "content/calculo/limites/calculo-de-limites/algebra-de-limites")
        self.assertEqual(found[0]["language"], "es")
        self.assertEqual(found[0]["line"], self.lines_of(es))
        self.assertEqual(found[0]["severity"], "warning")
        self.assertIn("«conjunot» (¿conjunto?)", found[0]["message"])

    def test_el_valenciano_con_el_diccionario_de_catalan(self):
        self.append(os.path.join(ALGEBRA, "va.tex"), "Una fucnió contínua.")
        found = self.found(self.check("--with", "spelling"))
        self.assertEqual([f["language"] for f in found], ["va"])
        self.assertIn("«fucnió» (¿funció?)", found[0]["message"])

    def test_las_palabras_del_repositorio_valen(self):
        self.append(os.path.join(ALGEBRA, "es.tex"), "El teorema de Banach.")
        self.assertEqual(len(self.found(self.check("--with", "spelling"))), 1)
        os.makedirs(os.path.join(self.repo, "shared"), exist_ok=True)
        with open(os.path.join(self.repo, spelling.WORDS_FILE), "w",
                  encoding="utf-8") as handle:
            handle.write("# Los nombres propios del curso\nBanach\n")
        self.assertEqual(self.found(self.check("--with", "spelling")), [])

    def test_lo_de_dentro_de_una_formula_no_es_una_errata(self):
        self.append(os.path.join(ALGEBRA, "es.tex"), r"Sea $\mathrm{conjunot}$.")
        self.assertEqual(self.found(self.check("--with", "spelling")), [])

    def test_un_idioma_sin_diccionario_se_dice_una_vez(self):
        # El ejemplo tiene lecciones en inglés, y este hunspell no sabe.
        found = self.found(self.check("--with", "spelling"), "info")
        self.assertEqual([f.get("language") for f in found], ["en"])
        self.assertIn("English", found[0]["message"])
        self.assertIn("en_US", found[0]["message"])

    def test_sin_hunspell_se_dice_y_no_es_un_aviso(self):
        report = self.check("--with", "spelling",
                            hunspell=os.path.join(self.work, "no-hay"))
        self.assertEqual(self.found(report), [])
        found = self.found(report, "info")
        self.assertEqual(len(found), 1)
        self.assertIn("hunspell", found[0]["message"])
        self.assertIn("brew install hunspell", found[0]["message"])
        self.assertTrue(report["ok"])

    def test_el_titulo_de_la_comprobacion(self):
        report = self.check("--with", "spelling")
        self.assertIn("spelling", report["checks"])
        self.assertEqual(report["titles"]["spelling"],
                         "Palabras que el diccionario no conoce")


if __name__ == "__main__":
    unittest.main(verbosity=2)
