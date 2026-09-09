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
import 'shell.dart';
import 'theme.dart';

class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});

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
        ),
        Expanded(
          child: ListView.separated(
            itemCount: courses.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _CourseTile(course: courses[index]),
          ),
        ),
      ],
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course});

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
