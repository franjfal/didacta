/// La biblioteca vuelve al sitio: lo buscado y lo abierto sobreviven a ir a
/// una lección y volver.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/main.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

final Finder back = find.byKey(const Key('go-back'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

GoRouter routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(DidactaShell)));

Uri where(WidgetTester tester) =>
    routerOf(tester).routeInformationProvider.value.uri;

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogueWith(defaultUnits()),
  );
  await tester.pumpWidget(
    DidactaApp(session: session, updates: offlineUpdates()),
  );
  await settle(tester);
  // Arranca en Asignaturas.
  routerOf(tester).go(Routes.library());
  await settle(tester);
}

void main() {
  testWidgets('lo buscado va a la dirección, y atrás vuelve a ello', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).first, 'normados');
    await settle(tester);
    expect(where(tester).queryParameters['q'], 'normados');

    routerOf(tester).go(Routes.unit(unitPath));
    await settle(tester);
    await tester.tap(back);
    await settle(tester);

    expect(where(tester).path, '/');
    expect(where(tester).queryParameters['q'], 'normados');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'normados',
    );
    // Y «atrás» otra vez no deshace la búsqueda letra a letra: vuelve a
    // donde se estaba antes de la biblioteca.
    await tester.tap(back);
    await settle(tester);
    expect(where(tester).path, '/courses');
  });

  testWidgets('lo abierto del árbol también', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Analysis').first);
    await settle(tester);
    await tester.tap(find.text('Normed').first);
    await settle(tester);
    // Las lecciones salen al llegar al último nivel: sin subtema declarado,
    // es el grupo «sin subtema».
    await tester.tap(find.byKey(const Key('subtopic-')));
    await settle(tester);
    expect(where(tester).queryParameters['en'], startsWith('analysis/normed'));

    routerOf(tester).go(Routes.unit(unitPath));
    await settle(tester);
    await tester.tap(back);
    await settle(tester);
    expect(where(tester).queryParameters['en'], startsWith('analysis/normed'));
    // El tema abierto: se ven sus lecciones.
    expect(find.text('Espacios normados'), findsWidgets);
  });

  testWidgets('un enlace con filtros abre la biblioteca así', (tester) async {
    await pumpApp(tester);
    routerOf(tester).go('/?q=banach');
    await settle(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'banach',
    );
    expect(find.text('Espacios de Banach'), findsWidgets);
  });
}
