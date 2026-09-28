/// Buscar en el texto que se edita, y reemplazar.
///
/// ⌘F (Ctrl+F) solo buscaba en la biblioteca: dentro de una lección de
/// trescientas líneas, encontrar dónde se usaba `\lambda` era leerla entera.
/// Esta barra se abre encima del texto, pinta todas las coincidencias en él y
/// salta de una a otra con Intro, Mayús+Intro o ⌘G; Esc la cierra y deja el
/// cursor en la que se estaba mirando.
///
/// Reemplazar va plegado detrás de un botón: es lo que hace falta de vez en
/// cuando, y con expresiones regulares, lo de quien sabe lo que hace.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/tex_find.dart';
import 'render_editable.dart';
import 'shortcuts.dart';
import 'tex_highlight.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// ⌘G o Ctrl+G: la siguiente; con Mayús, la anterior.
SingleActivator findNextActivator({bool back = false}) {
  final next = activatorFor(AppShortcut.findNext);
  return SingleActivator(
    next.trigger,
    meta: next.meta,
    control: next.control,
    shift: back,
  );
}

class TexFindBar extends StatefulWidget {
  const TexFindBar({
    super.key,
    required this.controller,
    required this.editorFocus,
    required this.onClose,
    this.readOnly = false,
    this.initial = '',
  });

  final TexEditingController controller;

  /// El foco del texto, para devolvérselo al cerrar y para encontrar la caja
  /// que hay que desplazar.
  final FocusNode editorFocus;

  final VoidCallback onClose;

  /// Sin reemplazar: un texto que no se puede escribir no se reemplaza.
  final bool readOnly;

  /// Lo que se busca al abrir: lo que estaba seleccionado, si era una línea.
  final String initial;

  @override
  State<TexFindBar> createState() => TexFindBarState();
}

class TexFindBarState extends State<TexFindBar> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initial,
  );
  final TextEditingController _replacement = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  bool _caseSensitive = false;
  bool _regex = false;
  bool _replacing = false;

  List<TextRange> _found = const [];
  int _current = -1;
  String? _error;

  /// Lo que se dice después de reemplazar todas.
  String? _note;

  /// El texto sobre el que se buscó: el controlador avisa también cuando
  /// solo se mueve el cursor, y entonces no hay que volver a buscar.
  String? _searched;

  TexSearch get _search =>
      TexSearch(_query.text, caseSensitive: _caseSensitive, regex: _regex);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _query.text.length,
    );
    // Buscar, sí; pintarlo en el texto y darle el foco, después de este
    // fotograma: la barra nace mientras se construye la página, y avisar
    // ahora al texto sería pedirle que se reconstruya a mitad.
    _find(from: widget.controller.selection.start, paint: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.showFound(_found, _current);
      _queryFocus.requestFocus();
      _reveal();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    // Sin avisar: al desmontarse el árbol está bloqueado, y el texto se
    // vuelve a pintar igual en cuanto cambie algo.
    widget.controller.forgetFound();
    _query.dispose();
    _replacement.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// Vuelve a poner el foco en lo que se busca, con todo marcado: es lo que
  /// hace ⌘F con la barra ya abierta.
  void focusQuery() {
    _queryFocus.requestFocus();
    _query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _query.text.length,
    );
  }

  void _onText() {
    if (widget.controller.text == _searched) return;
    _find(keep: true);
  }

  /// Busca otra vez. Con [from], la actual es la primera desde ahí; con
  /// [keep], la misma posición en la lista, que es lo que se espera cuando el
  /// texto cambia debajo.
  void _find({int? from, bool keep = false, bool paint = true}) {
    final text = widget.controller.text;
    _searched = text;
    List<TextRange> found;
    String? error;
    try {
      found = findAll(text, _search);
    } on FormatException {
      found = const [];
      error = tr('La expresión no es válida');
    }
    var current = -1;
    if (found.isNotEmpty) {
      if (from != null) {
        current = nextMatch(found, from);
      } else if (keep && _current >= 0) {
        current = _current.clamp(0, found.length - 1);
      } else {
        current = 0;
      }
    }
    _found = found;
    _current = current;
    _error = error;
    if (!paint) return;
    setState(() {});
    widget.controller.showFound(found, current);
  }

  /// La siguiente con [step] 1, la anterior con -1.
  void go(int step) {
    if (_found.isEmpty) return;
    setState(() {
      _current = (_current + step) % _found.length;
      if (_current < 0) _current += _found.length;
      _note = null;
    });
    widget.controller.showFound(_found, _current);
    _reveal();
  }

  void _reveal() {
    if (_current < 0 || _current >= _found.length) return;
    final range = _found[_current];
    final context = widget.editorFocus.context;
    if (context == null) return;
    final editable = renderEditableIn(context);
    if (editable != null) revealRange(editable, range);
  }

  void _onQuery() {
    _note = null;
    _find(from: widget.controller.selection.start);
    _reveal();
  }

  void _close() {
    // El cursor, en la que se estaba mirando: cerrar para escribir ahí es
    // lo más común.
    if (_current >= 0 && _current < _found.length) {
      final range = _found[_current];
      widget.controller.selection = TextSelection(
        baseOffset: range.start,
        extentOffset: range.end,
      );
    }
    widget.controller.showFound(const [], -1);
    widget.onClose();
    widget.editorFocus.requestFocus();
  }

  void _replaceCurrent() {
    if (_current < 0 || _current >= _found.length) return;
    final edit = replaceOne(
      widget.controller.text,
      _found[_current],
      _search,
      _replacement.text,
    );
    _searched = edit.text;
    widget.controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.end),
    );
    // La siguiente, desde donde acaba lo escrito: lo que se acaba de poner
    // no se vuelve a encontrar aunque contenga lo que se busca.
    _find(from: edit.end);
    _reveal();
  }

  void _replaceAll() {
    final result = replaceAll(
      widget.controller.text,
      _search,
      _replacement.text,
    );
    if (result.count == 0) return;
    _searched = result.text;
    final caret = widget.controller.selection.start.clamp(
      0,
      result.text.length,
    );
    widget.controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _find(from: caret);
    setState(
      () => _note = result.count == 1
          ? tr('1 reemplazada')
          : tr('{0} reemplazadas', [result.count]),
    );
  }

  String get _count {
    if (_error != null) return _error!;
    if (_note != null) return _note!;
    if (_query.text.isEmpty) return '';
    if (_found.isEmpty) return tr('Sin resultados');
    return tr('{0} de {1}', [_current + 1, _found.length]);
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    final problem =
        _error != null || (_found.isEmpty && _query.text.isNotEmpty);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
            go(-1),
        findNextActivator(): () => go(1),
        findNextActivator(back: true): () => go(-1),
      },
      child: Container(
        key: const Key('find-bar'),
        decoration: BoxDecoration(
          color: context.palette.panel,
          border: Border(bottom: BorderSide(color: context.palette.rule)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 260,
                  child: _Field(
                    key: const Key('find-query'),
                    controller: _query,
                    focusNode: _queryFocus,
                    hint: tr('Buscar en el texto'),
                    icon: Icons.search,
                    onChanged: (_) => _onQuery(),
                    onSubmitted: () {
                      go(1);
                      _queryFocus.requestFocus();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: Text(
                    count,
                    key: const Key('find-count'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: problem
                          ? context.palette.teacher
                          : context.palette.muted,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('find-prev'),
                  tooltip: tr('Anterior  ⇧↩'),
                  icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  onPressed: _found.isEmpty ? null : () => go(-1),
                ),
                IconButton(
                  key: const Key('find-next'),
                  tooltip: tr('Siguiente  ↩'),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  onPressed: _found.isEmpty ? null : () => go(1),
                ),
                const SizedBox(width: 4),
                _Toggle(
                  key: const Key('find-case'),
                  label: tr('Aa'),
                  tooltip: tr('Distinguir mayúsculas'),
                  on: _caseSensitive,
                  onChanged: (value) {
                    _caseSensitive = value;
                    _onQuery();
                  },
                ),
                const SizedBox(width: 4),
                _Toggle(
                  key: const Key('find-regex'),
                  label: '.*',
                  tooltip: tr('Expresión regular'),
                  on: _regex,
                  onChanged: (value) {
                    _regex = value;
                    _onQuery();
                  },
                ),
                if (!widget.readOnly) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('find-replace-toggle'),
                    tooltip: _replacing
                        ? tr('Ocultar reemplazar')
                        : tr('Reemplazar'),
                    isSelected: _replacing,
                    icon: const Icon(Icons.find_replace, size: 18),
                    onPressed: () => setState(() => _replacing = !_replacing),
                  ),
                ],
                const Spacer(),
                IconButton(
                  key: const Key('find-close'),
                  tooltip: tr('Cerrar  Esc'),
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    semanticLabel: tr('Cerrar la búsqueda'),
                  ),
                  onPressed: _close,
                ),
              ],
            ),
            if (_replacing && !widget.readOnly)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 260,
                      child: _Field(
                        key: const Key('find-replacement'),
                        controller: _replacement,
                        hint: _regex
                            ? tr(r'Reemplazar por ($1, $2…)')
                            : tr('Reemplazar por'),
                        icon: Icons.edit_outlined,
                        onSubmitted: _replaceCurrent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const Key('find-replace-one'),
                      onPressed: _found.isEmpty ? null : _replaceCurrent,
                      child: Text(tr('Reemplazar')),
                    ),
                    TextButton(
                      key: const Key('find-replace-all'),
                      onPressed: _found.isEmpty ? null : _replaceAll,
                      child: Text(tr('Todas')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    style: const TextStyle(fontSize: 13),
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      prefixIcon: Icon(icon, size: 16),
      prefixIconConstraints: const BoxConstraints(minWidth: 32),
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      border: const OutlineInputBorder(),
    ),
    onChanged: onChanged,
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
  );
}

/// Un interruptor pequeño con un rótulo: `Aa`, `.*`.
class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.label,
    required this.tooltip,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final String tooltip;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      toggled: on,
      label: tooltip,
      child: Hoverable(
        onTap: () => onChanged(!on),
        builder: (context, hovering) => Container(
          width: 32,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? context.palette.selected
                : (hovering ? context.palette.hover : Colors.transparent),
            border: Border.all(
              color: on ? context.palette.accentDark : context.palette.rule,
            ),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Text(
            label,
            style: monoStyle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: on ? context.palette.accentDark : context.palette.muted,
            ),
          ),
        ),
      ),
    ),
  );
}
