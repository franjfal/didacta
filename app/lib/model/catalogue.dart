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

/// Un tema del curso: el bloque bajo el que se agrupan sus documentos.
///
/// El Tema 1 lleva su teoría, su práctica, su análisis bibliográfico y su
/// marco histórico, y esos ficheros pueden estar en repositorios distintos.
/// Por eso el tema se declara aparte del documento: **el documento dice a qué
/// temas pertenece y el tema lo declara quien lo tenga**.
///
/// De ahí lo que lo hace seguro: quien no tenga el repositorio donde alguien
/// escribió el título ve sus documentos sueltos, como antes de que existieran
/// los temas. Nunca desaparece material por no tener un repositorio.
class CourseTheme {
  const CourseTheme({required this.id, required this.titles, this.repo = ''});

  factory CourseTheme.fromJson(Map<String, dynamic> json, {String repo = ''}) =>
      CourseTheme(
        id: json['id'] as String? ?? '',
        titles: _stringMap(json['title']),
        repo: repo,
      );

  final String id;
  final Map<String, String> titles;

  /// Quién lo declara. Para poder decirlo en la interfaz cuando hay varios
  /// repositorios abiertos.
  final String repo;

  String title([String? language]) {
    final wanted = titles[language ?? 'es'];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return id;
  }
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
    this.themes = const [],
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
        themes: _stringList(json['themes']),
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

  /// Los temas del curso a los que pertenece, por id.
  ///
  /// Varios porque un documento puede entrar en más de un tema --un apéndice
  /// que sirve a dos--, y ids sueltos porque **quién es cada tema lo declara
  /// otro fichero, que puede estar en otro repositorio**. Un id que nadie
  /// declara no es un error: el documento sale suelto.
  final List<String> themes;

  String title([String? language]) {
    final wanted = titles[language ?? this.language];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return id;
  }
}

/// Un tema y lo que lleva dentro, o los sueltos cuando no hay tema.
///
/// `theme` nulo es «los que no están en ningún tema declarado», que no es lo
/// mismo que un tema vacío: son los documentos que la interfaz enseña sin
/// tarjeta, tal como se enseñaban antes.
class ThemedDocuments {
  const ThemedDocuments({required this.theme, required this.documents});

  final CourseTheme? theme;
  final List<Document> documents;

  bool get isLoose => theme == null;
}

/// One academic year of a course.
class CourseYear {
  const CourseYear({
    required this.year,
    required this.language,
    required this.documents,
    this.group,
    this.themes = const [],
  });

  factory CourseYear.fromJson(Map<String, dynamic> json, {String repo = ''}) =>
      CourseYear(
        year: json['year'] as String? ?? '',
        language: json['language'] as String? ?? 'es',
        group: json['group'] is String ? json['group'] as String : null,
        themes: [
          for (final item in (json['themes'] as List?) ?? const [])
            CourseTheme.fromJson(
              (item as Map).cast<String, dynamic>(),
              repo: repo,
            ),
        ],
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
    // Los temas se suman, sin conflicto: dos repositorios que declaran el
    // mismo id están diciendo lo mismo --es un tema del curso, no de ninguno
    // de los dos-- y el primero se queda con el título. Que uno declare y el
    // otro no es el caso normal, no una discrepancia.
    final byTheme = {for (final theme in themes) theme.id: theme};
    final mergedThemes = [
      ...themes,
      for (final theme in other.themes)
        if (!byTheme.containsKey(theme.id)) theme,
    ];

    return CourseYear(
      year: year,
      language: language,
      group: group ?? other.group,
      themes: mergedThemes,
      documents: [...documents, ...added],
    );
  }

  final String year;
  final String language;
  final String? group;

  /// Los temas declarados para este curso, en el orden en que se dan.
  ///
  /// Juntando los de todos los repositorios abiertos. Vacía es lo corriente:
  /// un curso sin temas declarados enseña sus documentos en una lista, que es
  /// lo que hacían todos hasta ahora.
  final List<CourseTheme> themes;

  /// In composition order, which is content: the order units are taught in.
  final List<Document> documents;

  /// El mismo año sin lo que aporten [hidden].
  ///
  /// Los temas de un repositorio apagado se van con él: si el que declaraba
  /// el Tema 1 está apagado, sus documentos vuelven a salir sueltos, que es
  /// exactamente lo que le pasa a quien no tiene ese repositorio. Apagar y no
  /// tener enseñan lo mismo, y eso es lo que hace el filtro entendible.
  CourseYear? without(Set<String> hidden) {
    if (hidden.isEmpty) return this;
    final kept = [
      for (final document in documents)
        if (!hidden.contains(document.repo)) document,
    ];
    // Desaparece solo si **tenía** documentos y todos eran del repositorio
    // apagado. Un curso que todavía no tiene ninguno --recién creado, o con
    // sus temas aún vacíos-- no es un curso que no se esté mirando: es uno
    // que hay que poder abrir para llenarlo.
    if (documents.isNotEmpty && kept.isEmpty) return null;
    return CourseYear(
      year: year,
      language: language,
      group: group,
      themes: [
        for (final theme in themes)
          if (!hidden.contains(theme.repo)) theme,
      ],
      documents: kept,
    );
  }

  /// Los repositorios que aportan algo a este año.
  Set<String> get repos => {for (final document in documents) document.repo};

  /// Los documentos repartidos en temas, en el orden en que se dan.
  ///
  /// Un documento aparece en cada tema al que pertenece **y que esté
  /// declarado**; los que no caen en ninguno van al final, en un grupo sin
  /// título. Es la regla entera, y es la que hace que esto no pueda romper
  /// nada: sin la declaración no hay agrupación, y sin agrupación queda la
  /// lista de siempre.
  List<ThemedDocuments> get byTheme {
    final declared = {for (final theme in themes) theme.id};
    // Todos los declarados, también los que todavía no llevan nada. Un tema
    // vacío es un tema que se acaba de crear, y esconderlo deja sin sitio por
    // donde meterle el primer documento: se creaba y desaparecía.
    final groups = [
      for (final theme in themes)
        ThemedDocuments(
          theme: theme,
          documents: [
            for (final document in documents)
              if (document.themes.contains(theme.id)) document,
          ],
        ),
    ];

    final loose = [
      for (final document in documents)
        if (!document.themes.any(declared.contains)) document,
    ];
    if (loose.isNotEmpty) {
      groups.add(ThemedDocuments(theme: null, documents: loose));
    }
    return groups;
  }
}

/// Una titulación: el grado o el máster en que se da una asignatura.
///
/// Sigue el mismo patrón que un tema, que es el que sostiene todo lo que se
/// comparte entre repositorios: **la asignatura nombra el grado y el grado lo
/// declara quien lo tenga**. Así una asignatura repartida entre el repositorio
/// de teoría y el de problemas lo nombra desde los dos, y basta con que uno de
/// los dos lo declare.
///
/// Y por eso es no destructivo. Una asignatura que nombra un grado que no
/// declara ningún repositorio abierto sale igual que antes de que existieran
/// los grados: sin agrupar, pero entera.
class Degree {
  const Degree({
    required this.id,
    required this.titles,
    this.institution,
    this.sources = const {},
  });

  factory Degree.fromJson(Map<String, dynamic> json, {String repo = ''}) {
    final titles = _stringMap(json['title']);
    final institution = json['institution'] as String?;
    return Degree(
      id: json['id'] as String? ?? '',
      titles: titles,
      institution: institution,
      sources: {
        repo: DegreeFacts(titles: titles, institution: institution),
      },
    );
  }

  final String id;
  final Map<String, String> titles;
  final String? institution;

  /// Lo que declara cada repositorio, por separado.
  ///
  /// Es lo único que permite darse cuenta de que no dicen lo mismo: sin esto,
  /// la fusión elige un título y el otro desaparece para siempre.
  final Map<String, DegreeFacts> sources;

  String title([String? language]) {
    final wanted = titles[language ?? 'es'];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return id;
  }

  /// Junta lo que dicen dos repositorios del mismo grado.
  ///
  /// Gana el primero para lo que se enseña, y se guarda lo que dice cada uno
  /// para poder señalar la discrepancia. Nada se resuelve solo: son ficheros
  /// que pueden ser de otra persona.
  Degree mergedWith(Degree other) => Degree(
    id: id,
    titles: {...other.titles, ...titles},
    institution: institution ?? other.institution,
    sources: {...sources, ...other.sources},
  );
}

/// Lo que un repositorio declara de un grado.
class DegreeFacts {
  const DegreeFacts({this.titles = const {}, this.institution});

  final Map<String, String> titles;
  final String? institution;

  Map<String, String> get comparable => {
    for (final entry in titles.entries) 'título (${entry.key})': entry.value,
    if ((institution ?? '').isNotEmpty) 'institución': institution!,
  };
}

/// Lo que un repositorio declara de una asignatura, tal cual.
///
/// Sin fusionar con lo que digan los demás: es la única forma de saber que
/// dos repositorios no dicen lo mismo. La fusión elige un valor y las
/// pantallas enseñan ese; esto guarda los dos.
class CourseFacts {
  const CourseFacts({
    this.titles = const {},
    this.languages = const [],
    this.code,
    this.teacher,
    this.institution,
    this.degrees = const {},
    this.degreeId,
  });

  final Map<String, String> titles;
  final List<String> languages;
  final String? code;
  final String? teacher;
  final String? institution;
  final Map<String, String> degrees;

  /// A qué grado dice este repositorio que pertenece.
  final String? degreeId;

  /// Los campos comparables, con el nombre que se enseña.
  ///
  /// En un mapa y no en propiedades sueltas porque comparar, enseñar y
  /// escribir tienen que recorrer exactamente los mismos, y tres listas
  /// separadas acaban discrepando.
  Map<String, String> get comparable => {
    for (final entry in titles.entries) 'título (${entry.key})': entry.value,
    for (final entry in degrees.entries) 'titulación (${entry.key})': entry.value,
    if (languages.isNotEmpty) 'idiomas': languages.join(', '),
    if ((code ?? '').isNotEmpty) 'código': code!,
    if ((teacher ?? '').isNotEmpty) 'profesor': teacher!,
    if ((institution ?? '').isNotEmpty) 'institución': institution!,
    // A qué grado dice cada repositorio que pertenece. Que discrepen no es
    // cosmético: la asignatura saldría en un grado o en otro según en qué
    // orden se abrieron los repositorios.
    if ((degreeId ?? '').isNotEmpty) 'grado': degreeId!,
  };

  /// Dónde vive ese campo dentro de `course.yaml`, para poder escribirlo.
  static List<String>? pathOf(String field) {
    final localised = RegExp(r'^(título|titulación) \((\w+)\)$').firstMatch(field);
    if (localised != null) {
      final key = localised.group(1) == 'título' ? 'title' : 'degree';
      return [key, localised.group(2)!];
    }
    return switch (field) {
      'código' => const ['code'],
      'profesor' => const ['teacher'],
      'institución' => const ['institution'],
      'idiomas' => const ['languages'],
      'grado' => const ['degree_id'],
      _ => null,
    };
  }
}

/// Un campo de una asignatura en el que dos repositorios no coinciden.
///
/// No se resuelve solo. Son ficheros que pueden ser de otra persona, y
/// propagar el valor «más nuevo» por su cuenta deshace el cambio de quien
/// todavía no lo ha enviado. Se enseña, y se iguala cuando alguien lo decide.
/// De qué se discrepa: de una asignatura o de una titulación.
///
/// Dos ficheros distintos --`course.yaml` y `degrees.yaml`-- y dos formas de
/// escribirlos, así que quien resuelve la discrepancia necesita saber cuál es.
enum ConflictAbout { course, degree }

class MetadataConflict {
  const MetadataConflict({
    required this.course,
    required this.field,
    required this.values,
    this.about = ConflictAbout.course,
  });

  /// El id de lo que discrepa: la asignatura, o el grado.
  final String course;

  final ConflictAbout about;

  /// El campo, con el nombre que se lee: «título (es)», «código».
  final String field;

  /// Qué dice cada repositorio.
  final Map<String, String> values;

  /// Dónde se escribe, o null si no se sabe.
  ///
  /// Solo para una asignatura: un grado vive en una lista de `degrees.yaml`,
  /// y una lista no se direcciona por clave. Lo escribe [DegreesFile], que
  /// busca el grado por su id.
  List<String>? get path =>
      about == ConflictAbout.course ? CourseFacts.pathOf(field) : null;

  /// Si se puede resolver desde la interfaz.
  bool get fixable =>
      about == ConflictAbout.degree ? _localised.hasMatch(field) : path != null;

  static final RegExp _localised = RegExp(r'^título \((\w+)\)$');

  /// El idioma del que discrepa, cuando el campo es un título.
  String? get language => _localised.firstMatch(field)?.group(1);

  @override
  String toString() =>
      '$course · $field: ${values.entries.map((e) => '${e.key} dice '
          '«${e.value}»').join(' y ')}';
}

/// A subject, across the years it has run.
class Course {
  const Course({
    required this.id,
    required this.titles,
    this.degreeId,
    required this.language,
    required this.years,
    this.languages = const [],
    this.code,
    this.teacher,
    this.institution,
    this.sources = const {},
  });

  /// Lo que declara de esta asignatura cada repositorio, sin fusionar.
  ///
  /// La fusión se queda con un valor y eso es lo que las pantallas enseñan;
  /// esto guarda lo que dijo cada uno, que es lo único que permite darse
  /// cuenta de que no dicen lo mismo. Sin ello, dos repositorios con el
  /// título mal escrito de formas distintas se ven bien para siempre.
  final Map<String, CourseFacts> sources;

  /// En qué idiomas se da **esta** asignatura.
  ///
  /// No los del repositorio: un repositorio puede mantener castellano,
  /// valenciano e inglés y una asignatura del doble grado darse solo en
  /// castellano. Preguntar por los tres en esa asignatura llena la pantalla
  /// de traducciones que faltan y que no faltan.
  ///
  /// Vacía en un índice viejo, y entonces se cae a los del repositorio, que
  /// es como se comportaba esto antes.
  final List<String> languages;

  factory Course.fromJson(Map<String, dynamic> json, {String repo = ''}) {
    final years = (json['years'] as Map?) ?? const {};
    return Course(
      id: json['id'] as String? ?? '',
      titles: _stringMap(json['title']),
      language: json['language'] as String? ?? 'es',
      languages: _stringList(json['languages']),
      degreeId: json['degreeId'] as String?,
      sources: {
        repo: CourseFacts(
          titles: _stringMap(json['title']),
          languages: _stringList(json['languages']),
          code: json['code'] as String?,
          teacher: json['teacher'] as String?,
          institution: json['institution'] as String?,
          degrees: _stringMap(json['degree']),
          degreeId: json['degreeId'] as String?,
        ),
      },
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
  /// El mismo curso sin lo que aporten [hidden].
  ///
  /// Null cuando no le queda nada: una asignatura cuyos documentos son todos
  /// de un repositorio apagado no es una asignatura vacía, es una asignatura
  /// que no se está mirando.
  Course? without(Set<String> hidden) {
    final kept = <String, CourseYear>{};
    for (final entry in years.entries) {
      final year = entry.value.without(hidden);
      if (year != null) kept[entry.key] = year;
    }
    if (kept.isEmpty) return null;
    return Course(
      id: id,
      titles: titles,
      language: language,
      languages: languages,
      years: kept,
      code: code,
      teacher: teacher,
      institution: institution,
      degreeId: degreeId,
      sources: {
        for (final entry in sources.entries)
          if (!hidden.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

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
      // Unión: que un repositorio no sepa de un idioma no quiere decir que la
      // asignatura no se dé en él, quiere decir que ese repositorio no tiene
      // material suyo. Si los dos lo declaran y no coinciden, es una
      // discrepancia y se dice --ver [Catalogue.metadataConflicts]--, no se
      // resuelve aquí en silencio.
      languages: [
        ...languages,
        for (final code in other.languages)
          if (!languages.contains(code)) code,
      ],
      code: code ?? other.code,
      teacher: teacher ?? other.teacher,
      institution: institution ?? other.institution,
      degreeId: degreeId ?? other.degreeId,
      years: merged,
      sources: {...sources, ...other.sources},
    );
  }

  final String id;
  final Map<String, String> titles;
  final String language;
  final String? code;
  final String? teacher;
  final String? institution;

  /// A qué titulación pertenece, por id. Null cuando no lo dice.
  ///
  /// El id y no el título: el título puede escribirse distinto en cada
  /// repositorio, y lo que agrupa y se filtra tiene que ser lo mismo en los
  /// dos.
  final String? degreeId;

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

/// Una referencia que sale de su repositorio.
///
/// El documento vive en uno y la unidad que llama, en otro. Compila aquí y no
/// compila en la máquina de quien solo tenga uno de los dos.
class CrossRepoUse {
  const CrossRepoUse({
    required this.course,
    required this.year,
    required this.document,
    required this.documentRepo,
    required this.reference,
    required this.unitRepo,
  });

  final String course;
  final String year;
  final String document;
  final String documentRepo;
  final String reference;
  final String unitRepo;

  @override
  String toString() =>
      '$course $year · $document (en $documentRepo) llama a $reference, '
      'que está en $unitRepo';
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

/// Un idioma al que Didacta sabe imprimir.
///
/// El nombre es el que usa quien lo habla --«Català», no «Catalan»--, porque
/// es lo que se lee en una lista de idiomas y lo que permite reconocer el
/// propio sin traducir la interfaz a diez sitios.
class LanguageOption {
  const LanguageOption({required this.code, required this.name});

  final String code;
  final String name;

  factory LanguageOption.fromJson(Map<String, dynamic> json) => LanguageOption(
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? json['code'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is LanguageOption && other.code == code && other.name == name;

  @override
  int get hashCode => Object.hash(code, name);

  @override
  String toString() => '$code ($name)';
}

/// The whole catalogue: what one load gives an interface.
class Catalogue {
  const Catalogue({
    required this.name,
    required this.languages,
    this.available = const [],
    this.degrees = const [],
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
      available: [
        for (final item in (manifest['availableLanguages'] as List?) ?? const [])
          LanguageOption.fromJson((item as Map).cast<String, dynamic>()),
      ],
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
      degrees: [
        for (final item in (courses['degrees'] as List?) ?? const [])
          Degree.fromJson((item as Map).cast<String, dynamic>(), repo: repo),
      ],
      profiles: [
        for (final item in (manifest['profiles'] as List?) ?? const [])
          OutputProfile.fromJson((item as Map).cast<String, dynamic>()),
      ],
      errors: _stringList(manifest['errors']),
    );
  }

  final String name;

  /// A los que este repositorio traduce.
  final List<String> languages;

  /// A los que Didacta sabe imprimir, se usen aquí o no.
  ///
  /// Vacío cuando el índice es anterior a que esto existiera; [languageOptions]
  /// se encarga de que eso no deje la interfaz sin nada que ofrecer.
  final List<LanguageOption> available;

  final String defaultLanguage;

  /// Lo que se ofrece al elegir idioma.
  ///
  /// Con un índice viejo son los que ya se usan: no se puede añadir ninguno
  /// hasta regenerarlo, que es mejor que ofrecer una lista adivinada aquí y
  /// que el motor rechace la mitad.
  List<LanguageOption> get languageOptions => available.isNotEmpty
      ? available
      : [for (final code in languages) LanguageOption(code: code, name: code)];

  /// Identifies the content this catalogue describes, so a stale tab can be
  /// told apart from a current one without comparing every record.
  final String contentHash;

  final List<Unit> units;
  final List<Course> courses;

  /// Las titulaciones declaradas, juntas de todos los repositorios abiertos.
  ///
  /// Un grado que no declara ninguno no sale aquí, y sus asignaturas salen sin
  /// agrupar. Eso es lo que hace que esto no pueda romper nada: quien no tenga
  /// el repositorio donde alguien puso un título ve todo su material igual.
  final List<Degree> degrees;
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

    // El catálogo de idiomas posibles es del motor, así que los repositorios
    // dicen lo mismo salvo que uno tenga el índice viejo. Se unen igual, y
    // gana el orden del primero que lo traiga.
    final degrees = <String, Degree>{};
    for (final part in parts) {
      for (final degree in part.degrees) {
        final mine = degrees[degree.id];
        degrees[degree.id] = mine == null ? degree : mine.mergedWith(degree);
      }
    }

    final available = <LanguageOption>[];
    for (final part in parts) {
      for (final option in part.available) {
        if (!available.any((o) => o.code == option.code)) available.add(option);
      }
    }

    return Catalogue(
      name: parts.first.name,
      languages: languages,
      available: available,
      defaultLanguage: parts.first.defaultLanguage,
      // Uno por repositorio, juntos: sirve para lo de siempre --saber si esto
      // sigue describiendo lo que hay en disco-- y cambia si cambia
      // cualquiera.
      contentHash: [for (final part in parts) part.contentHash].join('+'),
      units: [for (final part in parts) ...part.units],
      courses: courses.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      degrees: degrees.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      profiles: parts.first.profiles,
      errors: [for (final part in parts) ...part.errors, ...conflicts],
    );
  }

  /// El mismo catálogo sin lo que aporten los repositorios apagados.
  ///
  /// Una vista, no otra carga: filtrar es de la interfaz --quién quiere mirar
  /// qué ahora mismo-- y volver al disco por eso significaría esperar medio
  /// segundo por marcar una casilla, y perder el resto mientras tanto.
  ///
  /// Que apagar un repositorio dé exactamente lo mismo que no tenerlo es la
  /// propiedad que se busca: así el filtro contesta «¿qué vería quien solo
  /// tiene esto?», que es la pregunta por la que se usa.
  Catalogue without(Set<String> hidden) {
    if (hidden.isEmpty) return this;
    return Catalogue(
      name: name,
      languages: languages,
      available: available,
      defaultLanguage: defaultLanguage,
      contentHash: contentHash,
      units: [
        for (final unit in units)
          if (!hidden.contains(unit.repo)) unit,
      ],
      courses: [
        for (final course in courses)
          ?course.without(hidden),
      ],
      degrees: [
        for (final degree in degrees)
          if (degree.sources.keys.any((repo) => !hidden.contains(repo)))
            degree,
      ],
      profiles: profiles,
      errors: errors,
    );
  }

  /// Los documentos de un curso, de todos los repositorios que aporten algo.
  List<Document> documentsIn(String courseId, String year) {
    for (final course in courses) {
      if (course.id != courseId) continue;
      return course.years[year]?.documents ?? const [];
    }
    return const [];
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
  /// Campos de una asignatura en los que los repositorios no coinciden.
  ///
  /// Una asignatura repartida se declara en los dos sitios, y los dos
  /// `course.yaml` tienen que decir lo mismo: si uno pone «Análisis
  /// Matemático I» y el otro «Analisis Matematico I», la que se enseña
  /// depende de en qué orden se abrieron los repositorios, que es la peor
  /// clase de comportamiento.
  ///
  /// Solo se compara lo que los dos declaran. Que uno tenga el código y el
  /// otro no, no es una discrepancia: es que uno lo sabe. Rellenarlo es otra
  /// operación y se ofrece aparte.
  List<MetadataConflict> get metadataConflicts {
    final conflicts = <MetadataConflict>[];
    for (final course in courses) {
      if (course.sources.length < 2) continue;
      final fields = <String>{};
      for (final facts in course.sources.values) {
        fields.addAll(facts.comparable.keys);
      }
      for (final field in fields.toList()..sort()) {
        final values = <String, String>{};
        for (final entry in course.sources.entries) {
          final value = entry.value.comparable[field];
          if (value != null && value.isNotEmpty) values[entry.key] = value;
        }
        if (values.length < 2) continue;
        if (values.values.toSet().length == 1) continue;
        conflicts.add(
          MetadataConflict(course: course.id, field: field, values: values),
        );
      }
    }
    conflicts.addAll(degreeConflicts);
    return conflicts;
  }

  /// Lo mismo, para las titulaciones.
  ///
  /// Un grado repartido entre repositorios se declara en los dos `degrees.yaml`
  /// y los dos tienen que decir lo mismo. Si uno pone «Grado en Matemáticas» y
  /// el otro «Matemáticas», el que se enseña depende de en qué orden se
  /// abrieron los repositorios, y las asignaturas de un mismo grado se agrupan
  /// bajo dos nombres distintos según la máquina.
  List<MetadataConflict> get degreeConflicts {
    final conflicts = <MetadataConflict>[];
    for (final degree in degrees) {
      if (degree.sources.length < 2) continue;
      final fields = <String>{};
      for (final facts in degree.sources.values) {
        fields.addAll(facts.comparable.keys);
      }
      for (final field in fields.toList()..sort()) {
        final values = <String, String>{};
        for (final entry in degree.sources.entries) {
          final value = entry.value.comparable[field];
          if (value != null && value.isNotEmpty) values[entry.key] = value;
        }
        if (values.length < 2) continue;
        if (values.values.toSet().length == 1) continue;
        conflicts.add(
          MetadataConflict(
            course: degree.id,
            field: field,
            values: values,
            about: ConflictAbout.degree,
          ),
        );
      }
    }
    return conflicts;
  }

  /// Las asignaturas de un grado, o las que no dicen a cuál pertenecen.
  List<Course> coursesIn(String? degree) => [
    for (final course in courses)
      if (course.degreeId == degree) course,
  ];

  /// Los grados que alguna asignatura nombra sin que nadie los declare.
  ///
  /// No es un error --la asignatura sale suelta, como antes de que existieran
  /// los grados-- pero casi siempre significa que falta una línea en un
  /// `degrees.yaml`, o que falta abrir el repositorio donde está.
  List<String> get undeclaredDegrees {
    final declared = {for (final degree in degrees) degree.id};
    final named = <String>{
      for (final course in courses)
        if ((course.degreeId ?? '').isNotEmpty) course.degreeId!,
    };
    return (named.difference(declared).toList())..sort();
  }

  /// Referencias que salen de su repositorio.
  ///
  /// La regla que sostiene que Didacta funcione con varios repositorios:
  /// **un documento y las unidades que llama viven en el mismo**. LaTeX las
  /// busca bajo la raíz del suyo, así que una lección tomada del repositorio
  /// de al lado compila en la máquina que tiene los dos abiertos y no compila
  /// en la de quien solo tiene uno -- y eso no se descubre editando, se
  /// descubre cuando otra persona va a dar la clase.
  ///
  /// Lo que sí se comparte es la clasificación: las asignaturas, los cursos y
  /// los temas pueden estar repartidos y se juntan. Lo que no puede repartirse
  /// es lo que se encadena para compilar.
  ///
  /// El motor no puede verlo --`didacta check` mira un repositorio y desde
  /// allí la unidad simplemente no existe-- así que lo ve quien tiene los dos
  /// delante, que es esto.
  List<CrossRepoUse> get crossRepoUses {
    final uses = <CrossRepoUse>[];
    for (final course in courses) {
      for (final entry in course.years.entries) {
        for (final document in entry.value.documents) {
          for (final reference in document.unitRefs) {
            // En el suyo: si está, no hay nada que decir.
            if (unitByReference(reference, repo: document.repo) != null) {
              continue;
            }
            final elsewhere = unitByReference(reference);
            if (elsewhere == null) continue; // Rota, que es otra cosa.
            uses.add(
              CrossRepoUse(
                course: course.id,
                year: entry.key,
                document: document.id,
                documentRepo: document.repo,
                reference: reference,
                unitRepo: elsewhere.repo,
              ),
            );
          }
        }
      }
    }
    return uses;
  }

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
