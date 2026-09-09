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
import '../data/content_gateway.dart';
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
  });

  final CatalogueSource catalogueSource;

  /// Only an [AuthSession]: this class has no business knowing that Firebase
  /// is what provides it, and depending on Firebase here would make every
  /// screen need it running -- including in a test.
  final AuthSession auth;

  final SecretStore tokenStore;

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

  /// Whether a repository token is stored on this machine.
  bool get hasStoredToken => _hasToken;

  /// Whether storing one is even possible here. False on the web.
  bool get canStoreToken => tokenStore.canStoreSafely;

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
  /// The catalogue is loaded first and on its own: it is the only thing the
  /// app cannot show anything without. Auth failing is a degraded state, not
  /// a broken one -- the public catalogue still lists.
  Future<void> start() async {
    _state = LoadState.loading;
    notifyListeners();

    try {
      _catalogue = await catalogueSource.load();
      _language = _catalogue!.defaultLanguage;
      _state = LoadState.ready;
    } catch (error) {
      _error = error;
      _state = LoadState.failed;
      notifyListeners();
      return;
    }

    // Auth is watched rather than read once, so signing in or out updates
    // every screen without any of them subscribing to Firebase themselves.
    auth.changes.listen((_) => refreshAccess());
    await refreshAccess();
  }

  /// Recomputes the authorisation and the gateway from scratch.
  ///
  /// Called on every auth change and after a token is stored or cleared.
  /// Deriving rather than mutating is what guarantees the two cannot drift.
  Future<void> refreshAccess() async {
    _hasToken = (await tokenStore.read())?.isNotEmpty ?? false;

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

  /// Picks the gateway. A stored token wins over the API, because someone who
  /// has gone to the trouble of authorising this machine wants the direct,
  /// offline-capable path.
  Future<ContentGateway> _deriveGateway() async {
    final token = await tokenStore.read();
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

  /// Reloads the catalogue, for after a commit that changed structure.
  Future<void> reloadCatalogue() async {
    try {
      _catalogue = await catalogueSource.load();
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
