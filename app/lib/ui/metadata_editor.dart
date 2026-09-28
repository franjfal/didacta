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
import '../model/metadata_suggestions.dart';
import '../model/yaml_patch.dart';
import '../router.dart';
import '../state/session.dart';
import 'manage_templates.dart';
import 'save_review.dart';
import 'save_shortcut.dart';
import 'suggest_field.dart';
import 'theme.dart';
import 'unit_page.dart';
import '../l10n/tr.dart';

export '../model/catalogue.dart' show declarableStatuses;

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

/// Lo que se ofrece declarar de una versión, según la interfaz.
///
/// En la esencial, dos estados y nada más: **sin revisar** y
/// **revisada**, que son las dos preguntas que se hace quien traduce. «Traducida»
/// --hecha y sin revisar, lo que deja la migración-- y «original» son de quien
/// mantiene el repositorio y quedan para la completa. La versión de referencia,
/// en la esencial, no ofrece nada: es el original y ya está.
List<String> declarableStatusesFor({
  required bool complete,
  required bool reference,
}) {
  if (complete) return declarableStatuses;
  return reference ? const [] : const ['draft', 'reviewed'];
}

/// Cómo se llama cada estado que se puede declarar, en un menú.
Map<String, String> get declarableStatusNames => {
  'draft': tr('sin revisar'),
  'translated': tr('traducida'),
  'reviewed': tr('revisada'),
  'source': tr('original'),
};

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

  /// Lo que usan las demás lecciones, calculado una vez por catálogo: el
  /// formulario se vuelve a pintar a cada tecla, y recorrer dos mil lecciones
  /// a cada tecla no hace falta.
  MetadataSuggestions? _suggestions;
  Catalogue? _suggestionsOf;

  MetadataSuggestions get _suggested {
    final catalogue = widget.session.catalogue;
    if (_suggestions == null || !identical(_suggestionsOf, catalogue)) {
      _suggestions = MetadataSuggestions.of(
        catalogue,
        language: widget.session.language,
      );
      _suggestionsOf = catalogue;
    }
    return _suggestions!;
  }

  @override
  void initState() {
    super.initState();
    // A microtask, not a synchronous call: this runs from `build` of the
    // page above, and notifying during a build is not allowed.
    scheduleMicrotask(_load);
  }

  @override
  void dispose() {
    widget.session.unsaved.mark(this, null);
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
      final file = await widget.session
          .gatewayFor(widget.unit.repo)
          .read(widget.unit.metadataPath);
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
            tr(
              'No se ha tocado el fichero: {0}. '
              'Edítalo como texto si hace falta.',
              [thrown.message],
            ),
          ),
          backgroundColor: context.palette.teacher,
          duration: const Duration(seconds: 7),
          action: SnackBarAction(
            label: tr('Ver el fichero'),
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
    widget.session.unsaved.mark(
      this,
      _dirty
          ? tr('Los metadatos de «{0}»', [
              widget.unit.title(widget.session.language),
            ])
          : null,
      place: Routes.unit(widget.unit.path),
    );
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

    final canWrite = widget.session.canWriteIn(widget.unit.repo);
    final patch = YamlPatch(_text);
    final size = diffSize(_loaded, _text);

    return SaveShortcut(
      onSave: canWrite && _dirty && !_saving ? _save : null,
      child: Column(
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
                tr(
                  'unit.yaml ha cambiado en el repositorio desde que lo abriste. '
                  'Vuelve a cargarlo antes de guardar; lo que has puesto sigue '
                  'aquí mientras decides.',
                ),
                tone: context.palette.teacher,
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
                    session: widget.session,
                    languages: languagesOfUnit(widget.session, widget.unit),
                    blocks: widget.session.catalogue.blocksInUse,
                    suggestions: _suggested,
                    enabled: canWrite,
                    onEdit: _edit,
                  ),
          ),
        ],
      ),
    );
  }

  void _discard() {
    setState(() {
      _text = _loaded;
      _raw.text = _loaded;
    });
  }

  Future<void> _save() async {
    final suggested = _suggestedMessage();
    final message = await askSaveMessage(
      context,
      widget.session,
      suggested: suggested,
      dialog: (context) => _MetadataCommitDialog(
        before: _loaded,
        after: _text,
        suggested: suggested,
      ),
    );
    if (message == null || !mounted) return;
    final before = _loaded;
    final navigator = Navigator.of(context, rootNavigator: true);

    setState(() {
      _saving = true;
      _conflicted = false;
    });
    try {
      final sha = await widget.session
          .gatewayFor(widget.unit.repo)
          .save(
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
        savedNotice(
          notice: widget.session.saveNotice(widget.unit.repo),
          message: message,
          before: before,
          after: _text,
          what: widget.unit.metadataPath,
          navigator: navigator,
        ),
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
          backgroundColor: context.palette.teacher,
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
      changed.add(tr('duración'));
    }
    for (final code in {
      ...before.keysUnder(['title']),
      ...after.keysUnder(['title']),
    }) {
      if (before.scalar(['title', code]) != after.scalar(['title', code])) {
        changed.add(tr('título {0}', [code]));
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
        changed.add(tr('estado de {0}', [code]));
      }
    }

    final title = widget.unit.title(widget.session.language);
    if (changed.isEmpty) return tr('Editar unit.yaml de «{0}»', [title]);
    if (changed.length > 3) {
      return tr('Actualizar los metadatos de «{0}»', [title]);
    }
    return tr('Cambiar {0} en «{1}»', [changed.join(', '), title]);
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
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
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: context.palette.muted,
                  ),
                ),
              ),
              if (added + removed > 0) ...[
                const SizedBox(width: 8),
                // The size of the change, next to the button that makes it.
                Text(
                  '+$added −$removed',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: context.palette.ex,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              // El fichero en bruto, en la interfaz completa; y también de
              // vuelta, si se llegó a él porque el formulario no podía.
              if (watchSession(context).completeInterface || showRaw)
                IconButton(
                  key: const Key('metadata-raw'),
                  tooltip: showRaw
                      ? tr('Ver el formulario')
                      : tr('Ver el fichero'),
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
                  child: Text(tr('Descartar')),
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
                label: Text(saving ? tr('Guardando…') : tr('Guardar')),
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
    required this.session,
    required this.languages,
    required this.blocks,
    required this.suggestions,
    required this.enabled,
    required this.onEdit,
  });

  final MetadataSuggestions suggestions;

  final YamlPatch patch;
  final Unit unit;

  /// Para el catálogo: qué plantillas hay y qué hereda esta lección de su
  /// bloque. No se escribe a través de ella --lo que se edita es el parche,
  /// que es lo que enseña su diff antes de confirmar-- solo se lee.
  final Session session;

  final List<String> languages;

  /// Los bloques entre los que se puede elegir. Ver [Catalogue.blocksInUse]:
  /// los declarados y, detrás, los que alguna lección nombra sin que nadie
  /// los declare -- porque el de esta lección puede ser uno de esos, y una
  /// lista que no lo incluyera lo borraría al primer cambio de otro campo.
  final List<CourseBlock> blocks;

  final bool enabled;
  final void Function(void Function(YamlPatch)) onEdit;

  /// El bloque escrito en el fichero, o el que el catálogo dedujo.
  ///
  /// Sin escribir es lo corriente en material migrado: entonces lo decidía el
  /// árbol, y es lo que [Unit] sigue deduciendo. Enseñar el deducido y no un
  /// hueco es lo que hace que elegir otro sea un cambio y no un
  /// descubrimiento.
  String? get _block => patch.scalar(['block']) ?? unit.block;

  /// Su nombre, de los que el catálogo ofrece.
  String _blockName(String id) {
    for (final block in blocks) {
      if (block.id == id) return block.title();
    }
    return blockLabel(id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final kind = patch.scalar(['kind']);
    final difficulty = patch.scalar(['difficulty']);

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        SectionLabel(tr('Identidad')),
        _Readonly('id', patch.scalar(['id']) ?? unit.id),
        _Readonly(tr('ruta'), unit.path),
        // Neither is editable here: the id is what compositions reference by,
        // and the path is the directory. Changing either means moving files
        // and rewriting every year.yaml that mentions it, which is a rename
        // operation and not a field on a form.
        Padding(
          padding: EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Note(
            tr(
              'El id y la ruta no se editan aquí: hay composiciones que '
              'referencian este id, así que cambiarlo es un renombrado, no un '
              'campo de un formulario.',
            ),
          ),
        ),

        SectionLabel(tr('Títulos')),
        for (final code in languages)
          _TextRow(
            key: ValueKey('title-$code'),
            label: code,
            value: patch.scalar(['title', code]) ?? '',
            hint: code == unit.reference
                ? tr('el título original')
                : tr('sin traducir'),
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

        SectionLabel(tr('Clasificación')),
        _ChoiceRow(
          label: tr('tipo'),
          value: kind,
          options: unitKinds,
          names: kindName,
          colours: context.palette.kind,
          enabled: enabled,
          onChanged: (value) => onEdit((p) => p.setScalar(['kind'], value)),
        ),
        // De qué parte de la asignatura es. No es el tipo, y confundirlos es
        // el error que esto deshizo: el tipo dice qué **es** el fichero --una
        // explicación, un ejemplo, un ejercicio-- y el bloque de qué parte de
        // la asignatura forma parte. Una explicación teórica dentro de una
        // práctica de problemas es `kind: theory` y bloque «problemas», y las
        // dos cosas son ciertas.
        //
        // Una lista y no un campo de texto, como el tipo: escribirlo a mano
        // es como un repositorio acaba con `problms` y una lección que no
        // sale en ningún filtro.
        _ChoiceRow(
          key: const ValueKey('unit-block'),
          label: tr('bloque'),
          value: _block,
          options: [for (final block in blocks) block.id],
          names: (value) => _blockName(value),
          enabled: enabled && blocks.isNotEmpty,
          onChanged: (value) => onEdit((p) => p.setScalar(['block'], value)),
        ),
        // Con lo que ya usan las demás, y diciendo cuándo lo escrito es
        // nuevo: una errata en la categoría crea una categoría y saca la
        // lección de su sitio en la biblioteca sin que nadie lo vea.
        _TextRow(
          key: const ValueKey('unit-category'),
          label: tr('categoría'),
          value: patch.scalar(['category']) ?? '',
          enabled: enabled,
          suggestions: suggestions.categories,
          note: (value) => value.isEmpty || suggestions.knowsCategory(value)
              ? null
              : tr(
                  'Categoría nueva: ninguna otra lección la usa. Si es una '
                  'errata, la lección saldrá sola en la biblioteca.',
                ),
          onChanged: (value) =>
              onEdit((p) => p.setScalar(['category'], value.trim())),
        ),
        _TextRow(
          key: const ValueKey('unit-topic'),
          label: tr('tema'),
          value: patch.scalar(['topic']) ?? '',
          enabled: enabled,
          suggestions: (typed) =>
              suggestions.topics(typed, category: patch.scalar(['category'])),
          note: (value) => value.isEmpty || suggestions.knowsTopic(value)
              ? null
              : tr('Tema nuevo: ninguna otra lección lo usa.'),
          onChanged: (value) =>
              onEdit((p) => p.setScalar(['topic'], value.trim())),
        ),
        _TagsRow(
          tags: patch.list(['tags']),
          enabled: enabled,
          suggestions: suggestions,
          onChanged: (tags) => onEdit((p) => p.setFlowList(['tags'], tags)),
        ),

        SectionLabel(tr('Salidas')),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Note(
            tr(
              'En qué plantillas se compila esta lección. Lo normal es no '
              'elegir: sale lo que diga su bloque, y cambiar el bloque las '
              'cambia todas de una vez. Elegir aquí es apartar esta en concreto.',
            ),
          ),
        ),
        _TemplatesRow(
          chosen: patch.list(['templates']),
          session: session,
          unit: unit,
          enabled: enabled,
          onChanged: (templates) => onEdit((p) {
            if (templates.isEmpty) {
              p.remove(['templates']);
            } else {
              p.setFlowList(['templates'], templates);
            }
          }),
        ),

        SectionLabel(tr('Para planificar una clase')),
        _NumberRow(
          label: tr('duración'),
          suffix: tr('minutos'),
          value: patch.scalar(['duration_minutes']),
          enabled: enabled,
          onChanged: (value) =>
              onEdit((p) => p.setNumber(['duration_minutes'], value)),
        ),
        _ChoiceRow(
          label: tr('dificultad'),
          value: difficulty,
          options: difficulties,
          names: difficultyName,
          enabled: enabled,
          allowNone: true,
          onChanged: (value) =>
              onEdit((p) => p.setScalar(['difficulty'], value)),
        ),

        SectionLabel(tr('Estado declarado por idioma')),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Note(
            tr(
              '«sin traducir» y «desactualizado» no se declaran: el motor los '
              'calcula, el primero de que el fichero exista y el segundo '
              'comparando el contenido con el original. Escribirlos aquí '
              'garantizaría que se queden obsoletos.',
            ),
          ),
        ),
        for (final code in patch.keysUnder(['languages']))
          if (declarableStatusesFor(
                complete: session.completeInterface,
                reference: code == unit.reference,
              )
              case final options when options.isNotEmpty)
            _ChoiceRow(
              key: ValueKey('status-$code'),
              label: code,
              value:
                  patch.scalar(['languages', code, 'status']) ??
                  patch.scalar(['languages', code]),
              options: [
                ...options,
                // Lo que tenga escrito, aunque en esta interfaz no se ofrezca:
                // un desplegable sin su valor lo borraría al tocar otro campo.
                if (patch.scalar(['languages', code, 'status'])
                    case final written?
                    when !options.contains(written) &&
                        declarableStatuses.contains(written))
                  written,
              ],
              names: (value) => declarableStatusNames[value]!,
              enabled: enabled,
              onChanged: (value) => onEdit(
                (p) => p.setInFlowMap(['languages', code], 'status', value),
              ),
            ),

        SectionLabel(tr('Prerrequisitos')),
        _ListRow(
          items: patch.list(['prerequisites']),
          hint: 'analysis/normed/definition',
          enabled: enabled,
          suggestions: (typed) =>
              suggestions.units(typed, except: unit.reference_),
          note: (value) => value.trim().isEmpty || suggestions.knowsUnit(value)
              ? null
              : tr('No hay ninguna lección con esa ruta.'),
          onChanged: (items) =>
              onEdit((p) => p.setBlockList(['prerequisites'], items)),
        ),

        SectionLabel(tr('Objetivos')),
        _ListRow(
          items: patch.list(['objectives']),
          hint: tr('Qué sabe hacer alguien después de esta unidad'),
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
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
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
    this.suggestions,
    this.note,
  });

  final String label;
  final String value;
  final String? hint;
  final bool enabled;
  final bool monospace;
  final ValueChanged<String> onChanged;

  /// Lo que se sugiere al escribir, si se sugiere algo.
  final List<Suggestion> Function(String typed)? suggestions;

  /// Un aviso debajo, sobre lo que hay escrito, o null.
  final String? Function(String value)? note;

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
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontFamily: widget.monospace ? 'monospace' : null,
    );
    final suggestions = widget.suggestions;
    final note = widget.note?.call(widget.value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
              Expanded(
                child: suggestions == null
                    ? TextField(
                        controller: _controller,
                        enabled: widget.enabled,
                        style: style,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.hint,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: widget.onChanged,
                      )
                    : SuggestField(
                        controller: _controller,
                        suggestions: suggestions,
                        enabled: widget.enabled,
                        hintText: widget.hint,
                        style: style,
                        onChanged: widget.onChanged,
                        onSelected: widget.onChanged,
                      ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 92, top: 4),
              child: Text(
                note,
                key: Key('note-${widget.label}'),
                style: TextStyle(fontSize: 11.5, color: context.palette.ex),
              ),
            ),
        ],
      ),
    );
  }
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
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
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
                    label: Text(tr('sin definir')),
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

/// Con qué plantillas se compila esta lección.
///
/// Se edita el parche, no el fichero: así el cambio entra en el mismo diff
/// que se enseña antes de confirmar, como el resto del formulario. Vacío
/// quiere decir «las de su bloque», y es lo que lleva casi todo el material.
class _TemplatesRow extends StatelessWidget {
  const _TemplatesRow({
    required this.chosen,
    required this.session,
    required this.unit,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> chosen;
  final Session session;
  final Unit unit;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final catalogue = session.catalogue;
    final inherited = catalogue.templatesOfBlock(unit.block);
    final showing = chosen.isEmpty ? inherited : chosen;
    final blockName = catalogue.blockNamed(unit.block).title(session.language);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              tr('plantillas'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showing.isEmpty
                      ? tr('ninguna encendida')
                      : showing
                            .map(
                              (id) => catalogue
                                  .templateNamed(id)
                                  .title(session.language),
                            )
                            .join(' · '),
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  chosen.isEmpty
                      ? tr('las de «{0}»', [blockName])
                      : tr('elegidas para esta lección'),
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('unit-templates'),
            onPressed: enabled
                ? () async {
                    final answer = await chooseTemplates(
                      context,
                      session,
                      title: tr('Salidas de esta lección'),
                      inherited: inherited.isEmpty
                          ? tr('Las de su bloque. No hay ninguna encendida.')
                          : tr('Las de «{0}»: {1}', [
                              blockName,
                              inherited.length,
                            ]),
                      chosen: chosen,
                      byDefault: inherited,
                    );
                    if (answer != null) onChanged(answer);
                  }
                : null,
            child: Text(tr('Elegir')),
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
    required this.suggestions,
    required this.onChanged,
  });

  final MetadataSuggestions suggestions;
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
          SizedBox(
            width: 92,
            child: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                tr('etiquetas'),
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
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
                    suggestions: (typed) =>
                        suggestions.tags(typed, except: tags.toSet()),
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
  const _AddTag({required this.onAdd, required this.suggestions});

  final ValueChanged<String> onAdd;
  final List<Suggestion> Function(String typed) suggestions;

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

  void _add(String tag) {
    widget.onAdd(tag.trim());
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    // Intro con lo escrito lo añade igual aunque no exista: lo nuevo va el
    // primero de la lista, marcado, y es lo que se elige.
    child: SuggestField(
      key: const Key('add-tag'),
      controller: _controller,
      suggestions: widget.suggestions,
      hintText: tr('+ etiqueta'),
      style: const TextStyle(fontSize: 12.5),
      onSelected: _add,
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
    this.suggestions,
    this.note,
  });

  final List<Suggestion> Function(String typed)? suggestions;
  final String? Function(String value)? note;
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
                    suggestions: suggestions,
                    note: note,
                    onChanged: (value) {
                      final next = [...items];
                      next[i] = value;
                      onChanged(next);
                    },
                  ),
                ),
                IconButton(
                  tooltip: tr('Quitar'),
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
                label: Text(
                  hint == null ? tr('Añadir') : tr('Añadir: {0}', [hint]),
                ),
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
    color: context.palette.card,
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
      title: Text(tr('Guardar unit.yaml')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Esto es lo que va a cambiar. Los comentarios y el orden de '
                'las claves no se tocan.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.palette.panel,
                  border: Border.all(color: context.palette.rule),
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
              decoration: InputDecoration(labelText: tr('Mensaje')),
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
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('metadata-commit'),
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? widget.suggested : text);
          },
          child: Text(tr('Guardar')),
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
      ChangeKind.added => ('+', context.palette.accentDark),
      ChangeKind.removed => ('−', context.palette.teacher),
      ChangeKind.kept => (' ', context.palette.muted),
    };
    return Text(
      '$marker ${line.text}',
      style: TextStyle(
        fontSize: 11.5,
        fontFamily: 'monospace',
        color: line.isChange ? colour : context.palette.muted,
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
              Text(
                tr('No se ha podido abrir unit.yaml'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                path,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: context.palette.muted,
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
                label: Text(tr('Reintentar')),
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
