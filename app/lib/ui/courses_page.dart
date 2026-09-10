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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'course_admin_ui.dart';
import 'shell.dart';
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
    final courses = [...session.catalogue.courses]
      ..sort(
        (a, b) => a.title().toLowerCase().compareTo(b.title().toLowerCase()),
      );

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
              admin: session.admin() != null,
              onDuplicate: () => _duplicateYear(session, courses[index]),
              onRemove: () => _removeCourse(session, courses[index]),
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

    final done = await runAdmin(
      context,
      session,
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

  Future<void> _duplicateYear(Session session, Course course) async {
    if (course.years.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta asignatura no tiene ningún curso del que copiar. El primero '
            'se hace copiando el de otra asignatura desde el terminal: '
            '`didacta new year`.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
      return;
    }
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
      done: 'Curso ${answer.year} creado, copiado de ${answer.from}.',
    );
    if (done) await session.reloadCatalogue();
  }

  Future<void> _removeCourse(Session session, Course course) async {
    final admin = session.admin();
    if (admin == null) return;

    final confirmed = await confirmRemoval(
      context,
      title: '¿Quitar «${course.title()}»?',
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
      (admin) => admin.removeCourse(course.id, title: course.title()),
      done: 'Asignatura «${course.title()}» quitada como un commit.',
    );
    if (done) await session.reloadCatalogue();
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.admin,
    required this.onDuplicate,
    required this.onRemove,
  });

  /// Si se pueden ofrecer las operaciones: hacen falta el clon y el motor.
  final bool admin;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  final Course course;

  @override
  Widget build(BuildContext context) {
    final sortedYears = course.sortedYears;

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
                      course.title(),
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Newest first: the year being taught is the one you want, and
              // an alphabetical list of eight years buries it.
              for (final year in sortedYears)
                _YearChip(
                  course: course,
                  year: year,
                  entry: course.years[year]!,
                  current: year == sortedYears.first,
                ),
              if (admin)
                ActionChip(
                  key: Key('add-year-${course.id}'),
                  avatar: const Icon(Icons.add, size: 14),
                  label: const Text('curso'),
                  onPressed: onDuplicate,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YearChip extends StatelessWidget {
  const _YearChip({
    required this.course,
    required this.year,
    required this.entry,
    required this.current,
  });

  final Course course;
  final String year;
  final CourseYear entry;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final references = entry.documents.fold<int>(
      0,
      (sum, document) => sum + document.unitRefs.length,
    );

    return InkWell(
      onTap: () => context.go(Routes.year(course.id, year)),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: current ? didactaAccent.withValues(alpha: 0.10) : Colors.white,
          border: Border.all(color: current ? didactaAccentDark : didactaRule),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                    style: const TextStyle(fontSize: 11, color: didactaMuted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${entry.documents.length} doc · $references unid.',
              style: const TextStyle(fontSize: 11, color: didactaMuted),
            ),
          ],
        ),
      ),
    );
  }
}
