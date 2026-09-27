"""Snippets: lo que la barra del editor sabe envolver, declarado por el repositorio.

La barra traía una lista fija --los canales, los teoremas, las partes de un
problema-- escrita en la aplicación. Eso servía para lo que Didacta define y
para nada más: un entorno propio, un `\\resumen{}` que usa medio
departamento, había que escribirlo a mano cada vez, y no había dónde decir
que en el repositorio de problemas «Teorema» sobra.

Un snippet es una entrada de:

    snippets.yaml           la lista, en el orden en que se ofrecen

con su definición de LaTeX y su texto de ejemplo dentro, como bloques `|`:

    snippets:
      - id: resumen
        label: Resumen
        group: Teoría
        environment: resumen
        definition: |
          \\DidactaNewTheorem{resumen}{Resumen}{didactaThm}
        sample: |
          Lo esencial del tema, en una caja.
      - id: theorem         # el de Didacta, tal cual

Tres decisiones que conviene leer antes de tocar esto:

**Una entrada con solo el id es la de Didacta.** La lista de serie vive en la
aplicación, que es quien la enseña; aquí basta con nombrarla para ofrecerla,
y los campos que se escriban la retocan. Así un repositorio puede quitar
«Teorema» de su barra o cambiarle el nombre sin copiar lo que Didacta ya
sabe, y cuando Didacta lo mejore lo recibe sin hacer nada. El motor no
necesita conocer esa lista: lo que compila es la definición, y las de serie
no la llevan porque ya están en `didacta-theorems.sty`.

**Sin `snippets.yaml`, la lista de serie.** Un repositorio que no dice nada
ofrece lo que se ofrecía antes de que esto existiera. Por eso el índice
distingue «no hay fichero» (None) de «hay uno vacío» (una lista vacía).

**La definición va a todo lo que se compila en el repositorio.** Un snippet
que define un entorno lo usa el material, y el material se compila en la
lección, en el tema y en la vista previa. Se reúne en un fichero de la
carpeta de compilación y LaTeX lo lee por `\\DidactaSnippets`, justo antes
del preámbulo de la plantilla --que así puede seguir redefiniéndolo todo--.
El `.tex` del material no cambia ni una línea.
"""

from __future__ import annotations

import os
import re

from . import yamlio

#: Dónde se declaran, en la raíz del repositorio.
SNIPPETS_META = "snippets.yaml"

#: Las definiciones reunidas, bajo la carpeta de compilación. Se reescribe en
#: cada arranque del motor y no se versiona.
DEFINITIONS = os.path.join("snippets", "define.tex")

#: Lo que se puede escribir en una entrada, con su nombre en el índice.
FIELDS = {
    "label": "label",
    "group": "group",
    "description": "description",
    "environment": "environment",
    "command": "command",
    "environment_aliases": "environmentAliases",
    "command_aliases": "commandAliases",
    "arguments": "arguments",
    "block": "block",
    "definition": "definition",
    "sample": "sample",
}

_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
_ENVIRONMENT = re.compile(r"^[A-Za-z@]+\*?$")
_COMMAND = re.compile(r"^[A-Za-z@]+$")


class SnippetError(ValueError):
    """Una declaración de snippet que no se puede leer."""


class Snippet:
    """Una entrada de `snippets.yaml`, con lo que tenga escrito y nada más.

    Los campos que faltan son None, no un valor por defecto: una entrada que
    no dice `label` hereda el de Didacta, y eso solo lo sabe quien conoce la
    lista de serie.
    """

    __slots__ = ("id",) + tuple(FIELDS)

    def __init__(self, id, **fields):
        self.id = id
        for name in FIELDS:
            setattr(self, name, fields.get(name))

    @property
    def names(self):
        """Los nombres de entorno que define o reconoce, el suyo primero."""
        return [name for name in [self.environment] + list(
            self.environment_aliases or []) if name]

    def as_dict(self):
        """Lo que va al índice: solo lo escrito, con los nombres de JSON."""
        data = {"id": self.id}
        for name, key in FIELDS.items():
            value = getattr(self, name)
            if value is not None:
                data[key] = list(value) if isinstance(value, list) else value
        return data


def load(directory):
    """Los snippets que declara un directorio, en el orden del fichero.

    None cuando no hay `snippets.yaml`: el repositorio ofrece los de serie.
    """
    path = os.path.join(directory, SNIPPETS_META)
    if not os.path.isfile(path):
        return None

    data = yamlio.load_file(path) or {}
    if not isinstance(data, dict):
        raise SnippetError("%s: expected a mapping" % path)
    declared = data.get("snippets")
    if declared is None:
        declared = []
    if not isinstance(declared, list):
        raise SnippetError("%s: `snippets` should be a list" % path)

    found = []
    seen = set()
    for item in declared:
        if not isinstance(item, dict):
            raise SnippetError("%s: each snippet should be a mapping" % path)
        identifier = item.get("id")
        if identifier is None or str(identifier).strip() == "":
            raise SnippetError("%s: a snippet is missing its `id`" % path)
        identifier = str(identifier).strip()
        if not _ID.match(identifier):
            raise SnippetError("%s: `%s` is not a valid snippet id"
                               % (path, identifier))
        if identifier in seen:
            raise SnippetError("%s: duplicate snippet `%s`" % (path, identifier))
        seen.add(identifier)
        found.append(_snippet(item, identifier, path))
    return found


def _snippet(item, identifier, path):
    fields = {}
    for name in ("label", "group", "description", "arguments"):
        value = item.get(name)
        if value is not None:
            fields[name] = str(value).strip()
    for name in ("definition", "sample"):
        value = item.get(name)
        if value is not None:
            # El salto que deja `|` al final no es parte del texto: una
            # definición se escribe en su línea y un ejemplo se mete dentro
            # de un entorno, y los dos ponen el suyo.
            fields[name] = str(value).rstrip("\n")

    environment = item.get("environment")
    if environment is not None:
        environment = str(environment).strip()
        if not _ENVIRONMENT.match(environment):
            raise SnippetError("%s: snippet `%s` has an invalid environment "
                               "name `%s`" % (path, identifier, environment))
        fields["environment"] = environment
    command = item.get("command")
    if command is not None:
        command = str(command).strip().lstrip("\\")
        if not _COMMAND.match(command):
            raise SnippetError("%s: snippet `%s` has an invalid command name "
                               "`%s`" % (path, identifier, command))
        fields["command"] = command

    for name, pattern in (("environment_aliases", _ENVIRONMENT),
                          ("command_aliases", _COMMAND)):
        value = item.get(name)
        if value is None:
            continue
        if isinstance(value, str):
            value = [part.strip() for part in value.split(",")]
        if not isinstance(value, list):
            raise SnippetError("%s: snippet `%s` should list `%s`"
                               % (path, identifier, name))
        names = [str(each).strip().lstrip("\\") for each in value
                 if str(each).strip()]
        for each in names:
            if not pattern.match(each):
                raise SnippetError("%s: snippet `%s` has an invalid name `%s` "
                                   "in `%s`" % (path, identifier, each, name))
        fields[name] = names

    block = item.get("block")
    if block is not None:
        fields["block"] = block is True
    return Snippet(identifier, **fields)


def write_definitions(path, snippets):
    r"""Reúne las definiciones en el fichero que lee LaTeX.

    Devuelve la ruta, o None si ninguno define nada -- y entonces no se
    escribe, para que un repositorio sin snippets propios compile sin dejar
    rastro, igual que antes.
    """
    defined = [snippet for snippet in snippets or []
               if (snippet.definition or "").strip()]
    if not defined:
        return None
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(
            "%% Generado por Didacta. No editar: se reescribe en cada\n"
            "%% compilación a partir de `snippets.yaml`.\n"
            "%%\n"
            "%% Va antes del preámbulo de la plantilla, así que una plantilla\n"
            "%% puede redefinir lo que se define aquí.\n"
        )
        for snippet in defined:
            handle.write("\n%%%% --- %s\n" % snippet.id)
            handle.write(snippet.definition.rstrip("\n") + "\n")
    return path


# --------------------------------------------------------------------------
# La vista previa
# --------------------------------------------------------------------------

#: Dónde se compila la vista previa de un snippet, bajo la carpeta de
#: compilación. Siempre la misma: se ve una a la vez.
PREVIEW_DIR = "snippet-preview"

_FRAGILE = re.compile(r"\\verb|\\begin\{(verbatim|lstlisting|minted)")


def preview_text(body, slides=False):
    r"""El documento más pequeño que enseña [body] con el preámbulo de verdad.

    En diapositivas el cuerpo va dentro de un `frame`, salvo que ya lo traiga:
    un snippet de diapositiva se enseña como es, y cualquier otro necesita
    una diapositiva donde caer.
    """
    body = body.rstrip("\n")
    if slides and "\\begin{frame}" not in body:
        fragile = "[fragile]" if _FRAGILE.search(body) else ""
        body = "\\begin{frame}%s\n%s\n\\end{frame}" % (fragile, body)
    elif not slides:
        # Sin cabecera ni número de página: el PDF se recorta a lo que tiene
        # tinta, y una cabecera arriba y un número abajo son tinta.
        body = "\\pagestyle{empty}\\thispagestyle{empty}\n" + body
    return (
        "%% Generado por Didacta: la vista previa de un snippet.\n"
        "\\input{didacta-bootstrap}\n"
        "\\usepackage{didacta}\n"
        "\\begin{document}\n"
        "%s\n"
        "\\end{document}\n" % body
    )


def write_preview(build_dir, body, slides=False):
    """Escribe el documento de la vista previa y devuelve su ruta."""
    folder = os.path.join(build_dir, PREVIEW_DIR)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "snippet.tex")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(preview_text(body, slides=slides))
    return path
