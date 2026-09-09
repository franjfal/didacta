/// Editing a unit's `unit.yaml` from the interface.
///
/// A form rather than a text box, for the fields where a form is better --
/// the kind is one of nine values, the status one of four, and typing either
/// by hand is how a repository ends up with `theroy` in it. The raw file is
/// one tap away, because a form can only offer the fields it knows about and
/// this schema will grow.
///
/// Two things this screen insists on:
///
/// **The commit shows its diff.** The editor claims to change only the lines
/// it was asked about, leaving the migration comments and the key order
/// alone. That is a promise about someone's file, so it is shown rather than
/// asserted: the dialog lists the lines that will change, and if the diff
/// looks wrong the author can cancel.
///
/// **A shape it does not understand is not overwritten.** `YamlPatch`
/// refuses rather than guesses, and this screen reports the refusal and
/// offers the raw editor. Corrupting a file that is the source of truth is
/// worse than not editing it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/content_gateway.dart';
import '../model/catalogue.dart';
import '../model/line_diff.dart';
import '../model/yaml_patch.dart';
import '../state/session.dart';
import 'theme.dart';

/// The kinds the engine knows. Kept in step with `repo.UNIT_KINDS`; a value
/// outside it is rejected when the repository is read, so offering a free
/// text field here would only move the error later.
const List<String> unitKinds = [
  'theory',
  'problem',
  'handout',
  'activity',
  'example',
  'experiment',
  'history',
  'seminar',
  'practical',
];

/// The statuses a file may declare. `missing` and `outdated` are computed by
/// the engine and deliberately absent: writing either down guarantees it goes
/// stale.
const List<String> declarableStatuses = [
  'draft',
  'translated',
  'reviewed',
  'source',
];

const List<String> difficulties = ['easy', 'medium', 'hard'];

class MetadataEditor extends StatefulWidget {
  const MetadataEditor({super.key, required this.unit, required this.session});

  final Unit unit;
  final Session session;

  @override
  State<MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<MetadataEditor> {
  ContentFile? _file;
  bool _loading = true;
  Object? _error;
  bool _saving = false;
  bool _showRaw = false;
  bool _conflicted = false;

  /// The text as it will be committed. Every form control edits this, not a
  /// parallel model -- so what is shown in the raw view is what will be
  /// written, and there is no second copy to fall out of step.
  String _text = '';
  String _loaded = '';

  final TextEditingController _raw = TextEditingController();

  bool get _dirty => _text != _loaded;

  @override
  void initState() {
    super.initState();
    // A microtask, not a synchronous call: this runs from `build` of the
    // page above, and notifying during a build is not allowed.
    scheduleMicrotask(_load);
  }

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _conflicted = false;
    });
    try {
      final file = await widget.session.gateway.read(widget.unit.metadataPath);
      if (!mounted) return;
      setState(() {
        _file = file;
        _text = file.text;
        _loaded = file.text;
        _raw.text = file.text;
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

  /// Applies an edit, reporting a refusal instead of writing a guess.
  void _edit(void Function(YamlPatch) change) {
    final patch = YamlPatch(_text);
    try {
      change(patch);
    } on YamlPatchException catch (thrown) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se ha tocado el fichero: ${thrown.message}. '
            'Edítalo como texto si hace falta.',
          ),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 7),
          action: SnackBarAction(
            label: 'Ver el fichero',
            onPressed: () => setState(() => _showRaw = true),
          ),
        ),
      );
      return;
    }
    setState(() {
      _text = patch.result;
      _raw.text = _text;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MetadataFailure(
        error: _error!,
        path: widget.unit.metadataPath,
        onRetry: _load,
      );
    }

    final canWrite = widget.session.gateway.canWrite;
    final patch = YamlPatch(_text);
    final size = diffSize(_loaded, _text);

    return Column(
      children: [
        _Bar(
          path: _file?.path ?? widget.unit.metadataPath,
          added: size.added,
          removed: size.removed,
          saving: _saving,
          canSave: canWrite && _dirty && !_saving,
          showRaw: _showRaw,
          onToggleRaw: () => setState(() => _showRaw = !_showRaw),
          onDiscard: _dirty ? _discard : null,
          onSave: _save,
        ),
        if (_conflicted)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Note(
              'unit.yaml ha cambiado en el repositorio desde que lo abriste. '
              'Vuelve a cargarlo antes de guardar; lo que has puesto sigue '
              'aquí mientras decides.',
              tone: didactaTeacher,
            ),
          ),
        Expanded(
          child: _showRaw
              ? _RawView(
                  controller: _raw,
                  readOnly: !canWrite,
                  onChanged: (value) => setState(() => _text = value),
                )
              : _Form(
                  patch: patch,
                  unit: widget.unit,
                  languages: widget.session.catalogue.languages,
                  enabled: canWrite,
                  onEdit: _edit,
                ),
        ),
      ],
    );
  }

  void _discard() {
    setState(() {
      _text = _loaded;
      _raw.text = _loaded;
    });
  }

  Future<void> _save() async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _MetadataCommitDialog(
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
        path: widget.unit.metadataPath,
        text: _text,
        sha: _file?.sha ?? '',
        message: message,
      );
      if (!mounted) return;
      setState(() {
        _loaded = _text;
        _file = ContentFile(
          path: widget.unit.metadataPath,
          text: _text,
          sha: sha,
        );
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('unit.yaml guardado como un commit.')),
      );
      // The catalogue's titles, kinds and statuses just changed.
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

  /// Says which fields changed, because "edit unit.yaml" is not a message
  /// anyone can use a year later.
  String _suggestedMessage() {
    final before = YamlPatch(_loaded);
    final after = YamlPatch(_text);
    final changed = <String>[];

    for (final field in const ['kind', 'category', 'topic', 'difficulty']) {
      if (before.scalar([field]) != after.scalar([field])) changed.add(field);
    }
    if (before.scalar(['duration_minutes']) !=
        after.scalar(['duration_minutes'])) {
      changed.add('duración');
    }
    for (final code in {
      ...before.keysUnder(['title']),
      ...after.keysUnder(['title']),
    }) {
      if (before.scalar(['title', code]) != after.scalar(['title', code])) {
        changed.add('título $code');
      }
    }
    for (final field in const ['tags', 'prerequisites', 'objectives']) {
      final was = before.list([field]);
      final now = after.list([field]);
      if (was.length != now.length || !was.every(now.contains)) {
        changed.add(field);
      }
    }
    for (final code in {
      ...before.keysUnder(['languages']),
      ...after.keysUnder(['languages']),
    }) {
      if (before.scalar(['languages', code]) !=
          after.scalar(['languages', code])) {
        changed.add('estado de $code');
      }
    }

    final title = widget.unit.title(widget.session.language);
    if (changed.isEmpty) return 'Editar unit.yaml de «$title»';
    if (changed.length > 3) {
      return 'Actualizar los metadatos de «$title»';
    }
    return 'Cambiar ${changed.join(', ')} en «$title»';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.path,
    required this.added,
    required this.removed,
    required this.saving,
    required this.canSave,
    required this.showRaw,
    required this.onToggleRaw,
    required this.onDiscard,
    required this.onSave,
  });

  final String path;
  final int added;
  final int removed;
  final bool saving;
  final bool canSave;
  final bool showRaw;
  final VoidCallback onToggleRaw;
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
                  path,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: didactaMuted,
                  ),
                ),
              ),
              if (added + removed > 0) ...[
                const SizedBox(width: 8),
                // The size of the change, next to the button that makes it.
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
              IconButton(
                tooltip: showRaw ? 'Ver el formulario' : 'Ver el fichero',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  showRaw ? Icons.list_alt_outlined : Icons.code,
                  size: 18,
                ),
                onPressed: onToggleRaw,
              ),
              if (!narrow && onDiscard != null)
                TextButton(
                  onPressed: saving ? null : onDiscard,
                  child: const Text('Descartar'),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                key: const Key('metadata-save'),
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

/// The form. Reads from the patch, writes through [onEdit].
class _Form extends StatelessWidget {
  const _Form({
    required this.patch,
    required this.unit,
    required this.languages,
    required this.enabled,
    required this.onEdit,
  });

  final YamlPatch patch;
  final Unit unit;
  final List<String> languages;
  final bool enabled;
  final void Function(void Function(YamlPatch)) onEdit;

  @override
  Widget build(BuildContext context) {
    final kind = patch.scalar(['kind']);
    final difficulty = patch.scalar(['difficulty']);

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        const SectionLabel('Identidad'),
        _Readonly('id', patch.scalar(['id']) ?? unit.id),
        _Readonly('ruta', unit.path),
        // Neither is editable here: the id is what compositions reference by,
        // and the path is the directory. Changing either means moving files
        // and rewriting every year.yaml that mentions it, which is a rename
        // operation and not a field on a form.
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Note(
            'El id y la ruta no se editan aquí: hay composiciones que '
            'referencian este id, así que cambiarlo es un renombrado, no un '
            'campo de un formulario.',
          ),
        ),

        const SectionLabel('Títulos'),
        for (final code in languages)
          _TextRow(
            key: ValueKey('title-$code'),
            label: code,
            value: patch.scalar(['title', code]) ?? '',
            hint: code == unit.reference
                ? 'el título original'
                : 'sin traducir',
            enabled: enabled,
            monospace: true,
            onChanged: (value) => onEdit((p) {
              if (value.trim().isEmpty) {
                p.remove(['title', code]);
              } else {
                p.setScalar(['title', code], value.trim());
              }
            }),
          ),

        const SectionLabel('Clasificación'),
        _ChoiceRow(
          label: 'tipo',
          value: kind,
          options: unitKinds,
          names: kindName,
          colours: kindColour,
          enabled: enabled,
          onChanged: (value) => onEdit((p) => p.setScalar(['kind'], value)),
        ),
        _TextRow(
          label: 'categoría',
          value: patch.scalar(['category']) ?? '',
          enabled: enabled,
          onChanged: (value) =>
              onEdit((p) => p.setScalar(['category'], value.trim())),
        ),
        _TextRow(
          label: 'tema',
          value: patch.scalar(['topic']) ?? '',
          enabled: enabled,
          onChanged: (value) =>
              onEdit((p) => p.setScalar(['topic'], value.trim())),
        ),
        _TagsRow(
          tags: patch.list(['tags']),
          enabled: enabled,
          onChanged: (tags) => onEdit((p) => p.setFlowList(['tags'], tags)),
        ),

        const SectionLabel('Para planificar una clase'),
        _NumberRow(
          label: 'duración',
          suffix: 'minutos',
          value: patch.scalar(['duration_minutes']),
          enabled: enabled,
          onChanged: (value) =>
              onEdit((p) => p.setNumber(['duration_minutes'], value)),
        ),
        _ChoiceRow(
          label: 'dificultad',
          value: difficulty,
          options: difficulties,
          names: (value) => const {
            'easy': 'fácil',
            'medium': 'media',
            'hard': 'difícil',
          }[value]!,
          enabled: enabled,
          allowNone: true,
          onChanged: (value) =>
              onEdit((p) => p.setScalar(['difficulty'], value)),
        ),

        const SectionLabel('Estado declarado por idioma'),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Note(
            '«sin traducir» y «desactualizado» no se declaran: el motor los '
            'calcula, el primero de que el fichero exista y el segundo '
            'comparando el contenido con el original. Escribirlos aquí '
            'garantizaría que se queden obsoletos.',
          ),
        ),
        for (final code in patch.keysUnder(['languages']))
          _ChoiceRow(
            key: ValueKey('status-$code'),
            label: code,
            value:
                patch.scalar(['languages', code, 'status']) ??
                patch.scalar(['languages', code]),
            options: declarableStatuses,
            names: (value) => const {
              'draft': 'borrador',
              'translated': 'traducido',
              'reviewed': 'revisado',
              'source': 'original',
            }[value]!,
            enabled: enabled,
            onChanged: (value) => onEdit(
              (p) => p.setInFlowMap(['languages', code], 'status', value),
            ),
          ),

        const SectionLabel('Prerrequisitos'),
        _ListRow(
          items: patch.list(['prerequisites']),
          hint: 'analysis/normed/definition',
          enabled: enabled,
          onChanged: (items) =>
              onEdit((p) => p.setBlockList(['prerequisites'], items)),
        ),

        const SectionLabel('Objetivos'),
        _ListRow(
          items: patch.list(['objectives']),
          hint: 'Qué sabe hacer alguien después de esta unidad',
          enabled: enabled,
          onChanged: (items) =>
              onEdit((p) => p.setBlockList(['objectives'], items)),
        ),
      ],
    );
  }
}

class _Readonly extends StatelessWidget {
  const _Readonly(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: didactaMuted),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );
}

/// A labelled field that commits on every keystroke.
///
/// Debounced would be wrong here: the value being edited is the file itself,
/// and a keystroke that has not reached it yet is a keystroke that a save
/// would lose.
class _TextRow extends StatefulWidget {
  const _TextRow({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.hint,
    this.monospace = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool enabled;
  final bool monospace;
  final ValueChanged<String> onChanged;

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_TextRow old) {
    super.didUpdateWidget(old);
    // Only when the file changed underneath -- a reload or a discard. Setting
    // it on every rebuild would fight the cursor.
    if (widget.value != _controller.text && widget.value != old.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            widget.label,
            style: const TextStyle(fontSize: 11.5, color: didactaMuted),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: widget.enabled,
            style: TextStyle(
              fontSize: 13,
              fontFamily: widget.monospace ? 'monospace' : null,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ],
    ),
  );
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.suffix,
  });

  final String label;
  final String? value;
  final String? suffix;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => _TextRow(
    label: label,
    value: value ?? '',
    hint: suffix,
    enabled: enabled,
    // An empty field means "not recorded", which is `null` -- not zero.
    onChanged: (text) => onChanged(int.tryParse(text.trim())),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.names,
    required this.enabled,
    required this.onChanged,
    this.colours,
    this.allowNone = false,
  });

  final String label;
  final String? value;
  final List<String> options;
  final String Function(String) names;
  final Color Function(String)? colours;
  final bool enabled;
  final bool allowNone;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                if (allowNone)
                  ChoiceChip(
                    label: const Text('sin definir'),
                    selected: value == null,
                    visualDensity: VisualDensity.compact,
                    onSelected: enabled ? (_) => onChanged(null) : null,
                  ),
                for (final option in options)
                  ChoiceChip(
                    label: Text(names(option)),
                    selected: option == value,
                    visualDensity: VisualDensity.compact,
                    avatar: colours == null
                        ? null
                        : Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colours!(option),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                    onSelected: enabled ? (_) => onChanged(option) : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  const _TagsRow({
    required this.tags,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> tags;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 92,
            child: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'etiquetas',
                style: TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final tag in tags)
                  InputChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onDeleted: enabled
                        ? () => onChanged([...tags]..remove(tag))
                        : null,
                  ),
                if (enabled)
                  _AddTag(
                    onAdd: (tag) {
                      if (tag.isEmpty || tags.contains(tag)) return;
                      onChanged([...tags, tag]);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTag extends StatefulWidget {
  const _AddTag({required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  State<_AddTag> createState() => _AddTagState();
}

class _AddTagState extends State<_AddTag> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onAdd(_controller.text.trim());
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: TextField(
      controller: _controller,
      style: const TextStyle(fontSize: 12.5),
      decoration: const InputDecoration(
        isDense: true,
        hintText: '+ etiqueta',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _submit(),
    ),
  );
}

/// A block list: one line each, add and remove.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.items,
    required this.enabled,
    required this.onChanged,
    this.hint,
  });

  final List<String> items;
  final String? hint;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i += 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: _TextRow(
                    key: ValueKey('item-$i-${items[i]}'),
                    label: '${i + 1}.',
                    value: items[i],
                    enabled: enabled,
                    onChanged: (value) {
                      final next = [...items];
                      next[i] = value;
                      onChanged(next);
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline, size: 17),
                  onPressed: enabled
                      ? () => onChanged([...items]..removeAt(i))
                      : null,
                ),
              ],
            ),
          ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(104, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 15),
                label: Text(hint == null ? 'Añadir' : 'Añadir: $hint'),
                onPressed: () => onChanged([...items, '']),
              ),
            ),
          ),
      ],
    );
  }
}

class _RawView extends StatelessWidget {
  const _RawView({
    required this.controller,
    required this.readOnly,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    child: TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: null,
      expands: true,
      style: monoStyle,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(
        border: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.all(14),
      ),
      onChanged: onChanged,
    ),
  );
}

/// The commit dialog, with the diff in it.
class _MetadataCommitDialog extends StatefulWidget {
  const _MetadataCommitDialog({
    required this.before,
    required this.after,
    required this.suggested,
  });

  final String before;
  final String after;
  final String suggested;

  @override
  State<_MetadataCommitDialog> createState() => _MetadataCommitDialogState();
}

class _MetadataCommitDialogState extends State<_MetadataCommitDialog> {
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
      title: const Text('Guardar unit.yaml'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esto es lo que va a cambiar. Los comentarios y el orden de '
              'las claves no se tocan.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
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
          key: const Key('metadata-commit'),
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

class _MetadataFailure extends StatelessWidget {
  const _MetadataFailure({
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No se ha podido abrir unit.yaml',
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
              FilledButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
