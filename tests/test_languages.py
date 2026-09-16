"""Los idiomas a los que Didacta sabe imprimir.

Didacta imprime por su cuenta treinta y seis palabras --«Teorema»,
«Demostración», «Curso»-- y el contenido no las lleva: las pone el paquete,
según el idioma del documento. Cada idioma es un `latex/lang/didacta-lang-XX.def`
con esas treinta y seis, y una línea en el registro del motor.

Lo que se fija aquí es que las dos mitades no se separen. Es el fallo fácil:
se añade el `.def` y se olvida el registro --el motor rechaza el código antes
de compilar, con un error que habla de idiomas desconocidos-- o al revés --el
motor lo acepta, y LaTeX para a mitad de la compilación--. Las dos veces el
mensaje habla de otra cosa.

El contenido de las traducciones no se comprueba aquí y no puede comprobarse:
si «Corol·lari» es la palabra que usa quien da clase en catalán lo dice quien
da clase en catalán. Los ficheros base lo avisan en su cabecera.
"""

from __future__ import annotations

import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import profiles as profiles_mod  # noqa: E402

LANG_DIR = os.path.join(ROOT, "latex", "lang")

_DEF = re.compile(r"^\\def\\didacta([A-Za-z]+)\{", re.M)

#: Las claves que un idioma tiene que definir, tomadas del castellano, que es
#: el que se escribió a mano y el que usa el material de verdad.
def keys_of(code):
    path = os.path.join(LANG_DIR, "didacta-lang-%s.def" % code)
    with open(path, encoding="utf-8") as handle:
        return set(_DEF.findall(handle.read()))


def files_present():
    return {
        name[len("didacta-lang-"):-len(".def")]
        for name in os.listdir(LANG_DIR)
        if name.startswith("didacta-lang-") and name.endswith(".def")
    }


class LanguageRegistry(unittest.TestCase):
    def test_every_registered_language_has_its_file(self):
        missing = [c for c in profiles_mod.LANGUAGES
                   if c not in files_present()]
        self.assertEqual(missing, [], "sin fichero de idioma: %s" % missing)

    def test_every_file_is_registered(self):
        # Al revés importa igual: un `.def` que el motor no conoce no se puede
        # pedir, así que no existe para nadie.
        extra = sorted(files_present() - set(profiles_mod.LANGUAGES))
        self.assertEqual(extra, [], "sin registrar en profiles.py: %s" % extra)

    def test_each_language_has_a_name_and_a_babel_option(self):
        for code in profiles_mod.LANGUAGES:
            self.assertTrue(profiles_mod.LANGUAGE_NAMES.get(code), code)
            self.assertTrue(profiles_mod.BABEL.get(code), code)

    def test_no_language_is_declared_twice(self):
        codes = list(profiles_mod.LANGUAGES)
        self.assertEqual(len(codes), len(set(codes)))

    def test_spanish_stays_the_default(self):
        # `didacta.sty` cae en `es` cuando el documento no dice nada, y el
        # material existente cuenta con ello.
        self.assertEqual(profiles_mod.LANGUAGES[0], "es")


class LatexSide(unittest.TestCase):
    """La lista que `didacta.sty` lleva por su cuenta."""

    def test_the_section_keys_cover_every_language(self):
        # `\DidactaSection{es=..., fr=...}` acepta una clave por idioma, y
        # keyval no puede preguntarle al motor cuáles hay. Si la lista de la
        # hoja de estilo se queda corta, dar un título en el idioma que falta
        # es un error de compilación en la línea de la composición; si le
        # sobra, no pasa nada, pero deja de ser verdad lo que dice el
        # comentario de al lado.
        path = os.path.join(ROOT, "latex", "didacta.sty")
        with open(path, encoding="utf-8") as handle:
            found = re.search(r"\\def\\didacta@langs\{([^}]*)\}", handle.read())
        self.assertIsNotNone(found, "didacta.sty ya no declara `\\didacta@langs`")
        self.assertEqual(
            found.group(1).split(","),
            list(profiles_mod.LANGUAGES),
        )


class LanguageFiles(unittest.TestCase):
    def test_none_of_them_is_missing_a_string(self):
        # Una clave que falta no es un fallo de compilación: LaTeX imprime la
        # secuencia sin definir donde iba la palabra, o peor, hereda la del
        # documento anterior en el mismo `latexmk`.
        expected = keys_of("es")
        self.assertIn("TheoremName", expected)
        for code in profiles_mod.LANGUAGES:
            self.assertEqual(
                keys_of(code),
                expected,
                "a didacta-lang-%s.def le faltan o le sobran cadenas" % code,
            )

    def test_the_printed_strings_are_ascii(self):
        # Los acentos van en notación LaTeX (`\'o`), no en UTF-8: el `.def` se
        # carga antes que `inputenc`, así que una «ó» de verdad se compone como
        # dos caracteres de basura y nadie lo ve hasta que el PDF está hecho.
        #
        # Solo los valores. Los comentarios los tira TeX antes de componer
        # nada, y el fichero valenciano los tiene acentuados desde que se
        # escribió a mano.
        for code in profiles_mod.LANGUAGES:
            path = os.path.join(LANG_DIR, "didacta-lang-%s.def" % code)
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            for line in text.splitlines():
                if not line.startswith("\\def\\didacta"):
                    continue
                self.assertTrue(
                    line.isascii(),
                    "didacta-lang-%s.def compone UTF-8 crudo: %s" % (code, line),
                )

    def test_the_babel_option_matches_the_registry(self):
        # El motor pasa la opción de babel y el `.def` también la declara. Si
        # discrepan, el documento se compone con una partición de palabras que
        # no es la suya y nadie mira los guiones hasta que es tarde.
        declared = re.compile(r"\\def\\didactaBabelName\{([^}]*)\}")
        for code in profiles_mod.LANGUAGES:
            path = os.path.join(LANG_DIR, "didacta-lang-%s.def" % code)
            with open(path, encoding="utf-8") as handle:
                found = declared.search(handle.read())
            self.assertIsNotNone(found, code)
            self.assertEqual(found.group(1), profiles_mod.BABEL[code], code)

    def test_each_one_ends_where_it_should(self):
        for code in profiles_mod.LANGUAGES:
            path = os.path.join(LANG_DIR, "didacta-lang-%s.def" % code)
            with open(path, encoding="utf-8") as handle:
                self.assertTrue(handle.read().rstrip().endswith("\\endinput"))


if __name__ == "__main__":
    unittest.main()
