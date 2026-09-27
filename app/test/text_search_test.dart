/// Buscar en el texto de las lecciones: el patrón, git de verdad y lo que
/// devuelve.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/model/text_search.dart';

void main() {
  group('el patrón', () {
    test('sin tildes ni mayúsculas', () {
      final pattern = RegExp(accentPattern('limite'));
      expect(pattern.hasMatch('Unicidad del límite'), isTrue);
      expect(pattern.hasMatch('LÍMITE'), isTrue);
      expect(pattern.hasMatch('limite'), isTrue);
      expect(RegExp(accentPattern('Límite')).hasMatch('limite'), isTrue);
    });

    test('lo demás, tal cual', () {
      final pattern = RegExp(accentPattern(r'\lambda x'));
      expect(pattern.hasMatch(r'$\lambda x$'), isTrue);
      expect(pattern.hasMatch('lambda x'), isFalse);
      expect(RegExp(accentPattern('a.b')).hasMatch('axb'), isFalse);
    });
  });

  test('lo que devuelve git grep --null', () {
    final hits = parseGrep(
      'content/a/b/c/es.tex\u000012\u0000Sea el límite\n'
      'problems/x/y/z/va.tex\u00003\u0000El límit\n'
      'basura sin separadores\n',
    );
    expect(hits, hasLength(2));
    expect(hits.first.unitPath, 'content/a/b/c');
    expect(hits.first.language, 'es');
    expect(hits.first.line, 12);
    expect(hits.last.language, 'va');
  });

  group('con git de verdad', () {
    late Directory root;

    setUp(() async {
      if (!await LocalClone.gitAvailable()) {
        markTestSkipped('sin git');
        return;
      }
      root = await Directory.systemTemp.createTemp('didacta-grep-');
      File('${root.path}/content/a/b/c/es.tex')
        ..createSync(recursive: true)
        ..writeAsStringSync('Primera línea.\nPor la unicidad del límite.\n');
      File('${root.path}/content/a/b/c/unit.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('topic: limite\n');
      for (final args in [
        ['init', '-q'],
        ['add', '.'],
        ['-c', 'user.name=T', '-c', 'user.email=t@t', 'commit', '-qm', 'uno'],
      ]) {
        await Process.run('git', args, workingDirectory: root.path);
      }
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('encuentra lo que dice, y solo en los .tex', () async {
      final clone = LocalClone(directory: root.path);
      final hits = await clone.grep(accentPattern('LIMITE'));
      expect(hits, hasLength(1));
      expect(hits.single.path, 'content/a/b/c/es.tex');
      expect(hits.single.line, 2);
      expect(hits.single.text, contains('límite'));
    });

    test('no encontrar nada no es un error', () async {
      final clone = LocalClone(directory: root.path);
      expect(await clone.grep(accentPattern('hilbert')), isEmpty);
    });
  });
}
