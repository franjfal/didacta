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
import '../data/translation_secrets.dart';
import '../data/compiler.dart';
import '../data/diagnostics.dart';
import '../data/content_gateway.dart';
import '../data/draft_store.dart';
import '../data/course_admin.dart';
import '../data/frozen.dart';
import '../data/engine_pin.dart';
import '../data/file_manager.dart';
import '../data/legacy_identity.dart';
import '../data/notifier.dart';
import '../data/github.dart';
import '../data/local_clone.dart';
import '../data/preferences.dart';
import '../data/template_store.dart';
import '../data/toolchain.dart';
import '../model/catalogue.dart';
import '../model/file_history.dart' show FileCommit;
import '../model/folder_safety.dart';
import '../model/github_credential.dart';
import '../model/glossary.dart';
import '../model/latex_snippets.dart';
import '../model/slug.dart';
import '../model/synced_prefs.dart';
import '../data/translator.dart';
import '../model/translation_memory.dart';
import '../model/translation_run.dart';
import '../model/workspace.dart';
import '../model/saved_search.dart';
import '../model/text_search.dart';
import 'auth_state.dart';
import 'build_console.dart';
import 'build_service.dart';
import 'catalogue_editor.dart';
import 'catalogue_store.dart';
import 'engine_service.dart';
import 'freeze_service.dart';
import 'history.dart';
import 'languages.dart';
import 'library_prefs.dart';
import 'repo_sync.dart';
import 'repositories.dart';
import 'startup.dart';
import 'translation_service.dart';
import 'unsaved_work.dart';
import 'work_settings.dart';
import '../l10n/tr.dart';

export 'auth_state.dart' show KeychainProblem, SignInState;
export 'repositories.dart' show AppAccessMissing, MaterialCiException;
export 'translation_service.dart' show TranslationBatch, TranslationTask;

/// El repositorio del motor: éste mismo.
///
/// Es de donde se descarga `cli/didacta`, que es lo que compila. Configurable
/// al compilar para poder probar contra un fork, con el de verdad por
/// defecto.
const String engineOwner = String.fromEnvironment(
  'DIDACTA_ENGINE_OWNER',
  defaultValue: 'franjfal',
);
const String engineRepo = String.fromEnvironment(
  'DIDACTA_ENGINE_REPO',
  defaultValue: 'didacta',
);

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
    TranslationSecrets? translationSecrets,
    Preferences? preferences,
    this.files = const FileManager(),
    this.notifier = const SystemNotifier(),
    this.forgetLegacy = forgetLegacyData,
    DraftStore? drafts,
  }) : preferences = preferences ?? MemoryPreferences(),
       translationSecrets = translationSecrets ?? KeychainTranslationSecrets(),
       drafts = drafts ?? MemoryDraftStore();

  /// Dónde se copia lo que se escribe y no se ha guardado todavía. Ver
  /// `data/draft_store.dart`. En memoria salvo que se diga otra cosa: la
  /// aplicación pone el del disco, y una prueba no escribe en la carpeta de
  /// datos de quien la ejecuta.
  final DraftStore drafts;

  /// El explorador de archivos: abrir la carpeta de un repositorio y
  /// mandarla a la Papelera. Las pruebas ponen uno que sólo apunta.
  final FileManager files;

  /// Los avisos del sistema. Las pruebas ponen uno que sólo apunta: un test
  /// que compila no puede dejar notificaciones en el ordenador de quien lo
  /// ejecuta.
  final SystemNotifier notifier;

  /// Borrar lo que quede del nombre de antes, al restablecer.
  ///
  /// Inyectado por la misma razón que [files], y con más motivo: el de
  /// verdad borra carpetas y un dominio de preferencias de la carpeta de
  /// usuario **de quien ejecuta las pruebas**. Una prueba de «Restablecer»
  /// con el de verdad es un «Restablecer» de verdad.
  final Future<void> Function() forgetLegacy;

  final CatalogueSource catalogueSource;

  /// Por dónde se ha pasado, para los botones de atrás y adelante.
  ///
  /// Aquí y no en un proveedor aparte porque es estado de la aplicación como
  /// el idioma que se está mirando, y porque toda pantalla ya tiene la
  /// sesión a mano.
  final NavigationHistory history = NavigationHistory();

  /// Lo que hay escrito y sin guardar en alguna pantalla. Ver
  /// `state/unsaved_work.dart`.
  final UnsavedWork unsaved = UnsavedWork();

  /// Donde vive el token de GitHub: el llavero del sistema.
  final SecretStore tokenStore;

  /// El llavero de las credenciales de traducción.
  ///
  /// Aparte del token de GitHub aunque el mecanismo sea el mismo: salir de
  /// GitHub no puede llevarse por delante la clave de Azure, y quitar la clave
  /// de Azure no puede cerrarte la sesión.
  ///
  /// En la sesión y no en las preferencias porque **no son una preferencia**:
  /// `shared_preferences` es un fichero de texto en disco, y ahí no va una
  /// clave de API.
  final TranslationSecrets translationSecrets;

  /// Where the clone is, and whether a commit is pushed. Not secrets, so not
  /// in the keychain.
  final Preferences preferences;

  /// El catálogo, el índice y la vigilancia del disco: ver [CatalogueStore].
  late final CatalogueStore catalogueStore = CatalogueStore(
    this,
    onChanged: notifyListeners,
  );

  LoadState get state => catalogueStore.state;

  Object? get error => catalogueStore.error;

  /// Throws if read before [state] is ready. Callers inside the shell are
  /// past that point by construction, and an optional catalogue would put a
  /// null check in every screen for a state none of them can see.
  /// Lo que se está mirando: el catálogo **sin los repositorios apagados**.
  ///
  /// El filtro se aplica aquí, en el único sitio por el que pasan todas las
  /// pantallas, y no en cada una. Esa es la diferencia entre una interfaz con
  /// dos fuentes y dos interfaces pegadas: ninguna pantalla pregunta de qué
  /// repositorio es nada para decidir si lo enseña.
  ///
  /// Con una versión congelada abierta, **el de aquel commit**: ese es el
  /// punto de abrirla. Lo que la aplicación entera enseña pasa por aquí, así
  /// que ninguna pantalla tiene que preguntar si está mirando el presente.
  Catalogue get catalogue =>
      frozen?.catalogue ?? catalogueStore.visible ?? catalogueStore.full!;
  Catalogue? get catalogueOrNull =>
      frozen?.catalogue ?? catalogueStore.visible ?? catalogueStore.full;

  /// El catálogo entero, apagados incluidos. Lo mira quien tiene que hablar
  /// de los repositorios en sí: el filtro y los ajustes.
  Catalogue? get fullCatalogue => catalogueStore.full;

  /// La carpeta de plantillas del programa, cuando la hay: ver
  /// [CatalogueStore.templateStore].
  TemplateStore? get templateStore => catalogueStore.templateStore;

  Future<void> loadStoredTemplates() => catalogueStore.loadStoredTemplates();

  /// Si un repositorio se está mirando ahora mismo.
  bool isRepoVisible(String repo) =>
      !libraryPrefs.synced.hiddenRepos.contains(repo);

  /// Enciende o apaga un repositorio en la interfaz.
  ///
  /// Apagar no lo cierra: sigue abierto, sigue clonándose y sigue guardando
  /// lo que ya tenía. Lo que cambia es qué se está mirando, y por eso esto no
  /// toca el disco ni vuelve a leer el índice.
  Future<void> setRepoVisible(String repo, bool visible) async {
    if (isRepoVisible(repo) == visible) return;
    await libraryPrefs.change((prefs) => prefs.withRepoHidden(repo, !visible));
  }

  /// Los repositorios abiertos, sus pasarelas, abrirlos, añadirlos y
  /// quitarlos: ver [Repositories].
  late final Repositories repositories = Repositories(
    this,
    onChanged: notifyListeners,
  );

  /// Los repositorios abiertos, en orden.
  Workspace get workspace => repositories.workspace;

  /// Los repositorios abiertos, sin pasar por [workspace].
  ///
  /// Es lo que leen el catálogo, el índice y las demás piezas de la sesión:
  /// una prueba que sustituye [workspace] para que una pantalla crea que hay
  /// un repositorio no puede cambiar de dónde se lee el catálogo.
  @nonVirtual
  Workspace get openedWorkspace => repositories.workspace;

  /// La del primer repositorio, para lo que no tiene uno en la mano.
  ContentGateway get gateway => repositories.gateways.isEmpty
      ? const UnconfiguredGateway()
      : repositories.gateways.values.first;

  /// La del repositorio de un fichero.
  ///
  /// Es la pieza que hace posible trabajar con varios a la vez: cada pantalla
  /// tiene en la mano la unidad o el documento que está tocando, y de ahí sale
  /// a qué clon va lo que escriba.
  ContentGateway gatewayFor(String? repo) {
    // Con una congelación abierta se lee de su árbol y no se escribe. Aquí y
    // no en cada pantalla: un editor que pareciera editable y fallara al
    // guardar sería peor que uno que dice desde el principio que esto es una
    // foto de septiembre.
    final frozen = freezes.frozen;
    if (frozen != null) return FrozenGateway(view: frozen);
    if (repo == null || repo.isEmpty) return gateway;
    return repositories.gateways[repo] ??
        UnconfiguredGateway(tr('No está abierto el repositorio {0}.', [repo]));
  }

  /// Si se puede escribir en el repositorio de un fichero.
  bool canWriteIn(String? repo) => gatewayFor(repo).canWrite;

  /// La sesión de GitHub. Aparte --ver `auth_state.dart`-- y ofrecida aquí
  /// con los nombres de siempre.
  late final AuthState auth = AuthState(
    tokenStore: tokenStore,
    preferences: preferences,
    whoIs: (token) => whoIs(token),
    onRejected: () async {
      notifyListeners();
      await refreshAccess();
    },
    renew: (old) => renewCredential(old),
    // Las pasarelas llevan el token con el que se abrieron: con uno nuevo se
    // vuelven a abrir, que es lo que hace `refreshAccess`.
    onRenewed: () => refreshAccess(),
  );

  /// Pide a GitHub una credencial nueva con la de renovar de [old], con la
  /// misma App con la que se pidió. Aparte por lo mismo que [whoIs]: es ir a
  /// GitHub, y las pruebas lo sustituyen.
  Future<GitHubCredential> renewCredential(GitHubCredential old) async {
    final github = GitHubAuth(clientId: old.clientId ?? githubClientId);
    try {
      return await github.refresh(old.refreshToken ?? '');
    } finally {
      github.close();
    }
  }

  /// Quién ha entrado en GitHub, si alguien lo ha hecho.
  GitHubUser? get user => auth.user;

  /// Si hay sesión de GitHub. Es lo que decide si la aplicación se abre.
  SignInState get signInState => auth.state;

  bool get signedIn => auth.state == SignInState.signedIn;

  /// Por qué se cerró la sesión sola, si se cerró.
  Object? get signInProblem => auth.problem;

  /// Cómo se guarda, cómo se compila, qué paneles se ven y qué interfaz se
  /// enseña: ver [WorkSettings]. Se avisa sola; quien enseña uno de estos
  /// ajustes la escucha a ella.
  late final WorkSettings settings = WorkSettings(preferences);

  bool get commitOnSave => settings.commitOnSave;

  bool get pushOnCommit => settings.pushOnCommit;

  bool get reviewBeforeSave => settings.reviewBeforeSave;

  Future<void> setReviewBeforeSave(bool value) =>
      settings.setReviewBeforeSave(value);

  bool get completeInterface => settings.completeInterface;

  Future<void> setCompleteInterface(bool value) =>
      settings.setCompleteInterface(value);

  int get buildJobs => settings.buildJobs;

  Future<void> setBuildJobs(int value) => settings.setBuildJobs(value);

  bool get overfullLines => settings.overfullLines;

  Future<void> setOverfullLines(bool value) => settings.setOverfullLines(value);

  bool get accessiblePdf => settings.accessiblePdf;

  Future<void> setAccessiblePdf(bool value) => settings.setAccessiblePdf(value);

  bool get quickBuild => settings.quickBuild;

  Future<void> setQuickBuild(bool value) => settings.setQuickBuild(value);

  bool get notifyWhenBuilt => settings.notifyWhenBuilt;

  Future<void> setNotifyWhenBuilt(bool value) =>
      settings.setNotifyWhenBuilt(value);

  /// Si hay un token de GitHub guardado en esta máquina.
  bool get hasStoredToken => auth.token?.isNotEmpty ?? false;

  /// Whether storing one is even possible here. False on the web.
  bool get canStoreToken => tokenStore.canStoreSafely;

  /// El Client ID de la OAuth App con la que se entra.
  String get githubClientId => settings.githubClientId;

  /// Dónde se clonan los repositorios nuevos.
  String get cloneBase => settings.cloneBase;

  /// Whether a clone is possible at all here. False on the web.
  bool get canUseClone => LocalClone.supported;

  /// Traer, enviar y tener los clones al día: ver [RepoSync].
  late final RepoSync repoSync = RepoSync(this);

  CloneStatus? statusOf(String repo) => repoSync.statusOf(repo);

  /// Lo que falló al abrir cada repositorio, por si alguno no abre.
  Object? problemOf(String repo) => repositories.problems[repo];

  /// Who the clone's commits will be attributed to.
  ({String name, String email})? get cloneAuthor => repositories.cloneAuthor;

  /// Las carpetas de los clones abiertos.
  List<String> get repoPaths => [
    for (final repo in openedWorkspace.repos) repo.directory,
  ];

  /// El primero: lo que mira quien necesita **un** clon --vigilar el disco,
  /// compilar por defecto, buscar el motor al lado-- y no todos.
  String? get primaryPath => openedWorkspace.repos.isEmpty
      ? null
      : openedWorkspace.repos.first.directory;

  /// El clon de un repositorio, para compilar contra su raíz.
  String? pathOf(String? repo) => repo == null || repo.isEmpty
      ? primaryPath
      : openedWorkspace.directoryOf(repo);

  /// La credencial de GitHub, la que haya: la de la sesión o la del llavero.
  Future<String> currentToken() async => await auth.storedToken() ?? '';

  // -- las preferencias que viajan entre ordenadores ----------------------

  /// Lo marcado, lo oculto, lo plegado, los idiomas y los repositorios que se
  /// miran. Aparte --ver `library_prefs.dart`-- y ofrecido aquí con los
  /// nombres de siempre.
  late final LibraryPrefs libraryPrefs = LibraryPrefs(
    preferences: preferences,
    gatewayFor: gatewayFor,
    login: () => auth.user?.login,
  )..addListener(_libraryPrefsChanged);

  /// Los repositorios ocultos la última vez que se miró. El catálogo visible
  /// se rehace solo si cambian: rehacerlo es un catálogo nuevo, y con él se
  /// tiran los índices que se habían hecho del anterior.
  Set<String> _hiddenSeen = const {};

  /// Los idiomas encendidos la última vez que se miró.
  Set<String> _languagesSeen = const {};

  /// Lo que cambia en las preferencias de la biblioteca **avisa por ellas**:
  /// plegar un tema, marcar una asignatura o abrir una lección --que la
  /// apunta entre las recientes-- le importa a la lista que lo enseña, no a
  /// todas las pantallas. Solo dos cosas cambian lo que se ve en todas y
  /// avisan también por aquí: qué repositorios se miran y qué idiomas se
  /// ofrecen.
  void _libraryPrefsChanged() {
    final synced = libraryPrefs.synced;
    final hidden = {...synced.hiddenRepos};
    final languages = {...synced.enabledLanguages};
    var everywhere = false;
    if (!setEquals(hidden, _hiddenSeen)) {
      _hiddenSeen = hidden;
      catalogueStore.refilter();
      everywhere = true;
    }
    if (!setEquals(languages, _languagesSeen)) {
      _languagesSeen = languages;
      everywhere = true;
    }
    if (everywhere) notifyListeners();
  }

  /// Las preferencias sincronizadas, tal como están ahora mismo.
  SyncedPrefs get syncedPrefs => libraryPrefs.synced;

  /// En qué repositorio se guardan. Null es «en ninguno»: se quedan aquí.
  String? get prefsRepo => libraryPrefs.repo;

  /// Dónde se escriben dentro de ese repositorio.
  String? get prefsPath => libraryPrefs.path;

  // -- lo marcado ---------------------------------------------------------

  bool isFavouriteCourse(String course) =>
      libraryPrefs.synced.isFavouriteCourse(course);

  bool isFavouriteYear(String course, String year) =>
      libraryPrefs.synced.isFavouriteYear(course, year);

  Future<void> setFavouriteCourse(String course, bool favourite) => libraryPrefs
      .change((prefs) => prefs.withFavouriteCourse(course, favourite));

  Future<void> setFavouriteYear(String course, String year, bool favourite) =>
      libraryPrefs.change(
        (prefs) => prefs.withFavouriteYear(course, year, favourite),
      );

  // -- ocultar y plegar ---------------------------------------------------

  bool isHiddenCourse(String course) =>
      libraryPrefs.synced.isHiddenCourse(course);

  bool isHiddenYear(String course, String year) =>
      libraryPrefs.synced.isHiddenYear(course, year);

  bool isCollapsedCourse(String course) =>
      libraryPrefs.synced.isCollapsedCourse(course);

  /// Oculta una asignatura, o la vuelve a enseñar.
  ///
  /// Ocultar no es quitar: la asignatura sigue en el repositorio, sigue
  /// compilando y sigue en la biblioteca. Lo que cambia es la lista, que
  /// después de unos años son veinte asignaturas de las que se dan tres.
  Future<void> setCourseHidden(String course, bool hidden) =>
      libraryPrefs.change((prefs) => prefs.withCourseHidden(course, hidden));

  /// Oculta un curso académico, o lo vuelve a enseñar.
  Future<void> setYearHidden(String course, String year, bool hidden) =>
      libraryPrefs.change(
        (prefs) => prefs.withYearHidden(course, year, hidden),
      );

  /// Pliega una asignatura: se ve su título y no sus cursos.
  Future<void> setCourseCollapsed(String course, bool collapsed) => libraryPrefs
      .change((prefs) => prefs.withCourseCollapsed(course, collapsed));

  /// Qué se está mirando en la lista de asignaturas.
  ///
  /// Se guarda con lo demás: quien está ordenando la lista se queda un rato
  /// en «las ocultas», y volver a «las que doy» cada vez que se entra en otra
  /// pantalla convierte esa tarde en un baile de clics.
  String get coursesView => libraryPrefs.synced.coursesView;

  Future<void> setCoursesView(String view) async {
    if (libraryPrefs.synced.coursesView == view) return;
    await libraryPrefs.change((prefs) => prefs.withCoursesView(view));
  }

  /// Las asignaturas, por título.
  ///
  /// Por título y nada más. Las marcadas subían al principio, y era peor: la
  /// lista dejaba de estar donde se aprendió que estaba, y marcar una
  /// asignatura movía otras cuatro de sitio. La estrella dice «esta me
  /// importa» y no «esta va antes»; para no ver lo que no se da está
  /// ocultarla.
  ///
  /// Aquí y no en la pantalla porque el orden es una decisión de la
  /// aplicación, no del sitio donde se dibuja: si una lista lo hiciera por su
  /// cuenta, acabaría discrepando de la de al lado.
  List<Course> get sortedCourses {
    final courses = [...catalogue.courses];
    courses.sort((a, b) => compareTitles(a.title(language), b.title(language)));
    return courses;
  }

  /// Los cursos de una asignatura, del más reciente al más antiguo.
  ///
  /// Que es el orden en que se buscan, y ahora también sin excepciones: un
  /// curso marcado ya no se cuela delante, así que «el primero» vuelve a
  /// querer decir «el último que se dio».
  List<String> sortedYearsOf(Course course) {
    final years = course.years.keys.toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  /// Los temas plegados de un curso.
  Set<String> collapsedThemes(String course, String year) =>
      libraryPrefs.synced.collapsedIn(course, year);

  /// Pliega o despliega un tema, y lo apunta donde toque.
  Future<void> setThemeCollapsed({
    required String course,
    required String year,
    required String theme,
    required bool collapsed,
  }) => libraryPrefs.change(
    (prefs) => prefs.withThemeCollapsed(
      course: course,
      year: year,
      theme: theme,
      collapsed: collapsed,
    ),
  );

  /// Elige el repositorio donde se sincronizan, o quita el que hubiera.
  Future<void> setPrefsRepo(String? repo) => libraryPrefs.setRepo(repo);

  /// Lee las preferencias del repositorio elegido, si hay alguno.
  Future<void> loadSyncedPrefs() => libraryPrefs.load();

  /// Escribe las preferencias en el repositorio elegido, como un commit.
  Future<void> pushSyncedPrefs() => libraryPrefs.push();

  /// Si el panel de la derecha de una unidad está desplegado.
  bool get unitPanelVisible => settings.unitPanelVisible;

  /// Si los idiomas de una unidad se editan lado a lado.
  bool get splitEditors => settings.splitEditors;

  Future<void> setUnitPanelVisible(bool value) =>
      settings.setUnitPanelVisible(value);

  Future<void> setSplitEditors(bool value) => settings.setSplitEditors(value);

  /// El motor y TeX: ver [EngineService]. Encontrar el motor o perderlo
  /// cambia qué se puede compilar, y eso avisa también por aquí.
  late final EngineService engine = EngineService(
    this,
    onPathChanged: notifyListeners,
  );

  /// Where the engine repository is, for compiling.
  String? get enginePath => engine.enginePath;

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

  /// Y lo que git va diciendo mientras se trae o se envía.
  ///
  /// Separada de la de compilar y no la misma, aunque la ventana sea la
  /// misma: son dos trabajos que se lanzan por su cuenta y que se solapan
  /// --se envía mientras compila un tema-- y compartir el registro haría que
  /// el segundo borrase lo del primero. Una por trabajo, y cada botón abre
  /// la suya.
  final BuildConsole syncConsole = BuildConsole();

  /// The compiler, or null when there is nothing to compile with -- no
  /// engine, no clone, or a browser.
  ///
  /// Built fresh rather than held: it is a thin wrapper over a process, and
  /// caching it would mean caching a stale engine path.
  ///
  /// **El de lo que se está mirando.** Con una versión congelada abierta,
  /// compila y busca PDF en el árbol de aquella versión, igual que
  /// [gatewayFor] lee de él: antes compilaba lo de hoy mientras la pantalla
  /// enseñaba lo de septiembre, y «Ver PDF» abría un PDF que no era de la
  /// versión que se estaba mirando. Lo que escribe en el repositorio --
  /// administrar asignaturas, reindexar, abrir la propia congelación-- usa
  /// [liveCompiler], que es siempre el clon.
  Compiler? compiler({String? repo}) {
    final root = compileRootOf(repo);
    return root == null ? null : _compilerAt(root);
  }

  /// Dónde compila [compiler]: el árbol de la congelación abierta, o el clon.
  String? compileRootOf(String? repo) => frozen?.directory ?? pathOf(repo);

  /// El compilador del clon, con congelación o sin ella.
  Compiler? liveCompiler({String? repo}) {
    final clone = pathOf(repo);
    return clone == null ? null : _compilerAt(clone);
  }

  Compiler? _compilerAt(String root) {
    if (!Compiler.supported) return null;
    final enginePath = engine.enginePath;
    if (enginePath == null) return null;
    return Compiler(
      enginePath: enginePath,
      repositoryPath: root,
      texPath: engine.texPath,
      templateDirs: _templateDirsBesides(root),
      jobs: settings.buildJobs,
      overfullLines: settings.overfullLines,
      accessible: settings.accessiblePdf,
    );
  }

  /// Los demás sitios donde buscar plantillas al compilar en [clone].
  ///
  /// Los otros repositorios abiertos. El que se compila las lee él solo, así
  /// que se queda fuera para no pasarlo dos veces.
  ///
  /// Sin esto, compilar el repositorio de teoría con una plantilla que
  /// declara el de problemas da «perfil desconocido», y el material está
  /// repartido justamente así.
  List<String> _templateDirsBesides(String clone) => [
    for (final repo in openedWorkspace.repos)
      if (pathOf(repo.id) != null && pathOf(repo.id) != clone) pathOf(repo.id)!,
    // Y la carpeta del programa, que no es un repositorio de nadie.
    ?catalogueStore.templateStore?.directory,
  ];

  /// Dónde está TeX, si se ha tenido que decir a mano.
  String? get texPath => engine.texPath;

  /// Con qué se comprueba qué hay instalado en la máquina, y se instala.
  ///
  /// Sale de la sesión y no se construye en la pantalla por lo mismo que el
  /// compilador: es lo que permite que un test de widgets monte Ajustes sin
  /// lanzar `git --version` de verdad. Un proceso dentro de un test cuyo
  /// reloj es falso no termina nunca, y deja al banco de pruebas quejándose
  /// de un temporizador pendiente en una pantalla que no iba de esto.
  ///
  /// Se construye cada vez, como el compilador: es una envoltura fina sobre
  /// unos procesos, y guardarla sería guardar la ruta del motor de hace un
  /// rato.
  Toolchain toolchain() =>
      Toolchain(texPath: engine.texPath, enginePath: engine.enginePath);

  // -- el índice y el disco: ver [CatalogueStore] --------------------------

  void watchDisk() => catalogueStore.watchDisk();

  /// Se vuelve a la ventana: mirar el disco y, si la credencial de GitHub
  /// caduca, renovarla. Ver `_DidactaAppState._lifecycle`.
  Future<void> backInFront() async {
    await checkDisk();
    if (await auth.renewIfDue()) await refreshAccess();
  }

  Future<void> checkDisk() => catalogueStore.checkDisk();

  String? get indexNote => catalogueStore.indexNote;

  void dismissIndexNote() => catalogueStore.dismissIndexNote();

  Future<bool> refreshIndex({
    bool force = false,
    String? only,
    bool skipFresh = false,
    bool quiet = false,
  }) => catalogueStore.refreshIndex(
    force: force,
    only: only,
    skipFresh: skipFresh,
    quiet: quiet,
  );

  String get catalogueOrigin => catalogueStore.catalogueOrigin;

  /// Reloads the catalogue, for after a commit that changed structure. Ver
  /// [CatalogueStore.reloadCatalogue].
  Future<void> reloadCatalogue() => catalogueStore.reloadCatalogue();

  int? get behind => repoSync.behind;

  int get ahead => repoSync.ahead;

  Map<String, List<String>> get pendingChanges => repoSync.pendingChanges;

  Future<int> checkRemote() => repoSync.checkRemote();

  Object? get remoteProblem => repoSync.remoteProblem;

  @override
  void dispose() {
    auth.dispose();
    catalogueStore.dispose();
    libraryPrefs.dispose();
    settings.dispose();
    engine.dispose();
    freezes.dispose();
    startup.dispose();
    builds.dispose();
    repoSync.dispose();
    buildConsole.dispose();
    syncConsole.dispose();
    super.dispose();
  }

  /// El botón de actualizar: el índice, el catálogo y lo compilado.
  Future<void> refreshEverything() async {
    // Buscar el motor solo si no hay: encontrarlo es mirar el disco, y
    // hacerlo cuando ya tenemos uno es trabajo por nada.
    if (compiler() == null) await engine.find();
    repoSync.forgetRemoteProblem();
    await refreshIndex(force: true);
    await reloadCatalogue();
    await refreshBuilt();
    await catalogueStore.rememberIndexDates();
    // Un repositorio al que le acaba de aparecer `generated/` no se estaba
    // vigilando: ahora sí.
    watchDisk();
    // Y lo de fuera. Al final y no al principio: lo de este disco es lo que
    // se está mirando ahora mismo, y la red puede tardar.
    await checkRemote();
  }

  /// El motor frente a la aplicación: si es el de su versión.
  EngineVersion? get engineVersion => engine.version;

  /// Mira la versión del motor. Ver [EngineService.checkVersion].
  Future<void> checkEngineVersion() => engine.checkVersion();

  /// Poner el motor en la versión de la aplicación, a petición. Ver
  /// [EngineService.pinNow].
  Future<void> pinEngineNow() => engine.pinNow();

  /// Qué hay compilado, por unidad. Ver [BuildService.built].
  Map<String, List<ExistingOutput>> get built => builds.built;

  /// Si ya se ha preguntado. Distinto de «no hay nada compilado».
  bool get builtKnown => builds.builtKnown;

  /// La versión que se abre al ojear una unidad desde la biblioteca. Ver
  /// [WorkSettings.previewProfile].
  String get previewProfile => settings.previewProfile;

  Future<void> setPreviewProfile(String id) => settings.setPreviewProfile(id);

  /// El clon en un directorio.
  ///
  /// Un solo sitio donde se construye, para que un test pueda dar otro sin
  /// que la sesión tenga que saber que está en un test.
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

  /// Si se puede buscar en el texto de las lecciones: hace falta una copia
  /// local, porque lo que busca es git en la carpeta.
  bool get canSearchText =>
      LocalClone.supported &&
      openedWorkspace.repos.any((repo) => cloneFor(repo.id) != null);

  /// Las líneas de las lecciones que dicen [query], sin mirar tildes ni
  /// mayúsculas, en todos los repositorios con copia local.
  ///
  /// Con tres letras por lo menos: con menos, «de» está en todas. Un
  /// repositorio que no contesta no deja sin resultados a los demás.
  Future<List<TextHit>> searchText(String query) async {
    final text = query.trim();
    if (text.length < 3) return const [];
    final pattern = accentPattern(text);
    final found = <TextHit>[];
    for (final repo in openedWorkspace.repos) {
      final clone = cloneFor(repo.id);
      if (clone == null) continue;
      try {
        for (final hit in await clone.grep(pattern)) {
          found.add(hit.inRepo(repo.id));
        }
      } on CloneException {
        continue;
      }
    }
    return found;
  }

  // -- lo reciente y las búsquedas guardadas --------------------------------

  /// Cuántas lecciones recientes se recuerdan: las de una tarde de trabajo.
  static const int recentLimit = LibraryPrefs.recentLimit;

  /// Las últimas lecciones abiertas, la más reciente primero, sin las que ya
  /// no están en el catálogo.
  List<Unit> get recentUnits => [
    for (final key in libraryPrefs.recent) ?_unitByKey(key),
  ];

  Unit? _unitByKey(String key) {
    final bar = key.indexOf('|');
    if (bar < 0) return unitByPath(key);
    final repo = key.substring(0, bar);
    return unitByPath(key.substring(bar + 1), repo: repo.isEmpty ? null : repo);
  }

  /// Apunta que se ha abierto [unit].
  void noteOpened(Unit unit) =>
      libraryPrefs.noteOpened('${unit.repo}|${unit.path}');

  List<SavedSearch> get savedSearches => libraryPrefs.savedSearches;

  /// Guarda [url] --una dirección de la biblioteca-- con [name]. Si ya había
  /// una con esa dirección, se renombra.
  Future<void> saveSearch(String name, String url) =>
      libraryPrefs.saveSearch(name, url);

  Future<void> forgetSearch(String url) => libraryPrefs.forgetSearch(url);

  /// Para un test: el clon, sin pasar por Ajustes ni por el disco.
  @visibleForTesting
  Future<void> useCloneForTest(String path) => useClonesForTest([path]);

  /// Para un test: varios clones, que es donde están los fallos que solo
  /// aparecen con más de uno abierto.
  @visibleForTesting
  Future<void> useClonesForTest(List<String> paths) async {
    repositories.workspace = Workspace([
      for (var index = 0; index < paths.length; index += 1)
        ContentRepo(
          owner: 'test',
          name: 'repo${index == 0 ? '' : index}',
          directory: paths[index],
        ),
    ]);
  }

  /// Para un test: quién firma los commits, sin git ni GitHub.
  ///
  /// Lo normal es que salga de la cuenta con la que se entró, o de lo que
  /// tenga configurado git en la máquina, y las dos cosas las averigua
  /// `refreshAccess` yendo al disco. Una prueba de widgets no puede.
  @visibleForTesting
  void setCloneAuthorForTest(({String name, String email}) author) {
    repositories.cloneAuthor = author;
  }

  /// Para un test: lo compilado, sin motor que lo diga.
  @visibleForTesting
  Future<void> setBuiltForTest(Map<String, List<ExistingOutput>> built) async =>
      builds.setForTest(built);

  // -- editar el material ---------------------------------------------------
  //
  // Aparte, en `catalogue_editor.dart`: los metadatos, los títulos, las
  // titulaciones, los bloques, los snippets, las plantillas y el estado de
  // cada traducción. Ofrecido aquí con los nombres de siempre.

  late final CatalogueEditor editor = CatalogueEditor(
    this,
    onChanged: notifyListeners,
  );

  static const String snippetsPath = CatalogueEditor.snippetsPath;

  static const String programTemplates = CatalogueEditor.programTemplates;

  Future<ContentFile?> approveTranslation({
    required Unit unit,
    required String language,
    String? text,
    String sha = '',
  }) => editor.approveTranslation(
    unit: unit,
    language: language,
    text: text,
    sha: sha,
  );

  List<Course> coursesUsing(String repo, String code) =>
      editor.coursesUsing(repo, code);

  Future<void> createDegree({
    required String repo,
    required String id,
    required Map<String, String> titles,
    String? institution,
  }) => editor.createDegree(
    repo: repo,
    id: id,
    titles: titles,
    institution: institution,
  );

  Future<void> declareBlock({
    required String repo,
    required String id,
    required Map<String, String> titles,
  }) => editor.declareBlock(repo: repo, id: id, titles: titles);

  Future<void> declareTemplate({
    required String repo,
    required String id,
    required Map<String, String> titles,
    required String documentClass,
    String classOptions = '',
    Map<String, String> axes = const {},
    String preamble = '',
  }) => editor.declareTemplate(
    repo: repo,
    id: id,
    titles: titles,
    documentClass: documentClass,
    classOptions: classOptions,
    axes: axes,
    preamble: preamble,
  );

  Future<int> moveUnitsBetweenBlocks({
    required String from,
    required String to,
  }) => editor.moveUnitsBetweenBlocks(from: from, to: to);

  Unit? nextToReview(String language, {String? after}) =>
      editor.nextToReview(language, after: after);

  Future<({String text, FileCommit commit})?> originalAtReview(
    Unit unit,
    String language, {
    int depth = 200,
  }) => editor.originalAtReview(unit, language, depth: depth);

  Future<void> setUnitTemplates({
    required String repo,
    required String path,
    required List<String> templates,
  }) => editor.setUnitTemplates(repo: repo, path: path, templates: templates);

  Future<SnippetPreview?> previewSnippet(
    LatexSnippet snippet, {
    String profile = 'notes',
    String? repo,
    void Function(String line)? onOutput,
  }) => editor.previewSnippet(
    snippet,
    profile: profile,
    repo: repo,
    onOutput: onOutput,
  );

  Future<int> removeBlock({required String id, String? moveTo}) =>
      editor.removeBlock(id: id, moveTo: moveTo);

  Future<int> removeSnippet(LatexSnippet snippet) =>
      editor.removeSnippet(snippet);

  Future<int> removeTemplate({required String id}) =>
      editor.removeTemplate(id: id);

  Future<int> reorderSnippets(List<String> order) =>
      editor.reorderSnippets(order);

  Future<int> resolveMetadata({
    required MetadataConflict conflict,
    required String value,
  }) => editor.resolveMetadata(conflict: conflict, value: value);

  Future<int> saveSnippet(LatexSnippet snippet, {required Set<String> repos}) =>
      editor.saveSnippet(snippet, repos: repos);

  Future<int> setBlockTemplates({
    required String id,
    required List<String> templates,
  }) => editor.setBlockTemplates(id: id, templates: templates);

  Future<int> setBlockTitles({
    required String id,
    required Map<String, String> titles,
  }) => editor.setBlockTitles(id: id, titles: titles);

  Future<int> setCourseDegree({
    required String course,
    required String? degree,
  }) => editor.setCourseDegree(course: course, degree: degree);

  Future<int> setCourseLanguages({
    required String course,
    required List<String> languages,
  }) => editor.setCourseLanguages(course: course, languages: languages);

  Future<int> setCourseTitles({
    required String course,
    required Map<String, String> titles,
  }) => editor.setCourseTitles(course: course, titles: titles);

  Future<int> setDegreeTitles({
    required String id,
    required Map<String, String> titles,
  }) => editor.setDegreeTitles(id: id, titles: titles);

  Future<void> setDocumentTemplates({
    required String repo,
    required String course,
    required String year,
    required String id,
    required List<String> templates,
  }) => editor.setDocumentTemplates(
    repo: repo,
    course: course,
    year: year,
    id: id,
    templates: templates,
  );

  Future<void> setDocumentTitles({
    required String repo,
    required String course,
    required String year,
    required String id,
    required Map<String, String> titles,
  }) => editor.setDocumentTitles(
    repo: repo,
    course: course,
    year: year,
    id: id,
    titles: titles,
  );

  Future<void> setRepoLanguages({
    required String repo,
    required List<String> languages,
  }) => editor.setRepoLanguages(repo: repo, languages: languages);

  Future<int> setTemplateActive({required String id, required bool active}) =>
      editor.setTemplateActive(id: id, active: active);

  Future<void> setTemplatePreamble({
    required String repo,
    required String id,
    required String text,
  }) => editor.setTemplatePreamble(repo: repo, id: id, text: text);

  Future<int> setTemplateShape({
    required String id,
    required String documentClass,
    required String classOptions,
    required Map<String, String> axes,
  }) => editor.setTemplateShape(
    id: id,
    documentClass: documentClass,
    classOptions: classOptions,
    axes: axes,
  );

  Future<int> setTemplateTitles({
    required String id,
    required Map<String, String> titles,
  }) => editor.setTemplateTitles(id: id, titles: titles);

  Future<void> setThemeTitles({
    required String repo,
    required String course,
    required String year,
    required String id,
    required Map<String, String> titles,
  }) => editor.setThemeTitles(
    repo: repo,
    course: course,
    year: year,
    id: id,
    titles: titles,
  );

  Future<void> setUnitBlock({
    required String repo,
    required String path,
    required String block,
  }) => editor.setUnitBlock(repo: repo, path: path, block: block);

  Future<void> setUnitIndent({
    required Unit unit,
    required String language,
    required bool on,
  }) => editor.setUnitIndent(unit: unit, language: language, on: on);

  Future<void> setUnitStatus({
    required Unit unit,
    required String language,
    required String status,
  }) => editor.setUnitStatus(unit: unit, language: language, status: status);

  List<SnippetConflict> get snippetConflicts => editor.snippetConflicts;

  /// Si «Entre repositorios» tiene algo que enseñar: metadatos que no
  /// coinciden, lecciones sin bloque, documentos que llaman fuera o snippets
  /// que no coinciden.
  ///
  /// Es lo que decide si sale en el carril con la interfaz Esencial: un
  /// apartado que casi siempre dice «todo cuadra» se deja de abrir, y el día
  /// que hay algo nadie lo mira.
  bool get betweenReposNeedsLooking {
    final catalogue = catalogueOrNull;
    if (catalogue == null || !workspace.isMultiple) return false;
    return catalogue.metadataConflicts.isNotEmpty ||
        catalogue.undeclaredBlocks.isNotEmpty ||
        catalogue.crossRepoUses.isNotEmpty ||
        snippetConflicts.isNotEmpty;
  }

  List<SnippetEntry> get snippetLibrary => editor.snippetLibrary;

  List<String> get snippetRepos => editor.snippetRepos;

  List<LatexSnippet> snippetsIn(String? repo) => editor.snippetsIn(repo);

  String templateHomeLabel(String home) => editor.templateHomeLabel(home);

  Future<String> templatePreamble({required String repo, required String id}) =>
      editor.templatePreamble(repo: repo, id: id);

  Future<String> tidyLatex(String text) => editor.tidyLatex(text);

  Future<void> undeclareBlock({required String repo, required String id}) =>
      editor.undeclareBlock(repo: repo, id: id);

  Future<void> undeclareDegree({required String repo, required String id}) =>
      editor.undeclareDegree(repo: repo, id: id);

  Future<int> useSnippetFrom({required String id, required String repo}) =>
      editor.useSnippetFrom(id: id, repo: repo);

  // -- traducir -----------------------------------------------------------
  //
  // Aparte, en `translation_service.dart`, y ofrecido aquí con los nombres de
  // siempre.

  late final TranslationService translations = TranslationService(this);

  /// La memoria de un par de idiomas, junta de todos los repositorios.
  Future<TranslationMemory> translationMemory({
    required String from,
    required String to,
  }) => translations.memoryFor(from: from, to: to);

  Future<Glossary> glossaryIn(String repo) => translations.glossaryIn(repo);

  Future<Glossary> glossary() => translations.glossary();

  Future<void> saveGlossary(String repo, Glossary glossary) =>
      translations.saveGlossary(repo, glossary);

  Future<TranslationResult> translateUnit({
    required Unit unit,
    required String from,
    required String to,
    required Translator translator,
    List<TermCheck> terms = const [],
  }) => translations.translateUnit(
    unit: unit,
    from: from,
    to: to,
    translator: translator,
    terms: terms,
  );

  Future<TranslationEstimate> estimateTranslation(
    List<TranslationTask> tasks,
  ) => translations.estimate(tasks);

  Future<TranslationBatch> translateUnits({
    required List<TranslationTask> tasks,
    required Translator translator,
    List<TermCheck> terms = const [],
    bool Function()? stop,
    void Function(int done, TranslationTask task)? onProgress,
    bool failFast = false,
    bool useGlossary = true,
  }) => translations.translateUnits(
    tasks: tasks,
    translator: translator,
    terms: terms,
    stop: stop,
    onProgress: onProgress,
    failFast: failFast,
    useGlossary: useGlossary,
  );

  // -- compilar en lote ---------------------------------------------------
  //
  // Aparte, en `build_service.dart`: la cola de compilaciones, compilar
  // documentos en tanda y lo que hay compilado. Ofrecido aquí con los
  // nombres de siempre.

  late final BuildService builds = BuildService(this);

  /// Cuántas compilaciones esperan detrás de la que está en marcha.
  int get queuedBuilds => builds.queued;

  /// Si se ha pedido parar y todavía no ha parado.
  bool get stoppingBuild => builds.stopping;

  Future<T?> runBuild<T>(
    String title,
    Future<T> Function(BuildConsole console) job, {
    int total = 0,
  }) => builds.run(title, job, total: total);

  Future<void> stopBuilds() => builds.stop();

  Future<int> buildDocuments(
    List<({String repo, String course, String year, String id, String title})>
    documents, {
    required String title,
    List<String> languages = const [],
    bool everyVersion = false,
    Map<String, List<({String profile, String language})>>? only,
  }) => builds.buildDocuments(
    documents,
    title: title,
    languages: languages,
    everyVersion: everyVersion,
    only: only,
  );

  /// Vuelve a preguntar qué hay compilado.
  Future<void> refreshBuilt() => builds.refreshBuilt();

  Future<void> setTexPath(String? path) => engine.setTexPath(path);

  // -- Versiones congeladas -------------------------------------------------
  //
  // Abrir una congelación cambia **qué se está mirando**, y por eso pasa por
  // aquí: es el único sitio por el que pasan todas las pantallas. Ninguna
  // tiene que preguntar si está en una versión antigua; lo que reciben es el
  // catálogo de aquel día y una pasarela que no deja escribir, y con eso ya
  // se comportan bien. Ver [FreezeService].

  late final FreezeService freezes = FreezeService(
    this,
    onChanged: notifyListeners,
  );

  /// La congelación que se está mirando, o null si es la versión actual.
  FrozenView? get frozen => freezes.frozen;

  bool get isFrozen => freezes.isFrozen;

  /// Cómo va la apertura, para poder contarlo mientras dura.
  FrozenStep? get frozenStep => freezes.step;

  /// Lo que abre, compara y restaura, para un repositorio.
  Frozen? frozenIn(String? repo) => freezes.frozenIn(repo);

  /// Abre una versión congelada. A partir de aquí todo es de solo lectura.
  ///
  /// El catálogo que se enseña es el de **ese repositorio** en ese commit. Una
  /// congelación es un commit de un repositorio, así que si la asignatura está
  /// repartida entre dos, lo que se ve es la mitad congelada -- y decirlo es
  /// mejor que mezclar la foto de septiembre de uno con lo de hoy del otro.
  Future<void> openFreeze(Freeze freeze, {String? repo}) =>
      freezes.open(freeze, repo: repo);

  /// Para un test de pantalla: la congelación ya abierta.
  ///
  /// Abrirla de verdad habla con git y lee un árbol del disco, y eso dentro
  /// de una prueba de widgets --cuyo reloj es falso-- no termina. Que abrirla
  /// funcione se prueba contra git de verdad en `frozen_repo_test.dart`; lo
  /// que se prueba desde la pantalla es qué enseña cuando ya está abierta.
  @visibleForTesting
  void useFrozenForTest(FrozenView? view) => freezes.useForTest(view);

  /// Vuelve a la versión actual.
  ///
  /// El árbol de la congelación se queda en la caché: volver a abrirla es lo
  /// que más se hace --se compara, se vuelve, se compara otra vez-- y
  /// recrearlo cada vez sería pagar la copia que esto existe para no pagar.
  void leaveFreeze() => freezes.leave();

  /// Vacía la caché de árboles de congelación. No pierde nada.
  Future<int> clearFrozenCache() => freezes.clearCache();

  /// Cuántos árboles de congelación hay guardados ahora mismo.
  Future<int> frozenCacheSize() => freezes.cacheSize();

  /// Las congelaciones de un curso, las más nuevas primero.
  List<Freeze> freezesOf(String courseId, String year) =>
      freezes.freezesOf(courseId, year);

  /// El commit que congelaría ahora mismo: el HEAD del repositorio.
  Future<String> headOf(String? repo) => freezes.headOf(repo);

  /// Si hay cambios sin guardar en el clon de un repositorio. Ver
  /// [FreezeService.pendingIn].
  Future<List<String>> pendingIn(String? repo) => freezes.pendingIn(repo);

  /// Crear, duplicar y borrar asignaturas y años.
  ///
  /// Null cuando no se puede: hace falta el clon --para escribir y para
  /// hacer el commit-- y el motor, que es el que sabe hacer cada operación.
  /// La pantalla lo dice en lugar de ofrecer botones que no funcionan.
  CourseAdmin? admin({String? repo}) {
    final compiler = liveCompiler(repo: repo);
    final path = pathOf(repo);
    if (compiler == null || path == null) return null;
    return CourseAdmin(
      compiler: compiler,
      clone: LocalClone(directory: path),
      author: cloneAuthor,
      token: auth.token ?? '',
      pushOnCommit: pushOnCommit,
      // Crear o borrar una asignatura es una modificación como cualquier
      // otra, y de las que más daño hacen si se hacen sobre una copia vieja:
      // toca la estructura del repositorio entero.
      beforeWrite: () {
        catalogueStore.forgetIndexFresh(repo);
        return ensureFresh(repo);
      },
      // Y al terminar deja el índice hecho: la recarga de después no tiene
      // que volver a mirarlo.
      onIndexed: () => catalogueStore.markIndexFresh(repo),
    );
  }

  /// Looks for the engine and remembers it.
  ///
  /// Called after the clone is known, because the likeliest place for the
  /// engine is next to it.
  Future<void> findEngine() => engine.findOrThrow();

  Future<void> setEnginePath(String? path) async {
    await preferences.setEnginePath(path);
    await refreshAccess();
  }

  // -- qué idiomas se ofrecen: ver [LanguageChoices] -----------------------

  late final LanguageChoices languages = LanguageChoices(
    this,
    onChanged: notifyListeners,
  );

  /// The language the interface is working in. Not a locale -- the app's own
  /// text is Spanish -- but which language of the *content* is being looked
  /// at, which is the choice that actually matters here.
  String get language => languages.language;

  set language(String code) => languages.language = code;

  bool isLanguageEnabled(String code) => languages.isEnabled(code);

  Future<void> setLanguageEnabled(String code, bool on) =>
      languages.setEnabled(code, on);

  List<LanguageOption> get languageChoices => languages.choices;

  List<LanguageOption> languageChoicesFor(Course course) =>
      languages.choicesFor(course);

  List<String> languagesIn(String? courseId) => languages.codesIn(courseId);

  List<LanguageOption> languagesToEdit({
    required List<String> allowed,
    required List<String> declared,
  }) => languages.toEdit(allowed: allowed, declared: declared);

  /// Lo mismo, en códigos, para quien no necesite los nombres.
  List<String> languagesToEditCodes({
    required List<String> allowed,
    required List<String> declared,
  }) => [
    for (final option in languagesToEdit(allowed: allowed, declared: declared))
      option.code,
  ];

  List<LanguageOption> namedLanguages(
    List<String> codes, {
    List<String> or = const [],
  }) => languages.named(codes, or: or);

  // -- el arranque: ver [Startup] -----------------------------------------

  late final Startup startup = Startup(this, onChanged: notifyListeners);

  /// Qué está haciendo el arranque, para la pantalla de carga. Null fuera
  /// de él.
  String? get startStep => startup.step;

  Future<void> start() => startup.run();

  /// Los repositorios ocultos la última vez que se miró: ver
  /// [_libraryPrefsChanged]. El arranque los apunta al leer las preferencias.
  void noteHiddenRepos() {
    _hiddenSeen = {...libraryPrefs.synced.hiddenRepos};
    _languagesSeen = {...libraryPrefs.synced.enabledLanguages};
  }

  /// Why the stored settings could not be read, if they could not be.
  Object? get settingsProblem => startup.settingsProblem;

  /// Why working out how to reach the content failed, if it did.
  ///
  /// Kept and shown in Ajustes. The app is usable without it -- reading the
  /// public catalogue needs no access at all -- so this is a degraded state
  /// and not a broken one.
  Object? get accessProblem => repositories.accessProblem;

  /// Vuelve a abrir los repositorios y a recalcular sus pasarelas.
  ///
  /// Se llama después de entrar, de salir, de añadir o quitar uno, y al
  /// arrancar. Derivar en lugar de ir tocando estados sueltos es lo que
  /// garantiza que no pueda quedar una pasarela que escribe en un repositorio
  /// que ya no está abierto.
  Future<void> refreshAccess() async {
    await repositories.refresh();
    // Las preferencias sincronizadas, después: hacen falta la pasarela del
    // repositorio y el login de quien ha entrado, y las dos salen de arriba.
    // Sin esperar a que terminen: lo local ya está puesto, y esto solo puede
    // mejorarlo.
    unawaited(loadSyncedPrefs());
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
  ///
  /// Sin `@protected`: lo llama [Repositories]. Sigue siendo el punto que
  /// sustituyen las pruebas, y por eso se llama siempre por la sesión.
  Future<GitHubRepo?> accessTo(String owner, String name) async {
    return GitHubApi(token: await currentToken()).repository(owner, name);
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

  Future<void> setCommitOnSave(bool value) async {
    await preferences.setCommitOnSave(value);
    await refreshAccess();
  }

  Future<int> commitPending(
    String message, {
    Map<String, List<String>>? only,
  }) => repoSync.commitPending(message, only: only);

  int get pendingCount => repoSync.pendingCount;

  /// Sets who the clone's commits are attributed to, for this clone only.
  Future<void> setCloneAuthor({required String name, required String email}) =>
      repositories.setCloneAuthor(name: name, email: email);

  // -- los repositorios ---------------------------------------------------

  /// Guarda el Client ID de la OAuth App con la que se entra.
  Future<void> setGithubClientId(String value) =>
      settings.setGithubClientId(value);

  /// Dónde se clonan los repositorios nuevos.
  Future<void> setCloneBase(String path) => settings.setCloneBase(path);

  /// Guarda el token de GitHub y mira quién es.
  ///
  /// Quién es se pregunta **aquí y sin red de seguridad**: entrar es el único
  /// momento en el que se puede exigir que GitHub conteste, y un token que no
  /// se ha podido comprobar ni una vez no es una sesión. Lo que se guarda es
  /// el resultado de esa comprobación, y es lo que permite que los arranques
  /// siguientes valgan sin red.
  Future<void> signIn(String token) =>
      signInWith(GitHubCredential(token: token));

  /// Entra con una credencial entera: la de una GitHub App trae el de renovar
  /// y cuándo caduca. Ver `model/github_credential.dart`.
  Future<void> signInWith(GitHubCredential credential) async {
    await auth.signInWith(credential);
    repoSync.forgetFreshness();
    await repositories.dropUnreachable();
    await refreshAccess();
  }

  /// Sale de GitHub. Los clones se quedan: son carpetas de esta máquina con
  /// el trabajo dentro, y borrarlas al salir sería perderlo.
  Future<void> signOut() async {
    await auth.signOut();
    // Avisando ya, antes de volver a abrir los repositorios: salir tiene que
    // devolver a la puerta en el acto. Lo que viene después --mirar el estado
    // de cada clon, buscar el motor-- habla con git y con el disco, y dejar
    // la biblioteca de alguien que acaba de salir en pantalla mientras tanto
    // sería enseñar lo que se acaba de cerrar.
    notifyListeners();
    await refreshAccess();
  }

  /// Dónde se clonaría un repositorio, y qué hay ya ahí. Ver
  /// [Repositories.inspectTarget].
  Future<({String directory, CloneTarget state})> inspectTarget({
    required String owner,
    required String name,
    String? directory,
  }) => repositories.inspectTarget(
    owner: owner,
    name: name,
    directory: directory,
  );

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
  }) => repositories.add(
    owner: owner,
    name: name,
    branch: branch,
    directory: directory,
    colour: colour,
    onProgress: onProgress,
  );

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
  }) => repositories.initialize(
    owner: owner,
    name: name,
    branch: branch,
    title: title,
    directory: directory,
    colour: colour,
    onProgress: onProgress,
  );

  /// Crea el repositorio de ejemplo en la cuenta de quien ha entrado, lo
  /// siembra con el curso que trae la aplicación y lo abre.
  ///
  /// Privado y con un nombre libre: `didacta-ejemplo`, o `didacta-ejemplo-2`
  /// si aquel ya está cogido por otra cosa. Si ya existe **y es de contenido**
  /// es el ejemplo de otra vez, y se abre ese en lugar de crear otro: quien
  /// vuelve a pulsar el botón quiere su ejemplo, no una colección de ellos.
  ///
  /// Devuelve el repositorio abierto y si ya existía.
  Future<({ContentRepo repo, bool reused})> createExampleRepository({
    Map<String, String>? files,
    void Function(String what)? onStep,
    void Function(String line)? onProgress,
  }) => repositories.createExample(
    files: files,
    onStep: onStep,
    onProgress: onProgress,
  );

  /// Crea un repositorio vacío y privado en GitHub. Aparte por lo mismo que
  /// [accessTo]: una prueba no puede crear repositorios de verdad.
  ///
  /// Sin `@protected`: lo llama [Repositories]. Sigue siendo el punto que
  /// sustituyen las pruebas, y por eso se llama siempre por la sesión.
  Future<GitHubRepo> createGitHubRepository({
    required String name,
    String description = '',
  }) async {
    final api = GitHubApi(token: await currentToken());
    try {
      return await api.createRepository(name: name, description: description);
    } finally {
      api.close();
    }
  }

  /// Si un repositorio de GitHub es de contenido de Didacta.
  ///
  /// Sin `@protected`: lo llama [Repositories]. Sigue siendo el punto que
  /// sustituyen las pruebas, y por eso se llama siempre por la sesión.
  Future<bool> isContentRepository(String owner, String name) async {
    final api = GitHubApi(token: await currentToken());
    try {
      return await api.isContentRepo(owner, name);
    } finally {
      api.close();
    }
  }

  /// Si el token puede enviar un commit que toca `.github/workflows/`.
  ///
  /// Null es que no se ha podido preguntar. Un token de antes de que Didacta
  /// pidiera el permiso `workflow` no puede, y GitHub rechaza el envío entero:
  /// el commit se quedaría aquí sin enviar y taparía los de después. Por eso
  /// se pregunta **antes** de escribir un workflow, y no se escribe si no.
  /// Punto de sustitución de las pruebas, como [accessTo].
  Future<bool?> canPushWorkflows() async {
    final api = GitHubApi(token: await currentToken());
    try {
      final scopes = await api.scopes();
      return scopes == null || scopes.contains('workflow');
    } catch (caught, trace) {
      Diagnostics.instance.note('session.canPushWorkflows', caught, trace);
      return null;
    } finally {
      api.close();
    }
  }

  /// De dónde se clona un repositorio. Null es GitHub; una prueba lo apunta
  /// a un repositorio desnudo del disco.
  ///
  /// Sin `@protected`: lo llama [Repositories]. Sigue siendo el punto que
  /// sustituyen las pruebas, y por eso se llama siempre por la sesión.
  String? remoteFor(String owner, String name) => null;

  /// Añade una carpeta que ya está en el disco.
  ///
  /// De qué repositorio es lo dice su propio remoto, así que esto funciona
  /// sin entrar en GitHub: un clon que ya tenías sigue siendo tuyo. Es también
  /// el camino de vuelta para quien tenía la aplicación de antes, cuando había
  /// un solo clon configurado en Ajustes.
  Future<ContentRepo> addExistingRepository(String directory) =>
      repositories.addExisting(directory);

  /// Qué impidió dejar al día el último repositorio añadido, si algo lo hizo.
  Object? get addProblem => repositories.addProblem;

  static const Duration freshFor = RepoSync.freshFor;

  static const Duration freshFetchLimit = RepoSync.freshFetchLimit;

  Future<void> ensureFresh(String? repo) => repoSync.ensureFresh(repo);

  String saveNotice(String? repo, {int files = 1}) =>
      repoSync.saveNotice(repo, files: files);

  Object? driftOf(String repo) => repoSync.driftOf(repo);

  /// Si todavía no hay ningún repositorio con el que trabajar.
  bool get needsRepository => openedWorkspace.isEmpty;

  /// Si la presentación de bienvenida ya se ha visto. Ver
  /// [Startup.welcomeDone].
  bool? get welcomeDone => startup.welcomeDone;

  /// La bienvenida se ha terminado --o se ha saltado--, y no vuelve.
  Future<void> completeWelcome() => startup.completeWelcome();

  /// Volver a enseñarla. Es lo que hace el botón de Ajustes.
  Future<void> replayWelcome() => startup.replayWelcome();

  /// Clona el motor --este mismo repositorio-- al lado de los de contenido.
  ///
  /// Existe porque es el único paso de la configuración que no se puede hacer
  /// desde la aplicación y que hace falta para compilar: la biblioteca y el
  /// editor funcionan solo con el clon de contenido, pero sacar un PDF
  /// necesita `cli/didacta`, que vive en otro repositorio.
  ///
  /// Se puede clonar sin haber entrado en GitHub --es público-- y por eso el
  /// token va vacío si no hay ninguno: pedir una sesión para descargar algo
  /// que cualquiera puede descargar sería inventarse un requisito.
  Future<String> installEngine({
    String owner = engineOwner,
    String repo = engineRepo,
    void Function(String line)? onProgress,
  }) => engine.install(owner: owner, repo: repo, onProgress: onProgress);

  /// Lo quita del espacio de trabajo. La carpeta se queda donde está: lleva
  /// trabajo dentro, y borrarla es otra decisión que hay que pedir aparte.
  ///
  /// Se pide con [trashFolder]: entonces la carpeta va a la
  /// Papelera --nunca se borra del todo--, y sólo si [whyNotTrash] no
  /// encuentra nada dentro que no sea suyo. Devuelve qué pasó con la carpeta
  /// si no se pudo tirar, o `null`. Que no se pueda no deshace el quitarlo:
  /// ya no está en la lista, y la carpeta sigue donde estaba.
  Future<String?> removeRepository(String id, {bool trashFolder = false}) =>
      repositories.remove(id, trashFolder: trashFolder);

  /// Deja Didacta en este ordenador como recién instalada.
  ///
  /// Borra la sesión de GitHub, las claves de traducción, todos los ajustes
  /// --la lista de repositorios, la bienvenida vista, dónde se clona-- y lo
  /// que quedara del nombre de antes. Las carpetas de los repositorios y las
  /// plantillas guardadas en el programa, sólo si se pide con [folders] y
  /// [templates], y a la Papelera.
  ///
  /// Después hay que volver a arrancar la aplicación ([restartApp]): lo que
  /// hay en memoria sigue siendo lo de antes, y es arrancar de nuevo lo que lo
  /// lee todo desde cero.
  ///
  /// Devuelve lo que no se pudo tirar. Lo demás se borra igual: una carpeta
  /// que no se deja tirar no es razón para dejar la sesión abierta.
  Future<List<String>> resetEverything({
    bool folders = false,
    bool templates = false,
  }) => repositories.resetEverything(folders: folders, templates: templates);

  /// Si [repo] compila su material en GitHub. Ver
  /// [Repositories.hasMaterialCi].
  Future<bool?> hasMaterialCi(String repo) => repositories.hasMaterialCi(repo);

  /// Que [repo] compile su material en GitHub en cada envío. Ver
  /// [Repositories.addMaterialCi].
  Future<void> addMaterialCi(String repo) => repositories.addMaterialCi(repo);

  /// Cambia el color con el que se marca un repositorio en la interfaz.
  Future<void> setRepositoryColour(String id, int colour) =>
      repositories.setColour(id, colour);

  Future<Map<String, Object>> pullAll() => repoSync.pullAll();

  Future<List<RepoOutbox>> outbox() => repoSync.outbox();

  Future<Map<String, Object>> pushAll(
    String message, {
    bool commitPending = true,
  }) => repoSync.pushAll(message, commitPending: commitPending);

  /// Installs a catalogue directly, for tests and for a build that ships one.
  ///
  /// Skips [start] entirely, so nothing has to reach a network or a keychain
  /// to exercise a screen.
  @visibleForTesting
  Future<void> primeForTest(Catalogue catalogue) async {
    // Las preferencias que deciden cómo se guarda, también: las lee
    // `refreshAccess`, que se va al disco y a git, y un test de widgets no
    // puede llamarla --el reloj es falso y el proceso no vuelve--.
    await settings.restoreWorking();
    await libraryPrefs.restoreLocal();

    // Y con sesión iniciada si hay token guardado, porque **Didacta no se
    // abre sin ella**: hay una puerta delante de todas las pantallas, así
    // que una pantalla montada en un test es siempre la de alguien que
    // entró. Un test que quiera lo contrario pide un llavero vacío
    // --`StubStore(token: null)`-- y lo dice.
    auth.token = await auth.readToken();
    if ((auth.token ?? '').isNotEmpty) auth.state = SignInState.signedIn;

    catalogueStore.loaded(catalogue);
    languages.resetTo(catalogue);
    notifyListeners();
  }

  // -- lookups the screens need ------------------------------------------

  Unit? unitByPath(String path, {String? repo}) =>
      catalogueOrNull?.unitByPath(path, repo: repo);

  /// El color con el que se marca un repositorio, o null si no hay más de uno
  /// --con uno solo, marcar no dice nada--.
  int? colourOf(String? repo) {
    if (!openedWorkspace.isMultiple || repo == null || repo.isEmpty) {
      return null;
    }
    return openedWorkspace.byId(repo)?.colour;
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
  ///
  /// Una vez por catálogo e idioma: el carril lo pide para su contador en
  /// cada redibujado, y eran dos mil unidades filtradas y ordenadas cada vez.
  List<Unit> needingTranslation(String language) {
    final catalogue = catalogueOrNull;
    final cached = _needing;
    if (cached != null &&
        identical(cached.catalogue, catalogue) &&
        cached.language == language) {
      return cached.units;
    }
    final units = [
      for (final unit in catalogue?.units ?? const <Unit>[])
        if (unit.statusIn(language).needsWork) unit,
    ];
    units.sort((a, b) {
      // Most used first: translating a unit six courses depend on is worth
      // more than one nobody teaches.
      final byUse = b.usedBy.length.compareTo(a.usedBy.length);
      return byUse != 0 ? byUse : a.path.compareTo(b.path);
    });
    final frozen = List<Unit>.unmodifiable(units);
    _needing = (catalogue: catalogue, language: language, units: frozen);
    return frozen;
  }

  ({Catalogue? catalogue, String language, List<Unit> units})? _needing;
}

/// La huella del original que declara [language] en un `unit.yaml`, escrita
/// en línea (`va: {status: reviewed, source_hash: sha256:…}`) o en bloque.
///
/// Solo dentro de `languages:`: el título también tiene una línea por idioma
/// (`title:` / `  va: …`), va antes, y se la tomaba por la del estado --así
/// que «Ver qué ha cambiado» no encontraba nunca la huella--.
String? declaredSourceHash(String yaml, String language) {
  final lines = yaml.split('\n');
  final head = RegExp('^(\\s+)${RegExp.escape(language)}:\\s*(.*)\$');
  var inLanguages = false;
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) {
      inLanguages = RegExp(r'^languages:\s*$').hasMatch(line);
      continue;
    }
    if (!inLanguages) continue;
    final match = head.firstMatch(line);
    if (match == null) continue;
    final rest = match.group(2)!;
    final inline = RegExp(r'source_hash:\s*([^,}\s]+)').firstMatch(rest);
    if (inline != null) return inline.group(1);
    if (rest.trim().isNotEmpty) return null;
    final indent = match.group(1)!.length;
    for (var j = i + 1; j < lines.length; j += 1) {
      final line = lines[j];
      if (line.trim().isEmpty) continue;
      if (line.length - line.trimLeft().length <= indent) break;
      final block = RegExp(r'^\s+source_hash:\s*(\S+)').firstMatch(line);
      if (block != null) return block.group(1);
    }
    return null;
  }
  return null;
}
