/// Envolver y desenvolver: lo que hace la barra del editor.
///
/// Didacta ya tenía las macros —`\onlyslides`, `\onlynotes`, `answer`,
/// `solution`, `teacheronly`— y no tenía ninguna superficie para tocarlas:
/// 772 ficheros migrados las usan y se escribían a mano, letra a letra. Esto
/// es lo que la barra llama.
///
/// Tres decisiones que dan forma al fichero:
///
/// **Un botón es un interruptor, no una plantilla.** Pulsar sobre una
/// selección que ya está envuelta la desenvuelve. Sin eso la barra solo sabe
/// añadir, y quitar sigue siendo trabajo de teclado —que es exactamente el
/// trabajo que venía a ahorrar—.
///
/// **La forma la elige el envoltorio, no la persona.** `\onlyslides{...}` se
/// rompe con un cuerpo que tenga `\par`, verbatim o un cambio de catcode, y
/// por eso `didacta-formats.sty` define además `slidesonly` como entorno. La
/// regla es mecánica: si la selección tiene una línea en blanco o un
/// `\begin`, entorno; si es una frase suelta, macro. Nadie tiene que
/// acordarse.
///
/// **Los nombres heredados cuentan.** `\onlybook` es `\onlynotes` y `ej` es
/// `exercise` en el material migrado (D19). Desenvolver tiene que
/// reconocerlos o el botón no funciona justo en los ficheros donde más falta
/// hace.
///
/// Sin Flutter a propósito (D38): esto es lo que se puede probar, y un fallo
/// aquí —una llave mal contada— corrompe el fichero de otra persona.
library;

import 'tex_scan.dart';

/// El texto después de una operación, con lo que queda seleccionado.
///
/// La selección importa tanto como el texto: después de envolver queda
/// marcado el cuerpo, que es lo que hace que volver a pulsar lo desenvuelva.
class TexEdit {
  const TexEdit(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

/// Dónde va cada envoltorio en la barra.
enum TexWrapGroup {
  /// A qué salida llega. Es la pregunta que más se hace y va a la vista.
  channel,

  /// La diapositiva.
  slide,

  /// Negrita, cursiva y demás: lo que se marca dentro de un párrafo.
  format,

  /// Las partes de un problema.
  problem,

  /// Teoremas y afines.
  theory,
}

/// Un envoltorio de Didacta, con sus dos formas y sus nombres heredados.
class TexWrapper {
  const TexWrapper({
    required this.id,
    required this.label,
    required this.group,
    this.macro,
    this.environment,
    this.macroAliases = const [],
    this.environmentAliases = const [],
    this.block = false,
  }) : assert(macro != null || environment != null);

  /// Identificador estable, el de la forma preferida.
  final String id;

  /// Lo que se lee en la barra.
  final String label;

  final TexWrapGroup group;

  /// `\onlyslides{...}`, si tiene forma de macro.
  final String? macro;

  /// `\begin{slidesonly}`, si tiene forma de entorno.
  final String? environment;

  final List<String> macroAliases;
  final List<String> environmentAliases;

  /// Siempre entorno, aunque la selección sea una frase: un `exercise` o un
  /// `answer` de una línea sigue siendo un bloque.
  final bool block;

  List<String> get _allMacros => [?macro, ...macroAliases];

  List<String> get _allEnvironments => [?environment, ...environmentAliases];
}

/// Los envoltorios que la barra ofrece.
///
/// Es la lista de `didacta-formats.sty`, `didacta-problems.sty` y
/// `didacta-theorems.sty`, no una selección: la barra decide cuáles enseña y
/// cuáles deja en el menú, pero reconocer un entorno para desenvolverlo no
/// depende de que quepa en la pantalla.
const List<TexWrapper> didactaWrappers = [
  TexWrapper(
    id: 'onlyslides',
    label: 'Solo diapositivas',
    group: TexWrapGroup.channel,
    macro: 'onlyslides',
    environment: 'slidesonly',
  ),
  TexWrapper(
    id: 'onlynotes',
    label: 'Solo apuntes',
    group: TexWrapGroup.channel,
    macro: 'onlynotes',
    environment: 'notesonly',
    // El nombre que usa el material migrado.
    macroAliases: ['onlybook'],
  ),
  TexWrapper(
    id: 'onlyteacher',
    label: 'Solo profesor',
    group: TexWrapGroup.channel,
    macro: 'onlyteacher',
    environment: 'teacheronly',
  ),
  TexWrapper(
    id: 'onlystudent',
    label: 'Solo alumno',
    group: TexWrapGroup.channel,
    macro: 'onlystudent',
    environment: 'studentonly',
  ),
  TexWrapper(
    id: 'textbf',
    label: 'Negrita',
    group: TexWrapGroup.format,
    macro: 'textbf',
  ),
  TexWrapper(
    id: 'emph',
    label: 'Cursiva',
    group: TexWrapGroup.format,
    macro: 'emph',
    // `\textit` hace lo mismo y el material migrado lo usa: desenvolver tiene
    // que reconocerlo o el botón no sirve justo donde hace falta.
    macroAliases: ['textit'],
  ),
  TexWrapper(
    id: 'texttt',
    label: 'Monoespaciada',
    group: TexWrapGroup.format,
    macro: 'texttt',
  ),
  TexWrapper(
    id: 'keyterm',
    label: 'Término que se define',
    group: TexWrapGroup.format,
    macro: 'keyterm',
  ),
  TexWrapper(
    id: 'hl',
    label: 'Resaltado',
    group: TexWrapGroup.format,
    macro: 'hl',
  ),
  TexWrapper(
    id: 'frame',
    label: 'Diapositiva',
    group: TexWrapGroup.slide,
    environment: 'frame',
    block: true,
  ),
  TexWrapper(
    id: 'exercise',
    label: 'Ejercicio',
    group: TexWrapGroup.problem,
    environment: 'exercise',
    environmentAliases: ['ej'],
    block: true,
  ),
  TexWrapper(
    id: 'parts',
    label: 'Apartados',
    group: TexWrapGroup.problem,
    environment: 'parts',
    block: true,
  ),
  TexWrapper(
    id: 'answer',
    label: 'Respuesta',
    group: TexWrapGroup.problem,
    environment: 'answer',
    block: true,
  ),
  TexWrapper(
    id: 'solution',
    label: 'Solución',
    group: TexWrapGroup.problem,
    environment: 'solution',
    block: true,
  ),
  TexWrapper(
    id: 'marking',
    label: 'Corrección',
    group: TexWrapGroup.problem,
    environment: 'marking',
    block: true,
  ),
  TexWrapper(
    id: 'hint',
    label: 'Pista',
    group: TexWrapGroup.problem,
    environment: 'hint',
    block: true,
  ),
  TexWrapper(
    id: 'theorem',
    label: 'Teorema',
    group: TexWrapGroup.theory,
    environment: 'theorem',
    environmentAliases: ['thrm', 'nthrm', 'nthm'],
    block: true,
  ),
  TexWrapper(
    id: 'definition',
    label: 'Definición',
    group: TexWrapGroup.theory,
    environment: 'definition',
    environmentAliases: ['defn', 'ndefn'],
    block: true,
  ),
  TexWrapper(
    id: 'proposition',
    label: 'Proposición',
    group: TexWrapGroup.theory,
    environment: 'proposition',
    environmentAliases: ['prop', 'nprop'],
    block: true,
  ),
  TexWrapper(
    id: 'lemma',
    label: 'Lema',
    group: TexWrapGroup.theory,
    environment: 'lemma',
    environmentAliases: ['lem', 'nlem'],
    block: true,
  ),
  TexWrapper(
    id: 'corollary',
    label: 'Corolario',
    group: TexWrapGroup.theory,
    environment: 'corollary',
    environmentAliases: ['cor', 'ncor'],
    block: true,
  ),
  TexWrapper(
    id: 'example',
    label: 'Ejemplo',
    group: TexWrapGroup.theory,
    environment: 'example',
    environmentAliases: ['ex', 'nex'],
    block: true,
  ),
  TexWrapper(
    id: 'remark',
    label: 'Observación',
    group: TexWrapGroup.theory,
    environment: 'remark',
    environmentAliases: ['rem', 'nrem'],
    block: true,
  ),
  TexWrapper(
    id: 'proof',
    label: 'Demostración',
    group: TexWrapGroup.theory,
    environment: 'proof',
    block: true,
  ),
  TexWrapper(
    id: 'keypoint',
    label: 'Recuadro',
    group: TexWrapGroup.theory,
    environment: 'keypoint',
    block: true,
  ),
  TexWrapper(
    id: 'keyformula',
    label: 'Fórmula destacada',
    group: TexWrapGroup.theory,
    environment: 'keyformula',
    environmentAliases: ['nformula'],
    block: true,
  ),
];

/// Envuelve la selección, o la desenvuelve si ya lo estaba.
///
/// Devuelve el texto entero: el que llama lo pone en el controlador y el
/// editor se encarga del resto —guardar, el diff y el conflicto no cambian,
/// que es lo que hace que esto sea una barra y no un segundo editor—.
TexEdit toggleWrap(String text, int start, int end, TexWrapper wrapper) {
  final masked = maskLatex(text);
  final found = _enclosing(masked, wrapper, start, end);
  if (found != null) return _unwrap(text, found);
  return _wrap(text, start, end, wrapper);
}

/// Los envoltorios que rodean a [offset], del más externo al más interno.
///
/// Es lo que enciende los botones: la barra dice dónde estás, igual que los
/// colores de la vista, y las dos cosas salen de la misma lectura del texto.
List<TexWrapper> wrappersAt(
  String text,
  int offset, {
  List<TexWrapper> among = didactaWrappers,
}) {
  final masked = maskLatex(text);
  final found = <_Span, TexWrapper>{};
  for (final wrapper in among) {
    final span = _enclosing(masked, wrapper, offset, offset);
    if (span != null) found[span] = wrapper;
  }
  final spans = found.keys.toList()
    ..sort((a, b) => a.outerStart.compareTo(b.outerStart));
  return [for (final span in spans) found[span]!];
}

/// Escribe algo alrededor de lo marcado: `\sqrt{` … `}`.
///
/// Con un trozo seleccionado lo mete dentro y lo deja marcado; sin nada
/// marcado, deja el cursor donde va el contenido. Es la misma regla que
/// envolver, y es lo que hace que una paleta sirva mientras se escribe y no
/// solo al empezar una fórmula.
TexEdit insertAround(
  String text,
  int start,
  int end,
  String before,
  String after,
) {
  if (start > end) {
    final swap = start;
    start = end;
    end = swap;
  }
  // Lo que envuelve recorta los blancos de los extremos, igual que los
  // envoltorios de entorno: un `\sqrt{contenido }` con el espacio dentro es
  // una raíz mal escrita que nadie ha pedido.
  if (after.isNotEmpty) {
    while (start < end && _isBlank(text[start])) {
      start += 1;
    }
    while (end > start && _isBlank(text[end - 1])) {
      end -= 1;
    }
  }
  final body = text.substring(start, end);
  final out =
      '${text.substring(0, start)}$before$body$after${text.substring(end)}';
  return TexEdit(
    out,
    start + before.length,
    start + before.length + body.length,
  );
}

/// Inserta un trozo suelto —`\dpause`— en el cursor, sustituyendo lo marcado.
TexEdit insertSnippet(String text, int start, int end, String snippet) {
  if (start > end) {
    final swap = start;
    start = end;
    end = swap;
  }
  final out = text.substring(0, start) + snippet + text.substring(end);
  return TexEdit(out, start + snippet.length, start + snippet.length);
}

// ---------------------------------------------------------------------------
// Lectura del texto
// ---------------------------------------------------------------------------

/// Un envoltorio encontrado en el texto: dónde empieza y acaba, y dónde
/// empieza y acaba su cuerpo.
class _Span {
  const _Span(this.outerStart, this.bodyStart, this.bodyEnd, this.outerEnd);

  final int outerStart;
  final int bodyStart;
  final int bodyEnd;
  final int outerEnd;

  /// Si es un entorno hay que llevarse también el salto de línea que dejaron
  /// los delimitadores al ocupar su propia línea.
  bool get isEnvironment => bodyStart - outerStart > 2;

  bool contains(int start, int end) => bodyStart <= start && end <= bodyEnd;
}

/// El envoltorio más interno de este tipo que contiene la selección.
_Span? _enclosing(String masked, TexWrapper wrapper, int start, int end) {
  if (start > end) {
    final swap = start;
    start = end;
    end = swap;
  }
  _Span? best;
  for (final name in wrapper._allMacros) {
    for (final span in _macroSpans(masked, name)) {
      if (!span.contains(start, end)) continue;
      if (best == null || span.bodyStart > best.bodyStart) best = span;
    }
  }
  for (final name in wrapper._allEnvironments) {
    for (final span in _environmentSpans(masked, name)) {
      if (!span.contains(start, end)) continue;
      if (best == null || span.bodyStart > best.bodyStart) best = span;
    }
  }
  return best;
}

Iterable<_Span> _macroSpans(String masked, String name) sync* {
  final needle = '\\$name';
  var from = 0;
  while (true) {
    final at = masked.indexOf(needle, from);
    if (at < 0) return;
    from = at + needle.length;
    final open = at + needle.length;
    // `\onlyslidesfoo{` no es `\onlyslides{`.
    if (open >= masked.length || masked[open] != '{') continue;
    final close = matchBrace(masked, open);
    if (close == null) continue;
    yield _Span(at, open + 1, close, close + 1);
  }
}

Iterable<_Span> _environmentSpans(String masked, String name) sync* {
  final open = '\\begin{$name}';
  final close = '\\end{$name}';
  var from = 0;
  while (true) {
    final at = masked.indexOf(open, from);
    if (at < 0) return;
    from = at + open.length;

    var bodyStart = at + open.length;
    // El argumento opcional es parte del delimitador: `\begin{exercise}[Norma]`.
    if (bodyStart < masked.length && masked[bodyStart] == '[') {
      final shut = masked.indexOf(']', bodyStart);
      if (shut > 0) bodyStart = shut + 1;
    }

    var depth = 1;
    var i = bodyStart;
    while (i < masked.length) {
      final nextOpen = masked.indexOf(open, i);
      final nextClose = masked.indexOf(close, i);
      if (nextClose < 0) break;
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth += 1;
        i = nextOpen + open.length;
        continue;
      }
      depth -= 1;
      if (depth == 0) {
        yield _Span(at, bodyStart, nextClose, nextClose + close.length);
        break;
      }
      i = nextClose + close.length;
    }
  }
}

// ---------------------------------------------------------------------------
// Las dos operaciones
// ---------------------------------------------------------------------------

TexEdit _unwrap(String text, _Span span) {
  var bodyStart = span.bodyStart;
  var bodyEnd = span.bodyEnd;

  if (span.isEnvironment) {
    // `\begin{x}\n` se lleva su salto, y el `\n` con la sangría que hubiera
    // delante de `\end{x}` también: si no, desenvolver deja el cuerpo rodeado
    // de líneas en blanco que nadie escribió.
    if (bodyStart < text.length && text[bodyStart] == '\n') bodyStart += 1;
    var j = bodyEnd - 1;
    while (j >= bodyStart && (text[j] == ' ' || text[j] == '\t')) {
      j -= 1;
    }
    if (j >= bodyStart && text[j] == '\n') bodyEnd = j;
  }

  final body = text.substring(bodyStart, bodyEnd);
  final out =
      text.substring(0, span.outerStart) + body + text.substring(span.outerEnd);
  return TexEdit(out, span.outerStart, span.outerStart + body.length);
}

TexEdit _wrap(String text, int start, int end, TexWrapper wrapper) {
  final (from, to) = _normalise(text, start, end);
  final body = text.substring(from, to);

  final asEnvironment =
      wrapper.macro == null ||
      (wrapper.environment != null &&
          (wrapper.block || _needsEnvironment(body)));

  if (!asEnvironment) {
    final open = '\\${wrapper.macro}{';
    final out = '${text.substring(0, from)}$open$body}${text.substring(to)}';
    return TexEdit(out, from + open.length, from + open.length + body.length);
  }

  final atLineStart = from == 0 || text[from - 1] == '\n';
  final atLineEnd = to == text.length || text[to] == '\n';
  final open = '${atLineStart ? '' : '\n'}\\begin{${wrapper.environment}}\n';
  final close = '\n\\end{${wrapper.environment}}${atLineEnd ? '' : '\n'}';
  final out =
      text.substring(0, from) + open + body + close + text.substring(to);
  return TexEdit(out, from + open.length, from + open.length + body.length);
}

/// El entorno hace falta cuando la macro no aguanta el cuerpo.
///
/// `\onlyslides{...}` se rompe con un `\par`, con verbatim y con cualquier
/// cambio de catcode; el entorno recoge el cuerpo y no.
bool _needsEnvironment(String body) =>
    RegExp(r'\n[ \t]*\n').hasMatch(body) ||
    body.contains(r'\begin{') ||
    body.contains(r'\verb');

/// Qué se envuelve exactamente.
///
/// Sin selección, el párrafo donde está el cursor: es lo que se quiere decir
/// al pulsar un botón con el cursor dentro de un párrafo, y envolver la nada
/// deja un `\onlyslides{}` vacío que hay que ir a borrar a mano.
///
/// Con selección, se recortan los blancos de los extremos, para que el
/// envoltorio no se coma la línea en blanco que separaba dos párrafos.
(int, int) _normalise(String text, int start, int end) {
  if (start > end) {
    final swap = start;
    start = end;
    end = swap;
  }

  if (start == end) {
    var from = 0;
    var to = text.length;
    for (final match in RegExp(r'\n[ \t]*\n').allMatches(text)) {
      if (match.end <= start) from = match.end;
      if (match.start >= start) {
        to = match.start;
        break;
      }
    }
    start = from;
    end = to;
  }

  while (start < end && _isBlank(text[start])) {
    start += 1;
  }
  while (end > start && _isBlank(text[end - 1])) {
    end -= 1;
  }
  return (start, end);
}

bool _isBlank(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
