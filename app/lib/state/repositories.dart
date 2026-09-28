/// Los repositorios abiertos: cuáles son, abrirlos con sus pasarelas,
/// añadirlos, crearlos y quitarlos.
///
/// Era una parte de la sesión, y la más grande de lo que le quedaba. Aparte
/// porque tiene su propio estado --el espacio de trabajo, una pasarela por
/// repositorio, lo que falló al abrir cada uno, quién firma los commits-- y de
/// la sesión solo necesita la credencial, las preferencias, dónde se clona y a
/// quién avisar. Cambiar qué repositorios hay cambia qué se enseña en todas
/// las pantallas, así que esto avisa por la sesión, que sigue ofreciéndolo
/// con los mismos nombres.
///
/// Lo que habla con GitHub para decidir --si se llega a un repositorio,
/// crearlo, si es de contenido-- sigue en la sesión, porque es lo que las
/// pruebas sustituyen para no necesitar una máquina conectada. Esto lo llama
/// por `session.`, igual que [Session.refreshAccess] y
/// [Session.reloadCatalogue].
library;

import 'package:flutter/foundation.dart';

import '../data/app_info.dart';
import '../data/content_gateway.dart';
import '../data/diagnostics.dart';
import '../data/example_repository.dart';
import '../data/github.dart';
import '../data/local_clone.dart';
import '../model/folder_safety.dart';
import '../model/material_ci.dart';
import '../model/translation.dart' show TranslationProvider;
import '../model/workspace.dart';
import 'session.dart';
import '../l10n/tr.dart';

/// Que el token de GitHub no puede enviar un workflow: es de antes de que
/// Didacta pidiera ese permiso, y hay que volver a entrar.
class MaterialCiException implements Exception {
  const MaterialCiException({this.unknown = false});

  /// Que no se ha podido preguntar a GitHub, y no que la respuesta sea «no».
  final bool unknown;

  @override
  String toString() => unknown
      ? tr(
          'No he podido preguntar a GitHub si tu sesión puede añadir un '
          'workflow, así que no lo añado: si no pudiera, el cambio se '
          'quedaría sin enviar y taparía los de después. Inténtalo con '
          'conexión.',
        )
      : tr(
          'Para añadir un workflow, GitHub pide un permiso que tu sesión no '
          'tiene: es de antes de que Didacta lo pidiera. Sal de GitHub y '
          'vuelve a entrar --en Ajustes → Cuenta y repositorios-- y ya se '
          'podrá.',
        );
}

/// Que la GitHub App de Didacta no llega a unos repositorios abiertos: no
/// está instalada en ellos. Se arregla en GitHub eligiéndolos.
class AppAccessMissing implements Exception {
  const AppAccessMissing(this.repos);

  final List<String> repos;

  /// Dónde se eligen.
  String get url => githubAppInstallUrl(didactaAppSlug);

  @override
  String toString() => repos.length == 1
      ? tr(
          'A {0} Didacta no llega: la GitHub App no tiene acceso. Dáselo en '
          'GitHub ({1}): en cuanto lo tenga, llega sin volver a entrar. '
          'Mientras tanto, lo de tu ordenador se puede leer y guardar, pero '
          'no enviar.',
          [repos.single, url],
        )
      : tr(
          'A {0} Didacta no llega a ninguno: la GitHub App no tiene acceso. '
          'Dáselo en GitHub ({1}): en cuanto lo tenga, llega sin volver a '
          'entrar. Mientras tanto, lo de tu ordenador se puede leer y '
          'guardar, pero no enviar.',
          [repos.join(', '), url],
        );
}

class Repositories {
  Repositories(this.session, {required this.onChanged});

  final Session session;

  /// Avisar a quien mira: la sesión, que avisa a las pantallas.
  final VoidCallback onChanged;

  /// Los repositorios abiertos, en orden.
  Workspace workspace = const Workspace.empty();

  /// Una pasarela por repositorio. Cada fichero es de uno y de uno solo.
  final Map<String, ContentGateway> gateways = {};

  /// Lo que falló al abrir cada repositorio, por si alguno no abre.
  final Map<String, Object> problems = {};

  /// Quién firma los commits de los clones.
  ({String name, String email})? cloneAuthor;

  /// Por qué no se pudo abrir lo que hay, si no se pudo. Ver
  /// [Session.accessProblem].
  Object? accessProblem;

  /// Qué impidió dejar al día el último repositorio añadido, si algo lo hizo.
  Object? addProblem;

  /// Lee el espacio de trabajo guardado.
  Future<void> restore() async {
    workspace = Workspace.fromJson(await session.preferences.workspace() ?? '');
  }

  Future<void> _save() => session.preferences.setWorkspace(workspace.toJson());

  /// Vuelve a abrir los repositorios y a recalcular sus pasarelas. Ver
  /// [Session.refreshAccess], que es por donde se llama.
  Future<void> refresh() async {
    try {
      await _open();
      accessProblem = null;
    } catch (error) {
      accessProblem = error;
    }
    onChanged();
  }

  /// Abre cada repositorio del espacio de trabajo: su clon y su pasarela.
  Future<void> _open() async {
    final auth = session.auth;
    auth.token = await auth.readToken();
    await session.settings.readSaving();
    final pushOnCommit = session.settings.pushOnCommit;
    final commitOnSave = session.settings.commitOnSave;

    // Los nuevos, aparte, y en su sitio de una vez al final. Vaciar los de
    // antes aquí --como estaba-- dejaba la aplicación varios segundos sin
    // ninguna pasarela mientras git contestaba a cada clon, y un guardado en
    // ese rato fallaba con «no está abierto el repositorio».
    final opened = <String, ContentGateway>{};
    final statuses = <String, CloneStatus>{};
    final failed = <String, Object>{};

    await auth.resolve();

    // El autor de los commits: quien ha entrado en GitHub. Sin sesión, lo que
    // git tenga configurado en la máquina, que es lo que hace que un clon
    // propio no necesite entrar en ningún sitio para escribir en él.
    final signedIn = auth.user;
    cloneAuthor = signedIn == null
        ? null
        : (name: signedIn.authorName, email: signedIn.authorEmail);

    // Todos los clones a la vez: son procesos de git que no dependen unos de
    // otros, y en fila el arranque con tres repositorios tardaba tres veces
    // lo que tarda uno.
    final clones = await Future.wait([
      for (final repo in workspace.repos)
        if (LocalClone.supported) _openClone(repo),
    ]);

    for (final each in clones) {
      final repo = each.repo;
      final problem = each.problem;
      if (problem != null) {
        // Uno que no abre no puede llevarse por delante a los demás: quien
        // tenga el otro tiene que poder trabajar con él.
        failed[repo.id] = problem;
        continue;
      }
      final clone = each.clone!;
      statuses[repo.id] = each.status!;
      // El del primero que lo tenga, en el orden del espacio de trabajo.
      cloneAuthor ??= each.author;
      opened[repo.id] = CloneGateway(
        clone: clone,
        token: auth.token ?? '',
        author: cloneAuthor,
        pushOnCommit: pushOnCommit,
        commitOnSave: commitOnSave,
        // Traer antes de escribir, con la ventana de [freshFor] para no
        // preguntar a GitHub en cada guardado. Y lo escrito deja viejo el
        // índice: la próxima recarga lo mira.
        beforeWrite: () {
          session.catalogueStore.forgetIndexFresh(repo.id);
          return session.ensureFresh(repo.id);
        },
        // El índice, al día antes de confirmar, para que vaya en el mismo
        // commit. Lo deja apuntado como comprobado, así que la recarga de
        // después no lo vuelve a mirar.
        refreshIndex: () => session.refreshIndex(only: repo.id, quiet: true),
        onUnsent: (unsent) => session.repoSync.noteUnsent(repo.id, unsent),
      );
    }

    gateways
      ..clear()
      ..addAll(opened);
    session.repoSync.setStatuses(statuses);
    problems
      ..clear()
      ..addAll(failed);

    if (session.compiler() == null) await session.engine.find();
  }

  /// Un clon, comprobado: que es el que dice ser, su estado y el autor que
  /// tenga configurado git. Lo que falle vuelve en `problem`.
  Future<
    ({
      ContentRepo repo,
      LocalClone? clone,
      CloneStatus? status,
      ({String name, String email})? author,
      Object? problem,
    })
  >
  _openClone(ContentRepo repo) async {
    try {
      final clone = LocalClone(directory: repo.directory);
      if (!await clone.looksRight(owner: repo.owner, repo: repo.name)) {
        throw CloneException(
          tr(
            '{0} no es una copia de {1}. '
            'Quítalo y vuelve a añadirlo.',
            [repo.directory, repo.id],
          ),
        );
      }
      final results = await Future.wait<Object?>([
        clone.status(),
        clone.configuredAuthor(),
      ]);
      return (
        repo: repo,
        clone: clone,
        status: results[0] as CloneStatus,
        author: results[1] as ({String name, String email})?,
        problem: null,
      );
    } catch (thrown) {
      return (
        repo: repo,
        clone: null,
        status: null,
        author: null,
        problem: thrown,
      );
    }
  }

  /// Quién firma los commits, para este clon y ninguno más.
  Future<void> setCloneAuthor({
    required String name,
    required String email,
  }) async {
    for (final repo in workspace.repos) {
      await LocalClone(
        directory: repo.directory,
      ).setAuthor(name: name, email: email);
    }
    await session.refreshAccess();
  }

  /// Los repositorios abiertos que esta cuenta no alcanza, fuera.
  ///
  /// Se hace al entrar y solo al entrar. Entrar es cuando puede cambiar la
  /// respuesta --es otra cuenta, o a esta le han quitado el acceso-- y es
  /// además el único momento en el que se sabe que hay red: comprobarlo en
  /// cada arranque costaría una llamada por repositorio y dejaría a quien
  /// abre sin conexión sin sus propias carpetas.
  ///
  /// Se quitan del espacio de trabajo, no del disco. La carpeta lleva trabajo
  /// dentro y perder el acceso a un repositorio no es motivo para borrarlo de
  /// la máquina de nadie.
  Future<void> dropUnreachable() async {
    final dropped = <String>[];
    for (final repo in workspace.repos) {
      try {
        if (await session.accessTo(repo.owner, repo.name) == null) {
          dropped.add(repo.id);
        }
      } catch (caught, trace) {
        Diagnostics.instance.note('session._dropUnreachable', caught, trace);
        // No haber podido preguntar no es un «no»: quitarle a alguien sus
        // repositorios porque GitHub tuvo un mal momento sería mucho peor
        // que dejarlos abiertos un rato de más.
      }
    }
    if (dropped.isEmpty) return;
    // Con una GitHub App no se cierra nada: que no llegue a un repositorio
    // es que la App no está instalada en él, y eso se arregla en GitHub en
    // un clic, no quitándolo de aquí. Se dice cuáles y dónde.
    if (session.auth.credential?.fromApp ?? false) {
      accessProblem = AppAccessMissing(dropped);
      return;
    }
    for (final id in dropped) {
      workspace = workspace.without(id);
    }
    await _save();
    accessProblem = CloneException(
      dropped.length == 1
          ? tr(
              'He cerrado {0}: esta cuenta no llega a él. La '
              'carpeta sigue en el disco.',
              [dropped.single],
            )
          : tr(
              'He cerrado {0} repositorios a los que esta cuenta '
              'no llega: {1}. Las carpetas siguen en el '
              'disco.',
              [dropped.length, dropped.join(', ')],
            ),
    );
  }

  /// Dónde se clonaría un repositorio, y qué hay ya ahí.
  ///
  /// Se consulta **antes** de clonar: es lo que permite decir «ya lo tienes,
  /// lo uso» o «ahí hay otra cosa, elige otra carpeta» en lugar de escribir
  /// encima y explicarlo después.
  Future<({String directory, CloneTarget state})> inspectTarget({
    required String owner,
    required String name,
    String? directory,
  }) async {
    final where = directory ?? '${session.cloneBase}/$name';
    if (!LocalClone.supported) {
      return (directory: where, state: CloneTarget.free);
    }
    return (
      directory: where,
      state: await LocalClone.inspect(
        directory: where,
        owner: owner,
        repo: name,
      ),
    );
  }

  /// Añade un repositorio al espacio de trabajo, clonándolo si hace falta.
  ///
  /// Cada uno en su carpeta, con su color. Devuelve el que ha quedado abierto.
  Future<ContentRepo> add({
    required String owner,
    required String name,
    required String branch,
    String? directory,
    int? colour,
    void Function(String line)? onProgress,
  }) async {
    final where = directory ?? '${session.cloneBase}/$name';
    final token = await session.currentToken();

    if (LocalClone.supported) {
      final existing = LocalClone(directory: where);
      final already = await existing.looksRight(owner: owner, repo: name);
      if (!already) {
        await LocalClone.create(
          directory: where,
          owner: owner,
          repo: name,
          branch: branch,
          token: token,
          url: session.remoteFor(owner, name),
          onProgress: onProgress,
        );
      }
    }

    return _register(
      owner: owner,
      name: name,
      directory: where,
      branch: branch,
      colour: colour,
    );
  }

  /// Prepara un repositorio de GitHub vacío como repositorio de contenido, y
  /// lo añade. Ver [Session.initializeRepository].
  Future<ContentRepo> initialize({
    required String owner,
    required String name,
    required String branch,
    required String title,
    String? directory,
    int? colour,
    void Function(String line)? onProgress,
  }) async {
    if (!LocalClone.supported) {
      throw CloneException(
        tr('Preparar un repositorio necesita clonarlo, y aquí no se puede.'),
      );
    }
    final where = directory ?? '${session.cloneBase}/$name';
    final token = await session.currentToken();
    final signedIn = session.auth.user;
    final author = signedIn == null
        ? cloneAuthor
        : (name: signedIn.authorName, email: signedIn.authorEmail);
    if (author == null) {
      throw CloneException(
        tr(
          'Entra en GitHub primero: el primer cambio tiene que ir a nombre de '
          'alguien.',
        ),
      );
    }

    await LocalClone.initialize(
      directory: where,
      owner: owner,
      repo: name,
      branch: branch,
      token: token,
      title: title,
      authorName: author.name,
      authorEmail: author.email,
      onProgress: onProgress,
    );
    return _register(
      owner: owner,
      name: name,
      directory: where,
      branch: branch,
      colour: colour,
    );
  }

  /// Crea el repositorio de ejemplo en la cuenta de quien ha entrado. Ver
  /// [Session.createExampleRepository].
  Future<({ContentRepo repo, bool reused})> createExample({
    Map<String, String>? files,
    void Function(String what)? onStep,
    void Function(String line)? onProgress,
  }) async {
    if (!LocalClone.supported) {
      throw CloneException(
        tr('Crear el ejemplo necesita clonarlo, y aquí no se puede.'),
      );
    }
    final signedIn = session.auth.user;
    if (signedIn == null) {
      throw CloneException(
        tr('Entra en GitHub primero: el ejemplo se crea en tu cuenta.'),
      );
    }
    final owner = signedIn.login;

    for (var attempt = 1; attempt <= 9; attempt += 1) {
      final name = attempt == 1
          ? exampleRepositoryName
          : '$exampleRepositoryName-$attempt';

      for (final repo in workspace.repos) {
        if (repo.owner == owner && repo.name == name) {
          return (repo: repo, reused: true);
        }
      }

      final there = await session.accessTo(owner, name);
      if (there != null) {
        if (!await session.isContentRepository(owner, name)) continue;
        onStep?.call(tr('Ya tenías {0}/{1}: lo abro…', [owner, name]));
        final repo = await session.addRepository(
          owner: owner,
          name: name,
          branch: there.defaultBranch,
          onProgress: onProgress,
        );
        return (repo: repo, reused: true);
      }

      // Libre en GitHub, pero puede no estarlo en el disco: una carpeta con
      // ese nombre es de alguien, y encima no se escribe.
      final target = await inspectTarget(owner: owner, name: name);
      if (target.state != CloneTarget.free) continue;

      var seed = {
        ...files ?? await loadExampleRepository(),
        materialWorkflowPath: await materialWorkflowText(),
      };
      // Los workflows solo si el token puede enviarlos: si no, GitHub
      // rechaza el primer envío entero y el ejemplo no se crea. Contra un
      // repositorio del disco --las pruebas-- no hay nada que preguntar.
      final local = session.remoteFor(owner, name) != null;
      if (!local && await session.canPushWorkflows() != true) {
        seed = {
          for (final entry in seed.entries)
            if (!entry.key.startsWith('.github/')) entry.key: entry.value,
        };
      }
      onStep?.call(tr('Creando {0}/{1} en GitHub…', [owner, name]));
      final created = await session.createGitHubRepository(
        name: name,
        description: tr(
          'El ejemplo de Didacta: una asignatura pequeña para ver cómo '
          'funciona.',
        ),
      );

      onStep?.call(tr('Subiendo el ejemplo a {0}/{1}…', [owner, name]));
      final token = await session.currentToken();
      // Un repositorio recién creado puede tardar un momento en poder
      // clonarse. Reintentar es seguro: si falla, [LocalClone.initialize]
      // deja la carpeta como estaba.
      for (var tries = 1; ; tries += 1) {
        try {
          await LocalClone.initialize(
            directory: target.directory,
            owner: owner,
            repo: name,
            branch: created.defaultBranch,
            token: token,
            title: tr('Ejemplo de Didacta'),
            authorName: signedIn.authorName,
            authorEmail: signedIn.authorEmail,
            url: session.remoteFor(owner, name),
            files: seed,
            message: tr('Empezar con el ejemplo de Didacta'),
            onProgress: onProgress,
          );
          break;
        } on CloneException {
          if (tries >= 3) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 * tries));
        }
      }
      final repo = await _register(
        owner: owner,
        name: name,
        directory: target.directory,
        branch: created.defaultBranch,
      );
      return (repo: repo, reused: false);
    }
    throw CloneException(
      tr(
        'No encuentro un nombre libre para el ejemplo: de '
        '{0} a {1}-9 están todos cogidos.',
        [exampleRepositoryName, exampleRepositoryName],
      ),
    );
  }

  /// Apunta un clon ya listo en el espacio de trabajo y lo abre.
  Future<ContentRepo> _register({
    required String owner,
    required String name,
    required String directory,
    required String branch,
    int? colour,
  }) async {
    final repo = ContentRepo(
      owner: owner,
      name: name,
      directory: directory,
      branch: branch,
      colour: colour ?? workspace.nextColour(),
    );
    workspace = workspace.with_(repo);
    await _save();
    await session.refreshAccess();
    await session.reloadCatalogue();
    return repo;
  }

  /// Añade una carpeta que ya está en el disco. Ver
  /// [Session.addExistingRepository].
  Future<ContentRepo> addExisting(String directory) async {
    final clone = session.cloneAt(directory);

    // 1. Que sea un clon de git con un remoto de GitHub.
    //
    // Una carpeta cualquiera del disco no sirve, y no por capricho: lo que
    // se escriba ahí no tiene a dónde ir. Un repositorio de contenido es la
    // fuente de la verdad de un curso entero, y una copia que solo existe en
    // un portátil es la copia que se pierde.
    final remote = await clone.remoteUrl();
    final found = repoFromRemote(remote);
    if (found == null) {
      throw CloneException(
        tr(
          '{0} no es una copia de un repositorio de GitHub. Didacta solo '
          'trabaja sobre esas copias: lo que se escribe tiene que poder enviarse, y '
          'una carpeta suelta no tiene a dónde.',
          [directory],
        ),
      );
    }

    // 2. Que la cuenta que ha entrado llegue a ese repositorio.
    //
    // Que la carpeta esté en este disco no dice nada de quién la puso ahí:
    // puede ser el clon de otra persona, o el de una cuenta anterior. Quien
    // decide si esto se puede abrir es GitHub, y se le pregunta.
    final GitHubRepo? reachable;
    try {
      reachable = await session.accessTo(found.owner, found.name);
    } on GitHubException catch (thrown) {
      throw CloneException(
        tr(
          'No se ha podido comprobar en GitHub si llegas a '
          '{0}/{1}, así que no lo añado: añadirlo sin '
          'saberlo sería abrir algo que quizá no se puede sincronizar.',
          [found.owner, found.name],
        ),
        stderr: '$thrown',
      );
    } catch (thrown) {
      throw CloneException(
        tr(
          'Sin conexión con GitHub no puedo comprobar si llegas a '
          '{0}/{1}. Añadir un repositorio se hace una vez '
          'y con red; lo que ya está añadido sigue abriéndose sin ella.',
          [found.owner, found.name],
        ),
        stderr: '$thrown',
      );
    }
    if (reachable == null) {
      final who = session.auth.user?.login;
      throw CloneException(
        tr(
          '{0}/{1} no existe o no llegas a él'
          '{2}. '
          'Pide acceso en GitHub, o entra con la cuenta que lo tiene.',
          [
            found.owner,
            found.name,
            who == null ? '' : tr(' con la cuenta {0}', [who]),
          ],
        ),
      );
    }

    final repo = ContentRepo(
      owner: found.owner,
      name: found.name,
      directory: directory,
      branch: (await clone.status()).branch,
      colour: workspace.nextColour(),
    );
    workspace = workspace.with_(repo);
    await _save();

    // 3. Y que quede al día.
    //
    // Se añade y acto seguido se pone en hora con GitHub, porque una carpeta
    // que llevaba meses parada abre enseñando material viejo sin decirlo. Lo
    // que no se puede alinear --commits sin enviar, ficheros sin guardar-- no
    // se toca ni se esconde: queda dicho y en la barra de sincronización.
    addProblem = await session.repoSync.catchUp(repo);

    await session.refreshAccess();
    await session.reloadCatalogue();
    return repo;
  }

  /// Lo quita del espacio de trabajo. Ver [Session.removeRepository].
  Future<String?> remove(String id, {bool trashFolder = false}) async {
    ContentRepo? removed;
    for (final repo in workspace.repos) {
      if (repo.id == id) removed = repo;
    }
    workspace = workspace.without(id);
    await _save();
    // Antes de tirarla: así ya nadie la está mirando.
    await session.refreshAccess();
    String? problem;
    if (trashFolder && removed != null) {
      problem = await _trashFolder(removed);
    }
    await session.reloadCatalogue();
    return problem;
  }

  /// Manda a la Papelera la carpeta de [repo], si es seguro. Devuelve el
  /// porqué si no se pudo.
  Future<String?> _trashFolder(ContentRepo repo) async {
    final folder = repo.directory;
    final why = whyNotTrash(
      folder,
      home: session.files.home,
      cloneBase: session.cloneBase,
      engine: session.enginePath,
      others: [
        for (final other in workspace.repos)
          if (other.id != repo.id) other.directory,
      ],
    );
    if (why != null) {
      return tr('No he mandado {0} a la Papelera: {1}. Sigue donde estaba.', [
        folder,
        why,
      ]);
    }
    if (!await session.files.trash(folder)) {
      return tr(
        'No he podido mandar {0} a la Papelera, así que sigue donde '
        'estaba. Si quieres quitarla, bórrala a mano.',
        [folder],
      );
    }
    return null;
  }

  /// Deja Didacta en este ordenador como recién instalada. Ver
  /// [Session.resetEverything].
  Future<List<String>> resetEverything({
    bool folders = false,
    bool templates = false,
  }) async {
    final problems = <String>[];
    if (folders) {
      for (final repo in List.of(workspace.repos)) {
        final problem = await _trashFolder(repo);
        if (problem != null) problems.add(problem);
      }
    }
    final store = session.catalogueStore.templateStore?.directory;
    if (templates && store != null && !await session.files.trash(store)) {
      problems.add(
        tr(
          'No he podido mandar las plantillas del programa ({0}) a la '
          'Papelera.',
          [store],
        ),
      );
    }
    await session.tokenStore.clear();
    for (final provider in TranslationProvider.values) {
      await session.translationSecrets.clear(provider);
    }
    await session.preferences.clearAll();
    await session.forgetLegacy();
    return problems;
  }

  /// El workflow del material, para la versión de esta aplicación. Ver
  /// `model/material_ci.dart`.
  Future<String> materialWorkflowText() async => materialWorkflow(
    engineRef: materialEngineRef((await AppInfo.load()).version),
    engineOwner: engineOwner,
    engineRepo: engineRepo,
  );

  /// Si [repo] compila en GitHub con el workflow de Didacta. Null es que no se
  /// ha podido leer.
  Future<bool?> hasMaterialCi(String repo) async {
    try {
      final file = await session.gatewayFor(repo).read(materialWorkflowPath);
      return isMaterialWorkflow(file.text);
    } on ContentException catch (thrown) {
      if (thrown.kind == ContentFailure.missing) return false;
      return null;
    } catch (caught, trace) {
      Diagnostics.instance.note('repositories.hasMaterialCi', caught, trace);
      return null;
    }
  }

  /// Pone en [repo] el workflow que compila el material en cada envío, como
  /// un cambio más: con los commits automáticos, se confirma y se envía.
  ///
  /// Si el token no puede enviar workflows no escribe nada y lo dice: un
  /// commit que GitHub rechaza se queda sin enviar y tapa los de después.
  Future<void> addMaterialCi(String repo) async {
    final allowed = await session.canPushWorkflows();
    if (allowed != true) throw MaterialCiException(unknown: allowed == null);
    final gateway = session.gatewayFor(repo);
    var sha = '';
    try {
      sha = (await gateway.read(materialWorkflowPath)).sha;
    } on ContentException catch (thrown) {
      if (thrown.kind != ContentFailure.missing) rethrow;
    }
    await gateway.save(
      path: materialWorkflowPath,
      text: await materialWorkflowText(),
      sha: sha,
      message: tr('Compilar el material en GitHub en cada cambio'),
    );
  }

  /// Cambia el color con el que se marca un repositorio en la interfaz.
  Future<void> setColour(String id, int colour) async {
    workspace = workspace.recoloured(id, colour);
    await _save();
    onChanged();
  }
}
