/// La carpeta de compilación de cada repositorio: cuánto ocupa, y vaciarla.
///
/// No se versiona y se rehace compilando, pero crece sin que nadie la vea:
/// en el repositorio real eran 443 MB de PDF, `.aux` y registros de las
/// vistas previas de dos mil lecciones. En Ajustes → Herramientas.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/compiler.dart';
import '../state/session.dart';
import 'problem.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class BuildFolders extends StatelessWidget {
  const BuildFolders({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final repos = session.workspace.repos;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Los PDF compilados y lo que LaTeX deja al lado. No se '
                  'versiona: vaciarla no toca el material, y todo vuelve a '
                  'salir al compilar.',
                ),
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
              const SizedBox(height: 8),
              if (repos.isEmpty)
                _FolderRow(
                  session: session,
                  repo: null,
                  label: tr('El repositorio'),
                )
              else
                for (final repo in repos)
                  _FolderRow(session: session, repo: repo.id, label: repo.name),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  const _FolderRow({
    required this.session,
    required this.repo,
    required this.label,
  });

  final Session session;
  final String? repo;
  final String label;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  BuildFolder? _folder;
  Object? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Compiler? get _compiler => widget.session.compiler(repo: widget.repo);

  Future<void> _measure() async {
    final compiler = _compiler;
    if (compiler == null) return;
    try {
      final folder = await compiler.buildFolder();
      if (mounted) setState(() => _folder = folder);
    } catch (error) {
      if (mounted) setState(() => _problem = error);
    }
  }

  Future<void> _empty() async {
    final folder = _folder;
    final compiler = _compiler;
    if (folder == null || compiler == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('build-folder-confirm'),
        title: Text(
          tr('¿Vaciar la carpeta de compilación de {0}?', [widget.label]),
        ),
        content: Text(
          tr(
            'Se borran {0} en {1} ficheros de '
            '{2}: los PDF compilados, sus registros y lo que LaTeX '
            'guarda para ir más rápido. El material no se toca; los PDF vuelven '
            'a salir al compilar, y la primera vez tardan un poco más.',
            [folder.size, folder.files, folder.path],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            key: const Key('build-folder-go'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Vaciarla')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await compiler.cleanBuild();
      // Lo que la biblioteca creía compilado ya no está.
      await widget.session.refreshBuilt();
      await _measure();
    } catch (error) {
      if (mounted) showProblem(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    final String text;
    if (_problem != null) {
      text = tr('No se ha podido medir: {0}', [_problem]);
    } else if (folder == null) {
      text = tr('Midiendo…');
    } else if (folder.isEmpty) {
      text = tr('vacía');
    } else {
      text = tr('{0} en {1} ficheros', [folder.size, folder.files]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: context.palette.muted),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: Key('build-folder-${widget.repo ?? ''}'),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
          ),
          TextButton(
            key: Key('build-folder-empty-${widget.repo ?? ''}'),
            onPressed: _busy || folder == null || folder.isEmpty
                ? null
                : _empty,
            child: Text(_busy ? tr('Vaciando…') : tr('Vaciar')),
          ),
        ],
      ),
    );
  }
}
