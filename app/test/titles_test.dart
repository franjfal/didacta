/// Cambiar un título sin cambiar de idioma toda la pantalla.
///
/// Desde que el idioma se elige en la barra de arriba, lo que se lee en la
/// lista de asignaturas, en la cabecera de un tema y en cada documento es el
/// título **en ese idioma**. Lo primero que se quiere hacer al ver un hueco es
/// rellenarlo, y hasta ahora eso no se podía: los títulos de la asignatura,
/// del tema y del documento no se editaban desde ninguna pantalla.
///
/// Lo que se fija aquí es sobre todo lo que **no** puede pasar al escribirlos:
/// que un idioma en blanco se escriba como cadena vacía --sería un título de
/// verdad, y saldría en el PDF-- y que reescribir el bloque del título se
/// lleve por delante lo que hay alrededor. Los ficheros están escritos a mano
/// y llevan comentarios que son datos.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/model/themes_file.dart';

const String yearYaml = '''
# El curso 2026-2027 de Análisis Matemático I.
year: "2026-2027"
language: es

documents:
  - id: tema-1
    kind: theory
    title:
      es: "Tema 1: los números reales"
      # TODO: va
      # TODO: en
    profiles: [notes, slides]
    themes: [tema-1]
    structure:
      - unit: analisis/reales/supremo

  - id: hoja-1
    kind: problems
    title:
      es: Hoja 1
      va: Full 1
    # Esta hoja la repartió Marta el año pasado y hay que revisarla.
    structure: []
''';

const String themesYaml = '''
# Los temas en que se agrupa el curso.
#
# Un tema que nadie declara no agrupa.

themes:
  - id: tema-1
    title:
      es: "Tema 1: el número y la recta real"
      # TODO: va
      # TODO: en

  - id: tema-2
    title:
      es: Sucesiones
      va: Successions
''';

void main() {
  group('el título de un documento', () {
    test('se escribe en su bloque y no toca lo demás', () {
      final file = CompositionFile(yearYaml)
        ..setDocumentTitles('tema-1', {
          'es': 'Tema 1: los números reales',
          'va': 'Tema 1: els nombres reals',
          'en': '',
        });

      // Con comillas simples, que es como entrecomilla este fichero desde
      // que se escribió: `Tema 1: los reales` sin comillas es otra clave y el
      // año entero deja de leerse.
      expect(file.text, contains("va: 'Tema 1: els nombres reals'"));
      expect(file.text, contains('# TODO: en'));
      // Lo de alrededor, intacto.
      expect(file.text, contains('profiles: [notes, slides]'));
      expect(file.text, contains('themes: [tema-1]'));
      expect(file.text, contains('- unit: analisis/reales/supremo'));
    });

    test('un idioma en blanco se comenta, no se escribe vacío', () {
      // Es la diferencia que importa: `va: ""` es un título de verdad y
      // saldría en la lista de documentos y dentro del PDF en valenciano.
      final file = CompositionFile(yearYaml)
        ..setDocumentTitles('hoja-1', {'es': 'Hoja 1', 'va': ''});

      expect(file.text, isNot(contains('va: ""')));
      expect(file.text, contains('# TODO: va'));
    });

    test('quitar una traducción no se lleva el comentario de al lado', () {
      // El comentario es de alguien y no es un TODO: reescribir el bloque del
      // título no puede tragárselo.
      final file = CompositionFile(yearYaml)
        ..setDocumentTitles('hoja-1', {'es': 'Hoja 1', 'va': ''});

      expect(
        file.text,
        contains('# Esta hoja la repartió Marta el año pasado'),
      );
    });

    test('un título con dos puntos sale entrecomillado', () {
      // Sin comillas, `Tema 1: los reales` es otra clave y el fichero deja de
      // leerse entero.
      final file = CompositionFile(yearYaml)
        ..setDocumentTitles('hoja-1', {'es': 'Hoja 1: los reales'});
      expect(file.text, contains("es: 'Hoja 1: los reales'"));
    });

    test('sin ningún idioma con título, se rechaza', () {
      expect(
        () => CompositionFile(
          yearYaml,
        ).setDocumentTitles('hoja-1', {'es': '', 'va': ''}),
        throwsA(isA<CompositionException>()),
      );
    });

    test('un documento que no existe se dice', () {
      expect(
        () => CompositionFile(
          yearYaml,
        ).setDocumentTitles('no-existe', {'es': 'X'}),
        throwsA(isA<CompositionException>()),
      );
    });

    test('el resto del fichero se queda como estaba', () {
      final file = CompositionFile(yearYaml)
        ..setDocumentTitles('tema-1', {'es': 'Otro'});
      expect(file.text, startsWith('# El curso 2026-2027'));
      expect(file.text.split('\n').where((l) => l.contains('- id:')).length, 2);
    });
  });

  group('el título de un tema', () {
    test('se escribe donde estaba', () {
      final file = ThemesFile(themesYaml)
        ..setTitles('tema-1', {
          'es': 'Tema 1: el número y la recta real',
          'va': 'Tema 1: el nombre i la recta real',
          'en': '',
        });

      expect(file.text, contains('va: "Tema 1: el nombre i la recta real"'));
      expect(file.text, contains('# TODO: en'));
      expect(file.text, isNot(contains('# TODO: va')));
    });

    test('no toca los demás temas', () {
      final file = ThemesFile(themesYaml)..setTitles('tema-1', {'es': 'Otro'});
      expect(file.text, contains('es: Sucesiones'));
      expect(file.text, contains('va: Successions'));
      expect(file.ids, ['tema-1', 'tema-2']);
    });

    test(
      'ni la cabecera del fichero, que explica por qué esto no rompe nada',
      () {
        final file = ThemesFile(themesYaml)
          ..setTitles('tema-2', {'es': 'Sucesiones y series'});
        expect(file.text, startsWith('# Los temas en que se agrupa el curso.'));
        expect(file.text, contains('# Un tema que nadie declara no agrupa.'));
      },
    );

    test('lee lo que hay antes de escribirlo', () {
      expect(ThemesFile(themesYaml).titlesOf('tema-2'), {
        'es': 'Sucesiones',
        'va': 'Successions',
      });
      expect(ThemesFile(themesYaml).titlesOf('tema-1'), {
        'es': 'Tema 1: el número y la recta real',
      });
    });

    test('un tema sin título en ningún idioma se rechaza', () {
      // Se enseñaría por su id, que es un slug.
      expect(
        () => ThemesFile(themesYaml).setTitles('tema-2', {'es': '', 'va': ''}),
        throwsA(isA<ThemesException>()),
      );
    });

    test('un tema que este fichero no declara se dice', () {
      expect(
        () => ThemesFile(themesYaml).setTitles('tema-9', {'es': 'X'}),
        throwsA(isA<ThemesException>()),
      );
    });

    test('escribir lo mismo no cambia el fichero', () {
      // Un commit que no cambia nada es ruido en el historial de otra persona.
      final file = ThemesFile(themesYaml)
        ..setTitles('tema-2', {'es': 'Sucesiones', 'va': 'Successions'});
      expect(file.text, themesYaml);
    });
  });
}
