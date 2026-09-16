"""El servidor MCP: lo que un modelo puede hacer con el repositorio.

Existe para delegar trabajo --traducir, corregir una errata en las cuarenta
unidades que la repiten-- en un LLM. Eso quiere decir que un programa que no
controlamos va a escribir en los ficheros de alguien, así que la mitad de este
fichero prueba lo que **no** se puede hacer.

Las tres reglas que sostienen que esto sea aceptable:

  1. escribir hay que pedirlo, repositorio por repositorio;
  2. ninguna ruta sale de la raíz del repositorio que la nombra;
  3. no se toca git: lo escrito queda en disco, y quien publica es la persona
     mirando el diff.

Si alguna de las tres deja de cumplirse, esto pasa de ser una herramienta útil
a ser una forma de que un modelo publique un error en el material de un curso
que se está dando.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import mcp as mcp_mod  # noqa: E402

DEMO = os.path.join(ROOT, "examples", "demo-course")


class Harness(unittest.TestCase):
    """Un repositorio de verdad, copiado, y un servidor encima."""

    writable = True

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="didacta-mcp-")
        self.root = os.path.join(self.tmp, "repo")
        shutil.copytree(DEMO, self.root)
        self.lines = []
        self.repository = mcp_mod.Repository(
            self.root, writable=self.writable, label="pruebas")
        self.server = mcp_mod.Server(
            mcp_mod.Workspace([self.repository]),
            journal=mcp_mod.Journal(self.lines.append),
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # -- ayudas -----------------------------------------------------------

    def ask(self, method, params=None, identifier=1):
        return self.server.handle({
            "jsonrpc": "2.0", "id": identifier,
            "method": method, "params": params or {},
        })

    def call(self, name, **arguments):
        out = self.ask("tools/call", {"name": name, "arguments": arguments})
        result = out["result"]
        body = result["content"][0]["text"]
        if result.get("isError"):
            raise AssertionError("la herramienta falló: %s" % body)
        try:
            return json.loads(body)
        except ValueError:
            return body

    def failing(self, name, **arguments):
        """Lo mismo, pero esperando que se niegue. Devuelve el mensaje."""
        out = self.ask("tools/call", {"name": name, "arguments": arguments})
        self.assertTrue(
            out["result"].get("isError"),
            "se esperaba que %s se negara y no lo hizo" % name,
        )
        return out["result"]["content"][0]["text"]

    def events(self, name):
        return [json.loads(line) for line in self.lines
                if json.loads(line).get("event") == name]


class Protocol(Harness):
    def test_initialize_answers_with_what_the_client_asked_for(self):
        out = self.ask("initialize", {
            "protocolVersion": "2024-11-05",
            "clientInfo": {"name": "prueba", "version": "1"},
        })
        result = out["result"]
        # La versión que pidió, no la nuestra: negociar a la baja es mejor
        # que negarse a hablar con un cliente de hace tres meses.
        self.assertEqual(result["protocolVersion"], "2024-11-05")
        self.assertEqual(result["serverInfo"]["name"], "didacta")
        self.assertIn("mismo repositorio", result["instructions"])

    def test_a_notification_is_never_answered(self):
        # Una petición sin `id` no se contesta ni para decir que no se
        # entendió: un cliente que recibe una respuesta que no pidió se
        # queda esperando la suya para siempre.
        self.assertIsNone(self.server.handle({
            "jsonrpc": "2.0", "method": "notifications/initialized",
        }))
        self.assertIsNone(self.server.handle({
            "jsonrpc": "2.0", "method": "no/existe",
        }))

    def test_an_unknown_method_is_an_error_with_its_id(self):
        out = self.ask("no/existe", identifier=7)
        self.assertEqual(out["id"], 7)
        self.assertEqual(out["error"]["code"], -32601)

    def test_every_tool_declares_a_schema_and_whether_it_writes(self):
        tools = self.ask("tools/list")["result"]["tools"]
        self.assertTrue(tools)
        for tool in tools:
            self.assertEqual(tool["inputSchema"]["type"], "object", tool["name"])
            self.assertTrue(tool["description"].strip(), tool["name"])
            self.assertIn("readOnlyHint", tool["annotations"], tool["name"])

    def test_a_tool_that_fails_answers_with_a_result_the_model_can_read(self):
        # La distinción que importa: un trabajo que sale mal es un resultado
        # con `isError`, porque el modelo lo lee y lo corrige. Un error de
        # JSON-RPC lo gestiona el cliente y el modelo no llega a verlo.
        out = self.ask("tools/call", {
            "name": "read_unit", "arguments": {"path": "no/existe"},
        })
        self.assertNotIn("error", out)
        self.assertTrue(out["result"]["isError"])

    def test_a_tool_that_does_not_exist_is_a_protocol_error(self):
        # Eso no es un trabajo que salga mal: es que el cliente llamó a algo
        # que no está. Con la lista dentro, que es lo que permite corregirse.
        out = self.ask("tools/call", {"name": "no_existe", "arguments": {}})
        self.assertEqual(out["error"]["code"], -32602)
        self.assertIn("read_unit", out["error"]["message"])

    def test_a_missing_argument_is_told_not_crashed(self):
        message = self.failing("read_unit")
        self.assertIn("path", message)


class Reading(Harness):
    def test_the_repositories_say_whether_they_can_be_written(self):
        out = self.call("list_repositories")
        self.assertEqual(out["repositories"][0]["id"], "pruebas")
        self.assertTrue(out["repositories"][0]["writable"])

    def test_courses_carry_their_years_and_languages(self):
        courses = self.call("list_courses")["courses"]
        self.assertTrue(courses)
        first = courses[0]
        self.assertTrue(first["years"])
        self.assertIn("es", first["languages"])

    def test_a_course_gives_the_units_each_document_composes(self):
        # Es el mapa: sin esto un modelo no sabe qué leer después.
        courses = self.call("list_courses")["courses"]
        course = courses[0]
        out = self.call("read_course", course=course["id"],
                        year=course["years"][0]["year"])
        self.assertTrue(out["documents"])
        self.assertTrue(out["documents"][0]["units"])

    def test_a_unit_comes_with_its_text_and_its_languages(self):
        found = self.call("search_units", limit=1)["units"]
        unit = self.call("read_unit", path=found[0]["path"])
        self.assertTrue(unit["text"].strip())
        self.assertIn("es", unit["languages"])

    def test_a_unit_can_be_asked_for_by_composition_reference(self):
        # `analisis/reales/supremo`, sin el árbol delante: es como se
        # escriben en `year.yaml`, así que es lo que un modelo va a mandar
        # después de leer un curso.
        courses = self.call("list_courses")["courses"]
        course = courses[0]
        year = self.call("read_course", course=course["id"],
                         year=course["years"][0]["year"])
        reference = year["documents"][0]["units"][0]
        self.assertNotIn("content/", reference)
        self.assertTrue(self.call("read_unit", path=reference)["text"])

    def test_searching_by_missing_language_is_the_translation_queue(self):
        found = self.call("search_units", missingLanguage="en")["units"]
        for unit in found:
            self.assertFalse(unit["languages"]["en"]["exists"], unit["path"])

    def test_translation_status_counts_what_is_left(self):
        out = self.call("translation_status", language="en")
        self.assertEqual(out["total"], len(out["units"]))
        for unit in out["units"]:
            self.assertTrue(unit["reference"])

    def test_a_language_the_unit_does_not_have_says_which_it_has(self):
        found = self.call("search_units", missingLanguage="en", limit=1)["units"]
        if not found:
            self.skipTest("el demo ya está traducido entero")
        message = self.failing("read_unit", path=found[0]["path"], language="en")
        self.assertIn("tiene:", message)


class Writing(Harness):
    def unit(self):
        return self.call("search_units", limit=1)["units"][0]

    def test_writing_a_translation_creates_the_file(self):
        unit = self.unit()
        out = self.call("write_unit", path=unit["path"], language="en",
                        text="\\didactatitle{A definition}\nThe text.\n")
        self.assertTrue(out["created"])
        self.assertTrue(
            os.path.isfile(os.path.join(self.root, unit["path"], "en.tex")))

    def test_and_the_unit_then_reads_back_in_that_language(self):
        unit = self.unit()
        self.call("write_unit", path=unit["path"], language="en", text="Hello.")
        back = self.call("read_unit", path=unit["path"], language="en")
        self.assertEqual(back["text"].strip(), "Hello.")

    def test_a_file_always_ends_in_a_newline(self):
        # Sin él, el siguiente diff marca la última línea entera aunque nadie
        # la haya tocado.
        unit = self.unit()
        self.call("write_unit", path=unit["path"], language="en", text="Sin salto")
        with open(os.path.join(self.root, unit["path"], "en.tex")) as handle:
            self.assertTrue(handle.read().endswith("\n"))

    def test_creating_a_unit_leaves_it_buildable_and_findable(self):
        out = self.call("create_unit", path="pruebas/una-nueva",
                        title="Una nueva", text="\\didactatitle{Una}\nTexto.")
        self.assertEqual(out["path"], "content/pruebas/una-nueva")
        for name in ("unit.yaml", "es.tex"):
            self.assertTrue(
                os.path.isfile(os.path.join(self.root, out["path"], name)), name)
        found = self.call("search_units", query="una-nueva")["units"]
        self.assertEqual(len(found), 1)

    def test_a_new_unit_marks_the_other_languages_as_pending(self):
        # Comentados, que es como el repositorio cuenta lo que falta. Un
        # título vacío sería un título, y saldría en el PDF.
        out = self.call("create_unit", path="pruebas/otra",
                        title="Otra", text="Texto.")
        with open(os.path.join(self.root, out["path"], "unit.yaml")) as handle:
            meta = handle.read()
        self.assertIn("# TODO: va", meta)
        self.assertIn("# TODO: en", meta)

    def test_metadata_changes_the_title_per_language(self):
        unit = self.unit()
        out = self.call("set_unit_metadata", path=unit["path"],
                        title={"es": "Nuevo", "en": "New"}, tags=["a", "b"])
        self.assertEqual(out["title"]["es"], "Nuevo")
        self.assertEqual(out["title"]["en"], "New")

    def test_an_empty_title_removes_that_language_rather_than_blanking_it(self):
        unit = self.unit()
        out = self.call("set_unit_metadata", path=unit["path"],
                        title={"es": "Solo este", "va": ""})
        self.assertNotIn("va", out["title"])

    def test_check_sees_what_was_written(self):
        self.call("create_unit", path="pruebas/comprobada",
                  title="Comprobada", text="Texto.")
        out = self.call("check")["repositories"][0]
        self.assertTrue(out["ok"], out)


class Refusals(Harness):
    """Lo que no se puede hacer. La mitad que importa."""

    def test_a_read_only_repository_refuses_every_write(self):
        self.repository.writable = False
        unit = self.call("search_units", limit=1)["units"][0]
        for name, arguments in [
            ("write_unit", {"path": unit["path"], "language": "en", "text": "x"}),
            ("create_unit", {"path": "x/y", "title": "t", "text": "x"}),
            ("set_unit_metadata", {"path": unit["path"], "tags": []}),
        ]:
            message = self.failing(name, **arguments)
            self.assertIn("solo lectura", message, name)

    def test_nothing_escapes_the_repository_root(self):
        # `../../../.ssh/id_rsa` es una ruta relativa perfectamente válida, y
        # lo que llega aquí es texto de un modelo.
        for path in ("../../../etc/passwd", "../fuera", "a/../../../fuera"):
            self.failing("read_unit", path=path)
            self.failing("write_unit", path=path, language="es", text="x")

    def test_an_absolute_path_is_refused_outright(self):
        message = self.failing("create_unit", path="/etc/didacta",
                               title="t", text="x")
        self.assertIn("relativa", message)

    def test_creating_over_something_that_exists_is_refused(self):
        self.call("create_unit", path="pruebas/una", title="Una", text="x")
        message = self.failing("create_unit", path="pruebas/una",
                               title="Otra", text="y")
        self.assertIn("write_unit", message)

    def test_a_language_the_repository_does_not_use_is_refused(self):
        unit = self.call("search_units", limit=1)["units"][0]
        message = self.failing("write_unit", path=unit["path"],
                               language="fr", text="x")
        self.assertIn("se traduce a", message)

    def test_a_unit_without_a_title_in_any_language_is_refused(self):
        unit = self.call("search_units", limit=1)["units"][0]
        self.failing("set_unit_metadata", path=unit["path"],
                     title={code: "" for code in ("es", "va", "en")})

    def test_there_is_no_tool_that_touches_git(self):
        # La regla que hace esto aceptable: lo escrito queda en disco y quien
        # publica es la persona, mirando el diff. Si algún día alguien añade
        # `commit` o `push`, este test se entera.
        names = " ".join(self.server.tools)
        for forbidden in ("commit", "push", "pull", "publish", "git"):
            self.assertNotIn(forbidden, names)

    def test_the_server_cannot_reach_a_credential(self):
        # No basta con que ninguna herramienta las pida: lo que se comprueba
        # es que **no hay por dónde**. Este módulo solo importa del motor, y
        # el motor no sabe de tokens ni de llaveros. Lo que no está en el
        # proceso no se filtra por una herramienta mal escrita.
        source = open(
            os.path.join(ROOT, "engine", "didacta", "mcp.py"), encoding="utf-8"
        ).read()
        imported = [
            line.strip() for line in source.splitlines()
            if line.startswith("import ") or line.startswith("from ")
        ]
        self.assertTrue(imported)
        for line in imported:
            allowed = (
                line.startswith("from . import")
                or line.startswith("from __future__")
                or line in ("import json", "import os", "import time")
            )
            self.assertTrue(allowed, "importa algo inesperado: %s" % line)

        # Y que no lea el entorno, que es la otra puerta: `GITHUB_TOKEN` está
        # ahí para cualquiera que se moleste en mirar.
        self.assertNotIn("environ", source)
        self.assertNotIn("getenv", source)


class TheJournal(Harness):
    """Que se pueda ver qué está haciendo."""

    def test_every_call_is_recorded_with_how_long_it_took(self):
        self.call("list_courses")
        calls = self.events("call")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["tool"], "list_courses")
        self.assertTrue(calls[0]["ok"])
        self.assertIn("ms", calls[0])

    def test_a_write_is_marked_as_such(self):
        unit = self.call("search_units", limit=1)["units"][0]
        self.call("write_unit", path=unit["path"], language="en", text="x")
        write = [c for c in self.events("call") if c["tool"] == "write_unit"]
        self.assertTrue(write[0]["writes"])

    def test_a_refusal_is_recorded_too(self):
        self.failing("read_unit", path="no/existe")
        calls = self.events("call")
        self.assertFalse(calls[0]["ok"])
        self.assertIn("error", calls[0])

    def test_the_body_of_a_file_does_not_go_into_the_journal(self):
        # Un `write_unit` lleva el `.tex` entero: apuntarlo llenaría la
        # pantalla con el texto de una unidad cada vez que se escribe una.
        unit = self.call("search_units", limit=1)["units"][0]
        self.call("write_unit", path=unit["path"], language="en",
                  text="x" * 5000)
        write = [c for c in self.events("call") if c["tool"] == "write_unit"]
        self.assertLess(len(json.dumps(write[0])), 600)
        self.assertIn("caracteres", write[0]["arguments"]["text"])

    def test_who_connected_is_recorded(self):
        self.ask("initialize", {"clientInfo": {"name": "un-editor"}})
        self.assertEqual(self.events("connected")[0]["client"], "un-editor")


class TwoRepositories(unittest.TestCase):
    """Uno de cada, que es la situación real."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="didacta-mcp-")
        self.mine = os.path.join(self.tmp, "mio")
        self.theirs = os.path.join(self.tmp, "ajeno")
        shutil.copytree(DEMO, self.mine)
        shutil.copytree(DEMO, self.theirs)
        self.server = mcp_mod.Server(mcp_mod.Workspace([
            mcp_mod.Repository(self.mine, writable=True, label="mio"),
            mcp_mod.Repository(self.theirs, writable=False, label="ajeno"),
        ]))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def call(self, name, **arguments):
        out = self.server.handle({
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        })["result"]
        body = out["content"][0]["text"]
        if out.get("isError"):
            raise AssertionError(body)
        try:
            return json.loads(body)
        except ValueError:
            return body

    def failing(self, name, **arguments):
        out = self.server.handle({
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        })["result"]
        self.assertTrue(out.get("isError"), name)
        return out["content"][0]["text"]

    def test_with_two_open_the_repository_has_to_be_named(self):
        message = self.failing("read_course", course="am-iii", year="2025-2026")
        self.assertIn("mio", message)
        self.assertIn("ajeno", message)

    def test_writing_goes_to_the_one_that_was_named(self):
        unit = self.call("search_units", repository="mio", limit=1)["units"][0]
        self.call("write_unit", repository="mio", path=unit["path"],
                  language="en", text="Mine.")
        self.assertTrue(
            os.path.isfile(os.path.join(self.mine, unit["path"], "en.tex")))
        self.assertFalse(
            os.path.isfile(os.path.join(self.theirs, unit["path"], "en.tex")))

    def test_the_read_only_one_is_refused_even_by_name(self):
        unit = self.call("search_units", repository="ajeno", limit=1)["units"][0]
        message = self.failing("write_unit", repository="ajeno",
                               path=unit["path"], language="en", text="x")
        self.assertIn("solo lectura", message)

    def test_searching_says_which_repository_each_unit_is_in(self):
        # Sin esto, un modelo no puede respetar la regla de que un documento
        # y sus unidades vivan en el mismo repositorio.
        found = self.call("search_units", limit=4)["units"]
        for unit in found:
            self.assertIn(unit["repository"], ("mio", "ajeno"))


if __name__ == "__main__":
    unittest.main()
