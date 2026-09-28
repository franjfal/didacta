"""La interfaz de la aplicación, en valenciano y en inglés: que no quede
ningún texto sin decidir.

Cada `tr('…')` de `app/lib` es una clave (ver `app/lib/l10n/tr.dart`), y
`app/l10n/va.json` y `app/l10n/en.json` tienen que decir de cada una su
traducción --con los mismos marcadores `{0}`-- o `null` si no es un texto de
la interfaz. Un texto nuevo sin traducir sale en castellano, que no rompe
nada, pero esta prueba lo dice para que no se quede así.

Y los catálogos que lee la aplicación, al día: `tool/l10n.py build`.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.abspath(os.path.join(HERE, "..", "app"))
sys.path.insert(0, os.path.join(APP, "tool"))

import l10n  # noqa: E402


class L10nTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.keys = l10n.extract()
        cls.tables = {code: l10n.load(code) for code in l10n.LANGUAGES}

    def test_cada_clave_esta_decidida(self):
        for code, table in self.tables.items():
            missing = [key for key in self.keys if key not in table]
            self.assertEqual(missing[:10], [], "%s: sin traducir" % code)

    def test_los_marcadores_cuadran(self):
        for code, table in self.tables.items():
            for key, value in table.items():
                if value is None:
                    continue
                self.assertEqual(
                    set(re.findall(r"\{\d+\}", value)),
                    set(re.findall(r"\{\d+\}", key)),
                    "%s: %r" % (code, key[:60]),
                )

    def test_lo_que_no_es_interfaz_es_lo_mismo_en_los_dos(self):
        va, en = self.tables["va"], self.tables["en"]
        for key in self.keys:
            if key in va and key in en:
                self.assertEqual(va[key] is None, en[key] is None, key[:60])

    def test_los_catalogos_estan_al_dia(self):
        before = {}
        for code in l10n.LANGUAGES:
            path = os.path.join(APP, "lib", "l10n", "catalog_%s.dart" % code)
            with open(path, encoding="utf-8") as handle:
                before[code] = handle.read()
        done = subprocess.run([sys.executable, os.path.join(APP, "tool",
                                                           "l10n.py"), "build"],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout)
        for code in l10n.LANGUAGES:
            path = os.path.join(APP, "lib", "l10n", "catalog_%s.dart" % code)
            with open(path, encoding="utf-8") as handle:
                self.assertEqual(handle.read(), before[code],
                                 "catalog_%s.dart no está al día: "
                                 "python3 app/tool/l10n.py build" % code)


class CodecTests(unittest.TestCase):
    def test_ida_y_vuelta_de_un_literal(self):
        for text in ["Guardado en {0}", "Una 'cita' y $dinero", "a\nb",
                     "barra \\ y tab\t"]:
            self.assertEqual(l10n.decode(l10n.encode(text)), text)

    def test_literales_pegados(self):
        self.assertEqual(l10n.decode("'Hola, ' 'mundo'"), "Hola, mundo")


if __name__ == "__main__":
    unittest.main()
