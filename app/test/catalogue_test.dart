/// Tests for the parsing and filtering, which is where the rules live.
///
/// No widgets here on purpose. Against 2147 units a filter that quietly omits
/// rows is invisible in an interface, so it is the part worth pinning down.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/library_filter.dart';

/// A unit record shaped like the generator's, with category and topic derived
/// from the path the way the real index does -- deriving them here rather than
/// defaulting to a fixed pair is what makes a fixture with several categories
/// behave like the real thing.
Map<String, dynamic> unitJson({
  String path = 'content/analysis/normed-spaces/definition',
  String kind = 'theory',
  String? category,
  String? topic,
  List<String> tags = const ['norm'],
  Map<String, String> title = const {'es': 'Espacios normados'},
  String reference = 'es',
  Map<String, String> statuses = const {
    'es': 'source',
    'va': 'translated',
    'en': 'missing',
  },
  List<Map<String, String>> usedBy = const [],
}) {
  final parts = path.split('/');
  return {
    'id': path.replaceAll('/', '.'),
    'path': path,
    'area': parts.first,
    'kind': kind,
    'category': category ?? (parts.length > 1 ? parts[1] : ''),
    'topic': topic ?? (parts.length > 2 ? parts[2] : ''),
    'tags': tags,
    'title': title,
    'reference': reference,
    'languages': {
      for (final entry in statuses.entries)
        entry.key: {'status': entry.value, 'exists': entry.value != 'missing'},
    },
    'prerequisites': const <String>[],
    'objectives': const <String>[],
    'usedBy': usedBy,
    'warnings': const <String>[],
  };
}

Catalogue catalogueOf(
  List<Map<String, dynamic>> units, {
  List<Map<String, dynamic>> courses = const [],
}) {
  return Catalogue.fromIndex(
    manifest: {
      'schemaVersion': supportedSchemaVersion,
      'name': 'Test',
      'languages': ['es', 'va', 'en'],
      'defaultLanguage': 'es',
      'contentHash': 'abc123',
      'profiles': [
        {'id': 'slides', 'family': 'slides', 'documentClass': 'beamer'},
        {'id': 'notes', 'family': 'notes', 'documentClass': 'article'},
      ],
      'errors': <String>[],
    },
    units: {'schemaVersion': supportedSchemaVersion, 'units': units},
    courses: {'schemaVersion': supportedSchemaVersion, 'courses': courses},
  );
}

void main() {
  group('schema version', () {
    test('a version this app does not know is refused, not guessed at', () {
      // A field that silently changed meaning is worse than a file that fails
      // to load, and the message has to say what to do about it.
      expect(
        () => Catalogue.fromIndex(
          manifest: {'schemaVersion': 99, 'name': 'x'},
          units: {'schemaVersion': 99, 'units': const []},
          courses: {'schemaVersion': 99, 'courses': const []},
        ),
        throwsA(
          isA<CatalogueFormatException>().having(
            (e) => e.message,
            'message',
            contains('didacta index'),
          ),
        ),
      );
    });

    test('a missing version is refused too', () {
      expect(
        () => Catalogue.fromIndex(
          manifest: {'name': 'x'},
          units: {'units': const []},
          courses: {'courses': const []},
        ),
        throwsA(isA<CatalogueFormatException>()),
      );
    });
  });

  group('unit', () {
    test('the reference drops the area, as a composition writes it', () {
      // year.yaml says `analysis/normed-spaces/definition`; the LaTeX side
      // appends content/ or problems/ itself.
      final unit = Unit.fromJson(unitJson());
      expect(unit.reference_, 'analysis/normed-spaces/definition');
      expect(unit.isProblem, isFalse);

      final problem = Unit.fromJson(
        unitJson(path: 'problems/analysis/normed-spaces/norm-axioms'),
      );
      expect(problem.reference_, 'analysis/normed-spaces/norm-axioms');
      expect(problem.isProblem, isTrue);
    });

    test('a title falls back rather than showing an empty row', () {
      final unit = Unit.fromJson(unitJson(title: {'es': 'Espacios normados'}));
      expect(unit.title('es'), 'Espacios normados');
      expect(unit.title('en'), 'Espacios normados');
      expect(unit.titleIsFallback('en'), isTrue);
      expect(unit.titleIsFallback('es'), isFalse);
    });

    test('a unit with no title at all shows its id', () {
      // Real in migrated material: 572 documents took their title from a
      // folder name because the file declared none.
      final unit = Unit.fromJson(unitJson(title: const {}));
      expect(unit.title('es'), 'content.analysis.normed-spaces.definition');
    });

    test('the status of an undeclared language is missing', () {
      final unit = Unit.fromJson(unitJson(statuses: const {'es': 'source'}));
      expect(unit.statusIn('va'), TranslationStatus.missing);
      expect(unit.statusIn('va').exists, isFalse);
    });

    test('outdated counts as needing work', () {
      // The original has moved on, so the translation is behind whatever the
      // metadata claims.
      expect(TranslationStatus.outdated.needsWork, isTrue);
      expect(TranslationStatus.outdated.exists, isTrue);
      expect(TranslationStatus.reviewed.needsWork, isFalse);
      expect(TranslationStatus.missing.needsWork, isTrue);
    });
  });

  group('filter', () {
    final units = [
      Unit.fromJson(
        unitJson(
          path: 'content/analysis/normed-spaces/definition',
          tags: const ['norm', 'definition'],
          title: const {'es': 'Espacios normados', 'va': 'Espais normats'},
          usedBy: const [
            {'course': 'am-iii', 'year': '2025-2026', 'document': 'tema-1'},
            {'course': 'am-iii', 'year': '2024-2025', 'document': 'tema-1'},
          ],
        ),
      ),
      Unit.fromJson(
        unitJson(
          path: 'content/analysis/normed-spaces/induced-metric',
          title: const {'es': 'Métrica inducida'},
          statuses: const {'es': 'source', 'va': 'missing', 'en': 'missing'},
        ),
      ),
      Unit.fromJson(
        unitJson(
          path: 'problems/analysis/normed-spaces/norm-axioms',
          kind: 'problem',
          title: const {'es': 'Axiomas de norma'},
          statuses: const {'es': 'draft', 'va': 'missing', 'en': 'missing'},
          usedBy: const [
            {'course': 'am-iii', 'year': '2025-2026', 'document': 'hoja-1'},
          ],
        ),
      ),
      Unit.fromJson(
        unitJson(
          path: 'content/functional/hilbert/projection',
          tags: const ['hilbert'],
          title: const {'es': 'Proyección ortogonal'},
        ),
      ),
    ];

    test('an empty filter shows everything', () {
      expect(const LibraryFilter().apply(units).length, 4);
      expect(const LibraryFilter().isNarrowed, isFalse);
    });

    test('el bloque manda, y no la carpeta ni el kind', () {
      // El fallo que esto fija: al fundir los dos árboles, 42 unidades del
      // bloque de problemas --catorce de ellas explicaciones teóricas--
      // pasaron a vivir en content/ y la biblioteca las pintó todas como
      // teoría, porque clasificaba por la carpeta.
      final explicacion = Unit.fromJson({
        'path': 'content/analisis/recta-real/valor-absoluto',
        'area': 'content',
        'block': 'problems',
        'kind': 'theory',
        'category': 'analisis',
        'topic': 'la-recta-real',
        'title': {'es': 'El valor absoluto'},
        'languages': const {},
      });
      expect(explicacion.isProblem, isTrue, reason: 'está en el bloque');
      expect(explicacion.kind, 'theory', reason: 'y sigue siendo teoría');
      expect(
        const LibraryFilter(block: 'problems').apply([explicacion]),
        hasLength(1),
      );
      expect(const LibraryFilter(block: 'theory').apply([explicacion]), isEmpty);
    });

    test('un índice viejo, sin bloque, lo deduce del árbol', () {
      // Un catálogo generado antes de que el bloque existiera se sigue
      // leyendo: sin esto, todo saldría como teoría el día que alguien abra
      // la aplicación contra un repositorio sin reindexar.
      final viejo = Unit.fromJson({
        'path': 'problems/analisis/induccion/suma',
        'area': 'problems',
        'kind': 'problem',
        'languages': const {},
      });
      expect(viejo.block, 'problems');
      expect(viejo.isProblem, isTrue);
    });

    test('by block', () {
      final problems = const LibraryFilter(block: 'problems').apply(units);
      expect(problems.length, 1);
      expect(problems.single.kind, 'problem');
    });

    test('by category and kind', () {
      expect(
        const LibraryFilter(category: 'functional').apply(units).length,
        1,
      );
      expect(const LibraryFilter(kind: 'theory').apply(units).length, 3);
    });

    test('by tag', () {
      expect(const LibraryFilter(tag: 'hilbert').apply(units).length, 1);
    });

    test('every word of a query must match, so typing narrows', () {
      // "normados espacios" in either order finds the one unit; adding a word
      // that does not appear finds none.
      expect(const LibraryFilter(query: 'normados').apply(units).length, 1);
      expect(
        const LibraryFilter(query: 'espacios normados').apply(units).length,
        1,
      );
      expect(
        const LibraryFilter(query: 'normados hilbert').apply(units).length,
        0,
      );
    });

    test('a query matches the path and the tags, not only the title', () {
      expect(
        const LibraryFilter(query: 'induced-metric').apply(units).length,
        1,
      );
      expect(const LibraryFilter(query: 'definition').apply(units).length, 1);
    });

    test('a query is case-insensitive', () {
      expect(const LibraryFilter(query: 'ESPACIOS').apply(units).length, 1);
    });

    test('missing in a language is the translation queue', () {
      final missing = const LibraryFilter(
        language: 'va',
        status: StatusFilter.missing,
      ).apply(units);
      expect(missing.length, 2);
      for (final unit in missing) {
        expect(unit.statusIn('va').exists, isFalse);
      }
    });

    test('present in a language excludes what is absent', () {
      final present = const LibraryFilter(
        language: 'va',
        status: StatusFilter.present,
      ).apply(units);
      expect(present.length, 2);
      for (final unit in present) {
        expect(unit.statusIn('va').exists, isTrue);
      }
    });

    test('needs work includes drafts as well as gaps', () {
      final work = const LibraryFilter(
        language: 'es',
        status: StatusFilter.needsWork,
      ).apply(units);
      // Only the problem sheet is a draft in Castilian.
      expect(work.length, 1);
      expect(work.single.kind, 'problem');
    });

    test('unused only finds what no composition references', () {
      final unused = const LibraryFilter(unusedOnly: true).apply(units);
      expect(unused.length, 2);
      for (final unit in unused) {
        expect(unit.usedBy, isEmpty);
      }
    });

    test('sorting by usage puts the most reused first, ties by path', () {
      final sorted = const LibraryFilter(sort: LibrarySort.usage).apply(units);
      expect(sorted.first.usedBy.length, 2);
      // The two unused units keep a stable order rather than reshuffling.
      final tail = sorted.sublist(2).map((unit) => unit.path).toList();
      expect(tail, List<String>.from(tail)..sort());
    });

    test('sorting by needs-work puts missing before draft before done', () {
      final sorted = const LibraryFilter(
        language: 'va',
        sort: LibrarySort.needsWork,
      ).apply(units);
      expect(sorted.last.statusIn('va'), TranslationStatus.translated);
    });

    test('sorting by title uses the chosen language', () {
      final sorted = const LibraryFilter(
        language: 'va',
        sort: LibrarySort.title,
      ).apply(units);
      // Sorted by what is actually shown, which for a unit with no Valencian
      // title is its Castilian one -- so `Axiomas de norma` comes first and
      // the Valencian `Espais normats` sorts under E, not under the Castilian
      // `Espacios normados` it replaces.
      expect(sorted.first.title('va'), 'Axiomas de norma');
      expect(
        sorted.map((unit) => unit.title('va')),
        containsAllInOrder(['Axiomas de norma', 'Espais normats']),
      );
    });

    test('copyWith can clear a facet as well as set one', () {
      const filter = LibraryFilter(category: 'analysis', kind: 'theory');
      expect(filter.copyWith(clearCategory: true).category, isNull);
      expect(filter.copyWith(clearCategory: true).kind, 'theory');
      expect(filter.copyWith(category: 'functional').category, 'functional');
    });

    test('describe names every active facet, for the empty state', () {
      const filter = LibraryFilter(
        query: 'norma',
        category: 'analysis',
        language: 'va',
        status: StatusFilter.missing,
        unusedOnly: true,
      );
      final text = filter.describe();
      expect(text, contains('norma'));
      expect(text, contains('analysis'));
      expect(text, contains('sin va'));
      expect(text, contains('sin usar'));
    });
  });

  group('facets', () {
    final units = [
      Unit.fromJson(unitJson(path: 'content/a/t/one')),
      Unit.fromJson(unitJson(path: 'content/a/t/two')),
      Unit.fromJson(unitJson(path: 'content/b/t/three')),
      Unit.fromJson(unitJson(path: 'problems/a/t/four', kind: 'problem')),
    ];

    test('a facet is counted without its own filter applied', () {
      // Otherwise choosing a category shows 1 and every other category shows
      // 0, which says nothing about where the material is.
      final facets = LibraryFacets.of(
        units,
        const LibraryFilter(category: 'a'),
      );
      expect(facets.byCategory['a'], 3);
      expect(facets.byCategory['b'], 1);
      expect(facets.shown, 3);
      expect(facets.total, 4);
    });

    test('other facets still constrain the count', () {
      final facets = LibraryFacets.of(
        units,
        const LibraryFilter(block: 'theory', category: 'a'),
      );
      // Category `a` has three units but only two are in content/.
      expect(facets.byCategory['a'], 2);
    });

    test('categories are ordered by how much is in them', () {
      final facets = LibraryFacets.of(units, const LibraryFilter());
      expect(facets.categoriesByCount.first, 'a');
    });

    test('the status breakdown is for the chosen language', () {
      final facets = LibraryFacets.of(
        units,
        const LibraryFilter(language: 'en'),
      );
      expect(facets.byStatus[TranslationStatus.missing], 4);
    });
  });

  group('catalogue', () {
    test('a composition reference resolves into either tree', () {
      final catalogue = catalogueOf([
        unitJson(path: 'content/analysis/normed-spaces/definition'),
        unitJson(path: 'problems/analysis/normed-spaces/norm-axioms'),
      ]);
      expect(
        catalogue.unitByReference('analysis/normed-spaces/definition')?.area,
        'content',
      );
      expect(
        catalogue.unitByReference('analysis/normed-spaces/norm-axioms')?.area,
        'problems',
      );
      expect(catalogue.unitByReference('nope/at/all'), isNull);
    });

    test('a reference with stray slashes still resolves', () {
      final catalogue = catalogueOf([unitJson(path: 'content/a/b/c')]);
      expect(catalogue.unitByReference('/a/b/c/'), isNotNull);
    });

    test('the profile list comes from the index, not from the app', () {
      final catalogue = catalogueOf([unitJson()]);
      expect(
        catalogue.profiles.map((p) => p.id),
        containsAll(['slides', 'notes']),
      );
      expect(
        catalogue.profiles.firstWhere((p) => p.id == 'slides').isSlides,
        isTrue,
      );
    });

    test('repository errors are carried through, not swallowed', () {
      final catalogue = Catalogue.fromIndex(
        manifest: {
          'schemaVersion': supportedSchemaVersion,
          'name': 'Test',
          'languages': ['es'],
          'defaultLanguage': 'es',
          'contentHash': 'x',
          'profiles': const [],
          'errors': ['unit.yaml: unknown kind `practical`'],
        },
        units: {'schemaVersion': supportedSchemaVersion, 'units': const []},
        courses: {'schemaVersion': supportedSchemaVersion, 'courses': const []},
      );
      expect(catalogue.errors, hasLength(1));
    });

    test('course years come back newest first', () {
      final catalogue = catalogueOf(
        [],
        courses: [
          {
            'id': 'am-iii',
            'title': {'va': 'Anàlisi III'},
            'language': 'va',
            'years': {
              '2024-2025': {
                'year': '2024-2025',
                'language': 'va',
                'documents': [],
              },
              '2025-2026': {
                'year': '2025-2026',
                'language': 'va',
                'documents': [],
              },
            },
          },
        ],
      );
      expect(catalogue.courses.single.sortedYears, ['2025-2026', '2024-2025']);
    });

    test(
      'a document with no explicit profiles leaves the choice to the engine',
      () {
        final catalogue = catalogueOf(
          [],
          courses: [
            {
              'id': 'am-iii',
              'title': {'va': 'Anàlisi III'},
              'language': 'va',
              'years': {
                '2025-2026': {
                  'year': '2025-2026',
                  'language': 'va',
                  'documents': [
                    {
                      'id': 'tema-1',
                      'kind': 'theory',
                      'language': 'va',
                      'title': {'va': 'Tema 1'},
                      'profiles': [],
                      'unitRefs': [],
                    },
                  ],
                },
              },
            },
          ],
        );
        final document =
            catalogue.courses.single.years['2025-2026']!.documents.single;
        expect(document.profiles, isEmpty);
        expect(document.title(), 'Tema 1');
      },
    );
  });
}
