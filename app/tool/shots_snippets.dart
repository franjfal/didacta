/// Las capturas de los snippets: el gestor, el editor, el selector de la barra
/// y lo que no coincide entre dos repositorios.
///
/// Con la sesión de mentira de las pruebas --dos repositorios, cada uno con su
/// `snippets.yaml`-- y, para la vista previa, **el motor de verdad**: el
/// editor compila el snippet con `didacta snippet-preview` sobre una copia del
/// curso de ejemplo, así que el PDF que se ve es el que saldría.
///
///     cd app && DIDACTA_SHOTS_OUT=<carpeta> flutter test tool/shots_snippets.dart
///
/// Con `DIDACTA_SHOTS_DARK=1`, en oscuro.
library;

import 'dart:async';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/latex_snippets.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/between_repos_page.dart';
import 'package:didacta_app/ui/manage_snippets.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/tex_field.dart';
import 'package:didacta_app/ui/tex_highlight.dart';
import 'package:didacta_app/ui/tex_toolbar.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';

import '../test/fixture.dart';
import 'generate_screenshots.dart' show loadFonts, shotTheme;

final String outputDir =
    Platform.environment['DIDACTA_SHOTS_OUT'] ?? '/tmp/didacta-shots';
final bool dark = Platform.environment['DIDACTA_SHOTS_DARK'] == '1';

/// La paleta de las capturas: la del modo que se está pintando.
final DidactaPalette shotPalette = dark
    ? DidactaPalette.dark
    : DidactaPalette.light;
final GlobalKey _frame = GlobalKey();

const teoria = 'test/repo';
const problemas = 'test/repo1';

class TwoRepos extends FakeSession {
  TwoRepos(this.gateways, Catalogue catalogue, {super.compilerOverride})
    : super(
        gatewayOverride: gateways.values.first,
        catalogue: catalogue,
        preferencesOverride: MemoryPreferences(),
      );

  final Map<String, FakeGateway> gateways;

  @override
  ContentGateway gatewayFor(String? repo) => gateways[repo] ?? gatewayOverride;
}

const resumen = SnippetDeclaration(
  id: 'resumen',
  label: 'Resumen',
  group: 'Teoría',
  description: 'Lo esencial del tema, en una caja.',
  environment: 'resumen',
  arguments: '[Título]',
  definition: r'\DidactaNewTheorem{resumen}{Resumen}{didactaProp}',
  sample:
      r'Una función continua en un intervalo cerrado y acotado alcanza '
      r'su máximo y su mínimo: existen $a, b \in [x_0, x_1]$ con '
      r'$f(a) \le f(x) \le f(b)$.',
);

const rojo = SnippetDeclaration(
  id: 'en-rojo',
  label: 'En rojo',
  group: 'Formato',
  command: 'textcolor',
  arguments: '{red}',
);

Catalogue catalogue() => Catalogue(
  name: 't',
  languages: const ['es'],
  defaultLanguage: 'es',
  contentHash: '',
  units: const [],
  courses: const [],
  profiles: const [],
  errors: const [],
  snippets: {
    teoria: const [
      SnippetDeclaration(id: 'frame'),
      SnippetDeclaration(id: 'didactatitle'),
      SnippetDeclaration(id: 'theorem', label: 'Teorema (con nombre)'),
      SnippetDeclaration(id: 'definition'),
      resumen,
      SnippetDeclaration(id: 'proposition'),
      SnippetDeclaration(id: 'lemma'),
      SnippetDeclaration(id: 'corollary'),
      SnippetDeclaration(id: 'example'),
      SnippetDeclaration(id: 'proof'),
      rojo,
      SnippetDeclaration(id: 'teaching'),
    ],
    problemas: const [
      SnippetDeclaration(id: 'exercise'),
      SnippetDeclaration(id: 'parts'),
      SnippetDeclaration(id: 'answer'),
      SnippetDeclaration(id: 'solution'),
      SnippetDeclaration(id: 'hint'),
      SnippetDeclaration(
        id: 'en-rojo',
        label: 'En rojo',
        group: 'Formato',
        command: 'textcolor',
        arguments: '{red!70!black}',
      ),
      SnippetDeclaration(id: 'theorem'),
    ],
  },
);

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes;
  });
  final file = File('$outputDir/$name${dark ? '-oscuro' : ''}.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!.buffer.asUint8List(), flush: true);
  stdout.writeln('  ${file.path}');
}

/// Deja pasar el tiempo de verdad: el motor compila fuera del reloj falso.
Future<void> wait(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> mount(
  WidgetTester tester,
  Session session,
  Widget page, {
  Size size = const Size(1280, 820),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<McpService>(
          create: (_) => McpService(
            openRunner: () => const UnavailableRunner('Sin servidor.'),
          ),
        ),
        ChangeNotifierProvider<UpdateService>(create: (_) => offlineUpdates()),
        ChangeNotifierProvider<TourController>(create: (_) => TourController()),
      ],
      child: RepaintBoundary(
        key: _frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shotTheme(shotPalette),
          home: Scaffold(body: page),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

String? engineRoot() {
  var directory = Directory.current;
  for (var i = 0; i < 4; i += 1) {
    if (File('${directory.path}/cli/didacta').existsSync()) {
      return directory.path;
    }
    directory = directory.parent;
  }
  return null;
}

void main() {
  late TwoRepos session;
  late String demo;

  setUpAll(() async {
    await loadFonts();
    // pdfrx pregunta por una carpeta temporal para su caché, y en una prueba
    // no hay plugin que conteste.
    final cache = Directory.systemTemp.createTempSync('didacta-pdfrx-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => cache.path,
        );
    final root = engineRoot()!;
    final work = Directory.systemTemp.createTempSync('didacta-snippet-shots-');
    demo = '${work.path}/demo';
    final copy = await Process.run('cp', [
      '-R',
      '$root/examples/demo-course',
      demo,
    ]);
    if (copy.exitCode != 0) throw StateError('${copy.stderr}');
  });

  setUp(() async {
    final root = engineRoot()!;
    final compiler = Compiler(enginePath: root, repositoryPath: demo);
    final data = catalogue();
    session = TwoRepos(
      {teoria: FakeGateway(files: {}), problemas: FakeGateway(files: {})},
      data,
      compilerOverride: compiler,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    await session.primeForTest(data);
    // ignore: invalid_use_of_visible_for_testing_member
    await session.useClonesForTest(['/tmp/teoria', '/tmp/problemas']);
  });

  testWidgets('el gestor', (tester) async {
    await mount(
      tester,
      session,
      const SettingsPage(section: 'snippets'),
      size: const Size(1280, 1180),
    );
    await shoot(tester, 'snippets-gestor');
  });

  testWidgets('el editor, con la vista previa compilada', (tester) async {
    await mount(tester, session, const SizedBox());
    final context = tester.element(find.byType(SizedBox).last);
    final entry = session.snippetLibrary.firstWhere((e) => e.id == 'resumen');
    unawaited(showSnippetEditor(context, session: session, entry: entry));
    await tester.pump(const Duration(milliseconds: 300));
    await wait(tester, rounds: 16);
    await shoot(tester, 'snippets-editor');

    // Y en diapositivas.
    await tester.tap(find.byKey(const Key('snippet-preview-profile')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('filter-option-Diapositivas')));
    await tester.pump(const Duration(milliseconds: 300));
    await wait(tester, rounds: 24);
    await shoot(tester, 'snippets-editor-diapositivas');
  });

  testWidgets('el editor, con un error en la definición', (tester) async {
    await mount(tester, session, const SizedBox());
    final context = tester.element(find.byType(SizedBox).last);
    unawaited(
      showSnippetEditor(
        context,
        session: session,
        template: const LatexSnippet(
          id: 'caja',
          label: 'Caja de fórmulas',
          group: 'Propios',
          environment: 'caja',
          definition:
              '\\newenvironment{caja}\n  {\\begin{tcolorbox}[colback=white'
              '\n  {\\end{tcolorbox}}',
          sample: r'$\int_a^b f(x)\,dx = F(b) - F(a)$',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await wait(tester, rounds: 16);
    await shoot(tester, 'snippets-editor-error');
  });

  testWidgets('la barra', (tester) async {
    final controller = TexEditingController(
      text:
          '\\begin{resumen}[Compacidad]\n'
          r'Toda sucesión acotada en $\mathbb{R}^n$ tiene una subsucesión '
          'convergente.\n'
          '\\end{resumen}\n\n'
          'Un teorema de otro repositorio:\n'
          '\\begin{frame}\nSin título.\n\\end{frame}\n',
    );
    controller.selection = const TextSelection.collapsed(offset: 40);
    await mount(
      tester,
      session,
      Padding(
        padding: const EdgeInsets.all(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: shotPalette.rule),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TexToolbar(controller: controller, enabled: true, repo: teoria),
              Expanded(
                child: ColoredBox(
                  color: shotPalette.card,
                  child: TexField(
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('wrap-menu')));
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, 'snippets-barra');

    await tester.enterText(find.byKey(const Key('snippet-search')), 'caja');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, 'snippets-barra-buscar');
  });

  testWidgets('la barra avisa', (tester) async {
    final controller = TexEditingController(
      text:
          'Un ejercicio que usa una caja de la teoría:\n'
          '\\begin{resumen}\nLo esencial.\n\\end{resumen}\n',
    );
    controller.selection = const TextSelection.collapsed(offset: 3);
    await mount(
      tester,
      session,
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TexToolbar(controller: controller, enabled: true, repo: problemas),
            Expanded(
              child: ColoredBox(
                color: shotPalette.card,
                child: TexField(
                  controller: controller,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
      size: const Size(1100, 420),
    );
    await tester.tap(find.byKey(const Key('snippet-warnings')));
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, 'snippets-aviso');
  });

  testWidgets('entre repositorios', (tester) async {
    await mount(
      tester,
      session,
      const BetweenReposPage(),
      size: const Size(1280, 1000),
    );
    await shoot(tester, 'snippets-entre-repositorios');
  });
}
