/// Las fórmulas que no coinciden con el original, en el editor.
///
/// Salen en el mismo panel que lo que no va a compilar, con su línea y un
/// clic para ir allí, porque se arreglan igual: mirando la línea. Pero con su
/// propio título: una fórmula distinta compila, y decir «esto no va a
/// compilar» sería mentir.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> open(WidgetTester tester, String translation) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final catalogue = catalogueWith([
    {
      ...unitJson(),
      'languages': {
        'es': {'status': 'source', 'exists': true},
        'va': {'status': 'draft', 'exists': true},
      },
    },
  ]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(
      files: {
        '$unitPath/es.tex': 'Sea \$f(x) = x^2\$.\n\nY \$g = 1\$.\n',
        '$unitPath/va.tex': translation,
        '$unitPath/unit.yaml': unitYaml,
      },
    ),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
          body: UnitPage(unitPath: unitPath, language: 'va'),
        ),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('una fórmula cambiada sale en el panel, con su título', (
    tester,
  ) async {
    await open(tester, 'Siga \$f(x) = x^3\$.\n\nI \$g = 1\$.\n');
    expect(find.byKey(const Key('tex-warnings')), findsOneWidget);
    expect(
      find.text('Una fórmula no coincide con el original'),
      findsOneWidget,
    );
    expect(find.textContaining('no es la del original'), findsOneWidget);
  });

  testWidgets('con las mismas fórmulas, no hay panel', (tester) async {
    await open(tester, 'Siga \$f(x)=x^2\$.\n\nI \$g = 1\$.\n');
    expect(find.byKey(const Key('tex-warnings')), findsNothing);
  });
}
