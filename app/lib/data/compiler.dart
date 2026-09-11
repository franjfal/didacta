/// Compilar una unidad desde la aplicación.
///
/// La pregunta que responde es la que se hace editando: «¿cómo queda esto?»,
/// en diapositivas y en libro, sin salir de la unidad. Lo hace el motor
/// --`didacta preview`--, no la aplicación: el preámbulo, los 14 perfiles y
/// el parseo del log de LaTeX ya existen y están probados, y una segunda
/// implementación en Dart sería una segunda cosa que se desincroniza.
///
/// **Solo en escritorio.** Compilar necesita LaTeX y un navegador no lo
/// tiene. La pantalla lo dice en lugar de fingirlo: un botón que no puede
/// funcionar es peor que su ausencia explicada.
library;

import 'compiler_stub.dart' if (dart.library.io) 'compiler_io.dart' as platform;

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
    this.byDefault = false,
  });

  final String id;

  /// El nombre en castellano: «Diapositivas», «Libro», «Apuntes (profesor)».
  final String label;

  /// `slides`, `notes`, `problems`, `handout`, `exam`.
  final String family;

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

  bool get usable => exists && !stale;

  /// Si es una de las que se miran primero.
  bool get isPrimary =>
      profile == 'slides' || profile == 'book' || profile == 'notes';
}

/// El resultado de compilar una unidad en un perfil y un idioma.
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
  });

  final String profile;
  final String language;
  final bool ok;

  /// La ruta del PDF, o null si no salió.
  final String? pdf;

  final int pages;
  final double seconds;

  /// Los diagnósticos del log, ya parseados por el motor: fichero, línea y
  /// mensaje. Se muestran tal cual porque el motor ya sabe a quién culpar.
  final List<String> errors;
  final List<String> warnings;
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
  factory Compiler({
    required String enginePath,
    required String repositoryPath,
    String? texPath,
  }) => platform.makeCompiler(
    enginePath: enginePath,
    repositoryPath: repositoryPath,
    texPath: texPath,
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
  Future<List<CompileOutput>> compile({
    required String unitPath,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
  });

  /// Las versiones en las que se puede compilar un **documento entero**.
  ///
  /// [document] es la referencia que usa el motor, `curso@año/documento`.
  ///
  /// Todas las de su familia y no solo las que el documento declara en
  /// `year.yaml`: el mismo tema se quiere en libro un día y en diapositivas
  /// otro, y eso no puede obligar a editar el fichero. Las suyas vienen
  /// marcadas, que es lo que se preselecciona.
  Future<List<BuildableProfile>> documentProfiles(String document);

  /// Compila un documento entero. Un resultado por versión y por idioma.
  Future<List<CompileOutput>> compileDocument({
    required String document,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
  });

  /// Lanza el motor con los argumentos que se le den, y devuelve su salida.
  ///
  /// Está aquí porque esto ya es «lo que sabe lanzar el motor»: encontrar
  /// `cli/didacta`, comprobar que está, ejecutarlo desde el clon y limpiar
  /// el token de lo que se enseñe. Tener un segundo objeto para lanzar otras
  /// órdenes sería tener dos sitios donde arreglar el mismo problema.
  Future<String> run(List<String> arguments, {bool allowFailure = false});

  /// Abre el PDF en el visor del sistema.
  ///
  /// En lugar de incrustar un visor: el del sistema tiene zoom, navegación y
  /// pantalla completa, que para repasar unas diapositivas es exactamente lo
  /// que hace falta, y no añade una dependencia de renderizado de PDF a una
  /// aplicación cuyo trabajo es editar LaTeX.
  Future<void> open(String pdf);

  /// Lo enseña en el Finder, para arrastrarlo a un correo.
  Future<void> reveal(String pdf);
}
