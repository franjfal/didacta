/// El icono de información de una lección y de un tema.
///
/// Lo que se comprueba es que el menú diga la verdad sobre los vínculos, que
/// es para lo que está: una lección que se da en dos asignaturas tiene dos
/// juegos de versiones congeladas y se puede partir en dos; una que no usa
/// nadie no tiene ni lo uno ni lo otro, y decirlo es más útil que enseñar un
/// menú vacío.
///
/// Va por el router de verdad y no por el widget suelto, porque la mitad de
/// lo que hace el menú es llevarte a otro sitio.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/main.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

final Finder info = find.byKey(const Key('info-menu'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

GoRouter routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(DidactaShell)));

String where(WidgetTester tester) =>
    routerOf(tester).routeInformationProvider.value.uri.path;

/// La misma asignatura con su `tema-1` vinculado en dos cursos: el mismo
/// tema dado en dos sitios, que es cuando partir la vinculación significa
/// algo.
Map<String, dynamic> courseWithLinkedTopic() {
  final course = courseWithFreeze();
  final years = Map<String, dynamic>.from(course['years'] as Map);
  final year = Map<String, dynamic>.from(years['2025-2026'] as Map);
  final documents = [
    for (final item in (year['documents'] as List))
      (item as Map).cast<String, dynamic>(),
  ];
  documents[0] = {...documents[0], 'content': 'd-abc123'};
  year['documents'] = documents;
  years['2025-2026'] = year;
  course['years'] = years;
  return course;
}

const List<Map<String, dynamic>> linkedTopic = [
  {
    'id': 'd-abc123',
    'title': {'es': 'Tema 1. Espacios normados'},
    'kind': 'theory',
    'placements': [
      {'course': 'am-iii', 'year': '2025-2026', 'document': 'tema-1'},
      {'course': 'am-iii', 'year': '2026-2027', 'document': 'tema-1'},
    ],
  },
];

/// Una asignatura con una versión congelada guardada, para que el menú tenga
/// algo que contar además de ofrecer el diálogo.
Map<String, dynamic> courseWithFreeze() {
  final course = Map<String, dynamic>.from(courseJson());
  final years = Map<String, dynamic>.from(course['years'] as Map);
  final year = Map<String, dynamic>.from(years['2025-2026'] as Map);
  year['freezes'] = const [
    {
      'id': 'antes-del-parcial',
      'name': 'Antes del primer parcial',
      'commit': '1111111111111111111111111111111111111111',
      'created': '2026-02-01',
      'course': 'am-iii',
      'year': '2025-2026',
    },
  ];
  years['2025-2026'] = year;
  course['years'] = years;
  return course;
}

Future<FakeSession> pumpApp(
  WidgetTester tester, {
  List<Map<String, dynamic>>? units,
  List<Map<String, dynamic>>? courses,
  List<Map<String, dynamic>> shared = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 950);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogueWith(
      units ?? defaultUnits(),
      courses: courses ?? [courseWithFreeze()],
      shared: shared,
    ),
  );
  await tester.pumpWidget(
    DidactaApp(session: session, updates: offlineUpdates()),
  );
  await settle(tester);
  return session;
}

Future<void> goTo(WidgetTester tester, String route) async {
  routerOf(tester).go(route);
  await settle(tester);
}

Future<void> openInfo(WidgetTester tester) async {
  expect(info, findsOneWidget);
  await tester.tap(info);
  await settle(tester);
}

void main() {
  group('en una lección', () {
    testWidgets('dice dónde se da y lleva al tema', (tester) async {
      await pumpApp(tester);
      await goTo(tester, Routes.unit('content/analysis/normed/definition'));
      await openInfo(tester);

      expect(find.text('SE DA EN (1)'), findsOneWidget);
      expect(find.text('tema-1'), findsWidgets);

      await tester.tap(
        find.byKey(const Key('info-place-am-iii-2025-2026-tema-1')),
      );
      await settle(tester);
      expect(where(tester), '/courses/am-iii/2025-2026/tema-1');
    });

    testWidgets('ofrece las versiones congeladas de su asignatura', (
      tester,
    ) async {
      await pumpApp(tester);
      await goTo(tester, Routes.unit('content/analysis/normed/definition'));
      await openInfo(tester);

      expect(find.text('VERSIONES CONGELADAS'), findsOneWidget);
      expect(
        find.byKey(const Key('info-freezes-am-iii-2025-2026')),
        findsOneWidget,
      );
      // Cuántas hay guardadas, que es lo que evita abrir el diálogo para
      // descubrir que no hay ninguna.
      expect(find.text('1 guardada'), findsOneWidget);
    });

    testWidgets('una que no usa nadie lo dice, y no se puede partir', (
      tester,
    ) async {
      await pumpApp(tester);
      await goTo(tester, Routes.unit('problems/analysis/normed/exercises'));
      await openInfo(tester);

      expect(find.text('SE DA EN (0)'), findsOneWidget);
      // Por clave y no por texto: el panel de la derecha dice lo mismo con
      // más palabras, y lo que se prueba aquí es el menú.
      expect(find.byKey(const Key('info-places-empty')), findsOneWidget);
      expect(find.byKey(const Key('info-split')), findsNothing);
      // Y tampoco hay de dónde sacar versiones congeladas: son de una
      // asignatura, y esta lección no está en ninguna.
      expect(find.byKey(const Key('info-freeze-create')), findsNothing);
    });

    testWidgets('una que se da en dos sitios se puede partir', (tester) async {
      await pumpApp(
        tester,
        units: [
          unitJson(
            usedBy: const [
              {'course': 'am-iii', 'year': '2025-2026', 'document': 'tema-1'},
              {'course': 'am-iii', 'year': '2025-2026', 'document': 'hoja-1'},
            ],
          ),
          ...defaultUnits().skip(1),
        ],
      );
      await goTo(tester, Routes.unit('content/analysis/normed/definition'));
      await openInfo(tester);

      expect(find.text('SE DA EN (2)'), findsOneWidget);
      expect(find.byKey(const Key('info-split')), findsOneWidget);
      // Dos temas del mismo curso académico son **un** juego de versiones
      // congeladas: no bajan al tema.
      expect(
        find.byKey(const Key('info-freezes-am-iii-2025-2026')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('info-freeze-create')), findsOneWidget);
    });
  });

  group('en un tema', () {
    testWidgets('dice de qué asignatura es y a qué temas pertenece', (
      tester,
    ) async {
      await pumpApp(tester);
      await goTo(tester, Routes.document('am-iii', '2025-2026', 'tema-1'));
      await openInfo(tester);

      expect(find.text('SE DA EN (1)'), findsOneWidget);
      expect(find.text('Análisis Matemático III'), findsWidgets);
    });

    testWidgets('ofrece ver y crear versiones congeladas', (tester) async {
      await pumpApp(tester);
      await goTo(tester, Routes.document('am-iii', '2025-2026', 'tema-1'));
      await openInfo(tester);

      expect(find.text('Ver versiones congeladas…'), findsOneWidget);
      expect(find.byKey(const Key('info-freeze-create')), findsOneWidget);
      // Sin vincular no hay vinculación que partir.
      expect(find.byKey(const Key('info-split')), findsNothing);
    });

    testWidgets('vinculado en dos sitios los enseña y se puede partir', (
      tester,
    ) async {
      await pumpApp(
        tester,
        courses: [courseWithLinkedTopic()],
        shared: linkedTopic,
      );
      await goTo(tester, Routes.document('am-iii', '2025-2026', 'tema-1'));
      await openInfo(tester);

      // Los dos sitios donde se da el mismo tema, no sólo este.
      expect(find.text('SE DA EN (2)'), findsOneWidget);
      expect(find.byKey(const Key('info-split')), findsOneWidget);
    });
  });
}
