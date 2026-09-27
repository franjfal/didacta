/// Las palabras que cambiaron dentro de una línea.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/word_diff.dart';

String changed(List<WordSpan>? spans) => [
  for (final span in spans ?? const <WordSpan>[])
    if (span.changed) '[${span.text}]' else span.text,
].join();

void main() {
  test('marca solo lo que cambió', () {
    expect(
      changed(
        wordSpans('Sea una sucesión de Cauchy.', 'Sea una serie de Cauchy.'),
      ),
      'Sea una [sucesión] de Cauchy.',
    );
  });

  test('en LaTeX, la pieza y no el comando entero', () {
    expect(
      changed(wordSpans(r'$\frac{a}{b}$', r'$\frac{a}{c}$')),
      r'$\frac{a}{[b]}$',
    );
  });

  test('dos palabras seguidas son una marca, con su espacio', () {
    expect(
      changed(
        wordSpans(
          'un espacio vectorial normado completo',
          'un espacio de Banach completo',
        ),
      ),
      'un espacio [vectorial normado] completo',
    );
  });

  test('dos líneas que no se parecen no se marcan', () {
    // Es una línea nueva, no una cambiada: marcarla entera no dice nada que
    // no diga ya su color.
    expect(wordSpans('Teorema de Baire.', 'Sea X un espacio métrico.'), isNull);
  });

  test('cada quitada con la añadida que ocupa su sitio', () {
    final pairs = pairChangedLines([
      (removed: false, added: false, text: 'igual'),
      (removed: true, added: false, text: 'antes 1'),
      (removed: true, added: false, text: 'antes 2'),
      (removed: false, added: true, text: 'ahora 1'),
      (removed: false, added: false, text: 'igual'),
      (removed: false, added: true, text: 'nueva, sin pareja'),
    ]);
    expect(pairs, {1: 'ahora 1', 3: 'antes 1'});
  });
}
