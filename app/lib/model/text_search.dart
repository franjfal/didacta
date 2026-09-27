/// Buscar en el texto de las lecciones, y no solo en su título.
///
/// «¿Dónde usé el teorema de Bolzano?» no se contesta con los títulos: está
/// en el cuerpo de tres lecciones que se llaman de otra forma. Esto prepara la
/// búsqueda que hace `git grep` en cada copia local --en milisegundos, sobre
/// dos mil ficheros-- y lee lo que devuelve.
///
/// **Sin mirar tildes, aunque git no sepa plegarlas.** Cada letra que puede
/// llevarla se busca como una alternativa de sus formas, `(a|á|à|ä|â|A|Á…)`:
/// una alternancia de secuencias de bytes funciona igual con cualquier
/// configuración regional, que es lo que no garantiza un `[aá]`.
library;

/// Una línea encontrada: en qué fichero, qué línea y qué dice.
class TextHit {
  const TextHit({
    required this.path,
    required this.line,
    required this.text,
    this.repo = '',
  });

  /// La ruta en el repositorio: `content/a/b/c/es.tex`.
  final String path;
  final int line;
  final String text;
  final String repo;

  /// La carpeta de la lección: la ruta sin el fichero.
  String get unitPath {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(0, slash);
  }

  /// El idioma, del nombre del fichero: `es.tex` es castellano.
  String get language {
    final name = path.substring(path.lastIndexOf('/') + 1);
    return name.endsWith('.tex') ? name.substring(0, name.length - 4) : '';
  }

  TextHit inRepo(String repo) =>
      TextHit(path: path, line: line, text: text, repo: repo);
}

const Map<String, String> _variants = {
  'a': 'aáàäâAÁÀÄÂ',
  'e': 'eéèëêEÉÈËÊ',
  'i': 'iíìïîIÍÌÏÎ',
  'o': 'oóòöôOÓÒÖÔ',
  'u': 'uúùüûUÚÙÜÛ',
  'n': 'nñNÑ',
  'c': 'cçCÇ',
};

const String _plain = 'áàäâéèëêíìïîóòöôúùüûñçÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ';
const String _base = 'aaaaeeeeiiiioooouuuuncaaaaeeeeiiiioooouuuunc';

/// La expresión extendida (`git grep -E`) que encuentra [query] sin mirar
/// tildes ni mayúsculas. Lo demás se busca tal cual: `\lambda` es `\lambda`.
String accentPattern(String query) {
  final out = StringBuffer();
  for (final rune in query.runes) {
    var char = String.fromCharCode(rune);
    final at = _plain.indexOf(char);
    if (at >= 0) char = _base[at];
    final variants = _variants[char.toLowerCase()];
    if (variants != null) {
      out.write('(${variants.split('').join('|')})');
    } else if (RegExp(r'[A-Za-z]').hasMatch(char)) {
      out.write('(${char.toLowerCase()}|${char.toUpperCase()})');
    } else if (r'.[]()*+?{}|^$\'.contains(char)) {
      out.write('\\$char');
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

/// Lo que devuelve `git grep -n --null`: `ruta\0línea\0texto` por línea.
List<TextHit> parseGrep(String output) {
  final hits = <TextHit>[];
  for (final row in output.split('\n')) {
    final parts = row.split('\u0000');
    if (parts.length < 3) continue;
    final line = int.tryParse(parts[1]);
    if (line == null) continue;
    hits.add(
      TextHit(
        path: parts[0],
        line: line,
        text: parts.sublist(2).join('\u0000'),
      ),
    );
  }
  return hits;
}
