/// One unit: what it is, where it is used, and its multilingual editor.
///
/// The editor is the reason this screen exists, and three decisions shape it:
///
/// **One tab per language, loaded on demand.** A unit has up to three
/// versions; opening them all up front would be three requests for a screen
/// where usually one is read. A tab that has never been opened is not fetched.
///
/// **Saving is a commit, and it asks for a message.** Not a dialog for the
/// sake of ceremony: the message is what makes the history readable a year
/// later, and a default of "edit x" produces a log nobody can use. The
/// suggested message says what changed; the author can replace it.
///
/// **A conflict is never resolved by retrying.** If the file moved on since it
/// was opened, the save fails and the screen says so with the option to
/// reload -- because the alternative is silently overwriting whoever got there
/// first.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/content_gateway.dart';
import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'metadata_editor.dart';
import 'pdf_tab.dart';
import 'unit_preview.dart';
import 'shell.dart';
import 'theme.dart';

class UnitPage extends StatefulWidget {
  const UnitPage({super.key, required this.unitPath});

  final String unitPath;

  @override
  State<UnitPage> createState() => _UnitPageState();
}

/// Which tab of a unit is open: one of its languages, or its `unit.yaml`.
///
/// The metadata sits alongside the languages rather than on its own screen
/// because it is the same object being edited -- and because the fields most
/// often wrong after a migration are the title and the kind, which is a
/// thing you notice while reading the text.
const String metadataTab = '\u0000metadata';

/// La pestaña de compilar: «¿cómo queda esto?».
const String previewTab = '\u0000preview';

/// La pestaña de un PDF abierto. El prefijo la distingue de un idioma sin
/// necesitar un tipo aparte para el valor de la pestaña activa.
const String pdfTabPrefix = '\u0000pdf:';

String _pdfTab(String key) => '$pdfTabPrefix$key';

class _UnitPageState extends State<UnitPage> {
  /// One editor per language, created when its tab is first opened.
  final Map<String, _LanguageEditor> _editors = {};
  String? _active;

  /// Los PDF abiertos, en el orden en que se abrieron.
  ///
  /// Varios a la vez a propósito: comparar «cómo queda en diapositivas» con
  /// «cómo queda en libro» es mirar dos cosas, y una sola pestaña de PDF
  /// obliga a recompilar para volver a la otra.
  final List<OpenPdf> _open = [];

  /// El estado de compilar, creado al abrir la pestaña por primera vez.
  ///
  /// Vive aquí y no en el widget por lo mismo que los editores: al volver de
  /// mirar el PDF, lo compilado tiene que seguir estando.
  PreviewState? _preview;

  void _openPdf(OpenPdf pdf) {
    setState(() {
      // La misma salida no se abre dos veces: se reemplaza, porque tras
      // recompilar el fichero es nuevo y la pestaña es la misma.
      final at = _open.indexWhere((other) => other.key == pdf.key);
      if (at >= 0) {
        _open[at] = pdf;
      } else {
        _open.add(pdf);
      }
      _active = _pdfTab(pdf.key);
    });
  }

  void _closePdf(String key) {
    setState(() {
      _open.removeWhere((pdf) => pdf.key == key);
      if (_active == _pdfTab(key)) {
        // Se vuelve a compilar y no al primer idioma: es de donde se venía.
        _active = previewTab;
      }
    });
  }

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final unit = session.unitByPath(widget.unitPath);

    if (unit == null) {
      return _Missing(path: widget.unitPath);
    }

    final languages = session.catalogue.languages;
    _active ??= _preferredLanguage(unit, session, languages);

    return Column(
      children: [
        PageHeader(
          title: unit.title(session.language),
          subtitle: unit.path,
          breadcrumbs: [('Biblioteca', Routes.library())],
          actions: [
            IconButton(
              tooltip: 'Copiar la referencia para una composición',
              icon: const Icon(Icons.content_copy_outlined, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: unit.reference_));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copiado: ${unit.reference_}')),
                );
              },
            ),
          ],
          bottom: _LanguageTabs(
            unit: unit,
            languages: languages,
            active: _active!,
            open: _open,
            dirty: {
              for (final entry in _editors.entries)
                if (entry.value.isDirty) entry.key,
            },
            onSelect: (code) => setState(() => _active = code),
            onClose: _closePdf,
          ),
        ),
        Expanded(
          // Built here rather than inside the `LayoutBuilder`: the editor is
          // needed in both branches, and creating state during layout is a
          // worse place to do it than during build.
          child: _WithEditor(
            editor: _panelFor(unit, session),
            builder: (context, constraints, editor) {
              // Side by side when there is room; the metadata panel is
              // reference material you consult while writing, so hiding it
              // behind a tab would mean leaving the text to check a tag.
              if (constraints.maxWidth >= 1000) {
                return Row(
                  children: [
                    Expanded(child: editor),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: _UnitPanel(unit: unit, session: session),
                    ),
                  ],
                );
              }
              return editor;
            },
          ),
        ),
      ],
    );
  }

  /// Lo que se muestra para la pestaña activa.
  Widget _panelFor(Unit unit, Session session) {
    final active = _active!;
    if (active.startsWith(pdfTabPrefix)) {
      final key = active.substring(pdfTabPrefix.length);
      final pdf = _open.where((other) => other.key == key).firstOrNull;
      // Puede no estar si se cerró justo antes de este build.
      if (pdf != null) {
        return PdfTabView(
          key: ValueKey('pdf-$key'),
          pdf: pdf,
          onOpenExternally: () => _external(session, pdf.path, reveal: false),
          onReveal: () => _external(session, pdf.path, reveal: true),
          onRecompile: () => setState(() => _active = previewTab),
        );
      }
    }
    return switch (active) {
      // Keyed by path so moving to another unit rebuilds it rather than
      // showing the previous unit's file while it loads.
      metadataTab => MetadataEditor(
        key: ValueKey('metadata-${unit.path}'),
        unit: unit,
        session: session,
      ),
      previewTab => UnitPreview(
        state: _preview ??= PreviewState(
          unit: unit,
          session: session,
          onChanged: () {
            if (mounted) setState(() {});
          },
        ),
        onOpen: _openPdf,
        onExternal: (path, {required bool reveal}) =>
            _external(session, path, reveal: reveal),
      ),
      final language => _editorFor(unit, language, session),
    };
  }

  Future<void> _external(
    Session session,
    String path, {
    required bool reveal,
  }) async {
    try {
      final compiler = session.compiler();
      if (compiler == null) return;
      if (reveal) {
        await compiler.reveal(path);
      } else {
        await compiler.open(path);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// Which language to open first: the one being browsed if it exists, else
  /// the unit's own reference. Opening a missing translation by default would
  /// show an empty editor for a unit that has content.
  String _preferredLanguage(
    Unit unit,
    Session session,
    List<String> languages,
  ) {
    if (unit.statusIn(session.language).exists) return session.language;
    if (unit.statusIn(unit.reference).exists) return unit.reference;
    for (final code in languages) {
      if (unit.statusIn(code).exists) return code;
    }
    return unit.reference;
  }

  Widget _editorFor(Unit unit, String language, Session session) {
    final editor = _editors.putIfAbsent(
      language,
      () => _LanguageEditor(
        unit: unit,
        language: language,
        session: session,
        onChanged: () => setState(() {}),
      ),
    );
    return _EditorView(editor: editor, unit: unit, language: language);
  }
}

/// The state of editing one language of one unit.
///
/// Not a widget: a tab that is switched away from must keep its unsaved text,
/// and state that lives in a widget is discarded when the widget is.
class _LanguageEditor {
  _LanguageEditor({
    required this.unit,
    required this.language,
    required this.session,
    required this.onChanged,
  }) {
    controller.addListener(_onEdit);
    // Deliberately *not* `load()`: this object is created from `build`, and
    // `load` notifies as soon as it starts, which would be a `setState`
    // during build. A microtask puts the whole of it after the frame's build
    // phase. Nothing is lost by waiting -- `loading` already starts true, so
    // the screen shows the spinner on the very first frame either way.
    scheduleMicrotask(load);
  }

  final Unit unit;
  final String language;
  final Session session;
  final VoidCallback onChanged;

  final TextEditingController controller = TextEditingController();

  ContentFile? file;
  String _loadedText = '';
  bool loading = true;
  Object? error;
  bool saving = false;

  /// Set when the file changed underneath. Cleared only by reloading, never
  /// by trying again.
  bool conflicted = false;

  bool get isDirty => !loading && controller.text != _loadedText;

  bool get exists => unit.statusIn(language).exists;

  void _onEdit() => onChanged();

  Future<void> load() async {
    loading = true;
    error = null;
    conflicted = false;
    onChanged();
    try {
      if (!exists) {
        // A language that does not exist yet is a new file, not an error. It
        // starts from the reference version so a translator has the original
        // in front of them rather than a blank page.
        final reference = unit.statusIn(unit.reference).exists
            ? await session.gateway.read(unit.fileFor(unit.reference))
            : null;
        file = ContentFile(path: unit.fileFor(language), text: '', sha: '');
        _loadedText = '';
        controller.text = reference == null
            ? ''
            : '%% Traducción pendiente. El original en '
                  '${unit.reference} está debajo; sustitúyelo.\n'
                  '${reference.text}';
      } else {
        final loaded = await session.gateway.read(unit.fileFor(language));
        file = loaded;
        _loadedText = loaded.text;
        controller.text = loaded.text;
      }
    } catch (thrown) {
      error = thrown;
    } finally {
      loading = false;
      onChanged();
    }
  }

  /// The message suggested in the save dialog.
  ///
  /// Says what actually changed, because a log full of "edit file" is a log
  /// nobody reads.
  String suggestedMessage() {
    final title = unit.title(language);
    if (!exists) return 'Añadir la versión $language de «$title»';
    return 'Editar la versión $language de «$title»';
  }

  Future<String?> save(String message) async {
    saving = true;
    conflicted = false;
    onChanged();
    try {
      final sha = await session.gateway.commit(
        path: unit.fileFor(language),
        text: controller.text,
        sha: file?.sha ?? '',
        message: message,
      );
      _loadedText = controller.text;
      file = ContentFile(
        path: unit.fileFor(language),
        text: controller.text,
        sha: sha,
      );
      return null;
    } on ContentException catch (thrown) {
      if (thrown.kind == ContentFailure.conflict) conflicted = true;
      return thrown.message;
    } catch (thrown) {
      return thrown.toString();
    } finally {
      saving = false;
      onChanged();
    }
  }

  void dispose() {
    controller.removeListener(_onEdit);
    controller.dispose();
  }
}

class _EditorView extends StatelessWidget {
  const _EditorView({
    required this.editor,
    required this.unit,
    required this.language,
  });

  final _LanguageEditor editor;
  final Unit unit;
  final String language;

  @override
  Widget build(BuildContext context) {
    if (editor.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (editor.error != null) {
      return _LoadFailure(
        error: editor.error!,
        path: unit.fileFor(language),
        onRetry: editor.load,
      );
    }

    final canWrite = watchSession(context).gateway.canWrite;

    return Column(
      children: [
        _EditorBar(editor: editor, canWrite: canWrite),
        if (editor.conflicted)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Note(
              'El fichero ha cambiado en el repositorio desde que lo abriste. '
              'Vuelve a cargarlo para no sobrescribir el trabajo de otra '
              'persona; tu texto sigue aquí mientras decides.',
              tone: didactaTeacher,
            ),
          ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: TextField(
              controller: editor.controller,
              readOnly: !canWrite,
              maxLines: null,
              expands: true,
              // LaTeX is code: monospace, no autocorrect, no capitalisation.
              // A phone helpfully capitalising `\begin` is a compile error.
              style: monoStyle,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.all(14),
                hintText: 'El fichero está vacío.',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditorBar extends StatelessWidget {
  const _EditorBar({required this.editor, required this.canWrite});

  final _LanguageEditor editor;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final dirty = editor.isDirty;
    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The path is the one thing here with no bound on its length --
          // `content/analysis/normed/definition/es.tex` is a real one -- so it
          // is the part that gives, and the counter is the part that goes. A bar
          // that overflows hides its own save button, which on a tablet is the
          // whole screen being useless.
          final narrow = constraints.maxWidth < 520;
          return Row(
            children: [
              Expanded(
                child: Text(
                  editor.file?.path ?? '',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  // Tail first: the filename matters more than `content/`.
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: didactaMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (!editor.exists)
                const _Tag('nuevo', colour: didactaAccentDark)
              else if (dirty)
                const _Tag('sin guardar', colour: didactaEx),
              if (!narrow) ...[
                const SizedBox(width: 10),
                Text(
                  '${editor.controller.text.length} car.',
                  style: const TextStyle(fontSize: 11, color: didactaMuted),
                ),
              ],
              const SizedBox(width: 10),
              if (dirty)
                TextButton(
                  onPressed: editor.saving ? null : () => _discard(context),
                  child: const Text('Descartar'),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                // Keyed because the commit dialog's confirm button carries the
                // same label -- rightly, "Guardar" is what both do -- and a test
                // that cannot tell them apart taps whichever comes first.
                key: const Key('editor-save'),
                icon: editor.saving
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 16),
                label: Text(editor.saving ? 'Guardando…' : 'Guardar'),
                // Disabled rather than hidden when there is nothing to save, so
                // the button does not move around as you type.
                onPressed: !canWrite || !dirty || editor.saving
                    ? null
                    : () => _save(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _discard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar los cambios?'),
        content: const Text(
          'Se perderá lo que has escrito desde que abriste el fichero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await editor.load();
  }

  Future<void> _save(BuildContext context) async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _CommitDialog(suggested: editor.suggestedMessage()),
    );
    if (message == null || !context.mounted) return;

    final problem = await editor.save(message);
    if (!context.mounted) return;

    if (problem == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Guardado como un commit.')));
      // The catalogue's translation status just changed, so the library and
      // the counts in the rail have to catch up.
      await sessionOf(context).reloadCatalogue();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problem),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }
}

/// Asks for the commit message.
///
/// Pre-filled and selected, so accepting the suggestion is one keystroke and
/// replacing it is one too. The point is that a message exists and means
/// something, not that someone types every time.
class _CommitDialog extends StatefulWidget {
  const _CommitDialog({required this.suggested});

  final String suggested;

  @override
  State<_CommitDialog> createState() => _CommitDialogState();
}

class _CommitDialogState extends State<_CommitDialog> {
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
    return AlertDialog(
      title: const Text('Guardar como commit'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cada cambio queda como un commit con autor y mensaje, así que '
              'se puede ver quién cambió qué y revertirlo.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
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
          key: const Key('commit-save'),
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

class _LanguageTabs extends StatelessWidget {
  const _LanguageTabs({
    required this.unit,
    required this.languages,
    required this.active,
    required this.dirty,
    required this.onSelect,
    required this.open,
    required this.onClose,
  });

  final Unit unit;
  final List<String> languages;
  final String active;
  final Set<String> dirty;
  final ValueChanged<String> onSelect;

  /// Los PDF abiertos, cada uno con su pestaña cerrable.
  final List<OpenPdf> open;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      // Scrolls rather than wraps: three languages plus the metadata fit on a
      // desktop and not on a phone, and a tab strip that reflows to two rows
      // moves the content down as you switch.
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final code in languages)
            _Tab(
              label: code,
              status: unit.statusIn(code),
              selected: code == active,
              dirty: dirty.contains(code),
              onTap: () => onSelect(code),
            ),
          const _Separator(),
          _Tab(
            label: 'unit.yaml',
            selected: active == metadataTab,
            dirty: false,
            onTap: () => onSelect(metadataTab),
          ),
          _Tab(
            label: 'compilar',
            icon: Icons.play_circle_outline,
            selected: active == previewTab,
            dirty: false,
            onTap: () => onSelect(previewTab),
          ),
          if (open.isNotEmpty) const _Separator(),
          for (final pdf in open)
            _Tab(
              label: pdf.label,
              icon: Icons.picture_as_pdf_outlined,
              selected: active == _pdfTab(pdf.key),
              dirty: false,
              onTap: () => onSelect(_pdfTab(pdf.key)),
              onClose: () => onClose(pdf.key),
            ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 9),
    child: SizedBox(width: 1, child: ColoredBox(color: didactaRule)),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.dirty,
    required this.onTap,
    this.status,
    this.icon,
    this.onClose,
  });

  final String label;

  /// Para una pestaña que no es un idioma: dice que hace algo, en lugar de
  /// que muestra algo.
  final IconData? icon;

  /// Puesto en una pestaña que se puede cerrar, que son las de PDF. Los
  /// idiomas y `unit.yaml` no se cierran: son la unidad.
  final VoidCallback? onClose;

  /// Null for the metadata tab, which has no translation state.
  final TranslationStatus? status;
  final bool selected;
  final bool dirty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = status;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? didactaAccentDark : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? didactaAccentDark : didactaMuted,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? didactaInk : didactaMuted,
              ),
            ),
            if (state != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: state.exists
                      ? statusColour(state)
                      : Colors.transparent,
                  border: Border.all(
                    color: state.exists ? statusColour(state) : didactaRule,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ],
            if (dirty) ...[
              const SizedBox(width: 4),
              // A dot rather than a word: it has to survive in a 38-pixel tab
              // and "sin guardar" is already spelled out in the editor bar.
              const Icon(Icons.circle, size: 6, color: didactaEx),
            ],
            if (onClose != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(9),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 12, color: didactaMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The reference panel: what this unit is, and what depends on it.
class _UnitPanel extends StatelessWidget {
  const _UnitPanel({required this.unit, required this.session});

  final Unit unit;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SectionLabel('Qué es'),
        _Row('tipo', kindName(unit.kind), colour: kindColour(unit.kind)),
        _Row('categoría', unit.category),
        _Row('tema', unit.topic),
        if (unit.difficulty != null) _Row('dificultad', unit.difficulty!),
        if (unit.durationMinutes != null)
          _Row('duración', '${unit.durationMinutes} min'),
        if (unit.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final tag in unit.tags)
                  Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),

        SectionLabel('Se usa en ${unit.usedBy.length} documento(s)'),
        if (unit.usedBy.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Note(
              'Ninguna composición la referencia. Después de una migración '
              'esto es material que llegó y no se está dando: o falta ponerlo '
              'en una asignatura, o se puede quitar.',
            ),
          )
        else
          for (final use in unit.usedBy)
            ListTile(
              leading: const Icon(Icons.description_outlined, size: 16),
              title: Text(
                use.document,
                style: const TextStyle(fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${session.courseById(use.course)?.title() ?? use.course} · '
                '${use.year}',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () => context.go(
                Routes.document(use.course, use.year, use.document),
              ),
            ),

        if (unit.objectives.isNotEmpty) ...[
          const SectionLabel('Objetivos'),
          for (final objective in unit.objectives)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('· ', style: TextStyle(color: didactaMuted)),
                  Expanded(
                    child: Text(
                      objective,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],

        if (unit.prerequisites.isNotEmpty) ...[
          const SectionLabel('Prerrequisitos'),
          for (final reference in unit.prerequisites)
            _Prerequisite(reference: reference, session: session),
        ],

        if (unit.warnings.isNotEmpty) ...[
          const SectionLabel('Avisos'),
          for (final warning in unit.warnings)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Note(warning, tone: didactaEx),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Prerequisite extends StatelessWidget {
  const _Prerequisite({required this.reference, required this.session});

  final String reference;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final unit = session.catalogue.unitByReference(reference);
    final missing = unit == null;
    return ListTile(
      leading: Icon(
        missing ? Icons.link_off : Icons.arrow_right,
        size: 16,
        color: missing ? didactaTeacher : didactaMuted,
      ),
      title: Text(
        missing ? '$reference (no existe)' : unit.title(session.language),
        style: TextStyle(
          fontSize: 12.5,
          color: missing ? didactaTeacher : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: missing ? null : () => context.go(Routes.unit(unit.path)),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.colour});

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: didactaMuted),
          ),
        ),
        if (colour != null) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5))),
      ],
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.12),
      border: Border.all(color: colour),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        color: colour,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({
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
    final unconfigured = content?.kind == ContentFailure.unconfigured;
    final forbidden =
        content?.kind == ContentFailure.forbidden ||
        content?.kind == ContentFailure.unauthenticated;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    forbidden ? Icons.lock_outline : Icons.error_outline,
                    color: didactaTeacher,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'No se ha podido abrir el fichero',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                  if (unconfigured || forbidden)
                    FilledButton.icon(
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('Ir a Ajustes'),
                      onPressed: () => context.go(Routes.settings()),
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar'),
                      onPressed: onRetry,
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

class _Missing extends StatelessWidget {
  const _Missing({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Unidad no encontrada',
          breadcrumbs: [('Biblioteca', Routes.library())],
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
                      path,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No está en el catálogo. Puede que se haya renombrado, '
                      'o que el catálogo esté desactualizado: se regenera con '
                      '`didacta index`.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => context.go(Routes.library()),
                      child: const Text('Ir a la biblioteca'),
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

/// A `LayoutBuilder` that carries the editor through to its builder.
///
/// Exists only so the editor is constructed during build and merely *used*
/// during layout. Inlining the construction into the builder is what made the
/// screen call `setState` during build.
class _WithEditor extends StatelessWidget {
  const _WithEditor({required this.editor, required this.builder});

  final Widget editor;
  final Widget Function(BuildContext, BoxConstraints, Widget) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => builder(context, constraints, editor),
  );
}
