/// Los colores dentro de la caja de texto.
///
/// Se prueba por los trozos que salen, no por cómo se ven: que el `\begin` de
/// un entorno lleve su color, que uno sin cerrar salga en rojo, que un
/// comentario no se pinte como un entorno --es prosa tachada-- y que lo que no
/// se proyecta se apague.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/tex_outline.dart';
import 'package:didacta_app/ui/tex_highlight.dart';
import 'package:didacta_app/ui/theme.dart';

const TextStyle base = TextStyle(color: didactaInk);

/// El color con el que sale un trozo del texto.
Color? colourOf(TextSpan root, String needle) {
  for (final span in root.children ?? const <InlineSpan>[]) {
    final text = (span as TextSpan).text ?? '';
    if (text.contains(needle)) return span.style?.color;
  }
  return null;
}

TextSpan highlight(String text, {bool dim = false}) {
  final outline = TexOutline.ofText(text);
  return highlightFragment(
    text: text,
    base: base,
    outline: outline,
    slice: outline.slices.single,
    dim: dim,
    colourOf: (block) => switch (block.kind) {
      TexBlockKind.slide => didactaAccentDark,
      TexBlockKind.exercise => didactaEx,
      _ => didactaThm,
    },
  );
}

void main() {
  test('el begin y el end llevan el color de su entorno', () {
    final span = highlight('\\begin{frame}\nUna cosa.\n\\end{frame}\n');
    expect(colourOf(span, '\\begin{frame}'), didactaAccentDark);
    expect(colourOf(span, '\\end{frame}'), didactaAccentDark);
    expect(colourOf(span, 'Una cosa.'), didactaInk);
  });

  test('un entorno sin cerrar sale en rojo, en su línea', () {
    final span = highlight('\\begin{frame}\nSin cerrar.\n');
    // El aviso, donde se causó: la banda de arriba dice el fichero, esto dice
    // la línea sin buscarla.
    expect(colourOf(span, '\\begin{frame}'), didactaTeacher);
  });

  test('un comentario no se pinta como un entorno', () {
    final span = highlight('% \\begin{frame}\nProsa.\n');
    final comment = colourOf(span, '\\begin{frame}');
    expect(comment, isNot(didactaAccentDark));
    expect(comment, isNot(didactaInk));
  });

  test('lo que no se proyecta se apaga, y solo si se pide', () {
    const text = 'Prosa fuera.\n\\begin{frame}\nDentro.\n\\end{frame}\n';
    expect(colourOf(highlight(text), 'Prosa fuera.'), didactaInk);
    expect(
      colourOf(highlight(text, dim: true), 'Prosa fuera.'),
      isNot(didactaInk),
    );
    // Lo de dentro de la diapositiva no se apaga.
    expect(colourOf(highlight(text, dim: true), 'Dentro.'), didactaInk);
  });

  test('el texto entero sobrevive, carácter a carácter', () {
    const text = '\\begin{frame}\n% nota\nUna cosa.\n\\end{frame}\n';
    final span = highlight(text, dim: true);
    final joined = [
      for (final child in span.children!) (child as TextSpan).text,
    ].join();
    // Pintar no puede perder ni añadir una letra: lo que se ve es lo que se
    // va a guardar.
    expect(joined, text);
  });
}
