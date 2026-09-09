/// Two ways to reach the repository, and one rule they share.
///
/// **Every change is a commit.** That is not an implementation detail, it is
/// the point: a commit has an author, a message, a parent and a diff, so every
/// change has a trail and any change can be reverted. Neither path below has a
/// way to modify content without producing one.
///
/// The two paths exist because a browser and a desktop can keep a secret to
/// very different degrees:
///
/// **Desktop — a token in the OS keychain, straight to GitHub.**
/// A fine-grained token scoped to one repository, pasted once and stored by
/// the operating system (Keychain on macOS, Credential Manager on Windows,
/// libsecret on Linux). The full clone lives on disk, so work happens offline
/// and a push is a push. No Worker in the way.
///
/// **Web — the Worker.** A browser cannot keep a secret: anything the page can
/// read, so can anyone with the developer tools open, and a GitHub token is
/// not scoped to one page. So on the web there is no token in the app at all;
/// the Worker holds it and the app proves who it is with a short-lived
/// Firebase token instead.
///
/// Note what is deliberately *not* offered anywhere: a username and password
/// field. GitHub removed password authentication for git in 2021, so it would
/// not work — and a form that asks for an account password in order to store
/// it is the shape of a phishing page even when the intent is honest.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth.dart';

/// Where a token is kept, and the checks it passes before it is.
class TokenStore implements SecretStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Not synchronised to iCloud: a repository credential should
              // stay on the machine it was authorised for.
              iOptions: IOSOptions(synchronizable: false),
            );

  static const String _key = 'didacta.github.token';

  final FlutterSecureStorage _storage;

  /// Whether storing a token here is safe at all.
  ///
  /// False on the web, where "secure storage" is browser storage and browser
  /// storage is readable by any script on the origin. The app must not offer
  /// to keep a token it cannot actually protect.
  @override
  bool get canStoreSafely => !kIsWeb;

  @override
  Future<String?> read() async {
    if (!canStoreSafely) return null;
    return _storage.read(key: _key);
  }

  @override
  Future<void> write(String token) async {
    if (!canStoreSafely) {
      throw const RepositoryAccessException(
        'Un navegador no puede guardar un token de forma segura. En web el '
        'acceso va por la API, que lo guarda por ti.',
      );
    }
    await _storage.write(key: _key, value: token.trim());
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class RepositoryAccessException implements Exception {
  const RepositoryAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a token turns out to be able to do.
///
/// Checked when it is pasted rather than when it is first used, so a wrong or
/// over-broad token is caught while the person is still looking at the field.
class TokenCheck {
  const TokenCheck({
    required this.valid,
    required this.canWrite,
    this.login,
    this.scopeWarning,
    this.problem,
  });

  final bool valid;
  final bool canWrite;
  final String? login;

  /// Set when the token works but reaches more than it needs to. Not an
  /// error -- it is the user's account and their decision -- but worth saying
  /// once, because the narrower token is free and strictly better.
  final String? scopeWarning;

  final String? problem;
}

/// The desktop path: a token, and commits made straight to GitHub.
class GitHubDirect {
  const GitHubDirect({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.token,
    this.client,
  });

  final String owner;
  final String repo;
  final String branch;
  final String token;
  /// Injected in tests. Absent means one per call, which is fine for the
  /// handful of requests an editor makes.
  final http.Client? client;

  http.Client get _http => client ?? http.Client();

  Map<String, String> get _headers => {
        'authorization': 'Bearer $token',
        'accept': 'application/vnd.github+json',
        'x-github-api-version': '2022-11-28',
      };

  /// Verifies a token and reports what it can actually do.
  ///
  /// Asks GitHub rather than parsing the token: the prefix says what kind it
  /// is, never what it may do, and a token that looks right and cannot write
  /// fails at the worst moment otherwise.
  static Future<TokenCheck> check({
    required String owner,
    required String repo,
    required String token,
    http.Client? client,
  }) async {
    final http.Client request = client ?? http.Client();
    try {
      final response = await request.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo'),
        headers: {
          'authorization': 'Bearer ${token.trim()}',
          'accept': 'application/vnd.github+json',
        },
      );

      if (response.statusCode == 401) {
        return const TokenCheck(
          valid: false,
          canWrite: false,
          problem: 'GitHub no reconoce ese token. Comprueba que lo has copiado '
              'entero y que no ha caducado.',
        );
      }
      if (response.statusCode == 404) {
        // 404 rather than 403 is what GitHub returns for a repository the
        // token cannot see at all, which is indistinguishable from one that
        // does not exist -- deliberately, on their side.
        return TokenCheck(
          valid: false,
          canWrite: false,
          problem: 'El token no alcanza $owner/$repo. Si es un token de '
              'permisos limitados, añade ese repositorio a su lista.',
        );
      }
      if (response.statusCode != 200) {
        return TokenCheck(
          valid: false,
          canWrite: false,
          problem: 'GitHub respondió ${response.statusCode}.',
        );
      }

      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final permissions = (body['permissions'] as Map?) ?? const {};
      final canPush = permissions['push'] == true;

      // A classic token with `repo` reaches every repository on the account.
      // It works, but the fine-grained equivalent is free and much narrower.
      String? warning;
      final scopes = response.headers['x-oauth-scopes'];
      if (scopes != null && scopes.contains('repo')) {
        warning = 'Este token es de los clásicos y alcanza todos tus '
            'repositorios. Uno de permisos limitados a $owner/$repo con '
            '«Contents: Read and write» haría lo mismo con mucho menos '
            'alcance.';
      }

      return TokenCheck(
        valid: true,
        canWrite: canPush,
        login: body['full_name'] as String?,
        scopeWarning: warning,
        problem: canPush
            ? null
            : 'El token puede leer $owner/$repo pero no escribir. Necesita '
                '«Contents: Read and write».',
      );
    } catch (error) {
      return TokenCheck(
        valid: false,
        canWrite: false,
        problem: 'No se ha podido contactar con GitHub: $error',
      );
    }
  }

  /// Reads a file at the current branch head.
  Future<({String text, String sha})> read(String path) async {
    final response = await _http.get(
      Uri.parse(
        'https://api.github.com/repos/$owner/$repo/contents/'
        '${_encode(path)}?ref=${Uri.encodeComponent(branch)}',
      ),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw RepositoryAccessException(
        'No se ha podido leer $path (HTTP ${response.statusCode}).',
      );
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = (body['content'] as String? ?? '').replaceAll('\n', '');
    return (
      text: utf8.decode(base64Decode(content)),
      sha: body['sha'] as String? ?? '',
    );
  }

  /// Writes a file as a commit.
  ///
  /// The `sha` makes it a compare-and-set: if the file moved on since it was
  /// read, GitHub refuses and nobody's work is silently overwritten. That
  /// refusal is surfaced rather than retried.
  Future<String> commit({
    required String path,
    required String text,
    required String sha,
    required String message,
    ({String name, String email})? author,
  }) async {
    final response = await _http.put(
      Uri.parse(
        'https://api.github.com/repos/$owner/$repo/contents/${_encode(path)}',
      ),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'content': base64Encode(utf8.encode(text)),
        'branch': branch,
        'sha': sha,
        if (author != null)
          'author': {'name': author.name, 'email': author.email},
      }),
    );

    if (response.statusCode == 409 || response.statusCode == 422) {
      throw const RepositoryAccessException(
        'El fichero ha cambiado desde que lo abriste. Vuelve a cargarlo para '
        'no perder el trabajo de otra persona.',
      );
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw RepositoryAccessException(
        'GitHub rechazó la escritura (HTTP ${response.statusCode}).',
      );
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return ((body['commit'] as Map?)?['sha'] as String?) ?? '';
  }

  static String _encode(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');
}
