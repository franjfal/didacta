/// Traer lo que Didacta guardó cuando se llamaba es.uv.didacta.
///
/// Se prueba porque falla en silencio y del peor modo: nada da error, y quien
/// se actualiza se encuentra una instalación vacía --sin repositorios, sin
/// plantillas, en Windows sin sesión-- sin ninguna pista de por qué.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/legacy_identity_io.dart';
import 'package:didacta_app/model/toolchain.dart';

void main() {
  group('dónde estaba', () {
    test('en macOS, por el identificador', () {
      expect(
        legacyDataDirectory(Host.macos, {'HOME': '/Users/ana'}),
        '/Users/ana/Library/Application Support/es.uv.didacta',
      );
    });

    test('en Linux, en XDG_DATA_HOME si lo hay, y si no en ~/.local/share', () {
      expect(
        legacyDataDirectory(Host.linux, {'HOME': '/home/ana'}),
        '/home/ana/.local/share/es.uv.didacta',
      );
      expect(
        legacyDataDirectory(Host.linux, {
          'HOME': '/home/ana',
          'XDG_DATA_HOME': '/datos',
        }),
        '/datos/es.uv.didacta',
      );
    });

    test('en Windows, por el editor y el producto', () {
      expect(
        legacyDataDirectory(Host.windows, {
          'APPDATA': r'C:\Users\ana\AppData\Roaming',
        }),
        r'C:\Users\ana\AppData\Roaming\Universitat de València\Didacta',
      );
    });

    test('sin la variable que lo dice, no se inventa', () {
      expect(legacyDataDirectory(Host.macos, {}), isNull);
      expect(legacyDataDirectory(Host.windows, {}), isNull);
    });
  });

  group('traerlo', () {
    late Directory root;
    late Directory before;
    late Directory now;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('didacta-legacy-');
      before = Directory('${root.path}/es.uv.didacta');
      now = Directory('${root.path}/io.github.franjfal.didacta');
      await Directory(
        '${before.path}/templates/apuntes',
      ).create(recursive: true);
      File(
        '${before.path}/shared_preferences.json',
      ).writeAsStringSync('{"flutter.didacta.welcome.done":true}');
      File(
        '${before.path}/templates/templates.yaml',
      ).writeAsStringSync('antes');
      File(
        '${before.path}/templates/apuntes/header.tex',
      ).writeAsStringSync('% cabecera');
      await now.create();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('copia todo, con sus carpetas', () async {
      expect(await copyMissing(before, now), 3);
      expect(
        File('${now.path}/templates/apuntes/header.tex').readAsStringSync(),
        '% cabecera',
      );
      expect(File('${now.path}/shared_preferences.json').existsSync(), isTrue);
    });

    test('nunca encima de lo que ya hay', () async {
      // Quien ya ha empezado a usar esta versión tiene lo suyo, y es más
      // nuevo que lo de antes.
      await Directory('${now.path}/templates').create();
      File('${now.path}/templates/templates.yaml').writeAsStringSync('ahora');
      expect(await copyMissing(before, now), 2);
      expect(
        File('${now.path}/templates/templates.yaml').readAsStringSync(),
        'ahora',
      );
    });

    test('lo de antes se queda donde estaba', () async {
      // Una versión anterior de Didacta lo seguiría usando.
      await copyMissing(before, now);
      expect(
        File('${before.path}/templates/templates.yaml').existsSync(),
        isTrue,
      );
    });
  });
}
