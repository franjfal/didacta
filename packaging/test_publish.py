#!/usr/bin/env python3
"""Los tests de `publish.py`, contra git de verdad y un GitHub de mentira.

git de verdad porque lo que se prueba es sobre todo git: qué entra en el
commit, qué se sube y qué se queda en el disco. Un git simulado probaría que
el programa es coherente consigo mismo y nada sobre si el commit que llega a
GitHub es el que se dijo.

GitHub, en cambio, de mentira: `origin` es un repositorio desnudo en una
carpeta temporal, y `gh` es un programa que apunta lo que se le pide y
contesta lo que el test le diga. Lanzar el workflow de verdad sería publicar.

    python3 -m unittest discover -s packaging -p 'test_*.py' -v
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import publish  # noqa: E402
import release  # noqa: E402

#: El `gh` de mentira. Apunta cada llamada y contesta desde un JSON.
FAKE_GH = r'''#!/usr/bin/env python3
import json, os, subprocess, sys

state = os.environ["FAKE_GH_STATE"]
args = sys.argv[1:]
with open(state + ".log", "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
with open(state, encoding="utf-8") as handle:
    data = json.load(handle)

def save():
    with open(state, "w", encoding="utf-8") as handle:
        json.dump(data, handle)

if args[:2] == ["auth", "status"]:
    sys.exit(0 if data.get("authed", True) else 1)
if args[:2] == ["release", "view"]:
    sys.exit(0 if args[2] in data.get("releases", []) else 1)
if args[:2] == ["workflow", "run"]:
    sha = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], universal_newlines=True).strip()
    number = 100 + len(data["runs"])
    data["runs"].insert(0, {
        "databaseId": number,
        "url": "https://github.com/test/didacta/actions/runs/%d" % number,
        "headSha": sha,
    })
    save()
    sys.exit(0)
if args[:2] == ["run", "list"]:
    if "--status" in args:
        status = args[args.index("--status") + 1]
        print(json.dumps([r for r in data.get("busy", []) if r["status"] == status]))
    else:
        print(json.dumps(data["runs"]))
    sys.exit(0)
if args[:2] == ["run", "watch"]:
    sys.exit(data.get("watch", 0))
sys.exit(2)
'''

CHANGELOG = """# Cambios

Lo que cambia en cada versión.

```markdown
## 1.4.2 — 2026-09-15

- Lo nuevo…
```

---

## Próxima

- Clonar dice por dónde va.

## 0.1.0 — 2026-09-17

- Lo primero.
"""


def git(cwd, *arguments):
    return subprocess.run(
        ["git"] + list(arguments),
        cwd=cwd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    ).stdout.strip()


@unittest.skipIf(os.name == "nt", "el gh de mentira es un guion con #!")
class PublishTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.mkdtemp()
        self.origin = os.path.join(self.temp, "origin.git")
        self.clone = os.path.join(self.temp, "clone")
        seed = os.path.join(self.temp, "seed")

        git(self.temp, "init", "--quiet", "--bare", "--initial-branch=main",
            self.origin)
        os.makedirs(os.path.join(seed, "app"))
        self._write(seed, "app/pubspec.yaml",
                    "name: didacta_app\nversion: 0.1.0+5\n")
        self._write(seed, "CHANGELOG.md", CHANGELOG)
        self._write(seed, "release.yaml", release.PLAN_TEMPLATE)
        self._write(seed, "README.md", "Didacta\n")
        git(self.temp, "init", "--quiet", "--initial-branch=main", seed)
        self._identity(seed)
        git(seed, "add", ".")
        git(seed, "commit", "--quiet", "-m", "Didacta 0.1.0")
        git(seed, "remote", "add", "origin", self.origin)
        git(seed, "push", "--quiet", "-u", "origin", "main")
        git(self.origin, "symbolic-ref", "HEAD", "refs/heads/main")

        git(self.temp, "clone", "--quiet", self.origin, self.clone)
        self._identity(self.clone)
        # Que parezca GitHub: la URL escrita es la de GitHub, y git la
        # cambia por la carpeta al hablar con ella.
        github = "https://github.com/test/didacta.git"
        git(self.clone, "config", "remote.origin.url", github)
        git(self.clone, "config", "url.%s.insteadOf" % self.origin, github)

        self.originals = (release.ROOT, release.PUBSPEC, release.CHANGELOG,
                          release.PLAN)
        release.ROOT = self.clone
        release.PUBSPEC = os.path.join(self.clone, "app", "pubspec.yaml")
        release.CHANGELOG = os.path.join(self.clone, "CHANGELOG.md")
        release.PLAN = os.path.join(self.clone, "release.yaml")

        bin_dir = os.path.join(self.temp, "bin")
        os.makedirs(bin_dir)
        gh = os.path.join(bin_dir, "gh")
        with open(gh, "w", encoding="utf-8") as handle:
            handle.write(FAKE_GH)
        os.chmod(gh, 0o755)
        self.state = os.path.join(self.temp, "gh.json")
        self.github({"runs": []})
        self.environment = dict(os.environ)
        os.environ["PATH"] = bin_dir + os.pathsep + os.environ["PATH"]
        os.environ["FAKE_GH_STATE"] = self.state

        self.opened = []
        self.saved_open = publish.webbrowser.open
        publish.webbrowser.open = self.opened.append

    def tearDown(self):
        (release.ROOT, release.PUBSPEC, release.CHANGELOG,
         release.PLAN) = self.originals
        os.environ.clear()
        os.environ.update(self.environment)
        publish.webbrowser.open = self.saved_open
        shutil.rmtree(self.temp, ignore_errors=True)

    # ------------------------------------------------------------ ayudas ---

    def _write(self, root, path, text):
        with open(os.path.join(root, path), "w", encoding="utf-8") as handle:
            handle.write(text)

    def _identity(self, repo):
        git(repo, "config", "user.name", "Alguien")
        git(repo, "config", "user.email", "alguien@example.com")

    def github(self, data):
        with open(self.state, "w", encoding="utf-8") as handle:
            json.dump(data, handle)

    def calls(self):
        path = self.state + ".log"
        if not os.path.exists(path):
            return []
        with open(path, encoding="utf-8") as handle:
            return handle.read().splitlines()

    def launched(self):
        return [call for call in self.calls() if call.startswith("workflow run")]

    def run_it(self, answers, *argv):
        """Ejecuta `publish.py` contestando [answers] en orden.

        Una pregunta de más es un fallo: quiere decir que el programa pregunta
        algo que el test no esperaba, que es justo lo que hay que ver.
        """
        pending = list(answers)
        self.asked = []

        def reader(prompt):
            self.asked.append(prompt)
            if not pending:
                raise AssertionError("pregunta de más: %r" % prompt)
            return pending.pop(0)

        out, err = io.StringIO(), io.StringIO()
        saved = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = out, err
        try:
            code = publish.main(list(argv), reader=reader)
        finally:
            sys.stdout, sys.stderr = saved
        self.output = out.getvalue() + err.getvalue()
        self.assertEqual(pending, [], "sobraron respuestas:\n" + self.output)
        return code

    def on_github(self, path):
        return git(self.origin, "show", "main:%s" % path)

    def head_on_github(self):
        return git(self.origin, "log", "-1", "--format=%s", "main")

    # ------------------------------------------------------------- casos ---

    def test_una_pequena_de_principio_a_fin(self):
        code = self.run_it(
            ["1",   # pequeña
             "s",   # ponerle el número a «Próxima»
             "",    # publicar (lo de por defecto)
             "s"],  # sigo
            "--no-watch")
        self.assertEqual(code, 0, self.output)

        # Lo que llega a GitHub es el plan y las notas, con su número.
        self.assertEqual(self.head_on_github(), "Preparar Didacta 0.1.1")
        self.assertIn("bump: patch", self.on_github("release.yaml"))
        changelog = self.on_github("CHANGELOG.md")
        self.assertRegex(changelog, r"## 0\.1\.1 — \d{4}-\d{2}-\d{2}\n\n- Clonar")
        # El ejemplo del principio sigue siendo un ejemplo.
        self.assertIn("## 1.4.2 — 2026-09-15", changelog)
        # Y el número no lo escribe esto: lo escribe el workflow al publicar.
        self.assertIn("version: 0.1.0+5", self.on_github("app/pubspec.yaml"))

        self.assertEqual(
            self.launched(),
            ["workflow run release.yml --ref main -f dry_run=false "
             "-R test/didacta"])
        self.assertIn("actions/runs/100", self.output)

    def test_la_de_siempre_con_enter(self):
        code = self.run_it(["", "s", "", "s"], "--no-watch")
        self.assertEqual(code, 0, self.output)
        # release.yaml ya decía minor: no hay nada que cambiar en él.
        self.assertIn("bump: minor", self.on_github("release.yaml"))
        self.assertIn("## 0.2.0 — ", self.on_github("CHANGELOG.md"))

    def test_un_ensayo_se_lanza_como_ensayo(self):
        code = self.run_it([], "--part", "grande", "--dry-run", "--yes",
                           "--no-watch")
        self.assertEqual(code, 0, self.output)
        self.assertIn("bump: major", self.on_github("release.yaml"))
        self.assertIn("## 1.0.0 — ", self.on_github("CHANGELOG.md"))
        self.assertEqual(len(self.launched()), 1)
        self.assertIn("dry_run=true", self.launched()[0])

    def test_decir_que_no_no_toca_nada(self):
        before = git(self.origin, "rev-parse", "main")
        code = self.run_it(["3", "s", "", "n"])
        self.assertEqual(code, 1)
        self.assertEqual(git(self.origin, "rev-parse", "main"), before)
        self.assertEqual(git(self.clone, "status", "--porcelain"), "")
        self.assertEqual(self.launched(), [])

    def test_sin_notas_nuevas_no_se_publica(self):
        # Arriba del todo, la que ya está publicada.
        text = CHANGELOG.replace("## Próxima\n\n- Clonar dice por dónde va.\n\n", "")
        self._write(self.clone, "CHANGELOG.md", text)
        git(self.clone, "commit", "--quiet", "-am", "Sin notas")
        code = self.run_it(["2"])
        self.assertEqual(code, 1)
        self.assertIn("no tiene nada sin publicar", self.output)
        self.assertIn("## 0.2.0", self.output)
        self.assertEqual(self.launched(), [])

    def test_avisa_de_lo_que_no_va_en_la_version(self):
        self._write(self.clone, "README.md", "Didacta, cambiado\n")
        code = self.run_it(["2", "s", "", "n"])
        self.assertEqual(code, 1)
        self.assertIn("NO va en la versión", self.output)
        self.assertIn("README.md", self.output)
        # Ni siquiera se ha escrito el plan.
        self.assertIn("bump: minor", self.on_github("release.yaml"))
        self.assertEqual(
            git(self.clone, "status", "--porcelain"), "M README.md")

    def test_y_si_se_sigue_ese_cambio_se_queda_fuera(self):
        self._write(self.clone, "README.md", "Didacta, cambiado\n")
        code = self.run_it(["2", "s", "", "s", "s"], "--no-watch")
        self.assertEqual(code, 0, self.output)
        self.assertEqual(self.on_github("README.md"), "Didacta")
        self.assertEqual(
            git(self.clone, "status", "--porcelain"), "M README.md")

    def test_trae_primero_el_commit_de_la_ultima_publicacion(self):
        # Lo que pasa siempre: el workflow deja «Didacta 0.2.0» en main, y
        # aquí todavía no está.
        other = os.path.join(self.temp, "otro")
        git(self.temp, "clone", "--quiet", self.origin, other)
        self._identity(other)
        self._write(other, "app/pubspec.yaml",
                    "name: didacta_app\nversion: 0.2.0+6\n")
        self._write(other, "CHANGELOG.md", CHANGELOG.replace(
            "## Próxima\n\n- Clonar dice por dónde va.\n",
            "## Próxima\n\n- Lo siguiente.\n\n"
            "## 0.2.0 — 2026-09-20\n\n- Clonar dice por dónde va.\n"))
        git(other, "commit", "--quiet", "-am", "Didacta 0.2.0")
        git(other, "push", "--quiet", "origin", "main")

        code = self.run_it(["s",   # traerlo
                            "",    # mediana: 0.2.0 → 0.3.0
                            "s",   # ponerle el número
                            "",    # publicar
                            "s"], "--no-watch")
        self.assertEqual(code, 0, self.output)
        self.assertIn("0.2.0 → 0.3.0", self.output)
        self.assertIn("## 0.3.0 — ", self.on_github("CHANGELOG.md"))
        self.assertEqual(len(self.launched()), 1)

    def test_un_numero_ya_publicado_no_se_vuelve_a_publicar(self):
        git(self.clone, "tag", "v0.2.0")
        git(self.clone, "push", "--quiet", "origin", "v0.2.0")
        code = self.run_it(["2"])
        self.assertEqual(code, 1)
        self.assertIn("ya está publicada", self.output)
        self.assertEqual(self.launched(), [])

    def test_ni_encima_de_un_borrador(self):
        self.github({"runs": [], "releases": ["v0.2.0"]})
        code = self.run_it(["2"])
        self.assertEqual(code, 1)
        self.assertIn("borrador", self.output)

    def test_con_otra_publicacion_en_marcha_pregunta(self):
        self.github({"runs": [], "busy": [
            {"status": "in_progress", "url": "https://x/run/7", "databaseId": 7}]})
        code = self.run_it(["2", "s", "", "n"])
        self.assertEqual(code, 1)
        self.assertIn("https://x/run/7", self.output)
        self.assertEqual(self.launched(), [])

    def test_sin_gh_lo_deja_listo_y_abre_el_boton(self):
        which = publish.shutil.which
        publish.shutil.which = lambda name: None if name == "gh" else which(name)
        try:
            code = self.run_it(["2", "s", "", "s"])
        finally:
            publish.shutil.which = which
        self.assertEqual(code, 0, self.output)
        self.assertEqual(self.head_on_github(), "Preparar Didacta 0.2.0")
        self.assertEqual(self.launched(), [])
        self.assertEqual(
            self.opened,
            ["https://github.com/test/didacta/actions/workflows/release.yml"])

    def test_lo_sigue_hasta_el_final(self):
        code = self.run_it(["2", "s", "", "s", ""])  # el último: seguirlo
        self.assertEqual(code, 0, self.output)
        self.assertIn("run watch 100 --exit-status -R test/didacta", self.calls())
        self.assertIn("hecho", self.output)

    def test_si_el_workflow_falla_lo_dice(self):
        self.github({"runs": [], "watch": 1})
        code = self.run_it(["2", "s", "", "s", ""])
        self.assertEqual(code, 1)
        self.assertIn("No se ha gastado el número", self.output)

    def test_una_errata_en_release_yaml_para_antes_de_preguntar_nada(self):
        self._write(self.clone, "release.yaml", "bump: enorme\n")
        code = self.run_it([])
        self.assertEqual(code, 1)
        self.assertIn("release.yaml, línea 1", self.output)

    def test_sin_terminal_y_sin_yes_no_se_queda_esperando(self):
        saved = sys.stdin
        sys.stdin = io.StringIO("")
        out = io.StringIO()
        saved_out = sys.stdout, sys.stderr
        sys.stdout = sys.stderr = out
        try:
            code = publish.main([])
        finally:
            sys.stdin = saved
            sys.stdout, sys.stderr = saved_out
        self.assertEqual(code, 1)
        self.assertIn("--yes", out.getvalue())


if __name__ == "__main__":
    unittest.main()
