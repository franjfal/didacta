/// El servidor MCP como proceso hijo.
///
/// `didacta mcp --http`, con el puerto a cero para que lo elija el sistema:
/// dos Didactas abiertos en la misma máquina no pueden pelearse por un número,
/// y un puerto fijo es exactamente eso. El motor contesta por su salida
/// estándar con el que le tocó, y a partir de ahí esa salida no se usa para
/// nada más.
///
/// El diario llega por la salida de error, una línea de JSON por suceso. Dos
/// canales, uno para cada lector: el mismo reparto que usa `build --progress`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/mcp.dart';
import 'compiler_io.dart'
    show cliIn, engineCommand, noPythonProblem, texAwarePath;
import 'mcp_process.dart';

McpRunner runnerFor({required String enginePath, String? texPath}) {
  if (enginePath.isEmpty) {
    return const UnavailableRunner(
      'No hay motor configurado. El servidor MCP es `didacta mcp`, así que '
      'hace falta decir dónde está Didacta en Ajustes.',
    );
  }
  return ProcessRunner(enginePath: enginePath, texPath: texPath);
}

class ProcessRunner implements McpRunner {
  const ProcessRunner({required this.enginePath, this.texPath});

  final String enginePath;
  final String? texPath;

  @override
  Future<McpSession> start(List<McpRepository> repositories) async {
    final script = cliIn(enginePath);
    if (!await File(script).exists()) {
      throw StateError('No existe $script.');
    }
    // Con el intérprete delante en Windows, igual que al compilar: lanzar el
    // script tal cual allí no ha funcionado nunca.
    final command = await engineCommand(enginePath, texPath: texPath);
    if (command == null) throw StateError(noPythonProblem);

    final process = await Process.start(
      command.executable,
      command.then([
        'mcp',
        '--http',
        // Cero: lo elige el sistema y lo dice. Un puerto fijo choca con otra
        // copia de Didacta, y con cualquier otra cosa que lo haya cogido.
        '--port', '0',
        for (final repository in repositories) ...[
          repository.writable ? '--write' : '--repo',
          repository.directory,
        ],
      ]),
      environment: {
        'NO_COLOR': '1',
        'TERM': 'dumb',
        // Con TeX dentro: si no, la herramienta de compilar no encuentra
        // `latexmk` aunque esté instalado. Es el mismo problema del PATH que
        // no hereda una aplicación de escritorio.
        'PATH': texAwarePath(configured: texPath),
      },
    );

    // El diario, desde ya: si el arranque falla, el motivo viene por aquí y
    // hay que tenerlo escuchando antes de esperar nada.
    final lines = StreamController<String>.broadcast();
    final problems = <String>[];
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.trim().startsWith('{')) problems.add(line);
          if (!lines.isClosed) lines.add(line);
        }, onDone: lines.close);

    final Map<String, dynamic> hello;
    try {
      hello = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .first
          // Con plazo: un motor que arranca y se queda callado dejaría la
          // pantalla en «encendiendo» para siempre, que es la peor de las
          // respuestas porque no invita ni a esperar ni a arreglar nada.
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      process.kill();
      await lines.close();
      throw StateError(
        problems.isEmpty
            ? 'El motor no dijo por qué puerto escucha ($error).'
            : problems.take(4).join('\n'),
      );
    }

    return _Session(
      process: process,
      url: hello['url'] as String? ?? 'http://127.0.0.1:${hello['port']}/',
      lines: lines,
    );
  }
}

class _Session implements McpSession {
  _Session({required this.process, required this.url, required this._lines});

  final Process process;

  /// Abierto mientras el proceso viva. Lo cierra o el proceso al morirse, o
  /// [stop].
  final StreamController<String> _lines;

  @override
  final String url;

  @override
  Stream<String> get journal => _lines.stream;

  /// Le pregunta al servidor qué sabe hacer, por el protocolo.
  ///
  /// Al servidor y no a una lista escrita en la aplicación: quien decide qué
  /// herramientas hay es el motor, y una copia de esta parte se quedaría
  /// vieja el día que alguien añada una.
  @override
  Future<List<McpTool>> listTools() async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/list',
            'params': const <String, dynamic>{},
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return const [];

    final decoded = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
        .cast<String, dynamic>();
    final result = (decoded['result'] as Map?)?.cast<String, dynamic>();
    return [
      for (final item in (result?['tools'] as List?) ?? const [])
        McpTool.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<void> stop() async {
    process.kill();
    // Sin esperar a que muera del todo: apagar un interruptor tiene que ser
    // instantáneo, y el proceso no tiene nada que guardar --lo que escribió
    // está en disco desde que lo escribió--.
    unawaited(process.exitCode);
    if (!_lines.isClosed) await _lines.close();
  }
}
