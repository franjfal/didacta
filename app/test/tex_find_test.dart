/// Buscar y reemplazar en el texto: la parte que no es pantalla.
library;

import 'package:flutter/services.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/tex_find.dart';

List<String> found(String text, TexSearch search) => [
  for (final range in findAll(text, search)) range.textInside(text),
];

void main() {
  test('sin mirar mayúsculas, salvo que se pida', () {
    const text = 'Norma, norma y NORMA.';
    expect(found(text, const TexSearch('norma')), hasLength(3));
    expect(found(text, const TexSearch('norma', caseSensitive: true)), [
      'norma',
    ]);
  });

  test('lo escrito se busca tal cual, con sus barras y sus llaves', () {
    const text = r'$\lambda x$ y \lambda{}';
    expect(found(text, const TexSearch(r'\lambda')), hasLength(2));
    expect(found(text, const TexSearch(r'\lambda{}')), [r'\lambda{}']);
  });

  test('con una expresión, y una mal escrita lo dice', () {
    expect(found('a1 b22 c333', const TexSearch(r'\d+', regex: true)), [
      '1',
      '22',
      '333',
    ]);
    expect(
      () => findAll('x', const TexSearch('(', regex: true)),
      throwsFormatException,
    );
  });

  test('las coincidencias vacías no cuentan', () {
    expect(findAll('abc', const TexSearch('^', regex: true)), isEmpty);
    expect(findAll('abc', const TexSearch('')), isEmpty);
  });

  test('la siguiente, dando la vuelta', () {
    final ranges = [
      const TextRange(start: 2, end: 4),
      const TextRange(start: 10, end: 12),
    ];
    expect(nextMatch(ranges, 0), 0);
    expect(nextMatch(ranges, 5), 1);
    expect(nextMatch(ranges, 11), 0);
    expect(nextMatch(const [], 3), -1);
  });

  test(r'reemplazar una, y con $1 lo capturado', () {
    const text = r'\textbf{uno} y \textbf{dos}';
    const search = TexSearch(r'\\textbf\{([^}]*)\}', regex: true);
    final first = findAll(text, search).first;
    final edit = replaceOne(text, first, search, r'\emph{$1}');
    expect(edit.text, r'\emph{uno} y \textbf{dos}');
    expect(edit.end, r'\emph{uno}'.length);
  });

  test('reemplazar todas, de una vez', () {
    final result = replaceAll(
      'la norma, la otra norma',
      const TexSearch('norma'),
      'métrica',
    );
    expect(result.text, 'la métrica, la otra métrica');
    expect(result.count, 2);
    // Sin expresión, `$1` es texto.
    expect(replaceAll('a', const TexSearch('a'), r'$1').text, r'$1');
  });
}
