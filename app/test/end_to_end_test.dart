/// El recorrido completo, con la aplicación de verdad.
///
/// Una sesión real --no la de mentira de los tests de pantalla-- apuntando a
/// un repositorio de contenido real, con git real y el motor real, y la
/// pantalla de un curso montada encima. Lo que se ejercita aquí es **la pila
/// entera**: el botón llama a `CourseAdmin`, que lanza el motor, que escribe
/// los ficheros, que se reindexan, que vuelven al catálogo, que la pantalla
/// vuelve a pintar.
///
/// Es el único sitio donde eso se comprueba junto. Cada capa tiene sus
/// pruebas --`test_reuse.py` para el modelo, `freeze_git_test.dart` para git,
/// `reuse_ui_test.dart` para los diálogos-- y ninguna ve el fallo que sale
/// cuando dos capas se entienden mal.
///
/// El escenario es el del encargo: Análisis con dos cursos, Matemáticas con
/// uno, un tema compartido entre los tres, editado desde cada sitio, dividido
/// después, y congelado antes y después de dividir.
///
/// **Con el reloj de verdad donde hace falta.** `testWidgets` corre con uno
/// falso, y esperar ahí dentro a git o al motor no vuelve nunca; por eso todo
/// lo que lanza un proceso va dentro de `runAsync`, que es exactamente para
/// esto.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/compiler_io.dart' show findTool;
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

/// El repositorio del motor, si esto corre dentro del árbol de Didacta.
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
  late Directory root;
  late String work;
  late String engine;
  late String remote;

  void write(String relative, String text) => File('$work/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  Future<String> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: work,
      environment: const {
        'GIT_AUTHOR_NAME': 'Javier',
        'GIT_AUTHOR_EMAIL': 'javier@uv.es',
        'GIT_COMMITTER_NAME': 'Javier',
        'GIT_COMMITTER_EMAIL': 'javier@uv.es',
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  Future<String> didacta(List<String> arguments) async {
    final result = await Process.run(
      '$engine/cli/didacta',
      arguments,
      workingDirectory: work,
      environment: const {'NO_COLOR': '1', 'TERM': 'dumb'},
    );
    if (result.exitCode != 0) {
      throw StateError(
        'didacta ${arguments.join(' ')}:\n${result.stdout}\n${result.stderr}',
      );
    }
    return (result.stdout as String).trim();
  }

  setUp(() async {
    final found = engineRoot();
    if (found == null) {
      fail('esta prueba corre dentro del árbol de Didacta');
    }
    engine = found;
    if (!await LocalClone.gitAvailable()) {
      fail('git no está instalado, así que esta parte no se puede probar');
    }

    root = await Directory.systemTemp.createTemp('didacta-e2e-');
    work = '${root.path}/db';
    Directory(work).createSync(recursive: true);

    write(
      'didacta.yaml',
      'name: didacta_db\nlanguages: [es, va]\ndefault_language: es\n',
    );
    write(
      'courses/analisis/course.yaml',
      'id: analisis\ntitle:\n  es: Análisis Matemático\n',
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
          '      es: Series\n'
          '      # TODO: va\n'
          '    structure:\n'
          '      - unit: analisis/series/convergencia\n'
          '      # - unit: analisis/series/criterios\n',
    );
    write(
      'courses/analisis/2025-2026/themes.yaml',
      'themes:\n  - id: t-series\n    title:\n      es: Series\n',
    );
    write(
      'courses/analisis/2025-2026/series.tex',
      '\\input{didacta-bootstrap}\n\\usepackage{didacta}\n'
          '\\DidactaDocument{Series 2025-2026}\n'
          '\\begin{document}\n'
          '\\DidactaUnit{analisis/series/convergencia}\n'
          '\\end{document}\n',
    );
    for (final pair in const [
      ('analisis', '2026-2027'),
      ('matematicas', '2026-2027'),
    ]) {
      write(
        'courses/${pair.$1}/${pair.$2}/year.yaml',
        'course: ${pair.$1}\nyear: ${pair.$2}\nlanguage: es\n\ndocuments:\n',
      );
    }

    // Un remoto de verdad, con el nombre que la sesión espera: la aplicación
    // comprueba que el clon es de `test/repo` antes de abrirlo, y un clon sin
    // remoto no lo es. Además deja `push` y `pull` a mano.
    remote = '${root.path}/test/repo.git';
    Directory(remote).createSync(recursive: true);
    await Process.run('git', [
      'init',
      '--bare',
      '--initial-branch=main',
      remote,
    ], workingDirectory: root.path);

    await didacta(const ['index']);
    await git(['init', '--initial-branch=main']);
    await git(['add', '.']);
    await git(['commit', '-m', 'El material, para empezar']);
    await git(['remote', 'add', 'origin', remote]);
    await git(['push', '-u', 'origin', 'main']);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Una sesión real: catálogo del clon, clon de verdad, motor de verdad.
  Future<Session> openSession() async {
    final preferences = MemoryPreferences()..engine = engine;
    final session = Session(
      catalogueSource: CatalogueSource.inClone(work, repo: 'test/repo')!,
      tokenStore: StubStore(),
      preferences: preferences,
    );
    await session.useClonesForTest([work]);
    await session.findEngine();
    await session.primeForTest(
      await CatalogueSource.inClone(work, repo: 'test/repo')!.load(),
    );
    await session.setCloneAuthor(name: 'Javier', email: 'javier@uv.es');
    return session;
  }

  /// Deja que corra lo que de verdad va al disco, y después pinta.
  ///
  /// `pumpAndSettle` no vale para lo primero: el reloj de `testWidgets` es
  /// falso y no hace avanzar una lectura de fichero ni un proceso, así que
  /// esperar a que «se calme» una pantalla que está leyendo el `year.yaml`
  /// del disco se queda esperando para siempre. `runAsync` corre con el
  /// reloj de verdad, y el `pump` de después pinta lo que haya llegado.
  Future<void> settleReal(WidgetTester tester) async {
    for (var round = 0; round < 6; round += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Course courseOf(Session session, String id) =>
      session.catalogue.courses.firstWhere((course) => course.id == id);

  Document documentOf(Session session, String course, String year, String id) =>
      courseOf(
        session,
        course,
      ).years[year]!.documents.firstWhere((document) => document.id == id);

  test(
    'un tema compartido entre dos asignaturas, por la pila entera',
    () async {
      // Sin TeX no hay pila entera que probar: `CourseAdmin` no arranca sin
      // una distribución, y lo dice. En un runner de CI no hay ninguna --son
      // varios gigas-- así que allí esto se salta en lugar de fallar, igual
      // que las pruebas del compilador contra el motor real. En la máquina de
      // quien desarrolla, que sí la tiene, corre entera.
      if (await findTool('latexmk') == null) {
        markTestSkipped('sin una distribución de TeX no arranca CourseAdmin');
        return;
      }
      final session = await openSession();
      final admin = session.admin(repo: 'test/repo')!;
      final ready = await admin.status();
      expect(ready.ready, isTrue, reason: '${ready.problem}');

      // 1. El mismo tema, también en el curso siguiente y en otra asignatura.
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

      final content = documentOf(
        session,
        'analisis',
        '2025-2026',
        'series',
      ).content;
      expect(content, isNotEmpty);
      final shared = session.catalogue.sharedById(content)!;
      expect(shared.placements.map((place) => place.key), [
        'analisis@2025-2026/series',
        'analisis@2026-2027/series',
        'matematicas@2026-2027/series',
      ]);

      // 2. Editarlo desde una ubicación se ve desde las demás. Y se edita como
      //    se edita todo: por la pasarela del repositorio.
      final gateway = session.gatewayFor('test/repo');
      final path = 'shared/documents/$content.yaml';
      final file = await gateway.read(path);
      await gateway.save(
        path: path,
        text: file.text.replaceAll('es: Series', 'es: Series numéricas'),
        sha: file.sha,
        message: 'Series: afinar el título',
      );
      await session.reloadCatalogue();

      for (final pair in const [
        ('analisis', '2025-2026'),
        ('analisis', '2026-2027'),
        ('matematicas', '2026-2027'),
      ]) {
        expect(
          documentOf(session, pair.$1, pair.$2, 'series').title('es'),
          'Series numéricas',
          reason: 'editar desde un sitio tiene que verse desde ${pair.$1}',
        );
      }

      // 3. Congelar antes de dividir.
      final before = await session.headOf('test/repo');
      await admin.addFreeze(
        course: 'analisis',
        year: '2025-2026',
        name: 'Antes de dividir',
        commit: before,
      );
      await session.reloadCatalogue();
      expect(session.freezesOf('analisis', '2025-2026').map((f) => f.name), [
        'Antes de dividir',
      ]);

      // 4. Dividir: Análisis por un lado, Matemáticas por otro.
      await admin.splitContent(
        content: content,
        groups: const [
          ['matematicas@2026-2027/series'],
        ],
        paths: const [
          'courses/analisis/2025-2026',
          'courses/analisis/2026-2027',
          'courses/matematicas/2026-2027',
        ],
        message: 'Separar Series de Matemáticas',
      );
      await session.reloadCatalogue();

      expect(
        documentOf(session, 'analisis', '2025-2026', 'series').content,
        content,
      );
      expect(
        documentOf(session, 'analisis', '2026-2027', 'series').content,
        content,
      );
      // Un grupo de uno no es un grupo: su tema vuelve a estar escrito en su
      // curso.
      expect(
        documentOf(session, 'matematicas', '2026-2027', 'series').content,
        isEmpty,
      );

      // 5. Cada rama va por su lado.
      final again = await gateway.read(path);
      await gateway.save(
        path: path,
        text: again.text.replaceAll(
          'es: Series numéricas',
          'es: Series, solo en Análisis',
        ),
        sha: again.sha,
        message: 'Series: retocar el título en Análisis',
      );
      await session.reloadCatalogue();
      expect(
        documentOf(session, 'analisis', '2026-2027', 'series').title('es'),
        'Series, solo en Análisis',
      );
      expect(
        documentOf(session, 'matematicas', '2026-2027', 'series').title('es'),
        'Series numéricas',
      );

      // 6. La congelación de antes sigue enseñando lo de antes.
      final frozen = session.frozenIn('test/repo')!;
      final view = await frozen.open(
        session.freezesOf('analisis', '2025-2026').first,
      );
      final old = view.catalogue;
      final oldShared = old.sharedById(content);
      expect(oldShared, isNotNull);
      expect(oldShared!.placements, hasLength(3));
      expect(
        old.courses
            .firstWhere((course) => course.id == 'matematicas')
            .years['2026-2027']!
            .documents
            .single
            .content,
        content,
        reason: 'en aquel commit los tres estaban vinculados',
      );

      // Y comparar dice lo que cambió, en términos de Didacta.
      final diff = await frozen.compare(
        from: view.freeze.commit,
        to: 'HEAD',
        course: 'matematicas',
        year: '2026-2027',
      );
      expect(diff.isEmpty, isFalse);
      expect(
        diff.documents.map((d) => d.id),
        contains('series'),
        reason: 'el tema de Matemáticas dejó de estar vinculado',
      );

      // 7. Y el repositorio sigue leyéndose limpio.
      final check = await Process.run(
        '$engine/cli/didacta',
        const ['check'],
        workingDirectory: work,
        environment: const {'NO_COLOR': '1'},
      );
      expect(check.exitCode, 0, reason: '${check.stdout}\n${check.stderr}');
    },
  );

  test('el editor lee y reescribe el fichero que escribe el motor', () async {
    // La juntura más fácil de romper de todo esto: el tema compartido lo
    // escribe el motor, en Python, y quien lo edita es el editor de
    // composición, en Dart. Si la sangría o la forma no coinciden, el editor
    // se queda en blanco -- que es exactamente lo que pasó.
    final session = await openSession();
    final admin = session.admin(repo: 'test/repo')!;
    await admin.linkDocument(
      fromCourse: 'analisis',
      fromYear: '2025-2026',
      document: 'series',
      toCourse: 'analisis',
      toYear: '2026-2027',
    );
    await session.reloadCatalogue();

    final document = documentOf(session, 'analisis', '2026-2027', 'series');
    expect(document.isLinked, isTrue);

    final path = 'shared/documents/${document.content}.yaml';
    final file = await session.gatewayFor('test/repo').read(path);
    final block = CompositionFile.shared(
      file.text,
    ).blockFor(CompositionFile.sharedDocument);

    expect(block, isNotNull, reason: 'el editor no encuentra la composición');
    // Las dos, y la comentada **como comentada**: es material que existe y
    // que este año no se da, y perderlo al mudar el tema al fichero
    // compartido habría sido el peor resultado posible.
    expect(
      [for (final entry in block!.entries) (entry.value, entry.enabled)],
      [
        ('analisis/series/convergencia', true),
        ('analisis/series/criterios', false),
      ],
    );

    // Y reescribirla deja un fichero que el motor vuelve a leer igual: la
    // ida y la vuelta, que es lo único que prueba que las dos mitades se
    // entienden.
    final composition = CompositionFile.shared(file.text)
      ..setStructure(CompositionFile.sharedDocument, [
        ...block.entries,
        const StructureEntry(
          kind: EntryKind.unit,
          value: 'analisis/series/potencias',
        ),
      ]);
    await session
        .gatewayFor('test/repo')
        .save(
          path: path,
          text: composition.text,
          sha: file.sha,
          message: 'Series: una lección más',
        );
    await session.reloadCatalogue();

    for (final year in const ['2025-2026', '2026-2027']) {
      expect(
        documentOf(session, 'analisis', year, 'series').unitRefs,
        ['analisis/series/convergencia', 'analisis/series/potencias'],
        reason: 'lo editado tiene que verse desde los dos cursos',
      );
    }
  });

  testWidgets('la pantalla de un curso enseña el vínculo y lo sabe romper', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Session session;
    // Todo lo que lanza un proceso, con el reloj de verdad: dentro del de
    // `testWidgets` un `Process.run` no vuelve nunca.
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

    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(
            body: YearPage(courseId: 'analisis', year: '2025-2026'),
          ),
        ),
      ),
    );
    await settleReal(tester);

    // El tema está, y el indicador dice en cuántos sitios se da.
    expect(find.text('Series'), findsWidgets);
    expect(find.text('3'), findsWidgets);

    // Y el menú ofrece las cuatro operaciones por separado.
    await tester.tap(find.byKey(const Key('reuse-menu-series')));
    await tester.pumpAndSettle();
    expect(find.text('Mover a…'), findsOneWidget);
    expect(find.text('Añadir vinculado a…'), findsOneWidget);
    expect(find.text('Duplicar en…'), findsOneWidget);
    expect(find.text('Ver ubicaciones vinculadas (3)'), findsOneWidget);
    expect(find.text('Gestionar vinculación…'), findsOneWidget);

    // Ver dónde se da lo dice con nombres, no con ids.
    await tester.tap(find.byKey(const Key('document-places-series')));
    await tester.pumpAndSettle();
    expect(find.text('Se utiliza en 3 ubicaciones:'), findsOneWidget);
    expect(find.text('Matemáticas · 2026-2027 · series'), findsOneWidget);
  });

  testWidgets('mirando una congelación no se puede escribir', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Session session;
    await tester.runAsync(() async {
      session = await openSession();
      final admin = session.admin(repo: 'test/repo')!;
      final head = await session.headOf('test/repo');
      await admin.addFreeze(
        course: 'analisis',
        year: '2025-2026',
        name: 'Inicio de curso',
        commit: head,
      );
      await session.reloadCatalogue();
      await session.openFreeze(
        session.freezesOf('analisis', '2025-2026').single,
        repo: 'test/repo',
      );
    });

    expect(session.isFrozen, isTrue);
    expect(session.canWriteIn('test/repo'), isFalse);

    // Y la pasarela dice por qué en lugar de fallar al guardar.
    await expectLater(
      session
          .gatewayFor('test/repo')
          .save(
            path: 'content/analisis/series/convergencia/es.tex',
            text: 'otra cosa',
            sha: 'x',
            message: 'no',
          ),
      throwsA(
        isA<ContentException>().having(
          (error) => error.message,
          'el porqué',
          allOf(contains('congelada'), contains('versión actual')),
        ),
      ),
    );

    // El curso se sigue viendo: lo que cambia es de qué momento.
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(
            body: YearPage(courseId: 'analisis', year: '2025-2026'),
          ),
        ),
      ),
    );
    await settleReal(tester);
    expect(find.text('Series'), findsWidgets);
    // Sin el menú de reutilizar, y con el de restaurar en su sitio.
    expect(find.byKey(const Key('reuse-menu-series')), findsNothing);
    expect(find.byKey(const Key('restore-document-series')), findsOneWidget);
  });
}
