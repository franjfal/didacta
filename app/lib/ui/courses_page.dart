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

import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'course_admin_ui.dart';
import 'export_year.dart';
import 'shell.dart';
import 'build_button.dart';
import 'heading_title.dart';
import 'theme.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    // Marcadas primero y el resto por título. El orden lo decide la sesión:
    // si cada lista lo hiciera por su cuenta, acabarían discrepando.
    final courses = session.sortedCourses;

    final years = courses.fold<int>(0, (sum, c) => sum + c.years.length);
    final documents = courses.fold<int>(
      0,
      (sum, c) =>
          sum + c.years.values.fold<int>(0, (n, y) => n + y.documents.length),
    );

    return Column(
      children: [
        PageHeader(
          title: 'Asignaturas',
          subtitle:
              '${courses.length} asignaturas · $years cursos '
              'académicos · $documents documentos',
          actions: [
            if (session.admin() != null)
              FilledButton.icon(
                key: const Key('new-course'),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nueva asignatura'),
                onPressed: () => _createCourse(session),
              ),
          ],
        ),
        Expanded(
          child: ListView.separated(
            itemCount: courses.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _CourseTile(
              course: courses[index],
              session: session,
              admin: session.admin() != null,
              onDuplicate: () => _duplicateYear(session, courses[index]),
              onCopy: (year) => _copyYear(session, courses[index], year),
              onBuild: (year, languages) => _buildYear(
                session,
                courses[index],
                year,
                languages: languages,
              ),
              onExport: (year) => _exportYear(session, courses[index], year),
              onRemove: () => _removeCourse(session, courses[index]),
              onEditTitle: () => _editCourseTitle(session, courses[index]),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createCourse(Session session) async {
    final catalogue = session.catalogue;
    final answer =
        await showDialog<
          ({String id, String title, String? from, String language})
        >(
          context: context,
          builder: (context) => NewCourseDialog(
            courses: catalogue.courses,
            languages: catalogue.languages,
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
      done: 'Asignatura «${answer.title}» creada como un commit.',
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
        SnackBar(content: Text('$year no tiene documentos que compilar.')),
      );
      return;
    }
    unawaited(showBuildConsole(context, session.buildConsole));
    await session.buildDocuments(
      wanted,
      title: '${course.title(session.language)} · $year',
      languages: languages,
    );
  }

  /// El título de la asignatura, en todos los idiomas a la vez.
  ///
  /// Aquí y no en el editor de cada fichero porque el título de la asignatura
  /// no está en ningún fichero de contenido: vive en `course.yaml`, que es lo
  /// único de una asignatura que no se edita desde ninguna pantalla.
  Future<void> _editCourseTitle(Session session, Course course) async {
    final languages = course.languages.isNotEmpty
        ? course.languages
        : session.catalogue.languages;
    final titles = await editHeadingTitles(
      context,
      heading: 'asignatura',
      article: 'de la',
      languages: languages,
      titles: course.titles,
      reference: course.language,
      note:
          'Un idioma en blanco quita ese título. Los demás se quedan, y la '
          'asignatura se sigue viendo por el que tenga.',
    );
    if (titles == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final written = await session.setCourseTitles(
        course: course.id,
        titles: titles,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written == 0
                ? 'No ha cambiado nada.'
                : written == 1
                ? 'Título cambiado, como un commit.'
                : 'Título cambiado en $written repositorios.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// Saca un curso a una carpeta, para repartirlo.
  Future<void> _exportYear(Session session, Course course, String year) async {
    final entry = course.years[year];
    if (entry == null) return;

    // Los idiomas de la asignatura, y si no los declara, los del catálogo:
    // preguntar por tres cuando la asignatura se da en uno llena la pantalla
    // de opciones que no son.
    final languages = course.languages.isNotEmpty
        ? course.languages
        : session.catalogue.languages;

    final answer = await showDialog<ExportRequest>(
      context: context,
      builder: (context) => ExportYearDialog(
        course: course,
        year: year,
        entry: entry,
        languages: languages,
        language: session.language,
      ),
    );
    if (answer == null || !mounted) return;

    final destination = await getDirectoryPath(
      confirmButtonText: 'Exportar aquí',
    );
    if (destination == null || !mounted) return;

    // Compilar primero, si se pidió. Con su registro y su barra, porque puede
    // ser media hora.
    if (answer.rebuild) {
      final wanted = [
        for (final document in entry.documents)
          if (answer.documents.contains(document.id))
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
    Object? failure;

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
              if (document.repo == repo && answer.documents.contains(document.id))
                document.id,
          ],
        );
        copied.addAll(result.copied);
        missing.addAll(result.missing);
      } catch (error) {
        failure ??= error;
      }
    }
    if (!mounted) return;

    if (failure != null && copied.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$failure'),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 8),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          missing.isEmpty
              ? '${copied.length} fichero(s) exportados a $destination.'
              : '${copied.length} exportados; ${missing.length} sin compilar '
                    'se han quedado fuera.',
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
          toCourse: course.id,
          toYear: answer.toYear,
          documents: group.value,
        ),
        repo: group.key,
        done: group.value.length == 1
            ? '«${group.value.single}» copiado a ${answer.toYear}.'
            : '${group.value.length} documentos copiados a '
                  '${answer.toYear}.',
      );
      if (!done || !mounted) break;
    }
    if (done) await session.reloadCatalogue();
  }

  Future<void> _duplicateYear(Session session, Course course) async {
    final answer = await showDialog<({String year, String from})>(
      context: context,
      builder: (context) => DuplicateYearDialog(course: course),
    );
    if (answer == null || !mounted) return;

    final done = await runAdmin(
      context,
      session,
      (admin) => admin.duplicateYear(
        course: course.id,
        year: answer.year,
        from: answer.from,
      ),
      done: answer.from.isEmpty
          ? 'Curso ${answer.year} creado, vacío.'
          : 'Curso ${answer.year} creado, copiado de ${answer.from}.',
    );
    if (done) await session.reloadCatalogue();
  }

  Future<void> _removeCourse(Session session, Course course) async {
    final admin = session.admin();
    if (admin == null) return;

    final confirmed = await confirmRemoval(
      context,
      title: '¿Quitar «${course.title(session.language)}»?',
      preview: () => admin.previewRemoveCourse(course.id),
      warning:
          'Las unidades no se tocan: siguen en la biblioteca y en las demás '
          'asignaturas que las usen. Lo que se pierde es la selección y el '
          'orden de esta.',
    );
    if (!confirmed || !mounted) return;

    final done = await runAdmin(
      context,
      session,
      (admin) => admin.removeCourse(course.id, title: course.title(session.language)),
      done: 'Asignatura «${course.title(session.language)}» quitada como un commit.',
    );
    if (done) await session.reloadCatalogue();
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.session,
    required this.admin,
    required this.onDuplicate,
    required this.onCopy,
    required this.onBuild,
    required this.onExport,
    required this.onRemove,
    required this.onEditTitle,
  });

  /// Si se pueden ofrecer las operaciones: hacen falta el clon y el motor.
  final Session session;
  final bool admin;
  final VoidCallback onDuplicate;

  /// Copiar de un curso de esta asignatura a otro. Recibe de cuál.
  final void Function(String year) onCopy;

  /// Compilar un curso entero. Recibe cuál.
  final void Function(String year, List<String> languages) onBuild;

  /// Exportar un curso. Recibe cuál.
  final void Function(String year) onExport;
  final VoidCallback onRemove;

  /// Abrir el diálogo de títulos de la asignatura.
  final VoidCallback onEditTitle;

  final Course course;

  @override
  Widget build(BuildContext context) {
    final sortedYears = session.sortedYearsOf(course);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title(session.language),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (course.code != null) course.code!,
                        course.language,
                        if (course.teacher != null) course.teacher!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: didactaMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // El título en todos los idiomas. Un lápiz y no una entrada del
              // menú: desde que el idioma se elige arriba, lo que se ve aquí
              // es el título en ese idioma, y lo primero que se quiere hacer
              // al ver un hueco es rellenarlo.
              if (session.canWriteIn(course.sources.keys.firstOrNull))
                TitleButton(
                  id: 'course-${course.id}',
                  what: 'esta asignatura',
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
              // Las operaciones de la asignatura, en un menú y no en botones:
              // son dos, una de ellas destructiva, y no compiten con los
              // cursos por la atención de la fila.
              if (admin)
                MenuAnchor(
                  builder: (context, controller, child) => IconButton(
                    key: Key('course-menu-${course.id}'),
                    tooltip: 'Operaciones de la asignatura',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      key: Key('duplicate-${course.id}'),
                      leadingIcon: const Icon(Icons.add, size: 15),
                      onPressed: onDuplicate,
                      child: const Text('Nuevo curso académico…'),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      key: Key('remove-${course.id}'),
                      leadingIcon: const Icon(
                        Icons.delete_outline,
                        size: 15,
                        color: didactaTeacher,
                      ),
                      onPressed: onRemove,
                      child: const Text('Quitar la asignatura…'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          // El más reciente arriba: el curso que se está dando es el que se
          // quiere, y una lista alfabética de ocho años lo entierra.
          for (final year in sortedYears)
            _YearRow(
              course: course,
              year: year,
              entry: course.years[year]!,
              session: session,
              current: year == sortedYears.first,
              canEdit: admin,
              onCopy: () => onCopy(year),
              onBuild: (languages) => onBuild(year, languages),
              onExport: () => onExport(year),
            ),
          if (admin)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('add-year-${course.id}'),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Nuevo curso académico'),
                onPressed: onDuplicate,
              ),
            ),
        ],
      ),
    );
  }
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
    this.canEdit = false,
    required this.onCopy,
    required this.onBuild,
    required this.onExport,
  });

  final Course course;
  final Session session;
  final String year;
  final CourseYear entry;
  final bool current;
  final bool canEdit;
  final VoidCallback onCopy;

  /// Compilar todas las versiones de todos los documentos de este curso.
  final BuildRequest onBuild;

  /// Sacar sus PDF a una carpeta.
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final references = entry.documents.fold<int>(
      0,
      (sum, document) => sum + document.unitRefs.length,
    );

    return Container(
      decoration: BoxDecoration(
        color: current ? didactaAccent.withValues(alpha: 0.08) : Colors.white,
        border: Border.all(color: current ? didactaAccentDark : didactaRule),
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: didactaMuted,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${entry.documents.length} doc · $references unid.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: didactaMuted,
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
            what: 'todo el curso $year',
            options: buildLanguagesOf(
              declared: course.languages,
              known: session.catalogue.languageOptions,
              fallback: session.language,
            ),
            current: session.language,
            onBuild: onBuild,
          ),
          _Star(
            id: 'year-${course.id}-$year',
            on: session.isFavouriteYear(course.id, year),
            what: '${course.title(session.language)} $year',
            onChanged: (value) =>
                session.setFavouriteYear(course.id, year, value),
          ),
          // Lo que se puede hacer con **este** curso. En el borde, alineado
          // con el de la asignatura: el mismo gesto siempre en el mismo
          // sitio.
          if (canEdit)
            MenuAnchor(
              builder: (context, controller, child) => IconButton(
                key: Key('year-menu-${course.id}-$year'),
                tooltip: 'Operaciones de este curso',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_horiz, size: 18),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  key: Key('copy-year-${course.id}-$year'),
                  leadingIcon: const Icon(Icons.copy_all_outlined, size: 15),
                  onPressed: onCopy,
                  child: const Text('Copiar a otro curso…'),
                ),
                MenuItemButton(
                  key: Key('export-year-${course.id}-$year'),
                  leadingIcon: const Icon(Icons.folder_zip_outlined, size: 15),
                  onPressed: onExport,
                  child: const Text('Exportar…'),
                ),
              ],
            )
          else
            const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// La estrella con la que se marca algo para que suba arriba.
///
/// Un botón y no una opción del menú: es lo que más se toca de una fila y lo
/// que hay que poder ver sin abrir nada. Apagada se queda en gris y con el
/// contorno, para que se vea que se puede marcar y que no lo está -- una
/// estrella que solo aparece cuando está encendida no se descubre nunca.
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
    tooltip: on ? 'Quitar «$what» de arriba' : 'Poner «$what» arriba',
    visualDensity: VisualDensity.compact,
    icon: Icon(
      on ? Icons.star : Icons.star_border,
      size: 17,
      color: on ? didactaEx : didactaMuted,
    ),
    onPressed: () => onChanged(!on),
  );
}
