/// Las comprobaciones que se piden aparte son las mismas en la aplicación y
/// en el motor: una nueva en `engine/didacta/review.py` que no se apunte aquí
/// no se puede pedir desde Didacta, y una de aquí que el motor no conoce hace
/// fallar `didacta check`.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/review.dart';

void main() {
  test('las opcionales, las mismas y con el mismo nombre', () {
    final engine = File('../engine/didacta/review.py').readAsStringSync();
    final tuple = RegExp(
      r'OPTIONAL_CHECKS = \(([^)]*)\)',
    ).firstMatch(engine)!.group(1)!;
    final ids = [
      for (final match in RegExp(r'"([a-z-]+)"').allMatches(tuple))
        match.group(1)!,
    ];
    expect(optionalReviewChecks.keys.toSet(), ids.toSet());
    for (final id in ids) {
      final title = RegExp(
        '"${RegExp.escape(id)}": "([^"]+)"',
      ).firstMatch(engine)!.group(1);
      expect(optionalReviewChecks[id], title, reason: id);
    }
  });
}
