/// Qué palabras cambiaron dentro de una línea que cambió.
///
/// Un diff por líneas dice «esta línea era así y ahora es así», y en un
/// párrafo de LaTeX de trescientos caracteres eso obliga a leer las dos
/// enteras buscando la coma que se movió. Esto marca, dentro de la línea, los
/// trozos que no están en la otra: la línea sigue entera y seleccionable, y lo
/// que cambió se ve sin buscarlo.
///
/// Por palabras y no por letras: una letra cambiada dentro de una palabra se
/// lee mejor marcando la palabra entera, y comparar letra a letra da marcas
/// sueltas que parecen ruido.
library;

/// Un trozo de una línea, y si está solo en esta versión.
typedef WordSpan = ({String text, bool changed});

/// Las palabras, los espacios y cada signo por separado: `\frac{a}{b}` son
/// seis piezas y no una, que es lo que hace que cambiar la `b` marque solo la
/// `b`.
final RegExp _token = RegExp(
  r'\s+|[\p{L}\p{N}_]+|[^\s\p{L}\p{N}_]',
  unicode: true,
);

List<String> _tokens(String text) => [
  for (final match in _token.allMatches(text)) match.group(0)!,
];

/// Por encima de esto no se marca nada: dos líneas de mil piezas son un
/// millón de celdas, y para una línea así la marca ya no ayuda.
const int _budget = 250000;

/// Los trozos de [line], con los que no están en [other] marcados.
///
/// Null si no merece la pena marcar: las dos líneas no se parecen en nada
/// --entonces es una línea nueva, no una cambiada, y marcarla entera no dice
/// más que su color-- o son demasiado largas.
List<WordSpan>? wordSpans(String line, String other) {
  final mine = _tokens(line);
  final theirs = _tokens(other);
  if (mine.isEmpty || theirs.isEmpty) return null;
  if (mine.length * theirs.length > _budget) return null;

  // La subsecuencia común más larga, por programación dinámica.
  final rows = mine.length + 1;
  final columns = theirs.length + 1;
  final table = List.generate(rows, (_) => List<int>.filled(columns, 0));
  for (var i = mine.length - 1; i >= 0; i -= 1) {
    for (var j = theirs.length - 1; j >= 0; j -= 1) {
      table[i][j] = mine[i] == theirs[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }

  final kept = List<bool>.filled(mine.length, false);
  var i = 0;
  var j = 0;
  while (i < mine.length && j < theirs.length) {
    if (mine[i] == theirs[j]) {
      kept[i] = true;
      i += 1;
      j += 1;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      i += 1;
    } else {
      j += 1;
    }
  }

  // Lo común tiene que ser algo más que los espacios: dos frases distintas
  // comparten siempre unos cuantos, y marcar todo lo demás es marcarlo todo.
  final shared = [
    for (var k = 0; k < mine.length; k += 1)
      if (kept[k] && mine[k].trim().isNotEmpty) mine[k],
  ];
  final words = mine.where((token) => token.trim().isNotEmpty).length;
  if (shared.isEmpty || shared.length * 3 < words) return null;

  // Juntas las piezas seguidas del mismo tipo. Un espacio entre dos palabras
  // cambiadas va con ellas, para que la marca sea una y no tres.
  final spans = <WordSpan>[];
  for (var k = 0; k < mine.length; k += 1) {
    var changed = !kept[k];
    if (!changed &&
        mine[k].trim().isEmpty &&
        k > 0 &&
        k + 1 < mine.length &&
        !kept[k - 1] &&
        !kept[k + 1]) {
      changed = true;
    }
    if (spans.isNotEmpty && spans.last.changed == changed) {
      spans[spans.length - 1] = (
        text: spans.last.text + mine[k],
        changed: changed,
      );
    } else {
      spans.add((text: mine[k], changed: changed));
    }
  }
  return spans;
}

/// Qué línea se compara con cuál en una lista de cambios.
///
/// Un bloque de líneas quitadas seguido de uno de añadidas es casi siempre la
/// misma frase reescrita: la primera quitada con la primera añadida, la
/// segunda con la segunda. Lo que sobra de uno de los dos lados no tiene
/// pareja y se queda sin marcar. Devuelve, por índice, el texto de la pareja.
Map<int, String> pairChangedLines(
  List<({bool removed, bool added, String text})> lines,
) {
  final pairs = <int, String>{};
  var i = 0;
  while (i < lines.length) {
    if (!lines[i].removed) {
      i += 1;
      continue;
    }
    final removedStart = i;
    while (i < lines.length && lines[i].removed) {
      i += 1;
    }
    final addedStart = i;
    while (i < lines.length && lines[i].added) {
      i += 1;
    }
    final removedCount = addedStart - removedStart;
    final addedCount = i - addedStart;
    final paired = removedCount < addedCount ? removedCount : addedCount;
    for (var k = 0; k < paired; k += 1) {
      pairs[removedStart + k] = lines[addedStart + k].text;
      pairs[addedStart + k] = lines[removedStart + k].text;
    }
  }
  return pairs;
}
