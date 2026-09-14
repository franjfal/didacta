/// Leer un documento entero: la composición y sus unidades, en orden.
///
/// Lo que se demuestra: que el orden es el de la composición, que un idioma
/// que falta no abre un hueco —usa el de referencia y lo dice, como LaTeX—,
/// que una referencia rota se ve, y que el árbol se calcula sobre el texto
/// pegado y no fichero a fichero.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/document_reading.dart';

import 'fixture.dart';

const String definition = 'content/analysis/normed/definition';
const String banach = 'content/analysis/normed/banach';

Document documentWith(List<CompositionPart> structure) => Document(
  id: 'tema-1',
  kind: 'theory',
  language: 'va',
  titles: const {'va': 'Preliminars'},
  profiles: const [],
  unitRefs: [
    for (final part in structure)
      if (part.kind == 'unit' || part.kind == 'problem') part.reference,
  ],
  structure: structure,
);

CompositionPart unit(String reference) =>
    CompositionPart(kind: 'unit', reference: reference, titles: const {});

Future<DocumentReading> read(
  Document document, {
  String language = 'va',
  Map<String, String> files = const {},
}) => readDocument(
  document: document,
  catalogue: catalogueWith(defaultUnits()),
  language: language,
  read: (unit, code) async {
    final path = '${unit.path}/$code.tex';
    final text = files[path];
    if (text == null) throw StateError('no existe $path');
    return (text: text, sha: 'sha-$path');
  },
);

void main() {
  test('las piezas salen en el orden de la composición', () async {
    final reading = await read(
      documentWith([
        CompositionPart(
          kind: 'section',
          reference: '',
          titles: const {'es': 'Espacios normados', 'va': 'Espais normats'},
        ),
        unit('analysis/normed/definition'),
        unit('analysis/normed/banach'),
      ]),
      files: {
        '$definition/es.tex': 'Definición.\n',
        '$banach/es.tex': 'Banach.\n',
        '$banach/va.tex': 'Banach en valencià.\n',
      },
    );

    expect(reading.pieces.length, 3);
    expect(reading.pieces.first, isA<ReadingHeading>());
    expect(
      (reading.pieces.first as ReadingHeading).title('va'),
      'Espais normats',
    );
    expect(
      [for (final file in reading.files) file.reference],
      ['analysis/normed/definition', 'analysis/normed/banach'],
    );
  });

  test('un idioma que falta usa el de referencia y lo dice', () async {
    final reading = await read(
      documentWith([unit('analysis/normed/definition')]),
      files: {'$definition/es.tex': 'Definición.\n'},
    );

    final file = reading.files.single;
    // La unidad del fixture solo tiene castellano: en valenciano se lee el
    // original, igual que hace el motor, y la vista puede decirlo.
    expect(file.language, 'es');
    expect(file.requestedLanguage, 'va');
    expect(file.isFallback, isTrue);
    expect(file.path, '$definition/es.tex');
  });

  test('una referencia que no resuelve se ve', () async {
    final reading = await read(documentWith([unit('analysis/no/existe')]));

    expect(reading.files, isEmpty);
    expect(reading.gaps.single.reference, 'analysis/no/existe');
    // Saltarla en silencio es cómo se llega a clase con un hueco.
    expect(reading.gaps.single.reason, contains('catálogo'));
  });

  test('un fichero que no se puede leer también', () async {
    final reading = await read(
      documentWith([unit('analysis/normed/definition')]),
      files: const {},
    );
    expect(reading.gaps.single.reason, contains('no existe'));
  });

  test('el árbol se calcula sobre los ficheros pegados', () async {
    final reading = await read(
      documentWith([
        unit('analysis/normed/definition'),
        unit('analysis/normed/banach'),
      ]),
      files: {
        '$definition/es.tex': '\\begin{frame}\nUna diapositiva\n',
        '$banach/va.tex': 'que sigue aquí.\n\\end{frame}\n',
      },
    );

    // Abierta en una unidad y cerrada en la siguiente: una diapositiva, no
    // dos errores.
    expect(reading.outline.slideCount, 1);
    expect(reading.outline.issues, isEmpty);
    expect(
      reading.outline
          .sliceAt(reading.outline.text.indexOf('que sigue'))!
          .source
          .id,
      '$banach/va.tex',
    );
  });

  test('sin estructura se leen las referencias sueltas', () async {
    // Un índice viejo no trae `structure`, y la pantalla no puede quedarse
    // en blanco por eso.
    final document = Document(
      id: 'tema-1',
      kind: 'theory',
      language: 'es',
      titles: const {'es': 'Tema 1'},
      profiles: const [],
      unitRefs: const ['analysis/normed/definition'],
    );
    final reading = await read(
      document,
      language: 'es',
      files: {'$definition/es.tex': 'Definición.\n'},
    );
    expect(reading.files.single.reference, 'analysis/normed/definition');
  });
}
