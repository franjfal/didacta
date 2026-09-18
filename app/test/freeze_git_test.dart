/// Las congelaciones, contra git de verdad.
///
/// De verdad a propósito, como el resto de lo que toca el clon: un worktree
/// simulado probaría que el Dart es coherente consigo mismo y nada sobre si
/// el árbol se crea de verdad, si el commit está, si el clon principal se
/// queda quieto o si un clon shallow puede recuperar la historia que le
/// falta. Cada prueba levanta un repositorio remoto y un clon en una carpeta
/// temporal y llama al `git` que hay instalado.
///
/// Lo que se fija aquí es lo que hace que congelar sea seguro:
///
/// * **abrir una congelación no toca el clon**: ni HEAD, ni el índice, ni el
///   árbol de trabajo, ni lo que haya sin guardar;
/// * **no se copia el repositorio**: un worktree es una carpeta con los
///   ficheros de ese commit, y git ya tenía el contenido;
/// * **quitar una congelación no borra commits**;
/// * **restaurar no reescribe la historia**: deja un cambio pendiente, como
///   cualquier edición.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/local_clone.dart';

const String unitFile = 'content/analysis/normed/definition/es.tex';
const String yearFile = 'courses/am-i/2026-2027/year.yaml';

void main() {
  late Directory root;
  late String remote;
  late String seed;
  late LocalClone clone;

  /// Los commits de la semilla, del primero al último.
  late List<String> history;

  setUp(() async {
    if (!await LocalClone.gitAvailable()) {
      fail('git no está instalado, así que esta parte no se puede probar');
    }
    root = await Directory.systemTemp.createTemp('didacta-freeze-');
    remote = '${root.path}/remote.git';
    seed = '${root.path}/seed';

    await _git(['init', '--bare', '--initial-branch=main', remote], root.path);
    await Directory(
      '$seed/content/analysis/normed/definition',
    ).create(recursive: true);
    await Directory('$seed/courses/am-i/2026-2027').create(recursive: true);
    _write('$seed/$unitFile', 'La versión de septiembre.\n');
    _write(
      '$seed/$yearFile',
      'course: am-i\nyear: 2026-2027\nlanguage: es\n\n'
          'documents:\n'
          '  - id: tema-1\n'
          '    structure:\n'
          '      - unit: analysis/normed/definition\n',
    );
    await _git(['init', '--initial-branch=main', seed], root.path);
    await _git(['add', '.'], seed);
    await _git(_asSomeone(['commit', '-m', 'Inicio de curso']), seed);
    await _git(['remote', 'add', 'origin', remote], seed);
    await _git(['push', '-u', 'origin', 'main'], seed);
    history = [await _sha(seed)];

    // Un segundo commit: el curso avanza.
    _write('$seed/$unitFile', 'La versión de noviembre.\n');
    _write(
      '$seed/courses/am-i/2026-2027/tema-2.tex',
      '% un tema que antes no estaba\n',
    );
    await _git(['add', '.'], seed);
    await _git(_asSomeone(['commit', '-m', 'Antes del parcial']), seed);
    await _git(['push'], seed);
    history.add(await _sha(seed));

    await _git([
      'clone',
      '--branch',
      'main',
      remote,
      '${root.path}/clone',
    ], root.path);
    clone = LocalClone(directory: '${root.path}/clone');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('el commit de una congelación', () {
    test('HEAD se lee entero, no en corto', () async {
      final head = await clone.head();
      expect(head.length, 40);
      expect(head, history.last);
    });

    test('un commit que está se reconoce', () async {
      expect(await clone.hasCommit(history.first), isTrue);
    });

    test('uno que no está se reconoce igual de bien', () async {
      expect(
        await clone.hasCommit('0123456789abcdef0123456789abcdef01234567'),
        isFalse,
      );
    });
  });

  group('abrir una congelación', () {
    test('da una carpeta con los ficheros de ese commit', () async {
      final tree = await clone.worktreeAt(history.first);
      expect(
        File('${tree.directory}/$unitFile').readAsStringSync(),
        'La versión de septiembre.\n',
      );
    });

    test('y el clon sigue en lo que estaba', () async {
      await clone.worktreeAt(history.first);
      expect(await clone.head(), history.last);
      expect(
        File('${root.path}/clone/$unitFile').readAsStringSync(),
        'La versión de noviembre.\n',
      );
    });

    test('no ensucia el árbol de trabajo', () async {
      await clone.worktreeAt(history.first);
      final status = await clone.status();
      expect(status.dirtyPaths, isEmpty);
      expect(status.branch, 'main');
    });

    test('un cambio sin guardar se queda donde estaba', () async {
      _write('${root.path}/clone/$unitFile', 'lo que estaba escribiendo\n');
      await clone.worktreeAt(history.first);
      expect(
        File('${root.path}/clone/$unitFile').readAsStringSync(),
        'lo que estaba escribiendo\n',
      );
    });

    test('abrirla dos veces reutiliza el mismo árbol', () async {
      final first = await clone.worktreeAt(history.first);
      final second = await clone.worktreeAt(history.first);
      expect(second.directory, first.directory);
      expect((await clone.worktrees()).length, 1);
    });

    test('dos congelaciones distintas son dos árboles', () async {
      await clone.worktreeAt(history.first);
      await clone.worktreeAt(history.last);
      expect((await clone.worktrees()).length, 2);
    });

    test('el árbol vive fuera de lo que git mira', () async {
      final tree = await clone.worktreeAt(history.first);
      expect(tree.directory, contains('/.git/'));
      expect((await clone.status()).dirtyPaths, isEmpty);
    });

    test('mover HEAD no cambia lo que enseña la congelación', () async {
      final tree = await clone.worktreeAt(history.first);
      _write('${root.path}/clone/$unitFile', 'la versión de enero\n');
      await clone.commitFile(
        path: unitFile,
        text: 'la versión de enero\n',
        expectedSha: await _hash(clone, unitFile),
        message: 'Reescribir la definición',
        authorName: 'Javier',
        authorEmail: 'javier@uv.es',
        token: '',
        push: false,
      );
      expect(
        File('${tree.directory}/$unitFile').readAsStringSync(),
        'La versión de septiembre.\n',
      );
    });
  });

  group('quitar una congelación', () {
    test('se lleva su árbol y nada más', () async {
      await clone.worktreeAt(history.first);
      await clone.removeWorktree(history.first);
      expect(await clone.worktrees(), isEmpty);
      expect(await clone.hasCommit(history.first), isTrue);
    });

    test('no borra el commit', () async {
      await clone.worktreeAt(history.first);
      await clone.removeWorktree(history.first);
      final log = await clone.history(unitFile);
      expect(log.map((c) => c.sha), contains(history.first));
    });

    test('no afecta a otra congelación', () async {
      await clone.worktreeAt(history.first);
      final kept = await clone.worktreeAt(history.last);
      await clone.removeWorktree(history.first);
      expect(Directory(kept.directory).existsSync(), isTrue);
    });

    test('quitar una que no se había abierto no es un error', () async {
      await clone.removeWorktree(history.first);
      expect(await clone.worktrees(), isEmpty);
    });

    test('la caché se puede vaciar entera', () async {
      await clone.worktreeAt(history.first);
      await clone.worktreeAt(history.last);
      expect(await clone.clearWorktrees(), 2);
      expect(await clone.worktrees(), isEmpty);
      // Y se vuelve a poder abrir: no había nada que perder ahí.
      final again = await clone.worktreeAt(history.first);
      expect(Directory(again.directory).existsSync(), isTrue);
    });

    test('un árbol borrado a mano no impide volver a abrirlo', () async {
      final tree = await clone.worktreeAt(history.first);
      await Directory(tree.directory).delete(recursive: true);
      final again = await clone.worktreeAt(history.first);
      expect(
        File('${again.directory}/$unitFile').readAsStringSync(),
        'La versión de septiembre.\n',
      );
    });
  });

  group('comparar', () {
    test('dice qué se modificó, qué se añadió y qué se quitó', () async {
      final changes = await clone.changesBetween(
        from: history.first,
        to: history.last,
      );
      final byPath = {for (final change in changes) change.path: change.kind};
      expect(byPath[unitFile], TreeChangeKind.modified);
      expect(byPath['courses/am-i/2026-2027/tema-2.tex'], TreeChangeKind.added);
    });

    test('se puede limitar a un curso', () async {
      final changes = await clone.changesBetween(
        from: history.first,
        to: history.last,
        paths: const ['courses/am-i/2026-2027'],
      );
      expect(changes.map((c) => c.path), ['courses/am-i/2026-2027/tema-2.tex']);
    });

    test('un fichero movido sale como movido', () async {
      await Directory(
        '$seed/content/analysis/normed/def',
      ).create(recursive: true);
      await _git(['mv', unitFile, 'content/analysis/normed/def/es.tex'], seed);
      await _git(['add', '-A'], seed);
      await _git(_asSomeone(['commit', '-m', 'Reorganizar']), seed);
      await _git(['push'], seed);
      await clone.pull(token: '');

      final changes = await clone.changesBetween(
        from: history.last,
        to: await clone.head(),
      );
      final moved = changes.firstWhere(
        (change) => change.kind == TreeChangeKind.renamed,
        orElse: () => const TreeChange(kind: TreeChangeKind.added, path: ''),
      );
      expect(moved.from, unitFile);
      expect(moved.path, 'content/analysis/normed/def/es.tex');
    });

    test('y el diff de un fichero se puede leer', () async {
      final diff = await clone.diffBetween(
        from: history.first,
        to: history.last,
        path: unitFile,
      );
      expect(diff.added, 1);
      expect(diff.removed, 1);
      expect(
        diff.hunks.single.lines.map((line) => line.text),
        contains('La versión de noviembre.'),
      );
    });

    test('las rutas de un commit se pueden enumerar', () async {
      final paths = await clone.pathsAt(
        sha: history.first,
        under: 'courses/am-i/2026-2027',
      );
      expect(paths, [yearFile]);
    });
  });

  group('restaurar', () {
    test('dice qué va a cambiar antes de tocar nada', () async {
      final preview = await clone.previewRestore(
        sha: history.first,
        paths: const ['content'],
      );
      expect(preview.map((c) => c.path), [unitFile]);
      expect(
        File('${root.path}/clone/$unitFile').readAsStringSync(),
        'La versión de noviembre.\n',
      );
    });

    test('devuelve el contenido de aquel commit', () async {
      await clone.restoreFrom(sha: history.first, paths: const ['content']);
      expect(
        File('${root.path}/clone/$unitFile').readAsStringSync(),
        'La versión de septiembre.\n',
      );
    });

    test(
      'lo deja como un cambio pendiente, no como historia reescrita',
      () async {
        final before = await clone.head();
        await clone.restoreFrom(sha: history.first, paths: const ['content']);
        expect(await clone.head(), before);
        expect((await clone.status()).dirtyPaths, contains(unitFile));
      },
    );

    test('quita lo que en aquel commit no existía', () async {
      await clone.restoreFrom(
        sha: history.first,
        paths: const ['courses/am-i/2026-2027'],
      );
      expect(
        File(
          '${root.path}/clone/courses/am-i/2026-2027/tema-2.tex',
        ).existsSync(),
        isFalse,
      );
    });

    test('no toca lo que queda fuera de las rutas pedidas', () async {
      await clone.restoreFrom(
        sha: history.first,
        paths: const ['courses/am-i/2026-2027'],
      );
      expect(
        File('${root.path}/clone/$unitFile').readAsStringSync(),
        'La versión de noviembre.\n',
      );
    });

    test('ningún commit se pierde por restaurar', () async {
      await clone.restoreFrom(sha: history.first, paths: const ['content']);
      final log = await clone.history(unitFile);
      expect(log.map((c) => c.sha), containsAll(history));
    });
  });

  group('un clon shallow', () {
    late LocalClone shallow;

    setUp(() async {
      // `file://` y no la ruta a secas: git ignora `--depth` en un clon
      // local, así que sin esto el «clon shallow» no sería shallow y la
      // prueba pasaría sin probar nada.
      await _git([
        'clone',
        '--depth=1',
        '--branch',
        'main',
        'file://$remote',
        '${root.path}/shallow',
      ], root.path);
      shallow = LocalClone(directory: '${root.path}/shallow');
    });

    test('se reconoce como tal', () async {
      expect(await shallow.isShallow(), isTrue);
      expect(await clone.isShallow(), isFalse);
    });

    test('no tiene el commit congelado', () async {
      expect(await shallow.hasCommit(history.first), isFalse);
    });

    test('lo recupera sin traerse todo por delante', () async {
      final steps = <FetchDepth>[];
      await shallow.fetchCommit(history.first, token: '', onStep: steps.add);
      expect(await shallow.hasCommit(history.first), isTrue);
      // Lo primero que se intenta es lo barato: el commit y nada más.
      expect(steps.first, FetchDepth.justTheCommit);
    });

    test('y después se abre como cualquier otra', () async {
      await shallow.fetchCommit(history.first, token: '');
      final tree = await shallow.worktreeAt(history.first);
      expect(
        File('${tree.directory}/$unitFile').readAsStringSync(),
        'La versión de septiembre.\n',
      );
    });

    test('pedir uno que no existe en ninguna parte se dice claro', () async {
      await expectLater(
        shallow.fetchCommit(
          '0123456789abcdef0123456789abcdef01234567',
          token: '',
        ),
        throwsA(isA<CloneException>()),
      );
    });

    test('un commit que ya está no se vuelve a pedir', () async {
      final steps = <FetchDepth>[];
      await shallow.fetchCommit(history.last, token: '', onStep: steps.add);
      expect(steps, isEmpty);
    });
  });
}

void _write(String path, String text) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(text);

Future<String> _sha(String directory) async {
  final result = await Process.run('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: directory);
  return (result.stdout as String).trim();
}

Future<String> _hash(LocalClone clone, String path) async =>
    (await clone.readFile(path)).sha;

Future<void> _git(List<String> arguments, String directory) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
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

List<String> _asSomeone(List<String> arguments) => [
  '-c',
  'user.name=Semilla',
  '-c',
  'user.email=semilla@example.com',
  ...arguments,
];
