/// Abrir un repositorio de contenido: los diálogos y el camino entero.
///
/// Está aquí y no dentro de Ajustes porque hay **dos sitios** desde donde se
/// hace, y son los dos primeros que ve alguien: el asistente de bienvenida y
/// Ajustes. Repartir esto entre los dos dejaría dos mitades de lo mismo, y la
/// que se arreglara primero sería la que menos se usa.
///
/// Lo que comparten es el camino, que tiene más recodos de los que parece:
/// mirar antes si en la carpeta de destino ya hay algo, ofrecer abrir el clon
/// que ya estaba en lugar de escribir encima, y reconocer un repositorio de
/// GitHub recién creado y vacío como lo que es --uno por empezar-- y no como
/// un error.
///
/// Lo que **no** comparten es cómo se enseña el progreso ni dónde sale un
/// fallo, y por eso [RepositoryAdder] no pinta nada: recibe tres funciones y
/// cada pantalla lo cuenta a su manera.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/github.dart';
import '../data/local_clone.dart';
import '../state/session.dart';
import 'theme.dart';

/// El camino de abrir un repositorio, sin interfaz propia.
class RepositoryAdder {
  const RepositoryAdder({
    required this.session,
    required this.onBusy,
    required this.onProgress,
    required this.onProblem,
  });

  final Session session;

  /// Si hay algo en marcha. Lo que se enseña mientras, lo decide quien llama.
  final void Function(bool working) onBusy;

  /// Una línea de progreso: la que escribe git al clonar, o la nuestra.
  final void Function(String line) onProgress;

  /// Lo que salió mal, o `null` para limpiar lo anterior.
  final void Function(Object? problem) onProblem;

  /// Elegir repositorios de GitHub y abrirlos.
  Future<void> fromGitHub(BuildContext context) async {
    if (!session.signedIn) {
      onProblem('Entra en GitHub primero.');
      return;
    }
    final chosen = await showDialog<List<GitHubRepo>>(
      context: context,
      builder: (context) => RepoPicker(session: session),
    );
    if (chosen == null || chosen.isEmpty || !context.mounted) return;

    for (final repo in chosen) {
      if (!context.mounted) return;
      if (!await _addOne(context, repo)) break;
    }
    onBusy(false);
  }

  /// Añade uno, preguntando antes si la carpeta de destino ya tiene algo.
  ///
  /// Devuelve si seguir con los demás. Clonar escribe en el disco de alguien,
  /// y la carpeta puede tener el clon de otra persona o cualquier otra cosa:
  /// mirarlo antes es lo que permite decirlo a tiempo en vez de explicarlo
  /// después.
  Future<bool> _addOne(BuildContext context, GitHubRepo chosen) async {
    final target = await session.inspectTarget(
      owner: chosen.owner,
      name: chosen.name,
    );
    if (!context.mounted) return false;

    if (target.state == CloneTarget.occupied) {
      onProblem(
        'En ${target.directory} hay algo que no es un clon de ${chosen.id}. '
        'No lo he tocado: vacía esa carpeta o elige otra con «Abrir una '
        'carpeta».',
      );
      return false;
    }

    if (target.state == CloneTarget.alreadyCloned) {
      final reuse = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${chosen.id} ya está clonado'),
          content: SizedBox(
            width: 460,
            child: Text(
              'Ya hay un clon en ${target.directory}. No se vuelve a clonar: '
              'encima de él se perdería lo que tenga sin enviar, que puede '
              'ser el trabajo de otra persona de esta máquina.\n\n'
              'Puedo abrir ese y ponerlo al día con GitHub.',
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Dejarlo'),
            ),
            FilledButton(
              key: const Key('reuse-clone'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Abrir el que hay'),
            ),
          ],
        ),
      );
      if (reuse != true || !context.mounted) return true;
    }

    onBusy(true);
    onProblem(null);
    onProgress(
      target.state == CloneTarget.alreadyCloned
          ? 'Abriendo ${chosen.id}…'
          : 'Clonando ${chosen.id}…',
    );
    try {
      await session.addRepository(
        owner: chosen.owner,
        name: chosen.name,
        branch: chosen.defaultBranch,
        onProgress: onProgress,
      );
    } on EmptyRepositoryException catch (empty) {
      // Recién creado en GitHub y sin nada dentro. No es un error que haya
      // que enseñar tal cual: es un repositorio por empezar, y eso se puede
      // hacer desde aquí.
      if (context.mounted) await _offerToInitialize(context, chosen, empty);
    } catch (thrown) {
      onProblem(thrown);
      return false;
    }
    return true;
  }

  /// Ofrece preparar un repositorio vacío y, si se acepta, lo prepara.
  ///
  /// Recoge sus propios errores: se llama desde el `on` de [_addOne], y lo
  /// que se lanza dentro de un `catch` no lo recoge el siguiente.
  Future<void> _offerToInitialize(
    BuildContext context,
    GitHubRepo chosen,
    EmptyRepositoryException empty,
  ) async {
    if (!chosen.canWrite) {
      onProblem(
        '${empty.message} Prepararlo es escribir en él, y con esta cuenta es '
        'de solo lectura: pídeselo a quien lo creó.',
      );
      return;
    }
    onProgress('${chosen.id} está vacío.');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => InitializeRepositoryDialog(repo: chosen),
    );
    if (title == null) return;

    onProgress('Preparando ${chosen.id}…');
    try {
      await session.initializeRepository(
        owner: chosen.owner,
        name: chosen.name,
        branch: chosen.defaultBranch,
        title: title,
        onProgress: onProgress,
      );
    } catch (thrown) {
      onProblem(thrown);
    }
  }

  /// Añadir una carpeta que ya está en el disco.
  ///
  /// De qué repositorio es lo dice su propio remoto, y si esta cuenta llega a
  /// él lo dice GitHub. Las dos cosas se comprueban: una carpeta cualquiera
  /// no sirve --lo que se escriba ahí no tiene a dónde ir-- y un clon de otra
  /// cuenta tampoco.
  Future<void> fromFolder(BuildContext context) async {
    if (!session.signedIn) {
      onProblem('Entra en GitHub primero.');
      return;
    }
    final chosen = await getDirectoryPath();
    if (chosen == null) return;
    onBusy(true);
    onProblem(null);
    onProgress('Comprobando $chosen en GitHub…');
    try {
      await session.addExistingRepository(chosen);
      // Se añadió, pero puede no haber quedado al día: eso no es un fallo de
      // añadir, y decirlo como si lo fuera haría pensar que no se añadió.
      onProblem(session.addProblem);
    } catch (thrown) {
      onProblem(thrown);
    } finally {
      onBusy(false);
    }
  }
}

/// Elegir de entre los repositorios de GitHub de esta persona.
class RepoPicker extends StatefulWidget {
  const RepoPicker({super.key, required this.session});

  final Session session;

  @override
  State<RepoPicker> createState() => _RepoPickerState();
}

class _RepoPickerState extends State<RepoPicker> {
  late final Future<List<GitHubRepo>> _repos = _load();
  String _filter = '';

  /// Los marcados. Varios a la vez porque una asignatura puede estar repartida
  /// --la teoría en uno, los problemas en otro-- y quien llega nuevo los
  /// quiere los dos: pedirlos de uno en uno obliga a saber de antemano que
  /// hacen falta dos, que es justo lo que no se sabe todavía.
  final Set<String> _chosen = {};

  Future<List<GitHubRepo>> _load() async {
    final token = await widget.session.tokenStore.read() ?? '';
    final api = GitHubApi(token: token);
    try {
      final all = await api.repositories();
      final already = {
        for (final repo in widget.session.workspace.repos) repo.id,
      };
      return [
        for (final repo in all)
          if (!already.contains(repo.id)) repo,
      ];
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Añadir repositorios'),
    content: SizedBox(
      width: 520,
      height: 440,
      child: Column(
        children: [
          TextField(
            key: const Key('repo-filter'),
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filter = value.toLowerCase()),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<GitHubRepo>>(
              future: _repos,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Note('${snapshot.error}', tone: didactaTeacher);
                }
                final repos = snapshot.data;
                if (repos == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final shown = [
                  for (final repo in repos)
                    if (_filter.isEmpty ||
                        repo.id.toLowerCase().contains(_filter))
                      repo,
                ];
                if (shown.isEmpty) {
                  return const Center(
                    child: Text('Ninguno que no esté ya abierto.'),
                  );
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final repo = shown[index];
                    return CheckboxListTile(
                      key: Key('pick-${repo.id}'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _chosen.contains(repo.id),
                      onChanged: (on) => setState(() {
                        if (on ?? false) {
                          _chosen.add(repo.id);
                        } else {
                          _chosen.remove(repo.id);
                        }
                      }),
                      title: Text(repo.id),
                      subtitle: Text(
                        [
                          repo.defaultBranch,
                          if (repo.private) 'privado',
                          if (!repo.canWrite) 'solo lectura',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                );
              },
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
      FutureBuilder<List<GitHubRepo>>(
        future: _repos,
        builder: (context, snapshot) => FilledButton(
          key: const Key('add-chosen-repos'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                  for (final repo in snapshot.data ?? const <GitHubRepo>[])
                    if (_chosen.contains(repo.id)) repo,
                ]),
          child: Text(
            _chosen.length <= 1 ? 'Añadir' : 'Añadir ${_chosen.length}',
          ),
        ),
      ),
    ],
  );
}

/// Preparar un repositorio de GitHub vacío para trabajar con él.
///
/// Se pregunta antes y se dice qué se va a hacer, porque escribe en GitHub:
/// el primer commit se queda en el historial del repositorio. Solo se pide el
/// nombre; lo demás tiene valores por defecto que luego se cambian en
/// `didacta.yaml`.
class InitializeRepositoryDialog extends StatefulWidget {
  const InitializeRepositoryDialog({super.key, required this.repo});

  final GitHubRepo repo;

  @override
  State<InitializeRepositoryDialog> createState() =>
      _InitializeRepositoryDialogState();
}

class _InitializeRepositoryDialogState
    extends State<InitializeRepositoryDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.repo.name,
  );

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _accept() {
    final title = _title.text.trim();
    Navigator.of(context).pop(title.isEmpty ? widget.repo.name : title);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Este repositorio está vacío'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.repo.id} todavía no tiene ningún commit, así que no hay '
            'nada que clonar. Didacta puede prepararlo como repositorio de '
            'contenido:',
          ),
          const SizedBox(height: 10),
          Text(
            '• didacta.yaml, con el nombre y los idiomas es, va y en\n'
            '• .gitignore, para que lo compilado no entre en git\n'
            '• el primer commit en ${widget.repo.defaultBranch}, enviado a '
            'GitHub',
            style: const TextStyle(fontSize: 12.5, color: didactaMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('initialize-title'),
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre del repositorio de contenido',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _accept(),
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
        key: const Key('initialize-repository'),
        onPressed: _accept,
        child: const Text('Preparar y añadir'),
      ),
    ],
  );
}
