/// Las versiones congeladas: abrir una, volver a la de hoy y la caché de sus
/// árboles.
///
/// Era una parte de la sesión. Aparte porque tiene su propio estado --la
/// congelación abierta y cómo va la apertura-- y de la sesión solo necesita
/// el clon y el compilador de cada repositorio, que pide por `session.`
/// porque son los que las pruebas sustituyen.
///
/// Abrir o cerrar una congelación cambia **qué se está mirando**: el
/// catálogo, las pasarelas, lo compilado. Eso avisa por la sesión, porque lo
/// enseñan todas las pantallas. Cómo va la apertura --«buscando», «copiando
/// el árbol»-- solo le interesa al diálogo que lo cuenta, y se avisa aquí.
library;

import 'package:flutter/foundation.dart';

import '../data/diagnostics.dart';
import '../data/frozen.dart';
import '../model/catalogue.dart';
import 'session.dart';
import '../l10n/tr.dart';

class FreezeService extends ChangeNotifier {
  FreezeService(this.session, {required this.onChanged});

  final Session session;

  /// Avisar a la sesión de que ha cambiado lo que se está mirando.
  final VoidCallback onChanged;

  FrozenView? _frozen;

  /// La congelación que se está mirando, o null si es la versión actual.
  FrozenView? get frozen => _frozen;

  bool get isFrozen => _frozen != null;

  /// Cómo va la apertura, para poder contarlo mientras dura.
  FrozenStep? _step;
  FrozenStep? get step => _step;

  void _setStep(FrozenStep? step) {
    _step = step;
    notifyListeners();
  }

  /// Lo que abre, compara y restaura, para un repositorio.
  Frozen? frozenIn(String? repo) {
    final clone = session.cloneFor(repo);
    if (clone == null) return null;
    return Frozen(
      clone: clone,
      repo: repo ?? session.openedWorkspace.repos.firstOrNull?.id ?? '',
      compiler: session.liveCompiler(repo: repo),
      token: session.auth.token ?? '',
    );
  }

  /// Abre una versión congelada. Ver [Session.openFreeze].
  Future<void> open(Freeze freeze, {String? repo}) async {
    final service = session.frozenIn(repo ?? freeze.repo);
    if (service == null) {
      throw FrozenException(
        tr(
          'Para abrir una versión congelada hace falta la copia del repositorio en tu ordenador.',
        ),
      );
    }
    _setStep(FrozenStep.looking);
    // La sesión también: el aviso de «abriendo» sale en el armazón.
    onChanged();
    try {
      _frozen = await service.open(freeze, onStep: _setStep);
    } finally {
      _setStep(null);
      onChanged();
    }
    session.builds.forget();
  }

  /// Para un test de pantalla: la congelación ya abierta.
  void useForTest(FrozenView? view) {
    _frozen = view;
    notifyListeners();
    onChanged();
  }

  /// Vuelve a la versión actual. Ver [Session.leaveFreeze].
  void leave() {
    if (_frozen == null) return;
    _frozen = null;
    session.builds.forget();
    notifyListeners();
    onChanged();
  }

  /// Vacía la caché de árboles de congelación. No pierde nada.
  Future<int> clearCache() async {
    var total = 0;
    for (final repo in session.openedWorkspace.repos) {
      final service = session.frozenIn(repo.id);
      if (service == null) continue;
      total += await service.clearCache();
    }
    if (_frozen != null) leave();
    return total;
  }

  /// Cuántos árboles de congelación hay guardados ahora mismo.
  Future<int> cacheSize() async {
    var total = 0;
    for (final repo in session.openedWorkspace.repos) {
      final clone = session.cloneFor(repo.id);
      if (clone == null) continue;
      total += (await clone.worktrees()).length;
    }
    return total;
  }

  /// Las congelaciones de un curso, las más nuevas primero.
  List<Freeze> freezesOf(String courseId, String year) {
    final entry = session.fullYear(courseId, year);
    if (entry == null) return const [];
    final found = [...entry.freezes];
    found.sort((a, b) => (b.created).compareTo(a.created));
    return found;
  }

  /// El commit que congelaría ahora mismo: el HEAD del repositorio.
  Future<String> headOf(String? repo) async {
    final clone = session.cloneFor(repo);
    if (clone == null) {
      throw FrozenException(
        tr(
          'Para congelar hace falta la copia del repositorio en tu ordenador.',
        ),
      );
    }
    return clone.head();
  }

  /// Si hay cambios sin guardar en el clon de un repositorio.
  ///
  /// Se pregunta antes de congelar y antes de restaurar: una congelación
  /// apunta a un commit, así que lo que esté sin confirmar **no entra**, y hay
  /// que decirlo antes y no después.
  Future<List<String>> pendingIn(String? repo) async {
    final clone = session.cloneFor(repo);
    if (clone == null) return const [];
    try {
      return (await clone.status()).dirtyPaths;
    } catch (caught, trace) {
      Diagnostics.instance.note('session.pendingIn', caught, trace);
      return const [];
    }
  }
}
