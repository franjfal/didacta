/// La barra de arriba: en qué repositorios se trabaja, y traer y enviar.
///
/// Con varios repositorios abiertos hay dos preguntas que se hacen todo el
/// rato y que antes no existían: **en cuál estoy** y **qué falta por enviar**.
/// Las dos se contestan aquí, en el mismo sitio siempre.
///
/// Traer y enviar son dos botones y no uno porque son dos decisiones
/// distintas: un `pull` cambia los ficheros de debajo de quien está editando,
/// y un `push` saca trabajo de esta máquina. Ninguna de las dos se hace sola.
///
/// Y enviar **propone un mensaje** con lo que se tocó, y lo deja editar antes
/// de escribir nada: es lo que queda en el historial de otra gente.
library;

import 'package:flutter/material.dart';

import '../model/commit_message.dart';
import '../state/session.dart';
import 'theme.dart';

class SyncBar extends StatefulWidget {
  const SyncBar({super.key, required this.session});

  final Session session;

  @override
  State<SyncBar> createState() => _SyncBarState();
}

class _SyncBarState extends State<SyncBar> {
  bool _busy = false;

  Future<void> _pull() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.session.pullAll();
      final failed = [
        for (final entry in result.entries)
          if (entry.value is! int) '${entry.key}: ${entry.value}',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed.isEmpty
                ? 'Traído de GitHub y actualizado.'
                : 'Traído, con problemas:\n${failed.join('\n')}',
          ),
          backgroundColor: failed.isEmpty ? null : didactaTeacher,
          duration: Duration(seconds: failed.isEmpty ? 3 : 10),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: didactaTeacher),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boxes = await widget.session.outbox();
      if (!mounted) return;
      if (boxes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No hay nada que enviar.')),
        );
        return;
      }
      final message = await showDialog<String>(
        context: context,
        builder: (context) => _PushDialog(boxes: boxes),
      );
      if (message == null || !mounted) return;

      final result = await widget.session.pushAll(message);
      final failed = [
        for (final entry in result.entries)
          if (entry.value is! int) '${entry.key}: ${entry.value}',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed.isEmpty
                ? 'Enviado a GitHub.'
                : 'No se pudo enviar todo:\n${failed.join('\n')}',
          ),
          backgroundColor: failed.isEmpty ? null : didactaTeacher,
          duration: Duration(seconds: failed.isEmpty ? 3 : 10),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: didactaTeacher),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final repos = session.workspace.repos;
    if (repos.isEmpty) return const SizedBox.shrink();

    final behind = session.behind ?? 0;
    var waiting = session.ahead;
    for (final files in session.pendingChanges.values) {
      waiting += files.length;
    }

    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          // En qué se está trabajando, con su color. Con uno solo no hace
          // falta decirlo: no hay con qué confundirlo.
          if (session.workspace.isMultiple)
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final repo in repos)
                    RepoChip(colour: repo.colour, label: repo.label),
                ],
              ),
            )
          else
            Expanded(
              child: Text(
                repos.single.id,
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // Lo que impide que un repositorio esté al día, si algo lo impide.
          //
          // Aquí y no en un diálogo: es una advertencia sobre lo que hay
          // debajo de lo que se está editando, y el sitio donde se resuelve
          // --traer y enviar-- son los dos botones de al lado.
          for (final repo in repos)
            if (session.driftOf(repo.id) != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: '${session.driftOf(repo.id)}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sync_problem_outlined,
                        size: 15,
                        color: didactaEx,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        session.workspace.isMultiple
                            ? repo.label
                            : 'sin sincronizar',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: didactaEx,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          _SyncButton(
            id: 'pull',
            icon: Icons.download_outlined,
            tooltip: behind > 0
                ? 'Traer de GitHub ($behind por traer)'
                : 'Traer de GitHub',
            badge: behind,
            onPressed: _busy ? null : _pull,
          ),
          _SyncButton(
            id: 'push',
            icon: Icons.upload_outlined,
            tooltip: waiting > 0
                ? 'Enviar a GitHub ($waiting sin enviar)'
                : 'Enviar a GitHub',
            badge: waiting,
            colour: didactaAccentDark,
            onPressed: _busy ? null : _push,
          ),
        ],
      ),
    );
  }
}

/// La etiqueta de color de un repositorio.
///
/// La misma en toda la aplicación: en la barra de arriba, en la fila de un
/// tema y al lado de una unidad. Un color que solo significa algo en una
/// pantalla no se aprende.
class RepoChip extends StatelessWidget {
  const RepoChip({
    super.key,
    required this.colour,
    required this.label,
    this.compact = false,
  });

  final int colour;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tint = Color(colour);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          fontWeight: FontWeight.w700,
          color: tint,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.badge,
    required this.onPressed,
    this.colour = didactaMuted,
  });

  final String id;
  final IconData icon;
  final String tooltip;
  final int badge;
  final VoidCallback? onPressed;
  final Color colour;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          key: Key('sync-$id'),
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 17, color: badge > 0 ? colour : didactaMuted),
          onPressed: onPressed,
        ),
        if (badge > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Qué se va a enviar, y con qué mensaje.
class _PushDialog extends StatefulWidget {
  const _PushDialog({required this.boxes});

  final List<RepoOutbox> boxes;

  @override
  State<_PushDialog> createState() => _PushDialogState();
}

class _PushDialogState extends State<_PushDialog> {
  late final List<String> _pending = [
    for (final box in widget.boxes) ...box.pending,
  ];

  late final TextEditingController _message = TextEditingController(
    text: proposedCommitMessage(_pending),
  );

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enviar a GitHub'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final box in widget.boxes) ...[
              Row(
                children: [
                  RepoChip(colour: box.repo.colour, label: box.repo.label),
                  const SizedBox(width: 8),
                  Text(
                    [
                      if (box.ahead > 0) '${box.ahead} commits sin enviar',
                      if (box.pending.isNotEmpty)
                        '${box.pending.length} ficheros sin guardar',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: didactaMuted),
                  ),
                ],
              ),
              for (final path in box.pending.take(6))
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Text(
                    path,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: didactaMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (box.pending.length > 6)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Text(
                    'y ${box.pending.length - 6} más',
                    style: const TextStyle(fontSize: 11, color: didactaMuted),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            if (_pending.isEmpty)
              const Text(
                'No hay nada escrito sin guardar: solo se envían los commits '
                'que ya están hechos.',
                style: TextStyle(fontSize: 12, color: didactaMuted),
              )
            else
              TextField(
                key: const Key('push-message'),
                controller: _message,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Mensaje del commit',
                  border: OutlineInputBorder(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('push-confirm'),
          onPressed: () {
            final message = _message.text.trim();
            if (_pending.isNotEmpty && message.isEmpty) return;
            Navigator.of(context).pop(message.isEmpty ? 'Enviar' : message);
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
