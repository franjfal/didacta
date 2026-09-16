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
import '../model/path_tree.dart';
import '../model/line_diff.dart';
import '../router.dart';
import '../state/session.dart';
import 'commit_dialog.dart';
import 'heading_title.dart';
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

  /// El repositorio del documento: es su `year.yaml` el que se edita.
  String get repo => session.documentIn(courseId, year, documentId)?.repo ?? '';

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
      final file = await widget.session
          .gatewayFor(widget.repo)
          .read(widget.path);
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
    final canWrite = session.canWriteIn(widget.repo);
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
                    // Dónde está la fila dentro de su apartado, para que la
                    // lista se lea como tarjetas. La lista sigue siendo una
                    // sola, que es lo que permite arrastrar dentro de un
                    // apartado y de un apartado a otro sin nada especial:
                    // anidar listas para dibujar tarjetas habría comprado el
                    // aspecto al precio de la función.
                    place: _placeOf(index),
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
                    onTitles: (titles) => _apply([
                      for (var i = 0; i < _entries.length; i += 1)
                        i == index
                            ? _retitle(_entries[i], titles)
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

  /// Dónde cae una fila dentro de su apartado.
  _Place _placeOf(int index) {
    final entry = _entries[index];
    if (!entry.isReference) {
      return entry.kind == EntryKind.section ? _Place.section : _Place.inside;
    }
    // La última de su apartado es la que cierra la tarjeta: la que va justo
    // antes de otro apartado, o la última de todas.
    final next = index + 1 < _entries.length ? _entries[index + 1] : null;
    final closes = next == null || next.kind == EntryKind.section;
    return closes ? _Place.last : _Place.inside;
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
    if (!widget.session.canWriteIn(widget.repo)) return;
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
    final chosen = await _pickUnits(context);
    if (chosen.isEmpty) return;
    // En el orden en que se eligieron, y todas en el mismo sitio: elegir
    // cinco y que aparezcan del revés sería peor que elegirlas de una en una.
    _apply([
      ..._entries.take(index),
      for (final unit in chosen) _entryFor(unit),
      ..._entries.skip(index),
    ]);
  }

  static StructureEntry _entryFor(Unit unit) => StructureEntry(
    // Un solo árbol, así que una sola forma de citar. `problem:` sigue
    // leyéndose para las composiciones de antes, pero no se escribe.
    kind: EntryKind.unit,
    value: unit.reference_,
  );

  Future<List<Unit>> _pickUnits(BuildContext context) async {
    final already = {
      for (final entry in _entries)
        if (entry.isReference) entry.value,
    };
    final chosen = await showDialog<List<Unit>>(
      context: context,
      builder: (context) =>
          _UnitPicker(
            session: widget.session,
            already: already,
            repo: widget.repo,
          ),
    );
    return chosen ?? const [];
  }

  Future<void> _addUnit(BuildContext context) async {
    final chosen = await _pickUnits(context);
    if (chosen.isEmpty) return;
    _apply([..._entries, for (final unit in chosen) _entryFor(unit)]);
  }

  void _addHeading(EntryKind kind) => _apply([..._entries, _newHeading(kind)]);

  /// Aplica los títulos de todos los idiomas a la vez.
  ///
  /// Uno en blanco no borra el apartado: se queda como pendiente, que es lo
  /// que el fichero ya sabía decir con `# TODO: va` y lo que hace que la
  /// pantalla de traducción lo cuente.
  StructureEntry _retitle(StructureEntry entry, Map<String, String> titles) {
    var updated = entry;
    for (final language in widget.session.catalogue.languages) {
      final text = titles[language] ?? '';
      if (text.isEmpty) continue;
      updated = updated.withTitle(language, text);
    }
    return updated;
  }

  Future<void> _save() async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => CommitDialog(
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
      final sha = await widget.session
          .gatewayFor(widget.repo)
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

/// Dónde cae una fila dentro de la tarjeta de su apartado.
enum _Place {
  /// La cabecera: abre la tarjeta.
  section,

  /// Una fila más, entre la cabecera y el cierre.
  inside,

  /// La última del apartado: cierra la tarjeta.
  last,
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.session,
    required this.enabled,
    required this.position,
    required this.place,
    required this.onToggle,
    required this.onRemove,
    required this.onTitles,
    required this.onInsertHeading,
    required this.onInsertUnit,
  });

  final int index;
  final StructureEntry entry;
  final Session session;
  final bool enabled;
  final int? position;
  final _Place place;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  /// Los títulos del apartado, todos a la vez.
  final ValueChanged<Map<String, String>> onTitles;

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

    // La tarjeta del apartado, dibujada fila a fila: la cabecera pone el
    // borde de arriba y las esquinas, las de dentro solo los lados, y la
    // última cierra por abajo. Parece una tarjeta y sigue siendo una lista,
    // que es lo que deja arrastrar de un apartado a otro.
    final head = place == _Place.section;
    final closes = place == _Place.last;
    const radius = Radius.circular(Radii.card);

    return Container(
      margin: EdgeInsets.fromLTRB(8, head ? 10 : 0, 8, closes ? 4 : 0),
      decoration: BoxDecoration(
        color: off
            ? didactaPanel
            : (head ? const Color(0xFFF3F6F1) : didactaCard),
        // Borde igual por los cuatro lados: Flutter no admite un radio con
        // lados de colores distintos, y la alternativa --dibujar cada línea
        // a mano para que no se doblen entre filas-- es mucho enredo por un
        // pelo de un gris que casi no se ve.
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.only(
          topLeft: head ? radius : Radius.zero,
          topRight: head ? radius : Radius.zero,
          bottomLeft: closes ? radius : Radius.zero,
          bottomRight: closes ? radius : Radius.zero,
        ),
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
                      languages: session.catalogue.languages,
                      enabled: enabled,
                      onTitles: onTitles,
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
                  // El tipo con su nombre, no solo con un color. Una barra
                  // de color dice «estos dos son distintos»; no dice cuál es
                  // la explicación y cuál el ejercicio, que es la pregunta
                  // que se hace al mirar la composición de un tema.
                  KindChip(kind: unit!.kind),
                  const SizedBox(width: 8),
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

/// La cabecera de un apartado dentro de la composición.
///
/// El título ya no se edita en la fila. Editarlo ahí significaba editar
/// **solo el idioma que se está mirando**, y para poner el valenciano había
/// que cambiar de idioma toda la pantalla y volver: con los ficheros no pasa
/// --tienen una pestaña por idioma-- y con los apartados sí, que es donde más
/// fácil es dejarse uno. El lápiz abre los tres a la vez.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.entry,
    required this.language,
    required this.languages,
    required this.enabled,
    required this.onTitles,
  });

  final StructureEntry entry;
  final String language;
  final List<String> languages;
  final bool enabled;
  final ValueChanged<Map<String, String>> onTitles;

  @override
  Widget build(BuildContext context) {
    final isSection = entry.kind == EntryKind.section;
    final missing = entry.isLocalised && !entry.titles.containsKey(language);
    final label = entry.label(language);

    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: 2, left: isSection ? 0 : 18),
      child: Row(
        children: [
          Icon(
            isSection ? Icons.folder_outlined : Icons.segment,
            size: isSection ? 16 : 14,
            color: didactaAccentDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label.isEmpty ? 'Apartado sin título' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isSection ? 14 : 13,
                fontWeight: isSection ? FontWeight.w700 : FontWeight.w600,
                // Un título prestado de otro idioma se marca, como en el
                // resto de la aplicación: no está traducido, está prestado.
                fontStyle: missing ? FontStyle.italic : null,
                color: missing || label.isEmpty ? didactaMuted : null,
              ),
            ),
          ),
          // Cuántos idiomas tienen título, que es lo que dice si hay trabajo
          // pendiente sin abrir nada.
          if (entry.isLocalised)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '${entry.titles.length}/${languages.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: entry.titles.length == languages.length
                      ? didactaAccentDark
                      : didactaTeacher,
                ),
              ),
            ),
          if (enabled)
            IconButton(
              key: Key('edit-title-${entry.value}-$label'),
              tooltip: 'Editar el título en todos los idiomas',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 15),
              onPressed: () async {
                final titles = await editHeadingTitles(
                  context,
                  heading: isSection ? 'Apartado' : 'Subapartado',
                  languages: languages,
                  titles: entry.titles,
                  reference: language,
                );
                if (titles != null) onTitles(titles);
              },
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
/// Elegir unidades para un documento: por carpetas o buscando.
///
/// Dos formas porque son dos preguntas distintas. El buscador responde a «sé
/// cómo se llama»; el árbol, a «sé dónde la dejé», que es lo que pasa cuando
/// se prepara un tema y se quiere ver **qué hay** en una carpeta antes de
/// elegir. Sin árbol, la única manera de ver lo que tiene `analysis/normed`
/// era acertar con la palabra.
///
/// Empieza todo cerrado y con las áreas del disco arriba --`content/` y
/// `problems/`-- porque es la estructura que alguien tiene en la cabeza. En
/// cuanto se escribe algo, el árbol deja sitio a los resultados, y al borrar
/// vuelve; es lo mismo que hace la biblioteca, así que no hay un modo nuevo
/// que aprender.
///
/// Y se eligen **varias**: preparar un tema es añadir cinco lecciones
/// seguidas, y hacerlo de una en una son cinco veces abrir el diálogo,
/// buscar y confirmar. Lo elegido se acumula aunque se cambie de carpeta o
/// se busque otra cosa.
class _UnitPicker extends StatefulWidget {
  const _UnitPicker({
    required this.session,
    required this.already,
    required this.repo,
  });

  final Session session;
  final Set<String> already;

  /// El repositorio del documento que se está componiendo.
  ///
  /// Solo se ofrecen unidades suyas, y es una regla dura: **un documento y
  /// las unidades que llama viven en el mismo repositorio**. LaTeX las busca
  /// bajo la raíz del suyo, así que una lección de otro repositorio compila
  /// aquí --donde están los dos abiertos-- y no compila en la máquina de
  /// quien solo tenga uno. Lo que sí se comparte entre repositorios es la
  /// clasificación: las asignaturas, los cursos y los temas.
  final String repo;

  @override
  State<_UnitPicker> createState() => _UnitPickerState();
}

class _UnitPickerState extends State<_UnitPicker> {
  final TextEditingController _query = TextEditingController();

  /// Las carpetas abiertas. Vacío es todo cerrado, que es como empieza.
  final Set<String> _open = {};

  /// Lo elegido, por ruta y en el orden en que se fue eligiendo: es el orden
  /// en que se van a añadir, y alfabetizarlo por detrás sería decidir por
  /// quien está preparando el tema.
  final List<Unit> _chosen = [];

  /// Las que se pueden elegir: las del repositorio del documento.
  late final List<Unit> _units = [
    for (final unit in widget.session.catalogue.units)
      if (unit.repo == widget.repo) unit,
  ];

  late final PathNode _tree = buildPathTree(_units);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _isChosen(Unit unit) => _chosen.any((u) => u.path == unit.path);

  void _toggle(Unit unit) {
    setState(() {
      final at = _chosen.indexWhere((u) => u.path == unit.path);
      if (at >= 0) {
        _chosen.removeAt(at);
      } else {
        _chosen.add(unit);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final language = widget.session.language;
    final searching = needle.isNotEmpty;
    final matches = [
      for (final unit in _units)
        if (unit.path.toLowerCase().contains(needle) ||
            unit.title(language).toLowerCase().contains(needle) ||
            unit.tags.any((tag) => tag.toLowerCase().contains(needle)))
          unit,
    ];

    return AlertDialog(
      title: const Text('Añadir unidades'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              key: const Key('picker-search'),
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Buscar por título, ruta o etiqueta…',
                suffixIcon: searching
                    ? IconButton(
                        key: const Key('picker-clear'),
                        tooltip: 'Volver a las carpetas',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(_query.clear),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                searching
                    ? '${matches.length} de ${_tree.count}'
                    : 'Carpetas del repositorio · ${_tree.count} unidades',
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: didactaCard,
                  border: Border.all(color: didactaRule),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.control),
                  child: searching
                      ? _results(matches, language)
                      : _folders(language),
                ),
              ),
            ),
            // El recuento, debajo de la lista y no en la fila de botones:
            // las acciones de un diálogo viven en una barra que no reparte
            // espacio, y un `Expanded` ahí dentro revienta el layout.
            if (_chosen.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: didactaAccentDark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _chosen.length == 1
                            ? '1 elegida: ${_chosen.single.title(language)}'
                            : '${_chosen.length} elegidas, y se añaden en '
                                  'este orden',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: didactaAccentDark,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('picker-clear-selection'),
                      onPressed: () => setState(_chosen.clear),
                      child: const Text('Quitar la selección'),
                    ),
                  ],
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
        FilledButton(
          key: const Key('picker-add'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(List<Unit>.from(_chosen)),
          child: Text(
            _chosen.length <= 1 ? 'Añadir' : 'Añadir ${_chosen.length}',
          ),
        ),
      ],
    );
  }

  Widget _results(List<Unit> matches, String language) {
    if (matches.isEmpty) {
      return const Center(
        child: Text(
          'Nada coincide.',
          style: TextStyle(fontSize: 13, color: didactaMuted),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: matches.length,
      itemBuilder: (context, index) =>
          _unitRow(matches[index], language, indent: 0, showPath: true),
    );
  }

  /// El árbol, aplanado a la lista de lo que está abierto.
  ///
  /// Aplanado y no anidado a propósito: con dos mil unidades, construir
  /// widgets de todo el árbol para enseñar tres carpetas abiertas es trabajo
  /// tirado, y un `ListView.builder` sobre una lista plana solo construye lo
  /// que se ve.
  Widget _folders(String language) {
    final rows = <Widget>[];

    void walk(PathNode node, int depth) {
      for (final child in node.children) {
        final open = _open.contains(child.path);
        rows.add(_folderRow(child, depth, open));
        if (open) walk(child, depth + 1);
      }
      if (_open.contains(node.path) || depth == 0) {
        for (final unit in node.units(language)) {
          rows.add(_unitRow(unit, language, indent: depth));
        }
      }
    }

    walk(_tree, 0);
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  Widget _folderRow(PathNode node, int depth, bool open) {
    // Cuántas de las de dentro están ya elegidas: al cerrar una carpeta hay
    // que seguir viendo que algo se eligió ahí, o se pierde la cuenta.
    final inside = node.everything('es');
    final chosen = inside.where(_isChosen).length;

    return Hoverable(
      key: Key('folder-${node.path}'),
      onTap: () => setState(() {
        if (!_open.remove(node.path)) _open.add(node.path);
      }),
      builder: (context, hovering) => Container(
        color: hovering ? didactaHover : null,
        padding: EdgeInsets.fromLTRB(8.0 + depth * 16, 7, 10, 7),
        child: Row(
          children: [
            Icon(
              open ? Icons.keyboard_arrow_down : Icons.chevron_right,
              size: 17,
              color: didactaMuted,
            ),
            const SizedBox(width: 4),
            Icon(
              open ? Icons.folder_open : Icons.folder,
              size: 15,
              color: didactaAccentDark.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (chosen > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '$chosen elegidas',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: didactaAccentDark,
                  ),
                ),
              ),
            Text(
              '${node.count}',
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unitRow(
    Unit unit,
    String language, {
    required int indent,
    bool showPath = false,
  }) {
    // Las que ya están se enseñan, no se esconden: saber que una unidad ya
    // está en el documento es la respuesta a «por qué no la encuentro».
    final present = widget.already.contains(unit.reference_);
    final chosen = _isChosen(unit);

    return Hoverable(
      key: Key('unit-${unit.path}'),
      onTap: present ? null : () => _toggle(unit),
      builder: (context, hovering) => Container(
        color: chosen
            ? didactaSelected
            : (hovering && !present ? didactaHover : null),
        padding: EdgeInsets.fromLTRB(10.0 + indent * 16, 5, 10, 5),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Checkbox(
                value: chosen,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: present ? null : (_) => _toggle(unit),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
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
                    unit.title(language),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: present ? didactaMuted : null,
                      fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (present)
                    const Text(
                      'ya está en este documento',
                      style: TextStyle(fontSize: 11, color: didactaEx),
                    )
                  else if (showPath)
                    Text(
                      unit.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: didactaMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            StatusBadge(language: language, status: unit.statusIn(language)),
          ],
        ),
      ),
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
