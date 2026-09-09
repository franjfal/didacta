/// One academic year: the documents it is made of.
///
/// This is the composition view. What matters here is that a year holds no
/// content -- every line is a reference into `content/` or `problems/` -- so
/// the screen's job is to make the *selection and order* legible, and to say
/// when a reference points at nothing.
///
/// A broken reference is shown in place rather than skipped. A composition
/// that silently omits a missing unit looks complete and compiles short, which
/// is the failure that is hardest to notice.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'shell.dart';
import 'theme.dart';

class YearPage extends StatelessWidget {
  const YearPage({super.key, required this.courseId, required this.year});

  final String courseId;
  final String year;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final course = session.courseById(courseId);
    final entry = course?.years[year];

    if (course == null || entry == null) {
      return _NotHere(
        what: '$courseId · $year',
        hint: 'No está en el catálogo. Puede que el año no exista todavía, o '
            'que el catálogo esté desactualizado (`didacta index`).',
      );
    }

    final references = entry.documents
        .fold<int>(0, (sum, document) => sum + document.unitRefs.length);
    final broken = _brokenCount(entry, session);

    return Column(
      children: [
        PageHeader(
          title: '${course.title()} · $year',
          subtitle: [
            '${entry.documents.length} documentos',
            '$references referencias',
            if (entry.group != null) entry.group!,
            'idioma ${entry.language}',
          ].join(' · '),
          breadcrumbs: [
            ('Asignaturas', Routes.courses()),
          ],
        ),
        if (broken > 0)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Note(
              '$broken referencia(s) de esta composición no apuntan a ninguna '
              'unidad del catálogo. Se muestran en su sitio, no se omiten: una '
              'composición que se salta lo que falta parece completa y compila '
              'corta.',
              tone: didactaTeacher,
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: entry.documents.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _DocumentTile(
              course: course,
              year: year,
              document: entry.documents[index],
              session: session,
            ),
          ),
        ),
      ],
    );
  }

  int _brokenCount(CourseYear entry, Session session) {
    var broken = 0;
    for (final document in entry.documents) {
      for (final reference in document.unitRefs) {
        if (session.catalogue.unitByReference(reference) == null) broken += 1;
      }
    }
    return broken;
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.course,
    required this.year,
    required this.document,
    required this.session,
  });

  final Course course;
  final String year;
  final Document document;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final resolved = [
      for (final reference in document.unitRefs)
        (reference, session.catalogue.unitByReference(reference)),
    ];
    final broken = resolved.where((pair) => pair.$2 == null).length;

    return InkWell(
      onTap: () =>
          context.go(Routes.document(course.id, year, document.id)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 34,
              margin: const EdgeInsets.only(top: 2, right: 10),
              decoration: BoxDecoration(
                color: kindColour(document.kind),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title(session.language),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        document.id,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: didactaMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        kindName(document.kind),
                        style: TextStyle(
                            fontSize: 11, color: kindColour(document.kind)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${document.unitRefs.length} unidades',
                        style: const TextStyle(
                            fontSize: 11, color: didactaMuted),
                      ),
                      if (broken > 0) ...[
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            const Icon(Icons.link_off,
                                size: 12, color: didactaTeacher),
                            const SizedBox(width: 2),
                            Text(
                              '$broken',
                              style: const TextStyle(
                                  fontSize: 11, color: didactaTeacher),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Which languages this document's content is available in, taken
            // from the units it uses -- so a document can be seen to be
            // buildable in Valencian before opening it.
            _LanguageSummary(
              units: [for (final pair in resolved) if (pair.$2 != null) pair.$2!],
              languages: session.catalogue.languages,
            ),
            const Icon(Icons.chevron_right, size: 18, color: didactaMuted),
          ],
        ),
      ),
    );
  }
}

/// How complete each language is across a document's units.
///
/// A ratio rather than a badge: "9/11 in va" says whether a Valencian build
/// would fall back to Castilian in two places, which a single colour cannot.
class _LanguageSummary extends StatelessWidget {
  const _LanguageSummary({required this.units, required this.languages});

  final List<Unit> units;
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final code in languages)
          Builder(
            builder: (context) {
              final present =
                  units.where((unit) => unit.statusIn(code).exists).length;
              final complete = present == units.length;
              final colour = present == 0
                  ? didactaMuted
                  : complete
                      ? didactaAccentDark
                      : didactaEx;
              return Tooltip(
                message: '$code: $present de ${units.length} unidades',
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: present == 0 ? null : colour.withValues(alpha: 0.10),
                    border: Border.all(
                        color: present == 0 ? didactaRule : colour),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    complete ? code : '$code $present/${units.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: present == 0 ? didactaMuted : colour,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _NotHere extends StatelessWidget {
  const _NotHere({required this.what, required this.hint});

  final String what;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'No encontrado',
          breadcrumbs: [('Asignaturas', Routes.courses())],
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(what,
                        style: const TextStyle(
                            fontSize: 12.5, fontFamily: 'monospace')),
                    const SizedBox(height: 12),
                    Text(hint, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => context.go(Routes.courses()),
                      child: const Text('Ver las asignaturas'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
