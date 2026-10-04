/// Dónde se está en la biblioteca, escrito en su dirección.
///
/// La ruta que se ha abierto, los filtros y lo buscado eran estado de la
/// pantalla, y se perdían al abrir una lección y volver: se volvía a la raíz,
/// sin filtros, a buscar otra vez lo mismo. En la dirección --`/?q=norma&
/// tipo=problem&en=analysis/normed`-- sobreviven a ir y volver, se pueden
/// mandar en un enlace y el botón de atrás vuelve al sitio.
///
/// Los nombres, en castellano y cortos: es una dirección que se lee.
library;

import 'library_filter.dart';

class LibraryPlace {
  const LibraryPlace({
    this.query = '',
    this.block,
    this.category,
    this.kind,
    this.tag,
    this.status = StatusFilter.any,
    this.sort = LibrarySort.path,
    this.unusedOnly = false,
    this.browse = const [],
    this.inText = false,
  });

  /// Lo que se ha escrito en el buscador.
  final String query;

  final String? block;
  final String? category;
  final String? kind;
  final String? tag;
  final StatusFilter status;
  final LibrarySort sort;
  final bool unusedOnly;

  /// Por dónde se ha entrado en el árbol: la categoría, el tema y la
  /// etiqueta, los que haya.
  final List<String> browse;

  /// Si lo buscado se busca también dentro del texto de las lecciones.
  final bool inText;

  static const Map<StatusFilter, String> _statuses = {
    StatusFilter.present: 'hay',
    StatusFilter.missing: 'falta',
    StatusFilter.needsWork: 'pendiente',
  };

  static const Map<LibrarySort, String> _sorts = {
    LibrarySort.title: 'titulo',
    LibrarySort.usage: 'uso',
    LibrarySort.needsWork: 'pendiente',
  };

  /// Lo que se lee de la dirección. Lo que no se entiende se ignora: un
  /// enlace viejo o mal copiado abre la biblioteca, no un error.
  factory LibraryPlace.fromQuery(Map<String, String> query) {
    String? text(String key) {
      final value = query[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    T pick<T>(Map<T, String> names, String? value, T fallback) {
      for (final entry in names.entries) {
        if (entry.value == value) return entry.key;
      }
      return fallback;
    }

    return LibraryPlace(
      query: text('q') ?? '',
      block: text('bloque'),
      category: text('categoria'),
      kind: text('tipo'),
      tag: text('etiqueta'),
      status: pick(_statuses, text('estado'), StatusFilter.any),
      sort: pick(_sorts, text('orden'), LibrarySort.path),
      unusedOnly: text('sinusar') == '1',
      inText: text('texto') == '1',
      browse: _browse(text('en') ?? ''),
    );
  }

  /// El subtema de las lecciones que no declaran ninguno es la cadena vacía,
  /// y tiene que sobrevivir a la dirección: `analysis/normed/`.
  static List<String> _browse(String value) {
    final parts = value.split('/');
    final deep = parts.length > 2 && parts[0].isNotEmpty && parts[1].isNotEmpty;
    return [
      for (var i = 0; i < parts.length; i += 1)
        if (parts[i].isNotEmpty || (i == 2 && deep)) parts[i],
    ].take(3).toList();
  }

  /// Lo que se escribe en la dirección: solo lo que no es lo de salida.
  Map<String, String> toQuery() => {
    if (query.trim().isNotEmpty) 'q': query.trim(),
    'bloque': ?block,
    'categoria': ?category,
    'tipo': ?kind,
    'etiqueta': ?tag,
    'estado': ?_statuses[status],
    'orden': ?_sorts[sort],
    if (unusedOnly) 'sinusar': '1',
    if (inText) 'texto': '1',
    if (browse.isNotEmpty) 'en': browse.join('/'),
  };

  /// Los filtros, en el idioma que se mira. El idioma no va en la dirección:
  /// es de la sesión, y manda en toda la aplicación.
  LibraryFilter filterIn(String language) => LibraryFilter(
    query: query,
    block: block,
    category: category,
    kind: kind,
    tag: tag,
    status: status,
    sort: sort,
    unusedOnly: unusedOnly,
    language: language,
  );

  factory LibraryPlace.of(
    LibraryFilter filter,
    List<String> browse, {
    bool inText = false,
  }) => LibraryPlace(
    inText: inText,
    query: filter.query,
    block: filter.block,
    category: filter.category,
    kind: filter.kind,
    tag: filter.tag,
    status: filter.status,
    sort: filter.sort,
    unusedOnly: filter.unusedOnly,
    browse: browse,
  );

  @override
  bool operator ==(Object other) => other is LibraryPlace && _key == other._key;

  @override
  int get hashCode => _key.hashCode;

  String get _key => Uri(queryParameters: toQuery()).query;
}
