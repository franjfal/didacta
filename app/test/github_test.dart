/// Entrar en GitHub y preguntarle lo que hace falta.
///
/// Todo contra un cliente falso: lo que se prueba es el trato con la API --que
/// se espera al ritmo que pide, que un error se cuenta como lo que es, que un
/// correo oculto no acaba en un commit sin atribuir-- y eso no necesita red.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:didacta_app/data/github.dart';

/// Un cliente que responde lo que se le diga, en orden.
MockClient responding(List<Object> replies) {
  var at = 0;
  return MockClient((request) async {
    final reply = replies[at.clamp(0, replies.length - 1)];
    at += 1;
    if (reply is Map) return http.Response(jsonEncode(reply), 200);
    if (reply is int) return http.Response('{}', reply);
    return http.Response(reply.toString(), 200);
  });
}

void main() {
  group('el sign in', () {
    test('devuelve el código que se le enseña a la persona', () async {
      final auth = GitHubAuth(
        clientId: 'Iv1.abc',
        client: responding([
          {
            'device_code': 'secreto',
            'user_code': 'ABCD-1234',
            'verification_uri': 'https://github.com/login/device',
            'expires_in': 900,
            'interval': 5,
          },
        ]),
      );
      final code = await auth.start();
      expect(code.userCode, 'ABCD-1234');
      expect(code.verificationUri, 'https://github.com/login/device');
    });

    test('un Client ID que no vale se dice, no se traga', () async {
      final auth = GitHubAuth(
        clientId: 'nada',
        client: responding([
          {'error': 'invalid_client'},
        ]),
      );
      await expectLater(
        auth.start(),
        throwsA(
          isA<GitHubException>().having(
            (each) => each.message,
            'message',
            contains('Client ID'),
          ),
        ),
      );
    });

    test('espera mientras la persona no ha autorizado', () async {
      final auth = GitHubAuth(
        clientId: 'Iv1.abc',
        client: responding([
          {'error': 'authorization_pending'},
          {'error': 'authorization_pending'},
          {'access_token': 'gho_token'},
        ]),
      );
      final waits = <Duration>[];
      final token = await auth.waitForToken(
        const DeviceCode(
          userCode: 'A',
          deviceCode: 'B',
          verificationUri: 'C',
          interval: 5,
          expiresIn: 900,
        ),
        sleep: (each) async => waits.add(each),
      );
      expect(token, 'gho_token');
      expect(waits.length, 3);
      // Al ritmo que pide GitHub, ni más deprisa.
      expect(waits.every((each) => each.inSeconds >= 5), isTrue);
    });

    test('un slow_down se obedece', () async {
      final auth = GitHubAuth(
        clientId: 'Iv1.abc',
        client: responding([
          {'error': 'slow_down'},
          {'access_token': 'gho_token'},
        ]),
      );
      final waits = <Duration>[];
      await auth.waitForToken(
        const DeviceCode(
          userCode: 'A',
          deviceCode: 'B',
          verificationUri: 'C',
          interval: 5,
          expiresIn: 900,
        ),
        sleep: (each) async => waits.add(each),
      );
      // Preguntar más deprisa de lo que dice es cómo se acaba bloqueado a
      // mitad de un sign in.
      expect(waits.last.inSeconds, 10);
    });

    test('un código caducado se cuenta como lo que es', () async {
      final auth = GitHubAuth(
        clientId: 'Iv1.abc',
        client: responding([
          {'error': 'expired_token'},
        ]),
      );
      await expectLater(
        auth.waitForToken(
          const DeviceCode(
            userCode: 'A',
            deviceCode: 'B',
            verificationUri: 'C',
            interval: 1,
            expiresIn: 900,
          ),
          sleep: (_) async {},
        ),
        throwsA(isA<GitHubException>()),
      );
    });
  });

  group('la API', () {
    test('quién ha entrado, para firmar los commits', () async {
      final api = GitHubApi(
        token: 't',
        client: responding([
          {'login': 'franjfal', 'name': 'Javier', 'email': null},
        ]),
      );
      final user = await api.me();
      expect(user.authorName, 'Javier');
      // Sin correo visible, el `noreply` suyo: un correo inventado deja el
      // commit sin atribuir a nadie.
      expect(user.authorEmail, 'franjfal@users.noreply.github.com');
    });

    test('los repositorios vienen con si se puede escribir en ellos', () async {
      final api = GitHubApi(
        token: 't',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer t');
          return http.Response(
            jsonEncode([
              {
                'name': 'didacta_db',
                'owner': {'login': 'franjfal'},
                'default_branch': 'main',
                'private': true,
                'permissions': {'push': true},
              },
              {
                'name': 'ajeno',
                'owner': {'login': 'otro'},
                'default_branch': 'master',
                'private': false,
                'permissions': {'push': false},
              },
            ]),
            200,
          );
        }),
      );
      final repos = await api.repositories();
      expect(
        [for (final repo in repos) repo.id],
        ['franjfal/didacta_db', 'otro/ajeno'],
      );
      expect(repos.first.canWrite, isTrue);
      expect(repos.last.canWrite, isFalse);
      expect(repos.last.defaultBranch, 'master');
    });

    test('un repositorio es de Didacta si tiene didacta.yaml', () async {
      final yes = GitHubApi(token: 't', client: responding([200]));
      final no = GitHubApi(token: 't', client: responding([404]));
      expect(await yes.isContentRepo('x', 'y'), isTrue);
      expect(await no.isContentRepo('x', 'y'), isFalse);
    });

    test('una sesión que ya no vale se dice', () async {
      final api = GitHubApi(token: 'viejo', client: responding([401]));
      await expectLater(api.me(), throwsA(isA<GitHubException>()));
    });
  });
}
