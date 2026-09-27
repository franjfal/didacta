/// «PDF accesibles» llega al motor como `--accessible`, y solo al compilar
/// documentos: la vista de una lección suelta es para mirarla, no para
/// repartirla.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/preferences.dart';

import 'build_jobs_test.dart' show argsIn, fakeEngine;
import 'fixture.dart';

void main() {
  test('encendido, se lo dice al motor', () async {
    final root = fakeEngine();
    final compiler = Compiler(
      enginePath: root.path,
      repositoryPath: root.path,
      accessible: true,
    );
    await compiler.compileDocument(
      document: 'am-i@2026-2027/tema-1',
      profiles: const ['notes'],
      languages: const ['es'],
    );
    expect(argsIn(root), contains('--accessible'));
  });

  test('apagado, que es lo de salida, no', () async {
    final root = fakeEngine();
    await Compiler(
      enginePath: root.path,
      repositoryPath: root.path,
    ).compileDocument(
      document: 'am-i@2026-2027/tema-1',
      profiles: const ['notes'],
      languages: const ['es'],
    );
    expect(argsIn(root), isNot(contains('--accessible')));
  });

  test('se guarda, y lo usan los compiladores de la sesión', () async {
    final preferences = MemoryPreferences();
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      preferencesOverride: preferences,
    );
    await session.primeForTest(catalogue);
    expect(session.accessiblePdf, isFalse);
    await session.setAccessiblePdf(true);
    expect(preferences.accessible, isTrue);
    expect(session.accessiblePdf, isTrue);
  });
}
