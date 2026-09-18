/// Abrir una versión congelada, compararla y restaurar desde ella.
///
/// La idea que sostiene todo esto: **git ya guarda el contenido de cada
/// commit**. Lo que faltaba no era una copia del repositorio -- dos mil
/// unidades duplicadas por cada septiembre que alguien quiera volver a mirar
/// -- sino una forma de abrir uno de esos commits sin mover el árbol de
/// trabajo. Eso es un worktree, y es de lo único que depende esto.
///
/// Tres cosas que conviene dejar dichas:
///
/// **El índice ya está en el commit.** `generated/` se versiona con el
/// contenido, así que el catálogo de una congelación no hay que reconstruirlo:
/// está ahí, escrito el día que se hizo el commit. Solo se regenera cuando
/// aquel commit es anterior a que el repositorio empezara a versionarlo, y
/// entonces se dice.
///
/// **Se abre en solo lectura.** Nada de lo que hace la aplicación escribe en
/// un worktree de congelación. La pasarela que se le da a las pantallas se
/// niega a guardar y explica por qué, en lugar de fallar al pulsar Guardar.
///
/// **Restaurar no reescribe nada.** Trae el contenido de aquel commit al árbol
/// de trabajo de ahora y lo deja como un cambio pendiente. Ni `reset`, ni
/// force push, ni commits borrados: lo que sale es un commit más, encima.
library;

import '../model/catalogue.dart';
import '../model/course_diff.dart';
import '../model/file_history.dart';
import 'catalogue_source.dart';
import 'compiler.dart';
import 'content_gateway.dart';
import 'local_clone.dart';

/// Una congelación abierta.
class FrozenView {
  const FrozenView({
    required this.freeze,
    required this.directory,
    required this.catalogue,
    required this.repo,
    this.rebuilt = false,
  });

  final Freeze freeze;

  /// El árbol de trabajo donde están sus ficheros.
  final String directory;

  /// El catálogo de aquel commit: sus asignaturas, sus temas, sus lecciones,
  /// sus ids y sus vínculos, tal como estaban.
  final Catalogue catalogue;

  /// De qué repositorio es.
  final String repo;

  /// Si el índice hubo que regenerarlo porque aquel commit no lo traía.
  ///
  /// Se dice: un catálogo reconstruido hoy con el motor de hoy describe el
  /// contenido de entonces, pero no es el fichero que había, y esa diferencia
  /// hay que poder verla.
  final bool rebuilt;

  /// La ruta de un fichero del repositorio dentro de esta versión.
  String fileAt(String path) => '$directory/$path';
}

/// Lo que no se pudo hacer con una congelación, y por qué.
class FrozenException implements Exception {
  const FrozenException(this.message, {this.detail = ''});

  final String message;
  final String detail;

  @override
  String toString() => detail.isEmpty ? message : '$message\n\n$detail';
}

/// Cómo va la apertura. Se cuenta porque puede tardar: un commit que no está
/// en un clon shallow hay que traerlo, y una descarga silenciosa es
/// indistinguible de un cuelgue.
enum FrozenStep {
  /// Mirando si el commit está aquí.
  looking,

  /// Pidiéndolo, lo justo.
  fetchingCommit,

  /// Cavando más historia porque el servidor no da commits sueltos.
  fetchingHistory,

  /// Trayendo la historia entera: el último recurso.
  fetchingEverything,

  /// Preparando el árbol de trabajo.
  preparing,

  /// Regenerando el índice, porque aquel commit no lo traía.
  rebuilding,

  /// Leyendo el catálogo.
  reading,
}

/// Abre, compara y restaura. Sin estado: lo que hay que recordar --qué
/// congelación se está mirando-- lo lleva la sesión.
class Frozen {
  const Frozen({
    required this.clone,
    required this.repo,
    this.compiler,
    this.token = '',
  });

  final LocalClone clone;

  /// De qué repositorio es este clon.
  final String repo;

  /// El motor, para el caso en que haya que regenerar el índice. Sin él una
  /// congelación anterior al índice versionado se abre a medias y lo dice.
  final Compiler? compiler;

  final String token;

  /// Abre una congelación: trae el commit si hace falta, prepara el árbol y
  /// lee el catálogo que hay dentro.
  Future<FrozenView> open(
    Freeze freeze, {
    void Function(FrozenStep step) onStep = _ignore,
  }) async {
    if (freeze.commit.isEmpty) {
      throw const FrozenException(
        'Esta versión congelada no dice a qué commit apunta.',
      );
    }

    onStep(FrozenStep.looking);
    if (!await clone.hasCommit(freeze.commit)) {
      try {
        await clone.fetchCommit(
          freeze.commit,
          token: token,
          onStep: (depth) => onStep(switch (depth) {
            FetchDepth.justTheCommit => FrozenStep.fetchingCommit,
            FetchDepth.deeper => FrozenStep.fetchingHistory,
            FetchDepth.everything => FrozenStep.fetchingEverything,
          }),
        );
      } on CloneException catch (error) {
        throw FrozenException(
          'No se pudo traer el commit de «${freeze.name}».',
          detail: error.stderr.isEmpty ? error.message : error.stderr,
        );
      }
    }

    onStep(FrozenStep.preparing);
    final Worktree tree;
    try {
      tree = await clone.worktreeAt(freeze.commit);
    } on CloneException catch (error) {
      throw FrozenException(
        'No se pudo preparar «${freeze.name}» para mirarla.',
        detail: error.stderr.isEmpty ? error.message : error.stderr,
      );
    }

    var rebuilt = false;
    onStep(FrozenStep.reading);
    var source = CatalogueSource.inClone(tree.directory, repo: repo);
    if (source == null) {
      throw const FrozenException(
        'Esta plataforma no puede leer una versión congelada del disco.',
      );
    }

    Catalogue catalogue;
    try {
      catalogue = await source.load();
    } catch (first) {
      // Aquel commit es anterior a que el repositorio versionara su índice.
      // Se reconstruye con el motor, sobre el árbol de la congelación, y se
      // dice -- porque lo que se enseña entonces describe el contenido de
      // entonces pero no es el fichero que había.
      final engine = compiler;
      if (engine == null) {
        throw FrozenException(
          '«${freeze.name}» no trae el índice de aquel día, y sin el motor no '
          'se puede reconstruir. Elige el motor en Ajustes.',
          detail: '$first',
        );
      }
      onStep(FrozenStep.rebuilding);
      try {
        // `--root` y no otro compilador: el motor ya sabe trabajar sobre
        // una raíz que no es la suya, y el árbol de una congelación es
        // exactamente eso -- un repositorio de contenido completo parado en
        // otro commit.
        await engine.run(['--root', tree.directory, 'index']);
      } on CompileException catch (error) {
        throw FrozenException(
          'No se pudo reconstruir el catálogo de «${freeze.name}».',
          detail: error.detail.isEmpty ? error.message : error.detail,
        );
      }
      rebuilt = true;
      source = CatalogueSource.inClone(tree.directory, repo: repo)!;
      catalogue = await source.load();
    }

    return FrozenView(
      freeze: freeze,
      directory: tree.directory,
      catalogue: catalogue,
      repo: repo,
      rebuilt: rebuilt,
    );
  }

  static void _ignore(FrozenStep step) {}

  /// Cierra una congelación: quita su árbol de la caché.
  ///
  /// Solo si no la usa nadie más. Dos congelaciones del mismo commit comparten
  /// árbol, y quitarlo por cerrar una dejaría a la otra sin nada que abrir.
  Future<void> close(Freeze freeze, {List<Freeze> others = const []}) async {
    if (others.any(
      (other) => other.id != freeze.id && other.commit == freeze.commit,
    )) {
      return;
    }
    await clone.removeWorktree(freeze.commit);
  }

  /// Vacía la caché de árboles. No pierde nada: se vuelven a crear.
  Future<int> clearCache() => clone.clearWorktrees();

  /// Qué cambió entre dos versiones, en términos de Didacta.
  ///
  /// [from] y [to] son commits; `HEAD` vale como cualquiera de los dos, que es
  /// lo que hace que «comparar con la versión actual» sea el mismo código.
  Future<CourseDiff> compare({
    required String from,
    required String to,
    String course = '',
    String year = '',
  }) async {
    // Limitado al curso cuando se pregunta por uno: el contenido cambia por
    // todas partes, y enseñar el repositorio entero al comparar dos versiones
    // de una asignatura es enterrar la respuesta.
    //
    // `content/` y `problems/` entran igual, porque un tema que no cambió de
    // composición puede haber cambiado entero por dentro -- que es justo el
    // caso que hay que ver antes de una clase.
    final paths = <String>[
      if (course.isNotEmpty && year.isNotEmpty) 'courses/$course/$year',
      if (course.isNotEmpty && year.isEmpty) 'courses/$course',
      'shared/documents',
      'content',
      'problems',
    ];
    final tree = await clone.changesBetween(
      from: from,
      to: to,
      paths: course.isEmpty ? const [] : paths,
    );
    String? before;
    String? after;
    if (course.isNotEmpty && year.isNotEmpty) {
      final path = 'courses/$course/$year/year.yaml';
      before = await clone.fileAt(sha: from, path: path);
      after = await clone.fileAt(sha: to, path: path);
    }
    return readCourseDiff(tree, before: before, after: after);
  }

  /// El diff de un fichero entre dos versiones.
  Future<FileDiff> diffOf({
    required String from,
    required String to,
    required String path,
    int context = 3,
  }) => clone.diffBetween(from: from, to: to, path: path, context: context);

  /// Qué haría restaurar, sin tocar nada.
  Future<List<TreeChange>> previewRestore({
    required Freeze freeze,
    required List<String> paths,
  }) => clone.previewRestore(sha: freeze.commit, paths: paths);

  /// Trae el contenido de aquel commit al árbol de trabajo de ahora.
  ///
  /// Y lo deja ahí. Confirmarlo es otra decisión y la toma quien llama, con el
  /// mensaje que quiera: restaurar no es una excepción a la regla de que todo
  /// cambio es un commit normal.
  Future<List<TreeChange>> restore({
    required Freeze freeze,
    required List<String> paths,
  }) => clone.restoreFrom(sha: freeze.commit, paths: paths);
}

/// La pasarela de una congelación: lee del árbol y se niega a escribir.
///
/// Se niega **diciendo por qué**, que es la diferencia entre una pantalla que
/// explica que esto es una foto de septiembre y un botón de guardar que falla.
class FrozenGateway extends ContentGateway {
  const FrozenGateway({required this.view});

  final FrozenView view;

  @override
  GatewayKind get kind => GatewayKind.clone;

  @override
  bool get canWrite => false;

  @override
  String describe() =>
      'Versión congelada «${view.freeze.name}» (${view.freeze.shortCommit}). '
      'Solo lectura.';

  @override
  Future<ContentFile> read(String path) async {
    final clone = LocalClone(directory: view.directory);
    try {
      final found = await clone.readFile(path);
      return ContentFile(path: path, text: found.text, sha: found.sha);
    } on CloneException catch (error) {
      throw ContentException(error.message, kind: ContentFailure.missing);
    }
  }

  @override
  Future<String> save({
    required String path,
    required String text,
    required String sha,
    required String message,
  }) async => throw ContentException(
    'Estás viendo «${view.freeze.name}», que es una versión congelada: es el '
    'estado de un commit y no se edita. Vuelve a la versión actual para '
    'escribir, o restaura esto desde aquí.',
    kind: ContentFailure.forbidden,
  );

  @override
  Future<void> saveAll({
    required List<({String path, String text, String sha})> files,
    required String message,
  }) async => throw ContentException(
    'Estás viendo «${view.freeze.name}», que es una versión congelada y no se '
    'edita.',
    kind: ContentFailure.forbidden,
  );
}
