/// Dejar Didacta en este ordenador como recién instalada.
///
/// Existe porque tirar la aplicación a la Papelera no la desinstala del todo.
/// macOS --y Windows, y Linux-- guarda sus ajustes aparte y los conserva, y
/// el token de GitHub sigue en el llavero: al volver a instalarla, arrancaba
/// con la sesión abierta, los repositorios de antes y la bienvenida dada por
/// vista. Ninguna aplicación puede enterarse de que la han tirado, así que la
/// única forma fiable de empezar de cero es pedirlo desde dentro.
///
/// Borra lo que es de este ordenador y de nadie más; en GitHub no toca nada.
/// Las carpetas de los repositorios y las plantillas guardadas en el
/// programa son trabajo, así que sólo se tiran si se marca, y a la Papelera.
library;

import 'package:flutter/material.dart';

import '../data/app_restart.dart';
import '../state/session.dart';
import 'theme.dart';

class StartOverSection extends StatelessWidget {
  const StartOverSection({
    super.key,
    required this.session,
    this.restart = restartApp,
  });

  final Session session;

  /// Cerrar y volver a abrir. Las pruebas ponen uno que sólo apunta.
  final Future<void> Function() restart;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deja Didacta en este ordenador como recién instalada: sin la '
              'sesión de GitHub, sin ajustes y sin la lista de repositorios. Al '
              'volver a abrirse empieza por la bienvenida.\n\n'
              'Tirar la aplicación a la Papelera no borra nada de esto, así que '
              'es lo que hay que hacer antes si no quieres que quede nada.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('start-over'),
              style: OutlinedButton.styleFrom(foregroundColor: didactaTeacher),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Restablecer Didacta…'),
              onPressed: () => _startOver(context),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _startOver(BuildContext context) async {
    final choice = await showDialog<({bool folders, bool templates})>(
      context: context,
      builder: (context) => StartOverDialog(session: session),
    );
    if (choice == null || !context.mounted) return;
    final problems = await session.resetEverything(
      folders: choice.folders,
      templates: choice.templates,
    );
    if (problems.isNotEmpty && context.mounted) {
      // Lo demás ya está borrado; esto es sólo para que se sepa qué se ha
      // quedado en el disco antes de que la ventana se cierre.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Casi todo'),
          content: SizedBox(width: 480, child: Text(problems.join('\n\n'))),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver a abrir Didacta'),
            ),
          ],
        ),
      );
    }
    await restart();
  }
}

/// Qué se borra, y qué más se quiere tirar.
class StartOverDialog extends StatefulWidget {
  const StartOverDialog({super.key, required this.session});

  final Session session;

  @override
  State<StartOverDialog> createState() => _StartOverDialogState();
}

class _StartOverDialogState extends State<StartOverDialog> {
  bool _folders = false;
  bool _templates = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final repos = session.workspace.repos;
    final unsent = [
      for (final repo in repos)
        if (_hasUnsentWork(session, repo.id)) repo.id,
    ];
    return AlertDialog(
      title: const Text('Restablecer Didacta'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se borra de este ordenador:'),
            const SizedBox(height: 6),
            Text(
              '• la sesión de GitHub y las claves de traducción\n'
              '• los ajustes, y la lista de repositorios'
              '${repos.isEmpty ? '' : ' (${repos.length})'}\n'
              '• que ya viste la bienvenida',
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'En GitHub no se toca nada.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            if (repos.isNotEmpty && session.files.supported)
              CheckboxListTile(
                key: const Key('start-over-folders'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _folders,
                onChanged: (value) => setState(() => _folders = value ?? false),
                title: Text(
                  'Mandar también a la Papelera las carpetas de los '
                  '${repos.length == 1 ? 'repositorio' : '${repos.length} repositorios'}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: unsent.isEmpty
                    ? null
                    : Text(
                        'Hay trabajo sin enviar a GitHub en ${unsent.join(', ')}: '
                        'se iría con ellas.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: didactaTeacher,
                        ),
                      ),
              ),
            if (session.templateStore != null && session.files.supported)
              CheckboxListTile(
                key: const Key('start-over-templates'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _templates,
                onChanged: (value) =>
                    setState(() => _templates = value ?? false),
                title: const Text(
                  'Mandar también a la Papelera las plantillas guardadas en el '
                  'programa',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Didacta se cerrará y volverá a abrirse.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
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
          key: const Key('start-over-confirm'),
          style: FilledButton.styleFrom(backgroundColor: didactaTeacher),
          onPressed: () => Navigator.of(
            context,
          ).pop((folders: _folders, templates: _templates)),
          child: const Text('Restablecer y volver a abrir'),
        ),
      ],
    );
  }

  static bool _hasUnsentWork(Session session, String repo) {
    final status = session.statusOf(repo);
    return status != null && (status.ahead > 0 || status.dirtyPaths.isNotEmpty);
  }
}
