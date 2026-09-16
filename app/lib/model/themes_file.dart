/// Editar `themes.yaml` sin volver a serializarlo.
///
/// La misma regla que [CompositionFile], y por la misma razón: el fichero está
/// escrito a mano y lleva veinte líneas de comentarios explicando qué pasa
/// cuando falta el repositorio que declara un tema. Volcarlo con un serializador
/// de YAML los borraría todos, y con ellos la única explicación que hay de por
/// qué esto no puede romper nada.
///
/// Y los `# TODO: va` son datos, no ruido: son la lista de lo que queda por
/// traducir, y la pantalla de traducciones los cuenta. Un idioma sin título se
/// escribe comentado, nunca como cadena vacía.
///
/// Solo el lado de escribir. Leer los temas ya lo hace el motor al indexar, y
/// tener dos lectores del mismo fichero es tener dos respuestas distintas a la
/// misma pregunta.
library;

/// Lo que no se puede hacer con este fichero.
class ThemesException implements Exception {
  const ThemesException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ThemesFile {
  ThemesFile(String text) : _lines = text.split('\n');

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// Los ids declarados, en el orden del fichero, que es el orden en que se
  /// dan los temas.
  List<String> get ids => [for (final theme in _themes()) theme.id];

  /// El título por idioma de un tema, tal como está escrito.
  Map<String, String> titlesOf(String id) {
    final theme = _themes().where((t) => t.id == id).firstOrNull;
    if (theme == null) return const {};
    final titles = <String, String>{};
    var inside = false;
    for (var i = theme.firstLine; i <= theme.lastLine; i += 1) {
      final line = _lines[i];
      if (_keyAt(line, theme.fieldIndent) == 'title') {
        inside = true;
        continue;
      }
      if (!inside) continue;
      final match = _title.firstMatch(line.trim());
      if (match == null) {
        if (_keyAt(line, theme.fieldIndent) != null) break;
        continue;
      }
      titles[match.group(1)!] = _unquote(match.group(2)!.trim());
    }
    return titles;
  }

  /// Cambia el título de un tema, en todos los idiomas a la vez.
  ///
  /// Lo que llegue vacío se escribe `# TODO: xx`, que es lo que hace el
  /// repositorio y lo que cuenta como pendiente. Al menos uno tiene que tener
  /// título: un tema sin ninguno se enseñaría por su id, que es un slug.
  void setTitles(String id, Map<String, String> titles) {
    final theme = _themes().where((t) => t.id == id).firstOrNull;
    if (theme == null) throw ThemesException('no se declara el tema `$id`');

    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (kept.isEmpty) {
      throw const ThemesException(
        'un tema sin título en ningún idioma se enseñaría por su id',
      );
    }
    final pending = [
      for (final entry in titles.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];

    final field = ' ' * theme.fieldIndent;
    final block = <String>[
      '${field}title:',
      for (final entry in kept.entries)
        '$field  ${entry.key}: ${_quote(entry.value)}',
      for (final code in pending) '$field  # TODO: $code',
    ];

    var start = -1;
    var end = -1;
    for (var i = theme.firstLine; i <= theme.lastLine; i += 1) {
      if (start < 0) {
        if (_keyAt(_lines[i], theme.fieldIndent) == 'title') start = i;
        continue;
      }
      if (_keyAt(_lines[i], theme.fieldIndent) != null) {
        end = i - 1;
        break;
      }
      final trimmed = _lines[i].trim();
      // Un comentario que no es un `# TODO: xx` lo escribió alguien: el bloque
      // acaba antes de él y se queda donde estaba.
      if (trimmed.isEmpty ||
          (trimmed.startsWith('#') && !_pending.hasMatch(trimmed))) {
        end = i - 1;
        break;
      }
    }
    if (start < 0) {
      _lines.insertAll(theme.firstLine + 1, block);
      return;
    }
    if (end < start) end = theme.lastLine;
    _lines.replaceRange(start, end + 1, block);
  }

  // -- leer la estructura ---------------------------------------------------

  List<_Theme> _themes() {
    final start = _lines.indexWhere((line) => _keyAt(line, 0) == 'themes');
    if (start < 0) return const [];

    final themes = <_Theme>[];
    int? itemIndent;
    for (var i = start + 1; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      final indent = _indentOf(line);
      if (indent == 0) break;
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('- ')) continue;
      itemIndent ??= indent;
      if (indent != itemIndent) continue;
      final match = _itemId.firstMatch(trimmed);
      if (match == null) continue;
      themes.add(
        _Theme(
          id: _unquote(_beforeComment(match.group(1)!).trim()),
          firstLine: i,
          fieldIndent: indent + 2,
        ),
      );
    }

    for (var i = 0; i < themes.length; i += 1) {
      themes[i].lastLine = i + 1 < themes.length
          ? themes[i + 1].firstLine - 1
          : _endOfThemes(themes[i].firstLine);
    }
    return themes;
  }

  int _endOfThemes(int from) {
    var last = from;
    for (var i = from + 1; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (line.trim().isEmpty) continue;
      if (_indentOf(line) == 0) return last;
      last = i;
    }
    return last;
  }

  static int _indentOf(String line) => line.length - line.trimLeft().length;

  /// La clave de una línea, si la tiene a esa sangría exacta.
  static String? _keyAt(String line, int indent) {
    if (_indentOf(line) != indent) return null;
    final match = _key.firstMatch(line.trimLeft());
    return match?.group(1);
  }

  static String _beforeComment(String value) {
    final at = value.indexOf(' #');
    return at < 0 ? value : value.substring(0, at);
  }

  static String _unquote(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Entre comillas cuando hace falta. Un título como `Tema 1: los reales`
  /// lleva dos puntos, que sin comillas es otra clave y el fichero deja de
  /// leerse.
  static String _quote(String value) {
    final needs =
        value.contains(':') ||
        value.contains('#') ||
        value.trim() != value ||
        value.startsWith('[') ||
        value.startsWith('{') ||
        value.startsWith('-') ||
        value.isEmpty;
    if (!needs) return value;
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  static final RegExp _key = RegExp(r'^([A-Za-z_][A-Za-z0-9_-]*):');
  static final RegExp _itemId = RegExp(r'^-\s+id:\s*(.*)$');
  static final RegExp _title = RegExp(r'^([a-z]{2}):(.*)$');
  static final RegExp _pending = RegExp(r'^#\s*TODO:\s*[a-z]{2}\s*$');
}

class _Theme {
  _Theme({
    required this.id,
    required this.firstLine,
    required this.fieldIndent,
  });

  final String id;
  final int firstLine;
  final int fieldIndent;
  int lastLine = 0;
}
