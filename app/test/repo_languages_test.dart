/// A qué idiomas traduce un repositorio, y por qué quitar uno no es libre.
///
/// `didacta.yaml` es la lista de la que cuelga todo lo demás: una asignatura
/// solo puede declararse en uno de estos, y una unidad solo tiene hueco de
/// traducción en uno de estos. Editarla desde la aplicación no existía, así
/// que había que abrir el fichero a mano — y el error corriente al hacerlo es
/// el que aquí no se deja cometer.
///
/// **Quitar un idioma que una asignatura declara rompe esa asignatura.** No
/// la avería a medias: el motor rechaza su `course.yaml` entero, así que
/// desaparece de la biblioteca y el motivo queda en una lista de errores. Por
/// eso esto se niega y dice quién lo usa, en lugar de escribir y dejar que se
/// descubra al volver a indexar.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';

import 'fixture.dart';

const String settingsYaml = '''
# Un repositorio de contenido de Didacta.

name: "Pruebas"

# Los idiomas que mantiene este repositorio.
languages: [es, va, en]

# El idioma que se supone cuando nada dice otra cosa.
default_language: es

build_dir: .didacta-build
''';

Map<String, dynamic> courseIn(List<String> languages) => {
  'id': 'am-i',
  'title': const {'es': 'Análisis Matemático I'},
  'language': 'es',
  'languages': languages,
  'years': const <String, dynamic>{},
};

/// Una sesión con un repositorio y su `didacta.yaml` escribible.
Future<({FakeSession session, FakeGateway gateway})> repo({
  List<String> languages = const ['es', 'va', 'en'],
  List<Map<String, dynamic>> courses = const [],
  String yaml = settingsYaml,
  bool writable = true,
}) async {
  final gateway = FakeGateway(
    writable: writable,
    files: {'didacta.yaml': yaml},
  );
  final catalogue = catalogueWith(
    const [],
    courses: courses,
    repo: 'test/repo',
    languages: languages,
  );
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  return (session: session, gateway: gateway);
}

void main() {
  group('escribir los idiomas del repositorio', () {
    test('añadir uno reescribe solo esa línea', () async {
      // Un `didacta.yaml` lleva comentarios que explican qué se puede
      // ajustar, y un ida y vuelta por un parser los borra todos en la
      // primera edición.
      final it = await repo();

      await it.session.setRepoLanguages(
        repo: 'test/repo',
        languages: const ['es', 'va', 'en', 'fr'],
      );

      final written = it.gateway.commits.single.text;
      expect(written, contains('languages: [es, va, en, fr]'));
      expect(written, contains('# Un repositorio de contenido de Didacta.'));
      expect(written, contains('build_dir: .didacta-build'));
    });

    test('el orden es el del registro, no el de los clics', () async {
      // Para que el fichero salga igual se marque como se marque: si no,
      // cambiar de opinión dos veces deja un diff que solo mueve códigos.
      final it = await repo();

      await it.session.setRepoLanguages(
        repo: 'test/repo',
        languages: const ['fr', 'es', 'ca', 'va', 'en'],
      );

      expect(
        it.gateway.commits.single.text,
        contains('languages: [es, va, ca, en, fr]'),
      );
    });

    test('quitar uno que no usa nadie se escribe', () async {
      final it = await repo();

      await it.session.setRepoLanguages(
        repo: 'test/repo',
        languages: const ['es', 'va'],
      );

      expect(it.gateway.commits.single.text, contains('languages: [es, va]'));
    });

    test('quedarse sin ninguno se rechaza', () async {
      final it = await repo();

      expect(
        () =>
            it.session.setRepoLanguages(repo: 'test/repo', languages: const []),
        throwsArgumentError,
      );
      expect(it.gateway.commits, isEmpty);
    });

    test('un repositorio de solo lectura se rechaza sin tocarlo', () async {
      final it = await repo(writable: false);

      expect(
        () => it.session.setRepoLanguages(
          repo: 'test/repo',
          languages: const ['es'],
        ),
        throwsArgumentError,
      );
      expect(it.gateway.commits, isEmpty);
    });
  });

  group('quitar un idioma en uso', () {
    test('se niega, y dice qué asignaturas lo usan', () async {
      final it = await repo(
        courses: [
          courseIn(const ['es', 'va']),
        ],
      );

      await expectLater(
        it.session.setRepoLanguages(
          repo: 'test/repo',
          languages: const ['es', 'en'],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '$error',
            'el motivo',
            allOf(contains('va'), contains('Análisis Matemático I')),
          ),
        ),
      );
      expect(it.gateway.commits, isEmpty);
    });

    test('pero uno que ninguna declara sale sin protestar', () async {
      final it = await repo(
        courses: [
          courseIn(const ['es', 'va']),
        ],
      );

      await it.session.setRepoLanguages(
        repo: 'test/repo',
        languages: const ['es', 'va'],
      );

      expect(it.gateway.commits.single.text, contains('languages: [es, va]'));
    });
  });

  group('el idioma de referencia', () {
    test('sigue a la lista cuando se queda fuera', () async {
      // Un `default_language` que no está en `languages` no es un ajuste
      // discutible: el motor no puede ni leer el fichero, así que el
      // repositorio entero deja de cargar.
      final it = await repo();

      await it.session.setRepoLanguages(
        repo: 'test/repo',
        languages: const ['va', 'en'],
      );

      final written = it.gateway.commits.single.text;
      expect(written, contains('languages: [va, en]'));
      expect(written, contains('default_language: va'));
    });

    test('y se queda quieto cuando sigue dentro', () async {
      final it = await repo();

      await it.session.setRepoLanguages(
        repo: 'test/repo',
        languages: const ['es', 'en'],
      );

      expect(it.gateway.commits.single.text, contains('default_language: es'));
    });
  });

  group('lo que el catálogo recuerda de cada repositorio', () {
    test('no se funde al juntar dos', () async {
      // La unión contesta «¿qué idiomas hay en lo que estoy mirando?» y esto
      // contesta «¿qué puedo escribir en este repositorio?». Fundirlas era lo
      // que hacía que la interfaz ofreciera los idiomas de uno para escribir
      // en el otro.
      final catalogue = Catalogue.merge([
        catalogueWith(
          const [],
          repo: 'x/teoria',
          languages: const ['es', 'va'],
        ),
        catalogueWith(
          const [],
          repo: 'x/practica',
          languages: const ['es', 'en'],
        ),
      ]);

      expect(catalogue.languages, ['es', 'va', 'en']);
      expect(catalogue.languagesOf('x/teoria'), ['es', 'va']);
      expect(catalogue.languagesOf('x/practica'), ['es', 'en']);
    });

    test('apagar un repositorio se lleva sus idiomas', () async {
      // La propiedad que se busca: apagar uno tiene que dar exactamente lo
      // mismo que no tenerlo.
      final catalogue = Catalogue.merge([
        catalogueWith(
          const [],
          repo: 'x/teoria',
          languages: const ['es', 'va'],
        ),
        catalogueWith(
          const [],
          repo: 'x/practica',
          languages: const ['es', 'en'],
        ),
      ]);

      expect(catalogue.without({'x/practica'}).languages, ['es', 'va']);
    });

    test('un índice que no nombra repositorios cae en los del catálogo', () {
      // Un catálogo leído por HTTP no nombra ninguno, y eso no puede dejar a
      // nadie sin idiomas.
      final catalogue = catalogueWith(const []);

      expect(catalogue.languagesOf('el/que/sea'), catalogue.languages);
    });
  });
}
