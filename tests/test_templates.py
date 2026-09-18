"""Plantillas de compilación: perfiles de salida que escribe quien enseña.

Las quince salidas de Didacta estaban escritas en `latex/didacta-profiles.tex`,
así que cambiar el margen de los apuntes era editar el programa. Una plantilla
es lo mismo --clase de documento, opciones, ejes-- declarado en el repositorio,
con un preámbulo propio al lado.

Lo que estas pruebas fijan es lo que hace que esto no pueda romper nada:

* un repositorio sin `templates.yaml` compila exactamente como antes;
* una plantilla con el id de una de serie la **sustituye** al compilar con
  Didacta, y la de serie sigue ahí para un `pdflatex` a mano;
* el preámbulo de la plantilla se lee **al final** del de Didacta, que es lo
  que permite que redefina lo que Didacta acaba de definir.

La última se comprueba compilando de verdad: un preámbulo que se carga en el
sitio equivocado produce un PDF de aspecto razonable, y eso no lo caza ningún
test de estructura.
"""

from __future__ import annotations

import glob
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import build as build_mod  # noqa: E402
from didacta import profiles as profiles_mod  # noqa: E402
from didacta import templates as templates_mod  # noqa: E402

LATEX_DIR = os.path.join(ROOT, "latex")
DEMO = os.path.join(ROOT, "examples", "demo-course")


def toolchain_available():
    return all(shutil.which(tool) for tool in ("latexmk", "pdflatex"))


class TemplateStore:
    """Un directorio de plantillas, montado para una prueba."""

    def __init__(self, directory):
        self.directory = directory

    def write(self, yaml_text, preambles=None):
        with open(os.path.join(self.directory, templates_mod.TEMPLATES_META),
                  "w", encoding="utf-8") as handle:
            handle.write(yaml_text)
        for identifier, text in (preambles or {}).items():
            folder = os.path.join(self.directory, templates_mod.TEMPLATES_DIR)
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, "%s.tex" % identifier),
                      "w", encoding="utf-8") as handle:
                handle.write(text)

    def load(self):
        return templates_mod.load(self.directory)


class LoadingTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-templates-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.store = TemplateStore(self.root)

    def test_a_directory_without_a_file_declares_none(self):
        """Y eso es lo corriente: se compila con las quince de siempre."""
        self.assertEqual(templates_mod.load(self.root), [])

    def test_a_template_is_a_profile(self):
        """Hereda de Profile a propósito: lo que compila un perfil, compila
        una plantilla sin enterarse de que lo es."""
        self.store.write(
            "templates:\n"
            "  - id: apuntes-a5\n"
            "    title: {es: Apuntes de bolsillo}\n"
            "    class: article\n"
            "    options: 10pt,a5paper\n"
            "    axes:\n"
            "      medium: document\n"
            "      detail: full\n"
        )
        template = self.store.load()[0]
        self.assertIsInstance(template, profiles_mod.Profile)
        self.assertEqual(template.id, "apuntes-a5")
        self.assertEqual(template.document_class, "article")
        self.assertEqual(template.class_options, "10pt,a5paper")
        self.assertEqual(template.title("es"), "Apuntes de bolsillo")
        self.assertFalse(template.is_slides)
        # El prólogo que selecciona la salida es el del perfil, sin más.
        self.assertIn(r"\def\DidactaProfile{apuntes-a5}",
                      template.pretex("es"))

    def test_without_a_title_it_reads_by_what_it_does(self):
        """Mejor que el id, y no obliga a rellenar tres idiomas para empezar."""
        self.store.write(
            "templates:\n"
            "  - id: mias\n"
            "    class: beamer\n"
            "    axes: {medium: slides, pauses: on}\n"
        )
        self.assertEqual(self.store.load()[0].title("es"), "Diapositivas")

    def test_pauses_off_is_the_word_and_not_the_boolean(self):
        """`off` en YAML es el booleano falso.

        Es la forma natural de escribirlo --y la que sale de copiar el eje tal
        como está en `didacta-profiles.tex`--, así que se traduce en vez de
        rechazarse con un mensaje sobre `False` que no significa nada.
        """
        self.store.write(
            "templates:\n"
            "  - id: plana\n"
            "    class: beamer\n"
            "    axes: {medium: slides, pauses: off}\n"
        )
        template = self.store.load()[0]
        self.assertEqual(template.axes["pauses"], "off")
        self.assertFalse(template.pauses)

    def test_a_preamble_is_a_tex_file_next_to_it(self):
        self.store.write(
            "templates:\n  - id: mias\n    class: article\n",
            preambles={"mias": "\\usepackage{lmodern}\n"},
        )
        template = self.store.load()[0]
        self.assertTrue(template.preamble.endswith("templates/mias.tex"))
        self.assertTrue(os.path.isfile(template.preamble))

    def test_without_one_it_is_none_rather_than_a_missing_path(self):
        """Para que el motor no le pase a LaTeX una ruta que no existe."""
        self.store.write("templates:\n  - id: mias\n    class: article\n")
        self.assertIsNone(self.store.load()[0].preamble)

    def test_active_by_default_and_switchable(self):
        """Apagar una la deja declarada y fuera de las salidas.

        Borrarla perdería su preámbulo, que es justo lo que se quiere guardar
        de una versión que este curso no se da.
        """
        self.store.write(
            "templates:\n"
            "  - id: una\n    class: article\n"
            "  - id: otra\n    class: article\n    active: false\n"
        )
        first, second = self.store.load()
        self.assertTrue(first.active)
        self.assertFalse(second.active)

    def test_a_malformed_declaration_says_what_is_wrong(self):
        for text, expected in [
            ("templates:\n  - class: article\n", "missing its `id`"),
            ("templates:\n  - id: a\n", "missing its `class`"),
            ("templates:\n  - id: a\n    class: article\n  - id: a\n"
             "    class: book\n", "duplicate template"),
            ("templates: 7\n", "should be a list"),
            ("templates:\n  - id: a\n    class: article\n    axes: {foo: bar}\n",
             "unknown axis"),
            ("templates:\n  - id: a\n    class: article\n"
             "    axes: {medium: papel}\n", "allowed"),
        ]:
            self.store.write(text)
            with self.assertRaises(templates_mod.TemplateError) as caught:
                self.store.load()
            self.assertIn(expected, str(caught.exception), text)


class MergeTests(unittest.TestCase):
    """Varios directorios abiertos: se juntan, no se eligen."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-templates-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

    def store(self, name, text):
        directory = os.path.join(self.root, name)
        os.makedirs(directory, exist_ok=True)
        store = TemplateStore(directory)
        store.write(text)
        return directory

    def test_the_first_to_declare_an_id_wins(self):
        first = self.store(
            "teoria",
            "templates:\n  - id: notes\n    class: article\n"
            "    title: {es: Los míos}\n",
        )
        second = self.store(
            "problemas",
            "templates:\n  - id: notes\n    class: book\n"
            "    title: {es: Los otros}\n"
            "  - id: hoja\n    class: article\n",
        )
        merged = templates_mod.load_many([first, second])
        by_id = {template.id: template for template in merged}
        self.assertEqual(by_id["notes"].title("es"), "Los míos")
        # Y la que solo declara el segundo entra igual: es lo que permite que
        # el bloque de un repositorio se compile con la plantilla del otro.
        self.assertIn("hoja", by_id)


class DeclarationTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-templates-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

    def test_the_declaration_is_what_latex_reads(self):
        template = templates_mod.Template(
            id="mias", document_class="article", class_options="12pt",
            axes={"medium": "document", "pauses": "off"},
        )
        self.assertEqual(
            template.declaration(),
            r"\DidactaDeclareProfile{mias}{article}{12pt}"
            r"{medium=document,pauses=off}",
        )

    def test_nothing_declared_writes_no_file(self):
        """Una compilación sin plantillas no deja rastro, y el arranque de
        LaTeX no lee nada: por eso no puede romper un repositorio que no las
        usa."""
        path = os.path.join(self.root, "declare.tex")
        self.assertIsNone(templates_mod.write_declarations(path, []))
        self.assertFalse(os.path.exists(path))

    def test_an_inactive_one_is_declared_too(self):
        """Apagada quiere decir «no la compiles», no «que LaTeX no sepa qué
        es»: quien pida una apagada a mano tiene que obtener su PDF."""
        path = os.path.join(self.root, "sub", "declare.tex")
        templates_mod.write_declarations(path, [
            templates_mod.Template(id="apagada", document_class="article",
                                   class_options="", axes={}, active=False),
        ])
        with open(path, encoding="utf-8") as handle:
            written = handle.read()
        self.assertIn("{apagada}", written)


@unittest.skipUnless(toolchain_available(), "latexmk and pdflatex are required")
class CompilingTests(unittest.TestCase):
    """Compilando de verdad, que es lo único que prueba el preámbulo."""

    @classmethod
    def setUpClass(cls):
        cls.source = sorted(
            glob.glob(os.path.join(DEMO, "courses", "*", "*", "*.tex"))
        )[0]
        cls.content_root = os.path.relpath(
            DEMO, os.path.dirname(cls.source)
        )

    def setUp(self):
        self.work = tempfile.mkdtemp(prefix="didacta-tpl-build-")
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)
        self.store = TemplateStore(os.path.join(self.work, "store"))
        os.makedirs(self.store.directory)

    def engine(self, dirs=()):
        return build_mod.Engine(
            latex_dir=LATEX_DIR,
            build_dir=os.path.join(self.work, "build"),
            template_dirs=dirs,
        )

    def build(self, engine, profile):
        return engine.build(self.source, profile, "es",
                            content_root=self.content_root)

    def test_a_repository_with_no_templates_compiles_as_always(self):
        engine = self.engine()
        self.assertIsNone(engine.declarations())
        self.assertTrue(self.build(engine, "notes").ok)

    def test_a_new_template_compiles_and_its_preamble_is_read(self):
        self.store.write(
            "templates:\n"
            "  - id: apuntes-a5\n"
            "    title: {es: Apuntes de bolsillo}\n"
            "    class: article\n"
            "    options: 10pt,oneside\n"
            "    axes: {medium: document, detail: full}\n",
            preambles={"apuntes-a5": "\\usepackage{lmodern}\n"},
        )
        engine = self.engine([self.store.directory])
        result = self.build(engine, "apuntes-a5")
        self.assertTrue(result.ok, [str(d) for d in result.errors[:2]])

        with open(result.log, encoding="utf-8", errors="replace") as handle:
            log = handle.read()
        self.assertIn("lmodern", log)

    def test_a_template_replaces_the_shipped_output_of_the_same_id(self):
        """Editar «Apuntes» es declarar una plantilla que se llama `notes`.

        Y la de serie sigue en `didacta-profiles.tex`, que es lo que mantiene
        vivo un `pdflatex master.tex` a mano.
        """
        self.store.write(
            "templates:\n"
            "  - id: notes\n"
            "    class: book\n"
            "    options: 11pt,twoside\n"
            "    axes: {medium: document, detail: full}\n"
        )
        engine = self.engine([self.store.directory])
        self.assertEqual(engine.profiles["notes"].document_class, "book")
        result = self.build(engine, "notes")
        self.assertTrue(result.ok, [str(d) for d in result.errors[:2]])
        # Y el registro del disco no se ha tocado.
        shipped = profiles_mod.load(LATEX_DIR)
        self.assertEqual(shipped["notes"].document_class, "article")

    def test_a_preamble_can_redefine_what_didacta_defined(self):
        """Es la razón de que se lea al final: para eso está una plantilla."""
        self.store.write(
            "templates:\n"
            "  - id: mias\n"
            "    class: article\n"
            "    axes: {medium: document}\n",
            preambles={
                "mias": "\\renewcommand{\\keyterm}[1]{\\emph{#1}}\n"
                        "\\typeout{DIDACTA-PLANTILLA-APLICADA}\n",
            },
        )
        engine = self.engine([self.store.directory])
        result = self.build(engine, "mias")
        self.assertTrue(result.ok, [str(d) for d in result.errors[:2]])
        with open(result.log, encoding="utf-8", errors="replace") as handle:
            self.assertIn("DIDACTA-PLANTILLA-APLICADA", handle.read())


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
