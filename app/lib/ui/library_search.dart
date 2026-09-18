/// Búsqueda: la biblioteca cuando la jerarquía no es lo que se quiere.
///
/// Una lista plana es la forma **correcta** para una búsqueda. Escribir
/// «hilbert» no es navegar un árbol: es preguntar por todo lo que coincide, y
/// lo que coincide no tiene por qué estar cerca en el árbol. Lo que estaba mal
/// era que la lista plana fuera *también* la vista por defecto, con 2147 filas
/// tiradas de golpe y la agrupación que el autor ya había hecho en la basura.
///
/// Así que esto es lo que aparece al escribir, y `library_page.dart` es lo que
/// aparece al entrar. Dos formas, dos preguntas distintas.
///
/// Tres cosas que esta vista mantiene:
///
/// **La lista está virtualizada.** Un builder sobre el resultado, así que
/// recorrer 2147 filas cuesta lo que recorrer 20.
///
/// **El filtro es un valor, reemplazado entero.** Cada control escribe un
/// [LibraryFilter] nuevo; nadie guarda un trozo. No hay forma de acabar con el
/// panel diciendo una cosa y la lista otra.
///
/// **Los recuentos dicen dónde está el material.** Cada faceta dice cuántas
/// unidades daría pulsarla, y en cero se apaga en lugar de mentir.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../model/library_filter.dart';
import '../router.dart';
import 'quick_look.dart';
import 'theme.dart';

class SortMenu extends StatelessWidget {
  const SortMenu({super.key, required this.sort, required this.onChanged});

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

class FilterPanel extends StatelessWidget {
  const FilterPanel({
    super.key,
    required this.facets,
    required this.filter,
    required this.onChanged,
    this.blocks = const <CourseBlock>[],
    this.withLanguageAndSort = false,
    this.languages = const <String>[],
    this.onLanguage,
  });

  final LibraryFacets facets;
  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onChanged;

  /// Los bloques que hay, declarados o nombrados. Ver
  /// [Catalogue.blocksInUse].
  final List<CourseBlock> blocks;

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
              child: SortMenu(
                sort: filter.sort,
                onChanged: (sort) => onChanged(filter.copyWith(sort: sort)),
              ),
            ),
          ],
          // Con uno solo no aparece: un filtro cuyo único valor es todo lo
          // que hay no contesta ninguna pregunta.
          if (blocks.length > 1) ...[
            const SectionLabel('Bloque'),
            for (final block in blocks)
              _Facet(
                label: block.title(filter.language),
                count: facets.byBlock[block.id] ?? 0,
                selected: filter.block == block.id,
                onTap: () => onChanged(
                  filter.block == block.id
                      ? filter.copyWith(clearBlock: true)
                      : filter.copyWith(block: block.id),
                ),
              ),
          ],

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

class UnitList extends StatelessWidget {
  const UnitList({super.key, required this.units, required this.filter});

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
          UnitRow(unit: units[index], language: filter.language),
    );
  }
}

class UnitRow extends StatelessWidget {
  const UnitRow({super.key, required this.unit, required this.language});

  final Unit unit;
  final String language;

  @override
  Widget build(BuildContext context) {
    final fallback = unit.titleIsFallback(language);

    return Hoverable(
      onTap: () => context.go(Routes.unit(unit.path)),
      builder: (context, hovering) => Container(
        color: hovering ? didactaHover : null,
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
            QuickLookButton(
              unit: unit,
              language: language,
              visible: hovering,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}
