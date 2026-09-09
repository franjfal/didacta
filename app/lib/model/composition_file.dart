/// Reading and rewriting the `structure:` block of a `year.yaml`.
///
/// A composition is a list of references in the order they are taught, and it
/// is the thing a teacher most wants to rearrange, so it needs a real editor
/// rather than a text box. What makes that awkward is what the migration left
/// behind, and it is worth being precise about because it shaped this file:
///
///     structure:
///       - unit: faq/general/cal00-1tutorias
///       # - unit: faq/general/cal00-1tutorias-virtuales
///       - unit: faq/general/cal01-ver-calificaciones
///
/// Nine hundred entries across the repository are commented out like that
/// one. They are not junk: each is material that exists and is deliberately
/// not being taught this year, and switching one back on is a normal edit --
/// arguably the most common one after a migration. An editor that parsed this
/// block would silently delete all nine hundred on the first reorder.
///
/// So a commented-out entry is a first-class thing here: it round-trips, it
/// can be reordered, and it can be switched on and off. Free comment lines --
/// the `# nota:` and `# Migrated from` that explain a document -- travel with
/// the entry they sit above.
library;

/// What an entry refers to. `section` and `subsection` are headings inside
/// the composition rather than references, which is why they carry text
/// instead of a path.
enum EntryKind { unit, problem, section, subsection }

String entryKeyword(EntryKind kind) => switch (kind) {
  EntryKind.unit => 'unit',
  EntryKind.problem => 'problem',
  EntryKind.section => 'section',
  EntryKind.subsection => 'subsection',
};

EntryKind? entryKindOf(String keyword) => switch (keyword) {
  'unit' => EntryKind.unit,
  'problem' => EntryKind.problem,
  'section' => EntryKind.section,
  'subsection' => EntryKind.subsection,
  _ => null,
};

/// One entry of a composition.
///
/// Usually one line. A heading may instead carry a title per language, which
/// in the repository looks like this:
///
///     - section:
///         es: "?`Qué es la matemática?"
///         # TODO: va
///         # TODO: en
///
/// Those inner lines are kept verbatim in [titleLines] and written back as
/// they were, for the same reason as everywhere else here: the `# TODO: va`
/// is somebody's note that this heading still needs translating, and an
/// editor that reserialised the mapping would delete it.
class StructureEntry {
  const StructureEntry({
    required this.kind,
    required this.value,
    this.enabled = true,
    this.notes = const [],
    this.trailingComment = '',
    this.titleLines = const [],
  });

  final EntryKind kind;

  /// The path, or the heading's text when it has a single one. Empty when the
  /// title is localised -- see [titleLines].
  final String value;

  /// The inner lines of a localised title, without their indentation.
  final List<String> titleLines;

  /// False when the line is commented out: material that exists and is not
  /// being taught. Kept, not dropped.
  final bool enabled;

  /// Comment lines that sat above this entry, verbatim, without their
  /// indentation. They move with it.
  final List<String> notes;

  /// A comment on the entry's own line, `- unit: x  # ojo`.
  final String trailingComment;

  bool get isReference => kind == EntryKind.unit || kind == EntryKind.problem;

  /// Whether the title is written per language rather than as one string.
  bool get isLocalised => titleLines.isNotEmpty;

  /// The languages a localised title has, and their text.
  Map<String, String> get titles {
    final found = <String, String>{};
    for (final line in titleLines) {
      if (line.trimLeft().startsWith('#')) continue;
      final match = _titleLine.firstMatch(line);
      if (match == null) continue;
      final (value, _) = CompositionFile._splitComment(match.group(2)!);
      found[match.group(1)!] = CompositionFile._unquote(value.trim());
    }
    return found;
  }

  /// What to show for this entry, in [language], falling back to any title
  /// it does have -- a heading with only a Spanish title still has a name.
  String label(String language) {
    if (!isLocalised) return value;
    final found = titles;
    final wanted = found[language];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final other in found.values) {
      if (other.isNotEmpty) return other;
    }
    return '';
  }

  /// The same entry with one language of its title changed.
  ///
  /// Surgical, like everything else: the line for that language is rewritten
  /// or added and the rest of the block -- the TODO markers for the languages
  /// still missing -- is left alone.
  StructureEntry withTitle(String language, String text) {
    if (!isLocalised) {
      // A single-string heading gains a localised title only when asked to
      // hold a second language; until then it stays as it is.
      return copyWith(value: text);
    }
    final lines = [...titleLines];
    final at = lines.indexWhere((line) {
      final match = _titleLine.firstMatch(line);
      return match != null && match.group(1) == language;
    });
    final written = '$language: ${CompositionFile._quote(text)}';
    if (at >= 0) {
      lines[at] = written;
    } else {
      // Above the TODO markers, so the block stays ordered by language the
      // way the migrator wrote it.
      final todo = lines.indexWhere((line) => line.contains('TODO: $language'));
      if (todo >= 0) {
        lines[todo] = written;
      } else {
        lines.add(written);
      }
    }
    return copyWith(titleLines: lines);
  }

  StructureEntry copyWith({
    EntryKind? kind,
    String? value,
    bool? enabled,
    List<String>? notes,
    String? trailingComment,
    List<String>? titleLines,
  }) => StructureEntry(
    kind: kind ?? this.kind,
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
    notes: notes ?? this.notes,
    trailingComment: trailingComment ?? this.trailingComment,
    titleLines: titleLines ?? this.titleLines,
  );

  @override
  String toString() => isLocalised
      ? '${enabled ? '' : '# '}- ${entryKeyword(kind)}: ${label('es')}'
      : '${enabled ? '' : '# '}- ${entryKeyword(kind)}: $value';

  static final RegExp _titleLine = RegExp(r'^([a-z]{2}):(.*)$');
}

/// Why a composition could not be read or rewritten.
class CompositionException implements Exception {
  const CompositionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One document's composition, and where it lives in the file.
class StructureBlock {
  const StructureBlock({
    required this.documentId,
    required this.entries,
    required this.firstLine,
    required this.lastLine,
    required this.indent,
    required this.titleIndent,
    required this.trailing,
  });

  final String documentId;
  final List<StructureEntry> entries;

  /// The `structure:` line itself, and the last line belonging to the block.
  final int firstLine;
  final int lastLine;

  /// The indentation entries are written at.
  final int indent;

  /// The indentation the inner lines of a localised title are written at.
  final int titleIndent;

  /// Comment lines after the last entry, which belong to the block rather
  /// than to any one entry.
  final List<String> trailing;
}

class CompositionFile {
  CompositionFile(String text) : _lines = text.split('\n');

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// The document ids, in the order the file lists them.
  List<String> documentIds() => [
    for (final document in _documents()) document.id,
  ];

  /// The composition of one document, or null when there is no such document.
  ///
  /// Returns null rather than throwing for a missing document, and throws
  /// only for a shape it cannot rewrite safely -- the caller can offer the
  /// raw editor for the second and not the first.
  StructureBlock? blockFor(String documentId) {
    final document = _documents().where((d) => d.id == documentId).firstOrNull;
    if (document == null) return null;

    final structure = _structureLineIn(document);
    if (structure == null) {
      // A document with no `structure:` at all: an empty composition that can
      // be given one.
      return StructureBlock(
        documentId: documentId,
        entries: const [],
        firstLine: document.lastLine,
        lastLine: document.lastLine,
        indent: document.fieldIndent + 2,
        titleIndent: document.fieldIndent + 6,
        trailing: const [],
      );
    }

    final inline = _valueAfterColon(_lines[structure]);
    if (inline.isNotEmpty && inline != '[]') {
      throw CompositionException(
        'la composición de `$documentId` está escrita en línea '
        '($inline), y este editor solo reescribe la forma en bloque',
      );
    }

    var last = structure;
    var indent = 0;
    final entries = <StructureEntry>[];
    final innerIndents = <int, int>{};
    var notes = <String>[];

    for (var i = structure + 1; i <= document.lastLine; i += 1) {
      final line = _lines[i];
      if (line.trim().isEmpty) continue;
      final lineIndent = _indentOf(line);
      final trimmed = line.trimLeft();

      if (!trimmed.startsWith('#') &&
          lineIndent <= _indentOf(_lines[structure])) {
        break;
      }

      final disabled = _disabledEntry.firstMatch(trimmed);
      final active = _activeEntry.firstMatch(trimmed);
      final match = active ?? disabled;

      if (match != null) {
        final kind = entryKindOf(match.group(1)!);
        if (kind == null) {
          notes.add(trimmed);
          last = i;
          continue;
        }
        if (active != null) indent = lineIndent;
        final (value, comment) = _splitComment(match.group(2)!);

        // An empty value means the title is written per language on the
        // lines below, at a deeper indentation.
        final titleLines = <String>[];
        if (value.trim().isEmpty) {
          int? innerIndent;
          var j = i + 1;
          for (; j <= document.lastLine && j < _lines.length; j += 1) {
            final inner = _lines[j];
            if (inner.trim().isEmpty) break;
            final at = _indentOf(inner);
            if (at <= lineIndent) break;
            innerIndent ??= at;
            var body = inner.substring(innerIndent.clamp(0, at));
            // A disabled entry's title lines carry the same `# ` marker as
            // its own line. It is stripped here and re-added when writing,
            // so the model holds one title either way -- and so switching an
            // entry off twice does not bury it under two layers of comment.
            if (active == null) {
              body = body.startsWith('# ')
                  ? body.substring(2)
                  : (body.startsWith('#') ? body.substring(1) : body);
            }
            titleLines.add(body);
          }
          if (titleLines.isNotEmpty) {
            innerIndents[entries.length] = innerIndent!;
            i = j - 1;
          }
        }

        entries.add(
          StructureEntry(
            kind: kind,
            value: _unquote(value.trim()),
            enabled: active != null,
            notes: notes,
            trailingComment: comment,
            titleLines: titleLines,
          ),
        );
        notes = <String>[];
        last = titleLines.isEmpty ? i : i;
        continue;
      }

      if (trimmed.startsWith('#')) {
        // A comment that is not an entry: an explanation. It belongs above
        // whatever comes next.
        notes.add(trimmed);
        last = i;
        continue;
      }

      throw CompositionException(
        'no se entiende la línea ${i + 1} de la composición de '
        '`$documentId`: $trimmed',
      );
    }

    final entryIndent = indent == 0 ? _indentOf(_lines[structure]) + 2 : indent;
    return StructureBlock(
      documentId: documentId,
      entries: entries,
      firstLine: structure,
      lastLine: last,
      indent: entryIndent,
      // The repository writes a localised title four spaces in from its
      // entry; taken from the file rather than assumed, so a hand-written
      // one keeps its own shape.
      titleIndent: innerIndents.values.firstOrNull ?? entryIndent + 4,
      // Whatever was collected after the last entry had nothing to attach to.
      trailing: notes,
    );
  }

  /// Replaces one document's composition, leaving the rest of the file alone.
  void setStructure(String documentId, List<StructureEntry> entries) {
    final block = blockFor(documentId);
    if (block == null) {
      throw CompositionException('no existe el documento `$documentId`');
    }

    final pad = ' ' * block.indent;
    final written = <String>[];
    for (final entry in entries) {
      for (final note in entry.notes) {
        written.add('$pad$note');
      }
      final comment = entry.trailingComment.isEmpty
          ? ''
          : '  ${entry.trailingComment}';
      final marker = entry.enabled ? '' : '# ';
      if (entry.isLocalised) {
        written.add('$pad$marker- ${entryKeyword(entry.kind)}:$comment');
        final innerPad = ' ' * block.titleIndent;
        for (final line in entry.titleLines) {
          written.add('$innerPad$marker$line');
        }
        continue;
      }
      final body = '- ${entryKeyword(entry.kind)}: ${_quote(entry.value)}';
      written.add('$pad$marker$body$comment');
    }
    for (final note in block.trailing) {
      written.add('$pad$note');
    }

    // An empty composition keeps the key and says so, rather than leaving a
    // bare `structure:` that reads as null.
    final structureLine = _lines[block.firstLine];
    final head = structureLine.substring(0, structureLine.indexOf(':') + 1);
    if (written.isEmpty) {
      _lines.replaceRange(block.firstLine, block.lastLine + 1, ['$head []']);
      return;
    }
    _lines.replaceRange(block.firstLine, block.lastLine + 1, [
      head,
      ...written,
    ]);
  }

  // -- finding things ------------------------------------------------------

  List<_Document> _documents() {
    final start = _lines.indexWhere((line) => _keyAt(line, 0) == 'documents');
    if (start < 0) return const [];

    final documents = <_Document>[];
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

      // `- id: faq`: the id is on the item's own line in every file the
      // migrator wrote, and in the hand-written ones too.
      final match = _itemId.firstMatch(trimmed);
      if (match == null) continue;
      final (value, _) = _splitComment(match.group(1)!);
      documents.add(
        _Document(
          id: _unquote(value.trim()),
          firstLine: i,
          fieldIndent: indent + 2,
        ),
      );
    }

    // Each document runs until the next one starts, or the end of the block.
    for (var i = 0; i < documents.length; i += 1) {
      final next = i + 1 < documents.length
          ? documents[i + 1].firstLine - 1
          : _endOfDocuments(documents[i].firstLine) - 1;
      documents[i].lastLine = next;
    }
    return documents;
  }

  int _endOfDocuments(int from) {
    for (var i = from + 1; i < _lines.length; i += 1) {
      final line = _lines[i];
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (_indentOf(line) == 0) return i;
    }
    return _lines.length;
  }

  int? _structureLineIn(_Document document) {
    for (var i = document.firstLine; i <= document.lastLine; i += 1) {
      final line = _lines[i];
      if (line.trimLeft().startsWith('#')) continue;
      if (_keyAt(line, document.fieldIndent) == 'structure') return i;
    }
    return null;
  }

  static final RegExp _activeEntry = RegExp(
    r'^-\s+([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$',
  );
  static final RegExp _disabledEntry = RegExp(
    r'^#\s*-\s+([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$',
  );
  static final RegExp _itemId = RegExp(r'^-\s+id:\s*(.*)$');
  static final RegExp _key = RegExp(r'^(\s*)([A-Za-z_][A-Za-z0-9_.-]*):(.*)$');

  static String? _keyAt(String line, int indent) {
    final match = _key.firstMatch(line);
    if (match == null) return null;
    if (match.group(1)!.length != indent) return null;
    return match.group(2);
  }

  static String _valueAfterColon(String line) {
    final match = _key.firstMatch(line);
    if (match == null) return '';
    final (value, _) = _splitComment(match.group(3)!);
    return value.trim();
  }

  static int _indentOf(String line) {
    var count = 0;
    while (count < line.length && line[count] == ' ') {
      count += 1;
    }
    return count;
  }

  /// Splits a value from a trailing comment, respecting quotes.
  static (String, String) _splitComment(String rest) {
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
      if (char == '#' &&
          (i == 0 || rest[i - 1] == ' ' || rest[i - 1] == '\t')) {
        return (rest.substring(0, i), rest.substring(i).trim());
      }
    }
    return (rest, '');
  }

  static String _unquote(String value) {
    if (value.length >= 2 && value[0] == value[value.length - 1]) {
      if (value[0] == "'") {
        return value.substring(1, value.length - 1).replaceAll("''", "'");
      }
      if (value[0] == '"') {
        return value.substring(1, value.length - 1).replaceAll(r'\"', '"');
      }
    }
    return value;
  }

  /// Quotes a value only when it needs it. A unit path never does; a section
  /// heading with a colon in it does.
  static String _quote(String value) {
    if (value.isEmpty) return "''";
    final needs =
        value != value.trim() ||
        value.contains(': ') ||
        value.endsWith(':') ||
        value.contains(' #') ||
        '-?:,[]{}#&*!|>%@`"\''.contains(value[0]);
    if (!needs) return value;
    return "'${value.replaceAll("'", "''")}'";
  }
}

class _Document {
  _Document({
    required this.id,
    required this.firstLine,
    required this.fieldIndent,
  });

  final String id;
  final int firstLine;
  final int fieldIndent;
  int lastLine = 0;
}
