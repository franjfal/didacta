/// El orden de la paleta de órdenes.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/palette.dart';

class _Entry implements PaletteCandidate {
  _Entry(this.title, this.group, {this.detail = '', this.keywords = ''});

  @override
  final String title;
  @override
  final PaletteGroup group;
  @override
  final String detail;
  @override
  final String keywords;

  @override
  String toString() => title;
}

List<String> _titles(List<_Entry> entries, String query) => [
  for (final entry in rankPalette(entries, query)) entry.title,
];

void main() {
  final entries = [
    _Entry('Análisis funcional avanzado', PaletteGroup.course),
    _Entry('Análisis', PaletteGroup.course),
    _Entry('Ir a la biblioteca', PaletteGroup.screen),
    _Entry('Espacios normados', PaletteGroup.unit, detail: 'content/analysis'),
    _Entry(
      'Ver el PDF',
      PaletteGroup.here,
      keywords: 'compilado abrir documento',
    ),
    _Entry('Apariencia oscura', PaletteGroup.action, keywords: 'modo noche'),
    _Entry('Compilar', PaletteGroup.here),
    _Entry('Compilar lo desactualizado', PaletteGroup.action),
  ];

  test('sin nada escrito, todo en el orden en que viene', () {
    expect(_titles(entries, ''), [for (final entry in entries) entry.title]);
  });

  test('sin tildes y sin mayúsculas', () {
    expect(_titles(entries, 'analisis').first, 'Análisis');
  });

  test('lo que empieza por lo escrito, primero; y lo más corto', () {
    expect(_titles(entries, 'anal'), [
      'Análisis',
      'Análisis funcional avanzado',
      // Por el detalle, después.
      'Espacios normados',
    ]);
  });

  test('a igualdad, lo de esta pantalla va antes que las órdenes', () {
    expect(_titles(entries, 'compilar'), [
      'Compilar',
      'Compilar lo desactualizado',
    ]);
  });

  test('por una palabra que empieza así, antes que por el medio', () {
    expect(_titles(entries, 'biblio').first, 'Ir a la biblioteca');
  });

  test('por las palabras clave, sin enseñarlas', () {
    expect(_titles(entries, 'noche'), ['Apariencia oscura']);
    expect(_titles(entries, 'pdf'), ['Ver el PDF']);
  });

  test('con una errata, también, y detrás', () {
    expect(_titles(entries, 'nomrados'), ['Espacios normados']);
  });

  test('lo que no casa, fuera', () {
    expect(_titles(entries, 'zzzz'), isEmpty);
  });

  test('como mucho [paletteLimit]', () {
    final many = [
      for (var i = 0; i < 200; i += 1) _Entry('Lección $i', PaletteGroup.unit),
    ];
    expect(rankPalette(many, 'leccion'), hasLength(paletteLimit));
  });
}
