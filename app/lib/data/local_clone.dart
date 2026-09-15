/// A local clone of the content repository, driven by git.
///
/// This is the path the requirement asked for: *"Todo serían clones del
/// repositorio realizadas de forma local. Esto se ha de integrar para que se
/// haga con la propia aplicación sin necesidad de instalar y configurar
/// GitHub."*
///
/// So: the app clones, pulls, commits and pushes by itself, with the token
/// the author pasted once. Nothing to configure, no `gh auth login`, no
/// credential helper to set up, no SSH key. On a desktop that also means the
/// whole repository is on disk, so browsing and editing work with no network
/// at all and a push is what publishes.
///
/// Three decisions worth stating.
///
/// **The token never touches argv or `.git/config`.** It goes into the child
/// process's environment and is read from there by a one-line credential
/// helper. Writing it into the remote URL -- the usual shortcut -- would
/// leave it in a file in the clone, and `ps` shows every command line on a
/// shared machine.
///
/// **A write is still a compare-and-set.** The `sha` a read hands back is the
/// git blob hash of the file, and a commit checks the file still hashes to it
/// before touching anything. That catches the case this actually has to
/// catch: a `git pull` -- or another editor, or the author's own text editor
/// -- having changed the file since the screen loaded.
///
/// **A commit is pushed.** The rule is that every change is traceable and
/// revertible, and a commit sitting in a local clone is neither, for anyone
/// else. If the push fails the commit stays and the failure is reported, so
/// nothing is lost and the state is honest.
library;

import 'local_clone_stub.dart'
    if (dart.library.io) 'local_clone_io.dart'
    as platform;

/// Where the clone is, and how it stands against the remote.
class CloneStatus {
  const CloneStatus({
    required this.directory,
    required this.branch,
    required this.head,
    required this.ahead,
    required this.behind,
    required this.dirtyPaths,
  });

  final String directory;
  final String branch;

  /// The short hash of HEAD.
  final String head;

  /// Commits this clone has that the remote does not, and the other way
  /// round. Shown in Ajustes: "you have 3 commits nobody else can see" is
  /// something an author needs to know.
  final int ahead;
  final int behind;

  /// Files changed outside the app. Not an error -- someone may well have
  /// been editing in a text editor -- but the interface says so.
  final List<String> dirtyPaths;

  bool get isClean => dirtyPaths.isEmpty;
  bool get isSynced => ahead == 0 && behind == 0;
}

class CloneException implements Exception {
  const CloneException(this.message, {this.stderr = ''});

  final String message;

  /// What git actually said. Kept because git's own message is usually the
  /// most useful thing anyone could be shown.
  final String stderr;

  @override
  String toString() => stderr.isEmpty ? message : '$message\n\n$stderr';
}

/// The operations the app needs from a clone. One implementation on the
/// platforms that have a filesystem, one that refuses on the web.
abstract class LocalClone {
  /// The implementation for this platform.
  factory LocalClone({required String directory}) =>
      platform.makeClone(directory: directory);

  /// Whether a clone is possible here at all. False on the web, where there
  /// is no filesystem and no process to run git in.
  static bool get supported => platform.supported;

  /// Whether git is installed and usable. Checked rather than assumed: the
  /// failure to report is "git is not installed", not a stack trace.
  static Future<bool> gitAvailable() => platform.gitAvailable();

  /// Busca un clon del repositorio de contenido en los sitios donde suele
  /// estar, o null.
  ///
  /// Existe porque sin esto una compilación de escritorio hecha sin
  /// `--dart-define=DIDACTA_CLONE` no encuentra nada: el catálogo se busca
  /// por HTTP en una ruta relativa, que en una aplicación de escritorio no
  /// resuelve, y la pantalla dice «no se pudo cargar el catálogo» sin que
  /// falte ningún catálogo. La ruta iba dentro del binario y era invisible,
  /// así que la siguiente compilación la perdía sin avisar.
  ///
  /// Lo configurado manda siempre; esto es solo para la primera vez.
  static Future<String?> discover({
    String? configured,
    String? repo,
    String? enginePath,
  }) => platform.discoverClone(
    configured: configured,
    repo: repo,
    enginePath: enginePath,
  );

  /// Clones [owner]/[repo] into [directory], authenticating with [token].
  static Future<LocalClone> create({
    required String directory,
    required String owner,
    required String repo,
    required String branch,
    required String token,
    void Function(String line)? onProgress,
  }) => platform.cloneInto(
    directory: directory,
    owner: owner,
    repo: repo,
    branch: branch,
    token: token,
    onProgress: onProgress,
  );

  String get directory;

  /// Whether [directory] is a git clone with the expected remote.
  Future<bool> looksRight({required String owner, required String repo});

  /// La URL del remoto, o null si esto no es un clon.
  ///
  /// Hace falta para añadir una carpeta que ya está en el disco: de ahí sale
  /// de qué repositorio es, sin preguntarle nada a nadie ni tener que entrar
  /// en GitHub. Es lo que permite seguir trabajando con lo que ya tenías el
  /// día que la aplicación pasó a manejar varios.
  Future<String?> remoteUrl();

  Future<CloneStatus> status();

  /// The identity git is configured with here, if any.
  ///
  /// Needed because a commit needs an author and the desktop path must not
  /// require Firebase: someone with a clone on their own machine already has
  /// a git identity, and asking them to sign in to a web service to write a
  /// file on their own disk would be absurd.
  Future<({String name, String email})?> configuredAuthor();

  /// Sets the identity for this clone only.
  ///
  /// Local rather than global on purpose: the app has no business changing
  /// how git behaves everywhere else on someone's machine.
  Future<void> setAuthor({required String name, required String email});

  /// The file's text and its blob hash.
  Future<({String text, String sha})> readFile(String path);

  /// Writes, commits and pushes, in that order.
  ///
  /// [expectedSha] is the hash the caller read the file at; an empty string
  /// means "this file should not exist yet". Either mismatching is a
  /// conflict, and nothing is written.
  Future<String> commitFile({
    required String path,
    required String text,
    required String expectedSha,
    required String message,
    required String authorName,
    required String authorEmail,
    required String token,
    bool push = true,
  });

  /// Cierra en un commit lo que haya cambiado **bajo [paths]**.
  ///
  /// Por rutas y no un `git add -A`: una operación sobre una asignatura toca
  /// `courses/<id>` y nada más, y barrer todo el árbol se llevaría al commit
  /// un `.tex` que el autor tuviera a medias en otro sitio. Un commit que
  /// dice «Quitar la asignatura X» y lleva dentro media traducción es peor
  /// que no tener commit.
  ///
  /// Devuelve false cuando no había nada que guardar: un historial con
  /// commits vacíos es un historial que nadie lee.
  Future<bool> commitPaths({
    required List<String> paths,
    required String message,
    required String authorName,
    required String authorEmail,
    required String token,
    bool push = true,
  });

  /// Trae de GitHub lo que haya, **sin tocar el clon**.
  ///
  /// Separado de `pull` a propósito: preguntar «¿hay algo nuevo?» y «tráelo»
  /// son dos decisiones distintas, y la primera se puede hacer sola mientras
  /// alguien trabaja. Después de esto, `status()` sabe cuántos commits hay
  /// detrás sin volver a la red.
  Future<void> fetch({required String token});

  Future<void> pull({required String token});

  Future<void> push({required String token});
}
