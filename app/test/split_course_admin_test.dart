/// Duplicar, quitar y congelar una asignatura repartida entre dos
/// repositorios.
///
/// La teoría en uno y los problemas en otro es como vive el material de
/// verdad. Las tres operaciones actuaban solo en el primero: el curso nuevo
/// salía sin la mitad, la asignatura quitada seguía en la lista por la otra
/// mitad, y la versión congelada dejaba los problemas cambiando por debajo.
/// Lo que se fija aquí es que cada una llega a los dos.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/courses_page.dart';
import 'package:didacta_app/ui/freezes.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

const teoria = 'x/teoria';
const problemas = 'x/problemas';

/// Una sesión con un administrador y un clon por repositorio.
class SplitSession extends FakeSession {
  SplitSession({
    required super.catalogue,
    required this.admins,
    required this.clones,
  }) : super(gatewayOverride: FakeGateway());

  final Map<String, CourseAdmin> admins;
  final Map<String, FakeClone> clones;

  @override
  CourseAdmin? admin({String? repo}) => admins[repo ?? teoria];

  @override
  LocalClone? cloneFor(String? repo) => clones[repo ?? teoria];
}

Catalogue splitCatalogue() {
  Map<String, dynamic> course(String document, String kind) => {
    'id': 'am-iii',
    'title': const {'es': 'Análisis Matemático III'},
    'language': 'es',
    'years': {
      '2025-2026': {
        'year': '2025-2026',
        'language': 'es',
        'documents': [
          {
            'id': document,
            'kind': kind,
            'language': 'es',
            'title': {'es': document},
            'unitRefs': const <String>[],
          },
        ],
      },
    },
  };
  return Catalogue.merge([
    catalogueWith(
      const [],
      courses: [course('tema-1', 'theory')],
      repo: teoria,
    ),
    catalogueWith(
      const [],
      courses: [course('hoja-1', 'problems')],
      repo: problemas,
    ),
  ]);
}

class Split {
  Split(this.session, this.engines, this.clones);

  final SplitSession session;
  final Map<String, FakeCompiler> engines;
  final Map<String, FakeClone> clones;

  List<List<String>> ran(String repo) => engines[repo]!.commands;
}

Future<Split> pumpSplit(
  WidgetTester tester,
  Widget page, {
  bool routed = false,
  String? failIn,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final engines = {
    for (final repo in [teoria, problemas])
      repo:
          FakeCompiler(
              failWith: repo == failIn
                  ? const CompileException('am-iii/2026-2027 already exists')
                  : null,
            )
            ..answers['remove course'] = '  1 año(s)\n  1 documento(s)\n'
            ..answers['remove year'] = '  1 documento(s)\n',
  };
  final clones = {
    teoria: FakeClone()..at = 'aaaaaaa0000000000000000000000000000000000',
    problemas: FakeClone()..at = 'bbbbbbb0000000000000000000000000000000000',
  };
  final admins = {
    for (final repo in engines.keys)
      repo: CourseAdmin(
        compiler: engines[repo]!,
        clone: clones[repo]!,
        author: (name: 'Javier', email: 'javier@uv.es'),
        token: '',
        pushOnCommit: false,
      ),
  };
  final catalogue = splitCatalogue();
  final session = SplitSession(
    catalogue: catalogue,
    admins: admins,
    clones: clones,
  );
  await session.primeForTest(catalogue);

  // Con router cuando la pantalla navega al acabar: quitar un curso vuelve
  // a la lista, porque el que se estaba mirando ya no existe.
  final router = GoRouter(
    initialLocation: '/here',
    routes: [
      GoRoute(
        path: '/here',
        builder: (context, state) => Scaffold(body: page),
      ),
      GoRoute(
        path: '/courses',
        builder: (context, state) => const Scaffold(body: Text('asignaturas')),
      ),
    ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: routed
          ? MaterialApp.router(theme: didactaTheme(), routerConfig: router)
          : MaterialApp(
              theme: didactaTheme(),
              home: Scaffold(body: page),
            ),
    ),
  );
  await settle(tester);
  return Split(session, engines, clones);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('el año está en los dos', () {
    final year = splitCatalogue().courses.single.years['2025-2026']!;
    expect(year.presentIn, {teoria, problemas});
  });

  testWidgets('duplicar el curso lo duplica en los dos', (tester) async {
    final split = await pumpSplit(tester, const CoursesPage());

    await tester.tap(find.byKey(const Key('add-year-am-iii')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-duplicate')));
    await settle(tester);

    const created = [
      'new',
      'year',
      '--from',
      '2025-2026',
      '--',
      'am-iii',
      '2026-2027',
    ];
    expect(split.ran(teoria), contains(equals(created)));
    expect(split.ran(problemas), contains(equals(created)));
    // Y el de origen, congelado en los dos con el mismo nombre: una foto de
    // la mitad no es el curso tal como quedó.
    for (final repo in [teoria, problemas]) {
      expect(split.ran(repo).first.take(5), [
        'freeze',
        'add',
        'am-iii@2025-2026',
        '--name',
        'Tal como quedó',
      ]);
    }
    expect(split.session.reloads, 1);
  });

  testWidgets('si falla en uno, dice en cuál sí se hizo', (tester) async {
    // Cada repositorio es su propio commit y no hay forma de deshacer los
    // dos a la vez: lo mínimo es saber en qué estado ha quedado cada uno.
    final split = await pumpSplit(
      tester,
      const CoursesPage(),
      failIn: problemas,
    );

    await tester.tap(find.byKey(const Key('add-year-am-iii')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-duplicate')));
    await settle(tester);

    expect(find.textContaining('already exists'), findsOneWidget);
    expect(find.textContaining('En x/teoria sí se hizo'), findsOneWidget);
    // Y lo que sí se hizo se ve.
    expect(split.session.reloads, 1);
  });

  testWidgets('quitar la asignatura la quita de los dos, con un recuento', (
    tester,
  ) async {
    final split = await pumpSplit(tester, const CoursesPage());

    await tester.tap(find.byKey(const Key('course-menu-am-iii')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('remove-am-iii')));
    await settle(tester);

    // Un documento en cada uno son dos; el mismo curso académico en los dos
    // es uno.
    expect(
      find.text('Esto se lleva 1 curso académico y 2 documentos.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm-removal')));
    await settle(tester);

    const removed = ['remove', 'course', '--apply', '--', 'am-iii'];
    expect(split.ran(teoria), contains(equals(removed)));
    expect(split.ran(problemas), contains(equals(removed)));
    expect(split.clones[teoria]!.commits, hasLength(1));
    expect(split.clones[problemas]!.commits, hasLength(1));
  });

  testWidgets('quitar el curso académico también', (tester) async {
    final split = await pumpSplit(
      tester,
      const YearPage(courseId: 'am-iii', year: '2025-2026'),
      routed: true,
    );

    await tester.tap(find.byKey(const Key('year-page-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('remove-year')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-removal')));
    await settle(tester);

    const removed = ['remove', 'year', '--apply', '--', 'am-iii', '2025-2026'];
    expect(split.ran(teoria), contains(equals(removed)));
    expect(split.ran(problemas), contains(equals(removed)));
  });

  testWidgets('congelar congela los dos, cada uno en su commit', (
    tester,
  ) async {
    final split = await pumpSplit(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () {
            final session = context.read<Session>();
            unawaited(
              createFreeze(
                context,
                session,
                session.catalogue.courses.single,
                '2025-2026',
              ),
            );
          },
          child: const Text('congelar'),
        ),
      ),
    );

    await tester.tap(find.text('congelar'));
    await settle(tester);
    // Dice a qué apunta en cada uno.
    expect(find.textContaining('aaaaaaa'), findsOneWidget);
    expect(find.textContaining('bbbbbbb'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('freeze-name')),
      'Inicio de curso',
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('freeze-confirm')));
    await settle(tester);

    List<String> freezeIn(String repo) =>
        split.ran(repo).firstWhere((command) => command.contains('freeze'));
    expect(freezeIn(teoria), contains(split.clones[teoria]!.at));
    expect(freezeIn(problemas), contains(split.clones[problemas]!.at));
  });

  testWidgets('congelar desde el menú del curso congela los dos', (
    tester,
  ) async {
    // Desde aquí se congelaba solo el primero, y la mitad de problemas
    // seguía cambiando por debajo de una foto que decía ser del curso.
    final split = await pumpSplit(tester, const CoursesPage());

    await tester.tap(find.byKey(const Key('year-menu-am-iii-2025-2026')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('freeze-year-am-iii-2025-2026')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('freeze-name')), 'Parcial');
    await settle(tester);
    await tester.tap(find.byKey(const Key('freeze-confirm')));
    await settle(tester);

    for (final repo in [teoria, problemas]) {
      expect(
        split.ran(repo),
        contains(containsAllInOrder(['freeze', 'add', 'am-iii@2025-2026'])),
      );
    }
  });
}
