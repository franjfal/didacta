/// Por dónde se ha pasado, para poder volver.
///
/// Hace falta porque esta aplicación navega con `go` y no con `push`: cada
/// pantalla tiene una URL propia y entrar en una unidad desde la biblioteca
/// **sustituye** la pantalla en lugar de apilarla, que es lo correcto para
/// que un enlace pegado en un mensaje abra donde debe. El precio es que no
/// hay pila de navegación que deshacer, y volver atrás obligaba a pulsar el
/// carril de la izquierda, que te lleva a la raíz de la sección y se lleva
/// por delante todo lo que llevabas navegado.
///
/// Así que la pila se lleva aparte. Dos listas y la dirección actual, que es
/// lo que hace un navegador: al ir a un sitio nuevo, lo de antes va a
/// «atrás» y «adelante» se vacía; al volver, se mueve una de una lista a la
/// otra. Lo único que no es obvio es el `_navigating`, que evita que volver
/// atrás se grabe como una visita nueva y deje el botón sin efecto.
library;

import 'package:flutter/foundation.dart';

class NavigationHistory extends ChangeNotifier {
  /// Cuántos sitios se recuerdan. Cien son más de los que nadie deshace, y
  /// evita que una sesión larga se lleve memoria por nada.
  static const int limit = 100;

  final List<String> _back = [];
  final List<String> _forward = [];
  String? _current;
  bool _navigating = false;

  String? get current => _current;
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  /// A dónde volvería «atrás», para poder decirlo en el tooltip.
  String? get previous => _back.isEmpty ? null : _back.last;
  String? get next => _forward.isEmpty ? null : _forward.last;

  @visibleForTesting
  List<String> get backStack => List.unmodifiable(_back);

  @visibleForTesting
  List<String> get forwardStack => List.unmodifiable(_forward);

  /// Anota dónde estamos.
  void record(String location) {
    if (location == _current) return;
    if (_navigating) {
      // Llega del botón: los movimientos de pila ya se hicieron.
      _navigating = false;
      _current = location;
      notifyListeners();
      return;
    }
    if (_current != null) {
      _back.add(_current!);
      if (_back.length > limit) _back.removeAt(0);
    }
    _current = location;
    _forward.clear();
    notifyListeners();
  }

  /// A dónde ir al pulsar «atrás», o null si no hay a dónde.
  String? back() {
    if (_back.isEmpty) return null;
    final target = _back.removeLast();
    if (_current != null) _forward.add(_current!);
    _navigating = true;
    notifyListeners();
    return target;
  }

  String? forward() {
    if (_forward.isEmpty) return null;
    final target = _forward.removeLast();
    if (_current != null) _back.add(_current!);
    _navigating = true;
    notifyListeners();
    return target;
  }
}
