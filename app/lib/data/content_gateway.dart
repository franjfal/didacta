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
