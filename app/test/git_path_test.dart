/// Git se lanza por la ruta que encuentra la comprobación de herramientas.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/git_path_io.dart';

void main() {
  test('la ruta entera, y es un git que contesta', () async {
    final git = gitExecutable();
    expect(git, startsWith('/'));
    final done = await Process.run(git, ['--version']);
    expect(done.exitCode, 0);
    expect('${done.stdout}', startsWith('git version'));
    // Y la misma la segunda vez: se busca una vez.
    expect(gitExecutable(), git);
  });
}
