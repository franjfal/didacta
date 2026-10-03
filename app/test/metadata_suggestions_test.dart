/// Lo que se sugiere en los metadatos de una lección.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/metadata_suggestions.dart';

import 'fixture.dart';

MetadataSuggestions suggestions() => MetadataSuggestions.of(
  catalogueWith([
    ...defaultUnits(),
    unitJson(
      path: 'content/analysis/series/ratio',
      topic: 'series',
      title: const {'es': 'Criterio del cociente'},
      tags: const ['series', 'convergencia'],
    ),
  ]),
  language: 'es',
);

List<String> values(List<Suggestion> found) => [
  for (final suggestion in found) suggestion.value,
];

void main() {
  test('las categorías, la más usada primero', () {
    final found = suggestions().categories('');
    expect(values(found), ['analysis', 'algebra']);
    expect(found.first.uses, 4);
  });

  test('sin mirar tildes ni mayúsculas', () {
    expect(values(suggestions().categories('ÁLG')), ['ÁLG', 'algebra']);
  });

  test('lo escrito que no existe va primero, marcado como nuevo', () {
    final found = suggestions().categories('analisys');
    expect(found.first.isNew, isTrue);
    expect(found.first.detail, 'categoría nueva');
    // Lo que existe, no.
    expect(suggestions().categories('analysis').first.isNew, isFalse);
  });

  test('los temas de la categoría, antes que los de las demás', () {
    final found = suggestions().topics('', category: 'algebra');
    expect(values(found).first, 'matrices');
    expect(values(found), containsAll(['normed', 'series']));
    // Un tema que existe en otra categoría no es nuevo.
    expect(
      suggestions().topics('matrices', category: 'analysis').first.isNew,
      isFalse,
    );
  });

  test('las etiquetas, sin las que ya tiene', () {
    final found = suggestions().tags('', except: {'norma'});
    expect(values(found), isNot(contains('norma')));
    expect(values(found), contains('banach'));
    expect(suggestions().tags('hilb').first.detail, 'etiqueta nueva');
  });

  test(
    'los prerrequisitos, por la ruta o por el título, y se escribe el id',
    () {
      expect(values(suggestions().units('analysis/series')), [
        'analysis.series.ratio',
      ]);
      final byTitle = suggestions().units('cociente');
      expect(values(byTitle), ['analysis.series.ratio']);
      expect(byTitle.single.detail, 'Criterio del cociente');
      expect(
        values(suggestions().units('', except: 'analysis.series.ratio')),
        isNot(contains('analysis.series.ratio')),
      );
      expect(suggestions().knowsUnit('analysis/normed/definition'), isTrue);
      expect(suggestions().knowsUnit('analysis/nada'), isFalse);
    },
  );
}
