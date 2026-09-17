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
import '../model/catalogue.dart';
import '../model/tex_indent.dart';
import '../router.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'history_tab.dart';
import 'metadata_editor.dart';
import 'pdf_tab.dart';
import 'unit_preview.dart';
import 'shell.dart';
import 'problem_editor.dart';
import 'tabs.dart';
import 'tex_field.dart';
import 'tex_highlight.dart';
import 'tex_toolbar.dart';
import 'theme.dart';
import 'translate_unit.dart';

class UnitPage extends StatefulWidget {
  const UnitPage({super.key, required this.unitPath, this.language});

  final String unitPath;

  /// El idioma en el que abrirla, si la dirección lo dice. Null es «el que
  /// tenga más sentido», que es lo que hace falta al entrar desde la
  /// biblioteca.
  final String? language;

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

    final console = session.buildConsole;
    console.start('${pane.profile} · $language');
    unawaited(showBuildConsole(context, console, autoClose: true));

    try {
      final results = await compiler.compile(
        unitPath: unit.path,
        profiles: [pane.profile],
        languages: [language],
        onOutput: console.add,
      );
      console.finish(ok: results.every((result) => result.ok));
      if (!mounted) return;
      final result = results.firstOrNull;
      // El índice se vuelve a buscar: entre el await y aquí alguien puede
      // haber cerrado la pestaña o separado el panel.
      final now = _open.indexWhere((group) => group.id == groupId);
      if (now < 0) return;
      final current = _open[now].pane(language);
      if (current == null) return;

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
        _say(result.errors.isEmpty ? 'No compiló.' : result.errors.first);
      }
    } catch (error) {
      console.finish(failure: error);
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

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _history?.dispose();
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
    // El de la dirección manda: se llega aquí desde «esto falta por
    // traducir», y abrir otra pestaña sería mandar a buscarla.
    _active ??= languages.contains(widget.language)
        ? widget.language
        : _preferredLanguage(unit, session, languages);

    return Column(
      children: [
        PageHeader(
          title: unit.title(session.language),
          // Con varios repositorios abiertos, la ruta sola no dice de cuál
          // es: dos pueden tener la misma.
          subtitle: session.colourOf(unit.repo) != null
              ? '${unit.repo} · ${unit.path}'
              : unit.path,
          breadcrumbs: [('Biblioteca', Routes.library())],
          actions: [
            // Solo cuando la pestaña activa es un idioma: partir en dos no
            // significa nada en `unit.yaml`, en compilar ni en un PDF.
            if (_isLanguage(_active!, languages))
              _SplitToggle(
                on: session.splitEditors,
                onChanged: (value) => sessionOf(context).setSplitEditors(value),
              ),
            IconButton(
              tooltip: session.unitPanelVisible
                  ? 'Ocultar el panel de la derecha'
                  : 'Mostrar el panel de la derecha',
              isSelected: session.unitPanelVisible,
              icon: const Icon(Icons.info_outline, size: 18),
              selectedIcon: const Icon(Icons.info, size: 18),
              onPressed: () => sessionOf(
                context,
              ).setUnitPanelVisible(!session.unitPanelVisible),
            ),
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
            onSelect: (code) {
              setState(() {
                if (_isLanguage(code, languages)) _lastLanguage = code;
                _active = code;
              });
              // Al volver a un PDF o a compilar, se vuelven a mirar las
              // fechas: puede haberse guardado un `.tex` mientras tanto.
              if (code == previewTab || code.startsWith(pdfTabPrefix)) {
                _refreshStaleness(session);
                if (code == previewTab) _preview?.refreshExisting();
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
    final languages = session.catalogue.languages;
    if (session.splitEditors && _isLanguage(active, languages)) {
      return _SplitEditors(
        unit: unit,
        session: session,
        languages: languages,
        active: active,
        editorFor: (language) => _editorFor(unit, language, session),
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
      historyTab => HistoryTab(state: _historyFor(unit, session)),
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

  /// De qué fichero se enseña el historial.
  ///
  /// El del idioma que estaba abierto, y el de referencia si se llegó aquí
  /// desde otra pestaña. Una unidad son tres o cuatro ficheros y el historial
  /// es de uno: enseñar el de `es.tex` estando en el valenciano sería
  /// contestar a otra pregunta.
  String _historyPathFor(Unit unit, Session session) {
    final languages = session.catalogue.languages;
    final last = _lastLanguage;
    final language = last != null && languages.contains(last)
        ? last
        : unit.reference;
    return unit.fileFor(language);
  }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
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
    // La del catálogo de ahora, no la de cuando se creó el editor: el editor
    // sobrevive a un cambio de pestaña y a una recarga, y lo que la unidad
    // dice de sí misma --su estado, su título-- cambia por debajo.
    editor.unit = unit;
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

  /// Pinta el LaTeX que contiene: órdenes, comentarios, matemáticas y los
  /// delimitadores de cada entorno, del color de ese entorno. Un fichero
  /// suelto calcula su propio árbol, así que aquí también sale en rojo lo que
  /// se quedó sin cerrar.
  final TexEditingController controller = TexEditingController();

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

  void _onEdit() => onChanged();

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
    if (!exists) return 'Añadir la versión $language de «$title»';
    return 'Editar la versión $language de «$title»';
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
    focusNode.dispose();
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

    final canWrite = watchSession(context).canWriteIn(unit.repo);
    // Los tres campos, para los problemas. Lo decide el tipo de la unidad y
    // no el árbol donde vive: una teoría o un ejemplo dentro de una práctica
    // se escriben de corrido. Y el fichero manda por encima de eso: si no
    // tiene la forma de un problema --porque son tres en un fichero-- el
    // editor de texto es lo que hay, y la pantalla lo dice en lugar de
    // esconder el botón.
    final structured = unit.editsAsProblem;

    return Column(
      children: [
        _EditorBar(
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
        if (editor.conflicted)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Note(
              'El fichero ha cambiado en el repositorio desde que lo abriste. '
              'Vuelve a cargarlo para no sobrescribir el trabajo de otra '
              'persona; tu texto sigue aquí mientras decides.',
              tone: didactaTeacher,
            ),
          )
        else if (!editor.exists)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Note(
                  'No existe la versión en $language de esta unidad. Lo que '
                  'se escriba aquí la crea, y hasta entonces ningún documento '
                  'que la use se puede compilar en $language.'
                  '${canWrite ? '\n\nPara traducir con el original delante, '
                            'marca «lado a lado» arriba: así se ve al lado y '
                            'no se puede guardar por error como si fuera '
                            'esta.' : ''}',
                  tone: didactaTeacher,
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
                      label: Text('Traducirla a $language con la máquina'),
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
                  color: didactaCard,
                  child: ProblemFields(
                    text: editor.controller.text,
                    readOnly: !canWrite,
                    onChanged: editor.replaceText,
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
                      // Solo cuando este idioma se sangra: ofrecerlo en uno
                      // que está marcado para dejar quieto sería ofrecer
                      // justo lo que se ha dicho que no se haga.
                      onTidy: editor.unit.indentsIn(editor.language)
                          ? () => _tidy(context, editor)
                          : null,
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        // La misma caja que en el tema: el LaTeX coloreado y
                        // una columna por cada entorno que envuelve a la
                        // línea. Una lección suelta calcula su propio árbol,
                        // así que las columnas salen sin que nadie le pase
                        // nada.
                        child: TexField(
                          controller: editor.controller,
                          focusNode: editor.focusNode,
                          readOnly: !canWrite,
                          hintText: 'El fichero está vacío.',
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                  ],
                ),
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

  static const String _noFields =
      'Solo un problema tiene enunciado, resultado y solución; '
      'lo demás se escribe de corrido.';

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        key: const Key('problem-view-toggle'),
        tooltip: hasFields
            ? (fields ? 'Ver el LaTeX' : 'Ver los campos')
            : _noFields,
        visualDensity: VisualDensity.compact,
        icon: Icon(fields ? Icons.code : Icons.view_agenda_outlined, size: 16),
        onPressed: onChanged == null ? null : () => onChanged!(!fields),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: didactaPanel,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: hasFields ? 'Enunciado, resultado y solución' : _noFields,
            child: _ViewOption(
              key: const Key('problem-view-fields'),
              label: 'Campos',
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
            ? didactaCard
            : (hovering ? didactaHover : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _colour),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: _colour,
            ),
          ),
        ],
      ),
    ),
  );
}

extension on _ViewOption {
  Color get _colour => !enabled
      ? didactaMuted.withValues(alpha: 0.45)
      : (selected ? didactaAccentDark : didactaMuted);
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

  static const Map<String, String> _names = {
    'draft': 'borrador',
    'translated': 'traducida',
    'reviewed': 'revisada',
    'source': 'original',
  };

  @override
  Widget build(BuildContext context) {
    final status = editor.unit.statusIn(editor.language);
    final settable = canWrite && !status.computed;

    final tag = compact
        ? Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: statusColour(status),
              shape: BoxShape.circle,
            ),
          )
        : _Tag(statusName(status), colour: statusColour(status));
    if (!settable) {
      return Tooltip(
        message: canWrite
            ? 'Lo calcula el motor: ${statusName(status)}'
            : 'Solo lectura · ${statusName(status)}',
        child: tag,
      );
    }

    return PopupMenuButton<String>(
      key: Key('status-${editor.language}'),
      tooltip:
          'Estado de la versión en ${editor.language}: '
          '${statusName(status)}',
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final option in declarableStatuses)
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
          const Icon(Icons.arrow_drop_down, size: 15, color: didactaMuted),
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
      messenger.showSnackBar(SnackBar(content: Text('$error')));
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
            ? 'Sangría ordenada. Guarda para dejarlo así.'
            : 'Ya estaba ordenado.',
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
            ? 'No se pudo traducir. ${result.warnings.firstOrNull ?? ''}'
            : 'Traducida como borrador. Revísala antes de darla por buena.',
      ),
    ),
  );
}

/// La casilla que apaga la sangría automática de un idioma.
///
/// **Por qué se puede apagar.** Sangrar es reescribir el fichero, y hay
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
    return Tooltip(
      message: on
          ? 'Al guardar se ordena la sangría de ${editor.language}.\n'
                'Quítalo si este fichero tiene que quedarse tal cual.'
          : 'La sangría de ${editor.language} se queda como esté.',
      child: InkWell(
        onTap: canWrite ? () => _toggle(context, !on) : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
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
              if (showLabel) ...[
                const SizedBox(width: 4),
                const Text(
                  'Sangrar',
                  style: TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
              ],
            ],
          ),
        ),
      ),
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
      messenger.showSnackBar(
        SnackBar(content: Text('$thrown'), backgroundColor: didactaTeacher),
      );
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
          // Dos umbrales y no uno, porque el modo lado a lado hace paneles
          // estrechos a propósito: un tercio de una ventana ancha son unos
          // 530 px, y a ese ancho quitar el contador no bastaba. Por debajo
          // del segundo se va también la etiqueta --el estado sin guardar ya
          // está en el punto de la pestaña y en que el botón esté vivo-- y
          // «Descartar» se queda en su icono.
          //
          // El segundo subió de 620 a 860 al entrar la casilla de sangría: a
          // 800 px con el fichero tocado la fila se desbordaba 27 píxeles, y
          // lo que sobra ahí es justo la palabra «sin guardar», que repite lo
          // que ya dicen el punto de la pestaña y el botón encendido. Una
          // barra que se desborda esconde su propio botón de guardar.
          final tight = constraints.maxWidth < 860;
          // El mismo ancho decide la palabra del estado («borrador»,
          // «revisada»): por debajo queda el punto de color, que se pulsa
          // igual y lo dice en el tooltip.
          final roomForStatus = !tight;
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
              // Campos o texto, para un problema. Un botón y no una pestaña
              // más: es la misma cosa vista de dos maneras, y guardar guarda
              // lo mismo desde las dos.
              _ViewToggle(
                fields: fields,
                hasFields: hasFields,
                compact: tight,
                onChanged: onFields,
              ),
              const SizedBox(width: 10),
              if (!editor.exists)
                const _Tag('nuevo', colour: didactaAccentDark)
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
                const SizedBox(width: 4),
                // Si este idioma se re-sangra al guardar. Aquí y no en las
                // preferencias porque la decisión es de **este fichero**: se
                // apaga por lo que tiene dentro, no por cómo le gusta
                // trabajar a nadie.
                _IndentToggle(
                  editor: editor,
                  canWrite: canWrite,
                  showLabel: constraints.maxWidth >= 1000,
                ),
                if (dirty && !tight) ...[
                  const SizedBox(width: 6),
                  const _Tag('sin guardar', colour: didactaEx),
                ],
              ],
              if (!narrow) ...[
                const SizedBox(width: 10),
                Text(
                  '${editor.controller.text.length} car.',
                  style: const TextStyle(fontSize: 11, color: didactaMuted),
                ),
              ],
              const SizedBox(width: 10),
              if (dirty)
                tight
                    ? IconButton(
                        tooltip: 'Descartar los cambios',
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

  /// Las pestañas de PDF abiertas, cada una cerrable.
  final List<PdfGroup> open;
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
            DidactaTab(
              label: code,
              status: unit.statusIn(code),
              selected: code == active,
              dirty: dirty.contains(code),
              onTap: () => onSelect(code),
            ),
          const _Separator(),
          // Compilar delante de los metadatos: es lo que se hace entre una
          // edición y la siguiente, y `unit.yaml` se toca una vez cada varios
          // meses. El orden de una fila de pestañas es una afirmación sobre
          // con qué frecuencia se usa cada una.
          DidactaTab(
            label: 'compilar',
            icon: Icons.play_circle_outline,
            selected: active == previewTab,
            dirty: false,
            onTap: () => onSelect(previewTab),
          ),
          DidactaTab(
            label: 'unit.yaml',
            selected: active == metadataTab,
            dirty: false,
            onTap: () => onSelect(metadataTab),
          ),
          DidactaTab(
            label: 'historial',
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
              iconColour: group.hasStale ? didactaEx : null,
              tooltip: group.hasStale
                  ? 'La unidad ha cambiado después de compilar esto'
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 9),
    child: SizedBox(width: 1, child: ColoredBox(color: didactaRule)),
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
                '${session.courseById(use.course)?.title(session.language) ?? use.course} · '
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
          ? 'Volver a un idioma a la vez'
          : 'Ver los idiomas uno al lado del otro',
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
                'lado a lado',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? didactaAccentDark : didactaMuted,
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
  });

  final Unit unit;
  final Session session;
  final List<String> languages;
  final String active;
  final Widget Function(String language) editorFor;
  final ValueChanged<String> onSelect;

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

        return Row(
          children: [
            for (var i = 0; i < shown.length; i += 1) ...[
              if (i > 0) const VerticalDivider(width: 1),
              Expanded(
                child: _Pane(
                  language: shown[i],
                  unit: unit,
                  selected: shown[i] == active,
                  onTap: () => onSelect(shown[i]),
                  child: editorFor(shown[i]),
                ),
              ),
            ],
          ],
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

class _Pane extends StatelessWidget {
  const _Pane({
    required this.language,
    required this.unit,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String language;
  final Unit unit;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

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
                  ? didactaAccentDark.withValues(alpha: 0.10)
                  : didactaPanel,
              border: Border(
                bottom: BorderSide(
                  color: selected ? didactaAccentDark : didactaRule,
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
                    color: selected ? didactaAccentDark : didactaInk,
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(language: language, status: status),
                const Spacer(),
                if (selected)
                  const Text(
                    'activo',
                    style: TextStyle(fontSize: 10.5, color: didactaMuted),
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
    color: didactaPanel,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: const Text(
      'No hay ancho para dos columnas de LaTeX. Oculta el panel de la '
      'derecha o ensancha la ventana.',
      style: TextStyle(fontSize: 11.5, color: didactaMuted),
    ),
  );
}
