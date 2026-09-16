/// Lo que el servidor MCP dice de sí mismo.
///
/// Dos cosas, y son distintas. Una **herramienta** es lo que el servidor sabe
/// hacer: la lista no cambia mientras corre, y es la referencia que alguien
/// lee para saber qué puede pedirle a un modelo. Un **evento** es algo que ha
/// pasado: una llamada, una conexión, un error. Lo primero se consulta, lo
/// segundo se mira pasar.
library;

import 'dart:convert';

/// Una herramienta del servidor, tal como la declara el motor.
class McpTool {
  const McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.writes,
    this.arguments = const [],
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    final schema = (json['inputSchema'] as Map?)?.cast<String, dynamic>();
    final properties = (schema?['properties'] as Map?)?.cast<String, dynamic>();
    final required = <String>{
      for (final item in (schema?['required'] as List?) ?? const []) '$item',
    };
    final annotations = (json['annotations'] as Map?)?.cast<String, dynamic>();
    return McpTool(
      name: json['name'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      // Del propio servidor, no de una lista escrita aquí: quien sabe si una
      // herramienta escribe es quien la implementa.
      writes: annotations?['readOnlyHint'] == false,
      arguments: [
        for (final entry in (properties ?? const {}).entries)
          McpArgument(
            name: entry.key,
            description:
                ((entry.value as Map?)?['description'] as String?) ?? '',
            required: required.contains(entry.key),
          ),
      ]..sort((a, b) {
        if (a.required != b.required) return a.required ? -1 : 1;
        return a.name.compareTo(b.name);
      }),
    );
  }

  final String name;
  final String title;
  final String description;

  /// Si modifica el repositorio. Es la distinción que importa al leer la
  /// lista: lo que solo lee no puede estropear nada.
  final bool writes;

  final List<McpArgument> arguments;
}

class McpArgument {
  const McpArgument({
    required this.name,
    required this.description,
    required this.required,
  });

  final String name;
  final String description;
  final bool required;
}

/// Qué clase de cosa ha pasado.
enum McpEventKind { started, stopped, connected, call, other }

/// Una línea del diario del servidor.
class McpEvent {
  const McpEvent({
    required this.kind,
    required this.at,
    this.tool,
    this.client,
    this.ok = true,
    this.writes = false,
    this.milliseconds,
    this.error,
    this.arguments = const {},
    this.detail,
  });

  /// Lo que el motor escribe por su salida de error, una línea por suceso.
  ///
  /// Devuelve null para lo que no sea JSON: el proceso también puede escribir
  /// ahí un aviso de Python, y eso no es un suceso del diario.
  static McpEvent? parse(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('{')) return null;
    final Map<String, dynamic> json;
    try {
      json = (jsonDecode(trimmed) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    final seconds = json['at'];
    return McpEvent(
      kind: switch (json['event']) {
        'ready' || 'listening' => McpEventKind.started,
        'stopped' => McpEventKind.stopped,
        'connected' => McpEventKind.connected,
        'call' => McpEventKind.call,
        _ => McpEventKind.other,
      },
      at: seconds is num
          ? DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round())
          : DateTime.now(),
      tool: json['tool'] as String?,
      client: json['client'] as String?,
      ok: json['ok'] as bool? ?? true,
      writes: json['writes'] as bool? ?? false,
      milliseconds: (json['ms'] as num?)?.round(),
      error: json['error'] as String?,
      arguments:
          (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
      detail: json['event'] as String?,
    );
  }

  factory McpEvent.started(String url) => McpEvent(
    kind: McpEventKind.started,
    at: DateTime.now(),
    detail: url,
  );

  factory McpEvent.stopped() =>
      McpEvent(kind: McpEventKind.stopped, at: DateTime.now());

  final McpEventKind kind;
  final DateTime at;
  final String? tool;
  final String? client;
  final bool ok;
  final bool writes;
  final int? milliseconds;
  final String? error;
  final Map<String, dynamic> arguments;
  final String? detail;

  bool get isCall => kind == McpEventKind.call;

  /// Una línea para leer de un vistazo.
  String get summary => switch (kind) {
    McpEventKind.started => 'Servidor en marcha',
    McpEventKind.stopped => 'Servidor detenido',
    McpEventKind.connected => 'Se ha conectado ${client ?? 'un cliente'}',
    McpEventKind.call => ok ? (tool ?? 'llamada') : '${tool ?? 'llamada'}: falló',
    McpEventKind.other => detail ?? 'suceso',
  };

  /// Sobre qué, cuando se sabe. Lo que un modelo tocó, no con qué: el texto
  /// de un fichero no cabe en una fila y no dice nada que no diga la ruta.
  String? get about {
    if (error != null) return error;
    for (final key in ['path', 'course', 'query', 'language', 'repository']) {
      final value = arguments[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
