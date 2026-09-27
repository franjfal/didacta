/// Lo que un snippet puede romper después de escribirlo.
///
/// La barra escribe bien lo que escribe; lo que viene después es de quien
/// edita. Un `\end` borrado o una llave de menos ya los avisa [checkTex], que
/// no sabe nada de snippets y no le hace falta. Esto es lo que **solo** se
/// sabe conociéndolos:
///
/// * **Un snippet de otro repositorio.** El texto usa `\begin{resumen}`, que
///   define un snippet del repositorio de al lado y no de este. En la
///   máquina de quien lo escribió compila --tiene los dos abiertos-- y en la
///   del resto no, porque la definición solo entra al compilar su
///   repositorio. Es el mismo problema que una lección que llama fuera, y
///   se descubre igual de tarde si nadie lo dice.
/// * **Un snippet sin sus argumentos.** Uno que declara `{Título}` detrás de
///   `\begin{frame}` no es el mismo sin él: LaTeX se come la primera palabra
///   del cuerpo como título, y el PDF sale sin error y mal.
///
/// Solo avisos seguros, como en [checkTex]: un entorno que no se conoce no
/// se avisa, porque puede venir de cualquier paquete.
library;

import 'latex_snippets.dart';
import 'tex_check.dart' show TexWarning;
import 'tex_scan.dart';
import '../l10n/tr.dart';

/// Los avisos de snippets de [text], en el orden del texto.
///
/// [here] son los que ofrece el repositorio del fichero; [library], todos
/// los de los repositorios abiertos.
List<TexWarning> checkSnippets(
  String text, {
  required List<LatexSnippet> here,
  required List<SnippetEntry> library,
  String Function(String repo)? repoName,
}) {
  final masked = maskLatex(text);
  final found = <TexWarning>[];
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i += 1) {
    if (text[i] == '\n') lineStarts.add(i + 1);
  }

  void warn(int offset, String message) {
    var line = 0;
    while (line + 1 < lineStarts.length && lineStarts[line + 1] <= offset) {
      line += 1;
    }
    found.add(
      TexWarning(
        offset: offset,
        line: line + 1,
        column: offset - lineStarts[line] + 1,
        message: message,
      ),
    );
  }

  final mine = {for (final snippet in here) snippet.id};
  // Los nombres que este repositorio sí conoce, sean del snippet que sean:
  // uno de otro repositorio con el mismo entorno que uno de aquí no es un
  // problema.
  final known = <String>{
    for (final snippet in here) ...[
      ?snippet.environment,
      ...snippet.environmentAliases,
      if (snippet.command != null) '\\${snippet.command}',
      for (final name in snippet.commandAliases) '\\$name',
    ],
  };

  for (final entry in library) {
    if (mine.contains(entry.id) || entry.byRepo.isEmpty) continue;
    final snippet = entry.shown;
    // Uno sin definición lo define otro --Didacta o un paquete-- y compila
    // igual en cualquier repositorio.
    if (snippet.definition.trim().isEmpty) continue;
    final where = [
      for (final repo in entry.byRepo.keys) repoName?.call(repo) ?? repo,
    ].join(', ');
    for (final name in [?snippet.environment, ...snippet.environmentAliases]) {
      if (known.contains(name)) continue;
      final at = masked.indexOf('\\begin{$name}');
      if (at < 0) continue;
      warn(
        at,
        tr(
          '«{0}» es un snippet de {1} y no de este '
          'repositorio: aquí no compila. Añádelo a este en Ajustes → '
          'Snippets de LaTeX, o usa otro.',
          [snippet.label, where],
        ),
      );
    }
    for (final name in [?snippet.command, ...snippet.commandAliases]) {
      if (known.contains('\\$name')) continue;
      final at = _commandAt(masked, name);
      if (at < 0) continue;
      warn(
        at,
        tr(
          '«{0}» (\\{1}) es un snippet de {2} y no de este '
          'repositorio: aquí no compila.',
          [snippet.label, name, where],
        ),
      );
    }
  }

  // Los argumentos que pide cada entorno: los **menos** que pida alguno de
  // los snippets de aquí. Con «Diapositiva» (`frame`) y «Diapositiva con
  // título» (`frame{Título}`) en la misma barra, un `frame` sin título es el
  // primero, no el segundo mal escrito.
  final fewest = <String, int>{};
  for (final snippet in here) {
    final braces = _braceCount(snippet.arguments);
    for (final name in [?snippet.environment, ...snippet.environmentAliases]) {
      final known = fewest[name];
      if (known == null || braces < known) fewest[name] = braces;
    }
  }

  for (final snippet in here) {
    final braces = _braceCount(snippet.arguments);
    if (braces == 0) continue;
    for (final name in [?snippet.environment, ...snippet.environmentAliases]) {
      if ((fewest[name] ?? 0) < braces) continue;
      final open = '\\begin{$name}';
      var from = 0;
      while (true) {
        final at = masked.indexOf(open, from);
        if (at < 0) break;
        from = at + open.length;
        if (_bracesAfter(masked, from) < braces) {
          warn(
            at,
            tr(
              '«{0}» lleva {1} detrás de '
              '\\begin{{2}}, y aquí falta: LaTeX tomará el principio del '
              'texto por el argumento.',
              [snippet.label, snippet.arguments, name],
            ),
          );
        }
      }
    }
  }

  found.sort((a, b) => a.offset.compareTo(b.offset));
  return found;
}

/// Dónde se usa `\name`, y no `\namefoo`; -1 si no.
int _commandAt(String masked, String name) {
  final needle = '\\$name';
  var from = 0;
  while (true) {
    final at = masked.indexOf(needle, from);
    if (at < 0) return -1;
    final end = at + needle.length;
    if (end >= masked.length || !_isLetter(masked[end])) return at;
    from = end;
  }
}

/// Cuántos argumentos `{…}` hay detrás de [from], saltando los `[…]`.
int _bracesAfter(String masked, int from) {
  var count = 0;
  var i = from;
  while (i < masked.length) {
    final ch = masked[i];
    if (ch == '[') {
      final shut = masked.indexOf(']', i);
      if (shut < 0) break;
      i = shut + 1;
      continue;
    }
    if (ch == '{') {
      final shut = matchBrace(masked, i);
      if (shut == null) break;
      count += 1;
      i = shut + 1;
      continue;
    }
    break;
  }
  return count;
}

int _braceCount(String arguments) {
  var count = 0;
  var depth = 0;
  for (var i = 0; i < arguments.length; i += 1) {
    final ch = arguments[i];
    if (ch == r'\') {
      i += 1;
    } else if (ch == '{') {
      if (depth == 0) count += 1;
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
    }
  }
  return count;
}

bool _isLetter(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || ch == '@';
}
