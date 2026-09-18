/// The clone, on a platform that has a filesystem and can run git.
///
/// Everything here goes through the `git` command rather than a Dart git
/// implementation, and that is a deliberate trade: git is already on every
/// machine this runs on, it is the reference implementation of the format,
/// and a bug in a reimplementation would corrupt the repository that is the
/// source of truth for two thousand units.
library;

import 'dart:convert';
import 'dart:io';

import '../model/file_history.dart';
import 'local_clone.dart';

bool get supported => true;

Future<bool> gitAvailable() async {
  try {
    final result = await Process.run('git', ['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

LocalClone makeClone({required String directory}) =>
    _GitClone(directory: directory);

/// El fichero que identifica el repositorio de contenido.
///
/// Se comprueba junto con `.git`: una carpeta que se llame `didacta_db` y no
/// sea un clon no sirve --no se podría hacer un commit-- y elegirla a la
/// callada sería peor que no encontrar nada.
const String _marker = 'didacta.yaml';

Future<bool> _isClone(String directory) async =>
    await File('$directory/$_marker').exists() &&
    await Directory('$directory/.git').exists();

Future<String?> discoverClone({
  String? configured,
  String? repo,
  String? enginePath,
}) async {
  // Lo configurado manda, incluso si no existe: decirlo es mejor que
  // sustituirlo por otra cosa a la callada. Es la misma regla que el motor.
  if (configured != null && configured.isNotEmpty) return configured;

  final names = <String>{
    if (repo != null && repo.isNotEmpty) repo,
    'didacta_db',
  };
  final home = Platform.environment['HOME'] ?? '';
  final candidates = <String>[];

  // Una variable de entorno, para quien lo tenga en un sitio raro y no
  // quiera tocar Ajustes.
  for (final key in ['DIDACTA_DB', 'DIDACTA_CLONE']) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty) candidates.add(value);
  }

  // Al lado del motor. Es la disposición que dice el README --los dos
  // repositorios hermanos-- y la que tiene quien esté editando el motor.
  if (enginePath != null && enginePath.isNotEmpty) {
    final parent = Directory(enginePath).parent.path;
    candidates.addAll([for (final name in names) '$parent/$name']);
  }

  // Hacia arriba desde donde se ejecuta. Sirve para `flutter run` desde
  // `app/`, donde el clon está dos niveles por encima; en una aplicación
  // empaquetada el directorio actual es `/` y esto no da nada.
  var here = Directory.current;
  for (var i = 0; i < 4; i += 1) {
    candidates.addAll([for (final name in names) '${here.path}/$name']);
    final up = here.parent;
    if (up.path == here.path) break;
    here = up;
  }

  if (home.isNotEmpty) {
    for (final folder in [
      '',
      '/Documents',
      '/Developer',
      '/Projects',
      '/src',
    ]) {
      candidates.addAll([for (final name in names) '$home$folder/$name']);
    }
  }

  for (final candidate in candidates) {
    if (await _isClone(candidate)) return candidate;
  }
  return null;
}

Future<LocalClone> cloneInto({
  required String directory,
  required String owner,
  required String repo,
  required String branch,
  required String token,
  String? url,
  void Function(String line)? onProgress,
}) async {
  final remote = url ?? _url(owner, repo);
  final target = Directory(directory);
  if (await target.exists() && target.listSync().isNotEmpty) {
    final existing = _GitClone(directory: directory);
    if (await existing.looksRight(owner: owner, repo: repo)) {
      // Already a clone of the right repository: keep it and catch it up
      // rather than refusing, because "the folder is not empty" is not
      // something an author can act on when the folder is the right one.
      onProgress?.call(
        'La carpeta ya es un clon de $owner/$repo; '
        'actualizándolo.',
      );
      await existing.pull(token: token);
      return existing;
    }
    throw CloneException(
      'La carpeta $directory no está vacía y no es un clon de '
      '$owner/$repo. Elige otra carpeta.',
    );
  }

  // Antes de crear nada. Un repositorio recién creado en GitHub no tiene
  // ninguna rama, y git lo cuenta como «Remote branch main not found», que
  // ni dice lo que pasa ni deja ver que tiene arreglo.
  if (await _remoteIsEmpty(remote, token: token, label: '$owner/$repo')) {
    throw EmptyRepositoryException(owner: owner, repo: repo);
  }

  await _intoFresh(
    target,
    () => _run(
      ['clone', '--branch', branch, remote, '.'],
      directory: directory,
      token: token,
      onProgress: onProgress,
      what: 'clonar $owner/$repo',
    ),
  );
  return _GitClone(directory: directory);
}

Future<LocalClone> initializeInto({
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
}) async {
  final remote = url ?? _url(owner, repo);
  final target = Directory(directory);
  if (await target.exists() && target.listSync().isNotEmpty) {
    throw CloneException(
      'La carpeta $directory no está vacía. Vacíala o elige otra antes de '
      'preparar $owner/$repo.',
    );
  }

  // Se vuelve a mirar justo antes: entre que se ofreció prepararlo y se
  // aceptó, alguien puede haber empujado.
  if (!await _remoteIsEmpty(remote, token: token, label: '$owner/$repo')) {
    throw CloneException(
      '$owner/$repo ya no está vacío: alguien ha subido algo mientras tanto. '
      'Vuelve a añadirlo desde GitHub.',
    );
  }

  Future<String> git(
    List<String> arguments,
    String what, {
    Map<String, String>? environment,
  }) => _run(
    arguments,
    directory: directory,
    what: what,
    token: token,
    onProgress: onProgress,
    environment: environment,
  );

  await _intoFresh(target, () async {
    await git(['clone', remote, '.'], 'clonar $owner/$repo');

    // Un clon vacío apunta HEAD a la rama por defecto de *esta* máquina, que
    // puede ser `master`. La que manda es la del repositorio en GitHub.
    await git([
      'symbolic-ref',
      'HEAD',
      'refs/heads/$branch',
    ], 'elegir la rama $branch');

    File(
      '$directory/$_marker',
    ).writeAsStringSync(LocalClone.settingsFor(title));
    File('$directory/.gitignore').writeAsStringSync(LocalClone.ignoredFiles);
    await git([
      'add',
      '--',
      _marker,
      '.gitignore',
    ], 'preparar el primer commit');

    await git(
      [
        '-c',
        'user.name=$authorName',
        '-c',
        'user.email=$authorEmail',
        'commit',
        '--message',
        'Preparar el repositorio de contenido de Didacta',
      ],
      'hacer el primer commit',
      environment: {
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      },
    );

    // Con `--set-upstream`: sin rama de seguimiento, traer y enviar después
    // no sabrían contra qué, y el estado no podría decir si está al día.
    await git([
      'push',
      '--set-upstream',
      'origin',
      branch,
    ], 'enviar el primer commit a GitHub');
  });
  return _GitClone(directory: directory);
}

String _url(String owner, String repo) => 'https://github.com/$owner/$repo.git';

/// Si el remoto no tiene ninguna referencia, que es lo que tiene un
/// repositorio recién creado en GitHub.
Future<bool> _remoteIsEmpty(
  String remote, {
  required String token,
  required String label,
}) async {
  final refs = await _runIn(
    ['ls-remote', remote],
    // En una carpeta que seguro que existe: la de destino todavía no.
    directory: Directory.systemTemp.path,
    what: 'consultar $label',
    token: token,
  );
  return refs.trim().isEmpty;
}

/// Hace [work] en [target], y si falla deja el disco como estaba.
///
/// Sin esto, cada intento fallido dejaba una carpeta vacía con el nombre del
/// repositorio al lado de las buenas. Quien llama ya ha comprobado que
/// [target] no existía o estaba vacía, así que no se borra nada que no
/// acabe de crear git.
Future<void> _intoFresh(Directory target, Future<void> Function() work) async {
  final existed = await target.exists();
  await target.create(recursive: true);
  try {
    await work();
  } catch (_) {
    if (!existed) {
      if (await target.exists()) await target.delete(recursive: true);
    } else {
      for (final entry in target.listSync()) {
        entry.deleteSync(recursive: true);
      }
    }
    rethrow;
  }
}

class _GitClone implements LocalClone {
  _GitClone({required this.directory});

  @override
  final String directory;

  @override
  Future<bool> looksRight({required String owner, required String repo}) async {
    if (!await Directory('$directory/.git').exists()) return false;
    try {
      final remote = await _text(['remote', 'get-url', 'origin']);
      // Matched loosely on purpose: https, ssh and a trailing `.git` are all
      // the same repository, and refusing an ssh remote would be pedantry.
      return remote.contains('$owner/$repo');
    } on CloneException {
      return false;
    }
  }

  @override
  Future<String?> remoteUrl() async {
    if (!await Directory('$directory/.git').exists()) return null;
    try {
      return await _text(['remote', 'get-url', 'origin']);
    } on CloneException {
      return null;
    }
  }

  @override
  Future<CloneStatus> status() async {
    final branch = await _text(['rev-parse', '--abbrev-ref', 'HEAD']);
    final head = await _text(['rev-parse', '--short', 'HEAD']);

    var ahead = 0;
    var behind = 0;
    try {
      // Against the remote-tracking ref, which is what the last fetch saw --
      // this must not reach the network, because Ajustes shows it on load.
      final counts = await _text([
        'rev-list',
        '--left-right',
        '--count',
        'HEAD...@{upstream}',
      ]);
      final parts = counts.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        ahead = int.tryParse(parts[0]) ?? 0;
        behind = int.tryParse(parts[1]) ?? 0;
      }
    } on CloneException {
      // No upstream configured. Not an error: a clone can be local-only.
    }

    // Not `_text`: porcelain lines start with the status characters, and the
    // first of them is a space for a change that is not staged. Trimming the
    // whole output eats it, and then the path loses its first letter.
    //
    // `--untracked-files=all` porque git, por defecto, **colapsa una carpeta
    // sin seguir en una sola línea**: crea una lección nueva y el estado dice
    // `content/analisis/nueva/` en vez de los ficheros que hay dentro. Da
    // igual mientras todo se confirme al guardar --nunca queda nada sin
    // seguir-- y deja de dar igual en cuanto los commits son manuales: la
    // cuenta de pendientes diría uno donde hay tres, y el diálogo de
    // confirmar enseñaría una carpeta en vez de decir qué ficheros lleva
    // dentro. Un commit que se firma sin ver qué contiene es como se envía
    // por error media traducción.
    final dirty = await _run([
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], what: 'ver el estado');
    return CloneStatus(
      directory: directory,
      branch: branch,
      head: head,
      ahead: ahead,
      behind: behind,
      dirtyPaths: [
        for (final line in dirty.split('\n'))
          if (_porcelain.firstMatch(line) case final match?)
            _pathOf(match.group(2)!),
      ],
    );
  }

  @override
  Future<({String name, String email})?> configuredAuthor() async {
    // `git config` here reads the local, global and system files in the
    // normal order, so a machine that has ever committed anything answers.
    final name = await _optional(['config', 'user.name']);
    final email = await _optional(['config', 'user.email']);
    if (name == null || email == null) return null;
    if (name.isEmpty || email.isEmpty) return null;
    return (name: name, email: email);
  }

  @override
  Future<void> setAuthor({required String name, required String email}) async {
    await _run([
      'config',
      '--local',
      'user.name',
      name,
    ], what: 'guardar el nombre del autor');
    await _run([
      'config',
      '--local',
      'user.email',
      email,
    ], what: 'guardar el correo del autor');
  }

  /// A git command whose failure means "not set" rather than "broken".
  Future<String?> _optional(List<String> arguments) async {
    try {
      return await _text(arguments);
    } on CloneException {
      return null;
    }
  }

  @override
  Future<({String text, String sha})> readFile(String path) async {
    final file = File('$directory/$path');
    if (!await file.exists()) {
      throw CloneException('$path no existe en el clon.');
    }
    final text = await file.readAsString();
    return (text: text, sha: await _hashOf(path));
  }

  //: El separador de campos de `git log --format`.
  //:
  //: Una unidad de separación de ASCII y no una coma o una tubería: es el
  //: carácter que existe para esto y **no puede aparecer** en el asunto de un
  //: commit escrito por una persona, que es lo que separa un parseo que
  //: funciona de uno que se rompe el día que alguien escribe una coma.
  static const String _fieldSeparator = '\x1f';
  static const String _recordSeparator = '\x1e';

  @override
  Future<List<FileCommit>> history(String path, {int limit = 60}) async {
    final output = await _text([
      'log',
      // El historial de antes de moverse. Reorganizar `content/` pasa, y sin
      // esto una unidad movida abre su historial vacía.
      '--follow',
      '--max-count=$limit',
      '--date=iso-strict',
      '--format=%H$_fieldSeparator%an$_fieldSeparator%ae$_fieldSeparator'
          '%aI$_fieldSeparator%s$_fieldSeparator%b$_recordSeparator',
      // `--` para que git no confunda la ruta con una rama que se llame igual.
      '--',
      path,
    ]);

    final commits = <FileCommit>[];
    for (final record in output.split(_recordSeparator)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;
      final fields = trimmed.split(_fieldSeparator);
      if (fields.length < 5) continue;
      final when = DateTime.tryParse(fields[3]);
      if (when == null) continue;
      commits.add(
        FileCommit(
          sha: fields[0],
          author: fields[1],
          email: fields[2],
          when: when,
          subject: fields[4],
          body: fields.length > 5 ? fields[5].trim() : '',
        ),
      );
    }
    return commits;
  }

  @override
  Future<FileDiff> diffOf({
    required String sha,
    required String path,
    int context = 3,
  }) async {
    final output = await _text([
      'show',
      // Sin la cabecera del commit: aquí solo se quiere el diff, y el autor y
      // la fecha ya vienen del historial.
      '--format=',
      // Los renombrados, detectados: un fichero que se movió tiene que
      // enseñar que se movió y no un borrado más un alta.
      '--find-renames',
      '--unified=$context',
      sha,
      '--',
      path,
    ]);
    return parseUnifiedDiff(output);
  }

  @override
  Future<String?> fileAt({required String sha, required String path}) async {
    try {
      // `_run` y no `_text`: recortar los espacios de un fichero sería
      // enseñar un contenido que no es el que hay. Lo único que se quita es
      // el salto final, que git escribe siempre y que como línea no existe.
      final text = await _run(['show', '$sha:$path'], what: 'leer $path');
      return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
    } on CloneException {
      // En ese commit no había ningún fichero con ese nombre: o todavía no
      // existía, o se llamaba de otra manera.
      return null;
    }
  }

  @override
  Future<String> writeFile({
    required String path,
    required String text,
    required String expectedSha,
  }) async {
    final file = File('$directory/$path');
    await _guard(file, path, expectedSha);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
    return _hashOf(path);
  }

  /// El compare-and-set, antes de escribir nada.
  ///
  /// El caso para el que existe es un `git pull` --o el editor de texto de
  /// quien escribe-- habiendo movido el fichero desde que se cargó la
  /// pantalla. Escribir encima perdería el otro cambio sin decirlo.
  Future<void> _guard(File file, String path, String expectedSha) async {
    final exists = await file.exists();
    if (expectedSha.isEmpty && exists) {
      throw CloneException(
        '$path ya existe en el clon. Vuelve a cargarlo antes de guardar.',
      );
    }
    if (expectedSha.isEmpty) return;
    if (!exists) {
      throw CloneException(
        '$path ha desaparecido del clon desde que lo abriste.',
      );
    }
    if (await _hashOf(path) != expectedSha) {
      throw CloneException(
        '$path ha cambiado en el clon desde que lo abriste. Vuelve a '
        'cargarlo para no perder el otro cambio.',
      );
    }
  }

  @override
  Future<String> commitFile({
    required String path,
    required String text,
    required String expectedSha,
    required String message,
    required String authorName,
    required String authorEmail,
    required String token,
    bool push = true,
  }) async {
    final file = File('$directory/$path');
    await _guard(file, path, expectedSha);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);

    await _run(['add', '--', path], what: 'preparar $path');
    final staged = await _text(['diff', '--cached', '--name-only', '--', path]);
    if (staged.trim().isEmpty) {
      // Nothing actually changed. Returning the hash rather than making an
      // empty commit: a log full of no-op commits is worse than no commit.
      return _hashOf(path);
    }

    await _run(
      [
        // The author is the person; the committer is this machine. Both are
        // set explicitly so a commit never depends on a global git config
        // that the requirement says nobody should have to set up.
        '-c', 'user.name=$authorName',
        '-c', 'user.email=$authorEmail',
        'commit',
        '--message', message,
        '--', path,
      ],
      what: 'hacer el commit de $path',
      environment: {
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      },
    );

    if (push) {
      // Deliberately after the commit and not instead of it: if the push
      // fails the work is committed and recoverable, and the caller is told.
      await this.push(token: token);
    }
    return _hashOf(path);
  }

  @override
  Future<bool> commitPaths({
    required List<String> paths,
    required String message,
    required String authorName,
    required String authorEmail,
    required String token,
    bool push = true,
  }) async {
    if (paths.isEmpty) return false;

    // Las rutas de las que git puede decir algo.
    //
    // Hace falta porque `git add -- <ruta>` **falla** si la ruta no existe
    // ni está en el índice, y ese es un caso normal, no un error: borrar
    // algo que ya no estaba deja el árbol intacto y la operación no cambió
    // nada. Sin este filtro eso salía como «los ficheros se han cambiado,
    // pero el commit falló», que dice justo lo contrario de lo que pasó.
    //
    // Una ruta borrada del disco pero seguida por git sí cuenta: es
    // exactamente el caso de quitar una asignatura, y hay que prepararla
    // para que el borrado entre en el commit.
    final known = <String>[];
    for (final path in paths) {
      final full = '$directory/$path';
      if (File(full).existsSync() || Directory(full).existsSync()) {
        known.add(path);
        continue;
      }
      final tracked = await _text(['ls-files', '--', path]);
      if (tracked.trim().isNotEmpty) known.add(path);
    }
    if (known.isEmpty) return false;

    // `add -A -- <rutas>` recoge lo nuevo, lo cambiado y lo borrado dentro
    // de esas rutas, que es lo que hace falta: una asignatura que se va son
    // borrados, y una que se crea son ficheros nuevos.
    await _run(['add', '-A', '--', ...known], what: 'preparar los cambios');

    final staged = await _text([
      'diff',
      '--cached',
      '--name-only',
      '--',
      ...known,
    ]);
    if (staged.trim().isEmpty) return false;

    await _run(
      [
        '-c',
        'user.name=$authorName',
        '-c',
        'user.email=$authorEmail',
        'commit',
        '--message',
        message,
        '--',
        ...known,
      ],
      what: 'hacer el commit',
      environment: {
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      },
    );

    if (push) await this.push(token: token);
    return true;
  }

  @override
  Future<void> fetch({required String token}) => _run(
    // Solo las ramas: traerse las etiquetas de un repositorio de contenido es
    // tráfico por nada.
    ['fetch', '--no-tags', '--quiet'],
    token: token,
    what: 'mirar si hay cambios en el repositorio',
  );

  @override
  Future<void> pull({required String token}) => _run(
    // `--ff-only`: a merge commit made behind someone's back is not a
    // thing an editor should produce. Diverged history is a conversation,
    // not an automatic resolution.
    ['pull', '--ff-only'],
    token: token,
    what: 'traer los cambios del repositorio',
  );

  @override
  Future<void> push({required String token}) =>
      _run(['push'], token: token, what: 'enviar los commits al repositorio');

  Future<String> _hashOf(String path) => _text(['hash-object', '--', path]);

  /// Two status characters, whitespace, then the path.
  static final RegExp _porcelain = RegExp(r'^(..)\s+(\S.*)$');

  /// A rename is written `old -> new`; the new name is the one that exists.
  static String _pathOf(String rest) {
    final arrow = rest.indexOf(' -> ');
    final path = arrow < 0 ? rest : rest.substring(arrow + 4);
    // Paths with awkward characters come back quoted by git.
    if (path.length >= 2 && path.startsWith('"') && path.endsWith('"')) {
      return path.substring(1, path.length - 1);
    }
    return path;
  }

  // -- Congelaciones: commits, árboles aparte y diferencias ---------------
  //
  // Todo lo de aquí se apoya en una idea: **git ya guarda el contenido de
  // cada commit**. Lo que faltaba no era una copia del repositorio, sino una
  // forma de mirar uno de esos commits sin mover el árbol de trabajo de
  // siempre. Eso es exactamente un worktree.

  /// Dónde viven los árboles de trabajo de las congelaciones.
  ///
  /// Dentro de `.git` a propósito, y no al lado del repositorio: ahí git no
  /// lo mira nunca, así que no sale en `git status` ni se cuela en un commit;
  /// se va con el clon cuando el clon se va; y no hace falta pedirle al
  /// sistema una carpeta de caché que después alguien tenga que limpiar.
  String get _worktreeBase => '$directory/.git/didacta-worktrees';

  @override
  Future<String> head() => _text(['rev-parse', 'HEAD']);

  @override
  Future<bool> hasCommit(String sha) async {
    if (sha.isEmpty) return false;
    try {
      // `^{commit}` y no el objeto a secas: en un clon shallow el borde de la
      // historia deja objetos a los que se llega y que no son commits
      // completos, y mirarlos como tales da un «sí» que después falla.
      await _text(['cat-file', '-e', '$sha^{commit}']);
      return true;
    } on CloneException {
      return false;
    }
  }

  @override
  Future<bool> isShallow() async {
    final answer = await _optional(['rev-parse', '--is-shallow-repository']);
    return answer?.trim() == 'true';
  }

  @override
  Future<void> fetchCommit(
    String sha, {
    required String token,
    void Function(FetchDepth step) onStep = _ignoreStep,
  }) async {
    if (await hasCommit(sha)) return;

    // 1. Pedirlo por su nombre. Es lo barato, y es lo que GitHub permite
    //    desde que soporta `uploadpack.allowReachableSHA1InWant`.
    onStep(FetchDepth.justTheCommit);
    try {
      await _run(
        ['fetch', '--no-tags', '--quiet', 'origin', sha],
        token: token,
        what: 'traer el commit $sha',
      );
      if (await hasCommit(sha)) return;
    } on CloneException {
      // El servidor no lo permite. Se sigue cavando.
    }

    // 2. Más historia, por tramos. Un clon shallow que solo tiene el último
    //    commit suele estar a unas decenas del que se busca, así que esto
    //    acaba casi siempre en la primera o la segunda vuelta.
    if (await isShallow()) {
      for (final depth in const [50, 250, 1000]) {
        onStep(FetchDepth.deeper);
        try {
          await _run(
            ['fetch', '--no-tags', '--quiet', '--deepen=$depth'],
            token: token,
            what: 'traer más historia',
          );
        } on CloneException {
          break;
        }
        if (await hasCommit(sha)) return;
      }

      // 3. Entera. El último recurso, y quien llama ya lo ha contado.
      onStep(FetchDepth.everything);
      await _run(
        ['fetch', '--no-tags', '--quiet', '--unshallow'],
        token: token,
        what: 'traer la historia entera',
      );
      if (await hasCommit(sha)) return;
    } else {
      // No es shallow: si el commit no está, o no está en el remoto o está en
      // una rama que no se sigue. Una última pasada normal lo resuelve.
      onStep(FetchDepth.deeper);
      await _run(
        ['fetch', '--no-tags', '--quiet', 'origin'],
        token: token,
        what: 'traer los commits del repositorio',
      );
      if (await hasCommit(sha)) return;
    }

    throw CloneException(
      'El commit $sha no está en el repositorio, ni aquí ni en GitHub. '
      'Puede que quien lo hizo no lo haya enviado todavía.',
    );
  }

  static void _ignoreStep(FetchDepth step) {}

  @override
  Future<Worktree> worktreeAt(String sha) async {
    final full = await _text(['rev-parse', '$sha^{commit}']);
    final path = '$_worktreeBase/$full';

    // Reutilizar el que haya. Recrearlo en cada apertura sería copiar el
    // árbol entero cada vez, que es justo el coste que esto evita.
    if (await Directory(path).exists()) {
      final at = await _optional(['-C', path, 'rev-parse', 'HEAD']);
      if (at?.trim() == full) return Worktree(directory: path, commit: full);
      // Está pero no sirve: alguien lo tocó, o quedó a medias. Se rehace.
      await _dropWorktree(path);
    }

    // Registros huérfanos de una caché que alguien borró a mano: sin esto,
    // `worktree add` falla diciendo que la ruta ya está registrada.
    await _optional(['worktree', 'prune']);

    await Directory(_worktreeBase).create(recursive: true);
    await _run(
      // `--detach`: sin rama. Una congelación no es una línea de trabajo, es
      // una foto, y crear una rama por cada una llenaría el repositorio de
      // ramas que nadie pidió.
      ['worktree', 'add', '--detach', '--quiet', path, full],
      what: 'preparar la versión congelada $full',
    );
    return Worktree(directory: path, commit: full);
  }

  @override
  Future<void> removeWorktree(String sha) async {
    if (sha.isEmpty) return;
    final full = await _optional(['rev-parse', '$sha^{commit}']);
    await _dropWorktree('$_worktreeBase/${(full ?? sha).trim()}');
  }

  Future<void> _dropWorktree(String path) async {
    if (await Directory(path).exists()) {
      // `--force` porque el árbol puede tener ficheros sin seguir --un PDF
      // compilado mientras se miraba-- y negarse por eso dejaría la caché sin
      // forma de vaciarse. No hay nada que perder ahí: es una caché.
      try {
        await _run([
          'worktree',
          'remove',
          '--force',
          path,
        ], what: 'quitar la versión congelada');
      } on CloneException {
        await Directory(path).delete(recursive: true);
      }
    }
    await _optional(['worktree', 'prune']);
  }

  @override
  Future<List<Worktree>> worktrees() async {
    final base = Directory(_worktreeBase);
    if (!await base.exists()) return const [];
    final found = <Worktree>[];
    for (final entry in base.listSync()) {
      if (entry is! Directory) continue;
      found.add(
        Worktree(directory: entry.path, commit: entry.path.split('/').last),
      );
    }
    found.sort((a, b) => a.commit.compareTo(b.commit));
    return found;
  }

  @override
  Future<int> clearWorktrees() async {
    final found = await worktrees();
    for (final tree in found) {
      await _dropWorktree(tree.directory);
    }
    final base = Directory(_worktreeBase);
    if (await base.exists()) await base.delete(recursive: true);
    await _optional(['worktree', 'prune']);
    return found.length;
  }

  @override
  Future<List<TreeChange>> changesBetween({
    required String from,
    required String to,
    List<String> paths = const [],
  }) async {
    final output = await _zText([
      'diff',
      '--name-status',
      // Los renombrados, detectados: un fichero que se movió tiene que salir
      // como movido y no como un borrado más un alta, que es la diferencia
      // entre «reorganizaron la carpeta» y «perdimos treinta lecciones».
      '--find-renames',
      // Los campos separados por NUL. Un nombre con un espacio o un acento
      // vuelve entrecomillado y con escapes en el formato normal, y
      // desentrecomillarlo a mano es una fuente de fallos que no hace falta.
      '-z',
      from,
      to,
      '--',
      ...paths,
    ], what: 'comparar $from con $to');
    return _parseNameStatus(output);
  }

  @override
  Future<FileDiff> diffBetween({
    required String from,
    required String to,
    required String path,
    int context = 3,
  }) async {
    final output = await _text([
      'diff',
      '--find-renames',
      '--unified=$context',
      from,
      to,
      '--',
      path,
    ]);
    return parseUnifiedDiff(output);
  }

  @override
  Future<List<String>> pathsAt({required String sha, String under = ''}) async {
    try {
      final output = await _zText([
        'ls-tree',
        '-r',
        '--name-only',
        '-z',
        sha,
        '--',
        if (under.isNotEmpty) under,
      ], what: 'leer el árbol de $sha');
      return [
        for (final name in output.split(_nul))
          if (name.isNotEmpty) name,
      ];
    } on CloneException {
      return const [];
    }
  }

  @override
  Future<List<TreeChange>> previewRestore({
    required String sha,
    required List<String> paths,
  }) =>
      // De HEAD **hacia** el commit congelado: lo que sale es lo que habría
      // que hacerle al árbol de trabajo para que volviera a ser aquello.
      changesBetween(from: 'HEAD', to: sha, paths: paths);

  @override
  Future<List<TreeChange>> restoreFrom({
    required String sha,
    required List<String> paths,
  }) async {
    final changes = await previewRestore(sha: sha, paths: paths);
    for (final change in changes) {
      switch (change.kind) {
        // `added` aquí quiere decir «está en el commit congelado y no ahora»,
        // así que restaurarlo es volver a escribirlo.
        case TreeChangeKind.added:
        case TreeChangeKind.modified:
          await _restoreOne(sha, change.path);
        case TreeChangeKind.removed:
          await _deleteOne(change.path);
        case TreeChangeKind.renamed:
          await _restoreOne(sha, change.path);
          if (change.from.isNotEmpty) await _deleteOne(change.from);
      }
    }
    return changes;
  }

  Future<void> _restoreOne(String sha, String path) async {
    final text = await _run(['show', '$sha:$path'], what: 'leer $path');
    final file = File('$directory/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<void> _deleteOne(String path) async {
    final file = File('$directory/$path');
    if (await file.exists()) await file.delete();
  }

  /// La salida cruda de una orden con `-z`, sin el salto final.
  ///
  /// El lector de procesos rearma la salida por líneas y escribe un `\n` al
  /// final; con `-z` no hay líneas, así que ese salto es un campo de más que
  /// aparece como una ruta vacía. Se quita aquí y no recortando la cadena
  /// entera: un nombre de fichero puede acabar en espacio, y `trim()` lo
  /// convertiría en otro nombre.
  Future<String> _zText(List<String> arguments, {required String what}) async {
    final output = await _run(arguments, what: what);
    return output.endsWith('\n')
        ? output.substring(0, output.length - 1)
        : output;
  }

  /// El separador que pone `-z`.
  static final String _nul = String.fromCharCode(0);

  /// La salida de `diff --name-status -z`, leída por campos: el estado, y
  /// detrás una ruta, o dos cuando el fichero se movió.
  static List<TreeChange> _parseNameStatus(String output) {
    final fields = output.split(_nul);
    final changes = <TreeChange>[];
    var index = 0;
    while (index < fields.length) {
      final status = fields[index].trim();
      if (status.isEmpty) {
        index += 1;
        continue;
      }
      final letter = status[0];
      if (letter == 'R' || letter == 'C') {
        if (index + 2 >= fields.length) break;
        changes.add(
          TreeChange(
            kind: TreeChangeKind.renamed,
            path: fields[index + 2],
            from: fields[index + 1],
          ),
        );
        index += 3;
        continue;
      }
      if (index + 1 >= fields.length) break;
      changes.add(
        TreeChange(
          kind: switch (letter) {
            'A' => TreeChangeKind.added,
            'D' => TreeChangeKind.removed,
            _ => TreeChangeKind.modified,
          },
          path: fields[index + 1],
        ),
      );
      index += 2;
    }
    return changes;
  }

  Future<String> _text(List<String> arguments) async {
    final result = await _run(arguments, what: arguments.first);
    return result.trim();
  }

  Future<String> _run(
    List<String> arguments, {
    required String what,
    String? token,
    Map<String, String>? environment,
  }) => _runIn(
    arguments,
    directory: directory,
    what: what,
    token: token,
    environment: environment,
  );
}

Future<String> _run(
  List<String> arguments, {
  required String directory,
  required String what,
  String? token,
  void Function(String line)? onProgress,
  Map<String, String>? environment,
}) => _runIn(
  arguments,
  directory: directory,
  what: what,
  token: token,
  onProgress: onProgress,
  environment: environment,
);

/// Runs git, with the token in the environment and never anywhere else.
Future<String> _runIn(
  List<String> arguments, {
  required String directory,
  required String what,
  String? token,
  void Function(String line)? onProgress,
  Map<String, String>? environment,
}) async {
  final full = <String>[
    if (token != null && token.isNotEmpty) ...[
      // An empty value first, which clears any helper git would otherwise
      // inherit -- osxkeychain, a manager, a stale entry. Without this a
      // wrong cached credential wins over the token that was just pasted.
      '-c', 'credential.helper=',
      // Then a helper that answers from the environment. The token is not in
      // this string: `$DIDACTA_GIT_TOKEN` is expanded by the shell git runs
      // the helper in, which inherits the environment below. So the token
      // never appears in a command line, and never in .git/config.
      '-c',
      r'credential.helper=!f() { test "$1" = get && '
          r'printf "username=x-access-token\npassword=%s\n" '
          r'"$DIDACTA_GIT_TOKEN"; }; f',
    ],
    ...arguments,
  ];

  final process = await Process.start(
    'git',
    full,
    workingDirectory: directory,
    environment: {
      if (token != null && token.isNotEmpty) 'DIDACTA_GIT_TOKEN': token,
      // Never hang waiting for a username: fail with a message instead.
      'GIT_TERMINAL_PROMPT': '0',
      // No pager, and English messages are not forced -- git's own
      // localisation is better than translating its output badly.
      'GIT_PAGER': 'cat',
      ...?environment,
    },
    // The parent's environment is inherited, so PATH and HOME still work.
    includeParentEnvironment: true,
    runInShell: false,
  );

  final out = StringBuffer();
  final err = StringBuffer();
  final outDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        out.writeln(line);
        onProgress?.call(line);
      });
  final errDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        err.writeln(line);
        // git reports progress on stderr, so this is not necessarily a problem.
        onProgress?.call(line);
      });

  final code = await process.exitCode;
  await outDone;
  await errDone;

  if (code != 0) {
    throw CloneException(
      'git falló al $what (código $code).',
      stderr: _redact(err.toString().trim(), token),
    );
  }
  return out.toString();
}

/// Removes the token from anything about to be shown or logged.
///
/// git does not normally echo a credential, but a URL it was given can end up
/// in an error message, and an error message ends up in a screenshot.
String _redact(String text, String? token) {
  if (token == null || token.isEmpty) return text;
  return text.replaceAll(token, '«token»');
}

/// Qué hay en la carpeta donde iría un clon, sin tocarla.
Future<CloneTarget> inspectTarget({
  required String directory,
  required String owner,
  required String repo,
}) async {
  final target = Directory(directory);
  if (!await target.exists()) return CloneTarget.free;
  if (target.listSync().isEmpty) return CloneTarget.free;
  final existing = _GitClone(directory: directory);
  if (await existing.looksRight(owner: owner, repo: repo)) {
    return CloneTarget.alreadyCloned;
  }
  return CloneTarget.occupied;
}
