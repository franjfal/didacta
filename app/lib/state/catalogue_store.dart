/// El catálogo: leerlo, saber si el índice sigue describiendo el disco y
/// enterarse cuando cambia.
///
/// Era una parte de la sesión. Aparte porque tiene su propio estado --lo
/// leído, cuándo se leyó el índice de cada clon, qué se vigila, la recarga en
/// curso-- y de la sesión solo necesita los repositorios abiertos y el motor.
/// Lo que se está mirando --con una versión congelada abierta, el catálogo de
/// aquel commit-- lo sigue decidiendo la sesión, que lo ofrece con los mismos
/// nombres.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/catalogue_source.dart';
import '../data/diagnostics.dart';
import '../data/disk_watch.dart';
import '../data/template_store.dart';
import '../model/catalogue.dart';
import 'catalogue_editor.dart';
import 'session.dart';
import '../l10n/tr.dart';

class CatalogueStore {
  CatalogueStore(this.session, {required this.onChanged});

  final Session session;

  /// Avisar a quien mira: la sesión, que avisa a las pantallas.
  final VoidCallback onChanged;

  /// Lo leído al arrancar, o lo que da una prueba: ya hay aplicación.
  void loaded(Catalogue catalogue) {
    _catalogue = catalogue;
    refilter();
    _state = LoadState.ready;
  }

  /// No se ha podido leer, y no hay aplicación sin catálogo.
  void failed(Object error) {
    _error = error;
    _state = LoadState.failed;
  }

  /// Otra vez desde el principio.
  void loading() => _state = LoadState.loading;

  LoadState _state = LoadState.loading;
  LoadState get state => _state;

  Object? _error;
  Object? get error => _error;

  Catalogue? _catalogue;

  /// El catálogo entero, apagados incluidos, tal como se leyó.
  Catalogue? get full => _catalogue;

  /// Sin los repositorios apagados y con las plantillas del programa.
  Catalogue? get visible => _visible;

  Catalogue? _visible;

  /// La carpeta de plantillas del programa, cuando la hay.
  ///
  /// Null en la web y hasta que se abre. Quien guarde algo ahí no lo tiene en
  /// ningún repositorio, así que no lo protege git ni lo ve nadie más: ver
  /// [TemplateStore].
  TemplateStore? get templateStore => _templateStore;
  TemplateStore? _templateStore;

  /// Lo que esa carpeta declara, leído por el motor.
  ///
  /// Se junta con el catálogo en [refilter], así que todo lo demás --qué
  /// ofrece un bloque, qué compila un tema-- las ve como cualquier otra.
  List<OutputTemplate> _storedTemplates = const [];

  /// Abre la carpeta del programa y lee lo que tenga.
  ///
  /// Silencioso si algo va mal: no poder leer las plantillas propias no puede
  /// impedir abrir la aplicación, y lo que se pierde es una lista, no el
  /// material.
  Future<void> loadStoredTemplates() async {
    try {
      _templateStore ??= await TemplateStore.open();
    } catch (caught, trace) {
      Diagnostics.instance.note('session.loadStoredTemplates', caught, trace);
      // Sin carpeta de datos --una plataforma que no la da, o una prueba sin
      // canales de plataforma-- no hay plantillas propias, y eso no puede
      // impedir leer el catálogo.
      return;
    }
    final store = _templateStore;
    if (store == null || !await store.hasAny) {
      if (_storedTemplates.isEmpty) return;
      _storedTemplates = const [];
      refilter();
      onChanged();
      return;
    }
    try {
      final compiler = session.liveCompiler();
      if (compiler == null) return;
      _storedTemplates = [
        for (final template in await compiler.templatesIn(store.directory))
          template.declaredBy(CatalogueEditor.programTemplates),
      ];
    } catch (caught, trace) {
      Diagnostics.instance.note('session.loadStoredTemplates', caught, trace);
      _storedTemplates = const [];
    }
    refilter();
    onChanged();
  }

  void refilter() {
    // Las del programa se añaden al final y solo si su id no está ya: un
    // repositorio que declare el mismo id gana, porque lo compartido manda
    // sobre lo personal.
    _visible = _catalogue
        ?.without(session.libraryPrefs.synced.hiddenRepos)
        .withTemplates(_storedTemplates);
  }

  /// Cuándo se escribió el índice que está cargado, por repositorio.
  ///
  /// Es lo que permite saber que el de disco es otro: la comprobación de
  /// arranque compara el índice con el contenido, y eso no ve que el índice
  /// haya cambiado **después** de leerlo --que es lo que pasa cuando alguien
  /// lo regenera desde el terminal con la aplicación abierta--.
  ///
  /// Uno por clon, y no uno solo: con dos repositorios abiertos, mirar el del
  /// primero deja al segundo enseñando lo que leyó al abrirse. Que no haya
  /// entrada para un clon significa que cuando se miró no tenía índice, y por
  /// eso encontrarlo ahora **es** un cambio.
  final Map<String, DateTime> _indexRead = {};

  final List<StreamSubscription<void>> _watching = [];
  final List<StreamSubscription<void>> _watchingContent = [];
  Timer? _settle;
  Timer? _settleContent;

  /// Los clones que se vigilan: todos los del espacio de trabajo.
  List<String> get _watchedPaths => session.repoPaths;

  /// Empieza a vigilar `generated/` de cada clon.
  ///
  /// Uno por repositorio abierto: vigilar solo el primero dejaba al segundo
  /// sin enterarse de nada --ni de un `.tex` editado por fuera, ni de un
  /// `didacta index` desde el terminal-- hasta reiniciar.
  ///
  /// Idempotente: llamarlo dos veces no deja dos vigilantes. Y se vuelve a
  /// llamar después de cada recarga, porque un clon al que le acaba de
  /// aparecer `generated/` necesita que se le monte el vigilante de verdad.
  void watchDisk() {
    for (final subscription in [..._watching, ..._watchingContent]) {
      unawaited(subscription.cancel());
    }
    _watching.clear();
    _watchingContent.clear();

    for (final path in _watchedPaths) {
      // El material. Editar un `.tex` en otro programa, copiar una figura o
      // traerse cien ficheros con un `git pull` son la misma cosa desde aquí:
      // el disco ya no es lo que el índice dice. Con más respiro que el
      // índice --un `pull` son cientos de eventos seguidos-- y sin forzar
      // nada: se pregunta si hace falta, que cuesta una décima, y solo se
      // regenera si la respuesta es que sí.
      _watchingContent.add(
        watchContent(path).listen((_) {
          _settleContent?.cancel();
          _settleContent = Timer(const Duration(seconds: 2), () {
            unawaited(_rescan());
          });
        }),
      );

      _watching.add(
        watchIndex(path).listen((_) {
          // Con un respiro: el motor escribe cuatro ficheros, y recargar el
          // catálogo cuatro veces por una regeneración es tirar el trabajo
          // tres veces.
          _settle?.cancel();
          _settle = Timer(const Duration(milliseconds: 400), () {
            unawaited(_reloadIfIndexChanged());
          });
        }),
      );
    }
  }

  /// Vuelve a mirar el disco: si el índice se ha quedado corto, lo regenera.
  Future<void> _rescan() async {
    if (await refreshIndex()) {
      await session.reloadCatalogue();
      await session.refreshBuilt();
      await rememberIndexDates();
      watchDisk();
    }
  }

  /// Al volver a la ventana: ¿ha cambiado algo mientras no mirábamos?
  ///
  /// Dos `stat` y, si el índice está viejo respecto al contenido, una
  /// regeneración. Es el momento exacto en que alguien vuelve después de
  /// tocar ficheros por fuera.
  Future<void> checkDisk() async {
    if (await _reloadIfIndexChanged()) {
      watchDisk();
      return;
    }
    if (await refreshIndex()) {
      await session.reloadCatalogue();
    } else if (_catalogue?.errors.isNotEmpty ?? false) {
      // Un repositorio que no cargó deja su queja en el catálogo, y esa queja
      // se queda en pantalla aunque el motivo desaparezca: el caso de siempre
      // es un clon recién añadido al que todavía no le habían pasado
      // `didacta index`. Volver a leer cuesta cuatro ficheros.
      await session.reloadCatalogue();
    }

    // Desde aquí, el disco avisa solo.
    if (_watchedPaths.isNotEmpty) {
      await rememberIndexDates();
      watchDisk();
    }
  }

  /// Relee el catálogo si el índice de algún clon es más nuevo que el leído.
  Future<bool> _reloadIfIndexChanged() async {
    var changed = false;
    for (final path in _watchedPaths) {
      final when = await indexModified(path);
      if (when == null) continue;
      final last = _indexRead[path];
      // Sin entrada: cuando se miró no había índice y ahora sí. Es
      // exactamente lo que pasa con un repositorio recién añadido.
      if (last != null && !when.isAfter(last)) continue;
      _indexRead[path] = when;
      changed = true;
    }
    if (!changed) return false;
    await session.reloadCatalogue();
    await session.refreshBuilt();
    return true;
  }

  /// Apunta la fecha del índice de cada clon, que es contra lo que se compara.
  Future<void> rememberIndexDates() async {
    for (final path in _watchedPaths) {
      final when = await indexModified(path);
      if (when != null) _indexRead[path] = when;
    }
  }

  /// Lo que pasó con el índice la última vez que se miró.
  ///
  /// Null cuando no había nada que decir. Se enseña porque regenerarlo
  /// cambia lo que la biblioteca lista, y un cambio así no puede ocurrir en
  /// silencio: quien acaba de mover una carpeta tiene que ver que la
  /// aplicación se ha enterado.
  String? get indexNote => _indexNote;
  String? _indexNote;

  void dismissIndexNote() {
    _indexNote = null;
    onChanged();
  }

  /// Si el índice sigue describiendo el disco; si no, lo regenera.
  ///
  /// [force] lo regenera igual, que es lo que hace el botón de actualizar:
  /// pedirlo a mano significa «ponlo como está el disco», no «mira a ver».
  ///
  /// [only] lo limita a un repositorio, que es lo que hace falta después de
  /// tocar su `didacta.yaml`: regenerar los de al lado cuesta segundos y no
  /// cambia nada de ellos.
  ///
  /// Devuelve si lo regeneró, que es cuando hay que volver a leerlo.
  ///
  /// Con [skipFresh], los repositorios cuyo índice se acaba de comprobar
  /// --en los últimos segundos, y sin que se haya escrito nada después-- no
  /// se vuelven a mirar. Con [quiet], no avisa a la pantalla: quien llama
  /// va a recargar, y avisar dos veces es redibujar dos veces.
  Future<bool> refreshIndex({
    bool force = false,
    String? only,
    bool skipFresh = false,
    bool quiet = false,
  }) async {
    var any = false;
    for (final repo in session.openedWorkspace.repos) {
      if (only != null && repo.id != only) continue;
      if (skipFresh && !force && _consumeFresh(repo.id)) continue;
      if (await _refreshIndexOf(repo.id, force: force, quiet: quiet)) {
        any = true;
      }
    }
    if (session.openedWorkspace.isEmpty) {
      if (skipFresh && !force && _consumeFresh(null)) return false;
      return _refreshIndexOf(null, force: force, quiet: quiet);
    }
    return any;
  }

  /// Los repositorios cuyo índice se sabe al día, y desde cuándo.
  ///
  /// Se apunta al comprobarlo o regenerarlo --aquí, o el motor al final de
  /// una operación--, se borra antes de escribir cualquier cosa en ese
  /// repositorio y caduca a los pocos segundos: es para no repetir la
  /// comprobación que se acaba de hacer, no para fiarse de ella más tarde.
  final Map<String?, DateTime> _indexFresh = {};

  void markIndexFresh(String? repo) => _indexFresh[repo] = DateTime.now();

  void forgetIndexFresh(String? repo) => _indexFresh.remove(repo);

  bool _consumeFresh(String? repo) {
    final at = _indexFresh.remove(repo);
    return at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 10);
  }

  /// El índice de un repositorio. Cada uno tiene el suyo, escrito por el
  /// motor en su carpeta, y se comprueba por separado.
  Future<bool> _refreshIndexOf(
    String? repo, {
    bool force = false,
    bool quiet = false,
  }) async {
    final compiler = session.liveCompiler(repo: repo);
    if (compiler == null) return false;
    try {
      final why = force
          ? (stale: true, reason: tr('a mano'))
          : await compiler.indexStale();
      if (!why.stale) {
        markIndexFresh(repo);
        return false;
      }
      await compiler.reindex();
      markIndexFresh(repo);
      _indexNote = force
          ? tr('Índice actualizado.')
          : tr(
              'El índice no describía lo que hay en el disco '
              '({0}), así que se ha regenerado.',
              [why.reason],
            );
      if (!quiet) onChanged();
      return true;
    } catch (error) {
      // No poder regenerarlo no puede impedir arrancar: se lee el que hay y
      // se dice que puede no corresponder.
      _indexNote = tr(
        'El índice puede estar desactualizado y no se ha podido '
        'regenerar: {0}',
        [error],
      );
      if (!quiet) onChanged();
      return false;
    }
  }

  /// Where the catalogue is actually read from: the clone if there is one,
  /// otherwise whatever the app was built with.
  CatalogueSource get source {
    if (session.openedWorkspace.isEmpty) return session.catalogueSource;
    final parts = <CatalogueSource>[
      for (final repo in session.openedWorkspace.repos)
        ?CatalogueSource.inClone(repo.directory, repo: repo.id),
    ];
    if (parts.isEmpty) return session.catalogueSource;
    return parts.length == 1 ? parts.single : CatalogueSource.merged(parts);
  }

  /// For the interface, which has to be able to say where it read from.
  String get catalogueOrigin => source.describe;

  /// La recarga en curso, si hay una, y si se pidió otra mientras duraba.
  ///
  /// Una sola a la vez. Un guardado disparaba varias seguidas --la pantalla,
  /// la vigilancia del disco, el que llamó-- y cada una lanzaba el motor y
  /// leía un índice de dos megas. Ahora las que llegan mientras hay una en
  /// marcha esperan a esa, y si alguna llegó después de empezar se hace una
  /// más al final: nadie se queda con un catálogo de antes de su cambio.
  Future<void>? _reloading;
  bool _reloadAgain = false;

  /// Reloads the catalogue, for after a commit that changed structure.
  Future<void> reloadCatalogue() {
    final running = _reloading;
    if (running != null) {
      _reloadAgain = true;
      return running;
    }
    final started = () async {
      do {
        _reloadAgain = false;
        await _reloadOnce();
      } while (_reloadAgain);
    }();
    _reloading = started.whenComplete(() => _reloading = null);
    return _reloading!;
  }

  Future<void> _reloadOnce() async {
    try {
      // Regenerar el índice si hace falta, **antes** de leerlo.
      //
      // Lo que la aplicación escribe son ficheros YAML --`degrees.yaml`,
      // `themes.yaml`, `year.yaml`, `unit.yaml`-- y lo que lee son los
      // índices que el motor saca de ellos. Sin esto, guardar el título de un
      // grado escribía el fichero, decía que lo había guardado y la pantalla
      // seguía enseñando el de antes: el cambio estaba en el disco y el
      // índice era de hace un minuto.
      //
      // Aquí y no en cada método que escribe, que son veinte y basta con
      // olvidarse de uno para que vuelva el mismo fallo en otro sitio. La
      // comprobación es barata --contar ficheros y mirar fechas-- y solo
      // regenera cuando de verdad hace falta. Y no se repite en un
      // repositorio cuyo índice se acaba de comprobar o de regenerar --una
      // operación del motor lo deja hecho--: es un proceso por repositorio
      // que no diría nada nuevo.
      await refreshIndex(skipFresh: true, quiet: true);
      _catalogue = await source.load();
      refilter();
      onChanged();
      // Las del programa, después: son una llamada al motor y no pueden
      // retrasar lo que la pantalla ya puede enseñar.
      unawaited(loadStoredTemplates());
    } catch (error) {
      // Deliberately not fatal: the old catalogue is stale, not wrong, and
      // throwing away a working screen because a refresh failed is worse.
      _error = error;
      onChanged();
    }
  }

  void dispose() {
    _settle?.cancel();
    _settleContent?.cancel();
    for (final subscription in [..._watching, ..._watchingContent]) {
      unawaited(subscription.cancel());
    }
  }
}
