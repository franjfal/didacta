/// Que la aplicación se entere del disco **mientras está abierta**.
///
/// Esto existe por un caso real y distinto del de arranque: el índice se
/// regeneró desde el terminal con la aplicación abierta, la comprobación de
/// arranque no tenía nada que decir --el índice estaba al día respecto al
/// contenido-- y la biblioteca siguió enseñando lo que había leído media hora
/// antes. Lo que no se miraba era si el índice **en sí** había cambiado
/// después de leerlo.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/disk_watch.dart';

import 'fixture.dart';

/// Un clon con su `generated/`, para tocarle la fecha al índice.
Directory seed() {
  final root = Directory.systemTemp.createTempSync('didacta-watch-');
  Directory('${root.path}/generated').createSync();
  File(
    '${root.path}/generated/manifest.json',
  ).writeAsStringSync('{"counts": {"units": 0}}');
  return root;
}

void main() {
  group('la fecha del índice', () {
    test('se lee, y dice cuándo se escribió', () async {
      final root = seed();
      addTearDown(() => root.deleteSync(recursive: true));
      expect(await indexModified(root.path), isNotNull);
    });

    test('sin índice no hay fecha, y eso no es un error', () async {
      final root = Directory.systemTemp.createTempSync('didacta-sin-');
      addTearDown(() => root.deleteSync(recursive: true));
      expect(await indexModified(root.path), isNull);
    });
  });

  group('al volver a la ventana', () {
    test('un índice reescrito por fuera se vuelve a leer', () async {
      // El caso exacto: `didacta index` desde el terminal con la aplicación
      // abierta. El índice no está viejo respecto al contenido --acaba de
      // generarse-- así que la comprobación de arranque no diría nada.
      final root = seed();
      addTearDown(() => root.deleteSync(recursive: true));

      final compiler = FakeCompiler();
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        compilerOverride: compiler,
      );
      await session.useCloneForTest(root.path);
      await session.checkDisk();
      final before = session.reloads;

      // Alguien regenera el índice.
      final later = DateTime.now().add(const Duration(seconds: 5));
      File('${root.path}/generated/manifest.json').setLastModifiedSync(later);

      await session.checkDisk();
      expect(
        session.reloads,
        before + 1,
        reason: 'el índice es otro y nadie lo volvió a leer',
      );
    });

    test('si nada ha cambiado no se recarga por gusto', () async {
      // Volver a la ventana ocurre cada vez que alguien cambia de aplicación:
      // recargar el catálogo en cada una sería tirar trabajo todo el día.
      final root = seed();
      addTearDown(() => root.deleteSync(recursive: true));

      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        compilerOverride: FakeCompiler(),
      );
      await session.useCloneForTest(root.path);
      await session.checkDisk();
      final before = session.reloads;

      await session.checkDisk();
      await session.checkDisk();
      expect(session.reloads, before);
    });

    test('y si además el índice está viejo, se regenera', () async {
      // Las dos cosas: el fichero no ha cambiado, pero el contenido sí.
      final root = seed();
      addTearDown(() => root.deleteSync(recursive: true));

      final compiler = FakeCompiler()
        ..staleIndex = (stale: true, reason: 'el disco tiene 42 unidades');
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        compilerOverride: compiler,
      );
      await session.useCloneForTest(root.path);
      // La primera lee la fecha; a partir de aquí lo que queda es la
      // comprobación de contenido.
      await session.checkDisk();
      compiler.staleIndex = (stale: true, reason: 'el disco tiene 42');

      await session.checkDisk();
      expect(compiler.reindexCalls, greaterThanOrEqualTo(1));
    });

    test('sin clon no se mira nada', () async {
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );
      await session.checkDisk();
      expect(session.reloads, 0);
    });
  });
}
