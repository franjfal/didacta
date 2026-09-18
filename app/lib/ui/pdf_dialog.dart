/// Ver lo compilado sin salir de donde estás.
///
/// La pantalla de un curso enseña treinta documentos y lo que se hace con
/// ellos todo el rato es mirar cómo ha quedado el PDF. Abrirlo en el visor
/// del sistema saca de la aplicación y pierde el sitio; navegar a la pantalla
/// del documento son dos clics y una vuelta. Un diálogo encima deja el listado
/// detrás y se cierra con Escape.
///
/// Dos filas de pestañas, y el orden entre ellas no es casual. Arriba el
/// **idioma**, porque es lo que menos cambia mientras se trabaja y lo que
/// manda sobre lo de abajo: cada idioma tiene sus versiones compiladas, y no
/// tienen por qué ser las mismas --el valenciano puede tener los apuntes y no
/// las diapositivas--. Debajo la **versión**, que es lo que distingue este
/// visor del de la pantalla del documento: allí se comparan idiomas lado a
/// lado mientras se edita, y aquí se trata de repasar las diapositivas, los
/// apuntes y la copia del profesor de lo mismo.
///
/// Entra seleccionado el idioma en el que se está trabajando. Si de ese no hay
/// nada compilado, el primero que haya: enseñar un visor vacío por respetar la
/// preferencia no ayuda a nadie.
library;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/compiler.dart';
import '../model/catalogue.dart';
import 'export_actions.dart';
import 'pdf_controls.dart';
import 'pdf_sidebar.dart';
import 'theme.dart';

Future<void> showBuiltPdfs(
  BuildContext context, {
  required String title,
  required List<ExistingOutput> outputs,
  String? language,
  List<LanguageOption> languages = const [],
  ValueChanged<String>? onOpenExternally,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (_) => BuiltPdfsDialog(
    title: title,
    outputs: outputs,
    language: language,
    languages: languages,
    onOpenExternally: onOpenExternally,
  ),
);

class BuiltPdfsDialog extends StatefulWidget {
  const BuiltPdfsDialog({
    super.key,
    required this.title,
    required this.outputs,
    this.language,
    this.languages = const [],
    this.onOpenExternally,
  });

  final String title;
  final List<ExistingOutput> outputs;

  /// En el que se está trabajando. Sale elegido si hay algo suyo compilado.
  final String? language;

  /// Cómo se llama cada idioma, para no enseñar códigos de dos letras a quien
  /// no tiene por qué saberlos. Lo que falte se enseña por su código.
  final List<LanguageOption> languages;

  final ValueChanged<String>? onOpenExternally;

  @override
  State<BuiltPdfsDialog> createState() => _BuiltPdfsDialogState();
}

class _BuiltPdfsDialogState extends State<BuiltPdfsDialog> {
  /// Lo que existe, por idioma, y las versiones de siempre primero.
  ///
  /// Quien abre esto quiere ver los apuntes o las diapositivas; la copia del
  /// profesor y la de con soluciones son variantes que se miran después.
  late final Map<String, List<ExistingOutput>> _byLanguage = () {
    final grouped = <String, List<ExistingOutput>>{};
    for (final output in widget.outputs) {
      if (!output.exists) continue;
      (grouped[output.language] ??= []).add(output);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.profile.compareTo(b.profile);
      });
    }
    return grouped;
  }();

  /// En el orden en que los declara la asignatura, y lo que no conozca detrás.
  late final List<String> _codes = [
    for (final option in widget.languages)
      if (_byLanguage.containsKey(option.code)) option.code,
    for (final code in _byLanguage.keys)
      if (!widget.languages.any((o) => o.code == code)) code,
  ];

  late String _language = _codes.contains(widget.language)
      ? widget.language!
      : (_codes.firstOrNull ?? '');

  int _at = 0;

  /// Lo mismo que en la pestaña, y por la misma razón: un visor con
  /// lateral, zoom y ajustes, y el otro con la rueda del ratón, son dos
  /// programas distintos para mirar el mismo PDF.
  final Map<String, PdfViewerController> _controllers = {};
  final Map<String, PdfDocument> _documents = {};
  final Map<String, List<PdfOutlineNode>> _outlines = {};
  final Map<String, int> _pages = {};
  final Map<String, int> _page = {};

  bool _sidebar = false;
  int? _zoom;

  List<ExistingOutput> get _shown => _byLanguage[_language] ?? const [];

  PdfViewerController _controllerFor(String path) =>
      _controllers.putIfAbsent(path, () {
        final controller = PdfViewerController();
        controller.addListener(() => _noteZoom(path, controller));
        return controller;
      });

  void _noteZoom(String path, PdfViewerController controller) {
    if (!mounted || path != _current?.pdf || !controller.isReady) return;
    final now = (controller.currentZoom * 100).round();
    if (now == _zoom) return;
    setState(() => _zoom = now);
  }

  ExistingOutput? get _current =>
      _shown.isEmpty ? null : _shown[_at.clamp(0, _shown.length - 1)];

  PdfViewerController? get _controller {
    final path = _current?.pdf;
    return path == null ? null : _controllers[path];
  }

  bool get _ready => _controller?.isReady ?? false;

  void _noteReady(String path, PdfDocument document) {
    if (!mounted) return;
    setState(() {
      _pages[path] = document.pages.length;
      _documents[path] = document;
    });
    _loadOutline(path, document);
  }

  Future<void> _loadOutline(String path, PdfDocument document) async {
    List<PdfOutlineNode> outline;
    try {
      outline = await document.loadOutline();
    } catch (_) {
      outline = const [];
    }
    if (!mounted || _documents[path] != document) return;
    setState(() => _outlines[path] = outline);
  }

  void _goTo(int page) {
    final path = _current?.pdf;
    if (path == null) return;
    final total = _pages[path] ?? 1;
    _controllers[path]?.goToPage(pageNumber: page.clamp(1, total));
  }

  void _fit(Matrix4? Function(PdfViewerController controller, int page) how) {
    final controller = _controller;
    if (controller == null || !controller.isReady) return;
    final matrix = how(controller, controller.pageNumber ?? 1);
    if (matrix != null) controller.goTo(matrix);
  }

  String _nameOf(String code) {
    for (final option in widget.languages) {
      if (option.code == code) return option.name;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    if (_shown.isEmpty) {
      return const AlertDialog(
        content: Text('No hay ningún PDF compilado de esto todavía.'),
      );
    }
    final current = _shown[_at.clamp(0, _shown.length - 1)];
    final page = _page[current.pdf] ?? 1;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, current),
            if (_codes.length > 1) _languages(),
            if (_shown.length > 1) _tabs(),
            _controls(current, page),
            Expanded(
              child: Row(
                children: [
                  if (_sidebar)
                    PdfSidebar(
                      document: _documents[current.pdf],
                      outline: _outlines[current.pdf] ?? const [],
                      page: page,
                      onGoToPage: _goTo,
                      onGoToDest: (dest) =>
                          _controllers[current.pdf]?.goToDest(dest),
                    ),
                  Expanded(
                    child: Container(
                      color: didactaSurface,
                      child: PdfViewer.file(
                        current.pdf,
                        // Con clave: cambiar de pestaña tiene que cargar el
                        // otro fichero, y sin esto el visor se queda con el
                        // primero.
                        key: ValueKey(current.pdf),
                        controller: _controllerFor(current.pdf),
                        params: PdfViewerParams(
                          margin: 10,
                          viewerOverlayBuilder:
                              (context, size, handleLinkTap) => [
                                PdfViewerScrollThumb(
                                  controller: _controllerFor(current.pdf),
                                  orientation: ScrollbarOrientation.right,
                                  thumbSize: const Size(38, 26),
                                ),
                              ],
                          onViewerReady: (document, controller) =>
                              _noteReady(current.pdf, document),
                          onPageChanged: (at) {
                            if (at == null || !mounted) return;
                            setState(() => _page[current.pdf] = at);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La barra de mandos, la misma que la de la pestaña.
  Widget _controls(ExistingOutput current, int page) => PdfViewerBar(
    page: page,
    pages: _pages[current.pdf] ?? 1,
    sidebar: _sidebar,
    zoom: _ready ? (_zoom ?? 100) / 100 : null,
    onSidebar: () => setState(() => _sidebar = !_sidebar),
    onGoToPage: _goTo,
    onZoomOut: _ready ? () => _controller!.zoomDown() : null,
    onZoomIn: _ready ? () => _controller!.zoomUp() : null,
    onActualSize: _ready
        ? () => _controller!.setZoom(_controller!.centerPosition, 1)
        : null,
    onFitWidth: _ready
        ? () => _fit((c, at) => c.calcMatrixFitWidthForPage(pageNumber: at))
        : null,
    onFitHeight: _ready
        ? () => _fit((c, at) => c.calcMatrixFitHeightForPage(pageNumber: at))
        : null,
    onFitPage: _ready
        ? () => _fit((c, at) => c.calcMatrixForFit(pageNumber: at))
        : null,
  );

  Widget _header(BuildContext context, ExistingOutput current) => Container(
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                current.stale
                    ? '${current.label} · ${_nameOf(current.language)} · de '
                          'antes del último cambio'
                    : '${current.label} · ${_nameOf(current.language)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: current.stale ? didactaEx : didactaMuted,
                ),
              ),
            ],
          ),
        ),
        // Llevárselo. Antes de abrirlo fuera, porque es lo que se hace con
        // el PDF que ya está bien: el visor del sistema es para mirarlo más
        // grande, esto es para que salga de aquí.
        IconButton(
          key: const Key('pdf-save-copy'),
          tooltip: 'Guardar una copia',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          onPressed: () => savePdfCopy(context, path: current.pdf),
        ),
        if (widget.onOpenExternally != null)
          IconButton(
            key: const Key('pdf-open-externally'),
            tooltip: 'Abrir en el visor del sistema',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.open_in_new, size: 17),
            onPressed: () => widget.onOpenExternally!(current.pdf),
          ),
        IconButton(
          key: const Key('pdf-dialog-close'),
          tooltip: 'Cerrar',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  /// La fila de idiomas, encima de la de versiones.
  ///
  /// Cambiar de idioma vuelve a la primera versión y no a la que estaba
  /// abierta: no tiene por qué existir ahí, y un índice que se sale de la
  /// lista es un visor en blanco.
  Widget _languages() => Container(
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final code in _codes) ...[
            if (code != _codes.first) const SizedBox(width: 6),
            ChoiceChip(
              key: Key('pdf-language-$code'),
              label: Text(
                '${_nameOf(code)} · ${_byLanguage[code]!.length}',
                style: const TextStyle(fontSize: 12),
              ),
              selected: code == _language,
              onSelected: (_) => setState(() {
                _language = code;
                _at = 0;
              }),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _tabs() => Container(
    decoration: const BoxDecoration(
      color: didactaCard,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < _shown.length; index += 1) ...[
            if (index > 0) const SizedBox(width: 6),
            ChoiceChip(
              key: Key('pdf-tab-${_shown[index].profile}'),
              label: Text(
                _shown[index].label,
                style: const TextStyle(fontSize: 12),
              ),
              selected: index == _at,
              onSelected: (_) => setState(() => _at = index),
            ),
          ],
        ],
      ),
    ),
  );
}
