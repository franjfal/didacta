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
import 'package:didacta_app/model/tex_syntax.dart';
import 'package:didacta_app/ui/tex_highlight.dart';
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
  // Ancho fijo y de sobra: la barra se encoge a iconos en los paneles
  // estrechos y rueda cuando no cabe, y una prueba que cambia de forma con el
  // tamaño de la ventana no prueba nada.
  tester.view.physicalSize = const Size(1700, 1000);
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

  testWidgets('la negrita envuelve lo marcado', (tester) async {
    await pumpUnit(tester);
    select(tester, 3, 13);
    await tester.pump();

    await tester.tap(find.byKey(const Key('wrap-textbf')));
    await tester.pump();

    expect(
      editing(tester).text,
      'El \\textbf{contenido} original en castellano.',
    );
  });

  testWidgets('la paleta de matemáticas escribe alrededor de lo marcado', (
    tester,
  ) async {
    await pumpUnit(tester);
    select(tester, 3, 13);
    await tester.pump();

    await tester.tap(find.byKey(const Key('palette-math')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snippet-√')));
    await tester.pumpAndSettle();

    expect(
      editing(tester).text,
      'El \\sqrt{contenido} original en castellano.',
    );
  });

  testWidgets('un símbolo escribe su orden, no su glifo', (tester) async {
    await pumpUnit(tester);
    select(tester, 2, 2);
    await tester.pump();

    await tester.tap(find.byKey(const Key('palette-symbols')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snippet-≤')));
    await tester.pumpAndSettle();

    // El fichero no lleva Unicode: lo que se busca es «≤» y lo que se escribe
    // es la orden.
    expect(editing(tester).text, startsWith('El\\leq '));
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

  testWidgets('el editor de una unidad pinta el LaTeX que contiene', (
    tester,
  ) async {
    await pumpUnit(
      tester,
      files: {
        '$unitPath/es.tex': '\\section{Normas}\n% nota\n',
        '$unitPath/unit.yaml': unitYaml,
        'courses/am-iii/2025-2026/year.yaml': yearYaml,
      },
    );

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(controller, isA<TexEditingController>());

    final span = controller.buildTextSpan(
      context: tester.element(find.byType(TextField)),
      style: const TextStyle(color: didactaInk),
      withComposing: false,
    );
    final coloured = {
      for (final child in span.children ?? const <InlineSpan>[])
        (child as TextSpan).text!: child.style?.color,
    };
    // Un fichero suelto calcula su propio árbol, así que la orden va de su
    // color sin que nadie le pase nada.
    expect(coloured['\\section'], didactaAlgo);
    expect(coloured['% nota'], isNot(didactaInk));
    expect(colourForToken(TexTokenKind.text), isNull);
  });

  testWidgets('sobre los campos de un problema es la misma barra', (
    tester,
  ) async {
    await pumpUnit(
      tester,
      path: problemPath,
      files: {
        '$problemPath/es.tex': '\\begin{exercise}\nDerivar.\n\\end{exercise}\n',
        '$problemPath/unit.yaml': unitYaml,
        'courses/am-iii/2025-2026/year.yaml': yearYaml,
      },
    );

    expect(find.text('Enunciado'), findsOneWidget);
    // La misma barra: lo que se aprende una vez sirve en las tres pantallas.
    expect(find.byType(TexToolbar), findsOneWidget);

    // Y escribe en el campo que tiene el cursor.
    final statement = find.descendant(
      of: find.byKey(const Key('problem-exercise')),
      matching: find.byType(TextField),
    );
    await tester.tap(statement);
    await tester.pump();
    tester.widget<TextField>(statement).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pump();

    await tester.tap(find.byKey(const Key('wrap-textbf')));
    await tester.pump();
    expect(
      tester.widget<TextField>(statement).controller!.text,
      startsWith('\\textbf{Derivar}'),
    );

    // Menos lo que aquí sería mentira: envolver la respuesta en `answer`.
    await tester.tap(find.byKey(const Key('wrap-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Problema'), findsNothing);
    expect(find.text('Teoría'), findsOneWidget);
  });
}
