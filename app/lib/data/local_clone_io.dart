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
  void Function(String line)? onProgress,
}) async {
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
  await target.create(recursive: true);

  await _run(
    ['clone', '--branch', branch, _url(owner, repo), '.'],
    directory: directory,
    token: token,
    onProgress: onProgress,
    what: 'clonar $owner/$repo',
  );
  return _GitClone(directory: directory);
}

String _url(String owner, String repo) => 'https://github.com/$owner/$repo.git';

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
    final dirty = await _run(['status', '--porcelain'], what: 'ver el estado');
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

    // Compare-and-set, before anything is written. The case this exists for
    // is a `git pull` -- or the author's own text editor -- having moved the
    // file on since the screen loaded.
    final exists = await file.exists();
    if (expectedSha.isEmpty && exists) {
      throw CloneException(
        '$path ya existe en el clon. Vuelve a cargarlo antes de guardar.',
      );
    }
    if (expectedSha.isNotEmpty) {
      if (!exists) {
        throw CloneException(
          '$path ha desaparecido del clon desde que lo abriste.',
        );
      }
      final current = await _hashOf(path);
      if (current != expectedSha) {
        throw CloneException(
          '$path ha cambiado en el clon desde que lo abriste. Vuelve a '
          'cargarlo para no perder el otro cambio.',
        );
      }
    }

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
