"""La clasificación de una unidad: bloque, categoría, tema y etiquetas.

Lo que estas pruebas fijan es la decisión de diseño que hay debajo: la
clasificación la declara la unidad y no la deduce su ruta. Con el nombre del
tema en la carpeta, renombrarlo era mover todas sus unidades y arreglar todas
las composiciones que las nombraban; con un id en `taxonomy.yaml`, es editar
una línea.
"""

from __future__ import annotations

import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import repo as repo_mod  # noqa: E402

class TaxonomyTests(unittest.TestCase):
    """La clasificación, declarada y no deducida de las carpetas.

    El punto entero: un tema tiene un **id**, que es lo que guarda la unidad, y
    un **nombre**, que es lo que lee una persona. Renombrarlo edita una línea y
    no mueve un solo fichero. Con el nombre en la ruta, renombrar un tema era
    mover todas sus unidades y arreglar todas las composiciones que las
    nombraban.
    """

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-taxonomy-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        with open(os.path.join(self.root, "didacta.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("languages: [es, va, en]\ndefault_language: es\n")

    def write(self, text):
        with open(os.path.join(self.root, "taxonomy.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write(text)

    def test_a_repository_without_one_still_works(self):
        taxonomy = repo_mod.Taxonomy.load(self.root)
        self.assertFalse(taxonomy.declared)
        self.assertEqual(taxonomy.categories, [])

    def test_ids_and_names_are_separate_things(self):
        self.write(
            "categories:\n"
            "  - id: analisis-real-una-variable\n"
            "    title:\n"
            "      es: Análisis real de una variable\n"
            "      va: Anàlisi real d'una variable\n"
            "    topics:\n"
            "      - id: la-recta-real\n"
            "        title:\n"
            "          es: La recta real\n"
            "          va: La recta real\n"
        )
        taxonomy = repo_mod.Taxonomy.load(self.root)
        self.assertTrue(taxonomy.declared)
        category = taxonomy.category("analisis-real-una-variable")
        self.assertIsNotNone(category)
        self.assertEqual(category.title("es"), "Análisis real de una variable")
        self.assertEqual(category.title("va"), "Anàlisi real d'una variable")
        topic = category.topic("la-recta-real")
        self.assertIsNotNone(topic)
        self.assertEqual(topic.title("es"), "La recta real")
        # Un idioma que falta cae a otro en lugar de dejar un hueco: una lista
        # desplegable con una entrada vacía no se puede usar.
        self.assertTrue(topic.title("en"))

    def test_an_id_that_is_not_there_is_not_found(self):
        self.write("categories:\n  - id: uno\n")
        taxonomy = repo_mod.Taxonomy.load(self.root)
        self.assertIsNone(taxonomy.category("dos"))
        self.assertIsNone(taxonomy.category("uno").topic("nada"))

    def test_a_malformed_taxonomy_says_what_is_wrong(self):
        for text, expected in [
            ("categories:\n  - title: {es: Sin id}\n", "missing its `id`"),
            ("categories:\n  - id: uno\n  - id: uno\n", "duplicate category"),
            ("categories: 7\n", "should be a list"),
            ("categories:\n  - id: uno\n    topics:\n      - id: t\n      - id: t\n",
             "duplicate topic"),
        ]:
            self.write(text)
            with self.assertRaises(repo_mod.RepoError) as caught:
                repo_mod.Taxonomy.load(self.root)
            self.assertIn(expected, str(caught.exception), text)


class BlockTests(unittest.TestCase):
    """De qué parte de la asignatura es una unidad.

    No es lo mismo que el `kind`: el kind dice qué es el fichero --una
    explicación, un ejemplo, un ejercicio-- y el bloque dice de qué parte de la
    asignatura forma parte. Una explicación teórica dentro de una práctica de
    problemas es `kind: theory` y `block: problems`, y las dos son ciertas.
    """

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="didacta-block-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        with open(os.path.join(self.root, "didacta.yaml"), "w",
                  encoding="utf-8") as handle:
            handle.write("languages: [es]\ndefault_language: es\n")
        self.settings = repo_mod.Settings.load(self.root)

    def unit(self, relpath, meta):
        directory = os.path.join(self.root, relpath)
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "es.tex"), "w", encoding="utf-8") as h:
            h.write("Contenido.\n")
        with open(os.path.join(directory, "unit.yaml"), "w", encoding="utf-8") as h:
            h.write(meta)
        return repo_mod.load_unit(self.root, relpath, self.settings)

    def test_it_is_declared_and_beats_the_tree(self):
        unit = self.unit("content/cat/tema/explicacion",
                         "kind: theory\nblock: problems\n")
        self.assertEqual(unit.kind, "theory")
        self.assertEqual(unit.block, "problems")
        self.assertEqual(unit.area, "content")

    def test_without_it_the_tree_decides_as_before(self):
        self.assertEqual(
            self.unit("content/cat/tema/uno", "kind: theory\n").block, "theory")
        self.assertEqual(
            self.unit("problems/cat/tema/dos", "kind: problem\n").block,
            "problems")

    def test_an_unknown_block_is_an_error(self):
        with self.assertRaises(repo_mod.RepoError) as caught:
            self.unit("content/cat/tema/tres", "block: apuntes\n")
        self.assertIn("unknown block", str(caught.exception))

    def test_it_reaches_the_index_record(self):
        unit = self.unit("content/cat/tema/cuatro",
                         "kind: example\nblock: problems\n")
        self.assertEqual(unit.as_dict()["block"], "problems")
