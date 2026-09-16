/// Editar `degrees.yaml` sin volver a serializarlo.
///
/// La misma regla que [ThemesFile], y por la misma razón: el fichero está
/// escrito a mano y lleva comentarios que explican qué pasa cuando falta el
/// repositorio que declara un grado. Volcarlo con un serializador de YAML los
/// borraría, y con ellos la única explicación de por qué esto no rompe nada.
///
/// Los `# TODO: va` son datos, no ruido: son la lista de lo que queda por
/// traducir, y la pantalla de traducciones los cuenta. Un idioma sin título se
/// escribe comentado, nunca como cadena vacía.
///
/// Solo el lado de escribir. Leer los grados ya lo hace el motor al indexar, y
/// tener dos lectores del mismo fichero es tener dos respuestas distintas a la
/// misma pregunta.
library;

/// Lo que no se puede hacer con este fichero.
class DegreesException implements Exception {
  const DegreesException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DegreesFile {
  DegreesFile(String text) : _lines = text.split('\n');

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// Los ids declarados, en el orden del fichero, que es el orden en que se
  /// se ofrecen los grados.
  List<String> get ids => [for (final theme in _degrees()) theme.id];

  /// El título por idioma de un grado, tal como está escrito.
  Map<String, String> titlesOf(String id) {
    final degree = _degrees().where((t) => t.id == id).firstOrNull;
    if (degree == null) return const {};
    final titles = <String, String>{};
    var inside = false;
    for (var i = degree.firstLine; i <= degree.lastLine; i += 1) {
      final line = _lines[i];
      if (_keyAt(line, degree.fieldIndent) == 'title') {
        inside = true;
        continue;
      }
      if (!inside) continue;
      final match = _title.firstMatch(line.trim());
      if (match == null) {
        if (_keyAt(line, degree.fieldIndent) != null) break;
        continue;
      }
      titles[match.group(1)!] = _unquote(match.group(2)!.trim());
    }
    return titles;
  }

  /// Cambia el título de un grado, en todos los idiomas a la vez.
  ///
  /// Lo que llegue vacío se escribe `# TODO: xx`, que es lo que hace el
  /// repositorio y lo que cuenta como pendiente. Al menos uno tiene que tener
  /// título: un grado sin ninguno se enseñaría por su id, que es un slug.
  void setTitles(String id, Map<String, String> titles) {
    final degree = _degrees().where((t) => t.id == id).firstOrNull;
    if (degree == null) throw DegreesException('no se declara el grado `$id`');

    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (kept.isEmpty) {
      throw const DegreesException(
        'un grado sin título en ningún idioma se enseñaría por su id',
      );
    }
    final pending = [
      for (final entry in titles.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];

    final field = ' ' * degree.fieldIndent;
    final block = <String>[
      '${field}title:',
      for (final entry in kept.entries)
        '$field  ${entry.key}: ${_quote(entry.value)}',
      for (final code in pending) '$field  # TODO: $code',
    ];

    var start = -1;
    var end = -1;
    for (var i = degree.firstLine; i <= degree.lastLine; i += 1) {
      if (start < 0) {
        if (_keyAt(_lines[i], degree.fieldIndent) == 'title') start = i;
        continue;
      }
      if (_keyAt(_lines[i], degree.fieldIndent) != null) {
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
      _lines.insertAll(degree.firstLine + 1, block);
      return;
    }
    if (end < start) end = degree.lastLine;
    _lines.replaceRange(start, end + 1, block);
  }


  /// Declara un grado nuevo al final de la lista.
  ///
  /// Con el fichero entero si no había ninguno: `degrees.yaml` empieza con
  /// veinte líneas de comentarios que explican por qué esto no puede romper
  /// nada, y crearlo vacío las perdería en el primer grado que se añada.
  void add({
    required String id,
    required Map<String, String> titles,
    String? institution,
    required List<String> languages,
  }) {
    if (ids.contains(id)) {
      throw DegreesException('este repositorio ya declara el grado `$id`');
    }
    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (kept.isEmpty) {
      throw const DegreesException(
        'un grado sin título en ningún idioma se enseñaría por su id',
      );
    }

    final block = <String>[
      '  - id: $id',
      '    title:',
      for (final entry in kept.entries)
        '      ${entry.key}: ${_quote(entry.value)}',
      for (final code in languages)
        if (!kept.containsKey(code)) '      # TODO: $code',
      if ((institution ?? '').trim().isNotEmpty)
        '    institution: ${_quote(institution!.trim())}',
    ];

    final at = _lines.indexWhere((line) => _keyAt(line, 0) == 'degrees');
    if (at < 0) {
      // Sin clave `degrees:`: es un fichero que no existía, o uno que alguien
      // dejó a medias. Se añade al final, con su clave.
      if (_lines.isNotEmpty && _lines.last.trim().isNotEmpty) _lines.add('');
      _lines.addAll(['degrees:', ...block]);
      return;
    }
    // `degrees: []` pasa a ser una lista con un elemento.
    final head = _lines[at];
    if (head.contains('[')) _lines[at] = head.substring(0, head.indexOf(':') + 1);

    var end = _lines.length;
    for (var i = at + 1; i < _lines.length; i += 1) {
      if (_lines[i].trim().isEmpty) continue;
      if (_indentOf(_lines[i]) == 0) {
        end = i;
        break;
      }
    }
    while (end > at + 1 && _lines[end - 1].trim().isEmpty) {
      end -= 1;
    }
    _lines.insertAll(end, ['', ...block]);
  }

  // -- leer la estructura ---------------------------------------------------

  List<_Degree> _degrees() {
    final start = _lines.indexWhere((line) => _keyAt(line, 0) == 'degrees');
    if (start < 0) return const [];

    final found = <_Degree>[];
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
      found.add(
        _Degree(
          id: _unquote(_beforeComment(match.group(1)!).trim()),
          firstLine: i,
          fieldIndent: indent + 2,
        ),
      );
    }

    for (var i = 0; i < found.length; i += 1) {
      found[i].lastLine = i + 1 < found.length
          ? found[i + 1].firstLine - 1
          : _endOfDegrees(found[i].firstLine);
    }
    return found;
  }

  int _endOfDegrees(int from) {
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

class _Degree {
  _Degree({
    required this.id,
    required this.firstLine,
    required this.fieldIndent,
  });

  final String id;
  final int firstLine;
  final int fieldIndent;
  int lastLine = 0;
}

/// El fichero que se escribe cuando no había ninguno.
///
/// Los comentarios son la mitad del fichero a propósito: explican que un grado
/// que nadie declara no agrupa, que es la propiedad de la que depende que esto
/// no pueda romperle el material a quien no tenga este repositorio.
const String emptyDegreesYaml = '''
# Las titulaciones en que se dan las asignaturas de este repositorio.
#
# Un grado agrupa asignaturas, así que vive en la raíz y no dentro de una.
# Cada asignatura dice a cuál pertenece con `degree_id:` en su `course.yaml`.
#
# Cómo funciona, que es lo que hay que saber antes de editar esto:
#
#   * la asignatura **nombra** el grado y el grado lo **declara** quien lo
#     tenga, igual que con los temas;
#   * las dos cosas pueden vivir en repositorios distintos;
#   * un grado que no declara nadie no agrupa: sus asignaturas salen sueltas,
#     exactamente como salían antes de que existieran los grados.
#
# Por eso esto no puede romper nada. Quien tenga solo uno de los repositorios
# verá las mismas asignaturas que veía; lo que no verá es el grado.

degrees: []
''';
