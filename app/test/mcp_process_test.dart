/// El servidor de verdad, lanzado como lo lanza la aplicación.
///
/// Los demás tests del servidor usan un proceso de mentira, que es lo correcto
/// para probar la pantalla y el servicio. Este no: levanta `didacta mcp` de
/// verdad, con un repositorio de verdad, y comprueba las tres cosas que solo
/// fallan cuando hay un proceso en medio --que diga por qué puerto escucha,
/// que el diario llegue línea a línea y que al apagar se muera--.
///
/// Es el test que se habría enterado de que el motor escribe el puerto por
/// stdout y el diario por stderr, y de que confundirlos deja la pantalla en
/// «encendiendo» para siempre.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/state/mcp_service.dart';

/// Dónde está Didacta, subiendo desde el test.
String get enginePath =>
    Directory.current.path.endsWith('/app')
    ? Directory.current.parent.path
    : Directory.current.path;

String get demo => '$enginePath/examples/demo-course';

void main() {
  late Directory work;
  late String repository;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('didacta-mcp-');
    repository = '${work.path}/repo';
    // Copiado: este test escribe, y el demo está en el repositorio.
    final copy = await Process.run('cp', ['-R', demo, repository]);
    expect(copy.exitCode, 0, reason: '${copy.stderr}');
  });

  tearDown(() async => work.delete(recursive: true));

  test('se levanta, dice dónde escucha y se apaga', () async {
    final service = McpService(
      openRunner: () => McpRunner.forHost(enginePath: enginePath),
    );

    await service.start(
      repositories: [
        McpRepository(id: 'pruebas', directory: repository, writable: true),
      ],
    );

    expect(service.state, McpState.running, reason: service.problem ?? '');
    expect(service.url, startsWith('http://127.0.0.1:'));

    // Las herramientas se le preguntan a él, por el protocolo y por el
    // puerto que acaba de decir: es el ida y vuelta completo.
    await _until(() => service.tools.isNotEmpty);
    expect(service.tools.map((t) => t.name), contains('read_unit'));
    expect(
      service.tools.where((t) => t.writes).map((t) => t.name),
      contains('write_unit'),
    );

    await service.stop();
    expect(service.state, McpState.off);
    expect(service.url, isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('el diario llega mientras trabaja', () async {
    final service = McpService(
      openRunner: () => McpRunner.forHost(enginePath: enginePath),
    );
    await service.start(
      repositories: [
        McpRepository(id: 'pruebas', directory: repository, writable: false),
      ],
    );
    expect(service.state, McpState.running, reason: service.problem ?? '');
    await _until(() => service.tools.isNotEmpty);

    // Una llamada de verdad, por el puerto que acaba de decir. `tools/list`
    // no vale: listar no es llamar a una herramienta, y el diario apunta lo
    // que se hace con el repositorio, no cada mensaje del protocolo.
    final answer = await _call(service.url!, 'list_courses');
    expect(answer, contains('am-iii'));

    await _until(() => service.calls > 0);
    final call = service.activity.firstWhere((e) => e.isCall);
    expect(call.tool, 'list_courses');
    expect(call.ok, isTrue);
    expect(call.writes, isFalse);

    await service.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('sin motor no se enciende, y lo dice en vez de quedarse pensando', () async {
    final service = McpService(
      openRunner: () => McpRunner.forHost(enginePath: '/no/existe'),
    );

    await service.start(
      repositories: [
        McpRepository(id: 'x', directory: repository, writable: false),
      ],
    );

    expect(service.state, McpState.failed);
    expect(service.problem, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// Le pide una herramienta al servidor, por HTTP, como haría un cliente.
Future<String> _call(String url, String tool) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': tool, 'arguments': const <String, dynamic>{}},
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final decoded = (jsonDecode(body) as Map).cast<String, dynamic>();
    final result = (decoded['result'] as Map).cast<String, dynamic>();
    return (result['content'] as List).first['text'] as String;
  } finally {
    client.close();
  }
}

/// Espera a que se cumpla algo, o se rinde.
///
/// Con un proceso de verdad en medio no hay forma de saber cuándo terminó de
/// contestar: lo que hay es esperar a que se note, con un tope para que un
/// fallo sea un fallo y no un test colgado.
Future<void> _until(bool Function() done, {int seconds = 20}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('no llegó a cumplirse en $seconds segundos');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
