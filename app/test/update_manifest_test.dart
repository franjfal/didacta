/// Que el manifiesto se lea bien, y sobre todo que se lea **mal** bien.
///
/// Este fichero viene de la red y decide qué binario se ejecuta en la
/// máquina de alguien. Así que la mitad de los tests son sobre lo que tiene
/// que rechazar: un asset sin SHA-256, un JSON que no es un objeto, una
/// versión que no es una versión. La regla que comprueban es una sola: ante
/// la duda, no hay actualización.
library;

import 'dart:convert';

import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un SHA-256 cualquiera, con la forma que se exige.
const String hash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

Map<String, dynamic> asset({
  String platform = 'macos',
  String architecture = 'universal',
  String kind = 'update',
  String name = 'Didacta-1.4.2-macos-universal.zip',
  int size = 1024,
  String? sha = hash,
  int id = 101,
}) => {
  'platform': platform,
  'architecture': architecture,
  'kind': kind,
  'name': name,
  'size': size,
  'sha256': ?sha,
  'assetId': id,
};

String manifestJson({
  String version = '1.4.2',
  List<Map<String, dynamic>>? assets,
  String? minimum,
}) => jsonEncode({
  'version': version,
  'build': 142,
  'tag': 'v$version',
  'publishedAt': '2026-09-15T10:00:00Z',
  'releaseNotes': '- Nueva funcionalidad\n- Corregido algo',
  'minimumSupportedVersion': ?minimum,
  'assets': assets ?? [asset()],
});

void main() {
  group('leer el manifiesto', () {
    test('uno completo', () {
      final manifest = UpdateManifest.tryParse(manifestJson())!;
      expect(manifest.version, AppVersion.parse('1.4.2'));
      expect(manifest.build, 142);
      expect(manifest.tag, 'v1.4.2');
      expect(manifest.releaseNotes, contains('Nueva funcionalidad'));
      expect(manifest.publishedAt.toUtc().year, 2026);
      expect(manifest.assets, hasLength(1));
      expect(manifest.assets.single.assetId, 101);
    });

    test('lo que no se entiende da null, no una excepción', () {
      // Sube hasta la interfaz, y allí lo que toca es «no se pudo
      // comprobar», no una pantalla roja.
      for (final bad in ['', 'null', '[]', '{', 'no soy json', '"texto"']) {
        expect(UpdateManifest.tryParse(bad), isNull, reason: '«$bad»');
      }
    });

    test('sin una versión válida no hay manifiesto', () {
      expect(UpdateManifest.tryParse(manifestJson(version: 'latest')), isNull);
    });

    test('un asset sin SHA-256 se descarta', () {
      // La regla dura: el manifiesto es de donde sale la única garantía de
      // integridad que hay, y «no venía» no puede significar «pues adelante».
      final manifest = UpdateManifest.tryParse(
        manifestJson(assets: [asset(sha: null)]),
      )!;
      expect(manifest.assets, isEmpty);
    });

    test('un SHA-256 con mala pinta también', () {
      for (final bad in [
        'abc',
        'sha256:$hash',
        hash.toUpperCase().substring(1),
      ]) {
        final manifest = UpdateManifest.tryParse(
          manifestJson(assets: [asset(sha: bad)]),
        )!;
        expect(manifest.assets, isEmpty, reason: bad);
      }
    });

    test('en mayúsculas sí vale: se normaliza', () {
      final manifest = UpdateManifest.tryParse(
        manifestJson(assets: [asset(sha: hash.toUpperCase())]),
      )!;
      expect(manifest.assets.single.sha256, hash);
    });

    test('un asset roto no se lleva por delante a los demás', () {
      // Que el de Windows venga mal no puede dejar sin actualización a macOS.
      final manifest = UpdateManifest.tryParse(
        manifestJson(
          assets: [
            asset(platform: 'windows', sha: null),
            asset(platform: 'macos'),
          ],
        ),
      )!;
      expect(manifest.assets, hasLength(1));
      expect(manifest.assets.single.platform, UpdatePlatform.macos);
    });

    test('una plataforma desconocida se ignora', () {
      final manifest = UpdateManifest.tryParse(
        manifestJson(assets: [asset(platform: 'haiku')]),
      )!;
      expect(manifest.assets, isEmpty);
    });

    test('ida y vuelta', () {
      final original = UpdateManifest.tryParse(manifestJson())!;
      final again = UpdateManifest.tryParse(jsonEncode(original.toJson()))!;
      expect(again.version, original.version);
      expect(again.assets.single.sha256, original.assets.single.sha256);
      expect(again.assets.single.assetId, original.assets.single.assetId);
    });
  });

  group('elegir el artefacto', () {
    UpdateManifest full() => UpdateManifest.tryParse(
      manifestJson(
        assets: [
          asset(
            platform: 'macos',
            architecture: 'universal',
            kind: 'installer',
            name: 'Didacta-1.4.2-macos-universal.dmg',
            id: 1,
          ),
          asset(
            platform: 'macos',
            architecture: 'universal',
            kind: 'update',
            name: 'Didacta-1.4.2-macos-universal.zip',
            id: 2,
          ),
          asset(
            platform: 'windows',
            architecture: 'x64',
            kind: 'installer',
            name: 'Didacta-1.4.2-windows-x64.exe',
            id: 3,
          ),
          asset(
            platform: 'linux',
            architecture: 'x64',
            kind: 'installer',
            name: 'Didacta-1.4.2-linux-x64.AppImage',
            id: 4,
          ),
        ],
      ),
    )!;

    test('macOS coge el ZIP para actualizar y el DMG para instalar', () {
      // Los dos son «el de macOS»; sin el campo `kind` no habría forma de
      // saber cuál es cuál, y el actualizador acabaría montando un DMG.
      final manifest = full();
      expect(manifest.updateFor(UpdatePlatform.macos, 'arm64')!.assetId, 2);
      expect(manifest.installerFor(UpdatePlatform.macos, 'arm64')!.assetId, 1);
    });

    test('universal sirve para arm64 y para x64', () {
      final manifest = full();
      expect(manifest.updateFor(UpdatePlatform.macos, 'arm64')!.assetId, 2);
      expect(manifest.updateFor(UpdatePlatform.macos, 'x64')!.assetId, 2);
    });

    test('la arquitectura exacta gana al universal', () {
      final manifest = UpdateManifest.tryParse(
        manifestJson(
          assets: [
            asset(architecture: 'universal', id: 10),
            asset(architecture: 'arm64', id: 11),
          ],
        ),
      )!;
      expect(manifest.updateFor(UpdatePlatform.macos, 'arm64')!.assetId, 11);
      expect(manifest.updateFor(UpdatePlatform.macos, 'x64')!.assetId, 10);
    });

    test('donde solo hay instalador, el instalador vale para actualizar', () {
      // Es el caso de Windows y de Linux: allí el fichero es el mismo.
      final manifest = full();
      expect(manifest.updateFor(UpdatePlatform.windows, 'x64')!.assetId, 3);
      expect(manifest.updateFor(UpdatePlatform.linux, 'x64')!.assetId, 4);
    });

    test('si no hay nada para ese sistema, null', () {
      // Un release al que le faltó una plataforma es un release incompleto,
      // no un fallo de la aplicación: se dice y se sigue.
      final manifest = UpdateManifest.tryParse(
        manifestJson(assets: [asset(platform: 'macos')]),
      )!;
      expect(manifest.updateFor(UpdatePlatform.linux, 'x64'), isNull);
    });

    test('una arquitectura que no está tampoco se inventa', () {
      final manifest = UpdateManifest.tryParse(
        manifestJson(
          assets: [asset(platform: 'linux', architecture: 'x64')],
        ),
      )!;
      expect(manifest.updateFor(UpdatePlatform.linux, 'arm64'), isNull);
    });
  });

  group('versión mínima', () {
    test('por debajo pide reinstalar', () {
      final manifest = UpdateManifest.tryParse(manifestJson(minimum: '1.2.0'))!;
      expect(
        manifest.needsFullReinstallFrom(AppVersion.parse('1.1.9')),
        isTrue,
      );
      expect(
        manifest.needsFullReinstallFrom(AppVersion.parse('1.2.0')),
        isFalse,
      );
    });

    test('sin mínimo declarado, nunca', () {
      final manifest = UpdateManifest.tryParse(manifestJson())!;
      expect(
        manifest.needsFullReinstallFrom(AppVersion.parse('0.0.1')),
        isFalse,
      );
    });
  });
}
