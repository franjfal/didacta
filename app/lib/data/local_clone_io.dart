/// The clone, on a platform that has a filesystem and can run git.
///
/// Everything here goes through the `git` command rather than a Dart git
/// implementation, and that is a deliberate trade: git is already on every
/// machine this runs on, it is the reference implementation of the format,
/// and a bug in a reimplementation would corrupt the repository that is the
/// source of truth for two thousand units.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/file_history.dart';
import '../model/text_search.dart';
import 'diagnostics.dart';
import 'git_path_io.dart';
import 'local_clone.dart';
import '../l10n/tr.dart';

bool get supported => true;

Future<bool> gitAvailable() async {
  try {
    final result = await Process.run(gitExecutable(), ['--version']);
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
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
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
        tr(
          'La carpeta ya es una copia de {0}/{1}; '
          'actualizándolo.',
          [owner, repo],
        ),
      );
      await existing.pull(token: token, onProgress: onProgress);
      return existing;
    }
    throw CloneException(
      tr(
        'La carpeta {0} no está vacía y no es una copia de '
        '{1}/{2}. Elige otra carpeta.',
        [directory, owner, repo],
      ),
    );
  }

  onProgress?.call(tr('Preguntando a GitHub por {0}/{1}…', [owner, repo]));
  // Antes de crear nada. Un repositorio recién creado en GitHub no tiene
  // ninguna rama, y git lo cuenta como «Remote branch main not found», que
  // ni dice lo que pasa ni deja ver que tiene arreglo.
  if (await _remoteIsEmpty(remote, token: token, label: '$owner/$repo')) {
    throw EmptyRepositoryException(owner: owner, repo: repo);
  }

  await _intoFresh(
    target,
    () => _run(
      // `--progress` solo cuando hay quien lo lea, como al traer: git se calla
      // al escribir a una tubería, y sin él un clon de minutos era un
      // «Cloning into '.'...» quieto hasta el final.
      [
        'clone',
        if (onProgress != null) '--progress',
        '--branch',
        branch,
        remote,
        '.',
      ],
      directory: directory,
      token: token,
      onProgress: onProgress,
      what: tr('clonar {0}/{1}', [owner, repo]),
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
  Map<String, String>? files,
  String? message,
  void Function(String line)? onProgress,
}) async {
  final remote = url ?? _url(owner, repo);
  final target = Directory(directory);
  if (await target.exists() && target.listSync().isNotEmpty) {
    throw CloneException(
      tr(
        'La carpeta {0} no está vacía. Vacíala o elige otra antes de '
        'preparar {1}/{2}.',
        [directory, owner, repo],
      ),
    );
  }

  // Se vuelve a mirar justo antes: entre que se ofreció prepararlo y se
  // aceptó, alguien puede haber empujado.
  if (!await _remoteIsEmpty(remote, token: token, label: '$owner/$repo')) {
    throw CloneException(
      tr(
        '{0}/{1} ya no está vacío: alguien ha subido algo mientras tanto. '
        'Vuelve a añadirlo desde GitHub.',
        [owner, repo],
      ),
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
    await git(['clone', remote, '.'], tr('clonar {0}/{1}', [owner, repo]));

    // Un clon vacío apunta HEAD a la rama por defecto de *esta* máquina, que
    // puede ser `master`. La que manda es la del repositorio en GitHub.
    await git([
      'symbolic-ref',
      'HEAD',
      'refs/heads/$branch',
    ], tr('elegir la rama {0}', [branch]));

    final seed = <String, String>{
      ...files ??
          {
            _marker: LocalClone.settingsFor(title),
            '.gitignore': LocalClone.ignoredFiles,
          },
    };
    seed.putIfAbsent('.gitattributes', () => LocalClone.textAttributes);
    for (final MapEntry(key: path, value: text) in seed.entries) {
      // Nada fuera de la carpeta: una ruta con `..` o absoluta escribiría en
      // el disco de alguien lo que venía para el repositorio.
      if (path.startsWith('/') || path.split('/').contains('..')) {
        throw CloneException(
          tr('{0} no es una ruta dentro del repositorio.', [path]),
        );
      }
      final file = File('$directory/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
    }
    await git(['add', '--all'], tr('preparar el primer cambio'));

    await git(
      [
        '-c',
        'user.name=$authorName',
        '-c',
        'user.email=$authorEmail',
        'commit',
        '--message',
        message ?? tr('Preparar el repositorio de contenido de Didacta'),
      ],
      tr('guardar el primer cambio'),
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
    ], tr('enviar el primer cambio a GitHub'));
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
    what: tr('consultar {0}', [label]),
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
    //
    // Con `-z`: los campos separados por un nulo y las rutas tal cual. Sin
    // él, git entrecomilla y escapa en octal lo que no es ASCII, así que
    // `análisis` llegaba como `"an\303\241lisis"` y la ruta no era la de
    // ningún fichero: se descartaba al confirmar sin decir nada, que en un
    // material en castellano y valenciano es casi todo.
    final dirty = await _run([
      'status',
      '--porcelain',
      '-z',
      '--untracked-files=all',
    ], what: tr('ver el estado'));
    return CloneStatus(
      directory: directory,
      branch: branch,
      head: head,
      ahead: ahead,
      behind: behind,
      dirtyPaths: _dirtyPathsOf(dirty),
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
  Future<void> setAuthor({required String name, required String email}) =>
      _exclusive(directory, () async {
        await _run([
          'config',
          '--local',
          'user.name',
          name,
        ], what: tr('guardar el nombre del autor'));
        await _run([
          'config',
          '--local',
          'user.email',
          email,
        ], what: tr('guardar el correo del autor'));
      });

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
      throw CloneException(
        tr('{0} no existe en tu copia del repositorio.', [path]),
        kind: CloneFailure.missing,
      );
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
    return _commitsIn(output);
  }

  @override
  Future<List<FileCommit>> recent({int limit = 20}) async {
    final output = await _text([
      'log',
      '--max-count=$limit',
      '--date=iso-strict',
      '--format=%H$_fieldSeparator%an$_fieldSeparator%ae$_fieldSeparator'
          '%aI$_fieldSeparator%s$_fieldSeparator%b$_recordSeparator',
    ]);
    return _commitsIn(output);
  }

  List<FileCommit> _commitsIn(String output) {
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
      final text = await _run([
        'show',
        '$sha:$path',
      ], what: tr('leer {0}', [path]));
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
  }) => _exclusive(directory, () async {
    final file = File('$directory/$path');
    await _guard(file, path, expectedSha);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
    return _hashOf(path);
  });

  /// El compare-and-set, antes de escribir nada.
  ///
  /// El caso para el que existe es un `git pull` --o el editor de texto de
  /// quien escribe-- habiendo movido el fichero desde que se cargó la
  /// pantalla. Escribir encima perdería el otro cambio sin decirlo.
  Future<void> _guard(File file, String path, String expectedSha) async {
    final exists = await file.exists();
    if (expectedSha.isEmpty && exists) {
      throw CloneException(
        tr('{0} ya existe en tu copia. Vuelve a cargarlo antes de guardar.', [
          path,
        ]),
        kind: CloneFailure.conflict,
      );
    }
    if (expectedSha.isEmpty) return;
    if (!exists) {
      throw CloneException(
        tr('{0} ha desaparecido de tu copia desde que lo abriste.', [path]),
        kind: CloneFailure.conflict,
      );
    }
    if (await _hashOf(path) != expectedSha) {
      throw CloneException(
        tr(
          '{0} ha cambiado en tu copia desde que lo abriste. Vuelve a '
          'cargarlo para no perder el otro cambio.',
          [path],
        ),
        kind: CloneFailure.conflict,
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
  }) => _exclusive(directory, () async {
    final file = File('$directory/$path');
    await _guard(file, path, expectedSha);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);

    await _run(['add', '--', path], what: tr('preparar {0}', [path]));
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
      what: tr('guardar {0} en el historial', [path]),
      environment: {
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      },
    );

    if (push) {
      // Deliberately after the commit and not instead of it: if the push
      // fails the work is committed and recoverable, and the caller is told
      // --as that, and not as a failed save--.
      try {
        await this.push(token: token);
      } on CloneException catch (failed) {
        throw UnsentException(sha: await _hashOf(path), cause: failed);
      }
    }
    return _hashOf(path);
  });

  @override
  Future<bool> commitPaths({
    required List<String> paths,
    required String message,
    required String authorName,
    required String authorEmail,
    required String token,
    bool push = true,
    void Function(String line)? onProgress,
  }) => _exclusive(directory, () async {
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
    onProgress?.call(
      known.length == 1
          ? tr('\$ git add -A -- 1 ruta')
          : tr('\$ git add -A -- {0} rutas', [known.length]),
    );
    await _run(['add', '-A', '--', ...known], what: tr('preparar los cambios'));

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
      what: tr('guardar en el historial'),
      onProgress: onProgress,
      environment: {
        'GIT_AUTHOR_NAME': authorName,
        'GIT_AUTHOR_EMAIL': authorEmail,
        'GIT_COMMITTER_NAME': authorName,
        'GIT_COMMITTER_EMAIL': authorEmail,
      },
    );

    if (push) {
      try {
        await this.push(token: token, onProgress: onProgress);
      } on CloneException catch (failed) {
        throw UnsentException(sha: '', cause: failed);
      }
    }
    return true;
  });

  @override
  Future<void> fetch({required String token, Duration? timeout}) => _exclusive(
    directory,
    () => _run(
      // Solo las ramas: traerse las etiquetas de un repositorio de contenido es
      // tráfico por nada.
      ['fetch', '--no-tags', '--quiet'],
      token: token,
      what: tr('mirar si hay cambios en el repositorio'),
      timeout: timeout,
    ),
  );

  @override
  Future<void> pull({
    required String token,
    void Function(String line)? onProgress,
  }) => _exclusive(directory, () async {
    await _discardGeneratedIndex(onProgress);
    onProgress?.call(r'$ git pull --ff-only');
    await _run(
      // `--ff-only`: a merge commit made behind someone's back is not a
      // thing an editor should produce. Diverged history is a conversation,
      // not an automatic resolution.
      //
      // `--progress` solo cuando hay quien lo lea: git se calla al escribir
      // a una tubería, y lo que se calla es justo el rato largo.
      ['pull', '--ff-only', if (onProgress != null) '--progress'],
      token: token,
      what: tr('traer los cambios del repositorio'),
      onProgress: onProgress,
    );
  });

  /// Deja `generated/` como está en el último commit, si tiene cambios.
  ///
  /// El índice está versionado y casi siempre sucio en local, porque la
  /// aplicación lo regenera al abrir. En cuanto otra máquina enviaba el suyo,
  /// `pull --ff-only` se negaba --«would be overwritten»-- y traer dejaba de
  /// funcionar sin que la persona hubiera tocado nada. Como el índice es
  /// determinista y se regenera después de traer, descartarlo no pierde
  /// nada: lo que dice sale de los ficheros de al lado.
  Future<void> _discardGeneratedIndex(
    void Function(String line)? onProgress,
  ) async {
    if (!await Directory('$directory/generated').exists()) return;
    final dirty = await _run([
      'status',
      '--porcelain',
      '-z',
      '--untracked-files=no',
      '--',
      'generated',
    ], what: tr('mirar el índice'));
    if (dirty.trim().isEmpty) return;
    onProgress?.call(r'$ git checkout -- generated');
    await _run([
      'checkout',
      '--',
      'generated',
    ], what: tr('dejar el índice como en el último commit'));
  }

  @override
  Future<void> push({
    required String token,
    void Function(String line)? onProgress,
  }) => _exclusive(directory, () {
    onProgress?.call(r'$ git push');
    return _run(
      ['push', if (onProgress != null) '--progress'],
      token: token,
      what: tr('enviar los cambios a GitHub'),
      onProgress: onProgress,
    );
  });

  Future<String> _hashOf(String path) => _text(['hash-object', '--', path]);

  /// A rename is written `old -> new`; the new name is the one that exists.
  /// Las rutas de `status --porcelain -z`.
  ///
  /// Cada entrada es `XY ruta`, y un renombrado o una copia traen detrás un
  /// campo más con la ruta de origen, que no es un fichero pendiente: es de
  /// dónde viene el que sí lo es.
  static List<String> _dirtyPathsOf(String raw) {
    final fields = raw.split('\u0000');
    final paths = <String>[];
    for (var i = 0; i < fields.length; i += 1) {
      final field = fields[i];
      if (field.length < 4) continue;
      final code = field.substring(0, 2);
      paths.add(field.substring(3));
      if (code.contains('R') || code.contains('C')) i += 1;
    }
    return paths;
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
  }) => _exclusive(directory, () async {
    if (await hasCommit(sha)) return;

    // 1. Pedirlo por su nombre. Es lo barato, y es lo que GitHub permite
    //    desde que soporta `uploadpack.allowReachableSHA1InWant`.
    onStep(FetchDepth.justTheCommit);
    try {
      await _run(
        ['fetch', '--no-tags', '--quiet', 'origin', sha],
        token: token,
        what: tr('traer la versión {0}', [sha]),
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
            what: tr('traer más historia'),
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
        what: tr('traer la historia entera'),
      );
      if (await hasCommit(sha)) return;
    } else {
      // No es shallow: si el commit no está, o no está en el remoto o está en
      // una rama que no se sigue. Una última pasada normal lo resuelve.
      onStep(FetchDepth.deeper);
      await _run(
        ['fetch', '--no-tags', '--quiet', 'origin'],
        token: token,
        what: tr('traer los cambios de GitHub'),
      );
      if (await hasCommit(sha)) return;
    }

    throw CloneException(
      tr(
        'La versión {0} no está en el repositorio, ni aquí ni en GitHub. '
        'Puede que quien lo hizo no lo haya enviado todavía.',
        [sha],
      ),
    );
  });

  static void _ignoreStep(FetchDepth step) {}

  @override
  Future<Worktree> worktreeAt(String sha) => _exclusive(directory, () async {
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
      what: tr('preparar la versión congelada {0}', [full]),
    );
    return Worktree(directory: path, commit: full);
  });

  @override
  Future<void> removeWorktree(String sha) => _exclusive(directory, () async {
    if (sha.isEmpty) return;
    final full = await _optional(['rev-parse', '$sha^{commit}']);
    await _dropWorktree('$_worktreeBase/${(full ?? sha).trim()}');
  });

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
        ], what: tr('quitar la versión congelada'));
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
      // Por los dos separadores: en Windows la ruta viene con `\`.
      found.add(
        Worktree(
          directory: entry.path,
          commit: entry.path.split(RegExp(r'[\\/]')).last,
        ),
      );
    }
    found.sort((a, b) => a.commit.compareTo(b.commit));
    return found;
  }

  @override
  Future<int> clearWorktrees() => _exclusive(directory, () async {
    final found = await worktrees();
    for (final tree in found) {
      await _dropWorktree(tree.directory);
    }
    final base = Directory(_worktreeBase);
    if (await base.exists()) await base.delete(recursive: true);
    await _optional(['worktree', 'prune']);
    return found.length;
  });

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
    ], what: tr('comparar {0} con {1}', [from, to]));
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
  Future<List<TextHit>> grep(String pattern, {int perFile = 3}) async {
    try {
      final output = await _run([
        'grep',
        '-n',
        '-I',
        '-E',
        '--null',
        '--max-count',
        '$perFile',
        '-e',
        pattern,
        '--',
        '*.tex',
      ], what: tr('buscar en el texto'));
      return parseGrep(output);
    } on CloneException catch (error) {
      // Sin nada encontrado, git sale con 1 y no dice nada: no es un fallo.
      if (error.stderr.trim().isEmpty) return const [];
      rethrow;
    }
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
      ], what: tr('leer el árbol de {0}', [sha]));
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
  }) => _exclusive(directory, () async {
    final changes = await previewRestore(sha: sha, paths: paths);
    final rewrite = <String>[];
    for (final change in changes) {
      switch (change.kind) {
        // `added` aquí quiere decir «está en el commit congelado y no ahora»,
        // así que restaurarlo es volver a escribirlo.
        case TreeChangeKind.added:
        case TreeChangeKind.modified:
          rewrite.add(change.path);
        case TreeChangeKind.removed:
          await _deleteOne(change.path);
        case TreeChangeKind.renamed:
          rewrite.add(change.path);
          if (change.from.isNotEmpty) await _deleteOne(change.from);
      }
    }
    if (rewrite.isNotEmpty) await _restoreAll(sha, rewrite);
    return changes;
  });

  /// Escribe [paths] como estaban en [sha], byte a byte y sin tocar el
  /// índice: queda como un cambio pendiente, igual que si se hubiera editado.
  ///
  /// Con `git restore` y no leyendo con `show` para escribir el texto, que es
  /// como estaba: eso pasaba el fichero por un lector de líneas en UTF-8, así
  /// que una figura PNG o PDF rompía la restauración a medias --y un `.tex`
  /// con saltos de Windows volvía con los de Unix--.
  Future<void> _restoreAll(String sha, List<String> paths) async {
    // De cien en cien: una lista de rutas sin tope acaba pasándose de lo que
    // el sistema deja poner en una línea de órdenes.
    for (var start = 0; start < paths.length; start += 100) {
      final end = start + 100 < paths.length ? start + 100 : paths.length;
      await _run([
        'restore',
        '--source=$sha',
        '--worktree',
        '--',
        ...paths.sublist(start, end),
      ], what: tr('restaurar la versión congelada'));
    }
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
    void Function(String line)? onProgress,
    Map<String, String>? environment,
    Duration? timeout,
  }) => _runIn(
    arguments,
    directory: directory,
    what: what,
    token: token,
    onProgress: onProgress,
    environment: environment,
    timeout: timeout,
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

/// Lo último que se ha pedido hacer en cada clon, por su carpeta.
final Map<String, Future<void>> _tails = {};

/// Qué clones tiene ya cogidos la tarea en curso, para no esperarse a sí
/// misma: guardar confirma y luego envía, y enviar también pide el clon.
final Object _holding = Object();

/// Hace [work] cuando nadie más esté escribiendo en el clon de [directory].
///
/// Una cola por carpeta y no por objeto: se crea un `LocalClone` nuevo en
/// cada sitio que lo necesita, y dos objetos sobre la misma carpeta son el
/// mismo repositorio. Sin esto chocaban dos guardados seguidos, las
/// preferencias que se confirman solas a los cinco segundos y un «traer»
/// pulsado desde dos sitios: `index.lock`, «cannot lock ref», o peor, un
/// commit que se llevaba el fichero que estaba añadiendo el otro.
///
/// Solo lo que escribe --en el árbol, el índice o las referencias--. Leer
/// (el estado, el historial, un fichero de otro commit) va por su lado: no
/// tiene por qué esperar a que termine un envío lento.
Future<T> _exclusive<T>(String directory, Future<T> Function() work) {
  final key = Directory(directory).absolute.path;
  final held = Zone.current[_holding] as Set<String>?;
  if (held != null && held.contains(key)) return work();

  final previous = _tails[key] ?? Future<void>.value();
  final done = Completer<void>();
  _tails[key] = done.future;
  return previous
      .then(
        (_) => runZoned(
          work,
          zoneValues: {
            _holding: {...?held, key},
          },
        ),
      )
      .whenComplete(() {
        done.complete();
        if (identical(_tails[key], done.future)) {
          // Lo que se quita es el propio `done`, que ya ha terminado.
          _tails.remove(key)?.ignore();
        }
      });
}

/// Las órdenes de git que hablan con GitHub.
const Set<String> _overTheNetwork = {
  'clone',
  'fetch',
  'pull',
  'push',
  'ls-remote',
};

/// La orden de git de una lista de argumentos: lo primero que no es un `-c`
/// con su valor.
String? _commandOf(List<String> arguments) {
  for (var i = 0; i < arguments.length; i += 1) {
    if (arguments[i] == '-c') {
      i += 1;
      continue;
    }
    if (!arguments[i].startsWith('-')) return arguments[i];
  }
  return null;
}

/// Cuánto se le deja a git antes de pararlo.
///
/// Generoso: el tope es para lo que se ha colgado, no para lo que va lento.
/// Clonar un repositorio grande por una red de aula puede ser un cuarto de
/// hora de verdad; lo que no es de verdad es quedarse esperando a un
/// servidor que no contesta, y de eso se encarga además `lowSpeedLimit`.
///
/// Público para poder probarlo sin lanzar git: un tope que se pierde no
/// falla en ningún test que lance git de verdad, solo el día que la red se
/// queda a medias.
Duration gitTimeLimit(List<String> arguments) =>
    switch (_commandOf(arguments)) {
      'clone' => const Duration(minutes: 15),
      final c when _overTheNetwork.contains(c) => const Duration(minutes: 5),
      _ => const Duration(minutes: 2),
    };

/// Lo que se le pasa a git de verdad para [arguments]: los `-c` de siempre
/// delante, los de la red si es una orden de red y el ayudante del token si
/// lo hay.
///
/// Aparte de [_runIn] por lo mismo que [gitTimeLimit]: `lowSpeedLimit` es lo
/// que corta una conexión muerta antes del tope, y quitarlo sin querer no lo
/// nota nadie hasta que un guardado se queda cinco minutos esperando.
List<String> gitArguments(List<String> arguments, {String? token}) => [
  // Las rutas tal cual en todo lo que las enseña --`diff --name-only`,
  // `ls-files`--, y no entrecomilladas con los acentos en octal: se
  // comparan con rutas de verdad, y `"an\303\241lisis"` no es igual a
  // `análisis`.
  '-c', 'core.quotePath=false',
  // Los ficheros como están en el repositorio, sin convertir el fin de
  // línea: el Git de Windows lo trae encendido de serie, y un `.tex` que
  // vuelve con `\r\n` sale entero en cada diff. Lo que se normaliza lo
  // dice el `.gitattributes`, no la máquina de cada uno.
  '-c', 'core.autocrlf=false',
  if (_overTheNetwork.contains(_commandOf(arguments))) ...[
    // Menos de 1 KB/s durante 30 s es una conexión muerta.
    '-c', 'http.lowSpeedLimit=1000',
    '-c', 'http.lowSpeedTime=30',
  ],
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

/// Runs git, with the token in the environment and never anywhere else.
///
/// **Con tope de tiempo, y matándolo al vencer.** Sin él, un `fetch` con la
/// red a medias --un portal cautivo, una wifi que se cae a mitad-- se quedaba
/// esperando para siempre, y con él el guardado que lo había pedido: el
/// editor en «guardando…» sin forma de salir. Las órdenes de red llevan
/// además `http.lowSpeedLimit`, que corta en cuanto la transferencia se
/// estanca en vez de esperar al tope entero.
Future<String> _runIn(
  List<String> arguments, {
  required String directory,
  required String what,
  String? token,
  void Function(String line)? onProgress,
  Map<String, String>? environment,
  Duration? timeout,
}) async {
  final network = _overTheNetwork.contains(_commandOf(arguments));
  final limit = timeout ?? gitTimeLimit(arguments);
  final full = gitArguments(arguments, token: token);

  final watch = Stopwatch()..start();
  final process = await Process.start(
    gitExecutable(),
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
  // Sin reventar con lo que no es UTF-8: un `.tex` antiguo en Latin-1 en el
  // historial lanzaba un `FormatException` que nadie espera de git, y la
  // pantalla se quedaba sin contestar. Un carácter raro en lo que se enseña
  // es mucho mejor que eso.
  final outDone = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
        out.writeln(line);
        onProgress?.call(line);
      });
  final errDone = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
        err.writeln(line);
        // git reports progress on stderr, so this is not necessarily a problem.
        onProgress?.call(line);
      });

  var timedOut = false;
  final code = await process.exitCode.timeout(
    limit,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  // Con plazo también esto: si git se ha matado a medias, un hijo suyo
  // --`git-remote-https`-- puede seguir con las tuberías abiertas, y esperar
  // a que se cierren sería colgarse igual que antes.
  await Future.wait([
    outDone,
    errDone,
  ]).timeout(const Duration(seconds: 3), onTimeout: () => const []);
  // Lo que se lanzó, sin la configuración que lleva delante: el ayudante de
  // credenciales es ruido, y el token nunca va en los argumentos.
  Diagnostics.instance.process(
    program: 'git',
    arguments: arguments,
    exitCode: code,
    took: watch.elapsed,
    stderr: _redact(err.toString(), token),
  );

  if (timedOut) {
    throw CloneException(
      network
          ? tr(
              'git no terminó de {0} en {1} y lo he parado. '
              'Suele ser la red: vuelve a intentarlo cuando vaya bien.',
              [what, _describe(limit)],
            )
          : tr('git no terminó de {0} en {1} y lo he parado.', [
              what,
              _describe(limit),
            ]),
      stderr: _redact(err.toString().trim(), token),
      // Lo dice aquí y no el texto: el mensaje sale en el idioma de la
      // interfaz, y [classifyGit] solo lee el inglés de git.
      kind: network ? CloneFailure.offline : null,
    );
  }

  if (code != 0) {
    throw CloneException(
      tr('git falló al {0} (código {1}).', [what, code]),
      stderr: _redact(err.toString().trim(), token),
    );
  }
  return out.toString();
}

String _describe(Duration limit) => limit.inMinutes >= 1
    ? tr('{0} min', [limit.inMinutes])
    : tr('{0} s', [limit.inSeconds]);

/// Removes the token from anything about to be shown or logged.
///
/// git does not normally echo a credential, but a URL it was given can end up
/// in an error message, and an error message ends up in a screenshot.
String _redact(String text, String? token) {
  if (token == null || token.isEmpty) return text;
  return text.replaceAll(token, tr('«token»'));
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
