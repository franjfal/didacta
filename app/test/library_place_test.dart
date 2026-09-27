/// La biblioteca en su dirección: ida y vuelta.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/library_filter.dart';
import 'package:didacta_app/model/library_place.dart';
import 'package:didacta_app/router.dart';

void main() {
  test('de salida, la dirección no lleva nada', () {
    expect(Routes.library(), '/');
    expect(const LibraryPlace().toQuery(), isEmpty);
  });

  test('ida y vuelta, con todo puesto', () {
    const place = LibraryPlace(
      query: 'espacio normado',
      block: 'problems',
      kind: 'problem',
      tag: 'banach',
      status: StatusFilter.missing,
      sort: LibrarySort.title,
      unusedOnly: true,
      browse: ['analysis', 'normed', 'norma'],
      inText: true,
    );
    final url = Routes.library(place);
    expect(url, startsWith('/?q=espacio+normado'));
    expect(url, contains('estado=falta'));
    expect(url, contains('texto=1'));
    expect(url, contains('en=analysis%2Fnormed%2Fnorma'));
    expect(LibraryPlace.fromQuery(Uri.parse(url).queryParameters), place);
  });

  test('lo que no se entiende se ignora', () {
    final place = LibraryPlace.fromQuery(const {
      'estado': 'raro',
      'orden': '',
      'sinusar': 'si',
      'en': '/a//b/c/d/',
    });
    expect(place.status, StatusFilter.any);
    expect(place.sort, LibrarySort.path);
    expect(place.unusedOnly, isFalse);
    expect(place.browse, ['a', 'b', 'c']);
  });

  test('los filtros, en el idioma que se mira', () {
    final filter = const LibraryPlace(
      query: 'x',
      kind: 'problem',
    ).filterIn('va');
    expect(filter.language, 'va');
    expect(filter.kind, 'problem');
    expect(LibraryPlace.of(filter, const ['a']).browse, ['a']);
  });
}
