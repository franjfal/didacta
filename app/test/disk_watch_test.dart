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

  group('el vigilante', () {
    test('avisa cuando aparece un `generated/` que no existía', () async {
      // Vigilar una carpeta que no existe no vigila nada, y un clon recién
      // añadido no tiene `generated/` hasta que alguien pasa el motor: sin
      // esto, ese repositorio se queda mudo hasta reiniciar.
      final root = Directory.systemTemp.createTempSync('didacta-vacio-');
      addTearDown(() => root.deleteSync(recursive: true));

      final avisos = watchIndex(root.path).take(1).first;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Directory('${root.path}/generated').createSync();
      File(
        '${root.path}/generated/manifest.json',
      ).writeAsStringSync('{"counts": {"units": 0}}');

      await expectLater(avisos.timeout(const Duration(seconds: 5)), completes);
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

  group('con dos repositorios abiertos', twoRepoTests);

  group('el botón de actualizar', refreshTests);
}

/// Dos clones a la vez, que es como se trabaja: la biblioteca y la teoría.
///
/// Esto existe por un caso real: se añadió un segundo repositorio, se le pasó
/// `didacta index` desde el terminal, y la aplicación siguió enseñando el
/// error de que no existía su `manifest.json` --y ninguna de sus asignaturas--
/// hasta reiniciarla. Lo que se miraba era el índice del **primer** clon.
void twoRepoTests() {
  test(
    'el índice del segundo, regenerado por fuera, se vuelve a leer',
    () async {
      final uno = seed();
      final dos = seed();
      addTearDown(() => uno.deleteSync(recursive: true));
      addTearDown(() => dos.deleteSync(recursive: true));

      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        compilerOverride: FakeCompiler(),
      );
      await session.useClonesForTest([uno.path, dos.path]);
      await session.checkDisk();
      final before = session.reloads;

      final later = DateTime.now().add(const Duration(seconds: 5));
      File('${dos.path}/generated/manifest.json').setLastModifiedSync(later);

      await session.checkDisk();
      expect(
        session.reloads,
        before + 1,
        reason: 'el índice del segundo clon es otro y nadie lo volvió a leer',
      );
    },
  );

  test('un repositorio sin índice se lee en cuanto el índice aparece', () async {
    // El caso exacto: se añade un clon recién hecho, todavía sin `generated/`,
    // y se le pasa el motor después. Antes no había nada que comparar, así
    // que encontrar un índice **es** el cambio.
    final uno = seed();
    final dos = Directory.systemTemp.createTempSync('didacta-nuevo-');
    addTearDown(() => uno.deleteSync(recursive: true));
    addTearDown(() => dos.deleteSync(recursive: true));

    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      compilerOverride: FakeCompiler(),
    );
    await session.useClonesForTest([uno.path, dos.path]);
    await session.checkDisk();
    final before = session.reloads;

    Directory('${dos.path}/generated').createSync();
    File(
      '${dos.path}/generated/manifest.json',
    ).writeAsStringSync('{"counts": {"units": 0}}');

    await session.checkDisk();
    expect(session.reloads, before + 1);
  });

  test('y sin cambios no se recarga por tener dos', () async {
    final uno = seed();
    final dos = seed();
    addTearDown(() => uno.deleteSync(recursive: true));
    addTearDown(() => dos.deleteSync(recursive: true));

    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      compilerOverride: FakeCompiler(),
    );
    await session.useClonesForTest([uno.path, dos.path]);
    await session.checkDisk();
    final before = session.reloads;

    await session.checkDisk();
    await session.checkDisk();
    expect(session.reloads, before);
  });
}

/// El botón de actualizar, y lo que mira.
///
/// «Actualizar» son tres preguntas, no una: ¿ha cambiado el índice?, ¿ha
/// cambiado el material que el índice describe?, ¿hay algo en GitHub que no
/// está aquí? Las tres tienen que pasar cuando se pulsa, porque se pulsa
/// justo cuando no te fías de lo que estás viendo.
void refreshTests() {
  test('rehace el índice aunque parezca al día, y pregunta a GitHub', () async {
    final root = seed();
    addTearDown(() => root.deleteSync(recursive: true));

    final compiler = FakeCompiler();
    final clone = FakeClone();
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      compilerOverride: compiler,
      cloneOverride: clone,
    );
    await session.useCloneForTest(root.path);

    await session.refreshEverything();

    // Un reíndice de verdad: lee todos los ficheros, que es lo que coge una
    // edición hecha por fuera con cualquier programa.
    expect(compiler.reindexCalls, 1);
    expect(session.reloads, 1);
    // Y la otra mitad.
    expect(clone.fetches, 1);
  });

  test('lo de GitHub no se trae solo', () async {
    // Un `pull` cambia los ficheros de debajo de quien está editando. Mirar
    // es una decisión; traer es otra.
    final root = seed();
    addTearDown(() => root.deleteSync(recursive: true));

    final clone = FakeClone(behind: 3);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      compilerOverride: FakeCompiler(),
      cloneOverride: clone,
    );
    await session.useCloneForTest(root.path);

    await session.refreshEverything();
    expect(session.behind, 3);
    expect(clone.pulls, 0, reason: 'traerlo es otra decisión');
  });

  test('sin red, lo local se actualiza igual', () async {
    // Preguntar a GitHub puede fallar --sin red, sin token, sin remoto-- y
    // eso no puede tirar un refresco que ya ha hecho su trabajo.
    final root = seed();
    addTearDown(() => root.deleteSync(recursive: true));

    final compiler = FakeCompiler();
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      compilerOverride: compiler,
      cloneOverride: FakeClone(failFetch: true),
    );
    await session.useCloneForTest(root.path);

    await session.refreshEverything();
    expect(compiler.reindexCalls, 1);
    expect(session.reloads, 1);
    expect(session.remoteProblem, isNotNull);
  });
}
