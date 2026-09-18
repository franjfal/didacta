/// Qué se ve en la lista de asignaturas, y qué se puede dejar de ver.
///
/// Después de unos años dando clase la lista son veinte asignaturas de las que
/// se dan tres, y cada una con seis cursos académicos de los que interesa el
/// último. Ocultar y plegar son las dos formas de que esa lista vuelva a caber
/// en una pantalla.
///
/// Lo que estas pruebas fijan, y que es lo que hace que no den miedo:
///
/// * **ocultar no es quitar.** La asignatura sigue en el catálogo, sigue
///   compilando y sigue en la biblioteca;
/// * **siempre se puede deshacer.** La vista «las ocultas» enseña lo que se
///   escondió, también los cursos de una asignatura que no está oculta;
/// * **marcar no reordena.** La estrella dice «esta me importa», no «esta va
///   primero»: la lista se queda donde se aprendió que estaba.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/courses_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> courseJsonWith(
  String id,
  String title,
  List<String> years,
) => {
  'id': id,
  'title': {'es': title},
  'language': 'es',
  'years': {
    for (final year in years)
      year: {
        'year': year,
        'language': 'es',
        'documents': const <Map<String, dynamic>>[],
      },
  },
};

Future<FakeSession> pumpCourses(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(
    const [],
    courses: [
      courseJsonWith('am-i', 'Análisis Matemático I', [
        '2026-2027',
        '2024-2025',
      ]),
      courseJsonWith('alg', 'Álgebra', ['2025-2026']),
    ],
  );
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(body: CoursesPage()),
      ),
    ),
  );
  await settle(tester);
  return session;
}

Future<void> chooseView(WidgetTester tester, CoursesView view) async {
  await tester.tap(find.byKey(const Key('courses-view')));
  await settle(tester);
  await tester.tap(find.byKey(Key('courses-view-${view.name}')));
  await settle(tester);
}

void main() {
  testWidgets('ocultar una asignatura la saca de la lista, no del material', (
    tester,
  ) async {
    final session = await pumpCourses(tester);
    expect(find.text('Álgebra'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hide-course-alg')));
    await settle(tester);

    expect(find.text('Álgebra'), findsNothing);
    // Sigue estando: lo que cambió es esta lista.
    expect(session.catalogue.courses, hasLength(2));
    expect(session.isHiddenCourse('alg'), isTrue);
    // Y se dice cuántas no se están enseñando, que si no la lista mentiría.
    expect(find.textContaining('1 sin enseñar'), findsOneWidget);
  });

  testWidgets('y se puede volver a enseñar desde «las ocultas»', (
    tester,
  ) async {
    // Sin esta vista, ocultar sería un viaje sin vuelta.
    final session = await pumpCourses(tester);
    await tester.tap(find.byKey(const Key('hide-course-alg')));
    await settle(tester);

    await chooseView(tester, CoursesView.hidden);
    expect(find.text('Álgebra'), findsOneWidget);
    expect(find.text('Análisis Matemático I'), findsNothing);

    await tester.tap(find.byKey(const Key('hide-course-alg')));
    await settle(tester);
    expect(session.isHiddenCourse('alg'), isFalse);
  });

  testWidgets('un curso académico se oculta por su cuenta', (tester) async {
    final session = await pumpCourses(tester);
    expect(find.text('2024-2025'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hide-year-am-i-2024-2025')));
    await settle(tester);

    expect(find.text('2024-2025'), findsNothing);
    expect(find.text('2026-2027'), findsOneWidget);
    expect(session.isHiddenCourse('am-i'), isFalse);
  });

  testWidgets('y su asignatura sale en «las ocultas» aunque no lo esté', (
    tester,
  ) async {
    // Si no, sus cursos ocultos no se podrían recuperar desde ningún sitio.
    await pumpCourses(tester);
    await tester.tap(find.byKey(const Key('hide-year-am-i-2024-2025')));
    await settle(tester);

    await chooseView(tester, CoursesView.hidden);
    expect(find.text('Análisis Matemático I'), findsOneWidget);
    expect(find.text('2024-2025'), findsOneWidget);
    // Y solo el que está oculto: es la lista de lo que hay que deshacer.
    expect(find.text('2026-2027'), findsNothing);
  });

  testWidgets('«todas» las enseña, y dice cuál está oculta', (tester) async {
    await pumpCourses(tester);
    await tester.tap(find.byKey(const Key('hide-course-alg')));
    await settle(tester);

    await chooseView(tester, CoursesView.all);
    expect(find.text('Álgebra'), findsOneWidget);
    expect(find.text('Análisis Matemático I'), findsOneWidget);
    // Sin la marca no habría forma de saber cuál se escondió.
    expect(find.text('oculta'), findsOneWidget);
  });

  testWidgets('el título pliega la asignatura', (tester) async {
    final session = await pumpCourses(tester);
    expect(find.text('2026-2027'), findsOneWidget);

    await tester.tap(find.text('Análisis Matemático I'));
    await settle(tester);

    expect(session.isCollapsedCourse('am-i'), isTrue);
    expect(find.text('2026-2027'), findsNothing);
    // Plegada sigue estando, y dice cuánto lleva dentro.
    expect(find.text('Análisis Matemático I'), findsOneWidget);
    expect(find.textContaining('2 cursos académicos'), findsOneWidget);

    await tester.tap(find.text('Análisis Matemático I'));
    await settle(tester);
    expect(find.text('2026-2027'), findsOneWidget);
  });

  testWidgets('la vista elegida se queda puesta', (tester) async {
    // Es la lista con la que se trabaja, no una forma de buscar un rato:
    // quien se pone a ordenar las asignaturas se queda en «las ocultas», y
    // volver de un curso para encontrarse otra vez «las que doy» convierte
    // esa tarde en un baile de clics.
    final session = await pumpCourses(tester);
    await chooseView(tester, CoursesView.all);

    expect(session.coursesView, 'all');
    expect(session.syncedPrefs.coursesView, 'all');
  });

  testWidgets('y sigue puesta al volver a la pantalla', (tester) async {
    final session = await pumpCourses(tester);
    await tester.tap(find.byKey(const Key('hide-course-alg')));
    await chooseView(tester, CoursesView.hidden);

    // Fuera de la pantalla y de vuelta, como al entrar en un curso: el árbol
    // se tira entero para que la página se construya de cero.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: CoursesPage()),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Álgebra'), findsOneWidget);
    expect(find.text('Análisis Matemático I'), findsNothing);
  });

  testWidgets('una vista que no se reconoce vuelve a «las que doy»', (
    tester,
  ) async {
    // Un fichero escrito por otra versión no puede dejar la pantalla sin
    // lista: lo que no se entiende es la vista de siempre.
    final session = await pumpCourses(tester);
    await session.setCoursesView('loquesea');
    await tester.tap(find.byKey(const Key('hide-course-alg')));
    await settle(tester);

    expect(find.text('Álgebra'), findsNothing);
    expect(find.text('Análisis Matemático I'), findsOneWidget);
  });

  testWidgets('marcar no mueve nada de sitio', (tester) async {
    // Lo movía, y era peor: marcar una asignatura movía otras cuatro.
    final session = await pumpCourses(tester);
    final before = tester.getTopLeft(find.text('Álgebra')).dy;

    await tester.tap(find.byKey(const Key('favourite-course-am-i')));
    await settle(tester);

    expect(session.isFavouriteCourse('am-i'), isTrue);
    expect(tester.getTopLeft(find.text('Álgebra')).dy, before);
  });
}
