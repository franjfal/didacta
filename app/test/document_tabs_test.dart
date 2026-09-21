/// Qué botones tiene la cabecera de un tema, y en qué pestaña.
///
/// El de editar la composición estaba siempre, y en las demás pestañas era un
/// botón que no hacía nada visible: se pulsaba mirando el PDF o el historial
/// y no pasaba nada, porque lo que enciende está en otra pantalla. Un mando
/// que a veces no manda es peor que uno que no está.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/document_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

final Finder toggle = find.byKey(const Key('toggle-composition-editor'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpDocument(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: FakeCompiler(),
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: DocumentPage(
            courseId: 'am-iii',
            year: '2025-2026',
            documentId: 'tema-1',
          ),
        ),
      ),
    ),
  );
  await settle(tester);
}

/// Cambia de pestaña por su nombre, que es como se cambia de verdad.
///
/// Por `textContaining` porque algunas llevan un recuento detrás
/// --«Composición (5)», «Traducir (2)»-- y el número cambia con los datos.
Future<void> open(WidgetTester tester, String tab) async {
  await tester.tap(find.textContaining(tab).first);
  await settle(tester);
}

void main() {
  testWidgets('con la composición delante, el botón de editarla está', (
    tester,
  ) async {
    await pumpDocument(tester);
    expect(toggle, findsOneWidget);
  });

  testWidgets('en las demás pestañas no sale', (tester) async {
    await pumpDocument(tester);
    for (final tab in const ['Fuente', 'Compilar', 'Historial']) {
      await open(tester, tab);
      expect(toggle, findsNothing, reason: 'no debería estar en «$tab»');
    }
  });

  testWidgets('y vuelve al volver a la composición', (tester) async {
    await pumpDocument(tester);
    await open(tester, 'Historial');
    expect(toggle, findsNothing);
    await open(tester, 'Composición');
    expect(toggle, findsOneWidget);
  });

  testWidgets('lo que estuviera editándose sigue ahí al volver', (
    tester,
  ) async {
    // Salir a mirar el PDF y volver no puede cerrar el editor: la razón de
    // que esto sea una pestaña y no otra dirección es que es el mismo tema.
    await pumpDocument(tester);
    await tester.tap(toggle);
    await settle(tester);
    expect(
      tester.widget<IconButton>(toggle).isSelected,
      isTrue,
      reason: 'el botón tiene que quedarse encendido',
    );

    await open(tester, 'Compilar');
    await open(tester, 'Composición');
    expect(tester.widget<IconButton>(toggle).isSelected, isTrue);
  });
}
