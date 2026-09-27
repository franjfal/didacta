/// El arranque: leer lo guardado, comprobar la sesión, leer el catálogo y,
/// después de pintar, abrir los repositorios y poner el índice al día.
///
/// Era una parte de la sesión. Aparte porque es una secuencia que se hace una
/// vez, con su propio estado --qué paso va, si las preferencias no se
/// pudieron leer, si la bienvenida ya se vio-- y que toca a todas las demás
/// piezas en un orden que importa. Aquí está ese orden, y el porqué de cada
/// paso, en un solo sitio.
///
/// Qué paso va solo le importa a la pantalla de carga, y se avisa aquí; que
/// ha terminado, o que ha fallado, avisa por la sesión.
library;

import 'package:flutter/foundation.dart';

import '../data/diagnostics.dart';
import '../data/local_clone.dart';
import '../model/catalogue.dart';
import '../model/workspace.dart';
import 'session.dart';
import '../l10n/tr.dart';

class Startup extends ChangeNotifier {
  Startup(this.session, {required this.onChanged});

  final Session session;

  /// Avisar a la sesión: ha cambiado lo que se enseña.
  final VoidCallback onChanged;

  /// Qué está haciendo el arranque, para la pantalla de carga. Null fuera
  /// de él.
  String? get step => _step;
  String? _step;

  void _at(String? what) {
    _step = what;
    notifyListeners();
    onChanged();
  }

  Object? _settingsProblem;

  /// Por qué no se pudieron leer los ajustes guardados, si no se pudieron.
  Object? get settingsProblem => _settingsProblem;

  /// Si la presentación de bienvenida ya se ha visto.
  ///
  /// `null` mientras no se ha leído, y eso no es lo mismo que `false`: la
  /// bienvenida se enseña **en lugar de** la aplicación, así que mientras no
  /// se sabe lo que toca es la pantalla de carga. Sin esa distinción, cada
  /// arranque enseñaría la bienvenida durante un parpadeo.
  bool? _welcomeDone;
  bool? get welcomeDone => _welcomeDone;

  /// La bienvenida se ha terminado --o se ha saltado--, y no vuelve.
  Future<void> completeWelcome() async {
    _welcomeDone = true;
    await session.preferences.setWelcomeDone(true);
    onChanged();
  }

  /// Volver a enseñarla. Es lo que hace el botón de Ajustes.
  Future<void> replayWelcome() async {
    _welcomeDone = false;
    await session.preferences.setWelcomeDone(false);
    onChanged();
  }

  /// Levanta el catálogo y averigua cómo se llega al contenido.
  ///
  /// **Solo el catálogo puede pararlo.** Todo lo demás -- una preferencia
  /// guardada, el llavero, un clon, GitHub -- puede fallar, y cada fallo se
  /// apunta y se enseña en lugar de lanzarse. No es defensivo: esto se llama
  /// desde `initState` sin `await`, así que lo que se escape es un error
  /// asíncrono sin manejar, y uno antes del primer fotograma es una ventana
  /// negra con el motivo en un registro que nadie lee. Ha pasado dos veces.
  Future<void> run() async {
    final store = session.catalogueStore;
    store.loading();
    _at(tr('Leyendo tus preferencias'));

    // The clone is looked up first because it changes where the catalogue is
    // read from: inside a clone, the index on disk is the one that matches
    // the files the editor writes, and fetching a different copy over HTTP
    // would let the library disagree with the editor.
    try {
      await session.repositories.restore();
      await session.settings.restore();
      await session.engine.restore();
      // La copia local primero: es la que hace que los temas abran plegados
      // sin esperar al repositorio, y la que vale cuando no hay ninguno.
      await session.libraryPrefs.restore();
      session.noteHiddenRepos();
      _welcomeDone = await session.preferences.welcomeDone();
      store.refilter();
    } catch (error) {
      // A setting that cannot be read is a setting that is not set.
      session.repositories.workspace = const Workspace.empty();
      _settingsProblem = error;
    }

    // La sesión, antes que el catálogo y antes de pintar.
    //
    // Va aquí y no en `refreshAccess`, que es donde estaba, porque ahora
    // decide **si hay aplicación**: sin sesión no se abre nada, así que la
    // primera pantalla depende de esto y no puede pintarse sin ello. Y porque
    // un catálogo que no carga sale por una rama que nunca llegaba a
    // `refreshAccess`, y habría dejado la pantalla de carga para siempre.
    _at(tr('Comprobando la sesión'));
    final auth = session.auth;
    auth.token = await auth.readToken();
    await auth.resolve();

    _at(tr('Leyendo el catálogo'));
    try {
      store.loaded(await store.source.load());
      session.languages.resetTo(store.full!);
    } catch (error) {
      // Sin repositorios abiertos, que no se pueda leer un catálogo **no es
      // un error**: es una instalación recién puesta y todavía no se le ha
      // dicho con qué trabajar. Antes caía en el catálogo por HTTP que traía
      // la compilación, que en escritorio no resuelve, y la primera pantalla
      // era «No se pudo cargar el catálogo» con una dirección relativa y un
      // botón que ya no llevaba a ninguna parte.
      if (session.openedWorkspace.isEmpty && LocalClone.supported) {
        store.loaded(Catalogue.merge(const []));
        session.languages.resetTo(store.full!);
        onChanged();
        return;
      }
      // El motor, también aquí: es lo que regenera el índice, y la pantalla
      // de fallo lo ofrece con un botón en lugar de mandar al terminal.
      if (session.compiler() == null) {
        try {
          await session.engine.find();
        } catch (caught, trace) {
          Diagnostics.instance.note('session.start', caught, trace);
          // Sin motor queda el consejo de siempre.
        }
      }
      store.failed(error);
      onChanged();
      return;
    }

    // Painted before access is resolved. The library needs none of what
    // follows, and making the reader wait for a keychain -- or lose the
    // screen to it -- is the wrong trade.
    _at(null);

    // Y ahora los repositorios: mirar el estado de cada clon, quién ha
    // entrado y dónde está el motor. Después de pintar a propósito, que es
    // hablar con git y con la red.
    await session.refreshAccess();

    // El índice, después de pintar.
    //
    // Es un fichero generado que describe el disco, y el disco cambia entre
    // arranques: mover `content/` a otro sitio deja un índice que habla de
    // dos mil unidades que ya no están, y la biblioteca las enseñaba tan
    // contenta. Preguntar cuesta una décima --el motor cuenta ficheros, no
    // los abre-- y solo se regenera cuando hace falta.
    //
    // Después y no antes a propósito: buscar el motor y hablar con él es
    // lanzar procesos, y ponerlo delante de la primera pantalla haría que un
    // motor lento o ausente retrasara el arranque entero. Así la biblioteca
    // aparece con lo que había y se corrige sola un segundo después, con el
    // aviso diciendo qué ha cambiado.
    if (await session.refreshIndex()) await session.reloadCatalogue();
  }
}
