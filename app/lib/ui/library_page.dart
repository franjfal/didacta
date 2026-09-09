/// The library: every unit, filtered.
///
/// The view the whole platform is judged on first, because it is the one that
/// has to make 2147 units navigable. Three things drive its design:
///
/// **The list is virtualised.** A `ListView.builder` over the filtered result,
/// so scrolling 2147 rows costs the same as scrolling 20. Building them all up
/// front is the obvious way to make this view unusable.
///
/// **Filtering happens on a value, not on scattered state.** One
/// [LibraryFilter] held here, replaced wholesale; every control writes a new
/// one. There is no way to end up with the sidebar showing one thing and the
/// list another.
///
/// **The counts say where the material is.** A sidebar of 51 categories in
/// alphabetical order buries the ones being taught, so they are ordered by how
/// much is in them and each shows what clicking it would give.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/library_filter.dart';
import 'theme.dart';
import 'unit_detail.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.catalogue});

  final Catalogue catalogue;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late LibraryFilter _filter;
  final TextEditingController _search = TextEditingController();
  Unit? _selected;

  @override
  void initState() {
    super.initState();
    _filter = LibraryFilter(language: widget.catalogue.defaultLanguage);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(LibraryFilter next) => setState(() => _filter = next);

  @override
  Widget build(BuildContext context) {
    final units = _filter.apply(widget.catalogue.units);
    final facets = LibraryFacets.of(widget.catalogue.units, _filter);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the three panes do not fit, so the detail becomes a
        // sheet and the filters a drawer. Same widgets either way -- the
        // point of keeping the logic out of them.
        final wide = constraints.maxWidth >= 1100;
        final medium = constraints.maxWidth >= 760;

        final list = _UnitList(
          units: units,
          filter: _filter,
          selected: _selected,
          onSelect: (unit) {
            if (wide) {
              setState(() => _selected = unit);
            } else {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => FractionallySizedBox(
                  heightFactor: 0.85,
                  child: UnitDetail(
                    unit: unit,
                    catalogue: widget.catalogue,
                    language: _filter.language,
                    onFilter: (next) {
                      Navigator.of(context).pop();
                      _update(next);
                    },
                  ),
                ),
              );
            }
          },
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.catalogue.name),
            titleSpacing: 16,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: _SearchBar(
                controller: _search,
                filter: _filter,
                languages: widget.catalogue.languages,
                shown: facets.shown,
                total: facets.total,
                onChanged: _update,
              ),
            ),
          ),
          drawer: medium
              ? null
              : Drawer(
                  child: SafeArea(
                    child: _FilterPanel(
                      facets: facets,
                      filter: _filter,
                      onChanged: _update,
                    ),
                  ),
                ),
          body: Row(
            children: [
              if (medium)
                SizedBox(
                  width: 250,
                  child: _FilterPanel(
                    facets: facets,
                    filter: _filter,
                    onChanged: _update,
                  ),
                ),
              if (medium) const VerticalDivider(width: 1),
              Expanded(child: list),
              if (wide && _selected != null) const VerticalDivider(width: 1),
              if (wide && _selected != null)
                SizedBox(
                  width: 380,
                  child: UnitDetail(
                    unit: _selected!,
                    catalogue: widget.catalogue,
                    language: _filter.language,
                    onClose: () => setState(() => _selected = null),
                    onFilter: _update,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.filter,
    required this.languages,
    required this.shown,
    required this.total,
    required this.onChanged,
  });

  final TextEditingController controller;
  final LibraryFilter filter;
  final List<String> languages;
  final int shown;
  final int total;
  final ValueChanged<LibraryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Buscar por título, ruta, etiqueta…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Limpiar',
                        onPressed: () {
                          controller.clear();
                          onChanged(filter.copyWith(query: ''));
                        },
                      ),
              ),
              onChanged: (value) => onChanged(filter.copyWith(query: value)),
            ),
          ),
          const SizedBox(width: 12),
          // The language the listing is about: it picks the title shown and
          // what the status filter applies to, so it belongs next to the
          // search rather than buried in the sidebar.
          _LanguagePicker(
            languages: languages,
            selected: filter.language,
            onChanged: (code) => onChanged(filter.copyWith(language: code)),
          ),
          const SizedBox(width: 12),
          _SortPicker(
            sort: filter.sort,
            onChanged: (sort) => onChanged(filter.copyWith(sort: sort)),
          ),
          const SizedBox(width: 12),
          Text(
            shown == total ? '$total' : '$shown / $total',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.languages,
    required this.selected,
    required this.onChanged,
  });

  final List<String> languages;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final code in languages)
          ButtonSegment(value: code, label: Text(code)),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

class _SortPicker extends StatelessWidget {
  const _SortPicker({required this.sort, required this.onChanged});

  final LibrarySort sort;
  final ValueChanged<LibrarySort> onChanged;

  static const Map<LibrarySort, String> _names = {
    LibrarySort.path: 'ruta',
    LibrarySort.title: 'título',
    LibrarySort.usage: 'más usadas',
    LibrarySort.needsWork: 'por traducir',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<LibrarySort>(
        value: sort,
        isDense: true,
        borderRadius: BorderRadius.circular(6),
        items: [
          for (final entry in _names.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text('orden: ${entry.value}',
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
        onChanged: (value) => value == null ? null : onChanged(value),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.facets,
    required this.filter,
    required this.onChanged,
  });

  final LibraryFacets facets;
  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (filter.isNarrowed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Quitar filtros'),
              onPressed: () => onChanged(
                  LibraryFilter(language: filter.language, sort: filter.sort)),
            ),
          ),
        _Section(
          title: 'Tipo de árbol',
          children: [
            for (final area in const ['content', 'problems'])
              _FacetTile(
                label: area == 'content' ? 'teoría y apuntes' : 'problemas',
                count: facets.byArea[area] ?? 0,
                selected: filter.area == area,
                onTap: () => onChanged(filter.area == area
                    ? filter.copyWith(clearArea: true)
                    : filter.copyWith(area: area)),
              ),
          ],
        ),
        _Section(
          title: 'Traducción (${filter.language})',
          children: [
            for (final entry in const [
              (StatusFilter.present, 'existe'),
              (StatusFilter.missing, 'falta'),
              (StatusFilter.needsWork, 'por revisar'),
            ])
              _FacetTile(
                label: entry.$2,
                count: _statusCount(entry.$1),
                selected: filter.status == entry.$1,
                onTap: () => onChanged(filter.copyWith(
                    status: filter.status == entry.$1
                        ? StatusFilter.any
                        : entry.$1)),
              ),
            _FacetTile(
              label: 'sin usar en ninguna asignatura',
              count: null,
              selected: filter.unusedOnly,
              onTap: () =>
                  onChanged(filter.copyWith(unusedOnly: !filter.unusedOnly)),
            ),
          ],
        ),
        _Section(
          title: 'Tipo',
          children: [
            for (final kind in facets.byKind.keys.toList()..sort())
              _FacetTile(
                label: kind,
                count: facets.byKind[kind],
                colour: kindColour(kind),
                selected: filter.kind == kind,
                onTap: () => onChanged(filter.kind == kind
                    ? filter.copyWith(clearKind: true)
                    : filter.copyWith(kind: kind)),
              ),
          ],
        ),
        _Section(
          title: 'Categoría',
          children: [
            // Ordered by size: with 51 categories, alphabetical buries the
            // ones actually being taught.
            for (final category in facets.categoriesByCount)
              _FacetTile(
                label: category,
                count: facets.byCategory[category],
                selected: filter.category == category,
                onTap: () => onChanged(filter.category == category
                    ? filter.copyWith(clearCategory: true)
                    : filter.copyWith(category: category)),
              ),
          ],
        ),
      ],
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: didactaMuted,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _FacetTile extends StatelessWidget {
  const _FacetTile({
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
    // A facet that would show nothing is disabled rather than hidden: a
    // sidebar whose entries appear and vanish as you filter is impossible to
    // aim at.
    final empty = count == 0;
    return InkWell(
      onTap: empty && !selected ? null : onTap,
      child: Container(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            if (colour != null) ...[
              Container(width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: colour, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: empty && !selected ? didactaMuted : null,
                ),
              ),
            ),
            if (count != null)
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: empty ? didactaMuted : didactaMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnitList extends StatelessWidget {
  const _UnitList({
    required this.units,
    required this.filter,
    required this.selected,
    required this.onSelect,
  });

  final List<Unit> units;
  final LibraryFilter filter;
  final Unit? selected;
  final ValueChanged<Unit> onSelect;

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 32, color: didactaMuted),
              const SizedBox(height: 12),
              // Says which filter is responsible, so "nothing here" is
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

    // Virtualised: 2147 rows cost the same as 20.
    return ListView.separated(
      itemCount: units.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final unit = units[index];
        return _UnitRow(
          unit: unit,
          language: filter.language,
          selected: unit.path == selected?.path,
          onTap: () => onSelect(unit),
        );
      },
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final Unit unit;
  final String language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = unit.titleIsFallback(language);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            // Marked when the title shown is not in the
                            // language asked for, so a Castilian title in a
                            // Valencian listing does not read as translated.
                            fontStyle:
                                fallback ? FontStyle.italic : FontStyle.normal,
                            color: fallback ? didactaMuted : null,
                          ),
                        ),
                      ),
                      if (unit.warnings.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: unit.warnings.join('\n'),
                          child: const Icon(Icons.warning_amber_rounded,
                              size: 14, color: didactaEx),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unit.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: didactaMuted,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // How many documents use it: the answer to "is this safe to
            // change", which is the reason the index computes it.
            if (unit.usedBy.isNotEmpty)
              Tooltip(
                message: unit.usedBy.map((use) => use.toString()).join('\n'),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 13, color: didactaMuted),
                    const SizedBox(width: 2),
                    Text('${unit.usedBy.length}',
                        style: const TextStyle(
                            fontSize: 12, color: didactaMuted)),
                    const SizedBox(width: 10),
                  ],
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
