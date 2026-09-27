/// Lo que la interfaz Esencial deja para la Completa, y lo que no.
///
/// Esencial es lo de todos los días; lo de quien mantiene el repositorio del
/// departamento --bloques y plantillas, el servidor MCP, poner los ids, las
/// rutas de cada herramienta-- se enseña con Completa. Pero nada de eso puede
/// quedarse sin salida: un enlace a una de esas secciones la abre, lo que está
/// encendido se puede apagar y lo que falla se ve entero.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

Future<FakeSession> sessionWith({bool complete = false}) async {
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogueWith(defaultUnits()),
    preferencesOverride: MemoryPreferences()..complete = complete,
  );
  await session.primeForTest(catalogueWith(defaultUnits()));
  return session;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> openSettings(
  WidgetTester tester,
  FakeSession session,
  String section,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    DidactaApp(session: session, updates: offlineUpdates()),
  );
  await settle(tester);
  GoRouter.of(
    tester.element(find.byType(DidactaShell)),
  ).go('/settings?s=$section');
  await settle(tester);
}

void main() {
  group('las secciones de Ajustes', () {
    List<String> ids(
      FakeSession session, {
      String? asked,
      bool mcpOn = false,
    }) => [
      for (final section in settingsSections(
        session,
        asked: asked,
        mcpOn: mcpOn,
      ))
        section.id,
    ];

    test('Esencial deja fuera las de quien mantiene el repositorio', () async {
      final session = await sessionWith();
      expect(ids(session), isNot(contains('material')));
      expect(ids(session), isNot(contains('mcp')));
      // Lo de todos los días sigue ahí.
      expect(
        ids(session),
        containsAll(['repositorios', 'idiomas', 'snippets']),
      );
    });

    test('Completa las enseña', () async {
      final session = await sessionWith(complete: true);
      expect(ids(session), containsAll(['material', 'mcp']));
    });

    test('un enlace a una de ellas la abre igual', () async {
      final session = await sessionWith();
      expect(ids(session, asked: 'material'), contains('material'));
      expect(ids(session, asked: 'mcp'), contains('mcp'));
    });

    test('con el servidor encendido, se ve para poder apagarlo', () async {
      final session = await sessionWith();
      expect(ids(session, mcpOn: true), contains('mcp'));
    });
  });

  group('las herramientas', () {
    testWidgets('en Esencial y con todo, en una línea con sus detalles', (
      tester,
    ) async {
      final session = await sessionWith();
      await openSettings(tester, session, 'herramientas');

      expect(find.byKey(const Key('tools-folded')), findsOneWidget);
      expect(find.byKey(const Key('tool-git')), findsNothing);

      await tester.tap(find.byKey(const Key('tools-details')));
      await settle(tester);
      expect(find.byKey(const Key('tools-folded')), findsNothing);
      expect(find.byKey(const Key('tool-git')), findsOneWidget);
    });

    testWidgets('en Completa, cada una con su ruta', (tester) async {
      final session = await sessionWith(complete: true);
      await openSettings(tester, session, 'herramientas');

      expect(find.byKey(const Key('tools-folded')), findsNothing);
      expect(find.byKey(const Key('tool-git')), findsOneWidget);
    });
  });
}
