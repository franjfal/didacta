/// El historial para quien no sabe git: comparar con ahora, recuperar una
/// versión en el editor sin guardar nada, y sin hashes a la vista.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/file_history.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Un clon cuyo fichero de ahora es [now].
class NowClone extends FakeClone {
  NowClone(this.now);

  final String now;

  @override
  Future<({String text, String sha})> readFile(String path) async =>
      (text: now, sha: 'x');
}

const String path = '$unitPath/es.tex';
const String now = 'Una norma en un espacio vectorial real.\n';
const String then = 'Una norma en un espacio vectorial.\n';

NowClone history() => NowClone(now)
  ..log[path] = [
    FileCommit(
      sha: 'nuevonuevonuevo',
      author: 'Javier',
      email: 'j@uv.es',
      when: DateTime(2026, 9, 10),
      subject: 'Precisar la definición',
    ),
    FileCommit(
      sha: 'viejoviejoviejo',
      author: 'Javier',
      email: 'j@uv.es',
      when: DateTime(2026, 3, 2),
      subject: 'La primera versión',
    ),
  ]
  ..diffs['nuevonuevonuevo'] = parseUnifiedDiff('@@ -1,1 +1,1 @@\n-$then+$now')
  ..contents['viejoviejoviejo'] = then;

Future<({FakeSession session, FakeGateway gateway})> pumpUnit(
  WidgetTester tester, {
  bool complete = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final gateway = FakeGateway(
    files: {path: now, '$unitPath/unit.yaml': unitYaml},
  );
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: gateway,
    catalogue: catalogue,
    cloneOverride: history(),
  );
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  if (complete) await session.setCompleteInterface(true);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
          body: UnitPage(unitPath: unitPath, language: 'es'),
        ),
      ),
    ),
  );
  await settle(tester);
  await tester.tap(find.text('historial').first);
  await settle(tester);
  await tester.tap(find.byKey(const Key('commit-viejoviejoviejo')));
  await settle(tester);
  return (session: session, gateway: gateway);
}

void main() {
  testWidgets('comparar con ahora enseña lo que ha cambiado desde entonces', (
    tester,
  ) async {
    await pumpUnit(tester);
    await tester.tap(find.byKey(const Key('compare-with-now')));
    await settle(tester);
    // Las dos líneas: la de entonces, quitada, y la de ahora, puesta.
    expect(find.text(then.trim()), findsOneWidget);
    expect(find.text(now.trim()), findsOneWidget);
  });

  testWidgets('recuperar lleva el texto al editor, sin guardar nada', (
    tester,
  ) async {
    final (:session, :gateway) = await pumpUnit(tester);
    await tester.tap(find.byKey(const Key('recover-version')));
    await settle(tester);
    // Antes, lo que cambiaría.
    expect(find.byKey(const Key('diff-box')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-recover')));
    await settle(tester);

    expect(find.byKey(const Key('recovered-notice')), findsOneWidget);
    // En el editor, y sin guardar: el fichero sigue como estaba.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, then);
    expect(gateway.commits, isEmpty);
    expect(gateway.files[path], now);
  });

  testWidgets('sin la interfaz completa no hay hashes', (tester) async {
    await pumpUnit(tester);
    expect(find.textContaining('viejovi'), findsNothing);
  });

  testWidgets('con ella, sí', (tester) async {
    await pumpUnit(tester, complete: true);
    expect(find.textContaining('viejovi'), findsWidgets);
  });
}
