/// Las capturas de las plantillas: su sección de Ajustes y el editor con la
/// vista previa.
///
/// Con la sesión de mentira de las pruebas --dos repositorios, la teoría con
/// el índice de verdad del curso de ejemplo y los problemas declarando una de
/// las mismas plantillas-- y, para la vista previa, **el motor de verdad**:
/// el editor compila una lección con `didacta template-preview` sobre una
/// copia del curso de ejemplo, así que el PDF que se ve es el que saldría.
///
///     cd app && DIDACTA_SHOTS_OUT=<carpeta> flutter test tool/shots_templates.dart
///
/// Con `DIDACTA_SHOTS_DARK=1`, en oscuro.
library;

import 'dart:async';
import 'dart:convert';
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
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/template_editor.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';

import '../test/fixture.dart';
import 'generate_screenshots.dart' show loadFonts, shotTheme;

final String outputDir =
    Platform.environment['DIDACTA_SHOTS_OUT'] ?? '/tmp/didacta-shots';
final bool dark = Platform.environment['DIDACTA_SHOTS_DARK'] == '1';

final DidactaPalette shotPalette = dark
    ? DidactaPalette.dark
    : DidactaPalette.light;
final GlobalKey _frame = GlobalKey();

const teoria = 'test/repo';
const problemas = 'test/repo1';

const String templatesYaml = '''
templates:
  - id: slides
    title:
      es: Diapositivas
    class: beamer
    options: "10pt,notheorems"
    axes: {medium: slides, detail: brief, pauses: "on"}

  - id: notes
    title:
      es: Apuntes
    class: article
    options: "11pt,oneside"
    axes: {medium: document, detail: full}

  - id: book
    title:
      es: Libro
    class: book
    options: "11pt,twoside,openright"
    axes: {medium: document, detail: full}
    active: false
''';

const String notesPreamble =
    '\\usepackage{lmodern}\n'
    '\\geometry{margin=2.6cm}\n'
    '\\definecolor{didactaThm}{HTML}{8C3B2E}\n';

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

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes;
  });
  final file = File('$outputDir/$name${dark ? '-oscuro' : ''}.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!.buffer.asUint8List(), flush: true);
  stdout.writeln('  ${file.path}');
}

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
  Size size = const Size(1280, 860),
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

Map<String, dynamic> _read(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

void main() {
  late TwoRepos session;
  late String demo;

  setUpAll(() async {
    await loadFonts();
    final cache = Directory.systemTemp.createTempSync('didacta-pdfrx-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => cache.path,
        );
    final root = engineRoot()!;
    final work = Directory.systemTemp.createTempSync('didacta-tpl-shots-');
    demo = '${work.path}/demo';
    final copy = await Process.run('cp', [
      '-R',
      '$root/examples/demo-course',
      demo,
    ]);
    if (copy.exitCode != 0) throw StateError('${copy.stderr}');
    File('$demo/templates.yaml').writeAsStringSync(templatesYaml);
    Directory('$demo/templates').createSync();
    File('$demo/templates/notes.tex').writeAsStringSync(notesPreamble);
    final index = await Process.run('python3', [
      '-B',
      '$root/cli/didacta',
      'index',
    ], workingDirectory: demo);
    if (index.exitCode != 0) throw StateError('${index.stderr}');
  });

  setUp(() async {
    final root = engineRoot()!;
    final compiler = Compiler(enginePath: root, repositoryPath: demo);
    final theory = Catalogue.fromIndex(
      manifest: _read('$demo/generated/manifest.json'),
      units: _read('$demo/generated/units.json'),
      courses: _read('$demo/generated/courses.json'),
      repo: teoria,
    );
    final problems = Catalogue.fromIndex(
      manifest: {
        'schemaVersion': supportedSchemaVersion,
        'name': 'Problemas',
        'languages': const ['es'],
        'defaultLanguage': 'es',
        'contentHash': 'p',
        'taxonomy': const {'blocks': <Map<String, dynamic>>[]},
        'templates': [
          {
            'id': 'notes',
            'title': {'es': 'Apuntes'},
            'label': 'Apuntes',
            'family': 'notes',
            'reveals': 'statements',
            'documentClass': 'article',
            'classOptions': '11pt,oneside',
            'axes': const {'medium': 'document', 'detail': 'full'},
            'active': true,
            'hasPreamble': true,
          },
        ],
        'profiles': const <Map<String, dynamic>>[],
        'errors': const <String>[],
      },
      units: {'schemaVersion': supportedSchemaVersion, 'units': const []},
      courses: {'schemaVersion': supportedSchemaVersion, 'courses': const []},
      repo: problemas,
    );
    final data = Catalogue.merge([theory, problems]);
    final files = {
      'templates.yaml': templatesYaml,
      'templates/notes.tex': notesPreamble,
    };
    session = TwoRepos(
      {
        teoria: FakeGateway(files: {...files}),
        problemas: FakeGateway(files: {...files}),
      },
      data,
      compilerOverride: compiler,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    await session.primeForTest(data);
    // ignore: invalid_use_of_visible_for_testing_member
    await session.useClonesForTest(['/tmp/teoria', '/tmp/problemas']);
  });

  testWidgets('la sección', (tester) async {
    await mount(
      tester,
      session,
      const SettingsPage(section: 'plantillas'),
      size: const Size(1280, 1100),
    );
    await shoot(tester, 'plantillas-seccion');
  });

  testWidgets('el editor, con la vista previa compilada', (tester) async {
    await mount(tester, session, const SizedBox());
    final context = tester.element(find.byType(SizedBox).last);
    final notes = session.catalogue.templatesInUse.firstWhere(
      (template) => template.id == 'notes',
    );
    unawaited(showTemplateEditor(context, session: session, template: notes));
    await tester.pump(const Duration(milliseconds: 300));
    await wait(tester, rounds: 20);
    await shoot(tester, 'plantillas-editor');

    // Y lo de abajo: la cabecera, dónde está y qué se compila con ella.
    await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, 'plantillas-editor-abajo');
  });

  testWidgets('el editor, diapositivas sin notheorems', (tester) async {
    await mount(tester, session, const SizedBox());
    final context = tester.element(find.byType(SizedBox).last);
    final slides = session.catalogue.templatesInUse.firstWhere(
      (template) => template.id == 'slides',
    );
    unawaited(
      showTemplateEditor(
        context,
        session: session,
        template: slides,
        duplicate: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('template-options')), '10pt');
    await tester.pump(const Duration(milliseconds: 300));
    await wait(tester, rounds: 24);
    await shoot(tester, 'plantillas-editor-error');
  });
}
