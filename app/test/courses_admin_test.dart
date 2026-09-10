/// La administración de asignaturas, desde la pantalla.
///
/// Lo que hay que demostrar aquí no es que los diálogos se abran, sino tres
/// cosas que se pueden hacer mal sin que se note:
///
/// * **nada se borra sin ver antes qué se lleva**. Un «¿seguro?» no es una
///   decisión; «se van 2 cursos y 77 documentos» sí, y el recuento lo pone el
///   motor;
/// * **el catálogo se recarga después**. Se genera aparte, así que crear una
///   asignatura y no recargar deja la pantalla sin lo que acaba de crear, y
///   parece que no funcionó;
/// * **en la web no hay botones**. Sin clon y sin motor no se puede
///   administrar nada, y ofrecer el botón para luego explicar que no puede
///   ser es peor que no ofrecerlo.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/course_admin_ui.dart';
import 'package:didacta_app/ui/courses_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class Harness {
  Harness(this.session, this.engine, this.clone);

  final FakeSession session;
  final FakeCompiler engine;
  final FakeClone? clone;
}

/// Monta una pantalla con administración disponible, o sin ella.
Future<Harness> pump(
  WidgetTester tester,
  Widget page, {
  bool withAdmin = true,
  bool changed = true,
  Map<String, String> answers = const {},
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final engine = FakeCompiler();
  answers.forEach((key, value) => engine.answers[key] = value);

  final clone = withAdmin ? FakeClone(changed: changed) : null;
  final admin = clone == null
      ? null
      : CourseAdmin(
          compiler: engine,
          clone: clone,
          author: (name: 'Javier', email: 'javier@uv.es'),
          token: '',
          pushOnCommit: false,
        );

  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: engine,
    adminOverride: admin,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await settle(tester);
  return Harness(session, engine, clone);
}

void main() {
  group('en la web no hay administración', () {
    testWidgets('ni botón de asignatura nueva ni menú de la fila', (
      tester,
    ) async {
      await pump(tester, const CoursesPage(), withAdmin: false);

      expect(find.byKey(const Key('new-course')), findsNothing);
      expect(find.byKey(const Key('course-menu-am-iii')), findsNothing);
      // Y la asignatura sigue viéndose: lo que falta es editarla, no verla.
      expect(find.text('Análisis Matemático III'), findsOneWidget);
    });

    testWidgets('ni el botón de quitar el curso académico', (tester) async {
      await pump(
        tester,
        const YearPage(courseId: 'am-iii', year: '2025-2026'),
        withAdmin: false,
      );
      expect(find.byKey(const Key('remove-year')), findsNothing);
    });
  });

  group('quitar una asignatura', () {
    testWidgets('enseña el recuento del motor antes de borrar', (tester) async {
      final harness = await pump(
        tester,
        const CoursesPage(),
        answers: {'remove course': '  2 año(s)\n  77 documento(s)\n'},
      );

      await tester.tap(find.byKey(const Key('course-menu-am-iii')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('remove-am-iii')));
      await settle(tester);

      expect(
        find.text('Esto se lleva 2 cursos académicos y 77 documentos.'),
        findsOneWidget,
      );
      // Lo que **no** se va, que es lo que evita el susto.
      expect(find.textContaining('Las unidades no se tocan'), findsOneWidget);
      expect(find.textContaining('se puede revertir'), findsOneWidget);

      // Y hasta aquí no se ha aplicado nada.
      expect(harness.engine.commands.single, isNot(contains('--apply')));
    });

    testWidgets('cancelar no toca nada', (tester) async {
      final harness = await pump(
        tester,
        const CoursesPage(),
        answers: {'remove course': '  2 año(s)\n  77 documento(s)\n'},
      );

      await tester.tap(find.byKey(const Key('course-menu-am-iii')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('remove-am-iii')));
      await settle(tester);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);

      expect(harness.engine.commands, hasLength(1));
      expect(harness.session.reloads, 0);
    });

    testWidgets('confirmar aplica y recarga el catálogo', (tester) async {
      final harness = await pump(
        tester,
        const CoursesPage(),
        answers: {'remove course': '  2 año(s)\n  77 documento(s)\n'},
      );

      await tester.tap(find.byKey(const Key('course-menu-am-iii')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('remove-am-iii')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirm-removal')));
      await settle(tester);

      expect(harness.engine.commands.last, [
        'remove',
        'course',
        '--apply',
        '--',
        'am-iii',
      ]);
      expect(
        harness.session.reloads,
        1,
        reason: 'sin recargar, la pantalla sigue enseñando lo que ya no está',
      );
      expect(find.textContaining('quitada como un commit'), findsOneWidget);

      // Un commit, con la asignatura dentro y nada más, firmado.
      final commit = harness.clone!.commits.single;
      expect(commit.paths, ['courses/am-iii']);
      expect(
        commit.message,
        'Quitar la asignatura «Análisis Matemático III» (am-iii)',
      );
      expect(commit.author, 'Javier <javier@uv.es>');
    });

    testWidgets('si el motor falla se dice, y no se recarga', (tester) async {
      final harness = await pump(
        tester,
        const CoursesPage(),
        answers: {'remove course': '  1 año(s)\n  3 documento(s)\n'},
        // El motor termina y no cambió nada, que es el caso de borrar algo
        // que ya no estaba.
        changed: false,
      );

      await tester.tap(find.byKey(const Key('course-menu-am-iii')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('remove-am-iii')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirm-removal')));
      await settle(tester);

      expect(find.textContaining('no cambió nada'), findsOneWidget);
      expect(harness.session.reloads, 0);
    });
  });

  group('quitar un curso académico', () {
    testWidgets('avisa de que es el único que tiene', (tester) async {
      final harness = await pump(
        tester,
        const YearPage(courseId: 'am-iii', year: '2025-2026'),
        answers: {'remove year': '  1 año(s)\n  2 documento(s)\n'},
      );

      await tester.tap(find.byKey(const Key('remove-year')));
      await settle(tester);

      expect(find.textContaining('el único curso'), findsOneWidget);
      // En singular donde toca: «1 curso académicos» hace dudar del
      // recuento, y el recuento es lo único que hay para decidir.
      expect(
        find.text('Esto se lleva 1 curso académico y 2 documentos.'),
        findsOneWidget,
      );
      expect(harness.engine.commands.single, [
        'remove',
        'year',
        '--',
        'am-iii',
        '2025-2026',
      ]);
    });
  });

  group('duplicar un curso académico', () {
    testWidgets('propone el año siguiente ya escrito', (tester) async {
      await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('add-year-am-iii')));
      await settle(tester);

      final field = tester.widget<TextField>(find.byKey(const Key('new-year')));
      expect(field.controller!.text, '2026-2027');
    });

    testWidgets('un año que ya existe no se puede crear', (tester) async {
      await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('add-year-am-iii')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('new-year')), '2025-2026');
      await settle(tester);

      expect(find.text('Ya existe'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('confirm-duplicate')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('mal escrito tampoco, y lo dice', (tester) async {
      await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('add-year-am-iii')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('new-year')), '2026');
      await settle(tester);

      expect(find.textContaining('Se escribe'), findsOneWidget);
    });

    testWidgets('crear pasa el año y de cuál copiarlo', (tester) async {
      final harness = await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('add-year-am-iii')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirm-duplicate')));
      await settle(tester);

      expect(harness.engine.commands.single, [
        'new',
        'year',
        '--from',
        '2025-2026',
        '--',
        'am-iii',
        '2026-2027',
      ]);
      expect(harness.session.reloads, 1);
      expect(harness.clone!.commits.single.paths, ['courses/am-iii/2026-2027']);
    });
  });

  group('una asignatura nueva', () {
    testWidgets('el identificador se deduce del título', (tester) async {
      await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('new-course')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('new-course-title')),
        'Análisis Matemático III (grupo B)',
      );
      await settle(tester);

      final id = tester.widget<TextField>(
        find.byKey(const Key('new-course-id')),
      );
      expect(id.controller!.text, 'analisis-matematico-iii-grupo-b');
    });

    testWidgets('un identificador escrito a mano no se sobreescribe', (
      tester,
    ) async {
      // Si el título se retoca después, cambiar el id por debajo cambiaría la
      // carpeta y lo que se referencia sin que nadie lo pida.
      await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('new-course')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('new-course-id')), 'am-iv');
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('new-course-title')),
        'Análisis IV',
      );
      await settle(tester);

      final id = tester.widget<TextField>(
        find.byKey(const Key('new-course-id')),
      );
      expect(id.controller!.text, 'am-iv');
    });

    testWidgets('un identificador que ya existe no se puede crear', (
      tester,
    ) async {
      await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('new-course')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('new-course-title')),
        'Análisis Matemático III, grupo B',
      );
      await settle(tester);
      // El id de la que ya está en el catálogo.
      await tester.enterText(find.byKey(const Key('new-course-id')), 'am-iii');
      await settle(tester);

      expect(find.text('Ya existe'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('confirm-new-course')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('crear pasa el título, el idioma y el id detrás de --', (
      tester,
    ) async {
      final harness = await pump(tester, const CoursesPage());

      await tester.tap(find.byKey(const Key('new-course')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('new-course-title')),
        'Topología',
      );
      await settle(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'va'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirm-new-course')));
      await settle(tester);

      expect(harness.engine.commands.single, [
        'new',
        'course',
        '--title',
        'Topología',
        '--lang',
        'va',
        '--',
        'topologia',
      ]);
      expect(find.textContaining('creada como un commit'), findsOneWidget);
      expect(harness.session.reloads, 1);
      expect(harness.clone!.commits.single.paths, ['courses/topologia']);
    });
  });

  group('el diálogo de borrar, por su cuenta', () {
    testWidgets('no deja confirmar hasta que hay recuento', (tester) async {
      // Mientras el motor cuenta, «Quitar» está apagado: confirmar a ciegas
      // es exactamente lo que este diálogo existe para impedir.
      final waiting = Completer<RemovalPreview>();
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await confirmRemoval(
                context,
                title: '¿Quitar?',
                preview: () => waiting.future,
                warning: 'Nada más se toca.',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await settle(tester);

      expect(find.textContaining('Contando'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-removal')))
            .onPressed,
        isNull,
      );

      waiting.complete(
        const RemovalPreview(what: 'x', years: 1, documents: 4, detail: ''),
      );
      await settle(tester);
      expect(
        find.text('Esto se lleva 1 curso académico y 4 documentos.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('confirm-removal')));
      await settle(tester);
      expect(answer, isTrue);
    });

    testWidgets('si el recuento falla, se ve el error y no un cero', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmRemoval(
                context,
                title: '¿Quitar?',
                preview: () async =>
                    throw const AdminException('No encuentro el motor'),
                warning: 'Nada más se toca.',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await settle(tester);

      expect(find.textContaining('No encuentro el motor'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-removal')))
            .onPressed,
        isNull,
      );
    });
  });
}
