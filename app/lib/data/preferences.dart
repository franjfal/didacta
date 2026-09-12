/// The small non-secret settings: where the clone is, and whether to push.
///
/// Separate from [SecretStore] on purpose. A token belongs in the keychain
/// because it is a credential; a folder path does not, and putting it there
/// would mean every read of a path prompts for keychain access on some
/// systems. The distinction is worth keeping visible.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// What the app remembers between runs, other than secrets.
abstract class Preferences {
  Future<String?> clonePath();
  Future<void> setClonePath(String? path);

  Future<bool> pushOnCommit();
  Future<void> setPushOnCommit(bool value);

  /// Si el panel de la derecha de una unidad está desplegado.
  ///
  /// Guardado y no un estado de la pantalla: es una decisión sobre el sitio
  /// de trabajo --cuánto ancho quiero para el texto-- y se toma una vez, no
  /// cada vez que se abre una unidad.
  Future<bool> unitPanelVisible();
  Future<void> setUnitPanelVisible(bool value);

  /// Si los idiomas de una unidad se editan lado a lado.
  Future<bool> splitEditors();
  Future<void> setSplitEditors(bool value);

  /// Dónde está el repositorio del motor: el que tiene `cli/didacta`.
  ///
  /// Hace falta para compilar, y no se puede deducir del clon de contenido:
  /// son dos repositorios, y el de la aplicación no viaja dentro del `.app`.
  Future<String?> enginePath();

  /// La carpeta `bin` de TeX, cuando no está en ninguno de los sitios de
  /// siempre.
  ///
  /// Normalmente vacía: se busca. Está para la instalación en un sitio raro,
  /// que es el caso que no se puede adivinar.
  Future<String?> texPath();
  Future<void> setTexPath(String? path);

  /// La versión que se abre al ojear una unidad desde la biblioteca.
  Future<String?> previewProfile();
  Future<void> setPreviewProfile(String id);
  Future<void> setEnginePath(String? path);
}

class StoredPreferences implements Preferences {
  const StoredPreferences({
    this.defaultClonePath = '',
    this.defaultEnginePath = '',
  });

  /// Where the clone is when nothing has been chosen yet.
  ///
  /// A build-time default, so a desktop build can be handed to someone who
  /// already has the repository on disk and have it work on first launch
  /// instead of starting on the Ajustes screen.
  final String defaultClonePath;

  /// Igual, para el motor.
  final String defaultEnginePath;

  static const String _clone = 'didacta.clone.path';
  static const String _push = 'didacta.clone.push';
  static const String _engine = 'didacta.engine.path';
  static const String _tex = 'didacta.tex.path';
  static const String _preview = 'didacta.preview.profile';
  static const String _panel = 'didacta.unit.panel';
  static const String _split = 'didacta.unit.split';

  /// The stored value, then the build-time default. A stored empty string is
  /// a real answer -- "I turned the clone off" -- and must win over the
  /// default, which is why [setClonePath] stores it rather than removing it.
  @override
  Future<String?> clonePath() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_clone)) {
      final value = prefs.getString(_clone);
      return (value == null || value.isEmpty) ? null : value;
    }
    return defaultClonePath.isEmpty ? null : defaultClonePath;
  }

  @override
  Future<void> setClonePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    // Stored empty rather than removed, so "stop using the clone" is not
    // undone by the build-time default on the next launch.
    await prefs.setString(_clone, path ?? '');
  }

  /// Defaults to true: a commit nobody else can see is not traceable, which
  /// is the whole point of committing.
  @override
  Future<bool> pushOnCommit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_push) ?? true;
  }

  @override
  Future<void> setPushOnCommit(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_push, value);
  }

  @override
  Future<bool> unitPanelVisible() async {
    final prefs = await SharedPreferences.getInstance();
    // Desplegado por defecto: lo que dice --dónde se usa esta unidad-- es la
    // respuesta a «¿puedo cambiar esto?», y esconderlo de entrada dejaría a
    // alguien editando sin saberlo.
    return prefs.getBool(_panel) ?? true;
  }

  @override
  Future<void> setUnitPanelVisible(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_panel, value);
  }

  @override
  Future<bool> splitEditors() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_split) ?? false;
  }

  @override
  Future<void> setSplitEditors(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_split, value);
  }

  @override
  Future<String?> enginePath() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_engine)) {
      final value = prefs.getString(_engine);
      return (value == null || value.isEmpty) ? null : value;
    }
    return defaultEnginePath.isEmpty ? null : defaultEnginePath;
  }

  @override
  Future<void> setEnginePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_engine, path ?? '');
  }

  @override
  Future<String?> texPath() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_tex);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> setTexPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tex, path ?? '');
  }

  @override
  Future<String?> previewProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_preview);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> setPreviewProfile(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preview, id);
  }
}

/// For tests, and for a platform where nothing is remembered.
class MemoryPreferences implements Preferences {
  MemoryPreferences({this.path, this.engine, this.push = true});

  String? path;
  String? engine;
  bool push;

  @override
  Future<String?> enginePath() async => engine;

  @override
  Future<void> setEnginePath(String? value) async => engine = value;

  String? tex;

  @override
  Future<String?> texPath() async => tex;

  @override
  Future<void> setTexPath(String? value) async => tex = value;

  String? preview;

  @override
  Future<String?> previewProfile() async => preview;

  @override
  Future<void> setPreviewProfile(String id) async => preview = id;

  bool panel = true;
  bool split = false;

  @override
  Future<bool> unitPanelVisible() async => panel;

  @override
  Future<void> setUnitPanelVisible(bool value) async => panel = value;

  @override
  Future<bool> splitEditors() async => split;

  @override
  Future<void> setSplitEditors(bool value) async => split = value;

  @override
  Future<String?> clonePath() async => path;

  @override
  Future<void> setClonePath(String? value) async => path = value;

  @override
  Future<bool> pushOnCommit() async => push;

  @override
  Future<void> setPushOnCommit(bool value) async => push = value;
}
