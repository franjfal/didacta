/// Un examen o una hoja de problemas, a partir de los problemas, de una vez.
///
/// Antes eran más de quince pasos y dos commits: crear el documento vacío,
/// guardar, entrar en él, abrir «Editar la composición», añadir los problemas
/// uno a uno buscándolos entre dos mil unidades, y guardar otra vez. Y sin
/// saber cuáles habían salido ya en un examen, que es la primera pregunta de
/// quien prepara uno.
///
/// Aquí es un diálogo: el tipo, el título, los problemas --filtrados por
/// carpeta y, si se quiere, sin los que ya salieron en un examen de esta
/// asignatura-- y un solo guardado. El repositorio no se pregunta: lo dicen
/// los problemas elegidos, porque **un documento y lo que llama viven en el
/// mismo repositorio**, así que al elegir el primero los de otros quedan
/// fuera.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/library_filter.dart';
import '../model/library_tree.dart' show humaniseSlug;
import '../model/slug.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que el diálogo devuelve.
class ProblemSetDraft {
  const ProblemSetDraft({
    required this.kind,
    required this.id,
    required this.title,
    required this.pending,
    required this.repo,
    required this.problems,
    this.theme,
  });

  /// `exam` o `problems`.
  final String kind;
  final String id;

  /// El título, en el idioma que se está mirando.
  final Map<String, String> title;

  /// Los idiomas a los que le falta el título, como en un documento nuevo.
  final List<String> pending;

  /// Dónde se escribe: el de los problemas elegidos.
  final String repo;

  /// En el orden en que se eligieron.
  final List<Unit> problems;

  /// El tema del curso al que va, o null para dejarlo suelto.
  final String? theme;
}

/// Si una unidad es un problema: del bloque de problemas o de tipo problema.
bool isProblemUnit(Unit unit) => unit.isProblem || unit.kind == 'problem';

/// Los exámenes de [course] en los que salió [unit], como «2024-2025 · Enero».
///
/// Sale de dónde se usa cada unidad hoy, así que cuenta los cursos que siguen
/// en el repositorio. Uno que se quitó no está: para ese queda su versión
/// congelada.
List<String> examsWith(Unit unit, Course course, String language) {
  final found = <String>[];
  for (final usage in unit.usedBy) {
    if (usage.course != course.id) continue;
    final year = course.years[usage.year];
    if (year == null) continue;
    for (final document in year.documents) {
      if (document.id != usage.document || document.kind != 'exam') continue;
      final label = '${usage.year} · ${document.title(language)}';
      if (!found.contains(label)) found.add(label);
    }
  }
  found.sort((a, b) => b.compareTo(a));
  return found;
}

class ProblemSetDialog extends StatefulWidget {
  const ProblemSetDialog({
    super.key,
    required this.session,
    required this.course,
    required this.year,
    required this.taken,
    required this.repos,
    this.themes = const [],
    this.theme,
  });

  final Session session;
  final Course course;
  final String year;

  /// Los ids que ya están en este año.
  final List<String> taken;

  /// Los repositorios en los que se puede escribir este curso. Solo se
  /// ofrecen problemas de ellos.
  final List<String> repos;

  /// Los temas del curso, para elegir dónde va.
  final List<CourseTheme> themes;

  /// El tema de partida, cuando se abre desde uno.
  final String? theme;

  @override
  State<ProblemSetDialog> createState() => _ProblemSetDialogState();
}

class _ProblemSetDialogState extends State<ProblemSetDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _query = TextEditingController();
  String _kind = 'exam';
  bool _idTyped = false;
  late String? _theme = widget.theme;

  /// La carpeta a la que se restringe, o vacío para todas.
  String _folder = '';

  /// Sin los que ya salieron en un examen de esta asignatura.
  bool _unseen = false;

  final List<Unit> _chosen = [];

  String get _language => widget.session.language;

  late final List<Unit> _problems = [
    for (final unit in widget.session.catalogue.units)
      if (isProblemUnit(unit) && widget.repos.contains(unit.repo)) unit,
  ]..sort((a, b) => compareTitles(a.title(_language), b.title(_language)));

  late final Map<Unit, List<String>> _exams = {
    for (final unit in _problems)
      unit: examsWith(unit, widget.course, _language),
  };

  static String _folderOf(Unit unit) {
    final reference = unit.reference_;
    final cut = reference.lastIndexOf('/');
    return cut < 0 ? '' : reference.substring(0, cut);
  }

  late final List<String> _folders = {
    for (final unit in _problems) _folderOf(unit),
  }.where((folder) => folder.isNotEmpty).toList()..sort();

  static String _folderLabel(String folder) =>
      folder.split('/').map(humaniseSlug).join(' › ');

  /// De qué repositorio es lo elegido: el primero manda.
  String? get _repo => _chosen.isEmpty ? null : _chosen.first.repo;

  @override
  void dispose() {
    _title.dispose();
    _id.dispose();
    _query.dispose();
    super.dispose();
  }

  bool get _valid {
    final id = _id.text.trim();
    return RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id) &&
        !widget.taken.contains(id) &&
        _title.text.trim().isNotEmpty &&
        _chosen.isNotEmpty;
  }

  void _toggle(Unit unit) => setState(() {
    if (!_chosen.remove(unit)) _chosen.add(unit);
  });

  void _create() {
    final languages = widget.session.languagesIn(widget.course.id);
    Navigator.of(context).pop(
      ProblemSetDraft(
        kind: _kind,
        id: _id.text.trim(),
        title: {_language: _title.text.trim()},
        pending: [
          for (final code in languages)
            if (code != _language) code,
        ],
        repo: _repo!,
        problems: [..._chosen],
        theme: _theme,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = LibraryFilter(
      query: _query.text.trim(),
      language: _language,
    );
    // Lo que casa con una errata, detrás de lo que casa tal cual.
    final shown = search.exactFirst([
      for (final unit in _problems)
        if ((_folder.isEmpty || _folderOf(unit) == _folder) &&
            (!_unseen || _exams[unit]!.isEmpty || _chosen.contains(unit)))
          unit,
    ]);
    final id = _id.text.trim();
    final taken = widget.taken.contains(id);
    final repo = _repo;
    final several = widget.repos.length > 1;

    return AlertDialog(
      title: Text(tr('Examen u hoja de problemas')),
      content: SizedBox(
        width: 720,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final (kind, label) in [
                  ('exam', tr('Examen')),
                  ('problems', tr('Hoja de problemas')),
                ])
                  ChoiceChip(
                    key: Key('problem-set-kind-$kind'),
                    label: Text(label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('problem-set-title'),
                    controller: _title,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: tr('Título en {0}', [_language]),
                      hintText: _kind == 'exam'
                          ? tr('Examen de enero')
                          : tr('Hoja 3. Series de funciones'),
                    ),
                    onChanged: (value) => setState(() {
                      if (!_idTyped) _id.text = slugify(value);
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('problem-set-id'),
                    controller: _id,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: tr('Identificador'),
                      errorText: taken
                          ? tr('Ya hay uno así en este curso')
                          : null,
                    ),
                    onChanged: (_) => setState(() => _idTyped = true),
                  ),
                ),
                if (widget.themes.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('problem-set-theme'),
                      initialValue: _theme,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: tr('En el tema'),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(tr('Ninguno, suelto')),
                        ),
                        for (final theme in widget.themes)
                          DropdownMenuItem<String?>(
                            value: theme.id,
                            child: Text(
                              theme.title(_language),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _theme = value),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              tr('Los problemas'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.palette.muted,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('problem-set-search'),
                    controller: _query,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: tr('Buscar por título, ruta o etiqueta…'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    key: const Key('problem-set-folder'),
                    initialValue: _folder,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: tr('De la carpeta'),
                    ),
                    items: [
                      DropdownMenuItem(value: '', child: Text(tr('Todas'))),
                      for (final folder in _folders)
                        DropdownMenuItem(
                          value: folder,
                          child: Text(
                            _folderLabel(folder),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _folder = value ?? ''),
                  ),
                ),
              ],
            ),
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: const Key('problem-set-unseen'),
                value: _unseen,
                onChanged: (value) => setState(() => _unseen = value ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  tr(
                    'Sin los que ya salieron en un examen de '
                    '{0}',
                    [widget.course.title(_language)],
                  ),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.card,
                  border: Border.all(color: context.palette.rule),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.control),
                  child: shown.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _problems.isEmpty
                                  ? tr(
                                      'No hay problemas en '
                                      '{0}.',
                                      [
                                        several
                                            ? tr('estos repositorios')
                                            : tr('este repositorio'),
                                      ],
                                    )
                                  : tr('Ningún problema con estos filtros.'),
                              style: TextStyle(color: context.palette.muted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (context, index) =>
                              _row(shown[index], repo),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _chosen.isEmpty
                  ? tr(
                      'Elige uno o más. Van en el orden en que los elijas, y se '
                      'reordenan después en la composición.',
                    )
                  : '${_chosen.length == 1 ? tr('1 elegido') : tr('{0} elegidos, en este orden', [_chosen.length])}'
                        '${several ? tr(' · se escribe en {0}', [widget.session.workspace.byId(repo!)?.label ?? repo]) : ''}.',
              key: const Key('problem-set-summary'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: _chosen.isEmpty ? null : FontWeight.w600,
                color: _chosen.isEmpty
                    ? context.palette.muted
                    : context.palette.accentDark,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('problem-set-create'),
          onPressed: _valid ? _create : null,
          child: Text(
            _kind == 'exam' ? tr('Crear el examen') : tr('Crear la hoja'),
          ),
        ),
      ],
    );
  }

  Widget _row(Unit unit, String? repo) {
    final chosen = _chosen.contains(unit);
    final elsewhere = repo != null && unit.repo != repo;
    final exams = _exams[unit]!;
    final position = _chosen.indexOf(unit);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: Key('problem-set-unit-${unit.path}'),
        dense: true,
        enabled: !elsewhere,
        onTap: elsewhere ? null : () => _toggle(unit),
        leading: Checkbox(
          value: chosen,
          onChanged: elsewhere ? null : (_) => _toggle(unit),
        ),
        title: Text(
          unit.title(_language),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          elsewhere
              ? tr(
                  'De otro repositorio: un documento y sus problemas viven en '
                  'el mismo.',
                )
              : unit.reference_,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: context.palette.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (exams.isNotEmpty)
              Tooltip(
                message: tr('Salió en: {0}', [exams.join('; ')]),
                child: Container(
                  key: Key('problem-set-seen-${unit.path}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.palette.teacher.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Radii.chip),
                  ),
                  child: Text(
                    tr(
                      'examen {0}'
                      '{1}',
                      [
                        exams.first.split(' · ').first,
                        exams.length > 1 ? ' +${exams.length - 1}' : '',
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.palette.teacher,
                    ),
                  ),
                ),
              ),
            if (position >= 0) ...[
              const SizedBox(width: 8),
              Text(
                '${position + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.palette.accentDark,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
