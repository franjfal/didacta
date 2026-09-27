/// Entrar con la GitHub App: una credencial que caduca a las ocho horas y se
/// renueva sola, sin que dejen de valer las sesiones de antes.
///
/// Todo contra un GitHub de mentira y con la hora en la mano: lo que se
/// prueba es qué se guarda, cuándo se renueva y qué pasa cuando no se puede.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:didacta_app/data/github.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/github_credential.dart';
import 'package:didacta_app/state/auth_state.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

final DateTime noon = DateTime.utc(2026, 9, 27, 12);

GitHubCredential appCredential({
  required DateTime issued,
  String token = 'ghu_uno',
}) => GitHubCredential(
  token: token,
  refreshToken: 'ghr_renovar',
  expires: issued.add(const Duration(hours: 8)),
  refreshExpires: issued.add(const Duration(days: 180)),
  clientId: 'Iv23liApp',
);

void main() {
  group('la credencial', () {
    test(
      'la de antes, un token suelto, se sigue leyendo y guardando igual',
      () {
        final old = GitHubCredential.decode('gho_de_siempre');
        expect(old.token, 'gho_de_siempre');
        expect(old.renewable, isFalse);
        expect(old.fromApp, isFalse);
        // Y se guarda como estaba: una versión anterior la sigue leyendo.
        expect(old.encode(), 'gho_de_siempre');
      },
    );

    test('la de la App va y vuelve entera', () {
      final saved = appCredential(issued: noon).encode();
      expect(jsonDecode(saved), isA<Map<String, dynamic>>());
      final back = GitHubCredential.decode(saved);
      expect(back.token, 'ghu_uno');
      expect(back.refreshToken, 'ghr_renovar');
      expect(back.expires, noon.add(const Duration(hours: 8)));
      expect(back.clientId, 'Iv23liApp');
      expect(back.fromApp, isTrue);
    });

    test('se renueva quince minutos antes de caducar, no antes', () {
      final credential = appCredential(issued: noon);
      expect(credential.dueAt(noon.add(const Duration(hours: 7))), isFalse);
      expect(
        credential.dueAt(noon.add(const Duration(hours: 7, minutes: 46))),
        isTrue,
      );
      expect(credential.dueAt(noon.add(const Duration(days: 2))), isTrue);
    });

    test('lo que devuelve GitHub, con las fechas desde ahora', () {
      final credential = GitHubCredential.fromResponse({
        'access_token': 'ghu_x',
        'refresh_token': 'ghr_y',
        'expires_in': 28800,
        'refresh_token_expires_in': 15897600,
      }, now: noon);
      expect(credential.expires, noon.add(const Duration(hours: 8)));
      expect(credential.refreshExpires, noon.add(const Duration(days: 184)));
    });
  });

  group('GitHub', () {
    test('con una App no se piden permisos al entrar', () async {
      late Map<String, String> sent;
      final auth = GitHubAuth(
        clientId: 'Iv23liApp',
        client: MockClient((request) async {
          sent = Uri.splitQueryString(request.body);
          return http.Response(
            jsonEncode({'device_code': 'd', 'user_code': 'U'}),
            200,
          );
        }),
      );
      expect(auth.isApp, isTrue);
      await auth.start();
      expect(sent.containsKey('scope'), isFalse);

      final oauth = GitHubAuth(
        clientId: 'Ov23liOAuth',
        client: MockClient((request) async {
          sent = Uri.splitQueryString(request.body);
          return http.Response(jsonEncode({'device_code': 'd'}), 200);
        }),
      );
      await oauth.start();
      expect(sent['scope'], 'repo workflow');
    });

    test('al entrar devuelve la credencial entera', () async {
      final auth = GitHubAuth(
        clientId: 'Iv23liApp',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'access_token': 'ghu_x',
              'refresh_token': 'ghr_y',
              'expires_in': 28800,
            }),
            200,
          ),
        ),
      );
      final credential = await auth.waitForCredential(
        const DeviceCode(
          userCode: 'A',
          deviceCode: 'B',
          verificationUri: 'https://github.com/login/device',
          interval: 1,
          expiresIn: 60,
        ),
        sleep: (_) async {},
        now: () => noon,
      );
      expect(credential.renewable, isTrue);
      expect(credential.clientId, 'Iv23liApp');
    });

    test('renovar: sin secreto, y con el de renovar', () async {
      late Map<String, String> sent;
      final auth = GitHubAuth(
        clientId: 'Iv23liApp',
        client: MockClient((request) async {
          sent = Uri.splitQueryString(request.body);
          return http.Response(
            jsonEncode({
              'access_token': 'ghu_nuevo',
              'refresh_token': 'ghr_nuevo',
              'expires_in': 28800,
            }),
            200,
          );
        }),
      );
      final fresh = await auth.refresh('ghr_viejo', now: () => noon);
      expect(sent['grant_type'], 'refresh_token');
      expect(sent['refresh_token'], 'ghr_viejo');
      expect(sent.containsKey('client_secret'), isFalse);
      expect(fresh.token, 'ghu_nuevo');
    });

    test('un de renovar que ya no vale es un 401: cierra la sesión', () async {
      final auth = GitHubAuth(
        clientId: 'Iv23liApp',
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode({'error': 'bad_refresh_token'}), 200),
        ),
      );
      await expectLater(
        auth.refresh('ghr_viejo'),
        throwsA(
          isA<GitHubException>().having(
            (error) => error.rejectsCredential,
            'rejectsCredential',
            isTrue,
          ),
        ),
      );
    });
  });

  group('la sesión', () {
    AuthState make(
      StubStore store, {
      required DateTime Function() now,
      required Future<GitHubCredential> Function(GitHubCredential) renew,
      List<String>? asked,
      void Function()? rejected,
    }) => AuthState(
      tokenStore: store,
      preferences: MemoryPreferences(),
      whoIs: (token) async {
        asked?.add(token);
        return testUser;
      },
      onRejected: () async => rejected?.call(),
      renew: renew,
      now: now,
    );

    test('caducada mientras Didacta estaba cerrada: se renueva antes de '
        'preguntar quién es', () async {
      final store = StubStore(token: appCredential(issued: noon).encode());
      final asked = <String>[];
      final auth = make(
        store,
        now: () => noon.add(const Duration(days: 1)),
        renew: (old) async => appCredential(
          issued: noon.add(const Duration(days: 1)),
          token: 'ghu_dos',
        ),
        asked: asked,
      );
      auth.token = await auth.readToken();
      await auth.resolve();
      addTearDown(auth.dispose);

      expect(auth.state, SignInState.signedIn);
      expect(auth.token, 'ghu_dos');
      expect(asked, ['ghu_dos']);
      // Y la nueva, guardada: el próximo arranque no la vuelve a pedir.
      expect(GitHubCredential.decode(store.token!).token, 'ghu_dos');
    });

    test('si GitHub ya no acepta el de renovar, se sale y se dice', () async {
      final store = StubStore(token: appCredential(issued: noon).encode());
      var rejected = 0;
      final auth = make(
        store,
        now: () => noon.add(const Duration(days: 1)),
        renew: (old) async =>
            throw const GitHubException('caducada', status: 401),
        rejected: () => rejected += 1,
      );
      auth.token = await auth.readToken();
      expect(await auth.renewIfDue(), isFalse);

      expect(auth.state, SignInState.signedOut);
      expect(store.token, isNull);
      expect(auth.problem, isA<GitHubException>());
      expect(rejected, 1);
    });

    test('sin red, se sigue con la que hay', () async {
      final store = StubStore(token: appCredential(issued: noon).encode());
      final auth = make(
        store,
        now: () => noon.add(const Duration(days: 1)),
        renew: (old) async => throw const GitHubException('sin red'),
      );
      auth.token = await auth.readToken();
      auth.state = SignInState.signedIn;
      expect(await auth.renewIfDue(), isFalse);
      auth.dispose();

      expect(auth.state, SignInState.signedIn);
      expect(auth.token, 'ghu_uno');
      expect(store.token, isNotNull);
    });

    test('lo que hay en el llavero nunca sale tal cual como token', () async {
      final store = StubStore(token: appCredential(issued: noon).encode());
      final auth = make(store, now: () => noon, renew: (old) async => old);
      expect(await auth.storedToken(), 'ghu_uno');
    });
  });

  group('el Client ID', () {
    StoredPreferences stored() => StoredPreferences(
      defaultClonePath: '',
      defaultEnginePath: '',
      defaultClientId: 'Iv23liApp',
      replacedClientIds: const ['Ov23liViejo'],
    );

    test(
      'el de la OAuth App guardado al entrar deja paso al de la App',
      () async {
        // Lo que hace `main.dart` cuando hay GitHub App: el Client ID que se
        // guardó por ser el de salida no se respeta como si se hubiera elegido.
        SharedPreferences.setMockInitialValues({
          'didacta.github.clientId': 'Ov23liViejo',
        });
        expect(await stored().githubClientId(), 'Iv23liApp');
      },
    );

    test('uno propio, sí', () async {
      SharedPreferences.setMockInitialValues({
        'didacta.github.clientId': 'Iv23liMio',
      });
      expect(await stored().githubClientId(), 'Iv23liMio');
    });
  });

  group('los repositorios', () {
    test('con la App, uno al que no llega no se cierra: se dice dónde dar '
        'acceso', () async {
      final session = _Unreachable();
      await session.useClonesForTest(['/tmp/didacta-app-test']);
      session.auth.credential = appCredential(issued: noon);

      await session.repositories.dropUnreachable();

      expect(session.openedWorkspace.repos, hasLength(1));
      final problem = session.accessProblem;
      expect(problem, isA<AppAccessMissing>());
      expect('$problem', contains('github.com/apps/'));
    });

    test('con un token de antes, sí: la cuenta no llega', () async {
      final session = _Unreachable();
      await session.useClonesForTest(['/tmp/didacta-app-test']);
      session.auth.credential = const GitHubCredential(token: 'gho_viejo');

      await session.repositories.dropUnreachable();

      expect(session.openedWorkspace.repos, isEmpty);
    });
  });
}

/// Una sesión a la que GitHub no deja llegar a ningún repositorio.
class _Unreachable extends FakeSession {
  _Unreachable()
    : super(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );

  @override
  Future<GitHubRepo?> accessTo(String owner, String name) async => null;
}
