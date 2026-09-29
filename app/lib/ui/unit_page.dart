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
import 'package:provider/provider.dart';

import '../data/compiler.dart';
import '../data/content_gateway.dart';
import '../data/diagnostics.dart';
import '../data/draft_store.dart';
import '../model/catalogue.dart';
import '../model/file_history.dart' show FileCommit;
import '../model/tex_indent.dart';
import '../router.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'commit_dialog.dart' show DiffBox;
import 'history_tab.dart';
import 'metadata_editor.dart';
import 'command_palette.dart';
import 'new_unit.dart' show duplicateUnitFrom, moveUnitFrom;
import 'pdf_tab.dart';
import 'problem.dart';
import 'unit_preview.dart';
import 'shell.dart';
import 'problem_editor.dart';
import 'tabs.dart';
import 'shortcuts.dart';
import 'tex_field.dart';
import 'tex_find_bar.dart';
import 'tex_highlight.dart';
import 'tex_toolbar.dart';
import 'tex_warnings.dart';
import 'course_admin_ui.dart';
import 'document_properties.dart' show languageNameOf;
import 'freezes.dart';
import 'reuse.dart';
import 'save_review.dart';
import 'save_shortcut.dart';
import 'info_menu.dart';
import 'theme.dart';
import 'tour.dart';
import 'translate_unit.dart';
import '../l10n/tr.dart';

class UnitPage extends StatefulWidget {
  const UnitPage({super.key, required this.unitPath, this.language, this.line});

  final String unitPath;

  /// El idioma en el que abrirla, si la dirección lo dice. Null es «el que
  /// tenga más sentido», que es lo que hace falta al entrar desde la
  /// biblioteca.
  final String? language;

  /// La línea donde dejar el cursor, desde 1: se llega aquí desde un error
  /// de compilación, y lo que se quiere ver es esa línea.
  final int? line;

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

/// La pestaña del historial: «¿qué le ha pasado a esto?».
///
/// La última de las fijas, y no por descarte: es la que menos se abre y la
/// única que no se usa para escribir. Las que se usan escribiendo --los
/// idiomas-- van primero, y compilar va justo detrás porque es lo que se hace
/// entre una edición y la siguiente.
const String historyTab = '\u0000history';

/// La pestaña de un PDF abierto. El prefijo la distingue de un idioma sin
/// necesitar un tipo aparte para el valor de la pestaña activa.
const String pdfTabPrefix = '\u0000pdf:';

String _pdfTab(String key) => '$pdfTabPrefix$key';

class _UnitPageState extends State<UnitPage> {
  /// One editor per language, created when its tab is first opened.
  final Map<String, _LanguageEditor> _editors = {};
  String? _active;

  /// La línea a la que llevar el cursor en cuanto el texto esté cargado.
  late int? _pendingLine = widget.line;

  @override
  void didUpdateWidget(UnitPage old) {
    super.didUpdateWidget(old);
    // La misma lección con otra dirección: otro error de la misma lista, que
    // puede ser de otro idioma y de otra línea.
    if (widget.language != null && widget.language != old.language) {
      _active = widget.language;
    }
    if (widget.line != old.line) _pendingLine = widget.line;
  }

  /// Si hay una línea pendiente y el texto ya está, lleva allí el cursor.
  void _goToPendingLine(List<String> languages) {
    final line = _pendingLine;
    final active = _active;
    if (line == null || active == null || !_isLanguage(active, languages)) {
      return;
    }
    final editor = _editors[active];
    if (editor == null || editor.loading) return;
    _pendingLine = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      editor.goTo(offsetOfLine(editor.controller.text, line));
    });
  }

  /// Las pestañas de PDF abiertas, en el orden en que se abrieron.
  ///
  /// Cada una puede tener varias versiones lado a lado: al compilar dos
  /// idiomas de un perfil se abren juntos, porque la comparación que importa
  /// es esa --si la traducción valenciana sigue cabiendo en la diapositiva no
  /// se sabe sin las dos delante-- y se separan de un botón.
  final List<PdfGroup> _open = [];

  /// Abre lo que acaba de compilar, agrupado por perfil.
  ///
  /// Automático y no a botones: acabas de pedir estas versiones, quererlas
  /// ver es la única razón por la que las pediste.
  void _openResults(List<CompileOutput> results) {
    final groups = groupResults(results);
    if (groups.isEmpty) return;

    setState(() {
      for (final group in groups) {
        final at = _open.indexWhere((other) => other.id == group.id);
        if (at >= 0) {
          _open[at] = group;
        } else {
          _open.add(group);
        }
        // Y se quitan las versiones sueltas que alguien había desacoplado de
        // este perfil: acaban de recompilarse dentro del grupo, y dejarlas
        // apuntaría a un PDF viejo.
        _open.removeWhere((other) => other.id.startsWith('${group.id}:'));
      }
      _active = _pdfTab(_open.first.id);
    });
    // La biblioteca enseña un botón de ojear en las unidades que tienen algo
    // compilado, y esta acaba de tenerlo.
    unawaited(context.read<Session>().refreshBuilt());
  }

  /// Abre un PDF en su pestaña, sin compilar nada.
  ///
  /// Es lo que se pulsa en «ya compiladas»: la versión está en disco y
  /// mirarla no tiene por qué costar una compilación.
  void _openPdf(OpenPdf pdf) {
    setState(() {
      final id = pdf.profile;
      final at = _open.indexWhere((group) => group.id == id);
      if (at >= 0) {
        final existing = _open[at].pane(pdf.language);
        _open[at] = existing == null
            ? PdfGroup(id: id, panes: [..._open[at].panes, pdf])
            : _open[at].replacing(pdf);
      } else {
        _open.add(PdfGroup(id: id, panes: [pdf]));
      }
      _active = _pdfTab(id);
    });
  }

  /// Vuelve a comprobar las fechas de lo que está abierto.
  ///
  /// Hace falta porque el estado cambia sin que esta pantalla haga nada:
  /// guardas el `.tex` en la pestaña de al lado y el PDF que tienes abierto
  /// pasa a ser de antes del cambio. Se pregunta al activar una pestaña y
  /// después de guardar, no por frame: son dos `stat` por panel, pero
  /// hacerlos sesenta veces por segundo sería absurdo.
  Future<void> _refreshStaleness(Session session) async {
    final compiler = session.compiler(
      repo: session.unitByPath(widget.unitPath)?.repo,
    );
    if (compiler == null || _open.isEmpty) return;

    final marks = <String, bool>{};
    for (final group in _open) {
      for (final pane in group.panes) {
        marks[pane.path] = await compiler.isStale(
          pdf: pane.path,
          unitPath: widget.unitPath,
        );
      }
    }
    if (!mounted) return;

    var changed = false;
    final next = <PdfGroup>[];
    for (final group in _open) {
      var updated = group;
      for (final pane in group.panes) {
        final stale = marks[pane.path] ?? pane.stale;
        if (stale != pane.stale) {
          updated = updated.replacing(pane.marked(stale: stale));
          changed = true;
        }
      }
      next.add(updated);
    }
    if (!changed) return;
    setState(() {
      _open
        ..clear()
        ..addAll(next);
    });
  }

  /// Vuelve a compilar un solo panel, en su sitio.
  ///
  /// La acción de después de editar: cambias el valenciano, lo recompilas y
  /// se actualiza esa columna sin tocar la de al lado --que es lo que permite
  /// ver el cambio-- y sin volver a la pantalla de compilar.
  Future<void> _recompilePane(
    Session session,
    String groupId,
    String language,
  ) async {
    final unit = session.unitByPath(widget.unitPath);
    final compiler = session.compiler(repo: unit?.repo);
    if (unit == null || compiler == null) return;

    final at = _open.indexWhere((group) => group.id == groupId);
    if (at < 0) return;
    final pane = _open[at].pane(language);
    if (pane == null) return;

    setState(() => _open[at] = _open[at].replacing(pane.working()));

    unawaited(showBuildConsole(context, session.buildConsole, autoClose: true));

    try {
      // Por la cola: si ya se compila otra cosa, espera su turno.
      final results = await session.runBuild('${pane.profile} · $language', (
        console,
      ) async {
        final made = await compiler.compile(
          unitPath: unit.path,
          profiles: [pane.profile],
          languages: [language],
          onOutput: console.add,
        );
        console.finish(ok: made.every((result) => result.ok));
        return made;
      });
      if (!mounted) return;
      // El índice se vuelve a buscar: entre el await y aquí alguien puede
      // haber cerrado la pestaña o separado el panel.
      final now = _open.indexWhere((group) => group.id == groupId);
      if (now < 0) return;
      final current = _open[now].pane(language);
      if (current == null) return;
      // Detenida: el panel vuelve a como estaba, sin error que decir.
      if (results == null) {
        setState(() => _open[now] = _open[now].replacing(current.idle()));
        return;
      }
      final result = results.firstOrNull;

      setState(() {
        _open[now] = _open[now].replacing(
          result != null && result.ok
              // Recién compilado ya no está viejo, que es lo que acaba de
              // arreglar el compilar.
              ? current.refreshed(pages: result.pages).marked(stale: false)
              : current.idle(),
        );
      });

      if (result != null && !result.ok) {
        _say(result.errors.isEmpty ? tr('No compiló.') : result.errors.first);
      }
    } catch (error) {
      if (!mounted) return;
      final now = _open.indexWhere((group) => group.id == groupId);
      if (now >= 0) {
        final current = _open[now].pane(language);
        if (current != null) {
          setState(() => _open[now] = _open[now].replacing(current.idle()));
        }
      }
      _say('$error');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  /// Saca una versión del grupo a su propia pestaña.
  void _detach(String groupId, String language) {
    setState(() {
      final at = _open.indexWhere((group) => group.id == groupId);
      if (at < 0) return;
      final group = _open[at];
      final pane = group.panes
          .where((other) => other.language == language)
          .firstOrNull;
      if (pane == null || group.isSingle) return;

      _open[at] = group.without(language);
      final id = '$groupId:$language';
      _open.insert(at + 1, PdfGroup(id: id, panes: [pane]));
      _active = _pdfTab(id);
    });
  }

  void _closePdf(String id) {
    setState(() {
      _open.removeWhere((group) => group.id == id);
      if (_active == _pdfTab(id)) {
        // Se vuelve a compilar y no al primer idioma: es de donde se venía.
        _active = previewTab;
      }
    });
  }

  /// El estado de compilar, creado al abrir la pestaña por primera vez.
  ///
  /// Vive aquí y no en el widget por lo mismo que los editores: al volver de
  /// mirar el PDF, lo compilado tiene que seguir estando.
  PreviewState? _preview;

  /// El último idioma que se estuvo mirando.
  ///
  /// Lo usa el historial para saber de qué fichero es: una unidad son tres o
  /// cuatro `.tex` y el historial es de uno. Sin esto, abrir el historial
  /// desde el valenciano enseñaría el del castellano.
  String? _lastLanguage;

  /// El historial, creado al abrir su pestaña por primera vez.
  ///
  /// Perezoso a propósito: `git log --follow` sobre un repositorio con años
  /// dentro cuesta, y cobrárselo a quien solo venía a editar el castellano
  /// sería cobrarlo casi siempre por nada.
  HistoryState? _history;

  /// La sesión en la que se apuntó lo que hay sin guardar, para borrarlo al
  /// cerrarse: en `dispose` ya no se puede buscar en el contexto.
  Session? _session;

  @override
  void dispose() {
    _session?.unsaved.mark(this, null);
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _original?.dispose();
    _history?.dispose();
    super.dispose();
  }

  /// Qué hay sin guardar en esta lección, dicho para el aviso de salir.
  String? _unsavedIn(Unit unit, Session session) {
    final dirty = [
      for (final editor in _editors.values)
        if (editor.isDirty) editor.language,
    ];
    if (dirty.isEmpty) return null;
    return tr('«{0}» en {1}', [unit.title(session.language), dirty.join(', ')]);
  }

  // El panel, los editores lado a lado y la interfaz avisan por los
  // ajustes, no por la sesión.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final session = watchSession(context);
    final unit = session.unitByPath(widget.unitPath);
    _session = session;

    if (unit == null) {
      return _Missing(path: widget.unitPath);
    }
    // Para «Abiertas hace poco» de la biblioteca.
    session.noteOpened(unit);
    session.unsaved.mark(
      this,
      _unsavedIn(unit, session),
      place: Routes.unit(unit.path),
    );

    final languages = languagesOfUnit(session, unit);
    // El de la dirección manda: se llega aquí desde «esto falta por
    // traducir», y abrir otra pestaña sería mandar a buscarla.
    _active ??= languages.contains(widget.language)
        ? widget.language
        : _preferredLanguage(unit, session, languages);

    // El ancho, aquí arriba: la cabecera tiene que decidir con el mismo
    // número que decide el cuerpo. El panel de la derecha sólo existe a
    // partir de mil píxeles, así que por debajo su botón ofrece algo que no
    // va a pasar --y desde que la ⓘ ocupa su sitio, además estrechaba el
    // título hasta hacerlo saltar de línea y desbordar la pantalla.
    _goToPendingLine(languages);
    return PaletteCommands(
      commands: (context) => _paletteCommands(context, unit, languages),
      child: LayoutBuilder(
        builder: (context, page) => _body(
          context,
          session,
          unit,
          languages,
          roomy: page.maxWidth >= 1000,
        ),
      ),
    );
  }

  /// Lo que ofrece la paleta de órdenes en esta lección: guardar lo que se
  /// está escribiendo, ir a otra pestaña y lo del menú ⓘ.
  List<PaletteCommand> _paletteCommands(
    BuildContext context,
    Unit unit,
    List<String> languages,
  ) {
    final session = sessionOf(context);
    final active = _active;
    final editor = active == null ? null : _editors[active];
    final writable = !session.isFrozen && session.canWriteIn(unit.repo);
    final canAdmin = writable && session.admin(repo: unit.repo) != null;
    void show(String tab) {
      if (mounted) setState(() => _active = tab);
    }

    return [
      if (editor != null && editor.isDirty && writable)
        PaletteCommand(
          title: tr(
            'Guardar «{0}» en '
            '{1}',
            [unit.title(session.language), _languageName(session, active!)],
          ),
          keywords: tr('guardar commit'),
          icon: Icons.save_outlined,
          shortcut: AppShortcut.save,
          run: () => _saveEditor(this.context, editor),
        ),
      for (final option in session.namedLanguages(languages))
        if (option.code != active)
          PaletteCommand(
            title: tr('Editar en {0}', [option.name]),
            detail: unit.title(session.language),
            keywords: tr('idioma pestaña {0}', [option.code]),
            icon: Icons.edit_outlined,
            run: () => show(option.code),
          ),
      if (active != previewTab)
        PaletteCommand(
          title: tr('Compilar y ver el PDF'),
          keywords: tr('vista previa pdf compilar'),
          icon: Icons.picture_as_pdf_outlined,
          run: () => show(previewTab),
        ),
      if (active != metadataTab)
        PaletteCommand(
          title: tr('Ver los metadatos'),
          keywords: tr('unit.yaml ficha etiquetas prerrequisitos'),
          icon: Icons.tune,
          run: () => show(metadataTab),
        ),
      if (active != historyTab)
        PaletteCommand(
          title: tr('Ver el historial'),
          keywords: tr('versiones cambios anteriores git'),
          icon: Icons.history,
          run: () => show(historyTab),
        ),
      if (active != null && _isLanguage(active, languages))
        PaletteCommand(
          title: session.splitEditors
              ? tr('Un idioma cada vez')
              : tr('Los idiomas lado a lado'),
          keywords: tr('dividir editores comparar'),
          icon: Icons.vertical_split_outlined,
          run: () => session.setSplitEditors(!session.splitEditors),
        ),
      if (writable)
        PaletteCommand(
          title: tr('Darla en otro tema…'),
          keywords: tr('usar añadir documento curso'),
          icon: Icons.playlist_add,
          run: () => _useUnit(this.context, session, unit),
        ),
      if (canAdmin) ...[
        PaletteCommand(
          title: tr('Duplicar esta lección…'),
          keywords: tr('copiar copia'),
          icon: Icons.copy_outlined,
          run: () => duplicateUnitFrom(this.context, session, unit),
        ),
        PaletteCommand(
          title: tr('Mover o renombrar esta lección…'),
          keywords: tr('carpeta nombre'),
          icon: Icons.drive_file_move_outline,
          run: () => moveUnitFrom(this.context, session, unit),
        ),
      ],
    ];
  }

  static String _languageName(Session session, String code) =>
      session.namedLanguages([code]).first.name;

  Widget _body(
    BuildContext context,
    Session session,
    Unit unit,
    List<String> languages, {
    required bool roomy,
  }) {
    return Column(
      children: [
        PageHeader(
          title: unit.title(session.language),
          // Con varios repositorios abiertos, la ruta sola no dice de cuál
          // es: dos pueden tener la misma.
          subtitle: session.colourOf(unit.repo) != null
              ? '${unit.repo} · ${unit.path}'
              : unit.path,
          breadcrumbs: [(tr('Biblioteca'), Routes.library())],
          actions: [
            // Solo cuando la pestaña activa es un idioma: partir en dos no
            // significa nada en `unit.yaml`, en compilar ni en un PDF.
            if (_isLanguage(_active!, languages))
              _SplitToggle(
                on: session.splitEditors,
                onChanged: (value) => sessionOf(context).setSplitEditors(value),
              ),
            // Dónde está y qué hay guardado de ella. Aquí y no sólo en el
            // panel: el panel se puede tener cerrado, y las congelaciones
            // estaban a dos pantallas de donde se preguntan.
            InfoMenu(
              session: session,
              places: [
                for (final use in unit.usedBy)
                  InfoPlace(
                    course: use.course,
                    year: use.year,
                    document: use.document,
                  ),
              ],
              placesLabel: tr('Se da en'),
              placesEmpty: tr(
                'Ninguna composición la referencia. Después de una '
                'migración esto es material que llegó y no se está dando.',
              ),
              // En Completa. La franja que sale al editar una lección que se
              // da en varios cursos lo sigue ofreciendo a todos: ahí es parte
              // de no romper la asignatura de otro, y eso no es opcional.
              onSplit:
                  session.completeInterface &&
                      !session.isFrozen &&
                      unit.usedBy.length > 1 &&
                      session.canWriteIn(unit.repo)
                  ? () => _splitUnit(context, session, unit)
                  : null,
              onUse: !session.isFrozen && session.canWriteIn(unit.repo)
                  ? () => _useUnit(context, session, unit)
                  : null,
              onDuplicate:
                  !session.isFrozen &&
                      session.canWriteIn(unit.repo) &&
                      session.admin(repo: unit.repo) != null
                  ? () => duplicateUnitFrom(context, session, unit)
                  : null,
              // Para todos: reescribe las composiciones de otros cursos, y
              // por eso el diálogo los nombra antes de confirmar.
              onMove:
                  !session.isFrozen &&
                      session.canWriteIn(unit.repo) &&
                      session.admin(repo: unit.repo) != null
                  ? () => moveUnitFrom(context, session, unit)
                  : null,
              onRestore: session.isFrozen
                  ? () => _restoreUnit(context, session, unit)
                  : null,
            ),
            if (roomy)
              IconButton(
                tooltip: session.unitPanelVisible
                    ? tr('Ocultar el panel de la derecha')
                    : tr('Mostrar el panel de la derecha'),
                isSelected: session.unitPanelVisible,
                icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                selectedIcon: const Icon(Icons.view_sidebar, size: 18),
                onPressed: () => sessionOf(
                  context,
                ).setUnitPanelVisible(!session.unitPanelVisible),
              ),
            if (session.completeInterface)
              IconButton(
                tooltip: tr('Copiar la referencia para una composición'),
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: unit.reference_)),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr('Copiado: {0}', [unit.reference_])),
                    ),
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
            onSelect: (code) {
              setState(() {
                if (_isLanguage(code, languages)) _lastLanguage = code;
                _active = code;
              });
              // Al volver a un PDF o a compilar, se vuelven a mirar las
              // fechas: puede haberse guardado un `.tex` mientras tanto.
              if (code == previewTab || code.startsWith(pdfTabPrefix)) {
                unawaited(_refreshStaleness(session));
                final preview = _preview;
                if (code == previewTab && preview != null) {
                  unawaited(preview.refreshExisting());
                }
              }
            },
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
              if (constraints.maxWidth >= 1000 && session.unitPanelVisible) {
                return Row(
                  children: [
                    Expanded(child: editor),
                    const VerticalDivider(width: 1),
                    TourTarget(
                      id: 'unit-used',
                      child: SizedBox(
                        width: 340,
                        child: _UnitPanel(unit: unit, session: session),
                      ),
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
      final id = active.substring(pdfTabPrefix.length);
      final group = _open.where((other) => other.id == id).firstOrNull;
      // Puede no estar si se cerró justo antes de este build.
      if (group != null) {
        return PdfTabView(
          key: ValueKey('pdf-$id'),
          group: group,
          onOpenExternally: (path) => _external(session, path, reveal: false),
          onReveal: (path) => _external(session, path, reveal: true),
          onRecompile: () => setState(() => _active = previewTab),
          onRecompilePane: (language) => _recompilePane(session, id, language),
          onDetach: (language) => _detach(id, language),
        );
      }
    }
    final languages = languagesOfUnit(session, unit);
    if (session.splitEditors && _isLanguage(active, languages)) {
      return _SplitEditors(
        unit: unit,
        session: session,
        languages: languages,
        active: active,
        // Con varios a la vez, el tour señala el de la pestaña elegida: la
        // marca es una clave global y no puede estar en dos.
        editorFor: (language) => _editorFor(
          unit,
          language,
          session,
          tour: language == active,
          // Revisando una traducción, el original se lee y no se toca: una
          // corrección que cae en el original por error cambia lo que dicen
          // todas las traducciones. Se pulsa su cabecera para editarlo.
          locked: language == unit.reference && active != unit.reference,
        ),
        scrollOf: (language) => _editors[language]?.scroll,
        onSelect: (language) => setState(() => _active = language),
      );
    }

    return switch (active) {
      // Keyed by path so moving to another unit rebuilds it rather than
      // showing the previous unit's file while it loads.
      metadataTab => MetadataEditor(
        key: ValueKey('metadata-${unit.path}'),
        unit: unit,
        session: session,
      ),
      // La ruta del fichero que se está mirando, no la de la unidad: el
      // historial contesta «¿qué le ha pasado a **esto**?», y en una unidad
      // eso es el `.tex` del idioma abierto.
      historyTab => HistoryTab(
        state: _historyFor(unit, session),
        onRecover: session.canWriteIn(unit.repo)
            ? (text, commit) => _recover(unit, session, text, commit)
            : null,
      ),
      previewTab => UnitPreview(
        onOpen: _openPdf,
        state: _preview ??= PreviewState(
          target: UnitTarget(unit),
          session: session,
          onChanged: () {
            if (mounted) setState(() {});
          },
          onCompiled: _openResults,
        ),
        onExternal: (path, {required bool reveal}) =>
            _external(session, path, reveal: reveal),
      ),
      final language => _editorFor(unit, language, session),
    };
  }

  /// El historial del fichero que se está mirando, creándolo si hace falta.
  ///
  /// Se rehace cuando cambia el fichero --se estaba en el castellano y se pasa
  /// al valenciano-- y solo entonces: volver a la pestaña después de mirar el
  /// PDF no puede costar otro `git log`.
  HistoryState _historyFor(Unit unit, Session session) {
    final path = _historyPathFor(unit, session);
    final current = _history;
    if (current != null && current.path == path) return current;
    current?.dispose();
    return _history = HistoryState(
      session: session,
      repo: unit.repo,
      path: path,
    );
  }

  /// Lleva una versión del historial al editor de su idioma, sin guardar.
  ///
  /// Como cualquier otra edición: el editor queda con cambios, Guardar pide
  /// el mensaje y enseña el diff, y Descartar vuelve a lo de ahora.
  Future<void> _recover(
    Unit unit,
    Session session,
    String text,
    FileCommit commit,
  ) async {
    final language = _historyLanguageFor(unit, session);
    _editorFor(unit, language, session);
    final editor = _editors[language];
    if (editor == null) return;
    await editor.ready;
    if (!mounted) return;
    editor.replaceText(text);
    setState(() {
      _lastLanguage = language;
      _active = language;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('recovered-notice'),
        duration: const Duration(seconds: 8),
        content: Text(
          tr(
            'La versión del {0} está en el editor, sin '
            'guardar. Guardar la deja como la de ahora; Descartar vuelve atrás.',
            [exactDay(commit.when)],
          ),
        ),
      ),
    );
  }

  /// El idioma del fichero cuyo historial se enseña.
  String _historyLanguageFor(Unit unit, Session session) {
    final languages = languagesOfUnit(session, unit);
    final last = _lastLanguage;
    return last != null && languages.contains(last) ? last : unit.reference;
  }

  /// De qué fichero se enseña el historial.
  ///
  /// El del idioma que estaba abierto, y el de referencia si se llegó aquí
  /// desde otra pestaña. Una unidad son tres o cuatro ficheros y el historial
  /// es de uno: enseñar el de `es.tex` estando en el valenciano sería
  /// contestar a otra pregunta.
  String _historyPathFor(Unit unit, Session session) =>
      unit.fileFor(_historyLanguageFor(unit, session));

  Future<void> _external(
    Session session,
    String path, {
    required bool reveal,
  }) async {
    try {
      final compiler = session.compiler(
        repo: session.unitByPath(widget.unitPath)?.repo,
      );
      if (compiler == null) return;
      if (reveal) {
        await compiler.reveal(path);
      } else {
        await compiler.open(path);
      }
    } catch (error) {
      if (!mounted) return;
      showProblem(context, error);
    }
  }

  /// Si una pestaña es un idioma, y no `unit.yaml`, compilar ni un PDF.
  static bool _isLanguage(String tab, List<String> languages) =>
      languages.contains(tab);

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

  /// El original leído aparte, solo para comparar las fórmulas de una
  /// traducción cuando su pestaña no está abierta. No es un editor: no tiene
  /// pestaña, ni cambios sin guardar, ni borrador.
  TextEditingController? _original;
  String? _originalPath;

  TextEditingController _originalOf(Unit unit, Session session) {
    final path = unit.fileFor(unit.reference);
    if (_original != null && _originalPath == path) return _original!;
    _original?.dispose();
    final controller = TextEditingController();
    _original = controller;
    _originalPath = path;
    unawaited(() async {
      try {
        final file = await session.gatewayFor(unit.repo).read(path);
        if (identical(_original, controller)) controller.text = file.text;
      } catch (caught, trace) {
        Diagnostics.instance.note('unit_page._originalOf', caught, trace);
        // Sin original no hay con qué comparar: el panel no dice nada.
      }
    }());
    return controller;
  }

  Widget _editorFor(
    Unit unit,
    String language,
    Session session, {
    bool tour = true,
    bool locked = false,
  }) {
    final editor = _editors.putIfAbsent(
      language,
      () => _LanguageEditor(
        unit: unit,
        language: language,
        session: session,
        // Un guardado sigue su curso aunque se cierre la pantalla, y avisa
        // al terminar: si ya no está, no hay nada que repintar.
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
    // La del catálogo de ahora, no la de cuando se creó el editor: el editor
    // sobrevive a un cambio de pestaña y a una recarga, y lo que la unidad
    // dice de sí misma --su estado, su título-- cambia por debajo.
    editor.unit = unit;
    // Una traducción se compara con su original: las fórmulas tienen que
    // ser las mismas. El del original es un editor como los demás --si ya
    // está abierto, el mismo, con lo que se esté escribiendo en él--.
    editor.original =
        language == unit.reference || !unit.statusIn(unit.reference).exists
        ? null
        : (_editors[unit.reference]?.controller ?? _originalOf(unit, session));
    return _EditorView(
      editor: editor,
      unit: unit,
      language: language,
      tour: tour,
      locked: locked,
    );
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
    scheduleMicrotask(() async {
      await load();
      if (!_firstLoad.isCompleted) _firstLoad.complete();
    });
  }

  final Completer<void> _firstLoad = Completer<void>();

  /// Cuando el fichero ya se ha leído la primera vez. Quien quiera poner algo
  /// en el editor --una versión recuperada del historial-- espera a esto:
  /// antes, la lectura lo pisaría.
  Future<void> get ready => _firstLoad.future;

  /// La unidad, **refrescada en cada `build`** de la página.
  ///
  /// No `final`: el editor se cachea por idioma para no perder lo que hay
  /// escrito al cambiar de pestaña, así que sin esto se queda con la unidad
  /// de cuando se creó. Y el estado de una unidad cambia --se aprueba una
  /// traducción, se vuelve a indexar-- de modo que el botón de estado seguía
  /// diciendo «borrador» después de marcarla como revisada, mientras el punto
  /// de la pestaña, que lee del catálogo, ya decía otra cosa.
  Unit unit;

  final String language;
  final Session session;
  final VoidCallback onChanged;

  /// El texto del original, si este es una traducción: con él se comparan
  /// las fórmulas. El del editor del original si está abierto --con lo que
  /// se esté escribiendo en él--, o una lectura aparte si no.
  TextEditingController? original;

  /// Pinta el LaTeX que contiene: órdenes, comentarios, matemáticas y los
  /// delimitadores de cada entorno, del color de ese entorno. Un fichero
  /// suelto calcula su propio árbol, así que aquí también sale en rojo lo que
  /// se quedó sin cerrar.
  final TexEditingController controller = TexEditingController();

  /// El desplazamiento del texto, para que el modo lado a lado lleve a la
  /// vez el original y la traducción.
  final ScrollController scroll = ScrollController();

  /// El foco del área de texto. Aquí y no en el widget por lo mismo que el
  /// controlador: la barra devuelve el cursor al editor después de envolver,
  /// y un foco que se recrea en cada `build` lo devuelve a ninguna parte.
  final FocusNode focusNode = FocusNode();

  ContentFile? file;
  String _loadedText = '';
  bool loading = true;
  Object? error;
  bool saving = false;

  /// Set when the file changed underneath. Cleared only by reloading, never
  /// by trying again.
  bool conflicted = false;

  bool get isDirty => !loading && controller.text != _loadedText;

  /// Si el problema se está editando por campos en lugar de como texto.
  ///
  /// Empieza en campos: es la forma de escribir un problema, y el texto
  /// sigue a un botón de distancia para cuando hace falta ver el LaTeX
  /// entero. Vive aquí y no en la pantalla para que cambiar de idioma y
  /// volver no reinicie la elección.
  bool asFields = true;

  void setAsFields(bool value) {
    asFields = value;
    onChanged();
  }

  /// Si la barra de buscar está abierta, y lo que busca al abrirse.
  bool finding = false;
  String findInitial = '';
  final GlobalKey<TexFindBarState> findBar = GlobalKey<TexFindBarState>();

  /// ⌘F: abre la barra de buscar, o le devuelve el foco si ya estaba.
  ///
  /// Con lo seleccionado como búsqueda, si es un trozo de una línea: es lo
  /// que se quiere encontrar otra vez casi siempre. Desde los campos de un
  /// problema, pasando al texto, que es donde se busca.
  void openFind() {
    if (finding) {
      findBar.currentState?.focusQuery();
      return;
    }
    final selection = controller.selection;
    final picked = selection.isValid && !selection.isCollapsed
        ? selection.textInside(controller.text)
        : '';
    findInitial = picked.contains('\n') ? '' : picked;
    finding = true;
    if (asFields) {
      setAsFields(false);
    } else {
      onChanged();
    }
  }

  void closeFind() {
    finding = false;
    onChanged();
  }

  /// Lleva el cursor a [offset] del fichero, con el foco en el texto.
  ///
  /// Desde los campos de un problema, pasando antes al texto: un aviso
  /// nombra una línea del fichero, y en los campos no hay líneas.
  void goTo(int offset) {
    void place() {
      controller.selection = TextSelection.collapsed(
        offset: offset.clamp(0, controller.text.length),
      );
      focusNode.requestFocus();
    }

    if (!asFields) return place();
    setAsFields(false);
    WidgetsBinding.instance.addPostFrameCallback((_) => place());
  }

  /// Sustituye el fichero entero, desde los campos.
  ///
  /// Por el mismo controlador que el editor de texto, y no por un camino
  /// aparte: así guardar, el diff y el aviso de conflicto siguen siendo
  /// exactamente los mismos, que es lo que hace que esto sea una vista y no
  /// un segundo editor.
  void replaceText(String text) {
    if (controller.text == text) return;
    controller.text = text;
  }

  bool get exists => unit.statusIn(language).exists;

  /// Lo que quedó escrito y sin guardar la última vez, si Didacta se cerró
  /// antes de guardarlo. Se ofrece al abrir; ver `data/draft_store.dart`.
  Draft? recovered;

  String get _draftKey => '${unit.repo}|${unit.fileFor(language)}';

  Timer? _draftTimer;

  void _onEdit() {
    onChanged();
    // Con un respiro: copiarlo a cada tecla es escribir en disco a cada
    // tecla, y lo que importa es no perder más de un segundo de trabajo.
    if (loading) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), _keepDraft);
  }

  Future<void> _keepDraft() async {
    if (controller.text == _loadedText) {
      await session.drafts.delete(_draftKey);
    } else {
      await session.drafts.write(
        _draftKey,
        Draft(
          text: controller.text,
          base: file?.sha ?? '',
          when: DateTime.now(),
        ),
      );
    }
  }

  /// Vuelve a poner lo recuperado en el editor, como cambio sin guardar.
  void restoreDraft() {
    final draft = recovered;
    if (draft == null) return;
    recovered = null;
    controller.text = draft.text;
  }

  /// Tira el borrador: ni se recupera ni se vuelve a ofrecer.
  Future<void> forgetDraft() async {
    _draftTimer?.cancel();
    recovered = null;
    await session.drafts.delete(_draftKey);
    onChanged();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    conflicted = false;
    onChanged();
    try {
      if (!exists) {
        // Vacío, y no con el original debajo.
        //
        // Empezaba copiando la versión de referencia para que quien traduce
        // tuviera el texto delante, y el efecto era el contrario del
        // buscado: abrir la pestaña de valenciano y ver castellano se lee
        // como «ya está traducida», y un descuido al guardar deja el
        // castellano archivado como si fuera la traducción. Ahora la
        // pestaña está vacía y lo dice en rojo.
        //
        // Tener el original delante sigue siendo lo correcto para traducir,
        // pero eso es lo que hace la vista lado a lado, donde el original se
        // ve y **no se puede guardar por error** como si fuera otro idioma.
        file = ContentFile(path: unit.fileFor(language), text: '', sha: '');
        _loadedText = '';
        controller.text = '';
      } else {
        final loaded = await session
            .gatewayFor(unit.repo)
            .read(unit.fileFor(language));
        file = loaded;
        _loadedText = loaded.text;
        controller.text = loaded.text;
      }
      // Si quedó algo sin guardar de la última vez, se ofrece; si es lo
      // mismo que hay en el fichero, sobra.
      final draft = await session.drafts.read(_draftKey);
      if (draft != null && draft.text != _loadedText) {
        recovered = draft;
      } else if (draft != null) {
        await session.drafts.delete(_draftKey);
      }
    } catch (thrown) {
      error = thrown;
    } finally {
      loading = false;
      onChanged();
    }
  }

  /// Ordena la sangría de lo que hay escrito, ahora.
  ///
  /// Devuelve si ha cambiado algo, para poder decir «ya estaba ordenado» en
  /// lugar de dejar un botón que al pulsarlo no hace nada visible.
  ///
  /// Deja el cambio **sin guardar**. Es lo mismo que hará el guardado, hecho
  /// antes para poder mirarlo y con «Descartar» al lado: reescribir el
  /// fichero de alguien y hacer el commit en el mismo clic no deja sitio para
  /// mirar qué se ha reescrito.
  Future<bool> tidyNow() async {
    final tidy = await session.tidyLatex(controller.text);
    if (tidy == controller.text) return false;
    controller.text = tidy;
    return true;
  }

  /// The message suggested in the save dialog.
  ///
  /// Says what actually changed, because a log full of "edit file" is a log
  /// nobody reads.
  String suggestedMessage() {
    final title = unit.title(language);
    if (!exists) return tr('Añadir la versión {0} de «{1}»', [language, title]);
    return tr('Editar la versión {0} de «{1}»', [language, title]);
  }

  Future<String?> save(String message) async {
    saving = true;
    conflicted = false;
    onChanged();
    try {
      // Se sangra al guardar y no al escribir: reindentar bajo los dedos de
      // alguien que está en mitad de una línea le mueve el cursor y le borra
      // el deshacer. Al guardar el fichero ya está cerrado como idea, y lo
      // que se ve después es lo que se ha guardado.
      final text = unit.indentsIn(language)
          ? await session.tidyLatex(controller.text)
          : controller.text;
      final sha = await session
          .gatewayFor(unit.repo)
          .save(
            path: unit.fileFor(language),
            text: text,
            sha: file?.sha ?? '',
            message: message,
          );
      // Lo guardado, en pantalla. Dejar el editor con el texto de antes
      // mientras el disco tiene otro es la manera de que el siguiente
      // guardado deshaga la sangría del anterior.
      if (controller.text != text) controller.text = text;
      _loadedText = text;
      file = ContentFile(path: unit.fileFor(language), text: text, sha: sha);
      // Guardado: el borrador ya no protege nada.
      _draftTimer?.cancel();
      recovered = null;
      await session.drafts.delete(_draftKey);
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

  /// Si esta versión se puede dar por revisada desde aquí: una traducción
  /// que existe, que nadie ha revisado todavía o que se ha quedado atrás.
  bool get canApprove {
    if (language == unit.reference || !exists) return false;
    final status = unit.statusIn(language);
    return status == TranslationStatus.draft ||
        status == TranslationStatus.translated ||
        status == TranslationStatus.outdated;
  }

  /// La da por revisada, con lo que se haya corregido, en un solo cambio.
  /// Ver [Session.approveTranslation]. Null si fue bien; si no, por qué.
  Future<String?> approve() async {
    saving = true;
    conflicted = false;
    onChanged();
    try {
      final text = !isDirty
          ? null
          : unit.indentsIn(language)
          ? await session.tidyLatex(controller.text)
          : controller.text;
      final written = await session.approveTranslation(
        unit: unit,
        language: language,
        text: text,
        sha: file?.sha ?? '',
      );
      if (text != null) {
        if (controller.text != text) controller.text = text;
        _loadedText = text;
        if (written != null) file = written;
        _draftTimer?.cancel();
        recovered = null;
        await session.drafts.delete(_draftKey);
      }
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

  /// Al cerrar la pantalla, el borrador se va con ella: salir es haber
  /// decidido --con el aviso delante-- no guardarlo. Solo sobrevive a lo que
  /// no pasa por aquí, que es justo cerrarse de golpe.
  void dispose() {
    _draftTimer?.cancel();
    unawaited(session.drafts.delete(_draftKey));
    controller.removeListener(_onEdit);
    controller.dispose();
    focusNode.dispose();
    scroll.dispose();
  }
}

class _EditorView extends StatelessWidget {
  const _EditorView({
    required this.editor,
    required this.unit,
    required this.language,
    this.tour = true,
    this.locked = false,
  });

  final _LanguageEditor editor;
  final Unit unit;
  final String language;

  /// Si su barra es la que señala el tour.
  final bool tour;

  /// De solo lectura aunque se pueda escribir: el original, mientras se
  /// revisa una traducción al lado.
  final bool locked;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
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

    final canWrite = watchSession(context).canWriteIn(unit.repo) && !locked;
    // Los tres campos, para los problemas. Lo decide el tipo de la unidad y
    // no el árbol donde vive: una teoría o un ejemplo dentro de una práctica
    // se escriben de corrido. Y el fichero manda por encima de eso: si no
    // tiene la forma de un problema --porque son tres en un fichero-- el
    // editor de texto es lo que hay, y la pantalla lo dice en lugar de
    // esconder el botón.
    final structured = unit.editsAsProblem;

    return SaveShortcut(
      onSave: canWrite && editor.isDirty && !editor.saving
          ? () => _saveEditor(context, editor)
          : null,
      // Buscar en el texto, aquí: en la biblioteca ⌘F busca en la biblioteca,
      // y dentro de una lección lo que se busca está en la lección.
      child: CallbackShortcuts(
        bindings: {
          activatorFor(AppShortcut.search): editor.openFind,
          findNextActivator(): () => editor.findBar.currentState?.go(1),
          findNextActivator(back: true): () =>
              editor.findBar.currentState?.go(-1),
        },
        child: _editorColumn(context, canWrite, structured),
      ),
    );
  }

  Widget _editorColumn(BuildContext context, bool canWrite, bool structured) {
    return Column(
      children: [
        TourTarget.first(
          id: 'unit-editor',
          when: tour,
          child: _EditorBar(
            editor: editor,
            canWrite: canWrite,
            // El interruptor sale **siempre**, también en una lección que no
            // tiene campos: decir «estás viendo el LaTeX entero» es lo que
            // contesta «¿dónde veo el LaTeX entero?», y un control que aparece y
            // desaparece según el tipo de unidad es una pantalla que nadie sabe
            // describir. En las que no son problemas, «Campos» está apagado y
            // dice por qué.
            fields: structured && editor.asFields,
            hasFields: structured,
            onFields: structured ? (value) => editor.setAsFields(value) : null,
          ),
        ),
        // Encima del texto y sin forma de cerrarla: el «Se da en» del panel
        // se puede tener oculto, y lo que se guarda aquí cambia en todos esos
        // cursos a la vez. Solo en el editor activo, que con dos lado a lado
        // la franja repetida no dice nada más.
        if (tour && canWrite && !watchSession(context).isFrozen)
          SharedLessonStrip(
            unit: unit,
            onSplit: () => _splitUnit(context, sessionOf(context), editor.unit),
          ),
        // Desactualizada: el original ha cambiado desde que se revisó. Lo que
        // hace falta para ponerla al día es saber qué, y está a un clic.
        if (language != unit.reference &&
            unit.statusIn(language) == TranslationStatus.outdated)
          _OutdatedStrip(unit: unit, language: language),
        if (editor.recovered case final draft?)
          _RecoveredDraft(
            draft: draft,
            changedSince: draft.base != (editor.file?.sha ?? ''),
            onRestore: editor.restoreDraft,
            onForget: editor.forgetDraft,
          ),
        if (editor.conflicted)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Note(
              tr(
                'El fichero ha cambiado en el repositorio desde que lo abriste. '
                'Vuelve a cargarlo para no sobrescribir el trabajo de otra '
                'persona; tu texto sigue aquí mientras decides.',
              ),
              tone: context.palette.teacher,
            ),
          )
        else if (!editor.exists)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Note(
                  tr(
                    'No existe la versión en {0} de esta unidad. Lo que '
                    'se escriba aquí la crea, y hasta entonces ningún documento '
                    'que la use se puede compilar en {1}.'
                    '{2}',
                    [
                      language,
                      language,
                      canWrite
                          ? tr(
                              '\n\nPara traducir con el original delante, '
                              'marca «lado a lado» arriba: así se ve al lado y '
                              'no se puede guardar por error como si fuera '
                              'esta.',
                            )
                          : '',
                    ],
                  ),
                  tone: context.palette.teacher,
                ),
                // Traducir esta pestaña, desde esta pestaña. Aquí y no solo
                // en la lista de traducciones porque es donde se descubre
                // que falta: se entra a mirar cómo quedó en valenciano y la
                // página está vacía.
                if (canWrite &&
                    editor.unit.statusIn(editor.unit.reference).exists)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      key: const Key('translate-this-language'),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                      label: Text(
                        tr('Traducirla a {0} con la máquina', [language]),
                      ),
                      onPressed: () =>
                          _translateHere(context, editor, language),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: structured && editor.asFields
              ? ColoredBox(
                  color: context.palette.card,
                  child: ProblemFields(
                    text: editor.controller.text,
                    readOnly: !canWrite,
                    onChanged: editor.replaceText,
                    repo: editor.unit.repo,
                  ),
                )
              : Column(
                  children: [
                    // Solo sobre el texto: en los campos de un problema el
                    // entorno ya lo pone el campo, y un botón «Respuesta»
                    // encima del campo de la respuesta no significa nada.
                    TexToolbar(
                      controller: editor.controller,
                      enabled: canWrite,
                      focusNode: editor.focusNode,
                      repo: editor.unit.repo,
                      // Solo cuando este idioma se sangra: ofrecerlo en uno
                      // que está marcado para dejar quieto sería ofrecer
                      // justo lo que se ha dicho que no se haga.
                      onTidy: editor.unit.indentsIn(editor.language)
                          ? () => _tidy(context, editor)
                          : null,
                    ),
                    if (editor.finding)
                      TexFindBar(
                        key: editor.findBar,
                        controller: editor.controller,
                        editorFocus: editor.focusNode,
                        onClose: editor.closeFind,
                        // Reemplazar, en la interfaz completa: buscar es de
                        // todos, reescribir de golpe no.
                        readOnly:
                            !canWrite ||
                            !watchSession(context).completeInterface,
                        initial: editor.findInitial,
                      ),
                    Expanded(
                      child: Container(
                        color: context.palette.card,
                        // La misma caja que en el tema: el LaTeX coloreado y
                        // una columna por cada entorno que envuelve a la
                        // línea. Una lección suelta calcula su propio árbol,
                        // así que las columnas salen sin que nadie le pase
                        // nada.
                        child: TexField(
                          controller: editor.controller,
                          focusNode: editor.focusNode,
                          scrollController: editor.scroll,
                          readOnly: !canWrite,
                          hintText: tr('El fichero está vacío.'),
                          padding: const EdgeInsets.all(14),
                          // Con números: aquí se edita el fichero entero, y
                          // es la única pantalla donde «la línea 37» quiere
                          // decir algo --lo que dice un error de LaTeX, lo
                          // que se señala hablando con alguien--.
                          lineNumbers: true,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        // Debajo del texto y en los dos modos: lo que no va a compilar no
        // depende de cómo se esté mirando el fichero.
        if (canWrite)
          TexWarnings(
            controller: editor.controller,
            language: editor.language,
            onGo: editor.goTo,
            original: editor.original,
          ),
      ],
    );
  }
}

/// Campos o texto.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.fields,
    required this.hasFields,
    required this.compact,
    required this.onChanged,
  });

  final bool fields;
  final bool hasFields;
  final bool compact;
  final ValueChanged<bool>? onChanged;

  static String get _noFields => tr(
    'Solo un problema tiene enunciado, resultado y solución; '
    'lo demás se escribe de corrido.',
  );

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        key: const Key('problem-view-toggle'),
        tooltip: hasFields
            ? (fields ? tr('Ver el LaTeX') : tr('Ver los campos'))
            : _noFields,
        visualDensity: VisualDensity.compact,
        icon: Icon(fields ? Icons.code : Icons.view_agenda_outlined, size: 16),
        onPressed: onChanged == null ? null : () => onChanged!(!fields),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border.all(color: context.palette.rule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: hasFields
                ? tr('Enunciado, resultado y solución')
                : _noFields,
            child: _ViewOption(
              key: const Key('problem-view-fields'),
              label: tr('Campos'),
              icon: Icons.view_agenda_outlined,
              selected: fields,
              enabled: hasFields,
              onTap: onChanged == null ? null : () => onChanged!(true),
            ),
          ),
          _ViewOption(
            key: const Key('problem-view-text'),
            label: 'LaTeX',
            icon: Icons.code,
            selected: !fields,
            onTap: onChanged == null ? null : () => onChanged!(false),
          ),
        ],
      ),
    );
  }
}

class _ViewOption extends StatelessWidget {
  const _ViewOption({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool selected;

  /// Apagado y no escondido: enseñar la opción que no se puede elegir es lo
  /// que contesta «¿por qué esta lección no tiene campos?».
  final bool enabled;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Hoverable(
    onTap: enabled ? onTap : null,
    builder: (context, hovering) => AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: selected
            ? context.palette.card
            : (hovering ? context.palette.hover : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _colour(context.palette)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: _colour(context.palette),
            ),
          ),
        ],
      ),
    ),
  );
}

extension on _ViewOption {
  Color _colour(DidactaPalette palette) => !enabled
      ? palette.muted.withValues(alpha: 0.45)
      : (selected ? palette.accentDark : palette.muted);
}

/// El estado del idioma que se está editando, y cómo cambiarlo.
///
/// Dentro de cada idioma y no en los metadatos de la unidad, aunque ahí
/// también esté: el estado es de la traducción que tienes delante, y tener
/// que abrir otra pantalla para decir «esto ya está revisado» es el paso que
/// hace que nadie lo diga nunca.
///
/// Los calculados --«no existe», «desactualizada»-- salen apagados: los
/// decide el motor, el primero de que el fichero esté y el segundo
/// comparando con el original, y declararlos garantizaría que se queden
/// obsoletos en cuanto alguien toque el original.
class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.editor,
    required this.canWrite,
    this.compact = false,
  });

  final _LanguageEditor editor;
  final bool canWrite;

  /// Sin la palabra: solo el punto de color y la flecha.
  final bool compact;

  static Map<String, String> get _names => declarableStatusNames;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final status = editor.unit.statusIn(editor.language);
    // En la interfaz esencial, dos estados: pendiente de revisar y revisada.
    // Ver [declarableStatusesFor].
    final options = declarableStatusesFor(
      complete: editor.session.completeInterface,
      reference: editor.language == editor.unit.reference,
    );
    final settable = canWrite && !status.computed && options.isNotEmpty;

    final tag = compact
        ? Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: context.palette.status(status),
              shape: BoxShape.circle,
            ),
          )
        : _Tag(statusName(status), colour: context.palette.status(status));
    if (!settable) {
      return Tooltip(
        message: !canWrite
            ? tr('Solo lectura · {0}', [statusName(status)])
            : status.computed
            ? tr('Lo calcula el motor: {0}', [statusName(status)])
            : tr('Es el original: la versión de la que se traduce'),
        child: tag,
      );
    }

    return PopupMenuButton<String>(
      key: Key('status-${editor.language}'),
      tooltip: tr(
        'Estado de la versión en {0}: '
        '{1}',
        [editor.language, statusName(status)],
      ),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final option in options)
          CheckedPopupMenuItem<String>(
            key: Key('status-${editor.language}-$option'),
            value: option,
            checked: status == TranslationStatus.parse(option),
            child: Text(_names[option] ?? option),
          ),
      ],
      onSelected: (value) => _set(context, value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tag,
          Icon(Icons.arrow_drop_down, size: 15, color: context.palette.muted),
        ],
      ),
    );
  }

  Future<void> _set(BuildContext context, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await editor.session.setUnitStatus(
        unit: editor.unit,
        language: editor.language,
        status: status,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('${editor.language}: ${_names[status] ?? status}.'),
        ),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    }
  }
}

/// Traduce la pestaña que se está mirando, y la recarga al terminar.
///
/// Con el mismo diálogo que la lista de traducciones y que un tema entero:
/// las tres preguntan lo mismo --a qué idiomas y con qué proveedor-- y tres
/// diálogos que se parecen acabarían comportándose distinto.
/// Ordena la sangría del fichero abierto y lo dice.
///
/// Decir «ya estaba ordenado» importa tanto como hacerlo: sin eso, un botón
/// que no cambia nada se lee como un botón roto, y es justo lo que va a pasar
/// la segunda vez que se pulse.
Future<void> _tidy(BuildContext context, _LanguageEditor editor) async {
  final messenger = ScaffoldMessenger.of(context);
  final changed = await editor.tidyNow();
  // Fuera el anterior antes de poner el nuevo: encolados, la respuesta a la
  // segunda pulsación aparece tres segundos después de darla, que es cuando
  // ya se ha decidido que el botón no hace nada.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        changed
            ? tr('Ordenado. Guarda para dejarlo así.')
            : tr('Ya estaba ordenado.'),
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}

Future<void> _translateHere(
  BuildContext context,
  _LanguageEditor editor,
  String language,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await translateWith(
    context,
    session: editor.session,
    units: [editor.unit],
    only: [language],
  );
  if (result == null) return;
  // Lo escrito está en disco; el editor tiene la pestaña vacía en memoria.
  await editor.load();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.failed > 0
            ? tr('No se pudo traducir. {0}', [
                result.warnings.firstOrNull ?? '',
              ])
            : tr('Traducida como borrador. Revísala antes de darla por buena.'),
      ),
    ),
  );
}

/// La casilla que apaga el beautify automático de un idioma, y el botón que
/// lo fuerza.
///
/// Dos cosas en un sitio, y a propósito: **la casilla** dice si este idioma
/// se ordena solo al guardar, y **la palabra** lo ordena ahora. Quien acaba de
/// leer «Beautify» y quiere ver qué hace, lo que pulsa es la palabra.
///
/// **Por qué se puede apagar.** Ordenar es reescribir el fichero, y hay
/// ficheros que no admiten que se los reescriba:
///
///  * Un entorno de código cuyo nombre no está en [verbatimEnvironments]
///    --uno propio de la asignatura, uno de un paquete que nadie más usa--.
///    Dentro el espacio en blanco es el contenido, y sangrarlo cambia lo que
///    sale impreso sin tocar una letra.
///  * Un `.tex` que genera otra herramienta y se vuelve a generar: sangrarlo
///    convierte cada regeneración en un diff enorme contra la versión
///    anterior, y el historial deja de servir para ver qué cambió.
///  * Una tabla alineada a mano, columna con columna, para poder leerla. Eso
///    es sangría interior y el indentador solo toca la del principio de cada
///    línea, así que sobrevive; pero un `latexindent` con la configuración de
///    alineado de columnas puesta la reordena a su gusto.
///  * Un fichero con un entorno mal cerrado --material migrado lo tiene--.
///    Compila porque LaTeX es indulgente, pero el contador de niveles no lo
///    es, y a partir de ahí el fichero entero sale corrido.
///
/// Ninguno es frecuente. Todos son reales, y en todos la respuesta correcta
/// es dejar el fichero en paz, no arreglar el indentador.
class _IndentToggle extends StatelessWidget {
  const _IndentToggle({
    required this.editor,
    required this.canWrite,
    required this.showLabel,
  });

  final _LanguageEditor editor;
  final bool canWrite;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final on = editor.unit.indentsIn(editor.language);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: on
              ? tr(
                  'Al guardar se ordena el {0}.\n'
                  'Quítalo si este fichero tiene que quedarse tal cual.',
                  [editor.language],
                )
              : tr('El {0} se queda como esté.', [editor.language]),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              key: const Key('editor-indent'),
              value: on,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: canWrite
                  ? (value) => _toggle(context, value ?? true)
                  : null,
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 4),
          // Un rótulo y no un botón. Antes la palabra ordenaba el fichero al
          // pulsarla, y el botón de la barra de formato hacía lo mismo: dos
          // «Beautify» para una cosa. Ordenar ahora es el de la barra; esto
          // dice qué hace la casilla.
          Text(
            tr('ordenar al guardar'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: context.palette.muted,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _toggle(BuildContext context, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await sessionOf(
        context,
      ).setUnitIndent(unit: editor.unit, language: editor.language, on: on);
      // Encenderla ordena el fichero en ese momento. Es lo que espera quien
      // acaba de pulsarla: una casilla que dice «sangrar» y deja el fichero
      // igual que estaba se lee como que no funciona --y así es como se
      // descubrió que hacía falta el botón de la barra--. Apagarla no deshace
      // nada: lo que ya está escrito no se desordena a posta.
      if (on) await editor.tidyNow();
    } catch (thrown) {
      showProblemIn(messenger, thrown);
    }
  }
}

class _EditorBar extends StatelessWidget {
  const _EditorBar({
    required this.editor,
    required this.canWrite,
    required this.fields,
    required this.hasFields,
    this.onFields,
  });

  final _LanguageEditor editor;
  final bool canWrite;

  /// Si se están viendo los campos en lugar del `.tex` entero.
  final bool fields;

  /// Si esta unidad tiene campos que ver: solo los problemas.
  final bool hasFields;

  final ValueChanged<bool>? onFields;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final dirty = editor.isDirty;
    // Lo que se ve de salida es lo que hace falta para corregir una errata:
    // guardar, descartar y el estado. La ruta, el contador y si se ordena al
    // guardar son de quien mantiene el repositorio, en la interfaz completa.
    final complete = watchSession(context).completeInterface;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
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
          // Dos umbrales y no uno, porque el modo lado a lado hace paneles
          // estrechos a propósito: un tercio de una ventana ancha son unos
          // 530 px, y a ese ancho quitar el contador no bastaba. Por debajo
          // del segundo se va también la etiqueta --el estado sin guardar ya
          // está en el punto de la pestaña y en que el botón esté vivo-- y
          // «Descartar» se queda en su icono.
          //
          // El segundo ha subido dos veces, y las dos por lo mismo: cada
          // cosa que entra en la barra empuja. Con la casilla, de 620 a 860;
          // con «Beautify», de 860 a 1100, porque a 915 se desbordaba 88
          // píxeles. Lo que se va por debajo es la palabra «sin guardar»
          // --que repite lo que ya dicen el punto de la pestaña y el botón
          // encendido-- y el rótulo de «Descartar», que se queda en su icono.
          // Una barra que se desborda esconde su propio botón de guardar, y
          // hay un test que la mide a doce anchos para que no vuelva a pasar.
          //
          // En la interfaz esencial la barra lleva mucho menos --ni ruta, ni
          // contador, ni casilla--, y el mismo umbral dejaba el estado en un
          // punto con media barra vacía al lado.
          final approving = canWrite && editor.canApprove;
          final base = complete ? 1250.0 : 600.0;
          // «Aprobar y siguiente» ocupa: con él a la vista la barra se
          // aprieta un poco antes, y su rótulo solo sale con sitio de sobra.
          // Sin rótulo es su icono, que se pulsa igual y lo dice al pasar.
          final tight = constraints.maxWidth < base + (approving ? 60 : 0);
          final approveLabel = constraints.maxWidth >= base + 420;
          // El de «Campos / LaTeX» va aparte, y más abajo. Es el control que
          // cambia **qué se está editando**, así que esconder sus rótulos es
          // más caro que esconder cualquier otra cosa de la barra: convertirlo
          // en un icono a 1000 px, solo porque «sin guardar» no cabe, sería
          // pagar en el sitio equivocado.
          final toggleTight = constraints.maxWidth < 760;
          // El mismo ancho decide la palabra del estado («borrador»,
          // «revisada»): por debajo queda el punto de color, que se pulsa
          // igual y lo dice en el tooltip.
          final roomForStatus = !tight;
          return Row(
            children: [
              Expanded(
                child: !complete
                    ? const SizedBox.shrink()
                    : Text(
                        editor.file?.path ?? '',
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        // Tail first: the filename matters more than `content/`.
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: context.palette.muted,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              // Campos o texto, para un problema. Un botón y no una pestaña
              // más: es la misma cosa vista de dos maneras, y guardar guarda
              // lo mismo desde las dos.
              if (hasFields || complete) ...[
                _ViewToggle(
                  fields: fields,
                  hasFields: hasFields,
                  compact: toggleTight,
                  onChanged: onFields,
                ),
                const SizedBox(width: 10),
              ],
              if (!editor.exists)
                _Tag('nuevo', colour: context.palette.accentDark)
              else ...[
                // El estado de **este** idioma, y se puede cambiar desde
                // aquí. Es lo que cierra el ciclo de traducir: una máquina
                // deja un borrador, alguien lo lee, y aquí dice que ya está.
                // Sin esto el borrador se quedaba en la lista para siempre y
                // la lista dejaba de significar nada.
                //
                // Compacto en un panel estrecho --el punto de color y la
                // flecha, sin la palabra-- porque el modo lado a lado deja
                // tercios de ventana y la barra se desbordaba ochenta y seis
                // píxeles. Se sigue pudiendo pulsar, que es lo que importa.
                _StatusButton(
                  editor: editor,
                  canWrite: canWrite,
                  compact: !roomForStatus,
                ),
                // Si este idioma se re-sangra al guardar. Aquí y no en las
                // preferencias porque la decisión es de **este fichero**: se
                // apaga por lo que tiene dentro, no por cómo le gusta
                // trabajar a nadie. Y en la interfaz completa: de salida se
                // ordena, y apagarlo es de quien sabe por qué.
                if (complete) ...[
                  const SizedBox(width: 4),
                  _IndentToggle(
                    editor: editor,
                    canWrite: canWrite,
                    // El rótulo es el botón que ordena ahora, así que aguanta
                    // hasta mucho más abajo: lo que se va antes es la palabra
                    // del estado, que se lee en el color del punto.
                    // Con «Aprobar y siguiente» a la vista, cede antes.
                    showLabel: constraints.maxWidth >= (approving ? 880 : 760),
                  ),
                ],
                if (dirty && !tight) ...[
                  const SizedBox(width: 6),
                  _Tag(tr('sin guardar'), colour: context.palette.ex),
                ],
              ],
              if (complete && !narrow) ...[
                const SizedBox(width: 10),
                Text(
                  tr('{0} car.', [editor.controller.text.length]),
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
                ),
              ],
              const SizedBox(width: 10),
              if (dirty)
                tight
                    ? IconButton(
                        tooltip: tr('Descartar los cambios'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.undo, size: 16),
                        onPressed: editor.saving
                            ? null
                            : () => _discard(context),
                      )
                    : TextButton(
                        onPressed: editor.saving
                            ? null
                            : () => _discard(context),
                        child: Text(tr('Descartar')),
                      ),
              const SizedBox(width: 4),
              if (approving) ...[
                _ApproveButton(editor: editor, compact: !approveLabel),
                const SizedBox(width: 6),
              ],
              Tooltip(
                message: tr('Guardar ({0})', [saveShortcutLabel]),
                child: FilledButton.icon(
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
                  label: Text(editor.saving ? tr('Guardando…') : tr('Guardar')),
                  // Disabled rather than hidden when there is nothing to save, so
                  // the button does not move around as you type.
                  onPressed: !canWrite || !dirty || editor.saving
                      ? null
                      : () => _saveEditor(context, editor),
                ),
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
        title: Text(tr('¿Descartar los cambios?')),
        content: Text(
          tr('Se perderá lo que has escrito desde que abriste el fichero.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Seguir editando')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Descartar')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await editor.forgetDraft();
      await editor.load();
    }
  }
}

/// Guarda lo que hay en [editor]: pide el mensaje, hace el commit y lo dice.
///
/// Uno para el botón de la barra y para ⌘S / Ctrl+S, que tienen que hacer lo
/// mismo.
/// «El original ha cambiado desde que se revisó», con lo que ha cambiado.
class _OutdatedStrip extends StatelessWidget {
  const _OutdatedStrip({required this.unit, required this.language});

  final Unit unit;
  final String language;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('outdated-strip'),
    width: double.infinity,
    color: context.palette.tint(
      context.palette.status(TranslationStatus.outdated),
      0.10,
    ),
    padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
    child: Row(
      children: [
        Icon(
          Icons.history_toggle_off,
          size: 15,
          color: context.palette.status(TranslationStatus.outdated),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tr('El original ha cambiado desde que se revisó esta traducción.'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.palette.ink),
          ),
        ),
        TextButton(
          key: const Key('show-original-changes'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => _OriginalChanges(
              session: sessionOf(context),
              unit: unit,
              language: language,
            ),
          ),
          child: Text(tr('Ver qué ha cambiado')),
        ),
      ],
    ),
  );
}

/// Lo que ha cambiado en el original desde la última revisión.
class _OriginalChanges extends StatefulWidget {
  const _OriginalChanges({
    required this.session,
    required this.unit,
    required this.language,
  });

  final Session session;
  final Unit unit;
  final String language;

  @override
  State<_OriginalChanges> createState() => _OriginalChangesState();
}

class _OriginalChangesState extends State<_OriginalChanges> {
  bool _loading = true;
  ({String text, FileCommit commit})? _then;
  String _now = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final unit = widget.unit;
    final then = await widget.session.originalAtReview(unit, widget.language);
    var now = '';
    try {
      now =
          (await widget.session
                  .gatewayFor(unit.repo)
                  .read(unit.fileFor(unit.reference)))
              .text;
    } catch (caught, trace) {
      Diagnostics.instance.note('unit_page._load', caught, trace);
    }
    if (!mounted) return;
    setState(() {
      _then = then;
      _now = now;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final then = _then;
    final reference = widget.unit.reference;
    return AlertDialog(
      title: Text(tr('Qué ha cambiado en el original ({0})', [reference])),
      content: SizedBox(
        width: 720,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : then == null
            ? Note(
                tr(
                  'No se sabe desde cuándo: esta traducción no guardó la huella '
                  'del original al revisarse --lo traducido antes de que '
                  'existiera--, o esa versión no está en el historial. Ponlas '
                  'lado a lado para compararlas.',
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      'Desde la versión del {0} '
                      '({1}), que es la que se revisó en '
                      '{2}:',
                      [
                        _date(then.commit.when),
                        then.commit.author,
                        widget.language,
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DiffBox(before: then.text, after: _now, maxHeight: 460),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cerrar')),
        ),
      ],
    );
  }

  static String _date(DateTime when) =>
      '${when.day}/${when.month}/${when.year}';
}

/// «Aprobar y siguiente»: da por buena la traducción que se está leyendo y
/// abre la siguiente sin revisar.
///
/// Revisar treinta traducciones era, treinta veces: guardar lo corregido,
/// cambiar el estado, volver a la lista y buscar la siguiente. Aquí es un
/// botón --con lo corregido y el estado en un solo cambio-- y la siguiente se
/// abre ya en el mismo idioma, en el orden de la lista de Traducción.
class _ApproveButton extends StatelessWidget {
  const _ApproveButton({required this.editor, required this.compact});

  final _LanguageEditor editor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tooltip = editor.isDirty
        ? tr(
            'Guardar lo corregido, darla por revisada y abrir la siguiente sin '
            'revisar',
          )
        : tr('Darla por revisada y abrir la siguiente sin revisar');
    final onPressed = editor.saving ? null : () => _approve(context, editor);
    if (compact) {
      return IconButton(
        key: const Key('approve-next'),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.task_alt, size: 17, color: context.palette.accentDark),
        onPressed: onPressed,
      );
    }
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        key: const Key('approve-next'),
        icon: const Icon(Icons.task_alt, size: 16),
        label: Text(tr('Aprobar y siguiente')),
        onPressed: onPressed,
      ),
    );
  }
}

Future<void> _approve(BuildContext context, _LanguageEditor editor) async {
  final session = sessionOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final language = editor.language;
  final title = editor.unit.title(editor.unit.reference);
  // La siguiente, antes de aprobar: después esta ya no está en la lista, y
  // no se sabría dónde se estaba.
  final next = session.nextToReview(language, after: editor.unit.path);
  final problem = await editor.approve();
  if (!context.mounted) return;
  if (problem != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(problem),
        backgroundColor: context.palette.teacher,
        duration: const Duration(seconds: 6),
      ),
    );
    return;
  }
  if (next == null || next.path == editor.unit.path) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr('«{0}» revisada. No queda nada sin revisar en {1}.', [
            title,
            language,
          ]),
        ),
      ),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        tr('«{0}» revisada. Siguiente: «{1}».', [
          title,
          next.title(next.reference),
        ]),
      ),
    ),
  );
  // Lo que dice si hay algo sin guardar se apunta al repintar, y aprobar
  // acaba de guardar lo corregido: sin esperar a ese repintado, salir
  // preguntaba por unos cambios que ya estaban guardados.
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  goTo(context, Routes.unit(next.path, language: language));
}

Future<void> _saveEditor(BuildContext context, _LanguageEditor editor) async {
  final session = sessionOf(context);
  final suggested = editor.suggestedMessage();
  final message = await askSaveMessage(
    context,
    session,
    suggested: suggested,
    dialog: (context) => _CommitDialog(suggested: suggested),
  );
  if (message == null || !context.mounted) return;

  // Lo de antes y lo de después, ahora: al guardar, lo cargado pasa a ser lo
  // guardado y el diff ya no se podría sacar.
  final before = editor._loadedText;
  final after = editor.controller.text;
  final navigator = Navigator.of(context, rootNavigator: true);
  final problem = await editor.save(message);
  if (!context.mounted) return;

  if (problem == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      savedNotice(
        notice: session.saveNotice(editor.unit.repo),
        message: message,
        before: before,
        after: after,
        what: editor.unit.fileFor(editor.language),
        navigator: navigator,
      ),
    );
    // The catalogue's translation status just changed, so the library and
    // the counts in the rail have to catch up.
    await sessionOf(context).reloadCatalogue();
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(problem),
        backgroundColor: context.palette.teacher,
        duration: const Duration(seconds: 6),
      ),
    );
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
      title: Text(tr('Guardar el cambio')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Queda en el historial con tu nombre y lo que digas aquí, así que '
                'después se puede ver quién cambió qué, y cuándo.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
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
          key: const Key('commit-save'),
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

  /// Las pestañas de PDF abiertas, cada una cerrable.
  final List<PdfGroup> open;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    return SizedBox(
      height: 38,
      // Scrolls rather than wraps: three languages plus the metadata fit on a
      // desktop and not on a phone, and a tab strip that reflows to two rows
      // moves the content down as you switch.
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          TourTarget(
            id: 'unit-languages',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Con el nombre del idioma y no su código: «va» es un código
                // que hay que saber, «Valencià» se lee. El código sigue en el
                // tooltip, que es lo que nombran las rutas y los ficheros.
                for (final code in languages)
                  DidactaTab(
                    key: Key('language-tab-$code'),
                    label: languageNameOf(session, code),
                    tooltip: '$code.tex',
                    status: unit.statusIn(code),
                    selected: code == active,
                    dirty: dirty.contains(code),
                    onTap: () => onSelect(code),
                  ),
              ],
            ),
          ),
          const _Separator(),
          // Compilar delante de los metadatos: es lo que se hace entre una
          // edición y la siguiente, y `unit.yaml` se toca una vez cada varios
          // meses. El orden de una fila de pestañas es una afirmación sobre
          // con qué frecuencia se usa cada una.
          TourTarget(
            id: 'unit-compile',
            child: DidactaTab(
              label: tr('compilar'),
              icon: Icons.play_circle_outline,
              selected: active == previewTab,
              dirty: false,
              onTap: () => onSelect(previewTab),
            ),
          ),
          DidactaTab(
            key: const Key('metadata-tab'),
            label: tr('metadatos'),
            tooltip: tr('El unit.yaml de la lección'),
            selected: active == metadataTab,
            dirty: false,
            onTap: () => onSelect(metadataTab),
          ),
          DidactaTab(
            label: tr('historial'),
            icon: Icons.history,
            selected: active == historyTab,
            dirty: false,
            onTap: () => onSelect(historyTab),
          ),
          if (open.isNotEmpty) const _Separator(),
          for (final group in open)
            DidactaTab(
              label: group.label,
              // Ámbar y discreto: lo que hay abierto sigue siendo un PDF de
              // verdad, pero es de antes del último cambio, y eso hay que
              // saberlo antes de proyectarlo en una clase.
              icon: group.hasStale
                  ? Icons.change_circle_outlined
                  : group.isSingle
                  ? Icons.picture_as_pdf_outlined
                  : Icons.compare_outlined,
              iconColour: group.hasStale ? context.palette.ex : null,
              tooltip: group.hasStale
                  ? tr('La unidad ha cambiado después de compilar esto')
                  : null,
              selected: active == _pdfTab(group.id),
              dirty: false,
              onTap: () => onSelect(_pdfTab(group.id)),
              onClose: () => onClose(group.id),
            ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 9),
    child: SizedBox(width: 1, child: ColoredBox(color: context.palette.rule)),
  );
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
        SectionLabel(tr('Qué es')),
        _Row(
          tr('tipo'),
          kindName(unit.kind),
          colour: context.palette.kind(unit.kind),
        ),
        _Row(tr('categoría'), unit.category),
        _Row(tr('tema'), unit.topic),
        if (unit.difficulty != null)
          _Row(tr('dificultad'), difficultyName(unit.difficulty!)),
        if (unit.durationMinutes != null)
          _Row(tr('duración'), tr('{0} min', [unit.durationMinutes])),
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

        // El rótulo y la lista, y nada más.
        //
        // Las tres acciones que había aquí --darla en otro tema, partirla en
        // dos y restaurarla desde una congelación-- se han ido a la ⓘ de la
        // cabecera. Dos razones, y la segunda es la que manda: este panel se
        // puede tener cerrado, y con la lección en dos sitios los dos botones
        // no cabían en sus trescientos y pico píxeles, así que el que decía
        // «Gestionar vinculación…» se salía del panel y no se podía pulsar.
        SectionLabel(tr('Se usa en {0} ubicación(es)', [unit.usedBy.length])),
        if (unit.usedBy.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Note(
              tr(
                'Ninguna composición la referencia. Después de una migración '
                'esto es material que llegó y no se está dando: o falta ponerlo '
                'en una asignatura, o se puede quitar.',
              ),
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
                '${session.courseById(use.course)?.title(session.language) ?? use.course} · '
                '${use.year}',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () => context.go(
                Routes.document(use.course, use.year, use.document),
              ),
            ),

        if (unit.objectives.isNotEmpty) ...[
          SectionLabel(tr('Objetivos')),
          for (final objective in unit.objectives)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('· ', style: TextStyle(color: context.palette.muted)),
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
          SectionLabel(tr('Prerrequisitos')),
          for (final reference in unit.prerequisites)
            _Prerequisite(reference: reference, session: session),
        ],

        if (unit.warnings.isNotEmpty) ...[
          SectionLabel(tr('Avisos')),
          for (final warning in unit.warnings)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Note(warning, tone: context.palette.ex),
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
        color: missing ? context.palette.teacher : context.palette.muted,
      ),
      title: Text(
        missing
            ? tr('{0} (no existe)', [reference])
            : unit.title(session.language),
        style: TextStyle(
          fontSize: 12.5,
          color: missing ? context.palette.teacher : null,
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
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
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
                    color: context.palette.teacher,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('No se ha podido abrir el fichero'),
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
              Row(
                children: [
                  if (unconfigured || forbidden)
                    FilledButton.icon(
                      icon: const Icon(Icons.settings, size: 16),
                      label: Text(tr('Ir a Ajustes')),
                      onPressed: () =>
                          context.go(Routes.settings(section: 'repositorios')),
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(tr('Reintentar')),
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
          title: tr('Unidad no encontrada'),
          breadcrumbs: [(tr('Biblioteca'), Routes.library())],
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
                    Text(
                      tr(
                        'No está en el catálogo. Puede que se haya renombrado, '
                        'o que el catálogo esté desactualizado: se regenera con '
                        '`didacta index`.',
                      ),
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => context.go(Routes.library()),
                      child: Text(tr('Ir a la biblioteca')),
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

/// El interruptor de editar los idiomas lado a lado.
///
/// Una casilla y no un botón, porque es un modo y no una acción: se queda
/// puesto, y lo que dice es en qué estado está la pantalla.
class _SplitToggle extends StatelessWidget {
  const _SplitToggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: on
          ? tr('Volver a un idioma a la vez')
          : tr('Ver los idiomas uno al lado del otro'),
      child: InkWell(
        onTap: () => onChanged(!on),
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 17,
                height: 17,
                child: Checkbox(
                  key: const Key('split-editors'),
                  value: on,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) => onChanged(value ?? false),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                tr('lado a lado'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on
                      ? context.palette.accentDark
                      : context.palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los idiomas de una unidad, editables a la vez.
///
/// Cada panel es el editor completo del idioma --su barra, su estado sin
/// guardar y su propio commit-- porque son tres ficheros y no tres vistas de
/// uno. Lo que comparten es la unidad.
///
/// El panel del idioma activo va marcado: con tres columnas de LaTeX
/// idénticas en forma, saber cuál responde a la pestaña de arriba y a los
/// atajos deja de ser evidente.
class _SplitEditors extends StatelessWidget {
  const _SplitEditors({
    required this.unit,
    required this.session,
    required this.languages,
    required this.active,
    required this.editorFor,
    required this.onSelect,
    this.scrollOf,
  });

  final Unit unit;
  final Session session;
  final List<String> languages;
  final String active;
  final Widget Function(String language) editorFor;
  final ValueChanged<String> onSelect;

  /// El desplazamiento de cada idioma, para llevarlos a la vez.
  final ScrollController? Function(String language)? scrollOf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Un panel de LaTeX por debajo de 300 px no es un panel: se cortan
        // las líneas y no se puede leer nada. Así que se muestran los que
        // caben, empezando por el activo y siguiendo por los que existen.
        final room = (constraints.maxWidth / 300).floor().clamp(1, 4);
        final shown = _order().take(room).toList();

        if (shown.length == 1) {
          // No cabe más de uno: se enseña el activo tal cual, con un aviso
          // en lugar de fingir una comparación de una columna.
          return Column(
            children: [
              const _TooNarrow(),
              Expanded(child: editorFor(shown.single)),
            ],
          );
        }

        return _ScrollTogether(
          leader: scrollOf?.call(active),
          followers: [
            for (final language in shown)
              if (language != active) ?scrollOf?.call(language),
          ],
          child: Row(
            children: [
              for (var i = 0; i < shown.length; i += 1) ...[
                if (i > 0) const VerticalDivider(width: 1),
                Expanded(
                  child: _Pane(
                    language: shown[i],
                    unit: unit,
                    selected: shown[i] == active,
                    locked:
                        shown[i] == unit.reference && active != unit.reference,
                    onTap: () => onSelect(shown[i]),
                    child: editorFor(shown[i]),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// El activo primero, luego los que existen, luego los que faltan.
  ///
  /// Los que faltan van al final pero van: empezar una traducción con el
  /// original al lado es justo para lo que sirve esto.
  List<String> _order() {
    final rest =
        [
          for (final code in languages)
            if (code != active) code,
        ]..sort((a, b) {
          final exists = unit.statusIn(b).exists ? 1 : 0;
          return exists.compareTo(unit.statusIn(a).exists ? 1 : 0);
        });
    return [active, ...rest];
  }
}

/// Lleva los paneles a la vez: donde está el activo, los demás.
///
/// Por proporción y no por línea: el original y la traducción no tienen las
/// mismas líneas, pero van en el mismo orden, y a media página de uno le toca
/// media página del otro. Solo manda el activo --el que se está leyendo--:
/// que los dos se movieran el uno al otro sería un rebote sin fin.
class _ScrollTogether extends StatefulWidget {
  const _ScrollTogether({
    required this.leader,
    required this.followers,
    required this.child,
  });

  final ScrollController? leader;
  final List<ScrollController> followers;
  final Widget child;

  @override
  State<_ScrollTogether> createState() => _ScrollTogetherState();
}

class _ScrollTogetherState extends State<_ScrollTogether> {
  ScrollController? _listening;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(_ScrollTogether old) {
    super.didUpdateWidget(old);
    if (old.leader != widget.leader) _listen();
  }

  void _listen() {
    _listening?.removeListener(_follow);
    _listening = widget.leader;
    _listening?.addListener(_follow);
  }

  void _follow() {
    final leader = widget.leader;
    if (leader == null || !leader.hasClients) return;
    final position = leader.position;
    final fraction = position.maxScrollExtent <= 0
        ? 0.0
        : (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    for (final follower in widget.followers) {
      if (!follower.hasClients) continue;
      final target = fraction * follower.position.maxScrollExtent;
      if ((follower.position.pixels - target).abs() > 1) {
        follower.jumpTo(target);
      }
    }
  }

  @override
  void dispose() {
    _listening?.removeListener(_follow);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.language,
    required this.unit,
    required this.selected,
    required this.onTap,
    required this.child,
    this.locked = false,
  });

  final String language;
  final Unit unit;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  /// Si se está leyendo y no editando: el original, mientras se revisa una
  /// traducción. La cabecera lo dice, y pulsarla lo deja editar.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final status = unit.statusIn(language);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: selected
                  ? context.palette.accentDark.withValues(alpha: 0.10)
                  : context.palette.panel,
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? context.palette.accentDark
                      : context.palette.rule,
                  width: selected ? 1.6 : 1,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                Text(
                  language,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? context.palette.accentDark
                        : context.palette.ink,
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(language: language, status: status),
                const Spacer(),
                if (selected)
                  Text(
                    'activo',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.palette.muted,
                    ),
                  )
                else if (locked)
                  Tooltip(
                    message: tr(
                      'El original, para leerlo al lado. Pulsa aquí para '
                      'editarlo.',
                    ),
                    child: Row(
                      key: Key('pane-locked-$language'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: context.palette.muted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            tr('solo lectura'),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: context.palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _TooNarrow extends StatelessWidget {
  const _TooNarrow();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: context.palette.panel,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(
      tr(
        'No hay ancho para dos columnas de LaTeX. Oculta el panel de la '
        'derecha o ensancha la ventana.',
      ),
      style: TextStyle(fontSize: 11.5, color: context.palette.muted),
    ),
  );
}

/// En qué idiomas se enseña una unidad.
///
/// Los que se han encendido en Ajustes, más aquellos en los que **ya tiene
/// fichero**. Lo segundo no es un detalle: una unidad con `en.tex` escrito y
/// el inglés apagado seguiría teniendo ese fichero, y una pestaña que no
/// aparece es contenido que no se puede ni leer ni borrar desde aquí.
List<String> languagesOfUnit(Session session, Unit unit) =>
    session.languagesToEditCodes(
      allowed: session.catalogue.languages,
      declared: [
        for (final entry in unit.statuses.entries)
          if (entry.value.exists) entry.key,
      ],
    );

/// Separa unas cuantas ubicaciones de una lección del resto.
///
/// Las que se nombren pasan a una copia con identidad propia; las demás se
/// quedan con la de siempre. Los dos grupos siguen sincronizados por dentro y
/// dejan de estarlo entre ellos.
/// Lo que quedó sin guardar la última vez, ofrecido al abrir el fichero.
///
/// Solo aparece si Didacta se cerró sin pasar por el aviso de salir --un
/// cuelgue, un corte--: al salir de la pantalla a propósito el borrador se va
/// con ella.
class _RecoveredDraft extends StatelessWidget {
  const _RecoveredDraft({
    required this.draft,
    required this.changedSince,
    required this.onRestore,
    required this.onForget,
  });

  final Draft draft;

  /// Si el fichero ha cambiado desde que se escribió el borrador.
  final bool changedSince;
  final VoidCallback onRestore;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('recovered-draft'),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 6, 8),
      decoration: BoxDecoration(
        color: context.palette.ex.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: context.palette.ex, width: 2.5)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(Radii.control),
          bottomRight: Radius.circular(Radii.control),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.restore_page_outlined,
            size: 16,
            color: context.palette.ex,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(
                'Hay texto sin guardar de {0}: Didacta '
                'se cerró antes de guardarlo.'
                '{1}',
                [
                  describeWhen(draft.when),
                  changedSince
                      ? tr(
                          ' El fichero ha cambiado desde entonces; si '
                          'lo recuperas, mira qué cambia antes de guardar.',
                        )
                      : '',
                ],
              ),
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
          TextButton(
            key: const Key('recovered-forget'),
            onPressed: onForget,
            child: Text(tr('Descartarlo')),
          ),
          FilledButton.tonal(
            key: const Key('recovered-restore'),
            onPressed: onRestore,
            child: Text(tr('Recuperarlo')),
          ),
        ],
      ),
    ),
  );
}

/// El aviso de que esta lección se da en más de un curso.
///
/// Una lección es una sola carpeta aunque la llamen tres composiciones:
/// guardarla la cambia en las tres. Eso es lo que la hace útil --se corrige
/// una errata una vez-- y lo que sorprende a quien entra a retocarla pensando
/// en el curso de este año. Por eso va encima del texto y dice cuáles, y
/// ofrece lo que se hace cuando no se quiere eso: separar una copia.
///
/// Cuenta cursos académicos y no composiciones: la misma lección en el tema
/// y en el examen del mismo curso es algo que quien la edita ya sabe.
class SharedLessonStrip extends StatelessWidget {
  const SharedLessonStrip({super.key, required this.unit, this.onSplit});

  final Unit unit;
  final VoidCallback? onSplit;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final years = <String, UnitUsage>{};
    for (final use in unit.usedBy) {
      years.putIfAbsent('${use.course}@${use.year}', () => use);
    }
    if (years.length < 2) return const SizedBox.shrink();

    String name(UnitUsage use) =>
        '${session.courseById(use.course)?.title(session.language) ?? use.course}'
        ' ${use.year}';
    final names = [for (final use in years.values) name(use)];
    final shown = names.length <= 3 ? names : names.take(2).toList();
    final rest = names.length - shown.length;
    final list = rest > 0
        ? tr('{0} y {1} más', [shown.join(', '), rest])
        : shown.length == 1
        ? shown.single
        : tr('{0} y {1}', [
            shown.take(shown.length - 1).join(', '),
            shown.last,
          ]);

    return Padding(
      key: const Key('shared-lesson-strip'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 6, 6, 6),
        decoration: BoxDecoration(
          color: context.palette.pending.withValues(alpha: 0.08),
          border: Border(
            left: BorderSide(color: context.palette.pending, width: 2.5),
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(Radii.control),
            bottomRight: Radius.circular(Radii.control),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.call_split, size: 15, color: context.palette.pending),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: tr('Se da en {0} cursos', [years.length]),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: tr(' ({0}): lo que guardes aquí cambia en todos.', [
                        list,
                      ]),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ),
            if (onSplit != null)
              TextButton(
                key: const Key('shared-lesson-split'),
                onPressed: onSplit,
                child: Text(tr('Separar una copia…')),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _splitUnit(
  BuildContext context,
  Session session,
  Unit unit,
) async {
  String label(UnitUsage use) =>
      '${session.courseById(use.course)?.title(session.language) ?? use.course}'
      ' · ${use.year} · ${use.document}'
      '${use.index > 0 ? tr(' (posición {0})', [use.index + 1]) : ''}';

  final request = await askSplit(
    context,
    title: tr('Dividir la vinculación de «{0}»', [
      unit.title(session.language),
    ]),
    places: [
      for (final use in unit.usedBy) SyncPlace(key: use.key, label: label(use)),
    ],
    explanation: tr(
      'Cada grupo que se separe recibe una copia de la lección, con su '
      'texto, sus figuras y sus metadatos tal como están ahora, y un id '
      'propio. Nada se pierde y ningún otro sitio cambia.',
    ),
  );
  if (request == null || !context.mounted) return;
  final groups = request.groups;

  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.splitContent(
      unit: unit.path,
      groups: groups,
      paths: [
        for (final use in unit.usedBy) 'courses/${use.course}/${use.year}',
      ],
      message: tr(
        'Dividir la vinculación de «{0}» en '
        '{1} grupo(s)',
        [unit.title(session.language), groups.length + 1],
      ),
    ),
    done: tr('Vinculación dividida. Cada grupo sigue sincronizado por dentro.'),
    repo: unit.repo,
  );
  if (ok) await session.reloadCatalogue();
}

/// Trae una lección al estado que tiene en la versión congelada que se está
/// mirando.
///
/// La carpeta entera: su texto en cada idioma, sus figuras y sus metadatos.
/// Una lección **sí** es una carpeta, así que restaurarla es copiar lo que
/// había, y lo que queda es un cambio pendiente como cualquier otro.
Future<void> _restoreUnit(
  BuildContext context,
  Session session,
  Unit unit,
) async {
  final frozen = session.frozen;
  if (frozen == null) return;
  final course =
      session.courseById(frozen.freeze.course) ??
      session.catalogue.courses.firstOrNull;
  if (course == null) return;
  await showRestore(
    context,
    session: session,
    course: course,
    year: frozen.freeze.year,
    freeze: frozen.freeze,
    scope: RestoreScope.lesson,
    path: unit.path,
    label: unit.title(session.language),
  );
}

/// Da esta lección también en otro tema, de otra asignatura si hace falta.
Future<void> _useUnit(BuildContext context, Session session, Unit unit) async {
  final target = await askLessonTarget(
    context,
    session: session,
    title: tr('Dar «{0}» en otro tema', [unit.title(session.language)]),
    fromCourse: unit.usedBy.firstOrNull?.course ?? '',
  );
  if (target == null || !context.mounted) return;

  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.useUnit(
      unit: unit.path,
      toCourse: target.course,
      toYear: target.year,
      document: target.document,
      duplicate: target.duplicate,
    ),
    done: target.duplicate
        ? tr('Copiada en «{0}». Son dos lecciones a partir de ahora.', [
            target.document,
          ])
        : tr(
            'Añadida a «{0}». Es la misma lección: corregirla '
            'sigue siendo corregirla una vez.',
            [target.document],
          ),
    repo: unit.repo,
  );
  if (ok) await session.reloadCatalogue();
}

/// Dónde empieza la línea [line] (desde 1) de [text]; el final, si no hay
/// tantas.
int offsetOfLine(String text, int line) {
  var offset = 0;
  for (var current = 1; current < line; current += 1) {
    final next = text.indexOf('\n', offset);
    if (next < 0) return text.length;
    offset = next + 1;
  }
  return offset;
}
