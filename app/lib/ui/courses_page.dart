/// The subjects, and the years each has run.
///
/// A course is not a folder of content -- it holds no content at all. It is a
/// selection and an order over units that live elsewhere, so this screen shows
/// what a year *consists of* rather than what it contains: how many documents,
/// how many unit references, and how much of it is shared with other years.
///
/// The most-recent year first, because the one being taught is the one you
/// want.
library;

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/compiler.dart' show ExistingOutput;
import '../data/course_admin.dart';
import '../data/diagnostics.dart';
import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'add_repository.dart';
import 'build_console.dart';
import 'command_palette.dart';
import 'course_admin_ui.dart';
import 'freezes.dart';
import 'export_actions.dart';
import 'export_year.dart';
import 'problem.dart';
import 'publish_folder.dart';
import 'recent_changes.dart';
import 'review_panel.dart';
import 'shell.dart';
import 'build_button.dart';
import 'edit_course.dart';
import 'manage_degrees.dart';
import 'heading_title.dart';
import 'theme.dart';
import 'tour.dart';
import 'working.dart';
import '../l10n/tr.dart';

/// Qué se enseña de la lista: lo que se mira, lo que se escondió, o todo.
///
/// Tres y no una casilla de «ver ocultas», porque son tres preguntas
/// distintas: «lo que doy» --lo de todos los días--, «qué escondí» --para
/// deshacerlo-- y «todo», que es la lista de verdad. Sin la segunda, ocultar
/// sería un viaje sin vuelta.
enum CoursesView { visible, hidden, all }

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  /// La carpeta de reparto, si hay: con ella cada curso tiene «Publicar».
  /// Se lee al abrir la pantalla, que es también al volver de Ajustes.
  String? _publishFolder;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      final session = context.read<Session>();
      final found = await session.preferences.publishFolder();
      if (mounted && found != _publishFolder) {
        setState(() => _publishFolder = found);
      }
    });
  }

  /// Qué grado se está mirando. Null es «todos».
  ///
  /// De la pantalla y no de las preferencias: es una forma de buscar, no una
  /// decisión sobre el sitio de trabajo, y volver mañana y no encontrar media
  /// lista porque quedó un filtro puesto es de las peores sorpresas que puede
  /// dar una aplicación.
  String? _degree;

  /// Qué se está mirando: lo visible, lo oculto o todo.
  ///
  /// De las preferencias, al revés que el grado. Parecían la misma clase de
  /// filtro y no lo son: el grado es una forma de buscar un rato, y esto es
  /// la lista con la que se trabaja. Quien se pone a ordenar las asignaturas
  /// se queda un rato en «las ocultas», y volver de un curso para encontrarse
  /// otra vez «las que doy» convierte esa tarde en un baile de clics.
  ///
  /// Un nombre que no se reconozca --un fichero de otra versión-- vuelve a
  /// «las que doy» en lugar de dejar la pantalla sin lista.
  CoursesView _viewOf(Session session) => CoursesView.values.firstWhere(
    (view) => view.name == session.coursesView,
    orElse: () => CoursesView.visible,
  );

  // Lo marcado, lo oculto y lo plegado avisan por las preferencias de la
  // biblioteca, no por la sesión.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).libraryPrefs,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) =>
      PaletteCommands(commands: _paletteCommands, child: _courses(context));

  /// Lo que ofrece la paleta de órdenes en la lista de asignaturas.
  List<PaletteCommand> _paletteCommands(BuildContext context) {
    final session = sessionOf(context);
    return [
      if (session.admin() != null)
        PaletteCommand(
          title: tr('Nueva asignatura'),
          keywords: tr('crear añadir curso'),
          icon: Icons.add,
          run: () => _createCourse(session),
        ),
      if (session.admin() != null)
        PaletteCommand(
          title: tr('Gestionar los grados'),
          keywords: tr('titulaciones grado agrupar'),
          icon: Icons.school_outlined,
          run: () => _manageDegrees(session),
        ),
      if (session.canSearchText)
        PaletteCommand(
          title: tr('Cambios recientes'),
          keywords: tr('historial últimos deshacer'),
          icon: Icons.history,
          run: () => showRecentChanges(this.context, session),
        ),
      for (final view in CoursesView.values)
        if (view.name != session.coursesView)
          PaletteCommand(
            title: switch (view) {
              CoursesView.visible => tr('Ver las asignaturas que doy'),
              CoursesView.hidden => tr('Ver las asignaturas ocultas'),
              CoursesView.all => tr('Ver todas las asignaturas'),
            },
            keywords: tr('filtro lista'),
            icon: Icons.filter_list,
            run: () => session.setCoursesView(view.name),
          ),
    ];
  }

  Widget _courses(BuildContext context) {
    final session = watchSession(context);
    // Por título. El orden lo decide la sesión: si cada lista lo hiciera por
    // su cuenta, acabarían discrepando.
    final all = session.sortedCourses;
    final view = _viewOf(session);
    final degrees = session.catalogue.degrees;
    // Un grado que se filtra y luego deja de existir --se cierra el
    // repositorio que lo declaraba-- no puede dejar la lista vacía sin
    // explicación: si ya no está, se mira todo.
    final filtering = degrees.any((degree) => degree.id == _degree);
    final byDegree = filtering
        ? [
            for (final course in all)
              if (course.degreeId == _degree) course,
          ]
        : all;
    final courses = [
      for (final course in byDegree)
        if (_shows(session, course)) course,
    ];
    final hidden = byDegree.length - courses.length;

    final years = courses.fold<int>(0, (sum, c) => sum + c.years.length);
    final documents = courses.fold<int>(
      0,
      (sum, c) =>
          sum + c.years.values.fold<int>(0, (n, y) => n + y.documents.length),
    );

    return Column(
      children: [
        PageHeader(
          title: tr('Asignaturas'),
          subtitle: filtering
              ? tr('{0} de {1} asignaturas', [courses.length, all.length])
              : [
                  courses.length == 1
                      ? tr('1 asignatura')
                      : tr('{0} asignaturas', [courses.length]),
                  years == 1
                      ? tr('1 curso académico')
                      : tr('{0} cursos académicos', [years]),
                  documents == 1
                      ? tr('1 documento')
                      : tr('{0} documentos', [documents]),
                  if (hidden > 0 && view == CoursesView.visible)
                    tr('{0} sin enseñar', [hidden]),
                ].join(' · '),
          actions: [
            // Qué se mira. Primero, porque decide lo que hay debajo.
            TourTarget(
              id: 'courses-view',
              child: _ViewFilter(
                view: view,
                onChanged: (value) => session.setCoursesView(value.name),
              ),
            ),
            // Filtrar por grado. Solo con más de uno declarado: con ninguno o
            // con uno no filtra nada, y un desplegable de una opción es un
            // control que enseña que no hay nada que elegir.
            if (degrees.length > 1)
              _DegreeFilter(
                degrees: degrees,
                chosen: filtering ? _degree : null,
                language: session.language,
                total: all.length,
                onChanged: (value) => setState(() => _degree = value),
              ),
            // Lo que se ha guardado estos días, y deshacerlo. Aquí, que es
            // por donde se entra: «ayer quité el curso que no era» se busca
            // en la lista de asignaturas.
            if (session.canSearchText)
              IconButton(
                key: const Key('recent-changes'),
                tooltip: tr('Cambios recientes'),
                icon: const Icon(Icons.history, size: 19),
                onPressed: () => showRecentChanges(context, session),
              ),
            if (session.admin() != null)
              FilledButton.icon(
                key: const Key('new-course'),
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr('Nueva asignatura')),
                onPressed: () => _createCourse(session),
              ),
          ],
        ),
        // Con la interfaz Completa, también sin ninguno: la tira es la única
        // puerta a crear el primero, y escondida hasta que hubiera uno no se
        // podía crear ninguno.
        if (degrees.isNotEmpty ||
            session.catalogue.undeclaredDegrees.isNotEmpty ||
            (session.completeInterface && session.admin() != null))
          _DegreeStrip(
            session: session,
            onManage: () => _manageDegrees(session),
          ),
        if (courses.isEmpty)
          Expanded(
            child: _NoCourses(
              session: session,
              anyAtAll: all.isNotEmpty,
              filtering: filtering,
              hidden: hidden,
              onCreate: session.admin() != null
                  ? () => _createCourse(session)
                  : null,
              onShowHidden: () =>
                  session.setCoursesView(CoursesView.hidden.name),
              onClearFilter: () => setState(() => _degree = null),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: courses.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              // La primera, marcada para el tour: es la que se enseña como «una
              // asignatura», y marcar todas repetiría la clave.
              itemBuilder: (context, index) => TourTarget.first(
                id: 'courses-first',
                when: index == 0,
                child: _CourseTile(
                  first: index == 0,
                  course: courses[index],
                  session: session,
                  view: view,
                  admin: session.admin() != null,
                  onDuplicate: () => _duplicateYear(session, courses[index]),
                  onCopy: (year) => _copyYear(session, courses[index], year),
                  onBuild: (year, choice) => _buildYear(
                    session,
                    courses[index],
                    year,
                    languages: choice.languages,
                    everyVersion: choice.everyVersion,
                  ),
                  onExport: (year) =>
                      _exportYear(session, courses[index], year),
                  onPublish: _publishFolder == null
                      ? null
                      : (year) => _exportYear(
                          session,
                          courses[index],
                          year,
                          publishTo: publishTargetFor(
                            _publishFolder!,
                            courses[index].title(session.language),
                            year,
                          ),
                        ),
                  onRemove: () => _removeCourse(session, courses[index]),
                  onEditTitle: () => _editCourse(session, courses[index]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Si esta asignatura entra en lo que se está mirando.
  ///
  /// En «ocultas» entra también la que no lo está pero tiene algún curso
  /// escondido: si no, sus cursos ocultos no se podrían volver a enseñar
  /// desde ningún sitio, que es la forma de que ocultar fuese un viaje sin
  /// vuelta.
  bool _shows(Session session, Course course) => switch (_viewOf(session)) {
    CoursesView.all => true,
    CoursesView.visible => !session.isHiddenCourse(course.id),
    CoursesView.hidden =>
      session.isHiddenCourse(course.id) ||
          course.years.keys.any(
            (year) => session.isHiddenYear(course.id, year),
          ),
  };

  Future<void> _createCourse(Session session) async {
    final catalogue = session.catalogue;
    final answer =
        await showDialog<
          ({String id, String title, String? from, String language})
        >(
          context: context,
          builder: (context) => NewCourseDialog(
            courses: catalogue.courses,
            languages: [
              for (final option in session.languageChoices) option.code,
            ],
            defaultLanguage: catalogue.defaultLanguage,
          ),
        );
    if (answer == null || !mounted) return;

    // Dónde se crea, antes de crearla: con varios repositorios abiertos,
    // adivinarlo es crear la asignatura en el sitio equivocado.
    final repo = await pickRepository(context, session);
    if (repo == null || !mounted) return;

    final done = await runAdmin(
      context,
      session,
      repo: repo,
      (admin) => admin.createCourse(
        id: answer.id,
        title: answer.title,
        from: answer.from,
        language: answer.language,
      ),
      done: tr('Asignatura «{0}» creada.', [answer.title]),
    );
    // El catálogo se genera aparte, así que sin recargarlo la pantalla no ve
    // lo que acaba de crear.
    if (done) await session.reloadCatalogue();
  }

  /// Copia documentos de un curso de esta asignatura a otro.
  /// Compila un curso entero: todos sus documentos, todas sus versiones.
  ///
  /// Puede ser media hora, así que abre el registro con su barra: lo que hace
  /// falta saber mientras tanto es por cuál va y que no se ha colgado.
  Future<void> _buildYear(
    Session session,
    Course course,
    String year, {
    List<String> languages = const [],
    bool everyVersion = false,
  }) async {
    final entry = course.years[year];
    if (entry == null) return;
    final wanted = [
      for (final document in entry.documents)
        (
          repo: document.repo,
          course: course.id,
          year: year,
          id: document.id,
          title: document.title(session.language),
        ),
    ];
    if (wanted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('{0} no tiene documentos que compilar.', [year])),
        ),
      );
      return;
    }
    final title = '${course.title(session.language)} · $year';
    if (!await confirmBigBuild(
          context,
          documents: wanted.length,
          what: title,
          languages: languages,
        ) ||
        !mounted) {
      return;
    }
    unawaited(showBuildConsole(context, session.buildConsole));
    await session.buildDocuments(
      wanted,
      title: title,
      languages: languages,
      everyVersion: everyVersion,
    );
  }

  /// Las titulaciones: verlas, declararlas y renombrarlas.
  ///
  /// Desde aquí y no desde Ajustes porque un grado es una clasificación del
  /// material, como un tema, y se toca mientras se mira la lista que agrupa.
  Future<void> _manageDegrees(Session session) => showDegrees(context, session);

  /// La ficha de la asignatura: nombre, idiomas y titulación.
  ///
  /// Las tres en un sitio porque son la misma decisión. Los idiomas estaban en
  /// Ajustes, en una lista de todas las asignaturas, lo cual obligaba a salir
  /// de donde se trabaja para cambiar algo de la que se tiene delante.
  ///
  /// Todo va a `course.yaml`, y a los de **todos** los repositorios que la
  /// declaran: una asignatura repartida tiene un fichero en cada uno.
  Future<void> _editCourse(Session session, Course course) async {
    final answer = await editCourse(
      context,
      course: course,
      // Lo que **se puede** escribir en su `course.yaml`, no los diez a los
      // que Didacta sabe imprimir: una asignatura no puede darse en un idioma
      // que su repositorio no mantiene, y el motor la rechaza entera si lo
      // dice. Más lo que la asignatura ya declara, que nunca se esconde.
      options: session.languagesToEdit(
        allowed: session.catalogue.languagesAvailableTo(course),
        declared: course.languages,
      ),
      degrees: session.catalogue.degrees,
      language: session.language,
    );
    if (answer == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    var touched = 0;
    try {
      touched += await session.setCourseTitles(
        course: course.id,
        titles: answer.titles,
      );
      if (!_sameLanguages(course.languages, answer.languages)) {
        touched += await session.setCourseLanguages(
          course: course.id,
          languages: answer.languages,
        );
      }
      if (answer.degree != course.degreeId) {
        touched += await session.setCourseDegree(
          course: course.id,
          degree: answer.degree,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            touched == 0
                ? tr('No ha cambiado nada.')
                : tr('Guardado en el historial.'),
          ),
        ),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    }
  }

  /// Si dos listas de idiomas dicen lo mismo, en el orden que sea.
  ///
  /// Para no escribir `course.yaml` --ni hacer un commit-- por abrir la ficha
  /// y cerrarla sin tocar nada.
  static bool _sameLanguages(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  /// Saca un curso a una carpeta, para repartirlo.
  /// Exportar un curso: a una carpeta que se pide, o --con [publishTo]-- a
  /// la suya dentro de la carpeta de reparto, sin preguntar.
  Future<void> _exportYear(
    Session session,
    Course course,
    String year, {
    String? publishTo,
  }) async {
    final entry = course.years[year];
    if (entry == null) return;

    // Los idiomas de la asignatura, y si no los declara, los del catálogo:
    // preguntar por tres cuando la asignatura se da en uno llena la pantalla
    // de opciones que no son.
    final languages = session.languagesIn(course.id);

    // Lo que hay compilado, para avisar de lo viejo antes de repartirlo. De
    // cada repositorio del curso; si alguno no contesta, no se avisa de nada
    // antes que avisar a medias.
    Map<String, List<ExistingOutput>>? outputs = {};
    for (final repo in {for (final d in entry.documents) d.repo}) {
      final compiler = session.compiler(repo: repo);
      try {
        if (compiler == null) throw StateError(tr('sin motor'));
        outputs?.addAll(await compiler.documentOutputs('${course.id}@$year'));
      } catch (caught, trace) {
        Diagnostics.instance.note('courses_page._exportYear', caught, trace);
        outputs = null;
      }
    }
    if (!mounted) return;

    final answer = await showDialog<ExportRequest>(
      context: context,
      builder: (context) => ExportYearDialog(
        course: course,
        year: year,
        entry: entry,
        languages: languages,
        language: session.language,
        outputs: outputs,
        publishTo: publishTo,
        reveals: {
          for (final template in session.catalogue.templatesInUse)
            template.id: template.reveals,
        },
      ),
    );
    if (answer == null || !mounted) return;

    // Revisar antes de repartir: lo que el motor encuentra --una referencia
    // rota, una traducción desactualizada-- se ve ahora y no en el aula.
    // Solo se enseña si hay algo, y se puede seguir igual.
    final everything = answer.documents.length == entry.documents.length;
    for (final repo in {
      for (final document in entry.documents)
        if (answer.documents.contains(document.id)) document.repo,
    }) {
      final go = await reviewBeforeExport(
        context,
        session,
        repo: repo,
        within: everything
            ? ['${course.id}@$year']
            : [
                for (final document in entry.documents)
                  if (document.repo == repo &&
                      answer.documents.contains(document.id))
                    '${course.id}@$year/${document.id}',
              ],
      );
      if (!go || !mounted) return;
    }

    // Donde se exportó la última vez esta asignatura: el aula virtual de cada
    // una tiene su carpeta, y buscarla cada vez es la mitad del trabajo. Al
    // publicar no se pregunta: la carpeta es la de reparto.
    final String? destination;
    if (publishTo != null) {
      destination = publishTo;
    } else {
      final remembered = await session.preferences.exportFolder(course.id);
      if (!mounted) return;
      destination = await getDirectoryPath(
        initialDirectory: remembered,
        confirmButtonText: tr('Exportar aquí'),
      );
      if (destination == null || !mounted) return;
      await session.preferences.setExportFolder(course.id, destination);
    }
    if (!mounted) return;

    // Compilar primero, si se pidió: todo, o solo lo que estaba viejo. Con su
    // registro y su barra, porque puede ser media hora.
    if (answer.rebuild || answer.rebuildOnly.isNotEmpty) {
      final wanted = [
        for (final document in entry.documents)
          if (answer.rebuild
              ? answer.documents.contains(document.id)
              : answer.rebuildOnly.contains(document.id))
            (
              repo: document.repo,
              course: course.id,
              year: year,
              id: document.id,
              title: document.title(session.language),
            ),
      ];
      unawaited(showBuildConsole(context, session.buildConsole));
      await session.buildDocuments(
        wanted,
        title: '${course.title(session.language)} · $year',
        // En los idiomas que se van a exportar, no en el propio de cada
        // documento: recompilar y que siga faltando la mitad de lo que se
        // marcó es exactamente lo que la casilla existe para evitar.
        languages: answer.languages,
      );
      if (!mounted) return;
    }

    // Un repositorio por vez: cada documento vive en el suyo y el motor se
    // lanza contra una raíz. Lo que salga se junta en la misma carpeta, que
    // es lo que se quiere llevar.
    final repos = {
      for (final document in entry.documents)
        if (answer.documents.contains(document.id)) document.repo,
    };
    final copied = <String>[];
    final missing = <String>[];
    final withheld = <String>[];
    Object? failure;
    // Uno para todo el curso, aunque salga de dos repositorios: el segundo
    // añade al que empezó el primero.
    final zip = answer.zip
        ? '$destination/${zipNameFor(course.title(session.language), year)}'
        : null;
    var zipped = false;

    for (final repo in repos) {
      final compiler = session.compiler(repo: repo);
      if (compiler == null) continue;
      try {
        final result = await compiler.exportCourse(
          where: '${course.id}@$year',
          to: destination,
          languages: answer.languages,
          documents: [
            for (final document in entry.documents)
              if (document.repo == repo &&
                  answer.documents.contains(document.id))
                document.id,
          ],
          reach: answer.reach,
          zip: zip,
          appendZip: zipped,
          html: answer.html,
        );
        zipped = zipped || result.zip != null;
        copied.addAll(result.copied);
        missing.addAll(result.missing);
        withheld.addAll(result.withheld);
      } catch (error) {
        failure ??= error;
      }
    }
    if (!mounted) return;

    if (failure != null && copied.isEmpty) {
      showProblem(context, failure);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          exportSummary(
            copied: copied.length,
            missing: missing.length,
            withheld: withheld.length,
            to: destination,
            zip: zipped ? zip : null,
          ),
        ),
        duration: const Duration(seconds: 7),
      ),
    );
  }

  Future<void> _copyYear(Session session, Course course, String year) async {
    final entry = course.years[year];
    if (entry == null) return;

    final answer = await showDialog<CopyRequest>(
      context: context,
      builder: (context) => CopyYearDialog(
        course: course,
        year: year,
        entry: entry,
        language: session.language,
        courses: session.catalogue.courses,
      ),
    );
    if (answer == null || !mounted) return;

    // Agrupados por repositorio, y cada grupo se copia **dentro del suyo**.
    //
    // Un documento y las unidades que llama viven juntos: copiarlo al
    // repositorio de al lado dejaría sus referencias fuera de alcance, y
    // compilaría aquí --donde están los dos abiertos-- y no en la máquina de
    // quien solo tenga uno. Si el curso de destino todavía no existe en ese
    // repositorio, el motor lo crea vacío: que no tenga carpeta allí no
    // significa que no exista, significa que ese repositorio aún no aportaba
    // nada a él.
    final byRepo = <String, List<String>>{};
    for (final id in answer.documents) {
      final document = entry.documents
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      byRepo.putIfAbsent(document?.repo ?? '', () => []).add(id);
    }

    var done = false;
    for (final group in byRepo.entries) {
      done = await runAdmin(
        context,
        session,
        (admin) => admin.copyDocuments(
          fromCourse: course.id,
          fromYear: year,
          toCourse: answer.toCourse.isEmpty ? course.id : answer.toCourse,
          toYear: answer.toYear,
          documents: group.value,
        ),
        repo: group.key,
        done: group.value.length == 1
            ? tr('«{0}» copiado a {1}.', [group.value.single, answer.toYear])
            : tr(
                '{0} documentos copiados a '
                '{1}.',
                [group.value.length, answer.toYear],
              ),
      );
      if (!done || !mounted) break;
    }
    if (done) await session.reloadCatalogue();
  }

  Future<void> _duplicateYear(Session session, Course course) async {
    final answer = await showDialog<({String year, String from, bool freeze})>(
      context: context,
      builder: (context) => DuplicateYearDialog(course: course),
    );
    if (answer == null || !mounted) return;

    // En cada repositorio que tiene algo del año de origen: en una
    // asignatura repartida entre teoría y problemas, duplicar solo en el
    // primero dejaba el curso nuevo sin la mitad. Uno vacío va al primero
    // donde vive la asignatura, que es donde lo buscaría cualquiera.
    final from = course.years[answer.from];
    final repos = answer.from.isEmpty || from == null
        ? <String?>[course.sources.keys.firstOrNull]
        : <String?>[...from.presentIn];

    // La congelación, antes de copiar y en los mismos repositorios: apunta a
    // lo último guardado de cada uno, que es el curso tal como quedó.
    final freeze = answer.freeze && from != null;
    final freezeName = freeze ? _freezeName(from) : '';

    final done = await runAdminIn(
      context,
      session,
      repos,
      (admin, _) async {
        if (freeze) {
          await admin.addFreeze(
            course: course.id,
            year: answer.from,
            name: freezeName,
            commit: await admin.clone.head(),
            description: tr('Al crear el curso {0}.', [answer.year]),
          );
        }
        await admin.duplicateYear(
          course: course.id,
          year: answer.year,
          from: answer.from,
        );
      },
      done: answer.from.isEmpty
          ? tr('Curso {0} creado, vacío.', [answer.year])
          : freeze
          ? tr(
              'Curso {0} creado, copiado de {1}, y '
              '{2} congelado como «{3}».',
              [answer.year, answer.from, answer.from, freezeName],
            )
          : tr('Curso {0} creado, copiado de {1}.', [answer.year, answer.from]),
    );
    if (done) await session.reloadCatalogue();
  }

  /// «Tal como quedó», o con un número si ese nombre ya está: un curso que
  /// se borró y se volvió a crear dejó la primera congelación en su sitio.
  static String _freezeName(CourseYear year) {
    final base = tr('Tal como quedó');
    final taken = {for (final freeze in year.freezes) freeze.name};
    if (!taken.contains(base)) return base;
    var n = 2;
    while (taken.contains('$base ($n)')) {
      n += 1;
    }
    return '$base ($n)';
  }

  Future<void> _removeCourse(Session session, Course course) async {
    // De todos los repositorios donde vive: quitarla solo del primero dejaba
    // la otra mitad de una asignatura repartida, que seguía saliendo en la
    // lista como si no se hubiera quitado.
    final repos = <String?>[...course.sources.keys];
    if (repos.isEmpty) repos.add(null);
    final admins = [for (final repo in repos) session.admin(repo: repo)];
    if (admins.any((admin) => admin == null)) return;

    final confirmed = await confirmRemoval(
      context,
      title: tr('¿Quitar «{0}»?', [course.title(session.language)]),
      freezes: course.years.values.fold(
        0,
        (sum, year) => sum + year.freezes.length,
      ),
      preview: () async => RemovalPreview.across([
        for (final admin in admins) await admin!.previewRemoveCourse(course.id),
      ]),
      warning: tr(
        'Las unidades no se tocan: siguen en la biblioteca y en las demás '
        'asignaturas que las usen. Lo que se pierde es la selección y el '
        'orden de esta.',
      ),
    );
    if (!confirmed || !mounted) return;

    // El HEAD de cada repositorio justo antes, que es a lo que vuelve
    // «Deshacer».
    final heads = <String?, String>{};
    final title = course.title(session.language);
    final root = Navigator.of(context, rootNavigator: true).context;
    final done = await runAdminIn(
      context,
      session,
      repos,
      (admin, repo) async {
        heads[repo] = await admin.clone.head();
        await admin.removeCourse(course.id, title: title);
      },
      done: tr('Asignatura «{0}» quitada. Queda en el historial.', [title]),
      onUndo: () => undoAdminIn(
        root,
        session,
        heads,
        paths: ['courses/${course.id}'],
        message: tr('Deshacer: quitar la asignatura «{0}»', [title]),
        done: tr('«{0}» ha vuelto.', [title]),
      ),
    );
    if (done) await session.reloadCatalogue();
  }
}

/// Lo que se enseña cuando no hay ninguna asignatura que enseñar.
///
/// Era una lista en blanco con «0 asignaturas» encima, que no dice si no hay
/// ninguna, si están ocultas o si las esconde un filtro, y no ofrece nada.
/// Aquí dice cuál de las tres es, con la salida de cada una.
class _NoCourses extends StatefulWidget {
  const _NoCourses({
    required this.session,
    required this.anyAtAll,
    required this.filtering,
    required this.hidden,
    required this.onCreate,
    required this.onShowHidden,
    required this.onClearFilter,
  });

  final Session session;

  /// Si hay alguna asignatura, aunque no se vea.
  final bool anyAtAll;
  final bool filtering;
  final int hidden;
  final VoidCallback? onCreate;
  final VoidCallback onShowHidden;
  final VoidCallback onClearFilter;

  @override
  State<_NoCourses> createState() => _NoCoursesState();
}

class _NoCoursesState extends State<_NoCourses> {
  bool _working = false;
  String _doing = '';

  late final RepositoryAdder _adder = RepositoryAdder(
    session: widget.session,
    onBusy: (working) {
      if (mounted) setState(() => _working = working);
    },
    onStep: (what) {
      if (mounted) setState(() => _doing = what);
    },
    onProgress: (_) {},
    onProblem: (problem) {
      if (mounted && problem != null) showProblem(context, problem);
    },
  );

  @override
  Widget build(BuildContext context) {
    final (title, text) = widget.filtering
        ? (
            tr('Ninguna asignatura en esta titulación'),
            tr('Quita el filtro para verlas todas.'),
          )
        : widget.anyAtAll
        ? (
            widget.hidden == 1
                ? tr('La única asignatura está oculta')
                : tr('Todas las asignaturas están ocultas'),
            tr(
              'Las escondiste de la lista, pero siguen ahí. Se vuelven a '
              'enseñar desde «Las ocultas».',
            ),
          )
        : (
            tr('Todavía no hay ninguna asignatura'),
            tr(
              'Crea la primera, o prueba Didacta con un ejemplo: una '
              'asignatura pequeña, con un tema, una hoja de problemas y '
              'lecciones traducidas, en un repositorio tuyo para tocar sin '
              'miedo.',
            ),
          );
    // Desplazable: en un móvil, con un aviso encima, no cabe entero.
    return Center(
      key: const Key('no-courses'),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.school_outlined,
                  size: 40,
                  color: context.palette.faint,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.palette.muted),
                ),
                const SizedBox(height: 16),
                if (_working)
                  Working(step: _doing)
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.filtering)
                        FilledButton(
                          key: const Key('no-courses-clear-filter'),
                          onPressed: widget.onClearFilter,
                          child: Text(tr('Quitar el filtro')),
                        )
                      else if (widget.anyAtAll)
                        FilledButton.icon(
                          key: const Key('no-courses-show-hidden'),
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: Text(tr('Ver las ocultas')),
                          onPressed: widget.onShowHidden,
                        )
                      else ...[
                        if (widget.onCreate != null)
                          FilledButton.icon(
                            key: const Key('no-courses-create'),
                            icon: const Icon(Icons.add, size: 16),
                            label: Text(tr('Nueva asignatura')),
                            onPressed: widget.onCreate,
                          ),
                        OutlinedButton.icon(
                          key: const Key('no-courses-example'),
                          icon: const Icon(
                            Icons.auto_stories_outlined,
                            size: 16,
                          ),
                          label: Text(tr('Probar con un ejemplo')),
                          onPressed: widget.session.signedIn
                              ? () => _adder.example(context)
                              : null,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El desplegable que filtra por titulación.
/// Qué se está mirando: lo visible, lo oculto o todo.
///
/// Un menú y no tres pestañas: es una pregunta que se hace de vez en cuando
/// --«¿qué escondí?»-- y tres pestañas permanentes en la cabecera dirían que
/// es una decisión de todos los días, que no lo es.
///
/// Con el ojo cerrado cuando no se está en lo normal, para que se vea de un
/// vistazo que la lista no está entera.
class _ViewFilter extends StatelessWidget {
  const _ViewFilter({required this.view, required this.onChanged});

  final CoursesView view;
  final ValueChanged<CoursesView> onChanged;

  static const Map<CoursesView, String> _names = {
    CoursesView.visible: 'Las que doy',
    CoursesView.hidden: 'Las ocultas',
    CoursesView.all: 'Todas',
  };

  @override
  Widget build(BuildContext context) => MenuAnchor(
    builder: (context, controller, child) => TextButton.icon(
      key: const Key('courses-view'),
      icon: Icon(
        view == CoursesView.visible
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        size: 15,
        color: view == CoursesView.visible
            ? context.palette.muted
            : context.palette.teacher,
      ),
      label: Text(tr(_names[view]!), style: const TextStyle(fontSize: 12.5)),
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
    menuChildren: [
      for (final entry in _names.entries)
        MenuItemButton(
          key: Key('courses-view-${entry.key.name}'),
          leadingIcon: Icon(view == entry.key ? Icons.check : null, size: 15),
          onPressed: () => onChanged(entry.key),
          child: Text(entry.value),
        ),
    ],
  );
}

class _DegreeFilter extends StatelessWidget {
  const _DegreeFilter({
    required this.degrees,
    required this.chosen,
    required this.language,
    required this.total,
    required this.onChanged,
  });

  final List<Degree> degrees;
  final String? chosen;
  final String language;
  final int total;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = degrees.where((d) => d.id == chosen).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String?>(
        key: const Key('degree-filter'),
        tooltip: tr('Ver solo las asignaturas de un grado'),
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            key: const Key('degree-filter-all'),
            value: null,
            child: Text(tr('Todas las asignaturas  ·  {0}', [total])),
          ),
          const PopupMenuDivider(),
          for (final degree in degrees)
            PopupMenuItem<String?>(
              key: Key('degree-filter-${degree.id}'),
              value: degree.id,
              child: Text(degree.title(language)),
            ),
        ],
        onSelected: onChanged,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          decoration: BoxDecoration(
            border: Border.all(color: context.palette.rule),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.school_outlined,
                size: 14,
                color: context.palette.muted,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  current?.title(language) ?? tr('Todos los grados'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: context.palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La tira de grados, bajo la cabecera.
///
/// Dice qué titulaciones hay y da paso a gestionarlas. Aquí y no en Ajustes
/// porque un grado es una clasificación del material, como un tema, y se
/// toca mientras se mira la lista que agrupa.
class _DegreeStrip extends StatelessWidget {
  const _DegreeStrip({required this.session, required this.onManage});

  final Session session;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final degrees = session.catalogue.degrees;
    final sinDeclarar = session.catalogue.undeclaredDegrees;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              degrees.isEmpty
                  ? tr('Ningún grado declarado todavía.')
                  : tr(
                      '{0} grado(s): '
                      '{1}',
                      [
                        degrees.length,
                        degrees
                            .map((d) => d.title(session.language))
                            .join(' · '),
                      ],
                    ),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
          ),
          // Un grado que alguna asignatura nombra y no declara nadie. No es
          // un error --la asignatura se ve entera, sin agrupar-- pero casi
          // siempre es que falta una línea, o que falta abrir un repositorio.
          if (sinDeclarar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: tr(
                  'Nombrados y sin declarar: {0}. '
                  'Sus asignaturas se ven, pero sin agrupar.',
                  [sinDeclarar.join(', ')],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: context.palette.ex,
                    ),
                    SizedBox(width: 4),
                    Text(
                      tr('sin declarar'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.palette.ex,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            key: const Key('manage-degrees'),
            icon: const Icon(Icons.school_outlined, size: 15),
            label: Text(tr('Grados')),
            onPressed: onManage,
          ),
        ],
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.session,
    required this.view,
    required this.admin,
    required this.onDuplicate,
    required this.onCopy,
    required this.onBuild,
    required this.onExport,
    this.onPublish,
    required this.onRemove,
    required this.onEditTitle,
    this.first = false,
  });

  /// Si es la primera de la lista, que es la que señala el tour.
  final bool first;

  /// Si se pueden ofrecer las operaciones: hacen falta el clon y el motor.
  final Session session;

  /// Qué se está mirando, que decide qué cursos de dentro se enseñan.
  final CoursesView view;

  final bool admin;
  final VoidCallback onDuplicate;

  /// Copiar de un curso de esta asignatura a otro. Recibe de cuál.
  final void Function(String year) onCopy;

  /// Compilar un curso entero. Recibe cuál.
  final void Function(String year, BuildChoice choice) onBuild;

  /// Exportar un curso. Recibe cuál.
  final void Function(String year) onExport;

  /// Publicarlo en la carpeta de reparto. Null si no hay.
  final void Function(String year)? onPublish;
  final VoidCallback onRemove;

  /// Abrir el diálogo de títulos de la asignatura.
  final VoidCallback onEditTitle;

  final Course course;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.libraryPrefs,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final all = session.sortedYearsOf(course);
    final sortedYears = [
      for (final year in all)
        if (_showsYear(year)) year,
    ];
    final hiddenYears = all.length - sortedYears.length;
    final collapsed = session.isCollapsedCourse(course.id);
    final hidden = session.isHiddenCourse(course.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // El título pliega. Un botón entero y no un triangulito al
                // lado: lo que se quiere pulsar es el nombre de la
                // asignatura, y un objetivo de doce píxeles al lado de un
                // texto de quince es un objetivo que se falla.
                child: Hoverable(
                  onTap: () => session.setCourseCollapsed(
                    course.id,
                    !session.isCollapsedCourse(course.id),
                  ),
                  builder: (context, hovering) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            collapsed ? Icons.chevron_right : Icons.expand_more,
                            size: 18,
                            color: context.palette.muted,
                            key: Key('collapse-${course.id}'),
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              course.title(session.language),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: hidden
                                    ? context.palette.muted
                                    : context.palette.ink,
                                decoration: hovering
                                    ? TextDecoration.underline
                                    : null,
                                decorationColor: context.palette.rule,
                              ),
                            ),
                          ),
                          // Que está oculta se dice aquí, donde se está
                          // mirando: si no, en la vista de todas no habría
                          // forma de saber cuál se escondió.
                          if (hidden)
                            Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text(
                                'oculta',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: context.palette.teacher,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (course.code != null) course.code!,
                          course.language,
                          if (course.teacher != null) course.teacher!,
                          if (collapsed)
                            all.length == 1
                                ? tr('1 curso académico')
                                : tr('{0} cursos académicos', [all.length]),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // El título en todos los idiomas. Un lápiz y no una entrada del
              // menú: desde que el idioma se elige arriba, lo que se ve aquí
              // es el título en ese idioma, y lo primero que se quiere hacer
              // al ver un hueco es rellenarlo.
              if (session.canWriteIn(course.sources.keys.firstOrNull))
                TitleButton(
                  id: 'course-${course.id}',
                  what: tr('esta asignatura'),
                  onPressed: () => onEditTitle(),
                ),
              // Marcar, con su estrella y no dentro del menú: es lo que más
              // se toca de esta fila y lo que hay que ver sin abrir nada.
              _Star(
                id: 'course-${course.id}',
                on: session.isFavouriteCourse(course.id),
                what: course.title(session.language),
                onChanged: (value) =>
                    session.setFavouriteCourse(course.id, value),
              ),
              // El ojo, fuera solo cuando está oculta: es el camino de vuelta,
              // y tiene que verse sin abrir nada. Para ocultarla, en «…».
              if (hidden)
                _Eye(
                  id: 'course-${course.id}',
                  hidden: hidden,
                  what: course.title(session.language),
                  onChanged: (value) =>
                      session.setCourseHidden(course.id, value),
                ),
              // Las operaciones de la asignatura, en un menú y no en botones:
              // ninguna se hace cada día, y no compiten con los cursos por la
              // atención de la fila.
              MenuAnchor(
                builder: (context, controller, child) => IconButton(
                  key: Key('course-menu-${course.id}'),
                  tooltip: tr('Más de la asignatura'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
                menuChildren: [
                  if (!hidden)
                    MenuItemButton(
                      key: Key('hide-course-${course.id}'),
                      leadingIcon: const Icon(
                        Icons.visibility_off_outlined,
                        size: 15,
                      ),
                      onPressed: () => session.setCourseHidden(course.id, true),
                      child: Text(tr('Ocultar de esta lista')),
                    ),
                  if (admin) ...[
                    MenuItemButton(
                      key: Key('duplicate-${course.id}'),
                      leadingIcon: const Icon(Icons.add, size: 15),
                      onPressed: onDuplicate,
                      child: Text(tr('Nuevo curso académico…')),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      key: Key('remove-${course.id}'),
                      leadingIcon: Icon(
                        Icons.delete_outline,
                        size: 15,
                        color: context.palette.teacher,
                      ),
                      onPressed: onRemove,
                      child: Text(tr('Quitar la asignatura…')),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (!collapsed) ...[
            const SizedBox(height: 8),
            // El más reciente arriba: el curso que se está dando es el que se
            // quiere, y una lista alfabética de ocho años lo entierra.
            for (final year in sortedYears)
              _YearRow(
                first: first && year == sortedYears.first,
                course: course,
                year: year,
                entry: course.years[year]!,
                session: session,
                current: year == all.first,
                hidden: session.isHiddenYear(course.id, year),
                canEdit: admin,
                onCopy: () => onCopy(year),
                onBuild: (choice) => onBuild(year, choice),
                onExport: () => onExport(year),
                onPublish: onPublish == null ? null : () => onPublish!(year),
              ),
            if (hiddenYears > 0 && view == CoursesView.visible)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  hiddenYears == 1
                      ? tr('1 curso académico sin enseñar')
                      : tr('{0} cursos académicos sin enseñar', [hiddenYears]),
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
                ),
              ),
            if (admin)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('add-year-${course.id}'),
                  icon: const Icon(Icons.add, size: 15),
                  label: Text(tr('Nuevo curso académico')),
                  onPressed: onDuplicate,
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Si este curso académico entra en lo que se está mirando.
  ///
  /// Con la asignatura oculta se enseñan todos: se ha entrado a mirar qué
  /// hay escondido, y esconder la asignatura no dice nada de sus cursos.
  bool _showsYear(String year) => switch (view) {
    CoursesView.all => true,
    CoursesView.visible => !session.isHiddenYear(course.id, year),
    CoursesView.hidden =>
      session.isHiddenCourse(course.id) ||
          session.isHiddenYear(course.id, year),
  };
}

/// Un curso académico: lo que lleva, y lo que se puede hacer con él.
///
/// Una fila y no una pastilla suelta para que su menú caiga en el borde
/// derecho de la tarjeta, en la misma vertical que el de la asignatura. Con
/// pastillas en una rejilla, los «…» quedaban repartidos por el medio, cada
/// uno a la altura que le tocase: eran el mismo gesto en sitios distintos.
class _YearRow extends StatelessWidget {
  const _YearRow({
    required this.course,
    required this.year,
    required this.entry,
    required this.session,
    required this.current,
    required this.hidden,
    this.canEdit = false,
    required this.onCopy,
    required this.onBuild,
    required this.onExport,
    this.onPublish,
    this.first = false,
  });

  /// Si es el primer curso de la primera asignatura: el que señala el tour.
  final bool first;

  final Course course;
  final Session session;
  final String year;
  final CourseYear entry;
  final bool current;

  /// Si está oculto. Se enseña igual cuando se está mirando lo oculto o
  /// todo, y marcado: en la vista de todas, sin marca no habría forma de
  /// saber cuál se escondió.
  final bool hidden;

  final bool canEdit;
  final VoidCallback onCopy;

  /// Compilar todas las versiones de todos los documentos de este curso.
  final BuildRequest onBuild;

  /// Sacar sus PDF a una carpeta.
  final VoidCallback onExport;

  /// Sacarlos a la carpeta de reparto, sin preguntar dónde.
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.libraryPrefs,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final references = entry.documents.fold<int>(
      0,
      (sum, document) => sum + document.unitRefs.length,
    );

    final row = Container(
      decoration: BoxDecoration(
        color: current
            ? context.palette.tint(context.palette.accent)
            : context.palette.card,
        border: Border.all(
          color: current ? context.palette.accentDark : context.palette.rule,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      margin: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => context.go(Routes.year(course.id, year)),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    Text(
                      year,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (entry.group != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        entry.group!,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('{0} doc · {1} unid.', [
                          entry.documents.length,
                          references,
                        ]),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Compilar el curso entero. Aquí y no solo dentro, porque esto es
          // lo que se hace la víspera: entrar, darle, y volver cuando estén
          // los PDF.
          BuildButton(
            id: 'year-${course.id}-$year',
            what: tr('todo el curso {0}', [year]),
            // Los de la asignatura ya cruzados con lo que mantienen sus
            // repositorios y con el filtro de Ajustes: compilar en un idioma
            // que no se ofrece en ninguna otra parte es una salida que nadie
            // va a mirar.
            options: buildLanguagesOf(
              declared: [
                for (final option in session.languageChoicesFor(course))
                  option.code,
              ],
              known: session.catalogue.languageOptions,
              fallback: session.language,
            ),
            current: session.language,
            onBuild: onBuild,
          ),
          // Llevarse el curso a una carpeta. Fuera del menú y al lado de la
          // estrella a propósito: exportar es de las tres cosas que se hacen
          // con un curso --mirarlo, compilarlo y repartirlo-- y estaba
          // escondido detrás de unos puntos suspensivos.
          //
          // Y sin pedir permiso de escritura, al revés que lo del menú:
          // exportar copia lo compilado y no toca el repositorio, así que
          // también lo hace quien solo lo tiene para leer.
          IconButton(
            key: Key('export-year-${course.id}-$year'),
            tooltip: tr('Exportar este curso a una carpeta'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.file_download_outlined, size: 17),
            onPressed: onExport,
          ),
          _Star(
            id: 'year-${course.id}-$year',
            on: session.isFavouriteYear(course.id, year),
            what: '${course.title(session.language)} $year',
            onChanged: (value) =>
                session.setFavouriteYear(course.id, year, value),
          ),
          // Como el de la asignatura: fuera solo para volver a enseñarlo.
          if (hidden)
            _Eye(
              id: 'year-${course.id}-$year',
              hidden: hidden,
              what: '${course.title(session.language)} $year',
              onChanged: (value) =>
                  session.setYearHidden(course.id, year, value),
            ),
          // Lo que se puede hacer con **este** curso. En el borde, alineado
          // con el de la asignatura: el mismo gesto siempre en el mismo
          // sitio.
          TourTarget.first(
            id: 'courses-year-menu',
            when: first && canEdit,
            child: MenuAnchor(
              builder: (context, controller, child) => IconButton(
                key: Key('year-menu-${course.id}-$year'),
                tooltip: tr('Más de este curso'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_horiz, size: 18),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              menuChildren: [
                if (onPublish != null)
                  MenuItemButton(
                    key: Key('publish-year-${course.id}-$year'),
                    leadingIcon: const Icon(
                      Icons.cloud_upload_outlined,
                      size: 15,
                    ),
                    onPressed: onPublish,
                    child: Text(tr('Publicar en la carpeta de reparto')),
                  ),
                if (!hidden)
                  MenuItemButton(
                    key: Key('hide-year-${course.id}-$year'),
                    leadingIcon: const Icon(
                      Icons.visibility_off_outlined,
                      size: 15,
                    ),
                    onPressed: () =>
                        session.setYearHidden(course.id, year, true),
                    child: Text(tr('Ocultar de esta lista')),
                  ),
                if (canEdit) ...[
                  MenuItemButton(
                    key: Key('copy-year-${course.id}-$year'),
                    leadingIcon: const Icon(Icons.copy_all_outlined, size: 15),
                    onPressed: onCopy,
                    child: Text(tr('Copiar a otro curso…')),
                  ),
                  const Divider(height: 1),
                  // Las versiones congeladas. En el menú del curso y no en una
                  // pantalla aparte porque congelar es algo que se hace
                  // **mirando el curso** --el día que empieza, el día antes del
                  // parcial-- y no algo a lo que se va.
                  MenuItemButton(
                    key: Key('freeze-year-${course.id}-$year'),
                    leadingIcon: const Icon(Icons.ac_unit, size: 15),
                    // En todos los repositorios del curso, con el mismo
                    // nombre: congelar solo el primero dejaba la otra mitad
                    // de una asignatura repartida cambiando por debajo.
                    onPressed: () =>
                        createFreeze(context, session, course, year),
                    child: Text(tr('Crear versión congelada…')),
                  ),
                  MenuItemButton(
                    key: Key('freezes-${course.id}-$year'),
                    leadingIcon: const Icon(Icons.history_toggle_off, size: 15),
                    onPressed: () =>
                        showFreezes(context, session, course, year),
                    child: Text(
                      entry.freezes.isEmpty
                          ? tr('Ver versiones congeladas…')
                          : tr('Ver versiones congeladas ({0})…', [
                              entry.freezes.length,
                            ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return TourTarget.first(id: 'courses-year-first', when: first, child: row);
  }
}

/// La estrella con la que se marca algo para que suba arriba.
///
/// Un botón y no una opción del menú: es lo que más se toca de una fila y lo
/// que hay que poder ver sin abrir nada. Apagada se queda en gris y con el
/// contorno, para que se vea que se puede marcar y que no lo está -- una
/// estrella que solo aparece cuando está encendida no se descubre nunca.
/// Ocultar algo de la lista, o volver a enseñarlo.
///
/// Un ojo y no una papelera, y el tooltip lo dice: **ocultar no es quitar**.
/// La asignatura sigue en el repositorio, sigue compilando y sigue en la
/// biblioteca; lo que cambia es esta lista, que después de unos años son
/// veinte asignaturas de las que se dan tres.
class _Eye extends StatelessWidget {
  const _Eye({
    required this.id,
    required this.hidden,
    required this.what,
    required this.onChanged,
  });

  final String id;
  final bool hidden;
  final String what;
  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('hide-$id'),
    tooltip: hidden
        ? tr('Volver a enseñar «{0}» en esta lista', [what])
        : tr('Ocultar «{0}» de esta lista. Sigue estando: no se quita nada.', [
            what,
          ]),
    visualDensity: VisualDensity.compact,
    icon: Icon(
      hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: 17,
      color: hidden ? context.palette.teacher : context.palette.muted,
    ),
    onPressed: () => onChanged(!hidden),
  );
}

class _Star extends StatelessWidget {
  const _Star({
    required this.id,
    required this.on,
    required this.what,
    required this.onChanged,
  });

  final String id;
  final bool on;

  /// Qué se marca, para el tooltip. Con el nombre dentro, porque en una lista
  /// de seis cursos «Quitar de preferidos» no dice cuál.
  final String what;

  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('favourite-$id'),
    tooltip: on ? tr('Desmarcar «{0}»', [what]) : tr('Marcar «{0}»', [what]),
    visualDensity: VisualDensity.compact,
    icon: Icon(
      on ? Icons.star : Icons.star_border,
      size: 17,
      color: on ? context.palette.ex : context.palette.muted,
    ),
    onPressed: () => onChanged(!on),
  );
}
