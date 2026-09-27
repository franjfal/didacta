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
/// fallo, y por eso [RepositoryAdder] no pinta nada: recibe cuatro funciones y
/// cada pantalla lo cuenta a su manera.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/browser.dart';
import '../data/github.dart';
import '../data/local_clone.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// El camino de abrir un repositorio, sin interfaz propia.
/// Lo que se dice cuando donde iría el clon de [repo] ya hay otra cosa.
///
/// Remitía a un botón «Abrir una carpeta» que no existe. Lo que se puede
/// hacer es vaciarla o clonar en otro sitio, y eso último se elige en la
/// sección de Ajustes que nombra.
String occupiedFolderMessage({
  required String directory,
  required String repo,
}) => tr(
  'En {0} hay algo que no es una copia de {1}. '
  'No lo he tocado: vacía esa carpeta, o cambia dónde se clonan los '
  'repositorios en Ajustes → Cuenta y repositorios.',
  [directory, repo],
);

class RepositoryAdder {
  const RepositoryAdder({
    required this.session,
    required this.onBusy,
    required this.onStep,
    required this.onProgress,
    required this.onProblem,
  });

  final Session session;

  /// Si hay algo en marcha. Lo que se enseña mientras, lo decide quien llama.
  final void Function(bool working) onBusy;

  /// Qué se está haciendo, en nuestras palabras: «Clonando didacta/curso…».
  /// Vacío cuando ya no hay nada que contar.
  ///
  /// Va aparte de [onProgress] para que lo que escribe git no lo pise: su
  /// primera línea es «Cloning into '.'...», y a partir de ahí ya no se sabe
  /// qué repositorio se está clonando.
  final void Function(String what) onStep;

  /// Una línea de las que escribe git mientras trabaja, tal cual.
  final void Function(String line) onProgress;

  /// Lo que salió mal, o `null` para limpiar lo anterior.
  final void Function(Object? problem) onProblem;

  /// Elegir repositorios de GitHub y abrirlos.
  Future<void> fromGitHub(BuildContext context) async {
    if (!session.signedIn) {
      onProblem(tr('Entra en GitHub primero.'));
      return;
    }
    final chosen = await showDialog<List<GitHubRepo>>(
      context: context,
      builder: (context) => RepoPicker(session: session),
    );
    if (chosen == null || chosen.isEmpty || !context.mounted) return;

    for (final (index, repo) in chosen.indexed) {
      if (!context.mounted) return;
      // Con varios, cuál va: tres clones seguidos sin decirlo parecen uno
      // que no acaba nunca.
      final of = chosen.length > 1
          ? tr(' ({0} de {1})', [index + 1, chosen.length])
          : '';
      if (!await _addOne(context, repo, of: of)) break;
    }
    onBusy(false);
  }

  /// Añade uno, preguntando antes si la carpeta de destino ya tiene algo.
  ///
  /// Devuelve si seguir con los demás. Clonar escribe en el disco de alguien,
  /// y la carpeta puede tener el clon de otra persona o cualquier otra cosa:
  /// mirarlo antes es lo que permite decirlo a tiempo en vez de explicarlo
  /// después.
  Future<bool> _addOne(
    BuildContext context,
    GitHubRepo chosen, {
    String of = '',
  }) async {
    final target = await session.inspectTarget(
      owner: chosen.owner,
      name: chosen.name,
    );
    if (!context.mounted) return false;

    if (target.state == CloneTarget.occupied) {
      onProblem(
        occupiedFolderMessage(directory: target.directory, repo: chosen.id),
      );
      return false;
    }

    if (target.state == CloneTarget.alreadyCloned) {
      final reuse = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('{0} ya está en tu ordenador', [chosen.id])),
          content: SizedBox(
            width: 460,
            child: Text(
              tr(
                'Ya hay una copia en {0}. No se vuelve a descargar: '
                'encima de él se perdería lo que tenga sin enviar, que puede '
                'ser el trabajo de otra persona de esta máquina.\n\n'
                'Puedo abrir ese y ponerlo al día con GitHub.',
                [target.directory],
              ),
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Dejarlo')),
            ),
            FilledButton(
              key: const Key('reuse-clone'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Abrir el que hay')),
            ),
          ],
        ),
      );
      if (reuse != true || !context.mounted) return true;
    }

    onBusy(true);
    onProblem(null);
    onStep(
      target.state == CloneTarget.alreadyCloned
          ? tr('Abriendo {0}{1}…', [chosen.id, of])
          : tr('Clonando {0}{1}…', [chosen.id, of]),
    );
    try {
      await session.addRepository(
        owner: chosen.owner,
        name: chosen.name,
        branch: chosen.defaultBranch,
        onProgress: onProgress,
      );
      // Ya está en la lista, con su marca: dejar «Clonando…» debajo diría
      // que sigue.
      onStep('');
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
        tr(
          '{0} Prepararlo es escribir en él, y con esta cuenta es '
          'de solo lectura: pídeselo a quien lo creó.',
          [empty.message],
        ),
      );
      return;
    }
    onStep(tr('{0} está vacío.', [chosen.id]));
    final title = await showDialog<String>(
      context: context,
      builder: (context) => InitializeRepositoryDialog(repo: chosen),
    );
    if (title == null) return;

    onStep(tr('Preparando {0}…', [chosen.id]));
    try {
      await session.initializeRepository(
        owner: chosen.owner,
        name: chosen.name,
        branch: chosen.defaultBranch,
        title: title,
        onProgress: onProgress,
      );
      onStep('');
    } catch (thrown) {
      onProblem(thrown);
    }
  }

  /// Crear el repositorio de ejemplo en la cuenta de quien ha entrado.
  ///
  /// Se pregunta antes, con el nombre delante, porque escribe en GitHub: el
  /// repositorio se queda en la cuenta hasta que alguien lo borre. Devuelve
  /// si quedó abierto.
  Future<bool> example(BuildContext context) async {
    if (!session.signedIn) {
      onProblem(tr('Entra en GitHub primero.'));
      return false;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => ExampleRepositoryDialog(
        owner: session.user?.login ?? tr('tu cuenta'),
      ),
    );
    if (go != true || !context.mounted) return false;

    onBusy(true);
    onProblem(null);
    onStep(tr('Preparando el ejemplo…'));
    try {
      final opened = await session.createExampleRepository(
        onStep: onStep,
        onProgress: onProgress,
      );
      onStep(
        opened.reused
            ? tr('Ya tenías el ejemplo: {0} está abierto.', [opened.repo.id])
            : tr('Listo: {0} está en tu GitHub y abierto aquí.', [
                opened.repo.id,
              ]),
      );
      return true;
    } catch (thrown) {
      onStep('');
      onProblem(thrown);
      return false;
    } finally {
      onBusy(false);
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
      onProblem(tr('Entra en GitHub primero.'));
      return;
    }
    final chosen = await getDirectoryPath();
    if (chosen == null) return;
    onBusy(true);
    onProblem(null);
    onStep(tr('Comprobando {0} en GitHub…', [chosen]));
    try {
      await session.addExistingRepository(chosen);
      onStep('');
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
    final token = await widget.session.currentToken();
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
    title: Text(tr('Añadir repositorios')),
    content: SizedBox(
      width: 520,
      height: 440,
      child: Column(
        children: [
          TextField(
            key: const Key('repo-filter'),
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: tr('Buscar'),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filter = value.toLowerCase()),
          ),
          // Con la GitHub App, la lista trae solo los repositorios a los que
          // se le ha dado acceso: el que falta se añade en GitHub, y vuelve
          // a salir aquí sin entrar otra vez.
          if (widget.session.auth.credential?.fromApp ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(
                        'Salen los repositorios a los que Didacta tiene acceso.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('repo-app-access'),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: Text(tr('Dar acceso a otro')),
                    onPressed: () =>
                        openLink(githubAppInstallUrl(didactaAppSlug)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<GitHubRepo>>(
              future: _repos,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Note(
                    '${snapshot.error}',
                    tone: context.palette.teacher,
                  );
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
                  return Center(
                    child: Text(tr('Ninguno que no esté ya abierto.')),
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
                          if (!repo.canWrite) tr('solo lectura'),
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
        child: Text(tr('Cancelar')),
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
            _chosen.length <= 1
                ? tr('Añadir')
                : tr('Añadir {0}', [_chosen.length]),
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
    title: Text(tr('Este repositorio está vacío')),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              '{0} todavía está vacío, así que no hay '
              'nada que descargar. Didacta puede prepararlo como repositorio de '
              'contenido:',
              [widget.repo.id],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              '• didacta.yaml, con el nombre y los idiomas es, va y en\n'
              '• .gitignore, para que lo compilado no entre en git\n'
              '• el primer cambio en {0}, enviado a '
              'GitHub',
              [widget.repo.defaultBranch],
            ),
            style: TextStyle(fontSize: 12.5, color: context.palette.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('initialize-title'),
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('Nombre del repositorio de contenido'),
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
        child: Text(tr('Cancelar')),
      ),
      FilledButton(
        key: const Key('initialize-repository'),
        onPressed: _accept,
        child: Text(tr('Preparar y añadir')),
      ),
    ],
  );
}

/// Qué se va a hacer al pedir el ejemplo, antes de hacerlo.
class ExampleRepositoryDialog extends StatelessWidget {
  const ExampleRepositoryDialog({super.key, required this.owner});

  /// La cuenta en la que se crea.
  final String owner;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Probar con un ejemplo')),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Una asignatura pequeña para ver Didacta con algo dentro: Cálculo I, '
              'con un tema, una hoja de problemas, lecciones traducidas y otras '
              'por traducir, y un README que cuenta cómo está organizado y por '
              'qué.',
            ),
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'Lo creo en tu cuenta como {0}/didacta-ejemplo, privado, y lo '
              'abro aquí. Es tuyo: puedes compilarlo, cambiarlo y romperlo sin '
              'miedo, y borrarlo desde GitHub cuando ya no lo quieras.',
              [owner],
            ),
            style: const TextStyle(fontSize: 12.5, height: 1.5),
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
        key: const Key('create-example'),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(tr('Crear el ejemplo')),
      ),
    ],
  );
}
