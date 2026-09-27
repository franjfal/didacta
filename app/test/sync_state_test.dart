/// Lo que dice la barra de abajo: cómo está lo tuyo, sin git.
///
/// Decía «Clon local en /Users/…, como Nombre `<correo>`, enviando cada
/// commit»: cierto, y nada de lo que se quiere saber de un vistazo.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

class _State extends FakeSession {
  _State({this.pending = 0, this.unsent = 0, this.waiting = 0})
    : super(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );

  final int pending;
  final int unsent;
  final int waiting;

  @override
  int get pendingCount => pending;

  @override
  int get ahead => unsent;

  @override
  int? get behind => waiting;
}

void main() {
  test('al día', () {
    final session = _State();
    expect(syncStateOf(session, FakeGateway()), 'Guardado en GitHub · al día');
  });

  test('lo que falta, contado', () {
    final session = _State(unsent: 2, waiting: 1);
    expect(
      syncStateOf(session, FakeGateway()),
      '2 cambios sin enviar · 1 cambio nuevo en GitHub',
    );
  });

  test('lo escrito y fuera del historial, también', () {
    final session = _State(pending: 3);
    expect(
      syncStateOf(session, FakeGateway()),
      contains('3 ficheros sin guardar'),
    );
  });

  test('sin poder escribir, lo dice', () {
    final session = _State();
    expect(
      syncStateOf(session, FakeGateway(writable: false)),
      startsWith('Solo lectura'),
    );
  });

  test('ninguna palabra de git', () {
    for (final session in [
      _State(),
      _State(pending: 1, unsent: 1, waiting: 1),
    ]) {
      final said = syncStateOf(session, FakeGateway()).toLowerCase();
      expect(said, isNot(contains('commit')));
      expect(said, isNot(contains('clon')));
    }
  });
}
