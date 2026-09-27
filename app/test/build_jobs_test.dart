/// «Compilaciones a la vez» llega al motor como `--jobs`.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/preferences.dart';

import 'fixture.dart';

/// Un motor de mentira que apunta con qué se le llamó.
Directory fakeEngine() {
  final root = Directory.systemTemp.createTempSync('didacta-jobs-');
  addTearDown(() => root.deleteSync(recursive: true));
  final script = File('${root.path}/cli/didacta')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '#!/bin/sh\n'
      'echo "\$@" >> "\$(dirname "\$0")/../args.txt"\n'
      "echo '[]'\n",
    );
  Process.runSync('chmod', ['+x', script.path]);
  return root;
}

String argsIn(Directory root) =>
    File('${root.path}/args.txt').readAsStringSync();

void main() {
  test('con un número, se lo dice al motor', () async {
    final root = fakeEngine();
    final compiler = Compiler(
      enginePath: root.path,
      repositoryPath: root.path,
      jobs: 3,
    );
    await compiler.compileDocument(
      document: 'am-i@2026-2027/tema-1',
      profiles: const ['notes'],
      languages: const ['es'],
    );
    expect(argsIn(root), contains('--jobs 3'));
  });

  test('en automático, que decida el motor', () async {
    final root = fakeEngine();
    final compiler = Compiler(enginePath: root.path, repositoryPath: root.path);
    await compiler.compileDocument(
      document: 'am-i@2026-2027/tema-1',
      profiles: const ['notes'],
      languages: const ['es'],
    );
    expect(argsIn(root), isNot(contains('--jobs')));
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
    expect(session.buildJobs, 0);
    await session.setBuildJobs(2);
    expect(preferences.jobs, 2);
    expect(session.buildJobs, 2);
  });
}
