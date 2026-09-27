/// La lista que se abre junto al cursor al escribir una orden o un entorno.
///
/// `\didac` ofrece `\didactatitle`; `\begin{` ofrece los entornos de Didacta
/// y, al aceptar uno, escribe también su `\end`. Con ↑ y ↓ se elige, con
/// Intro o Tab se acepta y con Esc se cierra. Lo que se ofrece es la lista
/// cerrada de [texCommands] y [didactaEnvironments]: lo que se usa en una
/// lección, no todo lo que existe en LaTeX.
///
/// Envuelve la caja de texto y no la sustituye: lee su controlador, y las
/// teclas le llegan antes que a la caja solo mientras la lista está abierta.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/tex_vocabulary.dart';
import 'render_editable.dart';
import 'theme.dart';

class TexCompletion extends StatefulWidget {
  const TexCompletion({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
  });

  final TextEditingController controller;

  /// Apagado en una caja de solo lectura: ahí no se escribe nada.
  final bool enabled;

  /// La caja de texto.
  final Widget child;

  @override
  State<TexCompletion> createState() => _TexCompletionState();
}

class _TexCompletionState extends State<TexCompletion> {
  final OverlayPortalController _portal = OverlayPortalController();

  TexCompletionQuery? _query;
  int _chosen = 0;
  bool _focused = false;

  /// Dónde empezaba lo que se cerró con Esc: esa misma palabra no vuelve a
  /// abrir la lista mientras se sigue escribiendo.
  int? _dismissedAt;

  /// Debajo del cursor, en coordenadas de la pantalla.
  Rect? _caret;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(TexCompletion old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_update);
      widget.controller.addListener(_update);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final value = widget.controller.value;
    TexCompletionQuery? query;
    // Mientras se compone un carácter --una tilde muerta, un acento-- no:
    // lo que hay escrito todavía no es lo que se va a escribir.
    final composing = value.composing.isValid && !value.composing.isCollapsed;
    if (widget.enabled &&
        _focused &&
        !composing &&
        value.selection.isValid &&
        value.selection.isCollapsed) {
      query = completionAt(value.text, value.selection.baseOffset);
    }
    if (query != null && query.start == _dismissedAt) query = null;
    if (query == null || query.words.isEmpty) {
      if (query == null && _dismissedAt != null) {
        // Fuera de la palabra que se cerró, la siguiente sí abre.
        final start = _dismissedAt!;
        final caret = value.selection.baseOffset;
        if (caret < start || caret > value.text.length) _dismissedAt = null;
      }
      _hide();
      return;
    }
    if (query.start != _query?.start || query.kind != _query?.kind) {
      _chosen = 0;
    }
    _chosen = _chosen.clamp(0, query.words.length - 1);
    setState(() => _query = query);
    // Dónde está el cursor se sabe después de pintar el texto nuevo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _place());
    if (!_portal.isShowing) _portal.show();
  }

  void _hide() {
    if (_query == null && !_portal.isShowing) return;
    if (_portal.isShowing) _portal.hide();
    if (mounted) setState(() => _query = null);
  }

  /// Lee dónde se pinta el cursor, de la caja de texto que hay dentro.
  void _place() {
    if (!mounted || _query == null) return;
    final editable = renderEditableIn(context);
    if (editable == null || !editable.attached) return;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: _query!.end),
    );
    final topLeft = editable.localToGlobal(caret.topLeft);
    final rect = topLeft & caret.size;
    if (rect != _caret) setState(() => _caret = rect);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final query = _query;
    if (query == null || !_portal.isShowing || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _chosen = (_chosen + 1) % query.words.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _chosen = (_chosen - 1 + query.words.length) % query.words.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _accept(query.words[_chosen]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _dismissedAt = query.start;
      _hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _accept(TexWord word) {
    final query = _query;
    if (query == null) return;
    final edit = acceptCompletion(widget.controller.text, query, word);
    _hide();
    widget.controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.start),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _list,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          _focused = focused;
          if (focused) {
            _update();
          } else {
            _hide();
          }
        },
        onKeyEvent: _onKey,
        child: widget.child,
      ),
    );
  }

  Widget _list(BuildContext context) {
    final query = _query;
    final caret = _caret;
    if (query == null || caret == null) return const SizedBox.shrink();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final below = overlay.globalToLocal(caret.bottomLeft);
    final above = overlay.globalToLocal(caret.topLeft);
    const width = 340.0;
    final height = query.words.length * _rowHeight + 8;
    // Debajo del cursor, o encima si abajo no cabe; y sin salirse por la
    // derecha.
    final top = below.dy + height + 4 > overlay.size.height
        ? above.dy - height - 4
        : below.dy + 4;
    final room = overlay.size.width - width - 8;
    final left = room < 8 ? 8.0 : below.dx.clamp(8.0, room);
    return Positioned(
      left: left,
      top: top,
      width: width,
      // Dentro de la caja a efectos de «pulsar fuera»: elegir con el ratón
      // no le quita el foco al texto.
      child: TextFieldTapRegion(
        child: ExcludeFocus(
          child: Material(
            key: const Key('tex-completion'),
            color: context.palette.card,
            elevation: 6,
            shadowColor: context.palette.shadow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.control),
              side: BorderSide(color: context.palette.rule),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, word) in query.words.indexed)
                    _Row(
                      key: Key('tex-completion-${word.name}'),
                      word: word,
                      kind: query.kind,
                      chosen: index == _chosen,
                      onTap: () => _accept(word),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _rowHeight = 30;

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.word,
    required this.kind,
    required this.chosen,
    required this.onTap,
  });

  final TexWord word;
  final TexCompletionKind kind;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: _rowHeight,
      color: chosen ? context.palette.selected : null,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text(
            kind == TexCompletionKind.command
                ? '\\${word.name}${word.arguments}'
                : word.name,
            style: monoStyle.copyWith(
              fontSize: 12.5,
              fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
              color: context.palette.ink,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              word.detail,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          ),
        ],
      ),
    ),
  );
}
