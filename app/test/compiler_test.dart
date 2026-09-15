/// Compilar desde la aplicación, contra el motor de verdad.
///
/// La mitad interesante no es que compile: eso lo prueban los 283 tests del
/// motor. Es la costura --que la aplicación encuentre el motor, le pase lo
/// que hace falta, y entienda lo que le devuelve-- y que **cuando no se
/// pueda compilar lo diga en lugar de ofrecer un botón que falla**.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler.dart';

/// El repositorio del motor, si esto corre dentro del árbol de Didacta.
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

void main() {
  test('en escritorio compilar es posible', () {
    expect(Compiler.supported, isTrue);
  });

  group('encontrar el motor', () {
    test('lo configurado manda, aunque no exista', () async {
      // Decirlo es mejor que sustituirlo por otra cosa a la callada: si
      // alguien eligió una carpeta equivocada, el mensaje tiene que hablar
      // de la carpeta que eligió.
      final found = await Compiler.discover(configured: '/no/existe');
      expect(found, '/no/existe');
    });

    test('lo busca al lado del clon', () async {
      // La disposición que sale de clonar los dos repositorios juntos, que
      // es la que dice el README y por tanto la que va a tener casi todo el
      // mundo.
      final root = engineRoot();
      if (root == null) return;
      final sibling = '${Directory(root).parent.path}/didacta_db';
      if (!Directory(sibling).existsSync()) return;

      final found = await Compiler.discover(repositoryPath: sibling);
      expect(found, root);
    });
  });

  group('cuando no se puede', () {
    test('sin motor lo dice, y dice dónde arreglarlo', () async {
      final compiler = Compiler(enginePath: '', repositoryPath: '/tmp');
      final status = await compiler.status();
      expect(status.ready, isFalse);
      expect(status.problem, contains('cli/didacta'));
      expect(status.problem, contains('Ajustes'));
    });

    test('con un motor que no existe nombra el fichero que falta', () async {
      final compiler = Compiler(
        enginePath: '/no/existe',
        repositoryPath: '/tmp',
      );
      final status = await compiler.status();
      expect(status.ready, isFalse);
      expect(status.problem, contains('/no/existe/cli/didacta'));
    });

    test('sin clon lo dice, porque compilar lee del disco', () async {
      final root = engineRoot();
      if (root == null) return;
      final compiler = Compiler(enginePath: root, repositoryPath: '');
      final status = await compiler.status();
      expect(status.ready, isFalse);
      expect(status.problem, contains('clon'));
    });

    test('un motor que no arranca sale como CompileException', () async {
      final compiler = Compiler(
        enginePath: '/no/existe',
        repositoryPath: '/tmp',
      );
      await expectLater(
        compiler.compile(
          unitPath: 'content/a/b/c',
          profiles: const ['notes'],
          languages: const ['es'],
        ),
        throwsA(isA<CompileException>()),
      );
    });
  });

  group('contra el motor real', () {
    late String root;
    late String repository;

    setUp(() {
      final found = engineRoot();
      if (found == null) {
        markTestSkipped('no estamos dentro del árbol de Didacta');
        return;
      }
      root = found;
      repository = '$found/examples/demo-course';
    });

    test('lista los perfiles que le pegan a una unidad', () async {
      if (engineRoot() == null) return;
      final compiler = Compiler(enginePath: root, repositoryPath: repository);
      final profiles = await compiler.profilesFor(
        'content/analysis/normed-spaces/definition',
      );

      // Diapositivas primero, y `book` entre los de prosa: las dos versiones
      // que se pidieron.
      expect(profiles, isNotEmpty);
      expect(profiles.first.id, 'slides');
      expect(profiles.map((p) => p.id), contains('book'));
      // Con su etiqueta en castellano, que es lo que se enseña.
      expect(profiles.first.label, 'Diapositivas');
      expect(profiles.first.family, 'slides');
      // Y las tres preseleccionadas son exactamente las primarias.
      expect(profiles.where((p) => p.isPrimary).map((p) => p.id).toSet(), {
        'slides',
        'book',
        'notes',
      });
    });

    test(
      'compila una unidad en presentación y en libro',
      () async {
        if (engineRoot() == null || !latexAvailable()) {
          markTestSkipped('hace falta latexmk');
          return;
        }
        final compiler = Compiler(enginePath: root, repositoryPath: repository);
        final results = await compiler.compile(
          unitPath: 'content/analysis/normed-spaces/definition',
          profiles: const ['slides', 'book'],
          languages: const ['es'],
        );

        expect(results, hasLength(2));
        for (final result in results) {
          expect(result.ok, isTrue, reason: result.errors.join('\n'));
          expect(result.pdf, isNotNull);
          expect(File(result.pdf!).existsSync(), isTrue);
          expect(result.pages, greaterThanOrEqualTo(1));
        }
        expect(results.map((r) => r.profile), ['slides', 'book']);
        // Y los dos PDF son distintos: son dos versiones, no una repetida.
        expect(results.first.pdf, isNot(results.last.pdf));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'entrega la salida de LaTeX según la escribe',
      () async {
        if (engineRoot() == null || !latexAvailable()) {
          markTestSkipped('hace falta latexmk');
          return;
        }
        // La costura entera: la aplicación pide progreso, el motor abre un
        // pseudoterminal para que LaTeX escriba línea a línea, y lo que sale
        // llega aquí mientras todavía se está compilando. Los tres trozos
        // están probados por su cuenta; esto prueba que encajan.
        final compiler = Compiler(enginePath: root, repositoryPath: repository);
        final lines = <String>[];
        final when = <Duration>[];
        final clock = Stopwatch()..start();

        final results = await compiler.compile(
          unitPath: 'content/analysis/normed-spaces/definition',
          profiles: const ['slides'],
          languages: const ['es'],
          onOutput: (line) {
            lines.add(line);
            when.add(clock.elapsed);
          },
        );
        clock.stop();

        expect(results.single.ok, isTrue);
        // Todo lo que enseña el terminal, no unos cuantos pasos: la salida
        // de una compilación de verdad pasa holgadamente de veinte líneas, y
        // un resumen cabría en menos.
        expect(lines.length, greaterThan(20));
        // La orden que se lanzó, que es la primera pregunta cuando algo no
        // compila desde la aplicación y sí desde el terminal.
        expect(lines.join('\n'), contains('latexmk'));
        expect(lines.join('\n'), contains('pdfTeX'));
        // Y a lo largo de la compilación, no en un bloque al final: sin el
        // pseudoterminal LaTeX escribe a bloques de cuatro kilobytes y esto
        // llegaría entero en el último instante.
        expect(
          when.first,
          lessThan(when.last * 0.75),
          reason: 'la primera línea llega mucho antes que la última',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'un idioma que falta sale como aviso, no como error',
      () async {
        if (engineRoot() == null || !latexAvailable()) {
          markTestSkipped('hace falta latexmk');
          return;
        }
        // El aviso más accionable que produce una compilación: «esta unidad no
        // tiene inglés, he usado el castellano». Estaba filtrado en el motor.
        final compiler = Compiler(enginePath: root, repositoryPath: repository);
        final results = await compiler.compile(
          unitPath: 'content/analysis/normed-spaces/definition',
          profiles: const ['notes'],
          languages: const ['en'],
        );
        final result = results.single;
        expect(result.ok, isTrue, reason: result.errors.join('\n'));
        expect(result.warnings.join(' '), contains('version'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'el preámbulo no acaba en el repositorio',
      () async {
        if (engineRoot() == null || !latexAvailable()) {
          markTestSkipped('hace falta latexmk');
          return;
        }
        // La razón de que la envoltura se genere en el directorio de
        // compilación: el `.tex` de una unidad es contenido.
        final before = Directory(
          repository,
        ).listSync(recursive: true).map((e) => e.path).toSet();

        await Compiler(enginePath: root, repositoryPath: repository).compile(
          unitPath: 'content/analysis/normed-spaces/definition',
          profiles: const ['notes'],
          languages: const ['es'],
        );

        final after = Directory(
          repository,
        ).listSync(recursive: true).map((e) => e.path).toSet();
        // Salvo el directorio de compilación, que vive dentro y no se versiona.
        expect(
          after.difference(before).where((p) => !p.contains('.didacta-build')),
          isEmpty,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
