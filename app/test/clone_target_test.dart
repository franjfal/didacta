/// Qué hay donde iría un clon, antes de tocarlo.
///
/// Esto existe porque clonar escribe en el disco de alguien. En una máquina
/// compartida la carpeta de destino puede tener ya el clon de otra persona,
/// con trabajo suyo sin enviar; o puede tener cualquier otra cosa. Escribir
/// encima y explicarlo después no es una opción, así que se mira antes y se
/// pregunta lo que se puede preguntar.
///
/// Contra git de verdad: lo que se prueba es precisamente el trato con el
/// disco y con un remoto, y un doble diría que sí a todo.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/local_clone.dart';

Future<void> git(List<String> args, String where) async {
  final result = await Process.run('git', args, workingDirectory: where);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('didacta-target-');
  });
  tearDown(() => root.delete(recursive: true));

  /// Un remoto desnudo y un clon suyo, como los de verdad.
  Future<String> cloneOf(String owner, String name) async {
    final remote = '${root.path}/$owner/$name.git';
    await Directory(remote).create(recursive: true);
    await git(['init', '--bare', '--initial-branch=main', remote], root.path);

    final seed = '${root.path}/seed';
    await Directory(seed).create(recursive: true);
    File('$seed/didacta.yaml').writeAsStringSync('name: $name\n');
    await git(['init', '--initial-branch=main', '.'], seed);
    await git(['add', '.'], seed);
    await git([
      '-c',
      'user.email=a@b',
      '-c',
      'user.name=A',
      'commit',
      '-m',
      'x',
    ], seed);
    await git(['remote', 'add', 'origin', remote], seed);
    await git(['push', '-u', 'origin', 'main'], seed);

    final clone = '${root.path}/clon';
    await git(['clone', remote, clone], root.path);
    return clone;
  }

  test('una carpeta que no existe está libre', () async {
    expect(
      await LocalClone.inspect(
        directory: '${root.path}/no-existe',
        owner: 'x',
        repo: 'uno',
      ),
      CloneTarget.free,
    );
  });

  test('una carpeta vacía está libre', () async {
    final empty = '${root.path}/vacia';
    await Directory(empty).create(recursive: true);
    expect(
      await LocalClone.inspect(directory: empty, owner: 'x', repo: 'uno'),
      CloneTarget.free,
    );
  });

  test(
    'un clon del mismo repositorio se reconoce, y no se vuelve a clonar',
    () async {
      // El caso que motiva todo esto: la carpeta ya la clonó alguien. Lo que
      // hay dentro puede ser trabajo sin enviar, así que no se pisa.
      final clone = await cloneOf('x', 'uno');
      expect(
        await LocalClone.inspect(directory: clone, owner: 'x', repo: 'uno'),
        CloneTarget.alreadyCloned,
      );
    },
  );

  test('un clon de otro repositorio cuenta como ocupada', () async {
    final clone = await cloneOf('x', 'uno');
    expect(
      await LocalClone.inspect(directory: clone, owner: 'x', repo: 'otro'),
      CloneTarget.occupied,
    );
  });

  test('una carpeta con cosas que no es un clon cuenta como ocupada', () async {
    // Lo más peligroso: aquí hay ficheros de alguien y ni siquiera hay git
    // que los tenga guardados.
    final busy = '${root.path}/mis-cosas';
    await Directory(busy).create(recursive: true);
    File('$busy/apuntes.tex').writeAsStringSync('Trabajo de alguien.\n');
    expect(
      await LocalClone.inspect(directory: busy, owner: 'x', repo: 'uno'),
      CloneTarget.occupied,
    );
  });

  test('mirar no toca nada', () async {
    // Un `inspect` que borrara o moviera algo sería justo lo contrario de
    // para lo que existe.
    final busy = '${root.path}/mis-cosas';
    await Directory(busy).create(recursive: true);
    File('$busy/apuntes.tex').writeAsStringSync('Trabajo de alguien.\n');

    await LocalClone.inspect(directory: busy, owner: 'x', repo: 'uno');

    expect(
      File('$busy/apuntes.tex').readAsStringSync(),
      'Trabajo de alguien.\n',
    );
  });

  test(
    'clonar sobre una carpeta ocupada se niega y la deja como estaba',
    () async {
      final busy = '${root.path}/mis-cosas';
      await Directory(busy).create(recursive: true);
      File('$busy/apuntes.tex').writeAsStringSync('Trabajo de alguien.\n');

      await expectLater(
        LocalClone.create(
          directory: busy,
          owner: 'x',
          repo: 'uno',
          branch: 'main',
          token: '',
          url: '${root.path}/x/uno.git',
        ),
        throwsA(isA<CloneException>()),
      );
      expect(File('$busy/apuntes.tex').existsSync(), isTrue);
    },
  );
}
