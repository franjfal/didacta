/// Volver atrás sin perder por dónde ibas.
///
/// El motivo es concreto: la aplicación navega con `go`, así que entrar en un
/// año desde una asignatura **sustituye** la pantalla. Para volver había que
/// pulsar el carril de la izquierda, que lleva a la raíz de la sección y se
/// lleva por delante todo lo navegado. Estos tests van por el router de
/// verdad, no por una pantalla suelta, porque lo que se prueba es justo la
/// costura entre navegar y recordar.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/main.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

final Finder back = find.byKey(const Key('go-back'));
final Finder forward = find.byKey(const Key('go-forward'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

GoRouter routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(DidactaShell)));

String where(WidgetTester tester) =>
    routerOf(tester).routeInformationProvider.value.uri.path;

Future<FakeSession> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogueWith(defaultUnits()),
  );
  await tester.pumpWidget(DidactaApp(session: session));
  await settle(tester);
  return session;
}

Future<void> goTo(WidgetTester tester, String route) async {
  routerOf(tester).go(route);
  await settle(tester);
}

void main() {
  testWidgets('al arrancar no hay a dónde volver, y se ve', (tester) async {
    await pumpApp(tester);
    expect(back, findsOneWidget);
    expect(tester.widget<IconButton>(back).onPressed, isNull);
    // Y «adelante» ni aparece: un botón que nunca se enciende es ruido.
    expect(forward, findsNothing);
  });

  testWidgets('vuelve al sitio anterior, no a la raíz de la sección', (
    tester,
  ) async {
    // El caso del que salió todo: asignaturas, un año, un documento. Desde el
    // documento, atrás tiene que devolver al año y no a la biblioteca.
    await pumpApp(tester);
    await goTo(tester, '/courses');
    await goTo(tester, '/courses/am-iii/2025-2026');
    await goTo(tester, '/courses/am-iii/2025-2026/tema-1');

    expect(tester.widget<IconButton>(back).onPressed, isNotNull);
    await tester.tap(back);
    await settle(tester);
    expect(where(tester), '/courses/am-iii/2025-2026');

    await tester.tap(back);
    await settle(tester);
    expect(where(tester), '/courses');
  });

  testWidgets('y adelante rehace lo deshecho', (tester) async {
    await pumpApp(tester);
    await goTo(tester, '/courses');
    await goTo(tester, '/settings');

    await tester.tap(back);
    await settle(tester);
    expect(where(tester), '/courses');
    expect(forward, findsOneWidget);

    await tester.tap(forward);
    await settle(tester);
    expect(where(tester), '/settings');
    expect(forward, findsNothing);
  });

  testWidgets('ir a otro sitio después de volver cierra el «adelante»', (
    tester,
  ) async {
    await pumpApp(tester);
    await goTo(tester, '/courses');
    await goTo(tester, '/settings');
    await tester.tap(back);
    await settle(tester);
    expect(forward, findsOneWidget);

    await goTo(tester, '/translations');
    expect(forward, findsNothing);
    await tester.tap(back);
    await settle(tester);
    expect(where(tester), '/courses');
  });

  testWidgets('el atajo del teclado hace lo mismo que el botón', (
    tester,
  ) async {
    await pumpApp(tester);
    await goTo(tester, '/courses');
    await goTo(tester, '/settings');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);

    expect(where(tester), '/courses');
  });

  testWidgets('una unidad abierta desde la biblioteca vuelve a ella', (
    tester,
  ) async {
    await pumpApp(tester);
    await goTo(tester, '/unit/content/analysis/normed/definition');
    await tester.tap(back);
    await settle(tester);
    expect(where(tester), '/');
  });
}
