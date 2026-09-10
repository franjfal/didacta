/// Crear, duplicar y borrar asignaturas, contra un git de verdad.
///
/// De verdad a propósito, por lo mismo que en `local_clone_test.dart`: lo
/// que hay que demostrar aquí no es que el Dart sea coherente consigo mismo,
/// sino que **una operación es un commit**. Borrar una asignatura toca
/// setenta y siete ficheros, y la razón de que esto no pase por el gateway es
/// justo esa; si el commit saliera partido en setenta y siete, o vacío, o sin
/// autor, el historial no serviría para revertir y nadie se enteraría.
///
/// El motor sí está falseado, y también a propósito: lo que hace `didacta
/// remove course` ya está probado en el motor, con sus propios tests. Lo que
/// no estaba probado es la costura --qué órdenes se le pasan, y qué se hace
/// con lo que deja en el disco-- y eso es lo que hay aquí.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/local_clone.dart';

import 'fixture.dart';

class Fixture {
  Fixture(this.root, this.clone);

  final Directory root;
  final LocalClone clone;

  String get path => root.path;

  /// Un repositorio con una asignatura dentro, como el de contenidos.
  static Future<Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('didacta-admin-');
    for (final year in ['2024-2025', '2025-2026']) {
      final directory = Directory('${root.path}/courses/algebra/$year');
      await directory.create(recursive: true);
      File(
        '${directory.path}/year.yaml',
      ).writeAsStringSync('course: algebra\nyear: $year\nstructure: []\n');
      for (final name in ['tema-1.tex', 'tema-2.tex']) {
        File('${directory.path}/$name').writeAsStringSync('% $year\n');
      }
    }
    await _git(['init', '--initial-branch=main', '.'], root.path);
    await _git(['add', '.'], root.path);
    await _git([
      '-c',
      'user.name=Semilla',
      '-c',
      'user.email=semilla@uv.es',
      'commit',
      '-m',
      'Contenido inicial',
    ], root.path);
    return Fixture(root, LocalClone(directory: root.path));
  }

  CourseAdmin admin(
    FakeCompiler engine, {
    ({String name, String email})? author = (
      name: 'Javier',
      email: 'javier@uv.es',
    ),
  }) => CourseAdmin(
    compiler: engine,
    clone: clone,
    author: author,
    token: '',
    pushOnCommit: false,
  );

  /// El último commit: mensaje, autor y qué ficheros toca.
  Future<({String message, String author, List<String> files})> head() async {
    final message = await _text(['log', '-1', '--format=%s']);
    final author = await _text(['log', '-1', '--format=%an <%ae>']);
    final files = await _text(['show', '--name-only', '--format=', 'HEAD']);
    return (
      message: message.trim(),
      author: author.trim(),
      files: files
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
    );
  }

  Future<int> commitCount() async =>
      int.parse((await _text(['rev-list', '--count', 'HEAD'])).trim());

  Future<String> _text(List<String> arguments) async {
    final result = await Process.run('git', arguments, workingDirectory: path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  Future<bool> get clean async =>
      (await _text(['status', '--porcelain'])).trim().isEmpty;

  Future<void> dispose() => root.delete(recursive: true);
}

Future<void> _git(List<String> arguments, String directory) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

void main() {
  late Fixture fixture;

  setUp(() async => fixture = await Fixture.create());
  tearDown(() async => fixture.dispose());

  group('lo que hace falta', () {
    test('sin autor no se puede: un commit necesita quién lo firma', () async {
      final admin = fixture.admin(FakeCompiler(), author: null);
      final status = await admin.status();
      expect(status.ready, isFalse);
      expect(status.problem, contains('autor'));
    });

    test('sin motor tampoco, y lo dice con las palabras del motor', () async {
      final admin = CourseAdmin(
        compiler: FakeCompiler(
          ready: false,
          problem: 'No encuentro cli/didacta',
        ),
        clone: fixture.clone,
        author: (name: 'Javier', email: 'javier@uv.es'),
        token: '',
        pushOnCommit: false,
      );
      final status = await admin.status();
      expect(status.ready, isFalse);
      expect(status.problem, 'No encuentro cli/didacta');
    });

    test('con las dos cosas, listo', () async {
      expect((await fixture.admin(FakeCompiler()).status()).ready, isTrue);
    });
  });

  group('antes de borrar', () {
    test('cuenta lo que se llevaría, y no borra nada', () async {
      final engine = FakeCompiler()
        ..answers['remove course'] =
            'Se quitaría la asignatura algebra:\n'
            '  2 año(s)\n'
            '  6 documento(s)\n'
            'Nada se ha borrado. Añade --apply.\n';
      final admin = fixture.admin(engine);

      final preview = await admin.previewRemoveCourse('algebra');

      expect(preview.years, 2);
      expect(preview.documents, 6);
      expect(preview.what, 'algebra');
      expect(preview.detail, contains('Añade --apply'));

      // Lo que de verdad importa de una previsualización.
      expect(engine.commands.single, isNot(contains('--apply')));
      expect(await fixture.clean, isTrue);
      expect(await fixture.commitCount(), 1);
    });

    test('un año se cuenta igual, con curso y año', () async {
      final engine = FakeCompiler()
        ..answers['remove year'] = '  1 año(s)\n  3 documento(s)\n';
      final preview = await fixture
          .admin(engine)
          .previewRemoveYear('algebra', '2024-2025');

      expect(preview.what, 'algebra 2024-2025');
      expect(preview.documents, 3);
      expect(engine.commands.single, [
        'remove',
        'year',
        '--',
        'algebra',
        '2024-2025',
      ]);
    });

    test('si el motor no cuenta nada, cero, y queda el texto', () async {
      final engine = FakeCompiler()
        ..answers['remove course'] = 'No existe la asignatura «fisica».';
      final preview = await fixture.admin(engine).previewRemoveCourse('fisica');

      expect(preview.years, 0);
      expect(preview.documents, 0);
      expect(preview.detail, contains('No existe'));
    });
  });

  group('borrar', () {
    test('una asignatura entera cabe en un commit', () async {
      final engine = FakeCompiler(
        onRun: (arguments) async {
          // Solo lo que borra borra. Regenerar el índice no toca el
          // contenido, y un fake que lo hiciera todo con cualquier orden no
          // probaría el orden.
          if (arguments.first == 'index') return;
          await Directory(
            '${fixture.path}/courses/algebra',
          ).delete(recursive: true);
        },
      );

      await fixture.admin(engine).removeCourse('algebra', title: 'Álgebra');

      final head = await fixture.head();
      expect(head.message, 'Quitar la asignatura «Álgebra» (algebra)');
      expect(head.author, 'Javier <javier@uv.es>');
      // Los seis ficheros de las dos ediciones, en uno.
      expect(head.files, hasLength(6));
      expect(head.files, contains('courses/algebra/2025-2026/tema-1.tex'));
      expect(await fixture.commitCount(), 2);
      expect(await fixture.clean, isTrue);

      expect(engine.commands, [
        ['remove', 'course', '--apply', '--', 'algebra'],
        // El índice, en la misma operación: sin él la biblioteca sigue
        // enseñando la asignatura que se acaba de quitar.
        ['index'],
      ]);
    });

    test('un año se lleva el año y deja el otro', () async {
      final engine = FakeCompiler(
        onRun: (arguments) async {
          if (arguments.first == 'index') return;
          await Directory(
            '${fixture.path}/courses/algebra/2024-2025',
          ).delete(recursive: true);
        },
      );

      await fixture.admin(engine).removeYear('algebra', '2024-2025');

      final head = await fixture.head();
      expect(head.message, 'Quitar el curso 2024-2025 de algebra');
      expect(head.files, hasLength(3));
      expect(
        head.files.every((path) => path.contains('2024-2025')),
        isTrue,
        reason: '${head.files}',
      );
      expect(
        Directory('${fixture.path}/courses/algebra/2025-2026').existsSync(),
        isTrue,
      );
    });
  });

  group('crear', () {
    test('una asignatura nueva, con su título y su idioma', () async {
      final engine = FakeCompiler(
        onRun: (_) async {
          final directory = Directory(
            '${fixture.path}/courses/topologia/2025-2026',
          );
          await directory.create(recursive: true);
          File(
            '${directory.path}/year.yaml',
          ).writeAsStringSync('course: topologia\n');
        },
      );

      await fixture
          .admin(engine)
          .createCourse(id: 'topologia', title: 'Topología', language: 'ca');

      expect(engine.commands, [
        [
          'new',
          'course',
          '--title',
          'Topología',
          '--lang',
          'ca',
          // El id, detrás de `--`: viene de un formulario y `argparse`
          // tomaría un `-algo` por una opción. Esto es lo que lo fija.
          '--',
          'topologia',
        ],
        ['index'],
      ]);
      final head = await fixture.head();
      expect(head.message, 'Añadir la asignatura «Topología» (topologia)');
      expect(head.files, ['courses/topologia/2025-2026/year.yaml']);
    });

    test('copiando otra, y el mensaje lo dice', () async {
      final engine = FakeCompiler(
        onRun: (_) async {
          final directory = Directory(
            '${fixture.path}/courses/algebra-ii/2025-2026',
          );
          await directory.create(recursive: true);
          File('${directory.path}/year.yaml').writeAsStringSync('x: 1\n');
        },
      );

      await fixture
          .admin(engine)
          .createCourse(id: 'algebra-ii', title: 'Álgebra II', from: 'algebra');

      expect(engine.commands.first, contains('--from'));
      expect(
        (await fixture.head()).message,
        'Añadir la asignatura «Álgebra II» (algebra), copiada de algebra'
            .replaceFirst('(algebra)', '(algebra-ii)'),
      );
    });

    test('duplicar un año copia del que se diga', () async {
      final engine = FakeCompiler(
        onRun: (_) async {
          final directory = Directory(
            '${fixture.path}/courses/algebra/2026-2027',
          );
          await directory.create(recursive: true);
          File('${directory.path}/year.yaml').writeAsStringSync('y: 1\n');
        },
      );

      await fixture
          .admin(engine)
          .duplicateYear(
            course: 'algebra',
            year: '2026-2027',
            from: '2025-2026',
          );

      expect(engine.commands, [
        ['new', 'year', '--from', '2025-2026', '--', 'algebra', '2026-2027'],
        ['index'],
      ]);
      expect(
        (await fixture.head()).message,
        'Añadir el curso 2026-2027 de algebra, copiado de 2025-2026',
      );
    });
  });

  group('el índice', () {
    // El fallo que esto coge ya ocurrió, y desde fuera se veía así: «dice
    // que el curso está creado y en la lista no aparece». La biblioteca y la
    // lista de asignaturas leen `generated/`, que lo genera el motor, así que
    // una operación que no lo regenera no existe para nadie.

    test('se regenera después de la operación, no antes', () async {
      final engine = FakeCompiler(
        onRun: (_) async {
          final directory = Directory(
            '${fixture.path}/courses/algebra/2026-2027',
          );
          await directory.create(recursive: true);
          File('${directory.path}/year.yaml').writeAsStringSync('y: 1\n');
        },
      );

      await fixture
          .admin(engine)
          .duplicateYear(
            course: 'algebra',
            year: '2026-2027',
            from: '2025-2026',
          );

      // El orden importa: al revés se indexaría el repositorio de antes.
      expect(engine.commands, [
        ['new', 'year', '--from', '2025-2026', '--', 'algebra', '2026-2027'],
        ['index'],
      ]);
    });

    test('entra en el mismo commit que el contenido', () async {
      // En el mismo y no en otro: un commit que añade un curso y deja el
      // índice como estaba describe un repositorio que se contradice, y
      // quien lo revierta tendría que acordarse de revertir los dos.
      final engine = FakeCompiler(
        onRun: (arguments) async {
          if (arguments.first == 'index') {
            Directory('${fixture.path}/generated').createSync();
            File(
              '${fixture.path}/generated/units.json',
            ).writeAsStringSync('{"units": []}\n');
            return;
          }
          final directory = Directory('${fixture.path}/courses/topologia');
          await directory.create(recursive: true);
          File('${directory.path}/course.yaml').writeAsStringSync('x: 1\n');
        },
      );

      await fixture
          .admin(engine)
          .createCourse(id: 'topologia', title: 'Topología');

      final head = await fixture.head();
      expect(head.files, [
        'courses/topologia/course.yaml',
        'generated/units.json',
      ]);
      expect(await fixture.commitCount(), 2);
    });

    test('si el índice falla, el cambio se guarda igual y se dice', () async {
      // Los ficheros ya están escritos: dejarlos sin commit sería perder el
      // cambio de vista, que es peor que tener el índice viejo. Pero hay que
      // decirlo, porque hasta que se regenere la pantalla no lo verá.
      final engine = _FailingIndex(fixture.path);

      await expectLater(
        fixture.admin(engine).createCourse(id: 'topologia', title: 'Topología'),
        throwsA(
          isA<AdminException>()
              .having((e) => e.message, 'message', contains('está hecho'))
              .having((e) => e.message, 'message', contains('didacta index'))
              .having((e) => e.detail, 'detail', contains('se atragantó')),
        ),
      );
      // Guardado, que es lo que importa.
      expect(await fixture.commitCount(), 2);
      expect((await fixture.head()).files, ['courses/topologia/course.yaml']);
      expect(await fixture.clean, isTrue);
    });
  });

  group('cuando algo va mal', () {
    test('si el motor falla no hay commit', () async {
      final engine = FakeCompiler(
        failWith: const CompileException(
          'El motor falló',
          detail: 'Traceback...',
        ),
      );

      await expectLater(
        fixture.admin(engine).removeCourse('algebra', title: 'Álgebra'),
        throwsA(
          isA<AdminException>()
              .having((e) => e.message, 'message', 'El motor falló')
              .having((e) => e.detail, 'detail', contains('Traceback')),
        ),
      );
      expect(await fixture.commitCount(), 1);
    });

    test(
      'si el motor no cambió nada, se dice, y no hay commit vacío',
      () async {
        // El caso de verdad: borrar algo que ya no está. El motor termina bien
        // y no toca el disco, y un commit vacío ahí sería basura en el
        // historial.
        final engine = FakeCompiler()
          ..answers['remove'] = 'No existe la asignatura «fisica».';

        await expectLater(
          fixture.admin(engine).removeCourse('fisica', title: 'Física'),
          throwsA(
            isA<AdminException>()
                .having((e) => e.message, 'message', contains('no cambió nada'))
                .having((e) => e.detail, 'detail', contains('No existe')),
          ),
        );
        expect(await fixture.commitCount(), 1);
      },
    );

    test('sin autor no se llega a lanzar el motor', () async {
      final engine = FakeCompiler();
      await expectLater(
        fixture.admin(engine, author: null).removeYear('algebra', '2024-2025'),
        throwsA(isA<AdminException>()),
      );
      expect(engine.commands, isEmpty);
      expect(await fixture.clean, isTrue);
    });
  });
}

/// Un motor que hace la operación y luego se atraganta con el índice.
class _FailingIndex extends FakeCompiler {
  _FailingIndex(this.root);

  final String root;

  @override
  Future<String> run(
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    commands.add(arguments);
    if (arguments.first == 'index') {
      throw const CompileException(
        'El motor falló (código 1).',
        detail: 'index: se atragantó con una unidad',
      );
    }
    final directory = Directory('$root/courses/topologia');
    await directory.create(recursive: true);
    File('${directory.path}/course.yaml').writeAsStringSync('x: 1\n');
    return '';
  }
}
