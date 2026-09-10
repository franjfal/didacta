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
  });

  final String id;

  /// El nombre en castellano: «Diapositivas», «Libro», «Apuntes (profesor)».
  final String label;

  /// `slides`, `notes`, `problems`, `handout`, `exam`.
  final String family;

  /// Si es una de las que se miran primero: las dos que se pidieron
  /// --presentación y libro-- más los apuntes, que son la prosa por defecto.
  bool get isPrimary => id == 'slides' || id == 'book' || id == 'notes';
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
  }) => platform.makeCompiler(
    enginePath: enginePath,
    repositoryPath: repositoryPath,
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
