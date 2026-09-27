/// Las fórmulas de una traducción, comparadas con las del original.
///
/// Una traducción cambia las palabras y deja las fórmulas como estaban: es la
/// única parte del fichero que tiene que ser **idéntica** en los dos idiomas.
/// Cuando no lo es, casi siempre es un error --un exponente que se perdió al
/// corregir a mano, una fórmula que el original arregló después y la
/// traducción no-- y es el peor de los errores, porque compila y dice otra
/// cosa. Nadie lo ve leyendo la traducción: hay que ponerla al lado.
///
/// Lo que se compara son los trozos que [splitLatex] ya aparta como fórmulas
/// (`$…$`, `\[…\]`, `\(…\)` y los entornos de ecuaciones), con dos
/// tolerancias para no avisar de lo que no es un error:
///
/// * los espacios y los espaciados finos (`\,`, `\;`, `\quad`) no cuentan;
/// * lo que va en `\text{…}` y compañía sí se traduce --«si», «if»-- y no se
///   compara.
///
/// Se alinean las dos listas en orden, como un diff: una fórmula nueva en
/// mitad de la traducción no hace que todas las de detrás salgan cambiadas.
library;

import 'latex_protect.dart';
import 'tex_check.dart' show TexWarning;
import '../l10n/tr.dart';

/// Una fórmula que no coincide.
enum FormulaDifferenceKind {
  /// Está en el original y no en la traducción.
  missing,

  /// Está en la traducción y no en el original.
  extra,

  /// Está en los dos sitios, distinta.
  changed,
}

class FormulaDifference {
  const FormulaDifference({
    required this.kind,
    this.original,
    this.translation,
    required this.offset,
  });

  final FormulaDifferenceKind kind;
  final String? original;
  final String? translation;

  /// Dónde está en la traducción: la fórmula, o donde tendría que estar.
  final int offset;
}

/// Un trozo de fórmula con dónde empieza.
typedef _Formula = ({String text, String key, int offset});

const Set<String> _mathEnvironments = {
  'equation',
  'align',
  'gather',
  'multline',
  'eqnarray',
  'split',
  'cases',
  'matrix',
  'pmatrix',
  'bmatrix',
  'vmatrix',
  'array',
};

/// Las fórmulas de [text], en orden.
List<_Formula> _formulas(String text) {
  final found = <_Formula>[];
  var at = 0;
  for (final piece in splitLatex(text)) {
    final start = at;
    at += piece.text.length;
    if (piece.translatable) continue;
    final trimmed = piece.text.trimLeft();
    final lead = piece.text.length - trimmed.length;
    if (!_isMath(trimmed)) continue;
    found.add((
      text: trimmed.trimRight(),
      key: _normalise(trimmed),
      offset: start + lead,
    ));
  }
  return found;
}

bool _isMath(String piece) {
  if (piece.startsWith(r'$') ||
      piece.startsWith(r'\[') ||
      piece.startsWith(r'\(')) {
    return true;
  }
  final environment = RegExp(r'^\\begin\{([A-Za-z]+)\*?\}').firstMatch(piece);
  return environment != null &&
      _mathEnvironments.contains(environment.group(1));
}

/// Lo que se compara de una fórmula: sin espacios, sin espaciados y sin lo
/// que va en texto, que sí se traduce.
String _normalise(String formula) {
  var out = formula;
  // `\text{si }` y compañía, con su contenido, que se traduce. Sin llaves
  // anidadas dentro, que es como se escriben casi siempre.
  out = out.replaceAll(
    RegExp(
      r'\\(?:text|textrm|textit|textbf|mbox|intertext|shortintertext)\s*'
      r'\{[^{}]*\}',
    ),
    r'\text{}',
  );
  out = out.replaceAll(RegExp(r'\\label\s*\{[^{}]*\}'), '');
  out = out.replaceAll(RegExp(r'\\[,;:!]'), '');
  out = out.replaceAll(RegExp(r'\\q?quad(?![A-Za-z])'), '');
  out = out.replaceAll(RegExp(r'\s+'), '');
  return out;
}

/// Lo que no coincide entre las fórmulas de [original] y las de [translation].
List<FormulaDifference> compareFormulas(String original, String translation) {
  final a = _formulas(original);
  final b = _formulas(translation);

  // La subsecuencia común más larga, por la clave normalizada.
  final lengths = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i -= 1) {
    for (var j = b.length - 1; j >= 0; j -= 1) {
      lengths[i][j] = a[i].key == b[j].key
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] >= lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }

  final differences = <FormulaDifference>[];
  final missing = <_Formula>[];
  final extra = <_Formula>[];
  var lastOffset = 0;

  void flush() {
    // Una que falta y otra que sobra en el mismo hueco son una cambiada.
    final pairs = missing.length < extra.length ? missing.length : extra.length;
    for (var k = 0; k < pairs; k += 1) {
      differences.add(
        FormulaDifference(
          kind: FormulaDifferenceKind.changed,
          original: missing[k].text,
          translation: extra[k].text,
          offset: extra[k].offset,
        ),
      );
    }
    for (final formula in missing.skip(pairs)) {
      differences.add(
        FormulaDifference(
          kind: FormulaDifferenceKind.missing,
          original: formula.text,
          offset: lastOffset,
        ),
      );
    }
    for (final formula in extra.skip(pairs)) {
      differences.add(
        FormulaDifference(
          kind: FormulaDifferenceKind.extra,
          translation: formula.text,
          offset: formula.offset,
        ),
      );
    }
    missing.clear();
    extra.clear();
  }

  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i].key == b[j].key) {
      flush();
      lastOffset = b[j].offset + b[j].text.length;
      i += 1;
      j += 1;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      missing.add(a[i]);
      i += 1;
    } else {
      extra.add(b[j]);
      j += 1;
    }
  }
  missing.addAll(a.skip(i));
  extra.addAll(b.skip(j));
  flush();
  differences.sort((x, y) => x.offset.compareTo(y.offset));
  return differences;
}

/// Las diferencias como avisos del editor, en la traducción.
List<TexWarning> formulaWarnings(String original, String translation) {
  final lineStarts = <int>[0];
  for (var i = 0; i < translation.length; i += 1) {
    if (translation[i] == '\n') lineStarts.add(i + 1);
  }
  String short(String formula) {
    final flat = formula.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 60 ? flat : '${flat.substring(0, 57)}…';
  }

  return [
    for (final difference in compareFormulas(original, translation))
      () {
        var line = 0;
        while (line + 1 < lineStarts.length &&
            lineStarts[line + 1] <= difference.offset) {
          line += 1;
        }
        return TexWarning(
          offset: difference.offset,
          line: line + 1,
          column: difference.offset - lineStarts[line] + 1,
          message: switch (difference.kind) {
            FormulaDifferenceKind.changed => tr(
              'Esta fórmula no es la del original: «{0}» '
              'donde el original dice «{1}».',
              [short(difference.translation!), short(difference.original!)],
            ),
            FormulaDifferenceKind.missing => tr(
              'Falta una fórmula del original: «{0}».',
              [short(difference.original!)],
            ),
            FormulaDifferenceKind.extra => tr(
              'Esta fórmula no está en el original: '
              '«{0}».',
              [short(difference.translation!)],
            ),
          },
        );
      }(),
  ];
}
