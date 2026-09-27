/// Compilar una unidad desde la aplicación.
///
/// La pregunta que responde es la que se hace editando: «¿cómo queda esto?»,
/// en diapositivas y en libro, sin salir de la unidad. Lo hace el motor
/// --`didacta preview`--, no la aplicación: el preámbulo, los 15 perfiles y
/// el parseo del log de LaTeX ya existen y están probados, y una segunda
/// implementación en Dart sería una segunda cosa que se desincroniza.
///
/// **Solo en escritorio.** Compilar necesita LaTeX y un navegador no lo
/// tiene. La pantalla lo dice en lugar de fingirlo: un botón que no puede
/// funcionar es peor que su ausencia explicada.
library;

import '../model/catalogue.dart';
import '../model/review.dart';
import 'compiler_stub.dart' if (dart.library.io) 'compiler_io.dart' as platform;
import '../l10n/tr.dart';

/// Un perfil de salida ofrecido para una unidad, tal como lo lista el motor.
///
/// Distinto de `catalogue.OutputProfile`, que es lo que el índice publica
/// --id, familia y clase-- y no lleva la etiqueta en castellano. Esta viene
/// de `didacta preview --list`, que es la que sabe cómo se llama en la
/// interfaz: «Diapositivas», «Libro», «Apuntes (profesor)».
class BuildableProfile {
  const BuildableProfile({
    required this.id,
    required this.label,
    required this.family,
    this.reveals = 'statements',
    this.byDefault = false,
  });

  final String id;

  /// El nombre en castellano: «Diapositivas», «Libro», «Apuntes (profesor)».
  final String label;

  /// `slides`, `notes`, `problems`, `handout`, `exam`.
  final String family;

  /// Cuánto enseña de un ejercicio: `statements`, `answers`, `solutions` o
  /// `teacher`.
  ///
  /// Lo dice el motor y no se deduce del id aquí: son los mismos tres campos
  /// del editor --enunciado, resultado, solución detallada-- leídos como
  /// niveles, y quien decide cuáles se ven es el perfil.
  final String reveals;

  /// Lo que un ejercicio enseña en esta versión, en una línea.
  ///
  /// Es la pregunta que se hace de verdad delante del menú --«¿esta lleva
  /// las soluciones?»-- y la que no se puede contestar leyendo `problems` o
  /// `problems-answers`. Entregar a una clase la hoja equivocada es el fallo
  /// que esto viene a impedir.
  String get shows => switch (reveals) {
    'answers' => tr('enunciados y resultados'),
    'solutions' => tr('enunciados, resultados y solución'),
    'teacher' => tr('todo, con la solución paso a paso'),
    _ => tr('solo los enunciados'),
  };

  /// Si enseña algo que un alumno no debería ver antes de tiempo.
  bool get givesAway => reveals != 'statements';

  /// Si es una de las que se miran primero: las dos que se pidieron
  /// --presentación y libro-- más los apuntes, que son la prosa por defecto.
  bool get isPrimary => id == 'slides' || id == 'book' || id == 'notes';

  /// Para un documento: si es una de las que declara en `year.yaml`.
  ///
  /// Es lo que se preselecciona. Las demás se pueden elegir igual --el mismo
  /// tema se quiere en libro un día y en diapositivas otro-- pero lo que el
  /// documento dice de sí mismo es el punto de partida razonable.
  final bool byDefault;
}

/// Una salida que puede estar compilada, y en qué estado.
///
/// Existe para responder a dos preguntas que la interfaz hacía a ciegas:
/// «¿esto ya está compilado?» --y entonces se abre sin volver a compilar-- y
/// «¿sigue valiendo?» --y si no, se dice, porque un PDF que no corresponde al
/// fichero es peor que no tenerlo.
class ExistingOutput {
  const ExistingOutput({
    required this.profile,
    required this.label,
    required this.family,
    required this.language,
    required this.pdf,
    required this.exists,
    required this.stale,
    this.modified,
    this.quick = false,
  });

  final String profile;

  /// El nombre en castellano: «Diapositivas», «Libro».
  final String label;
  final String family;
  final String language;

  /// Donde estaría el PDF, exista o no.
  final String pdf;

  final bool exists;

  /// El origen se tocó después de compilar esto.
  ///
  /// «No existe» y «está viejo» son dos cosas distintas: un PDF que falta no
  /// está viejo, y la interfaz dice cada una de otra forma.
  final bool stale;

  /// Cuándo se compiló, si está.
  final DateTime? modified;

  /// Salió de una sola pasada (la vista rápida). Cuenta como [stale]: el
  /// índice y las referencias pueden no estar al día, y lo que se reparte se
  /// compila entero.
  final bool quick;

  bool get usable => exists && !stale;

  /// Si es una de las que se miran primero.
  bool get isPrimary =>
      profile == 'slides' || profile == 'book' || profile == 'notes';
}

/// El resultado de compilar una unidad en un perfil y un idioma.
/// Un error o un aviso de LaTeX, con dónde está.
///
/// El motor sigue qué fichero tenía abierto LaTeX y lo traduce a la
/// lección: [unit] y [language] cuando el error está en el `.tex` de una, y
/// [line], la línea. Es lo que permite «Lección X (es) · línea 42 · [Abrir]»
/// en lugar de una ruta relativa a la carpeta de compilación.
class CompileDiagnostic {
  const CompileDiagnostic({
    required this.severity,
    required this.message,
    this.file,
    this.line,
    this.context,
    this.path,
    this.unit,
    this.language,
    this.code,
    this.points,
    this.times = 1,
  });

  factory CompileDiagnostic.fromJson(Map<String, dynamic> json) =>
      CompileDiagnostic(
        severity: json['severity'] as String? ?? 'error',
        message: json['message'] as String? ?? '',
        file: json['file'] as String?,
        line: (json['line'] as num?)?.toInt(),
        context: json['context'] as String?,
        path: json['path'] as String?,
        unit: json['unit'] as String?,
        language: json['language'] as String?,
        code: json['code'] as String?,
        points: (json['points'] as num?)?.toDouble(),
        times: (json['times'] as num?)?.toInt() ?? 1,
      );

  final String severity;
  final String message;

  /// Como lo nombra el log, relativo a la carpeta del documento.
  final String? file;
  final int? line;

  /// Lo que LaTeX estaba leyendo: en «Undefined control sequence», el único
  /// sitio donde sale el nombre de la orden.
  final String? context;

  /// Desde la raíz del repositorio: `content/a/b/c/es.tex`.
  final String? path;

  /// La lección y el idioma, si es el `.tex` de una.
  final String? unit;
  final String? language;

  /// Qué es, cuando el motor lo sabe: `overfull-slide` (una diapositiva que
  /// se sale por abajo) u `overfull-line` (una línea que se sale por la
  /// derecha).
  final String? code;

  /// Cuánto se sale, en puntos, y en cuántas páginas: una diapositiva con
  /// capas se sale en todas.
  final double? points;
  final int times;

  bool get isError => severity == 'error';

  /// Algo que se sale de la página: se compila, pero no se ve entero.
  bool get isOverflow => code == 'overfull-slide' || code == 'overfull-line';

  /// En una línea, sin saber de la lección más que su ruta.
  String get plain {
    final where = path ?? file;
    final head = where == null || where.isEmpty
        ? message
        : '${line == null ? where : '$where:$line'}: $message';
    return context == null || context!.isEmpty ? head : '$head  ← $context';
  }
}

class CompileOutput {
  const CompileOutput({
    required this.profile,
    required this.language,
    required this.ok,
    this.pdf,
    this.pages = 0,
    this.seconds = 0,
    this.errors = const [],
    this.warnings = const [],
    this.diagnostics = const [],
    this.quick = false,
  });

  /// De una sola pasada: el índice, las referencias y el total de
  /// diapositivas pueden no estar al día.
  final bool quick;

  /// Los diagnósticos con su sitio, tal como los devuelve el motor.
  final List<CompileDiagnostic> diagnostics;

  /// Los errores con su sitio. Si el motor no los dio así --uno viejo, o una
  /// prueba--, los de [errors] como texto.
  List<CompileDiagnostic> get errorDiagnostics {
    final located = [
      for (final diagnostic in diagnostics)
        if (diagnostic.isError) diagnostic,
    ];
    if (located.isNotEmpty || errors.isEmpty) return located;
    return [
      for (final error in errors)
        CompileDiagnostic(severity: 'error', message: error),
    ];
  }

  /// Lo que se sale de la página --diapositivas que no caben, líneas que
  /// pasan el margen--, cada uno con su lección y su línea.
  List<CompileDiagnostic> get overflowDiagnostics => [
    for (final diagnostic in diagnostics)
      if (diagnostic.isOverflow) diagnostic,
  ];

  final String profile;
  final String language;
  final bool ok;

  /// La ruta del PDF, o null si no salió.
  final String? pdf;

  final int pages;
  final double seconds;

  /// Los diagnósticos del log, ya parseados por el motor: fichero, línea y
  /// mensaje. Se muestran tal cual porque el motor ya sabe a quién culpar.
  /// En [warnings] no está lo que se sale de la página, que va en
  /// [overflowDiagnostics] con a dónde lleva.
  final List<String> errors;
  final List<String> warnings;
}

/// Hasta dónde puede enseñar lo que se exporta.
///
/// Una carpeta exportada acaba en el aula virtual, así que lo que sale por
/// defecto es lo del estudiante: los enunciados y, como mucho, los
/// resultados. Subir el listón es algo que se pide a sabiendas.
enum ExportReach {
  /// Enunciados y resultados: lo que se reparte.
  students('answers'),

  /// Además, las resoluciones completas.
  solutions('solutions'),

  /// Además, las copias del profesor: la plantilla de corrección del examen,
  /// las diapositivas con notas.
  teacher('teacher');

  const ExportReach(this.engineName);

  /// Lo que entiende `didacta export --reveal-up-to`.
  final String engineName;
}

/// Lo que salió de exportar un curso.
class ExportResult {
  const ExportResult({
    required this.copied,
    required this.missing,
    required this.to,
    this.withheld = const [],
    this.zip,
  });

  /// El .zip con todo lo exportado, cuando se pidió.
  final String? zip;

  /// Los ficheros copiados, con su ruta dentro del destino.
  final List<String> copied;

  /// Lo que se pidió y no estaba compilado, como «documento · versión ·
  /// idioma». Se dice: un reparto incompleto que no lo parece es peor que
  /// uno que falla.
  final List<String> missing;

  /// Lo que estaba compilado y se ha dejado fuera porque enseña más de lo
  /// que se pidió repartir. Aparte de [missing]: no es que falte compilarlo.
  final List<String> withheld;

  final String to;
}

/// Por qué no se pudo compilar.
class CompileException implements Exception {
  const CompileException(this.message, {this.detail = ''});

  final String message;

  /// Lo que dijo el proceso. Se guarda porque su mensaje suele ser lo más
  /// útil que se le puede enseñar a alguien.
  final String detail;

  @override
  String toString() => detail.isEmpty ? message : '$message\n\n$detail';
}

/// Qué hace falta para compilar, y si está.
class CompilerStatus {
  const CompilerStatus({
    required this.ready,
    required this.enginePath,
    this.problem,
  });

  final bool ready;

  /// La raíz del repositorio del motor: la que tiene `cli/didacta`.
  final String? enginePath;

  /// Qué falta, en palabras con las que se pueda hacer algo.
  final String? problem;
}

abstract class Compiler {
  /// La implementación de esta plataforma.
  /// [jobs] es cuántas salidas de un documento compilar a la vez; 0 deja
  /// que lo decida el motor (min(4, núcleos/2)). [overfullLines], si avisar
  /// también de las líneas que se salen por la derecha en lo que no son
  /// diapositivas. [accessible], PDF etiquetados (`--accessible`).
  factory Compiler({
    required String enginePath,
    required String repositoryPath,
    String? texPath,
    List<String> templateDirs = const [],
    int jobs = 0,
    bool overfullLines = false,
    bool accessible = false,
  }) => platform.makeCompiler(
    enginePath: enginePath,
    repositoryPath: repositoryPath,
    texPath: texPath,
    templateDirs: templateDirs,
    jobs: jobs,
    overfullLines: overfullLines,
    accessible: accessible,
  );

  /// Si compilar es posible aquí. Falso en web, donde no hay LaTeX ni forma
  /// de lanzar un proceso.
  static bool get supported => platform.supported;

  /// Busca el motor sin preguntar.
  ///
  /// Mira, por orden: lo que se haya configurado, `didacta` en el PATH, y el
  /// hermano del clon --que es la disposición que sale de clonar los dos
  /// repositorios al lado, y por tanto la que va a tener casi todo el mundo.
  static Future<String?> discover({
    String? configured,
    String? repositoryPath,
  }) =>
      platform.discover(configured: configured, repositoryPath: repositoryPath);

  Future<CompilerStatus> status();

  /// Los perfiles en los que merece la pena compilar esta unidad, en el
  /// orden en el que el motor los ofrece.
  Future<List<BuildableProfile>> profilesFor(String unitPath);

  /// Qué hay compilado de esta unidad, y si sigue valiendo.
  ///
  /// Una llamada al motor y no un `stat` propio: la ruta del PDF sale de las
  /// reglas de nombrado del perfil, y adivinarlas aquí sería una segunda
  /// copia de esas reglas.
  Future<List<ExistingOutput>> outputsFor(String unitPath);

  /// Si un PDF que ya está abierto se ha quedado viejo.
  ///
  /// Esto sí se hace aquí: con la ruta ya en la mano solo hace falta comparar
  /// fechas, y lanzar un proceso cada vez que alguien cambia de pestaña para
  /// preguntar algo que son dos `stat` sería absurdo.
  Future<bool> isStale({required String pdf, required String unitPath});

  /// Compila una unidad. Un resultado por perfil y por idioma.
  ///
  /// Varios idiomas de una vez porque la comparación que importa es esa: si
  /// la traducción valenciana sigue cabiendo en la diapositiva no se puede
  /// saber sin las dos delante.
  ///
  /// [onOutput] recibe cada línea que escribe LaTeX, según la escribe. Se
  /// pasa cuando hay alguien mirando --la consola de compilación-- y se
  /// omite cuando no, que es lo que decide si el motor la emite: una
  /// compilación silenciosa no paga nada por la que se está viendo.
  Future<List<CompileOutput>> compile({
    required String unitPath,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  });

  /// Las plantillas que declara un directorio, tal como las lee el motor.
  ///
  /// Existe por la carpeta de plantillas del programa: no es un repositorio,
  /// así que no tiene índice y el catálogo no la ve. Se le pregunta al motor
  /// en lugar de leer su `templates.yaml` aquí, porque tener dos lectores del
  /// mismo fichero es tener dos respuestas a la misma pregunta -- y la que
  /// importa es la del que compila.
  Future<List<OutputTemplate>> templatesIn(String directory);

  /// Si el índice de `generated/` ya no describe lo que hay en el disco.
  ///
  /// Barato: el motor cuenta ficheros y mira fechas, sin abrir ninguno. Se
  /// pregunta en cada arranque, así que tres segundos de generar el índice
  /// para saberlo no valdrían.
  Future<({bool stale, String? reason})> indexStale();

  /// Regenera el índice. Devuelve lo que el motor imprimió.
  Future<String> reindex();

  /// Qué hay compilado en toda la biblioteca, de una vez.
  ///
  /// Una llamada y no una por unidad: la biblioteca lista dos mil, y lo que
  /// quiere saber es cuáles se pueden ojear ya. Dos mil procesos para pintar
  /// una lista no es una opción.
  ///
  /// La clave es la ruta de la unidad, como en el catálogo. Solo salen las
  /// que tienen algo compilado.
  Future<Map<String, List<ExistingOutput>>> builtOutputs();

  /// Las versiones en las que se puede compilar un **documento entero**.
  ///
  /// [document] es la referencia que usa el motor, `curso@año/documento`.
  ///
  /// Todas las de su familia y no solo las que el documento declara en
  /// `year.yaml`: el mismo tema se quiere en libro un día y en diapositivas
  /// otro, y eso no puede obligar a editar el fichero. Las suyas vienen
  /// marcadas, que es lo que se preselecciona.
  Future<List<BuildableProfile>> documentProfiles(String document);

  /// Saca los PDF de un curso a una carpeta, ordenados por idioma y tema.
  ///
  /// Copia, no toca el repositorio: lo que sale es para repartir. Devuelve qué
  /// se copió y qué faltaba por compilar, porque un reparto al que le faltan
  /// tres PDF tiene que decirlo y no adivinarse contando ficheros.
  ///
  /// [reach] decide si entran las soluciones y las copias del profesor; por
  /// defecto, no. Con [zip], además, todo lo exportado en ese .zip; con
  /// [appendZip] se añade a uno que ya exista, que es lo que hace falta en
  /// la segunda pasada de una asignatura repartida en dos repositorios. Con
  /// [html], los apuntes también en HTML accesible, al lado de cada PDF que
  /// no sea de diapositivas (`export --html`).
  Future<ExportResult> exportCourse({
    required String where,
    required String to,
    List<String> languages = const [],
    List<String> documents = const [],
    ExportReach reach = ExportReach.students,
    String? zip,
    bool appendZip = false,
    bool html = false,
  });

  /// Qué hay compilado de cada documento de un curso, por id de documento.
  ///
  /// Del curso entero de una vez y no documento por documento: es lo que una
  /// pantalla pregunta al abrirse para saber qué se puede abrir sin compilar,
  /// y preguntarlo uno a uno serían tantos procesos como documentos.
  Future<Map<String, List<ExistingOutput>>> documentOutputs(String where);

  /// Compila un documento entero. Un resultado por versión y por idioma.
  Future<List<CompileOutput>> compileDocument({
    required String document,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
    void Function(String line)? onOutput,
  });

  /// Lanza el motor con los argumentos que se le den, y devuelve su salida.
  ///
  /// Está aquí porque esto ya es «lo que sabe lanzar el motor»: encontrar
  /// `cli/didacta`, comprobar que está, ejecutarlo desde el clon y limpiar
  /// el token de lo que se enseñe. Tener un segundo objeto para lanzar otras
  /// órdenes sería tener dos sitios donde arreglar el mismo problema.
  Future<String> run(
    List<String> arguments, {
    bool allowFailure = false,
    void Function(String line)? onOutput,
  });

  /// Abre el PDF en el visor del sistema.
  ///
  /// En lugar de incrustar un visor: el del sistema tiene zoom, navegación y
  /// pantalla completa, que para repasar unas diapositivas es exactamente lo
  /// que hace falta, y no añade una dependencia de renderizado de PDF a una
  /// aplicación cuyo trabajo es editar LaTeX.
  Future<void> open(String pdf);

  /// Lo enseña en el Finder, para arrastrarlo a un correo.
  Future<void> reveal(String pdf);

  /// Borra salidas compiladas, y devuelve cuántos ficheros se ha llevado.
  ///
  /// Se lleva también los restos que LaTeX deja al lado de cada PDF --el
  /// `.log`, el `.aux`, el `.synctex.gz`--, porque lo que se borra es la
  /// salida entera y no su portada. Todo vive en el directorio de
  /// compilación, que no se versiona: esto es tirar algo que se rehace
  /// pulsando el botón de al lado, y por eso no pregunta dos veces.
  Future<int> deleteOutputs(List<String> pdfs);

  /// Para lo que se esté compilando: el motor y lo que haya lanzado.
  ///
  /// Lo que estaba compilando termina entonces con un error o con un
  /// resultado a medias, y quien compila tiene que tomarlo por «detenido» y
  /// no por un fallo: lo sabe porque fue quien pidió parar.
  Future<void> stopCompiling();

  /// De dónde salió el punto ([x], [y]) de la página [page] de [pdf]:
  /// `didacta synctex`. Las coordenadas en puntos, desde arriba a la
  /// izquierda. [word] y [text], lo que había escrito ahí, afinan la línea
  /// dentro de una diapositiva. Null si ahí no hay nada que venga de un
  /// fichero.
  Future<SourceSpot?> sourceAt({
    required String pdf,
    required int page,
    required double x,
    required double y,
    String? word,
    String? text,
  });

  /// Revisa el repositorio: `didacta check --json`. [within] lo limita a
  /// esos documentos o cursos --`curso@año`, `curso@año/documento`--, que
  /// es lo que se mira antes de exportar; [extra], las comprobaciones que se
  /// piden aparte (ver `optionalReviewChecks`).
  Future<ReviewReport> review({
    List<String> within = const [],
    List<String> extra = const [],
  });

  /// Cuánto ocupa la carpeta de compilación: `didacta clean --size`.
  Future<BuildFolder> buildFolder();

  /// La vacía: `didacta clean`. Devuelve lo que había.
  Future<BuildFolder> cleanBuild();
}

/// La carpeta de compilación de un repositorio: los PDF, los `.aux` y los
/// registros, que no se versionan y se rehacen compilando.
class BuildFolder {
  const BuildFolder({required this.path, required this.bytes, this.files = 0});

  factory BuildFolder.fromJson(Map<String, dynamic> json) => BuildFolder(
    path: json['path'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    files: (json['files'] as num?)?.toInt() ?? 0,
  );

  /// Desde la raíz del repositorio: `.didacta-build`.
  final String path;
  final int bytes;
  final int files;

  bool get isEmpty => files == 0;

  /// «440,7 MB».
  String get size {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final number = unit == 0
        ? '${value.round()}'
        : value.toStringAsFixed(1).replaceAll('.', ',');
    return '$number ${units[unit]}';
  }
}

/// Un sitio de un fichero fuente: lo que dice SyncTeX de un punto del PDF.
class SourceSpot {
  const SourceSpot({
    required this.file,
    required this.line,
    this.path,
    this.unit,
    this.language,
  });

  factory SourceSpot.fromJson(Map<String, dynamic> json) => SourceSpot(
    file: json['file'] as String? ?? '',
    line: (json['line'] as num?)?.toInt() ?? 1,
    path: json['path'] as String?,
    unit: json['unit'] as String?,
    language: json['language'] as String?,
  );

  /// La ruta entera, como la leyó LaTeX.
  final String file;
  final int line;

  /// Desde la raíz del repositorio, si es suyo.
  final String? path;

  /// La lección y el idioma, si es el `.tex` de una.
  final String? unit;
  final String? language;
}
