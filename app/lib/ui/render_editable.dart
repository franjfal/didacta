/// La caja de texto que un widget pinta por dentro.
///
/// Un `TextField` no deja preguntarle dónde está el cursor ni pedirle que
/// enseñe un trozo de su texto; su `RenderEditable` sí. Lo usan la lista de
/// completar, para abrirse junto al cursor, y la búsqueda, para llevar el
/// texto hasta la coincidencia.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

RenderEditable? renderEditableIn(BuildContext context) {
  RenderEditable? found;
  void visit(Element element) {
    if (found != null) return;
    final object = element.renderObject;
    if (object is RenderEditable) {
      found = object;
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return found;
}

/// Desplaza lo que haga falta para que se vea [range] de [editable].
void revealRange(RenderEditable editable, TextRange range) {
  if (!editable.attached) return;
  final start = editable.getLocalRectForCaret(
    TextPosition(offset: range.start),
  );
  final end = editable.getLocalRectForCaret(TextPosition(offset: range.end));
  // Con aire alrededor: pegada al borde, una línea encontrada se lee como
  // cortada.
  editable.showOnScreen(
    rect: start.expandToInclude(end).inflate(48),
    duration: const Duration(milliseconds: 120),
  );
}
