/// Con el motor y LaTeX de verdad: un error llega con su lección y su línea,
/// y «Detener» para también a LaTeX.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';

String? engineRoot() {
  var directory = Directory.current;
  for (var i = 0; i < 4; i += 1) {
    if (File('${directory.path}/cli/didacta').existsSync()) {
      return directory.path;
    }
    directory = directory.parent;
  }
  return null;
}

bool latexAvailable() {
  try {
    return Process.runSync('which', ['latexmk']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Una copia del repositorio de ejemplo, con `\foo` en la línea 9 de una
/// lección.
Future<String> brokenExample(String engine) async {
  final root = await Directory.systemTemp.createTemp('didacta-errors-');
  addTearDown(() => root.delete(recursive: true));
  await Process.run('cp', ['-R', '$engine/app/assets/ejemplo/.', root.path]);
  final lesson = File(
    '${root.path}/content/calculo/limites/calculo-de-limites/algebra-de-limites/es.tex',
  );
  final lines = lesson.readAsLinesSync();
  final title = lines.indexWhere((line) => line.contains(r'\didactatitle'));
  lines.insert(title + 1, r'\foo');
  lesson.writeAsStringSync('${lines.join('\n')}\n');
  return root.path;
}

void main() {
  late String engine;

  setUp(() {
    final found = engineRoot();
    if (found == null || !latexAvailable()) {
      markTestSkipped('hace falta el motor y latexmk');
    }
    engine = found ?? '';
  });

  test(
    'un error dice de qué lección, en qué idioma y en qué línea',
    () async {
      if (!latexAvailable()) return;
      final repository = await brokenExample(engine);
      final compiler = Compiler(enginePath: engine, repositoryPath: repository);
      final results = await compiler.compileDocument(
        document: 'calculo-i@2026-2027/tema-1',
        profiles: const ['notes'],
        languages: const ['es'],
      );
      final result = results.single;
      expect(result.ok, isFalse);
      final error = result.errorDiagnostics.first;
      expect(error.unit, 'content/calculo/limites/calculo-de-limites/algebra-de-limites');
      expect(error.language, 'es');
      expect(error.path, 'content/calculo/limites/calculo-de-limites/algebra-de-limites/es.tex');
      expect(error.line, isNotNull);
      expect(error.message, contains('Undefined control sequence'));
      expect(error.context, contains(r'\foo'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'Detener para la compilación, y LaTeX con ella',
    () async {
      if (!latexAvailable() || !Platform.isMacOS && !Platform.isLinux) {
        return;
      }
      final repository = await brokenExample(engine);
      final compiler = Compiler(enginePath: engine, repositoryPath: repository);
      final started = DateTime.now();
      var sawLatex = false;
      final running = compiler.compileDocument(
        document: 'calculo-i@2026-2027/tema-1',
        profiles: const ['slides', 'notes', 'book'],
        languages: const ['es'],
        onOutput: (line) {
          if (line.contains('pdfTeX')) sawLatex = true;
        },
      );
      // En cuanto LaTeX habla, se para.
      while (!sawLatex &&
          DateTime.now().difference(started) < const Duration(seconds: 60)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(sawLatex, isTrue);
      await compiler.stopCompiling();
      try {
        await running.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        fail('Detener no paró la compilación');
      } catch (_) {
        // Parar deja un resultado a medias o un error: los dos valen.
      }
      // Y nada de LaTeX sigue compilando en esa carpeta.
      await Future<void>.delayed(const Duration(seconds: 1));
      final left = Process.runSync('ps', ['-axo', 'command=']).stdout
          .toString()
          .split('\n')
          .where(
            (line) =>
                (line.contains('pdflatex') || line.contains('latexmk')) &&
                line.contains(repository.split('/').last),
          )
          .toList();
      expect(left, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
