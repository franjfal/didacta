/// Un título, en todos los idiomas a la vez.
///
/// Antes se editaba en la fila, y eso significaba editar **solo el idioma que
/// se estaba mirando**: para poner el título en valenciano había que cambiar
/// de idioma toda la pantalla y volver. Con los ficheros no pasa --tienen una
/// pestaña por idioma-- y con los títulos de los apartados sí, que es
/// justamente donde más fácil es dejarse uno.
///
/// Así que un lápiz y un modal con todos. Los que falten se ven vacíos y con
/// su marca, que es la lista de lo que queda por traducir.
///
/// Lo usan los apartados, para los que se escribió, y desde que el idioma se
/// elige en la barra de arriba también la asignatura, el tema y el documento:
/// es el mismo problema en cuatro sitios, y resolverlo cuatro veces daría
/// cuatro diálogos que se parecen y no se comportan igual.
library;

import 'package:flutter/material.dart';

import '../model/library_tree.dart' show languageName;
import 'theme.dart';

Future<Map<String, String>?> editHeadingTitles(
  BuildContext context, {
  required String heading,
  required List<String> languages,
  required Map<String, String> titles,
  required String reference,

  /// «del» o «de la», según el nombre de lo que se titula. Sin esto el
  /// diálogo dice «Título del asignatura», que es la clase de detalle que
  /// hace que una pantalla parezca de mentira.
  String article = 'del',
  String note =
      'Un idioma en blanco se queda marcado como pendiente en el fichero, '
      'no se borra el apartado.',
}) => showDialog<Map<String, String>>(
  context: context,
  builder: (context) => _HeadingTitles(
    heading: heading,
    languages: languages,
    titles: titles,
    reference: reference,
    article: article,
    note: note,
  ),
);

class _HeadingTitles extends StatefulWidget {
  const _HeadingTitles({
    required this.heading,
    required this.languages,
    required this.titles,
    required this.reference,
    required this.article,
    required this.note,
  });

  /// «Apartado» o «Subapartado», para el título del diálogo.
  final String heading;

  final List<String> languages;
  final Map<String, String> titles;

  /// El idioma del documento: el que hace de original cuando faltan otros.
  final String reference;

  final String article;

  /// Qué pasa con lo que se deje en blanco. Cambia según qué se esté
  /// titulando, y decirlo mal es peor que no decirlo.
  final String note;

  @override
  State<_HeadingTitles> createState() => _HeadingTitlesState();
}

class _HeadingTitlesState extends State<_HeadingTitles> {
  late final Map<String, TextEditingController> _fields = {
    for (final code in widget.languages)
      code: TextEditingController(text: widget.titles[code] ?? ''),
  };

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Título ${widget.article} ${widget.heading.toLowerCase()}'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final code in widget.languages) ...[
            TextField(
              key: Key('heading-title-$code'),
              controller: _fields[code],
              autofocus: code == widget.reference,
              decoration: InputDecoration(
                labelText: languageName(code),
                // El que falta se dice, y no se rellena con el de al lado:
                // un título prestado que parece traducido es la misma
                // trampa que copiar el original en el editor.
                helperText: (widget.titles[code] ?? '').isEmpty
                    ? 'sin traducir'
                    : null,
                helperStyle: const TextStyle(
                  fontSize: 11.5,
                  color: didactaTeacher,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Note(widget.note),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('heading-title-save'),
        onPressed: () => Navigator.of(context).pop({
          for (final entry in _fields.entries)
            entry.key: entry.value.text.trim(),
        }),
        child: const Text('Aceptar'),
      ),
    ],
  );
}

/// El lápiz que abre [editHeadingTitles].
///
/// El mismo en los cuatro sitios donde se titula algo --asignatura, tema,
/// documento y apartado--, porque es el mismo gesto: cambiar el título sin
/// tener que cambiar de idioma toda la pantalla y volver.
class TitleButton extends StatelessWidget {
  const TitleButton({
    super.key,
    required this.id,
    required this.what,
    required this.onPressed,
  });

  final String id;

  /// Qué se titula, ya con su artículo: «este tema», «esta asignatura». La
  /// frase entera y no el nombre suelto, porque el género cambia.
  final String what;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('edit-title-$id'),
    tooltip: 'Título de $what en todos los idiomas',
    visualDensity: VisualDensity.compact,
    icon: const Icon(Icons.edit_outlined, size: 15),
    onPressed: onPressed,
  );
}
