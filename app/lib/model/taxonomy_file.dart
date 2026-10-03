/// Editar los bloques de `taxonomy.yaml` sin volver a serializarlo.
///
/// La misma regla que [ThemesFile] y [DegreesFile], y por la misma razón: el
/// fichero está escrito a mano y lleva veinte líneas de comentarios
/// explicando qué es un id y por qué no se toca nunca. Volcarlo con un
/// serializador de YAML los borraría todos, y con ellos la única explicación
/// que hay de por qué renombrar un bloque no mueve un solo fichero.
///
/// Y los `# TODO: va` son datos, no ruido: son la lista de lo que queda por
/// traducir, y la pantalla de traducciones los cuenta. Un idioma sin nombre se
/// escribe comentado, nunca como cadena vacía.
///
/// Los bloques se editan enteros --nombre, plantillas, quitar--. De las
/// categorías, los temas y los subtemas solo se **añade** ([declarePlace]),
/// que es lo que hace falta para crearlos desde las columnas de la biblioteca:
/// renombrarlos o quitarlos se sigue haciendo en el fichero, que es donde
/// están sus comentarios.
///
/// Solo el lado de escribir. Leer la taxonomía ya lo hace el motor al indexar,
/// y tener dos lectores del mismo fichero es tener dos respuestas distintas a
/// la misma pregunta.
library;

import '../l10n/tr.dart';

/// Lo que no se puede hacer con este fichero.
class TaxonomyException implements Exception {
  const TaxonomyException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TaxonomyFile {
  TaxonomyFile(String text) : _lines = text.split('\n');

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// Los ids declarados, en el orden del fichero.
  ///
  /// Y ese orden importa: es el orden en que se dan las partes de una
  /// asignatura --primero la teoría, luego los problemas-- y es el que se
  /// enseña. Alfabético los reordenaría al traducir la interfaz.
  List<String> get blockIds => [for (final block in _blocks()) block.id];

  /// El nombre por idioma de un bloque, tal como está escrito.
  Map<String, String> titlesOfBlock(String id) {
    final block = _blocks().where((b) => b.id == id).firstOrNull;
    if (block == null) return const {};
    final titles = <String, String>{};
    var inside = false;
    for (var i = block.firstLine; i <= block.lastLine; i += 1) {
      final line = _lines[i];
      if (_keyAt(line, block.fieldIndent) == 'title') {
        inside = true;
        continue;
      }
      if (!inside) continue;
      final match = _title.firstMatch(line.trim());
      if (match == null) {
        if (_keyAt(line, block.fieldIndent) != null) break;
        continue;
      }
      titles[match.group(1)!] = _unquote(match.group(2)!.trim());
    }
    return titles;
  }

  /// Cambia el nombre de un bloque, en todos los idiomas a la vez.
  ///
  /// Lo que llegue vacío se escribe `# TODO: xx`, que es lo que hace el
  /// repositorio y lo que cuenta como pendiente. Al menos uno tiene que tener
  /// nombre: un bloque sin ninguno se enseñaría por su id, que es un slug.
  void setBlockTitles(String id, Map<String, String> titles) {
    final block = _blocks().where((b) => b.id == id).firstOrNull;
    if (block == null) {
      throw TaxonomyException(tr('no se declara el bloque `{0}`', [id]));
    }

    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (kept.isEmpty) {
      throw TaxonomyException(
        tr('un bloque sin nombre en ningún idioma se enseñaría por su id'),
      );
    }
    final pending = [
      for (final entry in titles.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];

    final field = ' ' * block.fieldIndent;
    final written = <String>[
      '${field}title:',
      for (final entry in kept.entries)
        '$field  ${entry.key}: ${_quote(entry.value)}',
      for (final code in pending) '$field  # TODO: $code',
    ];

    var start = -1;
    var end = -1;
    for (var i = block.firstLine; i <= block.lastLine; i += 1) {
      if (start < 0) {
        if (_keyAt(_lines[i], block.fieldIndent) == 'title') start = i;
        continue;
      }
      if (_keyAt(_lines[i], block.fieldIndent) != null) {
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
      _lines.insertAll(block.firstLine + 1, written);
      return;
    }
    if (end < start) end = block.lastLine;
    _lines.replaceRange(start, end + 1, written);
  }

  /// Con qué plantillas se compila un bloque, por defecto.
  ///
  /// Lista vacía quita la línea, que es «todas las activas» y no «ninguna»:
  /// un bloque sin salidas no se podría compilar y nadie entendería por qué.
  void setBlockTemplates(String id, List<String> templates) {
    final block = _blocks().where((b) => b.id == id).firstOrNull;
    if (block == null) {
      throw TaxonomyException(tr('no se declara el bloque `{0}`', [id]));
    }
    final field = ' ' * block.fieldIndent;
    final written = templates.isEmpty
        ? <String>[]
        : ['${field}templates: [${templates.join(', ')}]'];

    for (var i = block.firstLine; i <= block.lastLine; i += 1) {
      if (_keyAt(_lines[i], block.fieldIndent) != 'templates') continue;
      _lines.replaceRange(i, i + 1, written);
      return;
    }
    if (written.isEmpty) return;
    _lines.insertAll(block.lastLine + 1, written);
  }

  /// Declara un bloque nuevo al final de la lista.
  ///
  /// Delante de `categories:` cuando la clave `blocks:` no existía todavía.
  /// No es cosmética: quien abre `taxonomy.yaml` a mano se encuentra primero
  /// las cuatro líneas de los bloques y después las mil de las categorías, y
  /// al revés no las encontraría nunca.
  void addBlock({
    required String id,
    required Map<String, String> titles,
    required List<String> languages,
  }) {
    if (blockIds.contains(id)) {
      throw TaxonomyException(
        tr('este repositorio ya declara el bloque `{0}`', [id]),
      );
    }
    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (kept.isEmpty) {
      throw TaxonomyException(
        tr('un bloque sin nombre en ningún idioma se enseñaría por su id'),
      );
    }

    final written = <String>[
      '  - id: $id',
      '    title:',
      for (final entry in kept.entries)
        '      ${entry.key}: ${_quote(entry.value)}',
      for (final code in languages)
        if (!kept.containsKey(code)) '      # TODO: $code',
    ];

    final at = _lines.indexWhere((line) => _keyAt(line, 0) == 'blocks');
    if (at < 0) {
      final categories = _lines.indexWhere(
        (line) => _keyAt(line, 0) == 'categories',
      );
      final head = ['blocks:', ...written, ''];
      if (categories < 0) {
        if (_lines.isNotEmpty && _lines.last.trim().isNotEmpty) _lines.add('');
        _lines.addAll(['blocks:', ...written]);
        return;
      }
      // Justo encima de `categories:`, y con sus comentarios si los lleva
      // delante: un comentario pegado a una clave es de esa clave.
      var where = categories;
      while (where > 0) {
        final above = _lines[where - 1].trimLeft();
        if (above.startsWith('#')) {
          where -= 1;
          continue;
        }
        break;
      }
      _lines.insertAll(where, head);
      return;
    }

    // `blocks: []` pasa a ser una lista con un elemento.
    final head = _lines[at];
    if (head.contains('[')) {
      _lines[at] = head.substring(0, head.indexOf(':') + 1);
    }

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
    _lines.insertAll(end, written);
  }

  /// Quita un bloque de la lista.
  ///
  /// Solo la declaración. Las unidades que lo nombran siguen nombrándolo, y
  /// eso es a propósito: borrar aquí no puede tocar noventa ficheros de otro
  /// directorio. Quien llama se encarga de moverlas antes --o de dejarlas, y
  /// entonces «Entre repositorios» las enseña como huérfanas--.
  void removeBlock(String id) {
    final block = _blocks().where((b) => b.id == id).firstOrNull;
    if (block == null) {
      throw TaxonomyException(tr('no se declara el bloque `{0}`', [id]));
    }
    var end = block.lastLine;
    // Las líneas en blanco de debajo se van con él; si no, cada bloque
    // borrado deja un hueco que no cierra nadie.
    while (end + 1 < _lines.length && _lines[end + 1].trim().isEmpty) {
      end += 1;
    }
    _lines.removeRange(block.firstLine, end + 1);

    // Sin ninguno queda `blocks:` colgando, que es un error de lectura: una
    // clave sin valor es null y no una lista vacía.
    if (blockIds.isEmpty) {
      final at = _lines.indexWhere((line) => _keyAt(line, 0) == 'blocks');
      if (at >= 0) _lines[at] = 'blocks: []';
    }
  }

  // -- categorías, temas y subtemas -----------------------------------------

  /// Si declara este sitio de la biblioteca: `calculo`, `calculo/limites` o
  /// `calculo/limites/concepto`.
  bool declares(String key) {
    final parts = key.split('/');
    var region = _region('categories', 0, 0, _lines.length);
    for (final (depth, id) in parts.indexed) {
      if (region == null) return false;
      final item = _item(region, id);
      if (item == null) return false;
      if (depth + 1 == parts.length) return true;
      region = _region(
        depth == 0 ? 'topics' : 'subtopics',
        item.$3 + 2,
        item.$1 + 1,
        item.$2,
      );
    }
    return false;
  }

  /// Declara un sitio de la biblioteca, y lo que le falte por encima.
  ///
  /// [titles] lleva el nombre por idioma de cada nivel, por su clave:
  /// `{'calculo': {...}, 'calculo/limites': {...}, 'calculo/limites/x': {...}}`.
  /// Lo que ya está declarado no se toca --ni su nombre--, así que llamarlo
  /// dos veces es lo mismo que una. Lo nuevo va al final de su lista, que es
  /// el orden en que se enseña; reordenar es cosa del fichero.
  ///
  /// Devuelve si ha cambiado algo.
  bool declarePlace(
    String key, {
    required Map<String, Map<String, String>> titles,
    required List<String> languages,
  }) {
    final parts = key.split('/');
    if (parts.isEmpty || parts.length > 3 || parts.any((p) => p.isEmpty)) {
      throw TaxonomyException(
        tr('`{0}` no es un sitio de la biblioteca', [key]),
      );
    }
    var changed = false;
    // Dónde se busca cada nivel: la clave de su lista, su sangría y el tramo
    // de líneas de su padre.
    var listKey = 'categories';
    var keyIndent = 0;
    var from = 0;
    var to = _lines.length;
    for (final (depth, id) in parts.indexed) {
      final here = parts.sublist(0, depth + 1).join('/');
      var region = _region(listKey, keyIndent, from, to);
      if (region == null) {
        _insertList(listKey, keyIndent, from, to);
        changed = true;
        to += 1;
        region = _region(listKey, keyIndent, from, to)!;
      }
      var item = _item(region, id);
      if (item == null) {
        final named = titles[here] ?? const <String, String>{};
        final kept = <String, String>{
          for (final entry in named.entries)
            if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
        };
        if (kept.isEmpty) {
          throw TaxonomyException(
            tr('`{0}` necesita un nombre en algún idioma', [here]),
          );
        }
        final pad = ' ' * (keyIndent + 2);
        final written = <String>[
          '$pad- id: $id',
          '$pad  title:',
          for (final entry in kept.entries)
            '$pad    ${entry.key}: ${_quote(entry.value)}',
          for (final code in languages)
            if (!kept.containsKey(code)) '$pad    # TODO: $code',
        ];
        _lines.insertAll(region.$2, written);
        changed = true;
        item = _item(
          _region(listKey, keyIndent, from, to + written.length)!,
          id,
        )!;
      }
      listKey = depth == 0 ? 'topics' : 'subtopics';
      keyIndent = item.$3 + 2;
      from = item.$1 + 1;
      to = item.$2;
    }
    return changed;
  }

  /// La lista `key:` a esa sangría dentro de [from, to): la línea de la clave
  /// y la línea siguiente a su último contenido (donde se añade). Null si no
  /// está.
  (int, int)? _region(String key, int indent, int from, int to) {
    for (var i = from; i < to && i < _lines.length; i += 1) {
      if (_keyAt(_lines[i], indent) != key) continue;
      var last = i;
      for (var j = i + 1; j < to && j < _lines.length; j += 1) {
        final line = _lines[j];
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        if (_indentOf(line) <= indent) break;
        last = j;
      }
      return (i, last + 1);
    }
    return null;
  }

  /// El elemento `- id: [id]` de una lista: su primera línea, la siguiente a
  /// la última suya y su sangría.
  (int, int, int)? _item((int, int) region, String id) {
    int? itemIndent;
    for (var i = region.$1 + 1; i < region.$2; i += 1) {
      final line = _lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (!trimmed.startsWith('- ')) continue;
      final indent = _indentOf(line);
      itemIndent ??= indent;
      if (indent != itemIndent) continue;
      final match = _itemId.firstMatch(trimmed);
      if (match == null) continue;
      if (_unquote(_beforeComment(match.group(1)!).trim()) != id) continue;
      var last = i;
      for (var j = i + 1; j < region.$2; j += 1) {
        final next = _lines[j];
        final t = next.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        if (_indentOf(next) <= indent) break;
        last = j;
      }
      return (i, last + 1, indent);
    }
    return null;
  }

  /// Escribe `key:` al final del tramo [from, to), detrás de su último
  /// contenido. `categories: []` se queda como lista vacía hasta que se le
  /// añade algo.
  void _insertList(String key, int indent, int from, int to) {
    // `categories: []` --o `topics: []`-- ya es la lista: se le quitan los
    // corchetes y se escribe debajo.
    for (var i = from; i < to && i < _lines.length; i += 1) {
      if (_keyAt(_lines[i], indent) == key && _lines[i].contains('[')) {
        _lines[i] = _lines[i].substring(0, _lines[i].indexOf(':') + 1);
        return;
      }
    }
    var at = to;
    while (at > from && _lines[at - 1].trim().isEmpty) {
      at -= 1;
    }
    if (indent == 0) {
      // Una clave de arriba: con una línea en blanco delante, como las demás.
      if (at > 0 && _lines[at - 1].trim().isNotEmpty) {
        _lines.insert(at, '');
        at += 1;
      }
    }
    _lines.insert(at, '${' ' * indent}$key:');
  }

  // -- leer la estructura ---------------------------------------------------

  List<_Block> _blocks() {
    final start = _lines.indexWhere((line) => _keyAt(line, 0) == 'blocks');
    if (start < 0) return const [];

    final found = <_Block>[];
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
        _Block(
          id: _unquote(_beforeComment(match.group(1)!).trim()),
          firstLine: i,
          fieldIndent: indent + 2,
        ),
      );
    }

    for (var i = 0; i < found.length; i += 1) {
      found[i].lastLine = i + 1 < found.length
          ? found[i + 1].firstLine - 1
          : _endOfBlocks(found[i].firstLine);
    }
    return found;
  }

  int _endOfBlocks(int from) {
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

  /// Entre comillas cuando hace falta. Un nombre como `Prácticas: ordenador`
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

class _Block {
  _Block({
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
/// Los comentarios son la mitad del fichero a propósito: explican que el id es
/// lo que guarda cada unidad y el nombre lo que se lee, que es la propiedad de
/// la que depende que renombrar un bloque no mueva un solo fichero.
const String emptyTaxonomyYaml = '''
# La clasificación con la que se etiqueta una unidad.
#
# Cada bloque, cada categoría y cada tema tienen un **id**, que es lo que
# guarda el `unit.yaml`, y un **nombre** por idioma, que es lo que se lee.
# Cambiar el nombre es cambiar una línea de aquí: no se mueve ningún fichero y
# no se rompe ninguna referencia. El id, en cambio, no se toca nunca -- si
# hace falta otro, es otro bloque.
#
# Los bloques son las partes en que se divide una asignatura: la teoría, los
# problemas, las prácticas de ordenador. Cómo funcionan, que es lo que hay que
# saber antes de editar esto:
#
#   * la unidad **nombra** el bloque y el bloque lo **declara** quien lo tenga;
#   * las dos cosas pueden vivir en repositorios distintos, y por eso la
#     teoría y los problemas pueden estar repartidos;
#   * un bloque que no declara nadie no esconde nada: sus unidades se ven
#     enteras, solo que el bloque se enseña por su id.

blocks: []
''';
