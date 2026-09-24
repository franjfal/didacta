#!/usr/bin/env python3
"""Publicar una versión de Didacta desde el terminal, preguntando.

    python3 packaging/publish.py

Pregunta si la versión es grande, mediana o pequeña, y si se publica de
verdad o se ensaya. Deja la respuesta en `release.yaml`, le pone el número a
la sección del CHANGELOG, hace el commit, lo sube y lanza «Publish Didacta
Release» en GitHub. Lo que compila y publica sigue siendo el workflow: esto
sólo lo prepara y pulsa el botón.

**Por qué existe, si el botón ya estaba.** Publicar eran tres pasos que había
que hacer en orden y sin equivocarse, y los tres fallaban en silencio o tarde:

* titular la sección del CHANGELOG con un número que todavía no existe;
* acordarse de que lo que se compila es **lo que hay en GitHub**, no lo que
  hay en el disco: un cambio sin commit, o un commit sin subir, no va en la
  versión, y nada lo avisaba;
* y pulsar el botón en la rama que es, sin otra publicación en marcha.

Así que antes de tocar nada lo mira todo, lo dice, y pide un «sí» con el plan
delante. Si algo impide publicar, para sin haber escrito nada.

`--part`, `--dry-run` y `--yes` lo dejan contestado de antemano, para
llamarlo desde otro sitio. `--yes` contesta que sí a las preguntas, pero no se
salta ninguna comprobación: lo que impide publicar lo sigue impidiendo.

Sin dependencias y con Python 3.9, como `release.py`. Para lanzar el workflow
usa `gh`, la herramienta de GitHub; sin ella hace todo lo demás y abre la
página del botón.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import webbrowser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import release  # noqa: E402
from release import Problem  # noqa: E402

#: El fichero del workflow, como lo nombra `gh workflow run`.
WORKFLOW = "release.yml"
WORKFLOW_NAME = "Publish Didacta Release"

#: Lo que este programa escribe, y por tanto lo único que mete en su commit.
OWN_FILES = ("release.yaml", "CHANGELOG.md")


class Stop(Exception):
    """Parar sin publicar nada. Se imprime y se sale con 1."""


# ------------------------------------------------------------- preguntar ---


class Asker:
    """Las preguntas, con lo que valga contestar sin preguntar.

    Aparte para que una sola cosa decida si hay alguien delante: sin
    terminal y sin `--yes`, preguntar sería quedarse esperando para siempre.
    [reader] es quien contesta; las pruebas pasan el suyo.
    """

    def __init__(self, yes=False, reader=None):
        self.yes = yes
        self.reader = reader

    def _input(self, prompt):
        if self.yes:
            return ""
        reader = self.reader
        if reader is None:
            if not sys.stdin.isatty():
                raise Stop(
                    "Esto pregunta, y aquí no hay nadie para contestar.\n"
                    "Sin terminal, di lo que haga falta de antemano:\n\n"
                    "    python3 packaging/publish.py --part minor --yes"
                )
            reader = input
        try:
            return reader(prompt).strip()
        except EOFError:
            raise Stop("Sin respuesta: no he tocado nada.")

    def confirm(self, question, default=False):
        """Sí o no. Con `--yes`, sí."""
        if self.yes:
            print("%s sí" % question)
            return True
        hint = "[S/n]" if default else "[s/N]"
        while True:
            answer = self._input("%s %s " % (question, hint)).lower()
            if not answer:
                return default
            if answer in ("s", "si", "sí", "y", "yes"):
                return True
            if answer in ("n", "no"):
                return False
            print("  Contesta s o n.")

    def choose(self, question, options, default, why="por defecto"):
        """Una de [options], una lista de `(clave, texto)`. Devuelve la clave.

        [why] es lo que se dice al lado de la que sale con Enter.
        """
        print(question)
        keys = [key for key, _ in options]
        for number, (key, text) in enumerate(options, 1):
            mark = "   ← %s" % why if key == default else ""
            print("  %d) %s%s" % (number, text, mark))
        if self.yes:
            print("  → %s" % default)
            return default
        while True:
            answer = self._input(
                "Elige [%d]: " % (keys.index(default) + 1)).lower()
            if not answer:
                return default
            if answer.isdigit() and 1 <= int(answer) <= len(keys):
                return keys[int(answer) - 1]
            try:
                part = release.canonical_part(answer)
                if part in keys:
                    return part
            except Problem:
                pass
            print("  Un número del 1 al %d." % len(keys))


# ------------------------------------------------------------------ git ---


def _run(command, check=True, quiet=True, raw=False):
    """Ejecuta [command] en la raíz del repositorio y devuelve su salida.

    Recortada, salvo con [raw]: en la de `git status` el primer espacio es
    parte del estado, y recortarlo convierte « M CHANGELOG.md» en otra ruta.
    """
    result = subprocess.run(
        command,
        cwd=release.ROOT,
        stdout=subprocess.PIPE if quiet else None,
        stderr=subprocess.PIPE if quiet else None,
        universal_newlines=True,
        encoding="utf-8",
        env=_quiet_git(),
    )
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip() if quiet else ""
        raise Stop(
            "Falló `%s`%s" % (" ".join(command), (":\n\n" + detail) if detail else ".")
        )
    if not quiet:
        return ""
    return (result.stdout or "") if raw else (result.stdout or "").strip()


def _quiet_git():
    """El entorno, con git sin permiso para preguntar usuario y contraseña.

    Sin credenciales, git pregunta «Username for 'https://github.com':» y se
    queda ahí, con la salida capturada y nadie viéndolo: desde fuera es un
    programa colgado. Así falla, y el fallo se puede explicar. Se calcula en
    cada llamada y no al importar, para que valga el PATH de ese momento.
    """
    return dict(os.environ, GIT_TERMINAL_PROMPT="0")


def _git(*arguments, check=True):
    return _run(["git"] + list(arguments), check=check)


def _can_push(branch):
    """Si GitHub va a aceptar un `git push` desde aquí, y si no, por qué.

    Un `push --dry-run` habla con GitHub y se autentica como el de verdad,
    pero no sube nada. Se hace al principio porque descubrirlo en el último
    paso es haberlo preguntado todo para nada.
    """
    result = subprocess.run(
        ["git", "push", "--dry-run", "--quiet", "origin", "HEAD:%s" % branch],
        cwd=release.ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        encoding="utf-8",
        env=_quiet_git(),
    )
    return result.returncode == 0, (result.stderr or result.stdout or "").strip()


def _cannot_push(detail, github):
    """El mensaje para cuando GitHub no deja subir, con lo que lo arregla."""
    fix = (
        "    gh auth refresh -h github.com -s workflow\n"
        "    gh auth setup-git\n\n"
        "La primera da permiso a gh para subir cambios en .github/workflows/;\n"
        "la segunda le dice a git que use la sesión de gh con GitHub."
        if github.ready else
        "    brew install gh && gh auth login -s workflow\n"
        "    gh auth setup-git"
    )
    return (
        "GitHub no me deja subir nada desde aquí:\n\n    %s\n\n"
        "No he tocado nada. Para arreglarlo, en un terminal:\n\n%s"
        % (detail.replace("\n", "\n    ") or "(sin detalle)", fix)
    )


def _succeeds(command):
    return subprocess.run(
        command,
        cwd=release.ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def _github_repo():
    """`dueño/repositorio` del remoto `origin`, si es de GitHub.

    La URL tal como está configurada, y no la de `git remote get-url`, que
    aplica los `insteadOf`: lo que dice qué repositorio es, es lo escrito.
    """
    url = _git("config", "--get", "remote.origin.url", check=False)
    match = re.search(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$", url)
    return "%s/%s" % match.groups() if match else None


def _dirty():
    """Lo que hay sin commit, como `(estado, ruta)`.

    Con `-z`: las rutas salen tal cual, sin comillas ni escapes, y un
    renombrado trae la ruta de antes en la entrada siguiente.
    """
    entries = _run(
        ["git", "status", "--porcelain", "-z", "--untracked-files=all"],
        raw=True).split("\0")
    changes = []
    skip = False
    for entry in entries:
        if skip:
            skip = False
            continue
        if len(entry) < 4:
            continue
        state, path = entry[:2], entry[3:]
        skip = state[0] in "RC"
        changes.append((state, path))
    return changes


def _noise(path):
    # Lo que el Finder deja en cada carpeta que abre. Avisar de él enterraría
    # el aviso que importa debajo de diez que no.
    return os.path.basename(path) == ".DS_Store"


# ------------------------------------------------------------------- gh ---


class GitHub:
    """Lo que se le pide a GitHub, a través de `gh`."""

    def __init__(self, repo):
        self.repo = repo
        self.path = shutil.which("gh")
        self.ready = bool(self.path) and _succeeds(["gh", "auth", "status"])

    def _gh(self, *arguments, check=True):
        return _run(["gh"] + list(arguments) + ["-R", self.repo], check=check)

    def release_exists(self, tag):
        # También los borradores: una publicación que se rompió a medias deja
        # uno, y encima de él no se puede publicar otra con el mismo número.
        return _succeeds(["gh", "release", "view", tag, "-R", self.repo])

    def runs(self, status):
        text = self._gh(
            "run", "list", "--workflow", WORKFLOW, "--status", status,
            "--json", "databaseId,url,headBranch", check=False)
        try:
            return json.loads(text or "[]")
        except ValueError:
            return []

    def launch(self, branch, dry_run):
        self._gh(
            "workflow", "run", WORKFLOW, "--ref", branch,
            "-f", "dry_run=%s" % ("true" if dry_run else "false"))

    def dispatched(self):
        """Las últimas ejecuciones lanzadas a mano, de la más nueva a la más
        vieja."""
        text = self._gh(
            "run", "list", "--workflow", WORKFLOW,
            "--event", "workflow_dispatch", "--limit", "20",
            "--json", "databaseId,url,headSha", check=False)
        try:
            return json.loads(text or "[]")
        except ValueError:
            return []

    def find_run(self, sha, known, wait=45, pause=3):
        """La ejecución que se acaba de lanzar.

        `gh workflow run` no dice qué ejecución ha creado --GitHub no lo
        devuelve--, así que se busca: la de este workflow, sobre este commit,
        que no estaba en [known] antes de lanzarla. Por los identificadores y
        no por la hora, que depende de que el reloj de aquí y el de GitHub
        digan lo mismo. Tarda unos segundos en aparecer.
        """
        deadline = time.time() + wait
        while True:
            for run in self.dispatched():
                if run.get("headSha") == sha and run.get("databaseId") not in known:
                    return run
            if time.time() >= deadline:
                return None
            time.sleep(pause)

    def watch(self, run_id):
        return subprocess.run(
            ["gh", "run", "watch", str(run_id), "--exit-status", "-R", self.repo],
            cwd=release.ROOT,
        ).returncode


# ---------------------------------------------------------------- publicar ---


def _say(text=""):
    print(text)


def _title(text):
    _say()
    _say(text)
    _say("─" * len(text))


def publish(args, reader=None):
    ask = Asker(yes=args.yes, reader=reader)
    _say("Didacta · publicar una versión")

    # ---- dónde estamos ----------------------------------------------------
    if not shutil.which("git"):
        raise Stop("Hace falta git, y no está.")
    if not _succeeds(["git", "rev-parse", "--git-dir"]):
        raise Stop("%s no es un repositorio de git." % release.ROOT)
    git_dir = _git("rev-parse", "--git-dir")
    for busy in ("MERGE_HEAD", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD"):
        if os.path.exists(os.path.join(release.ROOT, git_dir, busy)):
            raise Stop(
                "Hay una mezcla o un rebase a medias. Termínalo antes de publicar.")

    branch = _git("rev-parse", "--abbrev-ref", "HEAD")
    if branch == "HEAD":
        raise Stop("No estás en ninguna rama (HEAD suelto). Cámbiate a main.")
    upstream = _git("rev-parse", "--abbrev-ref", "@{u}", check=False)
    if not upstream or not upstream.startswith("origin/"):
        raise Stop(
            "La rama %s no sigue a ninguna de GitHub, así que no hay a dónde "
            "subir el commit." % branch)
    repo = _github_repo()
    if not repo:
        raise Stop("El remoto origin no es un repositorio de GitHub.")

    default = _git("symbolic-ref", "--short", "refs/remotes/origin/HEAD",
                   check=False).replace("origin/", "") or "main"
    if branch != default:
        _say()
        _say("Estás en %s, no en %s. Se publicaría lo que hay en %s." %
             (branch, default, branch))
        if not ask.confirm("¿Publicar desde %s?" % branch, default=False):
            raise Stop("No he tocado nada.")

    _say()
    _say("Mirando GitHub…")
    _git("fetch", "--quiet", "origin")
    behind = int(_git("rev-list", "--count", "HEAD..@{u}"))
    ahead = int(_git("rev-list", "--count", "@{u}..HEAD"))
    if behind and ahead:
        raise Stop(
            "Tu %s y la de GitHub se han separado (%d tuyos, %d suyos).\n"
            "Ponte al día y vuelve:\n\n    git pull --rebase" %
            (branch, ahead, behind))
    if behind:
        # Lo normal después de cada publicación: el workflow deja un commit
        # con la versión nueva, y aquí todavía no está.
        _say("GitHub tiene %d commit%s que aquí no está%s (el último: «%s»)." % (
            behind, "s" if behind > 1 else "", "n" if behind > 1 else "",
            _git("log", "-1", "--format=%s", "@{u}")))
        if not ask.confirm("¿Lo traigo? (git pull --ff-only)", default=True):
            raise Stop(
                "Sin traerlo no se puede: el número se calcula sobre lo último "
                "publicado.")
        _git("pull", "--ff-only", "--quiet")

    github = GitHub(repo)
    pushable, detail = _can_push(branch)
    if not pushable:
        raise Stop(_cannot_push(detail, github))

    # ---- la versión -------------------------------------------------------
    published, build = release.read_version()
    planned = release.planned_part()
    _title("La versión")
    _say("Última publicada:  %s (build %d)" % (published, build))

    if release.SEMVER.match(published).group(4):
        part = planned
        _say("Es una preliberación: sale como su final, %s." %
             release.next_version(published, part))
    elif args.part:
        part = release.canonical_part(args.part)
    else:
        _say()
        part = ask.choose(
            "¿Cómo es esta versión?",
            [
                ("patch", "pequeña   %s → %-8s sólo arreglos" %
                 (published, release.next_version(published, "patch"))),
                ("minor", "mediana   %s → %-8s lo de siempre: lo hecho desde la anterior" %
                 (published, release.next_version(published, "minor"))),
                ("major", "grande    %s → %-8s algo que obliga a aprender otra vez" %
                 (published, release.next_version(published, "major"))),
            ],
            default=planned,
            why="la de release.yaml",
        )
    version = release.next_version(published, part)
    tag = "v%s" % version

    # Un número publicado no se vuelve a publicar: sería una 0.2.0 distinta de
    # la 0.2.0 de al lado. Por el tag de git, que no necesita `gh`, y por el
    # release, que además ve los borradores.
    if _git("ls-remote", "--tags", "origin", "refs/tags/%s" % tag):
        raise Stop("%s ya está publicada (el tag %s existe en GitHub)." %
                   (version, tag))
    if github.ready and github.release_exists(tag):
        raise Stop(
            "Ya hay un release %s en GitHub, puede que en borrador. Bórralo o "
            "elige otro tamaño." % tag)

    # ---- las notas --------------------------------------------------------
    _title("Las notas (CHANGELOG.md)")
    retitle = None
    try:
        notes = release.read_notes(version)
    except Problem:
        pending = release.pending_section(published)
        if pending is None:
            raise Stop(
                "El CHANGELOG no tiene nada sin publicar. Escribe arriba del\n"
                "todo lo que trae esta versión y vuelve a ejecutar esto:\n\n"
                "    ## %s\n\n    - Lo que cambia…\n\n"
                "(Si no sabes el número, `## Próxima` también vale: se lo pongo "
                "yo.)" % version)
        index, label = pending
        _say("La sección de arriba es «%s» y esta versión es %s." % (label, version))
        if not ask.confirm("¿Le pongo el número %s?" % version, default=True):
            raise Stop("Sin sección para %s no se puede publicar." % version)
        retitle = (index, label)
        # Se leen como quedarán, sin escribir nada todavía: una sección vacía
        # tiene que parar aquí y no después del commit.
        lines = release._changelog_lines()
        lines[index] = "## %s" % version
        notes = release.notes_in(lines, version)
    shown = notes.split("\n")
    for line in shown[:14]:
        _say("  " + line)
    if len(shown) > 14:
        _say("  … (%d líneas más)" % (len(shown) - 14))

    # ---- publicar o ensayar -----------------------------------------------
    if args.dry_run:
        dry_run = True
    else:
        _say()
        dry_run = ask.choose(
            "¿Qué hago?",
            [
                ("publish", "publicar %s" % version),
                ("dry", "ensayo: compila y prueba los tres sistemas, no publica "
                        "nada ni gasta el número"),
            ],
            default="publish",
        ) == "dry"

    # ---- lo que no va a ir --------------------------------------------------
    others = [(state, path) for state, path in _dirty()
              if path not in OWN_FILES and not _noise(path)]
    if others:
        _title("Cuidado: esto NO va en la versión")
        _say("Se compila lo que hay en GitHub, y estos cambios no están:")
        for state, path in others[:15]:
            _say("  %s %s" % (state, path))
        if len(others) > 15:
            _say("  … y %d más" % (len(others) - 15))
        if not ask.confirm("¿Seguir sin ellos?", default=False):
            raise Stop(
                "No he tocado nada. Haz commit de lo que tenga que ir y vuelve.")

    unpushed = _git("log", "--format=  %h %s", "@{u}..HEAD").splitlines()

    busy = []
    if github.ready:
        busy = github.runs("in_progress") + github.runs("queued")
    if busy:
        _title("Ya hay una publicación en marcha")
        for run in busy:
            _say("  %s" % run.get("url", ""))
        _say("La nueva esperaría a que acabe, y calcularía su número sobre lo\n"
             "de antes de que esa escriba el suyo.")
        if not ask.confirm("¿Lanzarla igualmente?", default=False):
            raise Stop("No he tocado nada.")

    # ---- el plan ----------------------------------------------------------
    changes_plan = part != planned or not os.path.exists(release.PLAN)
    changelog_dirty = any(path == "CHANGELOG.md" for _, path in _dirty())

    _title("Voy a")
    _say("Versión: %s → %s (%s)%s" % (
        published, version, release.PARTS[part],
        " · ENSAYO: no se publica nada" if dry_run else ""))
    _say()
    step = 0

    def item(text):
        nonlocal step
        step += 1
        _say("  %d. %s" % (step, text))

    if changes_plan:
        item("release.yaml: bump: %s" % part)
    if retitle:
        item("CHANGELOG.md: «%s» pasa a «%s»" % (retitle[1], version))
    if changes_plan or retitle or changelog_dirty:
        item("commit «Preparar Didacta %s» con %s" % (
            version, " y ".join(OWN_FILES)))
    if unpushed:
        item("subir a GitHub también %d commit%s tuyo%s que no estaba%s:" % (
            len(unpushed), "s" if len(unpushed) > 1 else "",
            "s" if len(unpushed) > 1 else "", "n" if len(unpushed) > 1 else ""))
        for line in unpushed[:10]:
            _say("     " + line.strip())
    item("git push origin %s" % branch)
    if github.ready:
        item("lanzar «%s» en GitHub%s" % (
            WORKFLOW_NAME, " en modo ensayo" if dry_run else ""))
    else:
        item("abrirte la página del workflow para que pulses el botón "
             "(no tengo gh: %s)" % (
                 "no está instalado" if not github.path else "sin sesión"))
    _say()
    if dry_run:
        _say("El commit se sube igual: release.yaml y las notas son el plan de")
        _say("la próxima publicación, que saldrá con este mismo número.")
    else:
        _say("Al acabar, el workflow escribe %s en app/pubspec.yaml y vuelve a" %
             version)
        _say("dejar release.yaml en minor. Eso no hay que hacerlo a mano.")
    _say()
    if not ask.confirm("¿Sigo?", default=False):
        raise Stop("No he tocado nada.")

    # ---- hacerlo ----------------------------------------------------------
    _say()
    if changes_plan:
        release.write_plan("bump", part)
    if retitle:
        release.retitle_section(retitle[0], version)
    touched = [path for _, path in _dirty() if path in OWN_FILES]
    if touched:
        _git("add", "--", *touched)
        _git("commit", "--quiet", "-m", "Preparar Didacta %s" % version,
             "--", *touched)
        _say("· commit «Preparar Didacta %s»" % version)
    try:
        _run(["git", "push", "--quiet", "origin", "HEAD:%s" % branch])
    except Stop as failed:
        # Pasó la prueba del principio y aun así no entra. Lo típico: el
        # commit toca .github/workflows/ y el token no tiene `workflow`,
        # algo que GitHub sólo comprueba al subir de verdad.
        raise Stop(
            "%s\n\nEl commit se ha quedado aquí, sin subir: arreglado lo de "
            "arriba, vuelve a ejecutar esto y lo sube.\n\n%s"
            % (failed, _cannot_push("", github).split("\n\n", 2)[2]))
    sha = _git("rev-parse", "HEAD")
    _say("· subido a %s (%s)" % (branch, sha[:7]))

    page = "https://github.com/%s/actions/workflows/%s" % (repo, WORKFLOW)
    if not github.ready:
        _title("Falta pulsar el botón")
        _say("  %s" % page)
        _say("  «Run workflow» → rama %s → Ensayo: %s" % (
            branch, "marcado" if dry_run else "sin marcar"))
        _say()
        _say("Para que la próxima vez lo pulse yo: brew install gh && gh auth login")
        try:
            webbrowser.open(page)
        except Exception:  # noqa: BLE001
            pass
        return 0

    known = {run.get("databaseId") for run in github.dispatched()}
    github.launch(branch, dry_run)
    _say("· lanzado «%s»%s" % (WORKFLOW_NAME, " (ensayo)" if dry_run else ""))
    run = github.find_run(sha, known)
    if run is None:
        _say()
        _say("Está lanzado, pero no encuentro todavía su ejecución. Mírala aquí:")
        _say("  %s" % page)
        return 0
    _say()
    _say("  %s" % run["url"])
    if args.no_watch or not ask.confirm("¿Lo sigo desde aquí?", default=True):
        return 0
    code = github.watch(run["databaseId"])
    _say()
    if code == 0:
        _say("%s de %s: hecho." % ("Ensayo" if dry_run else "Publicación", version))
        if not dry_run:
            _say("Trae el commit de la versión antes de seguir: git pull")
    else:
        _say("El workflow ha fallado. Lo que pasó está en %s" % run["url"])
        _say("No se ha gastado el número: arréglalo y vuelve a ejecutar esto.")
    return code


def main(argv=None, reader=None):
    release._utf8_output()
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--part", metavar="PARTE",
        help="major, minor o patch (o grande, mediana, pequeña); sin él, pregunta")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="ensayo: compila y prueba, pero no publica")
    parser.add_argument(
        "--yes", action="store_true",
        help="contestar que sí a todo; las comprobaciones siguen parando")
    parser.add_argument(
        "--no-watch", action="store_true",
        help="no quedarse siguiendo el workflow")
    args = parser.parse_args(argv)
    try:
        return publish(args, reader=reader)
    except (Stop, Problem) as problem:
        sys.stderr.write("\n%s\n" % problem)
        return 1
    except KeyboardInterrupt:
        sys.stderr.write("\nInterrumpido.\n")
        return 130


if __name__ == "__main__":
    sys.exit(main())
