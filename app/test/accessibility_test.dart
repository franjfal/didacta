/// Lo básico para usar Didacta sin ratón o con un lector de pantalla.
///
/// No había ni un `Semantics` en toda la aplicación, y las filas pulsables no
/// recibían foco ni respondían a Intro: la navegación principal no se podía
/// usar con el teclado.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/ui/tabs.dart';
import 'package:didacta_app/ui/theme.dart';

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: didactaTheme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('una fila pulsable', () {
    Widget row(VoidCallback onTap) => Hoverable(
      onTap: onTap,
      builder: (context, hovering) => const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Análisis Matemático III'),
      ),
    );

    testWidgets('se alcanza con el tabulador y se pulsa con Intro', (
      tester,
    ) async {
      var taps = 0;
      await pump(tester, row(() => taps += 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('y un lector de pantalla sabe que es un botón', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, row(() {}));
      expect(
        tester.getSemantics(find.text('Análisis Matemático III')),
        matchesSemantics(
          label: 'Análisis Matemático III',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('con el foco, se ve dónde está', (tester) async {
      var hovering = false;
      await pump(
        tester,
        Hoverable(
          onTap: () {},
          builder: (context, over) {
            hovering = over;
            return const Text('fila');
          },
        ),
      );
      expect(hovering, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // El mismo resalte que al pasar el ratón.
      expect(hovering, isTrue);
    });
  });

  testWidgets('el estado de un idioma se dice, no solo se colorea', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      DidactaTab(
        label: 'va',
        selected: false,
        dirty: false,
        onTap: () {},
        status: TranslationStatus.draft,
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp('estado: sin revisar')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
