/// Lanzar el servidor MCP, o no poder.
///
/// La interfaz aquí y la implementación en `_io`, por lo mismo que el resto de
/// la capa de datos: la web no tiene procesos, y una pantalla que ofrece un
/// interruptor que no puede funcionar es peor que una que dice que ahí no.
/// Así además los tests del servicio no necesitan ni un proceso ni un puerto.
library;

import 'dart:async';

import '../model/mcp.dart';

import 'mcp_process_stub.dart'
    if (dart.library.io) 'mcp_process_io.dart'
    as host;

/// Un repositorio que se le ofrece al servidor.
class McpRepository {
  const McpRepository({
    required this.id,
    required this.directory,
    required this.writable,
  });

  final String id;
  final String directory;

  /// Si el modelo puede escribir en él.
  ///
  /// Se decide arriba, en Ajustes, y no se deduce de los permisos del sistema
  /// de ficheros: se puede tener permiso de escritura sobre el clon del
  /// material de otra persona y no tener ningún derecho a cambiarlo.
  final bool writable;
}

/// El servidor en marcha.
abstract class McpSession {
  /// Dónde escucha.
  String get url;

  /// El diario, línea a línea, según lo va escribiendo.
  Stream<String> get journal;

  /// Qué sabe hacer, preguntándoselo a él.
  Future<List<McpTool>> listTools();

  Future<void> stop();
}

/// Quien sabe levantarlo.
abstract class McpRunner {
  Future<McpSession> start(List<McpRepository> repositories);

  /// El de esta plataforma, o uno que se niega con un motivo.
  static McpRunner forHost({required String enginePath, String? texPath}) =>
      host.runnerFor(enginePath: enginePath, texPath: texPath);
}

/// El que no puede, allí donde no hay procesos.
class UnavailableRunner implements McpRunner {
  const UnavailableRunner(this.problem);

  final String problem;

  @override
  Future<McpSession> start(List<McpRepository> repositories) =>
      Future.error(StateError(problem));
}
