/// Qué se puede mandar a traducir de un `.tex`, y qué no puede tocarse.
///
/// Es la pieza de la que depende que traducir no rompa nada, así que la regla
/// es al revés de lo que parece natural: **se protege por defecto y se
/// traduce por lista**. Un comando que no esté en la lista de los que llevan
/// prosa viaja entero como bloque opaco. Perder una frase por no reconocer un
/// comando es un fallo que se ve y se arregla; mandar `\label{sec:normas}` a
/// Google y recibir `\label{sección:normas}` rompe todas las referencias del
/// tema y no se ve hasta que alguien compila.
///
/// Qué se protege, y por qué cada cosa:
///
/// **Matemáticas.** `$…$`, `\[…\]`, `equation`, `align` y compañía. Un
/// traductor reescribe los espacios y el orden, y `\frac{a}{b}` deja de ser
/// una fracción.
///
/// **Claves.** `\label`, `\ref`, `\cite`, `\includegraphics`, `\input`: su
/// argumento es un identificador, no una palabra. Traducirlo rompe el enlace
/// en silencio.
///
/// **Código y dibujos.** `verbatim`, `lstlisting`, `tikzpicture`: ahí dentro
/// no hay prosa, hay sintaxis.
///
/// **Comentarios.** No salen en el PDF, y el material migrado está lleno de
/// párrafos comentados a propósito.
///
/// Lo que sí se traduce es la prosa suelta y el argumento de los comandos que
/// llevan texto visible: `\textbf`, `\emph`, `\didactatitle`, el título
/// opcional de un teorema.
///
/// Cómo viaja lo protegido: cada trozo opaco se sustituye por una etiqueta
/// `<x id="N"/>`, y la traducción se pide en formato HTML. Es lo que Google y
/// Azure saben respetar --las dos documentan que no tocan las etiquetas-- y
/// además permite comprobarlo al volver: si falta una etiqueta o aparece una
/// que no era, la traducción no se aplica.
library;

import 'tex_scan.dart';

/// Comandos cuyo argumento es prosa que se lee en el PDF.
///
/// Lista blanca a propósito: lo que no esté aquí viaja protegido. Añadir uno
/// es una línea; recuperar un `\label` traducido son todas las referencias
/// del tema.
const Set<String> prosaCommands = {
  'textbf',
  'textit',
  'emph',
  'text',
  'textrm',
  'textsc',
  'underline',
  'caption',
  'footnote',
  'didactatitle',
  'keyterm',
  'hl',
  'onlynotes',
  'onlyslides',
  'section',
  'subsection',
  'subsubsection',
  'paragraph',
  'title',
};

/// Entornos cuyo contenido no es prosa.
const Set<String> opaqueEnvironments = {
  'equation',
  'align',
  'gather',
  'multline',
  'eqnarray',
  'array',
  'matrix',
  'pmatrix',
  'bmatrix',
  'vmatrix',
  'cases',
  'split',
  'verbatim',
  'lstlisting',
  'minted',
  'tikzpicture',
  'axis',
  'pgfplots',
  'picture',
  'tabular',
  'CD',
};

/// Un trozo del fichero: prosa que se traduce, o algo que viaja intacto.
class TexPiece {
  const TexPiece(this.text, {required this.translatable});

  final String text;
  final bool translatable;

  @override
  String toString() => translatable ? 'T(${text.length})' : 'X(${text.length})';
}

/// Un segmento listo para mandar, con lo opaco sustituido por etiquetas.
class ProtectedSegment {
  const ProtectedSegment({
    required this.text,
    required this.parts,
    this.verbatim = false,
  });

  /// Si va tal cual, sin pasar por ningún traductor: los separadores entre
  /// párrafos y lo que no lleva ni una letra.
  final bool verbatim;

  /// Lo que se manda al proveedor: prosa con `<x id="N"/>` donde había
  /// sintaxis.
  final String text;

  /// Lo que hay detrás de cada etiqueta, por su número.
  final List<String> parts;

  bool get isEmpty => text.trim().isEmpty;

  /// Cuántos caracteres de prosa lleva, sin contar las etiquetas.
  int get letters => text.replaceAll(_tag, '').trim().length;

  /// Devuelve el LaTeX, poniendo cada etiqueta en su sitio.
  ///
  /// Null cuando la traducción ha perdido, duplicado o inventado alguna
  /// etiqueta. No se arregla a mano: una etiqueta que falta es un `\ref` que
  /// desapareció, y adivinar dónde iba es peor que no aplicar la traducción.
  String? restore(String translated) {
    final seen = <int>[];
    for (final match in _tag.allMatches(translated)) {
      seen.add(int.parse(match.group(1)!));
    }
    final expected = [for (var i = 0; i < parts.length; i += 1) i];
    if (seen.length != expected.length || !seen.toSet().containsAll(expected)) {
      return null;
    }
    return translated.replaceAllMapped(
      _tag,
      (match) => parts[int.parse(match.group(1)!)],
    );
  }

  static final RegExp _tag = RegExp(r'<x id="(\d+)"/>');

  static String tagFor(int index) => '<x id="$index"/>';
}

/// Parte un `.tex` en prosa y bloques opacos.
///
/// Sobre el texto enmascarado de [maskLatex], que ya sabe qué es comentario y
/// qué es un carácter escapado: sin eso, un `% \begin{align}` dentro de un
/// comentario abriría un bloque matemático que nunca se cierra.
List<TexPiece> splitLatex(String text) {
  final masked = maskLatex(text);
  final pieces = <TexPiece>[];
  final prose = StringBuffer();
  var i = 0;

  void flush() {
    if (prose.isNotEmpty) {
      pieces.add(TexPiece(prose.toString(), translatable: true));
      prose.clear();
    }
  }

  void opaque(int from, int to) {
    flush();
    pieces.add(TexPiece(text.substring(from, to), translatable: false));
  }

  while (i < text.length) {
    // Un comentario: en el enmascarado es un hueco, así que se reconoce
    // porque el original tiene `%` donde la máscara no.
    if (text[i] == '%' && masked[i] != '%') {
      final end = text.indexOf('\n', i);
      opaque(i, end < 0 ? text.length : end);
      i = end < 0 ? text.length : end;
      continue;
    }

    final math = _mathAt(text, masked, i);
    if (math != null) {
      opaque(i, math);
      i = math;
      continue;
    }

    if (masked[i] == r'\') {
      final command = _commandAt(text, masked, i);
      if (command != null) {
        if (command.prose) {
          // El comando y su llave viajan aparte; lo de dentro se traduce.
          opaque(i, command.innerStart);
          final inner = text.substring(command.innerStart, command.innerEnd);
          pieces.addAll(splitLatex(inner));
          opaque(command.innerEnd, command.end);
        } else {
          opaque(i, command.end);
        }
        i = command.end;
        continue;
      }
    }

    prose.write(text[i]);
    i += 1;
  }
  flush();
  return pieces;
}

/// Dónde acaba el bloque matemático que empieza en [at], o null.
int? _mathAt(String text, String masked, int at) {
  if (masked[at] == r'$') {
    final double = masked.startsWith(r'$$', at);
    final close = double ? r'$$' : r'$';
    final from = at + close.length;
    final end = masked.indexOf(close, from);
    return end < 0 ? text.length : end + close.length;
  }
  if (masked.startsWith(r'\[', at)) {
    final end = masked.indexOf(r'\]', at + 2);
    return end < 0 ? text.length : end + 2;
  }
  if (masked.startsWith(r'\(', at)) {
    final end = masked.indexOf(r'\)', at + 2);
    return end < 0 ? text.length : end + 2;
  }
  return null;
}

class _Command {
  const _Command({
    required this.end,
    required this.prose,
    this.innerStart = 0,
    this.innerEnd = 0,
  });

  /// Dónde acaba todo lo que se traga este comando.
  final int end;

  /// Si su argumento es prosa que hay que traducir.
  final bool prose;

  final int innerStart;
  final int innerEnd;
}

final RegExp _name = RegExp(r'^\\([a-zA-Z@]+)\*?');

/// Qué hay en el comando que empieza en [at].
_Command? _commandAt(String text, String masked, int at) {
  final match = _name.firstMatch(masked.substring(at));
  if (match == null) {
    // `\\`, `\,`, `\%`: un carácter, no un comando con argumentos.
    return _Command(end: (at + 2).clamp(0, text.length), prose: false);
  }
  final name = match.group(1)!;
  var cursor = at + match.group(0)!.length;

  // `\begin{align}` se lleva el entorno entero; `\begin{theorem}[Título]` se
  // lleva solo su cabecera, y el título de dentro sí es prosa.
  if (name == 'begin' || name == 'end') {
    final open = _nextBrace(masked, cursor);
    if (open == null) return _Command(end: cursor, prose: false);
    final close = matchBrace(masked, open);
    if (close == null) return _Command(end: text.length, prose: false);
    final environment = text.substring(open + 1, close);
    if (name == 'begin' && opaqueEnvironments.contains(environment)) {
      final marker = masked.indexOf('\\end{$environment}', close);
      return _Command(
        end: marker < 0
            ? text.length
            : marker + '\\end{$environment}'.length,
        prose: false,
      );
    }
    return _Command(end: close + 1, prose: false);
  }

  // Los argumentos opcionales viajan protegidos salvo que el comando lleve
  // prosa: `[Título del teorema]` se lee, `[width=.8\textwidth]` no.
  while (cursor < masked.length && masked[cursor] == '[') {
    final close = masked.indexOf(']', cursor);
    if (close < 0) break;
    cursor = close + 1;
  }

  final open = _nextBrace(masked, cursor, sameLine: true);
  if (open == null) return _Command(end: cursor, prose: false);
  final close = matchBrace(masked, open);
  if (close == null) return _Command(end: text.length, prose: false);

  if (prosaCommands.contains(name)) {
    return _Command(
      end: close + 1,
      prose: true,
      innerStart: open + 1,
      innerEnd: close,
    );
  }
  return _Command(end: close + 1, prose: false);
}

int? _nextBrace(String masked, int from, {bool sameLine = false}) {
  for (var i = from; i < masked.length; i += 1) {
    if (masked[i] == '{') return i;
    if (masked[i] == ' ') continue;
    if (masked[i] == '\n' && !sameLine) continue;
    return null;
  }
  return null;
}

/// Prepara un `.tex` para mandarlo a traducir, párrafo a párrafo.
///
/// Por párrafos y no entero porque es la unidad que la memoria reutiliza: un
/// tema que cambia un párrafo vuelve a traducir uno, no cuarenta. Y porque un
/// documento entero en una sola llamada se pasa de los límites de las dos
/// APIs.
List<ProtectedSegment> protectLatex(String text) {
  final segments = <ProtectedSegment>[];
  final buffer = StringBuffer();
  final parts = <String>[];

  void flush() {
    if (buffer.isNotEmpty) {
      segments.add(
        ProtectedSegment(text: buffer.toString(), parts: List.of(parts)),
      );
      buffer.clear();
      parts.clear();
    }
  }

  for (final piece in splitLatex(text)) {
    if (!piece.translatable) {
      buffer.write(ProtectedSegment.tagFor(parts.length));
      parts.add(piece.text);
      continue;
    }
    // Un párrafo acaba en una línea en blanco, que es lo que LaTeX entiende
    // por párrafo. El separador se guarda **tal cual estaba**: un `\n \n`
    // con un espacio suelto en medio es lo que hay en el fichero, y
    // devolverlo como `\n\n` hace que traducir cambie ficheros que nadie ha
    // tocado. Lo encontró el material de verdad, no un ejemplo.
    var at = 0;
    for (final gap in RegExp(r'\n[ \t]*\n').allMatches(piece.text)) {
      buffer.write(piece.text.substring(at, gap.start));
      flush();
      segments.add(
        ProtectedSegment(text: gap.group(0)!, parts: const [], verbatim: true),
      );
      at = gap.end;
    }
    buffer.write(piece.text.substring(at));
  }
  flush();
  return segments;
}
