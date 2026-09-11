/// De un título a un identificador.
///
/// «Análisis Matemático III (grupo B)» da `analisis-matematico-iii-grupo-b`,
/// que es lo que alguien habría escrito a mano. Compartido entre la
/// asignatura nueva y el grupo nuevo porque la regla tiene que ser la misma:
/// dos formas de convertir un título en una carpeta acaban dando dos
/// carpetas distintas para el mismo título.
///
/// Las tildes se pliegan en lugar de borrarse: quitar la «á» de «Análisis»
/// daría `anlisis`, que no se lee.
library;

String slugify(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const to = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final at = from.indexOf(char);
    buffer.write(at >= 0 ? to[at] : char);
  }
  return buffer
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
