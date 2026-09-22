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

import 'dart:convert';

import '../model/file_history.dart';
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

/// Qué hay donde iría un clon.
///
/// Tres casos y no un booleano, porque los tres se tratan distinto: uno se
/// clona, otro se reutiliza y el tercero no se toca.
enum CloneTarget {
  /// No existe, o existe y está vacía. Se puede clonar.
  free,

  /// Ya es un clon de ese mismo repositorio. No hay que volver a clonarlo:
  /// basta con ponerlo al día, y lo que haya sin enviar se conserva.
  alreadyCloned,

  /// Tiene otra cosa dentro. Aquí no se escribe: puede ser el trabajo de
  /// alguien, y «no estaba vacía» es lo único que se puede decir con certeza.
  occupied,
}

/// Un árbol de trabajo aparte, parado en un commit.
///
/// Es lo que hace que abrir una congelación no cueste una copia del
/// repositorio: git ya tiene ese commit, y un worktree es una carpeta con sus
/// ficheros y nada más -- sin otro `.git`, sin otra historia y sin tocar el
/// árbol de trabajo de siempre.
class Worktree {
  const Worktree({required this.directory, required this.commit});

  final String directory;

  /// El commit entero al que está parado.
  final String commit;
}

/// Qué le pasó a un fichero entre dos commits.
enum TreeChangeKind { added, removed, modified, renamed }

class TreeChange {
  const TreeChange({required this.kind, required this.path, this.from = ''});

  final TreeChangeKind kind;

  /// La ruta al final. En un renombrado, la nueva.
  final String path;

  /// De dónde venía, cuando se movió.
  final String from;
}

/// Cómo de hondo hay que cavar para traerse un commit que no está.
///
/// Un clon shallow no tiene la historia entera, y un commit congelado hace un
/// año puede no estar en él. Traerlo **entero** funcionaría siempre y es lo
/// que no se hace: un repositorio de material son cientos de megas y nadie
/// pidió descargarlos por abrir una versión de septiembre.
enum FetchDepth {
  /// El commit y nada más. Es lo que hace GitHub cuando lo permite.
  justTheCommit,

  /// Unos cuantos commits más de historia. Se repite si hace falta.
  deeper,

  /// La historia entera. El último recurso, y se dice antes de hacerlo.
  everything,
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

/// El repositorio de GitHub no tiene ningún commit, así que no hay nada que
/// clonar: ni `main` ni ninguna otra rama.
///
/// Una excepción propia y no el mensaje de git --«Remote branch main not
/// found»--, porque aquí sí hay algo que hacer, que es prepararlo, y quien
/// llama tiene que poder distinguirlo de un fallo de red o de permisos.
class EmptyRepositoryException extends CloneException {
  EmptyRepositoryException({required this.owner, required this.repo})
    : super(
        '$owner/$repo está vacío en GitHub: todavía no tiene ningún commit, '
        'así que no hay nada que clonar.',
      );

  final String owner;
  final String repo;
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

  /// Qué hay en la carpeta donde iría un clon, **antes de tocarla**.
  ///
  /// Existe porque clonar puede escribir encima del trabajo de alguien, y eso
  /// no se hace sin decirlo: con dos personas usando la misma máquina, o con
  /// un clon hecho a mano, la carpeta de destino puede estar ocupada. Saber
  /// cuál de los tres casos es permite preguntar lo que se puede preguntar
  /// --«ya está clonado, ¿lo uso?»-- y negarse a lo que no --escribir sobre
  /// otra cosa.
  static Future<CloneTarget> inspect({
    required String directory,
    required String owner,
    required String repo,
  }) => platform.inspectTarget(directory: directory, owner: owner, repo: repo);

  /// Clones [owner]/[repo] into [directory], authenticating with [token].
  ///
  /// Un repositorio sin commits lanza [EmptyRepositoryException] antes de
  /// crear la carpeta, y un clon que falla no la deja detrás. [url] sustituye
  /// a la de GitHub: es para las pruebas, que clonan de un repositorio
  /// desnudo del disco.
  static Future<LocalClone> create({
    required String directory,
    required String owner,
    required String repo,
    required String branch,
    required String token,
    String? url,
    void Function(String line)? onProgress,
  }) => platform.cloneInto(
    directory: directory,
    owner: owner,
    repo: repo,
    branch: branch,
    token: token,
    url: url,
    onProgress: onProgress,
  );

  /// Prepara un repositorio de GitHub **vacío** como repositorio de contenido
  /// y lo deja clonado en [directory].
  ///
  /// Clona el repositorio vacío, escribe [settingsFor] con [title] y
  /// [ignoredFiles], hace el primer commit en [branch] a nombre del autor y
  /// lo envía. Si algo falla por el camino la carpeta se borra: dentro solo
  /// está lo que se acaba de generar, y dejarla a medias haría que el
  /// siguiente intento la tomara por un clon bueno.
  ///
  /// Si mientras tanto alguien ha empujado algo, no se toca y se dice:
  /// preparar encima sería competir con la historia de otra persona.
  static Future<LocalClone> initialize({
    required String directory,
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required String title,
    required String authorName,
    required String authorEmail,
    String? url,
    void Function(String line)? onProgress,
  }) => platform.initializeInto(
    directory: directory,
    owner: owner,
    repo: repo,
    branch: branch,
    token: token,
    title: title,
    authorName: authorName,
    authorEmail: authorEmail,
    url: url,
    onProgress: onProgress,
  );

  /// El `didacta.yaml` de un repositorio recién preparado.
  ///
  /// Los mismos valores que el motor toma por defecto, pero escritos: un
  /// fichero vacío también valdría, y uno que dice qué se puede ajustar se
  /// entiende sin ir a buscar la documentación. El nombre va entre comillas
  /// de JSON, que YAML lee igual, para que unos dos puntos o una almohadilla
  /// en el título no rompan el fichero.
  static String settingsFor(String title) =>
      '''
# Un repositorio de contenido de Didacta.
#
# Todo tiene un valor por defecto que funciona. El fichero existe sobre todo
# para marcar la raíz del repositorio: el motor sube buscándolo, igual que git
# busca .git.

name: ${jsonEncode(title)}

# Los idiomas que mantiene este repositorio. Didacta trae es, va y en.
languages: [es, va, en]

# El idioma que se supone cuando nada dice otra cosa.
default_language: es

# Dónde van los PDF. Relativo a la raíz del repositorio, y fuera de git: lo
# compilado no se versiona.
build_dir: .didacta-build
''';

  /// El `.gitignore` de un repositorio recién preparado.
  static const String ignoredFiles = '''
# Lo compilado. Los PDF salen de las fuentes que tienen al lado, así que
# guardarlos sería tener la misma información dos veces y dejar que no
# coincidan.
.didacta-build/
''';

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

  /// Los commits que tocaron [path], del más reciente al más antiguo.
  ///
  /// Con `--follow`, así que un fichero que se movió sigue teniendo el
  /// historial de antes de moverse. Es lo que hace que reorganizar `content/`
  /// --que pasa-- no borre de la vista tres años de trabajo.
  ///
  /// [limit] porque un historial se lee por arriba: nadie baja hasta el
  /// commit 400, y pedirlos todos es tiempo de git por nada.
  Future<List<FileCommit>> history(String path, {int limit});

  /// Qué le hizo [sha] a [path], con [context] líneas alrededor de cada
  /// cambio.
  ///
  /// El diff lo calcula git y aquí se lee: un commit puede renombrar, puede
  /// venir de una fusión y puede tocar un binario, y eso no se deduce
  /// comparando dos textos.
  ///
  /// [context] es lo que git llama `--unified`. Con [wholeFile] la respuesta
  /// deja de ser «los alrededores del cambio» y pasa a ser el fichero entero
  /// con el cambio marcado dentro, que es lo que hace falta para leer una
  /// versión y no solo su parte.
  Future<FileDiff> diffOf({
    required String sha,
    required String path,
    int context,
  });

  /// El [context] que pide el fichero entero en lugar de un recorte.
  ///
  /// Un número y no una bandera aparte porque para git es lo mismo: no hay
  /// ningún fichero de material con un millón de líneas, así que pedir un
  /// millón de líneas de contexto es pedirlo todo.
  static const int wholeFile = 1000000;

  /// El contenido de [path] tal y como estaba en [sha], o null si en ese
  /// commit no había ningún fichero con ese nombre.
  ///
  /// Hace falta para los commits que no cambiaron el contenido --un
  /// renombrado, un cambio de permisos, una fusión-- porque de esos no sale
  /// diff y aun así hay una versión que enseñar.
  Future<String?> fileAt({required String sha, required String path});

  /// Writes, commits and pushes, in that order.
  ///
  /// [expectedSha] is the hash the caller read the file at; an empty string
  /// means "this file should not exist yet". Either mismatching is a
  /// conflict, and nothing is written.
  /// Escribe un fichero **sin hacer commit**, con la misma comprobación.
  ///
  /// Para cuando los commits no son automáticos: lo escrito se queda en el
  /// árbol de trabajo, sale en `status()` como pendiente, y alguien lo
  /// confirma después con el mensaje que quiera. Guardar y decidir qué
  /// contar son dos cosas distintas, y hay quien prefiere hacer la segunda
  /// una vez al terminar en vez de treinta veces mientras escribe.
  ///
  /// El compare-and-set es el mismo que el de [commitFile] y por lo mismo:
  /// un `git pull` --o el editor de texto de quien escribe-- puede haber
  /// movido el fichero desde que se abrió la pantalla.
  Future<String> writeFile({
    required String path,
    required String text,
    required String expectedSha,
  });

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
    void Function(String line)? onProgress,
  });

  /// Trae de GitHub lo que haya, **sin tocar el clon**.
  ///
  /// Separado de `pull` a propósito: preguntar «¿hay algo nuevo?» y «tráelo»
  /// son dos decisiones distintas, y la primera se puede hacer sola mientras
  /// alguien trabaja. Después de esto, `status()` sabe cuántos commits hay
  /// detrás sin volver a la red.
  Future<void> fetch({required String token});

  /// [onProgress] recibe lo que git va diciendo, línea a línea.
  ///
  /// Con alguien escuchando se le pide a git que **cuente lo que hace**:
  /// normalmente se calla porque no está hablando con un terminal, y un
  /// `push` de setecientos ficheros son minutos de silencio absoluto. Lo que
  /// tiene que decir --cuántos objetos lleva contados, comprimidos y
  /// subidos-- es exactamente lo que distingue esperar de estar colgado.
  Future<void> pull({
    required String token,
    void Function(String line)? onProgress,
  });

  Future<void> push({
    required String token,
    void Function(String line)? onProgress,
  });

  /// El SHA entero de HEAD.
  ///
  /// Entero y no corto: una congelación lo guarda durante años, y un prefijo
  /// que hoy es único deja de serlo cuando el repositorio crece.
  Future<String> head();

  /// Si este clon tiene ese commit.
  Future<bool> hasCommit(String sha);

  /// Si este clon se hizo sin la historia entera.
  Future<bool> isShallow();

  /// Trae un commit que no está, cavando lo menos posible.
  ///
  /// Primero pidiéndolo por su SHA, que es lo barato y lo que GitHub permite;
  /// después profundizando la historia por tramos; y solo si nada de eso vale,
  /// entera. [onStep] cuenta cada intento para poder decir por qué está
  /// tardando -- una descarga silenciosa de trescientos megas es indistinguible
  /// de un cuelgue.
  Future<void> fetchCommit(
    String sha, {
    required String token,
    void Function(FetchDepth step) onStep,
  });

  /// Un árbol de trabajo parado en [sha], creándolo o reutilizando el que ya
  /// hubiera.
  ///
  /// Se abre **en solo lectura desde Didacta**: nada de lo que hace la
  /// aplicación escribe ahí. Y no toca el clon de siempre -- ni su HEAD, ni su
  /// índice, ni su árbol de trabajo.
  Future<Worktree> worktreeAt(String sha);

  /// Quita el árbol de trabajo de ese commit, si lo hay.
  ///
  /// No borra el commit ni toca la historia: lo único que se va es la carpeta
  /// de la caché.
  Future<void> removeWorktree(String sha);

  /// Los árboles de trabajo que tiene la caché.
  Future<List<Worktree>> worktrees();

  /// Vacía la caché de árboles de trabajo.
  Future<int> clearWorktrees();

  /// Qué cambió entre dos commits, limitado a [paths] cuando se dan.
  ///
  /// Con los renombrados detectados: un fichero que se movió tiene que salir
  /// como movido y no como un borrado más un alta, que es la diferencia entre
  /// «reorganizaron la carpeta» y «perdimos treinta lecciones».
  Future<List<TreeChange>> changesBetween({
    required String from,
    required String to,
    List<String> paths,
  });

  /// El diff de un fichero entre dos commits.
  Future<FileDiff> diffBetween({
    required String from,
    required String to,
    required String path,
    int context,
  });

  /// Las rutas que existen bajo [under] en ese commit.
  Future<List<String>> pathsAt({required String sha, String under = ''});

  /// Escribe en el árbol de trabajo el contenido que [sha] tenía bajo
  /// [paths], y borra lo que en ese commit no existía.
  ///
  /// **No hace `reset`, no mueve HEAD y no reescribe nada.** Deja los ficheros
  /// como estaban entonces y ya está: lo que quede es un cambio pendiente,
  /// que se confirma como cualquier otro. Devuelve lo que ha tocado.
  Future<List<TreeChange>> restoreFrom({
    required String sha,
    required List<String> paths,
  });

  /// Lo que haría [restoreFrom], sin tocar nada.
  ///
  /// Se enseña antes de restaurar. «Esto va a cambiar catorce ficheros y
  /// borrar dos» es lo que permite decidir; «¿seguro?» no lo es.
  Future<List<TreeChange>> previewRestore({
    required String sha,
    required List<String> paths,
  });
}
