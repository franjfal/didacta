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
  List<Map<String, dynamic>>? profiles,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final used = compiler ?? FakeCompiler();
  final catalogue = catalogueWith(defaultUnits(), profiles: profiles);
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

  testWidgets('ofrece lo que el tema permite, y nada más', (tester) async {
    // La lista del `year.yaml` es una **restricción**, no una sugerencia: si
    // alguien decidió que de este tema no salen libros, el menú de compilar
    // no es el sitio para saltárselo. Dentro de lo que quede sí se elige, que
    // es para lo que está el diálogo.
    await pumpDocument(tester);
    await tester.tap(find.text('Compilar'));
    await settle(tester);

    expect(find.text('Diapositivas'), findsOneWidget);
    expect(find.text('Apuntes'), findsOneWidget);
    expect(find.text('Libro'), findsNothing);
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
    await tester.tap(find.byKey(const Key('compile')));
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

  testWidgets('la composición se ve por apartados, y con el tipo de cada uno', (
    tester,
  ) async {
    // Dos preguntas que una lista plana no contesta: dónde acaba un bloque y
    // empieza otro, y cuál de estas filas es la explicación y cuál el
    // ejercicio.
    await pumpDocument(tester);

    expect(find.text('Normas'), findsOneWidget, reason: 'el apartado');
    expect(find.text('teoría'), findsWidgets, reason: 'el tipo, con su nombre');
  });

  group('sin traducir no se compila', () {
    // Compilar un tema en valenciano con cinco unidades en castellano da un
    // PDF que no se puede llevar a clase. Antes salía igual, con un aviso
    // dentro; ahora no sale, y en su lugar está la lista de lo que falta.

    Future<void> chooseLanguage(WidgetTester tester, String code) async {
      await tester.tap(find.text('Compilar'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilterChip, code));
      await settle(tester);
    }

    testWidgets('lo dice, y dice qué falta', (tester) async {
      final compiler = await pumpDocument(tester);
      await chooseLanguage(tester, 'va');

      expect(find.textContaining('No se puede compilar'), findsOneWidget);
      expect(find.textContaining('Espacios normados'), findsWidgets);
      expect(find.textContaining('traducir a va'), findsWidgets);
      expect(compiler.documentCalls, isEmpty);
    });

    testWidgets('y el botón está apagado', (tester) async {
      // Enterarte de que no se puede después de esperar la compilación es la
      // peor forma de enterarse.
      await pumpDocument(tester);
      await chooseLanguage(tester, 'va');

      expect(
        tester.widget<FilledButton>(find.byKey(const Key('compile'))).onPressed,
        isNull,
      );
    });

    testWidgets('una referencia rota no cuenta como traducción', (
      tester,
    ) async {
      // `analysis/normed/no-existe` no está en el catálogo: eso es otra cosa
      // --se dice en la composición, en rojo-- y meterla aquí haría que
      // «traducir esto» no se pudiera terminar nunca.
      final compiler = await pumpDocument(tester);
      await tester.tap(find.text('Compilar'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('compile')));
      await settle(tester);

      expect(compiler.documentCalls, hasLength(1));
    });
  });

  group('las tres versiones de lo que lleva ejercicios', () {
    // Un tema con ejercicios dentro se entrega de tres formas: el enunciado
    // solo, el enunciado con el resultado para que se corrijan ellos, y la
    // del profesor con la solución paso a paso. Las tres salen de la misma
    // fuente; lo único que hace falta es poder decir cuál se quiere.

    Future<FakeCompiler> pumpProblems(WidgetTester tester) async {
      // Las mismas tres en las dos capas: el catálogo decide qué se ofrece
      // --es quien manda desde que hay plantillas-- y el compilador las
      // recibe ya elegidas.
      final compiler = FakeCompiler(profiles: problemProfiles)
        ..documentProfileList = problemProfiles;
      // La hoja de problemas del ejemplo, que no restringe nada: lo que se
      // ofrece sale de su bloque, y ahí están las tres.
      await pumpDocument(
        tester,
        compiler: compiler,
        documentId: 'hoja-1',
        profiles: problemProfilesJson,
      );
      await tester.tap(find.text('Compilar'));
      await settle(tester);
      return compiler;
    }

    testWidgets('están las tres, y cada una dice qué lleva dentro', (
      tester,
    ) async {
      await pumpProblems(tester);

      expect(find.text('Hoja de problemas'), findsOneWidget);
      expect(find.text('Hoja de problemas (con resultados)'), findsOneWidget);
      expect(find.text('Hoja de problemas (profesor)'), findsOneWidget);

      // La etiqueta no basta: entre `problems` y `problems-answers` lo que se
      // decide es qué ve un alumno, y eso se dice con todas las letras.
      expect(find.text('solo los enunciados'), findsOneWidget);
      expect(find.text('enunciados y resultados'), findsOneWidget);
      expect(find.text('todo, con la solución paso a paso'), findsOneWidget);
    });

    testWidgets('la marcada de entrada no regala nada', (tester) async {
      // Compilar sin mirar tiene que dar la hoja del alumno. Repartir por
      // error la que lleva las soluciones no se deshace.
      await pumpProblems(tester);

      final chosen = [
        for (final profile in problemProfiles)
          if (tester
              .widget<FilterChip>(find.byKey(Key('profile-${profile.id}')))
              .selected)
            profile,
      ];
      expect(chosen.map((p) => p.id), ['problems']);
      expect(chosen.every((p) => !p.givesAway), isTrue);
    });

    testWidgets('se pueden pedir las tres a la vez', (tester) async {
      // Es lo normal la víspera: la hoja para clase, la de resultados para
      // colgar después y la del profesor para corregir.
      final compiler = await pumpProblems(tester);
      await tester.tap(find.byKey(const Key('profile-problems-answers')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('profile-problems-teacher')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('compile')));
      await settle(tester);

      expect(compiler.documentCalls.single.profiles, [
        'problems',
        'problems-answers',
        'problems-teacher',
      ]);
    });
  });
}
