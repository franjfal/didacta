/// «Compilar lo desactualizado», en la página de un curso.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';
import 'theme_cards_test.dart' show themedCourse;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ExistingOutput output(String profile, String language, {bool stale = false}) =>
    ExistingOutput(
      profile: profile,
      label: profile,
      family: 'notes',
      language: language,
      pdf: '/tmp/$profile-$language.pdf',
      exists: true,
      stale: stale,
    );

Future<FakeCompiler> pumpYear(
  WidgetTester tester,
  Map<String, List<ExistingOutput>> built,
) async {
  tester.view.physicalSize = const Size(1300, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final compiler = FakeCompiler()..documentOutputList = built;
  final catalogue = catalogueWith(defaultUnits(), courses: [themedCourse()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
          body: YearPage(courseId: 'am-iii', year: '2025-2026'),
        ),
      ),
    ),
  );
  await settle(tester);
  return compiler;
}

void main() {
  testWidgets('sin nada viejo, no hay botón', (tester) async {
    await pumpYear(tester, {
      'tema-1': [output('slides', 'es')],
    });
    expect(find.byKey(const Key('build-stale-year')), findsNothing);
    expect(find.byKey(const Key('build-stale-theme-tema-1')), findsNothing);
  });

  testWidgets('compila solo lo viejo, versión a versión', (tester) async {
    final compiler = await pumpYear(tester, {
      'tema-1': [
        output('slides', 'es', stale: true),
        output('notes', 'es'),
        output('notes', 'va', stale: true),
      ],
      'hoja-1': [output('problems', 'es')],
      'hoja-2': [output('problems', 'es', stale: true)],
    });
    expect(find.text('Compilar lo desactualizado (2)'), findsOneWidget);
    // En el tema 1 hay uno; en el 2, otro.
    expect(find.byKey(const Key('build-stale-theme-tema-1')), findsOneWidget);
    expect(find.text('1 desactualizado'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('build-stale-theme-tema-1')));
    await settle(tester);
    // Solo el tema 1, y de él solo las salidas viejas: diapositivas en
    // castellano y apuntes en valenciano, cada una en su idioma.
    expect(compiler.documentCalls.map((c) => c.document).toSet(), {
      'am-iii@2025-2026/tema-1',
    });
    expect(
      {
        for (final call in compiler.documentCalls)
          '${call.profiles.join(',')}·${call.languages.join(',')}',
      },
      {'slides·es', 'notes·va'},
    );
  });
}
