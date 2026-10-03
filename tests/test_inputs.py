"""Viejo por el contenido de lo que entró en el PDF, no por las fechas."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import inputs  # noqa: E402


class InputsTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-inputs-")
        self.addCleanup(shutil.rmtree, self.root, True)
        self.lesson = os.path.join(self.root, "content", "a", "b", "c")
        os.makedirs(os.path.join(self.lesson, "figures"))
        self.write(os.path.join(self.lesson, "es.tex"), "El texto.\n")
        self.write(os.path.join(self.lesson, "figures", "f.pdf"), "figura")
        self.outside = os.path.join(self.root, "..", os.path.basename(self.root) + "-tex")
        os.makedirs(self.outside, exist_ok=True)
        self.addCleanup(shutil.rmtree, self.outside, True)
        self.write(os.path.join(self.outside, "article.cls"), "de TeX Live")
        self.out = os.path.join(self.root, ".build")
        os.makedirs(self.out)
        self.pdf = os.path.join(self.out, "doc.pdf")
        self.write(self.pdf, "%PDF")
        fls = os.path.join(self.out, "doc.fls")
        self.write(fls, "\n".join([
            "PWD %s" % os.path.join(self.root, "courses"),
            "INPUT ../content/a/b/c/es.tex",
            "INPUT %s" % os.path.join(self.lesson, "figures", "f.pdf"),
            "INPUT %s" % os.path.join(self.outside, "article.cls"),
            "INPUT %s" % os.path.join(self.out, "doc.aux"),
            "OUTPUT %s" % self.pdf,
        ]))
        self.write(os.path.join(self.out, "doc.aux"), "aux")
        self.recorded = inputs.record(self.pdf, fls, [self.root],
                                      lesson_root=self.root)

    def write(self, path, text):
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def test_apunta_lo_del_repositorio_y_nada_mas(self):
        self.assertEqual(
            sorted(self.recorded),
            sorted([os.path.join(self.lesson, "es.tex"),
                    os.path.join(self.lesson, "figures", "f.pdf")]),
        )
        self.assertFalse(inputs.is_stale(self.pdf))

    def test_una_fecha_nueva_con_el_mismo_texto_no_es_viejo(self):
        # Lo que hace un `git pull` o un cambio de rama.
        later = time.time() + 100
        os.utime(os.path.join(self.lesson, "es.tex"), (later, later))
        self.assertFalse(inputs.is_stale(self.pdf))

    def test_un_texto_distinto_si(self):
        self.write(os.path.join(self.lesson, "es.tex"), "Otro texto.\n")
        self.assertTrue(inputs.is_stale(self.pdf))

    def test_mismo_tamano_otro_contenido_tambien(self):
        self.write(os.path.join(self.lesson, "es.tex"), "El textO.\n")
        later = time.time() + 100
        os.utime(os.path.join(self.lesson, "es.tex"), (later, later))
        self.assertTrue(inputs.is_stale(self.pdf))

    def test_una_figura_que_cambia_o_desaparece(self):
        os.remove(os.path.join(self.lesson, "figures", "f.pdf"))
        self.assertTrue(inputs.is_stale(self.pdf))

    def test_una_traduccion_que_aparece(self):
        # Se compiló en valenciano sin `va.tex`, con el castellano en su sitio.
        self.write(os.path.join(self.lesson, "va.tex"), "El text.\n")
        self.assertTrue(inputs.is_stale(self.pdf))

    def test_lo_de_tex_live_no_cuenta(self):
        self.write(os.path.join(self.outside, "article.cls"), "otra versión")
        self.assertFalse(inputs.is_stale(self.pdf))

    def test_una_sola_pasada_cuenta_como_vieja(self):
        # `--fast`: el índice y las referencias pueden no estar al día, y lo
        # que se reparte se compila entero.
        self.assertFalse(inputs.is_quick(self.pdf))
        inputs.record(self.pdf, os.path.join(self.out, "doc.fls"), [self.root],
                      lesson_root=self.root, quick=True)
        self.assertTrue(inputs.is_quick(self.pdf))
        self.assertTrue(inputs.is_stale(self.pdf))

    def test_sin_registro_no_se_sabe(self):
        os.remove(inputs.path_for(self.pdf))
        self.assertIsNone(inputs.is_stale(self.pdf))


def _latexmk():
    return shutil.which("latexmk") is not None


@unittest.skipUnless(_latexmk(), "hace falta latexmk")
class RealBuildTests(unittest.TestCase):
    """Con el repositorio de ejemplo y LaTeX de verdad."""

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-inputs-real-")
        self.addCleanup(shutil.rmtree, self.work, True)
        shutil.copytree(os.path.join(ROOT, "app", "assets", "ejemplo"),
                        os.path.join(self.work, "ej"))
        self.repo = os.path.join(self.work, "ej")

    def cli(self, *args):
        return subprocess.run(
            [sys.executable, os.path.join(ROOT, "cli", "didacta"), *args],
            cwd=self.repo, capture_output=True, text=True,
            env=dict(os.environ, NO_COLOR="1"),
        )

    def built(self):
        import json
        done = self.cli("built", "calculo-i@2026-2027", "--json")
        data = json.loads(done.stdout)
        return {
            (o["profile"], o["language"]): o
            for d in data["documents"] if d["document"] == "tema-1"
            for o in d["outputs"]
        }

    def test_compilar_apunta_y_se_sabe_si_esta_viejo(self):
        done = self.cli("build", "calculo-i@2026-2027/tema-1", "-p", "notes",
                        "--json")
        self.assertEqual(done.returncode, 0, done.stderr[-800:])
        output = self.built()[("notes", "es")]
        self.assertTrue(os.path.isfile(inputs.path_for(output["pdf"])))
        self.assertFalse(output["stale"])

        lesson = os.path.join(self.repo, "content", "calculo", "limites",
                              "calculo-de-limites", "algebra-de-limites",
                              "es.tex")
        # Solo la fecha: no está viejo.
        later = time.time() + 100
        os.utime(lesson, (later, later))
        self.assertFalse(self.built()[("notes", "es")]["stale"])
        # El texto: sí.
        with open(lesson, "a", encoding="utf-8") as handle:
            handle.write("\nUna frase más.\n")
        self.assertTrue(self.built()[("notes", "es")]["stale"])

    def test_una_pasada_queda_vieja_hasta_compilarla_entera(self):
        import json
        lesson = os.path.join(self.repo, "content", "calculo", "limites",
                              "calculo-de-limites", "algebra-de-limites",
                              "es.tex")
        done = self.cli("build", "calculo-i@2026-2027/tema-1", "-p", "notes",
                        "--json")
        self.assertEqual(done.returncode, 0, done.stderr[-800:])
        with open(lesson, "a", encoding="utf-8") as handle:
            handle.write("\nUna frase de la vista rápida.\n")

        done = self.cli("build", "calculo-i@2026-2027/tema-1", "-p", "notes",
                        "--fast", "--json")
        self.assertEqual(done.returncode, 0, done.stderr[-800:])
        [result] = json.loads(done.stdout[done.stdout.index("["):])
        self.assertTrue(result["quick"])
        output = self.built()[("notes", "es")]
        self.assertTrue(output["quick"])
        self.assertTrue(output["stale"])
        # El `.fls` es el de esta pasada, no el de la anterior.
        fls = os.path.splitext(output["pdf"])[0] + ".fls"
        self.assertGreaterEqual(os.path.getmtime(fls),
                                os.path.getmtime(lesson))
        quick_pdf = os.path.getmtime(output["pdf"])
        time.sleep(1.1)

        # Deshacer el cambio y compilar entera: latexmk no puede dar por
        # buena la pasada suelta, que tenía la frase.
        with open(lesson, encoding="utf-8") as handle:
            text = handle.read()
        with open(lesson, "w", encoding="utf-8") as handle:
            handle.write(text.replace("\nUna frase de la vista rápida.\n", ""))
        done = self.cli("build", "calculo-i@2026-2027/tema-1", "-p", "notes",
                        "--json")
        self.assertEqual(done.returncode, 0, done.stderr[-800:])
        [result] = json.loads(done.stdout[done.stdout.index("["):])
        self.assertNotIn("quick", result)
        output = self.built()[("notes", "es")]
        self.assertFalse(output["quick"])
        self.assertFalse(output["stale"])
        # Y se volvió a componer: el PDF no es el de la pasada suelta.
        self.assertGreater(os.path.getmtime(output["pdf"]), quick_pdf)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
