/// El panel de salidas de un tema, y lo que dice de compilar.
///
/// Decía siempre que compilar necesita LaTeX y que un navegador no lo tiene,
/// con el `didacta build` debajo; también en escritorio, donde se compila
/// desde la pestaña de al lado. Ahora eso sale solo donde no se puede.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/document_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

final Finder browserNote = find.textContaining('un navegador no lo tiene');
final Finder command = find.text('didacta build tema-1');

Future<void> pumpDocument(
  WidgetTester tester, {
  required bool canCompile,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: canCompile ? FakeCompiler() : null,
    canCompileOverride: canCompile,
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
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('en escritorio el panel no explica cómo compilar', (
    tester,
  ) async {
    await pumpDocument(tester, canCompile: true);
    expect(find.textContaining('SALIDAS ('), findsOneWidget);
    expect(browserNote, findsNothing);
    expect(command, findsNothing);
  });

  testWidgets('en la web dice por qué no y da el comando', (tester) async {
    await pumpDocument(tester, canCompile: false);
    expect(browserNote, findsOneWidget);
    expect(command, findsOneWidget);
  });

  testWidgets('estrecho, lo mismo: el panel va en su pestaña', (tester) async {
    // En una ventana estrecha el panel está detrás de `Offstage`, montado
    // aunque no se vea: se busca también lo que no está en pantalla.
    await pumpDocument(tester, canCompile: true, width: 700);
    expect(find.textContaining('SALIDAS (', skipOffstage: false), findsWidgets);
    expect(
      find.textContaining('un navegador no lo tiene', skipOffstage: false),
      findsNothing,
    );
  });
}
