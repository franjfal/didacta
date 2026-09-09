/// Tests for the gateway, which is the seam the whole app is written against.
///
/// Two things matter here more than anything else:
///
/// * a gateway that **cannot** write must say so, because `canWrite` is what
///   every editor consults before offering a save button, and an editor that
///   offers one and then fails has already cost someone their work;
/// * a conflict must arrive as a conflict, not as a generic failure, because
///   the correct response to it is "reload" and the wrong one is "retry".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:didacta_app/data/auth.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/repository_access.dart';
import 'package:didacta_app/model/catalogue.dart';

/// A token source that never touches Firebase.
///
/// Possible because `DidactaApi` takes a [TokenSource] rather than the whole
/// auth object -- it has no business being able to sign anyone in.
class _StubToken implements TokenSource {
  @override
  Future<String?> idToken({bool forceRefresh = false}) async => 'test-token';
}

Unit unitFor(String path) => Unit.fromJson({
      'id': path.replaceAll('/', '.'),
      'path': path,
      'area': path.split('/').first,
      'kind': 'theory',
      'category': 'a',
      'topic': 'b',
      'tags': const <String>[],
      'title': const {'es': 'Título'},
      'reference': 'es',
      'languages': const {
        'es': {'status': 'source', 'exists': true},
        'va': {'status': 'missing', 'exists': false},
      },
      'prerequisites': const <String>[],
      'objectives': const <String>[],
      'usedBy': const <Map<String, String>>[],
      'warnings': const <String>[],
    });

void main() {
  group('UnitPaths', () {
    test('a language file sits inside the unit directory', () {
      // Getting this wrong means editing the wrong file, so it is pinned.
      final unit = unitFor('content/analysis/normed/definition');
      expect(unit.fileFor('es'), 'content/analysis/normed/definition/es.tex');
      expect(unit.fileFor('va'), 'content/analysis/normed/definition/va.tex');
      expect(
        unit.metadataPath,
        'content/analysis/normed/definition/unit.yaml',
      );
    });
  });

  group('UnconfiguredGateway', () {
    test('cannot write, and refuses reads with an explanation', () async {
      const gateway = UnconfiguredGateway();
      expect(gateway.canWrite, isFalse);
      expect(gateway.kind, GatewayKind.none);
      await expectLater(
        gateway.read('content/a/es.tex'),
        throwsA(isA<ContentException>().having(
          (e) => e.kind,
          'kind',
          ContentFailure.unconfigured,
        )),
      );
    });

    test('carries the reason it was given, so Ajustes can explain', () {
      const gateway = UnconfiguredGateway('Sin API ni token.');
      expect(gateway.describe(), 'Sin API ni token.');
    });
  });

  group('ApiGateway', () {
    ApiGateway gatewayFor(
      Authorisation authorisation, {
      http.Client? client,
    }) =>
        ApiGateway(
          api: DidactaApi(
            base: 'https://api.example',
            auth: _StubToken(),
            client: client,
          ),
          authorisation: authorisation,
        );

    test('an anonymous caller cannot write and is told why', () {
      final gateway = gatewayFor(const Authorisation.anonymous());
      expect(gateway.canWrite, isFalse);
      expect(gateway.describe(), contains('Sin sesión'));
    });

    test('a signed-in user with no role cannot write', () {
      // The state that actually happens: someone with a Google account who is
      // not in access.json. The interface has to say so rather than look
      // broken.
      final gateway = gatewayFor(const Authorisation(
        signedIn: true,
        email: 'nadie@example.com',
      ));
      expect(gateway.canWrite, isFalse);
      expect(gateway.describe(), contains('sin permisos'));
    });

    test('a translator can write', () {
      final gateway = gatewayFor(const Authorisation(
        signedIn: true,
        email: 'traductora@uv.es',
        role: 'translator',
      ));
      expect(gateway.canWrite, isTrue);
      expect(gateway.describe(), contains('translator'));
    });

    test('a reader cannot write', () {
      final gateway = gatewayFor(const Authorisation(
        signedIn: true,
        email: 'lector@uv.es',
        role: 'reader',
      ));
      expect(gateway.canWrite, isFalse);
    });

    test('a 409 arrives as a conflict, not as a generic failure', () async {
      // The correct response is "reload"; treating it as generic invites a
      // retry, which overwrites whoever got there first.
      final gateway = gatewayFor(
        const Authorisation(
            signedIn: true, email: 'a@uv.es', role: 'owner'),
        client: MockClient((_) async => http.Response(
              jsonEncode({'error': 'cambió'}),
              409,
              headers: {'content-type': 'application/json'},
            )),
      );
      await expectLater(
        gateway.commit(
            path: 'content/a/es.tex', text: 'x', sha: 'old', message: 'm'),
        throwsA(isA<ContentException>()
            .having((e) => e.kind, 'kind', ContentFailure.conflict)),
      );
    });

    test('a 403 arrives as forbidden, so the screen can point at Ajustes',
        () async {
      final gateway = gatewayFor(
        const Authorisation(signedIn: true, email: 'a@uv.es', role: 'owner'),
        client: MockClient((_) async => http.Response(
              jsonEncode({'error': 'role reader may not write x'}),
              403,
              headers: {'content-type': 'application/json'},
            )),
      );
      await expectLater(
        gateway.read('content/a/es.tex'),
        throwsA(isA<ContentException>()
            .having((e) => e.kind, 'kind', ContentFailure.forbidden)),
      );
    });

    test('a read returns the sha, which a later write needs', () async {
      final gateway = gatewayFor(
        const Authorisation(signedIn: true, email: 'a@uv.es', role: 'owner'),
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'path': 'content/a/es.tex',
                'text': 'contenido',
                'sha': 'abc123',
              }),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );
      final file = await gateway.read('content/a/es.tex');
      expect(file.text, 'contenido');
      // Without this a write cannot be a compare-and-set.
      expect(file.sha, 'abc123');
    });
  });

  group('DirectGateway', () {
    DirectGateway gatewayFor({http.Client? client}) => DirectGateway(
          github: GitHubDirect(
            owner: 'franjfal',
            repo: 'didacta_db',
            branch: 'main',
            token: 'x',
            client: client,
          ),
          author: (name: 'Javier', email: 'javier@uv.es'),
        );

    test('a stored token means writing is possible', () {
      // No policy consultation: a token that can write the repository can
      // write all of it, and pretending otherwise in the interface would be
      // theatre.
      expect(gatewayFor().canWrite, isTrue);
      expect(gatewayFor().kind, GatewayKind.direct);
    });

    test('says where writes go, branch included', () {
      final described = gatewayFor().describe();
      expect(described, contains('franjfal/didacta_db'));
      expect(described, contains('main'));
      expect(described, contains('javier@uv.es'));
    });

    test('a conflict from GitHub arrives as a conflict', () async {
      final gateway = gatewayFor(
        client: MockClient((_) async => http.Response('{}', 409)),
      );
      await expectLater(
        gateway.commit(
            path: 'content/a/es.tex', text: 'x', sha: 'stale', message: 'm'),
        throwsA(isA<ContentException>()
            .having((e) => e.kind, 'kind', ContentFailure.conflict)),
      );
    });

    test('a commit is attributed to the author', () async {
      http.Request? sent;
      final gateway = gatewayFor(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'commit': {'sha': 'newsha'},
              'content': {'sha': 'blob'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final sha = await gateway.commit(
        path: 'content/a/va.tex',
        text: 'nou',
        sha: 'old',
        message: 'Traducir al valenciano',
      );
      expect(sha, 'newsha');
      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      expect((body['author'] as Map)['email'], 'javier@uv.es');
      expect(body['message'], 'Traducir al valenciano');
    });
  });
}
