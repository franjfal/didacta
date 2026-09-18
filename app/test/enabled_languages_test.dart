/// Con qué idiomas se trabaja, y hasta dónde llega esa decisión.
///
/// Hay tres listas de idiomas y confundirlas era el fallo. Didacta sabe
/// imprimir en diez; un repositorio traduce a los que diga su `didacta.yaml`;
/// una persona trabaja con los que le interesen. La barra de arriba ofrecía
/// los **diez**, así que se podía elegir un idioma al que ningún repositorio
/// traduce y dejar la aplicación entera enseñando el texto de reserva sin
/// nada que hacer desde ahí.
///
/// La regla que se fija aquí es una sola: se ofrece lo que hay en el material
/// cruzado con lo encendido, **más lo que el sitio que se está mirando ya
/// declara**. Lo último es lo que impide que apagar un idioma en Ajustes lo
/// borre de un fichero al guardar, que sería convertir una preferencia de
/// lectura en una edición del material de otra persona.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/synced_prefs.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/edit_course.dart';
import 'package:didacta_app/ui/sync_bar.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> course({List<String> languages = const ['es', 'va']}) => {
  'id': 'am-i',
  'title': const {'es': 'Análisis Matemático I'},
  'language': 'es',
  'languages': languages,
  'years': const <String, dynamic>{},
};

/// Un espacio de trabajo que traduce a castellano, valenciano e inglés, y en
/// el que Didacta sabe imprimir a seis.
Future<FakeSession> workspace({
  List<Map<String, dynamic>> courses = const [],
  List<String> languages = const ['es', 'va', 'en'],
}) async {
  final catalogue = catalogueWith(
    const [],
    courses: courses.isEmpty ? [course()] : courses,
    repo: 'test/repo',
    languages: languages,
  );
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
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
  group('lo que ofrece la barra', () {
    testWidgets('son los del material, no los diez del registro', (
      tester,
    ) async {
      // El fallo tal cual se veía: el desplegable traía Français y Deutsch,
      // a los que este espacio de trabajo no traduce una sola línea.
      final session = await workspace();
      await pump(tester, session, SyncBar(session: session));

      await tester.tap(find.byKey(const Key('language-picker')));
      await settle(tester);

      expect(find.byKey(const Key('pick-language-es')), findsOneWidget);
      expect(find.byKey(const Key('pick-language-va')), findsOneWidget);
      expect(find.byKey(const Key('pick-language-en')), findsOneWidget);
      expect(find.byKey(const Key('pick-language-fr')), findsNothing);
      expect(find.byKey(const Key('pick-language-de')), findsNothing);
    });

    testWidgets('y se encogen al apagar uno en Ajustes', (tester) async {
      final session = await workspace();
      await session.setLanguageEnabled('en', false);
      await pump(tester, session, SyncBar(session: session));

      await tester.tap(find.byKey(const Key('language-picker')));
      await settle(tester);

      expect(find.byKey(const Key('pick-language-es')), findsOneWidget);
      expect(find.byKey(const Key('pick-language-va')), findsOneWidget);
      expect(find.byKey(const Key('pick-language-en')), findsNothing);
    });
  });

  group('apagar un idioma', () {
    test('no puede dejar la sesión mirando uno que ya no se ofrece', () async {
      // Si no, la barra enseña «English» y su propio menú no lo tiene: no hay
      // forma de volver salvo adivinando que hay que encenderlo otra vez.
      final session = await workspace();
      session.language = 'en';

      await session.setLanguageEnabled('en', false);

      expect(session.language, isNot('en'));
      expect(
        session.languageChoices.map((option) => option.code),
        contains(session.language),
      );
    });

    test('apagarlos todos es no filtrar, no quedarse sin ninguno', () async {
      // Una aplicación sin ningún idioma no puede enseñar una línea de
      // material, así que el conjunto vacío significa «todos».
      final session = await workspace();
      for (final code in ['es', 'va', 'en']) {
        await session.setLanguageEnabled(code, false);
      }

      expect(session.languageChoices.map((o) => o.code), ['es', 'va', 'en']);
    });

    test('se guarda con las preferencias que viajan', () async {
      // Trabajar en castellano y valenciano es una decisión de la persona, no
      // de la máquina: quien la toma en el despacho la quiere en casa.
      final session = await workspace();
      await session.setLanguageEnabled('en', false);

      final back = SyncedPrefs.fromJson(session.syncedPrefs.toJson());
      expect(back.isLanguageEnabled('en'), isFalse);
      expect(back.isLanguageEnabled('es'), isTrue);
    });
  });

  group('la ficha de una asignatura', () {
    testWidgets('no ofrece un idioma que su repositorio no mantiene', (
      tester,
    ) async {
      // Es lo que producía un `course.yaml` que el motor rechaza, y una
      // asignatura rechazada desaparece de la biblioteca: el fallo no se veía
      // al guardar sino al volver a indexar.
      final session = await workspace();
      final entry = session.catalogue.courses.single;

      final options = session.languagesToEdit(
        allowed: session.catalogue.languagesAvailableTo(entry),
        declared: entry.languages,
      );

      expect(options.map((o) => o.code), ['es', 'va', 'en']);
      expect(options.map((o) => o.code), isNot(contains('fr')));
    });

    testWidgets('pero sí uno apagado que la asignatura ya declara', (
      tester,
    ) async {
      // Esconderlo sería quitárselo al guardar, y nadie ha pedido eso: apagar
      // un idioma en Ajustes es dejar de mirarlo.
      final session = await workspace(
        courses: [
          course(languages: const ['es', 'va', 'en']),
        ],
      );
      await session.setLanguageEnabled('en', false);
      final entry = session.catalogue.courses.single;

      final options = session.languagesToEdit(
        allowed: session.catalogue.languagesAvailableTo(entry),
        declared: entry.languages,
      );

      expect(options.map((o) => o.code), contains('en'));
      // Y no se cuela en la barra, que es de lectura y no escribe nada.
      expect(session.languageChoices.map((o) => o.code), isNot(contains('en')));
    });

    testWidgets('guardar con uno apagado no se lo quita', (tester) async {
      // La prueba de que la unión de arriba sirve para algo: se abre la ficha
      // con el inglés apagado, se toca otra cosa y el inglés sigue.
      final session = await workspace(
        courses: [
          course(languages: const ['es', 'va', 'en']),
        ],
      );
      await session.setLanguageEnabled('en', false);
      final entry = session.catalogue.courses.single;

      CourseEdit? answer;
      await pump(
        tester,
        session,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await editCourse(
                context,
                course: entry,
                options: session.languagesToEdit(
                  allowed: session.catalogue.languagesAvailableTo(entry),
                  declared: entry.languages,
                ),
                degrees: session.catalogue.degrees,
                language: 'es',
              );
            },
            child: const Text('abrir'),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('course-save')));
      await settle(tester);

      expect(answer?.languages, containsAll(['es', 'va', 'en']));
    });
  });

  group('los idiomas de una asignatura', () {
    test('son los suyos cruzados con los de su repositorio', () async {
      // El índice puede estar viejo y un repositorio apagado se lleva sus
      // idiomas con él: lo que se ofrece para compilar tiene que ser lo que
      // hay ahora.
      final session = await workspace(
        courses: [
          course(languages: const ['es', 'va', 'en']),
        ],
        languages: const ['es', 'va'],
      );

      expect(
        session.catalogue.languagesForCourse(session.catalogue.courses.single),
        ['es', 'va'],
      );
    });

    test('una que no declara ninguno se da en los de su repositorio', () async {
      final session = await workspace(courses: [course(languages: const [])]);

      expect(
        session.catalogue.languagesForCourse(session.catalogue.courses.single),
        ['es', 'va', 'en'],
      );
    });
  });
}
