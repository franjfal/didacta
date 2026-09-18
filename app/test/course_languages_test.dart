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

import 'package:didacta_app/data/app_info.dart';
import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/release_channel.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/edit_course.dart';
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
  String? degree,
}) => {
  'id': 'am-i',
  'title': const {'es': 'Análisis Matemático I'},
  'language': 'es',
  'languages': languages,
  'degreeId': degree,
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
    FakeGateway(writable: writable, files: {'courses/am-i/course.yaml': yaml});

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
  openChannel: () => ReleaseChannel(owner: 'franjfal', repo: 'didacta'),
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
        expect(
          gateway.commits.single.text,
          contains('languages: [es, va, en]'),
        );
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
        languages: const ['en', 'es', 'va'],
      );

      expect(gateway.commits.single.text, contains('languages: [es, va, en]'));
    });

    test('un idioma que el repositorio no mantiene no se escribe', () async {
      // Esto se hacía al revés: se escribía lo que se pidiera y se dejaba que
      // el motor se quejara. El problema es **cómo** se queja: rechaza el
      // `course.yaml` entero, así que la asignatura desaparece de la
      // biblioteca y el motivo queda en una lista de errores que nadie mira.
      // Un idioma que no se puede escribir se deja fuera aquí.
      final gateway = repoGateway();
      final session = await sessionWith({'x/uno': gateway});

      await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es', 'fr'],
      );

      expect(gateway.commits.single.text, contains('languages: [es]'));
      expect(gateway.commits.single.text, isNot(contains('fr')));
    });

    test('cada repositorio recibe lo suyo, no la lista entera', () async {
      // Una asignatura repartida entre un repositorio que mantiene castellano
      // y valenciano y otro que mantiene castellano e inglés se da en los
      // tres, cada uno con el material que tiene. Escribir los tres en los dos
      // ficheros --que es lo que se hacía-- deja los dos inválidos.
      // Los dos ficheros empiezan diciendo solo castellano, para que los dos
      // tengan algo que cambiar y se vea qué recibe cada uno.
      final soloEs = courseYaml.replaceAll(
        'languages: [es, va]',
        'languages: [es]',
      );
      final teoria = repoGateway(yaml: soloEs);
      final practica = repoGateway(yaml: soloEs);
      final catalogue = Catalogue.merge([
        // Cada índice dice lo que dice su fichero: solo castellano. Un
        // `course.yaml` que declarara un idioma que su repositorio no
        // mantiene no existe, porque el motor lo rechaza al indexar.
        catalogueWith(
          const [],
          courses: [
            courseWith(languages: const ['es']),
          ],
          repo: 'x/teoria',
          languages: const ['es', 'va'],
        ),
        catalogueWith(
          const [],
          courses: [
            courseWith(languages: const ['es']),
          ],
          repo: 'x/practica',
          languages: const ['es', 'en'],
        ),
      ]);
      final session = PerRepoSession(
        gateways: {'x/teoria': teoria, 'x/practica': practica},
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);

      final written = await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es', 'va', 'en'],
      );

      expect(written, 2);
      expect(teoria.commits.single.text, contains('languages: [es, va]'));
      expect(practica.commits.single.text, contains('languages: [es, en]'));
    });

    test('lo que el fichero ya dice no se poda al guardar', () async {
      // Un `course.yaml` con un idioma que el índice no conoce --porque está
      // viejo-- no es motivo para quitárselo: esta pantalla venía a cambiar
      // otra cosa, y podar en silencio lo que no se entiende es cómo se
      // pierde el trabajo de otra persona.
      final gateway = repoGateway(
        yaml: courseYaml.replaceAll(
          'languages: [es, va]',
          'languages: [es, zz]',
        ),
      );
      final catalogue = Catalogue.merge([
        catalogueWith(
          const [],
          courses: [
            courseWith(languages: const ['es', 'zz']),
          ],
          repo: 'x/uno',
        ),
      ]);
      final session = PerRepoSession(
        gateways: {'x/uno': gateway},
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);

      await session.setCourseLanguages(
        course: 'am-i',
        languages: const ['es', 'va', 'zz'],
      );

      expect(gateway.commits.single.text, contains('zz'));
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

      await session.setCourseLanguages(course: 'am-i', languages: const ['es']);

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

  group('la ficha de la asignatura', () {
    /// Abre la ficha y deja a mano lo que devuelva al cerrarse.
    ///
    /// En una caja y no como valor de retorno: cuando `show` acaba el diálogo
    /// está abierto, no cerrado, así que la respuesta llega después --al
    /// pulsar Guardar-- y hay que poder leerla entonces.
    Future<List<CourseEdit?>> show(
      WidgetTester tester,
      Course course, {
      List<Degree> degrees = const [],
    }) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final answer = <CourseEdit?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => answer.add(
                  await editCourse(
                    context,
                    course: course,
                    options: const [
                      LanguageOption(code: 'es', name: 'Castellano'),
                      LanguageOption(code: 'va', name: 'Valencià'),
                      LanguageOption(code: 'en', name: 'English'),
                    ],
                    degrees: degrees,
                    language: 'es',
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await settle(tester);
      return answer;
    }

    Course course({
      List<String> languages = const ['es', 'va'],
      String? degree,
    }) => catalogueWith(
      const [],
      courses: [courseWith(languages: languages, degree: degree)],
      repo: 'x/uno',
    ).courses.single;

    testWidgets('ofrece todos los idiomas, marcados los de la asignatura', (
      tester,
    ) async {
      await show(tester, course());

      // Los tres que Didacta trae, no los dos que se usan: lo que falta es
      // justamente lo que se viene a activar.
      for (final code in ['es', 'va', 'en']) {
        expect(find.byKey(Key('course-language-$code')), findsOneWidget);
      }
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('course-language-en')))
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('course-language-va')))
            .selected,
        isTrue,
      );
    });

    testWidgets('el nombre se pide solo en los idiomas de la asignatura', (
      tester,
    ) async {
      // No en los diez que Didacta trae: eso es un muro de campos vacíos que
      // además empuja la titulación fuera de la pantalla, y nueve de ellos
      // son idiomas a los que esta asignatura no se traduce.
      await show(tester, course(languages: const ['es', 'va']));

      expect(find.byKey(const Key('course-title-es')), findsOneWidget);
      expect(find.byKey(const Key('course-title-va')), findsOneWidget);
      expect(find.byKey(const Key('course-title-en')), findsNothing);
    });

    testWidgets('y aparece al marcar uno, sin cerrar y volver a abrir', (
      tester,
    ) async {
      await show(tester, course(languages: const ['es']));
      expect(find.byKey(const Key('course-title-en')), findsNothing);

      await tester.tap(find.byKey(const Key('course-language-en')));
      await settle(tester);

      expect(find.byKey(const Key('course-title-en')), findsOneWidget);
    });

    testWidgets('desmarcar uno no borra el título que ya tenía', (
      tester,
    ) async {
      // El título vive en `course.yaml` aparte de `languages:`. No haberlo
      // visto en el diálogo no es motivo para borrarlo del fichero.
      final answer = await show(tester, course(languages: const ['es', 'va']));

      await tester.tap(find.byKey(const Key('course-language-va')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('course-save')));
      await settle(tester);

      expect(answer.single!.titles.keys, ['es']);
    });

    testWidgets(
      'lo marcado sale en el orden del catálogo, no en el de los clics',
      (tester) async {
        // Para que `course.yaml` salga igual se marque como se marque, y no
        // haya diffs que solo mueven códigos de sitio.
        final answer = await show(tester, course(languages: const ['va']));

        await tester.tap(find.byKey(const Key('course-language-en')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('course-language-es')));
        await settle(tester);
        await tester.tap(find.byKey(const Key('course-save')));
        await settle(tester);

        expect(answer.single!.languages, ['es', 'va', 'en']);
      },
    );

    testWidgets('el último idioma no se puede quitar', (tester) async {
      // Una asignatura sin ningún idioma no se compila, y el motor lo
      // rechazaría al guardar.
      await show(tester, course(languages: const ['es']));

      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('course-language-es')))
            .onSelected,
        isNull,
      );
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('course-language-en')))
            .onSelected,
        isNotNull,
      );
    });

    testWidgets('el grado se elige de los declarados', (tester) async {
      final answer = await show(
        tester,
        course(degree: 'matematicas'),
        degrees: const [
          Degree(id: 'matematicas', titles: {'es': 'Grado en Matemáticas'}),
          Degree(id: 'fisica', titles: {'es': 'Grado en Física'}),
        ],
      );

      expect(find.text('Grado en Matemáticas'), findsWidgets);
      await tester.tap(find.byKey(const Key('course-save')));
      await settle(tester);
      expect(answer.single!.degree, 'matematicas');
    });

    testWidgets('y se puede dejar sin ninguno', (tester) async {
      // No todo lo que se da pertenece a una titulación, y obligar a elegir
      // una inventaría grados para no dejar huecos.
      final answer = await show(
        tester,
        course(),
        degrees: const [
          Degree(id: 'matematicas', titles: {'es': 'Grado en Matemáticas'}),
        ],
      );

      await tester.tap(find.byKey(const Key('course-save')));
      await settle(tester);
      expect(answer.single!.degree, isNull);
    });

    testWidgets('un grado que no declara nadie se avisa', (tester) async {
      // No es un error --la asignatura se ve entera, sin agrupar-- pero al
      // guardar se perdería el id, así que se dice antes.
      await show(tester, course(degree: 'inventado'));
      expect(
        find.textContaining('no declara ningún repositorio'),
        findsOneWidget,
      );
    });
  });
}
