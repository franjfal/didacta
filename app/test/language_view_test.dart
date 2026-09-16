/// El idioma en el que se mira el contenido, y qué cambia al cambiarlo.
///
/// No es el idioma de la aplicación --sus textos están en castellano-- sino el
/// del contenido. Estaba escondido en la biblioteca, y desde la lista de
/// asignaturas no había forma de tocarlo: los títulos salían siempre en el
/// idioma propio de cada asignatura aunque se estuviera preparando la versión
/// en valenciano, que es cuando hace falta verlos en valenciano.
///
/// Así que sube a la barra de arriba, delante de traer y enviar, y manda sobre
/// lo que se lee: el título de la asignatura, el del tema y el de cada
/// documento.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/courses_page.dart';
import 'package:didacta_app/ui/sync_bar.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Una asignatura con título en dos idiomas y un tema con los dos también.
Map<String, dynamic> bilingual() => {
  'id': 'am-i',
  'title': const {'es': 'Análisis Matemático I', 'va': 'Anàlisi Matemàtica I'},
  'language': 'es',
  'languages': const ['es', 'va'],
  'years': {
    '2026-2027': {
      'year': '2026-2027',
      'language': 'es',
      'themes': const [
        {
          'id': 'tema-1',
          'title': {'es': 'Los números reales', 'va': 'Els nombres reals'},
        },
      ],
      'documents': [
        {
          'id': 'tema-1-teoria',
          'kind': 'theory',
          'language': 'es',
          'title': const {'es': 'Teoría del tema 1', 'va': 'Teoria del tema 1'},
          'themes': const ['tema-1'],
          'profiles': const ['notes'],
          'unitRefs': const <String>[],
        },
      ],
    },
  },
};

Future<FakeSession> bilingualSession({String language = 'es'}) async {
  final catalogue = catalogueWith(const [], courses: [bilingual()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  // La barra superior no se dibuja sin repositorios: sin espacio de trabajo
  // no hay nada que traer, que enviar ni que filtrar.
  await session.useCloneForTest('/tmp/didacta-test');
  session.language = language;
  return session;
}

Future<void> pump(WidgetTester tester, Session session, Widget page) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  group('lo que se lee sigue al idioma', () {
    testWidgets('el título de la asignatura', (tester) async {
      final session = await bilingualSession(language: 'va');
      await pump(tester, session, const CoursesPage());

      expect(find.text('Anàlisi Matemàtica I'), findsOneWidget);
      expect(find.text('Análisis Matemático I'), findsNothing);
    });

    testWidgets('y vuelve al cambiar de idioma', (tester) async {
      final session = await bilingualSession();
      await pump(tester, session, const CoursesPage());
      expect(find.text('Análisis Matemático I'), findsOneWidget);

      session.language = 'va';
      await settle(tester);

      expect(find.text('Anàlisi Matemàtica I'), findsOneWidget);
    });

    test('el orden de las asignaturas es el de sus títulos de hoy', () async {
      // Ordenar por el título en castellano una lista que se está leyendo en
      // valenciano pone la A detrás de la Z sin motivo visible.
      Map<String, dynamic> named(String id, String es, String va) => {
        'id': id,
        'title': {'es': es, 'va': va},
        'language': 'es',
        'years': const <String, dynamic>{},
      };
      final catalogue = catalogueWith(
        const [],
        courses: [named('uno', 'Zeta', 'Alfa'), named('dos', 'Alfa', 'Zeta')],
      );
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);

      expect(session.sortedCourses.map((c) => c.id), ['dos', 'uno']);
      session.language = 'va';
      expect(session.sortedCourses.map((c) => c.id), ['uno', 'dos']);
    });
  });

  group('el selector de la barra', () {
    testWidgets('está, y dice en cuál se está', (tester) async {
      final session = await bilingualSession(language: 'va');
      await pump(tester, session, SyncBar(session: session));

      expect(find.byKey(const Key('language-picker')), findsOneWidget);
      expect(find.text('Valencià'), findsOneWidget);
    });

    testWidgets('elegir otro cambia el de la sesión', (tester) async {
      final session = await bilingualSession();
      await pump(tester, session, SyncBar(session: session));

      await tester.tap(find.byKey(const Key('language-picker')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('pick-language-va')));
      await settle(tester);

      expect(session.language, 'va');
    });

    testWidgets('va delante de traer y enviar', (tester) async {
      // Es una preferencia de lectura, no una operación sobre git: pegada a
      // los dos botones que sí tocan el repositorio se pulsa por error.
      final session = await bilingualSession();
      await pump(tester, session, SyncBar(session: session));

      final picker = tester.getTopLeft(
        find.byKey(const Key('language-picker')),
      );
      final pull = tester.getTopLeft(find.byKey(const Key('sync-pull')));
      expect(picker.dx, lessThan(pull.dx));
    });

    testWidgets('con un solo idioma no aparece', (tester) async {
      final wide = catalogueWith(const [], courses: [courseJson()]);
      final one = Catalogue(
        name: wide.name,
        languages: const ['es'],
        available: const [LanguageOption(code: 'es', name: 'Castellano')],
        defaultLanguage: 'es',
        contentHash: wide.contentHash,
        units: wide.units,
        courses: wide.courses,
        profiles: wide.profiles,
        errors: wide.errors,
      );
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: one,
      );
      await session.primeForTest(one);
      await session.useCloneForTest('/tmp/didacta-test');
      await pump(tester, session, SyncBar(session: session));

      expect(find.byKey(const Key('language-picker')), findsNothing);
    });
  });
}
