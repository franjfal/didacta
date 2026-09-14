/// Un problema, visto como lo que tiene dentro: enunciado, resultado y
/// solución.
///
/// El fichero sigue siendo un `.tex` y los entornos siguen siendo los del
/// paquete `didacta-problems`, que es lo que hace que una misma fuente dé la
/// hoja de clase, la hoja con resultados y la del profesor. Lo que cambia es
/// que editarlo deje de ser escribir `\begin{answer}` a mano.
///
/// La razón de que esto exista está en los datos: de los 429 ficheros de
/// `problems/`, **ninguno** usa `answer`. El entorno está definido y
/// documentado desde el principio --«el resultado, `f'(x) = 2x`, una
/// línea»-- y no lo usa nadie, porque para usarlo hay que saber que existe y
/// acordarse de escribirlo. Tres campos con su nombre lo convierten en algo
/// que se rellena.
///
/// Reescribe líneas, no serializa: el cuerpo de cada entorno se sustituye en
/// su sitio y todo lo demás --`\medskip`, un `hint`, un comentario-- se queda
/// exactamente donde estaba.
library;

/// Uno de los tres campos.
enum ProblemPart { statement, answer, solution }

/// El entorno de cada campo.
String environmentFor(ProblemPart part) => switch (part) {
  ProblemPart.statement => 'exercise',
  ProblemPart.answer => 'answer',
  ProblemPart.solution => 'solution',
};

String labelFor(ProblemPart part) => switch (part) {
  ProblemPart.statement => 'Enunciado',
  ProblemPart.answer => 'Resultado',
  ProblemPart.solution => 'Solución detallada',
};

String hintFor(ProblemPart part) => switch (part) {
  ProblemPart.statement => 'Lo que se pide. Sale en todas las versiones.',
  ProblemPart.answer =>
    'El resultado, en una línea. Sale en la hoja con resultados y en la '
        'del profesor.',
  ProblemPart.solution =>
    'Cómo se llega. Sale en la hoja con soluciones y en la del profesor.',
};

/// Por qué un fichero no se puede editar por campos.
class ProblemShape {
  const ProblemShape._(this.reason);

  static const ProblemShape ok = ProblemShape._(null);

  /// Null cuando encaja.
  final String? reason;

  bool get fits => reason == null;
}

class ProblemFile {
  ProblemFile(String text) : _lines = text.split('\n') {
    _parse();
  }

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// Dónde está el cuerpo de cada entorno: [primera, última] líneas, ambas
  /// dentro. Vacío cuando el entorno no está.
  final Map<ProblemPart, (int, int)> _body = {};

  /// La línea del `\end{exercise}`.
  int _exerciseEnd = -1;

  /// La línea del primer entorno metido **dentro** del `exercise`, si lo hay.
  ///
  /// Los ficheros se escriben de las dos formas --el resultado y la solución
  /// dentro del `exercise`, que es como los escribe `didacta new`, o detrás
  /// de su `\end`-- y las dos compilan igual. La diferencia importa aquí:
  /// sin esto el enunciado llegaba hasta el `\end{exercise}` y se comía el
  /// `hint`, el resultado, la solución y la corrección. Editar el enunciado
  /// los borraba.
  int _innerStart = -1;

  ProblemShape shape = ProblemShape.ok;

  /// Si no hay ningún entorno: el fichero entero es el enunciado.
  ///
  /// 72 de los 429 están así, y son enunciados que la migración no llegó a
  /// envolver. Se editan igual; el `\begin{exercise}` se pone solo cuando
  /// haga falta, que es al escribir el primer resultado o la primera
  /// solución.
  bool bare = false;

  void _parse() {
    // `marking` y `hint` no son campos del editor, pero sí marcan dónde deja
    // de haber enunciado.
    final begin = RegExp(
      r'^\s*\\begin\{(exercise\*?|ej|answer|solution|marking|hint)\}',
    );
    final end = RegExp(
      r'^\s*\\end\{(exercise\*?|ej|answer|solution|marking|hint)\}',
    );

    final counts = <String, int>{};
    final opened = <String, int>{};

    for (var i = 0; i < _lines.length; i += 1) {
      final at = begin.firstMatch(_lines[i]);
      if (at != null) {
        final name = _canonical(at.group(1)!);
        counts[name] = (counts[name] ?? 0) + 1;
        if (name != 'exercise' &&
            opened.containsKey('exercise') &&
            _innerStart < 0) {
          _innerStart = i;
        }
        opened[name] = i;
        continue;
      }
      final closing = end.firstMatch(_lines[i]);
      if (closing == null) continue;
      final name = _canonical(closing.group(1)!);
      final from = opened.remove(name);
      if (from == null) continue;
      if (name == 'exercise') _exerciseEnd = i;
      final part = switch (name) {
        'exercise' => ProblemPart.statement,
        'answer' => ProblemPart.answer,
        'solution' => ProblemPart.solution,
        _ => null,
      };
      // El primero de cada uno. Si hay más de uno, el fichero no encaja y se
      // dice abajo; quedarse con el primero evita además que un `solution`
      // dentro de otro lo pise.
      if (part != null && !_body.containsKey(part)) {
        // El enunciado acaba donde empieza lo que lleve dentro.
        final to = name == 'exercise' && _innerStart > from
            ? _innerStart - 1
            : i - 1;
        _body[part] = (from + 1, to);
      }
    }

    final exercises = counts['exercise'] ?? 0;
    if (exercises == 0 &&
        (counts['answer'] ?? 0) == 0 &&
        (counts['solution'] ?? 0) == 0) {
      bare = true;
      return;
    }
    if (exercises > 1) {
      shape = ProblemShape._(
        'este fichero tiene $exercises problemas, y los campos son de uno. '
        'Se edita como texto, y se parte en varios cuando toque.',
      );
      return;
    }
    for (final name in ['answer', 'solution']) {
      if ((counts[name] ?? 0) > 1) {
        shape = ProblemShape._(
          'este fichero tiene ${counts[name]} entornos `$name`, y el campo '
          'es uno. Se edita como texto.',
        );
        return;
      }
    }
  }

  static String _canonical(String name) => switch (name) {
    'exercise*' || 'ej' => 'exercise',
    _ => name,
  };

  /// El texto de un campo, o vacío si no está.
  String part(ProblemPart part) {
    if (bare && part == ProblemPart.statement) return text.trim();
    final at = _body[part];
    if (at == null) return '';
    final (from, to) = at;
    if (to < from) return '';
    return _lines.sublist(from, to + 1).join('\n').trim();
  }

  bool has(ProblemPart part) =>
      bare ? part == ProblemPart.statement : _body.containsKey(part);

  /// Cambia un campo y devuelve el fichero entero.
  ///
  /// Vaciar el resultado o la solución quita su entorno: uno vacío pinta un
  /// recuadro vacío en la hoja, que es peor que no tenerlo. Vaciar el
  /// enunciado no quita el `exercise`, porque hay ficheros con material
  /// fuera del entorno y perderlo cambiaría cómo se imprimen.
  String withPart(ProblemPart part, String value) {
    final body = value.trim();

    if (bare) {
      if (part == ProblemPart.statement) return body.isEmpty ? '' : '$body\n';
      // Poner un resultado o una solución obliga a envolver el enunciado:
      // `answer` fuera de un `exercise` no se numera ni se encuadra.
      final wrapped = ProblemFile(
        '\\begin{exercise}\n${text.trim()}\n\\end{exercise}\n',
      );
      return wrapped.withPart(part, value);
    }

    final at = _body[part];
    if (at == null) return body.isEmpty ? text : _insert(part, body);

    final (from, to) = at;
    if (body.isEmpty && part != ProblemPart.statement) {
      // Fuera el entorno entero, sus dos líneas incluidas. Un
      // `\begin{answer}\end{answer}` vacío pinta un recuadro vacío en la
      // hoja con resultados.
      final copy = [..._lines]..removeRange(from - 1, to + 2);
      return copy.join('\n');
    }
    // El enunciado no: un problema sin enunciado es uno a medio escribir, y
    // quitarle el `exercise` cambiaría cómo se imprime todo lo demás del
    // fichero --hay ficheros con material fuera del entorno-- por haber
    // borrado un campo.
    final copy = [..._lines]..replaceRange(from, to + 1, body.split('\n'));
    return copy.join('\n');
  }

  /// Mete un entorno que no estaba, en el sitio que le toca.
  ///
  /// El orden es enunciado, resultado, solución: es como se lee y como lo
  /// escribe el paquete de LaTeX, y un fichero en el que el resultado esté
  /// debajo de la solución se lee mal aunque compile igual.
  String _insert(ProblemPart part, String body) {
    final block = [
      '\\begin{${environmentFor(part)}}',
      ...body.split('\n'),
      '\\end{${environmentFor(part)}}',
    ];

    // Detrás del enunciado, y detrás del resultado si ya lo hay. Se respeta
    // la forma del fichero: en uno que lleva el resultado dentro del
    // `exercise` la solución entra al lado, y en uno que lo lleva detrás del
    // `\end` entra detrás.
    final statement = _body[ProblemPart.statement];
    final afterStatement = _innerStart >= 0 && statement != null
        ? statement.$2
        : _exerciseEnd;
    final after = switch (part) {
      ProblemPart.answer => afterStatement,
      ProblemPart.solution => _body[ProblemPart.answer] == null
          ? afterStatement
          : _body[ProblemPart.answer]!.$2 + 1,
      // Un enunciado que falta va el primero.
      ProblemPart.statement => -1,
    };

    final copy = [..._lines];
    if (after < 0) {
      copy.insertAll(0, [...block, '']);
    } else {
      copy.insertAll(after + 1, ['', ...block]);
    }
    return copy.join('\n');
  }
}
