/// Capturas de las pantallas nuevas: vínculos y versiones congeladas.
///
///     cd app && flutter test tool/shots_reuse.dart
///
/// Las pinta **la propia aplicación**, con los widgets de verdad y sobre un
/// repositorio de contenido de verdad --con git y con el motor--, que es lo
/// que hace que sirvan para comprobar algo y no solo para ilustrar. Si un
/// diálogo se desborda o un indicador no sale, aquí se ve.
///
/// Escribe los PNG en `../web/docs/img/app/`, al lado de las demás. No se
/// versionan: se regeneran.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/composition_editor.dart';
import 'package:didacta_app/ui/freezes.dart';
import 'package:didacta_app/ui/reuse.dart';
import 'package:didacta_app/ui/shell.dart';
import 'package:didacta_app/ui/year_page.dart';

import '../test/fixture.dart';
import 'generate_screenshots.dart' show loadFonts, shotTheme;

const String outputDir = '../web/docs/img/app';
const Size window = Size(1280, 820);
const double density = 2.0;

final GlobalKey _frame = GlobalKey();

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

Future<void> shoot(WidgetTester tester, String name) async {
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // Dentro de `runAsync` y con el factor a uno, por lo mismo que en
  // `generate_screenshots.dart`: rasterizar y codificar un PNG es trabajo del
  // motor de verdad, y con el reloj falso de un test ese futuro no vuelve --
  // sin error, sin excepción y sin salida, hasta que expira.
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes;
  });
  if (png == null) throw StateError('no se pudo codificar $name');
  final file = File('$outputDir/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png.buffer.asUint8List(), flush: true);
  stdout.writeln('  ${(png.lengthInBytes / 1024).round()} kB  ${file.path}');
}

void main() {
  late Directory root;
  late String work;
  late String engine;
  late String remote;

  void write(String relative, String text) => File('$work/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  Future<void> run(
    String program,
    List<String> arguments, {
    Map<String, String> environment = const {},
  }) async {
    final result = await Process.run(
      program,
      arguments,
      workingDirectory: work,
      environment: {
        'GIT_AUTHOR_NAME': 'Javier Falcó',
        'GIT_AUTHOR_EMAIL': 'javier@uv.es',
        'GIT_COMMITTER_NAME': 'Javier Falcó',
        'GIT_COMMITTER_EMAIL': 'javier@uv.es',
        'GIT_TERMINAL_PROMPT': '0',
        'NO_COLOR': '1',
        ...environment,
      },
    );
    if (result.exitCode != 0) {
      throw StateError('$program ${arguments.join(' ')}: ${result.stderr}');
    }
  }

  setUpAll(() async {
    await loadFonts();
    engine = engineRoot()!;
    root = await Directory.systemTemp.createTemp('didacta-shots-');
    work = '${root.path}/db';
    Directory(work).createSync(recursive: true);

    write(
      'didacta.yaml',
      'name: didacta_db\nlanguages: [es, va]\ndefault_language: es\n',
    );
    write(
      'courses/analisis/course.yaml',
      'id: analisis\ntitle:\n  es: Análisis Matemático I\n',
    );
    write(
      'courses/matematicas/course.yaml',
      'id: matematicas\ntitle:\n  es: Matemáticas\n',
    );
    for (final name in ['convergencia', 'criterios', 'potencias']) {
      write(
        'content/analisis/series/$name/unit.yaml',
        'kind: theory\ntitle:\n  es: $name\n',
      );
      write('content/analisis/series/$name/es.tex', 'el texto de $name\n');
    }
    write(
      'courses/analisis/2025-2026/year.yaml',
      'course: analisis\nyear: 2025-2026\nlanguage: es\n\n'
          'documents:\n'
          '  - id: series\n'
          '    kind: theory\n'
          '    themes: [t-series]\n'
          '    title:\n'
          '      es: "Tema 4: series numéricas"\n'
          '      # TODO: va\n'
          '    structure:\n'
          '      - unit: analisis/series/convergencia\n'
          '      - unit: analisis/series/criterios\n'
          '      # - unit: analisis/series/potencias\n'
          '\n'
          '  - id: hoja-4\n'
          '    kind: problems\n'
          '    themes: [t-series]\n'
          '    title:\n'
          '      es: "Hoja 4: series"\n'
          '    structure:\n'
          '      - unit: analisis/series/potencias\n',
    );
    write(
      'courses/analisis/2025-2026/themes.yaml',
      'themes:\n  - id: t-series\n    title:\n'
          '      es: "Tema 4: series numéricas"\n',
    );
    for (final name in ['series', 'hoja-4']) {
      write(
        'courses/analisis/2025-2026/$name.tex',
        '\\input{didacta-bootstrap}\n\\usepackage{didacta}\n'
            '\\begin{document}\n\\DidactaUnit{analisis/series/convergencia}\n'
            '\\end{document}\n',
      );
    }
    for (final pair in const [
      ('analisis', '2026-2027'),
      ('matematicas', '2026-2027'),
    ]) {
      write(
        'courses/${pair.$1}/${pair.$2}/year.yaml',
        'course: ${pair.$1}\nyear: ${pair.$2}\nlanguage: es\n\ndocuments:\n',
      );
    }

    remote = '${root.path}/test/repo.git';
    Directory(remote).createSync(recursive: true);
    await Process.run('git', [
      'init',
      '--bare',
      '--initial-branch=main',
      remote,
    ], workingDirectory: root.path);

    await run('$engine/cli/didacta', const ['index']);
    await run('git', const ['init', '--initial-branch=main']);
    await run('git', const ['add', '.']);
    await run('git', const ['commit', '-m', 'El curso, para empezar']);
    await run('git', ['remote', 'add', 'origin', remote]);
    await run('git', const ['push', '-u', 'origin', 'main']);
  });

  tearDownAll(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Session> openSession() async {
    final session = Session(
      catalogueSource: CatalogueSource.inClone(work, repo: 'test/repo')!,
      tokenStore: StubStore(),
      preferences: MemoryPreferences()..engine = engine,
    );
    // `useClonesForTest` y `primeForTest` están marcados para tests, y esto
    // es una herramienta; el uso es exactamente el mismo --levantar una
    // sesión contra un repositorio concreto sin pasar por Ajustes-- y la
    // alternativa, moverlo a `test/`, lo metería en cada `flutter test`:
    // generar ocho PNG no es un test.
    // ignore: invalid_use_of_visible_for_testing_member
    await session.useClonesForTest([work]);
    await session.findEngine();
    // ignore: invalid_use_of_visible_for_testing_member
    await session.primeForTest(
      await CatalogueSource.inClone(work, repo: 'test/repo')!.load(),
    );
    await session.setCloneAuthor(name: 'Javier Falcó', email: 'javier@uv.es');
    return session;
  }

  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = Size(
      window.width * density,
      window.height * density,
    );
    tester.view.devicePixelRatio = density;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shotTheme(),
          home: child,
        ),
      ),
    );
  }

  Future<void> settleReal(WidgetTester tester) async {
    for (var round = 0; round < 8; round += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('el curso con un tema vinculado', (tester) async {
    late Session session;
    await tester.runAsync(() async {
      session = await openSession();
      final admin = session.admin(repo: 'test/repo')!;
      await admin.linkDocument(
        fromCourse: 'analisis',
        fromYear: '2025-2026',
        document: 'series',
        toCourse: 'analisis',
        toYear: '2026-2027',
      );
      await admin.linkDocument(
        fromCourse: 'analisis',
        fromYear: '2025-2026',
        document: 'series',
        toCourse: 'matematicas',
        toYear: '2026-2027',
      );
      await session.reloadCatalogue();
    });

    await mount(
      tester,
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: const Scaffold(
          body: YearPage(courseId: 'analisis', year: '2025-2026'),
        ),
      ),
    );
    await settleReal(tester);
    await shoot(tester, 'vinculos-curso');

    await tester.tap(find.byKey(const Key('reuse-menu-series')));
    await tester.pumpAndSettle();
    await shoot(tester, 'vinculos-menu');

    await tester.tap(find.byKey(const Key('document-places-series')));
    await tester.pumpAndSettle();
    await shoot(tester, 'vinculos-ubicaciones');
  });

  testWidgets('el diálogo de mover, vincular o duplicar', (tester) async {
    late Session session;
    await tester.runAsync(() async {
      session = await openSession();
    });
    await mount(
      tester,
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => askReuseTarget(
                context,
                session: session,
                title: 'Añadir vinculado: «Tema 4: series numéricas»',
                fromCourse: 'analisis',
                fromYear: '2025-2026',
                documentId: 'series',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shoot(tester, 'vinculos-destino');
  });

  testWidgets('editar la composición de un tema vinculado', (tester) async {
    // El repositorio es el mismo para todas las capturas y la de arriba ya
    // vinculó este tema: aquí solo se abre.
    late Session session;
    await tester.runAsync(() async {
      session = await openSession();
    });

    await mount(
      tester,
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: Scaffold(
          body: CompositionEditor(
            courseId: 'analisis',
            year: '2026-2027',
            documentId: 'series',
            session: session,
          ),
        ),
      ),
    );
    await settleReal(tester);
    await shoot(tester, 'vinculos-componer');
  });

  testWidgets('dar una lección en otro tema', (tester) async {
    late Session session;
    await tester.runAsync(() async {
      session = await openSession();
    });
    await mount(
      tester,
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => askLessonTarget(
                context,
                session: session,
                title: 'Dar «convergencia» en otro tema',
                fromCourse: 'analisis',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shoot(tester, 'vinculos-leccion');
  });

  testWidgets('dividir un grupo de sincronización', (tester) async {
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => askSplit(
              context,
              title: 'Dividir la vinculación de «Tema 4: series numéricas»',
              places: const [
                SyncPlace(
                  key: 'analisis@2025-2026/series',
                  label: 'Análisis Matemático I · 2025-2026',
                ),
                SyncPlace(
                  key: 'analisis@2026-2027/series',
                  label: 'Análisis Matemático I · 2026-2027',
                ),
                SyncPlace(
                  key: 'matematicas@2026-2027/series',
                  label: 'Matemáticas · 2026-2027',
                ),
                SyncPlace(
                  key: 'doble@2026-2027/series',
                  label: 'Doble Grado · 2026-2027',
                ),
              ],
              offerDeep: true,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('split-matematicas@2026-2027/series-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('split-doble@2026-2027/series-1')));
    await tester.pumpAndSettle();
    await shoot(tester, 'vinculos-dividir');
  });

  testWidgets('las versiones congeladas', (tester) async {
    late Session session;
    await tester.runAsync(() async {
      session = await openSession();
      final admin = session.admin(repo: 'test/repo')!;
      final head = await session.headOf('test/repo');
      await admin.addFreeze(
        course: 'analisis',
        year: '2025-2026',
        name: 'Inicio curso 2025-26',
        commit: head,
        description: 'Como se repartió el primer día.',
      );
      await session.reloadCatalogue();
      final next = await session.headOf('test/repo');
      await admin.addFreeze(
        course: 'analisis',
        year: '2025-2026',
        name: 'Antes del primer parcial',
        commit: next,
      );
      await session.reloadCatalogue();
    });

    await mount(
      tester,
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFreezes(
                context,
                session,
                session.catalogue.courses.firstWhere(
                  (course) => course.id == 'analisis',
                ),
                '2025-2026',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await shoot(tester, 'congelaciones-lista');

    final menu = find.byType(IconButton).last;
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await shoot(tester, 'congelaciones-menu');
  });

  testWidgets('mirando una versión congelada', (tester) async {
    late Session session;
    await tester.runAsync(() async {
      session = await openSession();
      final admin = session.admin(repo: 'test/repo')!;
      final head = await session.headOf('test/repo');
      // Otro nombre: el repositorio es el mismo para todas las capturas, y
      // dos congelaciones no pueden llamarse igual en un curso.
      await admin.addFreeze(
        course: 'analisis',
        year: '2025-2026',
        name: 'Versión final 2025-26',
        commit: head,
      );
      await session.reloadCatalogue();
      await session.openFreeze(
        session
            .freezesOf('analisis', '2025-2026')
            .firstWhere((item) => item.name == 'Versión final 2025-26'),
        repo: 'test/repo',
      );
    });

    await mount(
      tester,
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: Scaffold(
          body: Column(
            children: [
              FrozenBar(session: session),
              const Expanded(
                child: YearPage(courseId: 'analisis', year: '2025-2026'),
              ),
            ],
          ),
        ),
      ),
    );
    await settleReal(tester);
    await shoot(tester, 'congelaciones-mirando');
  });
}
