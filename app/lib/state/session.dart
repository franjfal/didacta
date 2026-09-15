/// The one object that knows the state of the world.
///
/// Holds the catalogue, who is signed in, and which gateway is in play. Every
/// screen reads it and nothing else holds any of it, which is what stops the
/// interface from ever showing a sidebar that disagrees with a list, or an
/// editor that thinks it can save when it cannot.
///
/// It is a `ChangeNotifier` rather than anything larger on purpose. The state
/// here is small -- a catalogue, an authorisation, a gateway -- and the
/// interesting complexity of this app is in the LaTeX and the migration, not
/// in its state management. A store with actions and reducers would be
/// machinery around three fields.
///
/// One rule it enforces: **the gateway is derived, never set.** It is
/// recomputed from the auth state and the stored token every time either
/// changes, so there is no way to be signed out and still holding a writable
/// gateway.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/catalogue_source.dart';
import '../data/secrets.dart';
import '../data/compiler.dart';
import '../data/content_gateway.dart';
import '../data/course_admin.dart';
import '../data/disk_watch.dart';
import '../data/github.dart';
import '../data/local_clone.dart';
import '../data/preferences.dart';
import '../model/catalogue.dart';
import '../model/workspace.dart';
import 'history.dart';

/// Where the app is in bringing itself up.
enum LoadState { loading, ready, failed }

/// Lo que un repositorio tiene esperando para enviarse a GitHub.
class RepoOutbox {
  const RepoOutbox({
    required this.repo,
    required this.ahead,
    required this.pending,
  });

  final ContentRepo repo;

  /// Commits hechos aquí que GitHub no tiene.
  final int ahead;

  /// Ficheros escritos y todavía sin commit.
  final List<String> pending;

  bool get isEmpty => ahead == 0 && pending.isEmpty;
}

class Session extends ChangeNotifier {
  Session({
    required this.catalogueSource,
    required this.tokenStore,
    Preferences? preferences,
  }) : preferences = preferences ?? MemoryPreferences();

  final CatalogueSource catalogueSource;

  /// Por dónde se ha pasado, para los botones de atrás y adelante.
  ///
  /// Aquí y no en un proveedor aparte porque es estado de la aplicación como
  /// el idioma que se está mirando, y porque toda pantalla ya tiene la
  /// sesión a mano.
  final NavigationHistory history = NavigationHistory();

  /// Donde vive el token de GitHub: el llavero del sistema.
  final SecretStore tokenStore;

  /// Where the clone is, and whether a commit is pushed. Not secrets, so not
  /// in the keychain.
  final Preferences preferences;

  LoadState _state = LoadState.loading;
  LoadState get state => _state;

  Object? _error;
  Object? get error => _error;

  Catalogue? _catalogue;

  /// Throws if read before [state] is ready. Callers inside the shell are
  /// past that point by construction, and an optional catalogue would put a
  /// null check in every screen for a state none of them can see.
  Catalogue get catalogue => _catalogue!;
  Catalogue? get catalogueOrNull => _catalogue;

  /// Los repositorios abiertos, en orden.
  Workspace _workspace = const Workspace.empty();
  Workspace get workspace => _workspace;

  /// Una pasarela por repositorio. Cada fichero es de uno y de uno solo.
  final Map<String, ContentGateway> _gateways = {};

  /// La del primer repositorio, para lo que no tiene uno en la mano.
  ContentGateway get gateway =>
      _gateways.isEmpty ? const UnconfiguredGateway() : _gateways.values.first;

  /// La del repositorio de un fichero.
  ///
  /// Es la pieza que hace posible trabajar con varios a la vez: cada pantalla
  /// tiene en la mano la unidad o el documento que está tocando, y de ahí sale
  /// a qué clon va lo que escriba.
  ContentGateway gatewayFor(String? repo) {
    if (repo == null || repo.isEmpty) return gateway;
    return _gateways[repo] ??
        UnconfiguredGateway('No está abierto el repositorio $repo.');
  }

  /// Si se puede escribir en el repositorio de un fichero.
  bool canWriteIn(String? repo) => gatewayFor(repo).canWrite;

  GitHubUser? _user;

  /// Quién ha entrado en GitHub, si alguien lo ha hecho.
  GitHubUser? get user => _user;

  bool get signedIn => _user != null;

  String? _token;
  bool _pushOnCommit = true;

  /// Si hay un token de GitHub guardado en esta máquina.
  bool get hasStoredToken => _token?.isNotEmpty ?? false;

  /// Whether storing one is even possible here. False on the web.
  bool get canStoreToken => tokenStore.canStoreSafely;

  String _clientId = '';

  /// El Client ID de la OAuth App con la que se entra.
  String get githubClientId => _clientId;

  String _cloneBase = '';

  /// Dónde se clonan los repositorios nuevos.
  String get cloneBase => _cloneBase;

  /// Whether a clone is possible at all here. False on the web.
  bool get canUseClone => LocalClone.supported;

  /// Cómo está cada clon respecto a GitHub, por repositorio.
  final Map<String, CloneStatus> _cloneStatus = {};

  CloneStatus? statusOf(String repo) => _cloneStatus[repo];

  /// Lo que falló al abrir cada repositorio, por si alguno no abre.
  final Map<String, Object> _repoProblems = {};

  Object? problemOf(String repo) => _repoProblems[repo];

  ({String name, String email})? _cloneAuthor;

  /// Who the clone's commits will be attributed to.
  ({String name, String email})? get cloneAuthor => _cloneAuthor;

  /// Las carpetas de los clones abiertos.
  List<String> get repoPaths => [
    for (final repo in _workspace.repos) repo.directory,
  ];

  /// El primero: lo que mira quien necesita **un** clon --vigilar el disco,
  /// compilar por defecto-- y no todos.
  String? get _primaryPath =>
      _workspace.repos.isEmpty ? null : _workspace.repos.first.directory;

  /// El clon de un repositorio, para compilar contra su raíz.
  String? pathOf(String? repo) => repo == null || repo.isEmpty
      ? _primaryPath
      : _workspace.directoryOf(repo);

  bool _unitPanel = true;

  /// Si el panel de la derecha de una unidad está desplegado.
  bool get unitPanelVisible => _unitPanel;

  bool _split = false;

  /// Si los idiomas de una unidad se editan lado a lado.
  bool get splitEditors => _split;

  Future<void> setUnitPanelVisible(bool value) async {
    if (_unitPanel == value) return;
    _unitPanel = value;
    notifyListeners();
    await preferences.setUnitPanelVisible(value);
  }

  Future<void> setSplitEditors(bool value) async {
    if (_split == value) return;
    _split = value;
    notifyListeners();
    await preferences.setSplitEditors(value);
  }

  String? _enginePath;

  /// La carpeta `bin` de TeX, si se ha tenido que decir a mano. Casi siempre
  /// null: se busca en los sitios de siempre.
  String? _texPath;

  /// Where the engine repository is, for compiling.
  String? get enginePath => _enginePath;

  /// Whether compiling is possible on this platform at all. False on the
  /// web, which has no LaTeX and no way to run a process that does.
  bool get canCompile => Compiler.supported;

  /// The compiler, or null when there is nothing to compile with -- no
  /// engine, no clone, or a browser.
  ///
  /// Built fresh rather than held: it is a thin wrapper over a process, and
  /// caching it would mean caching a stale engine path.
  Compiler? compiler({String? repo}) {
    if (!Compiler.supported) return null;
    final engine = _enginePath;
    final clone = pathOf(repo);
    if (engine == null || clone == null) return null;
    return Compiler(
      enginePath: engine,
      repositoryPath: clone,
      texPath: _texPath,
    );
  }

  /// Dónde está TeX, si se ha tenido que decir a mano.
  String? get texPath => _texPath;

  /// Cuándo se escribió el índice que está cargado.
  ///
  /// Es lo que permite saber que el de disco es otro: la comprobación de
  /// arranque compara el índice con el contenido, y eso no ve que el índice
  /// haya cambiado **después** de leerlo --que es lo que pasa cuando alguien
  /// lo regenera desde el terminal con la aplicación abierta--.
  DateTime? _indexRead;

  StreamSubscription<void>? _watching;
  StreamSubscription<void>? _watchingContent;
  Timer? _settle;
  Timer? _settleContent;

  /// Empieza a vigilar `generated/` del clon.
  ///
  /// Idempotente: llamarlo dos veces no deja dos vigilantes.
  void watchDisk() {
    final path = _primaryPath;
    if (path == null) return;
    _watching?.cancel();
    // El material. Editar un `.tex` en otro programa, copiar una figura o
    // traerse cien ficheros con un `git pull` son la misma cosa desde aquí:
    // el disco ya no es lo que el índice dice. Con más respiro que el índice
    // --un `pull` son cientos de eventos seguidos-- y sin forzar nada: se
    // pregunta si hace falta, que cuesta una décima, y solo se regenera si
    // la respuesta es que sí.
    _watchingContent?.cancel();
    _watchingContent = watchContent(path).listen((_) {
      _settleContent?.cancel();
      _settleContent = Timer(const Duration(seconds: 2), () {
        unawaited(_rescan());
      });
    });

    _watching = watchIndex(path).listen((_) {
      // Con un respiro: el motor escribe cuatro ficheros, y recargar el
      // catálogo cuatro veces por una regeneración es tirar el trabajo tres
      // veces.
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 400), () {
        unawaited(_reloadIfIndexChanged());
      });
    });
  }

  /// Vuelve a mirar el disco: si el índice se ha quedado corto, lo regenera.
  Future<void> _rescan() async {
    if (await refreshIndex()) {
      await reloadCatalogue();
      await refreshBuilt();
      final path = _primaryPath;
      if (path != null) _indexRead = await indexModified(path);
    }
  }

  /// Al volver a la ventana: ¿ha cambiado algo mientras no mirábamos?
  ///
  /// Dos `stat` y, si el índice está viejo respecto al contenido, una
  /// regeneración. Es el momento exacto en que alguien vuelve después de
  /// tocar ficheros por fuera.
  Future<void> checkDisk() async {
    if (await _reloadIfIndexChanged()) return;
    if (await refreshIndex()) await reloadCatalogue();

    // Desde aquí, el disco avisa solo.
    final path = _primaryPath;
    if (path != null) {
      _indexRead = await indexModified(path);
      watchDisk();
    }
  }

  /// Relee el catálogo si el índice del disco es más nuevo que el cargado.
  Future<bool> _reloadIfIndexChanged() async {
    final path = _primaryPath;
    if (path == null) return false;
    final when = await indexModified(path);
    if (when == null) return false;
    if (_indexRead != null && !when.isAfter(_indexRead!)) return false;
    _indexRead = when;
    await reloadCatalogue();
    await refreshBuilt();
    return true;
  }

  /// Lo que pasó con el índice la última vez que se miró.
  ///
  /// Null cuando no había nada que decir. Se enseña porque regenerarlo
  /// cambia lo que la biblioteca lista, y un cambio así no puede ocurrir en
  /// silencio: quien acaba de mover una carpeta tiene que ver que la
  /// aplicación se ha enterado.
  String? get indexNote => _indexNote;
  String? _indexNote;

  void dismissIndexNote() {
    _indexNote = null;
    notifyListeners();
  }

  /// Si el índice sigue describiendo el disco; si no, lo regenera.
  ///
  /// [force] lo regenera igual, que es lo que hace el botón de actualizar:
  /// pedirlo a mano significa «ponlo como está el disco», no «mira a ver».
  ///
  /// Devuelve si lo regeneró, que es cuando hay que volver a leerlo.
  Future<bool> refreshIndex({bool force = false}) async {
    var any = false;
    for (final repo in _workspace.repos) {
      if (await _refreshIndexOf(repo.id, force: force)) any = true;
    }
    if (_workspace.isEmpty) return _refreshIndexOf(null, force: force);
    return any;
  }

  /// El índice de un repositorio. Cada uno tiene el suyo, escrito por el
  /// motor en su carpeta, y se comprueba por separado.
  Future<bool> _refreshIndexOf(String? repo, {bool force = false}) async {
    final compiler = this.compiler(repo: repo);
    if (compiler == null) return false;
    try {
      final why = force
          ? (stale: true, reason: 'a mano')
          : await compiler.indexStale();
      if (!why.stale) return false;
      await compiler.reindex();
      _indexNote = force
          ? 'Índice actualizado.'
          : 'El índice no describía lo que hay en el disco '
                '(${why.reason}), así que se ha regenerado.';
      notifyListeners();
      return true;
    } catch (error) {
      // No poder regenerarlo no puede impedir arrancar: se lee el que hay y
      // se dice que puede no corresponder.
      _indexNote =
          'El índice puede estar desactualizado y no se ha podido '
          'regenerar: $error';
      notifyListeners();
      return false;
    }
  }

  /// Qué dijo GitHub la última vez que se preguntó.
  ///
  /// Null cuando no se ha preguntado o no hay a quién preguntar. Es la
  /// segunda mitad de «actualizar»: lo de este disco ya está al día, pero
  /// puede haber trabajo de otra persona --o del mismo, desde otra máquina--
  /// esperando en el repositorio.
  int? get behind {
    if (_cloneStatus.isEmpty) return null;
    var most = 0;
    for (final status in _cloneStatus.values) {
      if (status.behind > most) most = status.behind;
    }
    return most;
  }

  /// Cuántos commits hay sin enviar, sumando los repositorios.
  int get ahead {
    var total = 0;
    for (final status in _cloneStatus.values) {
      total += status.ahead;
    }
    return total;
  }

  /// Los ficheros tocados fuera de la aplicación, por repositorio.
  Map<String, List<String>> get pendingChanges => {
    for (final entry in _cloneStatus.entries)
      if (entry.value.dirtyPaths.isNotEmpty) entry.key: entry.value.dirtyPaths,
  };

  /// Pregunta a GitHub si hay algo nuevo, sin traerlo.
  ///
  /// Traerlo es otra decisión: un `pull` cambia los ficheros de debajo de
  /// quien está editando, y eso no se hace sin decirlo. Aquí solo se mira.
  Future<int> checkRemote() async {
    if (_workspace.isEmpty) return 0;
    try {
      final token = await tokenStore.read() ?? '';
      for (final repo in _workspace.repos) {
        final clone = cloneAt(repo.directory);
        await clone.fetch(token: token);
        _cloneStatus[repo.id] = await clone.status();
      }
      notifyListeners();
      return behind ?? 0;
    } catch (error) {
      // Sin red, sin token o sin remoto: lo local sigue valiendo, y decirlo
      // como un error pararía un refresco que ya ha hecho su trabajo.
      _remoteProblem = error;
      notifyListeners();
      return 0;
    }
  }

  /// Por qué no se pudo preguntar a GitHub, si no se pudo.
  Object? get remoteProblem => _remoteProblem;
  Object? _remoteProblem;

  /// El botón de actualizar: el índice, el catálogo y lo compilado.
  @override
  void dispose() {
    _settle?.cancel();
    _settleContent?.cancel();
    _watching?.cancel();
    _watchingContent?.cancel();
    super.dispose();
  }

  Future<void> refreshEverything() async {
    // Buscar el motor solo si no hay: encontrarlo es mirar el disco, y
    // hacerlo cuando ya tenemos uno es trabajo por nada.
    if (compiler() == null) await _findEngine();
    _remoteProblem = null;
    await refreshIndex(force: true);
    await reloadCatalogue();
    await refreshBuilt();
    final primary = _primaryPath;
    if (primary != null) _indexRead = await indexModified(primary);
    // Y lo de fuera. Al final y no al principio: lo de este disco es lo que
    // se está mirando ahora mismo, y la red puede tardar.
    await checkRemote();
  }

  /// Busca el motor y lo recuerda.
  Future<void> _findEngine() async {
    if (!Compiler.supported) return;
    try {
      _enginePath = await Compiler.discover(
        configured: await preferences.enginePath(),
        repositoryPath: _primaryPath,
      );
    } catch (error) {
      // No encontrarlo no para nada: la pantalla de compilar lo dice.
      _enginePath = null;
    }
  }

  /// Qué hay compilado, por unidad.
  ///
  /// En la sesión y no en la pantalla porque la pregunta la hace la
  /// biblioteca --¿cuáles puedo ojear?-- y la respuesta vale para toda la
  /// aplicación: compilar una unidad la cambia, y la lista tiene que
  /// enterarse sin volver a preguntarle al motor por las dos mil.
  Map<String, List<ExistingOutput>> get built => _built;
  Map<String, List<ExistingOutput>> _built = const {};

  /// Si ya se ha preguntado. Distinto de «no hay nada compilado».
  bool get builtKnown => _builtKnown;
  bool _builtKnown = false;

  /// La versión que se abre al ojear una unidad desde la biblioteca.
  ///
  /// Una sola y elegida arriba, no una por unidad: quien prepara una clase
  /// está mirando diapositivas toda la tarde, y elegirlo en cada tarjeta
  /// sería el mismo clic dos mil veces.
  String get previewProfile => _previewProfile;
  String _previewProfile = 'slides';

  Future<void> setPreviewProfile(String id) async {
    _previewProfile = id;
    notifyListeners();
    await preferences.setPreviewProfile(id);
  }

  /// El clon en un directorio.
  ///
  /// Un solo sitio donde se construye, para que un test pueda dar otro sin
  /// que la sesión tenga que saber que está en un test.
  @visibleForTesting
  LocalClone cloneAt(String directory) => LocalClone(directory: directory);

  /// Para un test: el clon, sin pasar por Ajustes ni por el disco.
  @visibleForTesting
  Future<void> useCloneForTest(String path) async {
    _workspace = Workspace([
      ContentRepo(owner: 'test', name: 'repo', directory: path),
    ]);
  }

  /// Para un test: lo compilado, sin motor que lo diga.
  @visibleForTesting
  Future<void> setBuiltForTest(Map<String, List<ExistingOutput>> built) async {
    _built = built;
    _builtKnown = true;
    notifyListeners();
  }

  /// Vuelve a preguntar qué hay compilado.
  ///
  /// Silencioso a propósito: no saberlo quita un atajo, no una pantalla, y
  /// un error aquí no puede impedir listar la biblioteca.
  Future<void> refreshBuilt() async {
    final compiler = this.compiler();
    if (compiler == null) {
      _builtKnown = true;
      return;
    }
    try {
      _built = await compiler.builtOutputs();
    } catch (error) {
      _built = const {};
    }
    _builtKnown = true;
    notifyListeners();
  }

  Future<void> setTexPath(String? path) async {
    await preferences.setTexPath(path);
    _texPath = path == null || path.isEmpty ? null : path;
    notifyListeners();
  }

  /// Crear, duplicar y borrar asignaturas y años.
  ///
  /// Null cuando no se puede: hace falta el clon --para escribir y para
  /// hacer el commit-- y el motor, que es el que sabe hacer cada operación.
  /// La pantalla lo dice en lugar de ofrecer botones que no funcionan.
  CourseAdmin? admin({String? repo}) {
    final compiler = this.compiler(repo: repo);
    final path = pathOf(repo);
    if (compiler == null || path == null) return null;
    return CourseAdmin(
      compiler: compiler,
      clone: LocalClone(directory: path),
      author: _cloneAuthor,
      token: _token ?? '',
      pushOnCommit: _pushOnCommit,
    );
  }

  /// Looks for the engine and remembers it.
  ///
  /// Called after the clone is known, because the likeliest place for the
  /// engine is next to it.
  Future<void> findEngine() async {
    final found = await Compiler.discover(
      configured: await preferences.enginePath(),
      repositoryPath: _primaryPath,
    );
    if (found != _enginePath) {
      _enginePath = found;
      notifyListeners();
    }
  }

  Future<void> setEnginePath(String? path) async {
    await preferences.setEnginePath(path);
    await refreshAccess();
  }

  /// The language the interface is working in. Not a locale -- the app's own
  /// text is Spanish -- but which language of the *content* is being looked
  /// at, which is the choice that actually matters here.
  String _language = 'es';
  String get language => _language;

  set language(String code) {
    if (_language == code) return;
    _language = code;
    notifyListeners();
  }

  /// Brings up the catalogue and works out how content can be reached.
  ///
  /// **The catalogue is the only thing that can stop this.** Everything else
  /// here -- a stored preference, a keychain, a clone, GitHub --
  /// is allowed to fail, and each failure is recorded and shown rather than
  /// thrown. That is not defensiveness: this is called from `initState`
  /// without an `await`, so anything that escapes becomes an unhandled async
  /// error, and an unhandled error before the first frame is a black window
  /// with the reason in a log nobody reads. It has happened twice.
  Future<void> start() async {
    _state = LoadState.loading;
    notifyListeners();

    // The clone is looked up first because it changes where the catalogue is
    // read from: inside a clone, the index on disk is the one that matches
    // the files the editor writes, and fetching a different copy over HTTP
    // would let the library disagree with the editor.
    try {
      _workspace = Workspace.fromJson(await preferences.workspace() ?? '');
      _clientId = await preferences.githubClientId() ?? '';
      _cloneBase = await preferences.cloneBase() ?? '';
      _texPath = await preferences.texPath();
      _previewProfile = await preferences.previewProfile() ?? _previewProfile;
      _unitPanel = await preferences.unitPanelVisible();
      _split = await preferences.splitEditors();
    } catch (error) {
      // A setting that cannot be read is a setting that is not set.
      _workspace = const Workspace.empty();
      _settingsProblem = error;
    }

    try {
      _catalogue = await _source.load();
      _language = _catalogue!.defaultLanguage;
      _state = LoadState.ready;
    } catch (error) {
      // Sin repositorios abiertos, que no se pueda leer un catálogo **no es
      // un error**: es una instalación recién puesta y todavía no se le ha
      // dicho con qué trabajar. Antes caía en el catálogo por HTTP que traía
      // la compilación, que en escritorio no resuelve, y la primera pantalla
      // era «No se pudo cargar el catálogo» con una dirección relativa y un
      // botón que ya no llevaba a ninguna parte.
      if (_workspace.isEmpty && LocalClone.supported) {
        _catalogue = Catalogue.merge(const []);
        _language = _catalogue!.defaultLanguage;
        _state = LoadState.ready;
        notifyListeners();
        return;
      }
      _error = error;
      _state = LoadState.failed;
      notifyListeners();
      return;
    }

    // Painted before access is resolved. The library needs none of what
    // follows, and making the reader wait for a keychain -- or lose the
    // screen to it -- is the wrong trade.
    notifyListeners();

    // Y ahora los repositorios: mirar el estado de cada clon, quién ha
    // entrado y dónde está el motor. Después de pintar a propósito, que es
    // hablar con git y con la red.
    await refreshAccess();

    // El índice, después de pintar.
    //
    // Es un fichero generado que describe el disco, y el disco cambia entre
    // arranques: mover `content/` a otro sitio deja un índice que habla de
    // dos mil unidades que ya no están, y la biblioteca las enseñaba tan
    // contenta. Preguntar cuesta una décima --el motor cuenta ficheros, no
    // los abre-- y solo se regenera cuando hace falta.
    //
    // Después y no antes a propósito: buscar el motor y hablar con él es
    // lanzar procesos, y ponerlo delante de la primera pantalla haría que un
    // motor lento o ausente retrasara el arranque entero. Así la biblioteca
    // aparece con lo que había y se corrige sola un segundo después, con el
    // aviso diciendo qué ha cambiado.
    if (await refreshIndex()) await reloadCatalogue();
  }

  Object? _settingsProblem;

  /// Why the stored settings could not be read, if they could not be.
  Object? get settingsProblem => _settingsProblem;

  Object? _accessProblem;

  /// Why working out how to reach the content failed, if it did.
  ///
  /// Kept and shown in Ajustes. The app is usable without it -- reading the
  /// public catalogue needs no access at all -- so this is a degraded state
  /// and not a broken one.
  Object? get accessProblem => _accessProblem;

  /// Recomputes the authorisation and the gateway from scratch.
  ///
  /// Called on every auth change and after a token is stored or cleared.
  /// Deriving rather than mutating is what guarantees the two cannot drift.
  /// Vuelve a abrir los repositorios y a recalcular sus pasarelas.
  ///
  /// Se llama después de entrar, de salir, de añadir o quitar uno, y al
  /// arrancar. Derivar en lugar de ir tocando estados sueltos es lo que
  /// garantiza que no pueda quedar una pasarela que escribe en un repositorio
  /// que ya no está abierto.
  Future<void> refreshAccess() async {
    try {
      await _openRepositories();
      _accessProblem = null;
    } catch (error) {
      _accessProblem = error;
    }
    notifyListeners();
  }

  /// Abre cada repositorio del espacio de trabajo: su clon y su pasarela.
  Future<void> _openRepositories() async {
    _token = await tokenStore.read();
    _pushOnCommit = await preferences.pushOnCommit();
    _gateways.clear();
    _cloneStatus.clear();
    _repoProblems.clear();

    if (_token != null && _token!.isNotEmpty && _user == null) {
      try {
        _user = await GitHubApi(token: _token!).me();
      } catch (_) {
        // Un token que ya no vale no puede impedir leer lo que hay en disco.
      }
    }

    // El autor de los commits: quien ha entrado en GitHub. Sin sesión, lo que
    // git tenga configurado en la máquina, que es lo que hace que un clon
    // propio no necesite entrar en ningún sitio para escribir en él.
    final signedIn = _user;
    _cloneAuthor = signedIn == null
        ? null
        : (name: signedIn.authorName, email: signedIn.authorEmail);

    for (final repo in _workspace.repos) {
      if (!LocalClone.supported) continue;
      try {
        final clone = LocalClone(directory: repo.directory);
        if (!await clone.looksRight(owner: repo.owner, repo: repo.name)) {
          throw CloneException(
            '${repo.directory} no es un clon de ${repo.id}. '
            'Quítalo y vuelve a añadirlo.',
          );
        }
        _cloneStatus[repo.id] = await clone.status();
        _cloneAuthor ??= await clone.configuredAuthor();
        _gateways[repo.id] = CloneGateway(
          clone: clone,
          token: _token ?? '',
          author: _cloneAuthor,
          pushOnCommit: _pushOnCommit,
        );
      } catch (thrown) {
        // Uno que no abre no puede llevarse por delante a los demás: quien
        // tenga el otro tiene que poder trabajar con él.
        _repoProblems[repo.id] = thrown;
      }
    }

    if (compiler() == null) await _findEngine();
  }

  Future<void> storeToken(String token) async {
    await tokenStore.write(token);
    await refreshAccess();
  }

  Future<void> clearToken() async {
    await tokenStore.clear();
    await refreshAccess();
  }

  /// Uses an existing clone at [path], or stops using one when null.
  Future<void> useClone(String? path) async {
    await preferences.setClonePath(path);
    await refreshAccess();
  }

  Future<void> setPushOnCommit(bool value) async {
    await preferences.setPushOnCommit(value);
    await refreshAccess();
  }

  /// Sets who the clone's commits are attributed to, for this clone only.
  Future<void> setCloneAuthor({
    required String name,
    required String email,
  }) async {
    for (final repo in _workspace.repos) {
      await LocalClone(
        directory: repo.directory,
      ).setAuthor(name: name, email: email);
    }
    await refreshAccess();
  }

  // -- los repositorios ---------------------------------------------------

  /// Guarda el Client ID de la OAuth App con la que se entra.
  Future<void> setGithubClientId(String value) async {
    _clientId = value.trim();
    await preferences.setGithubClientId(_clientId);
    notifyListeners();
  }

  /// Dónde se clonan los repositorios nuevos.
  Future<void> setCloneBase(String path) async {
    _cloneBase = path;
    await preferences.setCloneBase(path);
    notifyListeners();
  }

  /// Guarda el token de GitHub y mira quién es.
  Future<void> signIn(String token) async {
    await tokenStore.write(token);
    _token = token;
    try {
      _user = await GitHubApi(token: token).me();
    } catch (thrown) {
      _accessProblem = thrown;
    }
    await refreshAccess();
  }

  /// Sale de GitHub. Los clones se quedan: son carpetas de esta máquina con
  /// el trabajo dentro, y borrarlas al salir sería perderlo.
  Future<void> signOut() async {
    await tokenStore.clear();
    _token = null;
    _user = null;
    await refreshAccess();
  }

  /// Añade un repositorio al espacio de trabajo, clonándolo si hace falta.
  ///
  /// Cada uno en su carpeta, con su color. Devuelve el que ha quedado abierto.
  Future<ContentRepo> addRepository({
    required String owner,
    required String name,
    required String branch,
    String? directory,
    int? colour,
    void Function(String line)? onProgress,
  }) async {
    final where = directory ?? '$_cloneBase/$name';
    final token = _token ?? await tokenStore.read() ?? '';

    if (LocalClone.supported) {
      final existing = LocalClone(directory: where);
      final already = await existing.looksRight(owner: owner, repo: name);
      if (!already) {
        await LocalClone.create(
          directory: where,
          owner: owner,
          repo: name,
          branch: branch,
          token: token,
          onProgress: onProgress,
        );
      }
    }

    final repo = ContentRepo(
      owner: owner,
      name: name,
      directory: where,
      branch: branch,
      colour: colour ?? _workspace.nextColour(),
    );
    _workspace = _workspace.with_(repo);
    await preferences.setWorkspace(_workspace.toJson());
    await refreshAccess();
    await reloadCatalogue();
    return repo;
  }

  /// Añade una carpeta que ya está en el disco.
  ///
  /// De qué repositorio es lo dice su propio remoto, así que esto funciona
  /// sin entrar en GitHub: un clon que ya tenías sigue siendo tuyo. Es también
  /// el camino de vuelta para quien tenía la aplicación de antes, cuando había
  /// un solo clon configurado en Ajustes.
  Future<ContentRepo> addExistingRepository(String directory) async {
    final clone = LocalClone(directory: directory);
    final remote = await clone.remoteUrl();
    final found = repoFromRemote(remote);
    if (found == null) {
      throw CloneException(
        '$directory no es un clon de git con remoto. Clónalo desde GitHub '
        'o elige otra carpeta.',
      );
    }
    final repo = ContentRepo(
      owner: found.owner,
      name: found.name,
      directory: directory,
      branch: (await clone.status()).branch,
      colour: _workspace.nextColour(),
    );
    _workspace = _workspace.with_(repo);
    await preferences.setWorkspace(_workspace.toJson());
    await refreshAccess();
    await reloadCatalogue();
    return repo;
  }

  /// Si todavía no hay ningún repositorio con el que trabajar.
  bool get needsRepository => _workspace.isEmpty;

  /// Lo quita del espacio de trabajo. La carpeta se queda donde está: lleva
  /// trabajo dentro y borrarla no es cosa de un botón de esta lista.
  Future<void> removeRepository(String id) async {
    _workspace = _workspace.without(id);
    await preferences.setWorkspace(_workspace.toJson());
    await refreshAccess();
    await reloadCatalogue();
  }

  /// Cambia el color con el que se marca un repositorio en la interfaz.
  Future<void> setRepositoryColour(String id, int colour) async {
    _workspace = _workspace.recoloured(id, colour);
    await preferences.setWorkspace(_workspace.toJson());
    notifyListeners();
  }

  /// Trae de GitHub lo que haya en todos los repositorios.
  ///
  /// Devuelve cuántos commits se han traído, por repositorio. Uno que falle
  /// no para a los demás: se cuenta y se sigue.
  Future<Map<String, Object>> pullAll() async {
    final result = <String, Object>{};
    final token = _token ?? await tokenStore.read() ?? '';
    for (final repo in _workspace.repos) {
      try {
        final clone = cloneAt(repo.directory);
        final before = await clone.status();
        await clone.pull(token: token);
        final after = await clone.status();
        result[repo.id] = before.head == after.head ? 0 : (before.behind);
      } catch (thrown) {
        result[repo.id] = thrown;
      }
    }
    await refreshAccess();
    if (await refreshIndex()) {
      await reloadCatalogue();
    } else {
      await reloadCatalogue();
    }
    return result;
  }

  /// Lo que se enviaría: por repositorio, lo que está sin guardar y lo que
  /// está guardado y sin enviar.
  Future<List<RepoOutbox>> outbox() async {
    final boxes = <RepoOutbox>[];
    for (final repo in _workspace.repos) {
      try {
        final status = await cloneAt(repo.directory).status();
        _cloneStatus[repo.id] = status;
        if (status.ahead == 0 && status.dirtyPaths.isEmpty) continue;
        boxes.add(
          RepoOutbox(
            repo: repo,
            ahead: status.ahead,
            pending: status.dirtyPaths,
          ),
        );
      } catch (_) {
        // Un repositorio que no se puede leer no tiene nada que enviar.
      }
    }
    return boxes;
  }

  /// Envía a GitHub: cierra en un commit lo que quedara suelto y empuja.
  ///
  /// El mensaje es uno para todos porque el gesto es uno: se estaba
  /// trabajando en algo, y ese algo tocó ficheros de varios repositorios.
  Future<Map<String, Object>> pushAll(String message) async {
    final result = <String, Object>{};
    final token = _token ?? await tokenStore.read() ?? '';
    final author = _cloneAuthor;
    for (final box in await outbox()) {
      try {
        final clone = cloneAt(box.repo.directory);
        if (box.pending.isNotEmpty && author != null) {
          await clone.commitPaths(
            paths: box.pending,
            message: message,
            authorName: author.name,
            authorEmail: author.email,
            token: token,
            push: false,
          );
        }
        await clone.push(token: token);
        result[box.repo.id] = box.ahead + (box.pending.isEmpty ? 0 : 1);
      } catch (thrown) {
        result[box.repo.id] = thrown;
      }
    }
    await refreshAccess();
    return result;
  }

  /// Installs a catalogue directly, for tests and for a build that ships one.
  ///
  /// Skips [start] entirely, so nothing has to reach a network or a keychain
  /// to exercise a screen.
  @visibleForTesting
  Future<void> primeForTest(Catalogue catalogue) async {
    _catalogue = catalogue;
    _language = catalogue.defaultLanguage;
    _state = LoadState.ready;
    notifyListeners();
  }

  /// Lo que un repositorio tiene esperando para enviarse.
  ///
  /// Dos cosas distintas: lo que está escrito y sin guardar en un commit --lo
  /// que se tocó desde fuera, o desde aquí sin cerrar-- y lo que ya tiene
  /// commit y no ha salido de la máquina. El diálogo de enviar enseña las dos
  /// porque son dos preguntas distintas: qué mensaje le pongo, y qué va a
  /// llegar a GitHub.
  ///
  /// Where the catalogue is actually read from: the clone if there is one,
  /// otherwise whatever the app was built with.
  CatalogueSource get _source {
    if (_workspace.isEmpty) return catalogueSource;
    final parts = <CatalogueSource>[
      for (final repo in _workspace.repos)
        ?CatalogueSource.inClone(repo.directory, repo: repo.id),
    ];
    if (parts.isEmpty) return catalogueSource;
    return parts.length == 1 ? parts.single : CatalogueSource.merged(parts);
  }

  /// For the interface, which has to be able to say where it read from.
  String get catalogueOrigin => _source.describe;

  /// Reloads the catalogue, for after a commit that changed structure.
  Future<void> reloadCatalogue() async {
    try {
      _catalogue = await _source.load();
      notifyListeners();
    } catch (error) {
      // Deliberately not fatal: the old catalogue is stale, not wrong, and
      // throwing away a working screen because a refresh failed is worse.
      _error = error;
      notifyListeners();
    }
  }

  // -- lookups the screens need ------------------------------------------

  Unit? unitByPath(String path, {String? repo}) =>
      _catalogue?.unitByPath(path, repo: repo);

  /// El color con el que se marca un repositorio, o null si no hay más de uno
  /// --con uno solo, marcar no dice nada--.
  int? colourOf(String? repo) {
    if (!_workspace.isMultiple || repo == null || repo.isEmpty) return null;
    return _workspace.byId(repo)?.colour;
  }

  Course? courseById(String id) {
    for (final course in _catalogue?.courses ?? const <Course>[]) {
      if (course.id == id) return course;
    }
    return null;
  }

  Document? documentIn(String courseId, String year, String documentId) {
    final entry = courseById(courseId)?.years[year];
    for (final document in entry?.documents ?? const <Document>[]) {
      if (document.id == documentId) return document;
    }
    return null;
  }

  /// Every unit that needs work in [language], worst first.
  ///
  /// Computed here rather than in the translations screen so the count in the
  /// navigation and the list in the page can never disagree.
  List<Unit> needingTranslation(String language) {
    final units = [
      for (final unit in _catalogue?.units ?? const <Unit>[])
        if (unit.statusIn(language).needsWork) unit,
    ];
    units.sort((a, b) {
      // Most used first: translating a unit six courses depend on is worth
      // more than one nobody teaches.
      final byUse = b.usedBy.length.compareTo(a.usedBy.length);
      return byUse != 0 ? byUse : a.path.compareTo(b.path);
    });
    return units;
  }
}
