/// One way to reach the content, whichever path it takes.
///
/// The app has two very different routes to the repository -- the Worker on
/// the web, a token in the OS keychain on desktop -- and exactly one of them
/// is available at a time. Every screen above this layer is written against
/// the interface, so no page contains a branch on which platform it is running
/// on. That is the whole reason this file exists.
///
/// Three things the interface insists on, because they are the rules the
/// platform is built around:
///
/// **Every change is a commit.** [commit] is the only way to write, and it
/// takes a message. There is no `save` that does something less traceable.
///
/// **A write is a compare-and-set.** [commit] takes the `sha` the content was
/// read at. If the file moved on, it fails and says so rather than
/// overwriting whoever got there first.
///
/// **Reading is authorised per path.** A gateway may refuse a read, and the
/// refusal carries a reason -- `access.json` decides, and the interface has to
/// be able to say which rule applied.
library;

import '../model/catalogue.dart';
import 'auth.dart';
import 'local_clone.dart';
import 'repository_access.dart';

/// A file as it exists in the repository right now.
class ContentFile {
  const ContentFile({
    required this.path,
    required this.text,
    required this.sha,
  });

  final String path;
  final String text;

  /// The version this text was read at. Required to write it back.
  final String sha;

  ContentFile withText(String next) =>
      ContentFile(path: path, text: next, sha: sha);
}

/// What went wrong, in terms a person can act on.
class ContentException implements Exception {
  const ContentException(this.message, {this.kind = ContentFailure.other});

  final String message;
  final ContentFailure kind;

  @override
  String toString() => message;
}

enum ContentFailure {
  /// Nobody is signed in, or the token has gone.
  unauthenticated,

  /// Signed in, but the policy says no. The message names the rule.
  forbidden,

  /// The file moved on since it was read. Re-read; do not retry.
  conflict,

  /// No such file.
  missing,

  /// Nothing is configured to reach the repository at all.
  unconfigured,

  other,
}

/// How the content is being reached, for the interface to show plainly.
enum GatewayKind {
  /// Through the Worker: identity by Firebase, policy in the repository.
  api,

  /// Straight to GitHub with a token from the keychain.
  direct,

  /// A clone on this machine, driven by git. Works with no network.
  clone,

  /// Nothing configured. Reads of public material may still work.
  none,
}

abstract class ContentGateway {
  const ContentGateway();

  GatewayKind get kind;

  /// A one-line description for the interface: where writes will go, and as
  /// whom. Shown rather than hidden, because "where did my change go" should
  /// never be a mystery.
  String describe();

  /// Whether writing is possible at all. False makes every editor read-only,
  /// which is better than an editor that fails on save.
  bool get canWrite;

  Future<ContentFile> read(String path);

  /// Writes the file as a commit. Returns the new sha.
  Future<String> commit({
    required String path,
    required String text,
    required String sha,
    required String message,
  });
}

/// Nothing configured: reads fail with an explanation, writes are impossible.
class UnconfiguredGateway extends ContentGateway {
  const UnconfiguredGateway([this.reason]);

  final String? reason;

  @override
  GatewayKind get kind => GatewayKind.none;

  @override
  bool get canWrite => false;

  @override
  String describe() =>
      reason ?? 'Sin acceso configurado: no se puede leer ni escribir.';

  @override
  Future<ContentFile> read(String path) async {
    throw ContentException(describe(), kind: ContentFailure.unconfigured);
  }

  @override
  Future<String> commit({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async {
    throw ContentException(describe(), kind: ContentFailure.unconfigured);
  }
}

/// Through the Worker. The web path.
class ApiGateway extends ContentGateway {
  const ApiGateway({required this.api, required this.authorisation});

  final DidactaApi api;
  final Authorisation authorisation;

  @override
  GatewayKind get kind => GatewayKind.api;

  @override
  bool get canWrite => authorisation.mayWriteSomething;

  @override
  String describe() {
    if (!authorisation.signedIn) return 'Sin sesión: solo material público.';
    final who = authorisation.email ?? 'sesión iniciada';
    final role = authorisation.role;
    if (role == null) {
      return '$who — sin permisos en access.json, solo lectura pública.';
    }
    return '$who — rol «$role» vía la API.';
  }

  @override
  Future<ContentFile> read(String path) async {
    try {
      final file = await api.readFile(path);
      return ContentFile(path: file.path, text: file.text, sha: file.sha);
    } on ApiException catch (error) {
      throw ContentException(error.message, kind: _kindOf(error));
    }
  }

  @override
  Future<String> commit({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async {
    try {
      final written = await api.writeFile(
        path: path,
        text: text,
        sha: sha,
        message: message,
      );
      return written.sha;
    } on ApiException catch (error) {
      throw ContentException(error.message, kind: _kindOf(error));
    }
  }

  static ContentFailure _kindOf(ApiException error) {
    if (error.isConflict) return ContentFailure.conflict;
    if (error.isForbidden) return ContentFailure.forbidden;
    if (error.isUnauthenticated) return ContentFailure.unauthenticated;
    if (error.status == 404) return ContentFailure.missing;
    return ContentFailure.other;
  }
}

/// Straight to GitHub with a stored token. The desktop path.
///
/// Note what is *not* here: any consultation of `access.json`. A token that
/// can write the repository can write all of it, and pretending otherwise in
/// the interface would be theatre. The policy is enforced by the Worker for
/// people who go through it; someone holding a repository token is, by
/// definition, someone trusted with the repository.
class DirectGateway extends ContentGateway {
  const DirectGateway({required this.github, required this.author});

  final GitHubDirect github;

  /// Who the commits are attributed to.
  final ({String name, String email})? author;

  @override
  GatewayKind get kind => GatewayKind.direct;

  @override
  bool get canWrite => true;

  @override
  String describe() {
    final who = author?.email ?? 'token local';
    return '$who — directo a ${github.owner}/${github.repo} '
        '(${github.branch}).';
  }

  @override
  Future<ContentFile> read(String path) async {
    try {
      final file = await github.read(path);
      return ContentFile(path: path, text: file.text, sha: file.sha);
    } on RepositoryAccessException catch (error) {
      throw ContentException(error.message);
    }
  }

  @override
  Future<String> commit({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async {
    try {
      return await github.commit(
        path: path,
        text: text,
        sha: sha,
        message: message,
        author: author,
      );
    } on RepositoryAccessException catch (error) {
      throw ContentException(
        error.message,
        kind: error.message.contains('ha cambiado')
            ? ContentFailure.conflict
            : ContentFailure.other,
      );
    }
  }
}

/// The paths a unit's files live at, derived rather than guessed.
///
/// Kept here next to the gateway because it is the one place that knows how a
/// catalogue record maps onto repository paths, and getting it wrong means
/// editing the wrong file.
extension UnitPaths on Unit {
  String fileFor(String language) => '$path/$language.tex';

  String get metadataPath => '$path/unit.yaml';
}

/// A clone on this machine, read and written through git.
///
/// The offline path, and the one the requirement asked for: everything is on
/// disk, so reading is instant and works on a train, and a save is a commit
/// followed by a push. Nothing about git has to be set up by hand -- the
/// token the author pasted is what authenticates the push.
///
/// Note what this does *not* do: consult `access.json`. A token that can
/// write the repository can write all of it, and a gateway that pretended
/// otherwise in the interface would be theatre. The policy is the Worker's
/// job, for the case where the app cannot be trusted with a token at all.
class CloneGateway extends ContentGateway {
  const CloneGateway({
    required this.clone,
    required this.token,
    required this.author,
    this.pushOnCommit = true,
  });

  final LocalClone clone;

  /// Only used to authenticate a push. Never written to disk by this class,
  /// and empty is a working configuration -- see [canWrite].
  final String token;

  final ({String name, String email})? author;

  /// A commit that is not pushed is not traceable by anyone else, so this
  /// defaults to true. It exists as a setting because pushing on every
  /// keystroke-sized commit is the wrong shape for a long editing session on
  /// a bad connection, and the interface can offer "push now" instead.
  final bool pushOnCommit;

  @override
  GatewayKind get kind => GatewayKind.clone;

  /// An author is all it takes.
  ///
  /// Deliberately **not** a token: committing to a clone on your own disk
  /// needs no credential at all, and only the push does. Requiring one here
  /// would mean the offline path -- the whole reason this gateway exists --
  /// stopped working the moment nobody had pasted a token.
  @override
  bool get canWrite => author != null;

  /// Whether a commit will actually reach GitHub.
  bool get willPush => pushOnCommit && token.isNotEmpty;

  @override
  String describe() {
    final who = author == null
        ? 'sin autor: pon un nombre y un correo para poder hacer commits'
        : 'como ${author!.name} <${author!.email}>';
    final push = token.isEmpty
        ? ', sin enviar a GitHub: falta el token'
        : (pushOnCommit ? ', enviando cada commit' : ', sin enviar al guardar');
    return 'Clon local en ${clone.directory}, $who$push';
  }

  @override
  Future<ContentFile> read(String path) async {
    try {
      final found = await clone.readFile(path);
      return ContentFile(path: path, text: found.text, sha: found.sha);
    } on CloneException catch (thrown) {
      throw ContentException(
        thrown.message,
        kind: thrown.message.contains('no existe')
            ? ContentFailure.missing
            : ContentFailure.other,
      );
    }
  }

  @override
  Future<String> commit({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async {
    if (author == null) {
      throw const ContentException(
        'Un commit necesita un autor. Inicia sesión antes de guardar.',
        kind: ContentFailure.unauthenticated,
      );
    }
    try {
      return await clone.commitFile(
        path: path,
        text: text,
        expectedSha: sha,
        message: message,
        authorName: author!.name,
        authorEmail: author!.email,
        token: token,
        // Not attempted without a token: it would fail, and a failed push
        // reported as a failed save would make an author think their work
        // was lost when it is committed and safe.
        push: willPush,
      );
    } on CloneException catch (thrown) {
      throw ContentException(
        thrown.stderr.isEmpty
            ? thrown.message
            : '${thrown.message}\n${thrown.stderr}',
        kind: thrown.message.contains('ha cambiado') ||
                thrown.message.contains('ya existe') ||
                thrown.message.contains('desaparecido')
            ? ContentFailure.conflict
            : ContentFailure.other,
      );
    }
  }
}
