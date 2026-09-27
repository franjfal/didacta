/// Lo que cada cual decide sobre cómo mirar el material: qué está marcado, qué
/// oculto, qué plegado, qué idiomas se ofrecen y qué repositorios se miran.
///
/// Es de la persona y no de la máquina, así que viaja: se guarda aquí al
/// instante y, si se ha elegido un repositorio para ello, en él unos segundos
/// después --plegar tres temas seguidos son tres clics y **un** commit--. Ver
/// `model/synced_prefs.dart` para qué lleva dentro.
///
/// Era una parte de la sesión. Aparte porque no depende de nada de lo demás
/// --ni del catálogo ni del motor--, solo de las preferencias locales, de una
/// pasarela para escribir y de saber quién ha entrado. La sesión la sigue
/// ofreciendo con los mismos nombres, así que las pantallas no cambian.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/content_gateway.dart';
import '../data/diagnostics.dart';
import '../data/preferences.dart';
import '../model/saved_search.dart';
import '../model/synced_prefs.dart';
import '../l10n/tr.dart';

class LibraryPrefs extends ChangeNotifier {
  LibraryPrefs({
    required this.preferences,
    required this.gatewayFor,
    required this.login,
  });

  final Preferences preferences;

  /// Con qué se escribe en un repositorio.
  final ContentGateway Function(String repo) gatewayFor;

  /// Quién ha entrado en GitHub, que es lo que da nombre al fichero.
  final String? Function() login;

  SyncedPrefs _synced = const SyncedPrefs();

  /// Tal como están ahora mismo.
  SyncedPrefs get synced => _synced;

  String? _repo;

  /// En qué repositorio se guardan. Null es «en ninguno»: se quedan aquí.
  String? get repo => _repo;

  /// Dónde se escriben dentro de ese repositorio.
  ///
  /// Con el login de GitHub en el nombre, que es lo que permite que un
  /// departamento comparta repositorio sin pisarse: cada uno escribe el suyo
  /// y nadie lee el de otro.
  String? get path {
    final who = login() ?? '';
    if (who.isEmpty) return null;
    return '.didacta/prefs/$who.json';
  }

  Timer? _write;

  /// Lo de esta máquina, al arrancar.
  Future<void> restore() async {
    _repo = await preferences.prefsRepo();
    _synced = SyncedPrefs.fromJson(await preferences.syncedPrefs() ?? '');
    await restoreLocal();
  }

  /// Solo lo que no viaja: lo reciente y las búsquedas.
  Future<void> restoreLocal() async {
    _recent = await preferences.recentUnits();
    _searches = SavedSearch.listFromJson(await preferences.savedSearches());
  }

  // -- lo reciente y las búsquedas guardadas --------------------------------
  //
  // De esta máquina y no de las que viajan: lo que se abrió esta tarde y las
  // búsquedas de quien trabaja aquí.

  List<String> _recent = const [];

  /// Cuántas lecciones recientes se recuerdan: las de una tarde de trabajo.
  static const int recentLimit = 8;

  /// Las últimas lecciones abiertas, como `repositorio|ruta`, la más reciente
  /// primero.
  List<String> get recent => _recent;

  /// Apunta que se ha abierto la lección [key].
  ///
  /// Sin avisar a nadie: se llama al abrir la pantalla de la lección, y lo
  /// que lo enseña --la biblioteca-- se vuelve a pintar al volver a ella.
  void noteOpened(String key) {
    if (_recent.isNotEmpty && _recent.first == key) return;
    _recent = [
      key,
      for (final other in _recent)
        if (other != key) other,
    ].take(recentLimit).toList();
    unawaited(preferences.setRecentUnits(_recent));
  }

  List<SavedSearch> _searches = const [];

  List<SavedSearch> get savedSearches => _searches;

  /// Guarda [url] --una dirección de la biblioteca-- con [name]. Si ya había
  /// una con esa dirección, se renombra.
  Future<void> saveSearch(String name, String url) async {
    _searches = [
      for (final search in _searches)
        if (search.url != url) search,
      SavedSearch(name: name, url: url),
    ];
    notifyListeners();
    await preferences.setSavedSearches(SavedSearch.listToJson(_searches));
  }

  Future<void> forgetSearch(String url) async {
    _searches = [
      for (final search in _searches)
        if (search.url != url) search,
    ];
    notifyListeners();
    await preferences.setSavedSearches(SavedSearch.listToJson(_searches));
  }

  /// Cambia algo: aquí y en la pantalla ya, y en el repositorio después.
  ///
  /// [then] va entre el cambio y el aviso, para lo que tiene que quedar al
  /// día antes de que nadie lo mire --si se apaga el idioma que se estaba
  /// mirando, pasar a otro--.
  Future<void> change(
    SyncedPrefs Function(SyncedPrefs prefs) edit, {
    VoidCallback? then,
  }) async {
    _synced = edit(_synced);
    then?.call();
    notifyListeners();
    await _remember();
  }

  /// Elige el repositorio donde se sincronizan, o quita el que hubiera.
  Future<void> setRepo(String? repo) async {
    if (_repo == repo) return;
    _repo = repo;
    await preferences.setPrefsRepo(repo);
    notifyListeners();
    if (repo != null) await load();
  }

  /// Guarda en esta máquina ya, y en el repositorio dentro de un rato.
  ///
  /// Lo segundo con espera a propósito: escribir un commit por clic
  /// llenaría el historial del material de ruido, que es el motivo por el que
  /// alguien decidiría no usar esto.
  Future<void> _remember() async {
    await preferences.setSyncedPrefs(_synced.toJson());
    if (_repo == null) return;
    _write?.cancel();
    _write = Timer(const Duration(seconds: 5), () {
      unawaited(push());
    });
  }

  /// Lee las del repositorio elegido, si hay alguno.
  ///
  /// Silencioso cuando falla. Es lo correcto aquí: no poder leer unas
  /// preferencias deja los paneles como estaban, y una aplicación que no abre
  /// porque no encuentra un fichero de ajustes es peor que una que abre con
  /// los de por defecto.
  Future<void> load() async {
    final repo = _repo;
    final path = this.path;
    if (repo == null || path == null) return;
    try {
      final file = await gatewayFor(repo).read(path);
      _synced = SyncedPrefs.fromJson(file.text);
      await preferences.setSyncedPrefs(_synced.toJson());
      notifyListeners();
    } catch (caught, trace) {
      Diagnostics.instance.note('library_prefs.load', caught, trace);
      // Todavía no existe, o no se puede leer. Se queda lo local.
    }
  }

  /// Las escribe en el repositorio elegido, como un commit.
  Future<void> push() async {
    final repo = _repo;
    final path = this.path;
    if (repo == null || path == null) return;
    final text = _synced.toJson();
    try {
      final gateway = gatewayFor(repo);
      var sha = '';
      try {
        final existing = await gateway.read(path);
        if (existing.text == text) return;
        sha = existing.sha;
      } catch (caught, trace) {
        Diagnostics.instance.note('library_prefs.push', caught, trace);
        // No estaba: se crea.
      }
      await gateway.save(
        path: path,
        text: text,
        sha: sha,
        message: tr('Preferencias de {0}', [login() ?? tr('quien edita')]),
      );
    } catch (caught, trace) {
      Diagnostics.instance.note('library_prefs.push', caught, trace);
      // Sin red, sin permiso o con un conflicto: lo local sigue valiendo y
      // el próximo cambio lo vuelve a intentar.
    }
  }

  @override
  void dispose() {
    _write?.cancel();
    super.dispose();
  }
}
