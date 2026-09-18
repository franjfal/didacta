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

/// Lo que el fichero sabe de un documento antes de que el índice lo recoja.
///
/// El catálogo se genera aparte, así que un documento recién creado existe en
/// `year.yaml` y todavía no en `generated/`. Esto es lo que permite enseñarlo
/// entero mientras tanto --con su tipo, su nombre y su tema-- en lugar de una
/// línea con el identificador.
class DocumentDraft {
  const DocumentDraft({
    required this.id,
    required this.kind,
    required this.titles,
    required this.themes,
    this.link = '',
  });

  final String id;
  final String kind;
  final Map<String, String> titles;
  final List<String> themes;

  /// El contenido al que apunta, cuando el tema está vinculado.
  ///
  /// Entonces el título, el tipo y la composición no están en este fichero:
  /// están en `shared/documents/<link>.yaml`, que es lo que hace que los
  /// cursos que lo dan den el mismo tema y no dos copias.
  final String link;

  bool get isLinked => link.isNotEmpty;

  String title(String language) {
    final wanted = titles[language];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return id;
  }
}

class CompositionFile {
  CompositionFile(String text) : _lines = text.split('\n');

  /// `es: Tema 1`, dentro de un `title:`.
  static final RegExp _draftTitle = RegExp(r'^([a-z]{2}):(.*)$');

  /// Un idioma pendiente: `# TODO: va`. Escrito por el migrador en dos mil
  /// unidades y por Didacta desde entonces, así que se reconoce para poder
  /// sustituirlo sin llevarse por delante los comentarios de al lado.
  static final RegExp _pendingTitle = RegExp(r'^#\s*TODO:\s*[a-z]{2}\s*$');

  final List<String> _lines;

  String get text => _lines.join('\n');

  /// The document ids, in the order the file lists them.
  List<String> documentIds() => [
    for (final document in _documents()) document.id,
  ];

  /// Lo que el fichero dice de cada documento, sin pasar por el índice.
  ///
  /// Existe para el rato que va desde crear un documento hasta que
  /// `didacta index` lo recoge. Durante ese rato el catálogo no sabe que
  /// existe, y sin esto la pantalla solo podía enseñar su id: ni de qué tipo
  /// es, ni cómo se llama, ni a qué tema pertenece -- justo lo que se acaba
  /// de escribir en el formulario.
  List<DocumentDraft> documentDrafts() => [
    for (final document in _documents())
      DocumentDraft(
        id: document.id,
        kind: _fieldOf(document, 'kind') ?? 'theory',
        titles: _titlesOf(document),
        themes: _listOf(document, 'themes'),
        link: _fieldOf(document, 'link') ?? '',
      ),
  ];

  /// Un campo de una línea del bloque de un documento.
  String? _fieldOf(_Document document, String key) {
    for (var i = document.firstLine; i <= document.lastLine; i += 1) {
      final line = _lines[i];
      if (_keyAt(line, document.fieldIndent) != key) continue;
      return _unquote(line.substring(line.indexOf(':') + 1).trim());
    }
    return null;
  }

  /// Un campo escrito como `[a, b]`.
  List<String> _listOf(_Document document, String key) {
    final raw = _fieldOf(document, key);
    if (raw == null || !raw.startsWith('[')) return const [];
    final inner = raw.substring(1, raw.length - (raw.endsWith(']') ? 1 : 0));
    return [
      for (final piece in inner.split(','))
        if (piece.trim().isNotEmpty) piece.trim(),
    ];
  }

  /// El título por idioma, que se escribe en las líneas de debajo de `title:`.
  Map<String, String> _titlesOf(_Document document) {
    final titles = <String, String>{};
    var inside = false;
    for (var i = document.firstLine; i <= document.lastLine; i += 1) {
      final line = _lines[i];
      if (_keyAt(line, document.fieldIndent) == 'title') {
        inside = true;
        continue;
      }
      if (!inside) continue;
      final match = _draftTitle.firstMatch(line.trim());
      if (match == null) {
        // Otra clave del documento: el título se acabó.
        if (_keyAt(line, document.fieldIndent) != null) break;
        continue;
      }
      titles[match.group(1)!] = _unquote(match.group(2)!.trim());
    }
    return titles;
  }

  /// Cambia el título de un documento, en todos los idiomas a la vez.
  ///
  /// Lo que no tenga título se escribe **comentado**, `# TODO: va`, y no como
  /// `va: ""`. La diferencia no es cosmética: una cadena vacía es un título de
  /// verdad y saldría en la lista de documentos y dentro del PDF compilado en
  /// valenciano. Comentado es lo que hace el repositorio en sus dos mil
  /// unidades, y es lo que la pantalla de traducción cuenta como pendiente.
  ///
  /// Se reescribe solo el bloque de `title:`; el resto del documento --sus
  /// perfiles, sus temas, su composición entera y los comentarios que lleve--
  /// se queda donde está, que es la regla de todo este fichero.
  void setDocumentTitles(String id, Map<String, String> titles) {
    final documents = _documents();
    final document = documents.where((d) => d.id == id).firstOrNull;
    if (document == null) {
      throw CompositionException('no existe el documento `$id`');
    }
    final kept = <String, String>{
      for (final entry in titles.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (kept.isEmpty) {
      throw const CompositionException(
        'un documento sin título en ningún idioma no se puede listar',
      );
    }
    final pending = [
      for (final entry in titles.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];

    final field = ' ' * document.fieldIndent;
    final block = <String>[
      '${field}title:',
      for (final entry in kept.entries)
        '$field  ${entry.key}: ${_quote(entry.value)}',
      for (final code in pending) '$field  # TODO: $code',
    ];

    // Dónde empieza y acaba lo que había. El final es la primera línea que
    // vuelve a ser una clave del documento: lo de en medio son los idiomas y
    // sus TODO, y se va entero.
    var start = -1;
    var end = -1;
    for (var i = document.firstLine; i <= document.lastLine; i += 1) {
      if (start < 0) {
        if (_keyAt(_lines[i], document.fieldIndent) == 'title') start = i;
        continue;
      }
      if (_keyAt(_lines[i], document.fieldIndent) != null) {
        end = i - 1;
        break;
      }
      final trimmed = _lines[i].trim();
      // Un comentario suelto que no es un `# TODO: xx` es de alguien: no se
      // toca, así que el bloque acaba antes de él.
      if (trimmed.startsWith('#') && !_pendingTitle.hasMatch(trimmed)) {
        end = i - 1;
        break;
      }
      if (trimmed.isEmpty) {
        end = i - 1;
        break;
      }
    }
    if (start < 0) {
      // Un documento sin `title:`. Pasa con los escritos a mano; se pone
      // detrás del `id`, que es donde va en todos los demás.
      _lines.insertAll(document.firstLine + 1, block);
      return;
    }
    if (end < start) end = document.lastLine;
    _lines.replaceRange(start, end + 1, block);
  }

  /// Con qué plantillas se compila un documento.
  ///
  /// Se escribe `templates:`, que es como se llama ahora. Si el documento
  /// traía el `profiles:` de antes se sustituye, porque los dos dicen lo
  /// mismo y dejar los dos sería dejar dos respuestas a la misma pregunta.
  ///
  /// Lista vacía quita la línea: el documento vuelve a compilarse con lo que
  /// digan los bloques de sus lecciones, que es el estado normal.
  void setDocumentTemplates(String id, List<String> templates) {
    final document = _documents().where((d) => d.id == id).firstOrNull;
    if (document == null) {
      throw CompositionException('no existe el documento `$id`');
    }
    final field = ' ' * document.fieldIndent;
    final written = templates.isEmpty
        ? <String>[]
        : ['${field}templates: [${templates.join(', ')}]'];

    // Las dos claves, en una sola pasada y de atrás adelante: quitar una
    // línea mueve las de abajo, y hacerlo al revés deja el índice de la
    // segunda apuntando a otra cosa.
    final found = <int>[];
    for (var i = document.firstLine; i <= document.lastLine; i += 1) {
      final key = _keyAt(_lines[i], document.fieldIndent);
      if (key == 'templates' || key == 'profiles') found.add(i);
    }
    if (found.isEmpty) {
      if (written.isEmpty) return;
      _lines.insertAll(document.firstLine + 1, written);
      return;
    }
    for (var i = found.length - 1; i >= 1; i -= 1) {
      _lines.removeAt(found[i]);
    }
    _lines.replaceRange(found.first, found.first + 1, written);
  }

  /// Reordena los documentos del año.
  ///
  /// Mueve **los bloques tal cual**, líneas incluidas: comentarios, TODO,
  /// títulos por idioma y la composición entera de cada uno. Es la misma
  /// regla que el resto de este fichero --reescribir líneas, nunca volver a
  /// serializar-- y aquí importa todavía más, porque un documento son veinte
  /// líneas y perder un comentario en cada movimiento vaciaría el fichero de
  /// lo que alguien escribió a mano.
  ///
  /// [ids] tiene que ser los mismos documentos que ya hay, sin añadir ni
  /// quitar: mover no es editar, y confundir las dos cosas es como se pierde
  /// un documento sin enterarse.
  void setDocumentOrder(List<String> ids) {
    final documents = _documents();
    if (documents.isEmpty) {
      throw const CompositionException('este año no tiene documentos');
    }
    final known = [for (final d in documents) d.id];
    if (ids.length != known.length || !ids.toSet().containsAll(known)) {
      throw CompositionException(
        'el orden nuevo no tiene los mismos documentos: $known contra $ids',
      );
    }

    final blocks = {
      for (final document in documents)
        document.id: _trimTrailingBlanks(
          _lines.sublist(document.firstLine, document.lastLine + 1),
        ),
    };

    // Lo que había entre el último documento y lo que siga (o el final del
    // fichero) se queda donde está: puede ser otra clave del año.
    final first = documents.first.firstLine;
    final last = documents.last.lastLine;
    final tail = _lines.sublist(last + 1);
    final trailingBlanks =
        _lines.sublist(first, last + 1).length -
        blocks.values.fold<int>(0, (sum, block) => sum + block.length) -
        (documents.length - 1);

    final written = <String>[];
    for (final (index, id) in ids.indexed) {
      if (index > 0) written.add('');
      written.addAll(blocks[id]!);
    }
    // Las líneas en blanco que había al final del bloque, de vuelta.
    for (var i = 0; i < trailingBlanks; i += 1) {
      written.add('');
    }

    _lines
      ..replaceRange(first, _lines.length, written)
      ..addAll(tail);
  }

  /// Añade un documento al final del año.
  ///
  /// Con la composición vacía: un documento nuevo es un sitio donde poner
  /// unidades, y elegirlas es el paso siguiente, en su propia pantalla.
  /// [pending] son los idiomas que **todavía no tienen título**, y se
  /// escriben como `# TODO: va`, no como `va: TODO`.
  ///
  /// La diferencia no es cosmética: un `va: TODO` es un título de verdad, y
  /// saldría en la lista de documentos y dentro del PDF compilado en
  /// valenciano. Comentado es lo que hace el repositorio en sus dos mil
  /// unidades, y es lo que la pantalla de traducción cuenta como pendiente.
  void addDocument({
    required String id,
    required String kind,
    required Map<String, String> title,
    List<String> pending = const [],
    List<String> profiles = const [],
    List<String> themes = const [],
  }) {
    final documents = _documents();
    if (documents.any((document) => document.id == id)) {
      throw CompositionException('ya hay un documento `$id`');
    }

    // La sangría del fichero, no una inventada: los ficheros del repositorio
    // usan dos espacios para el guion y cuatro para los campos, pero leerlo
    // del que hay es lo que hace que esto valga también para los escritos a
    // mano de otra manera.
    final itemIndent = documents.isEmpty
        ? 2
        : _indentOf(_lines[documents.first.firstLine]);
    final fieldIndent = documents.isEmpty ? 4 : documents.first.fieldIndent;
    final pad = ' ' * itemIndent;
    final field = ' ' * fieldIndent;

    final block = <String>[
      '$pad- id: ${_quote(id)}',
      '${field}kind: ${_quote(kind)}',
      '${field}title:',
      for (final entry in title.entries)
        '$field  ${entry.key}: ${_quote(entry.value)}',
      for (final code in pending) '$field  # TODO: $code',
      if (profiles.isNotEmpty) '${field}profiles: [${profiles.join(', ')}]',
      // A qué tema pertenece, si se crea dentro de uno. Una etiqueta y nada
      // más: quién es ese tema lo declara `themes.yaml`, que puede estar en
      // otro repositorio.
      if (themes.isNotEmpty) '${field}themes: [${themes.join(', ')}]',
      '${field}structure: []',
    ];

    if (documents.isEmpty) {
      final start = _lines.indexWhere((line) => _keyAt(line, 0) == 'documents');
      if (start < 0) {
        throw const CompositionException('el año no tiene clave `documents`');
      }
      // `documents: []` pasa a ser una lista con un elemento.
      final head = _lines[start];
      _lines[start] = head.substring(0, head.indexOf(':') + 1);
      _lines.insertAll(start + 1, block);
      return;
    }

    final last = documents.last.lastLine;
    final existing = _trimTrailingBlanks(_lines.sublist(0, last + 1)).length;
    _lines.insertAll(existing, ['', ...block]);
  }

  /// Quita un documento entero del año.
  void removeDocument(String id) {
    final documents = _documents();
    final document = documents.where((d) => d.id == id).firstOrNull;
    if (document == null) {
      throw CompositionException('no existe el documento `$id`');
    }
    _lines.removeRange(document.firstLine, document.lastLine + 1);
    // Si era el último, la línea en blanco que lo separaba del anterior
    // sobra: dos en blanco al final de un bloque no las escribe nadie.
    while (document.firstLine > 0 &&
        document.firstLine - 1 < _lines.length &&
        _lines[document.firstLine - 1].trim().isEmpty &&
        (document.firstLine >= _lines.length ||
            _lines.length == document.firstLine ||
            _lines[document.firstLine].trim().isEmpty)) {
      _lines.removeAt(document.firstLine - 1);
      break;
    }
  }

  static List<String> _trimTrailingBlanks(List<String> lines) {
    final copy = [...lines];
    while (copy.isNotEmpty && copy.last.trim().isEmpty) {
      copy.removeLast();
    }
    return copy;
  }

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
