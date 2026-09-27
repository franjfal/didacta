/// Filtering the library.
///
/// Pure Dart, separate from the widgets, for two reasons. It is the part with
/// rules in it -- which is the part worth testing -- and against 2147 units
/// the cost of getting it wrong is a list that quietly omits things, which is
/// invisible in an interface.
///
/// The filter is immutable and combined with [copyWith], so a view can rebuild
/// from a new value without any question of half-applied state.
library;

import 'fuzzy.dart';
import 'catalogue.dart';
import 'slug.dart';
import '../l10n/tr.dart';

/// How to order the results.
enum LibrarySort {
  /// By path, which groups a topic together -- the order someone browsing a
  /// category expects.
  path,

  /// By title in the current language, for when you know what it is called.
  title,

  /// Most reused first. The units at the top are the ones a change affects
  /// most, which is the question the `usedBy` index exists to answer.
  usage,

  /// Least translated first, for working through what is missing.
  needsWork,
}

/// Which translation states a row must have to be shown.
enum StatusFilter {
  any,

  /// Present in the chosen language, whatever its state.
  present,

  /// Absent in the chosen language: the translation queue.
  missing,

  /// Present but behind the original, or still a draft.
  needsWork,
}

class LibraryFilter {
  const LibraryFilter({
    this.query = '',
    this.category,
    this.kind,
    this.tag,
    this.block,
    this.language = 'es',
    this.status = StatusFilter.any,
    this.sort = LibrarySort.path,
    this.unusedOnly = false,
  });

  final String query;
  final String? category;
  final String? kind;
  final String? tag;

  /// `content` or `problems`. Theory and exercises are browsed differently
  /// often enough to be worth one click.
  final String? block;

  /// The language the listing is *about*: titles are shown in it and the
  /// status filter applies to it.
  final String language;

  final StatusFilter status;
  final LibrarySort sort;

  /// Units no composition references. Worth a switch of its own: after a
  /// migration these are the material that came across and is not being
  /// taught, which is either a gap or a candidate for deletion.
  final bool unusedOnly;

  LibraryFilter copyWith({
    String? query,
    String? language,
    StatusFilter? status,
    LibrarySort? sort,
    bool? unusedOnly,
    // Nullable fields need a way to be cleared, and an omitted named
    // parameter cannot express "set to null". A sentinel would be heavier
    // than these flags.
    String? category,
    bool clearCategory = false,
    String? kind,
    bool clearKind = false,
    String? tag,
    bool clearTag = false,
    String? block,
    bool clearBlock = false,
  }) {
    return LibraryFilter(
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      kind: clearKind ? null : (kind ?? this.kind),
      tag: clearTag ? null : (tag ?? this.tag),
      block: clearBlock ? null : (block ?? this.block),
      language: language ?? this.language,
      status: status ?? this.status,
      sort: sort ?? this.sort,
      unusedOnly: unusedOnly ?? this.unusedOnly,
    );
  }

  /// Whether any facet other than the query is set.
  ///
  /// Separate from [isNarrowed] because the two are shown in different
  /// places: the query lives in the search box, where it is already visible,
  /// and the facets need chips of their own or a filter nobody can see is
  /// silently hiding material.
  bool get hasFacets =>
      category != null ||
      kind != null ||
      tag != null ||
      block != null ||
      status != StatusFilter.any ||
      unusedOnly;

  bool get isNarrowed =>
      query.isNotEmpty ||
      category != null ||
      kind != null ||
      tag != null ||
      block != null ||
      status != StatusFilter.any ||
      unusedOnly;

  /// A short description of what is being shown, for the empty state -- so
  /// "nothing here" says which of six filters is responsible.
  String describe() {
    final parts = <String>[];
    if (query.isNotEmpty) parts.add('«$query»');
    if (block != null) parts.add(block!);
    if (category != null) parts.add(category!);
    if (kind != null) parts.add(kind!);
    if (tag != null) parts.add('#$tag');
    switch (status) {
      case StatusFilter.present:
        parts.add(tr('con {0}', [language]));
      case StatusFilter.missing:
        parts.add(tr('sin {0}', [language]));
      case StatusFilter.needsWork:
        parts.add(tr('{0} por revisar', [language]));
      case StatusFilter.any:
        break;
    }
    if (unusedOnly) parts.add(tr('sin usar'));
    return parts.join(' · ');
  }

  /// Si [unit] pasa el filtro. Con una errata, solo en las palabras de
  /// [typos]: ver [typosIn].
  bool matches(Unit unit, {Set<String> typos = const {}}) {
    if (block != null && unit.block != block) return false;
    if (category != null && unit.category != category) return false;
    if (kind != null && unit.kind != kind) return false;
    if (tag != null && !unit.tags.contains(tag)) return false;
    if (unusedOnly && unit.usedBy.isNotEmpty) return false;

    final state = unit.statusIn(language);
    switch (status) {
      case StatusFilter.present:
        if (!state.exists) return false;
      case StatusFilter.missing:
        if (state.exists) return false;
      case StatusFilter.needsWork:
        if (!state.needsWork) return false;
      case StatusFilter.any:
        break;
    }

    return queryMatch(unit, typos: typos) != SearchMatch.none;
  }

  /// Las palabras buscadas, plegadas como el texto en el que se buscan.
  List<String> get _words => [
    for (final word in fold(query.toLowerCase()).split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];

  /// Las palabras buscadas que no aparecen tal cual en ninguna de [units]:
  /// las únicas que pueden llevar una errata. Ver `model/fuzzy.dart`.
  Set<String> typosIn(Iterable<Unit> units) {
    if (query.isEmpty) return const {};
    return {
      for (final word in _words)
        if (word.length >= fuzzyMinLength &&
            !units.any((unit) => unit.searchable.contains(word)))
          word,
    };
  }

  /// Cómo casa lo escrito en el buscador con [unit]: tal cual, con una errata
  /// (en las palabras de [typos]) o nada. Sin nada escrito, tal cual.
  SearchMatch queryMatch(Unit unit, {Set<String> typos = const {}}) {
    if (query.isEmpty) return SearchMatch.exact;
    return matchWords(
      _words,
      unit.searchable,
      () => unit.searchTokens,
      typos: typos,
    );
  }

  /// [units] con lo que casa tal cual delante de lo que casa con una errata,
  /// y en el orden en que venían dentro de cada grupo.
  List<Unit> exactFirst(Iterable<Unit> units) {
    final typos = typosIn(units);
    final exact = <Unit>[];
    final near = <Unit>[];
    for (final unit in units) {
      switch (queryMatch(unit, typos: typos)) {
        case SearchMatch.exact:
          exact.add(unit);
        case SearchMatch.near:
          near.add(unit);
        case SearchMatch.none:
          break;
      }
    }
    return [...exact, ...near];
  }

  /// The filtered, sorted result: what matches exactly first, sorted; then
  /// what matches with a typo, sorted the same way.
  List<Unit> apply(List<Unit> units) {
    final typos = typosIn(units);
    final result = _sorted([
      for (final unit in units)
        if (matches(unit, typos: typos)) unit,
    ]);
    return query.isEmpty ? result : exactFirst(result);
  }

  List<Unit> _sorted(List<Unit> result) {
    switch (sort) {
      case LibrarySort.path:
        result.sort((a, b) => a.path.compareTo(b.path));
      case LibrarySort.title:
        // Plegando las tildes: comparando a secas, «Álgebra» iba detrás de
        // la Z.
        result.sort(
          (a, b) => compareTitles(a.title(language), b.title(language)),
        );
      case LibrarySort.usage:
        result.sort((a, b) {
          final byUsage = b.usedBy.length.compareTo(a.usedBy.length);
          // Ties broken by path rather than left to chance: an unstable list
          // that reshuffles between rebuilds is worse than an arbitrary order.
          return byUsage != 0 ? byUsage : a.path.compareTo(b.path);
        });
      case LibrarySort.needsWork:
        int rank(Unit unit) {
          final state = unit.statusIn(language);
          if (state == TranslationStatus.missing) return 0;
          if (state == TranslationStatus.outdated) return 1;
          if (state == TranslationStatus.draft) return 2;
          return 3;
        }

        result.sort((a, b) {
          final byRank = rank(a).compareTo(rank(b));
          return byRank != 0 ? byRank : a.path.compareTo(b.path);
        });
    }
    return result;
  }
}

/// Counts for the sidebar, computed once per filter change.
///
/// Each count is "how many would I see if I clicked this", which means every
/// facet is counted with the *other* filters applied but not its own --
/// otherwise clicking a category shows 1 and every other category shows 0,
/// which tells the reader nothing about where the material is.
class LibraryFacets {
  const LibraryFacets({
    required this.total,
    required this.shown,
    required this.byCategory,
    required this.byKind,
    required this.byBlock,
    required this.byStatus,
  });

  factory LibraryFacets.of(List<Unit> units, LibraryFilter filter) {
    final typos = filter.typosIn(units);
    final byCategory = <String, int>{};
    final byKind = <String, int>{};
    final byBlock = <String, int>{};
    final byStatus = <TranslationStatus, int>{};

    for (final unit in units) {
      if (filter.copyWith(clearCategory: true).matches(unit, typos: typos)) {
        byCategory[unit.category] = (byCategory[unit.category] ?? 0) + 1;
      }
      if (filter.copyWith(clearKind: true).matches(unit, typos: typos)) {
        byKind[unit.kind] = (byKind[unit.kind] ?? 0) + 1;
      }
      if (filter.copyWith(clearBlock: true).matches(unit, typos: typos)) {
        byBlock[unit.block] = (byBlock[unit.block] ?? 0) + 1;
      }
      if (filter.matches(unit, typos: typos)) {
        final state = unit.statusIn(filter.language);
        byStatus[state] = (byStatus[state] ?? 0) + 1;
      }
    }

    return LibraryFacets(
      total: units.length,
      shown: units.where((unit) => filter.matches(unit, typos: typos)).length,
      byCategory: byCategory,
      byKind: byKind,
      byBlock: byBlock,
      byStatus: byStatus,
    );
  }

  final int total;
  final int shown;
  final Map<String, int> byCategory;
  final Map<String, int> byKind;
  final Map<String, int> byBlock;
  final Map<TranslationStatus, int> byStatus;

  /// Categories with anything in them, most populated first -- a sidebar of 51
  /// categories in alphabetical order buries the ones being taught.
  List<String> get categoriesByCount {
    final names = byCategory.keys.toList();
    names.sort((a, b) {
      final byCount = (byCategory[b] ?? 0).compareTo(byCategory[a] ?? 0);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return names;
  }
}
