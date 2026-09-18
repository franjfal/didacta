/// Las plantillas en pantalla: Ajustes, el bloque, el tema y la lección.
///
/// Lo que se prueba aquí es lo que ningún test de modelo vería romperse: que
/// se puede llegar a editar una salida sin abrir un YAML, que apagar una
/// escribe lo que dice que escribe, y que los tres sitios donde se elige
/// --bloque, tema, lección-- guardan en el fichero que les toca.
///
/// Y una cosa más, que es la que importa de verdad: que editar una de las que
/// trae Didacta **avisa de que se escribe en tu repositorio**. Es la única
/// forma de que nadie se encuentre su material compilando distinto sin saber
/// por qué.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/templates_file.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/manage_blocks.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

const String templatesYaml = '''
# Las plantillas de este repositorio.

templates:
  - id: slides
    title:
      es: Diapositivas
    class: beamer
    options: "10pt"
    axes: {medium: slides, pauses: "on"}

  - id: notes
    title:
      es: Apuntes
    class: article
    options: "12pt,oneside"
    axes: {medium: document, detail: full}
''';

const String taxonomyYaml = '''
blocks:
  - id: theory
    title:
      es: Teoría
    templates: [slides, notes]
''';

Map<String, dynamic> templateJson(
  String id, {
  String title = '',
  String documentClass = 'article',
  bool active = true,
}) => {
  'id': id,
  if (title.isNotEmpty) 'title': {'es': title},
  'label': title.isEmpty ? id : title,
  'family': 'notes',
  'reveals': 'statements',
  'documentClass': documentClass,
  'classOptions': '',
  'axes': const <String, String>{},
  'active': active,
  'hasPreamble': false,
};

Map<String, dynamic> blockJson(
  String id, {
  List<String> templates = const [],
}) => {
  'id': id,
  'title': {'es': 'Teoría'},
  'templates': templates,
};

Catalogue catalogueOf({
  List<Map<String, dynamic>> templates = const [],
  List<Map<String, dynamic>> blocks = const [],
  List<Map<String, dynamic>> units = const [],
  String repo = 'test/repo',
}) => Catalogue.fromIndex(
  manifest: {
    'schemaVersion': supportedSchemaVersion,
    'name': 'Prueba',
    'languages': const ['es'],
    'defaultLanguage': 'es',
    'contentHash': 'abc',
    'taxonomy': {'blocks': blocks},
    'templates': templates,
    'profiles': const [
      {
        'id': 'book',
        'label': 'Libro',
        'family': 'notes',
        'documentClass': 'book',
      },
    ],
    'errors': const <String>[],
  },
  units: {'schemaVersion': supportedSchemaVersion, 'units': units},
  courses: {
    'schemaVersion': supportedSchemaVersion,
    'courses': const <Map<String, dynamic>>[],
  },
  repo: repo,
);

Future<(FakeSession, FakeGateway)> sessionWith({
  required Catalogue catalogue,
  Map<String, String> files = const {},
}) async {
  final gateway = FakeGateway(files: {...files});
  final session = FakeSession(
    gatewayOverride: gateway,
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
  );
  await session.primeForTest(catalogue);
  await session.useClonesForTest(['/tmp/didacta-0']);
  return (session, gateway);
}

Future<void> pump(
  WidgetTester tester,
  Session session,
  Widget page, {
  Size size = const Size(1280, 2200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<McpService>(
          create: (_) => McpService(
            openRunner: () =>
                const UnavailableRunner('Sin servidor en las pruebas.'),
          ),
        ),
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
}

/// Baja hasta el botón de las plantillas en Ajustes y lo pulsa.
Future<void> openTemplates(WidgetTester tester) async {
  final button = find.byKey(const Key('open-templates'));
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
  group('Ajustes', () {
    testWidgets('resume las salidas y abre su pantalla', (tester) async {
      final (session, _) = await sessionWith(
        catalogue: catalogueOf(
          templates: [
            templateJson('slides', title: 'Diapositivas'),
            templateJson('notes', title: 'Apuntes', active: false),
          ],
        ),
      );
      await pump(tester, session, const SettingsPage());
      await openTemplates(tester);

      expect(find.byKey(const Key('template-slides')), findsOneWidget);
      expect(find.byKey(const Key('template-notes')), findsOneWidget);
      expect(find.textContaining('apagada'), findsOneWidget);
    });

    testWidgets('sin ninguna declarada ofrece las que trae Didacta', (
      tester,
    ) async {
      // Un repositorio recién abierto: se compila con las de serie, y la
      // pantalla tiene que poder enseñarlas para poder editarlas.
      final (session, _) = await sessionWith(catalogue: catalogueOf());
      await pump(tester, session, const SettingsPage());
      await openTemplates(tester);

      expect(find.byKey(const Key('template-book')), findsOneWidget);
      expect(find.text('viene con Didacta'), findsOneWidget);
      // No se apaga una del programa: lo que hay que hacer con ella es
      // traerla al repositorio.
      final box = tester.widget<Checkbox>(
        find.byKey(const Key('template-active-book')),
      );
      expect(box.onChanged, isNull);
    });
  });

  group('la pantalla de plantillas', () {
    testWidgets('apagar una escribe que está apagada', (tester) async {
      final (session, gateway) = await sessionWith(
        catalogue: catalogueOf(
          templates: [templateJson('slides', title: 'Diapositivas')],
        ),
        files: {'templates.yaml': templatesYaml},
      );
      await pump(tester, session, const SettingsPage());
      await openTemplates(tester);

      await tester.tap(find.byKey(const Key('template-active-slides')));
      await settle(tester);

      expect(
        TemplatesFile(
          gateway.files['templates.yaml']!,
        ).fieldOf('slides', 'active'),
        'false',
      );
    });

    testWidgets('la cabecera se escribe como el LaTeX que es', (tester) async {
      final (session, gateway) = await sessionWith(
        catalogue: catalogueOf(
          templates: [templateJson('notes', title: 'Apuntes')],
        ),
        files: {'templates.yaml': templatesYaml},
      );
      await pump(tester, session, const SettingsPage());
      await openTemplates(tester);

      await tester.tap(find.byKey(const Key('template-preamble-notes')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('template-preamble-text')),
        '\\geometry{margin=3cm}',
      );
      await tester.tap(find.byKey(const Key('template-preamble-save')));
      await settle(tester);

      expect(gateway.files['templates/notes.tex'], contains('margin=3cm'));
    });

    testWidgets('editar una de serie avisa de dónde se va a escribir', (
      tester,
    ) async {
      // La única forma de que nadie se encuentre su material compilando
      // distinto sin saber por qué.
      final (session, gateway) = await sessionWith(catalogue: catalogueOf());
      await pump(tester, session, const SettingsPage());
      await openTemplates(tester);

      await tester.tap(find.byKey(const Key('template-edit-book')));
      await settle(tester);

      expect(
        find.textContaining('se escribe en tu repositorio con el mismo id'),
        findsOneWidget,
      );
      // El id no se toca: es lo que hace que sustituya a la de serie.
      final field = tester.widget<TextField>(
        find.byKey(const Key('template-id')),
      );
      expect(field.enabled, isFalse);

      await tester.tap(find.byKey(const Key('template-save')));
      await settle(tester);
      expect(TemplatesFile(gateway.files['templates.yaml']!).ids, ['book']);
    });
  });

  group('elegir con qué se compila', () {
    testWidgets('un bloque guarda su lista', (tester) async {
      final (session, gateway) = await sessionWith(
        catalogue: catalogueOf(
          templates: [
            templateJson('slides', title: 'Diapositivas'),
            templateJson('notes', title: 'Apuntes'),
          ],
          blocks: [
            blockJson('theory', templates: ['slides', 'notes']),
          ],
        ),
        files: {'taxonomy.yaml': taxonomyYaml},
      );
      await pump(tester, session, const SettingsPage());

      // Desde la pantalla de bloques, que es donde se dice qué es cada parte
      // de la asignatura.
      unawaited(showBlocks(tester.element(find.byType(SettingsPage)), session));
      await settle(tester);
      await tester.tap(find.byKey(const Key('block-templates-theory')));
      await settle(tester);

      // Se quitan las diapositivas.
      await tester.tap(find.byKey(const Key('pick-template-slides')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('templates-choose-save')));
      await settle(tester);

      expect(gateway.files['taxonomy.yaml'], contains('templates: [notes]'));
    });

    testWidgets('y «lo que toque» quita la línea en vez de dejarla vacía', (
      tester,
    ) async {
      // Una lista vacía que significara «ninguna» dejaría al bloque sin
      // salidas, y el botón de compilar no haría nada sin decir por qué.
      final (session, gateway) = await sessionWith(
        catalogue: catalogueOf(
          templates: [templateJson('slides'), templateJson('notes')],
          blocks: [
            blockJson('theory', templates: ['slides']),
          ],
        ),
        files: {'taxonomy.yaml': taxonomyYaml},
      );
      await pump(tester, session, const SettingsPage());
      unawaited(showBlocks(tester.element(find.byType(SettingsPage)), session));
      await settle(tester);
      await tester.tap(find.byKey(const Key('block-templates-theory')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('templates-inherit')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('templates-choose-save')));
      await settle(tester);

      expect(gateway.files['taxonomy.yaml'], isNot(contains('templates:')));
    });

    testWidgets('lo que no se puede enseñar no se pierde al guardar', (
      tester,
    ) async {
      // El fallo que esto arregla, y que pasó de verdad: el bloque compilaba
      // en siete, dos de ellas declaradas por un repositorio que no estaba
      // abierto, y guardar la lista se las llevó por delante sin que nadie
      // las hubiera visto siquiera.
      final (session, gateway) = await sessionWith(
        catalogue: catalogueOf(
          templates: [
            templateJson('slides', title: 'Diapositivas'),
            templateJson('notes', title: 'Apuntes'),
          ],
          blocks: [
            blockJson('theory', templates: ['slides', 'notes', 'book']),
          ],
        ),
        files: {'taxonomy.yaml': taxonomyYaml},
      );
      await pump(tester, session, const SettingsPage());
      unawaited(showBlocks(tester.element(find.byType(SettingsPage)), session));
      await settle(tester);
      await tester.tap(find.byKey(const Key('block-templates-theory')));
      await settle(tester);

      // Se dice que hay algo que no se puede enseñar.
      expect(find.textContaining('book'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pick-template-slides')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('templates-choose-save')));
      await settle(tester);

      expect(
        gateway.files['taxonomy.yaml'],
        contains('templates: [notes, book]'),
      );
    });

    testWidgets('sin marcar ninguna no se puede guardar «estas»', (
      tester,
    ) async {
      final (session, _) = await sessionWith(
        catalogue: catalogueOf(
          templates: [templateJson('slides', title: 'Diapositivas')],
          blocks: [
            blockJson('theory', templates: ['slides']),
          ],
        ),
        files: {'taxonomy.yaml': taxonomyYaml},
      );
      await pump(tester, session, const SettingsPage());
      unawaited(showBlocks(tester.element(find.byType(SettingsPage)), session));
      await settle(tester);
      await tester.tap(find.byKey(const Key('block-templates-theory')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('pick-template-slides')));
      await settle(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('templates-choose-save')),
      );
      expect(button.onPressed, isNull);
    });
  });
}
