/// A qué idiomas se da cada asignatura.
///
/// Didacta sabe imprimir sus rótulos en diez idiomas, pero una asignatura no
/// se da en diez. La diferencia no es cosmética: lo que está activado es lo
/// que cada unidad tiene que tener, así que activar de más convierte la lista
/// de traducciones pendientes --que es la lista de trabajo-- en ruido, y una
/// lista de trabajo que nadie mira no sirve para nada.
///
/// Dos cosas se fijan aquí. Que el cambio llegue a **todos** los repositorios
/// que declaran la asignatura, porque escribir en uno solo la deja diciendo
/// dos cosas distintas y eso es una discrepancia que hay que resolver a mano
/// después. Y que quitar un idioma no borre nada.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/app_info.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/release_channel.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

/// Nada de `pumpAndSettle`: el reloj de un test de widgets es falso, y una
/// animación que se repite lo deja girando para siempre.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

const String courseYaml = '''
id: am-i
title:
  es: Análisis Matemático I
languages: [es, va]
teacher: Javier Falcó
''';

Map<String, dynamic> courseWith({
  List<String> languages = const ['es', 'va'],
}) => {
  'id': 'am-i',
  'title': const {'es': 'Análisis Matemático I'},
  'language': 'es',
  'languages': languages,
  'years': const <String, dynamic>{},
};

/// Una sesión con una pasarela distinta por repositorio.
///
/// [FakeSession] da la misma a todos, que sirve para las pantallas pero no
/// aquí: lo que se prueba es precisamente que escribe en unos repositorios y
/// en otros no.
class PerRepoSession extends FakeSession {
  PerRepoSession({required this.gateways, required super.catalogue})
    : super(gatewayOverride: gateways.values.first);

  final Map<String, FakeGateway> gateways;

  @override
  ContentGateway gatewayFor(String? repo) =>
      gateways[repo] ?? UnconfiguredGateway('sin $repo');
}

Future<PerRepoSession> sessionWith(Map<String, FakeGateway> gateways) async {
  final catalogue = Catalogue.merge([
    for (final repo in gateways.keys)
      catalogueWith(const [], courses: [courseWith()], repo: repo),
  ]);
  final session = PerRepoSession(gateways: gateways, catalogue: catalogue);
  await session.primeForTest(catalogue);
  return session;
}

FakeGateway repoGateway({bool writable = true, String yaml = courseYaml}) =>
    FakeGateway(
      writable: writable,
      files: {'courses/am-i/course.yaml': yaml},
    );

/// El servicio de actualizaciones, sin red y sin nada que instalar.
UpdateService updates() => UpdateService(
  info: const AppInfo(
    version: AppVersion(1, 0, 0),
    platform: UpdatePlatform.macos,
    architecture: 'arm64',
    build: 1,
    packageName: 'app.didacta',
  ),
  preferences: MemoryPreferences(),
  readToken: () async => null,
  openChannel: (token) =>
      ReleaseChannel(owner: 'franjfal', repo: 'didacta_public', token: token),
);

void main() {
  group('escribir los idiomas', () {
    test('llega a todos los repositorios que declaran la asignatura', () async {
      // El caso que da sentido a todo: una asignatura partida tiene un
      // `course.yaml` en cada repositorio, y escribir en uno solo la convierte
      // en una discrepancia de metadatos inmediatamente.
      final teoria = repoGateway();
      final practica = repoGateway();
      final session = await sessionWith({
        'x/teoria': teoria,
        'x/practica': practica,
      });

      final written = await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es', 'va', 'en'],
      );

      expect(written, 2);
      for (final gateway in [teoria, practica]) {
        expect(gateway.commits.single.text, contains('languages: [es, va, en]'));
      }
    });

    test('un repositorio de solo lectura se salta', () async {
      final mio = repoGateway();
      final ajeno = repoGateway(writable: false);
      final session = await sessionWith({'x/mio': mio, 'x/ajeno': ajeno});

      final written = await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es'],
      );

      expect(written, 1);
      expect(ajeno.commits, isEmpty);
    });

    test('el orden es el del catálogo, no el de los clics', () async {
      // Para que el fichero salga igual se marque en el orden que se marque:
      // si no, cambiar de opinión dos veces deja un diff que solo mueve
      // códigos de sitio y hay que leerlo igual.
      final gateway = repoGateway();
      final session = await sessionWith({'x/uno': gateway});

      await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['fr', 'es', 'ca'],
      );

      expect(gateway.commits.single.text, contains('languages: [es, ca, fr]'));
    });

    test('un idioma que el índice no conoce se escribe igual', () async {
      // Con un índice viejo, ordenar no puede ser motivo para perder lo que
      // se ha pedido: el motor lo rechazará si de verdad no existe, y ese
      // error dice lo que pasa.
      final gateway = repoGateway();
      final session = await sessionWith({'x/uno': gateway});

      await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es', 'zz'],
      );

      expect(gateway.commits.single.text, contains('languages: [es, zz]'));
    });

    test('quedarse sin ningún idioma se rechaza', () async {
      final gateway = repoGateway();
      final session = await sessionWith({'x/uno': gateway});

      expect(
        () => session.setCourseLanguages(course: 'am-i', languages: const []),
        throwsArgumentError,
      );
      expect(gateway.commits, isEmpty);
    });

    test('no escribe cuando no hay nada que cambiar', () async {
      // Un commit que no cambia nada es ruido en el historial de otra
      // persona, y aquí es fácil provocarlo: abrir el menú y volver a marcar
      // lo que ya estaba.
      final gateway = repoGateway();
      final session = await sessionWith({'x/uno': gateway});

      final written = await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es', 'va'],
      );

      expect(written, 0);
      expect(gateway.commits, isEmpty);
    });

    test('quitar un idioma no toca ningún .tex', () async {
      final gateway = FakeGateway(
        files: {
          'courses/am-i/course.yaml': courseYaml,
          'content/a/b/va.tex': 'El texto en valenciano.',
        },
      );
      final session = await sessionWith({'x/uno': gateway});

      await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es'],
      );

      expect(gateway.commits.map((c) => c.path), ['courses/am-i/course.yaml']);
      expect(gateway.files['content/a/b/va.tex'], 'El texto en valenciano.');
    });

    test('una asignatura que no existe se dice', () async {
      final session = await sessionWith({'x/uno': repoGateway()});
      expect(
        () => session.setCourseLanguages(
          course: 'no-existe',
          languages: const ['es'],
        ),
        throwsArgumentError,
      );
    });
  });

  group('el desplegable', () {
    Future<void> show(WidgetTester tester, Session session) async {
      // Alto de sobra: los ajustes son una lista larga y perezosa, y la
      // sección de idiomas queda por debajo del pliegue en una ventana de
      // prueba del tamaño de un teléfono.
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Session>.value(value: session),
            // La página entera lleva abajo la sección de actualizaciones, que
            // pide su propio servicio. Montarla a trozos escondería que el
            // desplegable de idiomas convive con todo lo demás, que es donde
            // se usa.
            ChangeNotifierProvider<UpdateService>.value(value: updates()),
            // Y el servidor MCP, que la página ofrece encender. Sin motor
            // detrás: lo que se prueba aquí son los idiomas, y un servidor de
            // verdad levantaría un proceso.
            ChangeNotifierProvider<McpService>(
              create: (_) => McpService(
                openRunner: () => const UnavailableRunner('sin motor'),
              ),
            ),
          ],
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(body: SettingsPage()),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('ofrece todos los idiomas, marcados los de la asignatura', (
      tester,
    ) async {
      final session = await sessionWith({'x/uno': repoGateway()});
      await show(tester, session);

      await tester.tap(find.byKey(const Key('languages-am-i')));
      await settle(tester);

      // Los seis del índice, no los dos que se usan: lo que falta es
      // justamente lo que se viene a activar.
      for (final code in ['es', 'va', 'ca', 'en', 'fr', 'de']) {
        expect(find.byKey(Key('language-am-i-$code')), findsOneWidget);
      }
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.byKey(const Key('language-am-i-ca')),
            )
            .checked,
        isFalse,
      );
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.byKey(const Key('language-am-i-va')),
            )
            .checked,
        isTrue,
      );
    });

    testWidgets('marcar uno lo escribe', (tester) async {
      final gateway = repoGateway();
      final session = await sessionWith({'x/uno': gateway});
      await show(tester, session);

      await tester.tap(find.byKey(const Key('languages-am-i')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('language-am-i-fr')));
      await settle(tester);

      expect(gateway.commits.single.text, contains('languages: [es, va, fr]'));
    });

    testWidgets('el último idioma no se puede quitar', (tester) async {
      // Una asignatura sin ningún idioma no se compila, y el motor lo
      // rechazaría al guardar. Que no se pueda pulsar dice antes lo mismo.
      final catalogue = catalogueWith(
        const [],
        courses: [courseWith(languages: const ['es'])],
        repo: 'x/uno',
      );
      final session = PerRepoSession(
        gateways: {'x/uno': repoGateway()},
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await show(tester, session);

      await tester.tap(find.byKey(const Key('languages-am-i')));
      await settle(tester);

      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.byKey(const Key('language-am-i-es')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.byKey(const Key('language-am-i-fr')),
            )
            .enabled,
        isTrue,
      );
    });

    testWidgets('sin poder escribir, se ve pero no se toca', (tester) async {
      final session = await sessionWith({
        'x/ajeno': repoGateway(writable: false),
      });
      await show(tester, session);

      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const Key('languages-am-i')),
            )
            .enabled,
        isFalse,
      );
    });
  });
}
