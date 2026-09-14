/// El árbol de un texto de Didacta: qué entorno empieza dónde y qué se ve.
///
/// Es lo que hace falta para pintar la vista con sangrías de colores, para
/// encender los botones de la barra y para avisar de un `\begin` que nadie
/// cerró. Una sola lectura del texto contesta las tres cosas, y por eso está
/// aquí y no repartida por la interfaz.
///
/// Dos propiedades que lo hacen útil y que conviene no perder:
///
/// **Varios ficheros, un texto.** Una composición es la composición más las
/// unidades que referencia, y leerlas por separado no contesta la pregunta
/// que se hace mirándolas —«¿dónde cae el corte de esta diapositiva?»—. Así
/// que se concatenan y cada trozo recuerda de dónde salió: sin eso, una
/// edición no sabe a qué fichero volver y un aviso no sabe qué línea
/// nombrar.
///
/// **Un texto roto se lee igual.** Un `\begin{frame}` sin cerrar no puede
/// detener la lectura: es justo el fichero que hay que enseñar para que
/// alguien lo arregle. Se cierra donde acabe el fichero, se apunta el aviso y
/// se sigue.
library;

import 'tex_scan.dart';
import 'tex_wrap.dart';

/// De dónde sale un trozo del texto.
enum TexSourceKind {
  /// El `.tex` del documento: la lista de referencias.
  composition,

  /// Una unidad de `content/`.
  unit,

  /// Una unidad de `problems/`.
  problem,
}

/// Un fichero que entra en la vista.
class TexSource {
  const TexSource({
    required this.id,
    required this.label,
    required this.text,
    this.kind = TexSourceKind.unit,
    this.language,
  });

  /// La ruta, que es lo que identifica al fichero para volver a él.
  final String id;

  /// Lo que se lee en la línea de puntos que lo separa del anterior.
  final String label;

  final String text;
  final TexSourceKind kind;
  final String? language;
}

/// Qué clase de cosa es un entorno. El color sale de aquí; el color en sí
/// vive en el tema, que es donde viven los colores.
enum TexBlockKind {
  /// `document`: envuelve todo y no significa nada para quien lee.
  document,

  /// `frame`: una diapositiva.
  slide,

  /// `slidesonly`, `notesonly`, `teacheronly`, `studentonly`.
  channel,

  /// `exercise`, `parts`.
  exercise,

  /// `answer`, `solution`, `marking`, `hint`: lo que se revela por perfil.
  reveal,

  /// Teoremas, definiciones, demostraciones y recuadros.
  theorem,

  /// El canal del profesor con forma de bloque.
  teaching,

  /// `itemize`, `enumerate`, `description`.
  list,

  /// Matemáticas en display.
  math,

  /// Figuras, tablas y cajas.
  figure,

  /// Cualquier otro entorno.
  other,
}

/// Un entorno encontrado en el texto.
class TexBlock {
  const TexBlock({
    required this.name,
    required this.kind,
    required this.start,
    required this.end,
    required this.startLine,
    required this.endLine,
    required this.depth,
    required this.sourceId,
    required this.closed,
  });

  final String name;
  final TexBlockKind kind;

  /// Desplazamientos en el texto concatenado.
  final int start;
  final int end;

  /// Líneas del texto concatenado, contando desde 0.
  final int startLine;
  final int endLine;

  /// La columna de la sangría: cuántos entornos lo envuelven. `document` no
  /// cuenta, porque envolver el documento entero no es una sangría, es el
  /// documento.
  final int depth;

  final String sourceId;

  /// Falso cuando el `\end` no apareció y lo cerró el final del fichero.
  final bool closed;
}

/// Qué trozo del texto concatenado ocupa cada fichero.
class TexSlice {
  const TexSlice({
    required this.source,
    required this.start,
    required this.end,
    required this.startLine,
    required this.endLine,
  });

  final TexSource source;
  final int start;
  final int end;
  final int startLine;
  final int endLine;
}

/// Lo que está mal y hay que decir sin bloquear.
enum TexIssueKind {
  /// Un `\begin` que nadie cierra.
  unclosed,

  /// Un `\end` que no abre nada.
  unopened,

  /// `\begin{a}\begin{b}\end{a}`: se cierran cruzados.
  crossed,
}

/// Un aviso, con el fichero y la línea de quien lo causó.
///
/// LaTeX no sabe decir esto: un `frame` sin cerrar dentro de una unidad lo
/// denuncia contra la línea de la **composición** que la incluye, y encima
/// saca un PDF de una página que parece correcto. El fichero y la línea de
/// verdad solo los sabe quien lee los ficheros antes de compilar.
class TexIssue {
  const TexIssue({
    required this.kind,
    required this.name,
    required this.sourceId,
    required this.line,
    required this.lineInSource,
  });

  final TexIssueKind kind;
  final String name;
  final String sourceId;

  /// Línea del texto concatenado, desde 0.
  final int line;

  /// Línea dentro de su fichero, desde 1: la que se le dice a una persona.
  final int lineInSource;

  String get message => switch (kind) {
    TexIssueKind.unclosed => '«$name» se abre y no se cierra',
    TexIssueKind.unopened => '«$name» se cierra sin haberse abierto',
    TexIssueKind.crossed => '«$name» se cierra por fuera de otro entorno',
  };
}

/// El árbol de un texto, o de varios puestos en fila.
class TexOutline {
  TexOutline._({
    required this.text,
    required this.slices,
    required this.blocks,
    required this.issues,
    required this.lineStarts,
  }) {
    _stacks = List<List<TexBlock>>.generate(lineCount, (_) => <TexBlock>[]);
    for (final block in blocks) {
      for (var line = block.startLine; line <= block.endLine; line += 1) {
        if (line >= 0 && line < _stacks.length) _stacks[line].add(block);
      }
    }
  }

  /// Un solo fichero.
  factory TexOutline.ofText(String text, {String id = '', String label = ''}) =>
      TexOutline.of([TexSource(id: id, label: label, text: text)]);

  /// Varios ficheros en el orden en que se leen.
  factory TexOutline.of(List<TexSource> sources) {
    final buffer = StringBuffer();
    final slices = <TexSlice>[];
    final lineStarts = <int>[0];

    for (final source in sources) {
      final start = buffer.length;
      final startLine = lineStarts.length - 1;
      // Cada fichero acaba en salto de línea: sin eso, la última línea de uno
      // y la primera del siguiente serían la misma línea, y la línea de
      // puntos no tendría dónde ponerse.
      var text = source.text;
      if (text.isNotEmpty && !text.endsWith('\n')) text = '$text\n';
      buffer.write(text);
      for (var i = 0; i < text.length; i += 1) {
        if (text[i] == '\n') lineStarts.add(start + i + 1);
      }
      slices.add(
        TexSlice(
          source: source,
          start: start,
          end: buffer.length,
          startLine: startLine,
          endLine: lineStarts.length - 2 < startLine
              ? startLine
              : lineStarts.length - 2,
        ),
      );
    }

    final text = buffer.toString();
    final (blocks, issues) = _scan(text, slices, lineStarts);
    return TexOutline._(
      text: text,
      slices: slices,
      blocks: blocks,
      issues: issues,
      lineStarts: lineStarts,
    );
  }

  /// El texto de todos los ficheros, uno detrás de otro.
  final String text;

  final List<TexSlice> slices;

  /// Todos los entornos, en el orden en que empiezan.
  final List<TexBlock> blocks;

  final List<TexIssue> issues;

  /// Dónde empieza cada línea del texto concatenado. La vista lo necesita
  /// para ir de un desplazamiento a una línea y al revés.
  final List<int> lineStarts;

  late final List<List<TexBlock>> _stacks;

  int get lineCount => lineStarts.length - 1;

  /// Los entornos abiertos en esa línea, de fuera adentro.
  ///
  /// Es una columna de la sangría por cada uno, en ese orden. Como una
  /// diapositiva es lo más externo que se escribe, sale la primera.
  List<TexBlock> openAt(int line) =>
      line < 0 || line >= _stacks.length ? const [] : _stacks[line];

  /// Si esa línea cae dentro de una diapositiva.
  ///
  /// Lo que dé `false` no se proyecta: sale en los apuntes, en el libro y en
  /// la hoja, y no en el aula. Es la pregunta que la vista contesta pintando
  /// en gris, y la única que no se puede contestar mirando un PDF.
  bool projectedAt(int line) =>
      openAt(line).any((block) => block.kind == TexBlockKind.slide);

  /// Cuántas diapositivas tiene esto.
  int get slideCount =>
      blocks.where((block) => block.kind == TexBlockKind.slide).length;

  /// La línea del texto concatenado donde cae un desplazamiento.
  int lineOf(int offset) {
    var low = 0;
    var high = lineStarts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (lineStarts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// Los entornos que sangran esta línea: los que la contienen **por dentro**.
  ///
  /// La línea del `\begin` y la del `\end` no cuentan la suya: son el borde
  /// del bloque y se leen al nivel de fuera, como la llave de apertura de una
  /// función en un editor de código.
  ///
  /// De fuera adentro, que es el orden en que se pintan las columnas.
  List<TexBlock> guidesAt(int line) => [
    for (final block in openAt(line))
      if (block.kind != TexBlockKind.document &&
          block.startLine < line &&
          line < block.endLine)
        block,
  ];

  /// Cuánto sangra una línea, en niveles.
  int indentAt(int line) => guidesAt(line).length;

  /// La sangría más honda de un fichero.
  ///
  /// Es lo que hay que apartarle al texto dentro de un editor, donde la caja
  /// tiene un solo margen izquierdo y no puede sangrar línea a línea.
  int maxIndentIn(TexSlice slice) {
    var most = 0;
    for (var line = slice.startLine; line <= slice.endLine; line += 1) {
      final here = indentAt(line);
      if (here > most) most = here;
    }
    return most;
  }

  /// El texto de una línea, sin su salto.
  String lineAt(int line) {
    if (line < 0 || line >= lineCount) return '';
    final start = lineStarts[line];
    var stop = line + 1 < lineStarts.length
        ? lineStarts[line + 1]
        : text.length;
    if (stop > start && text[stop - 1] == '\n') stop -= 1;
    return text.substring(start, stop);
  }

  /// El fichero al que pertenece un desplazamiento.
  TexSlice? sliceAt(int offset) {
    for (final slice in slices) {
      if (offset >= slice.start && offset < slice.end) return slice;
    }
    return slices.isEmpty ? null : slices.last;
  }
}

// ---------------------------------------------------------------------------
// La lectura
// ---------------------------------------------------------------------------

final RegExp _environment = RegExp(r'\\(begin|end)\{([^}\n]*)\}');

class _Open {
  _Open(this.name, this.kind, this.start, this.line, this.depth, this.sourceId);

  final String name;
  final TexBlockKind kind;
  final int start;
  final int line;
  final int depth;
  final String sourceId;
}

(List<TexBlock>, List<TexIssue>) _scan(
  String text,
  List<TexSlice> slices,
  List<int> lineStarts,
) {
  final masked = maskLatex(text);
  final blocks = <TexBlock>[];
  final issues = <TexIssue>[];
  final stack = <_Open>[];

  int lineOf(int offset) {
    var low = 0;
    var high = lineStarts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (lineStarts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  TexSlice? sliceAt(int offset) {
    for (final slice in slices) {
      if (offset >= slice.start && offset < slice.end) return slice;
    }
    return slices.isEmpty ? null : slices.last;
  }

  TexIssue issue(TexIssueKind kind, String name, int offset) {
    final line = lineOf(offset);
    final slice = sliceAt(offset);
    return TexIssue(
      kind: kind,
      name: name,
      sourceId: slice?.source.id ?? '',
      line: line,
      lineInSource: line - (slice?.startLine ?? 0) + 1,
    );
  }

  TexBlock close(_Open open, int end, {required bool closed}) => TexBlock(
    name: open.name,
    kind: open.kind,
    start: open.start,
    end: end,
    startLine: open.line,
    endLine: lineOf(end > open.start ? end - 1 : end),
    depth: open.depth,
    sourceId: open.sourceId,
    closed: closed,
  );

  for (final match in _environment.allMatches(masked)) {
    final name = match.group(2)!;
    final kind = classifyEnvironment(name);

    if (match.group(1) == 'begin') {
      final depth = stack
          .where((open) => open.kind != TexBlockKind.document)
          .length;
      stack.add(
        _Open(
          name,
          kind,
          match.start,
          lineOf(match.start),
          kind == TexBlockKind.document ? 0 : depth,
          sliceAt(match.start)?.source.id ?? '',
        ),
      );
      continue;
    }

    final at = stack.lastIndexWhere((open) => open.name == name);
    if (at < 0) {
      issues.add(issue(TexIssueKind.unopened, name, match.start));
      continue;
    }
    // Lo que quedó abierto por encima se cierra aquí y se denuncia: son
    // entornos cruzados, que LaTeX tampoco acepta pero cuenta mucho peor.
    for (var i = stack.length - 1; i > at; i -= 1) {
      issues.add(issue(TexIssueKind.crossed, stack[i].name, stack[i].start));
      blocks.add(close(stack[i], match.start, closed: false));
    }
    stack.removeRange(at + 1, stack.length);
    blocks.add(close(stack.removeLast(), match.end, closed: true));
  }

  // Lo que sigue abierto al final del texto.
  for (final open in stack.reversed) {
    issues.add(issue(TexIssueKind.unclosed, open.name, open.start));
    blocks.add(close(open, text.length, closed: false));
  }

  blocks.sort((a, b) => a.start.compareTo(b.start));
  issues.sort((a, b) => a.line.compareTo(b.line));
  return (blocks, issues);
}

/// Qué clase de entorno es, por su nombre.
///
/// Los nombres de Didacta salen de la lista de la barra, alias heredados
/// incluidos: `ej` es un ejercicio y `ndefn` una definición en el material
/// migrado, y un color distinto para el mismo entorno según cómo se llame
/// sería exactamente la confusión que D6 quita.
TexBlockKind classifyEnvironment(String name) {
  final plain = name.endsWith('*') ? name.substring(0, name.length - 1) : name;
  final wrapper = _wrapperKinds[plain];
  if (wrapper != null) return wrapper;
  return _otherKinds[plain] ?? TexBlockKind.other;
}

/// id del envoltorio → qué clase de cosa es.
const Map<String, TexBlockKind> _kindOfWrapper = {
  'onlyslides': TexBlockKind.channel,
  'onlynotes': TexBlockKind.channel,
  'onlyteacher': TexBlockKind.channel,
  'onlystudent': TexBlockKind.channel,
  'frame': TexBlockKind.slide,
  'exercise': TexBlockKind.exercise,
  'parts': TexBlockKind.exercise,
  'answer': TexBlockKind.reveal,
  'solution': TexBlockKind.reveal,
  'marking': TexBlockKind.reveal,
  'hint': TexBlockKind.reveal,
};

/// Nombre de entorno → clase, construido a partir de la lista de la barra
/// para que los alias heredados no se escriban dos veces.
final Map<String, TexBlockKind> _wrapperKinds = {
  for (final wrapper in didactaWrappers)
    for (final name in [
      if (wrapper.environment != null) wrapper.environment!,
      ...wrapper.environmentAliases,
    ])
      name: _kindOfWrapper[wrapper.id] ?? TexBlockKind.theorem,
};

/// Lo que no es de Didacta pero está en todos los ficheros.
const Map<String, TexBlockKind> _otherKinds = {
  'document': TexBlockKind.document,
  'shownto': TexBlockKind.reveal,
  'teaching': TexBlockKind.teaching,
  'commonmistake': TexBlockKind.teaching,
  'objectives': TexBlockKind.teaching,
  'prerequisites': TexBlockKind.teaching,
  'summary': TexBlockKind.teaching,
  'itemize': TexBlockKind.list,
  'enumerate': TexBlockKind.list,
  'description': TexBlockKind.list,
  'equation': TexBlockKind.math,
  'align': TexBlockKind.math,
  'aligned': TexBlockKind.math,
  'gather': TexBlockKind.math,
  'multline': TexBlockKind.math,
  'cases': TexBlockKind.math,
  'displaymath': TexBlockKind.math,
  'empheq': TexBlockKind.math,
  'array': TexBlockKind.math,
  'figure': TexBlockKind.figure,
  'wrapfigure': TexBlockKind.figure,
  'table': TexBlockKind.figure,
  'tabular': TexBlockKind.figure,
  'tikzpicture': TexBlockKind.figure,
  'center': TexBlockKind.figure,
  'minipage': TexBlockKind.figure,
  'columns': TexBlockKind.figure,
  'column': TexBlockKind.figure,
};
