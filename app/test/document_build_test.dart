/// Compilar el tema entero desde su pantalla.
///
/// La diferencia con compilar una lección suelta no es de tamaño: una lección
/// compilada por su cuenta dice si esa lección está bien; el tema dice si
/// **la clase** está bien --su portada, su orden, sus referencias cruzadas--
/// que es la pregunta que se hace la víspera. Antes la pantalla del tema solo
/// enseñaba el comando a copiar en un terminal.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/document_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeCompiler> pumpDocument(
  WidgetTester tester, {
  FakeCompiler? compiler,
  String documentId = 'tema-1',
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final used = compiler ?? FakeCompiler();
  final catalogue = catalogueWith(defaultUnits());
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
          body: DocumentPage(
            courseId: 'am-iii',
            year: '2025-2026',
            documentId: documentId,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return used;
}

void main() {
  testWidgets('la pantalla del tema tiene su pestaña de compilar', (
    tester,
  ) async {
    await pumpDocument(tester);
    expect(find.text('Compilar'), findsOneWidget);
    expect(find.textContaining('Composición'), findsOneWidget);
  });

  testWidgets('ofrece las versiones que el motor dice, no las que se inventa', (
    tester,
  ) async {
    // Las del documento y las demás de su familia: el mismo tema se quiere en
    // libro un día y en diapositivas otro.
    await pumpDocument(tester);
    await tester.tap(find.text('Compilar'));
    await settle(tester);

    expect(find.text('Diapositivas'), findsOneWidget);
    expect(find.text('Libro'), findsOneWidget);
    expect(find.text('Apuntes'), findsOneWidget);
  });

  testWidgets('compila el documento entero, no sus unidades', (tester) async {
    final compiler = await pumpDocument(tester);
    await tester.tap(find.text('Compilar'));
    await settle(tester);

    await tester.tap(find.textContaining('Compilar').last);
    await settle(tester);

    // La referencia que usa el motor: `curso@año/documento`. Los ids se
    // repiten entre asignaturas, así que el nombre a secas no vale.
    expect(compiler.documentCalls.single.document, 'am-iii@2025-2026/tema-1');
    // Y ninguna llamada de unidad: son dos cosas distintas.
    expect(compiler.calls, isEmpty);
  });

  testWidgets('lo compilado se abre en pestañas, una por versión', (
    tester,
  ) async {
    final compiler = FakeCompiler(
      outputs: const [
        CompileOutput(
          profile: 'slides',
          language: 'es',
          ok: true,
          pdf: '/salida/slides-es.pdf',
          pages: 24,
        ),
        CompileOutput(
          profile: 'slides',
          language: 'va',
          ok: true,
          pdf: '/salida/slides-va.pdf',
          pages: 24,
        ),
        CompileOutput(
          profile: 'book',
          language: 'es',
          ok: true,
          pdf: '/salida/book-es.pdf',
          pages: 61,
        ),
      ],
    );
    await pumpDocument(tester, compiler: compiler);
    await tester.tap(find.text('Compilar'));
    await settle(tester);
    await tester.tap(find.textContaining('Compilar').last);
    await settle(tester);

    // Una pestaña por versión; los dos idiomas de las diapositivas van
    // dentro de la misma, lado a lado, que es lo que permite compararlas.
    expect(find.text('slides · es va'), findsOneWidget);
    expect(find.text('book · es'), findsOneWidget);
  });

  testWidgets('sin motor lo dice, y no ofrece un botón que falla', (
    tester,
  ) async {
    await pumpDocument(
      tester,
      compiler: FakeCompiler(ready: false, problem: 'No encuentro latexmk.'),
    );
    await tester.tap(find.text('Compilar'));
    await settle(tester);

    expect(find.textContaining('No encuentro latexmk'), findsOneWidget);
  });

  testWidgets('la composición sigue siendo la primera pestaña', (tester) async {
    // Lo primero que se quiere ver de un tema es qué lleva dentro.
    await pumpDocument(tester);
    expect(find.text('Espacios normados'), findsOneWidget);
  });
}
