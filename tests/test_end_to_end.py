"""El recorrido entero, sobre un repositorio de git de verdad.

Lo que se prueba aquí no es una pieza: es que las piezas encajan. Un tema
compartido entre tres cursos de dos asignaturas, editado desde cada uno,
congelado, dividido, vuelto a congelar, enviado a un remoto y clonado de
nuevo en otra carpeta. Cada paso comprueba lo que tiene que ser cierto
**después** de él, que es donde se ven los fallos que ninguna prueba de
unidad ve.

Las tres afirmaciones que sostiene:

* **vincular no copia**: editar desde una ubicación se ve desde las demás
  porque es el mismo fichero;
* **dividir separa de verdad**: después, cada grupo evoluciona solo;
* **una congelación enseña lo de entonces**: abierta después de dividir,
  sigue enseñando el grupo que había, porque los vínculos son los ficheros y
  los ficheros están en el commit.

Y la que las hace útiles: **un clon limpio lo reconstruye todo**, sin más
que leer lo que hay.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(ROOT, "engine"))

from didacta import freeze as freeze_mod  # noqa: E402
from didacta import identity as identity_mod  # noqa: E402
from didacta import repo as repo_mod  # noqa: E402
from didacta import reuse  # noqa: E402

CLI = os.path.join(ROOT, "cli", "didacta")

GIT_ENV = {
    "GIT_AUTHOR_NAME": "Semilla",
    "GIT_AUTHOR_EMAIL": "semilla@example.com",
    "GIT_COMMITTER_NAME": "Semilla",
    "GIT_COMMITTER_EMAIL": "semilla@example.com",
    "GIT_TERMINAL_PROMPT": "0",
}


def git(arguments, where):
    environment = dict(os.environ)
    environment.update(GIT_ENV)
    result = subprocess.run(
        ["git"] + arguments, cwd=where, env=environment,
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            "git %s: %s" % (" ".join(arguments), result.stderr.strip())
        )
    return result.stdout.strip()


def didacta(arguments, where):
    environment = dict(os.environ)
    environment["NO_COLOR"] = "1"
    result = subprocess.run(
        [sys.executable, CLI] + arguments, cwd=where, env=environment,
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            "didacta %s:\n%s\n%s"
            % (" ".join(arguments), result.stdout, result.stderr)
        )
    return result.stdout


class EndToEndTests(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix="didacta-e2e-")
        self.addCleanup(shutil.rmtree, self.base, ignore_errors=True)
        self.remote = os.path.join(self.base, "remote.git")
        self.work = os.path.join(self.base, "db")
        os.makedirs(self.work)

        git(["init", "--bare", "--initial-branch=main", self.remote], self.base)

        # Análisis Matemático, con dos cursos; Matemáticas, con uno.
        self.write("didacta.yaml",
                   "name: didacta_db\nlanguages: [es, va]\ndefault_language: es\n")
        self.write("courses/analisis/course.yaml",
                   "id: analisis\ntitle:\n  es: Análisis Matemático\n")
        self.write("courses/matematicas/course.yaml",
                   "id: matematicas\ntitle:\n  es: Matemáticas\n")
        for name in ("convergencia", "criterios"):
            self.write("content/analisis/series/%s/unit.yaml" % name,
                       "kind: theory\ntitle:\n  es: %s\n" % name)
            self.write("content/analisis/series/%s/es.tex" % name,
                       "el texto de %s\n" % name)

        self.write(
            "courses/analisis/2025-2026/year.yaml",
            "course: analisis\n"
            "year: 2025-2026\n"
            "language: es\n"
            "\n"
            "documents:\n"
            "  - id: series\n"
            "    kind: theory\n"
            "    themes: [t-series]\n"
            "    title:\n"
            "      es: Series\n"
            "      # TODO: va\n"
            "    structure:\n"
            "      - unit: analisis/series/convergencia\n"
            "      # - unit: analisis/series/criterios\n",
        )
        self.write("courses/analisis/2025-2026/themes.yaml",
                   "themes:\n  - id: t-series\n    title:\n      es: Series\n")
        self.master("analisis", "2025-2026", "series")
        for course, year in (("analisis", "2026-2027"),
                             ("matematicas", "2026-2027")):
            self.write("courses/%s/%s/year.yaml" % (course, year),
                       "course: %s\nyear: %s\nlanguage: es\n\ndocuments:\n"
                       % (course, year))

        didacta(["index"], self.work)
        git(["init", "--initial-branch=main"], self.work)
        git(["add", "."], self.work)
        git(["commit", "-m", "El material, para empezar"], self.work)
        git(["remote", "add", "origin", self.remote], self.work)
        git(["push", "-u", "origin", "main"], self.work)

    # -- utilidades --------------------------------------------------------

    def write(self, relpath, text, where=None):
        path = os.path.join(where or self.work, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def read(self, relpath, where=None):
        with open(os.path.join(where or self.work, relpath),
                  encoding="utf-8") as handle:
            return handle.read()

    def master(self, course, year, document):
        self.write(
            "courses/%s/%s/%s.tex" % (course, year, document),
            "\\input{didacta-bootstrap}\n"
            "\\usepackage{didacta}\n"
            "\\DidactaDocument{%s %s}\n"
            "\\begin{document}\n"
            "\\DidactaUnit{analisis/series/convergencia}\n"
            "\\end{document}\n" % (document, year),
        )

    def courses_in(self, where=None):
        where = where or self.work
        settings = repo_mod.Settings.load(where)
        courses, errors = repo_mod.scan_courses(where, settings)
        self.assertEqual(errors, [], "%s no se lee limpio" % where)
        return courses

    def document_in(self, course, year, document, where=None):
        found = self.courses_in(where)[course].years[year].documents
        return next(item for item in found if item.id == document)

    def commit(self, message):
        git(["add", "-A"], self.work)
        git(["commit", "-m", message], self.work)
        return git(["rev-parse", "HEAD"], self.work)

    def at_commit(self, sha):
        """Un árbol de trabajo parado en un commit, como abre una congelación."""
        where = os.path.join(self.base, "frozen-%s" % sha[:7])
        if not os.path.isdir(where):
            git(["worktree", "add", "--detach", "--quiet", where, sha],
                self.work)
        return where

    def edit_shared(self, content, old, new):
        """Un cambio en el fichero compartido, como lo haría el editor."""
        path = os.path.join(self.work, "shared/documents/%s.yaml" % content)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn(old, text)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text.replace(old, new))

    # -- el recorrido ------------------------------------------------------

    def test_the_whole_thing(self):
        # 1. El mismo tema en los tres cursos, vinculado.
        didacta(["link", "--from", "analisis@2025-2026/series",
                 "--to", "analisis@2026-2027"], self.work)
        didacta(["link", "--from", "analisis@2025-2026/series",
                 "--to", "matematicas@2026-2027"], self.work)

        content = self.document_in("analisis", "2025-2026", "series").content
        self.assertTrue(identity_mod.is_id(content))
        places = reuse.document_places(self.courses_in(), content)
        self.assertEqual([place.key for place in places],
                         ["analisis@2025-2026/series",
                          "analisis@2026-2027/series",
                          "matematicas@2026-2027/series"])

        # No se ha copiado contenido: los tres `year.yaml` llevan una línea.
        for course, year in (("analisis", "2026-2027"),
                             ("matematicas", "2026-2027")):
            text = self.read("courses/%s/%s/year.yaml" % (course, year))
            self.assertIn("link: %s" % content, text)
            self.assertNotIn("unit: analisis/series/convergencia", text)

        # Y los comentarios de quien compuso el curso siguen ahí.
        shared = self.read("shared/documents/%s.yaml" % content)
        self.assertIn("# TODO: va", shared)
        self.assertIn("# - unit: analisis/series/criterios", shared)

        didacta(["index"], self.work)
        first = self.commit("Dar Series también en 2026-2027 y en Matemáticas")

        # 2. Editarlo desde cada ubicación, y verlo desde las demás.
        self.edit_shared(content, "  es: Series", "  es: Series numéricas")
        for course, year in (("analisis", "2025-2026"),
                             ("analisis", "2026-2027"),
                             ("matematicas", "2026-2027")):
            self.assertEqual(
                self.document_in(course, year, "series").titles["es"],
                "Series numéricas",
                "editar desde un sitio tiene que verse desde %s %s"
                % (course, year),
            )

        # Añadir una lección al tema se ve en los tres. Es el cambio
        # estructural: si esto no se propaga, no están vinculados de verdad.
        self.edit_shared(
            content,
            "  - unit: analisis/series/convergencia",
            "  - unit: analisis/series/convergencia\n"
            "  - unit: analisis/series/criterios",
        )
        for course, year in (("analisis", "2025-2026"),
                             ("analisis", "2026-2027"),
                             ("matematicas", "2026-2027")):
            self.assertEqual(
                self.document_in(course, year, "series").unit_refs,
                ["analisis/series/convergencia", "analisis/series/criterios"],
            )

        didacta(["index"], self.work)
        before = self.commit("Series: el título y una lección más")

        # 3. Congelar **antes** de dividir.
        didacta(["freeze", "add", "analisis@2025-2026",
                 "--name", "Antes de dividir",
                 "--commit", before], self.work)
        self.commit("Congelar «Antes de dividir»")

        # 4. Dividir: Análisis por un lado, Matemáticas por otro.
        didacta(["split", "--content", content,
                 "--group", "matematicas@2026-2027/series"], self.work)
        didacta(["index"], self.work)
        after = self.commit("Separar Series de Matemáticas del de Análisis")

        # Los dos grupos existen y no se hablan.
        self.assertEqual(
            self.document_in("analisis", "2025-2026", "series").content, content)
        self.assertEqual(
            self.document_in("analisis", "2026-2027", "series").content, content)
        # Un grupo de uno no es un grupo: su tema vuelve a estar escrito en su
        # curso.
        self.assertIsNone(
            self.document_in("matematicas", "2026-2027", "series").content)
        self.assertIn("unit: analisis/series/convergencia",
                      self.read("courses/matematicas/2026-2027/year.yaml"))

        # 5. Cada rama evoluciona sola.
        self.edit_shared(content, "  es: Series numéricas",
                         "  es: Series, solo en Análisis")
        for year in ("2025-2026", "2026-2027"):
            self.assertEqual(
                self.document_in("analisis", year, "series").titles["es"],
                "Series, solo en Análisis")
        self.assertEqual(
            self.document_in("matematicas", "2026-2027", "series").titles["es"],
            "Series numéricas")

        didacta(["index"], self.work)
        self.commit("Series: retocar el título en Análisis")

        # 6. Congelar **después** de dividir.
        head = git(["rev-parse", "HEAD"], self.work)
        didacta(["freeze", "add", "analisis@2025-2026",
                 "--name", "Después de dividir",
                 "--commit", head], self.work)
        self.commit("Congelar «Después de dividir»")

        freezes = freeze_mod.load(
            os.path.join(self.work, "courses/analisis/2025-2026"),
            "analisis", "2025-2026")
        self.assertEqual([item.name for item in freezes],
                         ["Antes de dividir", "Después de dividir"])

        # 7. Abrir las dos congelaciones y comprobar que dicen lo que había.
        old = self.at_commit(before)
        self.assertEqual(
            self.document_in("matematicas", "2026-2027", "series", old).content,
            content,
            "la congelación antigua tiene que enseñar los tres vinculados",
        )
        old_places = reuse.document_places(self.courses_in(old), content)
        self.assertEqual(len(old_places), 3)

        new = self.at_commit(after)
        self.assertIsNone(
            self.document_in("matematicas", "2026-2027", "series", new).content,
            "la congelación nueva tiene que enseñar la división",
        )
        self.assertEqual(
            len(reuse.document_places(self.courses_in(new), content)), 2)

        # Y el curso de ahora sigue siendo el de ahora.
        self.assertEqual(
            len(reuse.document_places(self.courses_in(), content)), 2)

        # 8. Quitar una congelación no se lleva ningún commit.
        gone = freezes[0]
        didacta(["freeze", "remove", "analisis@2025-2026", gone.id], self.work)
        self.commit("Quitar «Antes de dividir»")
        self.assertEqual(
            git(["cat-file", "-t", "%s^{commit}" % before], self.work),
            "commit",
        )
        self.assertEqual(
            [item.name for item in freeze_mod.load(
                os.path.join(self.work, "courses/analisis/2025-2026"))],
            ["Después de dividir"],
        )

        # 9. Enviar, clonar limpio y comprobar que se reconstruye todo.
        git(["push"], self.work)
        fresh = os.path.join(self.base, "fresh")
        git(["clone", "--branch", "main", self.remote, fresh], self.base)

        rebuilt = self.courses_in(fresh)
        self.assertEqual(
            [place.key
             for place in reuse.document_places(rebuilt, content)],
            ["analisis@2025-2026/series", "analisis@2026-2027/series"],
        )
        self.assertEqual(
            self.document_in("analisis", "2026-2027", "series", fresh)
                .titles["es"],
            "Series, solo en Análisis",
        )
        self.assertIsNone(
            self.document_in("matematicas", "2026-2027", "series", fresh)
                .content)
        self.assertEqual(
            [item.name for item in freeze_mod.load(
                os.path.join(fresh, "courses/analisis/2025-2026"))],
            ["Después de dividir"],
        )

        # 10. Y el clon limpio se lee sin quejas.
        didacta(["check"], fresh)

    def test_a_pull_brings_the_links_someone_else_made(self):
        """Nada de esto depende de que lo haya hecho esta aplicación.

        Los ficheros pueden cambiar desde GitHub, desde otro ordenador o a
        mano. Lo único que hace falta es volver a leerlos.
        """
        other = os.path.join(self.base, "otro")
        git(["clone", "--branch", "main", self.remote, other], self.base)

        didacta(["link", "--from", "analisis@2025-2026/series",
                 "--to", "matematicas@2026-2027"], other)
        didacta(["index"], other)
        git(["add", "-A"], other)
        git(["commit", "-m", "Dar Series también en Matemáticas"], other)
        git(["push"], other)

        # Aquí todavía no se sabe nada de eso.
        self.assertIsNone(
            self.document_in("analisis", "2025-2026", "series").content)

        git(["pull", "--ff-only"], self.work)
        content = self.document_in("analisis", "2025-2026", "series").content
        self.assertTrue(identity_mod.is_id(content))
        self.assertEqual(
            len(reuse.document_places(self.courses_in(), content)), 2)
        didacta(["check"], self.work)

    def test_ids_survive_a_round_trip(self):
        """La migración, con un remoto de por medio.

        Dos personas que pongan al día el mismo repositorio por su cuenta
        tienen que escribir los mismos ids, o el merge trae dos identidades
        para la misma lección.
        """
        other = os.path.join(self.base, "otro")
        git(["clone", "--branch", "main", self.remote, other], self.base)

        here = didacta(["ids", "--apply"], self.work)
        there = didacta(["ids", "--apply"], other)
        mine = sorted(line.split()[-1] for line in here.split("\n")
                      if line.startswith("  content/"))
        theirs = sorted(line.split()[-1] for line in there.split("\n")
                        if line.startswith("  content/"))
        self.assertEqual(mine, theirs)
        self.assertTrue(mine)

        # Y lo escrito es lo que el motor usa.
        settings = repo_mod.Settings.load(self.work)
        units, _ = repo_mod.scan_units(self.work, settings)
        for unit in units.values():
            self.assertTrue(identity_mod.is_id(unit.id), unit.relpath)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
