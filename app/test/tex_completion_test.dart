/// La lista de completar, en el editor de una lección.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

final Finder list = find.byKey(const Key('tex-completion'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final catalogue = catalogueWith([unitJson()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(files: {'$unitPath/es.tex': ''}),
    catalogue: catalogue,
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
}

TextEditingController editing(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!;

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await settle(tester);
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settle(tester);
}

void main() {
  testWidgets('una orden se completa con Intro, con el cursor dentro', (
    tester,
  ) async {
    await pumpEditor(tester);
    await type(tester, r'\didac');
    expect(list, findsOneWidget);
    expect(
      find.byKey(const Key('tex-completion-didactatitle')),
      findsOneWidget,
    );

    await press(tester, LogicalKeyboardKey.enter);
    expect(list, findsNothing);
    expect(editing(tester).text, r'\didactatitle{}');
    expect(editing(tester).selection.baseOffset, r'\didactatitle{'.length);
  });

  testWidgets(r'\begin{ ofrece los entornos y escribe su \end', (tester) async {
    await pumpEditor(tester);
    await type(tester, r'\begin{comm');
    expect(
      find.byKey(const Key('tex-completion-commonmistake')),
      findsOneWidget,
    );
    await press(tester, LogicalKeyboardKey.tab);
    expect(
      editing(tester).text,
      '\\begin{commonmistake}\n\n\\end{commonmistake}',
    );
    expect(
      editing(tester).selection.baseOffset,
      '\\begin{commonmistake}\n'.length,
    );
  });

  testWidgets('con las flechas se elige otra', (tester) async {
    await pumpEditor(tester);
    await type(tester, r'$\Om');
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    expect(editing(tester).text, r'$\omega ');
  });

  testWidgets('Esc la cierra, y seguir escribiendo no la vuelve a abrir', (
    tester,
  ) async {
    await pumpEditor(tester);
    await type(tester, r'\onl');
    expect(list, findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(list, findsNothing);
    await type(tester, r'\only');
    expect(list, findsNothing);
    // Otra orden, sí.
    await type(tester, r'\only \key');
    expect(list, findsOneWidget);
  });

  testWidgets('con el ratón también', (tester) async {
    await pumpEditor(tester);
    await type(tester, r'\bym');
    await tester.tap(find.byKey(const Key('tex-completion-bymedium')));
    await settle(tester);
    expect(editing(tester).text, r'\bymedium{}{}');
  });

  testWidgets('sin nada que completar, no hay lista', (tester) async {
    await pumpEditor(tester);
    await type(tester, 'Texto normal, sin órdenes.');
    expect(list, findsNothing);
    await type(tester, r'fin de línea\\');
    expect(list, findsNothing);
  });
}
