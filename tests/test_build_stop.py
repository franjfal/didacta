"""Parar una compilación a medias, con todo lo que haya lanzado.

«Detener» en la aplicación manda SIGTERM a la orden `didacta`. Lo que tiene
que quedar claro es que con eso se para **todo**: latexmk lanza pdflatex, y
parar solo al primero dejaría al segundo escribiendo en la carpeta de salida
mientras la pantalla dice que ya no se compila nada.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import signal
import sys
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402


class _Quiet(build_mod.Engine):
    """Lo justo de un motor para lanzar una orden: ni LaTeX ni plantillas."""

    def __init__(self, on_output=None):
        self.on_output = on_output

    def environment(self):
        return dict(os.environ)


@unittest.skipUnless(os.name == "posix", "los grupos de procesos son de POSIX")
class StopTests(unittest.TestCase):
    def run_and_stop(self, on_output):
        engine = _Quiet(on_output)
        groups = []

        def stop_soon():
            for _ in range(50):
                if build_mod._running:
                    break
                time.sleep(0.05)
            groups.extend(p.pid for p in build_mod._running)
            time.sleep(0.3)
            build_mod.stop_all()

        threading.Thread(target=stop_soon, daemon=True).start()
        started = time.monotonic()
        # Un padre con un hijo: como latexmk con pdflatex.
        code, _ = engine._execute(["sh", "-c", "sleep 30 & sleep 30"], ROOT)
        took = time.monotonic() - started
        return code, took, groups

    def alive_in(self, group):
        """Los procesos vivos del grupo: los zombis --muertos y sin recoger
        todavía por quien los heredó-- no cuentan, porque ya no hacen nada."""
        import subprocess

        rows = subprocess.run(
            ["ps", "-axo", "pgid=,stat=,command="],
            capture_output=True, text=True,
        ).stdout.splitlines()
        return [
            row for row in rows
            if row.split() and row.split()[0] == str(group)
            and not row.split()[1].startswith("Z")
        ]

    def assert_group_gone(self, group):
        for _ in range(60):
            if not self.alive_in(group):
                return
            time.sleep(0.05)
        self.fail("el grupo %d sigue vivo: %s" % (group, self.alive_in(group)))

    def test_sin_nadie_mirando(self):
        code, took, groups = self.run_and_stop(None)
        self.assertLess(took, 10)
        self.assertNotEqual(code, 0)
        self.assertEqual(len(groups), 1)
        self.assert_group_gone(groups[0])
        self.assertEqual(build_mod._running, set())

    def test_con_la_consola_abierta(self):
        code, took, groups = self.run_and_stop(lambda line: None)
        self.assertLess(took, 10)
        self.assertEqual(len(groups), 1)
        self.assert_group_gone(groups[0])


@unittest.skipUnless(os.name == "posix", "SIGTERM es de POSIX")
class SigtermTests(unittest.TestCase):
    def test_sigterm_para_y_sale(self):
        spec = importlib.util.spec_from_loader(
            "didacta_cli_stop",
            importlib.machinery.SourceFileLoader(
                "didacta_cli_stop", os.path.join(ROOT, "cli", "didacta")),
        )
        cli = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cli)
        previous = signal.getsignal(signal.SIGTERM)
        self.addCleanup(signal.signal, signal.SIGTERM, previous)
        stopped = []
        original = build_mod.stop_all
        build_mod.stop_all = lambda: stopped.append(True)
        self.addCleanup(setattr, build_mod, "stop_all", original)

        cli._stop_on_sigterm()
        with self.assertRaises(SystemExit) as raised:
            os.kill(os.getpid(), signal.SIGTERM)
            time.sleep(1)
        self.assertEqual(raised.exception.code, 128 + signal.SIGTERM)
        self.assertEqual(stopped, [True])


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
