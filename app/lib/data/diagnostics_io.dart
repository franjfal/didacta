/// El registro en un fichero: dos de un mega, el de ahora y el anterior.
library;

import 'dart:io';

import 'diagnostics.dart';

/// El sistema, para el informe: «macos 15.3 (arm64)».
String describeSystem() =>
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

/// El sitio de siempre para los registros de cada sistema.
///
/// macOS, en `~/Library/Logs/Didacta`, que es donde lo busca Consola; Windows,
/// en `%LOCALAPPDATA%\Didacta`; Linux, en `$XDG_STATE_HOME/didacta` o
/// `~/.local/state/didacta`.
DiagnosticSink? defaultSink() {
  final env = Platform.environment;
  final String? folder;
  if (Platform.isMacOS) {
    final home = env['HOME'];
    folder = home == null ? null : '$home/Library/Logs/Didacta';
  } else if (Platform.isWindows) {
    final local = env['LOCALAPPDATA'];
    folder = local == null ? null : '$local\\Didacta';
  } else {
    final state = env['XDG_STATE_HOME'];
    final home = env['HOME'];
    folder = state != null && state.isNotEmpty
        ? '$state/didacta'
        : home == null
        ? null
        : '$home/.local/state/didacta';
  }
  if (folder == null) return null;
  return RotatingFileSink(directory: folder);
}

/// Un fichero que, al pasar de [limit], pasa a ser el anterior y empieza otro.
class RotatingFileSink implements DiagnosticSink {
  RotatingFileSink({required this.directory, this.limit = 1024 * 1024});

  final String directory;
  final int limit;

  String get _path => '$directory${Platform.pathSeparator}diagnostics.log';
  String get _previous =>
      '$directory${Platform.pathSeparator}diagnostics.1.log';

  @override
  String get describe => _path;

  @override
  void write(DiagnosticEntry entry) {
    final file = File(_path);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    if (file.existsSync() && file.lengthSync() > limit) {
      final old = File(_previous);
      if (old.existsSync()) old.deleteSync();
      file.renameSync(_previous);
    }
    File(_path).writeAsStringSync(
      '${Diagnostics.line(entry)}\n',
      mode: FileMode.append,
      flush: false,
    );
  }
}
