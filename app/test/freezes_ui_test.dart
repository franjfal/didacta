/// Las versiones congeladas, desde la pantalla.
///
/// Lo que se prueba aquí es lo que alguien lee y lo que la pantalla le pide
/// al motor, no que git haga lo que hace: eso está en `freeze_git_test.dart`
/// y en `frozen_repo_test.dart`, contra git de verdad.
///
/// Y lo que más importa: **que lo diga**. Una congelación es un commit con
/// nombre, quitarla no borra commits y restaurar no reescribe la historia.
/// Son tres frases que si no están en pantalla nadie pulsa los botones.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/data/frozen.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/freezes.dart';
import 'package:didacta_app/ui/shell.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const String commitA = '1111111111111111111111111111111111111111';
const String commitB = '2222222222222222222222222222222222222222';

Map<String, dynamic> freezeJson({
  String id = 'f-000000000001',
  String name = 'Inicio curso 2026-27',
  String commit = commitA,
  String description = 'Como se repartió el primer día.',
}) => {
  'id': id,
  'name': name,
  'commit': commit,
  'description': description,
  'created': '2026-09-01T09:00:00+02:00',
  'course': 'am-iii',
  'year': '2025-2026',
};

Map<String, dynamic> courseWithFreezes(List<Map<String, dynamic>> freezes) {
  final course = courseJson();
  final years = <String, dynamic>{
    for (final entry in (course['years'] as Map).entries)
      '${entry.key}': {
        ...(entry.value as Map).cast<String, dynamic>(),
        if (entry.key == '2025-2026') 'freezes': freezes,
      },
  };
  return {...course, 'years': years};
}

Future<FakeSession> sessionWith(
  List<Map<String, dynamic>> freezes, {
  CourseAdmin? admin,
}) async {
  final catalogue = catalogueWith(
    defaultUnits(),
    courses: [courseWithFreezes(freezes)],
  );
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    adminOverride: admin,
    cloneOverride: FakeClone(),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  return session;
}

Future<Session> pumpFreezes(
  WidgetTester tester, {
  List<Map<String, dynamic>> freezes = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final session = await sessionWith(freezes);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFreezes(
                context,
                session,
                session.catalogue.courses.single,
                '2025-2026',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  group('la lista', () {
    testWidgets('sin ninguna, lo dice en lugar de estar en blanco', (
      tester,
    ) async {
      await pumpFreezes(tester);
      expect(
        find.textContaining('no tiene ninguna versión congelada'),
        findsOneWidget,
      );
    });

    testWidgets('dice que no hay ninguna copia detrás', (tester) async {
      // Es lo que evita las dos preguntas que llegarían si no se dijera:
      // «¿esto ocupa el doble?» y «¿si la borro, pierdo aquello?».
      await pumpFreezes(tester);
      expect(find.textContaining('no ocupa diez veces más'), findsOneWidget);
      expect(find.textContaining('no borra ningún commit'), findsOneWidget);
    });

    testWidgets('enseña las que hay, con su commit', (tester) async {
      await pumpFreezes(
        tester,
        freezes: [
          freezeJson(),
          freezeJson(
            id: 'f-000000000002',
            name: 'Antes del primer parcial',
            commit: commitB,
            description: '',
          ),
        ],
      );
      expect(find.text('Inicio curso 2026-27'), findsOneWidget);
      expect(find.text('Antes del primer parcial'), findsOneWidget);
      expect(find.textContaining('1111111'), findsOneWidget);
    });

    testWidgets('varias del mismo commit no se estorban', (tester) async {
      // Pasa de verdad: congelar dos veces sin haber tocado nada.
      await pumpFreezes(
        tester,
        freezes: [
          freezeJson(),
          freezeJson(id: 'f-000000000002', name: 'Otra del mismo día'),
        ],
      );
      expect(find.byKey(const Key('freeze-f-000000000001')), findsOneWidget);
      expect(find.byKey(const Key('freeze-f-000000000002')), findsOneWidget);
    });
  });

  group('el menú de una congelación', () {
    testWidgets('ofrece abrir, comparar, restaurar y quitar', (tester) async {
      await pumpFreezes(tester, freezes: [freezeJson()]);
      await tester.tap(find.byKey(const Key('freeze-menu-f-000000000001')));
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);
      expect(find.text('Comparar con la versión actual'), findsOneWidget);
      expect(find.text('Comparar con…'), findsOneWidget);
      expect(find.text('Crear un curso desde aquí…'), findsOneWidget);
      expect(find.text('Restaurar…'), findsOneWidget);
      expect(find.text('Renombrar…'), findsOneWidget);
      expect(find.text('Quitar esta versión…'), findsOneWidget);
    });

    testWidgets('quitar pide confirmación y dice qué no se lleva', (
      tester,
    ) async {
      await pumpFreezes(tester, freezes: [freezeJson()]);
      await tester.tap(find.byKey(const Key('freeze-menu-f-000000000001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('freeze-remove-f-000000000001')));
      await tester.pumpAndSettle();

      expect(find.textContaining('¿Quitar'), findsOneWidget);
      expect(
        find.textContaining('El commit sigue donde estaba'),
        findsOneWidget,
      );
      expect(
        find.textContaining('también las que apunten a este mismo commit'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('confirm-remove-freeze')), findsOneWidget);
    });
  });

  group('crear una', () {
    testWidgets('pide un nombre y dice a qué commit apuntará', (tester) async {
      final session = await sessionWith(const []);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => createFreeze(
                    context,
                    session,
                    session.catalogue.courses.single,
                    '2025-2026',
                  ),
                  child: const Text('congelar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('congelar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('freeze-name')), findsOneWidget);
      expect(find.byKey(const Key('freeze-description')), findsOneWidget);
      expect(find.textContaining('Apuntará al commit'), findsOneWidget);
    });

    testWidgets('sin nombre no deja congelar', (tester) async {
      final session = await sessionWith(const []);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => createFreeze(
                    context,
                    session,
                    session.catalogue.courses.single,
                    '2025-2026',
                  ),
                  child: const Text('congelar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('congelar'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('freeze-confirm')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('mirando una congelación', () {
    FrozenView view(Catalogue catalogue) => FrozenView(
      freeze: Freeze.fromJson(freezeJson()),
      directory: '/clon/.git/didacta-worktrees/$commitA',
      catalogue: catalogue,
      repo: '',
    );

    testWidgets('la banda lo dice en todas las pantallas', (tester) async {
      final session = await sessionWith(const []);
      session.useFrozenForTest(view(session.catalogue));
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(body: FrozenBar(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Inicio curso 2026-27'), findsOneWidget);
      expect(find.textContaining('se mira, no se edita'), findsOneWidget);
      expect(find.byKey(const Key('leave-freeze')), findsOneWidget);
    });

    testWidgets('y se puede volver a la versión actual', (tester) async {
      final session = await sessionWith(const []);
      session.useFrozenForTest(view(session.catalogue));
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: Consumer<Session>(
                builder: (context, session, _) => FrozenBar(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('leave-freeze')));
      await tester.pumpAndSettle();
      expect(session.isFrozen, isFalse);
      expect(find.byKey(const Key('leave-freeze')), findsNothing);
    });

    testWidgets('sin congelación abierta no hay banda', (tester) async {
      final session = await sessionWith(const []);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(body: FrozenBar(session: session)),
          ),
        ),
      );
      expect(find.byKey(const Key('leave-freeze')), findsNothing);
    });

    test('el catálogo que se enseña es el de aquel commit', () async {
      final session = await sessionWith(const []);
      final other = catalogueWith(const [], courses: const []);
      session.useFrozenForTest(view(other));
      expect(session.catalogue.courses, isEmpty);
      session.leaveFreeze();
      expect(session.catalogue.courses, hasLength(1));
    });

    test('y no se puede escribir en ella', () async {
      final session = await sessionWith(const []);
      expect(session.canWriteIn(''), isTrue);
      session.useFrozenForTest(view(session.catalogue));
      expect(session.canWriteIn(''), isFalse);
      expect(session.gatewayFor('').describe(), contains('Solo lectura'));
    });
  });
}
