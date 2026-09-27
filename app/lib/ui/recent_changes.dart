/// Los cambios recientes, con un «Deshacer» que no pisa nada.
///
/// Lo que se ha guardado estos días, de todos los repositorios abiertos:
/// quitar una asignatura, reordenar un curso, corregir una lección. El aviso
/// de después de cada operación ya ofrece deshacerla; esto es para cuando el
/// aviso se fue --«ayer quité el curso que no era»--.
///
/// **Deshacer es un cambio nuevo**, no reescribir la historia: lo que había
/// en los ficheros de ese cambio vuelve, en un commit que dice que deshace el
/// otro. Y **solo si nadie los ha vuelto a tocar después**: deshacer un
/// cambio de hace tres días encima de lo que se escribió ayer se llevaría lo
/// de ayer. Eso se comprueba al pulsar, fichero por fichero, y si alguno cambió
/// se dice cuál en lugar de deshacer a medias.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/diagnostics.dart';
import '../data/local_clone.dart';
import '../model/file_history.dart';
import '../state/session.dart';
import 'course_admin_ui.dart';
import 'problem.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Abre la lista.
Future<void> showRecentChanges(BuildContext context, Session session) =>
    showDialog<void>(
      context: context,
      builder: (context) => RecentChangesDialog(session: session),
    );

/// Un commit, y de qué repositorio es.
typedef RecentChange = ({String? repo, FileCommit commit});

/// Lo que se deshace de un commit: sus ficheros, sin el índice --que se
/// regenera--, o por qué no se puede.
typedef UndoPlan = ({List<String> paths, String? blocked});

/// Qué haría deshacer [commit] en [clone].
///
/// Los ficheros que tocó, comparados con los de ahora: si alguno está
/// distinto de como lo dejó ese commit, alguien lo ha cambiado después y
/// deshacer se lo llevaría por delante.
Future<UndoPlan> planUndo(LocalClone clone, FileCommit commit) async {
  final List<TreeChange> changes;
  try {
    changes = await clone.changesBetween(
      from: '${commit.sha}~1',
      to: commit.sha,
    );
  } catch (caught, trace) {
    Diagnostics.instance.note('recent_changes.planUndo', caught, trace);
    return (
      paths: const <String>[],
      blocked: tr(
        'Es el primer cambio del repositorio: no hay nada antes al '
        'que volver.',
      ),
    );
  }
  final paths = <String>{
    for (final change in changes) ...[
      change.path,
      if (change.from.isNotEmpty) change.from,
    ],
  }.where((path) => !path.startsWith('generated/')).toList()..sort();
  if (paths.isEmpty) {
    return (paths: paths, blocked: tr('Ese cambio solo tocó el índice.'));
  }
  for (final path in paths) {
    final then = await clone.fileAt(sha: commit.sha, path: path);
    final now = await clone.fileAt(sha: 'HEAD', path: path);
    if (then != now) {
      return (
        paths: paths,
        blocked: tr(
          '{0} se ha vuelto a cambiar después. Deshacer se llevaría '
          'ese cambio también, así que no se hace: mira su historial y '
          'recupera de ahí lo que haga falta.',
          [path],
        ),
      );
    }
  }
  return (paths: paths, blocked: null);
}

class RecentChangesDialog extends StatefulWidget {
  const RecentChangesDialog({super.key, required this.session});

  final Session session;

  @override
  State<RecentChangesDialog> createState() => _RecentChangesDialogState();
}

class _RecentChangesDialogState extends State<RecentChangesDialog> {
  List<RecentChange>? _changes;
  Object? _problem;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  List<String?> get _repos {
    final repos = [
      for (final repo in widget.session.workspace.repos) repo.id as String?,
    ];
    return repos.isEmpty ? [null] : repos;
  }

  Future<void> _load() async {
    try {
      final found = <RecentChange>[];
      for (final repo in _repos) {
        final clone = widget.session.cloneFor(repo);
        if (clone == null) continue;
        for (final commit in await clone.recent(limit: 20)) {
          found.add((repo: repo, commit: commit));
        }
      }
      found.sort((a, b) => b.commit.when.compareTo(a.commit.when));
      if (mounted) setState(() => _changes = found.take(30).toList());
    } catch (thrown) {
      if (mounted) setState(() => _problem = thrown);
    }
  }

  Future<void> _undo(RecentChange change) async {
    final session = widget.session;
    final clone = session.cloneFor(change.repo);
    if (clone == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final root = Navigator.of(context, rootNavigator: true).context;
    final plan = await planUndo(clone, change.commit);
    if (!mounted) return;
    if (plan.blocked != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('No se puede deshacer')),
          content: SizedBox(
            width: 460,
            child: Text(
              plan.blocked!,
              key: const Key('undo-blocked'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Entendido')),
            ),
          ],
        ),
      );
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Deshacer «{0}»?', [change.commit.subject])),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Vuelve lo que había antes en '
                  '{0}, '
                  'como un cambio nuevo. El que se deshace sigue en la '
                  'historia.',
                  [
                    plan.paths.length == 1
                        ? tr('este fichero')
                        : tr('estos {0} ficheros', [plan.paths.length]),
                  ],
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              for (final path in plan.paths.take(8))
                Text(
                  path,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: context.palette.muted,
                  ),
                ),
              if (plan.paths.length > 8)
                Text(
                  tr('… y {0} más', [plan.paths.length - 8]),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            key: const Key('confirm-undo'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Deshacer')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    Navigator.of(context).pop();
    if (!root.mounted) return;
    try {
      await undoAdminIn(
        root,
        session,
        {change.repo: '${change.commit.sha}~1'},
        paths: plan.paths,
        message: tr('Deshacer: {0}', [change.commit.subject]),
        done: tr('Deshecho: «{0}».', [change.commit.subject]),
      );
    } catch (thrown) {
      showProblemIn(messenger, thrown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changes = _changes;
    final several = _repos.length > 1;
    final canUndo = {
      for (final repo in _repos)
        repo:
            widget.session.admin(repo: repo) != null &&
            widget.session.canWriteIn(repo),
    };
    return AlertDialog(
      title: Text(tr('Cambios recientes')),
      content: SizedBox(
        width: 640,
        height: 480,
        child: _problem != null
            ? Center(child: Text('$_problem'))
            : changes == null
            ? const Center(child: CircularProgressIndicator())
            : changes.isEmpty
            ? Center(
                child: Text(
                  tr(
                    'Todavía no hay cambios guardados, o no hay ninguna copia '
                    'del repositorio en este ordenador.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.muted),
                ),
              )
            : ListView.separated(
                itemCount: changes.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: context.palette.rule),
                itemBuilder: (context, index) {
                  final change = changes[index];
                  final label = several
                      ? widget.session.workspace.byId(change.repo ?? '')?.label
                      : null;
                  return ListTile(
                    key: Key('recent-${change.commit.sha}'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      change.commit.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      [
                        change.commit.author,
                        describeWhen(change.commit.when),
                        ?label,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.palette.muted,
                      ),
                    ),
                    trailing: canUndo[change.repo] == true
                        ? TextButton.icon(
                            key: Key('undo-${change.commit.sha}'),
                            icon: const Icon(Icons.undo, size: 15),
                            label: Text(tr('Deshacer')),
                            onPressed: () => _undo(change),
                          )
                        : null,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cerrar')),
        ),
      ],
    );
  }
}
