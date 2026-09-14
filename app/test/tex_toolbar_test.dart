/// La barra de entornos, en la pantalla.
///
/// La lógica de envolver está probada aparte; lo que se demuestra aquí es lo
/// que solo se ve montado: que la barra escribe **por el mismo controlador**
/// que el editor —así que guardar, el diff y el aviso de conflicto siguen
/// siendo los mismos—, que no aparece donde no significa nada, y que no
/// ofrece escribir a quien no puede.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/tex_toolbar.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const String problemPath = 'problems/analysis/normed/exercises';

final Finder slides = find.byKey(const Key('wrap-onlyslides'));
final Finder save = find.byKey(const Key('editor-save'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpUnit(
  WidgetTester tester, {
  String path = unitPath,
  bool writable = true,
  Map<String, String>? files,
}) async {
  // Ancho fijo: la barra se encoge a iconos en los paneles estrechos, y una
  // prueba que cambia de forma con el tamaño de la ventana no prueba nada.
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final gateway = FakeGateway(writable: writable, files: files);
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: UnitPage(unitPath: path)),
      ),
    ),
  );
  await settle(tester);
}

/// El controlador que está editando la pantalla.
TextEditingController editing(WidgetTester tester) =>
    tester.widget<TexToolbar>(find.byType(TexToolbar).first).controller;

void select(WidgetTester tester, int start, int end) {
  editing(tester).selection = TextSelection(
    baseOffset: start,
    extentOffset: end,
  );
}

void main() {
  testWidgets('sin cursor no hay nada que envolver', (tester) async {
    await pumpUnit(tester);

    // Recién abierto el fichero, el cursor no está en ninguna parte:
    // envolver «el párrafo 0» sería una edición que nadie ha pedido.
    expect((tester.widget(slides) as dynamic).onPressed, isNull);
  });

  testWidgets('envolver la selección escribe por el editor', (tester) async {
    await pumpUnit(tester);
    select(tester, 0, 36);
    await tester.pump();

    await tester.tap(slides);
    await tester.pump();

    expect(
      editing(tester).text,
      r'\onlyslides{El contenido original en castellano.}',
    );
    // Y queda sin guardar: la barra no tiene un camino propio hasta el
    // fichero, escribe donde escribe el teclado.
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('el mismo botón lo quita', (tester) async {
    await pumpUnit(tester);
    select(tester, 0, 36);
    await tester.pump();

    await tester.tap(slides);
    await tester.pump();
    // Con el cuerpo marcado, el botón ya dice que lo que hará es quitarlo.
    expect(find.byTooltip('Quitar «Solo diapositivas»'), findsOneWidget);

    await tester.tap(slides);
    await tester.pump();

    expect(editing(tester).text, 'El contenido original en castellano.');
  });

  testWidgets('sin permiso de escritura la barra se ve apagada', (
    tester,
  ) async {
    await pumpUnit(tester, writable: false);
    select(tester, 0, 36);
    await tester.pump();

    // Apagada y no escondida: una barra que desaparece según quién mire es
    // una pantalla que nadie sabe describir.
    expect(find.byType(TexToolbar), findsOneWidget);
    expect((tester.widget(slides) as dynamic).onPressed, isNull);
  });

  testWidgets('sobre los campos de un problema no aparece', (tester) async {
    await pumpUnit(
      tester,
      path: problemPath,
      files: {
        '$problemPath/es.tex': '\\begin{exercise}\nDerivar.\n\\end{exercise}\n',
        '$problemPath/unit.yaml': unitYaml,
        'courses/am-iii/2025-2026/year.yaml': yearYaml,
      },
    );

    // El entorno lo pone el campo: un botón «Respuesta» encima del campo de
    // la respuesta no significa nada.
    expect(find.text('Enunciado'), findsOneWidget);
    expect(find.byType(TexToolbar), findsNothing);
  });
}
