/// Sacar un curso a una carpeta, para repartirlo.
///
/// Lo que se lleva alguien al aula virtual o a un disco: los PDF ya
/// compilados, en carpetas con nombres que se leen. El repositorio no se
/// toca; lo que sale es una copia.
///
/// Tres decisiones en una pantalla, porque son la misma: en qué idiomas, qué
/// temas y qué documentos de cada tema. Todo viene marcado, que es lo que se
/// quiere casi siempre, y desmarcar es más rápido que buscar.
///
/// La casilla de recompilar está apagada de salida a propósito. Un curso
/// entero son cuarenta salidas y media hora; quien acaba de compilarlo no
/// quiere repetirlo por exportar, y quien lo necesita lo marca. Lo que no
/// esté compilado no se exporta y se dice cuál falta, en lugar de salir un
/// reparto al que le faltan tres PDF sin que nadie se entere.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import 'theme.dart';

/// Lo que la pantalla decide.
class ExportRequest {
  const ExportRequest({
    required this.languages,
    required this.documents,
    required this.rebuild,
  });

  final List<String> languages;

  /// Qué documentos, ya resueltos: la selección se hace por tema y por
  /// documento, pero lo que sale de aquí es la lista plana, que es lo que el
  /// motor entiende.
  final List<String> documents;

  /// Si hay que compilarlos antes de copiarlos.
  final bool rebuild;
}

class ExportYearDialog extends StatefulWidget {
  const ExportYearDialog({
    super.key,
    required this.course,
    required this.year,
    required this.entry,
    required this.languages,
    required this.language,
  });

  final Course course;
  final String year;
  final CourseYear entry;

  /// Los idiomas entre los que elegir: los de la asignatura.
  final List<String> languages;

  /// El que se está mirando, para los títulos.
  final String language;

  @override
  State<ExportYearDialog> createState() => _ExportYearDialogState();
}

class _ExportYearDialogState extends State<ExportYearDialog> {
  late final Set<String> _languages = {
    if (widget.languages.isNotEmpty) widget.languages.first,
  };
  late final Set<String> _documents = {
    for (final document in widget.entry.documents) document.id,
  };
  bool _rebuild = false;

  /// Los temas con lo que llevan, y los sueltos al final.
  late final List<ThemedDocuments> _groups = widget.entry.byTheme;

  bool get _valid => _languages.isNotEmpty && _documents.isNotEmpty;

  bool _allChosen(ThemedDocuments group) =>
      group.documents.isNotEmpty &&
      group.documents.every((d) => _documents.contains(d.id));

  bool _someChosen(ThemedDocuments group) =>
      group.documents.any((d) => _documents.contains(d.id));

  void _toggleGroup(ThemedDocuments group, bool on) => setState(() {
    for (final document in group.documents) {
      if (on) {
        _documents.add(document.id);
      } else {
        _documents.remove(document.id);
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final everything = _documents.length == widget.entry.documents.length;
    return AlertDialog(
      title: Text('Exportar ${widget.course.title()} · ${widget.year}'),
      content: SizedBox(
        width: 600,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saca los PDF a una carpeta, ordenados por tema. Con más de un '
              'idioma, cada uno va en su propia carpeta.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            const SizedBox(height: 12),
            const Text(
              'Idiomas',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              children: [
                for (final code in widget.languages)
                  FilterChip(
                    key: Key('export-language-$code'),
                    label: Text(code),
                    selected: _languages.contains(code),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _languages.add(code);
                      } else {
                        _languages.remove(code);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Qué se exporta',
                  style: TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('export-toggle-all'),
                  onPressed: () => setState(() {
                    if (everything) {
                      _documents.clear();
                    } else {
                      _documents.addAll(
                        widget.entry.documents.map((d) => d.id),
                      );
                    }
                  }),
                  child: Text(everything ? 'Ninguno' : 'Todos'),
                ),
              ],
            ),
            Expanded(
              // En un `Material` y no en una caja con color: una casilla
              // pinta su fondo y su pulsación sobre el `Material` más
              // cercano, y una caja de color en medio los tapa.
              child: Material(
                color: didactaCard,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: didactaRule),
                  borderRadius: BorderRadius.circular(4),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final group in _groups) ..._groupTiles(group),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('export-rebuild'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _rebuild,
              onChanged: (on) => setState(() => _rebuild = on ?? false),
              title: const Text(
                'Compilarlo todo antes de exportar',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'Puede tardar. Sin marcar, se exporta lo que ya esté '
                'compilado y se dice qué falta.',
                style: TextStyle(fontSize: 11.5),
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
          key: const Key('export-confirm'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                  ExportRequest(
                    languages: [
                      for (final code in widget.languages)
                        if (_languages.contains(code)) code,
                    ],
                    documents: [
                      for (final document in widget.entry.documents)
                        if (_documents.contains(document.id)) document.id,
                    ],
                    rebuild: _rebuild,
                  ),
                )
              : null,
          child: Text('Exportar ${_documents.length}'),
        ),
      ],
    );
  }

  List<Widget> _groupTiles(ThemedDocuments group) {
    final title = group.isLoose
        ? 'Sin tema'
        : group.theme!.title(widget.language);
    return [
      CheckboxListTile(
        key: Key('export-theme-${group.theme?.id ?? 'loose'}'),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: _allChosen(group)
            ? true
            : _someChosen(group)
            ? null
            : false,
        tristate: true,
        onChanged: (_) => _toggleGroup(group, !_allChosen(group)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      for (final document in group.documents)
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: CheckboxListTile(
            key: Key('export-document-${document.id}'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _documents.contains(document.id),
            onChanged: (on) => setState(() {
              if (on ?? false) {
                _documents.add(document.id);
              } else {
                _documents.remove(document.id);
              }
            }),
            title: Text(
              document.title(widget.language),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ),
    ];
  }
}
