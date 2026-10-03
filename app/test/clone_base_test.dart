/// La carpeta de todos los repositorios: que cada uno acabe dentro, el
/// primero igual que el segundo, y que cambiarla se lleve los de antes.
///
/// Contra git de verdad, con repositorios desnudos en lugar de GitHub: lo que
/// se prueba es que la carpeta se mueve entera y que el clon sigue siendo un
/// clon después, y eso un git de mentira no lo diría.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/github.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/data/preferences.dart';

import 'fixture.dart';

/// Una sesión cuyo GitHub es una carpeta con repositorios desnudos.
class BaseSession extends FakeSession {
  BaseSession(this.root)
    : super(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        preferencesOverride: MemoryPreferences(),
      );

  final String root;

  @override
  Future<GitHubRepo?> accessTo(String owner, String name) async => GitHubRepo(
    owner: owner,
    name: name,
    defaultBranch: 'main',
    private: true,
    canWrite: true,
  );

  @override
  String? remoteFor(String owner, String name) => '$root/remotes/$name.git';
}

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
    },
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
  }
}

/// Un repositorio de contenido en «GitHub», con un commit.
Future<void> _remote(String root, String name) async {
  final bare = '$root/remotes/$name.git';
  final seed = '$root/seeds/$name';
  await Directory(seed).create(recursive: true);
  await _git(['init', '--bare', '--initial-branch=main', bare], root);
  File('$seed/didacta.yaml').writeAsStringSync('name: "$name"\n');
  await _git(['init', '--initial-branch=main', seed], root);
  await _git(['add', '.'], seed);
  await _git(['commit', '-m', 'Empezar'], seed);
  await _git(['remote', 'add', 'origin', bare], seed);
  await _git(['push', '-u', 'origin', 'main'], seed);
}

void main() {
  late Directory root;
  late BaseSession session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('didacta-base-');
    await _remote(root.path, 'problemas');
    await _remote(root.path, 'teoria');
    session = BaseSession(root.path);
    await session.primeForTest(catalogueWith(defaultUnits()));
    await session.refreshAccess();
    await session.setCloneBase('${root.path}/Didacta');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> addBoth() async {
    for (final name in ['problemas', 'teoria']) {
      await session.addRepository(owner: 'ana', name: name, branch: 'main');
    }
  }

  test('el primero y el segundo, los dos dentro', () async {
    await addBoth();
    expect(session.workspace.repos.map((repo) => repo.directory), [
      '${root.path}/Didacta/problemas',
      '${root.path}/Didacta/teoria',
    ]);
    expect(session.outsideCloneBase, isEmpty);
  });

  test('uno de fuera se ve, y se lleva dentro sin perder nada', () async {
    // Como el `didacta_db` de antes de haber carpeta: en otro sitio.
    await session.addRepository(
      owner: 'ana',
      name: 'problemas',
      branch: 'main',
      directory: '${root.path}/viejo/problemas',
    );
    await session.addRepository(owner: 'ana', name: 'teoria', branch: 'main');
    File(
      '${root.path}/viejo/problemas/apuntes.tex',
    ).writeAsStringSync('a medias\n');

    expect(session.outsideCloneBase.map((repo) => repo.id), ['ana/problemas']);

    expect(await session.relocateRepository('ana/problemas'), isNull);

    final moved = '${root.path}/Didacta/problemas';
    // En su sitio de la lista: el primero sigue siendo el primero.
    expect(session.workspace.repos.map((repo) => repo.directory), [
      moved,
      '${root.path}/Didacta/teoria',
    ]);
    expect(session.outsideCloneBase, isEmpty);
    expect(await Directory('${root.path}/viejo/problemas').exists(), isFalse);
    expect(File('$moved/apuntes.tex').readAsStringSync(), 'a medias\n');
    // Y sigue siendo un clon: git lo abre donde está ahora.
    final status = await LocalClone(directory: moved).status();
    expect(status.branch, 'main');
    expect(status.dirtyPaths, contains('apuntes.tex'));
  });

  test('cambiar de carpeta deja fuera a todos, y se llevan todos', () async {
    await addBoth();
    await session.setCloneBase('${root.path}/Nueva');
    expect(session.outsideCloneBase, hasLength(2));

    for (final repo in List.of(session.outsideCloneBase)) {
      await session.relocateRepository(repo.id);
    }

    expect(session.workspace.repos.map((repo) => repo.directory), [
      '${root.path}/Nueva/problemas',
      '${root.path}/Nueva/teoria',
    ]);
    expect(session.outsideCloneBase, isEmpty);
  });

  test('si donde va ya hay algo, no se mueve nada', () async {
    await addBoth();
    await session.setCloneBase('${root.path}/Nueva');
    final there = Directory('${root.path}/Nueva/problemas')
      ..createSync(recursive: true);
    File('${there.path}/nota.txt').writeAsStringSync('de otra persona\n');

    await expectLater(
      session.relocateRepository('ana/problemas'),
      throwsA(isA<CloneException>()),
    );
    expect(
      session.workspace.byId('ana/problemas')!.directory,
      '${root.path}/Didacta/problemas',
    );
    expect(File('${there.path}/nota.txt').existsSync(), isTrue);
  });

  test('con algo a medio escribir, no se mueve', () async {
    await addBoth();
    await session.setCloneBase('${root.path}/Nueva');
    session.unsaved.mark(Object(), '«Espacios normados»');

    await expectLater(
      session.relocateRepository('ana/problemas'),
      throwsA(isA<CloneException>()),
    );
    expect(await Directory('${root.path}/Didacta/problemas').exists(), isTrue);
  });
}
