/// Dos repositorios a la vez, contra git de verdad.
///
/// Es la prueba que importa de todo el cambio: que lo que se escribe acaba en
/// **el repositorio del que salió el fichero**, que enviar cierra lo que está
/// suelto en cada uno y lo empuja, y que traer no se lleva por delante lo que
/// hubiera. Con clones reales y el binario `git`, porque lo que se está
/// probando es precisamente el trato con git.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

/// Un repositorio de contenido de mentira: un remoto desnudo y su clon.
class Repo {
  Repo(this.remote, this.directory);

  final String remote;
  final String directory;

  static Future<Repo> create(String root, String name, String unit) async {
    // Bajo `x/`, para que el remoto contenga `x/<nombre>`: es lo que mira la
    // aplicación para saber que una carpeta es el clon del repositorio que
    // dice ser, y aquí el remoto es una ruta en vez de una URL de GitHub.
    await Directory('$root/x').create(recursive: true);
    final remote = '$root/x/$name.git';
    final seed = '$root/$name-seed';
    final clone = '$root/$name';

    await _git(['init', '--bare', '--initial-branch=main', remote], root);
    await Directory('$seed/$unit').create(recursive: true);
    File('$seed/$unit/es.tex').writeAsStringSync('De $name.\n');
    File('$seed/didacta.yaml').writeAsStringSync('name: $name\n');
    await _git(['init', '--initial-branch=main', seed], root);
    await _git(['add', '.'], seed);
    await _git(['commit', '-m', 'Semilla'], seed);
    await _git(['remote', 'add', 'origin', remote], seed);
    await _git(['push', '-u', 'origin', 'main'], seed);
    await _git(['clone', '--branch', 'main', remote, clone], root);
    return Repo(remote, clone);
  }

  /// Lo que el remoto tiene en ese fichero, que es lo que vería otra persona.
  Future<String> remoteText(String path) async {
    final result = await Process.run('git', [
      'show',
      'main:$path',
    ], workingDirectory: remote);
    return result.exitCode == 0 ? result.stdout as String : '';
  }

  Future<int> remoteCommits() async {
    final result = await Process.run('git', [
      'rev-list',
      '--count',
      'main',
    ], workingDirectory: remote);
    return int.tryParse((result.stdout as String).trim()) ?? 0;
  }
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
      'GIT_TERMINAL_PROMPT': '0',
    },
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
  }
}

void main() {
  late Directory root;
  late Repo uno;
  late Repo dos;
  late Session session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('didacta-multi-');
    uno = await Repo.create(root.path, 'uno', 'content/analysis/normed/def');
    dos = await Repo.create(root.path, 'dos', 'content/algebra/matrices/rank');

    final workspace = Workspace([
      ContentRepo(
        owner: 'x',
        name: 'uno',
        directory: uno.directory,
        colour: 0xFF346E34,
      ),
      ContentRepo(
        owner: 'x',
        name: 'dos',
        directory: dos.directory,
        colour: 0xFF2D5FA0,
      ),
    ]);

    session = Session(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(repos: workspace.toJson()),
    );
    await session.start();
    // El autor: en un clon propio sale de git, sin entrar en ningún sitio.
    await session.setCloneAuthor(name: 'Javier', email: 'javier@uv.es');
  });

  tearDown(() => root.delete(recursive: true));

  test('cada repositorio tiene su pasarela, y escriben en el suyo', () async {
    // `looksRight` compara el remoto, y aquí es una ruta: lo que importa es
    // que la pasarela de cada uno apunta a su clon.
    expect(session.workspace.repos.length, 2);

    await session
        .gatewayFor('x/uno')
        .commit(
          path: 'content/analysis/normed/def/es.tex',
          text: 'Escrito en uno.\n',
          sha: await _shaOf(
            session,
            'x/uno',
            'content/analysis/normed/def/es.tex',
          ),
          message: 'Editar en uno',
        );
    await session
        .gatewayFor('x/dos')
        .commit(
          path: 'content/algebra/matrices/rank/es.tex',
          text: 'Escrito en dos.\n',
          sha: await _shaOf(
            session,
            'x/dos',
            'content/algebra/matrices/rank/es.tex',
          ),
          message: 'Editar en dos',
        );

    // Cada cambio, en su clon. Sin esto, con dos repositorios abiertos todo
    // se escribiría en el primero.
    expect(
      File(
        '${uno.directory}/content/analysis/normed/def/es.tex',
      ).readAsStringSync(),
      'Escrito en uno.\n',
    );
    expect(
      File(
        '${dos.directory}/content/algebra/matrices/rank/es.tex',
      ).readAsStringSync(),
      'Escrito en dos.\n',
    );
  });

  test('enviar cierra lo suelto de cada uno y lo empuja', () async {
    // Como si alguien hubiera editado con otro programa: ficheros escritos y
    // sin commit, en los dos repositorios.
    File(
      '${uno.directory}/content/analysis/normed/def/es.tex',
    ).writeAsStringSync('Tocado por fuera en uno.\n');
    File(
      '${dos.directory}/content/algebra/matrices/rank/es.tex',
    ).writeAsStringSync('Tocado por fuera en dos.\n');

    final boxes = await session.outbox();
    expect(boxes.length, 2);
    expect(boxes.first.pending.single, 'content/analysis/normed/def/es.tex');

    final result = await session.pushAll('Trabajo de la tarde');
    expect(result.values.every((each) => each is int), isTrue);

    // Y está en el remoto, que es lo único que le consta a otra persona.
    expect(
      await uno.remoteText('content/analysis/normed/def/es.tex'),
      'Tocado por fuera en uno.\n',
    );
    expect(
      await dos.remoteText('content/algebra/matrices/rank/es.tex'),
      'Tocado por fuera en dos.\n',
    );
  });

  test('traer se trae lo de los dos', () async {
    // Otra persona empuja a cada remoto.
    for (final repo in [uno, dos]) {
      final other = '${root.path}/otro-${repo.remote.hashCode}';
      await _git(['clone', '--branch', 'main', repo.remote, other], root.path);
      File('$other/nuevo.txt').writeAsStringSync('De otra persona\n');
      await _git(['add', '.'], other);
      await _git(['commit', '-m', 'Desde fuera'], other);
      await _git(['push'], other);
    }

    await session.pullAll();

    expect(File('${uno.directory}/nuevo.txt').existsSync(), isTrue);
    expect(File('${dos.directory}/nuevo.txt').existsSync(), isTrue);
  });

  test('lo que no se toca no se envía', () async {
    // Un historial con commits vacíos es un historial que nadie lee.
    final before = await uno.remoteCommits();
    await session.pushAll('Nada que enviar');
    expect(await uno.remoteCommits(), before);
  });

  test('una carpeta que ya está en el disco se añade sin GitHub', () async {
    // El camino de vuelta para quien ya tenía un clon, y el que funciona
    // antes de haber configurado la OAuth App.
    final fresh = Session(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    );
    await fresh.start();
    // Sin repositorios abre vacía y **sin error**: no es un fallo, es que
    // falta decirle con qué trabajar.
    expect(fresh.state, LoadState.ready);
    expect(fresh.needsRepository, isTrue);

    final added = await fresh.addExistingRepository(uno.directory);
    // De qué repositorio es lo dice su propio remoto.
    expect(added.name, 'uno');
    expect(added.directory, uno.directory);
    expect(fresh.needsRepository, isFalse);
    expect(fresh.gatewayFor(added.id).canWrite, isTrue);
  });

  test('una carpeta que no es un clon se rechaza diciendo por qué', () async {
    final fresh = Session(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
    );
    await fresh.start();
    await expectLater(
      fresh.addExistingRepository(root.path),
      throwsA(isA<CloneException>()),
    );
  });

  test('cada repositorio tiene su color, y solo cuando hay varios', () async {
    expect(session.colourOf('x/uno'), 0xFF346E34);
    expect(session.colourOf('x/dos'), 0xFF2D5FA0);

    // Con uno solo no hay con qué confundirlo, así que no se marca nada.
    final alone = Session(
      catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(
        repos: Workspace([
          ContentRepo(owner: 'x', name: 'uno', directory: uno.directory),
        ]).toJson(),
      ),
    );
    await alone.start();
    expect(alone.colourOf('x/uno'), isNull);
  });
}

Future<String> _shaOf(Session session, String repo, String path) async {
  final file = await session.gatewayFor(repo).read(path);
  return file.sha;
}
