/// El servidor MCP: qué ofrece y qué está haciendo.
///
/// Dos mitades, y son dos preguntas distintas. Arriba, **qué está pasando**:
/// quién se ha conectado, qué herramienta ha llamado, sobre qué y si salió
/// bien. Es lo que se mira mientras un modelo trabaja, y lo que hace la
/// diferencia entre delegar y perder el control: un servidor que escribe en
/// los ficheros de alguien sin que se pueda ver qué toca no es una herramienta
/// en la que haya motivo para confiar.
///
/// Abajo, **qué sabe hacer**. No cambia mientras corre, así que no es algo que
/// se mire: es una referencia, para saber qué se le puede pedir a un modelo y
/// qué no. Sale del propio servidor --se le pregunta por el protocolo-- y no
/// de una lista escrita aquí, que se quedaría vieja el día que alguien añada
/// una herramienta al motor.
///
/// Y entre las dos, cómo conectarse: la dirección y el trozo de configuración
/// que se pega en el cliente. Es lo primero que hace falta y lo único que no
/// se puede adivinar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../model/mcp.dart';
import '../state/mcp_service.dart';
import 'shell.dart';
import 'theme.dart';

class McpPage extends StatelessWidget {
  const McpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<McpService>();

    return Column(
      children: [
        PageHeader(
          title: 'Servidor MCP',
          subtitle: switch (service.state) {
            McpState.running =>
              '${service.calls} llamadas · ${service.writes} escrituras',
            McpState.starting => 'Encendiendo…',
            McpState.failed => 'No está en marcha',
            McpState.off => 'Apagado',
          },
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              const SectionLabel('Conexión'),
              _ConnectionCard(service: service),

              const SectionLabel('Qué está haciendo'),
              _ActivityCard(service: service),

              const SectionLabel('Qué sabe hacer'),
              _ToolsCard(service: service),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.service});

  final McpService service;

  @override
  Widget build(BuildContext context) {
    final configuration = service.clientConfiguration;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Light(state: service.state),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      service.url ?? 'Sin dirección: el servidor está parado.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: service.url == null ? null : 'monospace',
                      ),
                    ),
                  ),
                  if (service.url != null)
                    IconButton(
                      key: const Key('mcp-copy-url'),
                      tooltip: 'Copiar la dirección',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () => _copy(context, service.url!),
                    ),
                ],
              ),
              if (service.problem != null) ...[
                const SizedBox(height: 8),
                Note(service.problem!, tone: didactaEx),
              ],
              const SizedBox(height: 10),
              const Text(
                'Escucha solo en esta máquina. No pide contraseña, así que no '
                'sale de aquí: un servidor que escribe en tus ficheros '
                'escuchando en la red del departamento es una mala tarde.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              if (configuration != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Para conectar un cliente',
                  style: TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
                const SizedBox(height: 5),
                _Snippet(
                  text: configuration,
                  onCopy: () => _copy(context, configuration),
                ),
                const SizedBox(height: 6),
                const Note(
                  'El puerto lo elige el sistema cada vez que se enciende, '
                  'así que esto hay que volver a pegarlo tras reiniciar '
                  'Didacta.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context, String what) {
    Clipboard.setData(ClipboardData(text: what));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copiado.')));
  }
}

class _Light extends StatelessWidget {
  const _Light({required this.state});

  final McpState state;

  @override
  Widget build(BuildContext context) {
    final (colour, label) = switch (state) {
      McpState.running => (didactaAccentDark, 'En marcha'),
      McpState.starting => (didactaTeacher, 'Encendiendo'),
      McpState.failed => (didactaEx, 'Con problemas'),
      McpState.off => (didactaMuted, 'Apagado'),
    };
    return Tooltip(
      message: label,
      child: Container(
        key: Key('mcp-light-${state.name}'),
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      ),
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet({required this.text, required this.onCopy});

  final String text;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: didactaSurface,
      border: Border.all(color: didactaRule),
      borderRadius: BorderRadius.circular(4),
    ),
    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
          ),
        ),
        IconButton(
          key: const Key('mcp-copy-config'),
          tooltip: 'Copiar',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy, size: 15),
          onPressed: onCopy,
        ),
      ],
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.service});

  final McpService service;

  @override
  Widget build(BuildContext context) {
    final activity = service.activity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cada llamada que recibe, lo último arriba. Las que escriben '
                'van marcadas: lo que hacen queda en disco y se envía desde '
                'la barra de arriba, como cualquier otro cambio.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (activity.isEmpty)
                Note(
                  service.running
                      ? 'En marcha y esperando. Todavía no se ha conectado '
                            'nadie.'
                      : 'Nada todavía. Enciéndelo en Ajustes.',
                )
              else
                for (final event in activity.take(120))
                  _EventRow(event: event),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final McpEvent event;

  @override
  Widget build(BuildContext context) {
    final about = event.about;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              _clock(event.at),
              style: const TextStyle(
                fontSize: 11,
                color: didactaMuted,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Icon(
            switch (event.kind) {
              McpEventKind.started => Icons.play_arrow,
              McpEventKind.stopped => Icons.stop,
              McpEventKind.connected => Icons.link,
              _ => event.ok ? Icons.check : Icons.error_outline,
            },
            size: 13,
            color: event.ok ? didactaMuted : didactaEx,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12.5, color: didactaInk),
                children: [
                  TextSpan(
                    text: event.summary,
                    style: TextStyle(
                      fontWeight: event.isCall
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: event.ok ? didactaInk : didactaEx,
                    ),
                  ),
                  if (about != null)
                    TextSpan(
                      text: '  $about',
                      style: const TextStyle(color: didactaMuted),
                    ),
                ],
              ),
            ),
          ),
          if (event.writes)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: _Pill(label: 'escribe', tone: didactaTeacher),
            ),
          if (event.milliseconds != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '${event.milliseconds} ms',
                style: const TextStyle(fontSize: 11, color: didactaMuted),
              ),
            ),
        ],
      ),
    );
  }

  static String _clock(DateTime when) =>
      '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}:'
      '${when.second.toString().padLeft(2, '0')}';
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: tone, fontWeight: FontWeight.w600),
    ),
  );
}

class _ToolsCard extends StatelessWidget {
  const _ToolsCard({required this.service});

  final McpService service;

  @override
  Widget build(BuildContext context) {
    final tools = service.tools;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lo que un modelo conectado puede pedirle. Sale del propio '
                'servidor, así que es lo que hay de verdad, no una lista '
                'escrita aparte.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (tools.isEmpty)
                const Note(
                  'Se preguntan al servidor cuando arranca. Enciéndelo para '
                  'verlas.',
                )
              else ...[
                for (final tool in tools.where((t) => !t.writes))
                  _ToolTile(tool: tool),
                if (tools.any((t) => t.writes)) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Y estas escriben en el repositorio',
                    style: TextStyle(fontSize: 11.5, color: didactaTeacher),
                  ),
                  const SizedBox(height: 5),
                  for (final tool in tools.where((t) => t.writes))
                    _ToolTile(tool: tool),
                ],
                const SizedBox(height: 8),
                const Note(
                  'Ninguna toca git. Lo que un modelo escriba queda en disco '
                  'y lo envías tú, viendo el diff.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final McpTool tool;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('mcp-tool-${tool.name}'),
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: didactaSurface,
      border: Border.all(color: didactaRule),
      borderRadius: BorderRadius.circular(4),
    ),
    child: ExpansionTile(
      dense: true,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      title: Row(
        children: [
          Flexible(
            child: Text(
              tool.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (tool.writes) const _Pill(label: 'escribe', tone: didactaTeacher),
        ],
      ),
      subtitle: Text(
        tool.title,
        style: const TextStyle(fontSize: 11.5, color: didactaMuted),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            tool.description,
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
        if (tool.arguments.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final argument in tool.arguments)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: didactaInk),
                  children: [
                    TextSpan(
                      text: argument.name,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    if (argument.required)
                      const TextSpan(
                        text: ' obligatorio',
                        style: TextStyle(fontSize: 10, color: didactaTeacher),
                      ),
                    TextSpan(
                      text: '  ${argument.description}',
                      style: const TextStyle(color: didactaMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    ),
  );
}
