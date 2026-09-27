/// Editar una lección que se da en más de un curso.
///
/// Una lección es una sola carpeta aunque la llamen tres composiciones, y
/// guardarla la cambia en las tres. El «Se da en» del panel lo decía, pero el
/// panel se puede tener cerrado: esto fija que el aviso esté **encima del
/// texto**, que diga cuáles, y que no salga cuando no hay nada que avisar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

Future<FakeSession> pumpLesson(
  WidgetTester tester, {
  required List<Map<String, String>> usedBy,
  bool writable = true,
  bool panel = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith([unitJson(usedBy: usedBy)]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(writable: writable),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  await session.setUnitPanelVisible(panel);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(body: UnitPage(unitPath: unitPath)),
      ),
    ),
  );
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return session;
}

const threeCourses = [
  {'course': 'am-iii', 'year': '2025-2026', 'document': 'tema-1'},
  {'course': 'am-iii', 'year': '2025-2026', 'document': 'examen'},
  {'course': 'am-iii', 'year': '2024-2025', 'document': 'tema-1'},
  {'course': 'topologia', 'year': '2025-2026', 'document': 'tema-2'},
];

final Finder strip = find.byKey(const Key('shared-lesson-strip'));

void main() {
  testWidgets('dice en cuántos cursos se da y cuáles, con el panel cerrado', (
    tester,
  ) async {
    await pumpLesson(tester, usedBy: threeCourses);
    expect(strip, findsOneWidget);
    // Cursos académicos, no composiciones: el tema y el examen del mismo
    // curso cuentan una vez.
    final text = tester.widget<Text>(
      find.descendant(of: strip, matching: find.byType(Text)).first,
    );
    final said = text.textSpan!.toPlainText();
    expect(said, startsWith('Se da en 3 cursos'));
    expect(said, contains('2024-2025'));
    expect(said, contains('topologia 2025-2026'));
    expect(said, contains('cambia en todos'));
  });

  testWidgets('ofrece separar una copia', (tester) async {
    await pumpLesson(tester, usedBy: threeCourses);
    expect(find.byKey(const Key('shared-lesson-split')), findsOneWidget);
  });

  testWidgets('en un solo curso no hay nada que avisar', (tester) async {
    await pumpLesson(
      tester,
      usedBy: const [
        {'course': 'am-iii', 'year': '2025-2026', 'document': 'tema-1'},
        {'course': 'am-iii', 'year': '2025-2026', 'document': 'examen'},
      ],
    );
    expect(strip, findsNothing);
  });

  testWidgets('sin poder escribir, tampoco: no se va a guardar nada', (
    tester,
  ) async {
    await pumpLesson(tester, usedBy: threeCourses, writable: false);
    expect(strip, findsNothing);
  });
}
