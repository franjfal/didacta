/// Cuando dos repositorios no dicen lo mismo de la misma asignatura.
///
/// Una asignatura repartida se declara en los dos `course.yaml`, y los dos
/// tienen que decir lo mismo. Si uno pone «Análisis Matemático I» y el otro
/// «Analisis Matematico I», la que se enseña depende de en qué orden se
/// abrieron los repositorios: el mismo material se ve distinto en dos
/// máquinas y nadie sabe cuál es el bueno.
///
/// La regla de este fichero: **nada se resuelve solo**. Son ficheros que
/// pueden ser de otra persona, y propagar el valor «más nuevo» por su cuenta
/// deshace el cambio de quien todavía no lo ha enviado.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';

import 'fixture.dart';

Map<String, dynamic> courseJsonWith({
  String title = 'Análisis Matemático I',
  List<String> languages = const ['es'],
  String? code,
  String? teacher,
}) => {
  'id': 'am-i',
  'title': {'es': title},
  'language': 'es',
  'languages': languages,
  'code': ?code,
  'teacher': ?teacher,
  'years': {
    '2026-2027': {
      'year': '2026-2027',
      'language': 'es',
      'documents': const <Map<String, dynamic>>[],
    },
  },
};

Catalogue twoRepos(
  Map<String, dynamic> first,
  Map<String, dynamic> second, {
  String firstRepo = 'x/teoria',
  String secondRepo = 'x/problemas',
}) => Catalogue.merge([
  catalogueWith(const [], courses: [first], repo: firstRepo),
  catalogueWith(const [], courses: [second], repo: secondRepo),
]);

void main() {
  group('detectar', () {
    test('dos títulos distintos son una discrepancia', () {
      final catalogue = twoRepos(
        courseJsonWith(title: 'Análisis Matemático I'),
        courseJsonWith(title: 'Analisis Matematico I'),
      );

      final conflict = catalogue.metadataConflicts.single;
      expect(conflict.course, 'am-i');
      expect(conflict.field, 'título (es)');
      expect(conflict.values['x/teoria'], 'Análisis Matemático I');
      expect(conflict.values['x/problemas'], 'Analisis Matematico I');
    });

    test('decir lo mismo no lo es', () {
      final catalogue = twoRepos(courseJsonWith(), courseJsonWith());
      expect(catalogue.metadataConflicts, isEmpty);
    });

    test('que uno lo sepa y el otro no, tampoco', () {
      // Rellenar lo que falta es otra decisión, y tratarlo como discrepancia
      // llenaría la pantalla de avisos el día que se abre un repositorio
      // nuevo y todavía vacío de metadatos.
      final catalogue = twoRepos(
        courseJsonWith(code: '34151'),
        courseJsonWith(),
      );
      expect(catalogue.metadataConflicts, isEmpty);
    });

    test('los idiomas declarados distintos también discrepan', () {
      final catalogue = twoRepos(
        courseJsonWith(languages: const ['es', 'va']),
        courseJsonWith(languages: const ['es']),
      );
      expect(
        catalogue.metadataConflicts.single.field,
        'idiomas',
      );
    });

    test('con un solo repositorio no hay nada que comparar', () {
      final catalogue = catalogueWith(
        const [],
        courses: [courseJsonWith()],
        repo: 'x/uno',
      );
      expect(catalogue.metadataConflicts, isEmpty);
    });

    test('se detecta campo a campo, no la asignatura entera', () {
      final catalogue = twoRepos(
        courseJsonWith(title: 'Uno', teacher: 'Javier Falcó'),
        courseJsonWith(title: 'Otro', teacher: 'J. Falcó'),
      );
      expect(
        catalogue.metadataConflicts.map((c) => c.field),
        containsAll(['título (es)', 'profesor']),
      );
    });
  });

  group('la fusión mientras tanto', () {
    test('los idiomas se suman, no se pelean', () {
      // Que un repositorio no sepa de un idioma no quiere decir que la
      // asignatura no se dé en él: quiere decir que ese repositorio no tiene
      // material suyo.
      final catalogue = twoRepos(
        courseJsonWith(languages: const ['es', 'va']),
        courseJsonWith(languages: const ['es', 'en']),
      );
      expect(catalogue.courses.single.languages, ['es', 'va', 'en']);
    });

    test('lo que declara cada uno se conserva aparte', () {
      // Es lo único que permite darse cuenta de que no dicen lo mismo: sin
      // esto, la fusión elige un valor y el otro desaparece para siempre.
      final catalogue = twoRepos(
        courseJsonWith(title: 'Uno'),
        courseJsonWith(title: 'Otro'),
      );
      final sources = catalogue.courses.single.sources;
      expect(sources.keys, containsAll(['x/teoria', 'x/problemas']));
      expect(sources['x/teoria']!.titles['es'], 'Uno');
      expect(sources['x/problemas']!.titles['es'], 'Otro');
    });

    test('apagar un repositorio quita también lo que declaraba', () {
      final catalogue = twoRepos(
        courseJsonWith(title: 'Uno'),
        courseJsonWith(title: 'Otro'),
      ).without({'x/problemas'});
      expect(catalogue.metadataConflicts, isEmpty);
      expect(catalogue.courses.single.sources.keys, ['x/teoria']);
    });
  });

  group('dónde se escribe cada campo', () {
    test('un título localizado sabe su ruta', () {
      expect(CourseFacts.pathOf('título (va)'), ['title', 'va']);
      expect(CourseFacts.pathOf('titulación (es)'), ['degree', 'es']);
    });

    test('y los campos sueltos también', () {
      expect(CourseFacts.pathOf('código'), ['code']);
      expect(CourseFacts.pathOf('profesor'), ['teacher']);
      expect(CourseFacts.pathOf('idiomas'), ['languages']);
    });

    test('lo que no se sabe escribir se dice, no se adivina', () {
      expect(CourseFacts.pathOf('inventado'), isNull);
    });
  });
}
