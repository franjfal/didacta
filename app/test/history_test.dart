/// La pila de «atrás» y «adelante».
///
/// Existe porque la aplicación navega con `go` y no con `push`: cada pantalla
/// tiene su URL y entrar en una unidad **sustituye** la pantalla en lugar de
/// apilarla, que es lo que hace que un enlace pegado en un mensaje abra donde
/// debe. El precio era que volver atrás obligaba a pulsar el carril, que te
/// lleva a la raíz de la sección y se lleva por delante lo que llevabas
/// navegado.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/state/history.dart';

void main() {
  test('al principio no hay a dónde volver', () {
    final history = NavigationHistory()..record('/');
    expect(history.canGoBack, isFalse);
    expect(history.canGoForward, isFalse);
    expect(history.back(), isNull);
  });

  test('volver lleva a lo anterior, no a la raíz de la sección', () {
    // El caso del que vino todo esto: biblioteca, categoría, unidad; y desde
    // la unidad, atrás tiene que devolver a la categoría.
    final history = NavigationHistory()
      ..record('/')
      ..record('/courses')
      ..record('/courses/am-iii/2025-2026')
      ..record('/courses/am-iii/2025-2026/tema-1');

    expect(history.back(), '/courses/am-iii/2025-2026');
    history.record('/courses/am-iii/2025-2026');
    expect(history.back(), '/courses');
    history.record('/courses');
    expect(history.back(), '/');
  });

  test('adelante rehace lo deshecho', () {
    final history = NavigationHistory()
      ..record('/')
      ..record('/courses');

    expect(history.back(), '/');
    history.record('/');
    expect(history.canGoForward, isTrue);
    expect(history.forward(), '/courses');
    history.record('/courses');
    expect(history.canGoForward, isFalse);
  });

  test('ir a un sitio nuevo después de volver vacía «adelante»', () {
    // Es lo que hace un navegador, y lo que la gente espera: la rama que se
    // abandona no se guarda.
    final history = NavigationHistory()
      ..record('/')
      ..record('/courses');
    history.back();
    history.record('/');
    expect(history.canGoForward, isTrue);

    history.record('/settings');
    expect(history.canGoForward, isFalse);
    expect(history.back(), '/');
  });

  test('la misma dirección dos veces no cuenta dos veces', () {
    // La pantalla anota en cada fotograma, así que esto no es un caso raro:
    // sin esto, «atrás» devolvería al mismo sitio en el que ya se está.
    final history = NavigationHistory()
      ..record('/')
      ..record('/courses')
      ..record('/courses')
      ..record('/courses');
    expect(history.backStack, ['/']);
  });

  test('volver no se anota como visita nueva', () {
    // El fallo que esto evita: si al volver se anotara, «atrás» dejaría de
    // avanzar y el botón se quedaría dando vueltas entre dos páginas.
    final history = NavigationHistory()
      ..record('/')
      ..record('/courses')
      ..record('/settings');

    history.back();
    history.record('/courses');
    expect(history.backStack, ['/']);
    expect(history.forwardStack, ['/settings']);
  });

  test('la pila tiene tope', () {
    final history = NavigationHistory();
    for (var i = 0; i <= NavigationHistory.limit + 20; i += 1) {
      history.record('/sitio/$i');
    }
    expect(history.backStack, hasLength(NavigationHistory.limit));
    // Y lo que se tira es lo más viejo.
    expect(history.backStack.first, isNot('/sitio/0'));
  });

  test('avisa cuando cambia, que es lo que enciende el botón', () {
    var avisos = 0;
    final history = NavigationHistory()..addListener(() => avisos += 1);
    history.record('/');
    history.record('/courses');
    expect(avisos, 2);
    history.record('/courses');
    expect(avisos, 2, reason: 'la misma dirección no es un cambio');
    history.back();
    expect(avisos, 3);
  });
}
