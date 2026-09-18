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

  /// Si lo decide el motor en vez de declararlo alguien.
  ///
  /// «No existe» sale de que el fichero esté o no, y «desactualizada» de
  /// comparar el contenido con el original. Declarar cualquiera de los dos
  /// garantiza que se quede obsoleto en cuanto alguien toque el original, así
  /// que la interfaz no deja ponerlos.
  bool get computed =>
      this == TranslationStatus.missing || this == TranslationStatus.outdated;

  /// Whether it needs work. `outdated` counts: the original has moved on.
  bool get needsWork =>
      this == TranslationStatus.missing ||
      this == TranslationStatus.outdated ||
      this == TranslationStatus.draft;
}

/// Una ubicación de una lección: un documento de un año de una asignatura.
///
/// Con la posición dentro de la composición, porque **la misma lección puede
/// estar dos veces en el mismo tema** y entonces son dos ubicaciones. Sin
/// poder nombrarlas por separado, separar una de la otra sería adivinar cuál
/// se estaba tocando.
class UnitUsage {
  const UnitUsage({
    required this.course,
    required this.year,
    required this.document,
    this.index = 0,
    this.reference = '',
  });

  factory UnitUsage.fromJson(Map<String, dynamic> json) => UnitUsage(
    course: json['course'] as String? ?? '',
    year: json['year'] as String? ?? '',
    document: json['document'] as String? ?? '',
    index: (json['index'] as num?)?.toInt() ?? 0,
    reference: json['ref'] as String? ?? '',
  );

  final String course;
  final String year;
  final String document;

  /// Qué posición ocupa dentro de la composición. Cero en un índice de antes
  /// de que se publicara, que es el caso en que no había dos iguales que
  /// distinguir.
  final int index;

  /// Cómo está escrita la referencia: la ruta o el id. Las dos nombran la
  /// misma lección, y quien vaya a reescribir la línea necesita saber cuál
  /// de las dos hay delante.
  final String reference;

  /// Cómo se nombra esta ubicación en una orden del motor.
  String get key => '$course@$year/$document#$index';

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
    this.templates = const [],
    required this.kind,
    required this.category,
    required this.topic,
    required this.tags,
    required this.titles,
    required this.reference,
    required this.statuses,
    this.indentOff = const {},
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
      templates: _stringList(json['templates']),
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
      indentOff: {
        for (final entry in languages.entries)
          if ((entry.value as Map?)?['indent'] == false) entry.key as String,
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

  /// En qué plantillas se compila **esta** lección.
  ///
  /// Vacía es lo corriente y quiere decir «las que diga su bloque». Elegir
  /// aquí es la excepción --esta lección concreta no se quiere en
  /// diapositivas-- y por eso lo normal no se declara.
  final List<String> templates;

  final String kind;
  final String category;
  final String topic;
  final List<String> tags;
  final Map<String, String> titles;

  /// The language the others are translations of.
  final String reference;

  final Map<String, TranslationStatus> statuses;

  /// Los idiomas cuyo `.tex` se guarda tal cual, sin re-sangrar.
  ///
  /// Solo los apagados: sangrar es lo normal y lo normal no se declara. Se
  /// pregunta con [indentsIn], que es lo que lee el editor.
  final Set<String> indentOff;

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

  /// Si al guardar [language] se le pone la sangría.
  ///
  /// Encendido mientras nadie diga lo contrario: un fichero recién traducido
  /// llega en un bloque, y dejarlo así es el estado que nadie elige.
  bool indentsIn(String language) => !indentOff.contains(language);

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
    this.content = '',
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
        content: json['content'] as String? ?? '',
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

  /// De qué entidad de contenido es esta ubicación.
  ///
  /// Vacío en un documento que solo se da aquí: no forma grupo, así que no
  /// necesita identidad aparte, y eso es lo que evita que compartir sea
  /// obligatorio para escribir un curso. Con valor, el tema está **vinculado**
  /// y lo que se edite se ve desde todas las ubicaciones que lo nombran.
  final String content;

  bool get isLinked => content.isNotEmpty;

  /// Cómo se nombra esta ubicación en una orden del motor.
  String key(String course, String year) => '$course@$year/$id';

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

/// Una versión congelada de un curso: un commit con nombre.
///
/// No hay ninguna copia detrás. git ya guarda el contenido de cada commit; lo
/// que Didacta guarda es lo que git no sabe -- que ese commit concreto es
/// «Antes del primer parcial» y que pertenece a este curso.
///
/// Vive en el repositorio, en `courses/<asignatura>/<año>/freezes.yaml`, por
/// lo mismo que todo lo demás: un clon en otro ordenador tiene que ver las
/// mismas congelaciones, y una base de datos local no se clona.
class Freeze {
  const Freeze({
    required this.id,
    required this.name,
    required this.commit,
    this.description = '',
    this.created = '',
    this.course = '',
    this.year = '',
    this.repo = '',
  });

  factory Freeze.fromJson(Map<String, dynamic> json, {String repo = ''}) =>
      Freeze(
        repo: repo,
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        commit: json['commit'] as String? ?? '',
        description: json['description'] as String? ?? '',
        created: json['created'] as String? ?? '',
        course: json['course'] as String? ?? '',
        year: json['year'] as String? ?? '',
      );

  final String id;
  final String name;

  /// El commit entero. Los cortos no valen: se guardan para años, y un
  /// prefijo que hoy es único deja de serlo cuando el repositorio crece.
  final String commit;

  final String description;

  /// Cuándo se creó, en ISO-8601 con zona. Texto y no `DateTime` porque es lo
  /// que dice el fichero; quien quiera ordenarlas lo convierte.
  final String created;

  final String course;
  final String year;

  /// De qué repositorio sale. Un curso puede estar repartido entre varios, y
  /// una congelación es de aquel cuyo commit nombra.
  final String repo;

  String get shortCommit =>
      commit.length <= 7 ? commit : commit.substring(0, 7);

  DateTime? get when => DateTime.tryParse(created);
}

/// Una ubicación de un contenido: dónde aparece.
class ContentPlacement {
  const ContentPlacement({
    required this.course,
    required this.year,
    required this.document,
    this.index,
  });

  factory ContentPlacement.fromJson(Map<String, dynamic> json) =>
      ContentPlacement(
        course: json['course'] as String? ?? '',
        year: json['year'] as String? ?? '',
        document: json['document'] as String? ?? '',
        index: (json['index'] as num?)?.toInt(),
      );

  final String course;
  final String year;
  final String document;

  /// La posición dentro de una composición, para las lecciones. Nula para un
  /// documento, que no está dentro de nada.
  final int? index;

  String get key => index == null
      ? '$course@$year/$document'
      : '$course@$year/$document#$index';
}

/// Un documento compartido y dónde se da.
///
/// El grupo de sincronización no se guarda en ninguna parte: **es** el
/// conjunto de ubicaciones que nombran el mismo id, y el motor lo calcula
/// leyendo los ficheros. Una lista aparte sería una segunda verdad que puede
/// contradecir a los ficheros, y reconciliarla después de un `git merge` es
/// exactamente el problema que este modelo existe para no tener.
class SharedDocument {
  const SharedDocument({
    required this.id,
    required this.placements,
    this.declared = true,
    this.titles = const {},
    this.kind = '',
    this.repo = '',
  });

  factory SharedDocument.fromJson(
    Map<String, dynamic> json, {
    String repo = '',
  }) => SharedDocument(
    repo: repo,
    id: json['id'] as String? ?? '',
    declared: json['declared'] as bool? ?? true,
    titles: _stringMap(json['title']),
    kind: json['kind'] as String? ?? '',
    placements: [
      for (final item in (json['placements'] as List?) ?? const [])
        ContentPlacement.fromJson((item as Map).cast<String, dynamic>()),
    ],
  );

  final String id;

  /// Que el fichero esté **aquí**. Puede estar en el repositorio de al lado,
  /// y entonces el tema sale vacío hasta que se abra el otro: el mismo trato
  /// que un tema que declara otro repositorio.
  final bool declared;

  final Map<String, String> titles;
  final String kind;
  final List<ContentPlacement> placements;
  final String repo;

  String title(String language) {
    final wanted = titles[language];
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
    this.themes = const [],
    this.freezes = const [],
  });

  factory CourseYear.fromJson(
    Map<String, dynamic> json, {
    String repo = '',
  }) => CourseYear(
    year: json['year'] as String? ?? '',
    language: json['language'] as String? ?? 'es',
    group: json['group'] is String ? json['group'] as String : null,
    themes: [
      for (final item in (json['themes'] as List?) ?? const [])
        CourseTheme.fromJson((item as Map).cast<String, dynamic>(), repo: repo),
    ],
    documents: [
      for (final item in (json['documents'] as List?) ?? const [])
        Document.fromJson((item as Map).cast<String, dynamic>(), repo: repo),
    ],
    freezes: [
      for (final item in (json['freezes'] as List?) ?? const [])
        Freeze.fromJson((item as Map).cast<String, dynamic>(), repo: repo),
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

    // Las congelaciones se suman igual que los temas: cada repositorio
    // congela los commits del suyo, y un curso repartido entre dos tiene las
    // de los dos. Un id repetido se queda con la primera -- son ids opacos,
    // así que repetirse significa que es la misma.
    final byFreeze = {for (final item in freezes) item.id};
    final mergedFreezes = [
      ...freezes,
      for (final item in other.freezes)
        if (!byFreeze.contains(item.id)) item,
    ];

    return CourseYear(
      year: year,
      language: language,
      group: group ?? other.group,
      themes: mergedThemes,
      documents: [...documents, ...added],
      freezes: mergedFreezes,
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

  /// Las versiones congeladas de este curso, en el orden en que se crearon.
  ///
  /// Vacía es lo corriente: un curso sin congelar no tiene ninguna, y es el
  /// caso de todos hasta que alguien congela el primero.
  final List<Freeze> freezes;

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
      freezes: [
        for (final item in freezes)
          if (!hidden.contains(item.repo)) item,
      ],
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

/// Los bloques que Didacta conoce sin que nadie los declare, con su nombre.
///
/// Eran los dos que había cuando esto estaba escrito en el código, y siguen
/// aquí por una razón concreta: un repositorio que todavía no declara ninguno
/// tiene que verse exactamente igual que antes. Sin esto enseñaría `theory`
/// donde decía «Teoría», que es la clase de regresión que hace que nadie se
/// fíe de una migración.
const Map<String, Map<String, String>> defaultBlockTitles = {
  'theory': {'es': 'Teoría', 'va': 'Teoria', 'en': 'Theory'},
  'problems': {'es': 'Problemas', 'va': 'Problemes', 'en': 'Problems'},
};

/// Una parte en que se divide una asignatura: la teoría, los problemas, las
/// prácticas de ordenador.
///
/// `CourseBlock` y no `Block`, como [CourseTheme] y por lo mismo: `Block` ya
/// es una clase de `go_router`, y una pantalla que importe las dos no
/// compila. El nombre largo aquí ahorra un `hide` en cada fichero que
/// navegue.
///
/// El mismo patrón que un tema o una titulación, que es el que sostiene todo
/// lo que se comparte entre repositorios: **la unidad nombra el bloque y el
/// bloque lo declara quien lo tenga**. Así la teoría y los problemas pueden
/// vivir en repositorios distintos y las dos unidades saben a qué parte de la
/// asignatura pertenecen.
///
/// Y por eso no puede romper nada. Una unidad que nombra un bloque que no
/// declara ningún repositorio abierto se ve entera --sale en la biblioteca,
/// se edita, se compila-- solo que el bloque se enseña por su id y «Entre
/// repositorios» dice que falta declararlo. Nunca desaparece material por no
/// tener un repositorio.
class CourseBlock {
  const CourseBlock({
    required this.id,
    required this.titles,
    this.templates = const [],
    this.sources = const {},
  });

  factory CourseBlock.fromJson(Map<String, dynamic> json, {String repo = ''}) {
    final titles = _stringMap(json['title']);
    final templates = _stringList(json['templates']);
    return CourseBlock(
      id: json['id'] as String? ?? '',
      titles: titles,
      templates: templates,
      sources: {repo: BlockFacts(titles: titles, templates: templates)},
    );
  }

  final String id;
  final Map<String, String> titles;

  /// En qué plantillas se compila lo de este bloque, por defecto.
  ///
  /// Vacía quiere decir «todas las activas» y no «ninguna»: declarar un
  /// bloque no puede dejar su material sin salidas. Cada documento y cada
  /// lección pueden quedarse con menos.
  final List<String> templates;

  /// Lo que declara cada repositorio, por separado.
  ///
  /// Es lo único que permite darse cuenta de que no dicen lo mismo: sin esto,
  /// la fusión elige un nombre y el otro desaparece para siempre.
  final Map<String, BlockFacts> sources;

  String title([String? language]) {
    final wanted = titles[language ?? 'es'];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return blockLabel(id, language);
  }

  /// Si el nombre que se enseña no es el del idioma pedido. Lo mismo que en
  /// una unidad, y por lo mismo: un nombre castellano en una lista valenciana
  /// parece una traducción que existe.
  bool titleIsFallback(String language) => (titles[language] ?? '').isEmpty;

  /// Si lo declara alguien. Falso en los que solo existen porque alguna
  /// lección los nombra, que es lo que hay que arreglar.
  bool get declared => sources.isNotEmpty;

  /// El mismo bloque sin lo que digan [hidden].
  ///
  /// Apagar un repositorio tiene que dar exactamente lo mismo que no tenerlo,
  /// y lo que dijera el apagado no puede seguir contando como discrepancia.
  CourseBlock withoutSources(Set<String> hidden) => CourseBlock(
    id: id,
    titles: titles,
    templates: templates,
    sources: {
      for (final entry in sources.entries)
        if (!hidden.contains(entry.key)) entry.key: entry.value,
    },
  );

  /// Junta lo que dicen dos repositorios del mismo bloque.
  ///
  /// Gana el primero para lo que se enseña, y se guarda lo que dice cada uno
  /// para poder señalar la discrepancia. Nada se resuelve solo: son ficheros
  /// que pueden ser de otra persona.
  CourseBlock mergedWith(CourseBlock other) => CourseBlock(
    id: id,
    titles: {...other.titles, ...titles},
    templates: templates.isEmpty ? other.templates : templates,
    sources: {...sources, ...other.sources},
  );
}

/// Lo que un repositorio declara de un bloque.
class BlockFacts {
  const BlockFacts({this.titles = const {}, this.templates = const []});

  final Map<String, String> titles;
  final List<String> templates;

  Map<String, String> get comparable => {
    for (final entry in titles.entries)
      if (entry.value.isNotEmpty) 'título (${entry.key})': entry.value,
    // Con qué se compila entra en la comparación: si un repositorio dice que
    // la teoría sale en diapositivas y apuntes y el otro solo en apuntes, lo
    // que se compila depende de en qué orden se abrieron -- y eso se
    // descubre cuando falta media clase.
    if (templates.isNotEmpty) 'plantillas': templates.join(', '),
  };
}

/// El nombre de un bloque que no declara nadie.
///
/// Los dos de siempre por su nombre, y cualquier otro por su id. Enseñar el
/// id es feo y es cierto, que en una clasificación es lo que hace falta:
/// inventarle un nombre a un bloque que nadie declaró esconde justo lo que
/// hay que arreglar.
String blockLabel(String id, [String? language]) =>
    defaultBlockTitles[id]?[language ?? 'es'] ??
    defaultBlockTitles[id]?['es'] ??
    id;

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
      sources: {repo: DegreeFacts(titles: titles, institution: institution)},
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
    for (final entry in degrees.entries)
      'titulación (${entry.key})': entry.value,
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
    final localised = RegExp(
      r'^(título|titulación) \((\w+)\)$',
    ).firstMatch(field);
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
/// De qué se discrepa: de una asignatura, de una titulación o de un bloque.
///
/// Tres ficheros distintos --`course.yaml`, `degrees.yaml` y `taxonomy.yaml`--
/// y tres formas de escribirlos, así que quien resuelve la discrepancia
/// necesita saber cuál es.
enum ConflictAbout { course, degree, block, template }

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
  bool get fixable => switch (about) {
    ConflictAbout.degree => _localised.hasMatch(field),
    ConflictAbout.block => _localised.hasMatch(field),
    // De una plantilla solo se iguala el nombre desde aquí. La clase y las
    // opciones se dicen, y se arreglan editándola: cambiarlas a distancia es
    // cambiar qué PDF sale, y eso se mira antes de pulsar.
    ConflictAbout.template => _localised.hasMatch(field),
    ConflictAbout.course => path != null,
  };

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
    this.reveals = 'statements',
  });

  factory OutputProfile.fromJson(Map<String, dynamic> json) => OutputProfile(
    id: json['id'] as String? ?? '',
    family: json['family'] as String? ?? '',
    documentClass: json['documentClass'] as String? ?? '',
    label: json['label'] as String? ?? '',
    reveals: json['reveals'] as String? ?? 'statements',
  );

  final String id;
  final String family;
  final String documentClass;

  /// El nombre que se lee: «Diapositivas (sin pausas)», no `slides-flat`.
  ///
  /// Lo deriva el motor de los ejes del perfil y viaja en el índice. Vacío
  /// en un índice viejo, y entonces se enseña el id, que es feo pero cierto.
  final String label;

  /// Cuánto enseña de un ejercicio: `statements`, `answers`, `solutions` o
  /// `teacher`.
  ///
  /// Lo dice el motor y viaja en el índice. Es lo que contesta la pregunta
  /// que se hace de verdad delante del menú --«¿esta lleva las
  /// soluciones?»--, y entregar a una clase la hoja equivocada es el fallo
  /// que eso viene a impedir.
  final String reveals;

  String get name => label.isEmpty ? id : label;

  bool get isSlides => documentClass == 'beamer';
}

/// Una plantilla de compilación: una salida que declara el repositorio.
///
/// Es **lo mismo** que un [OutputProfile] --qué clase de documento sale, con
/// qué opciones y con qué ejes-- con dos diferencias que lo cambian todo: la
/// escribe quien enseña, y puede traer su propio preámbulo de LaTeX. Las
/// quince de siempre siguen viniendo con el programa; una plantilla con el
/// mismo id las sustituye.
///
/// Y como los bloques y las titulaciones, **se declara donde se tenga y se
/// nombra desde cualquier sitio**: el bloque de teoría puede compilarse con
/// una plantilla que declara el repositorio de problemas, que es como está
/// repartido el material de verdad.
class OutputTemplate {
  const OutputTemplate({
    required this.id,
    this.titles = const {},
    this.label = '',
    this.family = '',
    this.reveals = 'statements',
    this.documentClass = '',
    this.classOptions = '',
    this.axes = const {},
    this.active = true,
    this.hasPreamble = false,
    this.storedIn = '',
    this.sources = const {},
  });

  factory OutputTemplate.fromJson(
    Map<String, dynamic> json, {
    String repo = '',
  }) {
    final titles = _stringMap(json['title']);
    final template = OutputTemplate(
      id: json['id'] as String? ?? '',
      titles: titles,
      label: json['label'] as String? ?? '',
      family: json['family'] as String? ?? '',
      reveals: json['reveals'] as String? ?? 'statements',
      documentClass: json['documentClass'] as String? ?? '',
      classOptions: json['classOptions'] as String? ?? '',
      axes: _stringMap(json['axes']),
      active: json['active'] as bool? ?? true,
      hasPreamble: json['hasPreamble'] as bool? ?? false,
      // De qué carpeta salió. Solo lo dice `didacta profiles`, que es por
      // donde llegan las del programa; en el índice no viaja, porque ese
      // fichero se versiona y una ruta absoluta lo haría distinto en cada
      // ordenador.
      storedIn: json['source'] as String? ?? '',
    );
    return template._withSource(repo);
  }

  /// La misma salida vista como plantilla, para un repositorio que no declara
  /// ninguna.
  ///
  /// Sin esto, la primera pantalla que preguntara por las plantillas de un
  /// repositorio recién abierto no ofrecería nada que compilar. Las que trae
  /// el programa no las declara nadie, y eso es exactamente lo que dice
  /// [declared].
  factory OutputTemplate.ofProfile(OutputProfile profile) => OutputTemplate(
    id: profile.id,
    label: profile.label,
    family: profile.family,
    reveals: profile.reveals,
    documentClass: profile.documentClass,
  );

  final String id;

  /// El nombre puesto a mano, por idioma. Vacío es lo corriente: [label] ya
  /// dice «Diapositivas (sin pausas)» sin que nadie lo escriba.
  final Map<String, String> titles;

  /// El nombre que deduce el motor de los ejes de la plantilla.
  final String label;

  /// `slides`, `notes`, `problems`, `handout`, `exam`.
  final String family;

  /// Cuánto enseña de un ejercicio: `statements`, `answers`, `solutions` o
  /// `teacher`.
  final String reveals;

  final String documentClass;
  final String classOptions;
  final Map<String, String> axes;

  /// Si se compila. Apagada queda declarada y fuera de las salidas, que es lo
  /// que se quiere de una versión que este curso no se da: borrarla perdería
  /// su preámbulo.
  final bool active;

  /// Si trae un `templates/<id>.tex` con su propia cabecera.
  final bool hasPreamble;

  /// La carpeta que la declara, cuando se sabe.
  ///
  /// Vacía para las que llegan por el índice de un repositorio --ahí quien la
  /// declara es [sources]-- y puesta para las de la carpeta del programa, que
  /// no son de ningún repositorio y hay que poder distinguirlas para decir
  /// dónde se editan y que nadie las respalda.
  final String storedIn;

  /// Lo que declara cada repositorio, por separado. Lo mismo que en un bloque
  /// y por lo mismo: es lo único que permite ver que no dicen lo mismo.
  final Map<String, TemplateFacts> sources;

  /// Si la declara alguien, o viene con el programa.
  bool get declared => sources.isNotEmpty;

  String title([String? language]) {
    final wanted = titles[language ?? 'es'];
    if (wanted != null && wanted.isNotEmpty) return wanted;
    for (final value in titles.values) {
      if (value.isNotEmpty) return value;
    }
    return label.isEmpty ? id : label;
  }

  bool get isSlides => documentClass == 'beamer';

  /// Si enseña algo que un alumno no debería ver antes de tiempo.
  bool get givesAway => reveals != 'statements';

  /// Lo que enseña de un ejercicio, en una línea.
  ///
  /// Es la pregunta que se hace de verdad delante de un menú de versiones
  /// --«¿esta lleva las soluciones?»-- y la que no se contesta leyendo
  /// `problems` o `problems-answers`. Entregar a una clase la hoja
  /// equivocada es el fallo que esto viene a impedir.
  String get shows => switch (reveals) {
    'answers' => 'enunciados y resultados',
    'solutions' => 'enunciados, resultados y solución',
    'teacher' => 'todo, con la solución paso a paso',
    _ => 'solo los enunciados',
  };

  /// La misma, declarada por [repo].
  ///
  /// Para las de la carpeta del programa: llegan por el motor, que no sabe de
  /// repositorios, y la sesión les pone el suyo para que todo lo demás
  /// --quién la declara, dónde se escribe-- funcione igual que con las de un
  /// repositorio.
  OutputTemplate declaredBy(String repo) => _withSource(repo);

  OutputTemplate _withSource(String repo) => OutputTemplate(
    id: id,
    titles: titles,
    label: label,
    family: family,
    reveals: reveals,
    documentClass: documentClass,
    classOptions: classOptions,
    axes: axes,
    active: active,
    hasPreamble: hasPreamble,
    storedIn: storedIn,
    sources: {
      repo: TemplateFacts(
        titles: titles,
        documentClass: documentClass,
        classOptions: classOptions,
        axes: axes,
        active: active,
      ),
    },
  );

  /// Junta lo que dicen dos repositorios de la misma plantilla. Gana el
  /// primero para lo que se compila, y se guarda lo que dice cada uno.
  OutputTemplate mergedWith(OutputTemplate other) => OutputTemplate(
    id: id,
    titles: {...other.titles, ...titles},
    label: label.isEmpty ? other.label : label,
    family: family.isEmpty ? other.family : family,
    reveals: reveals,
    documentClass: documentClass,
    classOptions: classOptions,
    axes: axes,
    active: active,
    hasPreamble: hasPreamble || other.hasPreamble,
    storedIn: storedIn.isEmpty ? other.storedIn : storedIn,
    sources: {...sources, ...other.sources},
  );

  OutputTemplate withoutSources(Set<String> hidden) => OutputTemplate(
    id: id,
    titles: titles,
    label: label,
    family: family,
    reveals: reveals,
    documentClass: documentClass,
    classOptions: classOptions,
    axes: axes,
    active: active,
    hasPreamble: hasPreamble,
    storedIn: storedIn,
    sources: {
      for (final entry in sources.entries)
        if (!hidden.contains(entry.key)) entry.key: entry.value,
    },
  );
}

/// Lo que un repositorio declara de una plantilla.
class TemplateFacts {
  const TemplateFacts({
    this.titles = const {},
    this.documentClass = '',
    this.classOptions = '',
    this.axes = const {},
    this.active = true,
  });

  final Map<String, String> titles;
  final String documentClass;
  final String classOptions;
  final Map<String, String> axes;
  final bool active;

  /// Los campos comparables, con el nombre que se enseña.
  ///
  /// La clase y las opciones entran: dos repositorios que declaran la misma
  /// plantilla con clases distintas producen PDF distintos con el mismo
  /// nombre según en qué orden se abrieron, que es la peor clase de
  /// comportamiento. Los ejes no, porque son seis y llenarían la pantalla de
  /// filas para una discrepancia que casi siempre está en la clase.
  Map<String, String> get comparable => {
    for (final entry in titles.entries)
      if (entry.value.isNotEmpty) 'título (${entry.key})': entry.value,
    if (documentClass.isNotEmpty) 'clase': documentClass,
    if (classOptions.isNotEmpty) 'opciones': classOptions,
  };
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

/// A qué idiomas traduce **un** repositorio.
///
/// Aparte de la unión que guarda [Catalogue.languages] porque las dos
/// preguntas son distintas y las dos hacen falta. La unión contesta «¿qué
/// idiomas hay en lo que estoy mirando?», que es lo que ordena la barra de
/// arriba. Esto contesta «¿qué puedo escribir en el `course.yaml` de este
/// repositorio?», y esa no la puede contestar la unión: el motor rechaza una
/// asignatura que se declare en un idioma que **su** repositorio no mantiene,
/// y una asignatura rechazada no sale en el catálogo.
///
/// Sin esto, la fusión de dos repositorios dejaba una sola lista y no había
/// forma de volver atrás: la interfaz ofrecía los idiomas de uno para escribir
/// en el otro.
class RepoLanguages {
  const RepoLanguages({
    required this.repo,
    required this.languages,
    required this.defaultLanguage,
  });

  /// El repositorio, con el id que usa el espacio de trabajo. Vacío cuando el
  /// catálogo se lee por HTTP y no hay repositorios que nombrar.
  final String repo;

  /// Los de su `didacta.yaml`.
  final List<String> languages;

  /// El de referencia, el que se supone cuando nada dice otra cosa. Tiene que
  /// estar en [languages]: el motor lo comprueba al leer el fichero.
  final String defaultLanguage;
}

/// The whole catalogue: what one load gives an interface.
class Catalogue {
  const Catalogue({
    required this.name,
    required this.languages,
    this.available = const [],
    this.byRepo = const [],
    this.degrees = const [],
    this.blocks = const [],
    this.templates = const [],
    required this.defaultLanguage,
    required this.contentHash,
    required this.units,
    required this.courses,
    required this.profiles,
    required this.errors,
    this.shared = const [],
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

    final languages = _stringList(manifest['languages']);
    final defaultLanguage = manifest['defaultLanguage'] as String? ?? 'es';

    return Catalogue(
      name: manifest['name'] as String? ?? 'Didacta',
      languages: languages,
      available: [
        for (final item
            in (manifest['availableLanguages'] as List?) ?? const [])
          LanguageOption.fromJson((item as Map).cast<String, dynamic>()),
      ],
      byRepo: [
        RepoLanguages(
          repo: repo,
          languages: languages,
          defaultLanguage: defaultLanguage,
        ),
      ],
      defaultLanguage: defaultLanguage,
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
      // Dentro de la taxonomía, que es donde se declaran: un bloque clasifica
      // una lección, igual que la categoría y el tema. Vacío en un índice de
      // antes de que se declararan, y entonces valen los dos de siempre --ver
      // [blockLabel]--, que es lo que hace que esto no rompa nada.
      blocks: [
        for (final item
            in ((manifest['taxonomy'] as Map?)?['blocks'] as List?) ?? const [])
          CourseBlock.fromJson(
            (item as Map).cast<String, dynamic>(),
            repo: repo,
          ),
      ],
      // Las plantillas que declara este repositorio. Vacío es lo corriente:
      // entonces se compila con las que trae el programa, que es lo que hace
      // que esto no cambie nada mientras nadie declare ninguna.
      templates: [
        for (final item in (manifest['templates'] as List?) ?? const [])
          OutputTemplate.fromJson(
            (item as Map).cast<String, dynamic>(),
            repo: repo,
          ),
      ],
      profiles: [
        for (final item in (manifest['profiles'] as List?) ?? const [])
          OutputProfile.fromJson((item as Map).cast<String, dynamic>()),
      ],
      // Los temas compartidos de **este** repositorio, con las ubicaciones
      // que los dan. Vacío es lo corriente y también lo que trae un índice de
      // antes de que existieran: entonces no hay nada vinculado y todo se ve
      // como se veía.
      shared: [
        for (final item in (courses['shared'] as List?) ?? const [])
          SharedDocument.fromJson(
            (item as Map).cast<String, dynamic>(),
            repo: repo,
          ),
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

  /// Lo que declara cada repositorio por separado, en el orden en que se
  /// leyeron. Ver [RepoLanguages] para por qué no basta con la unión.
  final List<RepoLanguages> byRepo;

  /// A qué idiomas traduce un repositorio.
  ///
  /// Los del catálogo entero cuando no se sabe de él --un índice leído por
  /// HTTP no nombra repositorios--, que es lo que había antes de que esto
  /// existiera y no puede quitarle idiomas a nadie.
  List<String> languagesOf(String repo) {
    for (final entry in byRepo) {
      if (entry.repo == repo) return entry.languages;
    }
    return languages;
  }

  /// El idioma de referencia de un repositorio.
  String defaultLanguageOf(String repo) {
    for (final entry in byRepo) {
      if (entry.repo == repo) return entry.defaultLanguage;
    }
    return defaultLanguage;
  }

  /// El techo de una asignatura: lo que mantienen los repositorios que la
  /// declaran, se dé hoy en ellos o no.
  ///
  /// Es lo que puede ofrecer una pantalla que **escribe** su `course.yaml`:
  /// ofrecer lo que ya declara no dejaría añadir ninguno, y ofrecer los diez
  /// del registro deja escribir uno que el motor rechaza.
  ///
  /// Unión entre repositorios y no intersección: una asignatura repartida
  /// entre el repositorio de teoría --castellano y valenciano-- y el de
  /// problemas --castellano e inglés-- se puede dar en los tres, cada uno con
  /// el material que tiene. Lo que no puede es declararle a uno un idioma del
  /// otro, y de eso se encarga [languagesOf] al escribir.
  List<String> languagesAvailableTo(Course course) {
    final allowed = <String>[];
    for (final repo in course.sources.keys) {
      for (final code in languagesOf(repo)) {
        if (!allowed.contains(code)) allowed.add(code);
      }
    }
    return allowed.isEmpty ? languages : allowed;
  }

  /// En qué idiomas se da una asignatura: lo que declara, cruzado con su
  /// techo.
  ///
  /// La intersección y no lo que declara a secas, aunque el motor garantice
  /// que no puede declarar de más: el índice de un repositorio puede estar
  /// viejo, y un repositorio apagado se lleva sus idiomas con él. Lo que se
  /// ofrece para compilar o para traducir tiene que ser lo que hay ahora, no
  /// lo que había cuando se generó el índice.
  ///
  /// Una asignatura que no declara ninguno se da en los de su repositorio,
  /// que es lo que hace el motor.
  List<String> languagesForCourse(Course course) {
    final allowed = languagesAvailableTo(course);
    if (course.languages.isEmpty) return allowed;
    return [
      for (final code in course.languages)
        if (allowed.contains(code)) code,
    ];
  }

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

  /// Las partes en que se dividen las asignaturas, juntas de todos los
  /// repositorios abiertos.
  ///
  /// En el orden en que se declaran, que es el orden en que se dan --primero
  /// la teoría y luego los problemas-- y no alfabético: ordenar por nombre lo
  /// cambiaría, y volvería a cambiarlo al mirar el material en otro idioma.
  ///
  /// Un bloque que no declara nadie no sale aquí, y sus lecciones se ven
  /// igual: salen en la biblioteca con el bloque enseñado por su id, y
  /// [undeclaredBlocks] lo cuenta para que alguien lo declare. Eso es lo que
  /// hace que esto no pueda esconder material.
  final List<CourseBlock> blocks;

  /// Las plantillas de compilación declaradas, juntas de todos los
  /// repositorios abiertos.
  ///
  /// Vacía quiere decir «nadie declara ninguna», y entonces se compila con
  /// las quince que trae el programa -- ver [templatesInUse], que es lo que
  /// pregunta una pantalla.
  final List<OutputTemplate> templates;

  final List<OutputProfile> profiles;

  /// Los temas compartidos, con las ubicaciones que los dan.
  ///
  /// El grupo de sincronización no está guardado en ninguna parte: **es** el
  /// conjunto de ubicaciones que nombran el mismo id, y el motor lo calcula
  /// leyendo los ficheros. Esto es esa cuenta ya hecha, para que la interfaz
  /// no tenga que recorrer todas las composiciones para pintar un icono.
  final List<SharedDocument> shared;

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

    // Los bloques, por id y **sin ordenar**: el orden es el de la
    // declaración, que es el orden en que se dan las partes de una
    // asignatura. Que los dos repositorios declaren los mismos es el caso
    // normal --la teoría y los problemas repartidos necesitan los dos-- y por
    // eso se guarda lo que dice cada uno: es lo único que permite ver que no
    // dicen lo mismo.
    final blocks = <String, CourseBlock>{};
    for (final part in parts) {
      for (final block in part.blocks) {
        final mine = blocks[block.id];
        blocks[block.id] = mine == null ? block : mine.mergedWith(block);
      }
    }

    // Las plantillas, igual: por id y en el orden en que se declaran, que es
    // el orden en que se ofrecen las salidas. Que las declaren dos no es raro
    // --la teoría y los problemas están repartidos-- y es lo que puede acabar
    // discrepando.
    final templates = <String, OutputTemplate>{};
    for (final part in parts) {
      for (final template in part.templates) {
        final mine = templates[template.id];
        templates[template.id] = mine == null
            ? template
            : mine.mergedWith(template);
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
      // Sin fundir: la unión de arriba dice qué idiomas hay en lo que se está
      // mirando, y esto dice cuáles puede escribir cada repositorio. Lo
      // segundo no se deduce de lo primero.
      byRepo: [for (final part in parts) ...part.byRepo],
      defaultLanguage: parts.first.defaultLanguage,
      // Uno por repositorio, juntos: sirve para lo de siempre --saber si esto
      // sigue describiendo lo que hay en disco-- y cambia si cambia
      // cualquiera.
      contentHash: [for (final part in parts) part.contentHash].join('+'),
      units: [for (final part in parts) ...part.units],
      courses: courses.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      degrees: degrees.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      blocks: blocks.values.toList(),
      templates: templates.values.toList(),
      profiles: parts.first.profiles,
      // Por id, juntando ubicaciones: un tema compartido puede darse en
      // cursos de dos repositorios distintos, y el grupo es el de los dos.
      shared: _mergedShared(parts),
      errors: [for (final part in parts) ...part.errors, ...conflicts],
    );
  }

  static List<SharedDocument> _mergedShared(List<Catalogue> parts) {
    final found = <String, SharedDocument>{};
    for (final part in parts) {
      for (final item in part.shared) {
        final mine = found[item.id];
        if (mine == null) {
          found[item.id] = item;
          continue;
        }
        final keys = {for (final place in mine.placements) place.key};
        found[item.id] = SharedDocument(
          id: item.id,
          // Declarado en cuanto **alguno** lo tenga. Que falte en uno es el
          // caso normal de un curso repartido entre dos repositorios.
          declared: mine.declared || item.declared,
          titles: mine.declared ? mine.titles : item.titles,
          kind: mine.declared ? mine.kind : item.kind,
          repo: mine.declared ? mine.repo : item.repo,
          placements: [
            ...mine.placements,
            for (final place in item.placements)
              if (!keys.contains(place.key)) place,
          ],
        );
      }
    }
    return found.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// El mismo catálogo con unas plantillas más.
  ///
  /// Para las que no viven en ningún repositorio: la carpeta del programa. Se
  /// añaden **detrás** y solo las que no estén ya, así que un repositorio que
  /// declare el mismo id gana -- lo compartido manda sobre lo personal, que
  /// es lo que evita que la copia de alguien cambie en silencio lo que sale
  /// para todos.
  Catalogue withTemplates(List<OutputTemplate> extra) {
    if (extra.isEmpty) return this;
    final known = {for (final template in templates) template.id};
    final added = [
      for (final template in extra)
        if (!known.contains(template.id)) template,
    ];
    if (added.isEmpty) return this;
    return Catalogue(
      name: name,
      languages: languages,
      available: available,
      byRepo: byRepo,
      degrees: degrees,
      blocks: blocks,
      templates: [...templates, ...added],
      defaultLanguage: defaultLanguage,
      contentHash: contentHash,
      units: units,
      courses: courses,
      profiles: profiles,
      shared: shared,
      errors: errors,
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
    final kept = [
      for (final entry in byRepo)
        if (!hidden.contains(entry.repo)) entry,
    ];
    // Los idiomas también se encogen: apagar un repositorio tiene que dar
    // exactamente lo mismo que no tenerlo, y quien solo tuviera los que
    // quedan no vería el idioma que solo mantiene el apagado.
    final remaining = <String>[];
    for (final entry in kept) {
      for (final code in entry.languages) {
        if (!remaining.contains(code)) remaining.add(code);
      }
    }
    return Catalogue(
      name: name,
      languages: remaining.isEmpty ? languages : remaining,
      available: available,
      byRepo: kept,
      defaultLanguage: defaultLanguage,
      contentHash: contentHash,
      units: [
        for (final unit in units)
          if (!hidden.contains(unit.repo)) unit,
      ],
      courses: [for (final course in courses) ?course.without(hidden)],
      degrees: [
        for (final degree in degrees)
          if (degree.sources.keys.any((repo) => !hidden.contains(repo))) degree,
      ],
      // Y sin lo que dijera el apagado, no solo sin los suyos: si se quedara
      // su versión del nombre, apagar un repositorio dejaría en pantalla una
      // discrepancia con alguien que ya no está.
      blocks: [
        for (final block in blocks)
          if (block.sources.keys.any((repo) => !hidden.contains(repo)))
            block.withoutSources(hidden),
      ],
      templates: [
        for (final template in templates)
          if (template.sources.keys.any((repo) => !hidden.contains(repo)))
            template.withoutSources(hidden),
      ],
      profiles: profiles,
      // Un tema compartido deja de verse cuando ya no lo da ningún curso
      // visible: apagar un repositorio tiene que dar exactamente lo mismo que
      // no tenerlo.
      shared: [
        for (final item in shared)
          if (item.placements.any(
            (place) => courses.any(
              (course) =>
                  course.id == place.course &&
                  !hidden.contains(item.repo) &&
                  (course.years[place.year]?.documents.any(
                        (document) => document.id == place.document,
                      ) ??
                      false),
            ),
          ))
            item,
      ],
      errors: errors,
    );
  }

  /// Dónde más se da un tema compartido.
  ///
  /// La lista entera, incluida la ubicación desde la que se pregunta: «este
  /// tema se da en cuatro sitios» quiere decir cuatro, y quitar el de delante
  /// obliga a sumar uno de cabeza.
  SharedDocument? sharedById(String content) {
    if (content.isEmpty) return null;
    for (final item in shared) {
      if (item.id == content) return item;
    }
    return null;
  }

  /// Las ubicaciones de una lección: dónde está y en qué posición.
  List<UnitUsage> usesOf(String path, {String? repo}) =>
      unitByPath(path, repo: repo)?.usedBy ?? const [];

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
    conflicts.addAll(blockConflicts);
    conflicts.addAll(templateConflicts);
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

  /// Lo mismo, para los bloques.
  ///
  /// Un bloque repartido entre repositorios se declara en los dos
  /// `taxonomy.yaml` y los dos tienen que decir lo mismo. Si uno pone
  /// «Teoría» y el otro «Apuntes», el que se enseña depende de en qué orden
  /// se abrieron los repositorios: la misma lección aparece bajo un nombre u
  /// otro según la máquina, y el filtro de la biblioteca ofrece dos cosas que
  /// son una.
  List<MetadataConflict> get blockConflicts {
    final conflicts = <MetadataConflict>[];
    for (final block in blocks) {
      if (block.sources.length < 2) continue;
      final fields = <String>{};
      for (final facts in block.sources.values) {
        fields.addAll(facts.comparable.keys);
      }
      for (final field in fields.toList()..sort()) {
        final values = <String, String>{};
        for (final entry in block.sources.entries) {
          final value = entry.value.comparable[field];
          if (value != null && value.isNotEmpty) values[entry.key] = value;
        }
        // Solo lo que declaran los dos. Que uno tenga el nombre en inglés y
        // el otro no, no es una discrepancia: es que uno lo sabe.
        if (values.length < 2) continue;
        if (values.values.toSet().length == 1) continue;
        conflicts.add(
          MetadataConflict(
            course: block.id,
            field: field,
            values: values,
            about: ConflictAbout.block,
          ),
        );
      }
    }
    return conflicts;
  }

  /// Los bloques que alguna lección nombra y no declara ningún repositorio
  /// abierto, **y que hay que arreglar**.
  ///
  /// No es un error --la lección se ve entera, y el bloque se enseña por su
  /// id-- pero casi siempre significa una de dos cosas: que falta abrir el
  /// repositorio donde está declarado, o que alguien quitó el bloque y sus
  /// lecciones se quedaron nombrándolo. Las dos se arreglan desde «Entre
  /// repositorios», y ninguna se arregla sola.
  ///
  /// **Mientras nadie declare ninguno, los dos de siempre no cuentan.** Un
  /// repositorio de antes de que esto se pudiera declarar tiene teoría y
  /// problemas y no tiene `blocks:`, y señalarle las dos mil lecciones como
  /// «sin bloque» sería llenar la pantalla de un problema que no existe. En
  /// cuanto alguien declara el primero la lista deja de ser implícita, y
  /// entonces `theory` sin declarar es exactamente lo que parece: lecciones
  /// que se quedaron atrás al quitar su bloque.
  List<String> get undeclaredBlocks {
    final named = _namedButNotDeclared;
    if (blocks.isNotEmpty) return named;
    return [
      for (final id in named)
        if (!defaultBlockTitles.containsKey(id)) id,
    ];
  }

  /// Los ids que alguna lección nombra y nadie declara, sin más criterio.
  ///
  /// Separado de [undeclaredBlocks] porque son dos preguntas distintas: esta
  /// es «¿qué bloques hay que ofrecer?», que no puede dejarse ninguno fuera
  /// sin esconder material, y aquella «¿qué hay que arreglar?».
  List<String> get _namedButNotDeclared {
    final declared = {for (final block in blocks) block.id};
    final named = <String>{
      for (final unit in units)
        if (unit.block.isNotEmpty) unit.block,
    };
    return (named.difference(declared).toList())..sort();
  }

  /// Las lecciones de un bloque.
  List<Unit> unitsInBlock(String id) => [
    for (final unit in units)
      if (unit.block == id) unit,
  ];

  /// Lo que una pantalla tiene que ofrecer: los declarados, en su orden, y
  /// detrás los que alguna lección nombra sin que nadie los declare.
  ///
  /// Los segundos salen **a propósito**. Un filtro que no ofrece un bloque es
  /// un filtro desde el que no se llega a su material, así que esconderlos
  /// escondería lecciones que existen -- que es justo lo que este diseño no
  /// puede hacer. Se distinguen por [CourseBlock.declared].
  ///
  /// Los declarados salen aunque estén vacíos: uno vacío es uno que se acaba
  /// de crear, y esconderlo deja sin sitio por donde meterle la primera
  /// lección.
  List<CourseBlock> get blocksInUse => [
    ...blocks,
    for (final id in _undeclaredInReadingOrder)
      CourseBlock(id: id, titles: const {}),
  ];

  /// Los que nadie declara, en el orden en que se enseñan.
  ///
  /// Los dos de siempre primero y en el orden de siempre --la teoría antes
  /// que los problemas-- porque un repositorio que no declara ninguno tiene
  /// que verse exactamente igual que antes, y alfabético pondría los
  /// problemas delante. Los demás, alfabéticos: nadie ha dicho en qué orden
  /// van, y cualquier otro sería inventado.
  List<String> get _undeclaredInReadingOrder {
    final known = defaultBlockTitles.keys.toList();
    int rank(String id) {
      final at = known.indexOf(id);
      return at < 0 ? known.length : at;
    }

    return _namedButNotDeclared.toList()..sort((a, b) {
      final byDefault = rank(a).compareTo(rank(b));
      return byDefault != 0 ? byDefault : a.compareTo(b);
    });
  }

  /// El bloque con ese id, declarado o no.
  ///
  /// Nunca null para un id que alguien usa: si nadie lo declara sale uno sin
  /// nombre, que se enseña por su id. Una pantalla que pregunta por el bloque
  /// de una lección no puede quedarse sin respuesta.
  CourseBlock blockNamed(String id) {
    for (final block in blocks) {
      if (block.id == id) return block;
    }
    return CourseBlock(id: id, titles: const {});
  }

  /// Los bloques a los que pertenece un documento: los de las lecciones que
  /// compone.
  ///
  /// Derivado y no declarado, y eso es deliberado: un documento no elige
  /// bloque, lo hereda de lo que lleva dentro. Un tema con su teoría y sus
  /// ejercicios está en los dos, y decirlo de otra forma obligaría a
  /// mantener a mano algo que ya está escrito en cada lección.
  Set<String> blocksOf(Document document) {
    final found = <String>{};
    for (final reference in document.unitRefs) {
      final unit =
          unitByReference(reference, repo: document.repo) ??
          unitByReference(reference);
      if (unit != null) found.add(unit.block);
    }
    return found;
  }

  // -- las plantillas de compilación ---------------------------------------

  /// Las plantillas que hay que ofrecer, declaradas o de serie.
  ///
  /// Las declaradas cuando hay alguna, y si no las quince que trae el
  /// programa. Esa caída es lo que hace que un repositorio que todavía no
  /// declara ninguna compile exactamente como antes: sin ella, la primera
  /// pantalla que preguntara no ofrecería nada.
  List<OutputTemplate> get templatesInUse => templates.isNotEmpty
      ? templates
      : [for (final profile in profiles) OutputTemplate.ofProfile(profile)];

  /// Las que se pueden compilar: las de arriba sin las apagadas.
  ///
  /// Apagar una es decir «esta versión no se saca», y es la respuesta a tener
  /// quince salidas de las que se usan cuatro. Sigue declarada, con su
  /// preámbulo, para el día que vuelva a hacer falta.
  List<OutputTemplate> get activeTemplates => [
    for (final template in templatesInUse)
      if (template.active) template,
  ];

  /// La plantilla con ese id, declarada o no.
  ///
  /// Nunca null para un id que alguien usa: si nadie la declara sale una sin
  /// nombre, que se enseña por su id. Una pantalla que pregunta con qué se
  /// compila algo no puede quedarse sin respuesta.
  OutputTemplate templateNamed(String id) {
    for (final template in templatesInUse) {
      if (template.id == id) return template;
    }
    return OutputTemplate(id: id);
  }

  /// Con qué se compila lo de un bloque, por defecto.
  ///
  /// Lo que el bloque declare, y si no declara nada, todas las activas. Vacío
  /// no puede significar «ninguna»: declarar un bloque dejaría su material
  /// sin salidas y nadie entendería por qué el botón de compilar no hace
  /// nada.
  ///
  /// Siempre filtrado por las activas: una plantilla apagada no se compila
  /// aunque un bloque la nombre, que es justo lo que significa apagarla.
  List<String> templatesOfBlock(String block) {
    final live = {for (final template in activeTemplates) template.id};
    for (final entry in blocks) {
      if (entry.id != block) continue;
      if (entry.templates.isEmpty) break;
      return [
        for (final id in entry.templates)
          if (live.contains(id)) id,
      ];
    }
    return live.toList();
  }

  /// Con qué se compila una lección.
  ///
  /// La suya si la declara, y si no la de su bloque. Es el orden en que se
  /// decide: el bloque pone lo normal y la lección concreta se aparta.
  List<String> templatesFor(Unit unit) {
    if (unit.templates.isEmpty) return templatesOfBlock(unit.block);
    final live = {for (final template in activeTemplates) template.id};
    return [
      for (final id in unit.templates)
        if (live.contains(id)) id,
    ];
  }

  /// Con qué se compila un documento.
  ///
  /// Lo que declare, y si no lo de los bloques de las lecciones que compone
  /// --un tema con su teoría y sus ejercicios hereda de los dos--. En el
  /// orden de las plantillas y no en el de los bloques, para que dos
  /// documentos del mismo curso no ofrezcan lo mismo en orden distinto.
  List<String> templatesForDocument(Document document) {
    final live = {for (final template in activeTemplates) template.id};
    if (document.profiles.isNotEmpty) {
      return [
        for (final id in document.profiles)
          if (live.contains(id)) id,
      ];
    }
    final wanted = <String>{};
    for (final block in blocksOf(document)) {
      wanted.addAll(templatesOfBlock(block));
    }
    // Sin lecciones todavía --un documento recién creado-- no hay bloque del
    // que heredar, y quedarse sin nada que compilar sería lo peor que puede
    // pasarle a lo que se acaba de crear.
    if (wanted.isEmpty) return live.toList();
    return [
      for (final template in activeTemplates)
        if (wanted.contains(template.id)) template.id,
    ];
  }

  /// Las plantillas que alguien nombra y no declara nadie.
  ///
  /// Un bloque que compila en `apuntes-a5` y el repositorio que la declaraba
  /// sin abrir: se ve, se dice, y se arregla. Mientras nadie declare ninguna
  /// plantilla no cuenta ninguna, por lo mismo que con los bloques -- las
  /// quince de serie no las declara nadie y no son un problema.
  List<String> get undeclaredTemplates {
    if (templates.isEmpty) return const [];
    final declared = {for (final template in templates) template.id};
    final named = <String>{};
    for (final block in blocks) {
      named.addAll(block.templates);
    }
    for (final unit in units) {
      named.addAll(unit.templates);
    }
    for (final course in courses) {
      for (final year in course.years.values) {
        for (final document in year.documents) {
          named.addAll(document.profiles);
        }
      }
    }
    return (named.difference(declared).toList())..sort();
  }

  /// Campos de una plantilla en los que dos repositorios no coinciden.
  ///
  /// La misma plantilla declarada en los dos con clases distintas produce dos
  /// PDF distintos con el mismo nombre según en qué orden se abrieron los
  /// repositorios.
  List<MetadataConflict> get templateConflicts {
    final conflicts = <MetadataConflict>[];
    for (final template in templates) {
      if (template.sources.length < 2) continue;
      final fields = <String>{};
      for (final facts in template.sources.values) {
        fields.addAll(facts.comparable.keys);
      }
      for (final field in fields.toList()..sort()) {
        final values = <String, String>{};
        for (final entry in template.sources.entries) {
          final value = entry.value.comparable[field];
          if (value != null && value.isNotEmpty) values[entry.key] = value;
        }
        if (values.length < 2) continue;
        if (values.values.toSet().length == 1) continue;
        conflicts.add(
          MetadataConflict(
            course: template.id,
            field: field,
            values: values,
            about: ConflictAbout.template,
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
