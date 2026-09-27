"""El servidor MCP por HTTP: quién puede hablarle y cuándo se apaga.

Escucha solo en `127.0.0.1`, pero en la misma máquina está el navegador, y
una página cualquiera puede mandar a `localhost` una petición «simple» sin la
consulta previa de CORS. Estos tests son esa página: sin token, con `Origin`,
con otro `Host` y con `text/plain`, y ninguna de las cuatro tiene que llegar a
una herramienta.
"""

from __future__ import annotations

import http.client
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import mcp as mcp_mod  # noqa: E402

DEMO = os.path.join(ROOT, "examples", "demo-course")
TOKEN = "un-token-de-prueba"


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="didacta-mcp-http-")
        root = os.path.join(self.tmp, "repo")
        shutil.copytree(DEMO, root)
        server = mcp_mod.Server(
            mcp_mod.Workspace([mcp_mod.Repository(root, writable=True)]),
            latex_dir=None,
        )
        ready = threading.Event()
        self.port = None

        def on_ready(port):
            self.port = port
            ready.set()

        from http.server import ThreadingHTTPServer

        self.httpd = ThreadingHTTPServer(
            ("127.0.0.1", 0), mcp_mod.http_handler_class(server, TOKEN))
        on_ready(self.httpd.server_address[1])
        self.thread = threading.Thread(
            target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        ready.wait(5)

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def post(self, headers, body=None):
        body = body if body is not None else json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {},
        })
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.putrequest("POST", "/", skip_host=True)
        for name, value in headers.items():
            connection.putheader(name, value)
        encoded = body.encode("utf-8")
        connection.putheader("Content-Length", str(len(encoded)))
        connection.endheaders()
        connection.send(encoded)
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response.status, data

    def good(self, **extra):
        headers = {
            "Host": "127.0.0.1:%d" % self.port,
            "Content-Type": "application/json",
            "Authorization": "Bearer " + TOKEN,
        }
        headers.update(extra)
        return headers

    def test_con_todo_en_regla_contesta(self):
        status, data = self.post(self.good())
        self.assertEqual(status, 200)
        tools = json.loads(data)["result"]["tools"]
        self.assertTrue(any(tool["name"] == "list_courses" for tool in tools))

    def test_sin_token_no(self):
        headers = self.good()
        del headers["Authorization"]
        self.assertEqual(self.post(headers)[0], 401)

    def test_con_otro_token_no(self):
        self.assertEqual(
            self.post(self.good(Authorization="Bearer otro"))[0], 401)

    def test_una_pagina_web_no(self):
        # Lo que manda un navegador desde otra página: siempre con `Origin`.
        status, _ = self.post(self.good(Origin="https://ejemplo.com"))
        self.assertEqual(status, 403)

    def test_el_cuerpo_de_texto_de_una_peticion_simple_no(self):
        # La petición que se salta la consulta previa de CORS.
        status, _ = self.post(self.good(**{"Content-Type": "text/plain"}))
        self.assertEqual(status, 415)

    def test_otro_host_no(self):
        # El DNS rebinding: un dominio ajeno que acaba resolviendo aquí.
        status, _ = self.post(self.good(Host="atacante.ejemplo:%d" % self.port))
        self.assertEqual(status, 403)

    def test_localhost_tambien_vale(self):
        status, _ = self.post(self.good(Host="localhost:%d" % self.port))
        self.assertEqual(status, 200)

    def test_la_salud_tambien_pide_token(self):
        # Dice las rutas de los repositorios: tampoco es para cualquiera.
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request("GET", "/health")
        self.assertEqual(connection.getresponse().status, 401)
        connection.close()


class LifecycleTests(unittest.TestCase):
    """El proceso de verdad, como lo lanza la aplicación."""

    def test_dice_su_token_y_muere_con_quien_lo_lanzo(self):
        tmp = tempfile.mkdtemp(prefix="didacta-mcp-life-")
        try:
            root = os.path.join(tmp, "repo")
            shutil.copytree(DEMO, root)
            env = dict(os.environ, DIDACTA_MCP_TOKEN="el-de-la-aplicacion")
            process = subprocess.Popen(
                [sys.executable, os.path.join(ROOT, "cli", "didacta"),
                 "mcp", "--http", "--port", "0", "--no-build",
                 "--exit-with-stdin", "--repo", root],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, env=env,
            )
            hello = json.loads(process.stdout.readline())
            self.assertEqual(hello["token"], "el-de-la-aplicacion")
            self.assertTrue(hello["url"].startswith("http://127.0.0.1:"))

            # Cerrar su entrada estándar es lo que pasa cuando la
            # aplicación se muere: el servidor tiene que irse detrás.
            process.stdin.close()
            deadline = time.time() + 10
            while process.poll() is None and time.time() < deadline:
                time.sleep(0.1)
            if process.poll() is None:
                process.kill()
                self.fail("el servidor sobrevivió a quien lo lanzó")
            self.assertEqual(process.returncode, 0)
            process.stdout.close()
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
