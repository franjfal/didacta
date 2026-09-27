import 'dart:io';

import '../model/app_version.dart';
import 'engine_pin.dart';
import 'git_path_io.dart';
import '../l10n/tr.dart';

/// Dónde se marca que lo instaló Didacta: dentro de `.git`, que no se
/// versiona ni cuenta como un cambio del clon.
String markerIn(String engine) => '$engine/.git/didacta-engine';

Future<ProcessResult?> _git(String engine, List<String> arguments) async {
  try {
    return await Process.run(
      gitExecutable(),
      ['-C', engine, ...arguments],
      // Nunca una pregunta: el motor es público, y una contraseña pedida en
      // un terminal que nadie ve deja esto esperando para siempre.
      environment: const {'GIT_TERMINAL_PROMPT': '0'},
    );
  } on ProcessException {
    return null;
  }
}

String? _out(ProcessResult? result) =>
    result != null && result.exitCode == 0 ? '${result.stdout}'.trim() : null;

Future<EngineVersion> inspectEngine(String engine, AppVersion app) async {
  if (!await Directory('$engine/.git').exists()) {
    return EngineVersion(
      app: app,
      blocked: tr('no es un clon de git, así que no se puede mover de versión'),
    );
  }
  final tag = _out(
    await _git(engine, ['describe', '--tags', '--exact-match', 'HEAD']),
  );
  final commit = _out(await _git(engine, ['rev-parse', '--short', 'HEAD']));
  final status = _out(
    await _git(engine, ['status', '--porcelain', '--untracked-files=no']),
  );
  return EngineVersion(
    app: app,
    engine: AppVersion.tryParse(tag),
    commit: commit,
    managed: await File(markerIn(engine)).exists(),
    blocked: status == null
        ? 'git no contesta en esa carpeta'
        : status.isNotEmpty
        ? tr('tiene cambios sin guardar')
        : null,
  );
}

Future<void> pinEngine(String engine, AppVersion app) async {
  final tag = app.tag;
  // Solo la etiqueta, y a la fuerza: si alguien la movió en GitHub, la de
  // GitHub es la buena.
  final fetched = await _git(engine, [
    'fetch',
    '--quiet',
    '--no-tags',
    'origin',
    '+refs/tags/$tag:refs/tags/$tag',
  ]);
  if (fetched == null) {
    throw EnginePinException(tr('No encuentro git.'));
  }
  if (fetched.exitCode != 0) {
    final said = '${fetched.stderr}'.trim();
    throw EnginePinException(
      said.contains("couldn't find remote ref") ||
              said.contains('no se pudo encontrar')
          ? tr('GitHub no tiene la versión {0} del motor.', [tag])
          : tr('No he podido traer la versión {0} del motor: {1}', [tag, said]),
    );
  }
  final checked = await _git(engine, ['checkout', '--quiet', '--detach', tag]);
  if (checked == null || checked.exitCode != 0) {
    throw EnginePinException(
      tr('No he podido poner el motor en {0}: {1}', [
        tag,
        checked?.stderr ?? '',
      ]).trim(),
    );
  }
}

Future<void> markManaged(String engine) async {
  final marker = File(markerIn(engine));
  if (!await marker.parent.exists()) return;
  await marker.writeAsString(
    tr(
      'Este motor lo instaló Didacta, y lo pone en la versión de la '
      'aplicación al actualizarla.\n',
    ),
  );
}
