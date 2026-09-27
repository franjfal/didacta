/// Lo escrito y sin guardar sobrevive a que Didacta se cierre de golpe.
///
/// Un cuelgue o un corte se llevaba entero lo que hubiera en un editor sin
/// guardar. Ahora se va copiando fuera del repositorio mientras se escribe, y
/// al volver a abrir el fichero se ofrece.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/draft_store.dart';
import 'package:didacta_app/data/draft_store_io.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const String key = '|$unitPath/es.tex';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<(FakeSession, FakeGateway, MemoryDraftStore)> pumpLesson(
  WidgetTester tester, {
  Draft? leftOver,
}) async {
  final drafts = MemoryDraftStore();
  if (leftOver != null) drafts.drafts[key] = leftOver;
  final gateway = FakeGateway();
  final catalogue = catalogueWith([unitJson()]);
  final session = FakeSession(
    gatewayOverride: gateway,
    catalogue: catalogue,
    draftsOverride: drafts,
  );
  await session.primeForTest(catalogue);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(body: UnitPage(unitPath: unitPath)),
      ),
    ),
  );
  await settle(tester);
  return (session, gateway, drafts);
}

void main() {
  testWidgets('lo que se escribe se va copiando', (tester) async {
    final (_, _, drafts) = await pumpLesson(tester);
    await tester.enterText(find.byType(TextField), 'A medio escribir');
    await tester.pump(const Duration(seconds: 1));
    expect(drafts.drafts[key]?.text, 'A medio escribir');
  });

  testWidgets('al abrir, lo que quedó se ofrece y se recupera', (tester) async {
    await pumpLesson(
      tester,
      leftOver: Draft(
        text: 'Lo que no se llegó a guardar',
        base: 'sha-$unitPath/es.tex',
        when: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );
    expect(find.byKey(const Key('recovered-draft')), findsOneWidget);
    // El fichero no ha cambiado desde entonces: no hay nada que advertir.
    expect(find.textContaining('ha cambiado desde entonces'), findsNothing);

    await tester.tap(find.byKey(const Key('recovered-restore')));
    await settle(tester);
    expect(find.text('Lo que no se llegó a guardar'), findsOneWidget);
    // Vuelve como cambio sin guardar: el botón de guardar, vivo.
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('editor-save')),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets('si el fichero cambió después, lo dice', (tester) async {
    await pumpLesson(
      tester,
      leftOver: Draft(
        text: 'Otro texto',
        base: 'un-sha-viejo',
        when: DateTime(2026),
      ),
    );
    expect(find.textContaining('ha cambiado desde entonces'), findsOneWidget);
  });

  testWidgets('descartarlo no lo vuelve a ofrecer', (tester) async {
    final (_, _, drafts) = await pumpLesson(
      tester,
      leftOver: Draft(text: 'Otro texto', base: '', when: DateTime(2026)),
    );
    await tester.tap(find.byKey(const Key('recovered-forget')));
    await settle(tester);
    expect(find.byKey(const Key('recovered-draft')), findsNothing);
    expect(drafts.drafts, isEmpty);
  });

  testWidgets('guardar lo borra', (tester) async {
    final (_, gateway, drafts) = await pumpLesson(tester);
    await tester.enterText(find.byType(TextField), 'Texto nuevo');
    await tester.pump(const Duration(seconds: 1));
    expect(drafts.drafts, isNotEmpty);

    await tester.tap(find.byKey(const Key('editor-save')));
    await settle(tester);
    await tapIfShown(tester, find.byKey(const Key('commit-save')));
    await settle(tester);
    expect(gateway.commits, hasLength(1));
    expect(drafts.drafts, isEmpty);
  });

  testWidgets('igual que el fichero, sobra', (tester) async {
    final (_, _, drafts) = await pumpLesson(
      tester,
      leftOver: Draft(
        text: 'El contenido original en castellano.',
        base: '',
        when: DateTime(2026),
      ),
    );
    expect(find.byKey(const Key('recovered-draft')), findsNothing);
    expect(drafts.drafts, isEmpty);
  });

  test('en disco, fuera del repositorio, y de vuelta', () async {
    final root = await Directory.systemTemp.createTemp('didacta-drafts-');
    addTearDown(() => root.delete(recursive: true));
    final store = DiskDraftStore(root: root);
    final when = DateTime(2026, 9, 25, 10, 30);
    await store.write(
      'x/uno|content/a/b/c/va.tex',
      Draft(text: 'Hola', base: 'abc', when: when),
    );
    final back = await store.read('x/uno|content/a/b/c/va.tex');
    expect(back?.text, 'Hola');
    expect(back?.base, 'abc');
    expect(back?.when, when);
    // Otra clave, otro fichero.
    expect(await store.read('x/dos|content/a/b/c/va.tex'), isNull);
    await store.delete('x/uno|content/a/b/c/va.tex');
    expect(await store.read('x/uno|content/a/b/c/va.tex'), isNull);
  });
}
