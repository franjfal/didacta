"""Versiones congeladas de un curso.

Una congelación es **un commit con nombre**. No es una copia del material:
copiar un repositorio de dos mil unidades para poder mirar cómo estaba en
septiembre sería pagar gigabytes por una información que git ya tiene y sabe
dar. Lo que falta es lo que git no guarda: que ese commit concreto es «Antes
del primer parcial» y que pertenece a este curso.

Eso es lo que hay aquí, y vive en el repositorio:

    courses/<asignatura>/<año>/freezes.yaml

Dentro de git por lo mismo que todo lo demás. Un clon en otro ordenador tiene
que ver las mismas congelaciones, y una base de datos local no se clona.

**Una congelación apunta al commit que era HEAD al crearla.** No puede
apuntar al suyo propio --un commit no contiene su propio hash-- y tampoco
debería: lo que se congela es el estado que había, no la línea que lo anota.

**Quitar una congelación no toca git.** Se borra su entrada y ya está: los
commits siguen, la historia sigue, el curso sigue y las demás congelaciones
siguen, incluso las que apunten al mismo commit.
"""

from __future__ import annotations

import datetime
import os
import re

from . import identity as identity_mod
from . import yamlio

FREEZES_META = "freezes.yaml"

#: Un SHA de git, entero. Los cortos no valen aquí: se guardan para años y un
#: prefijo que hoy es único deja de serlo cuando el repositorio crece.
_SHA = re.compile(r"^[0-9a-f]{40}$")


class FreezeError(ValueError):
    """Algo de una congelación no cuadra."""


_HEADER = """\
# Las versiones congeladas de este curso.
#
# Cada una es un commit con nombre: el estado exacto del material en ese
# punto. No hay ninguna copia detrás -- git ya guarda el contenido, y lo que
# se guarda aquí es lo que git no sabe: cómo se llama ese momento.
#
# Quitar una de aquí no borra ningún commit ni toca la historia. Y abrir una
# no cambia el curso: se mira en un árbol aparte y de solo lectura.
"""


class Freeze:
    """Una versión congelada."""

    __slots__ = ("id", "name", "description", "created", "commit", "course",
                 "year", "repo")

    def __init__(self, id, name, commit, created=None, description="",
                 course="", year="", repo=""):
        self.id = id
        self.name = name
        self.commit = commit
        self.created = created
        self.description = description or ""
        self.course = course
        self.year = year
        self.repo = repo

    @property
    def short(self):
        return self.commit[:7] if self.commit else ""

    def as_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "created": self.created,
            "commit": self.commit,
            "course": self.course,
            "year": self.year,
        }

    def __repr__(self):  # pragma: no cover - para leer un fallo de test
        return "Freeze(%s, %r, %s)" % (self.id, self.name, self.short)


def path_for(year_directory):
    return os.path.join(year_directory, FREEZES_META)


def load(year_directory, course="", year=""):
    """Las congelaciones de un curso, en el orden en que se crearon.

    El fichero es opcional y su ausencia no es un error: un curso sin
    congelar no tiene ninguna, que es el caso de todos hasta que alguien
    congela el primero.

    La asignatura y el año salen de **dónde está el fichero**, no de lo que
    diga dentro. Los lleva escritos igual --como los lleva `year.yaml`, y por
    lo mismo: el fichero se lee suelto en un diff-- pero quien manda es la
    carpeta, porque es la que no puede equivocarse.
    """
    path = path_for(year_directory)
    if not os.path.isfile(path):
        return []
    data = yamlio.load_file(path)
    if not isinstance(data, dict):
        raise FreezeError("%s: se esperaba un mapa" % path)
    declared = data.get("freezes") or []
    if declared and not isinstance(declared, list):
        raise FreezeError("%s: `freezes` debería ser una lista" % path)

    found = []
    for item in declared:
        if not isinstance(item, dict):
            raise FreezeError("%s: cada congelación debería ser un mapa" % path)
        identifier = str(item.get("id") or "").strip()
        if not identifier:
            raise FreezeError("%s: una congelación no tiene `id`" % path)
        commit = str(item.get("commit") or "").strip().lower()
        if not _SHA.match(commit):
            raise FreezeError(
                "%s: `%s` no apunta a ningún commit (`commit:` tiene que ser "
                "un SHA de 40 caracteres)" % (path, identifier)
            )
        found.append(
            Freeze(
                id=identifier,
                name=str(item.get("name") or identifier),
                description=str(item.get("description") or ""),
                created=_text(item.get("created")),
                commit=commit,
                course=course or str(item.get("course") or ""),
                year=year or str(item.get("year") or ""),
            )
        )
    return found


def _text(value):
    if value is None:
        return ""
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    return str(value)


def now():
    """Ahora, con zona horaria. Una fecha sin zona no ordena entre máquinas."""
    return datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()


def add(year_directory, *, name, commit, description="", course="", year="",
        identifier=None, created=None):
    """Añade una congelación y devuelve la que se ha escrito.

    No comprueba que el commit exista: este módulo no habla con git, y quien
    llama --la aplicación, que tiene el clon delante-- ya lo ha resuelto. Lo
    que sí comprueba es la forma, porque un SHA corto guardado hoy es una
    ambigüedad dentro de tres años.
    """
    name = (name or "").strip()
    if not name:
        raise FreezeError("una congelación necesita un nombre")
    commit = (commit or "").strip().lower()
    if not _SHA.match(commit):
        raise FreezeError(
            "`%s` no es un commit entero: hacen falta los 40 caracteres" % commit
        )

    existing = load(year_directory, course, year)
    identifier = identifier or identity_mod.new_id(identity_mod.FREEZE)
    if any(item.id == identifier for item in existing):
        raise FreezeError("ya hay una congelación con el id `%s`" % identifier)
    if any(item.name == name for item in existing):
        raise FreezeError(
            "ya hay una congelación llamada «%s» en este curso. Los nombres "
            "son lo que se lee en la lista, así que no se repiten." % name
        )

    entry = Freeze(
        id=identifier,
        name=name,
        description=(description or "").strip(),
        created=created or now(),
        commit=commit,
        course=course,
        year=year,
    )
    _write(year_directory, existing + [entry])
    return entry


def remove(year_directory, identifier, course="", year=""):
    """Quita una congelación. Devuelve la que se ha quitado.

    Solo esto: su entrada. Ni un commit, ni una rama, ni una etiqueta, ni el
    árbol de trabajo. Lo único que puede sobrar después es un worktree en la
    caché, y de eso se encarga quien la tenga, porque puede estar en uso por
    otra congelación del mismo commit.
    """
    existing = load(year_directory, course, year)
    gone = [item for item in existing if item.id == identifier]
    if not gone:
        raise FreezeError("no hay ninguna congelación `%s`" % identifier)
    _write(year_directory, [item for item in existing if item.id != identifier])
    return gone[0]


def rename(year_directory, identifier, *, name=None, description=None,
           course="", year=""):
    """Cambia el nombre o la descripción de una congelación."""
    existing = load(year_directory, course, year)
    found = None
    for item in existing:
        if item.id != identifier:
            continue
        found = item
        if name is not None:
            cleaned = name.strip()
            if not cleaned:
                raise FreezeError("una congelación necesita un nombre")
            if any(other.name == cleaned and other.id != identifier
                   for other in existing):
                raise FreezeError(
                    "ya hay una congelación llamada «%s» en este curso" % cleaned
                )
            item.name = cleaned
        if description is not None:
            item.description = description.strip()
    if found is None:
        raise FreezeError("no hay ninguna congelación `%s`" % identifier)
    _write(year_directory, existing)
    return found


def _write(year_directory, entries):
    """Escribe el fichero entero.

    Aquí sí se reserializa, al revés que en `year.yaml`: este fichero lo
    escribe Didacta de principio a fin y nadie compone una congelación a mano.
    La cabecera se conserva porque explica lo que hay que saber antes de
    borrar una línea.
    """
    path = path_for(year_directory)
    header = _HEADER
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as handle:
            kept = []
            for line in handle.read().split("\n"):
                if line.strip() and not line.lstrip().startswith("#"):
                    break
                kept.append(line)
        while kept and not kept[-1].strip():
            kept.pop()
        if kept:
            header = "\n".join(kept) + "\n"

    body = ["freezes:"] if entries else ["freezes: []"]
    for item in entries:
        body.append("  - id: %s" % item.id)
        body.append("    name: %s" % yamlio._fmt(item.name))
        if item.description:
            body.append("    description: %s" % yamlio._fmt(item.description))
        body.append("    created: %s" % yamlio._fmt(item.created))
        body.append("    commit: %s" % item.commit)
        if item.course:
            body.append("    course: %s" % item.course)
        if item.year:
            body.append("    year: %s" % yamlio._fmt(item.year))

    os.makedirs(year_directory, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(header + "\n" + "\n".join(body) + "\n")
