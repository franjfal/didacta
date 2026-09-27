/// Buscar texto en los PDF abiertos.
///
/// «¿En qué diapositiva estaba la definición de supremo?» se contestaba
/// pasando páginas. pdfrx sabe buscar en el texto de un PDF; esto lo lleva a
/// la barra del visor, con ⌘F, y con la misma regla que el resto de
/// búsquedas de Didacta: sin mirar tildes ni mayúsculas.
///
/// Una pestaña puede tener dos PDF lado a lado --la misma versión en dos
/// idiomas--, así que se busca en todos y se resalta en todos. Lo que se
/// cuenta y por donde se avanza es el primero que tenga algo: buscar
/// «supremo» con el castellano y el valenciano abiertos avanza por el
/// castellano, y buscar «suprem» por los dos.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../model/pdf_query.dart';
import 'tex_find_bar.dart' show findNextActivator;
import 'theme.dart';
import '../l10n/tr.dart';

/// Los buscadores de los PDF de una pestaña, uno por panel.
class PdfSearch extends ChangeNotifier {
  final Map<String, PdfTextSearcher> _searchers = {};
  String _query = '';

  /// Los paneles, en el orden en que se ven: el primero con resultados es
  /// el que cuenta.
  List<String> order = const [];

  String get query => _query;

  /// Un panel listo para buscar. Se llama cada vez que su visor abre un
  /// documento --también al recompilar, que abre otro--, y si ya se estaba
  /// buscando algo se busca también en el nuevo.
  void attach(String path, PdfViewerController controller) {
    _searchers.remove(path)?.dispose();
    final searcher = PdfTextSearcher(controller)..addListener(notifyListeners);
    _searchers[path] = searcher;
    final pattern = pdfQueryPattern(_query);
    if (pattern != null) {
      searcher.startTextSearch(pattern, searchImmediately: true);
    }
  }

  /// Busca [text] en todos. Vacío, deja de buscar.
  void search(String text, {bool now = false}) {
    _query = text;
    final pattern = pdfQueryPattern(text);
    for (final searcher in _searchers.values) {
      if (pattern == null) {
        searcher.resetTextSearch();
      } else {
        searcher.startTextSearch(pattern, searchImmediately: now);
      }
    }
    notifyListeners();
  }

  void clear() => search('');

  /// El panel por el que se avanza: el primero con algo encontrado.
  String? get active {
    for (final path in order) {
      if (_searchers[path]?.matches.isNotEmpty ?? false) return path;
    }
    return null;
  }

  PdfTextSearcher? get _active => active == null ? null : _searchers[active];

  /// Cuántos hay en el panel que cuenta.
  int get count => _active?.matches.length ?? 0;

  /// Cuál es el actual, desde 1; 0 si ninguno.
  int get current {
    final index = _active?.currentIndex;
    return index == null ? 0 : index + 1;
  }

  bool get searching =>
      _searchers.values.any((searcher) => searcher.isSearching);

  /// Al siguiente (o al anterior), dando la vuelta al llegar al final. La
  /// página a la que se fue, para llevar allí a los demás paneles.
  Future<int?> step(int direction) async {
    final searcher = _active;
    if (searcher == null || searcher.matches.isEmpty) return null;
    final total = searcher.matches.length;
    final now = searcher.currentIndex;
    final next = now == null
        ? (direction > 0 ? 0 : total - 1)
        : (now + direction) % total;
    await searcher.goToMatchOfIndex(next < 0 ? next + total : next);
    notifyListeners();
    return searcher.matches[searcher.currentIndex ?? 0].pageNumber;
  }

  /// Resalta lo encontrado en una página de [path]. Para
  /// `PdfViewerParams.pagePaintCallbacks`.
  void paint(String path, ui.Canvas canvas, Rect pageRect, PdfPage page) =>
      _searchers[path]?.pageTextMatchPaintCallback(canvas, pageRect, page);

  /// Un panel que se cierra.
  void detach(String path) => _searchers.remove(path)?.dispose();

  @override
  void dispose() {
    for (final searcher in _searchers.values) {
      searcher.dispose();
    }
    _searchers.clear();
    super.dispose();
  }
}

/// La barra de buscar, debajo de la del visor.
///
/// Intro va al siguiente y Mayús+Intro al anterior, como en el editor; Esc
/// la cierra.
class PdfSearchBar extends StatefulWidget {
  const PdfSearchBar({
    super.key,
    required this.search,
    required this.onStep,
    required this.onClose,
    this.languageOf,
  });

  final PdfSearch search;

  /// Ir al siguiente (1) o al anterior (-1).
  final ValueChanged<int> onStep;
  final VoidCallback onClose;

  /// El idioma de un panel, para decir en cuál se cuenta cuando hay varios.
  final String? Function(String path)? languageOf;

  @override
  State<PdfSearchBar> createState() => PdfSearchBarState();
}

class PdfSearchBarState extends State<PdfSearchBar> {
  late final TextEditingController _text = TextEditingController(
    text: widget.search.query,
  );
  final FocusNode _focus = FocusNode();

  /// Volver al campo: ⌘F con la barra ya abierta.
  void focusQuery() {
    _focus.requestFocus();
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusQuery();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.search.removeListener(_changed);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _status {
    final search = widget.search;
    if (search.query.trim().isEmpty) return '';
    final count = search.count;
    if (count == 0) return search.searching ? tr('Buscando…') : tr('No está');
    final where = search.order.length > 1 && widget.languageOf != null
        ? ' · ${widget.languageOf!(search.active!) ?? ''}'
        : '';
    final more = search.searching ? '+' : '';
    return search.current == 0
        ? '$count$more$where'
        : tr('{0} de {1}{2}{3}', [search.current, count, more, where]);
  }

  @override
  Widget build(BuildContext context) {
    final found = widget.search.count > 0;
    return Container(
      key: const Key('pdf-search-bar'),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: context.palette.muted),
          const SizedBox(width: 6),
          SizedBox(
            width: 260,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  shift: true,
                ): () =>
                    widget.onStep(-1),
                findNextActivator(): () => widget.onStep(1),
                findNextActivator(back: true): () => widget.onStep(-1),
                const SingleActivator(LogicalKeyboardKey.escape):
                    widget.onClose,
              },
              child: TextField(
                key: const Key('pdf-search-field'),
                controller: _text,
                focusNode: _focus,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('Buscar en el PDF'),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
                onChanged: widget.search.search,
                onSubmitted: (_) {
                  // Intro antes de que acabe la espera de escribir: que
                  // busque ya, que eso ya lleva al primero.
                  if (widget.search.count == 0) {
                    widget.search.search(_text.text, now: true);
                  } else {
                    widget.onStep(1);
                  }
                  _focus.requestFocus();
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _status,
            key: const Key('pdf-search-count'),
            style: TextStyle(
              fontSize: 11.5,
              color:
                  widget.search.query.trim().isNotEmpty &&
                      !found &&
                      !widget.search.searching
                  ? context.palette.ex
                  : context.palette.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          IconButton(
            key: const Key('pdf-search-prev'),
            tooltip: tr('Anterior (Mayús+Intro)'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            onPressed: found ? () => widget.onStep(-1) : null,
          ),
          IconButton(
            key: const Key('pdf-search-next'),
            tooltip: tr('Siguiente (Intro)'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            onPressed: found ? () => widget.onStep(1) : null,
          ),
          IconButton(
            key: const Key('pdf-search-close'),
            tooltip: tr('Cerrar (Esc)'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}
