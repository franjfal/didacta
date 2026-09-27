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
import '../l10n/tr.dart';

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
List<(String, String)> get documentKinds => [
  ('theory', tr('Teoría')),
  ('problems', tr('Problemas')),
  ('exam', tr('Examen')),
  ('seminar', tr('Seminario')),
  ('practical', tr('Práctica')),
  ('handout', tr('Guía')),
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
      title: Text(tr('Nuevo grupo')),
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
                labelText: tr('Título en {0}', [widget.language]),
                hintText: tr('Tema 3. Series de funciones'),
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
                labelText: tr('Identificador'),
                helperText: tr('Lo que se escribe en year.yaml y en la URL'),
                errorText: taken
                    ? tr('Ya hay un grupo con ese identificador')
                    : (id.isEmpty || _valid
                          ? null
                          : tr('Minúsculas, dígitos y guiones')),
              ),
              onChanged: (_) => setState(() => _idTyped = true),
            ),
            const SizedBox(height: 14),
            Text(
              tr('Tipo'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
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
            Note(
              tr(
                'Se crea vacío. El paso siguiente es abrirlo y elegir qué '
                'unidades lleva y en qué orden.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar')),
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
          child: Text(tr('Crear')),
        ),
      ],
    );
  }
}

/// Pide los datos de un tema.
///
/// Un tema es un bloque del curso --el Tema 1, con su teoría, sus problemas y
/// su bibliografía-- y lo único que hace falta para declararlo es cómo se
/// llama. El id se deduce del título, como en las asignaturas: nadie quiere
/// escribir `tema-1-el-numero-real` a mano, y el que se escribe a mano acaba
/// siendo distinto del que habría salido.
class NewThemeDialog extends StatefulWidget {
  const NewThemeDialog({
    super.key,
    required this.taken,
    required this.language,
  });

  /// Los ids de tema que ya están en este curso.
  final List<String> taken;
  final String language;

  @override
  State<NewThemeDialog> createState() => _NewThemeDialogState();
}

class NewTheme {
  const NewTheme({required this.id, required this.title});

  final String id;
  final String title;
}

class _NewThemeDialogState extends State<NewThemeDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _id = TextEditingController();

  /// Si el id lo escribió la persona. Mientras no, se deduce del título.
  bool _idTyped = false;

  @override
  void dispose() {
    _title.dispose();
    _id.dispose();
    super.dispose();
  }

  String get _slug => _idTyped ? _id.text.trim() : slugify(_title.text);

  bool get _taken => widget.taken.contains(_slug);

  bool get _valid => _slug.isNotEmpty && !_taken;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Nuevo tema')),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Un bloque del curso, con todo lo suyo dentro: la teoría, los '
              'problemas, la bibliografía. Se crea vacío y los documentos se '
              'añaden desde él.',
            ),
            style: TextStyle(fontSize: 12.5, color: context.palette.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('new-theme-title'),
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('Cómo se llama'),
              hintText: tr('Tema 1: el número y la recta real'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('new-theme-id'),
            controller: _idTyped ? _id : (TextEditingController(text: _slug)),
            decoration: InputDecoration(
              labelText: tr('Identificador'),
              helperText: tr('Lo que escriben los documentos en `themes:`'),
              errorText: _taken
                  ? tr('Ya hay un tema con ese identificador')
                  : null,
            ),
            onChanged: (value) => setState(() {
              _idTyped = true;
              _id.text = value;
            }),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Cancelar')),
      ),
      FilledButton(
        key: const Key('confirm-new-theme'),
        onPressed: _valid
            ? () => Navigator.of(
                context,
              ).pop(NewTheme(id: _slug, title: _title.text.trim()))
            : null,
        child: Text(tr('Crear')),
      ),
    ],
  );
}
