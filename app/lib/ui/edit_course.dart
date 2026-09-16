/// Editar una asignatura: su nombre, sus idiomas y su titulación.
///
/// Las tres cosas en un sitio porque son la misma decisión. Los idiomas
/// estaban en Ajustes, en una lista de todas las asignaturas, y eso obligaba a
/// salir de donde se trabaja para cambiar algo de la asignatura que se tiene
/// delante; el nombre se editaba aquí, y el grado no se podía tocar. Tres
/// gestos distintos para editar una misma ficha.
///
/// Todo lo de aquí se escribe en `course.yaml`, y **en todos los repositorios
/// que declaran la asignatura**: una asignatura repartida tiene un fichero en
/// cada uno, y cambiarla en uno solo la deja diciendo dos cosas.
///
/// El diálogo no guarda: devuelve lo que se ha decidido y quien lo abrió
/// escribe. Así se puede probar sin sesión, y quien escribe es quien sabe
/// contar cuántos repositorios se tocaron.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import 'theme.dart';

/// Lo que la pantalla decide.
class CourseEdit {
  const CourseEdit({
    required this.titles,
    required this.languages,
    required this.degree,
  });

  final Map<String, String> titles;
  final List<String> languages;

  /// A qué grado pertenece. Null es «a ninguno», que es un estado legítimo.
  final String? degree;
}

Future<CourseEdit?> editCourse(
  BuildContext context, {
  required Course course,
  required List<LanguageOption> options,
  required List<Degree> degrees,
  required String language,
}) => showDialog<CourseEdit>(
  context: context,
  builder: (context) => EditCourseDialog(
    course: course,
    options: options,
    degrees: degrees,
    language: language,
  ),
);

class EditCourseDialog extends StatefulWidget {
  const EditCourseDialog({
    super.key,
    required this.course,
    required this.options,
    required this.degrees,
    required this.language,
  });

  final Course course;

  /// Los idiomas a los que Didacta sabe imprimir.
  final List<LanguageOption> options;

  /// Las titulaciones declaradas, de todos los repositorios abiertos.
  final List<Degree> degrees;

  /// En el que se está trabajando, para los títulos de los grados.
  final String language;

  @override
  State<EditCourseDialog> createState() => _EditCourseDialogState();
}

class _EditCourseDialogState extends State<EditCourseDialog> {
  /// Un controlador por idioma posible, aunque solo se enseñen los marcados.
  ///
  /// Creados todos de una vez para que desmarcar un idioma y volver a marcarlo
  /// no se lleve por delante lo que se había escrito mientras tanto.
  late final Map<String, TextEditingController> _titles = {
    for (final option in widget.options)
      option.code: TextEditingController(
        text: widget.course.titles[option.code] ?? '',
      ),
  };

  /// Los idiomas en los que se pide el nombre: los de la asignatura.
  ///
  /// Solo esos, y no los diez que Didacta trae. Con los diez el diálogo es un
  /// muro de campos vacíos que además empuja la titulación fuera de la
  /// pantalla, y nueve de ellos son idiomas a los que esta asignatura no se
  /// traduce. Marcar uno hace aparecer su campo al momento, así que no hay
  /// que cerrar y volver a abrir.
  List<LanguageOption> get _shown => [
    for (final option in widget.options)
      if (_languages.contains(option.code)) option,
  ];

  late final Set<String> _languages = {
    ...widget.course.languages.isNotEmpty
        ? widget.course.languages
        : [widget.course.language],
  };

  late String? _degree = widget.course.degreeId;

  @override
  void dispose() {
    for (final controller in _titles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Al menos un idioma, y con nombre: una asignatura sin ninguno se vería
  /// por su id, que es un slug.
  bool get _valid =>
      _languages.isNotEmpty &&
      _shown.any((option) => _titles[option.code]!.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar ${widget.course.title(widget.language)}'),
      content: SizedBox(
        width: 520,
        height: 560,
        child: ListView(
          children: [
            // Los idiomas primero: deciden en cuántos se pide el nombre, así
            // que preguntarlo después dejaba el diálogo enseñando campos que
            // no hacían falta.
            const _Label('Idiomas'),
            const Text(
              'A cuáles se traduce. Lo que no esté marcado no se pide y no '
              'cuenta como pendiente; quitarlo no borra ningún fichero.',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final option in widget.options)
                  FilterChip(
                    key: Key('course-language-${option.code}'),
                    label: Text(option.name),
                    selected: _languages.contains(option.code),
                    // El último no se puede quitar: una asignatura sin ningún
                    // idioma no se compila, y el motor lo rechazaría al
                    // guardar.
                    onSelected:
                        _languages.length == 1 &&
                            _languages.contains(option.code)
                        ? null
                        : (on) => setState(() {
                            if (on) {
                              _languages.add(option.code);
                            } else {
                              _languages.remove(option.code);
                            }
                          }),
                  ),
              ],
            ),

            const SizedBox(height: 14),
            const _Label('Nombre'),
            Text(
              _shown.length == 1
                  ? 'En ${_shown.single.name.toLowerCase()}.'
                  : 'En cada idioma de los de arriba. El que se deja en blanco '
                        'no se enseña, y la asignatura se ve por el que tenga.',
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 6),
            for (final option in _shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: Key('course-title-${option.code}'),
                  controller: _titles[option.code],
                  autofocus: option.code == widget.language,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: option.name,
                    isDense: true,
                    // El que falta se dice, y no se rellena con el de al
                    // lado: un nombre prestado que parece traducido es la
                    // misma trampa que copiar el original en el editor.
                    helperText:
                        (widget.course.titles[option.code] ?? '').isEmpty
                        ? 'sin traducir'
                        : null,
                    helperStyle: const TextStyle(
                      fontSize: 11,
                      color: didactaTeacher,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 8),
            const _Label('Titulación'),
            const Text(
              'En qué grado se da. Sirve para agruparlas y para filtrar; sin '
              'grado la asignatura se ve igual, suelta.',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              key: const Key('course-degree'),
              initialValue: widget.degrees.any((d) => d.id == _degree)
                  ? _degree
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin grado'),
                ),
                for (final degree in widget.degrees)
                  DropdownMenuItem<String?>(
                    key: Key('degree-option-${degree.id}'),
                    value: degree.id,
                    child: Text(degree.title(widget.language)),
                  ),
              ],
              onChanged: (value) => setState(() => _degree = value),
            ),
            if (_degree != null && !widget.degrees.any((d) => d.id == _degree))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Note(
                  'Pertenece a «$_degree», que no declara ningún repositorio '
                  'abierto. Se sigue viendo entera, pero sin agrupar. Al '
                  'aceptar se queda sin grado.',
                  tone: didactaTeacher,
                ),
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
          key: const Key('course-save'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                  CourseEdit(
                    // Solo los que se han enseñado. Un idioma que la
                    // asignatura no usa puede tener título escrito en el
                    // fichero, y no haberlo visto aquí no es motivo para
                    // borrarlo.
                    titles: {
                      for (final option in _shown)
                        option.code: _titles[option.code]!.text.trim(),
                    },
                    // En el orden del catálogo y no en el de los clics: así el
                    // fichero sale igual se marque como se marque, y no hay
                    // diffs que solo mueven códigos de sitio.
                    languages: [
                      for (final option in widget.options)
                        if (_languages.contains(option.code)) option.code,
                    ],
                    degree: _degree,
                  ),
                )
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    ),
  );
}
