/// Los errores de compilación llevan a la lección y a la línea.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/diagnostic_list.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const CompileDiagnostic inLesson = CompileDiagnostic(
  severity: 'error',
  message: 'Undefined control sequence.',
  file: '../../../$unitPath/es.tex',
  line: 2,
  context: r'\foo',
  path: '$unitPath/es.tex',
  unit: unitPath,
  language: 'es',
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeSession> prime() async {
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(
      files: {'$unitPath/es.tex': 'Primera.\nSegunda con \\foo.\nTercera.\n'},
    ),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  return session;
}

void main() {
  testWidgets('dice la lección, el idioma y la línea, y Abrir lleva allí', (
    tester,
  ) async {
    final session = await prime();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp.router(
          theme: didactaTheme(),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: DiagnosticList(
                    diagnostics: [
                      inLesson,
                      for (var i = 0; i < 8; i += 1)
                        CompileDiagnostic(
                          severity: 'error',
                          message: 'Otro $i',
                        ),
                    ],
                    session: session,
                  ),
                ),
              ),
            ],
            errorBuilder: (_, state) => Text('abierta ${state.uri}'),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text(
        r'«Espacios normados» (es) · línea 2 · Undefined control sequence. · '
        r'\foo',
      ),
      findsOneWidget,
    );
    // Seis a la vista, y el resto a un clic: ya no se pierden.
    expect(find.text('Ver los 9'), findsOneWidget);
    await tester.tap(find.byKey(const Key('diagnostics-all')));
    await settle(tester);
    expect(find.text('Otro 7'), findsOneWidget);

    await tester.tap(find.byKey(const Key('diagnostic-open-$unitPath-2')));
    await settle(tester);
    expect(
      find.text('abierta /unit/$unitPath?lang=es&linea=2'),
      findsOneWidget,
    );
  });

  testWidgets('la lección se abre con el cursor en esa línea', (tester) async {
    final session = await prime();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(
            body: UnitPage(unitPath: unitPath, language: 'es', line: 2),
          ),
        ),
      ),
    );
    await settle(tester);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.selection.baseOffset, 'Primera.\n'.length);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  test('dónde empieza cada línea', () {
    expect(offsetOfLine('a\nbb\nccc', 1), 0);
    expect(offsetOfLine('a\nbb\nccc', 3), 5);
    expect(offsetOfLine('a\nbb', 9), 4);
  });
}
