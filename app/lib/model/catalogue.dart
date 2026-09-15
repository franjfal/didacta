/// The content catalogue, as the generated index describes it.
///
/// Plain Dart with no Flutter imports, on purpose. The spec asks for web
/// first and desktop later "without rewriting the logic", and the only way
/// that holds is if the part worth reusing -- parsing, filtering, counting --
/// never touches a widget. It is also what makes it testable without a
/// rendering surface.
///
/// Everything here mirrors `engine/didacta/index.py`. That module is the
/// authority on the shape; this one only reads it, and refuses to read a
/// schema version it was not written for rather than misinterpret it.
library;

/// The index schema this code understands. The generator writes the same
/// number; a mismatch is reported rather than guessed at, because a field that
/// silently changed meaning is worse than a file that fails to load.
const int supportedSchemaVersion = 1;

/// Raised when an index cannot be read as this version expects.
class CatalogueFormatException implements Exception {
  const CatalogueFormatException(this.message);

  final String message;

  @override
  String toString() => 'CatalogueFormatException: $message';
}

/// The state of one language of one unit.
///
/// `missing` and `outdated` are computed by the engine and never declared, so
/// they arrive already resolved -- an interface must not try to work them out
/// again.
enum TranslationStatus {
  source,
  reviewed,
  translated,
  draft,
  outdated,
  missing;

  static TranslationStatus parse(String? value) {
    switch (value) {
      case 'source':
        return TranslationStatus.source;
      case 'reviewed':
        return TranslationStatus.reviewed;
      case 'translated':
        return TranslationStatus.translated;
      case 'draft':
        return TranslationStatus.draft;
      case 'outdated':
        return TranslationStatus.outdated;
      default:
        return TranslationStatus.missing;
    }
  }

  /// Whether this language exists at all, which is the first thing a reader
  /// wants to know and the only state that is not a matter of degree.
  bool get exists => this != TranslationStatus.missing;

  /// Whether it needs work. `outdated` counts: the original has moved on.
  bool get needsWork =>
      this == TranslationStatus.missing ||
      this == TranslationStatus.outdated ||
      this == TranslationStatus.draft;
}

/// Where a unit is used: one document in one year of one course.
class UnitUsage {
  const UnitUsage({
    required this.course,
    required this.year,
    required this.document,
  });

  factory UnitUsage.fromJson(Map<String, dynamic> json) => UnitUsage(
    course: json['course'] as String? ?? '',
    year: json['year'] as String? ?? '',
    document: json['document'] as String? ?? '',
  );

  final String course;
  final String year;
  final String document;

  @override
  String toString() => '$course/$year/$document';
}

/// One reusable piece of content.
class Unit {
  const Unit({
    required this.id,
    required this.path,
    this.repo = '',
    required this.area,
    required this.block,
    required this.kind,
    required this.category,
    required this.topic,
    required this.tags,
    required this.titles,
    required this.reference,
    required this.statuses,
    required this.prerequisites,
    required this.objectives,
    required this.usedBy,
    required this.warnings,
    this.durationMinutes,
    this.difficulty,
  });

  factory Unit.fromJson(Map<String, dynamic> json, {String repo = ''}) {
    final languages = (json['languages'] as Map?) ?? const {};
    return Unit(
      repo: repo,
      id: json['id'] as String? ?? '',
      path: json['path'] as String? ?? '',
      area: json['area'] as String? ?? 'content',
      // Un índice de antes de que el bloque existiera lo decidía con el
      // árbol, que es lo que hacía entonces: así un catálogo viejo se sigue
      // leyendo y no aparece todo como teoría.
      block:
          json['block'] as String? ??
          (json['area'] == 'problems' ? 'problems' : 'theory'),
      kind: json['kind'] as String? ?? 'theory',
      category: json['category'] as String? ?? '',
      topic: json['topic'] as String? ?? '',
      tags: _stringList(json['tags']),
      titles: _stringMap(json['title']),
      reference: json['reference'] as String? ?? 'es',
      statuses: {
        for (final entry in languages.entries)
          entry.key as String: TranslationStatus.parse(
            (entry.value as Map?)?['status'] as String?,
          ),
      },
      prerequisites: _stringList(json['prerequisites']),
      objectives: _stringList(json['objectives']),
      usedBy: [
        for (final item in (json['usedBy'] as List?) ?? const [])
          UnitUsage.fromJson((item as Map).cast<String, dynamic>()),
      ],
      warnings: _stringList(json['warnings']),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      difficulty: json['difficulty'] as String?,
    );
  }

  final String id;

  /// De qué repositorio salió.
  ///
  /// Un mismo usuario puede trabajar en varios a la vez, y la ruta sola no
  /// identifica nada: dos repositorios pueden tener
  /// `content/analysis/normed/definition` y son unidades distintas. Vacío
  /// cuando se lee un índice suelto, que es como está escrito cualquier test
  /// que no trate de esto.
  final String repo;

  final String path;

  /// El árbol donde vive el fichero. Almacenamiento, no significado: qué
  /// parte de la asignatura es una unidad lo dice [block]. Se conserva porque
  /// la referencia que escribe una composición es la ruta sin él.
  final String area;

  /// `theory` o `problems`: de qué parte de la asignatura forma parte.
  ///
  /// Distinto de [kind], y confundirlos es el error que esto deshizo: el kind
  /// dice qué **es** el fichero --una explicación, un ejemplo, un ejercicio--
  /// y el bloque de qué parte de la asignatura forma parte. Una explicación
  /// teórica dentro de una práctica de problemas es `kind: theory` y
  /// `block: problems`, y las dos cosas son ciertas.
  final String block;

  final String kind;
  final String category;
  final String topic;
  final List<String> tags;
  final Map<String, String> titles;

  /// The language the others are translations of.
  final String reference;

  final Map<String, TranslationStatus> statuses;
  final List<String> prerequisites;
  final List<String> objectives;
  final List<UnitUsage> usedBy;
  final List<String> warnings;
  final int? durationMinutes;
  final String? difficulty;

  /// The reference used by a composition: the path without its area.
  ///
  /// `content/analysis/normed-spaces/definition` is written
  /// `analysis/normed-spaces/definition` in a `year.yaml`, because the LaTeX
  /// side appends the tree itself.
  String get reference_ =>
      path.contains('/') ? path.substring(path.indexOf('/') + 1) : path;

  bool get isProblem => block == 'problems';

  /// Si se edita por campos: enunciado, resultado y solución.
  ///
  /// Lo decide **qué es** la unidad, no dónde vive. Una explicación teórica o
  /// un ejemplo dentro de una práctica de problemas son `kind: theory` y
  /// `kind: example` con `block: problems`, y las dos cosas son ciertas: van
  /// con la hoja, y no tienen resultado ni solución que rellenar. Ofrecerles
  /// tres campos es inventarles una estructura que no tienen.
  bool get editsAsProblem => kind == 'problem';

  /// The title in [language], falling back the way the engine does: the
  /// requested language, then the reference, then anything, then the id.
  ///
  /// A unit with no title at all is a real case in migrated material, and
  /// showing its id beats showing an empty row.
  String title(String language) {
    final wanted = titles[language];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    final fallback = titles[reference];
    if (fallback != null && fallback.isNotEmpty) return fallback;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return id;
  }

  /// True when the title shown is not in the language asked for -- worth
  /// marking in the interface, because otherwise a Castilian title in a
  /// Valencian listing looks like the translation exists.
  bool titleIsFallback(String language) {
    final wanted = titles[language];
    return wanted == null || wanted.isEmpty;
  }

  TranslationStatus statusIn(String language) =>
      statuses[language] ?? TranslationStatus.missing;

  /// Text a search box should match against: everything a person might type.
  String get searchable => [
    path,
    id,
    ...titles.values,
    ...tags,
    kind,
    category,
    topic,
  ].join(' ').toLowerCase();
}

/// One compilable document inside a course year.
/// Un trozo de la composición de un documento: un apartado o una referencia.
class CompositionPart {
  const CompositionPart({
    required this.kind,
    this.reference = '',
    this.titles = const {},
  });

  /// `section`, `subsection`, `unit` o `problem`.
  final String kind;

  /// Lo que referencia, si referencia algo.
  final String reference;

  /// El título por idiomas, si es un apartado.
  final Map<String, String> titles;

  bool get isHeading => kind == 'section' || kind == 'subsection';

  String title(String language) {
    final wanted = titles[language];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Si el título que se enseña no es el del idioma pedido.
  bool titleIsFallback(String language) =>
      titles.isNotEmpty && (titles[language] ?? '').isEmpty;
}

class Document {
  const Document({
    required this.id,
    required this.kind,
    this.repo = '',
    required this.language,
    required this.titles,
    required this.profiles,
    required this.unitRefs,
    this.structure = const [],
  });

  factory Document.fromJson(Map<String, dynamic> json, {String repo = ''}) =>
      Document(
        repo: repo,
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? 'theory',
        language: json['language'] as String? ?? 'es',
        titles: _stringMap(json['title']),
        profiles: _stringList(json['profiles']),
        unitRefs: _stringList(json['unitRefs']),
        structure: _structure(json['structure']),
      );

  /// La estructura tal como la escribe el motor: una lista de mapas de una
  /// sola clave, `{section: {es: ...}}` o `{unit: ruta}`.
  ///
  /// Vacía en un índice viejo, y entonces la pantalla enseña la lista plana,
  /// que es lo que hacía antes.
  static List<CompositionPart> _structure(Object? raw) {
    if (raw is! List) return const [];
    final parts = <CompositionPart>[];
    for (final item in raw) {
      if (item is! Map || item.isEmpty) continue;
      final kind = item.keys.first.toString();
      final value = item.values.first;
      parts.add(
        CompositionPart(
          kind: kind,
          reference: value is String ? value : '',
          titles: value is Map ? _stringMap(value) : const {},
        ),
      );
    }
    return parts;
  }

  final String id;

  /// El repositorio del que sale. Una asignatura puede tener temas en varios,
  /// y cada documento vive entero en el suyo: se compila contra su raíz y
  /// referencia unidades suyas.
  final String repo;

  final String kind;
  final String language;
  final Map<String, String> titles;

  /// Empty means "every profile that suits this kind", which the engine
  /// decides. The interface must not invent a list of its own.
  final List<String> profiles;

  final List<String> unitRefs;

  /// Cómo está repartido: los apartados y lo que va debajo de cada uno.
  final List<CompositionPart> structure;

  String title([String? language]) {
    final wanted = titles[language ?? this.language];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return id;
  }
}

/// One academic year of a course.
class CourseYear {
  const CourseYear({
    required this.year,
    required this.language,
    required this.documents,
    this.group,
  });

  factory CourseYear.fromJson(Map<String, dynamic> json, {String repo = ''}) =>
      CourseYear(
        year: json['year'] as String? ?? '',
        language: json['language'] as String? ?? 'es',
        group: json['group'] is String ? json['group'] as String : null,
        documents: [
          for (final item in (json['documents'] as List?) ?? const [])
            Document.fromJson(
              (item as Map).cast<String, dynamic>(),
              repo: repo,
            ),
        ],
      );

  /// El mismo año visto en dos repositorios: los documentos se juntan.
  ///
  /// Cada documento sigue siendo de su repositorio; lo que se mezcla es la
  /// lista. Un id repetido en los dos se queda con el primero y se cuenta
  /// como conflicto, porque son dos documentos distintos que dicen ser el
  /// mismo y elegir en silencio es esconder el problema.
  CourseYear mergedWith(CourseYear other, List<String> conflicts) {
    final known = {for (final document in documents) document.id};
    final added = <Document>[];
    for (final document in other.documents) {
      if (known.contains(document.id)) {
        conflicts.add('${document.id} está en dos repositorios');
        continue;
      }
      added.add(document);
    }
    return CourseYear(
      year: year,
      language: language,
      group: group ?? other.group,
      documents: [...documents, ...added],
    );
  }

  final String year;
  final String language;
  final String? group;

  /// In composition order, which is content: the order units are taught in.
  final List<Document> documents;

  /// Los repositorios que aportan algo a este año.
  Set<String> get repos => {for (final document in documents) document.repo};
}

/// A subject, across the years it has run.
class Course {
  const Course({
    required this.id,
    required this.titles,
    required this.language,
    required this.years,
    this.code,
    this.teacher,
    this.institution,
  });

  factory Course.fromJson(Map<String, dynamic> json, {String repo = ''}) {
    final years = (json['years'] as Map?) ?? const {};
    return Course(
      id: json['id'] as String? ?? '',
      titles: _stringMap(json['title']),
      language: json['language'] as String? ?? 'es',
      code: json['code'] as String?,
      teacher: json['teacher'] as String?,
      institution: json['institution'] as String?,
      years: {
        for (final entry in years.entries)
          entry.key as String: CourseYear.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
            repo: repo,
          ),
      },
    );
  }

  /// La misma asignatura descrita en dos repositorios.
  ///
  /// Los años se juntan y, dentro de cada año, los documentos. Lo que es un
  /// dato suelto --el título, el código, quién la da-- se queda con el primero
  /// que lo tenga: son la misma asignatura, y dos `course.yaml` que no
  /// coincidan es algo que hay que arreglar en el repositorio, no aquí.
  Course mergedWith(Course other, List<String> conflicts) {
    final merged = <String, CourseYear>{...years};
    for (final entry in other.years.entries) {
      final mine = merged[entry.key];
      merged[entry.key] = mine == null
          ? entry.value
          : mine.mergedWith(entry.value, conflicts);
    }
    return Course(
      id: id,
      titles: {...other.titles, ...titles},
      language: language,
      code: code ?? other.code,
      teacher: teacher ?? other.teacher,
      institution: institution ?? other.institution,
      years: merged,
    );
  }

  final String id;
  final Map<String, String> titles;
  final String language;
  final String? code;
  final String? teacher;
  final String? institution;
  final Map<String, CourseYear> years;

  String title([String? language]) {
    final wanted = titles[language ?? this.language];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return id;
  }

  /// Newest first: the year being taught is the one you want on top.
  List<String> get sortedYears =>
      years.keys.toList()..sort((a, b) => b.compareTo(a));

  /// Los repositorios que aportan algo a esta asignatura.
  Set<String> get repos => {for (final year in years.values) ...year.repos};
}

/// An output profile, so the interface can offer what exists rather than a
/// hardcoded list that drifts from `didacta-profiles.tex`.
class OutputProfile {
  const OutputProfile({
    required this.id,
    required this.family,
    required this.documentClass,
    this.label = '',
  });

  factory OutputProfile.fromJson(Map<String, dynamic> json) => OutputProfile(
    id: json['id'] as String? ?? '',
    family: json['family'] as String? ?? '',
    documentClass: json['documentClass'] as String? ?? '',
    label: json['label'] as String? ?? '',
  );

  final String id;
  final String family;
  final String documentClass;

  /// El nombre que se lee: «Diapositivas (sin pausas)», no `slides-flat`.
  ///
  /// Lo deriva el motor de los ejes del perfil y viaja en el índice. Vacío
  /// en un índice viejo, y entonces se enseña el id, que es feo pero cierto.
  final String label;

  String get name => label.isEmpty ? id : label;

  bool get isSlides => documentClass == 'beamer';
}

/// The whole catalogue: what one load gives an interface.
class Catalogue {
  const Catalogue({
    required this.name,
    required this.languages,
    required this.defaultLanguage,
    required this.contentHash,
    required this.units,
    required this.courses,
    required this.profiles,
    required this.errors,
  });

  /// Builds from the three index files.
  ///
  /// Throws [CatalogueFormatException] on a schema version this code does not
  /// know. Refusing beats rendering a field that changed meaning.
  factory Catalogue.fromIndex({
    required Map<String, dynamic> manifest,
    required Map<String, dynamic> units,
    required Map<String, dynamic> courses,
    String repo = '',
  }) {
    for (final entry in {
      'manifest': manifest,
      'units': units,
      'courses': courses,
    }.entries) {
      final version = (entry.value['schemaVersion'] as num?)?.toInt();
      if (version == null) {
        throw CatalogueFormatException(
          '${entry.key}.json has no schemaVersion',
        );
      }
      if (version != supportedSchemaVersion) {
        throw CatalogueFormatException(
          '${entry.key}.json is schema $version; this app reads '
          '$supportedSchemaVersion. Regenerate with `didacta index`, or '
          'update the app.',
        );
      }
    }

    return Catalogue(
      name: manifest['name'] as String? ?? 'Didacta',
      languages: _stringList(manifest['languages']),
      defaultLanguage: manifest['defaultLanguage'] as String? ?? 'es',
      contentHash: manifest['contentHash'] as String? ?? '',
      units: [
        for (final item in (units['units'] as List?) ?? const [])
          Unit.fromJson((item as Map).cast<String, dynamic>(), repo: repo),
      ],
      courses: [
        for (final item in (courses['courses'] as List?) ?? const [])
          Course.fromJson((item as Map).cast<String, dynamic>(), repo: repo),
      ],
      profiles: [
        for (final item in (manifest['profiles'] as List?) ?? const [])
          OutputProfile.fromJson((item as Map).cast<String, dynamic>()),
      ],
      errors: _stringList(manifest['errors']),
    );
  }

  final String name;
  final List<String> languages;
  final String defaultLanguage;

  /// Identifies the content this catalogue describes, so a stale tab can be
  /// told apart from a current one without comparing every record.
  final String contentHash;

  final List<Unit> units;
  final List<Course> courses;
  final List<OutputProfile> profiles;

  /// What the engine complained about while reading the repository. Surfaced
  /// rather than swallowed: an interface built on a repository that does not
  /// load cleanly should say so.
  final List<String> errors;

  List<String> get categories =>
      units.map((unit) => unit.category).toSet().toList()..sort();

  List<String> get kinds =>
      units.map((unit) => unit.kind).toSet().toList()..sort();

  List<String> get tags {
    final all = <String>{};
    for (final unit in units) {
      all.addAll(unit.tags);
    }
    return all.toList()..sort();
  }

  /// Los repositorios que hay cargados, en el orden en que se leyeron.
  List<String> get repos {
    final found = <String>[];
    for (final unit in units) {
      if (unit.repo.isNotEmpty && !found.contains(unit.repo)) {
        found.add(unit.repo);
      }
    }
    for (final course in courses) {
      for (final repo in course.repos) {
        if (repo.isNotEmpty && !found.contains(repo)) found.add(repo);
      }
    }
    return found;
  }

  /// Varios repositorios vistos como una sola biblioteca.
  ///
  /// Lo que se mezcla es la asignatura: los años y los documentos de cada uno
  /// se juntan, y cada documento sigue siendo de su repositorio --se compila
  /// contra su raíz y referencia unidades suyas--. Las unidades no se mezclan
  /// nunca: dos repositorios pueden tener la misma ruta y son cosas distintas.
  static Catalogue merge(List<Catalogue> parts) {
    if (parts.isEmpty) {
      return const Catalogue(
        name: 'Didacta',
        languages: ['es'],
        defaultLanguage: 'es',
        contentHash: '',
        units: [],
        courses: [],
        profiles: [],
        errors: [],
      );
    }
    if (parts.length == 1) return parts.single;

    final courses = <String, Course>{};
    final conflicts = <String>[];
    for (final part in parts) {
      for (final course in part.courses) {
        final mine = courses[course.id];
        courses[course.id] = mine == null
            ? course
            : mine.mergedWith(course, conflicts);
      }
    }

    final languages = <String>[];
    for (final part in parts) {
      for (final code in part.languages) {
        if (!languages.contains(code)) languages.add(code);
      }
    }

    return Catalogue(
      name: parts.first.name,
      languages: languages,
      defaultLanguage: parts.first.defaultLanguage,
      // Uno por repositorio, juntos: sirve para lo de siempre --saber si esto
      // sigue describiendo lo que hay en disco-- y cambia si cambia
      // cualquiera.
      contentHash: [for (final part in parts) part.contentHash].join('+'),
      units: [for (final part in parts) ...part.units],
      courses: courses.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      profiles: parts.first.profiles,
      errors: [for (final part in parts) ...part.errors, ...conflicts],
    );
  }

  /// La unidad en esa ruta. Con varios repositorios hay que decir en cuál:
  /// la misma ruta puede existir en dos y son unidades distintas.
  Unit? unitByPath(String path, {String? repo}) {
    for (final unit in units) {
      if (unit.path != path) continue;
      if (repo != null && repo.isNotEmpty && unit.repo != repo) continue;
      return unit;
    }
    return null;
  }

  /// Units a composition reference resolves to, matching the engine's rule:
  /// the reference is a path without its area, so try both trees.
  Unit? unitByReference(String reference, {String? repo}) {
    final trimmed = reference.replaceAll(RegExp(r'^/+|/+$'), '');
    for (final area in const ['content', 'problems']) {
      final found = unitByPath('$area/$trimmed', repo: repo);
      if (found != null) return found;
    }
    return unitByPath(trimmed, repo: repo);
  }
}

List<String> _stringList(Object? value) => [
  for (final item in (value as List?) ?? const []) item.toString(),
];

Map<String, String> _stringMap(Object? value) => {
  for (final entry in ((value as Map?) ?? const {}).entries)
    entry.key.toString(): entry.value?.toString() ?? '',
};
