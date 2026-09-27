/// Lo que se enseña cuando no hay nada que enseñar.
///
/// Era una lista en blanco con «0 asignaturas» o «0 unidades» encima, sin
/// decir por qué ni qué hacer. Ahora dice cuál es el motivo y ofrece la
/// salida de cada uno.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/courses_page.dart';
import 'package:didacta_app/ui/library_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeSession> pump(
  WidgetTester tester,
  Widget page, {
  required Catalogue catalogue,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
        home: Scaffold(body: page),
      ),
    ),
  );
  await settle(tester);
  return session;
}

void main() {
  group('asignaturas', () {
    testWidgets('sin ninguna: crear una o probar con un ejemplo', (
      tester,
    ) async {
      await pump(
        tester,
        const CoursesPage(),
        catalogue: catalogueWith(defaultUnits(), courses: const []),
      );
      expect(find.byKey(const Key('no-courses')), findsOneWidget);
      expect(find.text('Todavía no hay ninguna asignatura'), findsOneWidget);
      expect(find.byKey(const Key('no-courses-example')), findsOneWidget);
    });

    testWidgets('todas ocultas: lo dice y deja verlas', (tester) async {
      final session = await pump(
        tester,
        const CoursesPage(),
        catalogue: catalogueWith(defaultUnits()),
      );
      for (final course in session.catalogue.courses) {
        await session.setCourseHidden(course.id, true);
      }
      await settle(tester);
      expect(find.textContaining('está oculta'), findsOneWidget);

      await tester.tap(find.byKey(const Key('no-courses-show-hidden')));
      await settle(tester);
      expect(session.coursesView, 'hidden');
      expect(find.byKey(const Key('no-courses')), findsNothing);
      expect(find.text('Análisis Matemático III'), findsOneWidget);
    });
  });

  group('biblioteca', () {
    testWidgets('sin repositorio: añadir uno o probar con un ejemplo', (
      tester,
    ) async {
      await pump(
        tester,
        const LibraryPage(),
        catalogue: catalogueWith(const [], courses: const []),
      );
      expect(find.byKey(const Key('empty-library')), findsOneWidget);
      expect(find.byKey(const Key('empty-library-add')), findsOneWidget);
      expect(find.byKey(const Key('empty-library-example')), findsOneWidget);
    });
  });
}
