/// Las titulaciones: agrupar asignaturas sin poder romper nada.
///
/// Sigue el mismo patrón que los temas, que es el que sostiene todo lo que se
/// comparte entre repositorios: **la asignatura nombra el grado y el grado lo
/// declara quien lo tenga**. De ahí la propiedad que lo hace aceptable: una
/// asignatura que nombra un grado que no declara ningún repositorio abierto
/// sale igual que antes de que existieran los grados --sin agrupar, pero
/// entera--. Nadie se queda sin ver su material por no tener el repositorio
/// donde alguien puso un título.
///
/// Y como las asignaturas, pueden estar repartidos, hay que juntarlos por id y
/// hay que darse cuenta cuando dos repositorios no dicen lo mismo.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/degrees_file.dart';

Map<String, dynamic> degreeJson(
  String id, {
  String title = 'Grado en Matemáticas',
  String? institution,
}) => {
  'id': id,
  'title': {'es': title},
  'institution': institution,
};

Map<String, dynamic> courseJsonIn(String id, {String? degree}) => {
  'id': id,
  'title': {'es': 'La $id'},
  'language': 'es',
  'degreeId': degree,
  'years': const <String, dynamic>{},
};

Catalogue repoWith({
  required String repo,
  List<Map<String, dynamic>> degrees = const [],
  List<Map<String, dynamic>> courses = const [],
}) => Catalogue.fromIndex(
  manifest: {
    'schemaVersion': supportedSchemaVersion,
    'name': 'Prueba',
    'languages': const ['es', 'va', 'en'],
    'defaultLanguage': 'es',
    'contentHash': 'abc',
    'profiles': const <Map<String, dynamic>>[],
    'errors': const <String>[],
  },
  units: {'schemaVersion': supportedSchemaVersion, 'units': const []},
  courses: {
    'schemaVersion': supportedSchemaVersion,
    'degrees': degrees,
    'courses': courses,
  },
  repo: repo,
);

const String degreesYaml = '''
# Las titulaciones de este repositorio.
#
# Un grado que no declara nadie no agrupa: sus asignaturas salen sueltas.

degrees:
  - id: matematicas
    title:
      es: Grado en Matemáticas
      # TODO: va
      # TODO: en
    institution: Universitat de València

  - id: fisica
    title:
      es: Grado en Física
      va: Grau en Física
''';

void main() {
  group('juntar lo que declara cada repositorio', () {
    test('un grado declarado en dos sale una vez', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', degrees: [degreeJson('matematicas')]),
        repoWith(repo: 'x/problemas', degrees: [degreeJson('matematicas')]),
      ]);
      expect(catalogue.degrees.single.id, 'matematicas');
    });

    test('y guarda lo que dice cada uno, para poder comparar', () {
      // Es lo único que permite darse cuenta de que no dicen lo mismo: sin
      // esto, la fusión elige un título y el otro desaparece para siempre.
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          degrees: [degreeJson('matematicas', title: 'Grado en Matemáticas')],
        ),
        repoWith(
          repo: 'x/problemas',
          degrees: [degreeJson('matematicas', title: 'Matemáticas')],
        ),
      ]);
      final sources = catalogue.degrees.single.sources;
      expect(sources.keys, containsAll(['x/teoria', 'x/problemas']));
    });

    test('dos grados distintos se suman', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', degrees: [degreeJson('matematicas')]),
        repoWith(
          repo: 'x/problemas',
          degrees: [degreeJson('fisica', title: 'Grado en Física')],
        ),
      ]);
      expect(catalogue.degrees.map((d) => d.id), ['fisica', 'matematicas']);
    });

    test('apagar un repositorio quita lo que solo declaraba él', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', degrees: [degreeJson('matematicas')]),
        repoWith(repo: 'x/problemas', degrees: [degreeJson('fisica')]),
      ]).without({'x/problemas'});
      expect(catalogue.degrees.map((d) => d.id), ['matematicas']);
    });
  });

  group('cuando no dicen lo mismo', () {
    test('dos títulos distintos son una discrepancia', () {
      // Si no, el grado se enseña con un nombre u otro según en qué orden se
      // abrieron los repositorios, y las asignaturas de un mismo grado se
      // agrupan bajo dos nombres distintos según la máquina.
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          degrees: [degreeJson('matematicas', title: 'Grado en Matemáticas')],
        ),
        repoWith(
          repo: 'x/problemas',
          degrees: [degreeJson('matematicas', title: 'Matemáticas')],
        ),
      ]);

      final conflict = catalogue.degreeConflicts.single;
      expect(conflict.course, 'matematicas');
      expect(conflict.about, ConflictAbout.degree);
      expect(conflict.field, 'título (es)');
      expect(conflict.language, 'es');
    });

    test('decir lo mismo no lo es', () {
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', degrees: [degreeJson('matematicas')]),
        repoWith(repo: 'x/problemas', degrees: [degreeJson('matematicas')]),
      ]);
      expect(catalogue.degreeConflicts, isEmpty);
    });

    test('salen junto a las de las asignaturas, que se miran a la vez', () {
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          degrees: [degreeJson('matematicas', title: 'Uno')],
        ),
        repoWith(
          repo: 'x/problemas',
          degrees: [degreeJson('matematicas', title: 'Otro')],
        ),
      ]);
      expect(catalogue.metadataConflicts, isNotEmpty);
    });

    test(
      'que dos repositorios pongan la asignatura en grados distintos, también',
      () {
        // La asignatura saldría en un grado o en otro según en qué orden se
        // abrieron los repositorios.
        final catalogue = Catalogue.merge([
          repoWith(
            repo: 'x/teoria',
            courses: [courseJsonIn('am-i', degree: 'matematicas')],
          ),
          repoWith(
            repo: 'x/problemas',
            courses: [courseJsonIn('am-i', degree: 'fisica')],
          ),
        ]);
        expect(
          catalogue.metadataConflicts.map((c) => c.field),
          contains('grado'),
        );
      },
    );

    test('y se sabe dónde se escribe el de la asignatura', () {
      expect(CourseFacts.pathOf('grado'), ['degree_id']);
    });
  });

  group('dejar de declarar', () {
    test('quita el grado y no toca a los demás', () {
      final file = DegreesFile(degreesYaml)..remove('matematicas');
      expect(file.ids, ['fisica']);
      expect(file.titlesOf('fisica'), {
        'es': 'Grado en Física',
        'va': 'Grau en Física',
      });
      expect(file.text, contains('no agrupa'));
    });

    test('el último deja una lista vacía, no una clave colgando', () {
      // `degrees:` sin valor se lee como null y no como lista vacía, que es
      // un error de lectura del repositorio entero.
      final file = DegreesFile(degreesYaml)
        ..remove('matematicas')
        ..remove('fisica');
      expect(file.ids, isEmpty);
      expect(file.text, contains('degrees: []'));
    });

    test('quitar uno que no se declara aquí se niega', () {
      expect(
        () => DegreesFile(degreesYaml).remove('quimicas'),
        throwsA(isA<DegreesException>()),
      );
    });

    test('y sus asignaturas siguen saliendo, sin agrupar', () {
      // La regla que hace que esto no pueda perder material: un grado que no
      // declara nadie no agrupa, y sus asignaturas salen enteras.
      final catalogue = Catalogue.merge([
        repoWith(
          repo: 'x/teoria',
          courses: [courseJsonIn('am-i', degree: 'matematicas')],
        ),
      ]);
      expect(catalogue.degrees, isEmpty);
      expect(catalogue.courses, hasLength(1));
      expect(catalogue.undeclaredDegrees, ['matematicas']);
    });
  });

  group('agrupar sin romper nada', () {
    test('las asignaturas de un grado se pueden pedir', () {
      final catalogue = repoWith(
        repo: 'x/uno',
        degrees: [degreeJson('matematicas')],
        courses: [
          courseJsonIn('am-i', degree: 'matematicas'),
          courseJsonIn('am-ii', degree: 'matematicas'),
          courseJsonIn('fisica-i', degree: 'fisica'),
        ],
      );
      expect(catalogue.coursesIn('matematicas').length, 2);
      expect(catalogue.coursesIn('fisica').single.id, 'fisica-i');
    });

    test('y las que no dicen a cuál pertenecen', () {
      final catalogue = repoWith(
        repo: 'x/uno',
        courses: [
          courseJsonIn('am-i'),
          courseJsonIn('am-ii', degree: 'x'),
        ],
      );
      expect(catalogue.coursesIn(null).single.id, 'am-i');
    });

    test('un grado que nadie declara no es un error, pero se dice', () {
      // La asignatura sale entera y sin agrupar, como antes de que existieran
      // los grados. Casi siempre significa que falta una línea, o que falta
      // abrir un repositorio.
      final catalogue = repoWith(
        repo: 'x/uno',
        degrees: [degreeJson('matematicas')],
        courses: [
          courseJsonIn('am-i', degree: 'matematicas'),
          courseJsonIn('fisica-i', degree: 'fisica'),
        ],
      );
      expect(catalogue.courses.length, 2);
      expect(catalogue.undeclaredDegrees, ['fisica']);
    });

    test('con todo declarado no sobra ninguno', () {
      final catalogue = repoWith(
        repo: 'x/uno',
        degrees: [degreeJson('matematicas')],
        courses: [courseJsonIn('am-i', degree: 'matematicas')],
      );
      expect(catalogue.undeclaredDegrees, isEmpty);
    });

    test('lo declara uno y lo nombra el otro: basta con eso', () {
      // El caso que da sentido a todo el patrón.
      final catalogue = Catalogue.merge([
        repoWith(repo: 'x/teoria', degrees: [degreeJson('matematicas')]),
        repoWith(
          repo: 'x/problemas',
          courses: [courseJsonIn('am-i', degree: 'matematicas')],
        ),
      ]);
      expect(catalogue.undeclaredDegrees, isEmpty);
      expect(catalogue.coursesIn('matematicas').single.id, 'am-i');
    });
  });

  group('escribir degrees.yaml', () {
    test('cambiar un título no toca los demás grados', () {
      final file = DegreesFile(degreesYaml)
        ..setTitles('matematicas', {
          'es': 'Grado en Matemáticas',
          'va': 'Grau en Matemàtiques',
          'en': '',
        });

      // Sin comillas: no lleva dos puntos ni empieza por nada raro, así que
      // no hacen falta y el fichero se lee mejor sin ellas.
      expect(file.text, contains('va: Grau en Matemàtiques'));
      expect(file.text, contains('# TODO: en'));
      expect(file.text, contains('es: Grado en Física'));
      expect(file.text, contains('va: Grau en Física'));
    });

    test('ni la cabecera, que explica por qué esto no rompe nada', () {
      final file = DegreesFile(degreesYaml)
        ..setTitles('fisica', {'es': 'Física'});
      expect(file.text, startsWith('# Las titulaciones de este repositorio.'));
      expect(file.text, contains('no agrupa'));
    });

    test('un idioma en blanco se comenta, no se escribe vacío', () {
      // Una cadena vacía es un título de verdad, y se enseñaría.
      final file = DegreesFile(degreesYaml)
        ..setTitles('fisica', {'es': 'Grado en Física', 'va': ''});
      expect(file.text, isNot(contains('va: ""')));
      expect(file.text, contains('# TODO: va'));
    });

    test('declarar uno nuevo lo añade al final', () {
      final file = DegreesFile(degreesYaml)
        ..add(
          id: 'quimica',
          titles: {'es': 'Grado en Química'},
          languages: const ['es', 'va', 'en'],
        );

      expect(file.ids, ['matematicas', 'fisica', 'quimica']);
      expect(file.text, contains('es: Grado en Química'));
      expect(file.text, contains('# TODO: va'));
    });

    test('con institución, si se da', () {
      final file = DegreesFile(degreesYaml)
        ..add(
          id: 'quimica',
          titles: {'es': 'Química'},
          institution: 'Universitat de València',
          languages: const ['es'],
        );
      expect(file.text, contains('institution: Universitat de València'));
    });

    test('sobre un fichero recién creado, con sus comentarios', () {
      final file = DegreesFile(emptyDegreesYaml)
        ..add(
          id: 'matematicas',
          titles: {'es': 'Grado en Matemáticas'},
          languages: const ['es'],
        );

      expect(file.ids, ['matematicas']);
      expect(file.text, contains('no agrupa'));
      expect(file.text, isNot(contains('degrees: []')));
    });

    test('declarar dos veces el mismo se rechaza', () {
      expect(
        () => DegreesFile(
          degreesYaml,
        ).add(id: 'fisica', titles: {'es': 'Otro'}, languages: const ['es']),
        throwsA(isA<DegreesException>()),
      );
    });

    test('sin título en ningún idioma, tampoco', () {
      // Se enseñaría por su id, que es un slug.
      expect(
        () => DegreesFile(degreesYaml).add(
          id: 'quimica',
          titles: {'es': '', 'va': ''},
          languages: const ['es', 'va'],
        ),
        throwsA(isA<DegreesException>()),
      );
    });

    test('escribir lo mismo no cambia el fichero', () {
      // Un commit que no cambia nada es ruido en el historial de otra persona.
      final file = DegreesFile(
        degreesYaml,
      )..setTitles('fisica', {'es': 'Grado en Física', 'va': 'Grau en Física'});
      expect(file.text, degreesYaml);
    });

    test('un grado que este fichero no declara se dice', () {
      expect(
        () => DegreesFile(degreesYaml).setTitles('quimica', {'es': 'X'}),
        throwsA(isA<DegreesException>()),
      );
    });
  });
}
