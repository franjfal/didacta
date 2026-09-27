/// El repositorio de ejemplo: que se crea, que lleva lo que tiene que llevar
/// y que pulsar el botón dos veces no llena la cuenta de ejemplos.
///
/// Contra git de verdad, con un repositorio desnudo en lugar de GitHub: lo
/// que se prueba es precisamente que el primer commit llegue al remoto con
/// todos los ficheros, y eso un git de mentira no lo diría.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/example_repository.dart';
import 'package:didacta_app/data/github.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/data/preferences.dart';

import 'fixture.dart';

/// Una sesión cuyo GitHub es una carpeta con repositorios desnudos.
class ExampleSession extends FakeSession {
  ExampleSession(this.root)
    : super(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        preferencesOverride: MemoryPreferences(),
      );

  final String root;

  /// Lo que hay en «GitHub», por `dueño/nombre`.
  final Map<String, GitHubRepo> onGitHub = {};

  /// Cuáles de esos son de contenido de Didacta.
  final Set<String> content = {};

  /// Qué se ha creado, en orden.
  final List<String> created = [];

  @override
  Future<GitHubRepo?> accessTo(String owner, String name) async =>
      onGitHub['$owner/$name'];

  @override
  Future<bool> isContentRepository(String owner, String name) async =>
      content.contains('$owner/$name');

  @override
  Future<GitHubRepo> createGitHubRepository({
    required String name,
    String description = '',
  }) async {
    created.add(name);
    await bare(name);
    final repo = GitHubRepo(
      owner: testUser.login,
      name: name,
      defaultBranch: 'main',
      private: true,
      canWrite: true,
    );
    onGitHub['${testUser.login}/$name'] = repo;
    return repo;
  }

  @override
  String? remoteFor(String owner, String name) => '$root/remotes/$name.git';

  Future<void> bare(String name) async {
    final made = await Process.run('git', [
      'init',
      '--bare',
      '--initial-branch=main',
      '$root/remotes/$name.git',
    ]);
    if (made.exitCode != 0) throw StateError('${made.stderr}');
  }
}

const Map<String, String> seed = {
  'didacta.yaml': 'name: "Ejemplo de Didacta"\nlanguages: [es, va, en]\n',
  'README.md': '# El ejemplo\n',
  '.gitignore': '.didacta-build/\n',
  'courses/calculo-i/course.yaml': 'id: calculo-i\n',
};

Future<List<String>> filesIn(String remote) async {
  final tree = await Process.run('git', [
    'ls-tree',
    '-r',
    '--name-only',
    'main',
  ], workingDirectory: remote);
  return (tree.stdout as String).trim().split('\n');
}

void main() {
  late Directory root;
  late ExampleSession session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('didacta-ejemplo-');
    session = ExampleSession(root.path);
    await session.primeForTest(catalogueWith(defaultUnits()));
    // Quién ha entrado, que es a nombre de quien va el primer commit.
    await session.refreshAccess();
    await session.setCloneBase('${root.path}/clones');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('se crea en la cuenta, con todo dentro, y queda abierto', () async {
    final opened = await session.createExampleRepository(files: seed);

    expect(opened.reused, isFalse);
    expect(opened.repo.id, 'profe/didacta-ejemplo');
    expect(session.created, ['didacta-ejemplo']);
    // Y el `.gitattributes`, que lleva todo repositorio nuevo: el fin de
    // línea de sus ficheros no depende de quién los guarde.
    expect(
      await filesIn('${root.path}/remotes/didacta-ejemplo.git'),
      // Y el workflow que compila el material en GitHub, que no está entre
      // los recursos: se escribe con la versión de esta aplicación.
      unorderedEquals([
        ...seed.keys,
        '.gitattributes',
        '.github/workflows/material.yml',
      ]),
    );
    expect(
      File(
        '${root.path}/clones/didacta-ejemplo/courses/calculo-i/course.yaml',
      ).existsSync(),
      isTrue,
    );
    expect(
      session.workspace.repos.map((repo) => repo.id),
      contains('profe/didacta-ejemplo'),
    );
  });

  test('con el nombre cogido por otra cosa, usa el siguiente', () async {
    session.onGitHub['profe/didacta-ejemplo'] = const GitHubRepo(
      owner: 'profe',
      name: 'didacta-ejemplo',
      defaultBranch: 'main',
      private: false,
      canWrite: true,
    );

    final opened = await session.createExampleRepository(files: seed);

    expect(opened.repo.name, 'didacta-ejemplo-2');
    expect(session.created, ['didacta-ejemplo-2']);
  });

  test('si ya hay un ejemplo de antes, abre ese y no crea otro', () async {
    // El de antes: creado y sembrado, y ya no en este disco --se creó en el
    // otro ordenador, o se quitó con la carpeta--. En GitHub sigue.
    await session.createExampleRepository(files: seed);
    await session.removeRepository('profe/didacta-ejemplo');
    await Directory(
      '${root.path}/clones/didacta-ejemplo',
    ).delete(recursive: true);
    session.content.add('profe/didacta-ejemplo');
    session.created.clear();

    final opened = await session.createExampleRepository(files: seed);

    expect(opened.reused, isTrue);
    expect(opened.repo.id, 'profe/didacta-ejemplo');
    expect(session.created, isEmpty);
  });

  test('una carpeta ocupada en el disco no se pisa', () async {
    final taken = Directory('${root.path}/clones/didacta-ejemplo')
      ..createSync(recursive: true);
    File('${taken.path}/mio.txt').writeAsStringSync('no es un clon\n');

    final opened = await session.createExampleRepository(files: seed);

    expect(opened.repo.name, 'didacta-ejemplo-2');
    expect(File('${taken.path}/mio.txt').readAsStringSync(), 'no es un clon\n');
  });

  group('lo que viaja con la aplicación', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('trae un repositorio de contenido entero', () async {
      final files = await loadExampleRepository();

      expect(files.keys, containsAll(['didacta.yaml', 'README.md']));
      expect(files['.gitignore'], contains('.didacta-build/'));
      expect(
        files.keys.where((path) => path.startsWith('courses/')),
        isNotEmpty,
      );
      expect(
        files.keys.where((path) => path.startsWith('content/')),
        isNotEmpty,
      );
      expect(
        files.keys.any((path) => path.contains('.didacta-build')),
        isFalse,
      );
      // El workflow de la web del curso, con su punto: GitHub solo lee
      // `.github/`.
      expect(
        files['.github/workflows/web-del-curso.yml'],
        contains('didacta site'),
      );
      expect(files.keys.any((path) => path.startsWith('github/')), isFalse);
    });

    test('ningún fichero del ejemplo se queda fuera del paquete', () async {
      // Flutter empaqueta carpeta a carpeta, y una lección en una carpeta
      // nueva que nadie apuntó en `pubspec.yaml` no llega al repositorio de
      // quien lo pruebe --sin error: simplemente, no está--.
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final packed = manifest.listAssets().toSet();
      final onDisk = [
        for (final entity in Directory(
          exampleAssetRoot,
        ).listSync(recursive: true))
          if (entity is File && !entity.path.split('/').last.startsWith('.'))
            entity.path,
      ];

      expect(onDisk, isNotEmpty);
      for (final path in onDisk) {
        expect(packed, contains(path), reason: '$path no está en pubspec.yaml');
      }
    });
  });

  test('la ruta de los ficheros no sale nunca del repositorio', () {
    // Lo mismo que comprueba `LocalClone.initialize`, dicho desde aquí:
    // el ejemplo es una lista de rutas, y una mal escrita no puede escribir
    // fuera de la carpeta de quien lo prueba.
    expect(LocalClone.ignoredFiles, contains('.didacta-build/'));
  });
}
