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

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/local_clone.dart';

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
    await Directory('$work/content/analysis/normed/definition')
        .create(recursive: true);
    File('$work/content/analysis/normed/definition/es.tex')
        .writeAsStringSync('El contenido original.\n');
    File('$work/content/analysis/normed/definition/unit.yaml')
        .writeAsStringSync('id: analysis.normed.definition\nkind: theory\n');
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
      '-c', 'user.name=Semilla',
      '-c', 'user.email=semilla@example.com',
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
    await Directory('$seed/content/analysis/normed/definition')
        .create(recursive: true);
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

  group('the clone', () {
    test('reads a file and its blob hash', () async {
      final found = await clone.readFile(unitFile);
      expect(found.text, 'El contenido original.\n');
      // The same hash git itself computes, which is what makes it usable as
      // a compare-and-set token.
      final result = await Process.run(
        'git',
        ['hash-object', unitFile],
        workingDirectory: clone.directory,
      );
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
      final log = await Process.run(
        'git',
        ['log', '-1', '--pretty=%an|%ae|%s'],
        workingDirectory: clone.directory,
      );
      expect(
        (log.stdout as String).trim(),
        'Javier Falcó|javier@uv.es|Editar la versión es de «Espacios normados»',
      );

      // And it reached the remote, which is what makes it traceable by
      // anyone other than the person who made it.
      final remoteLog = await Process.run(
        'git',
        ['log', '-1', '--pretty=%s', 'main'],
        workingDirectory: remote,
      );
      expect((remoteLog.stdout as String).trim(),
          'Editar la versión es de «Espacios normados»');
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

    test('a file that changed underneath is a conflict, and nothing is written',
        () async {
      final before = await clone.readFile(unitFile);

      // Somebody else -- a pull, another editor, a text editor -- moves it on.
      File('${clone.directory}/$unitFile')
          .writeAsStringSync('Lo que escribió otra persona.\n');

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
    });

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
      final head = await Process.run('git', ['rev-parse', 'HEAD'],
          workingDirectory: clone.directory);

      await clone.commitFile(
        path: unitFile,
        text: before.text,
        expectedSha: before.sha,
        message: 'Sin cambios',
        authorName: 'A',
        authorEmail: 'a@uv.es',
        token: '',
      );

      final after = await Process.run('git', ['rev-parse', 'HEAD'],
          workingDirectory: clone.directory);
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
      final log = await Process.run('git', ['log', '-1', '--pretty=%s'],
          workingDirectory: clone.directory);
      expect((log.stdout as String).trim(), 'Editar sin conexión');
    });
  });

  group('the author', () {
    test('comes from git when nobody is signed in', () async {
      // The desktop case: a clone on your own disk must not need a web
      // sign-in to commit, and anyone with a clone already has an identity.
      await Process.run(
        'git',
        ['config', '--local', 'user.name', 'Javier Falcó'],
        workingDirectory: clone.directory,
      );
      await Process.run(
        'git',
        ['config', '--local', 'user.email', 'javier@uv.es'],
        workingDirectory: clone.directory,
      );
      final author = await clone.configuredAuthor();
      expect(author?.name, 'Javier Falcó');
      expect(author?.email, 'javier@uv.es');
    });

    test('is set locally, not globally', () async {
      await clone.setAuthor(name: 'Otra', email: 'otra@uv.es');
      final local = await Process.run(
        'git',
        ['config', '--local', '--get', 'user.email'],
        workingDirectory: clone.directory,
      );
      expect((local.stdout as String).trim(), 'otra@uv.es');
      // Written to this clone's config file and nowhere else, which is what
      // "not globally" means concretely.
      expect(
        File('${clone.directory}/.git/config').readAsStringSync(),
        contains('otra@uv.es'),
      );
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
      await gateway.commit(
        path: unitFile,
        text: 'Escrito sin token.\n',
        sha: file.sha,
        message: 'Editar sin token',
      );
      final log = await Process.run('git', ['log', '-1', '--pretty=%s'],
          workingDirectory: clone.directory);
      expect((log.stdout as String).trim(), 'Editar sin token');
    });

    test('cannot write without an author, and says why', () async {
      final gateway = gatewayFor(signedIn: false);
      expect(gateway.canWrite, isFalse);
      await expectLater(
        gateway.commit(path: unitFile, text: 'x', sha: 'y', message: 'm'),
        throwsA(isA<ContentException>().having(
          (e) => e.kind,
          'kind',
          ContentFailure.unauthenticated,
        )),
      );
    });

    test('a conflict arrives as a conflict, not as a generic failure',
        () async {
      // The correct response is "reload"; a generic failure invites a retry,
      // which overwrites whoever got there first.
      final gateway = gatewayFor(push: false);
      final file = await gateway.read(unitFile);
      File('${clone.directory}/$unitFile').writeAsStringSync('otra cosa\n');

      await expectLater(
        gateway.commit(
          path: unitFile,
          text: 'lo mío',
          sha: file.sha,
          message: 'm',
        ),
        throwsA(isA<ContentException>()
            .having((e) => e.kind, 'kind', ContentFailure.conflict)),
      );
    });

    test('a missing file arrives as missing', () async {
      await expectLater(
        gatewayFor().read('content/no/such.tex'),
        throwsA(isA<ContentException>()
            .having((e) => e.kind, 'kind', ContentFailure.missing)),
      );
    });

    test('a read then a commit round-trips through git', () async {
      final gateway = gatewayFor(push: false);
      final file = await gateway.read(unitFile);
      final sha = await gateway.commit(
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
