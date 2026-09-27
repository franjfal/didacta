"""Compilar varias salidas a la vez.

Se puede porque cada salida tiene su carpeta. Lo que hay que fijar es que de
verdad van a la vez, que los resultados vuelven en el orden pedido aunque
acaben en otro, y que el registro dice de cuál es cada línea.
"""

from __future__ import annotations

import os
import sys
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402


class _Slow(build_mod.Engine):
    """Un motor que tarda lo que se le diga en cada salida, y cuenta."""

    def __init__(self, delays, on_output=None):
        self.on_output = on_output
        self.delays = delays
        self.running = 0
        self.most = 0
        self.lock = threading.Lock()

    def declarations(self):
        return None

    def snippet_definitions(self):
        return None

    def build(self, source, profile, language, **extra):
        with self.lock:
            self.running += 1
            self.most = max(self.most, self.running)
        self.say("=== %s · %s" % (profile, language))
        time.sleep(self.delays[(profile, language)])
        self.say("hecho")
        with self.lock:
            self.running -= 1
        return build_mod.BuildResult(
            document=source, profile=profile, language=language, ok=True)


class ParallelTests(unittest.TestCase):
    JOBS = [
        ("tema-1.tex", "slides", "es", {}),
        ("tema-1.tex", "notes", "es", {}),
        ("tema-1.tex", "slides", "va", {}),
    ]
    DELAYS = {("slides", "es"): 0.3, ("notes", "es"): 0.1, ("slides", "va"): 0.2}

    def test_a_la_vez_y_en_el_orden_pedido(self):
        engine = _Slow(self.DELAYS)
        started = time.monotonic()
        results = engine.build_many(self.JOBS, workers=3)
        took = time.monotonic() - started
        self.assertEqual(engine.most, 3)
        self.assertLess(took, 0.55, "tres a la vez tardan lo que la más lenta")
        self.assertEqual(
            [(r.profile, r.language) for r in results],
            [("slides", "es"), ("notes", "es"), ("slides", "va")],
        )

    def test_cada_linea_dice_de_cual_es(self):
        lines = []
        engine = _Slow(self.DELAYS, on_output=lines.append)
        engine.build_many(self.JOBS, workers=3)
        self.assertIn("[notes · es] hecho", lines)
        self.assertIn("[slides · va] === slides · va", lines)
        self.assertTrue(all(line.startswith("[") for line in lines))

    def test_con_uno_como_siempre(self):
        lines = []
        engine = _Slow(self.DELAYS, on_output=lines.append)
        reported = []
        engine.build_many(self.JOBS, on_result=reported.append, workers=1)
        self.assertEqual(engine.most, 1)
        self.assertEqual(lines[0], "=== slides · es")
        self.assertEqual(len(reported), 3)

    def test_de_salida_la_mitad_de_los_nucleos_y_no_mas_de_cuatro(self):
        workers = build_mod.default_workers()
        self.assertGreaterEqual(workers, 1)
        self.assertLessEqual(workers, 4)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
