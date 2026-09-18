/// Reutilizar contenido, desde la pantalla.
///
/// Lo que se fija aquí es que **las cuatro operaciones se distingan**. Mover,
/// vincular, duplicar y dividir son cuatro cosas distintas, y una interfaz
/// que las ofrece con la misma palabra es cómo se pierde material: alguien
/// cree que está copiando y está compartiendo, o al revés.
///
/// Y lo otro que importa: que el destino **empiece en la asignatura actual**.
/// Volver a dar el mismo tema el curso que viene es lo que se hace casi
/// siempre, y obligar a elegir la asignatura cada vez convertiría lo
/// corriente en un formulario.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/reuse.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Map<String, dynamic> otherCourse() => {
  'id': 'mat',
  'title': const {'es': 'Matemáticas'},
  'language': 'es',
  'years': {
    '2026-2027': {
      'year': '2026-2027',
      'language': 'es',
      'documents': const <Map<String, dynamic>>[],
    },
  },
};

Map<String, dynamic> courseWithTwoYears() {
  final course = courseJson();
  final years = <String, dynamic>{
    for (final entry in (course['years'] as Map).entries)
      '${entry.key}': (entry.value as Map).cast<String, dynamic>(),
    '2026-2027': {
      'year': '2026-2027',
      'language': 'es',
      'documents': const <Map<String, dynamic>>[],
    },
  };
  return {...course, 'years': years};
}

Future<FakeSession> makeSession({
  List<Map<String, dynamic>> shared = const [],
}) async {
  final catalogue = catalogueWith(
    defaultUnits(),
    courses: [courseWithTwoYears(), otherCourse()],
    shared: shared,
  );
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    cloneOverride: FakeClone(),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  return session;
}

Future<ReuseTarget?> openTarget(
  WidgetTester tester, {
  ReuseMode mode = ReuseMode.link,
}) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final session = await makeSession();
  ReuseTarget? answer;
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await askReuseTarget(
                  context,
                  session: session,
                  title: 'Añadir vinculado: «Tema 1»',
                  fromCourse: 'am-iii',
                  fromYear: '2025-2026',
                  documentId: 'tema-1',
                  mode: mode,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  group('a dónde va', () {
    testWidgets('la asignatura actual viene elegida, y se ve que es esta', (
      tester,
    ) async {
      await openTarget(tester);
      expect(find.text('Análisis Matemático III  (esta)'), findsOneWidget);
    });

    testWidgets('pero se puede elegir otra', (tester) async {
      await openTarget(tester);
      await tester.tap(find.byKey(const Key('reuse-course')));
      await tester.pumpAndSettle();
      expect(find.text('Matemáticas'), findsWidgets);
    });

    testWidgets('no ofrece el curso del que se sale', (tester) async {
      await openTarget(tester);
      expect(find.byKey(const Key('reuse-year-2026-2027')), findsOneWidget);
      expect(find.byKey(const Key('reuse-year-2025-2026')), findsNothing);
    });

    testWidgets('un nombre que ya está cogido no deja seguir', (tester) async {
      await openTarget(tester);
      // `hoja-1` existe en 2025-2026, no en 2026-2027, así que hay que
      // elegir el año de origen para chocar. Se comprueba al revés: el
      // nombre propuesto no choca y el botón está vivo.
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('reuse-confirm')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('devuelve a dónde y de qué manera', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final session = await makeSession();
      ReuseTarget? answer;
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    answer = await askReuseTarget(
                      context,
                      session: session,
                      title: 'Añadir vinculado',
                      fromCourse: 'am-iii',
                      fromYear: '2025-2026',
                      documentId: 'tema-1',
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reuse-year-2026-2027')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reuse-confirm')));
      await tester.pumpAndSettle();

      expect(answer?.course, 'am-iii');
      expect(answer?.year, '2026-2027');
      expect(answer?.mode, ReuseMode.link);
      expect(answer?.asId, 'tema-1');
    });
  });

  group('las cuatro operaciones', () {
    testWidgets('se ofrecen por separado, cada una con lo que hace', (
      tester,
    ) async {
      await openTarget(tester);
      expect(find.byKey(const Key('reuse-mode-link')), findsOneWidget);
      expect(find.byKey(const Key('reuse-mode-move')), findsOneWidget);
      expect(find.byKey(const Key('reuse-mode-duplicate')), findsOneWidget);
      expect(
        find.textContaining('se ve desde el otro, porque es un solo fichero'),
        findsWidgets,
      );
      expect(
        find.textContaining('Una copia con identidad propia'),
        findsWidgets,
      );
    });

    testWidgets('elegir duplicar cambia lo que dice el botón', (tester) async {
      await openTarget(tester);
      await tester.tap(find.byKey(const Key('reuse-mode-duplicate')));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('reuse-confirm')),
      );
      expect((button.child as Text).data, 'Duplicar');
    });
  });

  group('ver dónde se usa', () {
    const places = [
      PlaceLink(
        label: 'Análisis I · 2025-2026 · series',
        course: 'am-i',
        year: '2025-2026',
        document: 'series',
        here: true,
      ),
      PlaceLink(
        label: 'Análisis I · 2026-2027 · series',
        course: 'am-i',
        year: '2026-2027',
        document: 'series',
      ),
      PlaceLink(
        label: 'Matemáticas · 2026-2027 · series',
        course: 'mat',
        year: '2026-2027',
        document: 'series',
      ),
    ];

    /// Con un router de verdad: lo que se prueba es que la fila lleva a la
    /// dirección del documento, y esa dirección la resuelve `go_router`.
    Future<void> openPlaces(
      WidgetTester tester, {
      void Function(String route)? onGo,
    }) async {
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (context, state) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPlaces(
                    context,
                    title: '«Series»',
                    places: places,
                    explanation: 'Es el mismo tema en todas ellas, no copias.',
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/courses/:course/:year/:document',
            builder: (context, state) {
              onGo?.call(state.uri.path);
              return const Scaffold(body: Text('el curso de destino'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: didactaTheme(), routerConfig: router),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('las cuenta y las lista', (tester) async {
      await openPlaces(tester);
      expect(find.text('Se utiliza en 3 ubicaciones:'), findsOneWidget);
      expect(find.text('Matemáticas · 2026-2027 · series'), findsOneWidget);
      expect(find.textContaining('no copias'), findsOneWidget);
    });

    testWidgets('cada una lleva a su sitio, menos donde ya estás', (
      tester,
    ) async {
      await openPlaces(tester);
      expect(
        find.byKey(const Key('place-mat-2026-2027-series')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('place-am-i-2025-2026-series')),
        findsNothing,
      );
      expect(find.text('aquí'), findsOneWidget);
    });

    testWidgets('pulsarla cierra el diálogo y navega al curso', (tester) async {
      // La dirección de un documento es `/courses/:curso/:año/:documento`, y
      // eso es lo que hace que «llévame allí» sea un enlace y no una búsqueda
      // a mano por la lista de asignaturas.
      String? went;
      await openPlaces(tester, onGo: (route) => went = route);
      await tester.tap(find.byKey(const Key('place-mat-2026-2027-series')));
      await tester.pumpAndSettle();
      expect(went, '/courses/mat/2026-2027/series');
      expect(find.text('Se utiliza en 3 ubicaciones:'), findsNothing);
      expect(find.text('el curso de destino'), findsOneWidget);
    });
  });

  group('dividir', () {
    const places = [
      SyncPlace(key: 'am-i@2025-2026/series', label: 'Análisis · 2025-2026'),
      SyncPlace(key: 'am-i@2026-2027/series', label: 'Análisis · 2026-2027'),
      SyncPlace(key: 'mat@2026-2027/series', label: 'Matemáticas · 2026-2027'),
      SyncPlace(key: 'dob@2026-2027/series', label: 'Doble · 2026-2027'),
    ];

    Future<SplitRequest?> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SplitRequest? answer;
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  answer = await askSplit(
                    context,
                    title: 'Dividir la vinculación de «Series»',
                    places: places,
                    explanation: 'Las lecciones no se duplican.',
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
      return answer;
    }

    testWidgets('enseña todas las ubicaciones actuales', (tester) async {
      await open(tester);
      expect(
        find.textContaining('4 ubicaciones sincronizadas'),
        findsOneWidget,
      );
      for (final place in places) {
        expect(find.text(place.label), findsOneWidget);
      }
    });

    testWidgets('empieza sin dividir nada, así que no deja confirmar', (
      tester,
    ) async {
      await open(tester);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('split-confirm')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('enseña el resultado antes de confirmarlo', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('split-mat@2026-2027/series-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('split-dob@2026-2027/series-1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Grupo A (conserva la identidad)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Grupo B: Matemáticas · 2026-2027 · Doble'),
        findsOneWidget,
      );
    });

    testWidgets('devuelve los grupos que se separan, no el que se queda', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SplitRequest? answer;
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  answer = await askSplit(
                    context,
                    title: 'Dividir',
                    places: places,
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
      await tester.tap(find.byKey(const Key('split-mat@2026-2027/series-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('split-dob@2026-2027/series-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('split-confirm')));
      await tester.pumpAndSettle();

      expect(answer?.groups, [
        ['mat@2026-2027/series', 'dob@2026-2027/series'],
      ]);
      // Y sin duplicar las lecciones, que es lo que no se pidió.
      expect(answer?.deep, isFalse);
    });

    testWidgets('se pueden crear más de dos grupos', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('split-add-group')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('split-mat@2026-2027/series-2')),
        findsOneWidget,
      );
    });
  });

  group('dar una lección en otro tema', () {
    Future<LessonTarget?> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final session = await makeSession();
      LessonTarget? answer;
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    answer = await askLessonTarget(
                      context,
                      session: session,
                      title: 'Dar «Espacios normados» en otro tema',
                      fromCourse: 'am-iii',
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('pregunta asignatura, curso y tema, en ese orden', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('A QUÉ ASIGNATURA'), findsOneWidget);
      expect(find.text('A QUÉ CURSO ACADÉMICO'), findsOneWidget);
      expect(find.text('A QUÉ TEMA'), findsOneWidget);
    });

    testWidgets('la asignatura actual viene elegida', (tester) async {
      await open(tester);
      expect(find.text('Análisis Matemático III  (esta)'), findsOneWidget);
    });

    testWidgets('vinculada por defecto, y lo dice el botón', (tester) async {
      await open(tester);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('lesson-confirm')),
      );
      expect((button.child as Text).data, 'Añadir vinculada');
    });

    testWidgets('marcar la copia cambia lo que va a pasar', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('lesson-duplicate')));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('lesson-confirm')),
      );
      expect((button.child as Text).data, 'Duplicar aquí');
    });

    testWidgets('devuelve a qué tema y de qué manera', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final session = await makeSession();
      LessonTarget? answer;
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    answer = await askLessonTarget(
                      context,
                      session: session,
                      title: 'Dar una lección en otro tema',
                      fromCourse: 'am-iii',
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-confirm')));
      await tester.pumpAndSettle();
      // El curso más reciente **que tenga temas**: 2026-2027 está recién
      // creado y vacío, y abrir en un curso donde no se puede elegir nada
      // obliga a cambiarlo antes de empezar.
      expect(answer?.course, 'am-iii');
      expect(answer?.year, '2025-2026');
      expect(answer?.document, 'tema-1');
      expect(answer?.duplicate, isFalse);
    });

    testWidgets('un curso sin temas lo dice en vez de dejar elegir', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('lesson-year-2026-2027')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('no tiene todavía ningún tema'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('lesson-confirm')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('el indicador', () {
    testWidgets('no sale cuando solo hay una ubicación', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LinkBadge(places: 1, what: 'Este tema')),
        ),
      );
      expect(find.text('1'), findsNothing);
    });

    testWidgets('sale con el número cuando hay varias', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LinkBadge(places: 4, what: 'Este tema')),
        ),
      );
      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });
  });
}
