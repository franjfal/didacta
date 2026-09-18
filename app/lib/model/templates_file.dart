/// Editar `templates.yaml` sin volver a serializarlo.
///
/// La misma regla que [TaxonomyFile], [ThemesFile] y [DegreesFile], y por la
/// misma razón: el fichero se escribe a mano y lleva veinte líneas de
/// comentarios explicando qué es un id y por qué apagar una plantilla no es
/// borrarla. Volcarlo con un serializador de YAML los borraría todos.
///
/// Lo que **no** está aquí es el preámbulo de cada plantilla: vive en
/// `templates/<id>.tex` y es LaTeX de verdad, así que se escribe como lo que
/// es, con su propio fichero y su propio diff.
///
/// Solo el lado de escribir. Leer las plantillas ya lo hace el motor al
/// indexar, y tener dos lectores del mismo fichero es tener dos respuestas
/// distintas a la misma pregunta.
library;

/// Lo que no se puede hacer con este fichero.
class TemplatesException implements Exception {
  const TemplatesException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TemplatesFile {
  TemplatesFile(String text) : _lines = text.split('\n');

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// Los ids declarados, en el orden del fichero, que es el orden en que se
  /// ofrecen las salidas.
  List<String> get ids => [for (final template in _templates()) template.id];

  /// El nombre por idioma de una plantilla, tal como está escrito.
  Map<String, String> titlesOf(String id) {
    final template = _find(id);
    if (template == null) return const {};
    final titles = <String, String>{};
    var inside = false;
    for (var i = template.firstLine; i <= template.lastLine; i += 1) {
      final line = _lines[i];
      if (_keyAt(line, template.fieldIndent) == 'title') {
        inside = true;
        continue;
      }
      if (!inside) continue;
      final match = _title.firstMatch(line.trim());
      if (match == null) {
        if (_keyAt(line, template.fieldIndent) != null) break;
        continue;
      }
      titles[match.group(1)!] = _unquote(match.group(2)!.trim());
    }
    return titles;
  }

  /// El valor de un campo suelto: `class`, `options`, `active`.
  String? fieldOf(String id, String key) {
    final template = _find(id);
    if (template == null) return null;
    for (var i = template.firstLine; i <= template.lastLine; i += 1) {
      if (_keyAt(_lines[i], template.fieldIndent) != key) continue;
      final at = _lines[i].indexOf(':');
      return _unquote(_beforeComment(_lines[i].substring(at + 1)).trim());
    }
    return null;
  }

  /// Cambia el nombre de una plantilla, en todos los idiomas a la vez.
  ///
  /// Lo que llegue vacío se escribe `# TODO: xx`, que es lo que hace el
  /// repositorio y lo que cuenta como pendiente.
  ///
  /// Sin ninguno **se quita el bloque entero** en vez de negarse, y esa es la
  /// diferencia con un bloque o un grado: una plantilla sin nombre no se
  /// queda sin poder enseñarse, se enseña por el que deduce el motor de sus
  /// ejes -- «Diapositivas (sin pausas)» --, que es un nombre de verdad.
  void setTitles(String id, Map<String, String> titles) {
    final template = _require(id);
    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    final pending = [
      for (final entry in titles.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];

    final field = ' ' * template.fieldIndent;
    final written = kept.isEmpty
        ? <String>[]
        : <String>[
            '${field}title:',
            for (final entry in kept.entries)
              '$field  ${entry.key}: ${_quote(entry.value)}',
            for (final code in pending) '$field  # TODO: $code',
          ];
    _replaceBlock(template, 'title', written);
  }

  /// Cambia un campo suelto. Sin él, lo añade detrás del id.
  void setField(String id, String key, String? value) {
    final template = _require(id);
    final field = ' ' * template.fieldIndent;
    if (value == null) {
      _replaceBlock(template, key, const []);
      return;
    }
    _replaceBlock(template, key, ['$field$key: ${_quote(value)}']);
  }

  /// Enciende o apaga una plantilla.
  ///
  /// Encendida es lo normal, así que se escribe solo cuando está apagada: un
  /// `active: true` en cada plantilla sería ruido en quince declaraciones
  /// para no decir nada.
  void setActive(String id, bool active) =>
      setField(id, 'active', active ? null : 'false');

  /// Los ejes, en forma de flujo: `axes: {medium: slides, pauses: "off"}`.
  ///
  /// En una línea y no en un bloque de seis porque se leen juntos --son los
  /// ejes de **una** salida-- y porque así una plantilla entera cabe en la
  /// pantalla mientras se edita.
  void setAxes(String id, Map<String, String> axes) {
    final template = _require(id);
    final field = ' ' * template.fieldIndent;
    if (axes.isEmpty) {
      _replaceBlock(template, 'axes', const []);
      return;
    }
    final pairs = [
      for (final key in axes.keys.toList()..sort())
        '$key: ${_quoteAxis(axes[key]!)}',
    ];
    _replaceBlock(template, 'axes', ['${field}axes: {${pairs.join(', ')}}']);
  }

  /// Declara una plantilla nueva al final de la lista.
  void add({
    required String id,
    required Map<String, String> titles,
    required String documentClass,
    String classOptions = '',
    Map<String, String> axes = const {},
    List<String> languages = const [],
  }) {
    if (ids.contains(id)) {
      throw TemplatesException('este repositorio ya declara `$id`');
    }
    if (documentClass.trim().isEmpty) {
      throw const TemplatesException(
        'una plantilla sin clase de documento no se puede compilar',
      );
    }
    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    final pairs = [
      for (final key in axes.keys.toList()..sort())
        '$key: ${_quoteAxis(axes[key]!)}',
    ];

    final written = <String>[
      '  - id: $id',
      if (kept.isNotEmpty) ...[
        '    title:',
        for (final entry in kept.entries)
          '      ${entry.key}: ${_quote(entry.value)}',
        for (final code in languages)
          if (!kept.containsKey(code)) '      # TODO: $code',
      ],
      '    class: ${documentClass.trim()}',
      if (classOptions.trim().isNotEmpty)
        '    options: ${_quote(classOptions.trim())}',
      if (pairs.isNotEmpty) '    axes: {${pairs.join(', ')}}',
    ];

    final at = _lines.indexWhere((line) => _keyAt(line, 0) == 'templates');
    if (at < 0) {
      if (_lines.isNotEmpty && _lines.last.trim().isNotEmpty) _lines.add('');
      _lines.addAll(['templates:', ...written]);
      return;
    }
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
    _lines.insertAll(end, ['', ...written]);
  }

  /// Quita una plantilla de la lista.
  ///
  /// Solo la declaración. El `templates/<id>.tex` lo borra quien llama, si
  /// quiere: es el trabajo de alguien y borrarlo desde aquí, de paso, sería
  /// la clase de ayuda que nadie pidió.
  void remove(String id) {
    final template = _require(id);
    var end = template.lastLine;
    while (end + 1 < _lines.length && _lines[end + 1].trim().isEmpty) {
      end += 1;
    }
    _lines.removeRange(template.firstLine, end + 1);
    if (ids.isEmpty) {
      final at = _lines.indexWhere((line) => _keyAt(line, 0) == 'templates');
      if (at >= 0) _lines[at] = 'templates: []';
    }
  }

  // -- leer y escribir la estructura ----------------------------------------

  /// Sustituye el campo [key] de una plantilla por [written].
  ///
  /// Lista vacía lo quita. El bloque de un campo acaba en la siguiente clave
  /// de su misma sangría, que es lo que permite cambiar `title:` --que lleva
  /// tres líneas debajo-- igual que `class:`, que lleva una.
  void _replaceBlock(_Template template, String key, List<String> written) {
    var start = -1;
    var end = -1;
    for (var i = template.firstLine; i <= template.lastLine; i += 1) {
      if (start < 0) {
        if (_keyAt(_lines[i], template.fieldIndent) == key) start = i;
        continue;
      }
      if (_keyAt(_lines[i], template.fieldIndent) != null) {
        end = i - 1;
        break;
      }
      final trimmed = _lines[i].trim();
      if (trimmed.isEmpty ||
          (trimmed.startsWith('#') && !_pending.hasMatch(trimmed))) {
        end = i - 1;
        break;
      }
    }
    if (start < 0) {
      if (written.isEmpty) return;
      _lines.insertAll(template.firstLine + 1, written);
      return;
    }
    if (end < start) end = template.lastLine;
    _lines.replaceRange(start, end + 1, written);
  }

  _Template? _find(String id) =>
      _templates().where((template) => template.id == id).firstOrNull;

  _Template _require(String id) {
    final found = _find(id);
    if (found == null) {
      throw TemplatesException('no se declara la plantilla `$id`');
    }
    return found;
  }

  List<_Template> _templates() {
    final start = _lines.indexWhere((line) => _keyAt(line, 0) == 'templates');
    if (start < 0) return const [];

    final found = <_Template>[];
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
        _Template(
          id: _unquote(_beforeComment(match.group(1)!).trim()),
          firstLine: i,
          fieldIndent: indent + 2,
        ),
      );
    }

    for (var i = 0; i < found.length; i += 1) {
      found[i].lastLine = i + 1 < found.length
          ? found[i + 1].firstLine - 1
          : _endOfList(found[i].firstLine);
    }
    return found;
  }

  int _endOfList(int from) {
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

  static String _quote(String value) {
    final needs =
        value.contains(':') ||
        value.contains('#') ||
        value.contains(',') ||
        value.trim() != value ||
        value.startsWith('[') ||
        value.startsWith('{') ||
        value.startsWith('-') ||
        value.isEmpty;
    if (!needs) return value;
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  /// `on` y `off` van entre comillas porque en YAML son booleanos.
  ///
  /// Sin ellas, `pauses: off` se lee como el falso y el motor recibe un eje
  /// que no existe. Lo traduce igual --es la forma natural de escribirlo-- y
  /// aun así lo que escribe Didacta se escribe bien.
  static String _quoteAxis(String value) =>
      value == 'on' || value == 'off' ? '"$value"' : _quote(value);

  static final RegExp _key = RegExp(r'^([A-Za-z_][A-Za-z0-9_-]*):');
  static final RegExp _itemId = RegExp(r'^-\s+id:\s*(.*)$');
  static final RegExp _title = RegExp(r'^([a-z]{2}):(.*)$');
  static final RegExp _pending = RegExp(r'^#\s*TODO:\s*[a-z]{2}\s*$');
}

class _Template {
  _Template({
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
const String emptyTemplatesYaml = '''
# Las plantillas de compilación de este repositorio.
#
# Una plantilla es una **salida**: qué clase de documento se produce, con qué
# opciones y con qué ejes. Cada lección y cada documento se compilan en las
# plantillas que les tocan, y aquí es donde se dice qué plantillas hay.
#
# Cómo funciona, que es lo que hay que saber antes de editar esto:
#
#   * el **id** es lo que guarda el bloque en `taxonomy.yaml` y lo que guardan
#     los ficheros que eligen unas cuantas; no se toca nunca;
#   * el **título** es lo que se lee, y se puede cambiar cuando se quiera. Sin
#     título, la salida se enseña por lo que hace: «Diapositivas (sin pausas)»;
#   * `active: false` la deja declarada y fuera de lo que se compila, que es
#     lo que se quiere de una versión que este curso no se da: borrarla
#     perdería su preámbulo;
#   * el **preámbulo** de cada una vive en `templates/<id>.tex` y es opcional.
#     Se lee al final del preámbulo de Didacta, así que puede redefinir lo que
#     Didacta acaba de definir: márgenes, colores, un entorno.
#
# Una plantilla con el id de una de las que trae Didacta la sustituye. Las de
# serie siguen en el programa, que es lo que mantiene vivo un
# `pdflatex master.tex` a mano, en un editor y sin que el motor intervenga.

templates: []
''';
