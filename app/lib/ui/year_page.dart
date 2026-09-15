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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/content_gateway.dart';
import '../model/catalogue.dart';
import '../model/composition_file.dart';
import '../model/line_diff.dart';
import '../router.dart';
import '../state/session.dart';
import 'commit_dialog.dart';
import 'course_admin_ui.dart';
import 'new_document.dart';
import 'shell.dart';
import 'sync_bar.dart';
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
        hint:
            'No está en el catálogo. Puede que el año no exista todavía, o '
            'que el catálogo esté desactualizado (`didacta index`).',
      );
    }

    final references = entry.documents.fold<int>(
      0,
      (sum, document) => sum + document.unitRefs.length,
    );
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
          breadcrumbs: [('Asignaturas', Routes.courses())],
          actions: [
            if (session.admin() != null)
              IconButton(
                key: const Key('remove-year'),
                tooltip: 'Quitar este curso académico',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _removeYear(context, session, course),
              ),
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
          child: _Documents(
            // Con clave: cambiar de año tiene que recargar el fichero, y sin
            // esto el estado del anterior se quedaría pegado.
            key: ValueKey('${course.id}/$year'),
            course: course,
            year: year,
            entry: entry,
            session: session,
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

  /// Quita este curso académico, y vuelve a la asignatura.
  ///
  /// Vuelve porque la pantalla en la que estás deja de existir: quedarse
  /// enseñando un curso borrado es peor que navegar.
  Future<void> _removeYear(
    BuildContext context,
    Session session,
    Course course,
  ) async {
    final admin = session.admin();
    if (admin == null) return;

    final onlyOne = course.years.length == 1;
    final confirmed = await confirmRemoval(
      context,
      title: '¿Quitar el curso $year de «${course.title()}»?',
      preview: () => admin.previewRemoveYear(course.id, year),
      warning: onlyOne
          ? 'Es el único curso de la asignatura, así que se queda sin '
                'ninguno. Las unidades no se tocan: lo que se pierde es la '
                'selección y el orden de este curso.'
          : 'Las unidades no se tocan, y los demás cursos de la asignatura '
                'tampoco. Lo que se pierde es la selección y el orden de '
                'este.',
    );
    if (!confirmed || !context.mounted) return;

    final done = await runAdmin(
      context,
      session,
      (admin) => admin.removeYear(course.id, year),
      done: 'Curso $year quitado como un commit.',
    );
    if (!done || !context.mounted) return;
    await session.reloadCatalogue();
    if (context.mounted) context.go(Routes.courses());
  }
}

/// Los grupos de contenido de un año: su orden, y los que hay.
///
/// La misma idea que el editor de composición pero un nivel más arriba. Un
/// año es una lista de documentos --temas, hojas de problemas, seminarios--
/// y reordenarlos es una edición tan normal como reordenar las unidades de
/// dentro: el tema 3 pasa a darse antes que el 2, y el fichero tiene que
/// decirlo.
///
/// Mueve **bloques enteros de `year.yaml`**, comentarios incluidos, y guarda
/// como un commit con su diff delante, igual que todo lo demás.
class _Documents extends StatefulWidget {
  const _Documents({
    super.key,
    required this.course,
    required this.year,
    required this.entry,
    required this.session,
  });

  final Course course;
  final String year;
  final CourseYear entry;
  final Session session;

  /// El repositorio cuyo `year.yaml` se edita.
  ///
  /// Con varios abiertos, un año puede tener temas de más de uno: cada uno
  /// tiene su `year.yaml` y el orden vive dentro de cada fichero, así que
  /// reordenar cruzando repositorios no es una operación que exista. Se edita
  /// el del primero que aporte algo, y los demás se ven con su color.
  String get repo => entry.documents.isEmpty ? '' : entry.documents.first.repo;

  String get path => 'courses/${course.id}/$year/year.yaml';

  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  /// Qué `year.yaml` se está editando.
  ///
  /// Un año puede tener temas de varios repositorios, y cada uno tiene el
  /// suyo: el orden vive dentro de cada fichero, así que reordenar cruzando
  /// repositorios no es una operación que exista. Se edita uno, y se dice
  /// cuál.
  late String _repo = widget.repo;

  ContentFile? _file;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  String _text = '';
  String _loaded = '';

  /// El orden en pantalla. Sale del fichero y no del catálogo: el catálogo se
  /// genera aparte y puede ir por detrás de lo que se acaba de guardar.
  List<String> _order = const [];

  bool get _dirty => _text != _loaded;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await widget.session.gatewayFor(_repo).read(widget.path);
      if (!mounted) return;
      setState(() {
        _file = file;
        _text = file.text;
        _loaded = file.text;
        _order = CompositionFile(file.text).documentIds();
        _loading = false;
      });
    } catch (thrown) {
      if (!mounted) return;
      setState(() {
        _error = thrown;
        _loading = false;
      });
    }
  }

  /// Aplica un cambio al fichero, o dice por qué no lo ha tocado.
  void _edit(void Function(CompositionFile file) change, {String? failure}) {
    final composition = CompositionFile(_text);
    try {
      change(composition);
    } on CompositionException catch (thrown) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${failure ?? 'No se ha tocado el fichero'}: ${thrown.message}',
          ),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 7),
        ),
      );
      return;
    }
    setState(() {
      _text = composition.text;
      _order = CompositionFile(composition.text).documentIds();
    });
  }

  void _reorder(int from, int to) {
    final next = [..._order];
    final moved = next.removeAt(from);
    next.insert(to, moved);
    _edit((file) => file.setDocumentOrder(next));
  }

  /// Cambia de repositorio: se edita el `year.yaml` del elegido.
  Future<void> _switchRepo(String repo) async {
    if (repo == _repo) return;
    setState(() => _repo = repo);
    await _load();
  }

  Future<void> _add() async {
    final draft = await showDialog<NewDocument>(
      context: context,
      builder: (context) => NewDocumentDialog(
        taken: _order,
        language: widget.session.language,
        languages: widget.session.catalogue.languages,
      ),
    );
    if (draft == null || !mounted) return;
    _edit(
      (file) =>
          file.addDocument(id: draft.id, kind: draft.kind, title: draft.title),
    );
  }

  Future<void> _remove(String id, String title) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Quitar «$title»?'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Se va el grupo y su composición: qué unidades llevaba y en qué '
            'orden. Las unidades no se tocan, siguen en la biblioteca y en '
            'los demás grupos que las usen.\n\n'
            'Queda como un commit, así que se puede revertir.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-remove-document'),
            style: FilledButton.styleFrom(backgroundColor: didactaTeacher),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    _edit((file) => file.removeDocument(id));
  }

  Future<void> _save() async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) =>
          CommitDialog(before: _loaded, after: _text, suggested: _suggested()),
    );
    if (message == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final sha = await widget.session
          .gatewayFor(_repo)
          .commit(
            path: widget.path,
            text: _text,
            sha: _file?.sha ?? '',
            message: message,
          );
      if (!mounted) return;
      setState(() {
        _loaded = _text;
        _file = ContentFile(path: widget.path, text: _text, sha: sha);
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('year.yaml guardado como un commit.')),
      );
      await widget.session.reloadCatalogue();
    } on ContentException catch (thrown) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(thrown.message),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Qué ha cambiado, en palabras.
  String _suggested() {
    final before = CompositionFile(_loaded).documentIds();
    final now = _order;
    final added = now.where((id) => !before.contains(id)).toList();
    final gone = before.where((id) => !now.contains(id)).toList();
    final where = '${widget.course.id} ${widget.year}';

    if (added.length == 1 && gone.isEmpty) {
      return 'Añadir el grupo ${added.first} a $where';
    }
    if (gone.length == 1 && added.isEmpty) {
      return 'Quitar el grupo ${gone.first} de $where';
    }
    if (added.isEmpty && gone.isEmpty) {
      return 'Cambiar el orden de los grupos de $where';
    }
    return 'Cambiar los grupos de $where';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _LoadFailed(error: _error!, path: widget.path, onRetry: _load);
    }

    final session = widget.session;
    final canWrite = session.canWriteIn(_repo);
    final size = diffSize(_loaded, _text);
    final byId = {
      for (final document in widget.entry.documents) document.id: document,
    };

    return Column(
      children: [
        // Qué composición se está editando, cuando el año se arma con varios
        // repositorios. Los temas de los demás se siguen viendo en la lista,
        // con su color; lo que cambia es dónde se escribe.
        if (widget.entry.repos.length > 1)
          Container(
            width: double.infinity,
            color: didactaPanel,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Editando la composición de',
                  style: TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
                for (final repo in widget.entry.repos)
                  InkWell(
                    key: Key('year-repo-$repo'),
                    onTap: () => _switchRepo(repo),
                    child: Opacity(
                      opacity: repo == _repo ? 1 : 0.45,
                      child: RepoChip(
                        colour: session.colourOf(repo) ?? 0xFF62697A,
                        label: session.workspace.byId(repo)?.label ?? repo,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (_dirty || _saving)
          _SaveBar(
            added: size.added,
            removed: size.removed,
            saving: _saving,
            onDiscard: _saving
                ? null
                : () => setState(() {
                    _text = _loaded;
                    _order = CompositionFile(_loaded).documentIds();
                  }),
            onSave: canWrite && !_saving ? _save : null,
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 72),
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            onReorderItem: canWrite ? _reorder : (_, _) {},
            itemBuilder: (context, index) {
              final id = _order[index];
              final document = byId[id];
              return _DocumentTile(
                key: ValueKey('document-$id'),
                index: index,
                course: widget.course,
                year: widget.year,
                id: id,
                document: document,
                session: session,
                canWrite: canWrite,
                onRemove: () =>
                    _remove(id, document?.title(session.language) ?? id),
              );
            },
          ),
        ),
        if (canWrite)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: didactaPanel,
              border: Border(top: BorderSide(color: didactaRule)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('add-document'),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nuevo grupo'),
                onPressed: _add,
              ),
            ),
          ),
      ],
    );
  }
}

/// La barra de guardar, que solo aparece cuando hay algo que guardar.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.added,
    required this.removed,
    required this.saving,
    required this.onDiscard,
    required this.onSave,
  });

  final int added;
  final int removed;
  final bool saving;
  final VoidCallback? onDiscard;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFFF3F7F1),
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
    child: Row(
      children: [
        const Icon(Icons.edit_outlined, size: 15, color: didactaAccentDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Sin guardar · +$added −$removed en year.yaml',
            style: const TextStyle(fontSize: 12.5, color: didactaMuted),
          ),
        ),
        if (onDiscard != null)
          TextButton(onPressed: onDiscard, child: const Text('Descartar')),
        const SizedBox(width: 4),
        FilledButton.icon(
          key: const Key('documents-save'),
          icon: saving
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(saving ? 'Guardando…' : 'Guardar'),
          onPressed: onSave,
        ),
      ],
    ),
  );
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({
    required this.error,
    required this.path,
    required this.onRetry,
  });

  final Object error;
  final String path;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se pudo leer la composición',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            SelectableText(
              path,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: didactaMuted,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText('$error', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    super.key,
    required this.index,
    required this.course,
    required this.year,
    required this.id,
    required this.document,
    required this.session,
    required this.canWrite,
    required this.onRemove,
  });

  final int index;
  final Course course;
  final String year;
  final String id;

  /// Null para un grupo que está en el fichero y todavía no en el catálogo:
  /// el índice se genera aparte, así que el recién creado se ve aquí antes
  /// de que `didacta index` lo recoja. Enseñarlo a medias es mejor que
  /// hacerlo desaparecer hasta el siguiente índice.
  final Document? document;
  final Session session;
  final bool canWrite;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final document = this.document;
    if (document == null) return _pending(context);

    final resolved = [
      for (final reference in document.unitRefs)
        (reference, session.catalogue.unitByReference(reference)),
    ];
    final broken = resolved.where((pair) => pair.$2 == null).length;

    return Hoverable(
      onTap: () => context.go(Routes.document(course.id, year, document.id)),
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: hovering ? didactaHover : Colors.transparent,
          border: const Border(bottom: BorderSide(color: didactaRule)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (canWrite)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 17,
                    color: didactaMuted,
                  ),
                ),
              )
            else
              const SizedBox(width: 10),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          document.title(session.language),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // De qué repositorio es este tema. Solo con varios
                      // abiertos: con uno, marcar no dice nada.
                      if (session.colourOf(document.repo) != null) ...[
                        const SizedBox(width: 8),
                        RepoChip(
                          colour: session.colourOf(document.repo)!,
                          label:
                              session.workspace.byId(document.repo)?.label ??
                              document.repo,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // A Wrap, not a Row: four pieces of metadata after a
                  // document id do not fit on a phone, and a second line is
                  // better than a hidden one.
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        document.id,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: didactaMuted,
                        ),
                      ),
                      Text(
                        kindName(document.kind),
                        style: TextStyle(
                          fontSize: 11,
                          color: kindColour(document.kind),
                        ),
                      ),
                      Text(
                        '${document.unitRefs.length} unidades',
                        style: const TextStyle(
                          fontSize: 11,
                          color: didactaMuted,
                        ),
                      ),
                      if (broken > 0)
                        Row(
                          children: [
                            const Icon(
                              Icons.link_off,
                              size: 12,
                              color: didactaTeacher,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$broken',
                              style: const TextStyle(
                                fontSize: 11,
                                color: didactaTeacher,
                              ),
                            ),
                          ],
                        ),
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
              units: [
                for (final pair in resolved)
                  if (pair.$2 != null) pair.$2!,
              ],
              languages: session.catalogue.languages,
            ),
            if (canWrite)
              IconButton(
                key: Key('remove-document-$id'),
                tooltip: 'Quitar este grupo',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 15),
                onPressed: onRemove,
              ),
            const Icon(Icons.chevron_right, size: 18, color: didactaMuted),
          ],
        ),
      ),
    );
  }

  /// Un grupo recién creado, todavía no indexado.
  Widget _pending(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
    child: Row(
      children: [
        if (canWrite)
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.drag_indicator, size: 17, color: didactaMuted),
            ),
          )
        else
          const SizedBox(width: 10),
        Expanded(
          child: Text(
            id,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: didactaMuted,
            ),
          ),
        ),
        const Text(
          'sin indexar todavía',
          style: TextStyle(fontSize: 11, color: didactaEx),
        ),
        if (canWrite)
          IconButton(
            key: Key('remove-document-$id'),
            tooltip: 'Quitar este grupo',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 15),
            onPressed: onRemove,
          ),
      ],
    ),
  );
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
              final present = units
                  .where((unit) => unit.statusIn(code).exists)
                  .length;
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: present == 0 ? null : colour.withValues(alpha: 0.10),
                    border: Border.all(
                      color: present == 0 ? didactaRule : colour,
                    ),
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
                    SelectableText(
                      what,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                      ),
                    ),
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
