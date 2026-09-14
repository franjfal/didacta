/// Los colores de un fragmento, dentro de la caja de texto.
///
/// Mientras había un «modo edición», la vista podía pintar cada línea a mano y
/// la caja era otra cosa. Sin modo —que es lo que hace que pulsar una línea
/// sea poner el cursor y escribir, y no que la pantalla se recomponga— el
/// color tiene que vivir **dentro** del texto editable. Un
/// `TextEditingController` puede decir cómo se pinta cada trozo de lo que
/// contiene, y eso es lo que se hace aquí.
///
/// Tres cosas se marcan, y las tres dicen algo que no se puede leer de otra
/// forma:
///
/// **El `\begin` y el `\end` van del color de su entorno**: es lo mismo que
/// dice la columna del margen, dicho en el sitio donde se escribe. Y si el
/// entorno se quedó sin cerrar, en rojo: el aviso, en la línea que lo causó.
///
/// **Lo que no se proyecta, en gris**, línea a línea, igual que fuera.
///
/// **Los comentarios, apagados**: el material migrado tiene párrafos enteros
/// comentados, y leerlos con el mismo peso que el contenido es leer dos veces
/// el mismo fichero.
library;

import 'package:flutter/material.dart';

import '../model/tex_outline.dart';
import 'theme.dart';

/// Cómo se pinta cada trozo del texto de un fichero.
///
/// [text] es el texto que hay ahora en la caja, que puede no ser el del árbol
/// —se está escribiendo—, así que todo lo que sale del árbol se recorta a lo
/// que el texto tiene ahora mismo.
TextSpan highlightFragment({
  required String text,
  required TextStyle base,
  required TexOutline outline,
  required TexSlice slice,
  required bool dim,
  required Color Function(TexBlock block) colourOf,
}) {
  if (text.isEmpty) return TextSpan(text: text, style: base);

  final styles = List<TextStyle>.filled(text.length, base);

  void paint(int from, int to, TextStyle style) {
    final start = from.clamp(0, text.length);
    final end = to.clamp(0, text.length);
    for (var i = start; i < end; i += 1) {
      styles[i] = style;
    }
  }

  // Las líneas que no se proyectan, en gris.
  if (dim) {
    final faded = base.copyWith(color: didactaMuted.withValues(alpha: 0.55));
    for (var line = slice.startLine; line <= slice.endLine; line += 1) {
      if (outline.projectedAt(line)) continue;
      final from = outline.lineStarts[line] - slice.start;
      final to = line + 1 < outline.lineStarts.length
          ? outline.lineStarts[line + 1] - slice.start
          : text.length;
      paint(from, to, faded);
    }
  }

  // Los delimitadores, del color de su entorno.
  for (final block in outline.blocks) {
    if (block.start < slice.start || block.start >= slice.end) continue;
    final colour = block.closed ? colourOf(block) : didactaTeacher;
    final style = base.copyWith(color: colour, fontWeight: FontWeight.w700);
    final open = block.start - slice.start;
    paint(open, open + '\\begin{${block.name}}'.length, style);
    if (block.closed) {
      final close = block.end - slice.start;
      paint(close - '\\end{${block.name}}'.length, close, style);
    }
  }

  // Los comentarios, por encima de todo: un `% \begin{frame}` es prosa
  // tachada, y pintarlo como un entorno diría lo contrario.
  final comment = base.copyWith(
    color: didactaMuted.withValues(alpha: 0.7),
    fontStyle: FontStyle.italic,
  );
  var at = 0;
  while (at < text.length) {
    final ch = text[at];
    if (ch == r'\' && at + 1 < text.length) {
      at += 2;
      continue;
    }
    if (ch == '%') {
      var end = text.indexOf('\n', at);
      if (end < 0) end = text.length;
      paint(at, end, comment);
      at = end + 1;
      continue;
    }
    at += 1;
  }

  // Juntar los caracteres seguidos que se pintan igual: un span por carácter
  // sería correcto y haría inútil la pantalla.
  final spans = <TextSpan>[];
  var from = 0;
  for (var i = 1; i <= text.length; i += 1) {
    if (i < text.length && styles[i] == styles[from]) continue;
    spans.add(TextSpan(text: text.substring(from, i), style: styles[from]));
    from = i;
  }
  return TextSpan(children: spans);
}
