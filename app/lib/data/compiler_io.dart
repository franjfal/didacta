/// Compilar, en una plataforma que puede lanzar un proceso.
///
/// Llama a `cli/didacta preview --json`, que es el mismo camino que usa el
/// terminal. La aplicación no reimplementa nada: ni el preámbulo, ni los
/// perfiles, ni el parseo del log. Lo que hace es elegir, lanzar y enseñar.
library;

import 'dart:convert';
import 'dart:io';

import 'compiler.dart';

bool get supported => true;

Compiler makeCompiler({
  required String enginePath,
  required String repositoryPath,
}) => _ProcessCompiler(enginePath: enginePath, repositoryPath: repositoryPath);

/// El script del motor dentro de su repositorio.
String cliIn(String engineRoot) => '$engineRoot/cli/didacta';

Future<String?> discover({String? configured, String? repositoryPath}) async {
  // Lo configurado manda, incluso si no existe: decirlo es mejor que
  // sustituirlo por otra cosa a la callada.
  if (configured != null && configured.isNotEmpty) return configured;

  final candidates = <String>[];
  if (repositoryPath != null && repositoryPath.isNotEmpty) {
    // El hermano del clon. Es la disposición que sale de clonar los dos
    // repositorios al lado, que es la que dice el README.
    final parent = File(repositoryPath).parent.path;
    candidates.add('$parent/didacta');
  }
  candidates.addAll([
    '${Platform.environment['HOME'] ?? ''}/didacta',
    '/usr/local/share/didacta',
  ]);

  for (final candidate in candidates) {
    if (await File(cliIn(candidate)).exists()) return candidate;
  }

  // `didacta` en el PATH: instalado, en lugar de clonado.
  try {
    final which = await Process.run('which', ['didacta']);
    if (which.exitCode == 0) {
      final script = (which.stdout as String).trim();
      if (script.isNotEmpty) {
        // El script vive en `<raíz>/cli/didacta`.
        final root = File(script).parent.parent.path;
        if (await File(cliIn(root)).exists()) return root;
      }
    }
  } on ProcessException {
    // No hay `which`. No es un problema: quedan los candidatos de arriba.
  }
  return null;
}

class _ProcessCompiler implements Compiler {
  _ProcessCompiler({required this.enginePath, required this.repositoryPath});

  final String enginePath;
  final String repositoryPath;

  @override
  Future<CompilerStatus> status() async {
    if (enginePath.isEmpty) {
      return const CompilerStatus(
        ready: false,
        enginePath: null,
        problem:
            'No se encuentra el motor. Es el repositorio que tiene '
            '`cli/didacta`; se elige en Ajustes.',
      );
    }
    if (!await File(cliIn(enginePath)).exists()) {
      return CompilerStatus(
        ready: false,
        enginePath: enginePath,
        problem: 'No existe ${cliIn(enginePath)}.',
      );
    }
    if (repositoryPath.isEmpty) {
      return CompilerStatus(
        ready: false,
        enginePath: enginePath,
        problem:
            'Compilar lee los ficheros del disco, así que hace falta un clon '
            'del repositorio de contenido. Se elige en Ajustes.',
      );
    }
    // latexmk: lo comprueba el motor, pero preguntar aquí permite decirlo
    // antes de que alguien pulse compilar y espere.
    final latex = await _which('latexmk');
    if (!latex) {
      return CompilerStatus(
        ready: false,
        enginePath: enginePath,
        problem:
            'Falta latexmk. Didacta necesita una distribución de TeX; en '
            'macOS, MacTeX o BasicTeX.',
      );
    }
    return CompilerStatus(ready: true, enginePath: enginePath);
  }

  Future<bool> _which(String tool) async {
    try {
      final result = await Process.run('which', [tool]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<List<BuildableProfile>> profilesFor(String unitPath) async {
    final output = await _run(['preview', unitPath, '--list']);
    // `--list` imprime para leerlo, no para parsearlo: dos columnas después
    // de la primera línea. Se parsea aquí y no se añade un `--json` más
    // porque el formato es de dos campos y esto no crece.
    final profiles = <BuildableProfile>[];
    for (final line in output.split('\n')) {
      final match = _listLine.firstMatch(line);
      if (match == null) continue;
      profiles.add(
        BuildableProfile(
          id: match.group(1)!,
          label: match.group(2)!.trim(),
          family: _familyOf(match.group(1)!),
        ),
      );
    }
    return profiles;
  }

  static final RegExp _listLine = RegExp(r'^  ([a-z][a-z0-9-]*)\s{2,}(.+)$');

  static String _familyOf(String id) {
    if (id.startsWith('slides')) return 'slides';
    if (id.startsWith('problems')) return 'problems';
    if (id.startsWith('exam')) return 'exam';
    if (id == 'handout') return 'handout';
    return 'notes';
  }

  @override
  Future<List<CompileOutput>> compile({
    required String unitPath,
    required List<String> profiles,
    required String language,
    bool fast = false,
  }) async {
    final arguments = <String>[
      'preview',
      unitPath,
      '-l',
      language,
      '--json',
      for (final profile in profiles) ...['-p', profile],
      if (fast) '--fast',
    ];
    // `preview` sale con 1 cuando algo no compila, y eso no es un fallo de
    // la llamada: el JSON con los diagnósticos es justo lo que hace falta.
    final output = await _run(arguments, allowFailure: true);

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(_jsonIn(output)) as Map<String, dynamic>;
    } catch (error) {
      throw CompileException(
        'El motor no devolvió un resultado legible.',
        detail: output.trim(),
      );
    }

    if (decoded['results'] == null && decoded['error'] != null) {
      throw CompileException('${decoded['error']}');
    }

    return [
      for (final item in (decoded['results'] as List? ?? const []))
        _outputFrom((item as Map).cast<String, dynamic>()),
    ];
  }

  /// El JSON dentro de la salida.
  ///
  /// El motor imprime avisos antes del JSON en algunos casos, y buscar la
  /// primera llave es más robusto que exigir que la salida sea JSON puro.
  static String _jsonIn(String output) {
    final start = output.indexOf('{');
    return start < 0 ? output : output.substring(start);
  }

  static CompileOutput _outputFrom(Map<String, dynamic> json) {
    final diagnostics = (json['diagnostics'] as List? ?? const []).cast<Map>();
    return CompileOutput(
      profile: json['profile'] as String? ?? '',
      language: json['language'] as String? ?? '',
      ok: json['ok'] == true,
      pdf: json['pdf'] as String?,
      pages: (json['pages'] as num?)?.toInt() ?? 0,
      seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
      errors: [
        for (final d in diagnostics)
          if (d['severity'] == 'error') _describe(d.cast<String, dynamic>()),
      ],
      warnings: [
        for (final d in diagnostics)
          if (d['severity'] != 'error') _describe(d.cast<String, dynamic>()),
      ],
    );
  }

  /// Un diagnóstico con su fichero y su línea, cuando los tiene.
  static String _describe(Map<String, dynamic> json) {
    final message = json['message'] as String? ?? '';
    final file = json['file'] as String?;
    final line = json['line'];
    if (file == null || file.isEmpty) return message;
    final where = line == null ? file : '$file:$line';
    return '$where: $message';
  }

  Future<String> _run(
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    final script = cliIn(enginePath);
    final ProcessResult result;
    try {
      result = await Process.run(
        script,
        arguments,
        // Desde el clon: el motor busca la raíz subiendo hasta didacta.yaml.
        workingDirectory: repositoryPath,
        environment: const {
          // Sin colores: los códigos de escape en un JSON o en una tabla que
          // se va a parsear son ruido.
          'NO_COLOR': '1',
          'TERM': 'dumb',
        },
      );
    } on ProcessException catch (error) {
      throw CompileException(
        'No se pudo lanzar el motor ($script).',
        detail: error.message,
      );
    }

    if (result.exitCode != 0 && !allowFailure) {
      throw CompileException(
        'El motor falló (código ${result.exitCode}).',
        detail: ((result.stderr as String?) ?? '').trim().isEmpty
            ? ((result.stdout as String?) ?? '').trim()
            : (result.stderr as String).trim(),
      );
    }
    return (result.stdout as String?) ?? '';
  }

  @override
  Future<void> open(String pdf) => _reveal(pdf, reveal: false);

  @override
  Future<void> reveal(String pdf) => _reveal(pdf, reveal: true);

  Future<void> _reveal(String pdf, {required bool reveal}) async {
    if (!Platform.isMacOS) {
      throw const CompileException(
        'Abrir el PDF solo está implementado en macOS por ahora.',
      );
    }
    final result = await Process.run('open', [if (reveal) '-R', pdf]);
    if (result.exitCode != 0) {
      throw CompileException(
        'No se pudo abrir el PDF.',
        detail: (result.stderr as String?)?.trim() ?? '',
      );
    }
  }
}
