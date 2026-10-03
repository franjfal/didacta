/// Un examen o una hoja a partir de los problemas, de una vez.
///
/// * solo se ofrecen problemas, y se filtran por carpeta;
/// * se dice en qué examen de la asignatura salió cada uno, y se pueden
///   quitar de la lista los que ya salieron;
/// * crear deja el documento compuesto y con su master, en un solo cambio.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/problem_set.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

const String seen = 'problems/analysis/normed/cauchy';
const String fresh = 'problems/analysis/normed/equivalence';
const String algebra = 'problems/algebra/matrices/rank-exercise';

/// Tres problemas --uno salió en el examen de enero del curso pasado-- y la
/// asignatura con ese examen.
Catalogue examCatalogue() {
  final course = courseJson();
  final years = (course['years'] as Map).cast<String, dynamic>();
  years['2024-2025'] = {
    'year': '2024-2025',
    'language': 'es',
    'documents': [
      {
        'id': 'examen-enero',
        'kind': 'exam',
        'language': 'es',
        'title': const {'es': 'Enero'},
        'profiles': const <String>[],
        'unitRefs': const ['analysis/normed/cauchy'],
        'structure': const [
          {'unit': 'analysis/normed/cauchy'},
        ],
      },
    ],
  };
  course['years'] = years;
  return catalogueWith(
    [
      ...defaultUnits(),
      unitJson(
        path: seen,
        area: 'problems',
        kind: 'problem',
        title: const {'es': 'Sucesiones de Cauchy'},
        usedBy: const [
          {'course': 'am-iii', 'year': '2024-2025', 'document': 'examen-enero'},
        ],
      ),
      unitJson(
        path: fresh,
        area: 'problems',
        kind: 'problem',
        title: const {'es': 'Normas equivalentes'},
        usedBy: const <Map<String, String>>[],
      ),
      unitJson(
        path: algebra,
        area: 'problems',
        kind: 'problem',
        category: 'algebra',
        topic: 'matrices',
        title: const {'es': 'El rango'},
        usedBy: const <Map<String, String>>[],
      ),
    ],
    courses: [course],
  );
}

Future<FakeGateway> pumpYear(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1300, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final gateway = FakeGateway();
  final catalogue = examCatalogue();
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
          body: YearPage(courseId: 'am-iii', year: '2025-2026'),
        ),
      ),
    ),
  );
  await settle(tester);
  return gateway;
}

Finder row(String path) => find.byKey(Key('problem-set-unit-$path'));

void main() {
  test('dice en qué exámenes de la asignatura salió', () {
    final catalogue = examCatalogue();
    final course = catalogue.courses.single;
    final unit = catalogue.units.firstWhere((u) => u.path == seen);
    expect(examsWith(unit, course, 'es'), ['2024-2025 · Enero']);
    // Una hoja no es un examen: la de 2025-2026 no cuenta.
    final exercises = catalogue.units.firstWhere(
      (u) => u.path == 'problems/analysis/normed/exercises',
    );
    expect(examsWith(exercises, course, 'es'), isEmpty);
  });

  testWidgets('solo problemas, filtrados, y sin los que ya salieron', (
    tester,
  ) async {
    await pumpYear(tester);
    await tester.tap(find.byKey(const Key('add-problem-set')));
    await settle(tester);

    expect(row(seen), findsOneWidget);
    expect(row(fresh), findsOneWidget);
    expect(row(algebra), findsOneWidget);
    // Una lección de teoría no es un problema.
    expect(row(unitPath), findsNothing);
    // El que salió lo dice.
    expect(find.byKey(const Key('problem-set-seen-$seen')), findsOneWidget);
    expect(find.text('examen 2024-2025'), findsOneWidget);

    await tester.tap(find.byKey(const Key('problem-set-unseen')));
    await settle(tester);
    expect(row(seen), findsNothing);
    expect(row(fresh), findsOneWidget);

    await tester.tap(find.byKey(const Key('problem-set-folder')));
    await settle(tester);
    await tester.tap(find.text('Algebra › Matrices').last);
    await settle(tester);
    expect(row(fresh), findsNothing);
    expect(row(algebra), findsOneWidget);
  });

  testWidgets('crear lo deja compuesto y con su master, de una vez', (
    tester,
  ) async {
    final gateway = await pumpYear(tester);
    await tester.tap(find.byKey(const Key('add-problem-set')));
    await settle(tester);

    final create = find.byKey(const Key('problem-set-create'));
    await tester.enterText(
      find.byKey(const Key('problem-set-title')),
      'Examen de enero',
    );
    await settle(tester);
    // Sin problemas no hay examen.
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    await tester.tap(row(fresh));
    await tester.tap(row(seen));
    await settle(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('problem-set-summary'))).data,
      startsWith('2 elegidos, en este orden'),
    );
    await tester.tap(create);
    await settle(tester);
    await tapIfShown(tester, find.byKey(const Key('composition-commit')));
    await settle(tester);

    const master = 'courses/am-iii/2025-2026/examen-de-enero.tex';
    expect(gateway.batches, [
      ['courses/am-iii/2025-2026/year.yaml', master],
    ]);
    final year = gateway.files['courses/am-iii/2025-2026/year.yaml']!;
    final draft = CompositionFile(
      year,
    ).documentDrafts().firstWhere((d) => d.id == 'examen-de-enero');
    expect(draft.kind, 'exam');
    expect(draft.titles['es'], 'Examen de enero');
    // En el orden en que se eligieron.
    final structure = CompositionFile(
      year,
    ).blockFor('examen-de-enero')!.entries;
    expect(
      [for (final entry in structure) entry.value],
      ['analysis.normed.equivalence', 'analysis.normed.cauchy'],
    );
    // Un examen no lleva índice.
    expect(
      gateway.files[master],
      contains(r'\DidactaDocument{Examen de enero}'),
    );
    expect(gateway.files[master], isNot(contains(r'\DidactaContents')));
  });
}
