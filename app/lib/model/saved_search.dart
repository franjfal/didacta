/// Una búsqueda de la biblioteca guardada con un nombre.
///
/// Es la dirección de la biblioteca --con lo buscado, los filtros y lo
/// abierto-- y un nombre para reconocerla: «Sin traducir al valenciano, de
/// Análisis». Guardar la dirección y no los filtros por separado es lo que
/// hace que lo que se guarde sea exactamente lo que se estaba mirando.
library;

import 'dart:convert';

class SavedSearch {
  const SavedSearch({required this.name, required this.url});

  final String name;

  /// `/?q=…&estado=falta`: lo que se abre al elegirla.
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  static List<SavedSearch> listFromJson(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map &&
              item['name'] is String &&
              item['url'] is String &&
              (item['url'] as String).startsWith('/'))
            SavedSearch(
              name: item['name'] as String,
              url: item['url'] as String,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  static String listToJson(List<SavedSearch> searches) =>
      jsonEncode([for (final search in searches) search.toJson()]);
}
