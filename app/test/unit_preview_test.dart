/// La pestaña de compilar, sin lanzar nada.
///
/// Lo que se comprueba aquí es la parte que no cubre el motor: que las dos
/// versiones que se pidieron vengan preseleccionadas, que se compile lo que
/// se eligió y no otra cosa, que un fallo se lea, y --lo que más importa--
/// que **cuando no se puede compilar la pantalla lo diga** en lugar de
/// ofrecer un botón que falla.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';
import 'package:didacta_app/ui/unit_preview.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

final Finder compile = find.byKey(const Key('compile'));

Future<FakeCompiler?> pumpPreview(
  WidgetTester tester, {
  FakeCompiler? compiler,
  bool none = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final used = none ? null : (compiler ?? FakeCompiler());
  final catalogue = catalogueWith([unitJson()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: used,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: UnitPreview(
            unit: catalogue.unitByPath(unitPath)!,
            session: session,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return used;
}

void main() {
  testWidgets('ofrece las versiones, con presentación y libro marcadas', (
    tester,
  ) async {
    await pumpPreview(tester);

    // Las dos que se pidieron, más los apuntes, preseleccionadas: son la
    // respuesta casi siempre que alguien abre esto.
    for (final label in ['Diapositivas', 'Libro', 'Apuntes']) {
      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, label),
      );
      expect(chip.selected, isTrue, reason: label);
    }
    // Y las variantes que nadie pidió, no.
    final teacher = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Apuntes (profesor)'),
    );
    expect(teacher.selected, isFalse);

    expect(find.text('Compilar 3 versiones'), findsOneWidget);
  });

  testWidgets('dice que el preámbulo lo pone Didacta', (tester) async {
    // Era la duda explícita: el preámbulo hace falta para compilar y no
    // tiene que verse en la biblioteca.
    await pumpPreview(tester);
    expect(find.textContaining('El preámbulo lo pone Didacta'), findsOneWidget);
  });

  testWidgets('compila lo elegido, y nada más', (tester) async {
    final compiler = (await pumpPreview(tester))!;

    // Se quitan los apuntes y se deja presentación y libro.
    await tester.tap(find.widgetWithText(FilterChip, 'Apuntes'));
    await settle(tester);
    await tester.tap(compile);
    await settle(tester);

    expect(compiler.calls, hasLength(1));
    expect(compiler.calls.single.profiles, ['slides', 'book']);
    expect(compiler.calls.single.language, 'es');
  });

  testWidgets('el idioma de la salida no es el que se está editando', (
    tester,
  ) async {
    // Se compila en valenciano para ver si la traducción cuadra con las
    // figuras, sin dejar de estar en la unidad.
    final compiler = (await pumpPreview(tester))!;

    await tester.tap(find.widgetWithText(ChoiceChip, 'va'));
    await settle(tester);
    await tester.tap(compile);
    await settle(tester);

    expect(compiler.calls.single.language, 'va');
  });

  testWidgets('el resultado dice páginas y abre el PDF', (tester) async {
    final compiler = (await pumpPreview(tester))!;

    await tester.tap(compile);
    await settle(tester);

    expect(find.textContaining('5 páginas'), findsOneWidget);
    expect(find.textContaining('1 página'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir el PDF').first);
    await settle(tester);
    expect(compiler.opened, ['/salida/slides-es.pdf']);
  });

  testWidgets('avisa de que la numeración será la del documento', (
    tester,
  ) async {
    // Una unidad sola sale como `0.0.1`, y decirlo evita que alguien lo tome
    // por un fallo.
    await pumpPreview(tester);
    await tester.tap(compile);
    await settle(tester);
    expect(find.textContaining('numeración de apartados'), findsOneWidget);
  });

  testWidgets('un error de LaTeX se lee, con su fichero y su línea', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        outputs: const [
          CompileOutput(
            profile: 'slides',
            language: 'es',
            ok: false,
            errors: ['es.tex:14: Undefined control sequence \\nosequence'],
          ),
        ],
      ),
    );

    await tester.tap(compile);
    await settle(tester);
    expect(
      find.textContaining('es.tex:14: Undefined control sequence'),
      findsOneWidget,
    );
  });

  testWidgets('un aviso de traducción se muestra, que es el accionable', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        outputs: const [
          CompileOutput(
            profile: 'notes',
            language: 'en',
            ok: true,
            pdf: '/salida/notes-en.pdf',
            pages: 1,
            warnings: [
              "No `en' version of `analysis/normed/definition'; using `es'",
            ],
          ),
        ],
      ),
    );

    await tester.tap(compile);
    await settle(tester);
    expect(find.textContaining("No `en' version"), findsOneWidget);
  });

  testWidgets('si el motor no arranca, lo cuenta en lugar de callarse', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        failWith: const CompileException(
          'No se pudo lanzar el motor (/no/existe/cli/didacta).',
          detail: 'No such file or directory',
        ),
      ),
    );

    await tester.tap(compile);
    await settle(tester);
    expect(find.text('La compilación no se pudo lanzar'), findsOneWidget);
    expect(find.textContaining('No such file or directory'), findsOneWidget);
  });

  testWidgets('sin nada con lo que compilar, ofrece Ajustes y no un botón', (
    tester,
  ) async {
    // El estado que de verdad importa: la web, y un escritorio sin motor
    // configurado. Un botón que no puede funcionar es peor que su ausencia
    // explicada.
    await pumpPreview(tester, none: true);

    expect(find.text('Todavía no se puede compilar aquí'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ir a Ajustes'), findsOneWidget);
    expect(compile, findsNothing);
  });

  testWidgets('falta latexmk: lo dice, con el nombre de lo que falta', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      compiler: FakeCompiler(
        ready: false,
        problem: 'Falta latexmk. Didacta necesita una distribución de TeX.',
      ),
    );

    expect(find.textContaining('Falta latexmk'), findsOneWidget);
    expect(compile, findsNothing);
  });

  testWidgets('se llega desde la pestaña de la unidad', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final catalogue = catalogueWith([unitJson()]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      compilerOverride: FakeCompiler(),
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

    await tester.tap(find.text('compilar'));
    await settle(tester);
    expect(find.text('Compilar esta unidad'), findsOneWidget);
  });
}
