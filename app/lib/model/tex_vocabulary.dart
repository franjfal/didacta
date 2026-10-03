/// Lo que se puede escribir en una lección, para completarlo al teclear.
///
/// La lista cerrada de `docs/AUTHORING.md` --órdenes y entornos de Didacta--
/// más las órdenes de las paletas de matemáticas y de símbolos. Cerrada a
/// propósito: completar con todo lo que define LaTeX con sus paquetes sería
/// ofrecer mil cosas que en una lección de Didacta no se usan, y esconder
/// entre ellas las veinte que sí. Un test comprueba que lo que dice
/// `AUTHORING.md` está aquí, para que las dos listas no se separen.
library;

import 'tex_scan.dart';
import 'tex_snippets.dart';
import 'tex_wrap.dart' show TexEdit;
import '../l10n/tr.dart';

/// Una orden o un entorno que se ofrece al completar.
class TexWord {
  const TexWord(this.name, this._detail, {this.arguments = ''});

  /// Sin la barra: `didactatitle`, `theorem`.
  final String name;

  /// Qué es, en pocas palabras, en el idioma de la interfaz.
  String get detail => tr(_detail);
  final String _detail;

  /// Lo que se escribe detrás del nombre, con el cursor en la primera llave:
  /// `{}` para una orden de un argumento, `{}{}` para dos. Vacío en una orden
  /// sin argumentos, que lleva un espacio detrás para no pegarse a lo que
  /// siga.
  final String arguments;
}

/// Las órdenes de Didacta, en el orden en que se ofrecen cuando empatan.
const List<TexWord> didactaCommands = [
  TexWord(
    'didactatitle',
    'Título de la diapositiva o del apartado',
    arguments: '{}',
  ),
  TexWord(
    'slidetitle',
    'Título solo de la diapositiva; en los apuntes, nada',
    arguments: '{}',
  ),
  TexWord('dpause', 'Pausa: revela lo siguiente en las diapositivas'),
  TexWord('onlyslides', 'Solo en las diapositivas', arguments: '{}'),
  TexWord('onlynotes', 'Solo en los apuntes', arguments: '{}'),
  TexWord('onlyteacher', 'Solo en las copias del profesor', arguments: '{}'),
  TexWord('onlystudent', 'Todo menos las copias del profesor', arguments: '{}'),
  TexWord(
    'onlyfull',
    'Solo con el detalle completo (no en un examen)',
    arguments: '{}',
  ),
  TexWord('onlybrief', 'Solo con el detalle reducido', arguments: '{}'),
  TexWord(
    'slidesandteacher',
    'Diapositivas o copia del profesor',
    arguments: '{}',
  ),
  TexWord('notesandteacher', 'Apuntes o copia del profesor', arguments: '{}'),
  TexWord(
    'bymedium',
    'Versión corta en diapositivas, larga en los apuntes',
    arguments: '{}{}',
  ),
  TexWord('keyterm', 'El término que se está definiendo', arguments: '{}'),
  TexWord('hl', 'Resaltado', arguments: '{}'),
  TexWord('timing', 'Duración, para el profesor', arguments: '{}'),
  TexWord('dmarks', 'Puntuación, solo en los exámenes', arguments: '{}'),
  TexWord(
    'answerspace',
    'Espacio para responder, solo en el examen',
    arguments: '{}',
  ),
  TexWord('item', 'Un elemento de una lista o un apartado'),
  TexWord('begin', 'Empieza un entorno', arguments: '{}'),
  TexWord('end', 'Cierra un entorno', arguments: '{}'),
  // Con su texto alternativo delante: es lo que lee un lector de pantalla en
  // el PDF accesible y en el HTML, y el cursor empieza ahí.
  TexWord(
    'includegraphics',
    'Una figura de figures/, con lo que se ve en ella',
    arguments: '[alt={}]{}',
  ),
  TexWord('cite', 'Cita de la bibliografía', arguments: '{}'),
  TexWord('cites', 'Varias citas', arguments: '{}'),
  TexWord('textcite', 'Cita dentro de la frase', arguments: '{}'),
  TexWord('didactaprofilebanner', 'Los ejes activos, para depurar'),
  TexWord('sen', 'Seno, con su nombre en cada idioma'),
  TexWord('tg', 'Tangente, con su nombre en cada idioma'),
  TexWord('arcsen', 'Arco seno'),
  TexWord('arctg', 'Arco tangente'),
  TexWord('cotg', 'Cotangente'),
  TexWord('cosec', 'Cosecante'),
  TexWord('senh', 'Seno hiperbólico'),
  TexWord('tgh', 'Tangente hiperbólica'),
  TexWord('textbf', 'Negrita', arguments: '{}'),
  TexWord('emph', 'Énfasis', arguments: '{}'),
  TexWord('footnote', 'Nota al pie', arguments: '{}'),
];

/// Los entornos de Didacta, con cómo se llaman en castellano.
const List<TexWord> didactaEnvironments = [
  TexWord('frame', 'Una diapositiva'),
  TexWord('theorem', 'Teorema'),
  TexWord('definition', 'Definición'),
  TexWord('proposition', 'Proposición'),
  TexWord('lemma', 'Lema'),
  TexWord('corollary', 'Corolario'),
  TexWord('property', 'Propiedad'),
  TexWord('example', 'Ejemplo'),
  TexWord('question', 'Cuestión'),
  TexWord('remark', 'Nota'),
  TexWord('axiom', 'Axioma'),
  TexWord('algorithm', 'Algoritmo'),
  TexWord('notation', 'Notación'),
  TexWord('keypoint', 'Recuadro sin número ni etiqueta'),
  TexWord('proof', 'Demostración'),
  TexWord('tikzpicture', 'Un dibujo, con [alt={…}]: lo que se ve en él'),
  TexWord('keyformula', 'Fórmula destacada'),
  TexWord('exercise', 'Ejercicio'),
  TexWord('parts', 'Apartados (i), (ii), (iii)'),
  TexWord('hint', 'Pista'),
  TexWord('answer', 'Resultado'),
  TexWord('solution', 'Solución detallada'),
  TexWord('marking', 'Criterios de corrección'),
  TexWord('teaching', 'Nota didáctica, solo para el profesor'),
  TexWord('commonmistake', 'Error frecuente, solo para el profesor'),
  TexWord('objectives', 'Objetivos de la lección'),
  TexWord('prerequisites', 'Lo que la lección da por sabido'),
  TexWord('summary', 'Resumen'),
  TexWord('notesonly', 'Solo en los apuntes, con párrafos'),
  TexWord('slidesonly', 'Solo en las diapositivas, con párrafos'),
  TexWord('teacheronly', 'Solo para el profesor, con párrafos'),
  TexWord('studentonly', 'Todo menos el profesor, con párrafos'),
  TexWord('fullonly', 'Solo con el detalle completo, con párrafos'),
  TexWord('itemize', 'Lista con viñetas'),
  TexWord('enumerate', 'Lista numerada'),
  TexWord('align*', 'Fórmulas alineadas, sin numerar'),
  TexWord('equation*', 'Fórmula aparte, sin numerar'),
  TexWord('cases', 'Definición por casos'),
  TexWord('pmatrix', 'Matriz entre paréntesis'),
];

/// Todas las órdenes que se ofrecen: las de Didacta y las de las paletas.
///
/// De las paletas, las que son una sola orden (`\alpha`, `\frac{}{}`), sin
/// repetir las que ya están arriba.
final List<TexWord> texCommands = () {
  final seen = {for (final word in didactaCommands) word.name};
  final words = [...didactaCommands];
  for (final palette in [texMathPalette, ...texSymbolPalettes]) {
    for (final snippet in palette.items) {
      final match = RegExp(
        r'^\\([A-Za-z]+)(.*)$',
      ).firstMatch(snippet.before.trimRight());
      if (match == null) continue;
      final name = match.group(1)!;
      if (!seen.add(name)) continue;
      // Lo que va detrás, con las llaves vacías: `\frac{` y `}{}` son
      // `\frac{}{}`, y `\mathbb{R}` se ofrece como `\mathbb{}`.
      final rest = (match.group(2)! + snippet.after).replaceAll(
        RegExp(r'\{[^{}]*\}'),
        '{}',
      );
      words.add(
        TexWord(
          name,
          snippet.tooltip ?? snippet.label,
          arguments: rest.startsWith('{') || rest.startsWith('_') ? rest : '',
        ),
      );
    }
  }
  return List<TexWord>.unmodifiable(words);
}();

/// Lo que empieza por [prefix] tal cual, después lo que empieza sin mirar
/// mayúsculas --`\Om` encuentra `\Omega` y luego `\omega`-- y al final lo
/// que lo contiene. Como mucho [limit].
///
/// Una orden ya escrita entera y sin otra más larga no se ofrece: `\item`
/// seguido de Intro es un salto de línea, no una sugerencia que aceptar.
List<TexWord> completionsFor(
  String prefix,
  List<TexWord> words, {
  int limit = 8,
}) {
  final wanted = prefix.toLowerCase();
  final exact = <TexWord>[];
  final folded = <TexWord>[];
  final inside = <TexWord>[];
  for (final word in words) {
    final name = word.name.toLowerCase();
    if (word.name.startsWith(prefix)) {
      exact.add(word);
    } else if (name.startsWith(wanted)) {
      folded.add(word);
    } else if (wanted.length > 2 && name.contains(wanted)) {
      // Con tres letras por lo menos: con dos, «te» encuentra media lista.
      inside.add(word);
    }
  }
  final found = [...exact, ...folded, ...inside];
  if (found.length == 1 && found.single.name == prefix) return const [];
  return found.take(limit).toList();
}

/// Qué se está completando.
enum TexCompletionKind {
  /// Una orden: `\didac`.
  command,

  /// El nombre de un entorno que se abre: `\begin{teo`.
  begin,

  /// El de uno que se cierra: `\end{`.
  end,
}

/// Lo que se está escribiendo junto al cursor, y lo que se puede ofrecer.
class TexCompletionQuery {
  const TexCompletionQuery({
    required this.kind,
    required this.start,
    required this.end,
    required this.prefix,
    required this.words,
  });

  final TexCompletionKind kind;

  /// Dónde empieza lo escrito --justo detrás de la barra o de la llave-- y
  /// dónde está el cursor.
  final int start;
  final int end;
  final String prefix;
  final List<TexWord> words;
}

final RegExp _environmentPrefix = RegExp(r'\\(begin|end)\{([A-Za-z*]*)$');

/// Lo que hay que completar en [caret], o null si no hay nada.
///
/// Una orden se ofrece a partir de la primera letra: con la barra sola
/// saldría en cada `\\` de fin de línea. El nombre de un entorno, en cuanto
/// se abre la llave de `\begin{`, que es cuando no se sabe cómo se llamaba.
TexCompletionQuery? completionAt(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final lineStart = text.lastIndexOf('\n', caret == 0 ? 0 : caret - 1) + 1;
  final before = text.substring(lineStart, caret);

  final environment = _environmentPrefix.firstMatch(before);
  if (environment != null) {
    final prefix = environment.group(2)!;
    final kind = environment.group(1) == 'begin'
        ? TexCompletionKind.begin
        : TexCompletionKind.end;
    var words = completionsFor(prefix, didactaEnvironments, limit: 40);
    if (kind == TexCompletionKind.end) {
      // El que está abierto, primero: casi siempre es el que se cierra.
      final open = _openEnvironments(
        text.substring(0, lineStart + environment.start),
      );
      final innermost = open.isEmpty ? null : open.last;
      if (innermost != null && innermost.startsWith(prefix)) {
        words = [
          TexWord(innermost, tr('El que está abierto aquí')),
          ...words.where((word) => word.name != innermost),
        ];
      }
    }
    return TexCompletionQuery(
      kind: kind,
      start: caret - prefix.length,
      end: caret,
      prefix: prefix,
      words: words.take(8).toList(),
    );
  }

  var start = caret;
  while (start > lineStart && _isLetter(text[start - 1])) {
    start -= 1;
  }
  if (start == caret || start == lineStart || text[start - 1] != '\\') {
    return null;
  }
  // `\\item` es un salto de línea seguido de «item», no la orden `\item`:
  // la barra de delante tiene que ser la primera de su tanda.
  var slashes = 0;
  for (var i = start - 1; i >= lineStart && text[i] == '\\'; i -= 1) {
    slashes += 1;
  }
  if (slashes.isEven) return null;
  final prefix = text.substring(start, caret);
  final words = completionsFor(prefix, texCommands);
  if (words.isEmpty) return null;
  return TexCompletionQuery(
    kind: TexCompletionKind.command,
    start: start,
    end: caret,
    prefix: prefix,
    words: words,
  );
}

/// El texto con [word] puesta en lugar de lo escrito, y el cursor donde se
/// sigue escribiendo.
///
/// Una orden con argumentos deja el cursor en la primera llave; sin ellos,
/// un espacio detrás para no pegarse a lo que venga. Un entorno que se abre
/// escribe también su `\end`, con una línea en blanco en medio para el
/// cuerpo, sin sangrar: la sangría es de la vista y no se guarda.
TexEdit acceptCompletion(String text, TexCompletionQuery query, TexWord word) {
  final head = text.substring(0, query.start);
  var tail = text.substring(query.end);
  switch (query.kind) {
    case TexCompletionKind.command:
      final arguments = word.arguments;
      if (arguments.isEmpty) {
        final spaced = tail.startsWith(' ') || tail.startsWith('\n');
        final written = '${word.name}${spaced ? '' : ' '}';
        return TexEdit(
          '$head$written$tail',
          head.length + written.length,
          head.length + written.length,
        );
      }
      final brace = arguments.indexOf('{');
      final cursor = head.length + word.name.length + brace + 1;
      return TexEdit('$head${word.name}$arguments$tail', cursor, cursor);
    case TexCompletionKind.begin:
    case TexCompletionKind.end:
      // Si la llave ya estaba cerrada --`\begin{}` completado antes como
      // orden--, se usa esa y no se escribe otra.
      if (tail.startsWith('}')) tail = tail.substring(1);
      if (query.kind == TexCompletionKind.end) {
        final written = '${word.name}}';
        final cursor = head.length + written.length;
        return TexEdit('$head$written$tail', cursor, cursor);
      }
      final written = '${word.name}}\n';
      final cursor = head.length + written.length;
      return TexEdit('$head$written\n\\end{${word.name}}$tail', cursor, cursor);
  }
}

/// Los entornos abiertos al final de [text], de fuera adentro.
List<String> _openEnvironments(String text) {
  final open = <String>[];
  final pattern = RegExp(r'\\(begin|end)\{([^}]*)\}');
  for (final match in pattern.allMatches(maskLatex(text))) {
    final name = match.group(2)!;
    if (match.group(1) == 'begin') {
      open.add(name);
    } else {
      final at = open.lastIndexOf(name);
      if (at >= 0) open.removeRange(at, open.length);
    }
  }
  return open;
}

bool _isLetter(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}
