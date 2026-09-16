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

const String _accented = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
const String _plain = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';

/// El mismo texto sin tildes.
String fold(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final at = _accented.indexOf(char);
    buffer.write(at >= 0 ? _plain[at] : char);
  }
  return buffer.toString();
}

/// Compara dos títulos como los ordenaría una persona.
///
/// Plegando las tildes, que es lo que hace que funcione en castellano:
/// comparando los caracteres a secas, «Álgebra» va **después** de «Zoología»
/// --la `á` es el carácter 225 y la `z` el 122-- y una lista de asignaturas
/// con Álgebra al final después de la Z parece rota.
///
/// Con el texto original como desempate, para que dos títulos que solo se
/// distinguen por una tilde no se consideren el mismo y salgan en un orden
/// que cambia entre ejecuciones.
int compareTitles(String a, String b) {
  final folded = fold(a).toLowerCase().compareTo(fold(b).toLowerCase());
  return folded != 0 ? folded : a.toLowerCase().compareTo(b.toLowerCase());
}

String slugify(String text) => fold(text)
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
