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
  /// Olvida todo lo guardado aquí, como si Didacta se acabara de instalar.
  ///
  /// Es lo que hace «Restablecer». Sólo lo de este fichero: el token y las
  /// claves de traducción están en el llavero, y las carpetas en el disco,
  /// y cada cosa se borra desde donde vive.
  Future<void> clearAll();

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

  /// Si guardar un fichero lo deja confirmado, sin preguntar.
  ///
  /// Puesto de salida. Lo que quiere casi todo el mundo es escribir y
  /// olvidarse: un commit por guardado da un historial fino pero utilizable,
  /// y el paso de «ahora escribe un mensaje» se salta treinta veces al día.
  /// Quien prefiera decidir qué contar lo apaga y confirma a mano.
  Future<bool> commitOnSave();
  Future<void> setCommitOnSave(bool value);

  /// Si guardar enseña el diff y pide el mensaje antes, o guarda con el
  /// mensaje propuesto y deja el diff detrás de «Ver cambios».
  ///
  /// Apagado de salida: para corregir una errata, un diálogo que se acepta
  /// sin leer treinta veces al día no revisa nada. Quien sí quiere mirar cada
  /// cambio antes de que quede en el historial lo enciende.
  Future<bool> reviewBeforeSave();
  Future<void> setReviewBeforeSave(bool value);

  /// Si la interfaz enseña todo (Completa) o lo de todos los días
  /// (Esencial). Esencial de salida: rutas, contadores y la sangría de un
  /// fichero son de quien mantiene el repositorio, y a quien corrige una
  /// errata le llenan la pantalla.
  Future<bool> completeInterface();
  Future<void> setCompleteInterface(bool value);

  /// Las últimas lecciones abiertas, `repositorio|ruta`, la más reciente
  /// primero. De esta máquina: lo que se abrió en el despacho no es lo que
  /// se quiere a mano en el aula.
  Future<List<String>> recentUnits();
  Future<void> setRecentUnits(List<String> value);

  /// Las búsquedas de la biblioteca guardadas con nombre, en JSON (ver
  /// `SavedSearch`).
  Future<String?> savedSearches();
  Future<void> setSavedSearches(String value);

  /// Cuántas salidas de un documento compilar a la vez. 0 es «lo que diga el
  /// motor»: la mitad de los núcleos y no más de cuatro.
  Future<int> buildJobs();
  Future<void> setBuildJobs(int value);

  /// Si avisar de las líneas que se salen por la derecha en los apuntes y lo
  /// demás que no son diapositivas. Apagado de salida.
  Future<bool> overfullLines();
  Future<void> setOverfullLines(bool value);

  /// PDF accesibles: lo que no son diapositivas, etiquetado y con LuaLaTeX
  /// (`didacta build --accessible`). Apagado de salida: compila más despacio.
  Future<bool> accessiblePdf();
  Future<void> setAccessiblePdf(bool value);

  /// La vista rápida: compilar un documento desde su panel en una sola
  /// pasada. Apagado de salida.
  Future<bool> quickBuild();
  Future<void> setQuickBuild(bool value);

  /// Un aviso del sistema al terminar de compilar, si Didacta no está
  /// delante. Apagado de salida.
  Future<bool> notifyWhenBuilt();
  Future<void> setNotifyWhenBuilt(bool value);

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

  /// Si se reciben también las versiones de prueba. Apagado de salida.
  Future<bool> testVersions();
  Future<void> setTestVersions(bool value);
  Future<void> setPendingUpdate(String? version);

  /// Las preferencias que viajan entre ordenadores, tal como se guardaron.
  ///
  /// Aquí también, y no solo en el repositorio: esta copia es la que hace que
  /// abran plegados los temas que plegaste, sin red y antes de que el
  /// repositorio conteste. El repositorio es donde se sincronizan; esto es la
  /// última versión que se vio.
  Future<String?> syncedPrefs();
  Future<void> setSyncedPrefs(String value);

  /// Si la presentación de bienvenida ya se ha visto.
  ///
  /// Separado del tour, y no un solo interruptor, porque son dos cosas que se
  /// quieren por separado: la presentación se ve una vez y nunca más, y el
  /// tour se vuelve a lanzar cuando alguien se pierde o cuando llega una
  /// pantalla nueva.
  Future<bool> welcomeDone();
  Future<void> setWelcomeDone(bool value);

  /// Si el tour guiado ya se ha hecho.
  Future<bool> tourDone();
  Future<void> setTourDone(bool value);

  /// Claro, oscuro o lo que diga el sistema: `light`, `dark` o `system`.
  ///
  /// De esta máquina y no de las que viajan: la pantalla del despacho y la
  /// del portátil en el aula no tienen por qué querer lo mismo.
  Future<String> appearance();
  Future<void> setAppearance(String value);

  /// Cuánto más grande o más pequeño se ve el texto: 1 es el normal.
  ///
  /// De esta máquina, por lo mismo que [appearance]: el proyector del aula
  /// pide más que la pantalla del despacho.
  Future<double> textScale();
  Future<void> setTextScale(double value);

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

  /// La carpeta a la que se exportó por última vez una asignatura.
  ///
  /// Por asignatura, porque cada una va a su sitio --el aula virtual de
  /// Análisis no es la de Álgebra-- y de esta máquina, porque es una ruta:
  /// no viaja con las preferencias sincronizadas.
  Future<String?> exportFolder(String courseId);
  Future<void> setExportFolder(String courseId, String path);

  /// La carpeta de reparto: una que sincroniza OneDrive, Drive o Nextcloud,
  /// donde «Publicar» deja lo de cada curso. Null si no se usa, que es lo de
  /// salida. De esta máquina, como toda ruta.
  Future<String?> publishFolder();
  Future<void> setPublishFolder(String? path);
}

class StoredPreferences implements Preferences {
  const StoredPreferences({
    this.defaultClonePath = '',
    this.defaultEnginePath = '',
    this.defaultClientId = '',
    this.replacedClientIds = const [],
  });

  /// El Client ID que traiga la compilación, si trae alguno. Lo que se haya
  /// guardado manda por encima.
  final String defaultClientId;

  /// Client ID guardados que ya no se usan: los que se guardaron al entrar
  /// cuando eran el de salida. Leídos, valen [defaultClientId]. Es lo que hace
  /// que quien entró con la OAuth App de Didacta entre con su GitHub App la
  /// próxima vez, sin tocar Ajustes; un Client ID propio no está aquí y se
  /// respeta.
  final List<String> replacedClientIds;

  /// Where the clone is when nothing has been chosen yet.
  ///
  /// A build-time default, so a desktop build can be handed to someone who
  /// already has the repository on disk and have it work on first launch
  /// instead of starting on the Ajustes screen.
  final String defaultClonePath;

  /// Igual, para el motor.
  final String defaultEnginePath;

  /// El prefijo de todas las claves de Didacta.
  static const String _prefix = 'didacta.';

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
  static const String _welcome = 'didacta.welcome.done';
  static const String _tour = 'didacta.tour.done';
  static const String _appearance = 'didacta.appearance';
  static const String _textScale = 'didacta.textScale';
  static const String _mcp = 'didacta.mcp.enabled';
  static const String _commitOnSave = 'didacta.clone.commitOnSave';
  static const String _review = 'didacta.save.review';
  static const String _complete = 'didacta.interface.complete';
  static const String _recent = 'didacta.library.recent';
  static const String _searches = 'didacta.library.searches';
  static const String _jobs = 'didacta.build.jobs';
  static const String _overfullLines = 'didacta.build.overfullLines';
  static const String _accessiblePdf = 'didacta.build.accessiblePdf';
  static const String _testVersions = 'didacta.updates.tests';
  static const String _quickBuild = 'didacta.build.quick';
  static const String _notifyWhenBuilt = 'didacta.build.notify';
  static const String _mcpWritable = 'didacta.mcp.writable';
  static const String _exportFolder = 'didacta.export.folder.';
  static const String _publishFolder = 'didacta.publish.folder';

  /// Las claves de Didacta, y ninguna más: `clear()` se llevaría también lo
  /// que guardara cualquier otro plugin en el mismo fichero.
  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_prefix)) await prefs.remove(key);
    }
  }

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
  Future<bool> commitOnSave() async =>
      (await SharedPreferences.getInstance()).getBool(_commitOnSave) ?? true;

  @override
  Future<void> setCommitOnSave(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_commitOnSave, value);

  @override
  Future<bool> reviewBeforeSave() async =>
      (await SharedPreferences.getInstance()).getBool(_review) ?? false;

  @override
  Future<void> setReviewBeforeSave(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_review, value);

  @override
  Future<bool> completeInterface() async =>
      (await SharedPreferences.getInstance()).getBool(_complete) ?? false;

  @override
  Future<void> setCompleteInterface(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_complete, value);

  @override
  Future<List<String>> recentUnits() async =>
      (await SharedPreferences.getInstance()).getStringList(_recent) ??
      const [];

  @override
  Future<void> setRecentUnits(List<String> value) async =>
      (await SharedPreferences.getInstance()).setStringList(_recent, value);

  @override
  Future<String?> savedSearches() async =>
      (await SharedPreferences.getInstance()).getString(_searches);

  @override
  Future<void> setSavedSearches(String value) async =>
      (await SharedPreferences.getInstance()).setString(_searches, value);

  @override
  Future<int> buildJobs() async =>
      (await SharedPreferences.getInstance()).getInt(_jobs) ?? 0;

  @override
  Future<void> setBuildJobs(int value) async =>
      (await SharedPreferences.getInstance()).setInt(_jobs, value);

  @override
  Future<bool> overfullLines() async =>
      (await SharedPreferences.getInstance()).getBool(_overfullLines) ?? false;

  @override
  Future<bool> testVersions() async =>
      (await SharedPreferences.getInstance()).getBool(_testVersions) ?? false;

  @override
  Future<void> setTestVersions(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_testVersions, value);

  @override
  Future<void> setOverfullLines(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_overfullLines, value);

  @override
  Future<bool> accessiblePdf() async =>
      (await SharedPreferences.getInstance()).getBool(_accessiblePdf) ?? false;

  @override
  Future<void> setAccessiblePdf(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_accessiblePdf, value);

  @override
  Future<bool> quickBuild() async =>
      (await SharedPreferences.getInstance()).getBool(_quickBuild) ?? false;

  @override
  Future<void> setQuickBuild(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_quickBuild, value);

  @override
  Future<bool> notifyWhenBuilt() async =>
      (await SharedPreferences.getInstance()).getBool(_notifyWhenBuilt) ??
      false;

  @override
  Future<void> setNotifyWhenBuilt(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_notifyWhenBuilt, value);

  @override
  Future<String?> exportFolder(String courseId) async =>
      (await SharedPreferences.getInstance()).getString(
        '$_exportFolder$courseId',
      );

  @override
  Future<void> setExportFolder(String courseId, String path) async =>
      (await SharedPreferences.getInstance()).setString(
        '$_exportFolder$courseId',
        path,
      );

  @override
  Future<String?> publishFolder() async =>
      (await SharedPreferences.getInstance()).getString(_publishFolder);

  @override
  Future<void> setPublishFolder(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_publishFolder);
    } else {
      await prefs.setString(_publishFolder, path);
    }
  }

  @override
  Future<bool> mcpEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_mcp) ?? false;

  @override
  Future<void> setMcpEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_mcp, value);

  @override
  Future<bool> welcomeDone() async =>
      (await SharedPreferences.getInstance()).getBool(_welcome) ?? false;

  @override
  Future<void> setWelcomeDone(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_welcome, value);

  @override
  Future<bool> tourDone() async =>
      (await SharedPreferences.getInstance()).getBool(_tour) ?? false;

  @override
  Future<void> setTourDone(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_tour, value);

  @override
  Future<String> appearance() async =>
      (await SharedPreferences.getInstance()).getString(_appearance) ??
      'system';

  @override
  Future<void> setAppearance(String value) async =>
      (await SharedPreferences.getInstance()).setString(_appearance, value);

  @override
  Future<double> textScale() async =>
      (await SharedPreferences.getInstance()).getDouble(_textScale) ?? 1;

  @override
  Future<void> setTextScale(double value) async =>
      (await SharedPreferences.getInstance()).setDouble(_textScale, value);

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
  Future<String?> githubClientId() async {
    final stored = (await SharedPreferences.getInstance()).getString(_clientId);
    if (stored != null && !replacedClientIds.contains(stored)) return stored;
    return defaultClientId.isEmpty ? null : defaultClientId;
  }

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

  /// Si se llamó a [clearAll].
  bool cleared = false;

  /// Lo que una prueba de «Restablecer» mira: que no quede nada que diga
  /// quién era ni qué tenía abierto, y que la bienvenida vuelva.
  @override
  Future<void> clearAll() async {
    cleared = true;
    path = null;
    engine = null;
    repos = null;
    base = null;
    githubUserJson = null;
    welcome = false;
    tour = false;
  }

  bool commit = true;
  bool mcp = false;

  /// Las carpetas de exportar, por asignatura.
  final Map<String, String> exportFolders = {};

  @override
  Future<String?> exportFolder(String courseId) async =>
      exportFolders[courseId];

  @override
  Future<void> setExportFolder(String courseId, String path) async =>
      exportFolders[courseId] = path;

  String? publish;

  @override
  Future<String?> publishFolder() async => publish;

  @override
  Future<void> setPublishFolder(String? path) async =>
      publish = path == null || path.isEmpty ? null : path;

  @override
  Future<bool> commitOnSave() async => commit;

  @override
  Future<void> setCommitOnSave(bool value) async => commit = value;

  bool review = false;

  @override
  Future<bool> reviewBeforeSave() async => review;

  @override
  Future<void> setReviewBeforeSave(bool value) async => review = value;

  bool complete = false;

  @override
  Future<bool> completeInterface() async => complete;

  @override
  Future<void> setCompleteInterface(bool value) async => complete = value;

  List<String> recent = const [];

  @override
  Future<List<String>> recentUnits() async => recent;

  @override
  Future<void> setRecentUnits(List<String> value) async => recent = value;

  String? searches;

  @override
  Future<String?> savedSearches() async => searches;

  @override
  Future<void> setSavedSearches(String value) async => searches = value;

  int jobs = 0;

  @override
  Future<int> buildJobs() async => jobs;

  @override
  Future<void> setBuildJobs(int value) async => jobs = value;

  bool overfull = false;

  bool tests = false;

  @override
  Future<bool> testVersions() async => tests;

  @override
  Future<void> setTestVersions(bool value) async => tests = value;

  @override
  Future<bool> overfullLines() async => overfull;

  @override
  Future<void> setOverfullLines(bool value) async => overfull = value;

  bool accessible = false;

  @override
  Future<bool> accessiblePdf() async => accessible;

  @override
  Future<void> setAccessiblePdf(bool value) async => accessible = value;

  bool quick = false;

  @override
  Future<bool> quickBuild() async => quick;

  @override
  Future<void> setQuickBuild(bool value) async => quick = value;

  bool notify = false;

  @override
  Future<bool> notifyWhenBuilt() async => notify;

  @override
  Future<void> setNotifyWhenBuilt(bool value) async => notify = value;
  List<String> mcpWrite = const [];

  /// Vista, por defecto: casi ningún test va de la bienvenida, y los que sí
  /// van la ponen a `false` y lo dicen.
  bool welcome = true;
  bool tour = true;

  @override
  Future<bool> welcomeDone() async => welcome;

  @override
  Future<void> setWelcomeDone(bool value) async => welcome = value;

  @override
  Future<bool> tourDone() async => tour;

  @override
  Future<void> setTourDone(bool value) async => tour = value;

  String look = 'system';

  @override
  Future<String> appearance() async => look;

  @override
  Future<void> setAppearance(String value) async => look = value;

  double scale = 1;

  @override
  Future<double> textScale() async => scale;

  @override
  Future<void> setTextScale(double value) async => scale = value;

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
