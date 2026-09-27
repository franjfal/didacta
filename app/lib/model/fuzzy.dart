/// Buscar con una errata: una letra de más, de menos, cambiada o dos
/// intercambiadas.
///
/// Lo que se teclea deprisa en un buscador sale así: «nomrados», «limtes»,
/// «ecuaciones difrenciales». Buscar tal cual no encuentra nada, y «nada
/// coincide» sobre una biblioteca que sí lo tiene enseña a desconfiar del
/// buscador.
///
/// Dos límites, a propósito:
///
/// * **Una errata por palabra, y solo en las de cinco letras o más.** En una
///   palabra corta una letra cambiada es otra palabra --«caso» y «cosa»,
///   «seno» y «sino»-- y lo que saldría sería ruido.
/// * **Solo en una palabra que no está tal cual en ningún sitio.** Si está,
///   está bien escrita.
/// * **Siempre por detrás de lo que coincide de verdad.** Quien escribe bien
///   una palabra quiere lo que la dice, no lo que se le parece; lo parecido
///   va después y se cuenta aparte.
///
/// Sin distancia de edición general ni índices de trigramas: con una errata
/// como mucho, comparar es recorrer las dos palabras una vez.
library;

/// Desde cuántas letras se admite una errata.
const int fuzzyMinLength = 5;

/// Si [a] y [b] son iguales salvo, como mucho, una errata: una letra de más,
/// de menos, cambiada, o dos seguidas intercambiadas.
bool withinOneEdit(String a, String b) => _within(a, b, b.length);

/// Lo mismo contra los [lb] primeros caracteres de [b], sin cortarlo: se
/// pregunta por cada palabra de dos mil lecciones a cada letra que se teclea,
/// y crear una subcadena por pregunta se notaba.
bool _within(String a, String b, int lb) {
  final la = a.length;
  if ((la - lb).abs() > 1) return false;
  var i = 0;
  while (i < la && i < lb && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i += 1;
  }
  if (i == la && i == lb) return true;
  if (la == lb) {
    // Cambiada: el resto igual.
    if (_same(a, i + 1, b, i + 1)) return true;
    // Intercambiadas: «nomr» por «norm».
    return i + 1 < la &&
        a.codeUnitAt(i) == b.codeUnitAt(i + 1) &&
        a.codeUnitAt(i + 1) == b.codeUnitAt(i) &&
        _same(a, i + 2, b, i + 2);
  }
  // De más en la larga: saltarla deja el resto igual.
  return la > lb ? _same(a, i + 1, b, i) : _same(a, i, b, i + 1);
}

/// Si lo que queda de [a] desde [from] está en [b] desde [at]. Quien llama
/// ya ha comprobado que cabe en la parte de [b] que cuenta.
bool _same(String a, int from, String b, int at) {
  var j = at;
  for (var k = from; k < a.length; k += 1, j += 1) {
    if (j >= b.length || a.codeUnitAt(k) != b.codeUnitAt(j)) return false;
  }
  return true;
}

/// Si [word] casa con [token] con una errata, entera o como principio.
///
/// Como principio porque así se busca: se teclea «normad» y se espera
/// «normados», igual que sin errata.
bool fuzzyWordMatch(String word, String token) {
  final n = word.length;
  if (n < fuzzyMinLength) return false;
  if ((token.length - n) < -1) return false;
  if (_within(word, token, token.length)) return true;
  for (final cut in [n - 1, n, n + 1]) {
    if (cut >= token.length) continue;
    if (_within(word, token, cut)) return true;
  }
  return false;
}

/// Las palabras de un texto ya plegado (sin tildes, en minúsculas).
Set<String> searchTokens(String folded) => {
  for (final token in folded.split(_separators))
    if (token.length >= fuzzyMinLength - 1) token,
};

final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Cómo casa lo buscado con un texto.
enum SearchMatch {
  /// Alguna palabra no está, ni con una errata.
  none,

  /// Todas están, alguna con una errata.
  near,

  /// Todas están tal cual.
  exact,
}

/// Cómo casan las [words] buscadas --ya plegadas-- con [haystack], cuyas
/// palabras son [tokens].
///
/// Cada palabra tiene que estar, tal cual o con una errata: escribir
/// «normados problemas» estrecha en lugar de no encontrar nada, y lo mismo
/// si una de las dos lleva una letra cambiada.
///
/// Con una errata, solo las palabras de [typos]: las que no aparecen tal
/// cual en ningún sitio. Una palabra que existe está bien escrita, y
/// buscar «integral» no tiene por qué traer también todo lo que dice
/// «integrar».
SearchMatch matchWords(
  List<String> words,
  String haystack,
  Set<String> Function() tokens, {
  Set<String> typos = const {},
}) {
  var result = SearchMatch.exact;
  for (final word in words) {
    if (word.isEmpty || haystack.contains(word)) continue;
    if (word.length < fuzzyMinLength || !typos.contains(word)) {
      return SearchMatch.none;
    }
    if (!tokens().any((token) => fuzzyWordMatch(word, token))) {
      return SearchMatch.none;
    }
    result = SearchMatch.near;
  }
  return result;
}
