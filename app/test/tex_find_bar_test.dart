/// Buscar en el editor de una lección.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/tex_field.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const String text = 'Una norma.\nOtra norma.\nY la tercera Norma.\n';

final Finder bar = find.byKey(const Key('find-bar'));
final Finder query = find.descendant(
  of: find.byKey(const Key('find-query')),
  matching: find.byType(TextField),
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpEditor(WidgetTester tester, {String? problem}) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(
      files: {'$unitPath/es.tex': text, if (problem != null) ...{}},
    ),
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

/// El texto de la lección, no el de la barra.
TextEditingController editing(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byType(TexField),
        matching: find.byType(TextField),
      ),
    )
    .controller!;

Future<void> openFind(WidgetTester tester, {bool tap = true}) async {
  // El foco en el texto, como cuando se está escribiendo, y el cursor al
  // principio: la búsqueda empieza donde está el cursor.
  if (tap) {
    await tester.tap(
      find.descendant(
        of: find.byType(TexField),
        matching: find.byType(TextField),
      ),
    );
    await settle(tester);
    editing(tester).selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
  }
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await settle(tester);
}

String count(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('find-count'))).data!;

void main() {
  testWidgets('Ctrl+F abre la barra, y cuenta lo que encuentra', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(bar, findsNothing);
    await openFind(tester);
    expect(bar, findsOneWidget);

    await tester.enterText(query, 'norma');
    await settle(tester);
    // Sin mirar mayúsculas: también la «Norma» de la tercera línea.
    expect(count(tester), '1 de 3');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(count(tester), '2 de 3');

    await tester.tap(find.byKey(const Key('find-case')));
    await settle(tester);
    expect(count(tester), endsWith('de 2'));

    await tester.enterText(query, 'nada de esto');
    await settle(tester);
    expect(count(tester), 'Sin resultados');
  });

  testWidgets('Esc cierra y deja seleccionada la que se miraba', (
    tester,
  ) async {
    await pumpEditor(tester);
    await openFind(tester);
    await tester.enterText(query, 'tercera');
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(bar, findsNothing);
    final selection = editing(tester).selection;
    expect(selection.textInside(text), 'tercera');
  });

  testWidgets('lo seleccionado es lo que se busca', (tester) async {
    await pumpEditor(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(TexField),
        matching: find.byType(TextField),
      ),
    );
    await settle(tester);
    editing(tester).selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 9,
    );
    await tester.pump();
    await openFind(tester, tap: false);
    expect(tester.widget<TextField>(query).controller!.text, 'norma');
    expect(count(tester), isNotEmpty);
  });

  testWidgets('reemplazar una y todas', (tester) async {
    await pumpEditor(tester);
    // Reemplazar es de la interfaz completa.
    await openFind(tester);
    expect(find.byKey(const Key('find-replace-toggle')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await useCompleteInterface(tester);
    await openFind(tester);
    await tester.enterText(query, 'norma');
    await settle(tester);
    await tester.tap(find.byKey(const Key('find-replace-toggle')));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('find-replacement')),
        matching: find.byType(TextField),
      ),
      'métrica',
    );
    await settle(tester);

    await tester.tap(find.byKey(const Key('find-replace-one')));
    await settle(tester);
    expect(editing(tester).text, startsWith('Una métrica.\nOtra norma.'));
    expect(count(tester), '1 de 2');

    await tester.tap(find.byKey(const Key('find-replace-all')));
    await settle(tester);
    expect(
      editing(tester).text,
      'Una métrica.\nOtra métrica.\nY la tercera métrica.\n',
    );
    expect(count(tester), '2 reemplazadas');
    // Es un cambio sin guardar, como cualquier otro.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('editor-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('una expresión mal escrita lo dice', (tester) async {
    await pumpEditor(tester);
    await openFind(tester);
    await tester.tap(find.byKey(const Key('find-regex')));
    await settle(tester);
    await tester.enterText(query, '(norma');
    await settle(tester);
    expect(count(tester), 'La expresión no es válida');
  });
}
