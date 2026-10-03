/// El diálogo de una lección nueva.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/new_unit.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

/// Una lección que ya vive en un subtema, para que las columnas tengan uno.
Map<String, dynamic> inSubtopic() => unitJson(
  path: 'content/analysis/normed/conceptos/definition',
  subtopic: 'conceptos',
  title: const {'es': 'Definición'},
);

/// Y otra en otro tema, que es a donde se mueve en las pruebas.
Map<String, dynamic> elsewhere() => unitJson(
  path: 'content/analysis/banach/teoria/hahn-banach',
  topic: 'banach',
  subtopic: 'teoria',
  title: const {'es': 'Hahn-Banach'},
);

/// Abre el diálogo y devuelve con qué leer lo que contestó al cerrarse.
Future<NewUnitRequest? Function()> Function() openDialog(
  WidgetTester tester, {
  String topic = 'normed',
  String subtopic = 'conceptos',
}) {
  NewUnitRequest? answer;
  return () async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final catalogue = catalogueWith([...defaultUnits(), inSubtopic()]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);
    await tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await showDialog<NewUnitRequest>(
                  context: context,
                  builder: (_) => NewUnitDialog(
                    session: session,
                    category: 'analysis',
                    topic: topic,
                    subtopic: subtopic,
                    kind: 'theory',
                    repos: const [],
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return () => answer;
  };
}

void main() {
  // Proponía siempre el primero de la lista: una lección de álgebra, en el
  // repositorio del ejemplo, aunque todas las de álgebra estuvieran en el
  // del departamento.
  test('propone el repositorio que ya tiene las lecciones del tema', () async {
    final catalogue = Catalogue.merge([
      catalogueWith([
        unitJson(path: 'content/analysis/normed/definition'),
      ], repo: 'profe/mio'),
      catalogueWith([
        unitJson(
          path: 'content/algebra/matrices/rank',
          category: 'algebra',
          topic: 'matrices',
        ),
        unitJson(
          path: 'content/algebra/matrices/det',
          category: 'algebra',
          topic: 'matrices',
        ),
      ], repo: 'dep/comun'),
    ]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);
    const both = ['profe/mio', 'dep/comun'];
    expect(repoWithMost(session, both, 'algebra', 'matrices'), 'dep/comun');
    expect(repoWithMost(session, both, 'analysis', null), 'profe/mio');
    // Una categoría que no tiene nadie: lo decide la lista.
    expect(repoWithMost(session, both, 'geometria', null), isNull);
    // Y solo entre los que se pueden escribir.
    expect(repoWithMost(session, ['profe/mio'], 'algebra', null), isNull);
  });

  testWidgets('del título sale el nombre de la carpeta, y se dice dónde va', (
    tester,
  ) async {
    final answer = await openDialog(tester)();

    // Sin título, no se crea.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('new-unit-create')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('new-unit-title')),
      'Espacios de Hilbert',
    );
    await tester.pumpAndSettle();
    // En el subtema que se miraba: su carpeta es su sitio.
    expect(
      find.text(
        'Se creará en content/analysis/normed/conceptos/espacios-de-hilbert',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('new-unit-create')));
    await tester.pumpAndSettle();
    final got = answer();
    expect(got?.title, 'Espacios de Hilbert');
    expect(got?.slug, 'espacios-de-hilbert');
    expect(got?.topic, 'normed');
    expect(got?.subtopic, 'conceptos');
  });

  testWidgets('sin subtema no se crea, y se elige en las columnas', (
    tester,
  ) async {
    await openDialog(tester, subtopic: '')();
    await tester.enterText(
      find.byKey(const Key('new-unit-title')),
      'Espacios de Hilbert',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Elige un subtema: cada lección vive en uno.'),
      findsWidgets,
    );
    await tester.tap(find.byKey(const Key('place-conceptos')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Se creará en content/analysis/normed/conceptos/espacios-de-hilbert',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no deja crear una que ya existe', (tester) async {
    await openDialog(tester)();
    // `content/analysis/normed/conceptos/definition` está en el fixture.
    await tester.enterText(
      find.byKey(const Key('new-unit-title')),
      'Definition',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ya hay una lección'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('new-unit-create')))
          .onPressed,
      isNull,
    );
  });

  group('duplicar', () {
    testWidgets('pide otro título y dice dónde va a quedar', (tester) async {
      await pumpDuplicate(tester);
      final create = find.byKey(const Key('duplicate-unit-create'));
      // Con el de la original no: serían dos filas iguales.
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      expect(
        find.text('Ponle otro título, para distinguirla de la original.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('duplicate-unit-title')),
        'Espacios de Hilbert',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Se creará en content/analysis/normed/espacios-de-hilbert'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    });

    testWidgets('no deja ponerla encima de otra', (tester) async {
      await pumpDuplicate(tester);
      // `content/analysis/normed/definition` es la original.
      await tester.enterText(
        find.byKey(const Key('duplicate-unit-title')),
        'Definition',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ya hay una lección en content/analysis/normed/definition.'),
        findsOneWidget,
      );
    });

    testWidgets('pide al motor la copia y abre la nueva', (tester) async {
      final engine = await pumpDuplicate(tester);
      await tester.enterText(
        find.byKey(const Key('duplicate-unit-title')),
        'Espacios de Hilbert',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('duplicate-unit-create')));
      await tester.pumpAndSettle();

      final asked = engine.commands.firstWhere((c) => c.first == 'new');
      expect(asked, [
        'new',
        'unit',
        '--from=content/analysis/normed/definition',
        '--title',
        'Espacios de Hilbert',
        '--lang',
        'es',
        '--',
        'analysis/normed/espacios-de-hilbert',
      ]);
      expect(
        find.text('abierta /unit/content/analysis/normed/espacios-de-hilbert'),
        findsOneWidget,
      );
    });
  });

  group('mover', () {
    testWidgets('se elige el subtema en las columnas, y dice a dónde va', (
      tester,
    ) async {
      await pumpAction(tester, moveUnitFrom);
      final apply = find.byKey(const Key('move-unit-apply'));
      // Una lección de antes de los subtemas: hasta que no se elige uno, no.
      expect(
        find.text('Elige un subtema: cada lección vive en uno.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      await tester.tap(find.byKey(const Key('place-banach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-teoria')));
      await tester.pumpAndSettle();
      expect(
        find.text('Irá a content/analysis/banach/teoria/definition'),
        findsOneWidget,
      );
      // Y que no hay que reescribir nada de lo que la usa.
      expect(
        find.textContaining('La usa 1 documento, y no hay que tocarlo'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    });

    testWidgets('pide al motor el cambio y abre la lección donde está ahora', (
      tester,
    ) async {
      final engine = await pumpAction(tester, moveUnitFrom);
      await tester.tap(find.byKey(const Key('place-banach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-teoria')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('move-unit-path')),
        'Definición',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move-unit-apply')));
      await tester.pumpAndSettle();

      expect(engine.commands.firstWhere((c) => c.first == 'move'), [
        'move',
        '--unit=content/analysis/normed/definition',
        '--to=analysis/banach/teoria/definicion',
      ]);
      expect(
        find.text('abierta /unit/content/analysis/banach/teoria/definicion'),
        findsOneWidget,
      );
    });

    testWidgets('arrastrada a un subtema, se mueve sin preguntar', (
      tester,
    ) async {
      final engine = await pumpAction(
        tester,
        (context, session, unit) => moveUnitFrom(
          context,
          session,
          unit,
          to: const ['analysis', 'banach', 'teoria'],
          open: false,
        ),
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(engine.commands.firstWhere((c) => c.first == 'move'), [
        'move',
        '--unit=content/analysis/normed/definition',
        '--to=analysis/banach/teoria/definition',
      ]);
      // Y se queda donde estaba: soltarla en otra columna no es abrirla.
      expect(find.textContaining('abierta'), findsNothing);
    });

    testWidgets('con algo sin guardar en ella, no', (tester) async {
      await pumpAction(
        tester,
        moveUnitFrom,
        before: (session) => session.unsaved.mark(
          Object(),
          '«Espacios normados» en es',
          place: Routes.unit(unitPath),
        ),
      );
      expect(find.byKey(const Key('move-unit-path')), findsNothing);
      expect(find.textContaining('Guarda o descarta antes'), findsOneWidget);
    });
  });
}

/// Monta una pantalla con un botón que hace [action] con [unitPath], con un
/// motor de mentira que apunta lo que se le pide.
Future<FakeCompiler> pumpAction(
  WidgetTester tester,
  Future<Object?> Function(BuildContext, Session, Unit) action, {
  void Function(FakeSession session)? before,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final engine = FakeCompiler();
  final catalogue = catalogueWith([...defaultUnits(), elsewhere()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: engine,
    adminOverride: CourseAdmin(
      compiler: engine,
      clone: FakeClone(changed: true),
      author: (name: 'Javier', email: 'javier@uv.es'),
      token: '',
      pushOnCommit: false,
    ),
  );
  await session.primeForTest(catalogue);
  before?.call(session);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp.router(
        theme: didactaTheme(),
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      action(context, session, session.unitByPath(unitPath)!),
                  child: const Text('hacer'),
                ),
              ),
            ),
          ],
          // La lección abierta, sin montar su pantalla: lo que se prueba es
          // que se va a ella.
          errorBuilder: (_, state) => Text('abierta ${state.uri.path}'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('hacer'));
  await tester.pumpAndSettle();
  return engine;
}

Future<FakeCompiler> pumpDuplicate(WidgetTester tester) =>
    pumpAction(tester, duplicateUnitFrom);
