/// El orden de la paleta de órdenes: qué sale primero al escribir.
///
/// La paleta mezcla cosas muy distintas --una acción de la pantalla, ir a
/// Ajustes, una lección entre dos mil-- y lo que decide si sirve es que lo
/// buscado salga arriba sin tener que bajar. Tres reglas, en este orden:
///
/// 1. **Cómo casa el título.** Que empiece por lo escrito gana a que una de
///    sus palabras empiece así, y eso a que lo diga en medio; lo que solo
///    casa por el detalle o por una palabra clave va después, y lo que casa
///    con una errata, lo último --antes si la errata está en el título--
///    (ver `fuzzy.dart`).
/// 2. **De qué tipo es.** A igualdad, lo de la pantalla en la que se está,
///    luego las órdenes, las pantallas, los cursos, los documentos y por
///    último las lecciones: son dos mil, y un título corto casaría siempre
///    con alguna.
/// 3. **Lo más corto**, y después por orden alfabético: entre «Análisis» y
///    «Análisis funcional avanzado», buscando «análisis» se quería lo
///    primero.
library;

import 'fuzzy.dart';
import 'slug.dart';
import '../l10n/tr.dart';

/// De qué tipo es una entrada, en el orden en que se prefieren.
enum PaletteGroup {
  /// Lo que se puede hacer en la pantalla que se está mirando.
  here('En esta pantalla'),

  /// Las órdenes de siempre: actualizar, enviar, el tamaño del texto…
  action('Órdenes'),

  /// Ir a una pantalla o a una sección de Ajustes.
  screen('Ir a'),

  /// Lo abierto hace poco.
  recent('Recientes'),

  /// Una asignatura en un curso académico.
  course('Cursos'),

  /// Un documento de un curso.
  document('Documentos'),

  /// Una lección.
  unit('Lecciones');

  const PaletteGroup(this._label);

  /// Cómo se titula el grupo en la lista, en el idioma de la interfaz.
  String get label => tr(_label);
  final String _label;
}

/// Lo que la paleta necesita saber de una entrada para ordenarla.
abstract interface class PaletteCandidate {
  String get title;

  /// Lo que se lee debajo: la ruta de una lección, el curso de un documento.
  String get detail;

  /// Otras palabras con las que se encuentra, sin enseñarlas: «pdf» para
  /// «Ver el PDF», «oscuro» para «Apariencia oscura».
  String get keywords;

  PaletteGroup get group;
}

/// Cuántas entradas se enseñan como mucho: más no se leen.
const int paletteLimit = 60;

/// Las entradas que casan con [query], de la mejor a la peor. Ver arriba.
List<T> rankPalette<T extends PaletteCandidate>(
  List<T> candidates,
  String query, {
  int limit = paletteLimit,
}) {
  final words = [
    for (final word in fold(query.toLowerCase()).split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];
  if (words.isEmpty) return candidates.take(limit).toList();

  final prepared = [for (final entry in candidates) _Prepared(entry)];
  // Con una errata, solo las palabras que no están tal cual en ninguna
  // entrada: si existe, está bien escrita.
  final typos = {
    for (final word in words)
      if (word.length >= fuzzyMinLength &&
          !prepared.any((entry) => entry.all.contains(word)))
        word,
  };

  final scored = <({T entry, int score, int length, String title})>[];
  for (final entry in prepared) {
    final score = _score(entry, words, typos);
    if (score == null) continue;
    scored.add((
      entry: entry.entry as T,
      score: score,
      length: entry.title.length,
      title: entry.title,
    ));
  }
  scored.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    if (byScore != 0) return byScore;
    final byGroup = a.entry.group.index.compareTo(b.entry.group.index);
    if (byGroup != 0) return byGroup;
    final byLength = a.length.compareTo(b.length);
    if (byLength != 0) return byLength;
    return a.title.compareTo(b.title);
  });
  return [for (final hit in scored.take(limit)) hit.entry];
}

class _Prepared {
  _Prepared(this.entry)
    : title = fold(entry.title.toLowerCase()),
      all = fold(
        '${entry.title} ${entry.detail} ${entry.keywords}'.toLowerCase(),
      );

  final PaletteCandidate entry;
  final String title;
  final String all;

  Set<String>? _tokens;
  Set<String> get tokens => _tokens ??= searchTokens(all);

  Set<String>? _titleTokens;
  Set<String> get titleTokens => _titleTokens ??= searchTokens(title);
}

/// Cuanto más bajo, mejor; null si no casa.
int? _score(_Prepared entry, List<String> words, Set<String> typos) {
  final match = matchWords(words, entry.all, () => entry.tokens, typos: typos);
  if (match == SearchMatch.none) return null;
  if (match == SearchMatch.near) {
    // Con una errata, mejor si la palabra parecida está en el título.
    final inTitle = matchWords(
      words,
      entry.title,
      () => entry.titleTokens,
      typos: typos,
    );
    return inTitle == SearchMatch.none ? 6 : 5;
  }
  final phrase = words.join(' ');
  final title = entry.title;
  if (title.startsWith(phrase)) return 0;
  if (title.contains(' $phrase') || title.contains('-$phrase')) return 1;
  if (title.contains(phrase)) return 2;
  if (words.every(title.contains)) return 3;
  return 4;
}
