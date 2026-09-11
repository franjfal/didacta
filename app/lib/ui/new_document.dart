/// Crear un grupo de contenido dentro de un año.
///
/// Un «grupo» es lo que `year.yaml` llama un documento: un tema, una hoja de
/// problemas, un seminario. Se crea vacío --sin unidades-- porque elegirlas
/// es el paso siguiente y tiene su propia pantalla, la de composición.
///
/// El identificador se deduce del título, como en una asignatura nueva, y por
/// la misma razón: es el nombre que acaba en el fichero y en la URL, y nadie
/// quiere escribirlo dos veces. Se puede cambiar a mano, y entonces manda lo
/// escrito.
library;

import 'package:flutter/material.dart';

import '../model/slug.dart';
import 'theme.dart';

/// Lo que el diálogo devuelve.
class NewDocument {
  const NewDocument({
    required this.id,
    required this.kind,
    required this.title,
    required this.pending,
  });

  final String id;
  final String kind;

  /// El título, en el idioma que se está mirando.
  final Map<String, String> title;

  /// Los idiomas que quedan por poner. Van comentados en el fichero, no como
  /// un título que diga «TODO»: eso sería un título de verdad, y saldría en
  /// la lista y dentro del PDF.
  final List<String> pending;
}

/// Los tipos que un grupo puede tener, con nombre en castellano.
///
/// Son los del esquema, no una lista nueva: el motor decide con `kind` qué
/// perfiles puede compilar un documento, así que inventarse uno aquí daría un
/// documento que no compila en nada.
const List<(String, String)> documentKinds = [
  ('theory', 'Teoría'),
  ('problems', 'Problemas'),
  ('seminar', 'Seminario'),
  ('practical', 'Práctica'),
  ('handout', 'Guía'),
];

class NewDocumentDialog extends StatefulWidget {
  const NewDocumentDialog({
    super.key,
    required this.taken,
    required this.language,
    required this.languages,
  });

  /// Los ids que ya están en este año.
  final List<String> taken;
  final String language;
  final List<String> languages;

  @override
  State<NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<NewDocumentDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _id = TextEditingController();
  String _kind = 'theory';
  bool _idTyped = false;

  @override
  void dispose() {
    _title.dispose();
    _id.dispose();
    super.dispose();
  }

  bool get _valid {
    final id = _id.text.trim();
    return RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id) &&
        !widget.taken.contains(id) &&
        _title.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final id = _id.text.trim();
    final taken = widget.taken.contains(id);
    return AlertDialog(
      title: const Text('Nuevo grupo'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('new-document-title'),
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Título en ${widget.language}',
                hintText: 'Tema 3. Series de funciones',
              ),
              onChanged: (value) => setState(() {
                if (!_idTyped) _id.text = slugify(value);
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('new-document-id'),
              controller: _id,
              decoration: InputDecoration(
                labelText: 'Identificador',
                helperText: 'Lo que se escribe en year.yaml y en la URL',
                errorText: taken
                    ? 'Ya hay un grupo con ese identificador'
                    : (id.isEmpty || _valid
                          ? null
                          : 'Minúsculas, dígitos y guiones'),
              ),
              onChanged: (_) => setState(() => _idTyped = true),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tipo',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final (value, label) in documentKinds)
                  ChoiceChip(
                    key: Key('kind-$value'),
                    label: Text(label),
                    selected: _kind == value,
                    onSelected: (_) => setState(() => _kind = value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Note(
              'Se crea vacío. El paso siguiente es abrirlo y elegir qué '
              'unidades lleva y en qué orden.',
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
          key: const Key('confirm-new-document'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                  NewDocument(
                    id: _id.text.trim(),
                    kind: _kind,
                    title: {widget.language: _title.text.trim()},
                    // Los demás, marcados como pendientes: es la forma que
                    // usa el repositorio y la lista de lo que queda por
                    // traducir.
                    pending: [
                      for (final code in widget.languages)
                        if (code != widget.language) code,
                    ],
                  ),
                )
              : null,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
