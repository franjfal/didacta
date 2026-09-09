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
    required this.area,
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

  factory Unit.fromJson(Map<String, dynamic> json) {
    final languages = (json['languages'] as Map?) ?? const {};
    return Unit(
      id: json['id'] as String? ?? '',
      path: json['path'] as String? ?? '',
      area: json['area'] as String? ?? 'content',
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
  final String path;

  /// `content` or `problems`. Kept because it decides which macro a
  /// composition uses, and a reader should not have to parse the path.
  final String area;

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

  bool get isProblem => area == 'problems';

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
class Document {
  const Document({
    required this.id,
    required this.kind,
    required this.language,
    required this.titles,
    required this.profiles,
    required this.unitRefs,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
    id: json['id'] as String? ?? '',
    kind: json['kind'] as String? ?? 'theory',
    language: json['language'] as String? ?? 'es',
    titles: _stringMap(json['title']),
    profiles: _stringList(json['profiles']),
    unitRefs: _stringList(json['unitRefs']),
  );

  final String id;
  final String kind;
  final String language;
  final Map<String, String> titles;

  /// Empty means "every profile that suits this kind", which the engine
  /// decides. The interface must not invent a list of its own.
  final List<String> profiles;

  final List<String> unitRefs;

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

  factory CourseYear.fromJson(Map<String, dynamic> json) => CourseYear(
    year: json['year'] as String? ?? '',
    language: json['language'] as String? ?? 'es',
    group: json['group'] is String ? json['group'] as String : null,
    documents: [
      for (final item in (json['documents'] as List?) ?? const [])
        Document.fromJson((item as Map).cast<String, dynamic>()),
    ],
  );

  final String year;
  final String language;
  final String? group;

  /// In composition order, which is content: the order units are taught in.
  final List<Document> documents;
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

  factory Course.fromJson(Map<String, dynamic> json) {
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
          ),
      },
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
}

/// An output profile, so the interface can offer what exists rather than a
/// hardcoded list that drifts from `didacta-profiles.tex`.
class OutputProfile {
  const OutputProfile({
    required this.id,
    required this.family,
    required this.documentClass,
  });

  factory OutputProfile.fromJson(Map<String, dynamic> json) => OutputProfile(
    id: json['id'] as String? ?? '',
    family: json['family'] as String? ?? '',
    documentClass: json['documentClass'] as String? ?? '',
  );

  final String id;
  final String family;
  final String documentClass;

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
          Unit.fromJson((item as Map).cast<String, dynamic>()),
      ],
      courses: [
        for (final item in (courses['courses'] as List?) ?? const [])
          Course.fromJson((item as Map).cast<String, dynamic>()),
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

  Unit? unitByPath(String path) {
    for (final unit in units) {
      if (unit.path == path) return unit;
    }
    return null;
  }

  /// Units a composition reference resolves to, matching the engine's rule:
  /// the reference is a path without its area, so try both trees.
  Unit? unitByReference(String reference) {
    final trimmed = reference.replaceAll(RegExp(r'^/+|/+$'), '');
    for (final area in const ['content', 'problems']) {
      final found = unitByPath('$area/$trimmed');
      if (found != null) return found;
    }
    return unitByPath(trimmed);
  }
}

List<String> _stringList(Object? value) => [
  for (final item in (value as List?) ?? const []) item.toString(),
];

Map<String, String> _stringMap(Object? value) => {
  for (final entry in ((value as Map?) ?? const {}).entries)
    entry.key.toString(): entry.value?.toString() ?? '',
};
