"""Plantillas de compilación: perfiles de salida que escribe quien enseña.

Un perfil dice qué **es** una salida --qué clase de documento, con qué
opciones y con qué ejes-- y hasta ahora los quince que hay estaban escritos en
`latex/didacta-profiles.tex`, que viene con Didacta. Eso significaba que
cambiar el margen de los apuntes o meter un paquete propio era editar el
programa.

Una plantilla es lo mismo, declarado por quien escribe el material:

    templates.yaml          las declaraciones
    templates/<id>.tex      el preámbulo de cada una, si lo tiene

y son **la misma cosa** que un perfil, no una capa encima: [Template] hereda
de [profiles.Profile], así que todo lo que sabe compilar un perfil sabe
compilar una plantilla sin enterarse.

Tres decisiones que conviene leer antes de tocar esto:

**El registro que trae Didacta no se retira.** Las quince salidas de siempre
siguen en `didacta-profiles.tex`, y por una razón concreta: `pdflatex
master.tex` a mano, en un editor y con SyncTeX, tiene que seguir produciendo
los apuntes sin que el motor intervenga. Una plantilla con el mismo id
**sustituye** a la de serie cuando compila Didacta, y la de serie sigue siendo
la que se usa cuando no.

**El preámbulo no se mete en el documento.** Se genera un fichero de
declaraciones en la carpeta de compilación y se le pasa a LaTeX por
`\\DidactaTemplates`; el preámbulo de la plantilla elegida, por
`\\DidactaPreamble`. El `.tex` del material no cambia ni una línea, que es lo
que permite cambiar de plantilla sin tocar el contenido.

**Un directorio de plantillas no es necesariamente un repositorio.** Se cargan
de cualquier carpeta que tenga `templates.yaml`, porque además de los
repositorios de contenido está la carpeta del propio programa, para quien no
quiera meter sus plantillas en el material de nadie.
"""

from __future__ import annotations

import os

from . import profiles as profiles_mod
from . import yamlio

#: Dónde se declaran, dentro de un directorio de plantillas.
TEMPLATES_META = "templates.yaml"

#: Dónde vive el preámbulo de cada una. Un fichero `.tex` de verdad y no una
#: cadena dentro del YAML: es LaTeX, y se edita, se resalta y se lee en un
#: diff como LaTeX.
TEMPLATES_DIR = "templates"

#: El fichero de declaraciones que se genera para LaTeX, bajo la carpeta de
#: compilación. Se reescribe en cada arranque y no se versiona.
DECLARATIONS = os.path.join("templates", "declare.tex")


class TemplateError(ValueError):
    """Una declaración de plantilla que no se puede leer."""


class Template(profiles_mod.Profile):
    """Una salida declarada por el repositorio.

    Hereda de [profiles.Profile] a propósito: el nombre legible, la familia,
    cuánto enseña de un ejercicio y el prólogo `\\def` que selecciona la
    salida son exactamente los mismos, y tenerlos dos veces sería tener dos
    respuestas a la misma pregunta.
    """

    __slots__ = ("titles", "active", "preamble", "source", "raw")

    def __init__(self, id, document_class, class_options, axes, titles=None,
                 active=True, preamble=None, source=None, raw=None):
        super().__init__(id, document_class, class_options, axes)
        self.titles = titles or {}
        #: Si se compila. Apagarla la deja declarada y fuera de las salidas,
        #: que es lo que se quiere de una versión que este curso no se da:
        #: borrarla perdería su preámbulo.
        self.active = active
        #: La ruta de su `.tex`, o None si no tiene preámbulo propio.
        self.preamble = preamble
        #: De qué directorio salió. Con varios abiertos hace falta para poder
        #: decir dónde se edita.
        self.source = source
        self.raw = raw or {}

    def title(self, language=None):
        """El nombre que se lee.

        El declarado, y si no hay ninguno el que el perfil deduce de sus ejes
        --«Diapositivas (sin pausas)»--, que es mejor que enseñar el id y no
        obliga a rellenar tres idiomas para empezar a usar una plantilla.
        """
        for code in (language, "es", "va", "en"):
            if code and self.titles.get(code):
                return self.titles[code]
        for value in self.titles.values():
            if value:
                return value
        return self.label

    def declaration(self):
        r"""La línea `\DidactaDeclareProfile` que la declara ante LaTeX."""
        axes = ",".join("%s=%s" % (key, self.axes[key])
                        for key in sorted(self.axes))
        return "\\DidactaDeclareProfile{%s}{%s}{%s}{%s}" % (
            self.id, self.document_class, self.class_options, axes,
        )

    def as_dict(self):
        data = super().as_dict()
        data.update({
            "title": dict(self.titles),
            "active": self.active,
            "hasPreamble": bool(self.preamble),
        })
        return data


def load(directory, settings=None):
    """Las plantillas declaradas en un directorio, en el orden del fichero.

    Lista vacía cuando no hay `templates.yaml`, que es lo corriente: un
    repositorio sin plantillas compila con las que trae Didacta, exactamente
    como antes de que esto existiera.
    """
    path = os.path.join(directory, TEMPLATES_META)
    if not os.path.isfile(path):
        return []

    data = yamlio.load_file(path) or {}
    if not isinstance(data, dict):
        raise TemplateError("%s: expected a mapping" % path)
    declared = data.get("templates") or []
    if not isinstance(declared, list):
        raise TemplateError("%s: `templates` should be a list" % path)

    languages = (settings.languages if settings
                 else list(profiles_mod.DEFAULT_LANGUAGES))
    found = []
    seen = set()
    for item in declared:
        if not isinstance(item, dict):
            raise TemplateError("%s: each template should be a mapping" % path)
        identifier = item.get("id")
        if not identifier:
            raise TemplateError("%s: a template is missing its `id`" % path)
        if identifier in seen:
            raise TemplateError("%s: duplicate template `%s`"
                                % (path, identifier))
        seen.add(identifier)

        document_class = (item.get("class") or "").strip()
        if not document_class:
            raise TemplateError(
                "%s: template `%s` is missing its `class`" % (path, identifier)
            )

        preamble = os.path.join(directory, TEMPLATES_DIR, "%s.tex" % identifier)
        found.append(Template(
            id=identifier,
            document_class=document_class,
            class_options=str(item.get("options") or "").strip(),
            axes=_axes(item.get("axes"), path, identifier),
            titles=yamlio.localised(item.get("title"), languages,
                                    path=path, key="title"),
            # Encendida mientras nadie diga lo contrario: lo normal es que una
            # plantilla declarada se use, y lo normal no se declara.
            active=item.get("active", True) is not False,
            preamble=preamble if os.path.isfile(preamble) else None,
            source=directory,
            raw=item,
        ))
    return found


def _axes(raw, path, identifier):
    """Los ejes de una plantilla, comprobados contra los que existen.

    Un mapa y no la cadena `medium=slides,detail=brief` que lleva el LaTeX:
    esto se escribe a mano en YAML, donde un mapa se lee y se edita mejor. La
    cadena la arma [Template.declaration] al generar la declaración.
    """
    axes = dict(profiles_mod.DEFAULT_AXES)
    if raw is None:
        return axes
    if not isinstance(raw, dict):
        raise TemplateError(
            "%s: template `%s` should declare `axes` as a mapping"
            % (path, identifier)
        )
    for key, value in raw.items():
        key = str(key).strip()
        # `pauses: off` en YAML es el booleano falso, no la cadena «off». Es
        # la forma natural de escribirlo y la que sale de copiar el eje tal
        # como se lee en `didacta-profiles.tex`, así que se traduce en vez de
        # rechazarse con un mensaje sobre `False` que no significa nada para
        # quien escribió `off`.
        if isinstance(value, bool):
            value = "on" if value else "off"
        value = str(value).strip()
        if key not in profiles_mod.VALID_AXES:
            raise TemplateError(
                "%s: template `%s` sets unknown axis `%s` (known: %s)"
                % (path, identifier, key,
                   ", ".join(sorted(profiles_mod.VALID_AXES)))
            )
        if value not in profiles_mod.VALID_AXES[key]:
            raise TemplateError(
                "%s: template `%s` sets %s=%s (allowed: %s)"
                % (path, identifier, key, value,
                   ", ".join(sorted(profiles_mod.VALID_AXES[key])))
            )
        axes[key] = value
    return axes


def merge(groups):
    """Junta las plantillas de varios directorios, por id.

    Gana el primero que la declare, que es el orden en que se pasan los
    directorios. Es la misma regla que sostiene lo demás cuando hay varios
    repositorios abiertos: se juntan, no se eligen.
    """
    merged = {}
    for group in groups:
        for template in group:
            merged.setdefault(template.id, template)
    return list(merged.values())


def load_many(directories, settings=None):
    """Lo mismo, cargando cada directorio."""
    return merge([load(directory, settings) for directory in directories])


def write_declarations(path, templates):
    r"""Escribe el fichero que LaTeX lee para conocer las plantillas.

    Todas, también las apagadas: apagada quiere decir «no la compiles», no
    «que LaTeX no sepa qué es». Alguien que pida una apagada a mano tiene que
    obtener su PDF y no un error de perfil desconocido.

    Devuelve la ruta, o None si no había ninguna que declarar -- y entonces no
    se escribe el fichero, para que una compilación sin plantillas no deje
    rastro.
    """
    if not templates:
        return None
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(
            "%% Generado por Didacta. No editar: se reescribe en cada\n"
            "%% compilación a partir de los `templates.yaml` abiertos.\n"
            "%%\n"
            "%% Va después del registro que trae Didacta, así que una\n"
            "%% plantilla con el mismo id sustituye a la de serie.\n"
        )
        for template in templates:
            handle.write(template.declaration() + "\n")
    return path
