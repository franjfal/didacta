/// Los tres niveles de la biblioteca: lo que se declara en `taxonomy.yaml` y
/// lo que el catálogo cuenta de ello.
///
/// Se prueba lo que no se ve en una pantalla y rompería en silencio: que
/// declarar un subtema no toque una sola línea de lo que ya había --los
/// comentarios de ese fichero son la única explicación de los ids--, que
/// cree lo que le falte por encima, y que dos repositorios que declaran lo
/// mismo se vean como una sola clasificación.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/taxonomy_file.dart';

const String taxonomy = '''
# La clasificación.

blocks:
  - id: theory
    title:
      es: Teoría

categories:
  - id: calculo
    title:
      es: Cálculo
    # Los temas, en el orden en que se dan.
    topics:
      - id: limites
        title:
          es: Límites
        subtopics:
          - id: concepto
            title:
              es: El concepto de límite
      - id: continuidad
        title:
          es: Continuidad
''';

Map<String, Map<String, String>> named(String key, String es) => {
  key: {'es': es},
};

Catalogue withTaxonomy(Map<String, dynamic> taxonomy, {String repo = ''}) =>
    Catalogue.fromIndex(
      manifest: {
        'schemaVersion': supportedSchemaVersion,
        'name': 'Prueba',
        'languages': const ['es'],
        'taxonomy': taxonomy,
      },
      units: {'schemaVersion': supportedSchemaVersion, 'units': const []},
      courses: {'schemaVersion': supportedSchemaVersion, 'courses': const []},
      repo: repo,
    );

void main() {
  group('declarar un sitio en taxonomy.yaml', () {
    test('un subtema nuevo va al final de los de su tema', () {
      final file = TaxonomyFile(taxonomy);
      final changed = file.declarePlace(
        'calculo/limites/calculo',
        titles: named('calculo/limites/calculo', 'Cálculo de límites'),
        languages: const ['es', 'va'],
      );
      expect(changed, isTrue);
      expect(
        file.text,
        contains(
          '          - id: concepto\n'
          '            title:\n'
          '              es: El concepto de límite\n'
          '          - id: calculo\n'
          '            title:\n'
          '              es: Cálculo de límites\n'
          '              # TODO: va\n'
          '      - id: continuidad\n',
        ),
      );
      // Y nada más ha cambiado: solo se han añadido esas cuatro líneas.
      final added = file.text.split('\n').length - taxonomy.split('\n').length;
      expect(added, 4);
      expect(file.text, contains('# Los temas, en el orden en que se dan.'));
    });

    test('un tema sin subtemas recibe la lista', () {
      final file = TaxonomyFile(taxonomy)
        ..declarePlace(
          'calculo/continuidad/bolzano',
          titles: named('calculo/continuidad/bolzano', 'Bolzano'),
          languages: const ['es'],
        );
      expect(
        file.text,
        contains(
          '      - id: continuidad\n'
          '        title:\n'
          '          es: Continuidad\n'
          '        subtopics:\n'
          '          - id: bolzano\n'
          '            title:\n'
          '              es: Bolzano\n',
        ),
      );
      expect(file.declares('calculo/continuidad/bolzano'), isTrue);
    });

    test('lo que falta por encima se crea, con el nombre que se dé', () {
      final file = TaxonomyFile(taxonomy)
        ..declarePlace(
          'algebra/matrices/rango',
          titles: {
            'algebra': {'es': 'Álgebra'},
            'algebra/matrices': {'es': 'Matrices'},
            'algebra/matrices/rango': {'es': 'El rango'},
          },
          languages: const ['es'],
        );
      expect(file.declares('algebra'), isTrue);
      expect(file.declares('algebra/matrices'), isTrue);
      expect(file.declares('algebra/matrices/rango'), isTrue);
      // Y la categoría de antes sigue entera.
      expect(file.declares('calculo/limites/concepto'), isTrue);
    });

    test('lo que ya está no se toca, ni su nombre', () {
      final file = TaxonomyFile(taxonomy);
      final changed = file.declarePlace(
        'calculo/limites/concepto',
        titles: named('calculo/limites/concepto', 'Otro nombre'),
        languages: const ['es'],
      );
      expect(changed, isFalse);
      expect(file.text, taxonomy);
    });

    test('en un fichero sin categorías, empieza la lista', () {
      final file = TaxonomyFile(emptyTaxonomyYaml)
        ..declarePlace(
          'calculo',
          titles: named('calculo', 'Cálculo'),
          languages: const ['es'],
        );
      expect(
        file.text,
        contains(
          '\ncategories:\n  - id: calculo\n    title:\n      es: Cálculo',
        ),
      );
    });

    test('sin nombre no se declara', () {
      expect(
        () => TaxonomyFile(taxonomy).declarePlace(
          'calculo/limites/x',
          titles: const {},
          languages: const ['es'],
        ),
        throwsA(isA<TaxonomyException>()),
      );
    });
  });

  group('lo declarado, en el catálogo', () {
    final declared = {
      'categories': [
        {
          'id': 'calculo',
          'title': {'es': 'Cálculo'},
          'topics': [
            {
              'id': 'limites',
              'title': {'es': 'Límites'},
              'subtopics': [
                {
                  'id': 'concepto',
                  'title': {'es': 'El concepto de límite'},
                },
              ],
            },
            {
              'id': 'continuidad',
              'title': {'es': 'Continuidad'},
            },
          ],
        },
      ],
    };

    test('en orden, con sus nombres, también los subtemas', () {
      final catalogue = withTaxonomy(declared);
      expect(catalogue.declaredChildren(''), ['calculo']);
      expect(catalogue.declaredChildren('calculo'), ['limites', 'continuidad']);
      expect(catalogue.declaredChildren('calculo/limites'), ['concepto']);
      expect(
        catalogue.taxonomyTitle('calculo/limites/concepto', 'es'),
        'El concepto de límite',
      );
    });

    test('dos repositorios que declaran lo mismo son una clasificación', () {
      final other = {
        'categories': [
          {
            'id': 'calculo',
            'topics': [
              {
                'id': 'limites',
                'subtopics': [
                  {'id': 'concepto'},
                  {'id': 'calculo'},
                ],
              },
            ],
          },
        ],
      };
      final both = Catalogue.merge([
        withTaxonomy(declared, repo: 'teoria'),
        withTaxonomy(other, repo: 'problemas'),
      ]);
      expect(both.declaredChildren('calculo/limites'), ['concepto', 'calculo']);
      expect(both.taxonomyDeclared['calculo/limites/concepto'], {
        'teoria',
        'problemas',
      });
      // Apagar uno se lleva lo que solo declaraba él.
      final shown = both.without({'problemas'});
      expect(shown.declaredChildren('calculo/limites'), ['concepto']);
      // Y no los nombres, que antes se perdían al apagar un repositorio.
      expect(shown.taxonomyTitle('calculo', 'es'), 'Cálculo');
    });
  });
}
