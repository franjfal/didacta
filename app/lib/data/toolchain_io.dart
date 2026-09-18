/// Buscar herramientas e instalarlas, en un sistema con procesos y ficheros.
///
/// Lo que hay aquí que no se ve venir es que **buscar es más difícil que
/// instalar**. Una aplicación lanzada desde el Finder recibe de launchd un
/// PATH de cuatro directorios, así que `which latexmk` contesta que no hay
/// LaTeX en una máquina con TeX Live 2026 funcionando en el terminal. Lo
/// mismo pasa con Homebrew --`/opt/homebrew/bin` no está en ese PATH-- y con
/// todo lo que no viva en `/usr/bin`.
///
/// Así que se mira a mano en los sitios de siempre, se guarda la lista de
/// dónde se ha mirado y se enseña cuando algo no aparece. Esa lista es lo que
/// convierte «no encuentro git» en algo accionable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/toolchain.dart';
import 'compiler_io.dart' show texAwarePath, texDirectories;
import 'toolchain.dart';

bool get supported => true;

Toolchain makeToolchain({String? texPath, String? enginePath}) =>
    _ProcessToolchain(texPath: texPath, enginePath: enginePath);

/// El sistema, dicho como lo dice el modelo.
///
/// Los tres que Didacta reparte. Cualquier otro se cuenta como Linux: es el
/// que menos supone --el plan de Linux es «tu gestor de paquetes»-- y así un
/// BSD ve instrucciones útiles en lugar de una pantalla vacía.
Host get currentHost => switch (true) {
  _ when Platform.isMacOS => Host.macos,
  _ when Platform.isWindows => Host.windows,
  _ => Host.linux,
};

/// Dónde se busca un programa que no es de TeX.
///
/// Al PATH heredado y a los directorios de TeX --que [texAwarePath] ya
/// conoce-- se les añaden los sitios donde acaban las cosas instaladas por
/// otro camino: Homebrew, el `~/.local/bin` de Linux, el Git de Windows.
List<String> toolDirectories({String? texPath}) {
  final separator = Platform.isWindows ? ';' : ':';
  final found = <String>[...texAwarePath(configured: texPath).split(separator)];

  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  if (Platform.isMacOS) {
    found.addAll([
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      if (home.isNotEmpty) '$home/.local/bin',
    ]);
  } else if (Platform.isLinux) {
    found.addAll([
      '/usr/bin',
      '/bin',
      '/usr/local/bin',
      '/home/linuxbrew/.linuxbrew/bin',
      if (home.isNotEmpty) ...['$home/.local/bin', '$home/bin'],
    ]);
  } else if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    found.addAll([
      r'C:\Program Files\Git\cmd',
      r'C:\Program Files\Git\bin',
      if (local.isNotEmpty) ...[
        '$local\\Programs\\Git\\cmd',
        '$local\\Microsoft\\WindowsApps',
      ],
      r'C:\Windows\System32',
    ]);
  }

  final seen = <String>{};
  return [
    for (final directory in found)
      if (directory.isNotEmpty &&
          seen.add(directory) &&
          Directory(directory).existsSync())
        directory,
  ];
}

/// El primero de [names] que exista en [directories].
///
/// En Windows se prueban las extensiones ejecutables: allí `git` es
/// `git.exe` y `winget` puede ser un alias de la Store.
({String path, String directory})? findIn(
  List<String> names,
  List<String> directories,
) {
  final suffixes = Platform.isWindows ? ['.exe', '.bat', '.cmd', ''] : [''];
  for (final directory in directories) {
    for (final name in names) {
      for (final suffix in suffixes) {
        final candidate = '$directory${Platform.pathSeparator}$name$suffix';
        if (File(candidate).existsSync()) {
          return (path: candidate, directory: directory);
        }
      }
    }
  }
  return null;
}

class _ProcessToolchain implements Toolchain {
  _ProcessToolchain({this.texPath, this.enginePath});

  /// El directorio de TeX dicho a mano, cuando lo hay.
  final String? texPath;

  /// Dónde está el motor, según la sesión. Null si no se ha encontrado.
  final String? enginePath;

  @override
  Host get host => currentHost;

  @override
  Future<List<ToolState>> inspectAll() async => [
    for (final tool in didactaTools) await inspect(tool.id),
  ];

  @override
  Future<ToolState> inspect(ToolId id) async {
    final tool = toolById(id);
    // El motor no se busca en el PATH: lo encuentra la sesión --al lado del
    // clon, en lo configurado-- y lo que hay que comprobar es que el script
    // siga ahí, que es lo que se rompe cuando alguien mueve la carpeta.
    if (id == ToolId.engine) return _inspectEngine(tool);

    final directories = toolDirectories(texPath: texPath);
    final found = findIn(tool.executables, directories);
    if (found == null) {
      return ToolState(tool: tool, searched: directories);
    }

    final version = await _versionOf(found.path, tool.versionArguments);
    if (version == null) {
      // El fichero está y no arranca. Es peor que faltar --parece
      // disponible-- y por eso se cuenta aparte en lugar de darlo por bueno.
      return ToolState(
        tool: tool,
        path: found.path,
        searched: directories,
        problem:
            'Está en ${found.path} pero no contesta. Puede ser una '
            'instalación a medias o un enlace roto.',
      );
    }

    if (id == ToolId.python && !meetsMinimum(version, minimumPython)) {
      return ToolState(
        tool: tool,
        path: found.path,
        version: version,
        searched: directories,
        problem:
            'El motor necesita Python $minimumPython o posterior, y esta es '
            'la $version.',
      );
    }

    return ToolState(
      tool: tool,
      path: found.path,
      version: version,
      searched: directories,
    );
  }

  Future<ToolState> _inspectEngine(Tool tool) async {
    final root = enginePath;
    if (root == null || root.isEmpty) {
      return ToolState(tool: tool, searched: const []);
    }
    final script = '$root/cli/didacta';
    if (!await File(script).exists()) {
      return ToolState(
        tool: tool,
        searched: [root],
        problem:
            'La carpeta configurada --$root-- ya no tiene cli/didacta '
            'dentro. Se ha movido o se ha borrado.',
      );
    }
    return ToolState(tool: tool, path: root, searched: [root]);
  }

  /// Lo que contesta un programa al preguntarle la versión.
  ///
  /// Con tope de tiempo: un binario roto puede quedarse esperando algo, y una
  /// comprobación que no termina deja la pantalla en «comprobando…» para
  /// siempre. Diez segundos es mucho para un `--version` y poco para que
  /// alguien se canse.
  Future<String?> _versionOf(String path, List<String> arguments) async {
    try {
      final result = await Process.run(
        path,
        arguments,
        environment: {'NO_COLOR': '1'},
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return null;
      final output = '${result.stdout}\n${result.stderr}';
      // La versión si se puede leer, y la primera línea si no: haber
      // contestado ya dice que el programa arranca, que es lo que se estaba
      // preguntando.
      return versionFrom(output) ??
          output
              .split('\n')
              .map((line) => line.trim())
              .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    } on ProcessException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<InstallPlan> choose(List<InstallPlan> candidates) async {
    final directories = toolDirectories(texPath: texPath);
    for (final plan in candidates) {
      final needs = plan.needs;
      if (needs == null) return plan;
      if (findIn([needs], directories) != null) return plan;
    }
    return candidates.last;
  }

  @override
  Future<void> install(
    InstallPlan plan, {
    void Function(String line)? onOutput,
  }) async {
    switch (plan.kind) {
      case InstallKind.own:
      case InstallKind.manual:
        // Ninguno de los dos llega aquí: el del motor lo hace la sesión y el
        // manual solo tiene instrucciones. Lanzar en vez de no hacer nada
        // porque un plan que se ejecuta en silencio y no instala nada es el
        // fallo más difícil de encontrar de todos.
        throw ToolInstallException(
          'Este paso no lo puede hacer Didacta por ti.',
          plan: plan,
        );

      case InstallKind.command:
        await _runCommand(plan, onOutput: onOutput);

      case InstallKind.script:
        final file = await _download(plan, onOutput: onOutput);
        final (program, arguments) = Platform.isWindows
            ? ('cmd', ['/c', file])
            : ('/bin/sh', [file]);
        await _run(program, arguments, plan: plan, onOutput: onOutput);

      case InstallKind.installer:
        final file = await _download(plan, onOutput: onOutput);
        await _openInstaller(file, plan);
    }

    if (plan.texPackages) await _addTexPackages(onOutput: onOutput);
  }

  Future<void> _runCommand(
    InstallPlan plan, {
    void Function(String line)? onOutput,
  }) async {
    final directories = toolDirectories(texPath: texPath);
    final program = plan.program!;
    final found = findIn([program], directories);
    if (found == null) {
      throw ToolInstallException(
        'No encuentro $program en esta máquina.',
        detail: 'He mirado en: ${directories.join(', ')}.',
        plan: plan,
      );
    }
    await _run(found.path, plan.arguments, plan: plan, onOutput: onOutput);
  }

  /// Lanza un proceso y va contando lo que escribe.
  ///
  /// Las dos corrientes juntas y línea a línea: esto no es una llamada al
  /// motor que devuelve JSON, es una instalación que tarda minutos, y lo
  /// único que hace llevadera la espera es ver que está pasando algo.
  Future<void> _run(
    String program,
    List<String> arguments, {
    required InstallPlan plan,
    void Function(String line)? onOutput,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        program,
        arguments,
        environment: {
          'NO_COLOR': '1',
          'TERM': 'dumb',
          'PATH': texAwarePath(configured: texPath),
        },
      );
    } on ProcessException catch (error) {
      throw ToolInstallException(
        'No se pudo lanzar $program.',
        detail: error.message,
        plan: plan,
      );
    }

    // Sin entrada: un instalador que pregunte algo se quedaría esperando a
    // una tubería que nadie va a escribir, y eso es un cuelgue para siempre
    // en lugar de un error.
    try {
      await process.stdin.close();
    } catch (_) {
      // Ya había terminado.
    }

    const decoder = Utf8Decoder(allowMalformed: true);
    final tail = <String>[];
    void keep(String line) {
      onOutput?.call(line);
      tail.add(line);
      // Las últimas cien líneas: es lo que se enseña si falla, y guardar la
      // salida entera de una instalación de seis gigas no le sirve a nadie.
      if (tail.length > 100) tail.removeAt(0);
    }

    final reading = <Future<void>>[
      process.stdout
          .transform(decoder)
          .transform(const LineSplitter())
          .forEach(keep),
      process.stderr
          .transform(decoder)
          .transform(const LineSplitter())
          .forEach(keep),
    ];
    final code = await process.exitCode;
    await Future.wait(reading);

    if (code != 0) {
      throw ToolInstallException(
        'La instalación terminó con un error (código $code).',
        detail: tail.join('\n').trim(),
        plan: plan,
      );
    }
  }

  /// Abre lo descargado con el instalador del sistema.
  ///
  /// A partir de aquí manda el instalador de Apple o el de Windows, que es
  /// quien comprueba la firma del paquete y quien pide la contraseña. Didacta
  /// no reimplementa nada de eso ni podría hacerlo mejor.
  Future<void> _openInstaller(String file, InstallPlan plan) async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('open', [file]);
        if (result.exitCode != 0) {
          throw ToolInstallException(
            'No se pudo abrir el instalador.',
            detail: '${result.stderr}'.trim(),
            plan: plan,
          );
        }
        return;
      }
      if (Platform.isWindows) {
        await Process.start(file, const [], mode: ProcessStartMode.detached);
        return;
      }
      throw ToolInstallException(
        'Aquí los instaladores se abren a mano.',
        detail: 'Está descargado en $file.',
        plan: plan,
      );
    } on ProcessException catch (error) {
      throw ToolInstallException(
        'No se pudo abrir el instalador.',
        detail: '${error.message}\nEstá descargado en $file.',
        plan: plan,
      );
    }
  }

  /// Descarga lo que el plan diga, y devuelve dónde ha quedado.
  ///
  /// Solo `https`, y comprobado aquí y no solo en la tabla: lo que se baja se
  /// va a ejecutar, y una dirección sin cifrar es una dirección que cualquiera
  /// en la red puede contestar.
  Future<String> _download(
    InstallPlan plan, {
    void Function(String line)? onOutput,
  }) async {
    final url = plan.url!;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw ToolInstallException(
        'La dirección de descarga no es válida.',
        detail: url,
        plan: plan,
      );
    }

    onOutput?.call('Descargando $url');
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode != 200) {
        throw ToolInstallException(
          'La descarga falló (HTTP ${response.statusCode}).',
          detail: url,
          plan: plan,
        );
      }

      final directory = await Directory.systemTemp.createTemp('didacta-tool');
      final file = File(
        '${directory.path}${Platform.pathSeparator}${plan.filename ?? 'descarga'}',
      );
      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      var received = 0;
      var announced = 0;
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        // Cada cinco megas: contar cada trozo llenaría el registro de mil
        // líneas iguales, y en una descarga de seis gigas eso es un millón.
        if (received - announced >= 5 * 1024 * 1024) {
          announced = received;
          onOutput?.call(
            total > 0
                ? 'Descargado ${_megabytes(received)} de ${_megabytes(total)}'
                : 'Descargado ${_megabytes(received)}',
          );
        }
      });
      await sink.close();
      onOutput?.call('Descargado en ${file.path}');
      return file.path;
    } on http.ClientException catch (error) {
      throw ToolInstallException(
        'No se pudo descargar el instalador.',
        detail: '${error.message}\n$url',
        plan: plan,
      );
    } finally {
      client.close();
    }
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  /// Le pide a `tlmgr` los paquetes que el preámbulo de Didacta usa.
  ///
  /// **No falla la instalación si esto falla.** Una distribución mínima con
  /// LaTeX funcionando ya es mucho más de lo que había, y lo que falte lo
  /// dirá el log de la primera compilación con nombre y apellido. Dejar la
  /// instalación por «inválida» porque un nombre de paquete cambió en CTAN
  /// sería tirar el trabajo hecho.
  Future<void> _addTexPackages({void Function(String line)? onOutput}) async {
    onOutput?.call('Buscando tlmgr…');
    // Los directorios se recalculan: TinyTeX acaba de aparecer, y la lista
    // que se leyó antes de instalarlo no lo tiene.
    final directories = [
      ...texDirectories(configured: texPath),
      ...toolDirectories(texPath: texPath),
    ];
    final tlmgr = findIn(['tlmgr'], directories);
    if (tlmgr == null) {
      onOutput?.call(
        'No encuentro tlmgr, así que los paquetes se añadirán cuando hagan '
        'falta: el log de la primera compilación dice cuál.',
      );
      return;
    }
    onOutput?.call('Añadiendo los paquetes que Didacta usa. Tarda un poco.');
    try {
      await _run(
        tlmgr.path,
        ['install', ...didactaTexPackages],
        plan: const InstallPlan.manual(label: 'tlmgr', explains: 'tlmgr'),
        onOutput: onOutput,
      );
    } on ToolInstallException catch (error) {
      onOutput?.call(
        'Algún paquete no se pudo añadir (${error.message}). LaTeX ya está '
        'instalado; lo que falte lo dirá el log al compilar.',
      );
    }
  }
}
