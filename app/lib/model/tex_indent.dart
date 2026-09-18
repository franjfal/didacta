/// Poner un `.tex` en su sitio: un entorno por línea y sangría por nivel.
///
/// Existe por lo que pasa al traducir. Un traductor devuelve un párrafo en una
/// sola línea --hace lo suyo-- y el fichero sale como un muro: `\begin{frame}`
/// pegado a su contenido, los `\item` seguidos, y nada que deje ver dónde
/// empieza y acaba cada bloque. Eso compila, pero no se lee.
///
/// **Por qué no basta con llamar a `latexindent`.** Es la herramienta buena y
/// se usa cuando está: [LatexIndentRunner] la prueba primero. Pero es un
/// script de Perl con cuatro dependencias de CPAN --`File::HomeDir`,
/// `Log::Log4perl`, `Log::Dispatch`, `Unicode::GCString`-- que MacTeX no
/// instala, así que en una máquina recién montada no arranca. Didacta la usan
/// personas que dan clase, no gente que quiera aprender a usar `cpan` para
/// poder guardar un fichero.
///
/// Así que esto: menos potente y siempre disponible.
///
/// **Lo que no toca, y es la parte que importa.** Dentro de `verbatim`,
/// `lstlisting`, `minted` y compañía el espacio en blanco **es el
/// contenido**: sangrar ahí cambia lo que sale impreso.
///
/// Y no parte ni junta líneas: solo cambia lo que hay al principio de cada
/// una, que es lo único que se puede tocar en un `.tex` sin tocar lo que
/// dice.
library;

import 'tex_outline.dart';
import 'tex_scan.dart';

/// Los entornos cuyo interior se imprime tal cual.
///
/// Uno que falte aquí y lleve espacio significativo saldría reindentado, y eso
/// cambia el PDF sin que nadie lo note hasta verlo impreso. Por eso la lista
/// peca de larga.
const Set<String> verbatimEnvironments = {
  'verbatim',
  'verbatim*',
  'Verbatim',
  'lstlisting',
  'minted',
  'alltt',
  'comment',
  'pycode',
  'sagesilent',
  'asy',
  'filecontents',
  'filecontents*',
};

/// Los entornos que no llevan sangría dentro aunque se cuenten.
///
/// Solo `document`, que envuelve el fichero entero: sangrarlo empuja todo a
/// la derecha sin decir nada, porque no hay nada fuera con lo que contrastar.
///
/// `frame` estuvo aquí y se sacó. El argumento era el mismo --envuelve la
/// diapositiva entera-- pero no se sostiene: una unidad tiene varias
/// diapositivas, así que sí hay con qué contrastar, y sin sangrar dentro no
/// se ve dónde acaba una y empieza la siguiente.
const Set<String> flatEnvironments = {'document'};

/// Indenta un `.tex`. Con [width] espacios por nivel.
///
/// Dos pasadas: primero se pone cada `\begin` y cada `\end` en su línea
/// ([breakLatexLines]), y después se sangra lo que ha quedado. En ese orden
/// porque sangrar mira el principio de cada línea, y un `\begin{definition}`
/// con medio párrafo detrás no tiene principio que valga.
String indentLatex(String text, {int width = 2, int columns = maxColumns}) =>
    wrapLatexProse(
      _indentLines(breakLatexLines(text), width: width),
      columns: columns,
    );

/// Dónde se corta un párrafo largo.
///
/// Ochenta, que es lo de siempre y lo que cabe en media pantalla: un `.tex`
/// se lee al lado del PDF, no a pantalla completa. Y lo que de verdad
/// arreglan es el diff: un párrafo en una sola línea hace que cambiar una
/// palabra salga en el historial como la línea entera, y entonces el
/// historial no dice qué cambió.
const int maxColumns = 80;

String _indentLines(String text, {int width = 2}) {
  final masked = maskLatex(text);
  final lines = text.split('\n');
  final maskedLines = masked.split('\n');

  final out = <String>[];
  var depth = 0;
  String? verbatim;

  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    final clean = i < maskedLines.length ? maskedLines[i] : line;
    final body = clean.trim();

    // Dentro de un entorno verbatim: tal cual, hasta su `\end`.
    if (verbatim != null) {
      out.add(line);
      if (body.startsWith('\\end{$verbatim}')) verbatim = null;
      continue;
    }

    final opens = _environment(body, 'begin');
    if (opens != null && verbatimEnvironments.contains(opens)) {
      out.add(_indented(line, depth, width));
      verbatim = opens;
      continue;
    }

    // Un `\end` al principio de la línea cierra antes de sangrarla, para que
    // quede a la altura de su `\begin` y no un nivel dentro.
    final closes = _environment(body, 'end');
    if (closes != null && !flatEnvironments.contains(closes) && depth > 0) {
      depth -= 1;
    }

    out.add(_indented(line, depth, width));

    if (opens != null && !flatEnvironments.contains(opens)) depth += 1;
  }

  var result = out.join('\n');
  // Nunca más de una línea en blanco seguida: dos separan lo mismo que una y
  // el material migrado está lleno de tres y de cuatro.
  result = result.replaceAll(RegExp(r'\n[ \t]*\n([ \t]*\n)+'), '\n\n');
  return result;
}

/// El nombre del entorno que abre o cierra esta línea, si lo hace.
///
/// Solo al principio: un `\begin{itemize}` en mitad de un párrafo es otra
/// cosa --alguien lo escribió así-- y moverlo sería reescribir su texto.
String? _environment(String body, String what) {
  final match = RegExp('^\\\\$what\\{([^}]*)\\}').firstMatch(body);
  return match?.group(1);
}

/// La línea con la sangría de su nivel.
///
/// Una que acabe en `%` no necesita trato aparte, aunque lo parezca: ese
/// porcentaje se come el salto para que no salga un espacio, y el espacio
/// **inicial** de la línea siguiente lo salta TeX de todas formas. Mover la
/// sangría de la línea de después no cambia nada de lo que se imprime.
String _indented(String line, int depth, int width) {
  final body = line.trim();
  if (body.isEmpty) return '';
  return '${' ' * (depth * width)}$body';
}

/// Pone cada `\begin`, cada `\end` y cada `\item` en su propia línea.
///
/// Esto es lo que la sangría sola no puede arreglar. Un traductor devuelve el
/// párrafo entero en una línea, así que lo que vuelve es
/// `\begin{definition} [Negació...] Si $(a$...` --el entorno, su título y el
/// texto pegados-- y ahí no hay principio de línea que sangrar. Peor: las
/// barras de color del margen marcan dónde empieza y acaba cada entorno **por
/// línea**, así que un entorno que empieza a mitad de una no se puede dibujar.
///
/// **Cuándo es seguro.** Un salto de línea en LaTeX es un espacio, así que
/// esto no se hace a ciegas. Hay dos clases de corte:
///
///  * **Sustituir** el espacio que ya hay por un salto. Es neutro siempre: un
///    espacio, cuatro espacios y un salto de línea son el mismo token para
///    TeX. La mayoría de los cortes son de este tipo.
///  * **Meter** un salto donde no había nada, como en `\end{definition}\dpause`.
///    Eso sí añade un espacio, y solo se hace con entornos que Didacta
///    conoce ([classifyEnvironment]), que son de bloque: terminan en modo
///    vertical y ahí un espacio se descarta. Con un entorno de nadie --uno que
///    se haya definido en el preámbulo de una asignatura-- no se toca, porque
///    podría ser de los que van dentro de una frase.
///
/// Y nunca dentro de un `verbatim`, donde el texto es lo que se imprime, ni
/// dentro de un comentario --un `% \end{itemize}` es prosa tachada, y partir
/// ahí sacaría medio comentario a la luz como código--.
String breakLatexLines(String text) {
  final masked = maskLatex(text);
  final cuts = <int>{};

  var i = 0;
  while (i < masked.length) {
    // Solo se prueba el patrón donde puede empezar. Sin esto son tantas
    // llamadas al motor de expresiones como caracteres tiene el fichero.
    if (masked[i] != '\\') {
      i += 1;
      continue;
    }
    final match = _delimiter.matchAsPrefix(masked, i);
    if (match == null) {
      i += 1;
      continue;
    }
    final opening = match.group(1) == 'begin';
    final name = match.group(2)!;

    // Un entorno verbatim se salta entero: dentro no se corta nada.
    if (opening && verbatimEnvironments.contains(name)) {
      final close = masked.indexOf('\\end{$name}', match.end);
      i = close < 0 ? masked.length : close + '\\end{$name}'.length;
      continue;
    }

    // Solo los entornos que Didacta conoce. Uno que no esté en la lista
    // --definido en el preámbulo de una asignatura, o `math`, que se usa
    // dentro de una frase-- se deja como está: partir `el conjunto
    // \begin{math}A\end{math} es abierto` en tres líneas no lo hace más
    // legible, lo parte por la mitad. Sangrar sí se le hace, porque mover el
    // margen izquierdo no puede cambiar nada.
    if (classifyEnvironment(name) == TexBlockKind.other) {
      i = match.end;
      continue;
    }
    if (opening) {
      final after = _afterArguments(masked, match.end);
      _cut(masked, after, cuts, mayInsert: true);
      // Y antes, para un `\begin` que quedó pegado al final de un párrafo.
      // Solo sustituyendo: meterlo donde no hay nada empujaría el entorno
      // contra el texto anterior con un espacio que no estaba.
      _cut(masked, match.start, cuts, mayInsert: false);
      i = after;
    } else {
      _cut(masked, match.start, cuts, mayInsert: true);
      _cut(masked, match.end, cuts, mayInsert: true);
      i = match.end;
    }
  }

  // `\item` aparte de los entornos: es donde más se pega el texto al traducir
  // una lista, y con una lista en una sola línea no se ve dónde empieza cada
  // punto. Solo sustituyendo espacio: `palabra\item` sin nada en medio no es
  // algo que vaya a arreglar un salto de línea.
  for (final match in _item.allMatches(masked)) {
    _cut(masked, match.start, cuts, mayInsert: false);
  }

  if (cuts.isEmpty) return text;
  final at = cuts.toList()..sort();
  final out = StringBuffer();
  var from = 0;
  for (final cut in at) {
    final left = _whitespaceBefore(text, cut);
    final right = _whitespaceAfter(text, cut);
    if (left < from) continue;
    out
      ..write(text.substring(from, left))
      ..write('\n');
    from = right;
  }
  out.write(text.substring(from));
  return out.toString();
}

/// Un `\begin{...}` o un `\end{...}`. Sobre el enmascarado, donde un `\\`
/// --que es un salto de línea, no una orden-- ya no tiene barras.
final RegExp _delimiter = RegExp(r'\\(begin|end)\s*\{([^}\n]*)\}');

final RegExp _item = RegExp(r'\\item\b');

/// Dónde acaban los argumentos del `\begin` que termina en [from].
///
/// Los salta para no cortar por medio: `\begin{emphaq} [box=...]{equation*}`
/// es una sola cosa, y el corte va detrás de toda ella. Solo en la misma
/// línea --un corchete que abre y no cierra antes del salto no es un
/// argumento-- y solo espacios entre uno y otro.
int _afterArguments(String masked, int from) {
  var at = from;
  while (true) {
    var probe = at;
    while (probe < masked.length &&
        (masked[probe] == ' ' || masked[probe] == '\t')) {
      probe += 1;
    }
    if (probe >= masked.length) return at;
    if (masked[probe] == '{') {
      final close = matchBrace(masked, probe);
      if (close == null) return at;
      at = close + 1;
      continue;
    }
    if (masked[probe] == '[') {
      final close = _matchBracket(masked, probe);
      if (close == null) return at;
      at = close + 1;
      continue;
    }
    return at;
  }
}

/// El `]` que cierra el `[` de [open], sin pasar de la línea.
int? _matchBracket(String masked, int open) {
  var depth = 0;
  for (var i = open; i < masked.length; i += 1) {
    final ch = masked[i];
    if (ch == '\n') return null;
    if (ch == '[') {
      depth += 1;
    } else if (ch == ']') {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// Apunta un corte en [at], si ahí hace falta uno y se puede.
///
/// Hace falta cuando queda texto a los dos lados **en la misma línea**: un
/// `\begin` que ya está solo en la suya no se toca, y cortar donde solo hay
/// espacio a un lado dejaría una línea en blanco, que en LaTeX es un punto y
/// aparte y no un adorno.
void _cut(String masked, int at, Set<int> cuts, {required bool mayInsert}) {
  final left = _whitespaceBefore(masked, at);
  final right = _whitespaceAfter(masked, at);
  if (left == right && !mayInsert) return;
  if (!_textBefore(masked, left) || !_textAfter(masked, right)) return;
  cuts.add(at);
}

int _whitespaceBefore(String text, int at) {
  var i = at;
  while (i > 0 && (text[i - 1] == ' ' || text[i - 1] == '\t')) {
    i -= 1;
  }
  return i;
}

int _whitespaceAfter(String text, int at) {
  var i = at;
  while (i < text.length && (text[i] == ' ' || text[i] == '\t')) {
    i += 1;
  }
  return i;
}

/// Si queda algo escrito antes de [at] en su línea.
bool _textBefore(String masked, int at) {
  for (var i = at - 1; i >= 0; i -= 1) {
    if (masked[i] == '\n') return false;
    if (masked[i] != ' ' && masked[i] != '\t') return true;
  }
  return false;
}

/// Si queda algo escrito después de [at] en su línea.
bool _textAfter(String masked, int at) {
  for (var i = at; i < masked.length; i += 1) {
    if (masked[i] == '\n') return false;
    if (masked[i] != ' ' && masked[i] != '\t') return true;
  }
  return false;
}

/// Junta cada párrafo y lo vuelve a cortar a [columns] columnas.
///
/// Es la mitad del trabajo que la sangría no hace. Lo que devuelve un
/// traductor es el párrafo entero en **una línea**, de cuatrocientos
/// caracteres, y eso no se lee ni se revisa: un cambio de una palabra sale en
/// el historial como la línea completa, así que el diff deja de decir qué
/// cambió.
///
/// **Junta y luego corta**, en ese orden. Solo cortar deja igual de mal un
/// párrafo que ya venía cortado a lo loco --y dos pasadas darían resultados
/// distintos--; juntando primero, el resultado depende del texto y no de
/// cómo estaba escrito antes.
///
/// **Qué no toca**, que es lo que hace que esto sea seguro:
///
///  * Una línea con un comentario. Juntarla con la siguiente metería la
///    siguiente dentro del comentario, y cortar por detrás del `%` sacaría a
///    la luz lo que estaba tachado. Las dos cosas cambian lo que compila.
///  * Una línea que acaba en `\\` o en `%`: ahí el corte es del autor.
///  * `\begin`, `\end`, `\[`, `\]` y lo que haya dentro de un `verbatim`.
///  * `\verb`, donde el texto es lo que se imprime.
///
/// Y **dónde corta**: solo en un espacio que esté fuera de las llaves y fuera
/// de las matemáticas. Partir `\textit{ negació}` por dentro compila igual
/// --el salto es un espacio-- pero deja la orden a un lado y su argumento al
/// otro, que es justo lo que se venía a arreglar. Si en toda la línea no hay
/// ningún sitio bueno, la línea se queda larga: mejor larga que partida por
/// el peor sitio.
String wrapLatexProse(String text, {int columns = maxColumns}) {
  final lines = text.split('\n');
  final out = <String>[];
  String? verbatim;
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    final body = line.trim();

    if (verbatim != null) {
      out.add(line);
      if (body.startsWith('\\end{$verbatim}')) verbatim = null;
      i += 1;
      continue;
    }
    final opens = _environment(body, 'begin');
    if (opens != null && verbatimEnvironments.contains(opens)) {
      out.add(line);
      verbatim = opens;
      i += 1;
      continue;
    }

    if (!_flows(line)) {
      out.add(line);
      i += 1;
      continue;
    }

    // El párrafo: esta línea y las que la siguen mientras sigan siendo
    // prosa. Un `\item` empieza uno nuevo --cada punto de una lista es una
    // cosa-- pero no corta el que ya venía.
    final run = <String>[body];
    var last = i;
    for (var j = i + 1; j < lines.length; j += 1) {
      final next = lines[j];
      if (!_flows(next) || _startsParagraph(next)) break;
      run.add(next.trim());
      last = j;
    }

    final indent = line.length - line.trimLeft().length;
    out.addAll(_wrap(run.join(' '), indent, columns));
    i = last + 1;
  }

  return out.join('\n');
}

/// Si esta línea es prosa que se puede juntar y cortar.
bool _flows(String line) {
  final body = line.trim();
  if (body.isEmpty) return false;
  // Un comentario, entero o al final: se deja como está.
  if (_commentAt(line) != null) return false;
  if (body.contains('\\verb')) return false;
  // Un corte que puso el autor a propósito.
  if (body.endsWith('\\\\')) return false;
  if (body.startsWith('\\begin') || body.startsWith('\\end')) return false;
  // Matemáticas en su propia línea: se quedan en una línea.
  if (body.startsWith('\\[') || body.startsWith('\\]')) return false;
  // Una línea que es **solo** una orden --`\vspace{-2mm}`, `\didactatitle{…}`,
  // `\dpause`-- se queda sola. Juntarla con el párrafo de al lado la esconde
  // en mitad de una frase, y quien escribió el fichero la puso aparte porque
  // hace algo aparte. Distinto de una que **empieza** por una orden y sigue
  // con texto --`\textbf{Nota:} lo demás`--: esa es prosa y fluye.
  if (_isLoneMacro(body)) return false;
  return true;
}

/// Si la línea entera es una sola llamada a una orden y nada más.
bool _isLoneMacro(String body) {
  if (!body.startsWith('\\')) return false;
  var i = 1;
  while (i < body.length && _letter(body.codeUnitAt(i))) {
    i += 1;
  }
  // `\\` o `\,`: una orden de un símbolo. Cuenta igual.
  if (i == 1) i = 2;
  final masked = maskLatex(body);
  final after = _afterArguments(masked, i);
  return body.substring(after.clamp(0, body.length)).trim().isEmpty;
}

/// Si esta línea abre párrafo aunque sea prosa.
bool _startsParagraph(String line) => line.trim().startsWith('\\item');

/// Dónde empieza el comentario de esta línea, si lo hay.
///
/// A mano y no con [maskLatex] porque ahí un `%` de verdad y un `\%` acaban
/// los dos en blanco, y la diferencia es justo la que importa: `\%` es un
/// signo de tanto por ciento en mitad de una frase, y esa frase se junta y se
/// corta como cualquier otra.
int? _commentAt(String line) {
  for (var i = 0; i < line.length; i += 1) {
    if (line[i] == '\\') {
      i += 1;
      continue;
    }
    if (line[i] == '%') return i;
  }
  return null;
}

/// Corta [body] a [columns], sangrando cada trozo con [indent] espacios.
List<String> _wrap(String body, int indent, int columns) {
  final limit = columns - indent;
  final pad = ' ' * indent;
  if (limit < 20 || body.length <= limit) return ['$pad$body'];

  final breaks = _breakPoints(body);
  final out = <String>[];
  var from = 0;
  while (body.length - from > limit) {
    // El último sitio bueno que cabe. Si no hay ninguno --una fórmula larga,
    // una URL-- se va al primero que haya después, y si tampoco hay, la línea
    // se queda larga. Cortar por el peor sitio es peor que no cortar.
    var cut = -1;
    for (final at in breaks) {
      if (at <= from) continue;
      if (at - from <= limit) {
        cut = at;
      } else {
        if (cut < 0) cut = at;
        break;
      }
    }
    if (cut < 0) break;
    out.add('$pad${body.substring(from, cut)}');
    from = cut + 1;
  }
  out.add('$pad${body.substring(from)}');
  return out;
}

/// Los espacios por los que se puede cortar: fuera de llaves y de fórmulas.
List<int> _breakPoints(String body) {
  final masked = maskLatex(body);
  final out = <int>[];
  var braces = 0;
  var dollars = 0;
  var display = false;
  for (var i = 0; i < masked.length; i += 1) {
    final ch = masked[i];
    if (ch == r'\' && i + 1 < masked.length) {
      final next = masked[i + 1];
      if (next == '[' || next == '(') display = true;
      if (next == ']' || next == ')') display = false;
      // Se salta el carácter de detrás siempre: `\$` es un signo de dólar y
      // no el principio de una fórmula, y contarlo desparejaría el resto de
      // la línea.
      i += 1;
      continue;
    }
    if (ch == '{') braces += 1;
    if (ch == '}') braces -= 1;
    if (ch == r'$') dollars += 1;
    if (ch != ' ') continue;
    if (braces > 0 || dollars.isOdd || display) continue;
    // Ni justo detrás de una orden: `\item` y su texto son una cosa, y
    // separarlos no ayuda a leer nada.
    if (i > 0 && _endsControlWord(masked, i)) continue;
    out.add(i);
  }
  return out;
}

/// Si lo que hay justo antes de [at] es el nombre de una orden.
bool _endsControlWord(String masked, int at) {
  var i = at - 1;
  while (i >= 0 && _letter(masked.codeUnitAt(i))) {
    i -= 1;
  }
  return i >= 0 && i < at - 1 && masked[i] == r'\';
}

bool _letter(int code) =>
    (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
