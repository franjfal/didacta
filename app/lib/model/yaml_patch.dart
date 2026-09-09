/// Editing one field of a YAML file without touching the rest of it.
///
/// The obvious way to edit `unit.yaml` from the interface is to parse it,
/// change the value and write it back out. That would be wrong here, and the
/// repository shows why: a migrated `unit.yaml` carries the file it came
/// from, and a `TODO` on every field the legacy material did not record.
///
///     # Adfgvx
///     #
///     # Migrated from:
///     #   00classnotes/908Criptography/.../00CAST-ADFGVX.tex
///
///     title:
///       # TODO: no title could be extracted from the source
///       es: Adfgvx
///
/// Those comments are the work list for two thousand units. A round trip
/// through a parser deletes all of them, silently, on the first edit anyone
/// makes. So this does surgery instead: it finds the line the key is on and
/// rewrites that line, and every byte it was not asked about survives —
/// comments, blank lines, key order, quoting style.
///
/// The trade is deliberate. This understands the shapes `unit.yaml` and
/// `year.yaml` actually use — block mappings, flow lists, flow maps one level
/// deep — and not the whole of YAML. When it does not recognise a shape it
/// says so rather than guessing, and the editor falls back to offering the
/// raw text. Refusing beats corrupting a file that is the source of truth.
library;

/// Why a patch could not be applied.
class YamlPatchException implements Exception {
  const YamlPatchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A YAML document being edited in place.
class YamlPatch {
  YamlPatch(String text) : _lines = _split(text), _eol = _eolOf(text);

  final List<String> _lines;

  /// Preserved rather than normalised: rewriting every line ending of a file
  /// to make one edit produces a diff nobody can read.
  final String _eol;

  static List<String> _split(String text) => text.split('\n');

  static String _eolOf(String text) => text.contains('\r\n') ? '\r\n' : '\n';

  String get result => _lines.join('\n');

  /// The line ending in use, for a caller that needs to know.
  String get eol => _eol;

  // -- reading -------------------------------------------------------------

  /// The scalar at [path], or null when the key is absent or explicitly null.
  String? scalar(List<String> path) {
    final found = _find(path);
    if (found == null) return null;
    final value = _valueOf(_lines[found.line]);
    if (value.isEmpty || value == 'null' || value == '~') return null;
    return _unquote(value);
  }

  /// The list at [path], flow (`[a, b]`) or block (`- a`), else empty.
  List<String> list(List<String> path) {
    final found = _find(path);
    if (found == null) return const [];
    final inline = _valueOf(_lines[found.line]);
    if (inline.startsWith('[')) return _parseFlowList(inline);

    final items = <String>[];
    for (var i = found.line + 1; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (_isBlankOrComment(line)) continue;
      final indent = _indentOf(line);
      if (indent <= found.indent) break;
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('- ') && trimmed != '-') break;
      items.add(_unquote(trimmed.substring(1).trim()));
    }
    return items;
  }

  /// The keys of the mapping at [path], in the order they appear.
  List<String> keysUnder(List<String> path) {
    final found = _find(path);
    if (found == null) return const [];
    final keys = <String>[];
    int? childIndent;
    for (var i = found.line + 1; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (_isBlankOrComment(line)) continue;
      final indent = _indentOf(line);
      if (indent <= found.indent) break;
      childIndent ??= indent;
      if (indent != childIndent) continue;
      final key = _keyOf(line);
      if (key != null) keys.add(key);
    }
    return keys;
  }

  // -- writing -------------------------------------------------------------

  /// Sets a scalar. A null [value] writes `null`, which is what the schema
  /// uses for "not recorded" -- deleting the key would lose the fact that the
  /// field exists and is unanswered.
  void setScalar(List<String> path, String? value) {
    final written = value == null ? 'null' : _quoteIfNeeded(value);
    final found = _find(path);
    if (found != null) {
      _lines[found.line] = _rewriteValue(_lines[found.line], written);
      return;
    }
    _insert(path, written);
  }

  /// Sets a numeric field, unquoted, so the engine reads a number.
  ///
  /// Separate from [setScalar] on purpose: `duration_minutes: '50'` is a
  /// string, and the schema wants a number. Which of the two a field is, is
  /// the caller's knowledge, not something to guess from the text someone
  /// typed -- a tag `2025` really is a string.
  void setNumber(List<String> path, num? value) {
    final found = _find(path);
    final written = value == null ? 'null' : '$value';
    if (found != null) {
      _lines[found.line] = _rewriteValue(_lines[found.line], written);
      return;
    }
    _insert(path, written);
  }

  /// Sets a field inside a flow mapping, as `languages: {es: {status: draft}}`
  /// is written in the repository.
  ///
  /// Handles the one-level-deep flow map that `unit.yaml` uses for a
  /// language's status, and the block form too, because both appear.
  void setInFlowMap(List<String> path, String field, String? value) {
    final found = _find(path);
    if (found == null) {
      final written = value == null ? '{}' : '{$field: ${_quoteIfNeeded(value)}}';
      _insert(path, written);
      return;
    }

    final inline = _valueOf(_lines[found.line]);
    if (inline.isEmpty) {
      // A block mapping under the key: treat the field as a nested scalar.
      setScalar([...path, field], value);
      return;
    }
    if (!inline.startsWith('{') || !inline.endsWith('}')) {
      throw YamlPatchException(
        'el valor de `${path.join('.')}` no es un mapa que se pueda editar '
        'campo a campo: $inline',
      );
    }

    final entries = _parseFlowMap(inline);
    if (value == null) {
      entries.remove(field);
    } else {
      entries[field] = _quoteIfNeeded(value);
    }
    final body = entries.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    _lines[found.line] = _rewriteValue(_lines[found.line], '{$body}');
  }

  /// Replaces a flow list: `tags: [a, b]`.
  void setFlowList(List<String> path, List<String> values) {
    final written = '[${values.map(_quoteIfNeeded).join(', ')}]';
    final found = _find(path);
    if (found == null) {
      _insert(path, written);
      return;
    }
    // A key that currently holds a block list has to lose those lines, or the
    // file ends up with the value twice.
    _dropBlockChildren(found);
    _lines[found.line] = _rewriteValue(_lines[found.line], written);
  }

  /// Replaces a block list. Empty writes `[]`, which is how the repository
  /// spells "none" and keeps the field visible.
  void setBlockList(List<String> path, List<String> values) {
    final found = _find(path);
    if (found == null) {
      if (values.isEmpty) {
        _insert(path, '[]');
        return;
      }
      _insert(path, '');
      final at = _find(path)!;
      _lines.insertAll(at.line + 1, [
        for (final value in values)
          '${' ' * (at.indent + 2)}- ${_quoteIfNeeded(value)}',
      ]);
      return;
    }

    _dropBlockChildren(found);
    if (values.isEmpty) {
      _lines[found.line] = _rewriteValue(_lines[found.line], '[]');
      return;
    }
    _lines[found.line] = _rewriteValue(_lines[found.line], '');
    _lines.insertAll(found.line + 1, [
      for (final value in values)
        '${' ' * (found.indent + 2)}- ${_quoteIfNeeded(value)}',
    ]);
  }

  /// Removes a key and whatever block belongs to it.
  void remove(List<String> path) {
    final found = _find(path);
    if (found == null) return;
    _dropBlockChildren(found);
    _lines.removeAt(found.line);
  }

  // -- the machinery -------------------------------------------------------

  /// Where a key lives: which line, and at what indentation.
  _Located? _find(List<String> path) {
    var from = 0;
    var to = _lines.length;
    var parentIndent = -1;
    _Located? found;

    for (final key in path) {
      found = _findIn(key, from, to, parentIndent);
      if (found == null) return null;
      from = found.line + 1;
      to = _endOfBlock(found);
      parentIndent = found.indent;
    }
    return found;
  }

  _Located? _findIn(String key, int from, int to, int parentIndent) {
    int? wanted;
    for (var i = from; i < to; i += 1) {
      final line = _lines[i];
      if (_isBlankOrComment(line)) continue;
      final indent = _indentOf(line);
      if (indent <= parentIndent) break;
      // The first non-blank line fixes the indentation of this level; deeper
      // lines belong to a child and must not be matched.
      wanted ??= indent;
      if (indent != wanted) continue;
      if (_keyOf(line) == key) return _Located(line: i, indent: indent);
    }
    return null;
  }

  /// The line after the last one belonging to [found]'s value.
  int _endOfBlock(_Located found) {
    for (var i = found.line + 1; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (_isBlankOrComment(line)) continue;
      if (_indentOf(line) <= found.indent) return i;
    }
    return _lines.length;
  }

  void _dropBlockChildren(_Located found) {
    final end = _endOfBlock(found);
    if (end <= found.line + 1) return;
    // Trailing blanks and comments after the last real child belong to what
    // comes next, not to this key, so they stay.
    var last = found.line;
    for (var i = found.line + 1; i < end; i += 1) {
      if (!_isBlankOrComment(_lines[i])) last = i;
    }
    if (last > found.line) _lines.removeRange(found.line + 1, last + 1);
  }

  /// Adds a key that was not there. At the end of its parent's block, which
  /// keeps related fields together instead of scattering them.
  void _insert(List<String> path, String value) {
    if (path.length == 1) {
      var at = _lines.length;
      while (at > 0 && _lines[at - 1].trim().isEmpty) {
        at -= 1;
      }
      _lines.insert(at, '${path.single}: $value'.trimRight());
      return;
    }

    final parentPath = path.sublist(0, path.length - 1);
    final parent = _find(parentPath);
    if (parent == null) {
      throw YamlPatchException(
        'no existe `${parentPath.join('.')}`, así que no se puede añadir '
        '`${path.last}` dentro',
      );
    }

    final inline = _valueOf(_lines[parent.line]);
    if (inline.startsWith('{')) {
      setInFlowMap(parentPath, path.last, _unquote(value));
      return;
    }
    if (inline == '[]' || inline == '{}') {
      // An empty collection has no block to insert into: open one.
      _lines[parent.line] = _rewriteValue(_lines[parent.line], '');
    } else if (inline.isNotEmpty) {
      throw YamlPatchException(
        '`${parentPath.join('.')}` tiene un valor escalar, así que no puede '
        'contener `${path.last}`',
      );
    }

    final indent = _childIndentOf(parent);
    var at = _endOfBlock(parent);
    while (at > parent.line + 1 && _isBlankOrComment(_lines[at - 1])) {
      at -= 1;
    }
    _lines.insert(at, '${' ' * indent}${path.last}: $value'.trimRight());
  }

  int _childIndentOf(_Located parent) {
    for (var i = parent.line + 1; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (_isBlankOrComment(line)) continue;
      final indent = _indentOf(line);
      if (indent <= parent.indent) break;
      return indent;
    }
    return parent.indent + 2;
  }

  /// Replaces the value on a `key: value` line, keeping the key, the
  /// indentation and any trailing comment.
  static String _rewriteValue(String line, String value) {
    final match = _keyLine.firstMatch(line);
    if (match == null) {
      throw YamlPatchException('no es una línea `clave: valor`: $line');
    }
    final rest = match.group(3)!;
    final comment = _trailingComment(rest);
    final head = '${match.group(1)}${match.group(2)}:';
    final body = value.isEmpty ? '' : ' $value';
    return '$head$body$comment';
  }

  /// The ` # ...` at the end of a value, if any.
  ///
  /// Only when it is preceded by whitespace: a `#` inside a value is not a
  /// comment, and a title like `C# para músicos` must survive.
  static String _trailingComment(String rest) {
    var quote = '';
    for (var i = 0; i < rest.length; i += 1) {
      final char = rest[i];
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '#' && i > 0 && _isSpace(rest[i - 1])) {
        return ' ${rest.substring(i)}'.replaceFirst(RegExp(r'^\s+'), ' ');
      }
    }
    return '';
  }

  static final RegExp _keyLine =
      RegExp(r'^(\s*)([A-Za-z_][A-Za-z0-9_.-]*):(.*)$');

  static bool _isSpace(String char) => char == ' ' || char == '\t';

  static bool _isBlankOrComment(String line) {
    final trimmed = line.trim();
    return trimmed.isEmpty || trimmed.startsWith('#');
  }

  static int _indentOf(String line) {
    var count = 0;
    while (count < line.length && line[count] == ' ') {
      count += 1;
    }
    return count;
  }

  static String? _keyOf(String line) => _keyLine.firstMatch(line)?.group(2);

  /// The value part of a `key: value` line, comment and whitespace removed.
  static String _valueOf(String line) {
    final match = _keyLine.firstMatch(line);
    if (match == null) return '';
    var rest = match.group(3)!;
    final comment = _trailingComment(rest);
    if (comment.isNotEmpty) {
      rest = rest.substring(0, rest.length - comment.trimLeft().length - 1);
    }
    return rest.trim();
  }

  static List<String> _parseFlowList(String value) {
    final inner = value.substring(1, value.lastIndexOf(']')).trim();
    if (inner.isEmpty) return [];
    return [for (final part in _splitFlow(inner)) _unquote(part.trim())];
  }

  static Map<String, String> _parseFlowMap(String value) {
    final inner = value.substring(1, value.lastIndexOf('}')).trim();
    final entries = <String, String>{};
    if (inner.isEmpty) return entries;
    for (final part in _splitFlow(inner)) {
      final at = part.indexOf(':');
      if (at < 0) {
        throw YamlPatchException('no se entiende el mapa: $value');
      }
      entries[part.substring(0, at).trim()] = part.substring(at + 1).trim();
    }
    return entries;
  }

  /// Splits on commas that are not inside quotes or nested brackets.
  static List<String> _splitFlow(String inner) {
    final parts = <String>[];
    var depth = 0;
    var quote = '';
    var start = 0;
    for (var i = 0; i < inner.length; i += 1) {
      final char = inner[i];
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '[' || char == '{') {
        depth += 1;
      } else if (char == ']' || char == '}') {
        depth -= 1;
      } else if (char == ',' && depth == 0) {
        parts.add(inner.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(inner.substring(start));
    return [for (final part in parts) if (part.trim().isNotEmpty) part];
  }

  static String _unquote(String value) {
    if (value.length >= 2) {
      if (value.startsWith("'") && value.endsWith("'")) {
        return value.substring(1, value.length - 1).replaceAll("''", "'");
      }
      if (value.startsWith('"') && value.endsWith('"')) {
        return value
            .substring(1, value.length - 1)
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\');
      }
    }
    return value;
  }
}

/// Quotes a scalar when YAML would otherwise read it as something else.
///
/// Single quotes, because the values here are LaTeX: `$\ell^p$` in double
/// quotes would have its backslash eaten, and titles with maths in them are
/// the normal case in this repository, not the exception.
String _quoteIfNeeded(String value) {
  if (value.isEmpty) return "''";

  final needsQuoting = value != value.trim() ||
      value.contains(': ') ||
      value.endsWith(':') ||
      value.contains(' #') ||
      _leadingIndicators.contains(value[0]) ||
      _looksLikeSomethingElse.hasMatch(value);

  if (!needsQuoting) return value;
  return "'${value.replaceAll("'", "''")}'";
}

/// Characters YAML gives a meaning to at the start of a scalar.
const Set<String> _leadingIndicators = {
  '-', '?', ':', ',', '[', ']', '{', '}', '#', '&', '*', '!', '|', '>',
  '%', '@', '`', '"', "'",
};

/// Values a parser would hand back as a number, a boolean or a null.
final RegExp _looksLikeSomethingElse = RegExp(
  r'^(-?\d+(\.\d+)?([eE][-+]?\d+)?|0[xX][0-9a-fA-F]+|'
  r'true|false|yes|no|on|off|null|~|True|False|Yes|No|On|Off|Null|NULL|TRUE|FALSE)$',
);

class _Located {
  const _Located({required this.line, required this.indent});

  final int line;
  final int indent;
}
