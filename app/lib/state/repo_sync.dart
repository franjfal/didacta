/// Tener los clones al día con GitHub: traer, enviar, comprobar antes de
/// escribir y lo que se sabe de cada uno.
///
/// Era una parte de la sesión. Aparte porque tiene su propio estado --el de
/// cada clon, cuándo se comprobó, las comprobaciones en marcha (una por clon:
/// dos guardados seguidos esperan a la misma), lo que no se pudo enviar-- y
/// de la sesión solo necesita los repositorios abiertos, la credencial y el
/// registro de git. Abrir, añadir y quitar repositorios está en
/// `repositories.dart`; la sesión ofrece esto con los mismos nombres.
///
/// **Avisa sola**, no por la sesión: cada guardado comprueba que el clon esté
/// al día, y que eso redibujara la aplicación entera era pagar por cada
/// guardado una pantalla nueva. Quien enseña cómo está un clon --la barra de
/// sincronización, la tira de abajo, el menú de enviar-- la escucha a ella.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/diagnostics.dart';
import '../data/local_clone.dart';
import '../model/workspace.dart';
import 'session.dart';
import '../l10n/tr.dart';

class RepoSync extends ChangeNotifier {
  RepoSync(this.session);

  final Session session;

  /// Lo que dijo git de cada clon al abrirlos todos.
  void setStatuses(Map<String, CloneStatus> statuses) {
    _cloneStatus
      ..clear()
      ..addAll(statuses);
  }

  /// Vuelve a preguntar a GitHub como si no se hubiera preguntado nunca.
  void forgetRemoteProblem() => _remoteProblem = null;

  /// Cómo está cada clon respecto a GitHub, por repositorio.
  final Map<String, CloneStatus> _cloneStatus = {};

  CloneStatus? statusOf(String repo) => _cloneStatus[repo];

  /// Lo que se enseña mientras git todavía no ha dicho nada.
  static String get _gitOpening => tr('Preguntándole a git…');
  static String get _gitAbout => tr('Todo lo que dice git, según lo dice.');

  /// Qué dijo GitHub la última vez que se preguntó.
  ///
  /// Null cuando no se ha preguntado o no hay a quién preguntar. Es la
  /// segunda mitad de «actualizar»: lo de este disco ya está al día, pero
  /// puede haber trabajo de otra persona --o del mismo, desde otra máquina--
  /// esperando en el repositorio.
  int? get behind {
    if (_cloneStatus.isEmpty) return null;
    var most = 0;
    for (final status in _cloneStatus.values) {
      if (status.behind > most) most = status.behind;
    }
    return most;
  }

  /// Cuántos commits hay sin enviar, sumando los repositorios.
  int get ahead {
    var total = 0;
    for (final status in _cloneStatus.values) {
      total += status.ahead;
    }
    return total;
  }

  /// Los ficheros tocados fuera de la aplicación, por repositorio.
  Map<String, List<String>> get pendingChanges => {
    for (final entry in _cloneStatus.entries)
      if (entry.value.dirtyPaths.isNotEmpty) entry.key: entry.value.dirtyPaths,
  };

  /// Pregunta a GitHub si hay algo nuevo, sin traerlo.
  ///
  /// Traerlo es otra decisión: un `pull` cambia los ficheros de debajo de
  /// quien está editando, y eso no se hace sin decirlo. Aquí solo se mira.
  Future<int> checkRemote() async {
    if (session.openedWorkspace.isEmpty) return 0;
    try {
      final token = await session.currentToken();
      for (final repo in session.openedWorkspace.repos) {
        final clone = session.cloneAt(repo.directory);
        await clone.fetch(token: token);
        _cloneStatus[repo.id] = await clone.status();
      }
      notifyListeners();
      return session.behind ?? 0;
    } catch (error) {
      // Sin red, sin token o sin remoto: lo local sigue valiendo, y decirlo
      // como un error pararía un refresco que ya ha hecho su trabajo.
      _remoteProblem = error;
      notifyListeners();
      return 0;
    }
  }

  /// Por qué no se pudo preguntar a GitHub, si no se pudo.
  Object? get remoteProblem => _remoteProblem;
  Object? _remoteProblem;

  /// Confirma lo que haya escrito y sin confirmar, con un mensaje.
  ///
  /// **También con los commits automáticos puestos.** Se creía que con ellos
  /// no quedaba nunca nada pendiente, y no es verdad: lo que se escribe
  /// desde fuera --otro editor, un `cp` de una lección, una carpeta traída
  /// de otro sitio-- aparece en el árbol de trabajo sin pasar por Didacta, y
  /// ahí se queda. Setecientos ficheros sin confirmar en un repositorio son
  /// setecientos ficheros que nadie más tiene.
  ///
  /// [only] son las rutas elegidas, por repositorio; null es todo lo
  /// pendiente. Se puede elegir porque setecientos ficheros rara vez son un
  /// solo cambio que contar, y un commit que dice «Editar 706 ficheros» es
  /// un commit que nadie va a poder leer dentro de seis meses.
  ///
  /// Repositorio por repositorio y por rutas, no un `git add -A`: cada uno
  /// tiene su historial y su mensaje, y barrer el árbol entero se llevaría al
  /// commit lo que alguien tenga a medias fuera de Didacta.
  ///
  /// Devuelve en cuántos repositorios se confirmó algo.
  Future<int> commitPending(
    String message, {
    Map<String, List<String>>? only,
  }) async {
    // El registro, desde el principio: confirmar setecientos ficheros tarda,
    // y lo que tarda tiene que decir lo que está haciendo.
    session.syncConsole.start(
      tr('Guardar en el historial'),
      opening: _gitOpening,
      about: _gitAbout,
    );

    if (message.trim().isEmpty) {
      final problem = ArgumentError(
        tr('para guardar hace falta decir qué has cambiado'),
      );
      session.syncConsole.finish(failure: problem);
      throw problem;
    }
    final author = session.cloneAuthor;
    if (author == null) {
      final problem = ArgumentError(
        tr(
          'Para guardar en el historial hace falta un autor. Entra en GitHub antes.',
        ),
      );
      session.syncConsole.finish(failure: problem);
      throw problem;
    }

    final chosen = only ?? pendingChanges;
    session.syncConsole.expect(
      chosen.values.where((files) => files.isNotEmpty).length,
    );

    var done = 0;
    Object? failure;
    for (final entry in chosen.entries) {
      if (entry.value.isEmpty) continue;
      final clone = session.cloneFor(entry.key);
      if (clone == null) continue;
      session.syncConsole.startStep(entry.key);
      session.syncConsole.add('=== ${entry.key}');
      try {
        final committed = await clone.commitPaths(
          paths: entry.value,
          message: message.trim(),
          authorName: author.name,
          authorEmail: author.email,
          token: session.auth.token ?? '',
          // Enviar o no lo decide la otra preferencia, igual que con los
          // commits automáticos: son dos decisiones distintas.
          push: session.pushOnCommit && (session.auth.token ?? '').isNotEmpty,
          onProgress: session.syncConsole.add,
        );
        if (committed) done += 1;
        if (!committed) {
          session.syncConsole.add('--- ${tr('no había nada que confirmar')}');
        }
      } catch (thrown) {
        // Uno que falle no para a los demás, igual que al enviar: lo que se
        // pudo confirmar queda confirmado, y por qué no salió el otro está
        // escrito ahí arriba.
        failure ??= thrown;
        session.syncConsole.add('--- FAIL $thrown');
      }
      session.syncConsole.finishStep();
    }
    if (done > 0) {
      session.syncConsole.startStep(tr('volviendo a mirar los repositorios'));
      await session.refreshAccess();
    }
    session.syncConsole.finish(ok: failure == null);
    if (failure != null) throw failure;
    return done;
  }

  /// Cuántos ficheros hay escritos y sin confirmar, en todos los repositorios.
  int get pendingCount =>
      pendingChanges.values.fold<int>(0, (sum, files) => sum + files.length);

  /// Cuánto vale una comprobación de que un clon está al día.
  ///
  /// Cinco minutos. Editando se guarda muchas veces seguidas --cada campo de
  /// un problema, cada vuelta a una unidad-- y preguntar a GitHub en cada
  /// guardado convertiría cada pulsación en una llamada de red: la aplicación
  /// se pondría lenta justo en lo que más se hace, y GitHub acabaría
  /// limitando las peticiones. Lo que hace falta es no editar sobre material
  /// viejo, y para eso una comprobación de hace un momento vale igual que una
  /// de ahora: en cinco minutos nadie ha empujado y se ha ido.
  static const Duration freshFor = Duration(minutes: 5);

  /// Cuándo se comprobó por última vez que cada clon estaba al día.
  final Map<String, DateTime> _verified = {};

  /// Se asegura de que el clon de [repo] está al día antes de escribir en él.
  ///
  /// Es la otra mitad de «siempre sincronizados»: traer antes de modificar,
  /// enviar después. Sin esto, dos personas sobre el mismo tema se pisan sin
  /// enterarse hasta que una de las dos no puede enviar.
  ///
  /// Cuatro cosas que decide, y las cuatro importan:
  ///
  /// * **no pregunta si preguntó hace poco** ([freshFor]). Guardar es lo que
  ///   más se hace, y una llamada de red por guardado se nota;
  /// * **avanza solo si no hay nada que perder**: con el clon limpio y sin
  ///   commits propios, ponerse al día es un avance rápido;
  /// * **si ha divergido, no toca nada y lo dice**. Juntar dos historias es
  ///   un merge, y eso no lo decide un guardado;
  /// * **sin red, deja escribir**. Un commit a un clon del propio disco no
  ///   necesita credencial ni conexión, y bloquear el guardado ahí sería
  ///   perder trabajo para proteger una sincronización que se hará luego.
  Future<void> ensureFresh(String? repo) async {
    final id = repo ?? session.openedWorkspace.repos.firstOrNull?.id;
    if (id == null) return;
    final target = session.openedWorkspace.repos
        .where((r) => r.id == id)
        .firstOrNull;
    if (target == null || !LocalClone.supported) return;

    final last = _verified[id];
    if (last != null && DateTime.now().difference(last) < freshFor) return;

    // De vuelo único: dos guardados seguidos esperan a la misma comprobación
    // en vez de lanzar cada uno la suya, con su `fetch` y quizá su `pull`.
    final running = _checking[id];
    if (running != null) return running;
    final check = _ensureFreshNow(id, target);
    _checking[id] = check;
    try {
      await check;
    } finally {
      // Lo que devuelve es la misma comprobación que se acaba de esperar.
      _checking.remove(id)?.ignore();
    }
  }

  final Map<String, Future<void>> _checking = {};

  Future<void> _ensureFreshNow(String id, ContentRepo target) async {
    final problem = await catchUp(target);
    if (problem == null) {
      _verified[id] = DateTime.now();
      _driftProblem.remove(id);
    } else {
      // No se marca como comprobado: la próxima vez se vuelve a intentar, que
      // es lo que hace que esto se arregle solo en cuanto vuelva la red o se
      // resuelva el desfase desde la barra.
      _driftProblem[id] = problem;
    }
    notifyListeners();
  }

  final Map<String, Object> _driftProblem = {};

  /// Qué decir al guardar en [repo]: que está guardado y, si no se pudo
  /// enviar, también eso. Lo segundo en el momento y no solo en la barra: es
  /// cuando alguien se pregunta si lo que acaba de escribir ha llegado.
  String saveNotice(String? repo, {int files = 1}) {
    final id = repo ?? session.openedWorkspace.repos.firstOrNull?.id;
    if (_driftProblem[id] is UnsentException) {
      return tr(
        'Guardado en tu ordenador, pero no se ha podido enviar a GitHub. '
        'Se enviará la próxima vez que envíes.',
      );
    }
    return files == 1
        ? tr('Guardado en el historial.')
        : tr('{0} ficheros guardados en el historial.', [files]);
  }

  /// Se guardó en [repo] pero no se pudo enviar: se dice donde se ve si un
  /// repositorio está al día, que es también donde se envía.
  void noteUnsent(String repo, UnsentException unsent) {
    _driftProblem[repo] = unsent;
    notifyListeners();
  }

  /// Cuánto se espera a GitHub al comprobar antes de guardar.
  static const Duration freshFetchLimit = Duration(seconds: 8);

  /// Qué impide que un repositorio esté al día con GitHub, si algo lo impide.
  ///
  /// Se enseña donde se ve el repositorio. No es un error de guardar --lo
  /// guardado está guardado-- sino una advertencia sobre lo que hay debajo.
  Object? driftOf(String repo) => _driftProblem[repo];

  /// Vuelve a exigir una comprobación, aunque se hiciera hace un momento.
  ///
  /// Después de traer o de enviar: lo que se acaba de hacer cambia lo que una
  /// comprobación anterior daba por bueno.
  void forgetFreshness() => _verified.clear();

  /// Pone un clon en hora con GitHub, hasta donde se pueda sin pisar nada.
  ///
  /// Trae siempre, y **avanza mientras no haya historia propia que juntar**.
  /// Con commits locales sin enviar no se toca nada: unir dos historias es un
  /// merge o un rebase, y eso no lo decide ni un guardado ni un botón de
  /// «añadir carpeta». Se dice lo que hay y se deja para la barra de
  /// sincronización, que es donde se trae y se envía a propósito.
  ///
  /// Quién decide si un fichero suelto sin guardar estorba es **git**, con
  /// `pull --ff-only`, y no una comprobación propia: un `generated/` recién
  /// regenerado deja el clon sucio casi siempre, y negarse a avanzar por eso
  /// habría convertido la garantía en un aviso permanente que nadie lee. Si
  /// lo que viene pisa algo sin guardar, git se niega y su mensaje es el
  /// bueno.
  ///
  /// Devuelve qué lo impidió, o null si quedó al día.
  Future<Object?> catchUp(ContentRepo repo) async {
    final token = await session.currentToken();
    final clone = session.cloneAt(repo.directory);
    try {
      // Corto: esto va delante de cada guardado, y sin red --o con una que
      // no contesta-- lo que toca es guardar igual y avisar, no esperar los
      // cinco minutos que se le dan a un `fetch` pedido a propósito.
      await clone.fetch(token: token, timeout: freshFetchLimit);
      final status = await clone.status();
      if (status.behind == 0) {
        // Al día en lo que importa aquí. Los commits propios sin enviar no
        // son un desfase con GitHub: son trabajo esperando a salir, y de eso
        // ya habla la barra de sincronización.
        return null;
      }
      if (status.ahead == 0) {
        await clone.pull(token: token);
        return null;
      }
      return CloneException(
        tr(
          '{0} no está al día con GitHub: {1}. '
          'Las dos historias han seguido por su lado, así que hay que juntarlas '
          'desde la barra de sincronización antes de seguir.',
          [repo.id, _describeDrift(status)],
        ),
      );
    } catch (thrown) {
      return thrown;
    }
  }

  static String _describeDrift(CloneStatus status) {
    final pieces = [
      if (status.behind > 0)
        status.behind == 1
            ? tr('1 commit por traer')
            : tr('{0} commits por traer', [status.behind]),
      if (status.ahead > 0) tr('{0} sin enviar', [status.ahead]),
      if (status.dirtyPaths.isNotEmpty)
        status.dirtyPaths.length == 1
            ? tr('1 fichero sin guardar')
            : tr('{0} ficheros sin guardar', [status.dirtyPaths.length]),
    ];
    return pieces.join(', ');
  }

  /// Trae de GitHub lo que haya en todos los repositorios.
  ///
  /// Devuelve cuántos commits se han traído, por repositorio. Uno que falle
  /// no para a los demás: se cuenta y se sigue.
  Future<Map<String, Object>> pullAll() async {
    // Lo primero de todo y antes del primer `await`, para que quien abra el
    // registro justo después lo encuentre ya en marcha y no enseñando lo de
    // la vez anterior.
    session.syncConsole.start(
      tr('Traer de GitHub'),
      total: session.openedWorkspace.repos.length,
      opening: _gitOpening,
      about: _gitAbout,
    );

    final result = <String, Object>{};
    final token = await session.currentToken();
    for (final repo in session.openedWorkspace.repos) {
      session.syncConsole.startStep(repo.label);
      session.syncConsole.add('=== ${repo.id}');
      try {
        final clone = session.cloneAt(repo.directory);
        final before = await clone.status();
        await clone.pull(token: token, onProgress: session.syncConsole.add);
        final after = await clone.status();
        _cloneStatus[repo.id] = after;
        result[repo.id] = before.head == after.head ? 0 : (before.behind);
        // El commit en el que queda, y no cuántos entraron: `before.behind`
        // es de la última vez que se preguntó a GitHub, así que en un clon
        // que no había hecho `fetch` diría cero justo cuando acaba de traer
        // algo. Cuántos fueron ya lo dice git ahí arriba.
        session.syncConsole.add(
          before.head == after.head
              ? '--- ${tr('ya estaba al día')}'
              : '--- ${tr('ahora en {0}', [after.head])}',
        );
      } catch (thrown) {
        result[repo.id] = thrown;
        session.syncConsole.add('--- FAIL $thrown');
      }
      session.syncConsole.finishStep();
    }

    // Y el registro sigue abierto durante lo que queda, que no es de git
    // pero tarda igual: releer el índice de un repositorio grande son varios
    // segundos más. Cerrarlo al acabar el `pull` devolvería la aplicación a
    // la pantalla quieta que esto viene a quitar, justo antes del final.
    session.syncConsole.startStep(tr('releyendo el índice'));
    session.syncConsole.add('--- ${tr('releyendo el índice y el catálogo')}');
    forgetFreshness();
    await session.refreshAccess();
    // Todo lo de después de traer, una vez: el índice de cada repositorio
    // --comprobado y regenerado si hace falta--, el catálogo, lo compilado y
    // la vigilancia del disco. Antes la pantalla llamaba además a
    // «actualizarlo todo», que regeneraba a la fuerza los índices recién
    // comprobados y volvía a leer el catálogo entero.
    await session.refreshIndex(quiet: true);
    await session.reloadCatalogue();
    await session.refreshBuilt();
    await session.catalogueStore.rememberIndexDates();
    session.watchDisk();
    session.syncConsole.finish(ok: result.values.every((each) => each is int));
    return result;
  }

  /// Lo que se enviaría: por repositorio, lo que está sin guardar y lo que
  /// está guardado y sin enviar.
  Future<List<RepoOutbox>> outbox() async {
    final boxes = <RepoOutbox>[];
    for (final repo in session.openedWorkspace.repos) {
      try {
        final status = await session.cloneAt(repo.directory).status();
        _cloneStatus[repo.id] = status;
        if (status.ahead == 0 && status.dirtyPaths.isEmpty) continue;
        boxes.add(
          RepoOutbox(
            repo: repo,
            ahead: status.ahead,
            pending: status.dirtyPaths,
          ),
        );
      } catch (caught, trace) {
        Diagnostics.instance.note('session.outbox', caught, trace);
        // Un repositorio que no se puede leer no tiene nada que enviar.
      }
    }
    return boxes;
  }

  /// Envía a GitHub: cierra en un commit lo que quedara suelto y empuja.
  ///
  /// El mensaje es uno para todos porque el gesto es uno: se estaba
  /// trabajando en algo, y ese algo tocó ficheros de varios repositorios.
  ///
  /// Sin [commitPending], solo lo que ya tiene commit: es lo que hace el menú
  /// (⌘⇧U), que no pregunta mensaje. Antes cerraba también lo suelto con el
  /// mensaje «Enviar», que en el historial no dice nada de lo que se hizo.
  Future<Map<String, Object>> pushAll(
    String message, {
    bool commitPending = true,
  }) async {
    // Antes del primer `await`, por lo mismo que en `pullAll`: la primera
    // espera de un envío es `outbox()`, que en un repositorio grande son ya
    // varios segundos de `git status`, y arrancar el registro después
    // dejaría sin contar justo el tramo en el que no se ve nada.
    session.syncConsole.start(
      tr('Enviar a GitHub'),
      opening: _gitOpening,
      about: _gitAbout,
    );

    final result = <String, Object>{};
    final token = await session.currentToken();
    final author = session.cloneAuthor;
    final boxes = await session.outbox();
    session.syncConsole.expect(boxes.length);
    if (boxes.isEmpty) {
      session.syncConsole.add('--- ${tr('no había nada que enviar')}');
    }

    for (final box in boxes) {
      session.syncConsole.startStep(box.repo.label);
      session.syncConsole.add('=== ${box.repo.id}');
      if (!commitPending && box.ahead == 0) {
        // Nada confirmado aquí: lo que hay está sin guardar, y eso necesita
        // un mensaje que este camino no tiene.
        result[box.repo.id] = 0;
        session.syncConsole.add('--- ${tr('nada confirmado que enviar')}');
        session.syncConsole.finishStep();
        continue;
      }
      try {
        final clone = session.cloneAt(box.repo.directory);
        if (commitPending && box.pending.isNotEmpty && author != null) {
          await clone.commitPaths(
            paths: box.pending,
            message: message,
            authorName: author.name,
            authorEmail: author.email,
            token: token,
            push: false,
            onProgress: session.syncConsole.add,
          );
        }
        await clone.push(token: token, onProgress: session.syncConsole.add);
        result[box.repo.id] =
            box.ahead + (commitPending && box.pending.isNotEmpty ? 1 : 0);
      } catch (thrown) {
        result[box.repo.id] = thrown;
        session.syncConsole.add('--- FAIL $thrown');
      }
      session.syncConsole.finishStep();
    }

    // Lo mismo que al traer: el registro se queda hasta que la aplicación
    // ha terminado de enterarse, y no solo hasta que git ha terminado.
    // Lo que no se pudo enviar al guardar ya ha salido: el aviso sobra.
    for (final entry in result.entries) {
      if (entry.value is int && _driftProblem[entry.key] is UnsentException) {
        _driftProblem.remove(entry.key);
      }
    }

    session.syncConsole.startStep(tr('volviendo a mirar los repositorios'));
    forgetFreshness();
    await session.refreshAccess();
    session.syncConsole.finish(ok: result.values.every((each) => each is int));
    return result;
  }
}
