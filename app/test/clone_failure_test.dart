/// Qué clase de fallo es lo que dice git.
///
/// En un solo sitio y con las frases de verdad: antes cada pantalla buscaba
/// las suyas en el mensaje, y el mismo fallo se contaba distinto según dónde
/// pasara.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/local_clone.dart';

void main() {
  final cases = <String, CloneFailure>{
    ' ! [rejected]        main -> main (fetch first)\n'
            "error: failed to push some refs to 'https://github.com/x/y.git'\n"
            'hint: Updates were rejected because the remote contains work that you do':
        CloneFailure.behind,
    ' ! [rejected]        main -> main (non-fast-forward)': CloneFailure.behind,
    "remote: Invalid username or password.\nfatal: Authentication failed for 'https://github.com/x/y.git/'":
        CloneFailure.unauthenticated,
    "remote: Permission to x/y.git denied to alguien.\nfatal: unable to access 'https://github.com/x/y.git/': The requested URL returned error: 403":
        CloneFailure.unauthenticated,
    "fatal: unable to access 'https://github.com/x/y.git/': Could not resolve host: github.com":
        CloneFailure.offline,
    "fatal: Unable to create '/r/.git/index.lock': File exists.\n\nAnother git process seems to be running in this repository":
        CloneFailure.locked,
    'CONFLICT (content): Merge conflict in content/a/b/es.tex\nAutomatic merge failed; fix conflicts and then commit the result.':
        CloneFailure.conflict,
    'error: Your local changes to the following files would be overwritten by merge:':
        CloneFailure.conflict,
    ' ! [remote rejected] main -> main (protected branch hook declined)':
        CloneFailure.rejected,
    'fatal: not a git repository': CloneFailure.other,
  };

  for (final entry in cases.entries) {
    test('${entry.value.name}: ${entry.key.split('\n').first}', () {
      expect(classifyGit(entry.key), entry.value);
    });
  }

  test('lo que se dice al lanzarlo manda sobre lo deducido', () {
    const thrown = CloneException(
      'x no existe en el clon.',
      kind: CloneFailure.missing,
    );
    expect(thrown.kind, CloneFailure.missing);
  });

  test('y si no se dice, se deduce de lo que dijo git', () {
    const thrown = CloneException(
      'git falló al enviar (código 1).',
      stderr: ' ! [rejected] main -> main (fetch first)',
    );
    expect(thrown.kind, CloneFailure.behind);
  });
}
