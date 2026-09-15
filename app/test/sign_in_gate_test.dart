/// Sin sesión de GitHub no hay aplicación.
///
/// Lo que se comprueba aquí es la regla y sus bordes, que es donde una puerta
/// se rompe: que sin credencial no se llega a la biblioteca, que **con
/// credencial y sin red sí** --un aula sin wifi no puede dejar a nadie sin sus
/// diapositivas--, que un token que GitHub rechaza echa y lo dice, y que
/// mientras se lee el llavero no se enseña la puerta por un parpadeo.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/github.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/sign_in.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Una sesión cuyo `whoIs` contesta lo que diga el test.
class _Session extends Session {
  _Session({required super.tokenStore, required super.preferences, this.answer})
    : super(
        catalogueSource: StaticCatalogueSource(catalogueWith(defaultUnits())),
      );

  /// Null: GitHub no contesta. Una excepción: contesta eso.
  final Object? answer;

  int asked = 0;

  @override
  Future<GitHubUser> whoIs(String token) async {
    asked += 1;
    final reply = answer;
    if (reply == null) throw const SocketException('sin red');
    if (reply is GitHubUser) return reply;
    throw reply;
  }
}

Future<void> pump(WidgetTester tester, Session session) async {
  await tester.pumpWidget(
    DidactaApp(session: session, updates: offlineUpdates()),
  );
  await settle(tester);
}

final Finder gate = find.byType(SignInGate);

void main() {
  testWidgets('sin credencial, la aplicación no se abre', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = _Session(
      tokenStore: StubStore(token: null),
      preferences: MemoryPreferences(),
      answer: testUser,
    );
    await pump(tester, session);

    expect(gate, findsOneWidget);
    expect(session.signInState, SignInState.signedOut);
    // Y no está detrás, tapada: no se ha construido.
    expect(find.byKey(const Key('github-sign-in')), findsOneWidget);
    expect(session.asked, 0, reason: 'sin token no hay a quién preguntar');
  });

  testWidgets('con credencial, se abre', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = _Session(
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
      answer: testUser,
    );
    await pump(tester, session);

    expect(gate, findsNothing);
    expect(session.signInState, SignInState.signedIn);
    expect(session.user?.login, 'profe');
  });

  testWidgets('con credencial y sin red, se abre igual', (tester) async {
    // El caso que decide si esto sirve en un aula: lo que se exige es haber
    // entrado, no estar conectado. El trabajo está en un clon del disco y
    // LaTeX compila sin internet.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = _Session(
      tokenStore: StubStore(),
      // Con quien entró apuntado de la última vez, que es lo que hace que los
      // commits sigan saliendo con su nombre.
      preferences: MemoryPreferences(
        githubUserJson: '{"login":"profe","name":"Profe","email":"p@uv.es"}',
      ),
      answer: null,
    );
    await pump(tester, session);

    expect(gate, findsNothing);
    expect(session.signInState, SignInState.signedIn);
    expect(session.user?.login, 'profe');
    expect(session.cloneAuthor?.email, 'p@uv.es');
  });

  testWidgets('sin red y sin saber quién, se abre pero no inventa un nombre', (
    tester,
  ) async {
    // Un token de una versión anterior, que todavía no apuntaba quién era.
    // Se abre --la credencial está-- y el autor de los commits sale de git,
    // que es de donde salía antes de que existiera nada de esto.
    final session = _Session(
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
      answer: null,
    );
    await pump(tester, session);

    expect(gate, findsNothing);
    expect(session.signInState, SignInState.signedIn);
    expect(session.user, isNull);
  });

  testWidgets('un token que GitHub rechaza echa, y dice por qué', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = StubStore();
    final session = _Session(
      tokenStore: store,
      preferences: MemoryPreferences(githubUserJson: '{"login":"profe"}'),
      answer: const GitHubException(
        'GitHub no reconoce la sesión (401).',
        status: 401,
      ),
    );
    await pump(tester, session);

    expect(gate, findsOneWidget);
    expect(session.signInState, SignInState.signedOut);
    // Y la credencial que ya no vale no se queda en el llavero.
    expect(store.token, isNull);
    expect(await session.preferences.githubUser(), isNull);
    expect(find.textContaining('ha dejado de valer'), findsOneWidget);
  });

  testWidgets('un fallo de GitHub que no habla de la credencial no echa', (
    tester,
  ) async {
    // Un 500 suyo es un mal día de GitHub, no una sesión caducada. Tratarlo
    // como tal dejaría a todo el mundo fuera de su propio trabajo por algo
    // que no depende de nadie aquí.
    final store = StubStore();
    final session = _Session(
      tokenStore: store,
      preferences: MemoryPreferences(),
      answer: const GitHubException(
        'GitHub no reconoce la sesión (500).',
        status: 500,
      ),
    );
    await pump(tester, session);

    expect(gate, findsNothing);
    expect(session.signInState, SignInState.signedIn);
    expect(store.token, isNotNull);
  });

  testWidgets('salir devuelve a la puerta', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = _Session(
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
      answer: testUser,
    );
    await pump(tester, session);
    expect(gate, findsNothing);

    // Sin esperarlo: salir avisa en el acto y después habla con git y con el
    // disco, que en un test de widgets no corre. Lo que se comprueba es
    // justo eso -- que la puerta vuelve sin esperar a nada de eso.
    unawaited(session.signOut());
    await settle(tester);

    expect(gate, findsOneWidget);
  });

  test('mientras se lee el llavero, no se sabe', () {
    // El estado que evita el parpadeo: una sesión recién creada no ha
    // contestado que no, ha contestado que todavía no.
    final session = _Session(
      tokenStore: StubStore(),
      preferences: MemoryPreferences(),
      answer: testUser,
    );
    expect(session.signInState, SignInState.checking);
    expect(session.signedIn, isFalse);
  });

  test('entrar exige que GitHub conteste', () async {
    // Entrar es el único momento en el que se puede pedir que GitHub
    // conteste, y un token que no se ha comprobado ni una vez no es sesión.
    final store = StubStore(token: null);
    final session = _Session(
      tokenStore: store,
      preferences: MemoryPreferences(),
      answer: const GitHubException('no', status: 401),
    );
    await expectLater(
      session.signIn('gho_lo_que_sea'),
      throwsA(isA<GitHubException>()),
    );
    expect(store.token, isNull, reason: 'no se guarda lo que no vale');
    expect(session.signedIn, isFalse);
  });

  test('entrar apunta quién, para la próxima vez que no haya red', () async {
    final session = _Session(
      tokenStore: StubStore(token: null),
      preferences: MemoryPreferences(),
      answer: testUser,
    );
    await session.signIn('gho_bueno');

    expect(session.signedIn, isTrue);
    expect(
      GitHubUser.fromJson(await session.preferences.githubUser())?.login,
      'profe',
    );
  });
}
