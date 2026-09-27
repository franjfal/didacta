/// Lo que va a romper la compilación, dicho antes de compilar.
///
/// Una llave sin cerrar, un `$` de más o un `\begin` sin su `\end` se
/// descubrían compilando: treinta segundos de espera y un error de LaTeX que
/// nombra la línea de la **composición** que incluye la lección, no la de la
/// lección. Esto los busca mientras se escribe, en el fichero que se tiene
/// delante y con la línea de verdad.
///
/// Solo lo que se puede decir con seguridad. Una orden que no se conoce no se
/// avisa: la lista de lo que define LaTeX con sus paquetes es enorme, y un
/// aviso que salta con lo que sí compila enseña a no leer los avisos. Sí se
/// avisa de las que se sabe que en **este** idioma no existen: Didacta carga
/// un solo idioma de babel por compilación, y lo que define uno --el `\lgem`
/// del catalán, el `\og` del francés-- no existe en los demás.
library;

import 'tex_outline.dart';
import 'tex_scan.dart';
import '../l10n/tr.dart';

/// Un aviso, en la línea y la columna donde empieza lo que falla.
class TexWarning {
  const TexWarning({
    required this.offset,
    required this.line,
    required this.column,
    required this.message,
  });

  /// Dónde está en el texto, para llevar allí el cursor.
  final int offset;

  /// Desde 1, como la numera el editor.
  final int line;
  final int column;

  final String message;

  @override
  String toString() => '$line:$column $message';
}

/// El idioma de babel que carga cada idioma de Didacta: `latex/lang/*.def`.
const Map<String, String> babelOf = {
  'es': 'spanish',
  'va': 'catalan',
  'ca': 'catalan',
  'gl': 'galician',
  'en': 'english',
  'fr': 'french',
  'it': 'italian',
  'pt': 'portuguese',
  'de': 'ngerman',
  'eu': 'basque',
};

/// Las órdenes que define un idioma de babel y ningún otro de los que usa
/// Didacta, leídas de sus `.ldf`.
///
/// Las funciones del castellano --`\sen`, `\tg` y compañía-- no están: las
/// define `didacta.sty` en todos los idiomas, precisamente para que una
/// traducción que copia las fórmulas compile.
const Map<String, Set<String>> babelOnly = {
  'sptext': {'spanish', 'galician'},
  'lsc': {'spanish', 'galician'},
  'dotlessi': {'spanish', 'galician'},
  'decimalcomma': {'spanish', 'galician'},
  'decimalpoint': {'spanish', 'galician'},
  'accentedoperators': {'spanish', 'galician'},
  'unaccentedoperators': {'spanish', 'galician'},
  'spanishoperators': {'spanish'},
  'spanishdeactivate': {'spanish'},
  'spanishdecimal': {'spanish'},
  'lgem': {'catalan'},
  'Lgem': {'catalan'},
  'og': {'french'},
  'fg': {'french'},
  'ier': {'french'},
  'iere': {'french'},
  'ieme': {'french'},
  'iemes': {'french'},
  'bsc': {'french'},
  'nombre': {'french'},
};

const Map<String, String> _babelName = {
  'spanish': 'castellano',
  'galician': 'gallego',
  'catalan': 'catalán y valenciano',
  'french': 'francés',
};

/// Los entornos cuyo contenido no es LaTeX: lo que haya dentro no cuenta.
const Set<String> _verbatim = {
  'verbatim',
  'verbatim*',
  'Verbatim',
  'lstlisting',
  'minted',
  'comment',
};

/// Todo lo que se sabe que va a fallar en [text], en el orden del texto.
///
/// [language] es el de la pestaña, para las órdenes que solo existen en otro.
List<TexWarning> checkTex(String text, {String? language}) {
  final masked = _withoutVerbatim(maskLatex(text));
  final lines = _LineIndex(text);
  final found = <TexWarning>[];

  void warn(int offset, String message) {
    final (line, column) = lines.at(offset);
    found.add(
      TexWarning(offset: offset, line: line, column: column, message: message),
    );
  }

  // Los entornos, del árbol que ya pinta de rojo el `\begin` sin cerrar.
  final outline = TexOutline.ofText(text);
  for (final issue in outline.issues) {
    final offset = issue.line < outline.lineStarts.length
        ? outline.lineStarts[issue.line]
        : 0;
    warn(offset, '${_capital(issue.message)}.');
  }

  final braces = <int>[];

  // La fórmula abierta, si hay una: qué la abrió y dónde.
  String? math;
  var mathAt = 0;

  void closeParagraph() {
    if (math == null) return;
    warn(
      mathAt,
      tr('{0} no se cierra antes del final del párrafo.', [_opened(math!)]),
    );
    math = null;
  }

  final babel = language == null ? null : babelOf[language];
  var i = 0;
  // Si la línea que se lee está en blanco **en el fichero**: una con solo un
  // comentario no lo está, y para LaTeX no acaba el párrafo.
  var blank = true;
  while (i < masked.length) {
    final ch = masked[i];
    if (ch == '\n') {
      // Una línea en blanco acaba el párrafo, y una fórmula no puede cruzarlo:
      // es donde LaTeX dice «Missing $ inserted».
      if (blank) closeParagraph();
      blank = true;
      i += 1;
      continue;
    }
    final original = text[i];
    if (original != ' ' && original != '\t' && original != '\r') {
      blank = false;
    }

    if (ch == r'\' && i + 1 < masked.length) {
      final next = masked[i + 1];
      if (_isLetter(next)) {
        var end = i + 1;
        while (end < masked.length && _isLetter(masked[end])) {
          end += 1;
        }
        final name = masked.substring(i + 1, end);
        final only = babelOnly[name];
        if (babel != null && only != null && !only.contains(babel)) {
          final where = only.map((b) => tr(_babelName[b] ?? b)).join(tr(' y '));
          warn(
            i,
            tr('«\\{0}» es del {1}: en este idioma no existe.', [name, where]),
          );
        }
        if (name == 'par') closeParagraph();
        i = end;
        continue;
      }
      switch (next) {
        case '(':
        case '[':
          if (math == null) {
            math = '\\$next';
            mathAt = i;
          }
        case ')':
        case ']':
          final opener = next == ')' ? r'\(' : r'\[';
          if (math == opener) {
            math = null;
          } else {
            warn(
              i,
              tr('«\\{0}» cierra una fórmula que no se ha abierto.', [next]),
            );
          }
      }
      i += 2;
      continue;
    }

    switch (ch) {
      case '{':
        braces.add(i);
      case '}':
        if (braces.isEmpty) {
          warn(i, tr('Una llave «}» que no abre nada.'));
        } else {
          braces.removeLast();
        }
      case r'$':
        final twice = i + 1 < masked.length && masked[i + 1] == r'$';
        final token = twice ? r'$$' : r'$';
        if (math == null) {
          math = token;
          mathAt = i;
        } else if (math == token) {
          math = null;
        } else if (math == r'$$' && !twice) {
          // Un `$` suelto dentro de `$$…$$`: lo más probable es que falte el
          // segundo del cierre.
          warn(i, tr('La fórmula «\$\$» se cierra con un solo «\$».'));
          math = null;
        }
        i += twice ? 2 : 1;
        continue;
    }
    i += 1;
  }
  if (math != null) {
    warn(mathAt, tr('{0} no se cierra.', [_opened(math!)]));
  }
  for (final open in braces) {
    warn(open, tr('Una llave «{» que no se cierra.'));
  }

  found.sort((a, b) => a.offset.compareTo(b.offset));
  return found;
}

String _opened(String token) => switch (token) {
  r'$' => tr('La fórmula que abre «\$»'),
  r'$$' => tr('La fórmula que abre «\$\$»'),
  r'\(' => tr(r'La fórmula que abre «\(»'),
  _ => tr(r'La fórmula que abre «\[»'),
};

String _capital(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

bool _isLetter(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

/// El texto enmascarado, con el contenido de los entornos literales y de
/// `\verb` también en blanco.
String _withoutVerbatim(String masked) {
  final out = masked.split('');
  void blankOut(int from, int to) {
    for (var i = from; i < to && i < out.length; i += 1) {
      if (out[i] != '\n') out[i] = ' ';
    }
  }

  final begin = RegExp(r'\\begin\{([^}]*)\}');
  var from = 0;
  for (final match in begin.allMatches(masked)) {
    // Un `\begin` dentro de un literal ya tapado no abre nada.
    if (match.start < from) continue;
    final name = match.group(1)!;
    if (!_verbatim.contains(name)) continue;
    final close = masked.indexOf('\\end{$name}', match.end);
    final end = close < 0 ? masked.length : close;
    blankOut(match.end, end);
    from = end;
  }

  final verb = RegExp(r'\\verb\*?(\S)');
  for (final match in verb.allMatches(masked)) {
    final delimiter = match.group(1)!;
    final close = masked.indexOf(delimiter, match.end);
    final lineEnd = masked.indexOf('\n', match.end);
    final end = close < 0 || (lineEnd >= 0 && lineEnd < close)
        ? (lineEnd < 0 ? masked.length : lineEnd)
        : close + 1;
    blankOut(match.start, end);
  }
  return out.join();
}

/// De un desplazamiento a línea y columna, desde 1.
class _LineIndex {
  _LineIndex(String text) {
    for (var i = 0; i < text.length; i += 1) {
      if (text[i] == '\n') _starts.add(i + 1);
    }
  }

  final List<int> _starts = [0];

  (int, int) at(int offset) {
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return (low + 1, offset - _starts[low] + 1);
  }
}

/// Los entornos que son una fórmula.
const Set<String> _mathEnvironments = {
  'equation',
  'equation*',
  'align',
  'align*',
  'alignat',
  'alignat*',
  'flalign',
  'flalign*',
  'gather',
  'gather*',
  'multline',
  'multline*',
  'eqnarray',
  'eqnarray*',
  'displaymath',
  'math',
};

/// Las órdenes que, dentro de una fórmula, vuelven al texto.
const Set<String> _textInMath = {
  'text',
  'textrm',
  'textit',
  'textbf',
  'textsf',
  'texttt',
  'mbox',
  'intertext',
};

/// Si [offset] cae dentro de una fórmula.
///
/// Es lo que decide si la paleta escribe `\alpha` tal cual o envuelto en
/// `$…$`: fuera de una fórmula, un `\alpha` suelto es un error de
/// compilación. Dentro de un `\text{…}` de una fórmula se está otra vez en el
/// texto, y un `$` ahí abre otra.
bool inMathAt(String text, int offset) {
  final masked = _withoutVerbatim(maskLatex(text));
  final end = offset.clamp(0, masked.length);

  // Lo que está abierto, de fuera adentro: `null` es el texto de un
  // `\text{…}`, que se cierra con su llave; lo demás es con qué se cierra la
  // fórmula abierta.
  final modes = <({String? closer, int depth})>[];
  var depth = 0;
  bool inMath() => modes.isNotEmpty && modes.last.closer != null;

  var i = 0;
  var blank = true;
  while (i < end) {
    final ch = masked[i];
    if (ch == '\n') {
      // Un párrafo nuevo lo cierra todo: una fórmula no puede cruzarlo.
      if (blank) modes.clear();
      blank = true;
      i += 1;
      continue;
    }
    if (text[i] != ' ' && text[i] != '\t' && text[i] != '\r') blank = false;

    if (ch == r'\' && i + 1 < masked.length) {
      final next = masked[i + 1];
      if (_isLetter(next)) {
        var stop = i + 1;
        while (stop < masked.length && _isLetter(masked[stop])) {
          stop += 1;
        }
        final name = masked.substring(i + 1, stop);
        if ((name == 'begin' || name == 'end') &&
            stop < masked.length &&
            masked[stop] == '{') {
          final close = masked.indexOf('}', stop);
          if (close > 0) {
            final environment = masked.substring(stop + 1, close);
            if (_mathEnvironments.contains(environment)) {
              if (name == 'begin' && !inMath()) {
                modes.add((closer: 'end:$environment', depth: depth));
              } else if (name == 'end' &&
                  modes.isNotEmpty &&
                  modes.last.closer == 'end:$environment') {
                modes.removeLast();
              }
            }
            i = close + 1;
            continue;
          }
        }
        if (_textInMath.contains(name) && inMath()) {
          var brace = stop;
          while (brace < masked.length && masked[brace] == ' ') {
            brace += 1;
          }
          if (brace < masked.length && masked[brace] == '{') {
            depth += 1;
            modes.add((closer: null, depth: depth));
            i = brace + 1;
            continue;
          }
        }
        i = stop;
        continue;
      }
      if ((next == '(' || next == '[') && !inMath()) {
        modes.add((closer: next == '(' ? r'\)' : r'\]', depth: depth));
      } else if ((next == ')' || next == ']') &&
          modes.isNotEmpty &&
          modes.last.closer == '\\$next') {
        modes.removeLast();
      }
      i += 2;
      continue;
    }

    if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      if (modes.isNotEmpty &&
          modes.last.closer == null &&
          modes.last.depth == depth) {
        modes.removeLast();
      }
      depth -= 1;
    } else if (ch == r'$') {
      final twice = i + 1 < masked.length && masked[i + 1] == r'$';
      if (inMath() && modes.last.closer == r'$') {
        modes.removeLast();
      } else if (inMath() && modes.last.closer == r'$$' && twice) {
        modes.removeLast();
        i += 2;
        continue;
      } else if (!inMath()) {
        modes.add((closer: twice ? r'$$' : r'$', depth: depth));
        if (twice) {
          i += 2;
          continue;
        }
      }
    }
    i += 1;
  }
  return inMath();
}
