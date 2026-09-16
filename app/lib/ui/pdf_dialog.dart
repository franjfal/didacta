/// Ver lo compilado sin salir de donde estás.
///
/// La pantalla de un curso enseña treinta documentos y lo que se hace con
/// ellos todo el rato es mirar cómo ha quedado el PDF. Abrirlo en el visor
/// del sistema saca de la aplicación y pierde el sitio; navegar a la pantalla
/// del documento son dos clics y una vuelta. Un diálogo encima deja el listado
/// detrás y se cierra con Escape.
///
/// Dos filas de pestañas, y el orden entre ellas no es casual. Arriba el
/// **idioma**, porque es lo que menos cambia mientras se trabaja y lo que
/// manda sobre lo de abajo: cada idioma tiene sus versiones compiladas, y no
/// tienen por qué ser las mismas --el valenciano puede tener los apuntes y no
/// las diapositivas--. Debajo la **versión**, que es lo que distingue este
/// visor del de la pantalla del documento: allí se comparan idiomas lado a
/// lado mientras se edita, y aquí se trata de repasar las diapositivas, los
/// apuntes y la copia del profesor de lo mismo.
///
/// Entra seleccionado el idioma en el que se está trabajando. Si de ese no hay
/// nada compilado, el primero que haya: enseñar un visor vacío por respetar la
/// preferencia no ayuda a nadie.
library;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/compiler.dart';
import '../model/catalogue.dart';
import 'theme.dart';

Future<void> showBuiltPdfs(
  BuildContext context, {
  required String title,
  required List<ExistingOutput> outputs,
  String? language,
  List<LanguageOption> languages = const [],
  ValueChanged<String>? onOpenExternally,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (_) => BuiltPdfsDialog(
    title: title,
    outputs: outputs,
    language: language,
    languages: languages,
    onOpenExternally: onOpenExternally,
  ),
);

class BuiltPdfsDialog extends StatefulWidget {
  const BuiltPdfsDialog({
    super.key,
    required this.title,
    required this.outputs,
    this.language,
    this.languages = const [],
    this.onOpenExternally,
  });

  final String title;
  final List<ExistingOutput> outputs;

  /// En el que se está trabajando. Sale elegido si hay algo suyo compilado.
  final String? language;

  /// Cómo se llama cada idioma, para no enseñar códigos de dos letras a quien
  /// no tiene por qué saberlos. Lo que falte se enseña por su código.
  final List<LanguageOption> languages;

  final ValueChanged<String>? onOpenExternally;

  @override
  State<BuiltPdfsDialog> createState() => _BuiltPdfsDialogState();
}

class _BuiltPdfsDialogState extends State<BuiltPdfsDialog> {
  /// Lo que existe, por idioma, y las versiones de siempre primero.
  ///
  /// Quien abre esto quiere ver los apuntes o las diapositivas; la copia del
  /// profesor y la de con soluciones son variantes que se miran después.
  late final Map<String, List<ExistingOutput>> _byLanguage = () {
    final grouped = <String, List<ExistingOutput>>{};
    for (final output in widget.outputs) {
      if (!output.exists) continue;
      (grouped[output.language] ??= []).add(output);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.profile.compareTo(b.profile);
      });
    }
    return grouped;
  }();

  /// En el orden en que los declara la asignatura, y lo que no conozca detrás.
  late final List<String> _codes = [
    for (final option in widget.languages)
      if (_byLanguage.containsKey(option.code)) option.code,
    for (final code in _byLanguage.keys)
      if (!widget.languages.any((o) => o.code == code)) code,
  ];

  late String _language = _codes.contains(widget.language)
      ? widget.language!
      : (_codes.firstOrNull ?? '');

  int _at = 0;

  List<ExistingOutput> get _shown => _byLanguage[_language] ?? const [];

  String _nameOf(String code) {
    for (final option in widget.languages) {
      if (option.code == code) return option.name;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    if (_shown.isEmpty) {
      return const AlertDialog(
        content: Text('No hay ningún PDF compilado de esto todavía.'),
      );
    }
    final current = _shown[_at.clamp(0, _shown.length - 1)];

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, current),
            if (_codes.length > 1) _languages(),
            if (_shown.length > 1) _tabs(),
            Expanded(
              child: Container(
                color: didactaSurface,
                child: PdfViewer.file(
                  current.pdf,
                  // Con clave: cambiar de pestaña tiene que cargar el otro
                  // fichero, y sin esto el visor se queda con el primero.
                  key: ValueKey(current.pdf),
                  params: const PdfViewerParams(margin: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ExistingOutput current) => Container(
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                current.stale
                    ? '${current.label} · ${_nameOf(current.language)} · de '
                          'antes del último cambio'
                    : '${current.label} · ${_nameOf(current.language)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: current.stale ? didactaEx : didactaMuted,
                ),
              ),
            ],
          ),
        ),
        if (widget.onOpenExternally != null)
          IconButton(
            key: const Key('pdf-open-externally'),
            tooltip: 'Abrir en el visor del sistema',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.open_in_new, size: 17),
            onPressed: () => widget.onOpenExternally!(current.pdf),
          ),
        IconButton(
          key: const Key('pdf-dialog-close'),
          tooltip: 'Cerrar',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  /// La fila de idiomas, encima de la de versiones.
  ///
  /// Cambiar de idioma vuelve a la primera versión y no a la que estaba
  /// abierta: no tiene por qué existir ahí, y un índice que se sale de la
  /// lista es un visor en blanco.
  Widget _languages() => Container(
    decoration: const BoxDecoration(
      color: didactaPanel,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final code in _codes) ...[
            if (code != _codes.first) const SizedBox(width: 6),
            ChoiceChip(
              key: Key('pdf-language-$code'),
              label: Text(
                '${_nameOf(code)} · ${_byLanguage[code]!.length}',
                style: const TextStyle(fontSize: 12),
              ),
              selected: code == _language,
              onSelected: (_) => setState(() {
                _language = code;
                _at = 0;
              }),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _tabs() => Container(
    decoration: const BoxDecoration(
      color: didactaCard,
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < _shown.length; index += 1) ...[
            if (index > 0) const SizedBox(width: 6),
            ChoiceChip(
              key: Key('pdf-tab-${_shown[index].profile}'),
              label: Text(
                _shown[index].label,
                style: const TextStyle(fontSize: 12),
              ),
              selected: index == _at,
              onSelected: (_) => setState(() => _at = index),
            ),
          ],
        ],
      ),
    ),
  );
}
