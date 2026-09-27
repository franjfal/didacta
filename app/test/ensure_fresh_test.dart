/// Comprobar que un repositorio está al día antes de guardar, una vez.
///
/// Dos guardados seguidos lanzaban cada uno su `fetch` --y quizá su `pull`--
/// sobre el mismo clon, y el segundo chocaba con el `index.lock` del primero.
/// Ahora esperan a la misma comprobación.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  test('dos a la vez esperan a la misma comprobación', () async {
    final root = Directory.systemTemp.createTempSync('didacta-fresh-');
    addTearDown(() => root.deleteSync(recursive: true));
    final clone = FakeClone();
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      cloneOverride: clone,
    );
    await session.useCloneForTest(root.path);

    await Future.wait([session.ensureFresh(null), session.ensureFresh(null)]);
    expect(clone.fetches, 1);
  });

  test('y la de después, recién comprobado, no pregunta', () async {
    final root = Directory.systemTemp.createTempSync('didacta-fresh-');
    addTearDown(() => root.deleteSync(recursive: true));
    final clone = FakeClone();
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      cloneOverride: clone,
    );
    await session.useCloneForTest(root.path);

    await session.ensureFresh(null);
    await session.ensureFresh(null);
    expect(clone.fetches, 1);
  });
}
