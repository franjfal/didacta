#!/usr/bin/env python3
"""La parte de la web que no se escribe a mano: las descargas.

La web de Didacta --`web/`, MkDocs Material-- es markdown escrito por
personas, salvo un trozo: qué versión hay publicada, para qué sistemas, cuánto
ocupa cada fichero y cuál es su SHA-256. Eso cambia en cada publicación y
nadie lo va a copiar a mano sin equivocarse una vez.

Este programa escribe ese trozo, y lo escribe **leyendo el release que hay
publicado**, no un fichero del repositorio:

    python3 packaging/web.py downloads --repo franjfal/didacta

Así la página dice lo que de verdad se puede descargar. La diferencia importa
el día que haya que volver atrás: marcar otra versión como la última es un
`gh release edit --latest`, y con esto la web se corrige volviéndola a
desplegar, sin publicar nada ni tocar ningún fichero.

Durante una publicación, el manifiesto ya está en el disco del runner, así que
también se puede dar directamente y ahorrarse la vuelta por la red:

    python3 packaging/web.py downloads --manifest latest.json

**Se llama `web.py` y no `site.py`** porque `site` es un módulo de la
biblioteca estándar que Python ya tiene importado antes de ejecutar nada:
`import site` desde los tests devolvía el suyo, no el nuestro, y el error
--«module 'site' has no attribute 'render'»-- no dice en ningún sitio que el
problema sea el nombre del fichero.

**Sin ninguna credencial.** El repositorio es público y la API pública basta;
que este programa no necesite un token es lo que permite que la web se
construya en cualquier sitio, incluida la máquina de quien esté escribiendo
documentación.

**Y sin release tampoco falla.** Un repositorio recién abierto, o un fork que
no ha publicado nada, produce un bloque que lo dice y explica cómo compilar
desde el código. Una web que se cae porque todavía no hay binarios es una web
que no se puede estrenar.

Sin dependencias y con Python 3.9, igual que el resto de `packaging/`.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: Dónde va el trozo generado. Bajo `_snippets/` y no entre las páginas para
#: que MkDocs no lo publique como una página suelta: se incluye con
#: `--8<--` desde las que lo necesitan, que son la portada y Descargas.
DEFAULT_OUT = os.path.join(ROOT, "web", "docs", "_snippets", "descargas.md")

API = "https://api.github.com"

TITLES = {"macos": "macOS", "windows": "Windows", "linux": "Linux"}

#: El icono de cada sistema, de los que trae Material.
ICONS = {
    "macos": ":material-apple:",
    "windows": ":material-microsoft-windows:",
    "linux": ":material-linux:",
}

#: Qué se descarga cada uno, dicho para quien no sabe qué es un AppImage.
WHAT = {
    "macos": "Universal: vale para Apple Silicon y para Intel.",
    "windows": "Instalador de 64 bits. **No pide permisos de administrador.**",
    "linux": "AppImage de 64 bits: un solo fichero, sin instalar nada.",
}

#: Y qué hay que hacer con él después de bajarlo. Breve a propósito: si
#: hiciera falta un párrafo, el formato estaría mal elegido.
HOWTO = {
    "macos": (
        "Abre el `.dmg` y arrastra **Didacta** a la carpeta Aplicaciones."
    ),
    "windows": "Ejecuta el instalador y abre Didacta.",
    "linux": "`chmod +x Didacta-*.AppImage` y ábrelo.",
}

#: El orden en que se enseñan. macOS primero porque es donde se desarrolla.
ORDER = ["macos", "windows", "linux"]

MONTHS = [
    "enero",
    "febrero",
    "marzo",
    "abril",
    "mayo",
    "junio",
    "julio",
    "agosto",
    "septiembre",
    "octubre",
    "noviembre",
    "diciembre",
]


class Problem(Exception):
    """Algo que impide escribir la página. Se imprime y se sale con 1."""


def human(size):
    """El tamaño, redondo. Nadie necesita los bytes de un instalador."""
    if size >= 1024 * 1024:
        return "%.0f MB" % (size / (1024.0 * 1024.0))
    return "%d kB" % (size / 1024.0)


def spanish_date(stamp):
    """`2026-09-15T10:00:00Z` → `15 de septiembre de 2026`."""
    if not stamp or len(stamp) < 10:
        return ""
    try:
        year, month, day = (int(part) for part in stamp[:10].split("-"))
    except ValueError:
        return ""
    if not 1 <= month <= 12:
        return ""
    return "%d de %s de %d" % (day, MONTHS[month - 1], year)


def download_url(repo, tag, name):
    """El enlace de descarga directa, el mismo que enseña GitHub.

    Con el repositorio público no hace falta nada más: ni sesión, ni enlace
    firmado, ni un identificador de asset. La aplicación sí descarga por
    `assetId` cuando se actualiza sola --está en `release_channel.dart` y allí
    se explica por qué-- pero una persona con un navegador quiere una
    dirección que se pueda pegar en un correo.
    """
    return "https://github.com/%s/releases/download/%s/%s" % (repo, tag, name)


# ------------------------------------------------------------- el origen ---


def _fetch(url, accept="application/vnd.github+json"):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": accept,
            # GitHub rechaza una petición sin `User-Agent`. No es cortesía.
            "User-Agent": "didacta-site",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def manifest_from_github(repo):
    """El manifiesto del último release publicado, o `None` si no hay.

    Dos peticiones y ninguna autenticada: la primera dice cuál es el último
    release, y la segunda trae su `latest.json`, que es donde están los
    SHA-256. GitHub no publica el hash de un asset, así que el manifiesto no
    es un lujo: es la única forma de que la página pueda enseñarlos.
    """
    try:
        release = json.loads(_fetch("%s/repos/%s/releases/latest" % (API, repo)))
    except urllib.error.HTTPError as failure:
        if failure.code == 404:
            return None
        raise Problem(
            "GitHub respondió %s al preguntar por el último release de %s"
            % (failure.code, repo)
        )
    except urllib.error.URLError as failure:
        raise Problem("no se pudo hablar con GitHub: %s" % failure.reason)

    for asset in release.get("assets", []):
        if asset.get("name") != "latest.json":
            continue
        raw = _fetch(asset["browser_download_url"], accept="application/octet-stream")
        return json.loads(raw.decode("utf-8"))

    raise Problem(
        "el último release de %s (%s) no lleva `latest.json`, así que no se\n"
        "pueden enseñar los SHA-256. Publica una versión con el workflow."
        % (repo, release.get("tag_name", "sin tag"))
    )


# -------------------------------------------------------------- la página ---


def render_missing(repo):
    """Lo que se enseña cuando todavía no hay ninguna versión publicada.

    No es un caso raro: es el primer día de la web, y el de cualquiera que se
    haga un fork. Decirlo y explicar cómo compilar vale más que una página
    rota o tres botones que dan 404.
    """
    return "\n".join(
        [
            '!!! info "Todavía no hay ninguna versión publicada"',
            "",
            "    En cuanto se publique la primera, los instaladores de macOS,",
            "    Windows y Linux aparecerán aquí solos.",
            "",
            "    Mientras tanto, Didacta se puede compilar desde el código:",
            "    está en [%s](https://github.com/%s) y hace falta Flutter." % (repo, repo),
            "",
        ]
    )


def render(manifest, repo):
    """El bloque de descargas: la versión, tres tarjetas y los checksums."""
    version = manifest["version"]
    tag = manifest.get("tag", "v%s" % version)
    published = spanish_date(manifest.get("publishedAt", ""))
    notes = (manifest.get("releaseNotes") or "").strip()

    # Solo los instaladores. El ZIP de macOS existe para que el actualizador
    # pueda sustituir la aplicación sin montar un DMG, y ofrecérselo a una
    # persona sería ofrecerle una segunda forma de instalar macOS que no
    # aporta nada y que hay que explicar.
    installers = {}
    for asset in manifest.get("assets", []):
        if asset.get("kind") == "installer":
            installers[asset["platform"]] = asset

    out = []
    out.append('<div class="didacta-latest" markdown>')
    out.append("")
    out.append(
        ":material-package-variant-closed: **Didacta %s**%s"
        % (version, " · publicada el %s" % published if published else "")
    )
    out.append("")
    out.append("</div>")
    out.append("")

    out.append('<div class="grid cards" markdown>')
    out.append("")
    for platform in ORDER:
        asset = installers.get(platform)
        title = "-   %s __%s__" % (ICONS[platform], TITLES[platform])
        out.append(title)
        out.append("")
        out.append("    ---")
        out.append("")
        if asset is None:
            # Que falte se dice. Una tarjeta que desaparece deja a alguien
            # buscando en la página de al lado si es cosa suya.
            out.append(
                "    Esta versión no trae paquete para %s." % TITLES[platform]
            )
            out.append("")
            continue
        out.append("    %s" % WHAT[platform])
        out.append("")
        out.append("    %s" % HOWTO[platform])
        out.append("")
        out.append(
            "    [:octicons-download-24: Descargar · %s](%s)"
            "{ .md-button .md-button--primary }"
            % (human(asset["size"]), download_url(repo, tag, asset["name"]))
        )
        out.append("")
    out.append("</div>")
    out.append("")

    if notes:
        out.append('??? abstract "Qué cambia en la %s"' % version)
        out.append("")
        for line in notes.split("\n"):
            out.append(("    " + line).rstrip())
        out.append("")

    out.append('??? question "Comprobar que el archivo es el que debe ser"')
    out.append("")
    out.append(
        "    Didacta comprueba el SHA-256 sola cuando se actualiza, y se niega"
    )
    out.append("    a instalar nada que no cuadre. Para comprobarlo a mano:")
    out.append("")
    out.append("    ```")
    for platform in ORDER:
        asset = installers.get(platform)
        if asset is not None:
            out.append("    %s  %s" % (asset["sha256"], asset["name"]))
    out.append("    ```")
    out.append("")
    out.append(
        "    En macOS y Linux, `shasum -a 256 <fichero>`; en Windows,"
    )
    out.append("    `Get-FileHash <fichero>`.")
    out.append("")

    out.append(
        "[Todas las versiones](https://github.com/%s/releases) ·" % repo
    )
    out.append(
        "[Notas de esta versión](https://github.com/%s/releases/tag/%s)"
        % (repo, tag)
    )
    out.append("")
    return "\n".join(out)


# --------------------------------------------------------------- órdenes ---


def cmd_downloads(args):
    if args.manifest:
        with open(args.manifest, encoding="utf-8") as handle:
            manifest = json.load(handle)
    else:
        manifest = manifest_from_github(args.repo)

    page = render(manifest, args.repo) if manifest else render_missing(args.repo)

    directory = os.path.dirname(os.path.abspath(args.out))
    if directory and not os.path.isdir(directory):
        os.makedirs(directory)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(page)
    if manifest:
        print("descargas de la %s → %s" % (manifest["version"], args.out))
    else:
        print("sin versión publicada todavía → %s" % args.out)


def _utf8_output():
    """Que se pueda imprimir en castellano también en Windows.

    Lo mismo que hace `release.py`, y por lo mismo: allí Python escribe en la
    página de códigos de la consola y un `→` tumba el programa desde dentro de
    `encodings/cp1252.py`, que es un sitio donde nadie va a buscar.
    """
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8")
            except Exception:  # noqa: BLE001
                pass


def main(argv=None):
    _utf8_output()
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command")

    downloads = sub.add_parser(
        "downloads", help="escribe el bloque de descargas de la web"
    )
    downloads.add_argument(
        "--repo",
        default="franjfal/didacta",
        help="de dónde se leen los releases (y a dónde apuntan los enlaces)",
    )
    downloads.add_argument(
        "--manifest",
        help="un latest.json local, en vez de preguntar a GitHub",
    )
    downloads.add_argument("--out", default=DEFAULT_OUT)
    downloads.set_defaults(run=cmd_downloads)

    args = parser.parse_args(argv)
    if not getattr(args, "run", None):
        parser.print_help()
        return 2
    try:
        args.run(args)
    except Problem as problem:
        sys.stderr.write("\nNo se puede escribir la página:\n\n%s\n\n" % problem)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
