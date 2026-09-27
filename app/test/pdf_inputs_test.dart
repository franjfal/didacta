/// La pestaña del PDF sabe si está vieja por lo que entró en él.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/pdf_inputs.dart';

void main() {
  late Directory root;
  late File lesson;
  late String pdf;

  /// Lo que escribe el motor al compilar, con las mismas claves.
  void record() {
    final stat = lesson.statSync();
    File('$pdf$inputsSuffix').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'files': {
          lesson.path: {
            'sha256': sha256.convert(lesson.readAsBytesSync()).toString(),
            'mtime': stat.modified.microsecondsSinceEpoch / 1e6,
            'size': stat.size,
          },
        },
        'lessons': {
          lesson.parent.path: ['es.tex'],
        },
      }),
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('didacta-pdf-inputs-');
    lesson = File('${root.path}/content/a/b/c/es.tex')
      ..createSync(recursive: true)
      ..writeAsStringSync('El texto.\n');
    pdf = '${root.path}/doc.pdf';
    File(pdf).writeAsStringSync('%PDF');
    record();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('sin cambios, al día', () async {
    expect(await staleByInputs(pdf), isFalse);
  });

  test('otra fecha con el mismo texto, al día', () async {
    lesson.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    expect(await staleByInputs(pdf), isFalse);
  });

  test('otro texto, viejo', () async {
    lesson.writeAsStringSync('El textO.\n');
    lesson.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    expect(await staleByInputs(pdf), isTrue);
  });

  test('una traducción nueva, viejo', () async {
    File('${lesson.parent.path}/va.tex').writeAsStringSync('El text.\n');
    expect(await staleByInputs(pdf), isTrue);
  });

  test('sin registro, no se sabe', () async {
    File('$pdf$inputsSuffix').deleteSync();
    expect(await staleByInputs(pdf), isNull);
  });
}
