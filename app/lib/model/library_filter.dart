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

import 'catalogue.dart';

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
    this.area,
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
  final String? area;

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
    String? area,
    bool clearArea = false,
  }) {
    return LibraryFilter(
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      kind: clearKind ? null : (kind ?? this.kind),
      tag: clearTag ? null : (tag ?? this.tag),
      area: clearArea ? null : (area ?? this.area),
      language: language ?? this.language,
      status: status ?? this.status,
      sort: sort ?? this.sort,
      unusedOnly: unusedOnly ?? this.unusedOnly,
    );
  }

  bool get isNarrowed =>
      query.isNotEmpty ||
      category != null ||
      kind != null ||
      tag != null ||
      area != null ||
      status != StatusFilter.any ||
      unusedOnly;

  /// A short description of what is being shown, for the empty state -- so
  /// "nothing here" says which of six filters is responsible.
  String describe() {
    final parts = <String>[];
    if (query.isNotEmpty) parts.add('«$query»');
    if (area != null) parts.add(area!);
    if (category != null) parts.add(category!);
    if (kind != null) parts.add(kind!);
    if (tag != null) parts.add('#$tag');
    switch (status) {
      case StatusFilter.present:
        parts.add('con $language');
      case StatusFilter.missing:
        parts.add('sin $language');
      case StatusFilter.needsWork:
        parts.add('$language por revisar');
      case StatusFilter.any:
        break;
    }
    if (unusedOnly) parts.add('sin usar');
    return parts.join(' · ');
  }

  bool matches(Unit unit) {
    if (area != null && unit.area != area) return false;
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

    if (query.isNotEmpty) {
      // Every whitespace-separated word must appear somewhere, so typing
      // "normados problemas" narrows instead of finding nothing.
      final haystack = unit.searchable;
      for (final word in query.toLowerCase().split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        if (!haystack.contains(word)) return false;
      }
    }
    return true;
  }

  /// The filtered, sorted result.
  List<Unit> apply(List<Unit> units) {
    final result = units.where(matches).toList();
    switch (sort) {
      case LibrarySort.path:
        result.sort((a, b) => a.path.compareTo(b.path));
      case LibrarySort.title:
        result.sort((a, b) => a
            .title(language)
            .toLowerCase()
            .compareTo(b.title(language).toLowerCase()));
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
    required this.byArea,
    required this.byStatus,
  });

  factory LibraryFacets.of(List<Unit> units, LibraryFilter filter) {
    final byCategory = <String, int>{};
    final byKind = <String, int>{};
    final byArea = <String, int>{};
    final byStatus = <TranslationStatus, int>{};

    for (final unit in units) {
      if (filter.copyWith(clearCategory: true).matches(unit)) {
        byCategory[unit.category] = (byCategory[unit.category] ?? 0) + 1;
      }
      if (filter.copyWith(clearKind: true).matches(unit)) {
        byKind[unit.kind] = (byKind[unit.kind] ?? 0) + 1;
      }
      if (filter.copyWith(clearArea: true).matches(unit)) {
        byArea[unit.area] = (byArea[unit.area] ?? 0) + 1;
      }
      if (filter.matches(unit)) {
        final state = unit.statusIn(filter.language);
        byStatus[state] = (byStatus[state] ?? 0) + 1;
      }
    }

    return LibraryFacets(
      total: units.length,
      shown: units.where(filter.matches).length,
      byCategory: byCategory,
      byKind: byKind,
      byArea: byArea,
      byStatus: byStatus,
    );
  }

  final int total;
  final int shown;
  final Map<String, int> byCategory;
  final Map<String, int> byKind;
  final Map<String, int> byArea;
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
