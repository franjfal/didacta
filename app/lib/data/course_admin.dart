/// Crear, duplicar y borrar asignaturas y años.
///
/// Estas operaciones no pasan por el gateway como el resto de la edición, y
/// merece la pena decir por qué. El gateway escribe **un fichero** por
/// commit, que es lo correcto para editar un `.tex` o un `year.yaml`.
/// Duplicar un año escribe un `year.yaml` y diecisiete `.tex`; borrar una
/// asignatura borra dos años y setenta y siete documentos. Hacerlo por el
/// gateway serían setenta y ocho commits para una sola cosa, y un historial
/// así no se puede leer ni revertir de una pieza.
///
/// Así que lo hace el motor sobre el clon --`didacta new course`,
/// `didacta remove year`, que ya existen y están probados-- y la aplicación
/// lo cierra en **un commit con todo dentro**. Sigue cumpliéndose la regla
/// que importa: todo cambio es un commit con autor y mensaje, y se puede
/// revertir.
///
/// La consecuencia es que esto es de escritorio. En web no hay clon ni forma
/// de lanzar un proceso, y la pantalla lo dice en lugar de ofrecer botones
/// que no pueden funcionar.
library;

import 'compiler.dart';
import 'local_clone.dart';

/// Qué hace falta para administrar asignaturas, y si está.
class AdminStatus {
  const AdminStatus({required this.ready, this.problem});

  final bool ready;

  /// Qué falta, en palabras con las que se pueda hacer algo.
  final String? problem;
}

/// El resumen de lo que un borrado se llevaría.
///
/// Se pide antes de borrar y se enseña en el diálogo: «esta asignatura tiene
/// dos años y setenta y siete documentos» es lo que hace que alguien pueda
/// decidir, y «¿seguro?» no lo es.
class RemovalPreview {
  const RemovalPreview({
    required this.what,
    required this.years,
    required this.documents,
    required this.detail,
  });

  final String what;
  final int years;
  final int documents;

  /// Lo que dijo el motor, tal cual, para lo que el resumen no cubra.
  final String detail;
}

class AdminException implements Exception {
  const AdminException(this.message, {this.detail = ''});

  final String message;
  final String detail;

  @override
  String toString() => detail.isEmpty ? message : '$message\n\n$detail';
}

/// Las operaciones sobre asignaturas y años.
class CourseAdmin {
  const CourseAdmin({
    required this.compiler,
    required this.clone,
    required this.author,
    required this.token,
    required this.pushOnCommit,
    this.beforeWrite,
  });

  /// El que sabe lanzar el motor. Se reutiliza en lugar de tener otro:
  /// encontrar `cli/didacta`, comprobar que está y lanzarlo ya está resuelto.
  final Compiler compiler;

  final LocalClone clone;

  final ({String name, String email})? author;
  final String token;
  final bool pushOnCommit;

  /// Ponerse al día con GitHub antes de tocar nada.
  ///
  /// Lo pone la sesión, que es quien sabe cuándo se miró por última vez.
  /// Crear o borrar una asignatura sobre una copia vieja del repositorio es
  /// de lo que peor se arregla después: mueve ficheros y reescribe el índice.
  final Future<void> Function()? beforeWrite;

  Future<AdminStatus> status() async {
    if (author == null) {
      return const AdminStatus(
        ready: false,
        problem:
            'Un commit necesita un autor. Pon un nombre y un correo en '
            'Ajustes.',
      );
    }
    final found = await compiler.status();
    if (!found.ready) {
      return AdminStatus(ready: false, problem: found.problem);
    }
    return const AdminStatus(ready: true);
  }

  /// Qué se llevaría borrar una asignatura. No borra nada.
  Future<RemovalPreview> previewRemoveCourse(String course) async {
    final output = await compiler.run(['remove', 'course', '--', course]);
    return _previewFrom(course, output);
  }

  /// Qué se llevaría borrar un año. No borra nada.
  Future<RemovalPreview> previewRemoveYear(String course, String year) async {
    final output = await compiler.run(['remove', 'year', '--', course, year]);
    return _previewFrom('$course $year', output);
  }

  static RemovalPreview _previewFrom(String what, String output) {
    // El motor imprime «N año(s)» y «N documento(s)». Se leen de ahí en
    // lugar de contarlos otra vez aquí: el motor es el que sabe escanear el
    // repositorio, y dos recuentos que pueden discrepar son peores que uno.
    int number(RegExp pattern) {
      final match = pattern.firstMatch(output);
      return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
    }

    return RemovalPreview(
      what: what,
      years: number(RegExp(r'(\d+)\s+año\(s\)')),
      documents: number(RegExp(r'(\d+)\s+documento\(s\)')),
      detail: output.trim(),
    );
  }

  /// El índice, que es lo que lee la biblioteca.
  ///
  /// `generated/` va **en el mismo commit** que el cambio de contenido, y no
  /// en uno aparte, porque son la misma cosa: un commit que añade un curso y
  /// deja el índice como estaba describe un repositorio que se contradice, y
  /// quien lo revierta tendría que acordarse de revertir los dos.
  static const String _index = 'generated';

  Future<void> removeCourse(String course, {required String title}) => _change(
    arguments: ['remove', 'course', '--apply', '--', course],
    paths: ['courses/$course'],
    message: 'Quitar la asignatura «$title» ($course)',
  );

  Future<void> removeYear(String course, String year) => _change(
    arguments: ['remove', 'year', '--apply', '--', course, year],
    paths: ['courses/$course/$year'],
    message: 'Quitar el curso $year de $course',
  );

  Future<void> createCourse({
    required String id,
    required String title,
    String? from,
    String? language,
  }) => _change(
    arguments: [
      'new',
      'course',
      if (from != null && from.isNotEmpty) ...['--from', from],
      if (title.isNotEmpty) ...['--title', title],
      if (language != null && language.isNotEmpty) ...['--lang', language],
      // Detrás de `--` porque el id viene de un formulario y `argparse`
      // tomaría un `-algo` por una opción.
      '--',
      id,
    ],
    paths: ['courses/$id'],
    message: from == null || from.isEmpty
        ? 'Añadir la asignatura «$title» ($id)'
        : 'Añadir la asignatura «$title» ($id), copiada de $from',
  );

  Future<void> duplicateYear({
    required String course,
    required String year,
    required String from,
  }) => _change(
    arguments: ['new', 'year', '--from', from, '--', course, year],
    paths: ['courses/$course/$year'],
    message: 'Añadir el curso $year de $course, copiado de $from',
  );

  /// Lanza el motor, regenera el índice y cierra todo en un commit.
  ///
  /// Si el motor falla no hay commit, y si no cambió nada tampoco: un
  /// historial con commits vacíos es un historial que nadie lee.
  ///
  /// El índice se regenera aquí y no se deja para después porque sin él la
  /// operación no existe para nadie: la biblioteca y la lista de asignaturas
  /// leen `generated/`, así que crear un curso y no regenerarlo se ve como
  /// «dice que lo ha creado y no aparece». Pasó.
  Future<void> _change({
    required List<String> arguments,
    required List<String> paths,
    required String message,
  }) async {
    final who = author;
    if (who == null) {
      throw const AdminException(
        'Un commit necesita un autor. Pon un nombre y un correo en Ajustes.',
      );
    }

    // Al día antes de tocar. Que no se pueda no para la operación: lo escrito
    // queda en el clon y la barra de sincronización dice lo que falta.
    try {
      await beforeWrite?.call();
    } catch (_) {
      // Ya lo cuenta quien puso la llamada.
    }

    final String output;
    try {
      output = await compiler.run(arguments);
    } on CompileException catch (error) {
      throw AdminException(error.message, detail: error.detail);
    }

    // El índice, después del cambio. Si falla, el commit se hace igual: los
    // ficheros ya están escritos y dejarlos sin commit sería perder el
    // cambio de vista, que es peor que tener el índice viejo. Se dice, eso
    // sí, porque hasta que se regenere la pantalla no verá lo que se hizo.
    Object? indexProblem;
    try {
      await compiler.run(const ['index']);
    } on CompileException catch (error) {
      indexProblem = error;
    }

    try {
      final committed = await clone.commitPaths(
        paths: [...paths, _index],
        message: message,
        authorName: who.name,
        authorEmail: who.email,
        token: token,
        push: pushOnCommit && token.isNotEmpty,
      );
      if (!committed) {
        throw AdminException(
          'El motor no cambió nada, así que no hay nada que guardar.',
          detail: output.trim(),
        );
      }
      if (indexProblem != null) {
        throw AdminException(
          'El cambio está hecho y guardado, pero el índice no se pudo '
          'regenerar, así que la pantalla no lo verá todavía. Ejecuta '
          '`didacta index` en el repositorio.',
          detail: '$indexProblem',
        );
      }
    } on CloneException catch (error) {
      throw AdminException(
        'Los ficheros se han cambiado, pero el commit falló: quedan sin '
        'guardar en el clon.',
        detail: error.stderr.isEmpty ? error.message : error.stderr,
      );
    }
  }
}
