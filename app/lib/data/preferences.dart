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
  /// Los repositorios abiertos, serializados.
  ///
  /// Aquí y no en el llavero: es una lista de rutas y de colores, no un
  /// secreto. El token sí es un secreto y vive aparte.
  Future<String?> workspace();
  Future<void> setWorkspace(String value);

  /// El Client ID de la OAuth App con la que se entra en GitHub.
  ///
  /// Configurable y no compilado dentro: es público por definición --una
  /// aplicación de escritorio no puede esconderlo-- y así se puede cambiar la
  /// aplicación de OAuth sin volver a compilar.
  Future<String?> githubClientId();
  Future<void> setGithubClientId(String value);

  /// Quién entró en GitHub la última vez, serializado.
  ///
  /// Existe para una sola situación, y es la normal: **abrir Didacta sin
  /// red**. Quien ha entrado tiene el token en el llavero, pero preguntarle a
  /// GitHub quién es no se puede, y sin esto la aplicación no sabría el
  /// nombre con el que firmar los commits ni a quién saludar.
  ///
  /// No es un secreto --es el nombre público de una cuenta-- así que no va al
  /// llavero. El token sí, y sigue donde estaba.
  Future<String?> githubUser();
  Future<void> setGithubUser(String? value);

  /// Dónde se clonan los repositorios nuevos.
  Future<String?> cloneBase();
  Future<void> setCloneBase(String path);

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

  /// Cuándo se miró por última vez si hay una versión nueva.
  ///
  /// Aquí y no en el llavero: es una fecha, no una credencial. Y guardada y
  /// no en memoria, que es lo que hace que la comprobación sea cada siete
  /// días de verdad y no cada vez que se abre la aplicación.
  Future<DateTime?> lastUpdateCheck();
  Future<void> setLastUpdateCheck(DateTime when);

  /// La versión a la que se estaba actualizando cuando se cerró.
  ///
  /// Se apunta **antes** de cerrar y se borra al arrancar. Es la única forma
  /// de saber si la sustitución salió: quien la hace es un script externo, y
  /// para cuando termina, la aplicación que lo lanzó ya no existe para
  /// enterarse. Al volver a arrancar, si la versión no es la apuntada, la
  /// actualización falló y hay que decirlo en vez de dejar a alguien creyendo
  /// que tiene una versión que no tiene.
  Future<String?> pendingUpdate();
  Future<void> setPendingUpdate(String? version);

  /// Las preferencias que viajan entre ordenadores, tal como se guardaron.
  ///
  /// Aquí también, y no solo en el repositorio: esta copia es la que hace que
  /// abran plegados los temas que plegaste, sin red y antes de que el
  /// repositorio conteste. El repositorio es donde se sincronizan; esto es la
  /// última versión que se vio.
  Future<String?> syncedPrefs();
  Future<void> setSyncedPrefs(String value);

  /// Si el servidor MCP está encendido.
  ///
  /// Apagado de salida, y eso no es prudencia de más: encendido, un modelo
  /// puede escribir en los repositorios de quien lo enciende. Es una decisión
  /// que se toma, no una que se hereda de una instalación.
  Future<bool> mcpEnabled();
  Future<void> setMcpEnabled(bool value);

  /// En qué repositorios puede escribir el servidor MCP, por su id.
  ///
  /// Vacío quiere decir «en ninguno»: enciende en solo lectura, que es lo que
  /// hace falta para preguntar y no para estropear nada.
  Future<List<String>> mcpWritable();
  Future<void> setMcpWritable(List<String> repos);

  /// En qué repositorio se guardan, si en alguno.
  ///
  /// Se elige porque no hay uno evidente: cada persona tiene los suyos y no
  /// coinciden. Sin elegir ninguno, las preferencias se quedan en esta
  /// máquina, que es lo que hacían todas hasta ahora.
  Future<String?> prefsRepo();
  Future<void> setPrefsRepo(String? repo);
}

class StoredPreferences implements Preferences {
  const StoredPreferences({
    this.defaultClonePath = '',
    this.defaultEnginePath = '',
    this.defaultClientId = '',
  });

  /// El Client ID que traiga la compilación, si trae alguno. Lo que se haya
  /// guardado manda por encima.
  final String defaultClientId;

  /// Where the clone is when nothing has been chosen yet.
  ///
  /// A build-time default, so a desktop build can be handed to someone who
  /// already has the repository on disk and have it work on first launch
  /// instead of starting on the Ajustes screen.
  final String defaultClonePath;

  /// Igual, para el motor.
  final String defaultEnginePath;

  static const String _workspace = 'didacta.workspace';
  static const String _clientId = 'didacta.github.clientId';
  static const String _githubUser = 'didacta.github.user';
  static const String _cloneBase = 'didacta.clone.base';
  static const String _clone = 'didacta.clone.path';
  static const String _push = 'didacta.clone.push';
  static const String _engine = 'didacta.engine.path';
  static const String _tex = 'didacta.tex.path';
  static const String _preview = 'didacta.preview.profile';
  static const String _panel = 'didacta.unit.panel';
  static const String _split = 'didacta.unit.split';
  static const String _checked = 'didacta.update.lastCheck';
  static const String _pending = 'didacta.update.pending';
  static const String _synced = 'didacta.synced.prefs';
  static const String _prefsRepo = 'didacta.synced.repo';
  static const String _mcp = 'didacta.mcp.enabled';
  static const String _mcpWritable = 'didacta.mcp.writable';

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
  Future<bool> mcpEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_mcp) ?? false;

  @override
  Future<void> setMcpEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_mcp, value);

  @override
  Future<List<String>> mcpWritable() async =>
      (await SharedPreferences.getInstance()).getStringList(_mcpWritable) ??
      const [];

  @override
  Future<void> setMcpWritable(List<String> repos) async =>
      (await SharedPreferences.getInstance()).setStringList(
        _mcpWritable,
        repos,
      );

  @override
  Future<String?> workspace() async =>
      (await SharedPreferences.getInstance()).getString(_workspace);

  @override
  Future<void> setWorkspace(String value) async =>
      (await SharedPreferences.getInstance()).setString(_workspace, value);

  @override
  Future<String?> githubClientId() async =>
      (await SharedPreferences.getInstance()).getString(_clientId) ??
      (defaultClientId.isEmpty ? null : defaultClientId);

  @override
  Future<String?> githubUser() async =>
      (await SharedPreferences.getInstance()).getString(_githubUser);

  @override
  Future<void> setGithubUser(String? value) async {
    final store = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await store.remove(_githubUser);
    } else {
      await store.setString(_githubUser, value);
    }
  }

  @override
  Future<void> setGithubClientId(String value) async =>
      (await SharedPreferences.getInstance()).setString(_clientId, value);

  @override
  Future<String?> cloneBase() async =>
      (await SharedPreferences.getInstance()).getString(_cloneBase);

  @override
  Future<void> setCloneBase(String path) async =>
      (await SharedPreferences.getInstance()).setString(_cloneBase, path);

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

  /// Guardada en UTC y como texto ISO: un entero de milisegundos es ilegible
  /// al mirar las preferencias, y la zona horaria importa aquí lo justo.
  @override
  Future<DateTime?> lastUpdateCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_checked);
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  @override
  Future<void> setLastUpdateCheck(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checked, when.toUtc().toIso8601String());
  }

  @override
  Future<String?> pendingUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_pending);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> setPendingUpdate(String? version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version == null) {
      await prefs.remove(_pending);
    } else {
      await prefs.setString(_pending, version);
    }
  }

  @override
  Future<String?> syncedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_synced);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> setSyncedPrefs(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_synced, value);
  }

  @override
  Future<String?> prefsRepo() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsRepo);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> setPrefsRepo(String? repo) async {
    final prefs = await SharedPreferences.getInstance();
    if (repo == null || repo.isEmpty) {
      await prefs.remove(_prefsRepo);
    } else {
      await prefs.setString(_prefsRepo, repo);
    }
  }
}

/// For tests, and for a platform where nothing is remembered.
class MemoryPreferences implements Preferences {
  MemoryPreferences({
    this.path,
    this.engine,
    this.push = true,
    this.repos,
    this.clientId,
    this.base,
    this.githubUserJson,
  });

  String? path;
  String? engine;
  bool push;
  String? repos;
  String? clientId;
  String? base;
  String? githubUserJson;

  bool mcp = false;
  List<String> mcpWrite = const [];

  @override
  Future<bool> mcpEnabled() async => mcp;

  @override
  Future<void> setMcpEnabled(bool value) async => mcp = value;

  @override
  Future<List<String>> mcpWritable() async => mcpWrite;

  @override
  Future<void> setMcpWritable(List<String> value) async => mcpWrite = value;

  @override
  Future<String?> workspace() async => repos;

  @override
  Future<void> setWorkspace(String value) async => repos = value;

  @override
  Future<String?> githubClientId() async => clientId;

  @override
  Future<void> setGithubClientId(String value) async => clientId = value;

  @override
  Future<String?> githubUser() async => githubUserJson;

  @override
  Future<void> setGithubUser(String? value) async => githubUserJson = value;

  @override
  Future<String?> cloneBase() async => base;

  @override
  Future<void> setCloneBase(String value) async => base = value;

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

  DateTime? checked;

  @override
  Future<DateTime?> lastUpdateCheck() async => checked;

  @override
  Future<void> setLastUpdateCheck(DateTime when) async => checked = when;

  String? pending;

  @override
  Future<String?> pendingUpdate() async => pending;

  @override
  Future<void> setPendingUpdate(String? version) async => pending = version;

  String? synced;

  @override
  Future<String?> syncedPrefs() async => synced;

  @override
  Future<void> setSyncedPrefs(String value) async => synced = value;

  String? prefsRepoId;

  @override
  Future<String?> prefsRepo() async => prefsRepoId;

  @override
  Future<void> setPrefsRepo(String? repo) async => prefsRepoId = repo;
}
