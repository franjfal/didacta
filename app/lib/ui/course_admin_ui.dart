/// Los diálogos de crear, duplicar y borrar asignaturas y años.
///
/// En un fichero propio porque son cuatro operaciones que comparten la misma
/// forma —comprobar que se puede, preguntar, lanzar el motor, contar qué
/// pasó— y repartirlas entre la pantalla de asignaturas y la de un curso
/// dejaría dos mitades de lo mismo.
///
/// Lo que tienen en común, y es lo que importa:
///
/// **Borrar dice qué se lleva, contado.** «Esta asignatura tiene dos años y
/// setenta y siete documentos» es lo que permite decidir; «¿seguro?» no lo
/// es. El recuento lo da el motor en seco, sin borrar nada, y por eso es el
/// de verdad.
///
/// **Y dice qué *no* se lleva.** Las unidades no se tocan: lo que se pierde
/// es la selección y el orden. Sin esa frase, borrar una asignatura parece
/// borrar el material, y nadie lo pulsaría.
library;

import 'package:flutter/material.dart';

import '../data/course_admin.dart';
import '../model/catalogue.dart';
import '../state/session.dart';
import 'theme.dart';

/// Lanza una operación y cuenta el resultado.
///
/// Devuelve true cuando algo cambió, para que quien llame recargue el
/// catálogo: el índice se genera aparte, así que después de crear un año la
/// pantalla no lo ve hasta que se vuelve a leer.
Future<bool> runAdmin(
  BuildContext context,
  Session session,
  Future<void> Function(CourseAdmin admin) action, {
  required String done,
}) async {
  final admin = session.admin();
  final messenger = ScaffoldMessenger.of(context);
  if (admin == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Esto necesita un clon del repositorio y el motor. Los dos se '
          'eligen en Ajustes.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
    return false;
  }

  final status = await admin.status();
  if (!status.ready) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(status.problem ?? 'No se puede.'),
        duration: const Duration(seconds: 6),
      ),
    );
    return false;
  }

  try {
    await action(admin);
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on AdminException catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        backgroundColor: didactaTeacher,
        duration: const Duration(seconds: 8),
      ),
    );
    return false;
  }
}

/// Pregunta antes de borrar, con el recuento delante.
Future<bool> confirmRemoval(
  BuildContext context, {
  required String title,
  required Future<RemovalPreview> Function() preview,
  required String warning,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) =>
            _RemovalDialog(title: title, preview: preview, warning: warning),
      ) ??
      false;
}

/// «1 curso académico», «2 cursos académicos».
///
/// Con la concordancia hecha, y por eso está: «se van 1 curso académicos» se
/// lee como un descuido, y en el diálogo que pregunta si borrar setenta y
/// siete documentos, un descuido hace dudar del recuento. La frase entera va
/// en tercera persona del singular --«esto se lleva...»-- justo para no tener
/// que concordar el verbo con lo que venga detrás.
String _count(int number, String singular, String plural) =>
    '$number ${number == 1 ? singular : plural}';

class _RemovalDialog extends StatefulWidget {
  const _RemovalDialog({
    required this.title,
    required this.preview,
    required this.warning,
  });

  final String title;
  final Future<RemovalPreview> Function() preview;
  final String warning;

  @override
  State<_RemovalDialog> createState() => _RemovalDialogState();
}

class _RemovalDialogState extends State<_RemovalDialog> {
  RemovalPreview? _preview;
  Object? _problem;

  @override
  void initState() {
    super.initState();
    widget
        .preview()
        .then((found) {
          if (mounted) setState(() => _preview = found);
        })
        .catchError((Object error) {
          if (mounted) setState(() => _problem = error);
        });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_problem != null)
              Text(
                '$_problem',
                style: const TextStyle(fontSize: 12.5, color: didactaTeacher),
              )
            else if (preview == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Contando qué se llevaría…',
                  style: TextStyle(fontSize: 12.5, color: didactaMuted),
                ),
              )
            else ...[
              // El recuento del motor, no uno propio: es el que sabe escanear
              // el repositorio, y dos recuentos que pueden discrepar son
              // peores que uno.
              Text(
                preview.years > 0
                    ? 'Esto se lleva ${_count(preview.years, 'curso '
                              'académico', 'cursos académicos')} y '
                          '${_count(preview.documents, 'documento', 'documentos')}.'
                    : 'Esto se lleva '
                          '${_count(preview.documents, 'documento', 'documentos')}.',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Y lo que **no** se va. Sin esta frase, borrar una asignatura
            // parece borrar el material.
            Note(widget.warning),
            const SizedBox(height: 8),
            const Text(
              'Queda como un commit, así que se puede revertir.',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm-removal'),
          style: FilledButton.styleFrom(backgroundColor: didactaTeacher),
          onPressed: preview == null
              ? null
              : () => Navigator.of(context).pop(true),
          child: const Text('Quitar'),
        ),
      ],
    );
  }
}

/// Pide el año nuevo y de cuál copiarlo.
class DuplicateYearDialog extends StatefulWidget {
  const DuplicateYearDialog({super.key, required this.course});

  final Course course;

  @override
  State<DuplicateYearDialog> createState() => _DuplicateYearDialogState();
}

class _DuplicateYearDialogState extends State<DuplicateYearDialog> {
  late final List<String> _years = widget.course.years.keys.toList()
    ..sort((a, b) => b.compareTo(a));

  late String _from = _years.first;
  late final TextEditingController _year = TextEditingController(
    text: _nextAfter(_years.first),
  );

  /// El año siguiente al más reciente, ya escrito.
  ///
  /// Es lo que se va a teclear el 95% de las veces, y `2025-2026` es
  /// suficientemente fácil de escribir mal como para que valga la pena.
  static String _nextAfter(String year) {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(year);
    if (match == null) return '';
    final start = int.parse(match.group(1)!) + 1;
    return '$start-${start + 1}';
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  bool get _valid =>
      RegExp(r'^\d{4}-\d{4}$').hasMatch(_year.text.trim()) &&
      !widget.course.years.containsKey(_year.text.trim());

  @override
  Widget build(BuildContext context) {
    final exists = widget.course.years.containsKey(_year.text.trim());
    return AlertDialog(
      title: const Text('Nuevo curso académico'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copia la selección y el orden de un curso que ya existe. Las '
              'unidades no se copian: el curso nuevo referencia las mismas, '
              'que es la razón de que el material y las asignaturas estén '
              'separados.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('new-year'),
              controller: _year,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'El curso nuevo',
                hintText: '2026-2027',
                errorText: exists
                    ? 'Ya existe'
                    : (_year.text.trim().isEmpty || _valid
                          ? null
                          : 'Se escribe 2026-2027'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text(
              'Copiado de',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final year in _years)
                  ChoiceChip(
                    label: Text(
                      '$year · '
                      '${widget.course.years[year]!.documents.length} doc.',
                    ),
                    selected: year == _from,
                    onSelected: (_) => setState(() => _from = year),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm-duplicate'),
          onPressed: _valid
              ? () => Navigator.of(
                  context,
                ).pop((year: _year.text.trim(), from: _from))
              : null,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

/// Pide los datos de una asignatura nueva.
class NewCourseDialog extends StatefulWidget {
  const NewCourseDialog({
    super.key,
    required this.courses,
    required this.languages,
    required this.defaultLanguage,
  });

  final List<Course> courses;
  final List<String> languages;
  final String defaultLanguage;

  @override
  State<NewCourseDialog> createState() => _NewCourseDialogState();
}

class _NewCourseDialogState extends State<NewCourseDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _id = TextEditingController();
  String? _from;
  late String _language = widget.defaultLanguage;

  /// Si el id lo escribió la persona. Mientras no, se deduce del título:
  /// «Análisis Matemático III (grupo B)» da `analisis-matematico-iii-grupo-b`,
  /// que es lo que se habría escrito a mano.
  bool _idTyped = false;

  @override
  void dispose() {
    _title.dispose();
    _id.dispose();
    super.dispose();
  }

  static String slugify(String text) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
    const to = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final at = from.indexOf(char);
      buffer.write(at >= 0 ? to[at] : char);
    }
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  bool get _valid {
    final id = _id.text.trim();
    return RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id) &&
        !widget.courses.any((course) => course.id == id) &&
        _title.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final id = _id.text.trim();
    final taken = widget.courses.any((course) => course.id == id);
    return AlertDialog(
      title: const Text('Nueva asignatura'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('new-course-title'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (value) => setState(() {
                if (!_idTyped) _id.text = slugify(value);
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('new-course-id'),
              controller: _id,
              decoration: InputDecoration(
                labelText: 'Identificador',
                helperText: 'El nombre de la carpeta y lo que se referencia',
                errorText: taken
                    ? 'Ya existe'
                    : (id.isEmpty || _valid
                          ? null
                          : 'Minúsculas, dígitos y guiones'),
              ),
              onChanged: (_) => setState(() => _idTyped = true),
            ),
            const SizedBox(height: 14),
            const Text(
              'Idioma en el que se da',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              children: [
                for (final code in widget.languages)
                  ChoiceChip(
                    label: Text(code),
                    selected: code == _language,
                    onSelected: (_) => setState(() => _language = code),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Copiar los datos de',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 5),
            // El caso que de verdad ocurre: la misma asignatura en otro grupo
            // o en otro idioma, donde todo menos el título y el código es lo
            // mismo. Copiar se queda con los TODO de los campos, que son la
            // lista de trabajo.
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                ChoiceChip(
                  label: const Text('nada, en blanco'),
                  selected: _from == null,
                  onSelected: (_) => setState(() => _from = null),
                ),
                for (final course in widget.courses)
                  ChoiceChip(
                    label: Text(course.id),
                    selected: _from == course.id,
                    onSelected: (_) => setState(() => _from = course.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Note(
              'Se crea sin cursos académicos. El siguiente paso es añadir '
              'uno, copiándolo del de otra asignatura o del de otro año.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm-new-course'),
          onPressed: _valid
              ? () => Navigator.of(context).pop((
                  id: _id.text.trim(),
                  title: _title.text.trim(),
                  from: _from,
                  language: _language,
                ))
              : null,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
