#!/usr/bin/env python3
"""Lo que el workflow de publicación necesita saber, en un solo sitio.

Existe para que el YAML del workflow no tenga lógica dentro. Un `grep` con una
expresión regular metido en un paso de GitHub Actions no se puede ejecutar en
la máquina de nadie, no se puede probar, y falla en el peor momento: cuando ya
se han compilado los tres sistemas. Esto sí se puede ejecutar a mano:

    python3 packaging/release.py version
    python3 packaging/release.py next
    python3 packaging/release.py plan
    python3 packaging/release.py check

Sin dependencias y con Python 3.9, igual que el motor, para que se pueda
ejecutar en cualquiera de las tres máquinas del CI sin instalar nada.

Las dos reglas que impone:

**La versión la dice `app/pubspec.yaml` y nadie más.** Ni el workflow, ni un
`input` de la acción, ni un fichero aparte. Todo lo que este programa imprime
sale de leer esa línea.

**Y el número lo sube el ciclo de publicación, no una persona.** Publicar sube
una de las tres partes y el build de uno en uno. La línea de `pubspec.yaml`
deja de ser algo que se edita antes de publicar y pasa a ser el registro de lo
último que se publicó. Lo que había antes era un número escrito a mano justo
antes de pulsar el botón, que es la clase de paso que un día se olvida y
publica la versión de encima de la anterior.

**Qué parte sube lo dice `release.yaml`**, en la raíz: `bump: minor` si nadie
dice otra cosa. No es un número sino cuánto se salta, así que no puede
contradecir a `pubspec.yaml`; y está en un fichero del repositorio y no en un
`input` del workflow para que los cuatro trabajos, que descargan el mismo
commit, lean lo mismo. **Vale para una publicación**: el trabajo que publica
lo vuelve a dejar en `minor` en el mismo commit que escribe la versión, y así
un `major` no se queda puesto para la siguiente.

Quien escribe el CHANGELOG necesita saber el número antes de que exista, y por
eso está `next`: lo calcula sin tocar nada. Y quien no quiera pensar en nada de
esto tiene `publish.py`, que pregunta, comprueba y lo hace.
"""

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBSPEC = os.path.join(ROOT, "app", "pubspec.yaml")
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
PLAN = os.path.join(ROOT, "release.yaml")

# `1.4.2`, con preliberación opcional. Es la misma forma que acepta
# `AppVersion.tryParse` en la aplicación; si una de las dos cambia, la otra
# tiene que cambiar con ella.
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


class Problem(Exception):
    """Algo que impide publicar. Se imprime y se sale con 1."""


# --------------------------------------------------------------- versión ---


def read_version():
    """La versión y el build de `pubspec.yaml`.

    Leído con una expresión regular en vez de con un parser de YAML porque la
    línea es `version: 1.4.2+142` y traer PyYAML al CI de los tres sistemas
    para eso sería pagar una dependencia por una línea.
    """
    if not os.path.exists(PUBSPEC):
        raise Problem("no encuentro app/pubspec.yaml")
    with open(PUBSPEC, encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r"^version:\s*(\S+)\s*$", line)
            if not match:
                continue
            raw = match.group(1)
            if "+" in raw:
                name, _, build = raw.partition("+")
            else:
                name, build = raw, "0"
            if not SEMVER.match(name):
                raise Problem(
                    "la versión de pubspec.yaml no es semántica: %r.\n"
                    "Tiene que ser MAJOR.MINOR.PATCH, por ejemplo 1.4.2+142."
                    % raw
                )
            if not build.isdigit():
                raise Problem("el build de pubspec.yaml no es un número: %r" % build)
            return name, int(build)
    raise Problem("app/pubspec.yaml no tiene una línea `version:`")


def write_version(name, build):
    """Deja `version: <name>+<build>` en pubspec.yaml y no toca nada más.

    Línea a línea en vez de con un parser de YAML por lo mismo que se lee así:
    reescribir el fichero con PyYAML se llevaría por delante los comentarios,
    que en `pubspec.yaml` son la documentación de Flutter sobre qué significa
    cada campo.
    """
    with open(PUBSPEC, encoding="utf-8") as handle:
        lines = handle.readlines()
    for index, line in enumerate(lines):
        if re.match(r"^version:\s*\S+\s*$", line):
            lines[index] = "version: %s+%d\n" % (name, build)
            break
    else:
        raise Problem("app/pubspec.yaml no tiene una línea `version:`")
    with open(PUBSPEC, "w", encoding="utf-8") as handle:
        handle.writelines(lines)


#: Qué sube una publicación si `release.yaml` no dice otra cosa. La mediana:
#: 1.1.0 → 1.2.0.
#:
#: Didacta se reparte a un grupo que la actualiza sola, y lo que cada versión
#: trae es «lo que se haya hecho desde la anterior» -- que es exactamente lo
#: que una mediana significa. Un parche diría que sólo se han arreglado cosas,
#: y eso lo tiene que decir alguien a propósito: por eso es lo que se escribe
#: en `release.yaml`, y no lo que pasa si nadie escribe nada.
DEFAULT_PART = "minor"

#: Las tres partes, y cómo se dicen en castellano.
PARTS = {
    "major": "grande",
    "minor": "mediana",
    "patch": "pequeña",
}

#: Otras formas de decir lo mismo en `release.yaml`.
#:
#: Quien lo edita a mano piensa «esta es pequeña», no «esta es un patch», y un
#: fichero que obliga a traducir es un fichero donde alguien escribe lo que no
#: quería. Lo que se escribe de vuelta es siempre el nombre en inglés.
ALIASES = {
    "grande": "major",
    "mayor": "major",
    "mediana": "minor",
    "media": "minor",
    "pequeña": "patch",
    "pequena": "patch",
    "parche": "patch",
}


def canonical_part(value):
    """`major`, `minor` o `patch`, de cualquiera de sus nombres."""
    word = value.strip().lower()
    word = ALIASES.get(word, word)
    if word not in PARTS:
        raise Problem(
            "%r no es cuánto sube una versión. Es una de estas:\n"
            "    major  (grande)   1.4.2 → 2.0.0\n"
            "    minor  (mediana)  1.4.2 → 1.5.0\n"
            "    patch  (pequeña)  1.4.2 → 1.4.3" % value.strip()
        )
    return word


def next_version(name, part=DEFAULT_PART):
    """La versión que asignará la próxima publicación.

    Función pura y probada aparte porque es la que decide el número que va a
    quedar publicado para siempre: un `sed` dentro del workflow no se puede
    ejecutar en la máquina de nadie ni probar, y se descubriría equivocado
    cuando ya hay un tag con el número que no era.

    Una preliberación es el caso que no tiene respuesta obvia, así que no se
    adivina: `1.5.0-rc.1` publica como **su propia final**, `1.5.0`. Subir la
    mediana ahí daría `1.6.0` y dejaría un `1.5.0` que nunca existió, que es
    justo lo que un número de versión no debe hacer.
    """
    match = SEMVER.match(name)
    if not match:
        raise Problem("no es una versión semántica: %r" % name)
    major, minor, patch = (int(match.group(index)) for index in (1, 2, 3))
    if match.group(4):
        return "%d.%d.%d" % (major, minor, patch)
    if part == "major":
        return "%d.0.0" % (major + 1)
    if part == "minor":
        return "%d.%d.0" % (major, minor + 1)
    if part == "patch":
        return "%d.%d.%d" % (major, minor, patch + 1)
    raise Problem("no sé subir %r: es major, minor o patch" % part)


def bump(part=None):
    """Sube la versión de pubspec.yaml y devuelve `(antes, después, build)`.

    Lo que sube es [part], o lo que diga `release.yaml` si no se dice.

    El build sube siempre de uno en uno, publique lo que publique: es un
    contador monótono --lo que Windows llama el sufijo de build y macOS
    `CFBundleVersion`-- y su único trabajo es no repetirse nunca.
    """
    if part is None:
        part = planned_part()
    name, build = read_version()
    new_name = next_version(name, part)
    new_build = build + 1
    write_version(new_name, new_build)
    return name, new_name, new_build


# ------------------------------------------------------------------ plan ---

#: Lo que se puede decir en `release.yaml`: cómo se lee cada clave y qué vale
#: si no está.
#:
#: Crecer es añadir una línea aquí. Lo que no está aquí es un error y no se
#: ignora: una clave mal escrita --`bumb: major`-- que se ignorase publicaría
#: una mediana creyendo que era una grande, y eso no tiene vuelta atrás.
PLAN_KEYS = {
    "bump": (canonical_part, DEFAULT_PART),
}

#: Lo que se escribe si `release.yaml` no existe.
PLAN_TEMPLATE = """\
# Cómo sale la próxima versión de Didacta.
#
# Lo leen packaging/release.py y el workflow «Publish Didacta Release». Lo
# normal es no tocarlo a mano: `python3 packaging/publish.py` pregunta, lo
# escribe y lanza la publicación.
#
# bump: cuánto sube el número respecto al último publicado (app/pubspec.yaml)
#
#   major   grande    1.4.2 → 2.0.0   algo que obliga a aprender otra vez
#   minor   mediana   1.4.2 → 1.5.0   lo de siempre: lo hecho desde la anterior
#   patch   pequeña   1.4.2 → 1.4.3   sólo arreglos
#
# Vale para UNA publicación: al publicar, el workflow lo vuelve a dejar en
# minor. Así una grande no se queda puesta y la siguiente no salta otra vez.
bump: minor
"""


def _uncommented(raw):
    """La línea sin su comentario. `#` abre uno al principio o tras un blanco,
    como en YAML: `bump: minor  # la de siempre`."""
    return re.sub(r"(^|\s)#.*$", "", raw.rstrip("\r\n"))


def read_plan():
    """Lo que dice `release.yaml`, comprobado, con lo que falte por defecto.

    Leído a mano y no con un parser de YAML por lo mismo que `pubspec.yaml`,
    y además más estricto que YAML: una línea por clave, sin sangrar, sin
    nada anidado. Es un fichero de una línea útil, y todo lo que no sea esa
    forma es alguien que ha escrito algo distinto de lo que creía.
    """
    plan = {key: default for key, (_, default) in PLAN_KEYS.items()}
    if not os.path.exists(PLAN):
        return plan
    seen = set()
    with open(PLAN, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = _uncommented(raw)
            if not line.strip():
                continue
            where = "release.yaml, línea %d" % number
            if line[0].isspace():
                raise Problem("%s: va sin sangrar: %r" % (where, raw.strip()))
            match = re.match(r"^([A-Za-z_][\w-]*)\s*:\s*(.*?)\s*$", line)
            if not match:
                raise Problem(
                    "%s: no se entiende %r.\nCada línea es `clave: valor`, "
                    "por ejemplo `bump: minor`." % (where, raw.strip())
                )
            key, value = match.groups()
            if key not in PLAN_KEYS:
                raise Problem(
                    "%s: no conozco «%s». Lo que se puede poner: %s."
                    % (where, key, ", ".join(sorted(PLAN_KEYS)))
                )
            if key in seen:
                raise Problem("%s: «%s» ya estaba más arriba." % (where, key))
            seen.add(key)
            value = value.strip("\"'").strip()
            if not value:
                raise Problem("%s: «%s» está vacío." % (where, key))
            parse, _ = PLAN_KEYS[key]
            try:
                plan[key] = parse(value)
            except Problem as problem:
                raise Problem("%s: %s" % (where, problem))
    return plan


def planned_part():
    """Lo que sube la próxima publicación, según `release.yaml`."""
    return read_plan()["bump"]


def write_plan(key, value):
    """Deja `key: value` en `release.yaml` y no toca nada más.

    Como `write_version`: los comentarios del fichero son su documentación, y
    reescribirlo entero se los llevaría. Si no existe, se crea con ellos.
    """
    if key not in PLAN_KEYS:
        raise Problem("release.yaml no tiene una clave «%s»" % key)
    if not os.path.exists(PLAN):
        with open(PLAN, "w", encoding="utf-8") as handle:
            handle.write(PLAN_TEMPLATE)
    with open(PLAN, encoding="utf-8") as handle:
        lines = handle.readlines()
    for index, raw in enumerate(lines):
        if re.match(r"^%s\s*:" % re.escape(key), _uncommented(raw)):
            lines[index] = "%s: %s\n" % (key, value)
            break
    else:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append("%s: %s\n" % (key, value))
    with open(PLAN, "w", encoding="utf-8") as handle:
        handle.writelines(lines)
    # Y se vuelve a leer: lo que queda escrito tiene que ser algo que el
    # workflow entienda, y es mejor descubrirlo aquí que allí.
    read_plan()


# ------------------------------------------------------------- changelog ---


def _headings(lines):
    """Los encabezados de versión del CHANGELOG, **fuera de los cercados**.

    El propio CHANGELOG explica su formato con un ejemplo dentro de un bloque
    de código:

        ```markdown
        ## 1.4.2 — 2026-09-15
        - Lo nuevo…
        ```

    Un parser que solo mire si la línea empieza por `## ` se cree ese ejemplo.
    El día que a alguien le tocase publicar la 1.4.2 --y con el número
    subiendo solo, llega-- las notas del release habrían sido «Lo nuevo…, lo
    mejorado…, lo corregido…», publicadas sin que nada fallara.

    Devuelve pares (número de línea, versión).
    """
    found = []
    fenced = False
    for index, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        match = re.match(r"^##\s+v?(\S+)", line)
        if match:
            found.append((index, match.group(1)))
    return found


def _changelog_lines():
    if not os.path.exists(CHANGELOG):
        raise Problem("no encuentro CHANGELOG.md")
    with open(CHANGELOG, encoding="utf-8") as handle:
        return handle.read().split("\n")


def read_notes(version):
    """La sección de [version] del CHANGELOG, sin su encabezado.

    Es lo que se publica como notas del release y lo que la aplicación enseña
    al ofrecer la actualización. Que falte es un error y no un aviso: publicar
    sin decir qué cambia es publicar algo que nadie puede decidir si quiere.
    """
    return notes_in(_changelog_lines(), version)


def notes_in(lines, version):
    """Lo mismo que [read_notes], sobre unas líneas ya leídas.

    Aparte para poder leer las notas de un CHANGELOG **como quedará** --con
    el número puesto a una sección que todavía no lo tiene-- antes de
    escribir nada en el disco.
    """
    headings = _headings(lines)

    # `## 1.4.2` o `## 1.4.2 — 2026-09-15`. La fecha es decorativa.
    start = None
    for index, found in headings:
        if found == version:
            start = index + 1
            break
    if start is None:
        raise Problem(
            "CHANGELOG.md no tiene una sección para %s.\n\n"
            "%s es el número que asigna esta publicación: sube lo que diga\n"
            "release.yaml, y `python3 packaging/release.py next` lo dice antes\n"
            "de lanzarlo. Añade la sección y vuelve a publicar:\n\n"
            "    ## %s — %s\n\n"
            "    - Lo que cambia…\n\n"
            "`python3 packaging/publish.py` hace esto por ti: si la sección de\n"
            "arriba todavía no se ha publicado, le pone el número que toca.\n"
            % (version, version, version, datetime.now().strftime("%Y-%m-%d"))
        )

    end = len(lines)
    for index, _ in headings:
        if index >= start:
            end = index
            break

    notes = "\n".join(lines[start:end]).strip()
    # Sin la raya que separa esta sección de la siguiente. En el CHANGELOG
    # ordena la lectura; en las notas del release --y en el diálogo de
    # actualizar, que enseña lo mismo-- es una raya suelta al final.
    while notes.endswith("---"):
        notes = notes[: -len("---")].rstrip()
    if not notes:
        raise Problem("la sección %s del CHANGELOG está vacía" % version)
    return notes


def version_key(name):
    """Para ordenar versiones: una preliberación va antes que su final."""
    match = SEMVER.match(name)
    if not match:
        raise Problem("no es una versión semántica: %r" % name)
    major, minor, patch = (int(match.group(index)) for index in (1, 2, 3))
    return (major, minor, patch, 0 if match.group(4) else 1)


def pending_section(published):
    """La sección de arriba del CHANGELOG si todavía no se ha publicado.

    Devuelve `(línea, título)`, o None si la de arriba es [published] o una
    anterior. «Sin publicar» es un número mayor que el publicado --escrito con
    el número que iba a salir, antes de decidir otro tamaño-- o un título que
    no es un número, como `## Próxima`: quien escribe las notas no tiene por
    qué saber todavía cuánto va a subir.
    """
    headings = _headings(_changelog_lines())
    if not headings:
        return None
    index, label = headings[0]
    if SEMVER.match(label) and version_key(label) <= version_key(published):
        return None
    return index, label


def retitle_section(index, version, today=None):
    """Le pone a la sección de la línea [index] el número [version]."""
    lines = _changelog_lines()
    if not re.match(r"^##\s", lines[index]):
        raise Problem("la línea %d del CHANGELOG no es un encabezado" % (index + 1))
    lines[index] = "## %s — %s" % (
        version, today or datetime.now().strftime("%Y-%m-%d"))
    with open(CHANGELOG, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


# -------------------------------------------------------------- assets ---

# De qué es cada artefacto, por su nombre. El nombre es el contrato: si se
# cambia aquí hay que cambiarlo en los scripts de empaquetado, y al revés.
KINDS = [
    # (sufijo, plataforma, arquitectura, para qué sirve)
    (".dmg", "macos", "universal", "installer"),
    ("-macos-universal.zip", "macos", "universal", "update"),
    (".exe", "windows", "x64", "installer"),
    (".AppImage", "linux", "x64", "installer"),
]


def classify(name):
    """Plataforma, arquitectura y uso de un artefacto, o None si no es uno."""
    for suffix, platform, architecture, kind in KINDS:
        if name.endswith(suffix):
            # La arquitectura de verdad, si el nombre la lleva: así añadir un
            # `-linux-arm64.AppImage` no obliga a tocar esta tabla.
            match = re.search(r"-(?:macos|windows|linux)-([a-z0-9]+)\.", name)
            if match:
                architecture = match.group(1)
            return platform, architecture, kind
    return None


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        # A trozos: un DMG son 90 MB y leerlo entero a memoria en el runner no
        # hace falta para nada.
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ------------------------------------------------------------ manifiesto ---


def build_manifest(version, build, notes, uploaded, minimum=None):
    """El `latest.json` que la aplicación lee para saber qué descargar.

    [uploaded] es lo que devuelve `gh release view --json assets`: cada asset
    con su `name`, su `size` y su `id`. El `id` es la pieza que importa: es lo
    que permite descargarlo con un `Authorization:` en vez de con una URL
    pública, que es lo único compatible con que el repositorio sea privado.
    """
    assets = []
    for item in uploaded:
        name = item["name"]
        if name == "latest.json" or name.endswith(".sha256") or name == "SHA256SUMS.txt":
            continue
        what = classify(name)
        if what is None:
            continue
        platform, architecture, kind = what
        digest = item.get("sha256")
        if not digest:
            raise Problem("falta el SHA-256 de %s" % name)
        assets.append(
            {
                "platform": platform,
                "architecture": architecture,
                "kind": kind,
                "name": name,
                "size": int(item["size"]),
                "sha256": digest,
                "assetId": int(item["id"]),
            }
        )

    if not assets:
        raise Problem(
            "el release no tiene ningún artefacto reconocible.\n"
            "Se esperaban nombres como Didacta-%s-macos-universal.dmg" % version
        )

    manifest = {
        "version": version,
        "build": build,
        "tag": "v%s" % version,
        "publishedAt": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "releaseNotes": notes,
        "assets": assets,
    }
    if minimum:
        manifest["minimumSupportedVersion"] = minimum
    return manifest


# --------------------------------------------------------------- órdenes ---


def cmd_version(args):
    name, _ = read_version()
    print(name)


def cmd_build(args):
    _, build = read_version()
    print(build)


def cmd_tag(args):
    name, _ = read_version()
    print("v%s" % name)


def _part_of(args):
    """La de `--part` si se dio, y si no la de `release.yaml`."""
    return canonical_part(args.part) if args.part else planned_part()


def cmd_next(args):
    """Qué número asignará la próxima publicación, sin tocar nada.

    Es la orden que se ejecuta antes de escribir el CHANGELOG: la sección hay
    que titularla con el número que va a salir, y este lo dice.
    """
    name, _ = read_version()
    print(next_version(name, _part_of(args)))


def cmd_plan(args):
    """Lo que dice `release.yaml`, y cambiarlo.

    `--reset` es lo que ejecuta el trabajo que publica justo antes de su
    commit: la parte elegida vale para la versión que se acaba de publicar, y
    la siguiente vuelve a ser la de siempre salvo que alguien diga otra cosa.
    """
    if args.set:
        write_plan("bump", canonical_part(args.set))
    elif args.reset:
        write_plan("bump", DEFAULT_PART)
    part = planned_part()
    name, _ = read_version()
    print(
        "bump: %s (%s) · %s → %s"
        % (part, PARTS[part], name, next_version(name, part))
    )


def cmd_bump(args):
    """Sube la versión en pubspec.yaml.

    La ejecuta cada trabajo del workflow sobre su propia copia nada más
    descargarla, y el resultado es el mismo en los cuatro porque la función es
    determinista. Así los binarios llevan dentro el número con el que se
    publican sin tener que pasarse un commit entre trabajos.

    A mano no hace falta ejecutarla nunca, y hacerlo se salta un número: el
    ciclo la ejecuta igual la próxima vez.
    """
    part = _part_of(args)
    before, after, build = bump(part)
    print("%s → %s+%d (%s)" % (before, after, build, PARTS[part]))


def cmd_notes(args):
    name, _ = read_version()
    print(read_notes(args.version or name))


def cmd_check(args):
    """Todo lo que se puede comprobar antes de compilar nada.

    Va primero en el workflow a propósito: descubrir que falta la sección del
    CHANGELOG después de tres compilaciones de quince minutos es tirar media
    hora por algo que se ve en un segundo.

    Se ejecuta **después** de `bump`, así que la versión que lee ya es la que
    se va a publicar: aquí no hay ningún número especial, sólo el que está
    escrito.
    """
    name, build = read_version()
    part = planned_part()
    notes = read_notes(name)
    print("versión:  %s" % name)
    print("sube:     %s (%s)" % (part, PARTS[part]))
    print("build:    %s" % build)
    print("tag:      v%s" % name)
    print("notas:    %d líneas" % len(notes.split("\n")))
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as handle:
            handle.write("version=%s\n" % name)
            handle.write("part=%s\n" % part)
            handle.write("build=%s\n" % build)
            handle.write("tag=v%s\n" % name)
            # Las notas **no** salen por aquí.
            #
            # Un valor multilínea en `GITHUB_OUTPUT` se delimita con una marca,
            # y una línea del CHANGELOG que coincidiera con esa marca cortaría
            # el valor y dejaría el resto del texto interpretado como más
            # salidas. Quien las necesita --el trabajo que publica-- tiene el
            # repositorio delante y las lee de aquí otra vez, que es gratis y
            # no tiene ese filo.


def cmd_checksums(args):
    """Los SHA-256 de una carpeta, en el formato de `sha256sum -c`."""
    lines = []
    for name in sorted(os.listdir(args.directory)):
        path = os.path.join(args.directory, name)
        if not os.path.isfile(path) or classify(name) is None:
            continue
        lines.append("%s  %s" % (sha256_of(path), name))
    if not lines:
        raise Problem("no hay ningún artefacto en %s" % args.directory)
    text = "\n".join(lines) + "\n"
    sys.stdout.write(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text)


def cmd_manifest(args):
    name, build = read_version()
    notes = read_notes(name)

    with open(args.assets, encoding="utf-8") as handle:
        listed = json.load(handle)
    # `gh release view --json assets` devuelve {"assets": [...]}; se acepta
    # también la lista suelta, que es lo que sale de `gh api`.
    if isinstance(listed, dict):
        listed = listed.get("assets", [])

    # El SHA-256 se calcula de los ficheros locales, no se pide a GitHub: lo
    # que tiene que cuadrar es lo que se subió, y GitHub no publica el hash.
    by_name = {}
    for item in listed:
        by_name[item["name"]] = dict(item)
    for name_ in sorted(os.listdir(args.directory)):
        path = os.path.join(args.directory, name_)
        if os.path.isfile(path) and name_ in by_name:
            by_name[name_]["sha256"] = sha256_of(path)

    manifest = build_manifest(
        name, build, notes, list(by_name.values()), minimum=args.minimum
    )
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("manifiesto con %d artefactos → %s" % (len(manifest["assets"]), args.out))
    for asset in manifest["assets"]:
        print(
            "  %-10s %-9s %-9s %s"
            % (asset["platform"], asset["architecture"], asset["kind"], asset["name"])
        )


def _utf8_output():
    """Que se pueda imprimir en castellano también en Windows.

    Allí Python escribe en la página de códigos de la consola --cp1252-- y
    esta herramienta imprime «», →, … y acentos por todas partes. El primer
    `print` con una flecha dentro revienta con un `UnicodeEncodeError` desde
    dentro de `encodings/cp1252.py`, que es un sitio donde nadie va a buscar
    por qué falló una publicación.

    Pasó: el trabajo de Windows se cayó en `bump`, antes de compilar nada, por
    un `→` en una línea de progreso.
    """
    for stream in (sys.stdout, sys.stderr):
        # `reconfigure` está desde 3.7 y esto se ejecuta con 3.9; el guardián
        # es por si alguien redirige la salida a algo que no es un
        # `TextIOWrapper`.
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8")
            except Exception:  # noqa: BLE001
                pass


def main(argv=None):
    _utf8_output()
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("version", help="la versión de pubspec.yaml").set_defaults(
        run=cmd_version
    )
    sub.add_parser("build", help="el build de pubspec.yaml").set_defaults(run=cmd_build)
    sub.add_parser("tag", help="el tag del release: vX.Y.Z").set_defaults(run=cmd_tag)

    # Sin `choices`: `canonical_part` acepta también los nombres en castellano
    # y dice cuáles valen si no es ninguno.
    following = sub.add_parser(
        "next", help="qué versión asignará la próxima publicación"
    )
    following.add_argument("--part", help="major, minor o patch; si no, release.yaml")
    following.set_defaults(run=cmd_next)

    raise_it = sub.add_parser("bump", help="sube la versión en pubspec.yaml")
    raise_it.add_argument("--part", help="major, minor o patch; si no, release.yaml")
    raise_it.set_defaults(run=cmd_bump)

    plan = sub.add_parser("plan", help="qué dice release.yaml, y cambiarlo")
    change = plan.add_mutually_exclusive_group()
    change.add_argument("--set", metavar="PARTE", help="major, minor o patch")
    change.add_argument("--reset", action="store_true",
                        help="volver a minor, lo de siempre")
    plan.set_defaults(run=cmd_plan)

    notes = sub.add_parser("notes", help="la sección del CHANGELOG")
    notes.add_argument("version", nargs="?")
    notes.set_defaults(run=cmd_notes)

    check = sub.add_parser("check", help="todo lo comprobable antes de compilar")
    check.add_argument(
        "--github-output",
        default=os.environ.get("GITHUB_OUTPUT"),
        help="dónde escribir las salidas para GitHub Actions",
    )
    check.set_defaults(run=cmd_check)

    sums = sub.add_parser("checksums", help="los SHA-256 de una carpeta")
    sums.add_argument("directory")
    sums.add_argument("--out")
    sums.set_defaults(run=cmd_checksums)

    manifest = sub.add_parser("manifest", help="genera latest.json")
    manifest.add_argument("directory", help="la carpeta con los artefactos")
    manifest.add_argument("--assets", required=True, help="el JSON de gh release view")
    manifest.add_argument("--out", required=True)
    manifest.add_argument("--minimum", help="minimumSupportedVersion, si procede")
    manifest.set_defaults(run=cmd_manifest)

    args = parser.parse_args(argv)
    if not getattr(args, "run", None):
        parser.print_help()
        return 2
    try:
        args.run(args)
    except Problem as problem:
        sys.stderr.write("\nNo se puede publicar:\n\n%s\n\n" % problem)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
