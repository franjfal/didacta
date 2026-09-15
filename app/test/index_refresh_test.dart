/// Que la aplicación se entere de lo que hay en el disco.
///
/// Esto existe por un caso real: alguien movió `content/` y `courses/` a
/// `content_backup/` y `courses_backup/`, arrancó la aplicación, y la
/// biblioteca seguía enseñando dos mil unidades. Y enseñaba lo que tenía
/// --el índice las tiene-- solo que el índice describía ficheros que ya no
/// estaban.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/main.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

FakeSession sessionWith(FakeCompiler compiler, {int? reloads}) => FakeSession(
  gatewayOverride: FakeGateway(),
  catalogue: catalogueWith(defaultUnits()),
  compilerOverride: compiler,
);

void main() {
  group('al arrancar', () {
    test('con el índice al día no se regenera nada', () async {
      // Arrancar no puede costar tres segundos de más porque sí.
      final compiler = FakeCompiler();
      final session = sessionWith(compiler);
      await session.start();

      expect(compiler.reindexCalls, 0);
      expect(session.indexNote, isNull);
    });

    test('si el disco no es lo que dice el índice, se regenera', () async {
      final compiler = FakeCompiler()
        ..staleIndex = (
          stale: true,
          reason: 'el disco tiene 0 unidades y el índice 2147',
        );
      final session = sessionWith(compiler);
      await session.start();

      expect(compiler.reindexCalls, 1);
      // Y el catálogo se vuelve a leer, que si no la pantalla sigue
      // enseñando lo de antes.
      expect(session.reloads, 1);
    });

    test('y se dice, porque cambia lo que se está viendo', () async {
      final compiler = FakeCompiler()
        ..staleIndex = (stale: true, reason: 'el disco tiene 0 unidades');
      final session = sessionWith(compiler);
      await session.start();

      expect(session.indexNote, contains('0 unidades'));
      expect(session.indexNote, contains('regenerado'));
      session.dismissIndexNote();
      expect(session.indexNote, isNull);
    });

    test('si regenerarlo falla, se arranca igual y se avisa', () async {
      // No poder regenerarlo no puede impedir leer lo que hay.
      final compiler = FakeCompiler(failWith: 'sin latexmk')
        ..staleIndex = (stale: true, reason: 'algo');
      final session = sessionWith(compiler);
      await session.start();

      expect(session.state, LoadState.ready);
      expect(session.indexNote, contains('no se ha podido'));
    });

    test('sin motor no se pregunta nada', () async {
      // En web no hay proceso que lanzar, y el índice llega por HTTP tal
      // como esté.
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );
      await session.start();
      expect(session.state, LoadState.ready);
      expect(session.indexNote, isNull);
    });
  });

  testWidgets('el aviso se puede cerrar, y no revienta sin Overlay', (
    tester,
  ) async {
    // Esta franja vive **por encima** del Navigator, donde no hay Overlay.
    // Un `Tooltip` ahí arriba lanza al construirse y se lleva por delante la
    // pantalla entera, así que el aviso de que algo cambió acababa siendo
    // una pantalla rota.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final compiler = FakeCompiler()
      ..staleIndex = (stale: true, reason: 'el disco tiene 0 unidades');
    await tester.pumpWidget(
      DidactaApp(session: sessionWith(compiler)),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('0 unidades'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dismiss-index-note')));
    await settle(tester);
    expect(find.textContaining('0 unidades'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('el botón de actualizar', () {
    test('regenera aunque el índice parezca al día', () async {
      // Pedirlo a mano significa «ponlo como está el disco», no «mira a
      // ver»: se pulsa justo cuando no te fías de lo que estás viendo.
      final compiler = FakeCompiler();
      final session = sessionWith(compiler);
      await session.refreshEverything();

      expect(compiler.reindexCalls, 1);
      expect(session.reloads, 1);
    });

    testWidgets('está en la barra que dice de dónde sale el contenido', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final compiler = FakeCompiler();
      await tester.pumpWidget(
        DidactaApp(session: sessionWith(compiler)),
      );
      await settle(tester);

      expect(find.byKey(const Key('refresh-everything')), findsOneWidget);
      await tester.tap(find.byKey(const Key('refresh-everything')));
      await settle(tester);

      expect(compiler.reindexCalls, 1);
      // Y dice las dos mitades: lo de este disco y lo de GitHub.
      expect(find.textContaining('Actualizado'), findsWidgets);
      expect(find.textContaining('GitHub'), findsWidgets);
    });
  });
}
