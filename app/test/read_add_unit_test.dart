/// Añadir una lección a un tema desde la vista de lectura, sin abrir el
/// editor de la composición, y compilar justo después.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/document_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<({FakeGateway gateway, FakeCompiler compiler})> pumpDocument(
  WidgetTester tester, {
  bool writable = true,
}) async {
  tester.view.physicalSize = const Size(1300, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final gateway = FakeGateway(writable: writable);
  final compiler = FakeCompiler();
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: gateway,
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await session.primeForTest(catalogue);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
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
  return (gateway: gateway, compiler: compiler);
}

void main() {
  testWidgets('se añade al final, en un commit, sin abrir el editor', (
    tester,
  ) async {
    final (:gateway, :compiler) = await pumpDocument(tester);

    await tester.tap(find.byKey(const Key('read-add-unit')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('picker-search')), 'rank');
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('unit-content/algebra/matrices/rank')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('picker-add')));
    await settle(tester);
    await tapIfShown(tester, find.byKey(const Key('composition-commit')));
    await settle(tester);

    expect(gateway.commits, hasLength(1));
    final saved = gateway.commits.single;
    expect(saved.path, 'courses/am-iii/2025-2026/year.yaml');
    final entries = CompositionFile(saved.text).blockFor('tema-1')!.entries;
    expect(entries.last.value, 'algebra.matrices.rank');
    // Lo de antes, intacto y en su sitio: la entrada comentada sigue ahí.
    expect(saved.text, contains('# - unit: analysis/normed/dedekind'));
    // Sin haber pasado por el editor.
    expect(find.byKey(const Key('composition-save')), findsNothing);

    // Y lo siguiente que se quiere es verlo.
    expect(find.byKey(const Key('saved-follow-up')), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-follow-up')));
    await settle(tester);
    expect(compiler.documentCalls, isNotEmpty);
    expect(compiler.documentCalls.last.document, 'am-iii@2025-2026/tema-1');
  });

  testWidgets('guardar desde el editor también ofrece compilar', (
    tester,
  ) async {
    final (:gateway, :compiler) = await pumpDocument(tester);
    await tester.tap(find.byKey(const Key('toggle-composition-editor')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('add-unit')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('picker-search')), 'rank');
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('unit-content/algebra/matrices/rank')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('picker-add')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('composition-save')));
    await settle(tester);
    await tapIfShown(tester, find.byKey(const Key('composition-commit')));
    await settle(tester);

    expect(gateway.commits, hasLength(1));
    await tester.tap(find.byKey(const Key('saved-follow-up')));
    await settle(tester);
    expect(compiler.documentCalls, isNotEmpty);
  });

  testWidgets('donde no se puede escribir, no se ofrece', (tester) async {
    await pumpDocument(tester, writable: false);
    expect(find.byKey(const Key('read-add-unit')), findsNothing);
  });
}
