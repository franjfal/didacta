/// The composition builder: a document's units, in the order they are taught.
///
/// Drag to reorder, switch an entry off without losing it, add a unit from
/// the library, insert a heading. Every change is a commit to `year.yaml`,
/// and the dialog shows the diff first.
///
/// The switch is the part worth explaining. Nine hundred entries in the
/// repository are commented out -- material that exists and is deliberately
/// not being taught this year -- and after a migration, turning some of them
/// back on is the most common edit there is. So "off" is a state an entry can
/// be in, shown greyed and struck through in its place in the order, rather
/// than a deletion. Deleting is also available, and says what it means.
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
import 'theme.dart';

class CompositionEditor extends StatefulWidget {
  const CompositionEditor({
    super.key,
    required this.courseId,
    required this.year,
    required this.documentId,
    required this.session,
  });

  final String courseId;
  final String year;
  final String documentId;
  final Session session;

  /// Where the composition of a year lives.
  String get path => 'courses/$courseId/$year/year.yaml';

  @override
  State<CompositionEditor> createState() => _CompositionEditorState();
}

class _CompositionEditorState extends State<CompositionEditor> {
  ContentFile? _file;
  bool _loading = true;
  Object? _error;
  bool _saving = false;
  bool _conflicted = false;

  String _text = '';
  String _loaded = '';
  List<StructureEntry> _entries = const [];

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
      _conflicted = false;
    });
    try {
      final file = await widget.session.gateway.read(widget.path);
      final composition = CompositionFile(file.text);
      final block = composition.blockFor(widget.documentId);
      if (block == null) {
        throw CompositionException(
          'el documento `${widget.documentId}` no está en '
          '${widget.path}. Puede que el catálogo esté desactualizado: se '
          'regenera con `didacta index`.',
        );
      }
      if (!mounted) return;
      setState(() {
        _file = file;
        _text = file.text;
        _loaded = file.text;
        _entries = block.entries;
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

  /// Applies a new order to the file, reporting a refusal rather than a guess.
  void _apply(List<StructureEntry> entries) {
    final composition = CompositionFile(_text);
    try {
      composition.setStructure(widget.documentId, entries);
    } on CompositionException catch (thrown) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se ha tocado el fichero: ${thrown.message}'),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 7),
        ),
      );
      return;
    }
    setState(() {
      _entries = entries;
      _text = composition.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _CompositionFailure(
        error: _error!,
        path: widget.path,
        onRetry: _load,
      );
    }

    final session = widget.session;
    final canWrite = session.gateway.canWrite;
    final size = diffSize(_loaded, _text);
    final active = _entries.where((e) => e.enabled).length;

    return Column(
      children: [
        _Bar(
          path: widget.path,
          active: active,
          total: _entries.length,
          added: size.added,
          removed: size.removed,
          saving: _saving,
          canSave: canWrite && _dirty && !_saving,
          onDiscard: _dirty ? () => _apply(_reload()) : null,
          onSave: _save,
        ),
        if (_conflicted)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Note(
              'year.yaml ha cambiado en el repositorio desde que lo abriste. '
              'Vuelve a cargarlo antes de guardar; tu orden sigue aquí '
              'mientras decides.',
              tone: didactaTeacher,
            ),
          ),
        Expanded(
          child: _entries.isEmpty
              ? _Empty(enabled: canWrite, onAdd: () => _addUnit(context))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  buildDefaultDragHandles: false,
                  itemCount: _entries.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) => _EntryRow(
                    key: ValueKey('entry-$index-${_entries[index]}'),
                    index: index,
                    entry: _entries[index],
                    session: session,
                    enabled: canWrite,
                    position: _positionOf(index),
                    onToggle: () => _apply([
                      for (var i = 0; i < _entries.length; i += 1)
                        i == index
                            ? _entries[i].copyWith(
                                enabled: !_entries[i].enabled,
                              )
                            : _entries[i],
                    ]),
                    onRemove: () => _remove(index),
                    onInsertHeading: (kind) =>
                        _insertAt(index, _newHeading(kind)),
                    onInsertUnit: () => _insertUnit(context, index),
                    onRename: (text) => _apply([
                      for (var i = 0; i < _entries.length; i += 1)
                        i == index
                            ? _entries[i].withTitle(session.language, text)
                            : _entries[i],
                    ]),
                  ),
                ),
        ),
        if (canWrite)
          _AddBar(
            onUnit: () => _addUnit(context),
            onHeading: (kind) => _addHeading(kind),
          ),
      ],
    );
  }

  /// The number shown against an entry: its place among the active ones, so
  /// switching one off renumbers what follows rather than leaving a gap.
  int? _positionOf(int index) {
    if (!_entries[index].enabled) return null;
    var position = 0;
    for (var i = 0; i <= index; i += 1) {
      if (_entries[i].enabled) position += 1;
    }
    return position;
  }

  List<StructureEntry> _reload() =>
      CompositionFile(_loaded).blockFor(widget.documentId)?.entries ?? const [];

  /// `onReorderItem` hands back an index already adjusted for the removal,
  /// which is the whole reason it replaced `onReorder`.
  ///
  /// The read-only check is here rather than on the callback because the list
  /// requires exactly one reorder callback and refuses a null one. The drag
  /// handles are already absent without write access; this is the belt to
  /// that braces.
  void _reorder(int from, int to) {
    if (!widget.session.gateway.canWrite) return;
    final next = [..._entries];
    next.insert(to, next.removeAt(from));
    _apply(next);
  }

  Future<void> _remove(int index) async {
    final entry = _entries[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar de la composición?'),
        content: Text(
          'Se quita «${entry.label(widget.session.language)}» de este '
          'documento. La unidad no se borra: sigue en la biblioteca y en los '
          'demás documentos que la usen.\n\n'
          'Si es que este año no se da, desactívala en lugar de quitarla: '
          'queda en su sitio, comentada, y se vuelve a activar en un toque.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _apply([..._entries]..removeAt(index));
  }

  /// Inserta una entrada en una posición.
  ///
  /// Hace falta porque «añadir un apartado» casi nunca significa «al final»:
  /// se reestructura un tema partiéndolo, y el apartado va justo delante de
  /// la unidad por la que empieza la parte nueva.
  void _insertAt(int index, StructureEntry entry) {
    final next = [..._entries];
    next.insert(index.clamp(0, next.length), entry);
    _apply(next);
  }

  StructureEntry _newHeading(EntryKind kind) => StructureEntry(
    kind: kind,
    value: '',
    // Con título por idiomas desde el principio, que es la forma que usa el
    // repositorio y lo que permite rellenar los demás después.
    titleLines: [
      '${widget.session.language}: Título nuevo',
      for (final code in widget.session.catalogue.languages)
        if (code != widget.session.language) '# TODO: $code',
    ],
  );

  Future<void> _insertUnit(BuildContext context, int index) async {
    final chosen = await _pickUnit(context);
    if (chosen == null) return;
    _insertAt(
      index,
      StructureEntry(
        kind: chosen.isProblem ? EntryKind.problem : EntryKind.unit,
        value: chosen.reference_,
      ),
    );
  }

  Future<Unit?> _pickUnit(BuildContext context) {
    final already = {
      for (final entry in _entries)
        if (entry.isReference) entry.value,
    };
    return showDialog<Unit>(
      context: context,
      builder: (context) =>
          _UnitPicker(session: widget.session, already: already),
    );
  }

  Future<void> _addUnit(BuildContext context) async {
    final already = {
      for (final entry in _entries)
        if (entry.isReference) entry.value,
    };
    final chosen = await showDialog<Unit>(
      context: context,
      builder: (context) =>
          _UnitPicker(session: widget.session, already: already),
    );
    if (chosen == null) return;
    _apply([
      ..._entries,
      StructureEntry(
        kind: chosen.isProblem ? EntryKind.problem : EntryKind.unit,
        value: chosen.reference_,
      ),
    ]);
  }

  void _addHeading(EntryKind kind) => _apply([..._entries, _newHeading(kind)]);

  Future<void> _save() async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _CompositionCommitDialog(
        before: _loaded,
        after: _text,
        suggested: _suggestedMessage(),
      ),
    );
    if (message == null || !mounted) return;

    setState(() {
      _saving = true;
      _conflicted = false;
    });
    try {
      final sha = await widget.session.gateway.commit(
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
      setState(() {
        _saving = false;
        _conflicted = thrown.kind == ContentFailure.conflict;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(thrown.message),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// What changed, in words. Reordering, switching on and adding are three
  /// different things and a log that calls them all "edit year.yaml" is a log
  /// nobody reads.
  String _suggestedMessage() {
    final before = _reload();
    final now = _entries;

    // Identity for the purpose of "did the order change": what an entry
    // refers to, *not* whether it is switched on. Including the enabled flag
    // made every toggle report itself as a reorder as well.
    List<String> keys(List<StructureEntry> entries) => [
      for (final entry in entries)
        '${entryKeyword(entry.kind)}:${entry.value}${entry.label('es')}',
    ];
    final wasValues = keys(before);
    final nowValues = keys(now);

    final added = now.length - before.length;
    final switchedOn =
        now.where((e) => e.enabled).length -
        before.where((e) => e.enabled).length;
    final reordered =
        wasValues.length == nowValues.length &&
        !_sameOrder(wasValues, nowValues);

    final parts = <String>[];
    if (added > 0) parts.add('añadir ${_entries_(added)}');
    if (added < 0) parts.add('quitar ${_entries_(-added)}');
    if (switchedOn > 0 && added <= 0) {
      parts.add('activar ${_entries_(switchedOn)}');
    }
    if (switchedOn < 0) parts.add('desactivar ${_entries_(-switchedOn)}');
    // "cambiar el orden" rather than "reordenar" so the sentence reads the
    // same whether it is the only change or one of several.
    if (reordered) parts.add('cambiar el orden');

    final what = parts.isEmpty ? 'editar' : parts.join(' y ');
    return '${_capitalise(what)} en la composición de ${widget.documentId} '
        '(${widget.courseId} ${widget.year})';
  }

  static String _entries_(int count) =>
      count == 1 ? 'una entrada' : '$count entradas';

  static bool _sameOrder(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _capitalise(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.path,
    required this.active,
    required this.total,
    required this.added,
    required this.removed,
    required this.saving,
    required this.canSave,
    required this.onDiscard,
    required this.onSave,
  });

  final String path;
  final int active;
  final int total;
  final int added;
  final int removed;
  final bool saving;
  final bool canSave;
  final VoidCallback? onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          return Row(
            children: [
              Expanded(
                child: Text(
                  narrow
                      ? '$active de $total'
                      : '$path · $active de $total activas',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: didactaMuted,
                  ),
                ),
              ),
              if (added + removed > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '+$added −$removed',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: didactaEx,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              if (!narrow && onDiscard != null)
                TextButton(
                  onPressed: saving ? null : onDiscard,
                  child: const Text('Descartar'),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                key: const Key('composition-save'),
                icon: saving
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 16),
                label: Text(saving ? 'Guardando…' : 'Guardar'),
                onPressed: canSave ? onSave : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.session,
    required this.enabled,
    required this.position,
    required this.onToggle,
    required this.onRemove,
    required this.onRename,
    required this.onInsertHeading,
    required this.onInsertUnit,
  });

  final int index;
  final StructureEntry entry;
  final Session session;
  final bool enabled;
  final int? position;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final ValueChanged<String> onRename;

  /// Insertar **encima de esta fila**. Es lo que convierte «añadir un
  /// apartado» en algo útil al reestructurar: el apartado va delante de la
  /// unidad por la que empieza la parte nueva, no al final del documento.
  final ValueChanged<EntryKind> onInsertHeading;
  final VoidCallback onInsertUnit;

  @override
  Widget build(BuildContext context) {
    final off = !entry.enabled;
    final unit = entry.isReference
        ? session.catalogue.unitByReference(entry.value)
        : null;
    final broken = entry.isReference && unit == null;

    return Container(
      decoration: BoxDecoration(
        color: off ? didactaPanel : Colors.white,
        border: const Border(bottom: BorderSide(color: didactaRule)),
      ),
      child: Opacity(
        opacity: off ? 0.55 : 1,
        child: Row(
          children: [
            if (enabled)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 17,
                    color: didactaMuted,
                  ),
                ),
              )
            else
              const SizedBox(width: 33),
            SizedBox(
              width: 30,
              child: Text(
                position == null ? '—' : '$position',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: didactaMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: entry.isReference
                  ? _Reference(
                      entry: entry,
                      unit: unit,
                      broken: broken,
                      off: off,
                      session: session,
                    )
                  : _Heading(
                      entry: entry,
                      language: session.language,
                      enabled: enabled,
                      onRename: onRename,
                    ),
            ),
            if (enabled)
              MenuAnchor(
                builder: (context, controller, child) => IconButton(
                  key: Key('insert-$index'),
                  tooltip: 'Insertar encima',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 16),
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
                menuChildren: [
                  MenuItemButton(
                    key: Key('insert-section-$index'),
                    leadingIcon: const Icon(Icons.title, size: 15),
                    onPressed: () => onInsertHeading(EntryKind.section),
                    child: const Text('Apartado, encima'),
                  ),
                  MenuItemButton(
                    key: Key('insert-subsection-$index'),
                    leadingIcon: const Icon(Icons.subtitles_outlined, size: 15),
                    onPressed: () => onInsertHeading(EntryKind.subsection),
                    child: const Text('Subapartado, encima'),
                  ),
                  const Divider(height: 1),
                  MenuItemButton(
                    key: Key('insert-unit-$index'),
                    leadingIcon: const Icon(Icons.add, size: 15),
                    onPressed: onInsertUnit,
                    child: const Text('Unidad, encima…'),
                  ),
                ],
              ),
            IconButton(
              // No se quita: se comenta. Que el texto lo diga es lo que
              // separa este botón del de al lado.
              tooltip: off ? 'Activar' : 'Desactivar, se queda comentada',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                off ? Icons.toggle_off_outlined : Icons.toggle_on,
                size: 21,
                color: off ? didactaMuted : didactaAccentDark,
              ),
              onPressed: enabled ? onToggle : null,
            ),
            IconButton(
              tooltip: 'Quitar',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 15),
              onPressed: enabled ? onRemove : null,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _Reference extends StatelessWidget {
  const _Reference({
    required this.entry,
    required this.unit,
    required this.broken,
    required this.off,
    required this.session,
  });

  final StructureEntry entry;
  final Unit? unit;
  final bool broken;
  final bool off;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final title = unit?.title(session.language) ?? entry.value;
    return InkWell(
      onTap: unit == null ? null : () => context.go(Routes.unit(unit!.path)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (unit != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: kindColour(unit!.kind),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.link_off,
                      size: 13,
                      color: didactaTeacher,
                    ),
                  ),
                Expanded(
                  child: Text(
                    broken ? '${entry.value} (no existe)' : title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: broken ? didactaTeacher : null,
                      decoration: off ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (unit != null)
                  StatusBadge(
                    language: session.language,
                    status: unit!.statusIn(session.language),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              entry.value,
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
    );
  }
}

/// A heading, editable in place.
class _Heading extends StatefulWidget {
  const _Heading({
    required this.entry,
    required this.language,
    required this.enabled,
    required this.onRename,
  });

  final StructureEntry entry;
  final String language;
  final bool enabled;
  final ValueChanged<String> onRename;

  @override
  State<_Heading> createState() => _HeadingState();
}

class _HeadingState extends State<_Heading> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.entry.label(widget.language),
  );

  @override
  void didUpdateWidget(_Heading old) {
    super.didUpdateWidget(old);
    final now = widget.entry.label(widget.language);
    if (now != _controller.text && now != old.entry.label(old.language)) {
      _controller.text = now;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSection = widget.entry.kind == EntryKind.section;
    final missing =
        widget.entry.isLocalised &&
        !widget.entry.titles.containsKey(widget.language);

    return Padding(
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6,
        // Indented so the shape of the document is visible at a glance.
        left: isSection ? 0 : 18,
      ),
      child: Row(
        children: [
          Text(
            isSection ? '§' : '§§',
            style: const TextStyle(
              fontSize: 12,
              color: didactaMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSection ? FontWeight.w700 : FontWeight.w600,
                // A heading shown in another language is marked, the way
                // titles are elsewhere: it is not translated, it is borrowed.
                fontStyle: missing ? FontStyle.italic : null,
                color: missing ? didactaMuted : null,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: missing
                    ? 'sin traducir a ${widget.language}'
                    : 'título del apartado',
              ),
              onChanged: widget.onRename,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({required this.onUnit, required this.onHeading});

  final VoidCallback onUnit;
  final ValueChanged<EntryKind> onHeading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(top: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          FilledButton.icon(
            key: const Key('add-unit'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Añadir unidad'),
            onPressed: onUnit,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.title, size: 15),
            label: const Text('Apartado'),
            onPressed: () => onHeading(EntryKind.section),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.subtitles_outlined, size: 15),
            label: const Text('Subapartado'),
            onPressed: () => onHeading(EntryKind.subsection),
          ),
        ],
      ),
    );
  }
}

/// Picking a unit to add: the library, filtered by typing.
class _UnitPicker extends StatefulWidget {
  const _UnitPicker({required this.session, required this.already});

  final Session session;
  final Set<String> already;

  @override
  State<_UnitPicker> createState() => _UnitPickerState();
}

class _UnitPickerState extends State<_UnitPicker> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final language = widget.session.language;
    final matches = [
      for (final unit in widget.session.catalogue.units)
        if (needle.isEmpty ||
            unit.path.toLowerCase().contains(needle) ||
            unit.title(language).toLowerCase().contains(needle) ||
            unit.tags.any((tag) => tag.toLowerCase().contains(needle)))
          unit,
    ];

    return AlertDialog(
      title: const Text('Añadir una unidad'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Buscar por título, ruta o etiqueta…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${matches.length} de ${widget.session.catalogue.units.length}',
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: matches.isEmpty
                  ? const Center(
                      child: Text(
                        'Nada coincide.',
                        style: TextStyle(fontSize: 13, color: didactaMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final unit = matches[index];
                        // Shown rather than hidden: knowing a unit is already
                        // in the document is the answer to "why can I not
                        // find it".
                        final present = widget.already.contains(
                          unit.reference_,
                        );
                        return ListTile(
                          dense: true,
                          enabled: !present,
                          leading: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: kindColour(unit.kind),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          title: Text(
                            unit.title(language),
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            present ? 'ya está en este documento' : unit.path,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: present ? null : 'monospace',
                              color: present ? didactaEx : didactaMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: StatusBadge(
                            language: language,
                            status: unit.statusIn(language),
                          ),
                          onTap: present
                              ? null
                              : () => Navigator.of(context).pop(unit),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.enabled, required this.onAdd});

  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Este documento no compone nada todavía.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Después de una migración esto suele significar que el '
              'documento original no importó ninguna unidad que se '
              'pudiera resolver.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (enabled)
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Añadir la primera unidad'),
                onPressed: onAdd,
              ),
          ],
        ),
      ),
    ),
  );
}

class _CompositionCommitDialog extends StatefulWidget {
  const _CompositionCommitDialog({
    required this.before,
    required this.after,
    required this.suggested,
  });

  final String before;
  final String after;
  final String suggested;

  @override
  State<_CompositionCommitDialog> createState() =>
      _CompositionCommitDialogState();
}

class _CompositionCommitDialogState extends State<_CompositionCommitDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.suggested,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hunks = diffHunks(widget.before, widget.after);
    return AlertDialog(
      title: const Text('Guardar la composición'),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esto es lo que va a cambiar en year.yaml. Los demás '
              'documentos del curso no se tocan.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: didactaPanel,
                  border: Border.all(color: didactaRule),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in hunks) _DiffRow(line: line),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Mensaje'),
              onSubmitted: (value) => Navigator.of(
                context,
              ).pop(value.trim().isEmpty ? widget.suggested : value.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('composition-commit'),
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? widget.suggested : text);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.line});

  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    final (marker, colour) = switch (line.kind) {
      ChangeKind.added => ('+', didactaAccentDark),
      ChangeKind.removed => ('−', didactaTeacher),
      ChangeKind.kept => (' ', didactaMuted),
    };
    return Text(
      '$marker ${line.text}',
      style: TextStyle(
        fontSize: 11.5,
        fontFamily: 'monospace',
        color: line.isChange ? colour : didactaMuted,
        fontWeight: line.isChange ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}

class _CompositionFailure extends StatelessWidget {
  const _CompositionFailure({
    required this.error,
    required this.path,
    required this.onRetry,
  });

  final Object error;
  final String path;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final content = error is ContentException
        ? error as ContentException
        : null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No se ha podido abrir la composición',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                path,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: didactaMuted,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                content?.message ?? error.toString(),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reintentar'),
                    onPressed: onRetry,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => context.go(Routes.settings()),
                    child: const Text('Ajustes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
