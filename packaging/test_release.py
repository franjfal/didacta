#!/usr/bin/env python3
"""Los tests de la herramienta de publicación.

Lo que comprueban es lo que se rompe callado: que el `latest.json` lleve el
identificador de cada asset, que un artefacto con un nombre que no se reconoce
**no se cuele** en el manifiesto, y que publicar sin sección del CHANGELOG
falle antes de compilar nada.

Nada de esto se ve mirando el YAML del workflow, que es la razón de que la
lógica no esté ahí dentro.

    python3 -m unittest discover -s packaging -p 'test_*.py' -v
"""

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import portal  # noqa: E402
import release  # noqa: E402


HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


class VersionTest(unittest.TestCase):
    """La versión sale de pubspec.yaml y de ningún otro sitio."""

    def setUp(self):
        self.temp = tempfile.mkdtemp()
        self.pubspec = os.path.join(self.temp, "pubspec.yaml")
        self.original = release.PUBSPEC
        release.PUBSPEC = self.pubspec

    def tearDown(self):
        release.PUBSPEC = self.original
        shutil.rmtree(self.temp, ignore_errors=True)

    def write(self, text):
        with open(self.pubspec, "w") as handle:
            handle.write(text)

    def test_la_forma_normal(self):
        self.write("name: didacta_app\nversion: 1.4.2+142\n")
        self.assertEqual(release.read_version(), ("1.4.2", 142))

    def test_sin_build(self):
        self.write("version: 1.4.2\n")
        self.assertEqual(release.read_version(), ("1.4.2", 0))

    def test_una_preliberacion(self):
        self.write("version: 1.4.2-rc.1+7\n")
        self.assertEqual(release.read_version(), ("1.4.2-rc.1", 7))

    def test_una_version_que_no_es_semantica_no_se_publica(self):
        # El fallo que esto coge: `version: 1.4` compila perfectamente y
        # produce un tag `v1.4` que la aplicación no sabe comparar, así que
        # deja de ofrecer actualizaciones sin decir nada.
        for bad in ["1.4", "1.4.2.3", "latest", "v1.4.2", "1.x.2"]:
            self.write("version: %s+1\n" % bad)
            with self.assertRaises(release.Problem, msg=bad):
                release.read_version()

    def test_un_build_que_no_es_un_numero(self):
        self.write("version: 1.4.2+beta\n")
        with self.assertRaises(release.Problem):
            release.read_version()

    def test_sin_linea_de_version(self):
        self.write("name: didacta_app\n")
        with self.assertRaises(release.Problem):
            release.read_version()


class BumpTest(unittest.TestCase):
    """Lo que sube una publicación.

    Es la parte con más consecuencias de todo esto: el número que salga de
    aquí queda en un tag, en el nombre de cuatro artefactos y en lo que cada
    instalación compara para decidir si se actualiza. No hay forma de
    corregirlo después.
    """

    def setUp(self):
        self.temp = tempfile.mkdtemp()
        self.pubspec = os.path.join(self.temp, "pubspec.yaml")
        self.original = release.PUBSPEC
        release.PUBSPEC = self.pubspec

    def tearDown(self):
        release.PUBSPEC = self.original
        shutil.rmtree(self.temp, ignore_errors=True)

    def write(self, text):
        with open(self.pubspec, "w") as handle:
            handle.write(text)

    def read(self):
        with open(self.pubspec) as handle:
            return handle.read()

    def test_publicar_sube_la_mediana(self):
        # La regla del ciclo, y la razón de que esto exista.
        self.assertEqual(release.next_version("1.1.0"), "1.2.0")
        self.assertEqual(release.next_version("1.0.0"), "1.1.0")

    def test_el_parche_vuelve_a_cero(self):
        # 1.4.2 → 1.5.0 y no 1.5.2: lo que la mediana dice es «otra tanda de
        # cambios», y arrastrar el parche de la anterior no significa nada.
        self.assertEqual(release.next_version("1.4.2"), "1.5.0")

    def test_la_mediana_no_arrastra_a_la_mayor(self):
        # 1.9.0 → 1.10.0, no 2.0.0. Es la comparación que la aplicación hace
        # semánticamente y no como texto, justo para que esto funcione.
        self.assertEqual(release.next_version("1.9.0"), "1.10.0")
        self.assertEqual(release.next_version("1.10.0"), "1.11.0")

    def test_las_otras_dos_partes_siguen_a_mano(self):
        self.assertEqual(release.next_version("1.4.2", "major"), "2.0.0")
        self.assertEqual(release.next_version("1.4.2", "patch"), "1.4.3")

    def test_una_preliberacion_publica_como_su_final(self):
        # El caso sin respuesta obvia, y por eso no se adivina: subir la
        # mediana de `1.5.0-rc.1` daría `1.6.0` y dejaría un `1.5.0` que
        # nunca existió.
        self.assertEqual(release.next_version("1.5.0-rc.1"), "1.5.0")
        self.assertEqual(release.next_version("1.5.0-rc.1", "major"), "1.5.0")

    def test_una_version_que_no_es_semantica_no_se_sube(self):
        with self.assertRaises(release.Problem):
            release.next_version("1.4")

    def test_una_parte_que_no_existe_se_dice(self):
        with self.assertRaises(release.Problem):
            release.next_version("1.4.2", "mediana")

    def test_bump_escribe_la_version_y_sube_el_build(self):
        self.write("name: didacta_app\nversion: 1.1.0+7\n\nenvironment:\n")
        self.assertEqual(release.bump(), ("1.1.0", "1.2.0", 8))
        self.assertEqual(release.read_version(), ("1.2.0", 8))

    def test_bump_no_toca_nada_más_del_fichero(self):
        # `pubspec.yaml` lleva quince líneas de comentarios de Flutter
        # explicando qué es cada campo. Reescribirlo con un parser de YAML se
        # las llevaría por delante sin que nadie lo notara hasta leerlo.
        original = (
            "name: didacta_app\n"
            "# A version number is three numbers separated by dots\n"
            "version: 1.1.0+7\n"
            "\n"
            "environment:\n"
            "  sdk: ^3.12.2\n"
        )
        self.write(original)
        release.bump()
        self.assertEqual(
            self.read(), original.replace("1.1.0+7", "1.2.0+8"))

    def test_bump_sin_linea_de_version(self):
        self.write("name: didacta_app\n")
        with self.assertRaises(release.Problem):
            release.bump()

    def test_los_cuatro_trabajos_llegan_al_mismo_numero(self):
        """La invariante de la que depende el workflow.

        macOS, Windows, Linux y el trabajo que publica ejecutan `bump` cada
        uno sobre su propia copia del repositorio, sin pasarse nada entre
        ellos. Si dos llegaran a números distintos, se publicaría un release
        con artefactos de dos versiones y nadie lo vería hasta instalarlo.
        """
        numbers = set()
        for index in range(4):
            copy = os.path.join(self.temp, "copia-%d.yaml" % index)
            with open(copy, "w") as handle:
                handle.write("name: didacta_app\nversion: 1.1.0+7\n")
            release.PUBSPEC = copy
            numbers.add(release.bump())
        self.assertEqual(numbers, {("1.1.0", "1.2.0", 8)})

    def test_el_ciclo_entero_no_repite_ni_salta_un_numero(self):
        # Cuatro publicaciones seguidas, como pasaría de verdad: cada una
        # sobre lo que dejó la anterior.
        self.write("version: 1.0.0+1\n")
        seen = []
        for _ in range(4):
            _, after, build = release.bump()
            seen.append((after, build))
        self.assertEqual(
            seen, [("1.1.0", 2), ("1.2.0", 3), ("1.3.0", 4), ("1.4.0", 5)])


class ChangelogTest(unittest.TestCase):
    """Publicar sin decir qué cambia no se puede."""

    def setUp(self):
        self.temp = tempfile.mkdtemp()
        self.changelog = os.path.join(self.temp, "CHANGELOG.md")
        self.original = release.CHANGELOG
        release.CHANGELOG = self.changelog

    def tearDown(self):
        release.CHANGELOG = self.original
        shutil.rmtree(self.temp, ignore_errors=True)

    def write(self, text):
        with open(self.changelog, "w") as handle:
            handle.write(text)

    def test_saca_la_seccion_y_solo_la_suya(self):
        self.write(
            "# Cambios\n\n"
            "## 1.4.2 — 2026-09-15\n\n"
            "- Lo nuevo\n"
            "- Lo corregido\n\n"
            "## 1.4.1 — 2026-08-01\n\n"
            "- Lo de antes\n"
        )
        notes = release.read_notes("1.4.2")
        self.assertIn("Lo nuevo", notes)
        self.assertIn("Lo corregido", notes)
        self.assertNotIn("Lo de antes", notes)
        # Y sin arrastrar su propio encabezado, que en el diálogo de la
        # aplicación saldría repetido justo debajo del título.
        self.assertNotIn("## 1.4.2", notes)

    def test_la_ultima_seccion_llega_hasta_el_final(self):
        self.write("# Cambios\n\n## 1.0.0\n\n- La primera\n")
        self.assertEqual(release.read_notes("1.0.0"), "- La primera")

    def test_sin_seccion_falla_y_dice_cómo_arreglarlo(self):
        self.write("# Cambios\n\n## 1.4.1\n\n- Lo de antes\n")
        with self.assertRaises(release.Problem) as caught:
            release.read_notes("1.4.2")
        # El mensaje tiene que traer la plantilla: este error sale en mitad de
        # una publicación y hay que poder arreglarlo sin ir a buscar nada.
        self.assertIn("## 1.4.2", str(caught.exception))

    def test_una_seccion_vacia_tampoco_vale(self):
        self.write("# Cambios\n\n## 1.4.2\n\n## 1.4.1\n\n- Algo\n")
        with self.assertRaises(release.Problem):
            release.read_notes("1.4.2")

    def test_acepta_la_v_delante(self):
        self.write("# Cambios\n\n## v1.4.2\n\n- Algo\n")
        self.assertEqual(release.read_notes("1.4.2"), "- Algo")


class ClassifyTest(unittest.TestCase):
    """El nombre del artefacto es el contrato."""

    def test_cada_artefacto_a_lo_suyo(self):
        self.assertEqual(
            release.classify("Didacta-1.4.2-macos-universal.dmg"),
            ("macos", "universal", "installer"),
        )
        # El ZIP de macOS es el del actualizador, no el instalador. Sin esta
        # distinción el actualizador acabaría intentando montar un DMG.
        self.assertEqual(
            release.classify("Didacta-1.4.2-macos-universal.zip"),
            ("macos", "universal", "update"),
        )
        self.assertEqual(
            release.classify("Didacta-1.4.2-windows-x64.exe"),
            ("windows", "x64", "installer"),
        )
        self.assertEqual(
            release.classify("Didacta-1.4.2-linux-x64.AppImage"),
            ("linux", "x64", "installer"),
        )

    def test_la_arquitectura_sale_del_nombre(self):
        # Añadir un AppImage de arm64 no debe obligar a tocar la tabla.
        self.assertEqual(
            release.classify("Didacta-1.4.2-linux-arm64.AppImage"),
            ("linux", "arm64", "installer"),
        )

    def test_lo_que_no_es_un_artefacto_no_lo_es(self):
        for name in ["latest.json", "SHA256SUMS.txt", "notas.md", "README.md"]:
            self.assertIsNone(release.classify(name), name)


class ManifestTest(unittest.TestCase):
    """El manifiesto es lo que decide qué binario se ejecuta en otra máquina."""

    def uploaded(self, **overrides):
        item = {
            "name": "Didacta-1.4.2-macos-universal.zip",
            "size": 1024,
            "id": 77,
            "sha256": HASH,
        }
        item.update(overrides)
        return item

    def test_lleva_el_identificador_del_asset(self):
        # La pieza que lo hace todo posible: con el `id` se descarga con un
        # `Authorization:`, que es lo único compatible con un repositorio
        # privado. Una URL pública no serviría.
        manifest = release.build_manifest(
            "1.4.2", 142, "- Algo", [self.uploaded()]
        )
        self.assertEqual(manifest["assets"][0]["assetId"], 77)
        self.assertEqual(manifest["assets"][0]["sha256"], HASH)
        self.assertEqual(manifest["tag"], "v1.4.2")
        self.assertTrue(manifest["publishedAt"].endswith("Z"))

    def test_sin_sha256_no_se_publica(self):
        # La regla dura: sin checksum no hay manifiesto, porque sin checksum
        # la aplicación no tendría con qué comprobar lo que descarga.
        with self.assertRaises(release.Problem):
            release.build_manifest(
                "1.4.2", 142, "- Algo", [self.uploaded(sha256=None)]
            )

    def test_lo_que_no_es_un_artefacto_se_queda_fuera(self):
        manifest = release.build_manifest(
            "1.4.2",
            142,
            "- Algo",
            [
                self.uploaded(),
                {"name": "latest.json", "size": 10, "id": 1, "sha256": HASH},
                {"name": "SHA256SUMS.txt", "size": 10, "id": 2, "sha256": HASH},
            ],
        )
        self.assertEqual(len(manifest["assets"]), 1)

    def test_un_release_sin_artefactos_falla(self):
        with self.assertRaises(release.Problem):
            release.build_manifest("1.4.2", 142, "- Algo", [])

    def test_la_version_minima_solo_si_se_pide(self):
        sin = release.build_manifest("1.4.2", 142, "-", [self.uploaded()])
        self.assertNotIn("minimumSupportedVersion", sin)
        con = release.build_manifest(
            "1.4.2", 142, "-", [self.uploaded()], minimum="1.2.0"
        )
        self.assertEqual(con["minimumSupportedVersion"], "1.2.0")

    def test_los_cuatro_artefactos_de_un_release_completo(self):
        names = [
            ("Didacta-1.4.2-macos-universal.dmg", 1),
            ("Didacta-1.4.2-macos-universal.zip", 2),
            ("Didacta-1.4.2-windows-x64.exe", 3),
            ("Didacta-1.4.2-linux-x64.AppImage", 4),
        ]
        manifest = release.build_manifest(
            "1.4.2",
            142,
            "- Algo",
            [self.uploaded(name=name, id=id_) for name, id_ in names],
        )
        kinds = {(a["platform"], a["kind"]) for a in manifest["assets"]}
        self.assertEqual(
            kinds,
            {
                ("macos", "installer"),
                ("macos", "update"),
                ("windows", "installer"),
                ("linux", "installer"),
            },
        )


class ChecksumTest(unittest.TestCase):
    def test_el_sha256_de_un_fichero(self):
        temp = tempfile.mkdtemp()
        try:
            path = os.path.join(temp, "Didacta-1.4.2-linux-x64.AppImage")
            with open(path, "wb") as handle:
                handle.write(b"")
            # El SHA-256 del fichero vacío, que es una constante conocida.
            self.assertEqual(release.sha256_of(path), HASH)
        finally:
            shutil.rmtree(temp, ignore_errors=True)


class PortalTest(unittest.TestCase):
    """La página de descarga."""

    def manifest(self):
        return {
            "version": "1.4.2",
            "tag": "v1.4.2",
            "publishedAt": "2026-09-15T10:00:00Z",
            "releaseNotes": "- Lo nuevo\n- Lo corregido",
            "assets": [
                {
                    "platform": "macos",
                    "architecture": "universal",
                    "kind": "installer",
                    "name": "Didacta-1.4.2-macos-universal.dmg",
                    "size": 94 * 1024 * 1024,
                    "sha256": HASH,
                    "assetId": 1,
                },
                {
                    "platform": "macos",
                    "architecture": "universal",
                    "kind": "update",
                    "name": "Didacta-1.4.2-macos-universal.zip",
                    "size": 90 * 1024 * 1024,
                    "sha256": HASH,
                    "assetId": 2,
                },
                {
                    "platform": "windows",
                    "architecture": "x64",
                    "kind": "installer",
                    "name": "Didacta-1.4.2-windows-x64.exe",
                    "size": 40 * 1024 * 1024,
                    "sha256": HASH,
                    "assetId": 3,
                },
            ],
        }

    def test_enseña_la_version_y_las_novedades(self):
        page = portal.render(self.manifest())
        self.assertIn("## Última versión: 1.4.2", page)
        self.assertIn("Lo nuevo", page)
        self.assertIn("2026-09-15", page)

    def test_un_enlace_por_instalador_y_ninguno_al_zip(self):
        # El ZIP es del actualizador. Ofrecerlo en la página de descarga sería
        # darle a alguien un fichero que no sabe qué hacer con él.
        page = portal.render(self.manifest())
        self.assertIn("Didacta-1.4.2-macos-universal.dmg", page)
        self.assertIn("Didacta-1.4.2-windows-x64.exe", page)
        self.assertNotIn("macos-universal.zip", page)

    def test_un_sistema_que_falta_sale_como_que_falta(self):
        # Y no desaparece de la tabla: «no hay para Linux» es información.
        page = portal.render(self.manifest())
        self.assertIn("| Linux | — | — |", page)

    def test_los_enlaces_son_del_repositorio_privado(self):
        page = portal.render(self.manifest())
        self.assertIn(
            "https://github.com/franjfal/didacta_public/releases/download/"
            "v1.4.2/Didacta-1.4.2-macos-universal.dmg",
            page,
        )

    def test_enseña_los_checksums(self):
        self.assertIn(HASH, portal.render(self.manifest()))

    def test_explica_que_la_contraseña_no_se_escribe_en_didacta(self):
        page = portal.render(self.manifest())
        self.assertIn("github.com/login/device", page)


if __name__ == "__main__":
    unittest.main()
