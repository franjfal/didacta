/// Editar `snippets.yaml` sin volver a serializarlo.
///
/// La misma regla que [TemplatesFile] y [TaxonomyFile]: el fichero puede
/// estar escrito a mano, lleva comentarios que explican qué es cada cosa, y
/// un serializador de YAML se los llevaría todos. Aquí se cambia **por
/// entradas**: una entrada es desde su `- id:` hasta la siguiente, y lo que
/// hay fuera de las que se tocan se queda como estaba, comentarios incluidos.
///
/// Una entrada se escribe entera y no campo a campo --al revés que una
/// plantilla-- porque lleva bloques `|` de LaTeX, y reemplazar una línea
/// dentro de uno de esos bloques es la forma de dejar el fichero roto.
///
/// Solo el lado de escribir. Leerlo es cosa del motor, que lo pone en el
/// índice; dos lectores del mismo fichero serían dos respuestas distintas a
/// la misma pregunta.
library;

import 'latex_snippets.dart';
import '../l10n/tr.dart';

/// Lo que no se puede hacer con este fichero.
class SnippetsException implements Exception {
  const SnippetsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SnippetsFile {
  SnippetsFile(String text) : _lines = text.split('\n');

  /// Un fichero nuevo con la lista de serie escrita, entrada a entrada.
  ///
  /// Es lo que se escribe la primera vez que se toca la barra de un
  /// repositorio que no tenía fichero: sin fichero ofrecía los de serie, y
  /// con fichero ofrece lo que el fichero diga. Para que añadir uno propio no
  /// quite los demás, el fichero nuevo empieza diciendo lo que ya había.
  factory SnippetsFile.withDefaults() {
    final file = SnippetsFile(emptySnippetsYaml);
    for (final snippet in didactaSnippets) {
      file.put(SnippetDeclaration(id: snippet.id));
    }
    return file;
  }

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// Los ids, en el orden del fichero.
  List<String> get ids => [for (final entry in _entries()) entry.id];

  bool has(String id) => ids.contains(id);

  /// Pone una entrada: la cambia donde está, o la añade.
  ///
  /// Nueva, va detrás de [after] si se dice y está, y si no al final.
  void put(SnippetDeclaration declaration, {String? after}) {
    final written = renderSnippet(declaration);
    final entries = _entries();
    final found = entries.where((e) => e.id == declaration.id).firstOrNull;
    if (found != null) {
      final end = _trimmedEnd(found);
      _lines.replaceRange(found.firstLine, end + 1, written);
      return;
    }

    final head = _head();
    if (head < 0) {
      if (_lines.isNotEmpty && _lines.last.trim().isEmpty) _lines.removeLast();
      _lines.addAll(['snippets:', ...written, '']);
      return;
    }
    if (_lines[head].contains('[')) {
      _lines[head] = _lines[head].substring(0, _lines[head].indexOf(':') + 1);
    }
    final anchor = after == null
        ? null
        : entries.where((e) => e.id == after).firstOrNull;
    final at = anchor != null
        ? _trimmedEnd(anchor) + 1
        : (entries.isEmpty ? head + 1 : _trimmedEnd(entries.last) + 1);
    _lines.insertAll(at, written);
  }

  /// Quita una entrada. Quitar la última deja `snippets: []`, que es «ninguno»
  /// y no «los de serie»: quitarlos todos es una decisión.
  void remove(String id) {
    final entries = _entries();
    final found = entries.where((e) => e.id == id).firstOrNull;
    if (found == null) {
      throw SnippetsException(tr('no se declara el snippet `{0}`', [id]));
    }
    _lines.removeRange(found.firstLine, found.lastLine + 1);
    if (_entries().isEmpty) {
      final head = _head();
      if (head >= 0) _lines[head] = tr('snippets: []');
    }
  }

  /// Ordena las entradas como [order].
  ///
  /// Las que [order] no nombra van detrás, en el orden que tenían: reordenar
  /// una vista filtrada no puede tirar lo que no se ve.
  void reorder(List<String> order) {
    final entries = _entries();
    if (entries.isEmpty) return;
    final blocks = <String, List<String>>{
      for (final entry in entries)
        entry.id: _lines.sublist(entry.firstLine, _trimmedEnd(entry) + 1),
    };
    final sorted = [
      for (final id in order)
        if (blocks.containsKey(id)) id,
      for (final entry in entries)
        if (!order.contains(entry.id)) entry.id,
    ];
    final start = entries.first.firstLine;
    final end = _trimmedEnd(entries.last);
    _lines.replaceRange(start, end + 1, [
      for (final id in sorted) ...blocks[id]!,
    ]);
  }

  // -- la estructura -------------------------------------------------------

  int _head() => _lines.indexWhere((line) => line.startsWith('snippets:'));

  List<_Entry> _entries() {
    final head = _head();
    if (head < 0) return const [];
    final found = <_Entry>[];
    int? itemIndent;
    var i = head + 1;
    for (; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (line.trim().isEmpty) continue;
      final indent = line.length - line.trimLeft().length;
      final trimmed = line.trimLeft();
      if (indent == 0 && !trimmed.startsWith('#') && !trimmed.startsWith('-')) {
        break;
      }
      if (!trimmed.startsWith('- ')) continue;
      itemIndent ??= indent;
      if (indent != itemIndent) continue;
      final match = _itemId.firstMatch(trimmed);
      if (match == null) continue;
      found.add(_Entry(_unquote(match.group(1)!.trim()), i));
    }
    final stop = i;
    for (var k = 0; k < found.length; k += 1) {
      found[k].lastLine = k + 1 < found.length
          ? found[k + 1].firstLine - 1
          : stop - 1;
    }
    return found;
  }

  /// La última línea con algo de la entrada: las líneas en blanco de detrás
  /// no son suyas. Un comentario de detrás sí lo es, porque suele hablar de
  /// ella.
  int _trimmedEnd(_Entry entry) {
    var end = entry.lastLine;
    while (end > entry.firstLine && _lines[end].trim().isEmpty) {
      end -= 1;
    }
    return end;
  }

  static final RegExp _itemId = RegExp(r'^-\s+id:\s*(.*?)\s*(#.*)?$');

  static String _unquote(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}

class _Entry {
  _Entry(this.id, this.firstLine);

  final String id;
  final int firstLine;
  int lastLine = 0;
}

/// Las líneas de una entrada, con dos espacios de sangría para el guion.
List<String> renderSnippet(SnippetDeclaration d) {
  const field = '    ';
  final out = <String>['  - id: ${d.id}'];
  void scalar(String key, String? value) {
    if (value == null) return;
    out.add('$field$key: ${quoteSnippetScalar(value)}');
  }

  void names(String key, List<String>? value) {
    if (value == null) return;
    out.add('$field$key: [${value.map(quoteSnippetScalar).join(', ')}]');
  }

  void literal(String key, String? value) {
    if (value == null) return;
    final lines = _literalLines(value);
    if (lines.isEmpty) {
      out.add("$field$key: ''");
      return;
    }
    out.add('$field$key: |');
    for (final line in lines) {
      out.add(line.isEmpty ? '' : '$field  $line');
    }
  }

  scalar('label', d.label);
  scalar('group', d.group);
  scalar('description', d.description);
  scalar('environment', d.environment);
  scalar('command', d.command);
  names('environment_aliases', d.environmentAliases);
  names('command_aliases', d.commandAliases);
  scalar('arguments', d.arguments);
  if (d.block != null) out.add(tr('{0}block: {1}', [field, d.block]));
  literal('definition', d.definition);
  literal('sample', d.sample);
  return out;
}

/// El texto de un bloque `|`, listo para sangrar.
///
/// Sin tabuladores --YAML no los admite como sangría, y dentro de un bloque
/// uno al principio de línea lo cierra-- y sin sangría común. La primera
/// línea no puede empezar por un blanco: es la que dice cuánto se sangra el
/// bloque, y una con dos espacios de más cierra el bloque en la siguiente.
/// A LaTeX le dan igual las dos cosas.
List<String> _literalLines(String value) {
  var lines = value.replaceAll('\r\n', '\n').replaceAll('\t', '  ').split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines = lines.sublist(1);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines = lines.sublist(0, lines.length - 1);
  }
  if (lines.isEmpty) return const [];
  final filled = lines.where((line) => line.trim().isNotEmpty);
  final margin = filled
      .map((line) => line.length - line.trimLeft().length)
      .reduce((a, b) => a < b ? a : b);
  lines = [
    for (final line in lines)
      line.trim().isEmpty ? '' : line.substring(margin).trimRight(),
  ];
  lines[0] = lines[0].trimLeft();
  return lines;
}

/// Un escalar de una línea, entre comillas simples si hace falta.
///
/// Simples y no dobles porque dentro no hay escapes: `'\textcolor'` es la
/// barra y la orden, tal cual, y lo único que se dobla es la comilla.
String quoteSnippetScalar(String value) {
  const reserved = {
    'true', 'false', 'yes', 'no', 'on', 'off', 'null', '~', 'y', 'n', //
    'True', 'False', 'Yes', 'No', 'On', 'Off', 'Null', 'NULL', //
  };
  final plain = RegExp(r'^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 _.,()/-]*$');
  final needs =
      value.isEmpty ||
      value.trim() != value ||
      reserved.contains(value) ||
      !plain.hasMatch(value) ||
      value.contains(': ') ||
      value.contains(' #');
  if (!needs) return value;
  return "'${value.replaceAll("'", "''")}'";
}

/// El fichero que se escribe cuando no había ninguno.
const String emptySnippetsYaml = '''
# Los snippets de este repositorio: lo que ofrece la barra del editor para
# envolver lo que marques --un teorema, un «solo diapositivas», una caja
# propia-- y quitarlo después sin tocar lo de dentro.
#
# Cómo funciona, que es lo que hay que saber antes de editar esto a mano:
#
#   * el orden de la lista es el orden en que salen en la barra;
#   * una entrada con solo el `id` es uno de los que trae Didacta, tal cual.
#     Los campos que se le escriban lo retocan: otro rótulo, otro grupo;
#   * uno propio dice qué escribe: `environment` (\\begin{…} … \\end{…}),
#     `command` (\\orden{…}) o los dos, y `arguments` si lleva algo entre el
#     nombre y el cuerpo, como `[Título]`;
#   * `definition` es el LaTeX que lo define, si no lo define ya Didacta o un
#     paquete. Se lee al compilar **cualquier cosa** de este repositorio, justo
#     antes del preámbulo de la plantilla: una definición con un error deja
#     sin compilar todo el repositorio, y por eso se prueba antes en Ajustes;
#   * `sample` es el texto con que se ve en la vista previa.
#
# Sin este fichero, la barra ofrece los de serie. Con él, exactamente lo que
# diga: quitar una entrada la quita de la barra de este repositorio.
#
# El mismo id en dos repositorios es el mismo snippet, y si no dicen lo mismo
# sale en «Entre repositorios» para igualarlo.

snippets: []
''';
