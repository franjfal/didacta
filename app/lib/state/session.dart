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

import 'package:flutter/foundation.dart';

import '../data/auth.dart';
import '../data/catalogue_source.dart';
import '../data/compiler.dart';
import '../data/content_gateway.dart';
import '../data/course_admin.dart';
import '../data/local_clone.dart';
import '../data/preferences.dart';
import '../data/repository_access.dart';
import '../model/catalogue.dart';

/// Where the app is in bringing itself up.
enum LoadState { loading, ready, failed }

class Session extends ChangeNotifier {
  Session({
    required this.catalogueSource,
    required this.auth,
    required this.tokenStore,
    required this.apiBase,
    required this.contentOwner,
    required this.contentRepo,
    required this.contentBranch,
    Preferences? preferences,
  }) : preferences = preferences ?? MemoryPreferences();

  final CatalogueSource catalogueSource;

  /// Only an [AuthSession]: this class has no business knowing that Firebase
  /// is what provides it, and depending on Firebase here would make every
  /// screen need it running -- including in a test.
  final AuthSession auth;

  final SecretStore tokenStore;

  /// Where the clone is, and whether a commit is pushed. Not secrets, so not
  /// in the keychain.
  final Preferences preferences;

  /// The Worker's origin. Empty when the app was built without one, which is
  /// a legitimate configuration: a desktop build with a token needs no API.
  final String apiBase;

  final String contentOwner;
  final String contentRepo;
  final String contentBranch;

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

  Authorisation _authorisation = const Authorisation.anonymous();
  Authorisation get authorisation => _authorisation;

  ContentGateway _gateway = const UnconfiguredGateway();
  ContentGateway get gateway => _gateway;

  bool _hasToken = false;
  String? _token;
  bool _pushOnCommit = true;

  /// Whether a repository token is stored on this machine.
  bool get hasStoredToken => _hasToken;

  /// Whether storing one is even possible here. False on the web.
  bool get canStoreToken => tokenStore.canStoreSafely;

  String? _clonePath;

  /// The clone this machine is using, if any.
  String? get clonePath => _clonePath;

  /// Whether a clone is possible at all here. False on the web.
  bool get canUseClone => LocalClone.supported;

  CloneStatus? _cloneStatus;

  /// How the clone stands against the remote, as of the last check. Null
  /// when there is no clone, or when reading it failed.
  CloneStatus? get cloneStatus => _cloneStatus;

  Object? _cloneProblem;

  /// Why the clone is not being used, when there is a path but no gateway.
  /// Shown rather than swallowed: "I set a folder and nothing happened" is
  /// the worst possible outcome.
  Object? get cloneProblem => _cloneProblem;

  ({String name, String email})? _cloneAuthor;

  /// Who the clone's commits will be attributed to.
  ({String name, String email})? get cloneAuthor => _cloneAuthor;

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
  Compiler? compiler() {
    if (!Compiler.supported) return null;
    final engine = _enginePath;
    final clone = _clonePath;
    if (engine == null || clone == null) return null;
    return Compiler(enginePath: engine, repositoryPath: clone);
  }

  /// Crear, duplicar y borrar asignaturas y años.
  ///
  /// Null cuando no se puede: hace falta el clon --para escribir y para
  /// hacer el commit-- y el motor, que es el que sabe hacer cada operación.
  /// La pantalla lo dice en lugar de ofrecer botones que no funcionan.
  CourseAdmin? admin() {
    final compiler = this.compiler();
    final path = _clonePath;
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
      repositoryPath: _clonePath,
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
  /// here -- a stored preference, a keychain, Firebase, a clone, the Worker --
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
      _clonePath = await preferences.clonePath();
      _unitPanel = await preferences.unitPanelVisible();
      _split = await preferences.splitEditors();
    } catch (error) {
      // A setting that cannot be read is a setting that is not set.
      _clonePath = null;
      _settingsProblem = error;
    }

    try {
      _catalogue = await _source.load();
      _language = _catalogue!.defaultLanguage;
      _state = LoadState.ready;
    } catch (error) {
      _error = error;
      _state = LoadState.failed;
      notifyListeners();
      return;
    }

    // Painted before access is resolved. The library needs none of what
    // follows, and making the reader wait for a keychain -- or lose the
    // screen to it -- is the wrong trade.
    notifyListeners();

    try {
      // Auth is watched rather than read once, so signing in or out updates
      // every screen without any of them subscribing to Firebase themselves.
      //
      // With an `onError`, which is not optional: a stream error with no
      // handler goes to the zone, and from a Firebase JS callback it lands in
      // the browser console as an uncaught object with no stack. Firebase
      // failing to watch is a degraded state -- reading needs no session --
      // so it is recorded and shown.
      auth.changes.listen(
        (_) => refreshAccess(),
        onError: (Object error) {
          _accessProblem = error;
          notifyListeners();
        },
      );
    } catch (error) {
      _accessProblem = error;
    }
    await refreshAccess();
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
  Future<void> refreshAccess() async {
    try {
      await _refreshAccess();
      _accessProblem = null;
    } catch (error) {
      // Recorded, not thrown: see the note on [start]. Whatever failed, the
      // catalogue is already loaded and reading public material still works.
      _accessProblem = error;
      _gateway = UnconfiguredGateway(
        'No se ha podido determinar el acceso: $error',
      );
      notifyListeners();
    }
  }

  Future<void> _refreshAccess() async {
    _token = await tokenStore.read();
    _hasToken = _token?.isNotEmpty ?? false;
    _pushOnCommit = await preferences.pushOnCommit();

    // The API is the authority on permissions, so ask it -- but only if there
    // is one and somebody is signed in. Its answer for an anonymous caller is
    // "anonymous", which we already know.
    if (apiBase.isNotEmpty) {
      try {
        _authorisation = await DidactaApi(base: apiBase, auth: auth).whoAmI();
      } catch (_) {
        // A Worker that is down must not make the app unusable: the catalogue
        // is already loaded and reading public material still works.
        _authorisation = _fromUser();
      }
    } else {
      _authorisation = _fromUser();
    }

    _gateway = await _deriveGateway();

    if (Compiler.supported) {
      try {
        _enginePath = await Compiler.discover(
          configured: await preferences.enginePath(),
          repositoryPath: _clonePath,
        );
      } catch (error) {
        // Looking for the engine must not stop the app: not finding it means
        // the compile screen says so, not that nothing loads.
        _enginePath = null;
        _accessProblem ??= error;
      }
    }

    notifyListeners();
  }

  /// What we know about the caller without asking the API.
  Authorisation _fromUser() {
    final user = auth.user;
    if (user == null) return const Authorisation.anonymous();
    return Authorisation(
      signedIn: true,
      email: user.email,
      emailVerified: user.emailVerified,
    );
  }

  /// Picks the gateway, in order of how much the author has committed to.
  ///
  /// A clone wins over a token straight to GitHub, which wins over the API.
  /// The ordering is not arbitrary: each step down is a step further from the
  /// machine, and someone who has cloned the repository onto this machine has
  /// said what they want -- the local, offline, whole-repository path.
  Future<ContentGateway> _deriveGateway() async {
    final token = await tokenStore.read();

    try {
      _clonePath = await preferences.clonePath();
      _settingsProblem = null;
    } catch (error) {
      _clonePath = null;
      _settingsProblem = error;
    }
    _cloneStatus = null;
    _cloneProblem = null;
    final path = _clonePath;
    if (path != null && LocalClone.supported) {
      try {
        final clone = LocalClone(directory: path);
        if (!await clone.looksRight(owner: contentOwner, repo: contentRepo)) {
          throw CloneException(
            '$path no es un clon de $contentOwner/$contentRepo. '
            'Elige otra carpeta o vuelve a clonar.',
          );
        }
        _cloneStatus = await clone.status();
        // The signed-in user first, then git's own identity on this machine.
        // A clone on someone's own disk must not need a web sign-in to
        // commit -- and someone who has a clone already has a git identity.
        _cloneAuthor =
            auth.user?.commitAuthor ?? await clone.configuredAuthor();
        return CloneGateway(
          clone: clone,
          token: token ?? '',
          author: _cloneAuthor,
          pushOnCommit: await preferences.pushOnCommit(),
        );
      } catch (thrown) {
        // Falls through to the other paths rather than leaving the app
        // unusable, but the reason is kept and shown in Ajustes.
        _cloneProblem = thrown;
      }
    }

    if (token != null && token.isNotEmpty) {
      return DirectGateway(
        github: GitHubDirect(
          owner: contentOwner,
          repo: contentRepo,
          branch: contentBranch,
          token: token,
        ),
        author: auth.user?.commitAuthor,
      );
    }

    if (apiBase.isNotEmpty) {
      return ApiGateway(
        api: DidactaApi(base: apiBase, auth: auth),
        authorisation: _authorisation,
      );
    }

    return const UnconfiguredGateway(
      'Sin API ni token: la aplicación solo puede leer el catálogo. '
      'Añade un token en Ajustes, o compila con --dart-define=DIDACTA_API.',
    );
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
    final path = _clonePath;
    if (path == null) return;
    await LocalClone(directory: path).setAuthor(name: name, email: email);
    await refreshAccess();
  }

  /// Clones the content repository into [directory] and starts using it.
  ///
  /// The token is needed for a private repository and harmless for a public
  /// one, so it is passed either way rather than asked about.
  Future<void> cloneInto(
    String directory, {
    void Function(String line)? onProgress,
  }) async {
    final token = await tokenStore.read() ?? '';
    await LocalClone.create(
      directory: directory,
      owner: contentOwner,
      repo: contentRepo,
      branch: contentBranch,
      token: token,
      onProgress: onProgress,
    );
    await useClone(directory);
  }

  /// Brings the clone up to date, and the catalogue with it.
  Future<void> pullClone() async {
    final path = _clonePath;
    if (path == null) return;
    final token = await tokenStore.read() ?? '';
    await LocalClone(directory: path).pull(token: token);
    await refreshAccess();
    await reloadCatalogue();
  }

  /// Sends the commits that are only on this machine.
  Future<void> pushClone() async {
    final path = _clonePath;
    if (path == null) return;
    final token = await tokenStore.read() ?? '';
    await LocalClone(directory: path).push(token: token);
    await refreshAccess();
  }

  Future<void> signOut() async {
    await auth.signOut();
    await refreshAccess();
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

  /// Where the catalogue is actually read from: the clone if there is one,
  /// otherwise whatever the app was built with.
  CatalogueSource get _source {
    final path = _clonePath;
    if (path == null) return catalogueSource;
    return CatalogueSource.inClone(path) ?? catalogueSource;
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

  Unit? unitByPath(String path) => _catalogue?.unitByPath(path);

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
