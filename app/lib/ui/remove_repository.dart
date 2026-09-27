/// Quitar un repositorio de la lista, y decidir qué pasa con su carpeta.
///
/// Quitarlo dejaba siempre la carpeta en el disco, y no había forma de
/// llevársela desde aquí: quien quería dejar el ordenador limpio tenía que ir
/// a buscarla al Finder sabiendo dónde estaba. Ahora se pregunta, con la ruta
/// delante, y la carpeta va a la **Papelera**, nunca a un borrado definitivo:
/// dentro puede haber trabajo que no está en GitHub, y se dice antes cuánto.
library;

import 'package:flutter/material.dart';

import '../data/diagnostics.dart';
import '../data/local_clone.dart';
import '../model/workspace.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Qué se hace con la carpeta.
enum RepositoryRemoval {
  /// Se queda en el disco, como siempre.
  keepFolder,

  /// A la Papelera, con todo lo que tenga dentro.
  trashFolder,
}

/// Pregunta, quita [repo] y, si se pide, manda su carpeta a la Papelera.
Future<void> removeRepositoryAsking(
  BuildContext context,
  Session session,
  ContentRepo repo,
) async {
  final status = await _freshStatus(session, repo);
  if (!context.mounted) return;
  final choice = await showDialog<RepositoryRemoval>(
    context: context,
    builder: (context) => RemoveRepositoryDialog(
      repo: repo,
      status: status,
      canTrash: session.files.supported,
    ),
  );
  if (choice == null) return;
  final problem = await session.removeRepository(
    repo.id,
    trashFolder: choice == RepositoryRemoval.trashFolder,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        problem ??
            (choice == RepositoryRemoval.trashFolder
                ? tr('{0} quitado, y su carpeta está en la Papelera.', [
                    repo.id,
                  ])
                : tr('{0} quitado. La carpeta sigue en {1}.', [
                    repo.id,
                    repo.directory,
                  ])),
      ),
    ),
  );
}

/// El estado de ahora, no el de la última vez que se miró: lo que se va a
/// decir es cuánto trabajo se perdería, y eso no puede ser de hace una hora.
Future<CloneStatus?> _freshStatus(Session session, ContentRepo repo) async {
  try {
    return await session.cloneFor(repo.id)?.status() ??
        session.statusOf(repo.id);
  } catch (caught, trace) {
    Diagnostics.instance.note('remove_repository._freshStatus', caught, trace);
    return session.statusOf(repo.id);
  }
}

class RemoveRepositoryDialog extends StatelessWidget {
  const RemoveRepositoryDialog({
    super.key,
    required this.repo,
    required this.status,
    required this.canTrash,
  });

  final ContentRepo repo;

  /// Lo que hay sin enviar, si se sabe.
  final CloneStatus? status;

  /// Si aquí se puede mandar algo a la Papelera. En la web, no.
  final bool canTrash;

  /// Lo que se perdería al tirar la carpeta, dicho en una frase, o `null`.
  String? get _atRisk {
    final known = status;
    if (known == null) return null;
    final parts = [
      if (known.dirtyPaths.isNotEmpty)
        known.dirtyPaths.length == 1
            ? tr('un cambio sin guardar')
            : tr('{0} cambios sin guardar', [known.dirtyPaths.length]),
      if (known.ahead > 0)
        known.ahead == 1
            ? tr('un cambio guardado sin enviar a GitHub')
            : tr('{0} cambios guardados sin enviar a GitHub', [known.ahead]),
    ];
    if (parts.isEmpty) return null;
    return tr(
      'Tiene {0}. Si mandas la carpeta a la Papelera, '
      'ese trabajo se va con ella.',
      [parts.join(' y ')],
    );
  }

  @override
  Widget build(BuildContext context) {
    final risk = _atRisk;
    return AlertDialog(
      title: Text(tr('Quitar {0}', [repo.id])),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Deja de aparecer en Didacta. Su carpeta es esta:')),
            const SizedBox(height: 6),
            SelectableText(
              repo.directory,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            if (canTrash) ...[
              const SizedBox(height: 12),
              Text(
                tr(
                  'Puedes dejarla en el disco o mandarla a la Papelera con todo '
                  'lo que tiene dentro. Desde la Papelera se recupera mientras no '
                  'la vacíes.',
                ),
                style: TextStyle(fontSize: 12.5, color: context.palette.muted),
              ),
            ],
            if (risk != null) ...[
              const SizedBox(height: 12),
              Note(risk, tone: context.palette.teacher),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar')),
        ),
        OutlinedButton(
          key: const Key('remove-keep-folder'),
          onPressed: () =>
              Navigator.of(context).pop(RepositoryRemoval.keepFolder),
          child: Text(tr('Quitar de la lista')),
        ),
        if (canTrash)
          FilledButton(
            key: const Key('remove-trash-folder'),
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.teacher,
            ),
            onPressed: () =>
                Navigator.of(context).pop(RepositoryRemoval.trashFolder),
            child: Text(tr('Quitar y mandar a la Papelera')),
          ),
      ],
    );
  }
}
