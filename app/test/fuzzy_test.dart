/// Buscar con una errata: qué se admite, qué no, y que lo parecido va detrás
/// de lo que casa de verdad.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/fuzzy.dart';
import 'package:didacta_app/model/library_filter.dart';

import 'fixture.dart';

void main() {
  group('una errata', () {
    test('las cuatro que se admiten', () {
      expect(withinOneEdit('normados', 'normados'), isTrue);
      expect(withinOneEdit('normadso', 'normados'), isTrue, reason: 'cruzadas');
      expect(withinOneEdit('nomrados', 'normados'), isTrue, reason: 'cruzadas');
      expect(withinOneEdit('normadox', 'normados'), isTrue, reason: 'cambiada');
      expect(withinOneEdit('normdos', 'normados'), isTrue, reason: 'de menos');
      expect(withinOneEdit('normaados', 'normados'), isTrue, reason: 'de más');
    });

    test('dos no', () {
      expect(withinOneEdit('nrmdos', 'normados'), isFalse);
      expect(withinOneEdit('nomradso', 'normados'), isFalse);
      expect(withinOneEdit('limites', 'normados'), isFalse);
    });

    test('también como principio de una palabra, como sin errata', () {
      expect(fuzzyWordMatch('nomrad', 'normados'), isTrue);
      expect(fuzzyWordMatch('difrenc', 'diferenciales'), isTrue);
    });

    test('en las palabras cortas, no: sería otra palabra', () {
      expect(fuzzyWordMatch('cosa', 'caso'), isFalse);
      expect(fuzzyWordMatch('sino', 'seno'), isFalse);
    });
  });

  group('las palabras de una búsqueda', () {
    const text = 'espacios normados definicion';
    Set<String> tokens() => searchTokens(text);

    test('todas tal cual', () {
      expect(
        matchWords(['normados', 'espacios'], text, tokens),
        SearchMatch.exact,
      );
    });

    test('alguna con una errata', () {
      expect(
        matchWords(['nomrados', 'espacios'], text, tokens, typos: {'nomrados'}),
        SearchMatch.near,
      );
    });

    test('una palabra que existe no se busca con errata', () {
      // «nomrados» no es una errata si alguien la ha escrito así en alguna
      // parte: quien la busca, busca eso.
      expect(
        matchWords(['nomrados', 'espacios'], text, tokens),
        SearchMatch.none,
      );
    });

    test('una que no está, ni con una errata, deja fuera', () {
      expect(
        matchWords(['nomrados', 'banach'], text, tokens),
        SearchMatch.none,
      );
    });
  });

  group('en la biblioteca', () {
    final units = catalogueWith(defaultUnits()).units;

    test('una errata encuentra lo que sin ella', () {
      final exact = LibraryFilter(
        language: 'es',
        query: 'normados',
      ).apply(units);
      final typo = LibraryFilter(
        language: 'es',
        query: 'nomrados',
      ).apply(units);
      expect(exact, isNotEmpty);
      expect(typo, exact);
    });

    test('bien escrita, solo lo que la dice: nada «parecido»', () {
      final filter = LibraryFilter(language: 'es', query: 'normados');
      final typos = filter.typosIn(units);
      expect(typos, isEmpty);
      for (final unit in filter.apply(units)) {
        expect(filter.queryMatch(unit, typos: typos), SearchMatch.exact);
      }
    });

    test('con una errata, lo parecido y contado aparte', () {
      final filter = LibraryFilter(language: 'es', query: 'nomrados');
      final typos = filter.typosIn(units);
      expect(typos, {'nomrados'});
      final found = filter.apply(units);
      expect(found, isNotEmpty);
      for (final unit in found) {
        expect(filter.queryMatch(unit, typos: typos), SearchMatch.near);
      }
    });
  });
}
