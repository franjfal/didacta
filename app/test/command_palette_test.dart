/// La paleta de órdenes, sobre la aplicación montada entera: el atajo la
/// abre, lo escrito la estrecha, Intro va, y cada pantalla ofrece lo suyo.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/main.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/ui/metadata_editor.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

String where(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(DidactaShell)),
).routeInformationProvider.value.uri.path;

final Finder palette = find.byKey(const Key('command-palette'));
final Finder field = find.byKey(const Key('palette-field'));

Future<FakeSession> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 950);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogueWith(defaultUnits(), courses: [courseJson()]),
  );
  await tester.pumpWidget(
    DidactaApp(session: session, updates: offlineUpdates()),
  );
  await settle(tester);
  return session;
}

Future<void> go(WidgetTester tester, String route) async {
  GoRouter.of(tester.element(find.byType(DidactaShell))).go(route);
  await settle(tester);
}

/// Ctrl+K: en las pruebas el sistema no es macOS, así que es Ctrl.
Future<void> openPalette(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(tester);
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(field, text);
  await settle(tester);
}

String firstTitle(WidgetTester tester) {
  final row = find.byKey(const Key('palette-item-0'));
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .first
      .data!;
}

void main() {
  testWidgets('el atajo la abre, y Esc la cierra', (tester) async {
    await pumpApp(tester);
    expect(palette, findsNothing);
    await openPalette(tester);
    expect(palette, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(palette, findsNothing);
  });

  testWidgets('una lección por su título, sin tildes, e Intro va a ella', (
    tester,
  ) async {
    await pumpApp(tester);
    await openPalette(tester);
    await type(tester, 'espacios de banach');
    expect(firstTitle(tester), 'Espacios de Banach');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(palette, findsNothing);
    expect(where(tester), '/unit/content/analysis/normed/banach');
  });

  testWidgets('con una errata también', (tester) async {
    await pumpApp(tester);
    await openPalette(tester);
    await type(tester, 'bancah');
    expect(firstTitle(tester), 'Espacios de Banach');
  });

  testWidgets('una sección de Ajustes, con las flechas', (tester) async {
    await pumpApp(tester);
    await openPalette(tester);
    await type(tester, 'ajustes snippets');
    expect(firstTitle(tester), 'Ajustes › Snippets de LaTeX');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(where(tester), '/settings');
  });

  testWidgets('en una lección ofrece lo de la lección primero', (tester) async {
    await pumpApp(tester);
    await go(tester, Routes.unit('content/analysis/normed/banach'));
    await openPalette(tester);
    // Sin escribir nada, lo de esta pantalla arriba.
    expect(find.text('En esta pantalla'), findsOneWidget);

    await type(tester, 'metadatos');
    expect(firstTitle(tester), 'Ver los metadatos');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    // La pestaña de metadatos: su editor.
    expect(find.byType(MetadataEditor), findsOneWidget);
  });

  testWidgets('fuera de la lección, lo de la lección ya no sale', (
    tester,
  ) async {
    await pumpApp(tester);
    await go(tester, Routes.unit('content/analysis/normed/banach'));
    await go(tester, Routes.courses());
    await openPalette(tester);
    await type(tester, 'metadatos');
    expect(find.text('Ver los metadatos'), findsNothing);
  });

  testWidgets('lo que no casa lo dice', (tester) async {
    await pumpApp(tester);
    await openPalette(tester);
    await type(tester, 'qqqqqqq');
    expect(find.byKey(const Key('palette-empty')), findsOneWidget);
  });
}
