/// El documento entero, en fuente, con los cortes a la vista y editable.
///
/// No es una previsualización del PDF: es el LaTeX de la composición y de sus
/// unidades puesto en fila, con **dónde empieza y acaba cada entorno** pintado
/// en el margen. Contesta lo que un PDF no puede contestar —dónde cae el corte
/// de cada diapositiva y qué queda dentro— y lo hace sin compilar, así que
/// también sirve con traducciones a medias.
///
/// Y no contesta lo que sí contesta un PDF: si el contenido **cabe** en la
/// diapositiva. Eso solo lo sabe el compilador, y para eso está la pestaña de
/// al lado.
///
/// Las decisiones que la sostienen:
///
/// **Una columna por entorno abierto**, con el color que ese entorno tiene en
/// el PDF (`didacta-colours.sty`). Una diapositiva es lo más externo que se
/// escribe, así que su columna es la primera. Y el mismo color, dentro del
/// texto, en el `\begin` y el `\end` de cada entorno.
///
/// **Lo que no se proyecta, en gris.** Es la regla entera de un perfil de
/// diapositivas dicha en un color. Se apaga cuando el documento no tiene
/// ninguna, porque entonces gris sería todo y no diría nada.
///
/// **Se edita aquí, y sin modo.** Cada fragmento es una caja de texto desde
/// que se abre la pantalla: pulsar una línea pone el cursor y se escribe, y no
/// pasa nada más —nada se recompone, nada se mueve—. Hubo un modo edición y
/// era peor de lo que parecía: cambiar de mirar a escribir movía la lista
/// entera bajo el ratón, así que el sitio donde ibas a escribir ya no estaba
/// donde lo habías pulsado.
///
/// **La barra de entornos, arriba y fija**, sobre el documento y no sobre el
/// fragmento: dentro empujaba el texto hacia abajo al aparecer, que es la
/// misma clase de estorbo. Actúa sobre el fichero que tenga el cursor.
///
/// **Un fragmento es un fichero.** Con sus pestañas de idioma y su propio
/// deshacer. Guardar es un commit con varios ficheros dentro, y los `sha` se
/// comprueban **todos antes** de escribir ninguno.
///
/// **Lo que no es texto de un fichero, no se teclea.** El título de un
/// apartado vive en `year.yaml` en los tres idiomas (D23): aquí es una ficha
/// con un lápiz que abre el diálogo de los tres. Tecleado en el sitio se
/// escribiría en uno solo, que es la cabecera en castellano sobre contenido en
/// valenciano que D14 existe para evitar.
///
/// **Los avisos no bloquean.** Un `\begin{frame}` sin cerrar se pinta en rojo
/// donde está, y arriba se dice el fichero y la línea de ese fichero: LaTeX,
/// ante lo mismo, denuncia la línea de la composición que incluye la unidad y
/// saca un PDF de una página que parece correcto.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/content_gateway.dart';
import '../model/catalogue.dart';
import '../model/composition_file.dart';
import '../model/document_reading.dart';
import '../model/line_diff.dart';
import '../model/source_drafts.dart';
import '../model/tex_outline.dart';
import '../state/session.dart';
import 'heading_title.dart';
import 'problem.dart';
import 'tex_field.dart';
import 'tex_highlight.dart';
import 'tex_toolbar.dart';
import 'theme.dart';
import 'save_review.dart';
import '../l10n/tr.dart';

class SourceTab extends StatefulWidget {
  const SourceTab({
    super.key,
    required this.courseId,
    required this.year,
    required this.document,
    required this.session,
    required this.language,
  });

  final String courseId;
  final String year;
  final Document document;
  final Session session;

  /// El idioma del documento: el que se pide, no el que se acaba leyendo.
  final String language;

  /// Dónde vive la composición de este año.
  String get yearPath => 'courses/$courseId/$year/year.yaml';

  @override
  State<SourceTab> createState() => _SourceTabState();
}

class _SourceTabState extends State<SourceTab> {
  DocumentReading? _reading;
  Object? _error;

  /// Un borrador por fichero abierto, aunque no se esté viendo.
  final SourceDrafts _drafts = SourceDrafts();

  /// Qué idioma se está viendo de cada referencia de la composición.
  final Map<String, String> _language = {};

  /// El idioma en el que se está mirando el documento entero.
  ///
  /// Distinto del de cada fragmento: este es el del documento —lo que se
  /// compilaría— y cambiarlo vuelve a elegir idioma en **todas** las unidades,
  /// con la misma caída que hace el motor. El de un fragmento es una excepción
  /// para esa unidad, que es lo que permite mirar una traducción sin cambiar
  /// de pantalla.
  late String _viewLanguage = widget.language;

  /// El fichero que tiene el cursor: sobre ese actúa la barra de arriba.
  String? _focused;

  final Map<String, TexEditingController> _controllers = {};
  final Map<String, FocusNode> _focus = {};

  /// Para la barra cuando no hay ningún cursor puesto. Apagada, pero en su
  /// sitio: una barra que aparece y desaparece mueve la pantalla entera.
  final TextEditingController _idle = TextEditingController();

  TexOutline _outline = TexOutline.of(const []);
  List<_Row> _rows = const [];

  bool _dim = false;
  bool _saving = false;
  List<String> _conflicts = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    _idle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final reading = await readDocument(
        document: widget.document,
        catalogue: widget.session.catalogue,
        language: _viewLanguage,
        read: (unit, code) async {
          final file = await widget.session
              .gatewayFor(unit.repo)
              .read(unit.fileFor(code));
          return (text: file.text, sha: file.sha);
        },
      );
      if (!mounted) return;
      for (final file in reading.files) {
        _language[file.reference] = file.language;
        if (!_drafts.has(file.path)) {
          _drafts.put(
            SourceDraft(
              path: file.path,
              loaded: file.text,
              sha: file.sha,
              exists: true,
            ),
          );
        }
      }
      setState(() {
        _reading = reading;
        _dim = false;
        _rebuild();
        _dim = _outline.slideCount > 0;
      });
    } catch (thrown) {
      if (!mounted) return;
      setState(() => _error = thrown);
    }
  }

  // -- el texto de ahora mismo -------------------------------------------

  /// La pasarela de un fichero, por la unidad de la que salió.
  ///
  /// Un fragmento es un fichero de un repositorio concreto, y con varios
  /// abiertos escribir en «el repositorio» no significa nada: hay que saber
  /// en cuál.
  ContentGateway _gatewayForPath(String path) {
    for (final piece in _reading?.pieces ?? const <ReadingPiece>[]) {
      if (piece is ReadingFile && path.startsWith('${piece.unit.path}/')) {
        return widget.session.gatewayFor(piece.unit.repo);
      }
    }
    return widget.session.gatewayFor(widget.document.repo);
  }

  /// La ruta que se está viendo de una referencia.
  String _pathOf(ReadingFile file) {
    final language = _language[file.reference] ?? file.language;
    return '${file.unit.path}/$language.tex';
  }

  List<TexSource> _sourcesNow() => [
    for (final piece in _reading?.pieces ?? const <ReadingPiece>[])
      if (piece is ReadingFile)
        TexSource(
          id: _pathOf(piece),
          label: piece.reference,
          text: _drafts.of(_pathOf(piece))?.text ?? '',
          language: _language[piece.reference] ?? piece.language,
          kind: piece.unit.isProblem
              ? TexSourceKind.problem
              : TexSourceKind.unit,
        ),
  ];

  /// Vuelve a leer el texto de todos los fragmentos y rehace el árbol.
  ///
  /// En cada tecla, sin retraso. Se midió antes de decidirlo: 2,15 ms con 120
  /// unidades (68 KB), más de lo que es un tema de verdad. Y hace falta que
  /// sea así: las columnas de colores del fragmento que se está escribiendo
  /// salen de este árbol, y unas guías que van tres décimas por detrás del
  /// texto son peores que no tenerlas.
  void _rebuild() {
    _outline = TexOutline.of(_sourcesNow());
    _rows = _buildRows();
  }

  void _afterEdit() => setState(_rebuild);

  List<_Row> _buildRows() {
    final rows = <_Row>[];
    var next = 0;
    for (final piece in _reading?.pieces ?? const <ReadingPiece>[]) {
      switch (piece) {
        case ReadingHeading():
          rows.add(_HeadingRow(piece));
        case ReadingGap():
          rows.add(_GapRow(piece));
        case ReadingFile():
          final path = _pathOf(piece);
          final slice = next < _outline.slices.length
              ? _outline.slices[next]
              : null;
          next += 1;
          rows.add(_FileRow(piece, path, slice));
      }
    }
    return rows;
  }

  // -- editar -------------------------------------------------------------

  TexEditingController _controllerFor(String path) {
    final existing = _controllers[path];
    if (existing != null) return existing;
    final draft = _drafts.of(path);
    final created = TexEditingController()..text = draft?.text ?? '';
    created.addListener(() {
      final draft = _drafts.of(path);
      if (draft == null || draft.text == created.text) return;
      draft.text = created.text;
      _afterEdit();
    });
    _controllers[path] = created;
    return created;
  }

  FocusNode _focusFor(String path) {
    final existing = _focus[path];
    if (existing != null) return existing;
    final created = FocusNode(debugLabel: path);
    // Solo al **ganar** el foco, nunca al perderlo. Al perderlo también se
    // apagaba la barra, y eso la dejaba inservible: pulsar uno de sus botones
    // le quita el foco al campo, así que entre que se aprieta y se suelta el
    // botón ya estaba gris y el clic no hacía nada. Lo que la barra necesita
    // saber es sobre qué fichero actuar, y eso sigue siendo cierto mientras
    // no se ponga el cursor en otro.
    created.addListener(() {
      if (!mounted) return;
      if (created.hasFocus && _focused != path) {
        setState(() => _focused = path);
      }
    });
    _focus[path] = created;
    return created;
  }

  /// Cambia el idioma del documento entero.
  ///
  /// Vuelve a elegir idioma en cada unidad con la caída del motor: la que no
  /// esté traducida se sigue viendo en el suyo y lo dice, en lugar de dejar un
  /// hueco. Lo que estuviera sin guardar en otro idioma sigue sin guardarse y
  /// sigue contando: los borradores son por fichero, no por pantalla.
  Future<void> _switchDocument(String language) async {
    final reading = _reading;
    if (reading == null || language == _viewLanguage) return;

    for (final file in reading.files) {
      final chosen = languageForUnit(file.unit, language) ?? file.language;
      await _draftFor(file.unit, chosen);
      _language[file.reference] = chosen;
    }
    if (!mounted) return;
    setState(() {
      _viewLanguage = language;
      _rebuild();
    });
  }

  /// Se asegura de tener el borrador de un fichero, leyéndolo si hace falta.
  Future<void> _draftFor(Unit unit, String language) async {
    final path = '${unit.path}/$language.tex';
    if (_drafts.has(path)) return;
    if (!unit.statusIn(language).exists) {
      // Vacío, y no con el original debajo: ver otro idioma en la pestaña de
      // este se lee como «ya está traducido», y un descuido al guardar lo
      // archiva como si lo estuviera.
      _drafts.put(SourceDraft(path: path, loaded: '', sha: '', exists: false));
      return;
    }
    try {
      final loaded = await widget.session.gatewayFor(unit.repo).read(path);
      _drafts.put(
        SourceDraft(
          path: path,
          loaded: loaded.text,
          sha: loaded.sha,
          exists: true,
        ),
      );
    } catch (thrown) {
      if (!mounted) return;
      showProblem(context, thrown);
    }
  }

  /// Cambia de idioma un fragmento, cargando el fichero que toque.
  Future<void> _switchLanguage(ReadingFile file, String language) async {
    await _draftFor(file.unit, language);
    if (!mounted) return;
    setState(() {
      _language[file.reference] = language;
      _rebuild();
    });
  }

  // -- guardar ------------------------------------------------------------

  void _discard() {
    for (final draft in _drafts.dirty) {
      draft.text = draft.loaded;
      _controllers[draft.path]?.text = draft.loaded;
    }
    setState(() {
      _conflicts = const [];
      _rebuild();
    });
  }

  Future<void> _save() async {
    final touched = _drafts.dirty;
    if (touched.isEmpty) return;

    final suggested = _drafts.suggestedMessage(
      widget.document.title(_viewLanguage),
    );
    final message = await askSaveMessage(
      context,
      widget.session,
      suggested: suggested,
      dialog: (context) => _SaveDialog(drafts: touched, suggested: suggested),
    );
    if (message == null || !mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);

    setState(() {
      _saving = true;
      _conflicts = const [];
    });

    try {
      // Todos los `sha` antes de escribir ninguno: un conflicto en el tercer
      // fichero no puede dejar los dos primeros escritos.
      final current = <String, String>{};
      for (final draft in touched) {
        try {
          final now = await _gatewayForPath(draft.path).read(draft.path);
          current[draft.path] = now.sha;
        } on ContentException catch (thrown) {
          if (thrown.kind != ContentFailure.missing) rethrow;
        }
      }
      final clashes = _drafts.conflicts(current);
      if (clashes.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _conflicts = clashes;
        });
        return;
      }

      for (final draft in touched) {
        final sha = await _gatewayForPath(draft.path).save(
          path: draft.path,
          text: draft.text,
          sha: draft.sha,
          message: message,
        );
        _drafts.put(draft.saved(text: draft.text, sha: sha));
      }

      if (!mounted) return;
      setState(() {
        _saving = false;
        _rebuild();
      });
      final only = touched.length == 1 ? touched.single : null;
      ScaffoldMessenger.of(context).showSnackBar(
        only == null
            ? SnackBar(
                content: Text(
                  widget.session.saveNotice(
                    widget.document.repo,
                    files: touched.length,
                  ),
                ),
              )
            : savedNotice(
                notice: widget.session.saveNotice(widget.document.repo),
                message: message,
                before: only.loaded,
                after: only.text,
                what: only.path,
                navigator: navigator,
              ),
      );
      await widget.session.reloadCatalogue();
    } catch (thrown) {
      if (!mounted) return;
      setState(() => _saving = false);
      showProblem(context, thrown);
    }
  }

  // -- los apartados ------------------------------------------------------

  /// Edita el título de un apartado en los tres idiomas, en `year.yaml`.
  ///
  /// Por el mismo modelo que el editor de composiciones —se reescribe la
  /// línea, no se reserializa el fichero— para no borrar los `# TODO: va` ni
  /// las entradas comentadas (D40, D41).
  Future<void> _editHeading(ReadingHeading heading) async {
    final languages = widget.session.languagesToEditCodes(
      allowed: widget.session.languagesIn(widget.courseId),
      declared: heading.titles.keys.toList(),
    );
    final titles = await editHeadingTitles(
      context,
      heading: heading.kind == 'section' ? tr('Apartado') : tr('Subapartado'),
      languages: languages,
      titles: heading.titles,
      reference: _viewLanguage,
    );
    if (titles == null || !mounted) return;

    try {
      final file = await widget.session
          .gatewayFor(widget.document.repo)
          .read(widget.yearPath);
      final composition = CompositionFile(file.text);
      final block = composition.blockFor(widget.document.id);
      if (block == null) {
        throw CompositionException(
          tr('este documento no tiene composición en year.yaml'),
        );
      }

      // La estructura del catálogo son las entradas **activas**: las
      // comentadas no llegan al índice. Así que se cuenta sobre las activas y,
      // si lo que hay en esa posición no es el apartado que se estaba
      // editando, se rechaza en lugar de adivinar.
      final entries = block.entries;
      final activeIndexes = [
        for (final (index, entry) in entries.indexed)
          if (entry.enabled) index,
      ];
      if (heading.partIndex >= activeIndexes.length) {
        throw CompositionException(
          tr('no se ha encontrado el apartado en year.yaml'),
        );
      }
      final at = activeIndexes[heading.partIndex];
      final entry = entries[at];
      if (entry.kind != EntryKind.section &&
          entry.kind != EntryKind.subsection) {
        throw CompositionException(
          tr('la entrada de year.yaml no es un apartado'),
        );
      }

      var updated = entry;
      for (final language in languages) {
        final text = titles[language] ?? '';
        if (text.isEmpty) continue;
        updated = updated.withTitle(language, text);
      }
      final now = [...entries]..[at] = updated;
      composition.setStructure(widget.document.id, now);

      await widget.session
          .gatewayFor(widget.document.repo)
          .save(
            path: widget.yearPath,
            text: composition.text,
            sha: file.sha,
            message: tr('Retitular un apartado de {0}', [widget.document.id]),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Guardado en el historial.'))));
      await widget.session.reloadCatalogue();
    } catch (thrown) {
      if (!mounted) return;
      showProblem(context, thrown);
    }
  }

  // -- pintar -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('No se ha podido leer el documento:\n\n{0}', [_error]),
            style: TextStyle(color: context.palette.teacher),
          ),
        ),
      );
    }
    final reading = _reading;
    if (reading == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final canWrite = widget.session.canWriteIn(widget.document.repo);
    final focused = _focused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          reading: reading,
          outline: _outline,
          languages: widget.session.languagesIn(widget.courseId),
          language: _viewLanguage,
          onLanguage: _switchDocument,
          dim: _dim,
          canDim: _outline.slideCount > 0,
          onDim: (value) => setState(() => _dim = value),
          dirty: _drafts.dirty.length,
          saving: _saving,
          canSave: canWrite && _drafts.isDirty && !_saving,
          onSave: _save,
          onDiscard: _drafts.isDirty && !_saving ? _discard : null,
        ),
        // Arriba del todo y siempre en el mismo sitio: dentro del fragmento
        // empujaba el texto al aparecer, y lo que se estaba mirando se movía.
        TexToolbar(
          controller: focused == null ? _idle : _controllerFor(focused),
          focusNode: focused == null ? null : _focusFor(focused),
          enabled: canWrite && focused != null,
          repo: widget.document.repo,
        ),
        if (_conflicts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Note(
              tr(
                'Han cambiado en el repositorio desde que los abriste: '
                '{0}. No se ha escrito nada. Vuelve a '
                'abrir el documento; lo que has escrito sigue aquí mientras '
                'decides.',
                [_conflicts.join(', ')],
              ),
              tone: context.palette.teacher,
            ),
          ),
        if (_outline.issues.isNotEmpty) _IssueBanner(issues: _outline.issues),
        Expanded(
          child: Container(
            color: context.palette.card,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 40),
              itemCount: _rows.length,
              itemBuilder: (context, index) => switch (_rows[index]) {
                _HeadingRow(:final heading) => _Heading(
                  heading: heading,
                  language: _viewLanguage,
                  onEdit: canWrite ? () => _editHeading(heading) : null,
                ),
                _GapRow(:final gap) => _Gap(gap: gap),
                _FileRow(:final file, :final path, :final slice) => _Fragment(
                  file: file,
                  path: path,
                  controller: _controllerFor(path)
                    ..inDocument(outline: _outline, slice: slice, dim: _dim),
                  focusNode: _focusFor(path),
                  canWrite: canWrite,
                  exists: _drafts.of(path)?.exists ?? true,
                  languages: widget.session.languagesIn(widget.courseId),
                  language: _language[file.reference] ?? file.language,
                  dirty: _drafts.of(path)?.isDirty ?? false,
                  existsIn: {
                    for (final code in widget.session.languagesIn(
                      widget.courseId,
                    ))
                      code:
                          _drafts.of('${file.unit.path}/$code.tex')?.exists ??
                          file.unit.statusIn(code).exists,
                  },
                  dirtyLanguages: {
                    for (final code in widget.session.languagesIn(
                      widget.courseId,
                    ))
                      if (_drafts.of('${file.unit.path}/$code.tex')?.isDirty ??
                          false)
                        code,
                  },
                  onLanguage: (code) => _switchLanguage(file, code),
                ),
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Las filas
// ---------------------------------------------------------------------------

sealed class _Row {
  const _Row();
}

class _HeadingRow extends _Row {
  const _HeadingRow(this.heading);
  final ReadingHeading heading;
}

class _FileRow extends _Row {
  const _FileRow(this.file, this.path, this.slice);
  final ReadingFile file;
  final String path;
  final TexSlice? slice;
}

class _GapRow extends _Row {
  const _GapRow(this.gap);
  final ReadingGap gap;
}

// ---------------------------------------------------------------------------
// Las piezas
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.reading,
    required this.outline,
    required this.languages,
    required this.language,
    required this.onLanguage,
    required this.dim,
    required this.canDim,
    required this.onDim,
    required this.dirty,
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.onDiscard,
  });

  final DocumentReading reading;
  final TexOutline outline;

  /// El idioma del documento, y los que el repositorio tiene.
  final List<String> languages;
  final String language;
  final ValueChanged<String> onLanguage;

  final bool dim;
  final bool canDim;
  final ValueChanged<bool> onDim;
  final int dirty;
  final bool saving;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // El idioma del documento, a la izquierda del todo: es lo primero
          // que se decide al mirar un tema --«¿esto en valenciano cómo va?»--
          // y cambia lo que se ve en todos los fragmentos a la vez.
          Text(
            tr('Idioma'),
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
          ),
          const SizedBox(width: 6),
          for (final code in languages)
            _DocumentLanguage(
              code: code,
              selected: code == language,
              onTap: () => onLanguage(code),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              [
                reading.files.length == 1
                    ? tr('1 fichero')
                    : tr('{0} ficheros', [reading.files.length]),
                if (outline.slideCount > 0)
                  outline.slideCount == 1
                      ? tr('1 diapositiva')
                      : tr('{0} diapositivas', [outline.slideCount]),
                if (outline.issues.isNotEmpty)
                  outline.issues.length == 1
                      ? tr('1 aviso')
                      : tr('{0} avisos', [outline.issues.length]),
                if (dirty > 0)
                  dirty == 1
                      ? tr('1 fichero tocado')
                      : tr('{0} ficheros tocados', [dirty]),
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
          ),
          if (canDim) ...[
            // «Lo que no se proyecta, en gris» es una lectura del documento,
            // no una propiedad suya: en unos apuntes no significa nada.
            Text(
              tr('Marcar lo que no se proyecta'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
            const SizedBox(width: 6),
            Switch(key: const Key('source-dim'), value: dim, onChanged: onDim),
            const SizedBox(width: 10),
          ],
          if (onDiscard != null)
            TextButton(
              key: const Key('source-discard'),
              onPressed: onDiscard,
              child: Text(tr('Descartar')),
            ),
          const SizedBox(width: 4),
          FilledButton.icon(
            key: const Key('source-save'),
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
      ),
    );
  }
}

/// El idioma del documento entero.
class _DocumentLanguage extends StatelessWidget {
  const _DocumentLanguage({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('source-document-language-$code'),
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? context.palette.accentDark.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: selected
              ? context.palette.accentDark.withValues(alpha: 0.4)
              : context.palette.rule,
        ),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? context.palette.accentDark : context.palette.muted,
        ),
      ),
    ),
  );
}

class _IssueBanner extends StatelessWidget {
  const _IssueBanner({required this.issues});

  final List<TexIssue> issues;

  @override
  Widget build(BuildContext context) {
    final shown = issues.take(4).toList();
    return Container(
      width: double.infinity,
      color: context.palette.teacher.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final issue in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                // El fichero y la línea de *ese* fichero: es lo que LaTeX no
                // sabe decir y lo único que sirve para ir a arreglarlo.
                '${issue.message} — ${issue.sourceId}:${issue.lineInSource}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: context.palette.teacher,
                ),
              ),
            ),
          if (issues.length > shown.length)
            Text(
              tr('y {0} más', [issues.length - shown.length]),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.heading,
    required this.language,
    required this.onEdit,
  });

  final ReadingHeading heading;
  final String language;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final subsection = heading.kind == 'subsection';
    return Padding(
      padding: EdgeInsets.fromLTRB(subsection ? 28 : 12, 18, 12, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              heading.title(language),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: subsection ? 13 : 15,
                fontWeight: FontWeight.w700,
                color: context.palette.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const _Tag('apartado'),
          if (onEdit != null)
            IconButton(
              key: Key('source-heading-${heading.partIndex}'),
              tooltip: tr('Editar el título en todos los idiomas'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 15),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.colour});

  final String text;

  /// Sin él, el gris del texto secundario.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final tint = colour ?? context.palette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: tint,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Un fichero: su línea de puntos y su texto, editable desde el principio.
///
/// Sin modo: la caja está ahí desde que se abre la pantalla, así que pulsar
/// una línea pone el cursor y se escribe. Lo que antes era «entrar a editar»
/// recomponía la lista debajo del ratón, y el sitio que habías pulsado ya no
/// estaba donde lo pulsaste.
///
/// Las pestañas de idioma están en su línea de puntos porque el idioma es una
/// propiedad de **este** trozo, no de la pantalla: en una hoja bilingüe
/// conviven, y cambiar uno de arriba cambiaría también los demás.
class _Fragment extends StatelessWidget {
  const _Fragment({
    required this.file,
    required this.path,
    required this.controller,
    required this.focusNode,
    required this.canWrite,
    required this.exists,
    required this.languages,
    required this.language,
    required this.dirty,
    required this.existsIn,
    required this.dirtyLanguages,
    required this.onLanguage,
  });

  final ReadingFile file;
  final String path;
  final TexEditingController controller;
  final FocusNode focusNode;
  final bool canWrite;

  /// Falso cuando el fichero todavía no existe: escribir aquí lo crea.
  final bool exists;

  final List<String> languages;
  final String language;
  final bool dirty;
  final Map<String, bool> existsIn;
  final Set<String> dirtyLanguages;
  final ValueChanged<String> onLanguage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _break(context),
        if (!exists)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Note(
              tr(
                'No existe la versión en {0} de esta unidad. Lo que se '
                'escriba aquí la crea, y hasta entonces ningún documento que la '
                'use se puede compilar en {1}.',
                [language, language],
              ),
              tone: context.palette.teacher,
            ),
          ),
        TexField(
          key: Key('source-field-$path'),
          controller: controller,
          focusNode: focusNode,
          readOnly: !canWrite,
          hintText: tr('El fichero está vacío.'),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        ),
      ],
    );
  }

  Widget _break(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
    child: Row(
      children: [
        const _Dots(width: 14),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            path,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: dirty ? context.palette.accentDark : context.palette.muted,
              fontWeight: dirty ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        if (dirty) ...[
          const SizedBox(width: 6),
          _Tag(tr('sin guardar'), colour: context.palette.ex),
        ],
        if (file.unit.usedBy.length > 1) ...[
          const SizedBox(width: 6),
          // Editar aquí es cómodo justo porque no parece que estés abriendo un
          // fichero que usan doce documentos.
          _Tag(tr('en {0} documentos', [file.unit.usedBy.length])),
        ],
        const SizedBox(width: 8),
        for (final code in languages)
          _LanguageTab(
            code: code,
            selected: code == language,
            exists: existsIn[code] ?? file.unit.statusIn(code).exists,
            dirty: dirtyLanguages.contains(code),
            onTap: () => onLanguage(code),
            path: '${file.unit.path}/$code.tex',
          ),
        const SizedBox(width: 8),
        const Expanded(child: _Dots()),
      ],
    ),
  );
}

class _LanguageTab extends StatelessWidget {
  const _LanguageTab({
    required this.code,
    required this.selected,
    required this.exists,
    required this.dirty,
    required this.onTap,
    required this.path,
  });

  final String code;
  final bool selected;
  final bool exists;
  final bool dirty;
  final VoidCallback onTap;
  final String path;

  @override
  Widget build(BuildContext context) {
    final colour = selected
        ? context.palette.accentDark
        : (exists
              ? context.palette.muted
              : context.palette.muted.withValues(alpha: 0.45));
    return Tooltip(
      // Un idioma que no existe se puede abrir igual: escribir ahí es como se
      // empieza una traducción.
      message: exists ? path : tr('No existe todavía: {0}', [path]),
      child: InkWell(
        key: Key('source-language-$path'),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? context.palette.accentDark.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: selected
                  ? context.palette.accentDark.withValues(alpha: 0.35)
                  : context.palette.rule,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: colour,
                  fontStyle: exists ? FontStyle.normal : FontStyle.italic,
                ),
              ),
              if (dirty) ...[
                const SizedBox(width: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.palette.ex,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({this.width});

  /// Nulo dentro de un `Expanded`, que es quien le da el ancho entonces.
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    width: width,
    child: CustomPaint(painter: _DotsPainter(context.palette.rule)),
  );
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, 0), Offset(x + 2, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.colour != colour;
}

class _Gap extends StatelessWidget {
  const _Gap({required this.gap});

  final ReadingGap gap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.teacher.withValues(alpha: 0.06),
        border: Border.all(
          color: context.palette.teacher.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${gap.reference} — ${gap.reason}',
        style: TextStyle(
          fontSize: 11.5,
          fontFamily: 'monospace',
          color: context.palette.teacher,
        ),
      ),
    ),
  );
}

/// Qué se va a escribir, antes de escribirlo.
///
/// Con los ficheros y las líneas que cambian en cada uno: que solo se toque lo
/// que se ha tocado es una promesa sobre ficheros de otra gente, y se enseña
/// en lugar de afirmarse (D42). Un mensaje para todos, porque es un gesto: se
/// editó una cosa que está repartida en varios ficheros.
class _SaveDialog extends StatefulWidget {
  const _SaveDialog({required this.drafts, required this.suggested});

  final List<SourceDraft> drafts;
  final String suggested;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
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
      title: Text(
        widget.drafts.length == 1
            ? tr('Guardar un fichero')
            : tr('Guardar {0} ficheros', [widget.drafts.length]),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Un solo cambio con todos. Lo que no has tocado no se escribe.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 10),
            for (final draft in widget.drafts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        draft.path,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final size = diffSize(draft.loaded, draft.text);
                        return Text(
                          '+${size.added} −${size.removed}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: context.palette.muted,
                          ),
                        );
                      },
                    ),
                    if (!draft.exists) ...[
                      const SizedBox(width: 8),
                      _Tag('nuevo', colour: context.palette.accentDark),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('source-commit-message'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Qué has cambiado'),
                border: OutlineInputBorder(),
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
          key: const Key('source-commit-save'),
          onPressed: () {
            final message = _controller.text.trim();
            if (message.isEmpty) return;
            Navigator.of(context).pop(message);
          },
          child: Text(tr('Guardar')),
        ),
      ],
    );
  }
}
