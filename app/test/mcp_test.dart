/// El servidor MCP visto desde la aplicación.
///
/// La aplicación es dueña del proceso: lo enciende, lo apaga y lee su diario.
/// Podría lanzarlo el cliente --es lo que hace un servidor MCP por stdio--
/// pero entonces no habría interruptor en Ajustes ni forma de ver qué hace,
/// porque nadie tendría el otro extremo de la tubería.
///
/// Lo que se fija aquí: que el interruptor mande, que el diario se lea, y que
/// la pantalla enseñe las dos cosas que hay que ver --qué está pasando y qué
/// se puede pedir--. El protocolo se prueba en `tests/test_mcp.py`, contra el
/// motor; esto es la mitad de acá.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/model/mcp.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/ui/mcp_page.dart';
import 'package:didacta_app/ui/shell.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

const List<McpRepository> unRepo = [
  McpRepository(id: 'x/teoria', directory: '/tmp/teoria', writable: true),
];

/// Un servidor de mentira: ni proceso ni puerto.
class StubSession implements McpSession {
  StubSession({this.tools = const []});

  final List<McpTool> tools;
  final StreamController<String> lines = StreamController<String>.broadcast();
  bool stopped = false;

  @override
  String get url => 'http://127.0.0.1:41234/';

  @override
  Stream<String> get journal => lines.stream;

  @override
  Future<List<McpTool>> listTools() async => tools;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!lines.isClosed) await lines.close();
  }
}

class FakeRunner implements McpRunner {
  FakeRunner({this.session, this.problem});

  final StubSession? session;
  final String? problem;
  final List<List<McpRepository>> asked = [];

  @override
  Future<McpSession> start(List<McpRepository> repositories) async {
    asked.add(repositories);
    if (problem != null) throw StateError(problem!);
    return session!;
  }
}

McpTool tool(String name, {bool writes = false}) => McpTool(
  name: name,
  title: 'La de $name',
  description: 'Lo que hace $name.',
  writes: writes,
  arguments: [
    McpArgument(name: 'path', description: 'Qué unidad.', required: true),
    McpArgument(name: 'repository', description: 'Cuál.', required: false),
  ],
);

/// Una línea del diario, como la escribe el motor.
String line(Map<String, Object?> fields) {
  final parts = fields.entries.map((entry) {
    final value = entry.value;
    return '"${entry.key}": ${value is String ? '"$value"' : value}';
  });
  return '{${parts.join(', ')}}';
}

void main() {
  group('encender y apagar', () {
    test('encendido, dice dónde escucha', () async {
      final session = StubSession();
      final service = McpService(
        openRunner: () => FakeRunner(session: session),
      );

      await service.start(repositories: unRepo);

      expect(service.state, McpState.running);
      expect(service.url, 'http://127.0.0.1:41234/');
    });

    test('apagado, suelta el proceso y se queda sin dirección', () async {
      final session = StubSession();
      final service = McpService(
        openRunner: () => FakeRunner(session: session),
      );
      await service.start(repositories: unRepo);

      await service.stop();

      expect(session.stopped, isTrue);
      expect(service.state, McpState.off);
      expect(service.url, isNull);
    });

    test('encenderlo dos veces no levanta dos procesos', () async {
      final runner = FakeRunner(session: StubSession());
      final service = McpService(openRunner: () => runner);

      await service.start(repositories: unRepo);
      await service.start(repositories: unRepo);

      expect(runner.asked.length, 1);
    });

    test('sin repositorios no se enciende, y se dice por qué', () async {
      // Un servidor sirviendo la nada figura encendido y no contesta a nada,
      // que es peor que uno apagado.
      final service = McpService(
        openRunner: () => FakeRunner(session: StubSession()),
      );

      await service.start(repositories: const []);

      expect(service.state, McpState.failed);
      expect(service.problem, contains('repositorio'));
    });

    test('si el motor no arranca, el motivo queda a la vista', () async {
      final service = McpService(
        openRunner: () => FakeRunner(problem: 'No existe el motor.'),
      );

      await service.start(repositories: unRepo);

      expect(service.state, McpState.failed);
      expect(service.problem, contains('No existe el motor'));
    });

    test('si el proceso se muere solo, deja de figurar encendido', () async {
      final session = StubSession();
      final service = McpService(
        openRunner: () => FakeRunner(session: session),
      );
      await service.start(repositories: unRepo);

      await session.lines.close();
      await Future<void>.delayed(Duration.zero);

      expect(service.state, McpState.failed);
      expect(service.url, isNull);
    });

    test('los repositorios llegan con su permiso de escritura', () async {
      // La decisión la toma la persona en Ajustes, no este servicio mirando
      // los permisos del sistema de ficheros: se puede tener permiso sobre el
      // clon del material de otra persona y no tener derecho a cambiarlo.
      final runner = FakeRunner(session: StubSession());
      final service = McpService(openRunner: () => runner);

      await service.start(
        repositories: const [
          McpRepository(id: 'mio', directory: '/tmp/a', writable: true),
          McpRepository(id: 'ajeno', directory: '/tmp/b', writable: false),
        ],
      );

      expect(runner.asked.single.map((r) => r.writable), [true, false]);
    });

    test('la configuración que se pega en un cliente lleva la dirección', () async {
      final service = McpService(
        openRunner: () => FakeRunner(session: StubSession()),
      );
      expect(service.clientConfiguration, isNull);

      await service.start(repositories: unRepo);

      expect(service.clientConfiguration, contains('127.0.0.1:41234'));
      expect(service.clientConfiguration, contains('didacta'));
    });
  });

  group('el diario', () {
    Future<(McpService, StubSession)> running() async {
      final session = StubSession();
      final service = McpService(
        openRunner: () => FakeRunner(session: session),
      );
      await service.start(repositories: unRepo);
      return (service, session);
    }

    test('una llamada se lee y se cuenta', () async {
      final (service, session) = await running();

      session.lines.add(line({
        'event': 'call', 'tool': 'read_unit', 'ok': true, 'ms': 12,
      }));
      await Future<void>.delayed(Duration.zero);

      expect(service.calls, 1);
      expect(service.activity.first.tool, 'read_unit');
      expect(service.activity.first.milliseconds, 12);
    });

    test('las que escriben se cuentan aparte', () async {
      // Es la distinción que importa al mirar esto: lo que solo lee no puede
      // estropear nada.
      final (service, session) = await running();

      session.lines.add(line({'event': 'call', 'tool': 'read_unit', 'ok': true}));
      session.lines.add(line({
        'event': 'call', 'tool': 'write_unit', 'ok': true, 'writes': true,
      }));
      await Future<void>.delayed(Duration.zero);

      expect(service.calls, 2);
      expect(service.writes, 1);
    });

    test('una que falla se ve como tal', () async {
      final (service, session) = await running();

      session.lines.add(line({
        'event': 'call', 'tool': 'read_unit', 'ok': false,
        'error': 'no existe esa unidad',
      }));
      await Future<void>.delayed(Duration.zero);

      expect(service.activity.first.ok, isFalse);
      expect(service.activity.first.about, 'no existe esa unidad');
    });

    test('quién se conecta queda apuntado', () async {
      final (service, session) = await running();

      session.lines.add(line({'event': 'connected', 'client': 'un-editor'}));
      await Future<void>.delayed(Duration.zero);

      expect(service.activity.first.summary, contains('un-editor'));
    });

    test('lo que no es JSON no ensucia el registro', () async {
      // El proceso también puede escribir ahí un aviso de Python, y eso no es
      // un suceso del diario.
      final (service, session) = await running();
      final before = service.activity.length;

      session.lines.add('DeprecationWarning: algo');
      await Future<void>.delayed(Duration.zero);

      expect(service.activity.length, before);
    });

    test('no crece sin límite', () async {
      // Una sesión larga son miles de llamadas: guardarlas todas es una fuga
      // de memoria con forma de registro.
      final (service, session) = await running();

      for (var i = 0; i < 700; i += 1) {
        session.lines.add(line({'event': 'call', 'tool': 'read_unit', 'ok': true}));
      }
      await Future<void>.delayed(Duration.zero);

      expect(service.activity.length, lessThanOrEqualTo(500));
    });

    test('lo último, arriba', () async {
      final (service, session) = await running();

      session.lines.add(line({'event': 'call', 'tool': 'primera', 'ok': true}));
      await Future<void>.delayed(Duration.zero);
      session.lines.add(line({'event': 'call', 'tool': 'segunda', 'ok': true}));
      await Future<void>.delayed(Duration.zero);

      expect(service.activity.first.tool, 'segunda');
    });
  });

  group('las herramientas', () {
    test('se preguntan al servidor, no se escriben aquí', () async {
      // Quien decide qué herramientas hay es el motor: una copia en esta
      // parte se quedaría vieja el día que alguien añada una.
      final session = StubSession(
        tools: [tool('read_unit'), tool('write_unit', writes: true)],
      );
      final service = McpService(
        openRunner: () => FakeRunner(session: session),
      );

      await service.start(repositories: unRepo);
      await Future<void>.delayed(Duration.zero);

      expect(service.tools.map((t) => t.name), ['read_unit', 'write_unit']);
      expect(service.tools.last.writes, isTrue);
    });

    test('siguen ahí con el servidor apagado', () async {
      // La referencia se lee estando parado: es lo que alguien mira para
      // saber qué puede pedirle a un modelo antes de encenderlo.
      final service = McpService(
        openRunner: () => FakeRunner(session: StubSession(tools: [tool('check')])),
      );
      await service.start(repositories: unRepo);
      await Future<void>.delayed(Duration.zero);

      await service.stop();

      expect(service.tools.single.name, 'check');
    });

    test('se leen del esquema, con sus argumentos obligatorios primero', () {
      final parsed = McpTool.fromJson({
        'name': 'read_unit',
        'title': 'Leer una unidad',
        'description': 'El LaTeX de una unidad.',
        'annotations': {'readOnlyHint': true},
        'inputSchema': {
          'type': 'object',
          'properties': {
            'language': {'description': 'En cuál.'},
            'path': {'description': 'Qué unidad.'},
          },
          'required': ['path'],
        },
      });

      expect(parsed.writes, isFalse);
      expect(parsed.arguments.first.name, 'path');
      expect(parsed.arguments.first.required, isTrue);
    });
  });

  group('el icono del carril', () {
    Future<McpService> rail(
      WidgetTester tester, {
      required bool on,
    }) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final service = McpService(
        openRunner: () => FakeRunner(session: StubSession()),
      );
      addTearDown(service.dispose);
      if (on) {
        await service.start(repositories: unRepo);
        await Future<void>.microtask(() {});
      }
      final catalogue = catalogueWith(const []);
      final app = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
      );
      addTearDown(app.dispose);
      // El armazón cuenta lo que falta por traducir para la insignia del
      // carril, y eso pide el catálogo cargado.
      await app.primeForTest(catalogue);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Session>.value(value: app),
            ChangeNotifierProvider<McpService>.value(value: service),
          ],
          child: MaterialApp(
            theme: didactaTheme(),
            home: const DidactaShell(
              location: '/courses',
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await settle(tester);
      return service;
    }

    testWidgets('apagado no aparece', (tester) async {
      // Un icono que lleva a una pantalla vacía es una pestaña que se aprende
      // a ignorar.
      await rail(tester, on: false);
      expect(find.text('Servidor'), findsNothing);
    });

    testWidgets('encendido sí', (tester) async {
      // Porque entonces hay un programa escribiendo en tus ficheros, y tiene
      // que estar a un clic.
      await rail(tester, on: true);
      expect(find.text('Servidor'), findsOneWidget);
    });

    testWidgets('aparece al encenderlo, sin cambiar de pantalla', (
      tester,
    ) async {
      final service = await rail(tester, on: false);
      expect(find.text('Servidor'), findsNothing);

      await service.start(repositories: unRepo);
      await settle(tester);

      expect(find.text('Servidor'), findsOneWidget);
    });

    testWidgets('y Ajustes se queda el último', (tester) async {
      // El carril se lee por posición: lo nuevo no puede empujar a Ajustes a
      // un sitio distinto según esté el servidor encendido o no.
      await rail(tester, on: true);
      final servidor = tester.getTopLeft(find.text('Servidor')).dy;
      final ajustes = tester.getTopLeft(find.text('Ajustes')).dy;
      expect(servidor, lessThan(ajustes));
    });
  });

  group('la pantalla', () {
    Future<McpService> show(
      WidgetTester tester, {
      bool start = true,
      List<McpTool> tools = const [],
      StubSession? session,
    }) async {
      tester.view.physicalSize = const Size(1100, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final service = McpService(
        openRunner: () =>
            FakeRunner(session: session ?? StubSession(tools: tools)),
      );
      addTearDown(service.dispose);
      if (start) {
        // Nada de `Future.delayed` aquí: un test de widgets corre con reloj
        // falso, y un temporizador que nadie hace avanzar no vence nunca. Lo
        // que sí corre son las microtareas, y eso es lo que `start` y la
        // consulta de herramientas necesitan.
        await service.start(repositories: unRepo);
        await Future<void>.microtask(() {});
      }
      // Con sesión: la cabecera de la página lleva los botones de atrás y
      // adelante, que leen el historial de la sesión.
      final app = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(const []),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Session>.value(value: app),
            ChangeNotifierProvider<McpService>.value(value: service),
          ],
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(body: McpPage()),
          ),
        ),
      );
      await settle(tester);
      return service;
    }

    testWidgets('enseña la dirección y cómo conectarse', (tester) async {
      await show(tester);
      expect(find.textContaining('127.0.0.1:41234'), findsWidgets);
      expect(find.byKey(const Key('mcp-copy-config')), findsOneWidget);
    });

    testWidgets('parado, lo dice en vez de enseñar un ejemplo que no vale', (
      tester,
    ) async {
      await show(tester, start: false);
      expect(find.byKey(const Key('mcp-light-off')), findsOneWidget);
      expect(find.byKey(const Key('mcp-copy-config')), findsNothing);
    });

    testWidgets('lista las herramientas separando las que escriben', (
      tester,
    ) async {
      await show(
        tester,
        tools: [tool('read_unit'), tool('write_unit', writes: true)],
      );

      expect(find.byKey(const Key('mcp-tool-read_unit')), findsOneWidget);
      expect(find.byKey(const Key('mcp-tool-write_unit')), findsOneWidget);
      expect(find.text('Y estas escriben en el repositorio'), findsOneWidget);
    });

    testWidgets('y dice que ninguna toca git', (tester) async {
      // Es lo que hace aceptable dejar escribir a un modelo, así que se dice
      // donde se leen las herramientas y no en una nota al pie.
      await show(tester, tools: [tool('write_unit', writes: true)]);
      expect(find.textContaining('git'), findsWidgets);
    });

    testWidgets('el detalle de una herramienta trae sus argumentos', (
      tester,
    ) async {
      await show(tester, tools: [tool('read_unit')]);

      await tester.tap(find.byKey(const Key('mcp-tool-read_unit')));
      await settle(tester);

      expect(find.textContaining('Lo que hace read_unit'), findsOneWidget);
      // `findRichText` porque la ficha de un argumento es un `RichText` --el
      // nombre en monoespaciada y la explicación en gris, en la misma línea--
      // y los buscadores de texto solo miran los `Text` por defecto.
      expect(
        find.textContaining('obligatorio', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('las llamadas van apareciendo', (tester) async {
      final session = StubSession();
      await show(tester, session: session);

      session.lines.add(line({
        'event': 'call', 'tool': 'write_unit', 'ok': true, 'writes': true,
        'ms': 8,
      }));
      await Future<void>.microtask(() {});
      await settle(tester);

      expect(find.text('write_unit', findRichText: true), findsWidgets);
      expect(find.text('8 ms'), findsOneWidget);
      expect(find.text('escribe'), findsWidgets);
    });

    testWidgets('sin nada todavía, lo dice en vez de dejar un hueco', (
      tester,
    ) async {
      await show(tester, start: false);
      expect(find.textContaining('Enciéndelo en Ajustes'), findsOneWidget);
    });
  });
}
