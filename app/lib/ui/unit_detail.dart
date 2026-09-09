/// One unit, in full.
///
/// The panel exists to answer the two questions a listing cannot: what is this
/// unit, and what happens if I change it. The second is why `usedBy` is
/// computed in the index -- without it, deciding whether a unit is safe to
/// edit means reading every composition in the repository.
///
/// It does not edit anything yet. The editor is a later phase, and a panel
/// that looks editable but is not would be worse than one that plainly reads.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/library_filter.dart';
import 'theme.dart';

class UnitDetail extends StatelessWidget {
  const UnitDetail({
    super.key,
    required this.unit,
    required this.catalogue,
    required this.language,
    this.onClose,
    this.onFilter,
  });

  final Unit unit;
  final Catalogue catalogue;
  final String language;
  final VoidCallback? onClose;

  /// Clicking a tag or a category filters the library by it, which is what
  /// makes the panel a way to navigate rather than a dead end.
  final ValueChanged<LibraryFilter>? onFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.title(language),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unit.path,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: didactaMuted),
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Row(label: 'tipo', child: _Chips(
                labels: [unit.kind],
                colour: kindColour(unit.kind),
                onTap: (value) => onFilter?.call(
                    LibraryFilter(language: language, kind: value)),
              )),
              _Row(label: 'categoría', child: _Chips(
                labels: [unit.category, unit.topic],
                onTap: (value) => onFilter?.call(value == unit.category
                    ? LibraryFilter(language: language, category: value)
                    : LibraryFilter(language: language, query: value)),
              )),
              if (unit.tags.isNotEmpty)
                _Row(label: 'etiquetas', child: _Chips(
                  labels: unit.tags,
                  onTap: (value) => onFilter?.call(
                      LibraryFilter(language: language, tag: value)),
                )),

              const SizedBox(height: 8),
              _SectionTitle('Idiomas'),
              // Every declared language, including the ones that do not
              // exist: a gap is information, and hiding it makes the unit look
              // complete.
              for (final code in catalogue.languages)
                _LanguageRow(
                  code: code,
                  status: unit.statusIn(code),
                  isReference: code == unit.reference,
                  title: unit.titles[code],
                ),

              if (unit.titles.isEmpty) ...[
                const SizedBox(height: 6),
                const _Note(
                  'Sin título en ningún idioma. En el material migrado esto '
                  'significa que el fichero no lo declaraba y la migración no '
                  'lo ha inventado.',
                ),
              ],

              const SizedBox(height: 12),
              _SectionTitle('Se usa en ${unit.usedBy.length} documento(s)'),
              if (unit.usedBy.isEmpty)
                const _Note(
                  'Ninguna composición la referencia. Después de una migración '
                  'esto es material que llegó y no se está usando: o falta '
                  'ponerlo en una asignatura, o se puede quitar.',
                )
              else
                for (final use in unit.usedBy)
                  _UsageRow(usage: use, catalogue: catalogue),

              if (unit.prerequisites.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionTitle('Prerrequisitos'),
                for (final reference in unit.prerequisites)
                  _PrerequisiteRow(
                    reference: reference,
                    catalogue: catalogue,
                    language: language,
                    onOpen: onFilter == null
                        ? null
                        : (path) => onFilter!(
                            LibraryFilter(language: language, query: path)),
                  ),
              ],

              if (unit.objectives.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionTitle('Objetivos'),
                for (final objective in unit.objectives)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('· '),
                        Expanded(
                            child: Text(objective,
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
              ],

              if (unit.durationMinutes != null || unit.difficulty != null) ...[
                const SizedBox(height: 12),
                _SectionTitle('Otros'),
                if (unit.durationMinutes != null)
                  _Row(
                      label: 'duración',
                      child: Text('${unit.durationMinutes} min',
                          style: const TextStyle(fontSize: 13))),
                if (unit.difficulty != null)
                  _Row(
                      label: 'dificultad',
                      child: Text(unit.difficulty!,
                          style: const TextStyle(fontSize: 13))),
              ],

              if (unit.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionTitle('Avisos'),
                for (final warning in unit.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 15, color: didactaEx),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(warning,
                                style: const TextStyle(fontSize: 12.5))),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: didactaMuted,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: didactaMuted)),
            ),
            Expanded(child: child),
          ],
        ),
      );
}

class _Chips extends StatelessWidget {
  const _Chips({required this.labels, required this.onTap, this.colour});

  final List<String> labels;
  final ValueChanged<String> onTap;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final label in labels.where((value) => value.isNotEmpty))
            ActionChip(
              label: Text(label),
              side: colour == null ? null : BorderSide(color: colour!),
              onPressed: () => onTap(label),
            ),
        ],
      );
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.code,
    required this.status,
    required this.isReference,
    this.title,
  });

  final String code;
  final TranslationStatus status;
  final bool isReference;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(language: code, status: status),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title?.isNotEmpty == true ? title! : statusName(status),
                  style: TextStyle(
                    fontSize: 13,
                    color: title?.isNotEmpty == true ? null : didactaMuted,
                    fontStyle: title?.isNotEmpty == true
                        ? FontStyle.normal
                        : FontStyle.italic,
                  ),
                ),
                if (isReference)
                  const Text('idioma de referencia',
                      style: TextStyle(fontSize: 11, color: didactaMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.usage, required this.catalogue});

  final UnitUsage usage;
  final Catalogue catalogue;

  @override
  Widget build(BuildContext context) {
    // The course's real title rather than its id, when the catalogue has it.
    String courseName = usage.course;
    for (final course in catalogue.courses) {
      if (course.id == usage.course) {
        courseName = course.title();
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 14, color: didactaMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$courseName · ${usage.year} · ${usage.document}',
              style: const TextStyle(fontSize: 12.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrerequisiteRow extends StatelessWidget {
  const _PrerequisiteRow({
    required this.reference,
    required this.catalogue,
    required this.language,
    this.onOpen,
  });

  final String reference;
  final Catalogue catalogue;
  final String language;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    // A prerequisite may name a unit id or a path; either resolves, and one
    // that resolves to nothing is shown as broken rather than as a link.
    final unit = catalogue.unitByReference(reference) ??
        catalogue.units.where((item) => item.id == reference).firstOrNull;
    final missing = unit == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: missing || onOpen == null ? null : () => onOpen!(unit.path),
        child: Row(
          children: [
            Icon(missing ? Icons.link_off : Icons.arrow_right,
                size: 15, color: missing ? didactaTeacher : didactaMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                missing ? '$reference (no existe)' : unit.title(language),
                style: TextStyle(
                  fontSize: 12.5,
                  color: missing ? didactaTeacher : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: didactaMuted.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12.5, color: didactaInk)),
      );
}
