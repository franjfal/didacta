/// Abrir una versión congelada de un repositorio de contenido de verdad.
///
/// Con git de verdad y con el motor de verdad, porque lo que se prueba aquí
/// es justamente la juntura: que el árbol de la congelación es un repositorio
/// de contenido completo, que su `generated/` es el de aquel commit, y que el
/// catálogo que sale de él describe el material **de entonces** aunque el de
/// ahora diga otra cosa.
///
/// Es la prueba que sostiene la frase que repite toda la interfaz: una
/// congelación no copia nada. Si eso fuera falso, se vería aquí.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/frozen.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/course_diff.dart';

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
  late LocalClone clone;
  late Compiler engine;
  late String enginePath;
  late String first;
  late String second;

  Future<void> git(List<String> arguments, [String? where]) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: where ?? work,
      environment: const {
        'GIT_AUTHOR_NAME': 'Semilla',
        'GIT_AUTHOR_EMAIL': 'semilla@example.com',
        'GIT_COMMITTER_NAME': 'Semilla',
        'GIT_COMMITTER_EMAIL': 'semilla@example.com',
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
    }
  }

  void write(String relative, String text) => File('$work/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() async {
    final found = engineRoot();
    if (found == null) {
      fail('esta prueba corre dentro del árbol de Didacta, y el motor no está');
    }
    enginePath = found;
    if (!await LocalClone.gitAvailable()) {
      fail('git no está instalado, así que esta parte no se puede probar');
    }

    root = await Directory.systemTemp.createTemp('didacta-frozen-');
    work = '${root.path}/db';
    Directory(work).createSync(recursive: true);

    write('didacta.yaml', 'languages: [es]\ndefault_language: es\n');
    write('courses/am-i/course.yaml', 'id: am-i\ntitle:\n  es: AM I\n');
    for (final name in ['series', 'limites']) {
      write(
        'content/analisis/$name/unit.yaml',
        'kind: theory\ntitle:\n  es: $name\n',
      );
      write('content/analisis/$name/es.tex', 'el texto de $name\n');
    }
    write(
      'courses/am-i/2026-2027/year.yaml',
      'course: am-i\nyear: 2026-2027\nlanguage: es\n\n'
          'documents:\n'
          '  - id: tema-1\n'
          '    kind: theory\n'
          '    title:\n'
          '      es: Tema 1\n'
          '    structure:\n'
          '      - unit: analisis/series\n',
    );
    write(
      'courses/am-i/2026-2027/tema-1.tex',
      '\\input{didacta-bootstrap}\n\\usepackage{didacta}\n'
          '\\begin{document}\n\\DidactaUnit{analisis/series}\n\\end{document}\n',
    );

    engine = Compiler(enginePath: enginePath, repositoryPath: work);
    await engine.run(const ['index']);

    await git(['init', '--initial-branch=main']);
    await git(['add', '.']);
    await git([
      '-c',
      'user.name=Semilla',
      '-c',
      'user.email=semilla@example.com',
      'commit',
      '-m',
      'Inicio de curso',
    ]);
    first = (await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: work)).stdout.toString().trim();

    // El curso avanza: otra lección, otro tema, otro texto.
    write('content/analisis/series/es.tex', 'el texto de series, corregido\n');
    write(
      'courses/am-i/2026-2027/year.yaml',
      'course: am-i\nyear: 2026-2027\nlanguage: es\n\n'
          'documents:\n'
          '  - id: tema-1\n'
          '    kind: theory\n'
          '    title:\n'
          '      es: Tema 1, revisado\n'
          '    structure:\n'
          '      - unit: analisis/series\n'
          '      - unit: analisis/limites\n'
          '\n'
          '  - id: tema-2\n'
          '    kind: handout\n'
          '    title:\n'
          '      es: Tema 2\n'
          '    structure:\n'
          '      - unit: analisis/limites\n',
    );
    write(
      'courses/am-i/2026-2027/tema-2.tex',
      '\\input{didacta-bootstrap}\n\\usepackage{didacta}\n'
          '\\begin{document}\n\\DidactaUnit{analisis/limites}\n\\end{document}\n',
    );
    await engine.run(const ['index']);
    await git(['add', '-A']);
    await git([
      '-c',
      'user.name=Semilla',
      '-c',
      'user.email=semilla@example.com',
      'commit',
      '-m',
      'Antes del parcial',
    ]);
    second = (await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: work)).stdout.toString().trim();

    clone = LocalClone(directory: work);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Frozen service() =>
      Frozen(clone: clone, repo: 'x/db', compiler: engine, token: '');

  Freeze freezeAt(String commit, {String name = 'Inicio curso 2026-27'}) =>
      Freeze(
        id: 'f-000000000001',
        name: name,
        commit: commit,
        course: 'am-i',
        year: '2026-2027',
        repo: 'x/db',
      );

  group('abrir', () {
    test('da el catálogo de aquel commit', () async {
      final view = await service().open(freezeAt(first));
      final course = view.catalogue.courses.single;
      final year = course.years['2026-2027']!;
      expect(year.documents.map((d) => d.id), ['tema-1']);
      expect(year.documents.single.title('es'), 'Tema 1');
      expect(year.documents.single.unitRefs, ['analisis/series']);
    });

    test('y el de ahora sigue diciendo otra cosa', () async {
      await service().open(freezeAt(first));
      final now = await service().open(freezeAt(second, name: 'Ahora'));
      expect(
        now.catalogue.courses.single.years['2026-2027']!.documents.map(
          (d) => d.id,
        ),
        ['tema-1', 'tema-2'],
      );
    });

    test('no lo reconstruye: el índice ya estaba en el commit', () async {
      final view = await service().open(freezeAt(first));
      expect(view.rebuilt, isFalse);
    });

    test('no copia el repositorio: es un árbol de git', () async {
      final view = await service().open(freezeAt(first));
      // Un worktree tiene un `.git` que es un fichero, no una carpeta: apunta
      // al repositorio de al lado en vez de traerse otra copia de la historia.
      expect(File('${view.directory}/.git').existsSync(), isTrue);
      expect(Directory('${view.directory}/.git').existsSync(), isFalse);
    });

    test('el texto de una lección es el de entonces', () async {
      final view = await service().open(freezeAt(first));
      expect(
        File(
          '${view.directory}/content/analisis/series/es.tex',
        ).readAsStringSync(),
        'el texto de series\n',
      );
      expect(
        File('$work/content/analisis/series/es.tex').readAsStringSync(),
        'el texto de series, corregido\n',
      );
    });

    test('abrirla no ensucia el repositorio', () async {
      await service().open(freezeAt(first));
      expect((await clone.status()).dirtyPaths, isEmpty);
    });

    test('un commit sin índice se reconstruye y se dice', () async {
      // Un repositorio de antes de que se versionara `generated/`.
      await git(['rm', '-r', '--quiet', 'generated']);
      await git([
        '-c',
        'user.name=Semilla',
        '-c',
        'user.email=semilla@example.com',
        'commit',
        '-m',
        'Sin índice',
      ]);
      final without = (await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: work)).stdout.toString().trim();
      final view = await service().open(freezeAt(without, name: 'Sin índice'));
      expect(view.rebuilt, isTrue);
      expect(view.catalogue.courses, hasLength(1));
    });
  });

  group('cerrar', () {
    test('quita el árbol', () async {
      final view = await service().open(freezeAt(first));
      await service().close(freezeAt(first));
      expect(Directory(view.directory).existsSync(), isFalse);
    });

    test('pero no si otra congelación usa el mismo commit', () async {
      final view = await service().open(freezeAt(first));
      await service().close(
        freezeAt(first),
        others: [
          freezeAt(first),
          Freeze(
            id: 'f-000000000002',
            name: 'Otra del mismo día',
            commit: first,
          ),
        ],
      );
      expect(Directory(view.directory).existsSync(), isTrue);
    });

    test('vaciar la caché no pierde nada', () async {
      await service().open(freezeAt(first));
      expect(await service().clearCache(), 1);
      final again = await service().open(freezeAt(first));
      expect(again.catalogue.courses, hasLength(1));
    });
  });

  group('comparar', () {
    test('dice qué temas entraron y cuáles cambiaron', () async {
      final diff = await service().compare(
        from: first,
        to: 'HEAD',
        course: 'am-i',
        year: '2026-2027',
      );
      final added = diff.documents
          .where((d) => d.kind == TreeChangeKind.added)
          .map((d) => d.id);
      expect(added, ['tema-2']);
      final changed = diff.documents
          .where((d) => d.kind == TreeChangeKind.modified)
          .map((d) => d.id);
      expect(changed, ['tema-1']);
    });

    test('y qué lecciones se tocaron, con su idioma', () async {
      final diff = await service().compare(
        from: first,
        to: 'HEAD',
        course: 'am-i',
        year: '2026-2027',
      );
      final lessons = diff.of(ChangedThing.lesson);
      expect(lessons.map((l) => l.title), contains('series'));
      expect(lessons.firstWhere((l) => l.title == 'series').language, 'es');
    });

    test('lo derivado no ensucia la lista', () async {
      final diff = await service().compare(
        from: first,
        to: 'HEAD',
        course: 'am-i',
        year: '2026-2027',
      );
      expect(
        diff.changes.where((c) => c.path.startsWith('generated/')),
        isEmpty,
      );
    });

    test('dos congelaciones se comparan igual que una con HEAD', () async {
      final diff = await service().compare(
        from: first,
        to: second,
        course: 'am-i',
        year: '2026-2027',
      );
      expect(diff.isEmpty, isFalse);
    });

    test('el diff de un fichero se puede leer', () async {
      final diff = await service().diffOf(
        from: first,
        to: 'HEAD',
        path: 'content/analisis/series/es.tex',
      );
      expect(diff.added, 1);
      expect(diff.removed, 1);
    });
  });

  group('restaurar', () {
    test('dice qué cambiaría antes de tocar nada', () async {
      final preview = await service().previewRestore(
        freeze: freezeAt(first),
        paths: const ['content/analisis/series'],
      );
      expect(preview.single.path, 'content/analisis/series/es.tex');
      expect(
        File('$work/content/analisis/series/es.tex').readAsStringSync(),
        'el texto de series, corregido\n',
      );
    });

    test('una lección vuelve a como estaba', () async {
      await service().restore(
        freeze: freezeAt(first),
        paths: const ['content/analisis/series'],
      );
      expect(
        File('$work/content/analisis/series/es.tex').readAsStringSync(),
        'el texto de series\n',
      );
    });

    test('un tema vuelve, y lo que no estaba entonces se va', () async {
      await service().restore(
        freeze: freezeAt(first),
        paths: const ['courses/am-i/2026-2027'],
      );
      expect(
        File('$work/courses/am-i/2026-2027/tema-2.tex').existsSync(),
        isFalse,
      );
      expect(
        File('$work/courses/am-i/2026-2027/year.yaml').readAsStringSync(),
        contains('es: Tema 1\n'),
      );
    });

    test('no reescribe la historia: HEAD no se mueve', () async {
      await service().restore(
        freeze: freezeAt(first),
        paths: const ['content'],
      );
      expect(await clone.head(), second);
    });

    test('ni borra ningún commit', () async {
      await service().restore(
        freeze: freezeAt(first),
        paths: const ['content'],
      );
      expect(await clone.hasCommit(first), isTrue);
      expect(await clone.hasCommit(second), isTrue);
    });

    test('lo restaurado queda pendiente de confirmar', () async {
      await service().restore(
        freeze: freezeAt(first),
        paths: const ['content/analisis/series'],
      );
      expect(
        (await clone.status()).dirtyPaths,
        contains('content/analisis/series/es.tex'),
      );
    });
  });

  group('la pasarela de una congelación', () {
    test('lee del árbol de aquel commit', () async {
      final view = await service().open(freezeAt(first));
      final gateway = FrozenGateway(view: view);
      final file = await gateway.read('content/analisis/series/es.tex');
      expect(file.text, 'el texto de series\n');
    });

    test('y se niega a escribir, diciendo por qué', () async {
      final view = await service().open(freezeAt(first));
      final gateway = FrozenGateway(view: view);
      expect(gateway.canWrite, isFalse);
      await expectLater(
        gateway.save(
          path: 'content/analisis/series/es.tex',
          text: 'otra cosa',
          sha: 'x',
          message: 'no',
        ),
        throwsA(
          isA<Object>().having(
            (error) => '$error',
            'el porqué',
            allOf(contains('congelada'), contains('versión actual')),
          ),
        ),
      );
    });
  });
}
