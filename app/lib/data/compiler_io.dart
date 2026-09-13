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
  String? texPath,
}) => _ProcessCompiler(
  enginePath: enginePath,
  repositoryPath: repositoryPath,
  texPath: texPath,
);

/// El script del motor dentro de su repositorio.
String cliIn(String engineRoot) => '$engineRoot/cli/didacta';

/// Dónde vive TeX, además de lo que diga el PATH.
///
/// Esto existe por una razón que no se ve venir: **una aplicación de
/// escritorio no hereda el PATH del terminal**. A una app lanzada desde el
/// Finder launchd le da `/usr/bin:/bin:/usr/sbin:/sbin` y nada más, y en
/// macOS `latexmk` vive en `/Library/TeX/texbin`, que está en el PATH porque
/// `/etc/paths.d/TeX` lo añade --y eso solo lo lee un shell de login--. El
/// resultado era que Didacta decía «necesita una distribución de TeX» con
/// TeX Live 2026 instalada y funcionando en el terminal.
///
/// Así que se buscan los sitios de siempre en lugar de confiar en el PATH.
/// La lista es de instalaciones por defecto de TeX Live, MacTeX, MiKTeX y
/// TinyTeX; [configured] es la escapatoria para una instalación en un sitio
/// raro, y va primero.
List<String> texDirectories({String? configured}) {
  final found = <String>[];
  if (configured != null && configured.isNotEmpty) found.add(configured);

  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  /// `/usr/local/texlive/2026/bin/universal-darwin` y sus parientes. Por
  /// glob y no con el año escrito: el año cambia todos los abriles, y una
  /// lista con años dentro caduca sola.
  void texliveUnder(String root) {
    final directory = Directory(root);
    if (!directory.existsSync()) return;
    for (final year in directory.listSync().whereType<Directory>()) {
      final bin = Directory('${year.path}/bin');
      if (!bin.existsSync()) continue;
      for (final platform in bin.listSync().whereType<Directory>()) {
        found.add(platform.path);
      }
    }
  }

  if (Platform.isMacOS) {
    // El enlace que pone MacTeX, que es lo que tiene casi todo el mundo.
    found.add('/Library/TeX/texbin');
    texliveUnder('/usr/local/texlive');
    if (home.isNotEmpty) {
      texliveUnder('$home/texlive');
      found.addAll([
        '$home/Library/TinyTeX/bin/universal-darwin',
        '$home/.TinyTeX/bin/universal-darwin',
      ]);
    }
    // Homebrew, por si viene de ahí --`brew install tectonic`, o un
    // basictex-- y por si el PATH de la app no lo lleva.
    found.addAll(['/opt/homebrew/bin', '/usr/local/bin']);
  } else if (Platform.isLinux) {
    texliveUnder('/usr/local/texlive');
    texliveUnder('/opt/texlive');
    if (home.isNotEmpty) {
      texliveUnder('$home/texlive');
      found.addAll([
        '$home/.TinyTeX/bin/x86_64-linux',
        '$home/.TinyTeX/bin/aarch64-linux',
        '$home/bin',
        '$home/.local/bin',
      ]);
    }
  } else if (Platform.isWindows) {
    texliveUnder(r'C:	exlive');
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final roaming = Platform.environment['APPDATA'] ?? '';
    found.addAll([
      if (local.isNotEmpty) '$local\\Programs\\MiKTeX\\miktex\\bin\\x64',
      if (roaming.isNotEmpty) '$roaming\\TinyTeX\\bin\\windows',
      r'C:\Program Files\MiKTeX\miktex\bin\x64',
      r'C:\Program Files (x86)\MiKTeX\miktex\bin\x64',
    ]);
  }

  // Sin repetidos y solo lo que existe: la lista va a un PATH, y un PATH con
  // basura dentro hace que cada búsqueda mire en carpetas que no están.
  final seen = <String>{};
  return [
    for (final directory in found)
      if (seen.add(directory) && Directory(directory).existsSync()) directory,
  ];
}

/// El PATH con TeX dentro.
String texAwarePath({String? configured}) {
  final separator = Platform.isWindows ? ';' : ':';
  final inherited = Platform.environment['PATH'] ?? '';
  final extra = texDirectories(configured: configured);
  // Lo heredado primero: si alguien ha puesto una versión suya delante en el
  // PATH, es la que quiere usar, y esto no es quién para adelantarle otra.
  return [if (inherited.isNotEmpty) inherited, ...extra].join(separator);
}

/// Busca una herramienta en el PATH y en donde vive TeX.
///
/// A mano en lugar de `which`, porque `which` busca en el PATH del proceso
/// --el que launchd le dio-- y ese es justo el que no sirve.
Future<String?> findTool(String name, {String? configured}) async {
  final separator = Platform.isWindows ? ';' : ':';
  final names = Platform.isWindows
      ? ['$name.exe', '$name.bat', '$name.cmd', name]
      : [name];
  for (final directory in texAwarePath(
    configured: configured,
  ).split(separator)) {
    if (directory.isEmpty) continue;
    for (final candidate in names) {
      if (await File('$directory/$candidate').exists()) {
        return '$directory/$candidate';
      }
    }
  }
  return null;
}

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
  _ProcessCompiler({
    required this.enginePath,
    required this.repositoryPath,
    this.texPath,
  });

  final String enginePath;
  final String repositoryPath;

  /// La carpeta `bin` de TeX, cuando está en un sitio que no es ninguno de
  /// los de siempre. Normalmente null: se busca.
  final String? texPath;

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
    final latex = await findTool('latexmk', configured: texPath);
    if (latex == null) {
      return CompilerStatus(
        ready: false,
        enginePath: enginePath,
        problem:
            'No encuentro latexmk. Didacta necesita una distribución de TeX '
            '--en macOS MacTeX o BasicTeX, en Windows MiKTeX o TeX Live, en '
            'Linux el texlive de la distribución-- o TinyTeX, que vale en '
            'las tres.\n\n'
            // Dónde se ha mirado, porque el caso frecuente no es que falte
            // TeX: es que esté en un sitio que no está en esta lista. Sin
            // decirlo, «instálalo» es el consejo equivocado y no hay forma
            // de saberlo.
            'He mirado en: ${texDirectories(configured: texPath).join(', ')}.',
      );
    }
    return CompilerStatus(ready: true, enginePath: enginePath);
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
  Future<List<ExistingOutput>> outputsFor(String unitPath) async {
    final output = await _run(['preview', unitPath, '--status', '--json']);
    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(_jsonIn(output)) as Map<String, dynamic>;
    } catch (error) {
      throw CompileException(
        'El motor no devolvió un estado legible.',
        detail: output.trim(),
      );
    }
    return [
      for (final item in (decoded['outputs'] as List? ?? const []))
        _existingFrom((item as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<({bool stale, String? reason})> indexStale() async {
    // `--stale` sale con 1 cuando lo está, y eso no es un fallo de la
    // llamada: es la respuesta.
    final output = await _run([
      'index',
      '--stale',
      '--json',
    ], allowFailure: true);
    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(_jsonIn(output)) as Map<String, dynamic>;
    } catch (error) {
      throw CompileException(
        'El motor no dijo si el índice está al día.',
        detail: output.trim(),
      );
    }
    return (
      stale: decoded['stale'] == true,
      reason: decoded['reason'] as String?,
    );
  }

  @override
  Future<String> reindex() => _run(['index']);

  @override
  Future<Map<String, List<ExistingOutput>>> builtOutputs() async {
    final output = await _run(['preview', '--built', '--json']);
    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(_jsonIn(output)) as Map<String, dynamic>;
    } catch (error) {
      throw CompileException(
        'El motor no devolvió un estado legible.',
        detail: output.trim(),
      );
    }
    return {
      for (final item in (decoded['units'] as List? ?? const []))
        (item as Map)['unit'] as String: [
          for (final record in (item['outputs'] as List? ?? const []))
            _existingFrom((record as Map).cast<String, dynamic>()),
        ],
    };
  }

  static ExistingOutput _existingFrom(Map<String, dynamic> json) {
    final when = json['mtime'] as num?;
    return ExistingOutput(
      profile: json['profile'] as String? ?? '',
      label: json['label'] as String? ?? '',
      family: json['family'] as String? ?? '',
      language: json['language'] as String? ?? '',
      pdf: json['pdf'] as String? ?? '',
      exists: json['exists'] == true,
      stale: json['stale'] == true,
      modified: when == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((when * 1000).round()),
    );
  }

  @override
  Future<bool> isStale({required String pdf, required String unitPath}) async {
    final file = File(pdf);
    if (!await file.exists()) return false;
    final built = await file.lastModified();

    // Cualquier fichero del directorio de la unidad, por lo mismo que en el
    // motor: un `en` sin inglés se compila del `es.tex`, `unit.yaml` cambia
    // el título, y una figura es tan origen como el texto.
    final directory = Directory('$repositoryPath/$unitPath');
    if (!await directory.exists()) return false;
    await for (final entry in directory.list(recursive: true)) {
      if (entry is! File) continue;
      if (entry.uri.pathSegments.last.startsWith('.')) continue;
      if ((await entry.lastModified()).isAfter(built)) return true;
    }
    return false;
  }

  @override
  Future<List<CompileOutput>> compile({
    required String unitPath,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
  }) async {
    final arguments = <String>[
      'preview',
      unitPath,
      '--json',
      for (final language in languages) ...['-l', language],
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

  @override
  Future<List<BuildableProfile>> documentProfiles(String document) async {
    final output = await _run(['build', document, '--profiles', '--json']);
    final decoded = _listIn(output, document);
    return [
      for (final item in decoded)
        BuildableProfile(
          id: item['profile'] as String? ?? '',
          label: item['label'] as String? ?? '',
          family: item['family'] as String? ?? '',
          byDefault: item['default'] == true,
        ),
    ];
  }

  @override
  Future<List<CompileOutput>> compileDocument({
    required String document,
    required List<String> profiles,
    required List<String> languages,
    bool fast = false,
  }) async {
    final output = await _run([
      'build',
      document,
      '--json',
      for (final language in languages) ...['-l', language],
      for (final profile in profiles) ...['-p', profile],
      if (fast) '--fast',
    ], allowFailure: true);

    return [
      for (final item in _listIn(output, document))
        _outputFrom(item.cast<String, dynamic>()),
    ];
  }

  /// La lista JSON dentro de la salida.
  ///
  /// `build --json` imprime solo JSON, pero buscar el primer corchete en
  /// lugar de exigirlo cuesta una línea y sobrevive a que algún día el motor
  /// escupa un aviso por delante.
  static List<Map<String, dynamic>> _listIn(String output, String what) {
    final start = output.indexOf('[');
    try {
      final decoded = jsonDecode(start < 0 ? output : output.substring(start));
      return [
        for (final item in decoded as List)
          (item as Map).cast<String, dynamic>(),
      ];
    } catch (error) {
      throw CompileException(
        'El motor no devolvió un resultado legible para $what.',
        detail: output.trim(),
      );
    }
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

  @override
  Future<String> run(List<String> arguments, {bool allowFailure = false}) =>
      _run(arguments, allowFailure: allowFailure);

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
        environment: {
          // Sin colores: los códigos de escape en un JSON o en una tabla que
          // se va a parsear son ruido.
          'NO_COLOR': '1',
          'TERM': 'dumb',
          // Con TeX dentro. El motor busca `latexmk` con `shutil.which`, o
          // sea en el PATH, y el PATH que launchd da a una aplicación de
          // escritorio no lleva TeX: sin esto el motor no lo encuentra
          // aunque esté instalado.
          'PATH': texAwarePath(configured: texPath),
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
