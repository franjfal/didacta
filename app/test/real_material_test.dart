/// El protector, contra el material de verdad.
///
/// Los tests de al lado usan ejemplos escogidos; este pasa por las 57
/// unidades del Tema 1 recuperado, que llevan encima quince años de LaTeX
/// escrito a mano: `\nohyphens`, `\cites` con cinco argumentos, tikz,
/// comentarios a medias, acentos de todas las formas.
///
/// Comprueba una sola cosa, que es la que decide si esto se puede usar: que
/// el ida y vuelta devuelve el fichero **byte a byte**. Si no lo hace con una
/// traducción que no cambia nada, no lo va a hacer con una que sí.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/latex_protect.dart';

const String repo = '/Users/javier/didacta/didacta_db_teoria';

void main() {
  final root = Directory('$repo/content');
  final files = root.existsSync()
      ? root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.tex'))
            .toList()
      : <File>[];

  test('el material real entra y sale idéntico', () {
    if (files.isEmpty) {
      markTestSkipped('sin el repositorio de contenido delante');
      return;
    }
    final broken = <String>[];
    for (final file in files) {
      final tex = file.readAsStringSync();
      final out = StringBuffer();
      for (final segment in protectLatex(tex)) {
        final restored = segment.restore(segment.text);
        if (restored == null) {
          broken.add('${file.path}: no reconstruye');
          break;
        }
        out.write(restored);
      }
      if (out.toString() != tex) broken.add('${file.path}: sale distinto');
    }
    expect(broken, isEmpty, reason: broken.take(5).join('\n'));
  });

  test('de todas ellas sale prosa que traducir', () {
    if (files.isEmpty) {
      markTestSkipped('sin el repositorio de contenido delante');
      return;
    }
    // La otra mitad: protegerlo todo también sería «no romper nada».
    var withProse = 0;
    for (final file in files) {
      final letters = protectLatex(
        file.readAsStringSync(),
      ).fold<int>(0, (sum, s) => sum + s.letters);
      if (letters > 0) withProse += 1;
    }
    expect(withProse, greaterThan(files.length ~/ 2));
  });
}
