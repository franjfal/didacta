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
import 'dart:convert';

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
import '../model/composition_file.dart';
import '../model/degrees_file.dart';
import '../model/slug.dart';
import '../model/synced_prefs.dart';
import '../model/themes_file.dart';
import '../model/workspace.dart';
import '../model/yaml_patch.dart';
import 'build_console.dart';
import 'history.dart';

/// Where the app is in bringing itself up.
enum LoadState { loading, ready, failed }

/// Si hay sesión de GitHub, que es lo que decide si Didacta se abre.
///
/// Tres estados y no un booleano, porque el tercero es real y confundirlo con
/// «no» tiene consecuencias: al arrancar, leer el llavero tarda, y durante ese
/// rato la respuesta no es «no ha entrado» sino **todavía no se sabe**. Con un
/// booleano, cada arranque enseñaría la pantalla de entrar durante un
/// parpadeo antes de abrir la biblioteca.
enum SignInState {
  /// Leyendo el llavero. No se sabe.
  checking,

  /// Hay credencial guardada y GitHub no la ha rechazado.
  ///
  /// Sin red también es esto. Lo que se exige es **haber entrado**, no estar
  /// conectado: un aula sin wifi no puede dejar a nadie sin sus diapositivas,
  /// y el trabajo está en un clon del disco.
  signedIn,

  /// No hay credencial, o GitHub ha dicho que ya no vale.
  signedOut,
}

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
  /// Lo que se está mirando: el catálogo **sin los repositorios apagados**.
  ///
  /// El filtro se aplica aquí, en el único sitio por el que pasan todas las
  /// pantallas, y no en cada una. Esa es la diferencia entre una interfaz con
  /// dos fuentes y dos interfaces pegadas: ninguna pantalla pregunta de qué
  /// repositorio es nada para decidir si lo enseña.
  Catalogue get catalogue => _visible ?? _catalogue!;
  Catalogue? get catalogueOrNull => _visible ?? _catalogue;

  /// El catálogo entero, apagados incluidos. Lo mira quien tiene que hablar
  /// de los repositorios en sí: el filtro y los ajustes.
  Catalogue? get fullCatalogue => _catalogue;

  Catalogue? _visible;

  void _refilter() {
    _visible = _catalogue?.without(_synced.hiddenRepos);
  }

  /// Si un repositorio se está mirando ahora mismo.
  bool isRepoVisible(String repo) => !_synced.hiddenRepos.contains(repo);

  /// Enciende o apaga un repositorio en la interfaz.
  ///
  /// Apagar no lo cierra: sigue abierto, sigue clonándose y sigue guardando
  /// lo que ya tenía. Lo que cambia es qué se está mirando, y por eso esto no
  /// toca el disco ni vuelve a leer el índice.
  Future<void> setRepoVisible(String repo, bool visible) async {
    if (isRepoVisible(repo) == visible) return;
    _synced = _synced.withRepoHidden(repo, !visible);
    _refilter();
    notifyListeners();
    await _rememberPrefs();
  }

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
  ///
  /// Puede ser null habiendo sesión: es lo que pasa al abrir sin red con un
  /// token guardado de una versión anterior, que todavía no recordaba el
  /// nombre. Quien decide si se puede usar Didacta es [signInState], no esto.
  GitHubUser? get user => _user;

  SignInState _signIn = SignInState.checking;

  /// Si hay sesión de GitHub. Es lo que decide si la aplicación se abre.
  SignInState get signInState => _signIn;

  bool get signedIn => _signIn == SignInState.signedIn;

  Object? _signInProblem;

  /// Por qué se cerró la sesión sola, si se cerró.
  ///
  /// Se enseña en la pantalla de entrar. Que la sesión caduque y la
  /// aplicación se limite a pedir la contraseña otra vez, sin decir que antes
  /// había una, es la clase de silencio que hace pensar que algo se ha
  /// perdido.
  Object? get signInProblem => _signInProblem;

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

  // -- las preferencias que viajan entre ordenadores ----------------------

  SyncedPrefs _synced = const SyncedPrefs();

  /// Las preferencias sincronizadas, tal como están ahora mismo.
  SyncedPrefs get syncedPrefs => _synced;

  String? _prefsRepo;

  /// En qué repositorio se guardan. Null es «en ninguno»: se quedan aquí.
  String? get prefsRepo => _prefsRepo;

  /// Dónde se escriben dentro de ese repositorio.
  ///
  /// Con el login de GitHub en el nombre, que es lo que permite que un
  /// departamento comparta repositorio sin pisarse: cada uno escribe el suyo
  /// y nadie lee el de otro.
  String? get prefsPath {
    final login = _user?.login ?? '';
    if (login.isEmpty) return null;
    return '.didacta/prefs/$login.json';
  }

  Timer? _prefsWrite;

  // -- lo marcado ---------------------------------------------------------

  bool isFavouriteCourse(String course) => _synced.isFavouriteCourse(course);

  bool isFavouriteYear(String course, String year) =>
      _synced.isFavouriteYear(course, year);

  Future<void> setFavouriteCourse(String course, bool favourite) async {
    _synced = _synced.withFavouriteCourse(course, favourite);
    notifyListeners();
    await _rememberPrefs();
  }

  Future<void> setFavouriteYear(
    String course,
    String year,
    bool favourite,
  ) async {
    _synced = _synced.withFavouriteYear(course, year, favourite);
    notifyListeners();
    await _rememberPrefs();
  }

  /// Las asignaturas en el orden en que se enseñan: las marcadas primero, y
  /// dentro de cada mitad por título.
  ///
  /// Aquí y no en la pantalla porque el orden es una decisión de la
  /// aplicación, no del sitio donde se dibuja: si una lista lo hiciera por su
  /// cuenta, acabaría discrepando de la de al lado.
  List<Course> get sortedCourses {
    final courses = [...catalogue.courses];
    courses.sort((a, b) {
      final mine = isFavouriteCourse(a.id);
      final theirs = isFavouriteCourse(b.id);
      if (mine != theirs) return mine ? -1 : 1;
      return compareTitles(a.title(_language), b.title(_language));
    });
    return courses;
  }

  /// Los cursos de una asignatura: los marcados primero, y el resto del más
  /// reciente al más antiguo, que es el orden en que se buscan.
  List<String> sortedYearsOf(Course course) {
    final years = course.years.keys.toList();
    years.sort((a, b) {
      final mine = isFavouriteYear(course.id, a);
      final theirs = isFavouriteYear(course.id, b);
      if (mine != theirs) return mine ? -1 : 1;
      return b.compareTo(a);
    });
    return years;
  }

  /// Los temas plegados de un curso.
  Set<String> collapsedThemes(String course, String year) =>
      _synced.collapsedIn(course, year);

  /// Pliega o despliega un tema, y lo apunta donde toque.
  Future<void> setThemeCollapsed({
    required String course,
    required String year,
    required String theme,
    required bool collapsed,
  }) async {
    _synced = _synced.withThemeCollapsed(
      course: course,
      year: year,
      theme: theme,
      collapsed: collapsed,
    );
    notifyListeners();
    await _rememberPrefs();
  }

  /// Elige el repositorio donde se sincronizan, o quita el que hubiera.
  Future<void> setPrefsRepo(String? repo) async {
    if (_prefsRepo == repo) return;
    _prefsRepo = repo;
    await preferences.setPrefsRepo(repo);
    notifyListeners();
    if (repo != null) await loadSyncedPrefs();
  }

  /// Guarda en esta máquina ya, y en el repositorio dentro de un rato.
  ///
  /// Lo segundo con espera a propósito: plegar tres temas seguidos son tres
  /// clics y **un** commit. Escribir uno por clic llenaría el historial del
  /// material de ruido, que es el motivo por el que alguien decidiría no usar
  /// esto.
  Future<void> _rememberPrefs() async {
    await preferences.setSyncedPrefs(_synced.toJson());
    if (_prefsRepo == null) return;
    _prefsWrite?.cancel();
    _prefsWrite = Timer(const Duration(seconds: 5), () {
      unawaited(pushSyncedPrefs());
    });
  }

  /// Lee las preferencias del repositorio elegido, si hay alguno.
  ///
  /// Silencioso cuando falla. Es lo correcto aquí: no poder leer unas
  /// preferencias deja paneles como estaban, y una aplicación que no abre
  /// porque no encuentra un fichero de ajustes es peor que una que abre con
  /// los de por defecto.
  Future<void> loadSyncedPrefs() async {
    final repo = _prefsRepo;
    final path = prefsPath;
    if (repo == null || path == null) return;
    try {
      final file = await gatewayFor(repo).read(path);
      _synced = SyncedPrefs.fromJson(file.text);
      _refilter();
      await preferences.setSyncedPrefs(_synced.toJson());
      notifyListeners();
    } catch (_) {
      // Todavía no existe, o no se puede leer. Se queda lo local.
    }
  }

  /// Escribe las preferencias en el repositorio elegido, como un commit.
  Future<void> pushSyncedPrefs() async {
    final repo = _prefsRepo;
    final path = prefsPath;
    if (repo == null || path == null) return;
    final text = _synced.toJson();
    try {
      final gateway = gatewayFor(repo);
      var sha = '';
      try {
        final existing = await gateway.read(path);
        if (existing.text == text) return;
        sha = existing.sha;
      } catch (_) {
        // No estaba: se crea.
      }
      await gateway.commit(
        path: path,
        text: text,
        sha: sha,
        message: 'Preferencias de ${_user?.login ?? 'quien edita'}',
      );
    } catch (_) {
      // Sin red, sin permiso o con un conflicto: lo local sigue valiendo y
      // el próximo cambio lo vuelve a intentar.
    }
  }

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

  /// Lo que el motor va escribiendo mientras compila.
  ///
  /// En la sesión y no en la pantalla que compila, por lo mismo que el resto
  /// de lo que hay aquí: se compila desde tres sitios --la pestaña de una
  /// unidad, la de un tema, el botón de rehacer un panel-- y el registro
  /// tiene que sobrevivir a cerrar la ventana que lo enseña y a irse de la
  /// pantalla. Uno solo, además, porque las compilaciones van de una en una.
  final BuildConsole buildConsole = BuildConsole();

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

  /// Cuándo se escribió el índice que está cargado, por repositorio.
  ///
  /// Es lo que permite saber que el de disco es otro: la comprobación de
  /// arranque compara el índice con el contenido, y eso no ve que el índice
  /// haya cambiado **después** de leerlo --que es lo que pasa cuando alguien
  /// lo regenera desde el terminal con la aplicación abierta--.
  ///
  /// Uno por clon, y no uno solo: con dos repositorios abiertos, mirar el del
  /// primero deja al segundo enseñando lo que leyó al abrirse. Que no haya
  /// entrada para un clon significa que cuando se miró no tenía índice, y por
  /// eso encontrarlo ahora **es** un cambio.
  final Map<String, DateTime> _indexRead = {};

  final List<StreamSubscription<void>> _watching = [];
  final List<StreamSubscription<void>> _watchingContent = [];
  Timer? _settle;
  Timer? _settleContent;

  /// Los clones que se vigilan: todos los del espacio de trabajo.
  List<String> get _watchedPaths => repoPaths;

  /// Empieza a vigilar `generated/` de cada clon.
  ///
  /// Uno por repositorio abierto: vigilar solo el primero dejaba al segundo
  /// sin enterarse de nada --ni de un `.tex` editado por fuera, ni de un
  /// `didacta index` desde el terminal-- hasta reiniciar.
  ///
  /// Idempotente: llamarlo dos veces no deja dos vigilantes. Y se vuelve a
  /// llamar después de cada recarga, porque un clon al que le acaba de
  /// aparecer `generated/` necesita que se le monte el vigilante de verdad.
  void watchDisk() {
    for (final subscription in [..._watching, ..._watchingContent]) {
      unawaited(subscription.cancel());
    }
    _watching.clear();
    _watchingContent.clear();

    for (final path in _watchedPaths) {
      // El material. Editar un `.tex` en otro programa, copiar una figura o
      // traerse cien ficheros con un `git pull` son la misma cosa desde aquí:
      // el disco ya no es lo que el índice dice. Con más respiro que el
      // índice --un `pull` son cientos de eventos seguidos-- y sin forzar
      // nada: se pregunta si hace falta, que cuesta una décima, y solo se
      // regenera si la respuesta es que sí.
      _watchingContent.add(
        watchContent(path).listen((_) {
          _settleContent?.cancel();
          _settleContent = Timer(const Duration(seconds: 2), () {
            unawaited(_rescan());
          });
        }),
      );

      _watching.add(
        watchIndex(path).listen((_) {
          // Con un respiro: el motor escribe cuatro ficheros, y recargar el
          // catálogo cuatro veces por una regeneración es tirar el trabajo
          // tres veces.
          _settle?.cancel();
          _settle = Timer(const Duration(milliseconds: 400), () {
            unawaited(_reloadIfIndexChanged());
          });
        }),
      );
    }
  }

  /// Vuelve a mirar el disco: si el índice se ha quedado corto, lo regenera.
  Future<void> _rescan() async {
    if (await refreshIndex()) {
      await reloadCatalogue();
      await refreshBuilt();
      await _rememberIndexDates();
      watchDisk();
    }
  }

  /// Al volver a la ventana: ¿ha cambiado algo mientras no mirábamos?
  ///
  /// Dos `stat` y, si el índice está viejo respecto al contenido, una
  /// regeneración. Es el momento exacto en que alguien vuelve después de
  /// tocar ficheros por fuera.
  Future<void> checkDisk() async {
    if (await _reloadIfIndexChanged()) {
      watchDisk();
      return;
    }
    if (await refreshIndex()) {
      await reloadCatalogue();
    } else if (_catalogue?.errors.isNotEmpty ?? false) {
      // Un repositorio que no cargó deja su queja en el catálogo, y esa queja
      // se queda en pantalla aunque el motivo desaparezca: el caso de siempre
      // es un clon recién añadido al que todavía no le habían pasado
      // `didacta index`. Volver a leer cuesta cuatro ficheros.
      await reloadCatalogue();
    }

    // Desde aquí, el disco avisa solo.
    if (_watchedPaths.isNotEmpty) {
      await _rememberIndexDates();
      watchDisk();
    }
  }

  /// Relee el catálogo si el índice de algún clon es más nuevo que el leído.
  Future<bool> _reloadIfIndexChanged() async {
    var changed = false;
    for (final path in _watchedPaths) {
      final when = await indexModified(path);
      if (when == null) continue;
      final last = _indexRead[path];
      // Sin entrada: cuando se miró no había índice y ahora sí. Es
      // exactamente lo que pasa con un repositorio recién añadido.
      if (last != null && !when.isAfter(last)) continue;
      _indexRead[path] = when;
      changed = true;
    }
    if (!changed) return false;
    await reloadCatalogue();
    await refreshBuilt();
    return true;
  }

  /// Apunta la fecha del índice de cada clon, que es contra lo que se compara.
  Future<void> _rememberIndexDates() async {
    for (final path in _watchedPaths) {
      final when = await indexModified(path);
      if (when != null) _indexRead[path] = when;
    }
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
    _prefsWrite?.cancel();
    for (final subscription in [..._watching, ..._watchingContent]) {
      unawaited(subscription.cancel());
    }
    buildConsole.dispose();
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
    await _rememberIndexDates();
    // Un repositorio al que le acaba de aparecer `generated/` no se estaba
    // vigilando: ahora sí.
    watchDisk();
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

  /// El clon de un repositorio, o null si no hay con qué.
  ///
  /// Lo que una pantalla pide cuando necesita hablar con git directamente --el
  /// historial de un fichero, por ejemplo--. Aparte de `cloneAt`, que es el
  /// punto de sustitución de los tests y no una puerta de entrada: una
  /// pantalla no tiene por qué saber en qué carpeta está cada repositorio.
  LocalClone? cloneFor(String? repo) {
    if (!LocalClone.supported) return null;
    final directory = pathOf(repo);
    if (directory == null) return null;
    return cloneAt(directory);
  }

  /// Para un test: el clon, sin pasar por Ajustes ni por el disco.
  @visibleForTesting
  Future<void> useCloneForTest(String path) => useClonesForTest([path]);

  /// Para un test: varios clones, que es donde están los fallos que solo
  /// aparecen con más de uno abierto.
  @visibleForTesting
  Future<void> useClonesForTest(List<String> paths) async {
    _workspace = Workspace([
      for (var index = 0; index < paths.length; index += 1)
        ContentRepo(
          owner: 'test',
          name: 'repo${index == 0 ? '' : index}',
          directory: paths[index],
        ),
    ]);
  }

  /// Para un test: lo compilado, sin motor que lo diga.
  @visibleForTesting
  Future<void> setBuiltForTest(Map<String, List<ExistingOutput>> built) async {
    _built = built;
    _builtKnown = true;
    notifyListeners();
  }

  // -- metadatos que discrepan entre repositorios -------------------------

  /// Iguala un campo de una asignatura en todos los repositorios.
  ///
  /// Escribe [value] en el `course.yaml` de cada repositorio que diga otra
  /// cosa, y no toca los que ya coinciden ni los que no lo declaran: rellenar
  /// lo que falta es otra decisión.
  ///
  /// Por líneas, con [YamlPatch], como el resto de ediciones de YAML aquí:
  /// un `course.yaml` lleva comentarios y `# TODO` que dicen qué falta por
  /// rellenar, y volver a serializarlo se los lleva por delante.
  ///
  /// Un commit por repositorio, porque son historiales distintos. Devuelve en
  /// cuántos se escribió.
  Future<int> resolveMetadata({
    required MetadataConflict conflict,
    required String value,
  }) async {
    final path = conflict.path;
    if (path == null) {
      throw ArgumentError('no sé dónde se escribe «${conflict.field}»');
    }
    final where = 'courses/${conflict.course}/course.yaml';
    var written = 0;

    for (final entry in conflict.values.entries) {
      if (entry.value == value) continue;
      final gateway = gatewayFor(entry.key);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      if (conflict.field == 'idiomas') {
        patch.setFlowList(path, [
          for (final code in value.split(',')) code.trim(),
        ]);
      } else {
        patch.setScalar(path, value);
      }
      if (patch.result == file.text) continue;

      await gateway.commit(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: 'Igualar ${conflict.field} de ${conflict.course}',
      );
      written += 1;
    }
    if (written > 0) await reloadCatalogue();
    return written;
  }


  /// Cambia a qué idiomas se da una asignatura.
  ///
  /// En **todos** los repositorios que la declaran, no solo en uno. Una
  /// asignatura partida tiene un `course.yaml` en cada uno y los dos han de
  /// decir lo mismo: escribir en uno solo convierte el cambio en una
  /// discrepancia de metadatos que hay que resolver a mano después, y deja al
  /// otro repositorio pidiendo traducciones que ya no se quieren.
  ///
  /// Un repositorio de solo lectura se salta en silencio. No es un fallo --se
  /// puede mirar material de otra persona-- pero sí queda la asignatura
  /// diciendo dos cosas, y de eso ya avisa la sección de discrepancias.
  ///
  /// Quitar un idioma no borra nada: los `.tex` que hubiera siguen donde
  /// estaban, simplemente dejan de pedirse. Volver a activarlo los recupera.
  ///
  /// Devuelve en cuántos repositorios se escribió.
  Future<int> setCourseLanguages({
    required String course,
    required List<String> languages,
  }) async {
    if (languages.isEmpty) {
      throw ArgumentError('una asignatura tiene que darse en algún idioma');
    }
    final entry = courseById(course);
    if (entry == null) throw ArgumentError('no existe la asignatura $course');

    final where = 'courses/$course/course.yaml';
    // El orden es el del catálogo, no el de los clics: así el fichero sale
    // igual se marque como se marque, y no hay diffs que solo mueven códigos.
    final options = catalogueOrNull?.languageOptions ?? const <LanguageOption>[];
    final ordered = <String>[
      for (final option in options)
        if (languages.contains(option.code)) option.code,
      // Lo que se pide y el índice no conoce se escribe igual, al final: con
      // un índice viejo, ordenar no puede ser motivo para perder un idioma.
      for (final code in languages)
        if (!options.any((o) => o.code == code)) code,
    ];
    final written = <String>[];

    for (final repo in entry.sources.keys) {
      final gateway = gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      patch.setFlowList(const ['languages'], ordered);
      if (patch.result == file.text) continue;

      await gateway.commit(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: 'Idiomas de $course: ${ordered.join(', ')}',
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await reloadCatalogue();
    return written.length;
  }

  // -- los títulos, en todos los idiomas ----------------------------------

  /// Cambia el título de una asignatura, en todos los idiomas a la vez.
  ///
  /// En todos los repositorios que la declaran, por lo mismo que los idiomas:
  /// una asignatura partida tiene un `course.yaml` en cada uno y si dicen
  /// cosas distintas el título que se enseña depende de en qué orden se
  /// abrieron los repositorios.
  ///
  /// Un idioma vacío borra ese título. No se escribe cadena vacía --sería un
  /// título de verdad, y saldría en el PDF-- sino que se quita la línea.
  Future<int> setCourseTitles({
    required String course,
    required Map<String, String> titles,
  }) async {
    final entry = courseById(course);
    if (entry == null) throw ArgumentError('no existe la asignatura $course');
    if (titles.values.every((value) => value.trim().isEmpty)) {
      throw ArgumentError('una asignatura sin título se enseñaría por su id');
    }

    final where = 'courses/$course/course.yaml';
    final written = <String>[];
    for (final repo in entry.sources.keys) {
      final gateway = gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      for (final item in titles.entries) {
        final value = item.value.trim();
        if (value.isEmpty) {
          patch.remove(['title', item.key]);
        } else {
          patch.setScalar(['title', item.key], value);
        }
      }
      if (patch.result == file.text) continue;

      await gateway.commit(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: 'Título de $course',
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await reloadCatalogue();
    return written.length;
  }

  /// Cambia el título de un tema, en el repositorio que lo declara.
  ///
  /// En ese y en ninguno más: un tema lo declara **uno** --los demás solo lo
  /// nombran desde sus documentos-- así que aquí no hay nada que hacer
  /// converger. Esa asimetría es lo que permite que quien no tenga el
  /// repositorio que declara el tema siga viendo todo su material.
  Future<void> setThemeTitles({
    required String repo,
    required String course,
    required String year,
    required String id,
    required Map<String, String> titles,
  }) async {
    final where = 'courses/$course/$year/themes.yaml';
    final gateway = gatewayFor(repo);
    final file = await gateway.read(where);
    final themes = ThemesFile(file.text)..setTitles(id, titles);
    if (themes.text == file.text) return;

    await gateway.commit(
      path: where,
      text: themes.text,
      sha: file.sha,
      message: 'Título del tema $id en $course $year',
    );
    await reloadCatalogue();
  }

  /// Cambia el título de un documento, en el `year.yaml` donde vive.
  ///
  /// En el suyo y solo el suyo: un documento está en un repositorio, y su
  /// composición --qué unidades lleva-- también, que es la regla que sostiene
  /// que esto funcione con varios repositorios abiertos.
  Future<void> setDocumentTitles({
    required String repo,
    required String course,
    required String year,
    required String id,
    required Map<String, String> titles,
  }) async {
    final where = 'courses/$course/$year/year.yaml';
    final gateway = gatewayFor(repo);
    final file = await gateway.read(where);
    final composition = CompositionFile(file.text)
      ..setDocumentTitles(id, titles);
    if (composition.text == file.text) return;

    await gateway.commit(
      path: where,
      text: composition.text,
      sha: file.sha,
      message: 'Título de $id en $course $year',
    );
    await reloadCatalogue();
  }

  // -- las titulaciones ---------------------------------------------------

  /// Cambia a qué grado pertenece una asignatura.
  ///
  /// En todos los repositorios que la declaran, por lo mismo que los idiomas:
  /// si dicen cosas distintas, la asignatura sale en un grado o en otro según
  /// en qué orden se abrieron los repositorios.
  ///
  /// [degree] vacío la deja sin grado, que es un estado legítimo: no todo lo
  /// que se da pertenece a una titulación, y obligar a elegir una inventaría
  /// grados para no dejar huecos.
  Future<int> setCourseDegree({
    required String course,
    required String? degree,
  }) async {
    final entry = courseById(course);
    if (entry == null) throw ArgumentError('no existe la asignatura $course');

    final where = 'courses/$course/course.yaml';
    final written = <String>[];
    for (final repo in entry.sources.keys) {
      final gateway = gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      if ((degree ?? '').isEmpty) {
        patch.remove(const ['degree_id']);
      } else {
        patch.setScalar(const ['degree_id'], degree!);
      }
      if (patch.result == file.text) continue;

      await gateway.commit(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: (degree ?? '').isEmpty
            ? 'Quitar el grado de $course'
            : 'Grado de $course: $degree',
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await reloadCatalogue();
    return written.length;
  }

  /// Declara un grado nuevo en un repositorio.
  ///
  /// En **uno**, no en todos: un grado lo declara quien lo tenga y los demás
  /// lo nombran desde sus asignaturas. Declararlo en los dos no rompe nada
  /// --se fusionan por id-- pero es lo que hace que luego discrepen.
  Future<void> createDegree({
    required String repo,
    required String id,
    required Map<String, String> titles,
    String? institution,
  }) async {
    final gateway = gatewayFor(repo);
    if (!gateway.canWrite) {
      throw ArgumentError('no se puede escribir en $repo');
    }
    const where = 'degrees.yaml';

    String text;
    // Vacío cuando el fichero no existe todavía: es lo que la pasarela
    // entiende por «no había nada aquí».
    var sha = '';
    try {
      final file = await gateway.read(where);
      text = file.text;
      sha = file.sha;
    } on ContentException catch (error) {
      if (error.kind != ContentFailure.missing) rethrow;
      // Se crea con sus comentarios, que explican por qué un grado que nadie
      // declara no rompe nada.
      text = emptyDegreesYaml;
    }

    final degrees = DegreesFile(text)
      ..add(
        id: id,
        titles: titles,
        institution: institution,
        languages: catalogueOrNull?.languages ?? const ['es'],
      );

    await gateway.commit(
      path: where,
      text: degrees.text,
      sha: sha,
      message: 'Declarar el grado $id',
    );
    await reloadCatalogue();
  }

  /// Cambia el título de un grado, en todos los idiomas a la vez.
  ///
  /// En los repositorios que lo declaran, que pueden ser varios: si lo
  /// declaran dos y solo se cambia en uno, la discrepancia aparece al momento.
  Future<int> setDegreeTitles({
    required String id,
    required Map<String, String> titles,
  }) async {
    final degree = catalogueOrNull?.degrees
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (degree == null) throw ArgumentError('no se declara el grado $id');

    const where = 'degrees.yaml';
    final written = <String>[];
    for (final repo in degree.sources.keys) {
      final gateway = gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final degrees = DegreesFile(file.text)..setTitles(id, titles);
      if (degrees.text == file.text) continue;

      await gateway.commit(
        path: where,
        text: degrees.text,
        sha: file.sha,
        message: 'Título del grado $id',
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await reloadCatalogue();
    return written.length;
  }

  // -- compilar en lote ---------------------------------------------------

  /// Compila varios documentos, todas sus versiones, contándolo por el
  /// camino.
  ///
  /// Un documento a la vez y no todos de golpe: LaTeX come un núcleo entero y
  /// lanzar ocho a la vez no acaba antes, solo deja el ordenador inservible
  /// mientras tanto. El orden es el de la lista, que es el orden en que se
  /// dan, así que lo primero que se compila es lo primero que se busca.
  ///
  /// Devuelve cuántos documentos salieron enteros. No lanza: un documento que
  /// no compila es un resultado --sale en el registro con su error-- y parar
  /// el lote por él dejaría los demás sin hacer.
  /// [languages] son los idiomas en los que compilar. Vacío es «el suyo», que
  /// es lo que hace el motor por su cuenta y lo que se quiere casi siempre:
  /// quien compila un tema para la clase del jueves lo quiere en el idioma en
  /// el que va a darla, no en los tres.
  Future<int> buildDocuments(
    List<({String repo, String course, String year, String id, String title})>
    documents, {
    required String title,
    List<String> languages = const [],
  }) async {
    buildConsole.start(title, total: documents.length);
    var ok = 0;
    for (final document in documents) {
      final compiler = this.compiler(repo: document.repo);
      final reference = '${document.course}@${document.year}/${document.id}';
      buildConsole.startStep(document.title);
      if (compiler == null) {
        buildConsole.add('--- sin motor para $reference');
        buildConsole.finishStep();
        continue;
      }
      try {
        final profiles = await compiler.documentProfiles(reference);
        final results = await compiler.compileDocument(
          document: reference,
          // Todas las versiones que admite, que es lo que se pide al darle a
          // compilar sobre un documento entero.
          profiles: [for (final profile in profiles) profile.id],
          languages: languages,
          onOutput: buildConsole.add,
        );
        if (results.isNotEmpty && results.every((result) => result.ok)) ok += 1;
      } catch (error) {
        buildConsole.add('--- $reference: $error');
      }
      buildConsole.finishStep();
    }
    buildConsole.finish(ok: ok == documents.length);
    await refreshBuilt();
    return ok;
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
      // Crear o borrar una asignatura es una modificación como cualquier
      // otra, y de las que más daño hacen si se hacen sobre una copia vieja:
      // toca la estructura del repositorio entero.
      beforeWrite: () => ensureFresh(repo),
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
      // La copia local primero: es la que hace que los temas abran plegados
      // sin esperar al repositorio, y la que vale cuando no hay ninguno.
      _prefsRepo = await preferences.prefsRepo();
      _synced = SyncedPrefs.fromJson(await preferences.syncedPrefs() ?? '');
      _refilter();
    } catch (error) {
      // A setting that cannot be read is a setting that is not set.
      _workspace = const Workspace.empty();
      _settingsProblem = error;
    }

    // La sesión, antes que el catálogo y antes de pintar.
    //
    // Va aquí y no en `refreshAccess`, que es donde estaba, porque ahora
    // decide **si hay aplicación**: sin sesión no se abre nada, así que la
    // primera pantalla depende de esto y no puede pintarse sin ello. Y porque
    // un catálogo que no carga sale por una rama que nunca llegaba a
    // `refreshAccess`, y habría dejado la pantalla de carga para siempre.
    _token = await tokenStore.read();
    await _resolveSignIn();

    try {
      _catalogue = await _source.load();
      _refilter();
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
        _refilter();
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
    // Las preferencias sincronizadas, después: hacen falta la pasarela del
    // repositorio y el login de quien ha entrado, y las dos salen de arriba.
    // Sin esperar a que terminen: lo local ya está puesto, y esto solo puede
    // mejorarlo.
    unawaited(loadSyncedPrefs());
  }

  /// Abre cada repositorio del espacio de trabajo: su clon y su pasarela.
  Future<void> _openRepositories() async {
    _token = await tokenStore.read();
    _pushOnCommit = await preferences.pushOnCommit();
    _gateways.clear();
    _cloneStatus.clear();
    _repoProblems.clear();

    await _resolveSignIn();

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
          // Traer antes de escribir, con la ventana de [freshFor] para no
          // preguntar a GitHub en cada guardado.
          beforeWrite: () => ensureFresh(repo.id),
        );
      } catch (thrown) {
        // Uno que no abre no puede llevarse por delante a los demás: quien
        // tenga el otro tiene que poder trabajar con él.
        _repoProblems[repo.id] = thrown;
      }
    }

    if (compiler() == null) await _findEngine();
  }

  /// Quién es quien tiene este token, según GitHub.
  ///
  /// Un método propio y no la llamada directa porque es **la única parte de
  /// tener sesión que necesita internet**, y aislarla es lo que permite
  /// probar todo lo demás --que sin sesión no se abre, que sin red sí, que un
  /// token rechazado echa-- sin una máquina conectada.
  @protected
  @visibleForTesting
  Future<GitHubUser> whoIs(String token) => GitHubApi(token: token).me();

  /// A qué llega en GitHub la cuenta que ha entrado, para un repositorio.
  ///
  /// Null es que no llega. Aparte por lo mismo que [whoIs]: es de las pocas
  /// cosas que necesitan internet, y aislarla permite probar la regla --qué
  /// carpetas se dejan añadir y cuáles no-- sin una máquina conectada.
  @protected
  @visibleForTesting
  Future<GitHubRepo?> accessTo(String owner, String name) async {
    final token = _token ?? await tokenStore.read() ?? '';
    return GitHubApi(token: token).repository(owner, name);
  }

  /// Decide si hay sesión, que es lo que decide si Didacta se abre.
  ///
  /// La regla, en una línea: **hay sesión si hay credencial guardada y GitHub
  /// no la ha rechazado.** Los cuatro casos que salen de ahí no son
  /// intercambiables:
  ///
  /// * sin token, no hay sesión. Es la instalación recién puesta;
  /// * con token y GitHub contestando, hay sesión y además se sabe de quién.
  ///   Se apunta, para la próxima vez que no haya red;
  /// * con token y **GitHub diciendo que no vale** --un 401, un token
  ///   revocado desde github.com-- se cierra la sesión aquí y se dice por
  ///   qué. Dejar abierta una sesión que GitHub ya no reconoce sería enseñar
  ///   un candado que no cierra;
  /// * con token y **sin poder preguntar** --sin red-- hay sesión. Lo que se
  ///   exige es haber entrado, y eso ya pasó; lo que no hay ahora es forma de
  ///   confirmarlo, que no es lo mismo. Se usa el nombre apuntado la última
  ///   vez.
  Future<void> _resolveSignIn() async {
    if (_token == null || _token!.isEmpty) {
      _user = null;
      _signIn = SignInState.signedOut;
      return;
    }

    if (_user == null) {
      try {
        // Con tope: sin red, una petición puede tardar lo que tarde el DNS en
        // rendirse, y eso es tiempo con la aplicación en blanco delante de
        // alguien que ya entró. Pasado el tope se sigue con lo apuntado, que
        // es exactamente lo que hay que hacer cuando no se puede preguntar.
        _user = await whoIs(_token!).timeout(const Duration(seconds: 6));
        await preferences.setGithubUser(jsonEncode(_user!.toJson()));
        _signInProblem = null;
      } on GitHubException catch (rejected) {
        if (rejected.rejectsCredential) {
          await tokenStore.clear();
          await preferences.setGithubUser(null);
          _token = null;
          _user = null;
          _signInProblem = rejected;
          _signIn = SignInState.signedOut;
          return;
        }
        // GitHub contestó, pero con algo que no habla de la credencial --un
        // 500 suyo--. No es motivo para echar a nadie.
        _user = GitHubUser.fromJson(await preferences.githubUser());
      } catch (_) {
        // Ni siquiera contestó: sin red. Lo que se sabe es lo de la última
        // vez, y basta para firmar los commits.
        _user = GitHubUser.fromJson(await preferences.githubUser());
      }
    }
    _signIn = SignInState.signedIn;
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
  ///
  /// Quién es se pregunta **aquí y sin red de seguridad**: entrar es el único
  /// momento en el que se puede exigir que GitHub conteste, y un token que no
  /// se ha podido comprobar ni una vez no es una sesión. Lo que se guarda es
  /// el resultado de esa comprobación, y es lo que permite que los arranques
  /// siguientes valgan sin red.
  Future<void> signIn(String token) async {
    final who = await whoIs(token);
    await tokenStore.write(token);
    await preferences.setGithubUser(jsonEncode(who.toJson()));
    _token = token;
    _user = who;
    _signIn = SignInState.signedIn;
    _signInProblem = null;
    _forgetFreshness();
    await _dropUnreachable();
    await refreshAccess();
  }

  /// Los repositorios abiertos que esta cuenta no alcanza, fuera.
  ///
  /// Se hace al entrar y solo al entrar. Entrar es cuando puede cambiar la
  /// respuesta --es otra cuenta, o a esta le han quitado el acceso-- y es
  /// además el único momento en el que se sabe que hay red: comprobarlo en
  /// cada arranque costaría una llamada por repositorio y dejaría a quien
  /// abre sin conexión sin sus propias carpetas.
  ///
  /// Se quitan del espacio de trabajo, no del disco. La carpeta lleva trabajo
  /// dentro y perder el acceso a un repositorio no es motivo para borrarlo de
  /// la máquina de nadie.
  Future<void> _dropUnreachable() async {
    final dropped = <String>[];
    for (final repo in _workspace.repos) {
      try {
        if (await accessTo(repo.owner, repo.name) == null) {
          dropped.add(repo.id);
        }
      } catch (_) {
        // No haber podido preguntar no es un «no»: quitarle a alguien sus
        // repositorios porque GitHub tuvo un mal momento sería mucho peor
        // que dejarlos abiertos un rato de más.
      }
    }
    if (dropped.isEmpty) return;
    for (final id in dropped) {
      _workspace = _workspace.without(id);
    }
    await preferences.setWorkspace(_workspace.toJson());
    _accessProblem = CloneException(
      dropped.length == 1
          ? 'He cerrado ${dropped.single}: esta cuenta no llega a él. La '
                'carpeta sigue en el disco.'
          : 'He cerrado ${dropped.length} repositorios a los que esta cuenta '
                'no llega: ${dropped.join(', ')}. Las carpetas siguen en el '
                'disco.',
    );
  }

  /// Sale de GitHub. Los clones se quedan: son carpetas de esta máquina con
  /// el trabajo dentro, y borrarlas al salir sería perderlo.
  Future<void> signOut() async {
    await tokenStore.clear();
    await preferences.setGithubUser(null);
    _token = null;
    _user = null;
    _signIn = SignInState.signedOut;
    _signInProblem = null;
    // Avisando ya, antes de volver a abrir los repositorios: salir tiene que
    // devolver a la puerta en el acto. Lo que viene después --mirar el estado
    // de cada clon, buscar el motor-- habla con git y con el disco, y dejar
    // la biblioteca de alguien que acaba de salir en pantalla mientras tanto
    // sería enseñar lo que se acaba de cerrar.
    notifyListeners();
    await refreshAccess();
  }

  /// Dónde se clonaría un repositorio, y qué hay ya ahí.
  ///
  /// Se consulta **antes** de clonar: es lo que permite decir «ya lo tienes,
  /// lo uso» o «ahí hay otra cosa, elige otra carpeta» en lugar de escribir
  /// encima y explicarlo después.
  Future<({String directory, CloneTarget state})> inspectTarget({
    required String owner,
    required String name,
    String? directory,
  }) async {
    final where = directory ?? '$_cloneBase/$name';
    if (!LocalClone.supported) {
      return (directory: where, state: CloneTarget.free);
    }
    return (
      directory: where,
      state: await LocalClone.inspect(
        directory: where,
        owner: owner,
        repo: name,
      ),
    );
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

    return _register(
      owner: owner,
      name: name,
      directory: where,
      branch: branch,
      colour: colour,
    );
  }

  /// Prepara un repositorio de GitHub vacío como repositorio de contenido, y
  /// lo añade.
  ///
  /// Es lo que se ofrece cuando [addRepository] se encuentra un repositorio
  /// sin commits ([EmptyRepositoryException]): uno recién creado en GitHub
  /// para empezar un curso. El primer commit va a nombre de quien ha entrado,
  /// igual que cualquier otro cambio.
  Future<ContentRepo> initializeRepository({
    required String owner,
    required String name,
    required String branch,
    required String title,
    String? directory,
    int? colour,
    void Function(String line)? onProgress,
  }) async {
    if (!LocalClone.supported) {
      throw const CloneException(
        'Preparar un repositorio necesita clonarlo, y aquí no se puede.',
      );
    }
    final where = directory ?? '$_cloneBase/$name';
    final token = _token ?? await tokenStore.read() ?? '';
    final signedIn = _user;
    final author = signedIn == null
        ? _cloneAuthor
        : (name: signedIn.authorName, email: signedIn.authorEmail);
    if (author == null) {
      throw const CloneException(
        'Entra en GitHub primero: el primer commit tiene que ir a nombre de '
        'alguien.',
      );
    }

    await LocalClone.initialize(
      directory: where,
      owner: owner,
      repo: name,
      branch: branch,
      token: token,
      title: title,
      authorName: author.name,
      authorEmail: author.email,
      onProgress: onProgress,
    );
    return _register(
      owner: owner,
      name: name,
      directory: where,
      branch: branch,
      colour: colour,
    );
  }

  /// Apunta un clon ya listo en el espacio de trabajo y lo abre.
  Future<ContentRepo> _register({
    required String owner,
    required String name,
    required String directory,
    required String branch,
    int? colour,
  }) async {
    final repo = ContentRepo(
      owner: owner,
      name: name,
      directory: directory,
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
    final clone = cloneAt(directory);

    // 1. Que sea un clon de git con un remoto de GitHub.
    //
    // Una carpeta cualquiera del disco no sirve, y no por capricho: lo que
    // se escriba ahí no tiene a dónde ir. Un repositorio de contenido es la
    // fuente de la verdad de un curso entero, y una copia que solo existe en
    // un portátil es la copia que se pierde.
    final remote = await clone.remoteUrl();
    final found = repoFromRemote(remote);
    if (found == null) {
      throw CloneException(
        '$directory no es un clon de un repositorio de GitHub. Didacta solo '
        'trabaja sobre clones: lo que se escribe tiene que poder enviarse, y '
        'una carpeta suelta no tiene a dónde.',
      );
    }

    // 2. Que la cuenta que ha entrado llegue a ese repositorio.
    //
    // Que la carpeta esté en este disco no dice nada de quién la puso ahí:
    // puede ser el clon de otra persona, o el de una cuenta anterior. Quien
    // decide si esto se puede abrir es GitHub, y se le pregunta.
    final GitHubRepo? reachable;
    try {
      reachable = await accessTo(found.owner, found.name);
    } on GitHubException catch (thrown) {
      throw CloneException(
        'No se ha podido comprobar en GitHub si llegas a '
        '${found.owner}/${found.name}, así que no lo añado: añadirlo sin '
        'saberlo sería abrir algo que quizá no se puede sincronizar.',
        stderr: '$thrown',
      );
    } catch (thrown) {
      throw CloneException(
        'Sin conexión con GitHub no puedo comprobar si llegas a '
        '${found.owner}/${found.name}. Añadir un repositorio se hace una vez '
        'y con red; lo que ya está añadido sigue abriéndose sin ella.',
        stderr: '$thrown',
      );
    }
    if (reachable == null) {
      final who = _user?.login;
      throw CloneException(
        '${found.owner}/${found.name} no existe o no llegas a él'
        '${who == null ? '' : ' con la cuenta $who'}. '
        'Pide acceso en GitHub, o entra con la cuenta que lo tiene.',
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

    // 3. Y que quede al día.
    //
    // Se añade y acto seguido se pone en hora con GitHub, porque una carpeta
    // que llevaba meses parada abre enseñando material viejo sin decirlo. Lo
    // que no se puede alinear --commits sin enviar, ficheros sin guardar-- no
    // se toca ni se esconde: queda dicho y en la barra de sincronización.
    _addProblem = await _catchUp(repo);

    await refreshAccess();
    await reloadCatalogue();
    return repo;
  }

  Object? _addProblem;

  /// Qué impidió dejar al día el último repositorio añadido, si algo lo hizo.
  Object? get addProblem => _addProblem;

  /// Cuánto vale una comprobación de que un clon está al día.
  ///
  /// Cinco minutos. Editando se guarda muchas veces seguidas --cada campo de
  /// un problema, cada vuelta a una unidad-- y preguntar a GitHub en cada
  /// guardado convertiría cada pulsación en una llamada de red: la aplicación
  /// se pondría lenta justo en lo que más se hace, y GitHub acabaría
  /// limitando las peticiones. Lo que hace falta es no editar sobre material
  /// viejo, y para eso una comprobación de hace un momento vale igual que una
  /// de ahora: en cinco minutos nadie ha empujado y se ha ido.
  static const Duration freshFor = Duration(minutes: 5);

  /// Cuándo se comprobó por última vez que cada clon estaba al día.
  final Map<String, DateTime> _verified = {};

  /// Se asegura de que el clon de [repo] está al día antes de escribir en él.
  ///
  /// Es la otra mitad de «siempre sincronizados»: traer antes de modificar,
  /// enviar después. Sin esto, dos personas sobre el mismo tema se pisan sin
  /// enterarse hasta que una de las dos no puede enviar.
  ///
  /// Cuatro cosas que decide, y las cuatro importan:
  ///
  /// * **no pregunta si preguntó hace poco** ([freshFor]). Guardar es lo que
  ///   más se hace, y una llamada de red por guardado se nota;
  /// * **avanza solo si no hay nada que perder**: con el clon limpio y sin
  ///   commits propios, ponerse al día es un avance rápido;
  /// * **si ha divergido, no toca nada y lo dice**. Juntar dos historias es
  ///   un merge, y eso no lo decide un guardado;
  /// * **sin red, deja escribir**. Un commit a un clon del propio disco no
  ///   necesita credencial ni conexión, y bloquear el guardado ahí sería
  ///   perder trabajo para proteger una sincronización que se hará luego.
  Future<void> ensureFresh(String? repo) async {
    final id = repo ?? _workspace.repos.firstOrNull?.id;
    if (id == null) return;
    final target = _workspace.repos.where((r) => r.id == id).firstOrNull;
    if (target == null || !LocalClone.supported) return;

    final last = _verified[id];
    if (last != null && DateTime.now().difference(last) < freshFor) return;

    final problem = await _catchUp(target);
    if (problem == null) {
      _verified[id] = DateTime.now();
      _driftProblem.remove(id);
    } else {
      // No se marca como comprobado: la próxima vez se vuelve a intentar, que
      // es lo que hace que esto se arregle solo en cuanto vuelva la red o se
      // resuelva el desfase desde la barra.
      _driftProblem[id] = problem;
    }
    notifyListeners();
  }

  final Map<String, Object> _driftProblem = {};

  /// Qué impide que un repositorio esté al día con GitHub, si algo lo impide.
  ///
  /// Se enseña donde se ve el repositorio. No es un error de guardar --lo
  /// guardado está guardado-- sino una advertencia sobre lo que hay debajo.
  Object? driftOf(String repo) => _driftProblem[repo];

  /// Vuelve a exigir una comprobación, aunque se hiciera hace un momento.
  ///
  /// Después de traer o de enviar: lo que se acaba de hacer cambia lo que una
  /// comprobación anterior daba por bueno.
  void _forgetFreshness() => _verified.clear();

  /// Pone un clon en hora con GitHub, hasta donde se pueda sin pisar nada.
  ///
  /// Trae siempre, y **avanza mientras no haya historia propia que juntar**.
  /// Con commits locales sin enviar no se toca nada: unir dos historias es un
  /// merge o un rebase, y eso no lo decide ni un guardado ni un botón de
  /// «añadir carpeta». Se dice lo que hay y se deja para la barra de
  /// sincronización, que es donde se trae y se envía a propósito.
  ///
  /// Quién decide si un fichero suelto sin guardar estorba es **git**, con
  /// `pull --ff-only`, y no una comprobación propia: un `generated/` recién
  /// regenerado deja el clon sucio casi siempre, y negarse a avanzar por eso
  /// habría convertido la garantía en un aviso permanente que nadie lee. Si
  /// lo que viene pisa algo sin guardar, git se niega y su mensaje es el
  /// bueno.
  ///
  /// Devuelve qué lo impidió, o null si quedó al día.
  Future<Object?> _catchUp(ContentRepo repo) async {
    final token = _token ?? await tokenStore.read() ?? '';
    final clone = cloneAt(repo.directory);
    try {
      await clone.fetch(token: token);
      final status = await clone.status();
      if (status.behind == 0) {
        // Al día en lo que importa aquí. Los commits propios sin enviar no
        // son un desfase con GitHub: son trabajo esperando a salir, y de eso
        // ya habla la barra de sincronización.
        return null;
      }
      if (status.ahead == 0) {
        await clone.pull(token: token);
        return null;
      }
      return CloneException(
        '${repo.id} no está al día con GitHub: ${_describeDrift(status)}. '
        'Las dos historias han seguido por su lado, así que hay que juntarlas '
        'desde la barra de sincronización antes de seguir.',
      );
    } catch (thrown) {
      return thrown;
    }
  }

  static String _describeDrift(CloneStatus status) {
    final pieces = [
      if (status.behind > 0)
        '${status.behind} ${status.behind == 1 ? 'commit' : 'commits'} por '
            'traer',
      if (status.ahead > 0) '${status.ahead} sin enviar',
      if (status.dirtyPaths.isNotEmpty)
        '${status.dirtyPaths.length} '
            '${status.dirtyPaths.length == 1 ? 'fichero' : 'ficheros'} sin '
            'guardar',
    ];
    return pieces.join(', ');
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
    _forgetFreshness();
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
    _forgetFreshness();
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
    _refilter();
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
      _refilter();
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
      catalogueOrNull?.unitByPath(path, repo: repo);

  /// El color con el que se marca un repositorio, o null si no hay más de uno
  /// --con uno solo, marcar no dice nada--.
  int? colourOf(String? repo) {
    if (!_workspace.isMultiple || repo == null || repo.isEmpty) return null;
    return _workspace.byId(repo)?.colour;
  }

  /// El año tal como está sin filtrar, para poder decir cuánto se está
  /// escondiendo. Es lo único que mira el catálogo entero desde una pantalla.
  CourseYear? fullYear(String courseId, String year) {
    for (final course in fullCatalogue?.courses ?? const <Course>[]) {
      if (course.id == courseId) return course.years[year];
    }
    return null;
  }

  Course? courseById(String id) {
    for (final course in catalogueOrNull?.courses ?? const <Course>[]) {
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
      for (final unit in catalogueOrNull?.units ?? const <Unit>[])
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
