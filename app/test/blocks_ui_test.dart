/// Los bloques en pantalla: Ajustes, la biblioteca, el curso y Entre repos.
///
/// Lo que se prueba aquí es lo que ningún test de modelo vería romperse: que
/// un bloque nuevo **aparece** donde se elige material, que con uno solo el
/// filtro no ocupa sitio, y que una lección cuyo bloque no declara nadie sigue
/// saliendo en la biblioteca en vez de desaparecer de ella.
///
/// Esa última es la propiedad que sostiene todo el diseño, y es la única que
/// nadie notaría a tiempo: material que deja de verse no da ningún error.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/between_repos_page.dart';
import 'package:didacta_app/ui/library_page.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> block(String id, String title) => {
  'id': id,
  'title': {'es': title},
};

/// Un catálogo con los bloques que se le digan, y unidades en cada uno.
Catalogue catalogueOfBlocks({
  required List<Map<String, dynamic>> blocks,
  required Map<String, String> units,
  List<Map<String, dynamic>>? courses,
  String repo = '',
}) => Catalogue.fromIndex(
  manifest: {
    'schemaVersion': supportedSchemaVersion,
    'name': 'Prueba',
    'languages': const ['es', 'va', 'en'],
    'defaultLanguage': 'es',
    'contentHash': 'abc',
    'profiles': const <Map<String, dynamic>>[],
    'taxonomy': {'blocks': blocks},
    'errors': const <String>[],
  },
  units: {
    'schemaVersion': supportedSchemaVersion,
    'units': [
      for (final entry in units.entries)
        unitJson(path: entry.key, block: entry.value),
    ],
  },
  courses: {
    'schemaVersion': supportedSchemaVersion,
    'courses': courses ?? const <Map<String, dynamic>>[],
  },
  repo: repo,
);

Future<FakeSession> pumpPage(
  WidgetTester tester,
  Catalogue catalogue,
  Widget page, {
  Size size = const Size(1280, 1500),
  int repos = 1,
  FakeGateway? gateway,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final session = FakeSession(
    gatewayOverride: gateway ?? FakeGateway(),
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
  );
  await session.primeForTest(catalogue);
  await session.useClonesForTest([
    for (var i = 0; i < repos; i += 1) '/tmp/didacta-$i',
  ]);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        // Ajustes tiene una sección de MCP, y sin servidor que ofrecer la
        // pantalla no se monta. Uno que no puede levantarse vale: lo que se
        // prueba aquí está en la sección de al lado.
        ChangeNotifierProvider<McpService>(
          create: (_) => McpService(
            openRunner: () =>
                const UnavailableRunner('Sin servidor en las pruebas.'),
          ),
        ),
        // Y una sección de actualizaciones, que sin red no pregunta nada.
        ChangeNotifierProvider<UpdateService>(create: (_) => offlineUpdates()),
        ChangeNotifierProvider<TourController>(create: (_) => TourController()),
      ],
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await settle(tester);
  return session;
}

/// Abre la pantalla de bloques desde Ajustes.
///
/// Con un arrastre y no con `ensureVisible`: la lista de Ajustes construye
/// sus secciones según entran en pantalla, así que la de los bloques no está
/// en el árbol hasta que se baja hasta ella.
Future<void> openBlocks(WidgetTester tester) async {
  final button = find.byKey(const Key('open-blocks'));
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 40 && button.evaluate().isEmpty; i += 1) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pump();
  }
  await tester.ensureVisible(button);
  await settle(tester);
  await tester.tap(button);
  await settle(tester);
}

void main() {
  group('la biblioteca', () {
    testWidgets('ofrece los bloques que el repositorio declara', (
      tester,
    ) async {
      // Eran dos y estaban escritos en la pantalla. Quien parta su asignatura
      // en tres tiene que ver tres sin que nadie toque el código.
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [
            block('teoria', 'Teoría'),
            block('problemas', 'Problemas'),
            block('practicas', 'Prácticas de ordenador'),
          ],
          units: {
            'content/analysis/normed/definition': 'teoria',
            'content/analysis/normed/exercises': 'problemas',
            'content/analysis/normed/lab': 'practicas',
          },
        ),
        const LibraryPage(),
      );

      expect(find.text('Prácticas de ordenador'), findsOneWidget);
      expect(find.text('Teoría'), findsOneWidget);
    });

    testWidgets('y con uno solo no enseña el filtro', (tester) async {
      // Un filtro cuyo único valor es todo lo que hay no contesta ninguna
      // pregunta, y se come el alto de la primera columna.
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [block('teoria', 'Teoría')],
          units: {'content/analysis/normed/definition': 'teoria'},
        ),
        const LibraryPage(),
      );

      expect(find.text('Todo'), findsNothing);
      expect(find.text('Teoría'), findsNothing);
    });

    testWidgets('filtrar por un bloque deja solo lo suyo', (tester) async {
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [block('teoria', 'Teoría'), block('practicas', 'Prácticas')],
          units: {
            'content/analysis/normed/definition': 'teoria',
            'content/analysis/normed/lab': 'practicas',
          },
        ),
        const LibraryPage(),
      );

      await tester.tap(find.text('Prácticas'));
      await settle(tester);
      expect(find.textContaining('1 unidades'), findsOneWidget);
    });

    testWidgets('una lección de un bloque que nadie declara se sigue viendo', (
      tester,
    ) async {
      // La propiedad que sostiene el diseño entero: material que deja de
      // verse no da ningún error, así que si esto se rompe nadie se entera.
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [block('teoria', 'Teoría')],
          units: {
            'content/analysis/normed/definition': 'teoria',
            'content/analysis/normed/lab': 'practicas-de-ordenador',
          },
        ),
        const LibraryPage(),
      );

      // Por su id, que es feo y es cierto: inventarle un nombre escondería
      // justo lo que hay que arreglar.
      expect(find.text('practicas-de-ordenador'), findsOneWidget);
      await tester.tap(find.text('practicas-de-ordenador'));
      await settle(tester);
      expect(find.textContaining('1 unidades'), findsOneWidget);
    });
  });

  group('Ajustes', () {
    testWidgets('resume los bloques y abre su pantalla', (tester) async {
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [block('teoria', 'Teoría'), block('practicas', 'Prácticas')],
          units: {'content/analysis/normed/definition': 'teoria'},
          repo: 'test/repo',
        ),
        const SettingsPage(),
      );

      await openBlocks(tester);
      await settle(tester);

      expect(find.byKey(const Key('block-teoria')), findsOneWidget);
      expect(find.byKey(const Key('block-practicas')), findsOneWidget);
      // Con su id y lo que lleva, que es lo que hace falta antes de tocar
      // nada: renombrar uno vacío y renombrar uno con noventa lecciones no
      // dan el mismo respeto.
      expect(find.textContaining('teoria · 1 lección'), findsOneWidget);
    });

    testWidgets('renombrar escribe el nombre nuevo en el repositorio', (
      tester,
    ) async {
      // El camino entero, desde el botón hasta el YAML: es donde se rompen
      // las cosas que ningún test de modelo ve.
      final gateway = FakeGateway(
        files: {
          'taxonomy.yaml':
              'blocks:\n'
              '  - id: teoria\n'
              '    title:\n'
              '      es: Teoría\n',
        },
      );
      final catalogue = catalogueOfBlocks(
        blocks: [block('teoria', 'Teoría')],
        units: {'content/analysis/normed/definition': 'teoria'},
        repo: 'test/repo',
      );
      final session = await pumpPage(
        tester,
        catalogue,
        const SettingsPage(),
        size: const Size(1280, 2200),
        gateway: gateway,
      );
      expect(session.catalogue.blocks, hasLength(1));

      await openBlocks(tester);
      await tester.tap(find.byKey(const Key('rename-block-teoria')));
      await settle(tester);

      await tester.enterText(
        find.byKey(const Key('block-title-es')),
        'Apuntes',
      );
      await tester.tap(find.byKey(const Key('block-titles-save')));
      await settle(tester);

      expect(gateway.files['taxonomy.yaml'], contains('es: Apuntes'));
    });

    testWidgets('y ofrece declarar el que nadie declara', (tester) async {
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [block('teoria', 'Teoría')],
          units: {
            'content/analysis/normed/definition': 'teoria',
            'content/analysis/normed/lab': 'practicas',
          },
          repo: 'test/repo',
        ),
        const SettingsPage(),
      );

      await openBlocks(tester);
      await settle(tester);

      expect(find.byKey(const Key('declare-block-practicas')), findsOneWidget);
    });
  });

  group('entre repositorios', () {
    Catalogue withOrphans() => Catalogue.merge([
      catalogueOfBlocks(
        blocks: [block('teoria', 'Teoría')],
        units: {
          'content/analysis/normed/definition': 'teoria',
          'content/analysis/normed/lab': 'practicas',
        },
        repo: 'x/teoria',
      ),
      catalogueOfBlocks(
        blocks: [block('teoria', 'Teoría')],
        units: const {},
        repo: 'x/problemas',
      ),
    ]);

    testWidgets('enseña las lecciones sin bloque, con dónde están', (
      tester,
    ) async {
      await pumpPage(tester, withOrphans(), const BetweenReposPage(), repos: 2);

      expect(find.byKey(const Key('orphan-block-practicas')), findsOneWidget);
      expect(find.textContaining('lo nombra 1 lección'), findsOneWidget);
      // Las dos salidas: declararlo, o mandar sus lecciones a otro.
      expect(find.byKey(const Key('declare-orphan-practicas')), findsOneWidget);
      expect(find.byKey(const Key('move-orphan-practicas')), findsOneWidget);
    });

    testWidgets('y cuando no hay ninguna, lo dice', (tester) async {
      await pumpPage(
        tester,
        Catalogue.merge([
          catalogueOfBlocks(
            blocks: [block('teoria', 'Teoría')],
            units: {'content/analysis/normed/definition': 'teoria'},
            repo: 'x/teoria',
          ),
          catalogueOfBlocks(
            blocks: [block('teoria', 'Teoría')],
            units: const {},
            repo: 'x/problemas',
          ),
        ]),
        const BetweenReposPage(),
        repos: 2,
      );

      expect(
        find.text('Todas las lecciones tienen su bloque declarado.'),
        findsOneWidget,
      );
    });

    testWidgets('dos nombres distintos del mismo bloque se pueden igualar', (
      tester,
    ) async {
      await pumpPage(
        tester,
        Catalogue.merge([
          catalogueOfBlocks(
            blocks: [block('teoria', 'Teoría')],
            units: const {},
            repo: 'x/teoria',
          ),
          catalogueOfBlocks(
            blocks: [block('teoria', 'Apuntes')],
            units: const {},
            repo: 'x/problemas',
          ),
        ]),
        const BetweenReposPage(),
        repos: 2,
      );

      expect(find.textContaining('Bloque teoria'), findsOneWidget);
      expect(find.text('«Teoría»'), findsOneWidget);
      expect(find.text('«Apuntes»'), findsOneWidget);
      expect(
        find.byKey(const Key('use-teoria-título (es)-x/teoria')),
        findsOneWidget,
      );
    });
  });

  group('dentro de un curso', () {
    Map<String, dynamic> courseWithBoth() => {
      'id': 'am-iii',
      'title': const {'es': 'Análisis Matemático III'},
      'language': 'es',
      'years': {
        '2025-2026': {
          'year': '2025-2026',
          'language': 'es',
          'documents': [
            {
              'id': 'tema-1',
              'kind': 'theory',
              'language': 'es',
              'title': const {'es': 'Tema 1'},
              'unitRefs': const ['analysis/normed/definition'],
            },
            {
              'id': 'hoja-1',
              'kind': 'problems',
              'language': 'es',
              'title': const {'es': 'Hoja 1'},
              'unitRefs': const ['analysis/normed/lab'],
            },
          ],
        },
      },
    };

    testWidgets('el filtro sale con más de un bloque, y filtra', (
      tester,
    ) async {
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [block('teoria', 'Teoría'), block('practicas', 'Prácticas')],
          units: {
            'content/analysis/normed/definition': 'teoria',
            'content/analysis/normed/lab': 'practicas',
          },
          courses: [courseWithBoth()],
        ),
        const YearPage(courseId: 'am-iii', year: '2025-2026'),
      );

      expect(find.byKey(const Key('year-block-practicas')), findsOneWidget);
      expect(find.text('Tema 1'), findsOneWidget);
      expect(find.text('Hoja 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('year-block-practicas')));
      await settle(tester);

      // El documento de teoría se va; el de prácticas se queda.
      expect(find.text('Tema 1'), findsNothing);
      expect(find.text('Hoja 1'), findsOneWidget);
    });

    testWidgets('y con un bloque solo no aparece', (tester) async {
      await pumpPage(
        tester,
        catalogueOfBlocks(
          blocks: [block('teoria', 'Teoría')],
          units: {
            'content/analysis/normed/definition': 'teoria',
            'content/analysis/normed/lab': 'teoria',
          },
          courses: [courseWithBoth()],
        ),
        const YearPage(courseId: 'am-iii', year: '2025-2026'),
      );

      expect(find.byKey(const Key('year-block-all')), findsNothing);
      expect(find.text('Tema 1'), findsOneWidget);
      expect(find.text('Hoja 1'), findsOneWidget);
    });
  });
}
