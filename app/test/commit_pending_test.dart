/// Confirmar es una cosa y enviar es otra, y la barra tiene que decirlo.
///
/// Lo que motiva este fichero es un número que mentía: la insignia de enviar
/// sumaba los commits sin enviar **y** los ficheros escritos sin confirmar,
/// así que decía «697 sin enviar» sobre un repositorio que estaba a cero
/// commits de GitHub. Lo que había eran 697 ficheros que no estaban todavía
/// en ningún commit -- traídos de otro editor, copiados de otra carpeta --
/// y para eso hace falta otro botón y otra decisión: qué entra, y con qué
/// mensaje se cuenta.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/sync_bar.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

/// La sesión de la barra, sin git debajo.
///
/// `refreshAccess` va al disco y lanza `git` de verdad, y el reloj de una
/// prueba de widgets es falso: esperarlo sería esperar para siempre. Lo que
/// se prueba aquí es lo que la barra enseña y lo que le pide a la sesión,
/// que es exactamente lo que queda de este lado.
class _BarSession extends FakeSession {
  _BarSession({
    required super.gatewayOverride,
    required super.catalogue,
    super.cloneOverride,
    super.preferencesOverride,
  });

  @override
  Future<void> refreshAccess() async {}
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

final Finder commitButton = find.byKey(const Key('sync-commit'));
final Finder pushButton = find.byKey(const Key('sync-push'));
final Finder message = find.byKey(const Key('commit-pending-message'));
final Finder confirm = find.byKey(const Key('commit-pending-confirm'));

/// La barra, con un clon que dice tener lo que se le pida.
Future<({_BarSession session, FakeClone clone})> bar(
  WidgetTester tester, {
  int ahead = 0,
  List<String> dirty = const [],
  bool commitOnSave = true,
}) async {
  tester.view.physicalSize = const Size(1200, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits());
  final clone = FakeClone(ahead: ahead, dirty: dirty);
  final session = _BarSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    cloneOverride: clone,
    preferencesOverride: MemoryPreferences()..commit = commitOnSave,
  );
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/clon');
  session.setCloneAuthorForTest((name: 'Javier', email: 'javier@uv.es'));
  // Es lo que llena el estado de los clones sin tocar el disco: pregunta por
  // `cloneAt`, y en esta sesión `cloneAt` es el clon de mentira.
  await session.checkRemote();

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
  return (session: session, clone: clone);
}

/// Lo que dice la insignia de un botón de la barra.
String badgeOf(WidgetTester tester, String id) =>
    tester.widget<Text>(find.byKey(Key('sync-$id-badge'))).data ?? '';

void main() {
  testWidgets('las dos cuentas van por separado', (tester) async {
    // Dos commits hechos y sin enviar, y tres ficheros escritos y sin
    // confirmar. Son dos cosas distintas y se arreglan con dos botones
    // distintos; sumarlas daba un número que no se correspondía con nada.
    await bar(
      tester,
      ahead: 2,
      dirty: const ['content/a/es.tex', 'content/b/es.tex', 'content/c/es.tex'],
    );

    expect(badgeOf(tester, 'push'), '2');
    expect(badgeOf(tester, 'commit'), '3');
  });

  testWidgets('con commits automáticos, confirmar aparece si hay pendiente', (
    tester,
  ) async {
    // Se creía que con ellos puestos no quedaba nunca nada pendiente. Lo que
    // se escribe fuera de Didacta llega al árbol de trabajo sin pasar por
    // aquí, y entonces el botón que lo arregla era el único que no estaba.
    await bar(tester, commitOnSave: true, dirty: const ['content/a/es.tex']);
    expect(commitButton, findsOneWidget);
  });

  testWidgets('y no aparece cuando no hay nada que confirmar', (tester) async {
    // Un botón que no hace nada se aprende a ignorar justo antes del día en
    // que sí hacía falta.
    await bar(tester, commitOnSave: true);
    expect(commitButton, findsNothing);
  });

  testWidgets('sin commits automáticos sigue estando siempre', (tester) async {
    await bar(tester, commitOnSave: false);
    expect(commitButton, findsOneWidget);
    expect(
      tester.widget<IconButton>(commitButton).onPressed,
      isNull,
      reason: 'está, y dice que no hay nada que confirmar',
    );
  });

  group('el diálogo de confirmar', () {
    Future<({_BarSession session, FakeClone clone})> open(
      WidgetTester tester, {
      List<String> dirty = const [
        'content/a/es.tex',
        'content/b/es.tex',
        'content/c/es.tex',
      ],
    }) async {
      final made = await bar(tester, dirty: dirty);
      await tester.tap(commitButton);
      await settle(tester);
      return made;
    }

    testWidgets('enseña lo que hay, agrupado por repositorio', (tester) async {
      await open(tester);

      expect(find.byKey(const Key('commit-pending-files')), findsOneWidget);
      expect(find.text('3 ficheros'), findsOneWidget);
      expect(find.byKey(const Key('commit-repo-test/repo')), findsOneWidget);
      expect(
        find.byKey(const Key('commit-file-content/b/es.tex')),
        findsOneWidget,
      );
    });

    testWidgets('sin mensaje no se confirma', (tester) async {
      await open(tester);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(message, 'Traer las lecciones de análisis');
      await settle(tester);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    });

    testWidgets('sin nada marcado tampoco', (tester) async {
      await open(tester);
      await tester.enterText(message, 'Un mensaje');
      await settle(tester);

      // La cabecera del repositorio desmarca los suyos de una vez.
      await tester.tap(find.byKey(const Key('commit-repo-test/repo')));
      await settle(tester);

      expect(find.text('0 de 3 ficheros'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason: 'un commit vacío no es un commit',
      );
    });

    testWidgets('lo que se deja fuera no entra en el commit', (tester) async {
      // La razón de que se pueda elegir: setecientos ficheros rara vez son un
      // solo cambio que contar, y «Editar 706 ficheros» no lo lee nadie.
      final made = await open(tester);

      await tester.tap(find.byKey(const Key('commit-file-content/b/es.tex')));
      await settle(tester);
      expect(find.text('2 de 3 ficheros'), findsOneWidget);

      await tester.enterText(message, 'Traer las lecciones de análisis');
      await settle(tester);
      await tester.tap(confirm);
      await settle(tester);

      final done = made.clone.commits.single;
      expect(done.message, 'Traer las lecciones de análisis');
      expect(done.paths, ['content/a/es.tex', 'content/c/es.tex']);
    });

    testWidgets('el filtro deja elegir un grupo, y la cabecera lo marca', (
      tester,
    ) async {
      // A setecientas líneas, elegir a mano no es elegir. Escribir «taylor»
      // deja lo de Taylor, y la casilla de la cabecera pasa a marcar y
      // desmarcar lo que se ve: ese es el gesto que convierte una tarde de
      // trabajo en varios commits que se leen.
      final made = await open(
        tester,
        dirty: [
          for (var i = 1; i <= 10; i += 1) 'content/taylor/leccion-$i/es.tex',
          for (var i = 1; i <= 10; i += 1) 'content/series/leccion-$i/es.tex',
        ],
      );

      final filter = find.byKey(const Key('commit-pending-filter'));
      expect(filter, findsOneWidget, reason: 'con veinte ficheros hay filtro');

      // Nada marcado, y luego solo lo de Taylor.
      await tester.tap(find.byKey(const Key('commit-repo-test/repo')));
      await settle(tester);
      expect(find.text('0 de 20 ficheros'), findsOneWidget);

      await tester.enterText(filter, 'taylor');
      await settle(tester);
      expect(find.text('0 de 20 ficheros · 10 se ven'), findsOneWidget);

      await tester.tap(find.byKey(const Key('commit-repo-test/repo')));
      await settle(tester);
      expect(find.text('10 de 20 ficheros · 10 se ven'), findsOneWidget);

      await tester.enterText(message, 'Traer las lecciones de Taylor');
      await settle(tester);
      await tester.tap(confirm);
      await settle(tester);

      final done = made.clone.commits.single;
      expect(done.paths, hasLength(10));
      expect(done.paths.every((path) => path.contains('taylor')), isTrue);
    });

    testWidgets('un filtro que no encaja con nada lo dice', (tester) async {
      await open(
        tester,
        dirty: [
          for (var i = 1; i <= 20; i += 1) 'content/taylor/leccion-$i/es.tex',
        ],
      );
      await tester.enterText(
        find.byKey(const Key('commit-pending-filter')),
        'weierstrass',
      );
      await settle(tester);
      expect(find.text('Nada encaja con «weierstrass».'), findsOneWidget);
    });

    testWidgets('y confirmar cuenta lo que hace en el terminal', (
      tester,
    ) async {
      // Lo mismo que traer y enviar: confirmar setecientos ficheros tarda, y
      // lo que tarda tiene que decir lo que está haciendo.
      final made = await open(tester);
      await tester.enterText(message, 'Traer las lecciones');
      await settle(tester);
      await tester.tap(confirm);
      await settle(tester);

      final console = made.session.syncConsole;
      expect(console.title, 'Confirmar los cambios');
      expect(console.lines, contains('=== test/repo'));
      expect(console.ok, isTrue);
    });
  });
}
