/// Qué pasa al guardar: confirmar y enviar son dos decisiones distintas.
///
/// **Confirmar** es dejar el cambio anotado en el historial con un mensaje;
/// **enviar** es que lo vea el resto. Las dos puestas de salida, que es lo
/// que quiere quien no se ha parado a pensar en esto: escribes, se guarda,
/// está en GitHub.
///
/// Apagar la primera cambia lo que hace guardar: el fichero se escribe en el
/// árbol de trabajo y ya, y alguien lo confirma después con el mensaje que
/// quiera. Eso es lo que este fichero fija, porque un guardado que dice que
/// guardó y no dejó commit sería una forma preciosa de perder trabajo.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/sync_bar.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

CloneGateway gatewayOver(
  FakeClone clone, {
  bool commitOnSave = true,
  bool pushOnCommit = true,
}) => CloneGateway(
  clone: clone,
  token: 'gho_x',
  author: (name: 'Javier', email: 'javier@uv.es'),
  commitOnSave: commitOnSave,
  pushOnCommit: pushOnCommit,
);

void main() {
  group('la pasarela', () {
    test('con commits automáticos, guardar confirma', () async {
      final clone = FakeClone();
      await gatewayOver(clone).save(
        path: 'content/a/es.tex',
        text: 'Hola.',
        sha: 'viejo',
        message: 'Editar a',
      );

      expect(clone.fileCommits.single.path, 'content/a/es.tex');
      expect(clone.fileCommits.single.message, 'Editar a');
      expect(clone.writes, isEmpty);
    });

    test('sin ellos, guardar solo escribe', () async {
      final clone = FakeClone();
      await gatewayOver(clone, commitOnSave: false).save(
        path: 'content/a/es.tex',
        text: 'Hola.',
        sha: 'viejo',
        message: 'Editar a',
      );

      expect(clone.writes.single.path, 'content/a/es.tex');
      expect(clone.writes.single.text, 'Hola.');
      expect(clone.fileCommits, isEmpty);
    });

    test('y lo dice, para que la pantalla no mienta al terminar', () {
      // «Guardado como un commit» y «guardado, pendiente de confirmar» son
      // dos cosas distintas, y quien guarda tiene que saber cuál fue.
      expect(gatewayOver(FakeClone()).commitsOnSave, isTrue);
      expect(
        gatewayOver(FakeClone(), commitOnSave: false).commitsOnSave,
        isFalse,
      );
    });

    test('sin confirmar no hace falta autor', () async {
      // No hay nada que firmar, así que escribir tiene que funcionar incluso
      // sin haber entrado en GitHub: es el caso de quien está probando.
      final clone = FakeClone();
      final gateway = CloneGateway(
        clone: clone,
        token: '',
        author: null,
        commitOnSave: false,
      );

      await gateway.save(
        path: 'content/a/es.tex',
        text: 'Hola.',
        sha: '',
        message: 'da igual',
      );
      expect(clone.writes, isNotEmpty);
    });

    test('con confirmación sí, y se dice cuál falta', () async {
      final gateway = CloneGateway(clone: FakeClone(), token: '', author: null);
      await expectLater(
        gateway.save(
          path: 'content/a/es.tex',
          text: 'Hola.',
          sha: '',
          message: 'Editar',
        ),
        throwsA(
          isA<ContentException>().having(
            (e) => e.kind,
            'la clase de fallo',
            ContentFailure.unauthenticated,
          ),
        ),
      );
    });

    test('enviar es otra decisión, aparte de confirmar', () async {
      final clone = FakeClone();
      await gatewayOver(clone, pushOnCommit: false).save(
        path: 'content/a/es.tex',
        text: 'Hola.',
        sha: 'viejo',
        message: 'Editar',
      );
      expect(clone.fileCommits.single.pushed, isFalse);
    });
  });

  group('confirmar a mano', () {
    test('un mensaje vacío se rechaza', () async {
      // «Cambios» en cuarenta commits seguidos ya es un historial que no
      // sirve; uno sin mensaje no sirve ni para eso.
      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      expect(() => session.commitPending('   '), throwsArgumentError);
    });

    test('sin autor tampoco: un commit lleva quién lo hizo', () async {
      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await expectLater(
        session.commitPending('Un mensaje'),
        throwsArgumentError,
      );
    });
  });

  group('el botón de la barra', () {
    Future<void> bar(WidgetTester tester, {required bool commitOnSave}) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        preferencesOverride: MemoryPreferences()..commit = commitOnSave,
      );
      await session.primeForTest(catalogue);
      await session.useCloneForTest('/tmp/didacta-test');

      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(body: SyncBar(session: session)),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('con commits automáticos no aparece', (tester) async {
      // No queda nunca nada pendiente, así que no tendría nada que hacer la
      // mitad del tiempo, y un botón que no hace nada se aprende a ignorar
      // justo antes del día en que sí hacía falta.
      await bar(tester, commitOnSave: true);
      expect(find.byKey(const Key('sync-commit')), findsNothing);
    });

    testWidgets('sin ellos, sí', (tester) async {
      await bar(tester, commitOnSave: false);
      expect(find.byKey(const Key('sync-commit')), findsOneWidget);
    });

    testWidgets('y va delante de traer y enviar', (tester) async {
      // Es el paso que va antes.
      await bar(tester, commitOnSave: false);
      expect(
        tester.getTopLeft(find.byKey(const Key('sync-commit'))).dx,
        lessThan(tester.getTopLeft(find.byKey(const Key('sync-pull'))).dx),
      );
    });

    testWidgets('sin nada pendiente no se puede pulsar', (tester) async {
      await bar(tester, commitOnSave: false);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('sync-commit')))
            .onPressed,
        isNull,
      );
    });
  });
}
