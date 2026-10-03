/// Los snippets en la pantalla: el gestor de Ajustes, el editor, el selector
/// de la barra y lo que avisa cuando un snippet deja de cuadrar.
///
/// La lógica está probada aparte; aquí va lo que solo se ve montado:
///
/// * que el gestor enseña los de los dos repositorios y un interruptor por
///   cada uno, y que pulsarlo escribe en el `snippets.yaml` de ese;
/// * que el editor crea uno propio y lo guarda donde se eligió;
/// * que la barra ofrece los del repositorio **del fichero**, los filtra al
///   escribir, envuelve con Intro y quita el que rodea al cursor;
/// * que un snippet de otro repositorio usado aquí se avisa en la barra.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/latex_snippets.dart';
import 'package:didacta_app/model/snippet_check.dart';
import 'package:didacta_app/model/snippets_file.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/between_repos_page.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/tex_toolbar.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';

import 'fixture.dart';

const teoria = 'test/repo';
const problemas = 'test/repo1';

/// Dos repositorios, cada uno con su pasarela.
class TwoRepos extends FakeSession {
  TwoRepos(this.gateways, Catalogue catalogue)
    : super(
        gatewayOverride: gateways.values.first,
        catalogue: catalogue,
        preferencesOverride: MemoryPreferences(),
      );

  final Map<String, FakeGateway> gateways;

  @override
  ContentGateway gatewayFor(String? repo) => gateways[repo] ?? gatewayOverride;
}

Catalogue catalogueOf(
  Map<String, List<SnippetDeclaration>?> snippets, {
  List<RepoLanguages> byRepo = const [],
}) => Catalogue(
  name: 't',
  languages: const ['es'],
  byRepo: byRepo,
  defaultLanguage: 'es',
  contentHash: '',
  units: const [],
  courses: const [],
  profiles: const [],
  errors: const [],
  snippets: snippets,
);

const resumen = SnippetDeclaration(
  id: 'resumen',
  label: 'Resumen',
  group: 'Teoría',
  environment: 'resumen',
  definition: r'\DidactaNewTheorem{resumen}{Resumen}{didactaThm}',
  sample: 'Lo esencial.',
);

late FakeGateway teoriaFiles;
late FakeGateway problemasFiles;

Future<TwoRepos> start(
  Map<String, List<SnippetDeclaration>?> declared, {
  List<RepoLanguages> byRepo = const [],
}) async {
  final catalogue = catalogueOf(declared, byRepo: byRepo);
  final session = TwoRepos({
    teoria: teoriaFiles,
    problemas: problemasFiles,
  }, catalogue);
  await session.primeForTest(catalogue);
  await session.useClonesForTest(['/tmp/didacta-0', '/tmp/didacta-1']);
  return session;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pump(WidgetTester tester, Session session, Widget page) async {
  tester.view.physicalSize = const Size(1400, 2400);
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

void main() {
  setUp(() {
    teoriaFiles = FakeGateway(files: {});
    problemasFiles = FakeGateway(files: {});
  });

  group('el gestor', () {
    testWidgets('enseña los de los dos repositorios, con un interruptor '
        'por cada uno', (tester) async {
      final session = await start({
        teoria: const [SnippetDeclaration(id: 'theorem'), resumen],
        problemas: null,
      });
      await pump(tester, session, const SettingsPage(section: 'snippets'));

      expect(find.byKey(const Key('snippet-row-resumen')), findsOneWidget);
      expect(find.byKey(const Key('snippet-row-exercise')), findsOneWidget);
      expect(find.text('Propio'), findsOneWidget);
      // Resumen está en la teoría y no en los problemas.
      expect(
        find.byKey(const Key('snippet-resumen-in-$problemas')),
        findsOneWidget,
      );

      // Buscar filtra.
      await tester.enterText(find.byKey(const Key('snippet-filter')), 'resu');
      await settle(tester);
      expect(find.byKey(const Key('snippet-row-resumen')), findsOneWidget);
      expect(find.byKey(const Key('snippet-row-exercise')), findsNothing);
    });

    testWidgets('pulsar un repositorio lo añade ahí', (tester) async {
      final session = await start({
        teoria: const [SnippetDeclaration(id: 'theorem'), resumen],
        problemas: null,
      });
      await pump(tester, session, const SettingsPage(section: 'snippets'));

      await tester.ensureVisible(
        find.byKey(const Key('snippet-resumen-in-$problemas')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('snippet-resumen-in-$problemas')));
      await settle(tester);

      final written = problemasFiles.files[Session.snippetsPath]!;
      expect(SnippetsFile(written).ids, contains('resumen'));
      expect(written, contains(r'\DidactaNewTheorem{resumen}'));
      // La teoría ya lo tenía: no se toca.
      expect(teoriaFiles.commits, isEmpty);
    });

    testWidgets('el editor crea uno propio y lo guarda donde se elige', (
      tester,
    ) async {
      final session = await start({teoria: null, problemas: null});
      await pump(tester, session, const SettingsPage(section: 'snippets'));

      await tester.tap(find.byKey(const Key('new-snippet')));
      await settle(tester);
      expect(find.byKey(const Key('snippet-editor')), findsOneWidget);
      // Sin motor en la prueba: la vista previa lo dice, en lugar de girar.
      expect(find.textContaining('Aquí no se puede compilar'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('snippet-label')),
          matching: find.byType(EditableText),
        ),
        'Caja de fórmulas',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('snippet-environment')),
          matching: find.byType(EditableText),
        ),
        'formulas',
      );
      await settle(tester);
      expect(find.text(r'\begin{formulas} … \end{formulas}'), findsOneWidget);

      // Solo en los problemas.
      await tester.ensureVisible(find.byKey(Key('snippet-editor-in-$teoria')));
      await settle(tester);
      await tester.tap(find.byKey(Key('snippet-editor-in-$teoria')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-snippet')));
      await settle(tester);

      expect(find.byKey(const Key('snippet-editor')), findsNothing);
      expect(teoriaFiles.files.containsKey(Session.snippetsPath), isFalse);
      final written = problemasFiles.files[Session.snippetsPath]!;
      expect(written, contains('- id: caja-de-formulas'));
      expect(written, contains('environment: formulas'));
    });

    testWidgets('una caja de teorema escribe su definición, y guardarla sin '
        'compilar se pregunta', (tester) async {
      final session = await start({teoria: null, problemas: null});
      await pump(tester, session, const SettingsPage(section: 'snippets'));
      await tester.tap(find.byKey(const Key('new-snippet')));
      await settle(tester);

      Finder field(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field('snippet-label'), 'Resumen');
      await tester.enterText(field('snippet-environment'), 'resumen');
      await settle(tester);
      await tester.tap(find.text('Caja de teorema'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('snippet-colour-didactaProp')));
      await settle(tester);
      expect(
        find.text(r'\DidactaNewTheorem{resumen}{Resumen}{didactaProp}'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('save-snippet')));
      await settle(tester);
      expect(find.text('¿Guardar sin haberlo compilado?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-unchecked-snippet')));
      await settle(tester);
      expect(
        teoriaFiles.files[Session.snippetsPath],
        contains(r'\DidactaNewTheorem{resumen}{Resumen}{didactaProp}'),
      );
    });

    testWidgets('con repositorios en varios idiomas, la caja lleva un título '
        'por idioma', (tester) async {
      final session = await start(
        {teoria: null, problemas: null},
        byRepo: const [
          RepoLanguages(
            repo: teoria,
            languages: ['es', 'va'],
            defaultLanguage: 'es',
          ),
          RepoLanguages(
            repo: problemas,
            languages: ['es', 'en'],
            defaultLanguage: 'es',
          ),
        ],
      );
      await pump(tester, session, const SettingsPage(section: 'snippets'));
      await tester.tap(find.byKey(const Key('new-snippet')));
      await settle(tester);

      Finder field(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field('snippet-label'), 'Resumen');
      await tester.enterText(field('snippet-environment'), 'resumen');
      await settle(tester);
      await tester.tap(find.text('Caja de teorema'));
      await settle(tester);

      // El de referencia lleva el rótulo; los demás, vacíos, dicen qué sale.
      expect(find.text('Título en castellano'), findsOneWidget);
      expect(find.byKey(const Key('snippet-box-title-va')), findsOneWidget);
      expect(find.byKey(const Key('snippet-box-title-en')), findsOneWidget);
      expect(
        find.text(r'\DidactaNewTheorem{resumen}{Resumen}{didactaThm}'),
        findsOneWidget,
      );
      // La vista previa se puede mirar en cada uno.
      expect(find.byKey(const Key('snippet-preview-language')), findsOneWidget);

      await tester.enterText(field('snippet-box-title-va'), 'Resum');
      await settle(tester);
      const translated =
          r'\DidactaNewTheorem{resumen}'
          r'{\DidactaTranslated{es=Resumen, va=Resum}}{didactaThm}';
      expect(find.text(translated), findsOneWidget);

      // Sin el repositorio en valenciano, el título en valenciano se queda.
      await tester.ensureVisible(find.byKey(Key('snippet-editor-in-$teoria')));
      await settle(tester);
      await tester.tap(find.byKey(Key('snippet-editor-in-$teoria')));
      await settle(tester);
      expect(find.byKey(const Key('snippet-box-title-va')), findsOneWidget);

      await tester.tap(find.byKey(const Key('save-snippet')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-unchecked-snippet')));
      await settle(tester);
      final written = problemasFiles.files[Session.snippetsPath]!;
      expect(written, contains('    definition: |\n      $translated'));
    });

    testWidgets('no deja redefinir un entorno de Didacta', (tester) async {
      final session = await start({teoria: null, problemas: null});
      await pump(tester, session, const SettingsPage(section: 'snippets'));
      await tester.tap(find.byKey(const Key('new-snippet')));
      await settle(tester);

      Finder field(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field('snippet-label'), 'Otro teorema');
      await tester.enterText(field('snippet-environment'), 'theorem');
      await tester.tap(find.text('Caja de teorema'));
      await settle(tester);
      expect(
        find.textContaining('Didacta ya define «theorem»'),
        findsOneWidget,
      );
      final save = tester.widget<FilledButton>(
        find.byKey(const Key('save-snippet')),
      );
      expect(save.onPressed, isNull);
    });
  });

  group('la barra', () {
    Future<TextEditingController> pumpBar(
      WidgetTester tester,
      Session session, {
      String text = 'Una frase importante.',
      String repo = teoria,
    }) async {
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );
      await pump(
        tester,
        session,
        Column(
          children: [
            TexToolbar(controller: controller, enabled: true, repo: repo),
            const Expanded(child: SizedBox()),
          ],
        ),
      );
      return controller;
    }

    testWidgets(
      'ofrece los del repositorio del fichero, y filtra al escribir',
      (tester) async {
        final session = await start({
          teoria: const [SnippetDeclaration(id: 'theorem'), resumen],
          problemas: const [SnippetDeclaration(id: 'exercise')],
        });
        await pumpBar(tester, session);

        await tester.tap(find.byKey(const Key('wrap-menu')));
        await settle(tester);
        expect(find.byKey(const Key('wrap-item-resumen')), findsOneWidget);
        expect(find.byKey(const Key('wrap-item-theorem')), findsOneWidget);
        // El ejercicio es de los problemas, y este fichero es de la teoría.
        expect(find.byKey(const Key('wrap-item-exercise')), findsNothing);

        // Sin tildes ni mayúsculas: «teore» es «Teorema».
        await tester.enterText(
          find.byKey(const Key('snippet-search')),
          'teore',
        );
        await settle(tester);
        expect(find.byKey(const Key('wrap-item-theorem')), findsOneWidget);
        expect(find.byKey(const Key('wrap-item-resumen')), findsNothing);
      },
    );

    testWidgets('Intro envuelve lo marcado con el primero que casa', (
      tester,
    ) async {
      final session = await start({
        teoria: const [resumen],
        problemas: null,
      });
      final controller = await pumpBar(
        tester,
        session,
        text: 'Una frase importante.',
      );
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('wrap-menu')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('snippet-search')), 'resu');
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      expect(
        controller.text,
        '\\begin{resumen}\nUna frase importante.\n\\end{resumen}',
      );
    });

    testWidgets(
      'dentro de un snippet, ofrece quitarlo sin tocar lo de dentro',
      (tester) async {
        final session = await start({
          teoria: const [resumen],
          problemas: null,
        });
        final controller = await pumpBar(
          tester,
          session,
          text: '\\begin{resumen}\nLo de dentro.\n\\end{resumen}',
        );
        controller.selection = const TextSelection.collapsed(offset: 20);
        await settle(tester);

        await tester.tap(find.byKey(const Key('wrap-menu')));
        await settle(tester);
        expect(find.text('Quitar «Resumen»'), findsOneWidget);
        await tester.tap(find.byKey(const Key('unwrap-item-resumen')));
        await settle(tester);
        expect(controller.text, 'Lo de dentro.');
      },
    );

    testWidgets('un snippet de otro repositorio se avisa en la barra', (
      tester,
    ) async {
      final session = await start({
        teoria: const [resumen],
        problemas: const [SnippetDeclaration(id: 'exercise')],
      });
      final controller = await pumpBar(
        tester,
        session,
        repo: problemas,
        text: 'Antes.\n\\begin{resumen}\nX\n\\end{resumen}',
      );
      expect(find.byKey(const Key('snippet-warnings')), findsOneWidget);

      await tester.tap(find.byKey(const Key('snippet-warnings')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('snippet-warning-0')));
      await settle(tester);
      // Lleva el cursor a donde está.
      expect(controller.selection.baseOffset, 7);
    });
  });

  group('entre repositorios', () {
    testWidgets('enseña el que no coincide y lo iguala', (tester) async {
      teoriaFiles.files[Session.snippetsPath] = 'snippets:\n  - id: resumen\n';
      problemasFiles.files[Session.snippetsPath] =
          'snippets:\n  - id: resumen\n';
      final session = await start({
        teoria: const [resumen],
        problemas: const [
          SnippetDeclaration(
            id: 'resumen',
            label: 'Resumen',
            group: 'Teoría',
            environment: 'resumen',
            definition: r'\DidactaNewTheorem{resumen}{Resumen}{didactaDefn}',
            sample: 'Lo esencial.',
          ),
        ],
      });
      await pump(tester, session, const BetweenReposPage());

      expect(find.byKey(const Key('snippet-conflict-resumen')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('use-snippet-resumen-from-$teoria')),
      );
      await tester.tap(
        find.byKey(const Key('use-snippet-resumen-from-$teoria')),
      );
      await settle(tester);
      expect(
        problemasFiles.files[Session.snippetsPath],
        contains('didactaThm'),
      );
    });
  });

  group('los avisos', () {
    final library = catalogueOf({
      teoria: const [resumen],
      problemas: const [
        SnippetDeclaration(
          id: 'diapo',
          label: 'Diapositiva con título',
          environment: 'frame',
          arguments: '{Título}',
        ),
      ],
    }).snippetLibrary([teoria, problemas]);

    test('uno de otro repositorio no compila aquí', () {
      final here = resolveSnippets(const [SnippetDeclaration(id: 'theorem')]);
      final warnings = checkSnippets(
        'Texto.\n\\begin{resumen}\nX\n\\end{resumen}\n',
        here: here,
        library: library,
      );
      expect(warnings, hasLength(1));
      expect(warnings.single.line, 2);
      expect(warnings.single.message, contains('no compila'));
    });

    test('en su repositorio no se avisa', () {
      final here = resolveSnippets(const [resumen]);
      expect(
        checkSnippets(
          '\\begin{resumen}\nX\n\\end{resumen}',
          here: here,
          library: library,
        ),
        isEmpty,
      );
    });

    test('sin sus argumentos se avisa', () {
      final here = resolveSnippets(const [
        SnippetDeclaration(
          id: 'diapo',
          label: 'Diapositiva con título',
          environment: 'frame',
          arguments: '{Título}',
        ),
      ]);
      final warnings = checkSnippets(
        '\\begin{frame}{Bien}\nX\n\\end{frame}\n\\begin{frame}\nY\n\\end{frame}',
        here: here,
        library: library,
      );
      expect(warnings, hasLength(1));
      expect(warnings.single.line, 4);
    });

    test('si otro snippet de aquí usa el entorno sin argumentos, no se '
        'avisa', () {
      final here = resolveSnippets(const [
        SnippetDeclaration(id: 'frame'),
        SnippetDeclaration(
          id: 'diapo',
          label: 'Diapositiva con título',
          environment: 'frame',
          arguments: '{Título}',
        ),
      ]);
      expect(
        checkSnippets(
          '\\begin{frame}\nY\n\\end{frame}',
          here: here,
          library: library,
        ),
        isEmpty,
      );
    });

    test('uno de Didacta sin definición compila en cualquier parte', () {
      final here = resolveSnippets(const [resumen]);
      expect(
        checkSnippets(
          '\\begin{theorem}\nX\n\\end{theorem}',
          here: here,
          library: catalogueOf({
            teoria: const [resumen],
            problemas: const [SnippetDeclaration(id: 'theorem')],
          }).snippetLibrary([teoria, problemas]),
        ),
        isEmpty,
      );
    });
  });
}
