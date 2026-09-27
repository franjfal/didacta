/// Dos estados a la vista: «sin revisar» y «revisada».
///
/// Quien traduce se hace dos preguntas --¿lo ha leído alguien? ¿está bien?--
/// y el menú de estado le ofrecía cuatro, dos de ellas de quien mantiene el
/// repositorio: «traducida», lo que deja la migración, y «original». En la
/// interfaz esencial quedan las dos que responden; en la completa, las cuatro.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/metadata_editor.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> open(WidgetTester tester, String language) async {
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
        '$unitPath/es.tex': 'El original.\n',
        '$unitPath/va.tex': 'La traducció.\n',
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
        home: Scaffold(
          body: UnitPage(unitPath: unitPath, language: language),
        ),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  test('las opciones, según la interfaz', () {
    expect(declarableStatusesFor(complete: false, reference: false), [
      'draft',
      'reviewed',
    ]);
    expect(declarableStatusesFor(complete: false, reference: true), isEmpty);
    expect(
      declarableStatusesFor(complete: true, reference: false),
      declarableStatuses,
    );
  });

  testWidgets('en la esencial, el menú ofrece dos', (tester) async {
    await open(tester, 'va');
    expect(find.text('sin revisar'), findsWidgets);

    await tester.tap(find.byKey(const Key('status-va')));
    await settle(tester);
    expect(find.byKey(const Key('status-va-draft')), findsOneWidget);
    expect(find.byKey(const Key('status-va-reviewed')), findsOneWidget);
    expect(find.byKey(const Key('status-va-translated')), findsNothing);
    expect(find.byKey(const Key('status-va-source')), findsNothing);
  });

  testWidgets('en la completa, las cuatro', (tester) async {
    await open(tester, 'va');
    await useCompleteInterface(tester);
    await settle(tester);

    await tester.tap(find.byKey(const Key('status-va')));
    await settle(tester);
    for (final status in declarableStatuses) {
      expect(find.byKey(Key('status-va-$status')), findsOneWidget);
    }
  });

  testWidgets('el original, en la esencial, no ofrece nada', (tester) async {
    await open(tester, 'es');
    expect(find.byKey(const Key('status-es')), findsNothing);
  });
}
