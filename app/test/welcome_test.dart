/// La bienvenida: que salga la primera vez, y que no salga la segunda.
///
/// Lo que se comprueba aquí es lo que decide si alguien llega a usar Didacta
/// o la cierra: **qué es lo primero que se ve**. Y la otra mitad, que es tan
/// importante: que una vez vista no vuelva a aparecer, porque un asistente
/// que sale en cada arranque se convierte en un obstáculo a los dos días.
@TestOn('vm')
library;

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/welcome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// La aplicación entera, como la levanta `main`.
///
/// Dentro de `runAsync` porque el arranque lee preferencias y mira el disco, y
/// dentro de `testWidgets` el reloj es falso: un futuro de verdad no se
/// completa por mucho que se pumpee.
Future<void> pumpApp(WidgetTester tester, Session session) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      DidactaApp(session: session, updates: offlineUpdates()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await settle(tester);
}

Session sessionWith({required bool welcomeSeen, String? token}) => LocalSession(
  catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
  tokenStore: StubStore(token: token),
  preferences: MemoryPreferences()..welcome = welcomeSeen,
);

void main() {
  testWidgets('la primera vez se ve la bienvenida, no la biblioteca', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, sessionWith(welcomeSeen: false));

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(
      find.textContaining('El material se escribe una vez'),
      findsOneWidget,
    );
    // Y la aplicación de debajo no se ha construido: la bienvenida va **en
    // lugar de** ella, no encima.
    expect(find.text('Biblioteca'), findsNothing);
  });

  testWidgets('va antes que la puerta de GitHub', (tester) async {
    // El orden importa: entrar es uno de los pasos de la bienvenida, no algo
    // que haya que hacer antes de que nadie te diga qué es esto.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, sessionWith(welcomeSeen: false, token: null));

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Entra en GitHub para empezar.'), findsNothing);
  });

  testWidgets('vista una vez, no vuelve', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, sessionWith(welcomeSeen: true));

    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('saltarla la da por vista', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = sessionWith(welcomeSeen: false);
    await pumpApp(tester, session);

    await tester.tap(find.byKey(const Key('welcome-skip')));
    await settle(tester);

    expect(find.byType(WelcomeScreen), findsNothing);
    expect(await session.preferences.welcomeDone(), isTrue);
  });

  testWidgets('sin haber entrado, el paso de la cuenta no deja seguir', (
    tester,
  ) async {
    // Es el único paso obligatorio, y tiene que serlo: sin sesión no hay
    // ningún repositorio que abrir, así que dejar pasar sería llevar a
    // alguien a un paso que no puede hacer.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
    );
    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(session: session)));
    await settle(tester);

    await tester.tap(find.byKey(const Key('welcome-next')));
    await settle(tester);

    expect(find.text('Entra en GitHub'), findsOneWidget);
    final next = tester.widget<FilledButton>(
      find.byKey(const Key('welcome-next')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('entrado ya, los pasos se recorren hasta el final', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
    );
    // Quien monta esta pantalla en un test ya ha entrado: el fixture trae un
    // token en el llavero de mentira.
    await session.primeForTest(catalogueWith(defaultUnits()));

    var terminada = false;
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          session: session,
          onFinished: () => terminada = true,
        ),
      ),
    );
    await settle(tester);

    // Qué es → cuenta → repositorio → (motor) → listo.
    for (var i = 0; i < 6 && !terminada; i += 1) {
      final next = find.byKey(const Key('welcome-next'));
      if (next.evaluate().isEmpty) break;
      final button = tester.widget<FilledButton>(next);
      if (button.onPressed == null) break;
      await tester.tap(next);
      await settle(tester);
    }

    expect(terminada, isTrue);
  });
}
