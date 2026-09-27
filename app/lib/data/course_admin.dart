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

import 'dart:math';

import 'compiler.dart';
import 'diagnostics.dart';
import 'local_clone.dart';
import '../l10n/tr.dart';

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

  /// Lo que se llevaría en varios repositorios a la vez: una asignatura
  /// repartida se quita de todos.
  ///
  /// Los documentos se suman, que cada uno vive en uno solo. Los años no:
  /// el mismo curso académico está en los dos y no son dos cursos, así que
  /// cuenta el mayor.
  factory RemovalPreview.across(List<RemovalPreview> parts) {
    if (parts.length == 1) return parts.single;
    return RemovalPreview(
      what: parts.isEmpty ? '' : parts.first.what,
      years: parts.fold(0, (most, part) => max(most, part.years)),
      documents: parts.fold(0, (sum, part) => sum + part.documents),
      detail: parts.map((part) => part.detail).join('\n'),
    );
  }
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
    this.onIndexed,
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

  /// Avisa de que el índice se acaba de regenerar, para que la recarga del
  /// catálogo que viene detrás no lance el motor otra vez a comprobarlo.
  final void Function()? onIndexed;

  Future<AdminStatus> status() async {
    if (author == null) {
      return AdminStatus(
        ready: false,
        problem: tr(
          'Para guardar en el historial hace falta un autor. Pon un '
          'nombre y un correo en Ajustes.',
        ),
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

  /// Deshace un cambio: lo que había en [paths] en [sha] --el commit de
  /// justo antes-- vuelve, como un commit nuevo.
  ///
  /// No reescribe la historia: el cambio deshecho sigue en ella, y deshacer
  /// es un cambio más, con su mensaje, que a su vez se puede deshacer.
  Future<void> undo({
    required String sha,
    required List<String> paths,
    required String message,
  }) => _change(
    arguments: const [],
    write: () async {
      await clone.restoreFrom(sha: sha, paths: paths);
    },
    paths: paths,
    message: message,
  );

  Future<void> removeCourse(String course, {required String title}) => _change(
    arguments: ['remove', 'course', '--apply', '--', course],
    paths: ['courses/$course'],
    message: tr('Quitar la asignatura «{0}» ({1})', [title, course]),
  );

  Future<void> removeYear(String course, String year) => _change(
    arguments: ['remove', 'year', '--apply', '--', course, year],
    paths: ['courses/$course/$year'],
    message: tr('Quitar el curso {0} de {1}', [year, course]),
  );

  /// Una lección nueva, en `categoría/tema/nombre`.
  ///
  /// Con lo que escribe `didacta new unit`: el `.tex` del idioma con el
  /// esqueleto y un `unit.yaml` con título, tipo y bloque. Un problema va a
  /// `problems/` y lo demás a `content/`, que es lo que decide el motor por el
  /// tipo.
  Future<void> createUnit({
    required String path,
    required String kind,
    required String title,
    String? language,
    String? block,
  }) => _change(
    arguments: [
      'new',
      'unit',
      '--kind',
      kind,
      if (title.isNotEmpty) ...['--title', title],
      if (language != null && language.isNotEmpty) ...['--lang', language],
      if (block != null && block.isNotEmpty) ...['--block', block],
      '--',
      path,
    ],
    paths: ['${unitAreaFor(kind)}/$path'],
    message: tr('Añadir la lección «{0}»', [title]),
  );

  /// Una lección que empieza siendo una copia de [from], en
  /// `categoría/tema/nombre` de su misma área.
  ///
  /// Con `didacta new unit --from`: la carpeta entera --idiomas, figuras,
  /// `unit.yaml`-- con un id nuevo, y [title] puesto en [language]. Son dos
  /// lecciones desde ese momento.
  Future<void> duplicateUnit({
    required String from,
    required String path,
    required String title,
    required String fromTitle,
    String? language,
  }) => _change(
    arguments: [
      'new',
      'unit',
      '--from=$from',
      if (title.isNotEmpty) ...['--title', title],
      if (language != null && language.isNotEmpty) ...['--lang', language],
      '--',
      path,
    ],
    paths: ['${from.split('/').first}/$path'],
    message: tr('Añadir la lección «{0}», copia de «{1}»', [title, fromTitle]),
  );

  /// Lleva la lección [unit] a [to] (`categoría/tema/nombre`, sin el área),
  /// con `didacta move --unit`.
  ///
  /// La misma lección en otra carpeta: el motor reescribe cada composición
  /// que la nombra por su ruta, los temas vinculados y los prerrequisitos de
  /// las demás, y el commit se los lleva todos junto con la carpeta.
  Future<void> moveUnit({
    required String unit,
    required String to,
    required String title,
  }) => _change(
    arguments: ['move', '--unit=$unit', '--to=$to'],
    paths: ['content', 'problems', 'courses', 'shared/documents'],
    message: tr('Mover la lección «{0}» a {1}', [title, to]),
  );

  /// Dónde va una lección de este tipo: los problemas en `problems/`, lo
  /// demás en `content/`. La misma regla que el motor.
  static String unitAreaFor(String kind) =>
      kind == 'problem' ? 'problems' : 'content';

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
        ? tr('Añadir la asignatura «{0}» ({1})', [title, id])
        : tr('Añadir la asignatura «{0}» ({1}), copiada de {2}', [
            title,
            id,
            from,
          ]),
  );

  /// Crea un curso académico, copiando otro o en blanco.
  ///
  /// [from] vacío es en blanco, y es un caso de verdad: el primer curso de
  /// una asignatura nueva no tiene de dónde copiar, y el de un año que se
  /// compone desde cero tampoco quiere arrastrar lo del anterior para ir
  /// borrándolo.
  Future<void> duplicateYear({
    required String course,
    required String year,
    String from = '',
    String fromDirectory = '',
    String fromLabel = '',
  }) => _change(
    arguments: [
      'new',
      'year',
      if (fromDirectory.isNotEmpty) ...[
        '--from-dir',
        fromDirectory,
      ] else if (from.isEmpty)
        '--empty'
      else ...[
        '--from',
        from,
      ],
      '--',
      course,
      year,
    ],
    paths: ['courses/$course/$year'],
    message: fromDirectory.isNotEmpty
        // El nombre de la congelación y no la carpeta: la carpeta es una
        // caché de esta máquina y no dice nada a quien lea el historial.
        ? tr('Añadir el curso {0} de {1}, desde «{2}»', [
            year,
            course,
            fromLabel,
          ])
        : from.isEmpty
        ? tr('Añadir el curso {0} de {1}', [year, course])
        : tr('Añadir el curso {0} de {1}, copiado de {2}', [
            year,
            course,
            from,
          ]),
  );

  /// Declara un tema en un curso.
  ///
  /// El tema es el bloque bajo el que se agrupan los documentos, y se declara
  /// aparte de ellos: sus ficheros pueden estar en repositorios distintos,
  /// así que uno declara y los demás nombran. Esto escribe la mitad que
  /// declara; la otra la pone cada documento con `themes:`.
  Future<void> createTheme({
    required String course,
    required String year,
    required String id,
    required String title,
    String? language,
  }) => _change(
    arguments: [
      'new',
      'theme',
      '--id',
      id,
      if (title.isNotEmpty) ...['--title', title],
      if (language != null && language.isNotEmpty) ...['--lang', language],
      '--',
      course,
      year,
    ],
    paths: ['courses/$course/$year'],
    message: tr('Declarar el tema «{0}» en {1} {2}', [title, course, year]),
  );

  /// Copia documentos de un curso a otro.
  ///
  /// Composición, nunca contenido: el curso de destino **referencia las
  /// mismas unidades**. Es lo que hace útil que una unidad no sepa en qué
  /// asignatura entra -- volver a dar el Tema 1 es copiar su composición, no
  /// su material, y una errata se sigue corrigiendo en un solo sitio.
  ///
  /// Con la lista vacía se copia el curso entero.
  ///
  /// [asId] le cambia el nombre en el destino (uno solo). [independent] hace
  /// que una copia de un tema vinculado deje de estarlo; [withUnits] además
  /// duplica sus lecciones, y entonces el commit lleva las carpetas nuevas.
  Future<void> copyDocuments({
    required String fromCourse,
    required String fromYear,
    required String toCourse,
    required String toYear,
    List<String> documents = const [],
    String asId = '',
    bool independent = false,
    bool withUnits = false,
  }) => _change(
    arguments: [
      'copy',
      '--from',
      '$fromCourse@$fromYear',
      '--to',
      '$toCourse@$toYear',
      // El curso de destino puede existir y no tener carpeta **aquí**: un
      // curso repartido entre repositorios es lo normal, y este solo ve el
      // suyo. La pantalla elige el destino de una lista de cursos que
      // existen, así que si falta es eso y no un dedazo.
      '--create-year',
      if (asId.isNotEmpty && documents.length == 1) ...['--as', asId],
      if (independent) '--independent',
      if (withUnits) '--with-units',
      // Detrás de `--` porque los ids vienen de una pantalla y `argparse`
      // tomaría un `-algo` por una opción.
      '--',
      ...documents,
    ],
    paths: [
      'courses/$toCourse/$toYear',
      if (withUnits) ...['content', 'problems'],
    ],
    message: documents.isEmpty
        ? tr('Copiar {0} {1} entero a {2}', [fromCourse, fromYear, toYear])
        : documents.length == 1
        ? tr('Copiar {0} de {1} a {2}', [documents.single, fromYear, toYear])
        : tr('Copiar {0} documentos de {1} a {2}', [
            documents.length,
            fromYear,
            toYear,
          ]),
  );

  // -- Contenido vinculado -------------------------------------------------
  //
  // Todo por el motor y cerrado en un commit, como el resto: vincular un tema
  // toca el `year.yaml` de dos cursos, un fichero en `shared/documents/` y a
  // veces un `themes.yaml`, y repartir eso en cuatro commits deja cuatro
  // estados intermedios en los que el repositorio se contradice.

  /// Da el mismo tema en otro curso, vinculado.
  Future<void> linkDocument({
    required String fromCourse,
    required String fromYear,
    required String document,
    required String toCourse,
    required String toYear,
    String? asId,
  }) => _change(
    arguments: [
      'link',
      '--from',
      '$fromCourse@$fromYear/$document',
      '--to',
      '$toCourse@$toYear',
      if (asId != null && asId.isNotEmpty) ...['--as', asId],
    ],
    paths: [
      'courses/$fromCourse/$fromYear',
      'courses/$toCourse/$toYear',
      'shared/documents',
    ],
    message: tr(
      'Dar «{0}» también en {1} {2}, vinculado a '
      '{3} {4}',
      [document, toCourse, toYear, fromCourse, fromYear],
    ),
  );

  /// Cambia de sitio una ubicación, sin tocar la identidad del contenido.
  Future<void> moveDocument({
    required String fromCourse,
    required String fromYear,
    required String document,
    required String toCourse,
    required String toYear,
    String? asId,
  }) => _change(
    arguments: [
      'move',
      '--from',
      '$fromCourse@$fromYear/$document',
      '--to',
      '$toCourse@$toYear',
      if (asId != null && asId.isNotEmpty) ...['--as', asId],
    ],
    paths: [
      'courses/$fromCourse/$fromYear',
      'courses/$toCourse/$toYear',
      'shared/documents',
    ],
    message: tr('Mover «{0}» de {1} {2} a {3} {4}', [
      document,
      fromCourse,
      fromYear,
      toCourse,
      toYear,
    ]),
  );

  /// Parte un grupo de ubicaciones sincronizadas en varios.
  ///
  /// [groups] son las que se separan; lo que no se nombre se queda con la
  /// entidad de siempre. Cada grupo es una lista de claves
  /// `asignatura@año/documento`, o `…#posición` para una lección.
  Future<void> splitContent({
    String? content,
    String? unit,
    required List<List<String>> groups,
    required List<String> paths,
    required String message,
    bool deep = false,
  }) => _change(
    arguments: [
      'split',
      if (content != null && content.isNotEmpty) ...['--content', content],
      if (unit != null && unit.isNotEmpty) ...['--unit', unit],
      for (final group in groups) ...['--group', group.join(',')],
      if (deep) '--deep',
    ],
    paths: [...paths, 'shared/documents', 'content', 'problems'],
    message: message,
  );

  /// Da una lección en otro tema, de otra asignatura si hace falta.
  ///
  /// Vinculada por defecto, que es lo que una referencia ha sido siempre: la
  /// lección vive una vez y los dos temas llaman a la misma. Con [duplicate],
  /// una copia con identidad propia.
  Future<void> useUnit({
    required String unit,
    required String toCourse,
    required String toYear,
    required String document,
    bool duplicate = false,
  }) => _change(
    arguments: [
      'use',
      '--unit',
      unit,
      '--in',
      '$toCourse@$toYear/$document',
      if (duplicate) '--duplicate',
    ],
    paths: [
      'courses/$toCourse/$toYear',
      'shared/documents',
      if (duplicate) ...['content', 'problems'],
    ],
    message: duplicate
        ? tr('Duplicar «{0}» en «{1}» de {2} {3}', [
            unit,
            document,
            toCourse,
            toYear,
          ])
        : tr('Dar «{0}» también en «{1}» de {2} {3}', [
            unit,
            document,
            toCourse,
            toYear,
          ]),
  );

  /// Hace independiente una ubicación de un tema vinculado.
  Future<void> unlinkDocument({
    required String course,
    required String year,
    required String document,
  }) => _change(
    arguments: ['unlink', '--at', '$course@$year/$document'],
    paths: ['courses/$course/$year', 'shared/documents'],
    message: tr('Separar «{0}» de {1} {2} del tema compartido', [
      document,
      course,
      year,
    ]),
  );

  /// Pone un id estable a cada lección que no lo tenga.
  ///
  /// La migración. No mueve nada, no renombra nada y no toca el contenido:
  /// escribe una línea `id:` en cada `unit.yaml` que le falte, derivada de la
  /// ruta con un hash, así que dos personas que lo hagan por su cuenta
  /// escriben los mismos ids y el merge no tiene nada que resolver.
  Future<void> writeUnitIds() => _change(
    arguments: const ['ids', '--apply'],
    paths: const ['content', 'problems'],
    message: tr(
      'Poner un id estable a cada lección\n\n'
      'Derivado de la ruta con un hash, así que es el mismo lo haga quien '
      'lo haga. A partir de aquí manda el id y no la ruta: mover una '
      'lección de carpeta ya no rompe quién la usa.',
    ),
  );

  /// Lo que haría [writeUnitIds], sin escribir nada.
  Future<String> previewUnitIds() => compiler.run(const ['ids']);

  // -- Versiones congeladas -------------------------------------------------

  /// Registra una versión congelada: el commit que hay ahora, con nombre.
  ///
  /// El commit que anota la congelación no puede contener su propio hash, así
  /// que apunta al que era HEAD al crearla. Es lo correcto: lo que se congela
  /// es el estado que había, no la línea que lo anota.
  Future<void> addFreeze({
    required String course,
    required String year,
    required String name,
    required String commit,
    String description = '',
  }) => _change(
    arguments: [
      'freeze',
      'add',
      '$course@$year',
      '--name',
      name,
      '--commit',
      commit,
      if (description.isNotEmpty) ...['--description', description],
    ],
    paths: ['courses/$course/$year'],
    message: tr('Congelar «{0}» en {1} {2}', [name, course, year]),
    reindex: false,
  );

  /// Quita una congelación. Ni un commit, ni una rama, ni la historia.
  Future<void> removeFreeze({
    required String course,
    required String year,
    required String id,
    required String name,
  }) => _change(
    arguments: ['freeze', 'remove', '$course@$year', id],
    paths: ['courses/$course/$year'],
    message: tr('Quitar la versión congelada «{0}» de {1} {2}', [
      name,
      course,
      year,
    ]),
    reindex: false,
  );

  Future<void> renameFreeze({
    required String course,
    required String year,
    required String id,
    required String name,
    String? description,
  }) => _change(
    arguments: [
      'freeze',
      'rename',
      '$course@$year',
      id,
      '--name',
      name,
      if (description != null) ...['--description', description],
    ],
    paths: ['courses/$course/$year'],
    message: tr('Renombrar una versión congelada de {0} {1} a «{2}»', [
      course,
      year,
      name,
    ]),
    reindex: false,
  );

  /// Devuelve un tema al estado que tiene en otra versión del repositorio.
  ///
  /// [fromDirectory] es la raíz del árbol de una congelación. El curso entero
  /// y una lección se restauran copiando ficheros --eso lo hace el clon--;
  /// un tema no, porque su composición vive dentro del `year.yaml` entre las
  /// de los demás y hay que sustituir solo su bloque.
  Future<void> restoreDocument({
    required String course,
    required String year,
    required String document,
    required String fromDirectory,
    required String fromLabel,
  }) => _change(
    arguments: ['restore', '--from', fromDirectory, '$course@$year/$document'],
    paths: ['courses/$course/$year', 'shared/documents'],
    message: tr('Restaurar «{0}» de {1} {2} desde «{3}»', [
      document,
      course,
      year,
      fromLabel,
    ]),
    // Sin confirmar, como el resto de restaurar: lo que sale es un cambio
    // pendiente que se revisa y se guarda con el mensaje que quiera quien lo
    // hizo. Restaurar no es una excepción a la regla de que todo cambio es un
    // commit normal; lo que no es, es un commit que aparece solo.
    commit: false,
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
    bool reindex = true,
    bool commit = true,
    Future<void> Function()? write,
  }) async {
    final who = author;
    if (who == null) {
      throw AdminException(
        tr(
          'Para guardar en el historial hace falta un autor. Pon un nombre y un correo en Ajustes.',
        ),
      );
    }

    // Al día antes de tocar. Que no se pueda no para la operación: lo escrito
    // queda en el clon y la barra de sincronización dice lo que falta.
    try {
      await beforeWrite?.call();
    } catch (caught, trace) {
      Diagnostics.instance.note('course_admin.Function', caught, trace);
      // Ya lo cuenta quien puso la llamada.
    }

    // Lo que cambia los ficheros: una orden del motor, o --al deshacer-- traer
    // los de antes desde git.
    var output = '';
    try {
      await write?.call();
      if (arguments.isNotEmpty) output = await compiler.run(arguments);
    } on CompileException catch (error) {
      throw AdminException(error.message, detail: error.detail);
    } on CloneException catch (error) {
      throw AdminException(
        tr('No se pudo traer la versión de antes.'),
        detail: error.stderr.isEmpty ? error.message : error.stderr,
      );
    }

    // El índice, después del cambio. Si falla, el commit se hace igual: los
    // ficheros ya están escritos y dejarlos sin commit sería perder el
    // cambio de vista, que es peor que tener el índice viejo. Se dice, eso
    // sí, porque hasta que se regenere la pantalla no verá lo que se hizo.
    Object? indexProblem;
    // Las congelaciones no entran en el índice de contenido --lo que cambian
    // es un `freezes.yaml`, y el motor lo lee con el curso--, así que
    // regenerar dos mil unidades por ponerle nombre a un commit sería pagar
    // unos segundos por nada. El índice sí cambia, y se escribe igual: por
    // eso la ruta va en el commit aunque no se regenere aquí.
    if (reindex) {
      try {
        await compiler.run(const ['index']);
        onIndexed?.call();
      } on CompileException catch (error) {
        indexProblem = error;
      }
    }

    if (!commit) {
      if (indexProblem != null) {
        throw AdminException(
          tr(
            'El cambio está hecho, pero el índice no se pudo regenerar, así que '
            'la pantalla no lo verá todavía. Ejecuta `didacta index` en el '
            'repositorio.',
          ),
          detail: '$indexProblem',
        );
      }
      return;
    }

    try {
      final committed = await clone.commitPaths(
        paths: [...paths, if (reindex) _index],
        message: message,
        authorName: who.name,
        authorEmail: who.email,
        token: token,
        push: pushOnCommit && token.isNotEmpty,
      );
      if (!committed) {
        throw AdminException(
          tr('El motor no cambió nada, así que no hay nada que guardar.'),
          detail: output.trim(),
        );
      }
      if (indexProblem != null) {
        throw AdminException(
          tr(
            'El cambio está hecho y guardado, pero el índice no se pudo '
            'regenerar, así que la pantalla no lo verá todavía. Ejecuta '
            '`didacta index` en el repositorio.',
          ),
          detail: '$indexProblem',
        );
      }
    } on CloneException catch (error) {
      throw AdminException(
        tr(
          'Los ficheros se han cambiado, pero no se pudieron guardar en el '
          'historial: quedan escritos y sin guardar.',
        ),
        detail: error.stderr.isEmpty ? error.message : error.stderr,
      );
    }
  }
}
