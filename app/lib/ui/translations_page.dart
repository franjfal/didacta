/// What needs translating, in the order worth doing it.
///
/// Ordered by how many documents use each unit, which is the whole point of
/// the screen. A library of 2147 units has more gaps than anyone will ever
/// close, so a flat alphabetical list of what is missing is not a work queue
/// — it is a reproach. Sorted by reuse it becomes one: translating a unit six
/// courses depend on buys six documents.
///
/// `outdated` is listed alongside `missing`, and that matters: a translation
/// whose original has moved on is *wrong*, not merely absent, and it will
/// compile happily while saying something out of date.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../router.dart';
import 'shell.dart';
import 'theme.dart';

class TranslationsPage extends StatelessWidget {
  const TranslationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final catalogue = session.catalogue;
    final language = session.language;
    final pending = session.needingTranslation(language);

    final missing = pending
        .where((unit) => unit.statusIn(language) == TranslationStatus.missing)
        .length;
    final outdated = pending
        .where((unit) => unit.statusIn(language) == TranslationStatus.outdated)
        .length;
    final drafts = pending
        .where((unit) => unit.statusIn(language) == TranslationStatus.draft)
        .length;

    return Column(
      children: [
        PageHeader(
          title: 'Traducción',
          subtitle: '${pending.length} de ${catalogue.units.length} unidades '
              'necesitan trabajo en $language',
          bottom: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Text('Idioma:',
                    style: TextStyle(fontSize: 12, color: didactaMuted)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    for (final code in catalogue.languages)
                      ButtonSegment(value: code, label: Text(code)),
                  ],
                  selected: {language},
                  onSelectionChanged: (values) =>
                      sessionOf(context).language = values.first,
                ),
                const SizedBox(width: 16),
                if (outdated > 0) _Count(outdated, 'desactualizadas',
                    statusColour(TranslationStatus.outdated)),
                if (missing > 0)
                  _Count(missing, 'sin traducir',
                      statusColour(TranslationStatus.missing)),
                if (drafts > 0)
                  _Count(drafts, 'en borrador',
                      statusColour(TranslationStatus.draft)),
              ],
            ),
          ),
        ),
        if (outdated > 0)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Note(
              'Las $outdated desactualizadas van primero por un motivo: su '
              'original ha cambiado desde que se tradujeron, así que dicen '
              'algo que ya no es cierto — y compilan sin queja.',
              tone: statusColour(TranslationStatus.outdated),
            ),
          ),
        Expanded(
          child: pending.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 32, color: statusColour(
                                TranslationStatus.reviewed)),
                        const SizedBox(height: 12),
                        Text(
                          'Nada pendiente en $language.',
                          style: const TextStyle(color: didactaMuted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _PendingRow(
                    unit: pending[index],
                    language: language,
                    // The rank is worth showing: it makes the ordering
                    // legible instead of looking arbitrary.
                    showDivider: index == 0 ||
                        pending[index].usedBy.length !=
                            pending[index - 1].usedBy.length,
                  ),
                ),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label, this.colour);

  final int value;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              '$value $label',
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
          ],
        ),
      );
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.unit,
    required this.language,
    required this.showDivider,
  });

  final Unit unit;
  final String language;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final status = unit.statusIn(language);
    final uses = unit.usedBy.length;

    return InkWell(
      onTap: () => context.go(Routes.unit(unit.path)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            // How many documents this unblocks. The reason for the ordering,
            // so it is the first thing in the row.
            SizedBox(
              width: 40,
              child: uses == 0
                  ? const Text('—',
                      style: TextStyle(fontSize: 12, color: didactaMuted))
                  : Row(
                      children: [
                        const Icon(Icons.link, size: 12, color: didactaMuted),
                        const SizedBox(width: 3),
                        Text(
                          '$uses',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
            ),
            Container(
              width: 3,
              height: 26,
              margin: const EdgeInsets.only(right: 9),
              decoration: BoxDecoration(
                color: kindColour(unit.kind),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit.title(unit.reference),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    unit.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: didactaMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusName(status),
              style: TextStyle(fontSize: 11, color: statusColour(status)),
            ),
            const SizedBox(width: 8),
            StatusBadge(
              language: unit.reference,
              status: unit.statusIn(unit.reference),
            ),
            const Icon(Icons.chevron_right, size: 18, color: didactaMuted),
          ],
        ),
      ),
    );
  }
}
