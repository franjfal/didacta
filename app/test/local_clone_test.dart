/// Tests for the local clone, against real git repositories.
///
/// Real ones on purpose. A git-backed gateway mocked out would prove that
/// the Dart is self-consistent and nothing about whether the commits are
/// real, the author is right, the push works, or a concurrent change is
/// caught. So each test builds a bare repository and a clone of it in a
/// temporary directory and drives the actual `git` binary.
///
/// The two properties that matter:
///
/// * **a save is a commit, pushed** -- traceable and revertible by someone
///   else, which a commit sitting in a local clone is not;
/// * **a write is a compare-and-set** -- if the file moved on since the
///   screen read it, the save fails and nothing is written.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

/// A bare repository standing in for GitHub, plus a clone of it.
class Fixture {
  Fixture(this.root, this.remote, this.clone);

  final Directory root;
  final String remote;
  final LocalClone clone;

  static Future<Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('didacta-clone-');
    final remote = '${root.path}/remote.git';
    final work = '${root.path}/seed';
    final clone = '${root.path}/clone';

    await _git(['init', '--bare', '--initial-branch=main', remote], root.path);

    // Seed the remote with something that looks like the content repository.
    await Directory(
      '$work/content/analysis/normed/definition',
    ).create(recursive: true);
    File(
      '$work/content/analysis/normed/definition/es.tex',
    ).writeAsStringSync('El contenido original.\n');
    File(
      '$work/content/analysis/normed/definition/unit.yaml',
    ).writeAsStringSync('id: analysis.normed.definition\nkind: theory\n');
    await _git(['init', '--initial-branch=main', work], root.path);
    await _git(['add', '.'], work);
    await _git(_asSomeone(['commit', '-m', 'Contenido inicial']), work);
    await _git(['remote', 'add', 'origin', remote], work);
    await _git(['push', '-u', 'origin', 'main'], work);

    final local = await LocalClone.create(
      directory: clone,
      // A path rather than an owner/repo: `create` builds
      // `https://github.com/<owner>/<repo>.git`, so the remote is faked by
      // giving it a path that lands on the bare repository above.
      owner: '.',
      repo: 'x',
      branch: 'main',
      token: '',
    );
    return Fixture(root, remote, local);
  }

  Future<void> dispose() => root.delete(recursive: true);
}

/// The clone helper builds a GitHub URL, which a test cannot reach. This
/// clones by path instead, exercising the same `_GitClone` afterwards.
Future<LocalClone> cloneByPath(String from, String into) async {
  await _git(['clone', '--branch', 'main', from, into], '.');
  return LocalClone(directory: into);
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

List<String> _asSomeone(List<String> arguments) => [
  '-c',
  'user.name=Semilla',
  '-c',
  'user.email=semilla@example.com',
  ...arguments,
];

const String unitFile = 'content/analysis/normed/definition/es.tex';

void main() {
  late Directory root;
  late String remote;
  late LocalClone clone;

  setUp(() async {
    if (!await LocalClone.gitAvailable()) {
      // Reported rather than skipped silently: a suite that quietly stops
      // testing the git path is worse than one that says it did.
      fail('git no está instalado, así que esta parte no se puede probar');
    }
    root = await Directory.systemTemp.createTemp('didacta-clone-');
    remote = '${root.path}/remote.git';
    final seed = '${root.path}/seed';

    await _git(['init', '--bare', '--initial-branch=main', remote], root.path);
    await Directory(
      '$seed/content/analysis/normed/definition',
    ).create(recursive: true);
    File('$seed/$unitFile').writeAsStringSync('El contenido original.\n');
    await _git(['init', '--initial-branch=main', seed], root.path);
    await _git(['add', '.'], seed);
    await _git(_asSomeone(['commit', '-m', 'Contenido inicial']), seed);
    await _git(['remote', 'add', 'origin', remote], seed);
    await _git(['push', '-u', 'origin', 'main'], seed);

    clone = await cloneByPath(remote, '${root.path}/clone');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('guardar sin confirmar', () {
    // Con los commits automáticos apagados, guardar escribe en el árbol de
    // trabajo y ya: el cambio queda pendiente y alguien lo confirma después
    // con el mensaje que quiera. Contra git de verdad, porque lo que se está
    // probando es precisamente que git lo vea como pendiente.

    test('escribe el fichero y lo deja sucio', () async {
      final sha = (await clone.readFile(unitFile)).sha;
      await clone.writeFile(
        path: unitFile,
        text: 'Cambiado sin confirmar.\n',
        expectedSha: sha,
      );

      expect(
        (await clone.readFile(unitFile)).text,
        'Cambiado sin confirmar.\n',
      );
      final status = await clone.status();
      expect(status.dirtyPaths, contains(unitFile));
      expect(status.ahead, 0, reason: 'no hay commit todavía');
    });

    test(
      'devuelve el hash nuevo, para poder volver a guardar encima',
      () async {
        final first = (await clone.readFile(unitFile)).sha;
        final after = await clone.writeFile(
          path: unitFile,
          text: 'Una vez.\n',
          expectedSha: first,
        );
        expect(after, isNot(first));

        // Y con ese hash se puede guardar otra vez sin que se queje.
        await clone.writeFile(
          path: unitFile,
          text: 'Dos veces.\n',
          expectedSha: after,
        );
        expect((await clone.readFile(unitFile)).text, 'Dos veces.\n');
      },
    );

    test('se niega si el fichero cambió por debajo', () async {
      // El mismo compare-and-set que el commit, y por lo mismo: un `git pull`
      // --o el editor de texto de quien escribe-- puede haberlo movido desde
      // que se abrió la pantalla.
      final stale = (await clone.readFile(unitFile)).sha;
      File('${clone.directory}/$unitFile').writeAsStringSync('Otra cosa.\n');

      await expectLater(
        clone.writeFile(path: unitFile, text: 'Lo mío.\n', expectedSha: stale),
        throwsA(isA<CloneException>()),
      );
      expect((await clone.readFile(unitFile)).text, 'Otra cosa.\n');
    });

    test('crea uno nuevo, con sus carpetas', () async {
      const nuevo = 'content/analysis/normed/nueva/es.tex';
      await clone.writeFile(path: nuevo, text: 'Nueva.\n', expectedSha: '');
      expect((await clone.readFile(nuevo)).text, 'Nueva.\n');
      expect((await clone.status()).dirtyPaths, contains(nuevo));
    });

    test('y después se confirma todo junto, con un mensaje', () async {
      // Es el flujo entero: escribir varias veces y contar una.
      final sha = (await clone.readFile(unitFile)).sha;
      await clone.writeFile(path: unitFile, text: 'Uno.\n', expectedSha: sha);
      await clone.writeFile(
        path: 'content/analysis/normed/otra/es.tex',
        text: 'Dos.\n',
        expectedSha: '',
      );

      final pending = (await clone.status()).dirtyPaths;
      expect(pending.length, 2);

      final done = await clone.commitPaths(
        paths: pending,
        message: 'Lo de esta tarde',
        authorName: 'Javier',
        authorEmail: 'javier@uv.es',
        token: '',
        push: false,
      );

      expect(done, isTrue);
      final after = await clone.status();
      expect(after.dirtyPaths, isEmpty);
      expect(after.ahead, 1, reason: 'un commit, no dos');
    });
  });

  group('the clone', () {
    test('reads a file and its blob hash', () async {
      final found = await clone.readFile(unitFile);
      expect(found.text, 'El contenido original.\n');
      // The same hash git itself computes, which is what makes it usable as
      // a compare-and-set token.
      final result = await Process.run('git', [
        'hash-object',
        unitFile,
      ], workingDirectory: clone.directory);
      expect(found.sha, (result.stdout as String).trim());
    });

    test('a missing file is reported by name', () async {
      await expectLater(
        clone.readFile('content/no/such/file.tex'),
        throwsA(isA<CloneException>()),
      );
    });

    test('reports the branch, the head and a clean tree', () async {
      final status = await clone.status();
      expect(status.branch, 'main');
      expect(status.head, isNotEmpty);
      expect(status.isClean, isTrue);
      expect(status.isSynced, isTrue);
    });

    test('sees a change made outside the app', () async {
      // Someone editing in a text editor is a normal thing, not an error,
      // and the interface has to be able to say it happened.
      File('${clone.directory}/$unitFile').writeAsStringSync('a mano\n');
      final status = await clone.status();
      expect(status.isClean, isFalse);
      expect(status.dirtyPaths, contains(unitFile));
    });
  });

  group('committing', () {
    test('writes, commits and pushes, attributed to the author', () async {
      final before = await clone.readFile(unitFile);
      final sha = await clone.commitFile(
        path: unitFile,
        text: 'Contenido editado.\n',
        expectedSha: before.sha,
        message: 'Editar la versión es de «Espacios normados»',
        authorName: 'Javier Falcó',
        authorEmail: 'javier@uv.es',
        token: '',
      );
      expect(sha, isNot(before.sha));

      // The commit is real, and says who made it and why.
      final log = await Process.run('git', [
        'log',
        '-1',
        '--pretty=%an|%ae|%s',
      ], workingDirectory: clone.directory);
      expect(
        (log.stdout as String).trim(),
        'Javier Falcó|javier@uv.es|Editar la versión es de «Espacios normados»',
      );

      // And it reached the remote, which is what makes it traceable by
      // anyone other than the person who made it.
      final remoteLog = await Process.run('git', [
        'log',
        '-1',
        '--pretty=%s',
        'main',
      ], workingDirectory: remote);
      expect(
        (remoteLog.stdout as String).trim(),
        'Editar la versión es de «Espacios normados»',
      );
    });

    test('a new file needs an empty sha, and gets committed', () async {
      const newFile = 'content/analysis/normed/definition/va.tex';
      await clone.commitFile(
        path: newFile,
        text: 'El contingut en valencià.\n',
        expectedSha: '',
        message: 'Añadir la versión va',
        authorName: 'Javier Falcó',
        authorEmail: 'javier@uv.es',
        token: '',
      );
      final found = await clone.readFile(newFile);
      expect(found.text, 'El contingut en valencià.\n');
      final status = await clone.status();
      expect(status.isClean, isTrue);
    });

    test(
      'a file that changed underneath is a conflict, and nothing is written',
      () async {
        final before = await clone.readFile(unitFile);

        // Somebody else -- a pull, another editor, a text editor -- moves it on.
        File(
          '${clone.directory}/$unitFile',
        ).writeAsStringSync('Lo que escribió otra persona.\n');

        await expectLater(
          clone.commitFile(
            path: unitFile,
            text: 'Lo mío.\n',
            expectedSha: before.sha,
            message: 'Editar',
            authorName: 'Javier Falcó',
            authorEmail: 'javier@uv.es',
            token: '',
          ),
          throwsA(isA<CloneException>()),
        );

        // The other person's work is still there: the point of failing.
        expect(
          File('${clone.directory}/$unitFile').readAsStringSync(),
          'Lo que escribió otra persona.\n',
        );
      },
    );

    test('claiming a file is new when it exists is a conflict', () async {
      await expectLater(
        clone.commitFile(
          path: unitFile,
          text: 'x',
          expectedSha: '',
          message: 'Añadir',
          authorName: 'A',
          authorEmail: 'a@uv.es',
          token: '',
        ),
        throwsA(isA<CloneException>()),
      );
    });

    test('saving identical text makes no commit', () async {
      final before = await clone.readFile(unitFile);
      final head = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: clone.directory);

      await clone.commitFile(
        path: unitFile,
        text: before.text,
        expectedSha: before.sha,
        message: 'Sin cambios',
        authorName: 'A',
        authorEmail: 'a@uv.es',
        token: '',
      );

      final after = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: clone.directory);
      // A log full of no-op commits is worse than no commit.
      expect(after.stdout, head.stdout);
    });

    test('a commit stands even when the push fails', () async {
      // The remote goes away mid-session, which on a laptop is just called
      // "leaving the building".
      await Directory(remote).delete(recursive: true);
      final before = await clone.readFile(unitFile);

      await expectLater(
        clone.commitFile(
          path: unitFile,
          text: 'Escrito sin conexión.\n',
          expectedSha: before.sha,
          message: 'Editar sin conexión',
          authorName: 'Javier Falcó',
          authorEmail: 'javier@uv.es',
          token: '',
        ),
        throwsA(isA<CloneException>()),
      );

      // Committed, so nothing is lost, and the status says it is ahead.
      final log = await Process.run('git', [
        'log',
        '-1',
        '--pretty=%s',
      ], workingDirectory: clone.directory);
      expect((log.stdout as String).trim(), 'Editar sin conexión');
    });
  });

  group('the author', () {
    test('comes from git when nobody is signed in', () async {
      // The desktop case: a clone on your own disk must not need a web
      // sign-in to commit, and anyone with a clone already has an identity.
      await Process.run('git', [
        'config',
        '--local',
        'user.name',
        'Javier Falcó',
      ], workingDirectory: clone.directory);
      await Process.run('git', [
        'config',
        '--local',
        'user.email',
        'javier@uv.es',
      ], workingDirectory: clone.directory);
      final author = await clone.configuredAuthor();
      expect(author?.name, 'Javier Falcó');
      expect(author?.email, 'javier@uv.es');
    });

    test('is set locally, not globally', () async {
      await clone.setAuthor(name: 'Otra', email: 'otra@uv.es');
      final local = await Process.run('git', [
        'config',
        '--local',
        '--get',
        'user.email',
      ], workingDirectory: clone.directory);
      expect((local.stdout as String).trim(), 'otra@uv.es');
      // Written to this clone's config file and nowhere else, which is what
      // "not globally" means concretely.
      expect(
        File('${clone.directory}/.git/config').readAsStringSync(),
        contains('otra@uv.es'),
      );
    });
  });

  group('sin Firebase', () {
    // The desktop build has no `GoogleService-Info.plist`, so Firebase does
    // not come up. That must be a working configuration, not a broken one:
    // the whole point of the clone is that editing your own disk needs no
    // web service. The bug this pins was worse than a missing feature --
    // building `DidactaAuth` without Firebase threw from `main` before
    // `runApp`, so the window opened and stayed black.
    test('un clon sigue siendo escribible', () async {
      await clone.setAuthor(name: 'Javier Falcó', email: 'javier@uv.es');

      final session = Session(
        catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
        tokenStore: StubStore(),
        preferences: MemoryPreferences(path: clone.directory),
      );
      // The fixture's remote is a path, so `looksRight` is what would refuse
      // it; the gateway is what is under test, so it is built the same way
      // the session builds one.
      final gateway = CloneGateway(
        clone: clone,
        token: '',
        author: await clone.configuredAuthor(),
      );

      expect(session.canUseClone, isTrue);
      expect(
        gateway.canWrite,
        isTrue,
        reason: 'sin Firebase no se puede escribir',
      );
      expect(gateway.willPush, isFalse);

      final file = await gateway.read(unitFile);
      await gateway.save(
        path: unitFile,
        text: 'Editado sin Firebase.\n',
        sha: file.sha,
        message: 'Editar sin Firebase',
      );
      final log = await Process.run('git', [
        'log',
        '-1',
        '--pretty=%an|%s',
      ], workingDirectory: clone.directory);
      expect((log.stdout as String).trim(), 'Javier Falcó|Editar sin Firebase');
    });
  });

  group('un repositorio vacío', () {
    // El caso de un repositorio recién creado en GitHub para empezar un
    // curso: sin commits, así que sin ninguna rama que clonar.
    late String empty;

    setUp(() async {
      empty = '${root.path}/empty.git';
      await _git(['init', '--bare', '--initial-branch=main', empty], root.path);
    });

    test('clonarlo se dice como vacío, y no deja carpeta', () async {
      final into = '${root.path}/vacio';
      await expectLater(
        LocalClone.create(
          directory: into,
          owner: 'x',
          repo: 'vacio',
          branch: 'main',
          token: '',
          url: empty,
        ),
        throwsA(isA<EmptyRepositoryException>()),
      );
      expect(Directory(into).existsSync(), isFalse);
    });

    test('un clon que falla no deja la carpeta a medias', () async {
      // La rama no existe: el remoto tiene commits, pero no esa.
      final into = '${root.path}/sin-rama';
      await expectLater(
        LocalClone.create(
          directory: into,
          owner: 'x',
          repo: 'x',
          branch: 'no-existe',
          token: '',
          url: remote,
        ),
        throwsA(isA<CloneException>()),
      );
      expect(Directory(into).existsSync(), isFalse);
    });

    test(
      'prepararlo deja un clon al día, con el commit en el remoto',
      () async {
        final into = '${root.path}/curso';
        final prepared = await LocalClone.initialize(
          directory: into,
          owner: 'x',
          repo: 'curso',
          branch: 'main',
          token: '',
          title: 'Teoría: «Bases de datos» #1',
          authorName: 'Javier Falcó',
          authorEmail: 'javier@uv.es',
          url: empty,
        );

        // El nombre entre comillas: los dos puntos y la almohadilla romperían
        // un YAML escrito a pelo.
        expect(
          File('$into/didacta.yaml').readAsStringSync(),
          contains('name: "Teoría: «Bases de datos» #1"'),
        );
        expect(
          File('$into/.gitignore').readAsStringSync(),
          contains('.didacta-build/'),
        );

        final status = await prepared.status();
        expect(status.branch, 'main');
        expect(status.isClean, isTrue);
        expect(status.isSynced, isTrue, reason: 'enviado y con seguimiento');

        final log = await Process.run('git', [
          'log',
          '-1',
          '--pretty=%an|%ae',
          'main',
        ], workingDirectory: empty);
        expect((log.stdout as String).trim(), 'Javier Falcó|javier@uv.es');
      },
    );

    test('con la rama que dice GitHub, no la de esta máquina', () async {
      final into = '${root.path}/trunk';
      final prepared = await LocalClone.initialize(
        directory: into,
        owner: 'x',
        repo: 'trunk',
        branch: 'trunk',
        token: '',
        title: 'Trunk',
        authorName: 'A',
        authorEmail: 'a@uv.es',
        url: empty,
      );
      expect((await prepared.status()).branch, 'trunk');
      final refs = await Process.run('git', [
        'show-ref',
        '--heads',
      ], workingDirectory: empty);
      expect(refs.stdout as String, contains('refs/heads/trunk'));
    });

    test('si ya no está vacío no se pisa, y no deja carpeta', () async {
      final into = '${root.path}/pisar';
      await expectLater(
        LocalClone.initialize(
          directory: into,
          owner: 'x',
          repo: 'x',
          branch: 'main',
          token: '',
          title: 'Encima',
          authorName: 'A',
          authorEmail: 'a@uv.es',
          url: remote,
        ),
        throwsA(
          isA<CloneException>().having(
            (e) => e.message,
            'motivo',
            contains('ya no está vacío'),
          ),
        ),
      );
      expect(Directory(into).existsSync(), isFalse);
    });

    test('una carpeta con cosas dentro no se usa', () async {
      final into = '${root.path}/ocupada';
      await Directory(into).create();
      File('$into/algo.txt').writeAsStringSync('mío\n');
      await expectLater(
        LocalClone.initialize(
          directory: into,
          owner: 'x',
          repo: 'curso',
          branch: 'main',
          token: '',
          title: 'Curso',
          authorName: 'A',
          authorEmail: 'a@uv.es',
          url: empty,
        ),
        throwsA(isA<CloneException>()),
      );
      expect(File('$into/algo.txt').readAsStringSync(), 'mío\n');
    });
  });

  group('the gateway on top', () {
    CloneGateway gatewayFor({bool signedIn = true, bool push = true}) =>
        CloneGateway(
          clone: clone,
          token: 'x',
          author: signedIn
              ? (name: 'Javier Falcó', email: 'javier@uv.es')
              : null,
          pushOnCommit: push,
        );

    test('says where the clone is and as whom it commits', () {
      final described = gatewayFor().describe();
      expect(described, contains(clone.directory));
      expect(described, contains('javier@uv.es'));
      expect(gatewayFor().kind, GatewayKind.clone);
    });

    test('can write with no token at all', () async {
      // The offline case, and the reason this gateway exists: committing to a
      // clone on your own disk needs no credential. Only the push does.
      final gateway = CloneGateway(
        clone: clone,
        token: '',
        author: (name: 'Javier Falcó', email: 'javier@uv.es'),
      );
      expect(gateway.canWrite, isTrue);
      expect(gateway.willPush, isFalse);
      expect(gateway.describe(), contains('falta el token'));

      final file = await gateway.read(unitFile);
      await gateway.save(
        path: unitFile,
        text: 'Escrito sin token.\n',
        sha: file.sha,
        message: 'Editar sin token',
      );
      final log = await Process.run('git', [
        'log',
        '-1',
        '--pretty=%s',
      ], workingDirectory: clone.directory);
      expect((log.stdout as String).trim(), 'Editar sin token');
    });

    test('cannot write without an author, and says why', () async {
      final gateway = gatewayFor(signedIn: false);
      expect(gateway.canWrite, isFalse);
      await expectLater(
        gateway.save(path: unitFile, text: 'x', sha: 'y', message: 'm'),
        throwsA(
          isA<ContentException>().having(
            (e) => e.kind,
            'kind',
            ContentFailure.unauthenticated,
          ),
        ),
      );
    });

    test(
      'a conflict arrives as a conflict, not as a generic failure',
      () async {
        // The correct response is "reload"; a generic failure invites a retry,
        // which overwrites whoever got there first.
        final gateway = gatewayFor(push: false);
        final file = await gateway.read(unitFile);
        File('${clone.directory}/$unitFile').writeAsStringSync('otra cosa\n');

        await expectLater(
          gateway.save(
            path: unitFile,
            text: 'lo mío',
            sha: file.sha,
            message: 'm',
          ),
          throwsA(
            isA<ContentException>().having(
              (e) => e.kind,
              'kind',
              ContentFailure.conflict,
            ),
          ),
        );
      },
    );

    test('a missing file arrives as missing', () async {
      await expectLater(
        gatewayFor().read('content/no/such.tex'),
        throwsA(
          isA<ContentException>().having(
            (e) => e.kind,
            'kind',
            ContentFailure.missing,
          ),
        ),
      );
    });

    test('a read then a commit round-trips through git', () async {
      final gateway = gatewayFor(push: false);
      final file = await gateway.read(unitFile);
      final sha = await gateway.save(
        path: unitFile,
        text: 'Editado por la aplicación.\n',
        sha: file.sha,
        message: 'Editar desde la aplicación',
      );
      final again = await gateway.read(unitFile);
      expect(again.text, 'Editado por la aplicación.\n');
      expect(again.sha, sha);
    });
  });
}
