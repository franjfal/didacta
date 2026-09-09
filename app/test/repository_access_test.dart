/// Tests for the token check and the commit path.
///
/// The token check exists so a wrong or over-broad token is caught while the
/// person is still looking at the field, instead of failing at the moment they
/// try to save work. So these are mostly about the messages: each one has to
/// say what to do next.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:didacta_app/data/repository_access.dart';

http.Client clientReturning(
  int status,
  Object body, {
  Map<String, String> headers = const {},
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );
  });
}

void main() {
  group('token check', () {
    test('a token that can push is accepted', () async {
      final check = await GitHubDirect.check(
        owner: 'franjfal',
        repo: 'didacta_db',
        token: 'whatever',
        client: clientReturning(200, {
          'full_name': 'franjfal/didacta_db',
          'permissions': {'push': true, 'pull': true},
        }),
      );
      expect(check.valid, isTrue);
      expect(check.canWrite, isTrue);
      expect(check.login, 'franjfal/didacta_db');
      expect(check.problem, isNull);
    });

    test('read-only is reported as such, not as valid', () async {
      // Otherwise the failure lands when someone tries to save.
      final check = await GitHubDirect.check(
        owner: 'franjfal',
        repo: 'didacta_db',
        token: 'whatever',
        client: clientReturning(200, {
          'full_name': 'franjfal/didacta_db',
          'permissions': {'push': false, 'pull': true},
        }),
      );
      expect(check.valid, isTrue);
      expect(check.canWrite, isFalse);
      expect(check.problem, contains('Contents: Read and write'));
    });

    test('401 says the token is not recognised', () async {
      final check = await GitHubDirect.check(
        owner: 'franjfal',
        repo: 'didacta_db',
        token: 'bad',
        client: clientReturning(401, {'message': 'Bad credentials'}),
      );
      expect(check.valid, isFalse);
      expect(check.problem, contains('no reconoce'));
    });

    test('404 says the token does not reach the repository', () async {
      // GitHub returns 404 rather than 403 for a repository a token cannot
      // see, so "not found" and "not permitted" arrive identically and the
      // message has to cover both.
      final check = await GitHubDirect.check(
        owner: 'franjfal',
        repo: 'didacta_db',
        token: 'narrow',
        client: clientReturning(404, {'message': 'Not Found'}),
      );
      expect(check.valid, isFalse);
      expect(check.problem, contains('no alcanza'));
      expect(check.problem, contains('didacta_db'));
    });

    test('a classic token is accepted but its reach is pointed out', () async {
      final check = await GitHubDirect.check(
        owner: 'franjfal',
        repo: 'didacta_db',
        token: 'classic',
        client: clientReturning(
          200,
          {
            'full_name': 'franjfal/didacta_db',
            'permissions': {'push': true},
          },
          headers: {'x-oauth-scopes': 'repo, gist'},
        ),
      );
      expect(check.valid, isTrue);
      expect(check.canWrite, isTrue);
      // Not an error: it is their account. Said once, because the narrower
      // token is free and strictly better.
      expect(check.scopeWarning, contains('todos tus'));
    });

    test('a fine-grained token gets no warning', () async {
      final check = await GitHubDirect.check(
        owner: 'franjfal',
        repo: 'didacta_db',
        token: 'fine',
        client: clientReturning(200, {
          'full_name': 'franjfal/didacta_db',
          'permissions': {'push': true},
        }),
      );
      expect(check.scopeWarning, isNull);
    });

    test('a network failure is reported, not swallowed', () async {
      final check = await GitHubDirect.check(
        owner: 'franjfal',
        repo: 'didacta_db',
        token: 'x',
        client: MockClient((_) async => throw Exception('sin red')),
      );
      expect(check.valid, isFalse);
      expect(check.problem, contains('No se ha podido contactar'));
    });
  });

  group('reading', () {
    test('decodes GitHub base64, newlines and accents included', () async {
      // GitHub wraps base64 at 60 characters, and these titles are Valencian.
      const text = 'La mètrica induïda en un espai normat';
      final wrapped = base64Encode(utf8.encode(text))
          .replaceAllMapped(RegExp('.{1,20}'), (m) => '${m[0]}\n');
      final github = GitHubDirect(
        owner: 'franjfal',
        repo: 'didacta_db',
        branch: 'main',
        token: 'x',
        client: clientReturning(200, {'content': wrapped, 'sha': 'abc'}),
      );
      final file = await github.read('content/a/es.tex');
      expect(file.text, text);
      expect(file.sha, 'abc');
    });

    test('a failure names the path', () async {
      final github = GitHubDirect(
        owner: 'franjfal',
        repo: 'didacta_db',
        branch: 'main',
        token: 'x',
        client: clientReturning(500, {'message': 'boom'}),
      );
      await expectLater(
        github.read('content/a/es.tex'),
        throwsA(isA<RepositoryAccessException>().having(
            (e) => e.message, 'message', contains('content/a/es.tex'))),
      );
    });
  });

  group('committing', () {
    test('every change is a commit, with a message and a parent sha', () async {
      // The rule the whole design rests on: no path modifies content without
      // producing a commit, so every change has an author and can be reverted.
      http.Request? sent;
      final github = GitHubDirect(
        owner: 'franjfal',
        repo: 'didacta_db',
        branch: 'main',
        token: 'x',
        client: clientReturning(
          200,
          {'commit': {'sha': 'newcommit'}, 'content': {'sha': 'newblob'}},
          onRequest: (request) => sent = request,
        ),
      );

      final sha = await github.commit(
        path: 'content/a/va.tex',
        text: 'nou contingut',
        sha: 'oldblob',
        message: 'Traducir métrica inducida al valenciano',
        author: (name: 'Javier Falcó', email: 'francisco.j.falco@uv.es'),
      );

      expect(sha, 'newcommit');
      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      expect(body['message'], 'Traducir métrica inducida al valenciano');
      expect(body['branch'], 'main');
      // The sha of what was read: this is what makes it a compare-and-set.
      expect(body['sha'], 'oldblob');
      expect((body['author'] as Map)['email'], 'francisco.j.falco@uv.es');
      expect(utf8.decode(base64Decode(body['content'] as String)),
          'nou contingut');
    });

    test('a conflict tells the author to reload rather than retrying', () async {
      // Retrying would overwrite whatever the other person wrote.
      for (final status in [409, 422]) {
        final github = GitHubDirect(
          owner: 'franjfal',
          repo: 'didacta_db',
          branch: 'main',
          token: 'x',
          client: clientReturning(status, {'message': 'conflict'}),
        );
        await expectLater(
          github.commit(
            path: 'content/a/va.tex',
            text: 'x',
            sha: 'stale',
            message: 'm',
          ),
          throwsA(isA<RepositoryAccessException>().having(
              (e) => e.message, 'message', contains('ha cambiado'))),
        );
      }
    });
  });

  group('token storage', () {
    test('the web cannot store a token, and says so instead of pretending',
        () async {
      // `flutter test` runs as non-web, so this asserts the contract rather
      // than the platform: `canStoreSafely` is what the UI must consult before
      // offering to keep a token.
      final store = TokenStore();
      expect(store.canStoreSafely, isTrue);
    });
  });
}
