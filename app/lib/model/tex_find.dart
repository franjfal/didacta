/// Buscar y reemplazar dentro del texto que se edita.
///
/// Sin mirar mayúsculas por defecto, que es lo que se espera al buscar una
/// palabra; con ellas, o con una expresión regular, cuando se piden. Lo que se
/// reemplaza con una expresión puede usar `$1`, `$2`… para lo que capturó.
library;

import 'package:flutter/services.dart' show TextRange;

import 'tex_wrap.dart' show TexEdit;

/// Una búsqueda: lo escrito y cómo se lee.
class TexSearch {
  const TexSearch(this.query, {this.caseSensitive = false, this.regex = false});

  final String query;
  final bool caseSensitive;
  final bool regex;

  /// La expresión que busca, o una [FormatException] si lo escrito no es
  /// una expresión válida.
  RegExp get pattern => RegExp(
    regex ? query : RegExp.escape(query),
    caseSensitive: caseSensitive,
    multiLine: true,
  );
}

/// Dónde aparece [search] en [text], en orden. Vacío si no se busca nada.
///
/// Las coincidencias vacías --una expresión como `^` o `a*`-- no cuentan:
/// no hay nada que enseñar ni que reemplazar, y saltar de una a otra deja el
/// cursor quieto.
List<TextRange> findAll(String text, TexSearch search) {
  if (search.query.isEmpty) return const [];
  return [
    for (final match in search.pattern.allMatches(text))
      if (match.end > match.start)
        TextRange(start: match.start, end: match.end),
  ];
}

/// La coincidencia que va después de [offset], dando la vuelta al final.
int nextMatch(List<TextRange> found, int offset) {
  if (found.isEmpty) return -1;
  for (var i = 0; i < found.length; i += 1) {
    if (found[i].start >= offset) return i;
  }
  return 0;
}

/// Lo que se escribe en lugar de [range], con `$1`, `$2`… si es una
/// expresión.
String replacementFor(
  String text,
  TextRange range,
  TexSearch search,
  String replacement,
) {
  if (!search.regex) return replacement;
  final match = search.pattern.matchAsPrefix(text, range.start);
  if (match == null) return replacement;
  return replacement.replaceAllMapped(RegExp(r'\$(\d)'), (group) {
    final index = int.parse(group.group(1)!);
    return index <= match.groupCount ? (match.group(index) ?? '') : group[0]!;
  });
}

/// El texto con [range] reemplazado, y el cursor detrás de lo escrito.
TexEdit replaceOne(
  String text,
  TextRange range,
  TexSearch search,
  String replacement,
) {
  final written = replacementFor(text, range, search, replacement);
  final out = text.replaceRange(range.start, range.end, written);
  final end = range.start + written.length;
  return TexEdit(out, end, end);
}

/// Todas reemplazadas de una vez, y cuántas eran.
///
/// De una vez y no una a una: deshacer lo devuelve entero, y lo que se
/// escribe en una no se vuelve a buscar en la siguiente.
({String text, int count}) replaceAll(
  String text,
  TexSearch search,
  String replacement,
) {
  final found = findAll(text, search);
  if (found.isEmpty) return (text: text, count: 0);
  final out = StringBuffer();
  var from = 0;
  for (final range in found) {
    out
      ..write(text.substring(from, range.start))
      ..write(replacementFor(text, range, search, replacement));
    from = range.end;
  }
  out.write(text.substring(from));
  return (text: out.toString(), count: found.length);
}
