#!/usr/bin/env python3
"""Escribe el README de `didacta_public`: la página de descarga.

**Por qué el README y no una GitHub Page.** Una Page servida desde un
repositorio privado es pública salvo que la cuenta tenga GitHub Enterprise
Cloud, que es donde vive el control de acceso de Pages. En una cuenta
personal, activar Pages sobre `didacta_public` publicaría en internet la lista
de versiones y los enlaces de descarga. El README, en cambio, lo ve quien
entra al repositorio, y al repositorio entra quien tiene acceso: la misma
puerta que ya controla quién puede actualizar.

Es menos bonito y es lo correcto. La seguridad va por delante de tener una
página con estilo.

Uso:
    python3 packaging/portal.py latest.json > README.md
"""

import json
import sys

REPO = "franjfal/didacta_public"

# Lo que hay que hacer con cada fichero después de descargarlo. Breve: si
# hiciera falta un párrafo, el formato estaría mal elegido.
HOWTO = {
    "macos": (
        "Abre el `.dmg` y arrastra **Didacta** a la carpeta Aplicaciones. "
        "La primera vez, si macOS avisa de que no se puede comprobar el "
        "desarrollador, ábrela con el botón derecho → Abrir."
    ),
    "windows": (
        "Ejecuta el instalador. Se instala para tu usuario, así que **no "
        "pide contraseña de administrador**. Si SmartScreen avisa, "
        "«Más información» → «Ejecutar de todas formas»."
    ),
    "linux": (
        "Dale permiso de ejecución y ábrelo:\n\n"
        "    chmod +x Didacta-*.AppImage\n"
        "    ./Didacta-*.AppImage\n"
    ),
}

TITLES = {"macos": "macOS", "windows": "Windows", "linux": "Linux"}

# El orden en que se enseñan. macOS primero porque es donde se desarrolla.
ORDER = ["macos", "windows", "linux"]


def human(size):
    if size >= 1024 * 1024:
        return "%.0f MB" % (size / (1024.0 * 1024.0))
    return "%d kB" % (size / 1024.0)


def download_url(tag, name):
    """El enlace de descarga.

    Funciona en el navegador para quien ha entrado en GitHub y tiene acceso al
    repositorio; para quien no, GitHub devuelve un 404. No es un enlace
    público ni firmado: es la misma dirección de siempre, protegida por la
    sesión, que es exactamente lo que se quiere.
    """
    return "https://github.com/%s/releases/download/%s/%s" % (REPO, tag, name)


def render(manifest):
    version = manifest["version"]
    tag = manifest.get("tag", "v%s" % version)
    published = manifest.get("publishedAt", "")[:10]
    notes = manifest.get("releaseNotes", "").strip()

    installers = {}
    for asset in manifest.get("assets", []):
        if asset.get("kind") != "installer":
            continue
        installers[asset["platform"]] = asset

    out = []
    out.append("# Didacta")
    out.append("")
    out.append(
        "Material docente en LaTeX: se escribe una vez y se generan las "
        "diapositivas, los apuntes, las hojas de problemas y los exámenes, "
        "en castellano, valenciano e inglés."
    )
    out.append("")
    out.append(
        "Este repositorio **no tiene el código**. Solo sirve para descargar "
        "la aplicación, y tenerlo a mano es lo que te permite instalarla y "
        "recibir las actualizaciones."
    )
    out.append("")
    out.append("---")
    out.append("")
    out.append("## Última versión: %s" % version)
    out.append("")
    if published:
        out.append("Publicada el %s." % published)
        out.append("")

    if notes:
        out.append("### Qué cambia")
        out.append("")
        out.append(notes)
        out.append("")

    out.append("### Descargar")
    out.append("")
    out.append("| Sistema | Archivo | Tamaño |")
    out.append("| --- | --- | --- |")
    for platform in ORDER:
        asset = installers.get(platform)
        if asset is None:
            out.append("| %s | — | — |" % TITLES[platform])
            continue
        out.append(
            "| **%s** | [%s](%s) | %s |"
            % (
                TITLES[platform],
                asset["name"],
                download_url(tag, asset["name"]),
                human(asset["size"]),
            )
        )
    out.append("")
    out.append(
        "Si el enlace te da un 404, es que tu cuenta de GitHub no tiene "
        "acceso a este repositorio todavía."
    )
    out.append("")

    out.append("### Cómo se instala")
    out.append("")
    for platform in ORDER:
        if platform not in installers:
            continue
        out.append("**%s.** %s" % (TITLES[platform], HOWTO[platform]))
        out.append("")

    out.append("---")
    out.append("")
    out.append("## Después de instalarla")
    out.append("")
    out.append(
        "Abre Didacta y ve a **Ajustes → Cuenta de GitHub → Entrar en "
        "GitHub**. Te dará un código corto; lo escribes en "
        "[github.com/login/device](https://github.com/login/device) y ya "
        "está. **La contraseña no se escribe nunca dentro de Didacta**: se "
        "teclea en github.com, que es el único sitio donde tiene sentido "
        "hacerlo."
    )
    out.append("")
    out.append(
        "A partir de ahí Didacta comprueba sola si hay una versión nueva, "
        "una vez por semana, y te pregunta antes de hacer nada. También "
        "puedes buscarlas cuando quieras en **Ajustes → Actualizaciones**."
    )
    out.append("")

    out.append("## Comprobar que el archivo es el que debe ser")
    out.append("")
    out.append(
        "Cada versión publica los SHA-256 de todos sus archivos en "
        "`SHA256SUMS.txt`. Didacta los comprueba sola al actualizarse y se "
        "niega a instalar nada que no coincida; si quieres comprobarlo a "
        "mano:"
    )
    out.append("")
    out.append("```")
    for platform in ORDER:
        asset = installers.get(platform)
        if asset is None:
            continue
        out.append("%s  %s" % (asset["sha256"], asset["name"]))
    out.append("```")
    out.append("")

    out.append("## Versiones anteriores")
    out.append("")
    out.append(
        "Están todas en [Releases](https://github.com/%s/releases)." % REPO
    )
    out.append("")
    out.append("---")
    out.append("")
    out.append(
        "<sub>Esta página la escribe el workflow de publicación a partir del "
        "manifiesto de la versión. No la edites a mano: el siguiente release "
        "la sobrescribe.</sub>"
    )
    out.append("")
    return "\n".join(out)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("uso: portal.py <latest.json>\n")
        return 2
    with open(argv[1], encoding="utf-8") as handle:
        manifest = json.load(handle)
    sys.stdout.write(render(manifest))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
