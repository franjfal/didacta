/// Trocear LaTeX para poder pintarlo.
///
/// Un `.tex` de Didacta se lee como código y se editaba como un bloc de
/// notas. Esto es lo que hace que se lea como código: un recorrido que dice
/// qué es cada trozo —una orden, un comentario, unas matemáticas, el nombre de
/// un entorno— para que la interfaz le ponga color.
///
/// Está aquí y no en la interfaz porque es lo que se puede probar: un color
/// equivocado se ve, pero un `%` dentro de unas matemáticas que apaga media
/// unidad, o un `\\%` que se toma por comentario, no se ve hasta que alguien
/// abre ese fichero.
///
/// Lo que **no** hace: entender LaTeX. No sabe cuántos argumentos lleva una
/// orden ni qué hace un paquete. Distingue las siete cosas que se distinguen
/// leyendo, y para de ahí.
library;

/// Qué es un trozo de texto.
enum TexTokenKind {
  /// Texto corriente.
  text,

  /// De `%` a final de línea. Prosa tachada: el material migrado está lleno.
  comment,

  /// `\section`, `\frac`, `\\`, `\%`… La orden, sin sus argumentos.
  command,

  /// El nombre dentro de `\begin{...}` y `\end{...}`.
  ///
  /// Aparte de la orden porque es lo que dice **qué** entorno es, y va del
  /// color de ese entorno.
  environment,

  /// Llaves y corchetes: la puntuación de LaTeX.
  delimiter,

  /// `$`, `\[`, `\]` y lo que va entre ellos, salvo las órdenes de dentro.
  math,

  /// `&`, `#`, `_`, `^`, `~`: los caracteres que LaTeX se reserva.
  special,
}

/// Un trozo, con dónde empieza y dónde acaba.
class TexToken {
  const TexToken(this.kind, this.start, this.end);

  final TexTokenKind kind;
  final int start;
  final int end;

  @override
  String toString() => '$kind[$start,$end)';
}

/// Trocea un `.tex`.
///
/// Devuelve los trozos en orden y sin huecos: lo que no es nada en particular
/// sale como [TexTokenKind.text], así que quien pinta puede recorrerlos sin
/// preocuparse de lo que falta.
List<TexToken> scanLatex(String text) {
  final tokens = <TexToken>[];
  var at = 0;
  var plain = 0;
  var inMath = false;

  // Cierra lo que llevara acumulado como texto corriente. Marca si viene de
  // dentro de unas matemáticas **antes** de cerrarlas: si no, lo de dentro de
  // `$...$` sale como prosa justo al llegar al `$` final.
  void flush(int upto) {
    if (upto > plain) {
      tokens.add(
        TexToken(inMath ? TexTokenKind.math : TexTokenKind.text, plain, upto),
      );
    }
    plain = upto;
  }

  void emit(TexTokenKind kind, int start, int end) {
    flush(start);
    tokens.add(TexToken(kind, start, end));
    plain = end;
  }

  bool isLetter(String ch) =>
      (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
      (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0);

  while (at < text.length) {
    final ch = text[at];

    if (ch == '%') {
      var end = text.indexOf('\n', at);
      if (end < 0) end = text.length;
      emit(TexTokenKind.comment, at, end);
      at = end;
      continue;
    }

    if (ch == r'\') {
      if (at + 1 >= text.length) {
        emit(TexTokenKind.command, at, text.length);
        at = text.length;
        continue;
      }
      final next = text[at + 1];

      // `\[` y `\]` abren y cierran matemáticas; `\(` y `\)` también.
      if (next == '[' || next == '(') {
        emit(TexTokenKind.math, at, at + 2);
        at += 2;
        inMath = true;
        plain = at;
        continue;
      }
      if (next == ']' || next == ')') {
        flush(at);
        inMath = false;
        emit(TexTokenKind.math, at, at + 2);
        at += 2;
        continue;
      }

      if (!isLetter(next)) {
        // `\\`, `\%`, `\{`: una orden de un solo carácter.
        emit(TexTokenKind.command, at, at + 2);
        at += 2;
        continue;
      }

      var end = at + 1;
      while (end < text.length && isLetter(text[end])) {
        end += 1;
      }
      if (end < text.length && text[end] == '*') end += 1;
      final name = text.substring(at + 1, end);
      emit(TexTokenKind.command, at, end);
      at = end;

      // `\begin{ejercicio}`: el nombre va aparte, que es lo que dice qué
      // entorno es y de qué color va.
      if (name == 'begin' || name == 'end') {
        var cursor = at;
        while (cursor < text.length &&
            (text[cursor] == ' ' || text[cursor] == '\t')) {
          cursor += 1;
        }
        if (cursor < text.length && text[cursor] == '{') {
          final close = text.indexOf('}', cursor);
          if (close > 0) {
            emit(TexTokenKind.delimiter, cursor, cursor + 1);
            emit(TexTokenKind.environment, cursor + 1, close);
            emit(TexTokenKind.delimiter, close, close + 1);
            at = close + 1;
          }
        }
      }
      continue;
    }

    if (ch == r'$') {
      final double = at + 1 < text.length && text[at + 1] == r'$';
      final end = at + (double ? 2 : 1);
      if (inMath) {
        flush(at);
        inMath = false;
        emit(TexTokenKind.math, at, end);
      } else {
        emit(TexTokenKind.math, at, end);
        inMath = true;
        plain = end;
      }
      at = end;
      continue;
    }

    if (ch == '{' || ch == '}' || ch == '[' || ch == ']') {
      emit(TexTokenKind.delimiter, at, at + 1);
      at += 1;
      continue;
    }

    if (ch == '&' || ch == '#' || ch == '_' || ch == '^' || ch == '~') {
      emit(TexTokenKind.special, at, at + 1);
      at += 1;
      continue;
    }

    at += 1;
  }

  flush(text.length);
  return tokens;
}
