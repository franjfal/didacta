/// Revisar: el informe de `didacta check`, el panel y la revisión antes de
/// exportar.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/model/review.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/review_panel.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const Map<String, dynamic> reportJson = {
  'ok': false,
  'errors': 1,
  'warnings': 1,
  'checks': ['babel', 'figures', 'labels'],
  'titles': {
    'babel': 'Órdenes de otro idioma',
    'labels': 'Etiquetas repetidas y referencias sin destino',
  },
  'findings': [
    {
      'check': 'babel',
      'severity': 'error',
      'message': r'\sptext solo existe en castellano',
      'path': '$unitPath/va.tex',
      'line': 4,
      'unit': unitPath,
      'language': 'va',
    },
    {
      'check': 'labels',
      'severity': 'warning',
      'message': r'\ref{nada} no tiene destino en Tema 1: saldrá como «??»',
      'path': '$unitPath/es.tex',
      'line': 9,
      'unit': unitPath,
      'language': 'es',
      'document': 'am-iii@2025-2026/tema-1',
    },
  ],
};

final ReviewReport report = ReviewReport.fromJson(reportJson);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<(FakeSession, FakeCompiler)> prime({ReviewReport? answer}) async {
  final compiler = FakeCompiler();
  if (answer != null) compiler.reviewReport = answer;
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await session.primeForTest(catalogue);
  return (session, compiler);
}

/// Una pantalla con un botón que hace [action] con su contexto.
Future<void> pumpHost(
  WidgetTester tester,
  Session session,
  Future<void> Function(BuildContext context) action,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('go'),
              onPressed: () => action(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('el informe', () {
    test('lee cada hallazgo con su sitio', () {
      expect(report.errors, 1);
      expect(report.warnings, 1);
      expect(report.clean, isFalse);
      final [babel, labels] = report.findings;
      expect(babel.isError, isTrue);
      expect(babel.unit, unitPath);
      expect(babel.line, 4);
      expect(labels.document, 'am-iii@2025-2026/tema-1');
      expect(report.byCheck.keys, ['babel', 'labels']);
      expect(report.titleOf('babel'), 'Órdenes de otro idioma');
      // Las que se piden aparte tienen nombre aunque el motor no lo diga.
      expect(report.titleOf('formulas'), 'Fórmulas distintas entre idiomas');
    });

    test('se le pide al motor con lo que se revisa', () async {
      final root = Directory.systemTemp.createTempSync('didacta-review-cli-');
      addTearDown(() => root.deleteSync(recursive: true));
      final script = File('${root.path}/cli/didacta')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'echo "\$@" > "\$(dirname "\$0")/../args.txt"\n'
          'echo \'{"ok": true, "findings": []}\'\n'
          'exit 1\n',
        );
      Process.runSync('chmod', ['+x', script.path]);
      final compiler = Compiler(
        enginePath: root.path,
        repositoryPath: root.path,
      );
      final found = await compiler.review(
        within: const ['am-iii@2025-2026'],
        extra: const ['formulas', 'unused'],
      );
      expect(found.clean, isTrue);
      expect(
        File('${root.path}/args.txt').readAsStringSync().trim(),
        'check --json --in am-iii@2025-2026 --with formulas,unused',
      );
    });
  });

  group('el panel', () {
    testWidgets('agrupa por comprobación y cada uno lleva a su línea', (
      tester,
    ) async {
      final (session, compiler) = await prime(answer: report);
      await pumpHost(
        tester,
        session,
        (context) => showReview(context, session),
      );
      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);

      expect(find.byKey(const Key('review-dialog')), findsOneWidget);
      expect(find.text('1 error · 1 aviso'), findsOneWidget);
      expect(find.byKey(const Key('review-group-babel')), findsOneWidget);
      expect(find.text('Órdenes de otro idioma'), findsOneWidget);
      expect(
        find.byKey(const Key('diagnostic-open-$unitPath-4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('diagnostic-open-$unitPath-9')),
        findsOneWidget,
      );
      expect(compiler.reviews.single.extra, isEmpty);
    });

    testWidgets('las de más se piden con su chip, y se recuerdan', (
      tester,
    ) async {
      final (session, compiler) = await prime(answer: report);
      await pumpHost(
        tester,
        session,
        (context) => showReview(context, session),
      );
      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('review-with-formulas')));
      await settle(tester);
      expect(compiler.reviews.last.extra, ['formulas']);

      await tester.tap(find.byKey(const Key('review-close')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);
      expect(compiler.reviews.last.extra, ['formulas']);
      // Y se quita para no contaminar las demás pruebas.
      await tester.tap(find.byKey(const Key('review-with-formulas')));
      await settle(tester);
      expect(compiler.reviews.last.extra, isEmpty);
    });

    testWidgets('la ortografía se pide como las demás', (tester) async {
      final (session, compiler) = await prime(answer: report);
      await pumpHost(
        tester,
        session,
        (context) => showReview(context, session),
      );
      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);
      expect(
        find.text('Palabras que el diccionario no conoce'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('review-with-spelling')));
      await settle(tester);
      expect(compiler.reviews.last.extra, ['spelling']);
      await tester.tap(find.byKey(const Key('review-with-spelling')));
      await settle(tester);
    });

    testWidgets('sin nada que mirar, lo dice', (tester) async {
      final (session, _) = await prime();
      await pumpHost(
        tester,
        session,
        (context) => showReview(context, session),
      );
      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);
      expect(find.byKey(const Key('review-clean')), findsOneWidget);
      expect(find.text('Todo en orden'), findsOneWidget);
    });
  });

  group('antes de exportar', () {
    testWidgets('sin nada que mirar, sigue sin enseñar nada', (tester) async {
      final (session, compiler) = await prime();
      bool? go;
      await pumpHost(tester, session, (context) async {
        go = await reviewBeforeExport(
          context,
          session,
          within: const ['am-iii@2025-2026'],
        );
      });
      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);
      expect(go, isTrue);
      expect(find.byKey(const Key('review-dialog')), findsNothing);
      expect(compiler.reviews.single.within, ['am-iii@2025-2026']);
    });

    testWidgets('con algo, pregunta: exportar igualmente o no', (tester) async {
      final (session, _) = await prime(answer: report);
      bool? go;
      await pumpHost(tester, session, (context) async {
        go = await reviewBeforeExport(
          context,
          session,
          within: const ['am-iii@2025-2026/tema-1'],
        );
      });
      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);
      expect(find.text('Revisar lo que se va a exportar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-cancel')));
      await settle(tester);
      expect(go, isFalse);

      await tester.tap(find.byKey(const Key('go')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('review-export')));
      await settle(tester);
      expect(go, isTrue);
    });
  });
}
