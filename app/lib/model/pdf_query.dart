/// Lo que se escribe para buscar en un PDF, como patrón para su texto.
///
/// El texto que saca pdfium de un PDF de Didacta es limpio --las tildes, una
/// letra cada una; «fi», dos letras--, pero las líneas se cortan donde las
/// cortó LaTeX. Así que un espacio de lo escrito vale por cualquier blanco,
/// salto de línea incluido: «teorema de Bolzano» se encuentra aunque «de»
/// acabe una línea. Y como en la biblioteca, sin mirar tildes ni mayúsculas:
/// «bolzano», «límite» y «limite» encuentran lo que se espera.
library;

const Map<String, String> _variants = {
  'a': 'aáàäâ',
  'e': 'eéèëê',
  'i': 'iíìïî',
  'o': 'oóòöô',
  'u': 'uúùüû',
  'n': 'nñ',
  'c': 'cç',
};

const String _accented = 'áàäâéèëêíìïîóòöôúùüûñçÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ';
const String _plain = 'aaaaeeeeiiiioooouuuuncaaaaeeeeiiiioooouuuunc';

/// El patrón para [query], o null si no hay nada que buscar.
RegExp? pdfQueryPattern(String query) {
  final text = query.trim();
  if (text.isEmpty) return null;
  final out = StringBuffer();
  var blank = false;
  for (final rune in text.runes) {
    var char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      if (!blank) out.write(r'\s+');
      blank = true;
      continue;
    }
    blank = false;
    final at = _accented.indexOf(char);
    if (at >= 0) char = _plain[at];
    final variants = _variants[char.toLowerCase()];
    out.write(variants == null ? RegExp.escape(char) : '[$variants]');
  }
  return RegExp(out.toString(), caseSensitive: false, unicode: true);
}
