/// Que el motor vaya con la versión de la aplicación.
///
/// El motor --`cli/`, `engine/` y `latex/`-- se clonaba de `main` una vez y
/// no se movía nunca: ningún arreglo de LaTeX le llegaba a quien ya lo
/// tenía, y una aplicación nueva podía pedirle opciones que ese motor no
/// conocía. Ahora el clon que instala Didacta se pone en la etiqueta de su
/// misma versión, `v0.2.1`, y al actualizar la aplicación se mueve a la
/// nueva.
///
/// **Solo el que instaló Didacta**, que lo marca. Una copia de desarrollo
/// --la de quien trabaja en Didacta, que suele ser también su motor-- no se
/// toca sola: se dice qué versión es, y moverla es un botón que se pulsa a
/// sabiendas. Y ninguna con cambios sin guardar.
library;

import '../model/app_version.dart';
import 'engine_pin_stub.dart'
    if (dart.library.io) 'engine_pin_io.dart'
    as platform;

/// Lo que se sabe del motor frente a la aplicación.
class EngineVersion {
  const EngineVersion({
    required this.app,
    this.engine,
    this.commit,
    this.managed = false,
    this.blocked,
    this.problem,
  });

  /// La versión de la aplicación.
  final AppVersion app;

  /// La del motor: la etiqueta en la que está su clon. Null si no está en
  /// ninguna, que es una copia de desarrollo.
  final AppVersion? engine;

  /// Su commit, para decir cuál es cuando no hay versión.
  final String? commit;

  /// Si lo instaló Didacta, y por tanto lo mueve ella sola.
  final bool managed;

  /// Por qué no se puede mover: no es un clon de git, tiene cambios sin
  /// guardar. Null si se puede.
  final String? blocked;

  /// Lo que falló la última vez que se intentó moverlo.
  final String? problem;

  /// Una aplicación sin versión --una prueba, `0.0.0`-- no pide ninguna.
  bool get appKnown => app > const AppVersion(0, 0, 0);

  /// Si es el de esta versión.
  bool get matches => engine != null && engine!.compareTo(app) == 0;

  /// Si se puede poner en la versión de la aplicación.
  bool get canPin => appKnown && !matches && blocked == null;

  EngineVersion failed(String why) => EngineVersion(
    app: app,
    engine: engine,
    commit: commit,
    managed: managed,
    blocked: blocked,
    problem: why,
  );
}

/// Lo que hay en [engine], frente a [app].
Future<EngineVersion> inspectEngine(String engine, AppVersion app) =>
    platform.inspectEngine(engine, app);

/// Pone el clon de [engine] en la etiqueta de [app]: la trae de GitHub y
/// la saca. Lanza [EnginePinException] si no se puede.
Future<void> pinEngine(String engine, AppVersion app) =>
    platform.pinEngine(engine, app);

/// Marca el clon como instalado por Didacta: a partir de ahí lo mueve sola.
Future<void> markManaged(String engine) => platform.markManaged(engine);

class EnginePinException implements Exception {
  const EnginePinException(this.message);

  final String message;

  @override
  String toString() => message;
}
