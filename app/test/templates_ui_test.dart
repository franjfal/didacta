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

import 'package:didacta_app/data/content_gateway.dart';
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

/// Una sesión con una pasarela por repositorio, para ver que se escribe en
/// los dos.
class TwoRepoSession extends FakeSession {
  TwoRepoSession({
    required this.gateways,
    required super.catalogue,
    required super.gatewayOverride,
  });

  final Map<String, ContentGateway> gateways;

  @override
  ContentGateway gatewayFor(String? repo) =>
      gateways[repo] ?? super.gatewayFor(repo);
}

/// Dos repositorios abiertos, `test/repo` y `test/repo1`, que declaran las
/// plantillas que se les diga.
Future<(TwoRepoSession, FakeGateway, FakeGateway)> twoRepos({
  List<Map<String, dynamic>> first = const [],
  List<Map<String, dynamic>> second = const [],
  Map<String, String> firstFiles = const {},
  Map<String, String> secondFiles = const {},
}) async {
  final one = FakeGateway(files: {...firstFiles});
  final two = FakeGateway(files: {...secondFiles});
  final catalogue = Catalogue.merge([
    catalogueOf(templates: first, repo: 'test/repo'),
    catalogueOf(templates: second, repo: 'test/repo1'),
  ]);
  final session = TwoRepoSession(
    gateways: {'test/repo': one, 'test/repo1': two},
    gatewayOverride: one,
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  await session.useClonesForTest(['/tmp/didacta-0', '/tmp/didacta-1']);
  return (session, one, two);
}

/// Abre la sección de plantillas de Ajustes.
Future<void> openTemplates(WidgetTester tester, Session session) =>
    pump(tester, session, const SettingsPage(section: 'plantillas'));

/// Pulsa algo que puede estar más abajo de lo que se ve.
Future<void> tapDown(WidgetTester tester, Finder target) async {
  // Sin foco: un campo con el cursor vuelve a desplazar la lista hasta él en
  // cuanto se repinta, y lo de abajo se queda fuera.
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
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
      await openTemplates(tester, session);

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
      await openTemplates(tester, session);

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
      await openTemplates(tester, session);

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
      await openTemplates(tester, session);

      await tapDown(tester, find.byKey(const Key('template-edit-notes')));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('template-preamble-text')),
          matching: find.byType(EditableText),
        ),
        '\\geometry{margin=3cm}',
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('template-save')));
      await settle(tester);

      expect(gateway.files['templates/notes.tex'], contains('margin=3cm'));
    });

    testWidgets('editar una de serie avisa de dónde se va a escribir', (
      tester,
    ) async {
      // La única forma de que nadie se encuentre su material compilando
      // distinto sin saber por qué.
      final (session, gateway) = await sessionWith(catalogue: catalogueOf());
      await openTemplates(tester, session);

      await tapDown(tester, find.byKey(const Key('template-edit-book')));

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

  test('la carpeta del programa se apunta como una fuente más', () {
    // Si el repositorio declara el mismo id gana el repositorio, pero la
    // casilla del programa tiene que salir marcada: el fichero está ahí.
    final catalogue = catalogueOf(templates: [templateJson('notes')]);
    final stored = OutputTemplate.fromJson(
      templateJson('notes', documentClass: 'book'),
    ).declaredBy(Session.programTemplates);
    final merged = catalogue.withTemplates([stored]).templates.single;
    expect(merged.sources.keys, ['test/repo', Session.programTemplates]);
    expect(merged.documentClass, 'article');
  });

  group('su sección de Ajustes', () {
    test('va justo antes de los snippets, también en la interfaz sencilla', () {
      // Era un botón dentro de «Bloques y plantillas», que solo sale con la
      // interfaz completa: quien buscaba dónde se edita lo que sale de
      // compilar no lo encontraba.
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueOf(),
        preferencesOverride: MemoryPreferences(),
      );
      final ids = [for (final s in settingsSections(session)) s.id];
      expect(ids, contains('plantillas'));
      expect(ids.indexOf('plantillas') + 1, ids.indexOf('snippets'));
    });

    testWidgets('marcar otro repositorio la copia allí, con su cabecera', (
      tester,
    ) async {
      final (session, one, two) = await twoRepos(
        first: [templateJson('slides', title: 'Diapositivas')],
        firstFiles: {
          'templates.yaml': templatesYaml,
          'templates/slides.tex': '\\usepackage{lmodern}\n',
        },
      );
      // La cabecera la dice el índice; aquí basta con que el fichero esté.
      final withPreamble = Catalogue.merge([
        catalogueOf(
          templates: [
            {
              ...templateJson('slides', title: 'Diapositivas'),
              'hasPreamble': true,
            },
          ],
          repo: 'test/repo',
        ),
        catalogueOf(repo: 'test/repo1'),
      ]);
      await session.primeForTest(withPreamble);
      await openTemplates(tester, session);

      await tapDown(
        tester,
        find.byKey(const Key('template-slides-in-test/repo1')),
      );

      final copied = TemplatesFile(two.files['templates.yaml']!);
      expect(copied.ids, contains('slides'));
      expect(copied.fieldOf('slides', 'class'), 'article');
      expect(two.files['templates/slides.tex'], contains('lmodern'));
      // Y el primero sigue igual.
      expect(TemplatesFile(one.files['templates.yaml']!).ids, [
        'slides',
        'notes',
      ]);
    });

    testWidgets('desmarcar uno la quita solo de ahí', (tester) async {
      final (session, one, two) = await twoRepos(
        first: [templateJson('slides')],
        second: [templateJson('slides')],
        firstFiles: {'templates.yaml': templatesYaml},
        secondFiles: {'templates.yaml': templatesYaml},
      );
      await openTemplates(tester, session);

      await tapDown(
        tester,
        find.byKey(const Key('template-slides-in-test/repo1')),
      );

      expect(TemplatesFile(two.files['templates.yaml']!).ids, ['notes']);
      expect(TemplatesFile(one.files['templates.yaml']!).ids, [
        'slides',
        'notes',
      ]);
    });

    testWidgets('la cabecera se guarda en todos los que la declaran', (
      tester,
    ) async {
      // Dos cabeceras para la misma plantilla son dos PDF distintos con el
      // mismo nombre.
      final (session, one, two) = await twoRepos(
        first: [templateJson('notes')],
        second: [templateJson('notes')],
        firstFiles: {'templates.yaml': templatesYaml},
        secondFiles: {'templates.yaml': templatesYaml},
      );
      await openTemplates(tester, session);
      await tapDown(tester, find.byKey(const Key('template-edit-notes')));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('template-preamble-text')),
          matching: find.byType(EditableText),
        ),
        '\\geometry{margin=3cm}',
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('template-save')));
      await settle(tester);

      expect(one.files['templates/notes.tex'], contains('margin=3cm'));
      expect(two.files['templates/notes.tex'], contains('margin=3cm'));
    });
  });

  group('el editor', () {
    testWidgets('dice qué se compila con ella', (tester) async {
      final (session, _) = await sessionWith(
        catalogue: catalogueOf(
          templates: [templateJson('slides', title: 'Diapositivas')],
          blocks: [
            blockJson('theory', templates: ['slides']),
          ],
        ),
        files: {'templates.yaml': templatesYaml},
      );
      await openTemplates(tester, session);
      expect(find.textContaining('la usa 1 cosa'), findsOneWidget);

      await tapDown(tester, find.byKey(const Key('template-edit-slides')));
      expect(find.byKey(const Key('template-editor')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('template-uses')),
          matching: find.textContaining('Teoría'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('avisa de beamer sin notheorems', (tester) async {
      // Sin esa opción beamer trae sus propios teoremas, chocan con los de
      // Didacta y no compila nada: pasó al escribir la primera plantilla de
      // diapositivas a mano.
      final (session, _) = await sessionWith(
        catalogue: catalogueOf(templates: [templateJson('slides')]),
        files: {'templates.yaml': templatesYaml},
      );
      await openTemplates(tester, session);
      await tapDown(tester, find.byKey(const Key('new-template')));
      expect(find.byKey(const Key('template-notheorems')), findsNothing);

      await tester.enterText(find.byKey(const Key('template-class')), 'beamer');
      await settle(tester);
      expect(find.byKey(const Key('template-notheorems')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('template-options')),
        '10pt,notheorems',
      );
      await settle(tester);
      expect(find.byKey(const Key('template-notheorems')), findsNothing);
    });

    testWidgets('una nueva se declara en los repositorios marcados', (
      tester,
    ) async {
      final (session, one, two) = await twoRepos(
        first: [templateJson('slides')],
        firstFiles: {'templates.yaml': templatesYaml},
      );
      await openTemplates(tester, session);
      await tapDown(tester, find.byKey(const Key('new-template')));

      await tester.enterText(find.byKey(const Key('template-id')), 'a5');
      await tapDown(
        tester,
        find.byKey(const Key('template-editor-in-test/repo1')),
      );
      await tester.tap(find.byKey(const Key('template-save')));
      await settle(tester);

      expect(TemplatesFile(one.files['templates.yaml']!).ids, contains('a5'));
      expect(TemplatesFile(two.files['templates.yaml']!).ids, contains('a5'));
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
      await pump(tester, session, const SettingsPage(section: 'material'));

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
      await pump(tester, session, const SettingsPage(section: 'material'));
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
      await pump(tester, session, const SettingsPage(section: 'material'));
      unawaited(showBlocks(tester.element(find.byType(SettingsPage)), session));
      await settle(tester);
      await tester.tap(find.byKey(const Key('block-templates-theory')));
      await settle(tester);

      // Se dice que hay algo que no se puede enseñar, en el diálogo: el
      // catálogo de la misma sección de Ajustes también lo avisa.
      expect(
        find.textContaining('que no se pueden enseñar aquí'),
        findsOneWidget,
      );

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
      await pump(tester, session, const SettingsPage(section: 'material'));
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
