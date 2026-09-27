/// El registro de diagnóstico: lo que ha pasado por dentro, para cuando algo
/// falla y hay que contarlo.
///
/// Una incidencia que dice «no compila» sin nada más se contesta con tres
/// preguntas --¿qué versión?, ¿qué dijo el motor?, ¿con qué código salió
/// git?-- que quien la abrió ya no puede contestar, porque el mensaje se fue
/// de la pantalla. Esto lo apunta mientras pasa:
///
/// * **cada proceso** que se lanza --el motor, git--, con su código de
///   salida, cuánto tardó y la cola de lo que escribió en la salida de error;
/// * **lo que contesta GitHub** cuando no es un sí;
/// * **los errores que se tragan a propósito** --los `catch` que siguen
///   adelante porque lo que falló no impide trabajar--, que de otro modo no
///   dejaban rastro en ninguna parte.
///
/// En memoria siempre, y en un fichero cuando la aplicación lo enciende al
/// arrancar: dos de un mega como mucho, el nuevo y el anterior. **Sin
/// secretos**: todo lo que se apunta pasa antes por [scrubSecrets].
library;

import 'dart:convert';
import '../l10n/tr.dart';

import 'diagnostics_stub.dart'
    if (dart.library.io) 'diagnostics_io.dart'
    as platform;

/// Una línea del registro.
class DiagnosticEntry {
  DiagnosticEntry({
    required this.when,
    required this.kind,
    required this.message,
    this.detail = const {},
  });

  final DateTime when;

  /// `process`, `github` o `error`.
  final String kind;
  final String message;
  final Map<String, Object?> detail;

  /// Cuántas veces seguidas ha pasado lo mismo. Un error que se repite en un
  /// bucle es una línea con un número, no mil líneas iguales.
  int repeated = 1;

  Map<String, Object?> toJson() => {
    'when': when.toIso8601String(),
    'kind': kind,
    'message': message,
    if (detail.isNotEmpty) 'detail': detail,
    if (repeated > 1) 'repeated': repeated,
  };

  @override
  String toString() {
    final extra = detail.isEmpty
        ? ''
        : ' ${detail.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    final times = repeated > 1 ? ' (×$repeated)' : '';
    return '${when.toIso8601String()} [$kind] $message$extra$times';
  }
}

/// Donde acaba el registro, además de la memoria.
abstract class DiagnosticSink {
  void write(DiagnosticEntry entry);

  /// Dónde está, para decirlo en el informe.
  String get describe;
}

/// Lo que se quita de todo lo que se apunta: tokens de GitHub, claves de
/// traducción, contraseñas en una URL.
String scrubSecrets(String text) => text
    .replaceAll(RegExp(r'(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}'), '[token]')
    .replaceAll(RegExp(r'github_pat_[A-Za-z0-9_]{20,}'), '[token]')
    .replaceAll(RegExp(r'AIza[0-9A-Za-z_\-]{30,}'), '[clave]')
    .replaceAll(
      RegExp(r'(https?://)[^/\s:@]+(:[^@\s/]*)?@'),
      r'$1[credencial]@',
    )
    .replaceAllMapped(
      RegExp(
        r'((?:token|key|password|secret|authorization)\s*[=:]\s*)\S+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[oculto]',
    );

class Diagnostics {
  Diagnostics._();

  static final Diagnostics instance = Diagnostics._();

  /// Lo último, en memoria. Es lo que va en el informe.
  final List<DiagnosticEntry> recent = [];

  static const int _keep = 400;

  /// El fichero, cuando la aplicación lo ha encendido. Null en las pruebas:
  /// una prueba no escribe en la carpeta de nadie.
  DiagnosticSink? sink;

  /// El sistema en el que corre, dicho para un informe.
  static String get system => platform.describeSystem();

  /// Enciende el fichero en su sitio de siempre para este sistema.
  void useDefaultFile() => sink = platform.defaultSink();

  void _add(DiagnosticEntry entry) {
    final last = recent.isEmpty ? null : recent.last;
    if (last != null &&
        last.kind == entry.kind &&
        last.message == entry.message &&
        entry.when.difference(last.when) < const Duration(seconds: 30)) {
      last.repeated += 1;
      return;
    }
    recent.add(entry);
    if (recent.length > _keep) recent.removeRange(0, recent.length - _keep);
    try {
      sink?.write(entry);
    } catch (_) {
      // El registro no puede ser lo que rompa la aplicación: sin disco, se
      // queda en memoria.
    }
  }

  /// Un error que se sigue adelante sin él. [where] dice dónde, en palabras
  /// de quien lo lee: «session.loadSyncedPrefs».
  void note(String where, Object error, [StackTrace? stack]) {
    final frames = stack?.toString().split('\n').take(4).join(' | ');
    _add(
      DiagnosticEntry(
        when: DateTime.now(),
        kind: 'error',
        message: scrubSecrets('$where: $error'),
        detail: {if (frames != null && frames.isNotEmpty) 'stack': frames},
      ),
    );
  }

  /// Un proceso que ha terminado.
  void process({
    required String program,
    required List<String> arguments,
    required int exitCode,
    required Duration took,
    String stderr = '',
  }) {
    final tail = stderr
        .trimRight()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    _add(
      DiagnosticEntry(
        when: DateTime.now(),
        kind: 'process',
        message: scrubSecrets(
          '${_short(program)} ${arguments.map(_quote).join(' ')}',
        ),
        detail: {
          'exit': exitCode,
          'ms': took.inMilliseconds,
          if (exitCode != 0 && tail.isNotEmpty)
            'stderr': scrubSecrets(
              tail.skip(tail.length > 12 ? tail.length - 12 : 0).join(' ⏎ '),
            ),
        },
      ),
    );
  }

  /// Lo que contestó GitHub, cuando no fue un sí.
  void github({
    required String method,
    required String path,
    required int status,
  }) => _add(
    DiagnosticEntry(
      when: DateTime.now(),
      kind: 'github',
      message: scrubSecrets('$method $path'),
      detail: {'status': status},
    ),
  );

  /// El informe que se pega en una incidencia: de qué máquina y versión, y
  /// lo último que ha pasado.
  String report({required Map<String, String> about, int lines = 150}) {
    final buffer = StringBuffer()
      ..writeln(tr('## Didacta: informe de diagnóstico'))
      ..writeln();
    for (final entry in about.entries) {
      buffer.writeln('- ${entry.key}: ${scrubSecrets(entry.value)}');
    }
    final where = sink?.describe;
    if (where != null) buffer.writeln(tr('- registro: {0}', [where]));
    buffer
      ..writeln()
      ..writeln('```');
    final shown = recent.length > lines
        ? recent.sublist(recent.length - lines)
        : recent;
    for (final entry in shown) {
      buffer.writeln(entry);
    }
    if (shown.isEmpty) buffer.writeln(tr('(nada apuntado todavía)'));
    buffer.writeln('```');
    return buffer.toString();
  }

  /// Todo, como JSON por líneas, que es como va al fichero.
  static String line(DiagnosticEntry entry) => jsonEncode(entry.toJson());

  static String _short(String program) {
    final cut = program.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? program : program.substring(cut + 1);
  }

  static String _quote(String argument) =>
      argument.contains(' ') ? '"$argument"' : argument;
}
