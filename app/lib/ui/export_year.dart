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
///
/// Lo que sí viene apagado es todo lo que no es para el estudiante. La
/// carpeta acaba en el aula virtual, y la plantilla de corrección del examen
/// no puede ir detrás solo porque estaba compilada: las resoluciones se
/// piden con una casilla y las copias del profesor con otra, aparte y en
/// rojo, que es el color de lo que no se reparte.
library;

import 'package:flutter/material.dart';

import '../data/compiler.dart';
import '../model/catalogue.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que la pantalla decide.
class ExportRequest {
  const ExportRequest({
    required this.languages,
    required this.documents,
    required this.rebuild,
    this.reach = ExportReach.students,
    this.rebuildOnly = const [],
    this.zip = false,
    this.html = false,
  });

  /// Si, además de los PDF, salen los apuntes en HTML accesible.
  final bool html;

  /// Los documentos que hay que compilar antes, cuando no se compila todo:
  /// los que tienen algún PDF viejo o sin compilar en lo que se exporta.
  final List<String> rebuildOnly;

  /// Si, además de la carpeta, sale un .zip con todo.
  final bool zip;

  final List<String> languages;

  /// Qué documentos, ya resueltos: la selección se hace por tema y por
  /// documento, pero lo que sale de aquí es la lista plana, que es lo que el
  /// motor entiende.
  final List<String> documents;

  /// Si hay que compilarlos antes de copiarlos.
  final bool rebuild;

  /// Hasta dónde puede enseñar lo que sale.
  final ExportReach reach;
}

class ExportYearDialog extends StatefulWidget {
  const ExportYearDialog({
    super.key,
    required this.course,
    required this.year,
    required this.entry,
    required this.languages,
    required this.language,
    this.outputs,
    this.reveals = const {},
    this.publishTo,
  });

  /// Dónde se publica, cuando esto es «Publicar» y no «Exportar»: la
  /// carpeta de este curso dentro de la de reparto.
  final String? publishTo;

  final Course course;
  final String year;
  final CourseYear entry;

  /// Lo que hay compilado de cada documento, por id. Null si no se sabe: sin
  /// motor no hay a quién preguntar, y entonces no se avisa de nada en vez
  /// de avisar de todo.
  final Map<String, List<ExistingOutput>>? outputs;

  /// Hasta dónde enseña cada plantilla, por id: una copia del profesor vieja
  /// no es motivo de aviso en un reparto que no la lleva.
  final Map<String, String> reveals;

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

  /// Compilar antes lo que está viejo o sin compilar. Marcado: repartir un
  /// PDF de antes de la última corrección es justo lo que no se nota hasta
  /// que un estudiante pregunta.
  bool _rebuildBehind = true;
  bool _zip = false;
  bool _html = false;
  ExportReach _reach = ExportReach.students;

  static const List<String> _revealOrder = [
    'statements',
    'answers',
    'solutions',
    'teacher',
  ];

  /// Si esta versión sale con el alcance elegido.
  bool _exported(ExistingOutput output) {
    final reveals = widget.reveals[output.profile];
    if (reveals == null) return true;
    return _revealOrder.indexOf(reveals) <=
        _revealOrder.indexOf(_reach.engineName);
  }

  /// Los documentos elegidos con algún PDF viejo o sin compilar en lo que se
  /// va a exportar, en el orden del curso.
  List<Document> get _behind {
    final outputs = widget.outputs;
    if (outputs == null) return const [];
    return [
      for (final document in widget.entry.documents)
        if (_documents.contains(document.id) &&
            _isBehind(outputs[document.id] ?? const []))
          document,
    ];
  }

  bool _isBehind(List<ExistingOutput> found) {
    for (final language in _languages) {
      final here = [
        for (final output in found)
          if (output.language == language && _exported(output)) output,
      ];
      if (here.isEmpty) return true;
      if (here.any((output) => !output.exists || output.stale)) return true;
    }
    return false;
  }

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

  /// «Tema 1, Hoja 2 y 3 más».
  String _names(List<Document> documents) {
    final titles = [
      for (final document in documents.take(3))
        '«${document.title(widget.language)}»',
    ];
    final rest = documents.length - titles.length;
    if (rest > 0) return tr('{0} y {1} más', [titles.join(', '), rest]);
    if (titles.length == 1) return titles.single;
    return tr('{0} y {1}', [
      titles.sublist(0, titles.length - 1).join(', '),
      titles.last,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final everything = _documents.length == widget.entry.documents.length;
    final behind = _behind;
    return AlertDialog(
      title: Text(
        widget.publishTo == null
            ? tr('Exportar {0} · {1}', [widget.course.title(), widget.year])
            : tr('Publicar {0} · {1}', [widget.course.title(), widget.year]),
      ),
      content: SizedBox(
        width: 600,
        // Lo que quepa en la ventana, sin pasar de lo que hace falta: en una
        // pantalla baja la lista de documentos se encoge, que es la parte que
        // ya se desplaza.
        height: (MediaQuery.sizeOf(context).height - 200).clamp(360, 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.publishTo == null
                  ? tr(
                      'Saca los PDF a una carpeta, ordenados por tema. Con más de '
                      'un idioma, cada uno va en su propia carpeta. Sin tocar '
                      'nada, solo sale lo que puede ver un estudiante.',
                    )
                  : tr(
                      'A la carpeta de reparto, que se sincroniza sola: '
                      '{0}. Ordenado por tema, y sin tocar '
                      'nada, solo lo que puede ver un estudiante.',
                      [widget.publishTo],
                    ),
              key: const Key('export-intro'),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 12),
            Text(
              tr('Idiomas'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
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
                Text(
                  tr('Qué se exporta'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
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
                  child: Text(everything ? tr('Ninguno') : tr('Todos')),
                ),
              ],
            ),
            Expanded(
              // En un `Material` y no en una caja con color: una casilla
              // pinta su fondo y su pulsación sobre el `Material` más
              // cercano, y una caja de color en medio los tapa.
              child: Material(
                color: context.palette.card,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: context.palette.rule),
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
            // Las resoluciones van incluidas en las copias del profesor: con
            // esa marcada, esta se ve marcada y no se puede quitar, que es
            // la verdad de lo que va a salir.
            CheckboxListTile(
              key: const Key('export-solutions'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _reach != ExportReach.students,
              onChanged: _reach == ExportReach.teacher
                  ? null
                  : (on) => setState(
                      () => _reach = (on ?? false)
                          ? ExportReach.solutions
                          : ExportReach.students,
                    ),
              title: Text(
                tr('Con las resoluciones completas'),
                style: TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                tr(
                  'Los apuntes y las hojas resueltas. Sin marcar, salen los '
                  'enunciados y, como mucho, los resultados.',
                ),
                style: TextStyle(fontSize: 11.5),
              ),
            ),
            CheckboxListTile(
              key: const Key('export-teacher'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.palette.teacher,
              value: _reach == ExportReach.teacher,
              onChanged: (on) => setState(
                () => _reach = (on ?? false)
                    ? ExportReach.teacher
                    : ExportReach.students,
              ),
              title: Text(
                tr('También las copias del profesor'),
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.teacher,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                tr(
                  'La plantilla de corrección del examen y las notas de clase. '
                  'No es para el aula virtual.',
                ),
                style: TextStyle(fontSize: 11.5),
              ),
            ),
            if (behind.isNotEmpty) ...[
              const SizedBox(height: 4),
              Note(
                key: const Key('export-stale'),
                tr(
                  '{0} '
                  'algún PDF desactualizado o sin compilar: '
                  '{1}.',
                  [
                    behind.length == 1
                        ? tr('Un documento tiene')
                        : tr('{0} documentos tienen', [behind.length]),
                    _names(behind),
                  ],
                ),
                tone: context.palette.teacher,
              ),
              CheckboxListTile(
                key: const Key('export-rebuild-stale'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _rebuild || _rebuildBehind,
                onChanged: _rebuild
                    ? null
                    : (on) => setState(() => _rebuildBehind = on ?? false),
                title: Text(
                  behind.length == 1
                      ? tr('Compilar antes solo ese')
                      : tr('Compilar antes solo esos {0}', [behind.length]),
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  tr('Lo demás está al día y se copia tal cual.'),
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
            CheckboxListTile(
              key: const Key('export-rebuild'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _rebuild,
              onChanged: (on) => setState(() => _rebuild = on ?? false),
              title: Text(
                tr('Compilarlo todo antes de exportar'),
                style: TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                tr(
                  'Puede tardar. Sin marcar, se exporta lo que ya esté '
                  'compilado y se dice qué falta.',
                ),
                style: TextStyle(fontSize: 11.5),
              ),
            ),
            // Los dos formatos de más, en una fila: son decisiones pequeñas y
            // cada casilla le quitaba a la lista de documentos el alto de
            // una fila y media. Lo que hace cada una, al pasar por encima.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    tr('También:'),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.muted,
                    ),
                  ),
                  Tooltip(
                    message: tr(
                      'Para el aula virtual: Moodle lo descomprime en un '
                      'recurso Carpeta, con los temas dentro.',
                    ),
                    child: FilterChip(
                      key: const Key('export-zip'),
                      avatar: const Icon(Icons.folder_zip_outlined, size: 16),
                      label: Text(tr('un .zip con todo')),
                      selected: _zip,
                      showCheckmark: false,
                      onSelected: (on) => setState(() => _zip = on),
                    ),
                  ),
                  // Para quien lee con un lector de pantalla o necesita el
                  // texto grande: lo que piden los servicios de
                  // accesibilidad.
                  Tooltip(
                    message: tr(
                      'Para leerlos con un lector de pantalla o con el '
                      'texto grande: una página al lado de cada PDF, con las '
                      'mismas reglas. Las diapositivas no: se leen en sus '
                      'apuntes.',
                    ),
                    child: FilterChip(
                      key: const Key('export-html'),
                      avatar: const Icon(
                        Icons.accessibility_new_outlined,
                        size: 16,
                      ),
                      label: Text(tr('los apuntes en HTML')),
                      selected: _html,
                      showCheckmark: false,
                      onSelected: (on) => setState(() => _html = on),
                    ),
                  ),
                ],
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
                    rebuildOnly: _rebuild || !_rebuildBehind
                        ? const []
                        : [for (final document in behind) document.id],
                    reach: _reach,
                    zip: _zip,
                    html: _html,
                  ),
                )
              : null,
          child: Text(
            widget.publishTo == null
                ? tr('Exportar {0}', [_documents.length])
                : tr('Publicar {0}', [_documents.length]),
          ),
        ),
      ],
    );
  }

  List<Widget> _groupTiles(ThemedDocuments group) {
    final title = group.isLoose
        ? tr('Sin tema')
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
