/// El motor y TeX: dónde están, de qué versión es el motor y cómo se instala.
///
/// Era una parte de la sesión. Aparte porque tiene su propio estado --las dos
/// rutas y lo que se sabe de la versión del motor-- y de la sesión solo
/// necesita las preferencias, dónde se clona, el primer repositorio (el motor
/// suele estar al lado) y la credencial para descargarlo. Se avisa sola: que
/// se acabe de comprobar la versión del motor le interesa a Ajustes, no a la
/// biblioteca. Lo que cambia qué se puede compilar --encontrar el motor o
/// perderlo-- avisa también a la sesión, que es de donde las pantallas sacan
/// el compilador.
///
/// Construir el compilador y la lista de herramientas se queda en la sesión:
/// son los puntos que las pruebas sustituyen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_info.dart';
import '../data/compiler.dart';
import '../data/diagnostics.dart';
import '../data/engine_pin.dart';
import '../data/local_clone.dart';
import '../model/app_version.dart';
import 'session.dart';
import '../l10n/tr.dart';

class EngineService extends ChangeNotifier {
  EngineService(this.session, {required this.onPathChanged});

  final Session session;

  /// Avisar a la sesión de que ha cambiado con qué se compila.
  final VoidCallback onPathChanged;

  String? _enginePath;

  /// La carpeta `bin` de TeX, si se ha tenido que decir a mano. Casi siempre
  /// null: se busca en los sitios de siempre.
  String? _texPath;

  /// Dónde está el repositorio del motor, para compilar.
  String? get enginePath => _enginePath;

  /// Dónde está TeX, si se ha tenido que decir a mano.
  String? get texPath => _texPath;

  void _setEngine(String? path) {
    if (path == _enginePath) return;
    _enginePath = path;
    notifyListeners();
    onPathChanged();
  }

  /// Lee la ruta de TeX guardada.
  Future<void> restore() async {
    _texPath = await session.preferences.texPath();
  }

  Future<void> setTexPath(String? path) async {
    await session.preferences.setTexPath(path);
    _texPath = path == null || path.isEmpty ? null : path;
    notifyListeners();
    onPathChanged();
  }

  /// Busca el motor y lo recuerda, sin que no encontrarlo pare nada: la
  /// pantalla de compilar lo dice.
  Future<void> find() async {
    if (!Compiler.supported) return;
    String? found;
    try {
      found = await Compiler.discover(
        configured: await session.preferences.enginePath(),
        repositoryPath: session.primaryPath,
      );
    } catch (error) {
      found = null;
    }
    _setEngine(found);
    // Sin esperar: mirar la versión es preguntarle a git, y moverlo, ir a
    // GitHub. Nada de eso tiene que retrasar la primera pantalla.
    if (_enginePath != null) unawaited(checkVersion());
  }

  /// Busca el motor y lo recuerda; lo que falle, sale.
  ///
  /// Se llama después de conocer el clon, porque el sitio más probable para
  /// el motor es al lado.
  Future<void> findOrThrow() async {
    final found = await Compiler.discover(
      configured: await session.preferences.enginePath(),
      repositoryPath: session.primaryPath,
    );
    _setEngine(found);
  }

  /// El motor frente a la aplicación: si es el de su versión.
  EngineVersion? get version => _version;
  EngineVersion? _version;

  /// Mira la versión del motor y, si lo instaló Didacta y no es el de esta
  /// versión, lo pone en ella. Ver `data/engine_pin.dart`.
  Future<void> checkVersion() async {
    final engine = _enginePath;
    if (engine == null || !LocalClone.supported) return;
    try {
      final app = (await AppInfo.load()).version;
      var found = await inspectEngine(engine, app);
      if (found.managed && found.canPin) {
        try {
          await pinEngine(engine, app);
          found = await inspectEngine(engine, app);
        } on EnginePinException catch (error) {
          // Sin red, o sin esa versión en GitHub: se sigue con el que hay y
          // Ajustes lo dice.
          found = found.failed(error.message);
        }
      }
      if (_enginePath != engine) return;
      _version = found;
      notifyListeners();
    } catch (caught, trace) {
      Diagnostics.instance.note('session.checkEngineVersion', caught, trace);
      // Mirar la versión no puede romper nada: sin respuesta, no se dice.
    }
  }

  /// Poner el motor en la versión de la aplicación, a petición: lo que hace
  /// el botón de Ajustes con un motor que no instaló Didacta. A partir de
  /// ahí queda marcado, y lo mueve ella sola al actualizar.
  Future<void> pinNow() async {
    final engine = _enginePath;
    if (engine == null) return;
    final app = (await AppInfo.load()).version;
    await pinEngine(engine, app);
    await markManaged(engine);
    await checkVersion();
  }

  /// Clona el motor --el repositorio de Didacta-- al lado de los de
  /// contenido. Ver [Session.installEngine].
  Future<String> install({
    required String owner,
    required String repo,
    void Function(String line)? onProgress,
  }) async {
    if (!LocalClone.supported) {
      throw CloneException(tr('Aquí no se puede clonar nada.'));
    }
    final cloneBase = session.cloneBase;
    final base = cloneBase.isEmpty ? '.' : cloneBase;
    final where = '$base/$repo';

    final existing = LocalClone(directory: where);
    if (!await existing.looksRight(owner: owner, repo: repo)) {
      // El de la versión de esta aplicación, y no `main`: lo que hay en
      // `main` puede ir por delante de lo que esta aplicación sabe pedirle.
      // Si esa versión no está publicada --una compilación de desarrollo--,
      // `main`.
      final app = (await AppInfo.load()).version;
      final token = await session.currentToken();
      try {
        await LocalClone.create(
          directory: where,
          owner: owner,
          repo: repo,
          branch: app > const AppVersion(0, 0, 0) ? app.tag : 'main',
          token: token,
          onProgress: onProgress,
        );
      } on CloneException {
        if (app <= const AppVersion(0, 0, 0)) rethrow;
        await LocalClone.create(
          directory: where,
          owner: owner,
          repo: repo,
          branch: 'main',
          token: token,
          onProgress: onProgress,
        );
      }
      // Lo instaló Didacta: lo mueve ella a la versión nueva al actualizar.
      await markManaged(where);
    }

    await session.preferences.setEnginePath(where);
    _setEngine(where);
    unawaited(checkVersion());
    return where;
  }
}
