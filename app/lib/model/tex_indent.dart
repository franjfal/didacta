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
/// `document` y `frame` envuelven el fichero entero o la diapositiva entera:
/// sangrarlos empuja todo a la derecha sin decir nada, porque no hay nada
/// fuera con lo que contrastar.
const Set<String> flatEnvironments = {'document', 'frame'};

/// Indenta un `.tex`. Con [width] espacios por nivel.
String indentLatex(String text, {int width = 2}) {
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
