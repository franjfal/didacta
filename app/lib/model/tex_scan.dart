/// Lo que hay que saber del texto antes de mirarlo: qué es comentario.
///
/// Un `% \begin{answer}` es prosa tachada, no un entorno, y el material
/// migrado está lleno de ellos —párrafos enteros comentados que alguien dejó
/// por si acaso—. Cualquier cosa que cuente entornos o llaves sin ver eso
/// cuenta mal, así que la respuesta vive en un solo sitio y la usan la barra
/// y el árbol.
library;

/// El texto con los comentarios y los caracteres escapados en blanco.
///
/// Devuelve una cadena de **la misma longitud** que la original, así que los
/// índices que se calculan sobre ella valen tal cual sobre el texto de
/// verdad. Los saltos de línea se conservan para que el recuento de líneas
/// siga cuadrando.
String maskLatex(String text) {
  final out = List<String>.filled(text.length, ' ');
  var i = 0;
  var inComment = false;
  while (i < text.length) {
    final ch = text[i];
    if (inComment) {
      if (ch == '\n') {
        inComment = false;
        out[i] = '\n';
      }
      i += 1;
      continue;
    }
    if (ch == r'\' && i + 1 < text.length) {
      final next = text[i + 1];
      // `\%`, `\{`, `\}` y `\\` son caracteres, no sintaxis.
      if (next == '%' || next == '{' || next == '}' || next == r'\') {
        i += 2;
        continue;
      }
      out[i] = ch;
      i += 1;
      continue;
    }
    if (ch == '%') {
      inComment = true;
      i += 1;
      continue;
    }
    out[i] = ch;
    i += 1;
  }
  return out.join();
}

/// La llave que cierra la que empieza en [open], contando las de dentro.
int? matchBrace(String masked, int open) {
  var depth = 0;
  for (var i = open; i < masked.length; i += 1) {
    if (masked[i] == '{') {
      depth += 1;
    } else if (masked[i] == '}') {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  return null;
}
