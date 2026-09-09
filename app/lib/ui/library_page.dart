/// The library: every unit, filtered.
///
/// The screen the platform is judged on first, because it is the one that has
/// to make 2147 units navigable. Three things drive it:
///
/// **The list is virtualised.** A builder over the filtered result, so
/// scrolling 2147 rows costs what scrolling 20 does.
///
/// **Filtering is one value, replaced whole.** Every control writes a new
/// [LibraryFilter]; nothing holds a piece of it. There is no way to end up
/// with the sidebar showing one thing and the list another.
///
/// **The counts say where the material is.** 51 categories in alphabetical
/// order buries the ones being taught, so they are ordered by how much is in
/// them and each says what clicking it would give.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../model/library_filter.dart';
import '../router.dart';
import 'shell.dart';
import 'theme.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryFilter? _filter;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    // The language lives in the session so the rail's translation count and
    // this list cannot disagree about which language they mean.
    _filter ??= LibraryFilter(language: session.language);
    if (_filter!.language != session.language) {
      _filter = _filter!.copyWith(language: session.language);
    }

    final filter = _filter!;
    final units = filter.apply(session.catalogue.units);
    final facets = LibraryFacets.of(session.catalogue.units, filter);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        // A second breakpoint, below the one that hides the filter panel: on
        // a phone the search field plus a language selector plus an order
        // menu do not fit, and squeezing the search box to nothing to keep
        // two controls that belong in the sheet is the wrong trade.
        final compact = constraints.maxWidth < 560;

        return Column(
          children: [
            PageHeader(
              title: 'Biblioteca',
              subtitle: facets.shown == facets.total
                  ? '${facets.total} unidades'
                  : '${facets.shown} de ${facets.total} unidades · '
                        '${filter.describe()}',
              bottom: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          hintText: 'Buscar por título, ruta o etiqueta…',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: filter.query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  tooltip: 'Limpiar',
                                  onPressed: () {
                                    _search.clear();
                                    setState(
                                      () =>
                                          _filter = filter.copyWith(query: ''),
                                    );
                                  },
                                ),
                        ),
                        onChanged: (value) => setState(
                          () => _filter = filter.copyWith(query: value),
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        segments: [
                          for (final code in session.catalogue.languages)
                            ButtonSegment(value: code, label: Text(code)),
                        ],
                        selected: {filter.language},
                        onSelectionChanged: (values) =>
                            sessionOf(context).language = values.first,
                      ),
                      const SizedBox(width: 10),
                      _SortMenu(
                        sort: filter.sort,
                        onChanged: (sort) => setState(
                          () => _filter = filter.copyWith(sort: sort),
                        ),
                      ),
                    ],
                    if (!wide) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Filtros',
                        icon: Badge(
                          isLabelVisible: filter.isNarrowed,
                          child: const Icon(
                            Icons.filter_alt_outlined,
                            size: 20,
                          ),
                        ),
                        onPressed: () => _showFilters(
                          context,
                          facets,
                          filter,
                          withLanguageAndSort: compact,
                          languages: session.catalogue.languages,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  if (wide) ...[
                    SizedBox(
                      width: 236,
                      child: _FilterPanel(
                        facets: facets,
                        filter: filter,
                        onChanged: (next) => setState(() => _filter = next),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: _UnitList(units: units, filter: filter),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showFilters(
    BuildContext context,
    LibraryFacets facets,
    LibraryFilter filter, {
    bool withLanguageAndSort = false,
    List<String> languages = const <String>[],
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _FilterPanel(
          facets: facets,
          filter: filter,
          // The two controls the header dropped on a narrow screen have to
          // land somewhere, and this is the somewhere.
          withLanguageAndSort: withLanguageAndSort,
          languages: languages,
          onLanguage: (code) {
            sessionOf(context).language = code;
            Navigator.of(sheetContext).pop();
          },
          onChanged: (next) {
            setState(() => _filter = next);
            Navigator.of(sheetContext).pop();
          },
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onChanged});

  final LibrarySort sort;
  final ValueChanged<LibrarySort> onChanged;

  static const Map<LibrarySort, String> _names = {
    LibrarySort.path: 'ruta',
    LibrarySort.title: 'título',
    LibrarySort.usage: 'más usadas',
    LibrarySort.needsWork: 'por traducir',
  };

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<LibrarySort>(
      value: sort,
      isDense: true,
      borderRadius: BorderRadius.circular(4),
      items: [
        for (final entry in _names.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(
              'orden: ${entry.value}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
      ],
      onChanged: (value) => value == null ? null : onChanged(value),
    ),
  );
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.facets,
    required this.filter,
    required this.onChanged,
    this.withLanguageAndSort = false,
    this.languages = const <String>[],
    this.onLanguage,
  });

  final LibraryFacets facets;
  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onChanged;

  /// Set when the header had no room for these two, which is the phone.
  final bool withLanguageAndSort;
  final List<String> languages;
  final ValueChanged<String>? onLanguage;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: didactaPanel,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          if (filter.isNarrowed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                label: const Text('Quitar filtros'),
                onPressed: () => onChanged(
                  LibraryFilter(language: filter.language, sort: filter.sort),
                ),
              ),
            ),
          if (withLanguageAndSort) ...[
            const SectionLabel('Idioma'),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final code in languages)
                    ChoiceChip(
                      label: Text(code),
                      selected: code == filter.language,
                      onSelected: (_) => onLanguage?.call(code),
                    ),
                ],
              ),
            ),
            const SectionLabel('Orden'),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _SortMenu(
                sort: filter.sort,
                onChanged: (sort) => onChanged(filter.copyWith(sort: sort)),
              ),
            ),
          ],
          const SectionLabel('Árbol'),
          for (final area in const ['content', 'problems'])
            _Facet(
              label: area == 'content' ? 'teoría y apuntes' : 'problemas',
              count: facets.byArea[area] ?? 0,
              selected: filter.area == area,
              onTap: () => onChanged(
                filter.area == area
                    ? filter.copyWith(clearArea: true)
                    : filter.copyWith(area: area),
              ),
            ),

          SectionLabel('Traducción · ${filter.language}'),
          for (final (status, label) in const [
            (StatusFilter.present, 'existe'),
            (StatusFilter.missing, 'falta'),
            (StatusFilter.needsWork, 'por revisar'),
          ])
            _Facet(
              label: label,
              count: _statusCount(status),
              selected: filter.status == status,
              onTap: () => onChanged(
                filter.copyWith(
                  status: filter.status == status ? StatusFilter.any : status,
                ),
              ),
            ),
          _Facet(
            label: 'sin usar en ninguna asignatura',
            count: null,
            selected: filter.unusedOnly,
            onTap: () =>
                onChanged(filter.copyWith(unusedOnly: !filter.unusedOnly)),
          ),

          const SectionLabel('Tipo'),
          for (final kind in facets.byKind.keys.toList()..sort())
            _Facet(
              label: kindName(kind),
              count: facets.byKind[kind],
              colour: kindColour(kind),
              selected: filter.kind == kind,
              onTap: () => onChanged(
                filter.kind == kind
                    ? filter.copyWith(clearKind: true)
                    : filter.copyWith(kind: kind),
              ),
            ),

          const SectionLabel('Categoría'),
          for (final category in facets.categoriesByCount)
            _Facet(
              label: category,
              count: facets.byCategory[category],
              selected: filter.category == category,
              onTap: () => onChanged(
                filter.category == category
                    ? filter.copyWith(clearCategory: true)
                    : filter.copyWith(category: category),
              ),
            ),
        ],
      ),
    );
  }

  int _statusCount(StatusFilter which) {
    var total = 0;
    facets.byStatus.forEach((status, count) {
      switch (which) {
        case StatusFilter.present:
          if (status.exists) total += count;
        case StatusFilter.missing:
          if (!status.exists) total += count;
        case StatusFilter.needsWork:
          if (status.needsWork) total += count;
        case StatusFilter.any:
          total += count;
      }
    });
    return total;
  }
}

class _Facet extends StatelessWidget {
  const _Facet({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.colour,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    // Disabled rather than hidden when it would show nothing: a sidebar whose
    // entries appear and vanish as you filter is impossible to aim at.
    final empty = count == 0;
    return InkWell(
      onTap: empty && !selected ? null : onTap,
      child: Container(
        color: selected ? didactaAccent.withValues(alpha: 0.14) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            if (colour != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: empty && !selected ? didactaMuted : null,
                ),
              ),
            ),
            if (count != null)
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: didactaMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnitList extends StatelessWidget {
  const _UnitList({required this.units, required this.filter});

  final List<Unit> units;
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 30, color: didactaMuted),
              const SizedBox(height: 12),
              // Names the filters responsible, so "nothing here" is
              // actionable rather than a dead end.
              Text(
                filter.isNarrowed
                    ? 'Nada con ${filter.describe()}'
                    : 'La biblioteca está vacía',
                textAlign: TextAlign.center,
                style: const TextStyle(color: didactaMuted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: units.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _UnitRow(unit: units[index], language: filter.language),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit, required this.language});

  final Unit unit;
  final String language;

  @override
  Widget build(BuildContext context) {
    final fallback = unit.titleIsFallback(language);

    return InkWell(
      onTap: () => context.go(Routes.unit(unit.path)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                color: kindColour(unit.kind),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          unit.title(language),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            // Marked when the title is not in the language
                            // asked for, so a Castilian title in a Valencian
                            // listing does not read as translated.
                            fontStyle: fallback
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: fallback ? didactaMuted : null,
                          ),
                        ),
                      ),
                      if (unit.warnings.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: unit.warnings.join('\n'),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: didactaEx,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    unit.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: didactaMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // How many documents use it: the answer to "is this safe to
            // change", which is why the index computes it.
            if (unit.usedBy.isNotEmpty)
              Tooltip(
                message: unit.usedBy.map((use) => use.toString()).join('\n'),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 12, color: didactaMuted),
                      const SizedBox(width: 2),
                      Text(
                        '${unit.usedBy.length}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: didactaMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final code in unit.statuses.keys)
              StatusBadge(language: code, status: unit.statusIn(code)),
          ],
        ),
      ),
    );
  }
}
