/// One document: the units it is made of, in order, and the outputs it makes.
///
/// The composition, in the order it is taught. Each line is a reference the
/// reader can follow into the unit, with the state of the language being
/// built — because "will this come out in Valencian" is answered by the units,
/// not by the document.
///
/// About compiling: this screen says what *would* be built and does not
/// pretend it can build it. Compiling needs LaTeX, and a browser has none.
/// Showing a disabled button with the reason beats a button that fails, and
/// beats hiding the outputs entirely — knowing a document makes seven PDFs is
/// useful even when you have to run one command to get them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'document_links.dart';
import 'history_tab.dart';
import 'info_menu.dart';
import 'composition_editor.dart';
import 'manage_templates.dart';
import 'shell.dart';
import '../data/compiler.dart';
import 'pdf_tab.dart';
import 'source_view.dart';
import 'tabs.dart';
import 'theme.dart';
import 'translate_tab.dart';
import 'unit_preview.dart';

class DocumentPage extends StatefulWidget {
  const DocumentPage({
    super.key,
    required this.courseId,
    required this.year,
    required this.documentId,
  });

  final String courseId;
  final String year;
  final String documentId;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

/// La pestaña de la composición, la del fuente entero y la de compilar.
const String compositionTab = 'composicion';
const String sourceTab = 'fuente';
const String buildTab = 'compilar';

/// La del historial: qué le ha pasado a la composición de este tema.
///
/// De `year.yaml` y no del `.tex`: la composición es lo que se edita desde
/// aquí --qué unidades lleva el tema, en qué orden, cuáles están comentadas--
/// y por tanto lo que cambia de un curso a otro. La última, como en una
/// unidad: es la que menos se abre y la única que no escribe.
const String historyTab = 'historial';

/// Los huecos de traducción del tema. La pestaña solo existe cuando
/// falta algo: una que siempre dice «no falta nada» se deja de mirar
/// justo antes del día en que sí faltaba.
const String translateTab = 'traducir';

/// Prefijo de las pestañas de PDF. Con un carácter que no puede estar en un
/// perfil, para que no choque con las otras dos.
const String documentPdfPrefix = '\u0000pdf:';

class _DocumentPageState extends State<DocumentPage> {
  /// Reading a composition needs neither write access nor a fetch -- the
  /// catalogue already has it -- so the editor is opened deliberately rather
  /// than being the default. It also loads `year.yaml`, which the read-only
  /// view does not need at all.
  bool _editing = false;

  String _active = compositionTab;

  /// Los PDF abiertos, una pestaña por versión y un panel por idioma dentro.
  final List<PdfGroup> _open = [];

  /// El estado de compilar, vivo mientras la pantalla lo esté.
  ///
  /// Aquí y no dentro del panel por lo mismo que en la unidad: si vive en el
  /// widget, cambiar de pestaña tira los resultados que se acaban de
  /// compilar, y volver a la de compilar enseña una pantalla vacía como si
  /// no hubiera pasado nada.
  PreviewState? _preview;

  /// El historial, creado al abrir su pestaña por primera vez. Perezoso: un
  /// `git log` sobre un repositorio con años dentro cuesta, y no se le puede
  /// cobrar a quien solo venía a compilar.
  HistoryState? _history;

  String get courseId => widget.courseId;
  String get year => widget.year;
  String get documentId => widget.documentId;

  String _pdfTab(String id) => '$documentPdfPrefix$id';

  /// Lo que se acaba de compilar, en sus pestañas.
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
        _open.removeWhere((other) => other.id.startsWith('${group.id}:'));
      }
      _active = _pdfTab(groups.first.id);
    });
  }

  void _openPdf(OpenPdf pdf) {
    setState(() {
      final id = pdf.profile;
      final at = _open.indexWhere((group) => group.id == id);
      if (at >= 0) {
        _open[at] = _open[at].replacing(pdf);
      } else {
        _open.add(PdfGroup(id: id, panes: [pdf]));
      }
      _active = _pdfTab(id);
    });
  }

  void _closePdf(String id) {
    setState(() {
      _open.removeWhere((group) => group.id == id);
      if (_active == _pdfTab(id)) _active = buildTab;
    });
  }

  /// Saca un idioma a su propia pestaña.
  void _detach(String groupId, String language) {
    final at = _open.indexWhere((group) => group.id == groupId);
    if (at < 0) return;
    final group = _open[at];
    final pane = group.pane(language);
    if (pane == null || group.panes.length < 2) return;
    setState(() {
      _open[at] = group.without(language);
      final id = '$groupId:$language';
      _open.add(PdfGroup(id: id, panes: [pane]));
      _active = _pdfTab(id);
    });
  }

  /// Vuelve a compilar una sola versión: la del panel que se está mirando.
  Future<void> _recompilePane(
    Session session,
    String groupId,
    String language,
  ) async {
    final compiler = session.compiler(
      repo: session.documentIn(courseId, year, documentId)?.repo,
    );
    final at = _open.indexWhere((group) => group.id == groupId);
    if (compiler == null || at < 0) return;
    final pane = _open[at].pane(language);
    if (pane == null) return;

    setState(() => _open[at] = _open[at].replacing(pane.working()));

    final console = session.buildConsole;
    console.start('${pane.profile} · $language');
    unawaited(showBuildConsole(context, console, autoClose: true));

    try {
      final results = await compiler.compileDocument(
        // La referencia que usa el motor. Aquí no hace falta el documento
        // entero: lo que falte por traducir ya lo bloqueó la pantalla de
        // compilar, y este panel salió de una compilación que sí pudo.
        document: '$courseId@$year/$documentId',
        profiles: [pane.profile],
        languages: [language],
        onOutput: console.add,
      );
      console.finish(ok: results.every((result) => result.ok));
      if (!mounted) return;
      final made = results.where((r) => r.ok && r.pdf != null).firstOrNull;
      setState(() {
        final now = _open.indexWhere((group) => group.id == groupId);
        if (now < 0) return;
        _open[now] = _open[now].replacing(
          made == null ? pane.idle() : pane.refreshed(pages: made.pages),
        );
      });
      await _preview?.refreshExisting();
    } catch (error) {
      console.finish(failure: error);
      if (!mounted) return;
      setState(() {
        final now = _open.indexWhere((group) => group.id == groupId);
        if (now >= 0) _open[now] = _open[now].replacing(pane.idle());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _external(
    Session session,
    String path, {
    required bool reveal,
  }) async {
    final compiler = session.compiler(
      repo: session.documentIn(courseId, year, documentId)?.repo,
    );
    if (compiler == null) return;
    try {
      reveal ? await compiler.reveal(path) : await compiler.open(path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final course = session.courseById(courseId);
    final document = session.documentIn(courseId, year, documentId);

    if (course == null || document == null) {
      return _Missing(courseId: courseId, year: year, documentId: documentId);
    }

    final profiles = _profilesFor(document, session);
    final language = document.language;

    return Column(
      children: [
        PageHeader(
          title: document.title(language),
          subtitle:
              '${document.id} · ${kindName(document.kind)} · '
              'idioma $language',
          breadcrumbs: [
            ('Asignaturas', Routes.courses()),
            (course.title(language), Routes.year(courseId, year)),
            (year, Routes.year(courseId, year)),
          ],
          actions: [
            // De qué asignatura es, a qué temas pertenece --que puede
            // declararlos otro repositorio-- y qué versiones congeladas hay
            // de su curso. Lo último estaba sólo en Asignaturas, que es donde
            // no estás cuando te lo preguntas.
            InfoMenu(
              session: session,
              // Los sitios donde se da **este mismo tema**: vinculado en dos
              // grupos son dos, no uno, y es lo que hay que ver antes de
              // tocarlo. Sin vincular, el suyo.
              places: () {
                final linked = placementsOf(session, document);
                if (linked.isEmpty) {
                  return [InfoPlace(course: courseId, year: year)];
                }
                return [
                  for (final place in linked)
                    InfoPlace(
                      course: place.course,
                      year: place.year,
                      document: place.document,
                    ),
                ];
              }(),
              placesLabel: 'Se da en',
              belongsTo: document.themes,
              belongsToLabel: 'Pertenece a',
              splitLabel: 'Gestionar vinculación…',
              onSplit:
                  !session.isFrozen &&
                      document.isLinked &&
                      session.canWriteIn(document.repo)
                  ? () => splitDocumentLinks(context, session, document)
                  : null,
            ),
            // A toggle rather than a separate route: it is the same document,
            // and the URL of a document should not depend on whether someone
            // happens to be rearranging it.
            IconButton(
              key: const Key('toggle-composition-editor'),
              tooltip: _editing
                  ? 'Dejar de editar la composición'
                  : 'Editar la composición',
              isSelected: _editing,
              icon: const Icon(Icons.reorder, size: 18),
              selectedIcon: const Icon(Icons.reorder, size: 18),
              onPressed: () => setState(() => _editing = !_editing),
            ),
            IconButton(
              tooltip: 'Copiar el comando para compilarlo',
              icon: const Icon(Icons.terminal_outlined, size: 18),
              onPressed: () {
                final command = 'didacta build $documentId';
                Clipboard.setData(ClipboardData(text: command));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Copiado: $command')));
              },
            ),
          ],
        ),
        _TabBar(
          active: _active,
          units: document.unitRefs.length,
          gaps: _gaps(session, document).length,
          open: _open,
          onSelect: (code) => setState(() => _active = code),
          onClose: _closePdf,
        ),
        Expanded(child: _panel(session, course, document, profiles, language)),
      ],
    );
  }

  /// Lo que se ve debajo de las pestañas.
  /// Qué lecciones de este tema tienen algún idioma sin traducir.
  ///
  /// Sobre los idiomas de la **asignatura** y no los del espacio de trabajo:
  /// un tema que solo se da en castellano y valenciano no tiene un hueco en
  /// inglés, tiene un idioma que no se usa.
  List<TranslationGap> _gaps(Session session, Document document) {
    final languages = session.languagesIn(widget.courseId);
    return gapsIn(
      document: document,
      catalogue: session.catalogue,
      languages: languages,
    );
  }

  Widget _panel(
    Session session,
    Course course,
    Document document,
    List<OutputTemplate> profiles,
    String language,
  ) {
    if (_active.startsWith(documentPdfPrefix)) {
      final id = _active.substring(documentPdfPrefix.length);
      final group = _open.where((group) => group.id == id).firstOrNull;
      if (group == null) return const SizedBox.shrink();
      return PdfTabView(
        group: group,
        onOpenExternally: (path) => _external(session, path, reveal: false),
        onReveal: (path) => _external(session, path, reveal: true),
        onRecompile: () =>
            _recompilePane(session, id, group.panes.first.language),
        onRecompilePane: (code) => _recompilePane(session, id, code),
        onDetach: (code) => _detach(id, code),
      );
    }

    if (_active == sourceTab) {
      return SourceTab(
        key: ValueKey('fuente-$courseId-$year-$documentId-$language'),
        courseId: courseId,
        year: year,
        document: document,
        session: session,
        language: language,
      );
    }

    if (_active == translateTab) {
      return TranslateTab(
        session: session,
        gaps: _gaps(session, document),
        language: language,
      );
    }

    if (_active == historyTab) {
      return HistoryTab(
        state: _history ??= HistoryState(
          session: session,
          repo: document.repo,
          path: 'courses/$courseId/$year/year.yaml',
        ),
      );
    }

    if (_active == buildTab) {
      return UnitPreview(
        onOpen: _openPdf,
        state: _preview ??= PreviewState(
          // El tema entero, no sus lecciones sueltas: con su portada, su
          // orden y sus referencias cruzadas, que es lo que se proyecta en
          // clase y lo que una lección compilada por su cuenta no dice.
          target: DocumentTarget(
            courseId: courseId,
            year: year,
            documentId: documentId,
            language: language,
            document: document,
          ),
          session: session,
          onChanged: () {
            if (mounted) setState(() {});
          },
          onCompiled: _openResults,
        ),
        onExternal: (path, {required bool reveal}) =>
            _external(session, path, reveal: reveal),
      );
    }

    final Widget composition = _editing
        ? CompositionEditor(
            key: ValueKey('edit-$courseId-$year-$documentId'),
            courseId: courseId,
            year: year,
            documentId: documentId,
            session: session,
          )
        : _Composition(
            document: document,
            session: session,
            language: language,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1000) {
          return Row(
            children: [
              Expanded(child: composition),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 320,
                child: _OutputsPanel(
                  document: document,
                  profiles: profiles,
                  language: language,
                  onChoose: session.canWriteIn(document.repo)
                      ? () => _chooseTemplates(session, document)
                      : null,
                ),
              ),
            ],
          );
        }
        // Narrow: two panels, one at a time. The previous version stacked
        // them in a scroll view, which nested one list inside another --
        // unbounded height, so the whole screen rendered nothing on a phone.
        return _NarrowPanels(
          composition: composition,
          outputs: _OutputsPanel(
            document: document,
            profiles: profiles,
            language: language,
            onChoose: session.canWriteIn(document.repo)
                ? () => _chooseTemplates(session, document)
                : null,
          ),
          outputCount: profiles.length,
          unitCount: document.unitRefs.length,
        );
      },
    );
  }

  /// En qué plantillas se compila este tema.
  ///
  /// Lo decide el catálogo: lo que el documento declare, y si no declara
  /// nada, lo que digan los bloques de las lecciones que compone. Aquí había
  /// una tabla por tipo de documento --copia de la que tenía el motor-- y las
  /// dos tenían que decir lo mismo para siempre; ahora lo decide quien lo
  /// configuró.
  List<OutputTemplate> _profilesFor(Document document, Session session) => [
    for (final id in session.catalogue.templatesForDocument(document))
      session.catalogue.templateNamed(id),
  ];

  /// Cambiar con qué se compila este tema.
  Future<void> _chooseTemplates(Session session, Document document) async {
    final catalogue = session.catalogue;
    final inherited = <String>{};
    for (final block in catalogue.blocksOf(document)) {
      inherited.addAll(catalogue.templatesOfBlock(block));
    }
    final chosen = await chooseTemplates(
      context,
      session,
      title: 'Salidas de «${document.title(document.language)}»',
      inherited: inherited.isEmpty
          ? 'Las de los bloques de sus lecciones. Todavía no lleva ninguna, '
                'así que salen todas las encendidas.'
          : 'Las de los bloques de sus lecciones: ${inherited.length}',
      chosen: document.profiles,
      byDefault: catalogue.templatesForDocument(document),
    );
    if (chosen == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.setDocumentTemplates(
        repo: document.repo,
        course: courseId,
        year: year,
        id: document.id,
        templates: chosen,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            chosen.isEmpty
                ? 'Este tema vuelve a compilar lo que digan sus bloques.'
                : 'Guardado: ${chosen.length} salida(s).',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

/// Las pestañas del tema: su composición, compilarlo, y lo compilado.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.active,
    required this.units,
    required this.gaps,
    required this.open,
    required this.onSelect,
    required this.onClose,
  });

  final String active;
  final int units;

  /// Cuántas lecciones de este tema tienen algún idioma sin traducir. Cero
  /// quita la pestaña: no hay nada que enseñar en ella.
  final int gaps;
  final List<PdfGroup> open;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        DidactaTab(
          label: 'Composición ($units)',
          selected: active == compositionTab,
          dirty: false,
          onTap: () => onSelect(compositionTab),
        ),
        DidactaTab(
          label: 'Fuente',
          icon: Icons.notes_outlined,
          selected: active == sourceTab,
          dirty: false,
          onTap: () => onSelect(sourceTab),
        ),
        DidactaTab(
          label: 'Compilar',
          icon: Icons.play_arrow_outlined,
          selected: active == buildTab,
          dirty: false,
          onTap: () => onSelect(buildTab),
        ),
        if (gaps > 0)
          DidactaTab(
            label: 'Traducir ($gaps)',
            icon: Icons.auto_awesome_outlined,
            selected: active == translateTab,
            dirty: false,
            onTap: () => onSelect(translateTab),
          ),
        DidactaTab(
          label: 'Historial',
          icon: Icons.history,
          selected: active == historyTab,
          dirty: false,
          onTap: () => onSelect(historyTab),
        ),
        for (final group in open)
          DidactaTab(
            label: group.label,
            icon: Icons.picture_as_pdf_outlined,
            selected: active == '$documentPdfPrefix${group.id}',
            dirty: false,
            onTap: () => onSelect('$documentPdfPrefix${group.id}'),
            onClose: () => onClose(group.id),
          ),
      ],
    ),
  );
}

class _Composition extends StatelessWidget {
  const _Composition({
    required this.document,
    required this.session,
    required this.language,
  });

  final Document document;
  final Session session;
  final String language;

  @override
  Widget build(BuildContext context) {
    if (document.unitRefs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Note(
            'Esta composición está vacía: no referencia ninguna unidad. En el '
            'material migrado suele significar que el master antiguo apuntaba '
            'a ficheros que no llegaron.',
            tone: didactaEx,
          ),
        ),
      );
    }

    // Por apartados, en tarjetas. Una lista plana de cuarenta y dos filas
    // dice lo que hay; no dice dónde termina un bloque y empieza otro, que
    // es lo primero que se mira al preparar una clase.
    final parts = document.structure;
    if (parts.isEmpty) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: document.unitRefs.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final reference = document.unitRefs[index];
          return _CompositionRow(
            position: index + 1,
            reference: reference,
            unit: session.catalogue.unitByReference(reference),
            language: language,
          );
        },
      );
    }

    // Lo que va antes del primer apartado --si va algo-- en una tarjeta sin
    // título: el documento puede empezar sin apartado, y esconderlo sería
    // perderlo.
    final cards = <({CompositionPart? heading, List<CompositionPart> items})>[];
    for (final part in parts) {
      if (part.isHeading) {
        cards.add((heading: part, items: []));
      } else {
        if (cards.isEmpty) cards.add((heading: null, items: []));
        cards.last.items.add(part);
      }
    }

    var position = 0;
    final numbered = <CompositionPart, int>{};
    for (final part in parts) {
      if (!part.isHeading) numbered[part] = ++position;
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      itemCount: cards.length,
      itemBuilder: (context, index) => _SectionCard(
        heading: cards[index].heading,
        items: cards[index].items,
        numbers: numbered,
        session: session,
        language: language,
      ),
    );
  }
}

/// Un apartado y lo que lleva dentro.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.heading,
    required this.items,
    required this.numbers,
    required this.session,
    required this.language,
  });

  final CompositionPart? heading;
  final List<CompositionPart> items;
  final Map<CompositionPart, int> numbers;
  final Session session;
  final String language;

  @override
  Widget build(BuildContext context) {
    final title = heading?.title(language) ?? '';
    final borrowed = heading?.titleIsFallback(language) ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: didactaCard,
          border: Border.all(color: didactaRule),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading != null)
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F6F1),
                  border: Border(bottom: BorderSide(color: didactaRule)),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(Radii.card),
                    topRight: Radius.circular(Radii.card),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
                child: Row(
                  children: [
                    Icon(
                      heading!.kind == 'section'
                          ? Icons.folder_outlined
                          : Icons.segment,
                      size: 15,
                      color: didactaAccentDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title.isEmpty ? 'Apartado sin título' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          // Prestado de otro idioma, marcado como en el resto
                          // de la aplicación.
                          fontStyle: borrowed ? FontStyle.italic : null,
                          color: borrowed || title.isEmpty
                              ? didactaMuted
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      '${items.length}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: didactaMuted,
                      ),
                    ),
                  ],
                ),
              ),
            for (final (at, part) in items.indexed) ...[
              if (at > 0) const Divider(height: 1),
              _CompositionRow(
                position: numbers[part] ?? at + 1,
                reference: part.reference,
                unit: session.catalogue.unitByReference(part.reference),
                language: language,
              ),
            ],
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Text(
                  'Este apartado no lleva nada todavía.',
                  style: TextStyle(fontSize: 12, color: didactaMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompositionRow extends StatelessWidget {
  const _CompositionRow({
    required this.position,
    required this.reference,
    required this.unit,
    required this.language,
  });

  final int position;
  final String reference;
  final Unit? unit;
  final String language;

  @override
  Widget build(BuildContext context) {
    if (unit == null) {
      // Shown in place, not skipped: a composition that omits what is missing
      // looks complete and compiles short.
      return Container(
        color: didactaTeacher.withValues(alpha: 0.05),
        padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
        child: Row(
          children: [
            _Position(position),
            const Icon(Icons.link_off, size: 15, color: didactaTeacher),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reference,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  color: didactaTeacher,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Text(
              'no está en el catálogo',
              style: TextStyle(fontSize: 11, color: didactaTeacher),
            ),
          ],
        ),
      );
    }

    final status = unit!.statusIn(language);
    return Hoverable(
      onTap: () => context.go(Routes.unit(unit!.path)),
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        color: hovering ? didactaHover : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
        child: Row(
          children: [
            _Position(position),
            // La barra del tipo, que crece al pasar por encima: es la
            // respuesta a «¿esta fila hace algo?» sin añadir un icono más.
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: hovering ? 4 : 3,
              height: 28,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: kindColour(unit!.kind),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Y su nombre. El color dice que dos filas son distintas; no dice
            // cuál es la explicación y cuál el ejercicio, que es la pregunta
            // que se hace mirando la composición de un tema.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: KindChip(kind: unit!.kind),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit!.title(language),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.3,
                      // En negrita frente a la ruta, que es lo que pone el
                      // título por delante: antes los dos pesaban igual y en
                      // una lista se leía primero la ruta, que es lo que
                      // menos importa.
                      fontWeight: FontWeight.w600,
                      // Italic and grey when the title shown is a fallback,
                      // so a Castilian title in a Valencian document does not
                      // read as translated.
                      fontStyle: unit!.titleIsFallback(language)
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: unit!.titleIsFallback(language)
                          ? didactaMuted
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reference,
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
            const SizedBox(width: 8),
            if (!status.exists)
              Tooltip(
                message:
                    'Sin versión en $language: se compilará con la de '
                    '${unit!.reference} y un aviso.',
                child: const Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 13,
                      color: didactaEx,
                    ),
                    SizedBox(width: 2),
                    Text(
                      'respaldo',
                      style: TextStyle(fontSize: 10.5, color: didactaEx),
                    ),
                    SizedBox(width: 8),
                  ],
                ),
              ),
            StatusBadge(language: language, status: status),
            // La flecha solo cuando el ratón está encima: dice que la fila
            // lleva a algún sitio, y no ocupa una columna cuando no hace
            // falta.
            SizedBox(
              width: 18,
              child: hovering
                  ? const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: didactaMuted,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Position extends StatelessWidget {
  const _Position(this.value);

  final int value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    child: Text(
      '$value',
      style: const TextStyle(
        fontSize: 11,
        color: didactaMuted,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// The composition and the outputs as two tabs, for a narrow screen.
class _NarrowPanels extends StatefulWidget {
  const _NarrowPanels({
    required this.composition,
    required this.outputs,
    required this.outputCount,
    required this.unitCount,
  });

  final Widget composition;
  final Widget outputs;
  final int outputCount;
  final int unitCount;

  @override
  State<_NarrowPanels> createState() => _NarrowPanelsState();
}

class _NarrowPanelsState extends State<_NarrowPanels> {
  bool _showOutputs = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: didactaPanel,
            border: Border(bottom: BorderSide(color: didactaRule)),
          ),
          child: Row(
            children: [
              _PanelTab(
                label: 'Composición (${widget.unitCount})',
                selected: !_showOutputs,
                onTap: () => setState(() => _showOutputs = false),
              ),
              _PanelTab(
                label: 'Salidas (${widget.outputCount})',
                selected: _showOutputs,
                onTap: () => setState(() => _showOutputs = true),
              ),
            ],
          ),
        ),
        // Both kept alive: switching back to the composition should not lose
        // where you had scrolled to.
        Expanded(
          child: Stack(
            children: [
              Offstage(offstage: _showOutputs, child: widget.composition),
              Offstage(offstage: !_showOutputs, child: widget.outputs),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? didactaAccentDark : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? didactaInk : didactaMuted,
        ),
      ),
    ),
  );
}

/// What this document produces.
class _OutputsPanel extends StatelessWidget {
  const _OutputsPanel({
    required this.document,
    required this.profiles,
    required this.language,
    this.onChoose,
  });

  final Document document;
  final List<OutputTemplate> profiles;
  final String language;

  /// Cambiar con qué se compila. Null cuando no se puede escribir en su
  /// repositorio: se ve lo que sale, y no se ofrece un botón que va a fallar.
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SectionLabel('Salidas (${profiles.length})'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.profiles.isEmpty
                    ? 'Este tema no elige: compila lo que digan los bloques '
                          'de las lecciones que lleva dentro.'
                    : 'Este tema elige sus salidas, en su `year.yaml`.',
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
              if (onChoose != null) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: const Key('choose-document-templates'),
                  icon: const Icon(Icons.tune, size: 15),
                  label: const Text('Elegir salidas'),
                  onPressed: onChoose,
                ),
              ],
            ],
          ),
        ),
        for (final profile in profiles)
          ListTile(
            leading: Icon(
              profile.isSlides
                  ? Icons.slideshow_outlined
                  : Icons.article_outlined,
              size: 16,
              color: profile.isSlides ? didactaThm : didactaDefn,
            ),
            title: Text(
              profile.title(language),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              '${profile.id} · ${profile.documentClass}',
              style: const TextStyle(fontSize: 11),
            ),
          ),

        const SectionLabel('Compilar'),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Note(
            'Compilar necesita LaTeX, y un navegador no lo tiene. Desde el '
            'repositorio de contenido:',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _Command('didacta build ${document.id}'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Command extends StatelessWidget {
  const _Command(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: didactaInk,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        Expanded(
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copiar',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.content_copy, size: 14, color: Colors.white70),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Copiado.')));
          },
        ),
      ],
    ),
  );
}

class _Missing extends StatelessWidget {
  const _Missing({
    required this.courseId,
    required this.year,
    required this.documentId,
  });

  final String courseId;
  final String year;
  final String documentId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Documento no encontrado',
          breadcrumbs: [('Asignaturas', Routes.courses())],
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                    '$courseId / $year / $documentId',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(Routes.courses()),
                    child: const Text('Ver las asignaturas'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
