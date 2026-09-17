/// Los huecos de traducción de un tema, en una pestaña.
///
/// Existe porque el hueco se descubre aquí. Se entra a preparar la clase en
/// valenciano, se compila, y salen tres lecciones en castellano en mitad del
/// tema. Hasta ahora había que apuntar cuáles eran, irse a la lista de
/// traducciones, buscarlas entre doscientas y traducirlas de una en una.
///
/// La pestaña solo aparece cuando falta algo: un sitio que siempre dice «no
/// falta nada» es una pestaña que se deja de mirar justo antes del día en que
/// sí faltaba.
///
/// Lo que se marca aquí son **lecciones**, no ficheros: a qué idiomas se
/// traduce lo decide el diálogo, que es donde ya se decide para todo lo demás.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../state/session.dart';
import 'theme.dart';
import 'translate_unit.dart';

/// Un hueco: una lección que no está en un idioma.
class TranslationGap {
  const TranslationGap({required this.unit, required this.languages});

  final Unit unit;

  /// Los idiomas que le faltan, de los que la asignatura usa.
  final List<String> languages;
}

/// Qué le falta a un documento, mirando las lecciones que compone.
///
/// Sobre los idiomas de la **asignatura** y no los del espacio de trabajo: un
/// tema que solo se da en castellano y valenciano no tiene un hueco en inglés,
/// tiene un idioma que no se usa.
List<TranslationGap> gapsIn({
  required Document document,
  required Catalogue catalogue,
  required List<String> languages,
}) {
  final gaps = <TranslationGap>[];
  final seen = <String>{};
  for (final reference in document.unitRefs) {
    final unit = catalogue.unitByReference(reference, repo: document.repo);
    if (unit == null || !seen.add(unit.path)) continue;
    final missing = [
      for (final code in languages)
        if (code != unit.reference && unit.statusIn(code).needsWork) code,
    ];
    if (missing.isEmpty) continue;
    gaps.add(TranslationGap(unit: unit, languages: missing));
  }
  return gaps;
}

class TranslateTab extends StatefulWidget {
  const TranslateTab({
    super.key,
    required this.session,
    required this.gaps,
    required this.language,
  });

  final Session session;
  final List<TranslationGap> gaps;

  /// En el que se está mirando, para los títulos.
  final String language;

  @override
  State<TranslateTab> createState() => _TranslateTabState();
}

class _TranslateTabState extends State<TranslateTab> {
  /// Por ruta y no por objeto: el catálogo se rehace al recargar, y guardar
  /// las unidades dejaría marcadas copias que ya no son las que se traducen.
  late Set<String> _picked = {
    for (final gap in widget.gaps)
      if (widget.session.canWriteIn(gap.unit.repo)) gap.unit.path,
  };

  List<TranslationGap> get _writable => [
    for (final gap in widget.gaps)
      if (widget.session.canWriteIn(gap.unit.repo)) gap,
  ];

  @override
  Widget build(BuildContext context) {
    final all = _writable.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: didactaPanel,
            border: Border(bottom: BorderSide(color: didactaRule)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.gaps.length == 1
                      ? 'A una lección de este tema le falta algún idioma'
                      : 'A ${widget.gaps.length} lecciones de este tema les '
                            'falta algún idioma',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (all > 0) ...[
                TextButton(
                  key: const Key('gaps-all'),
                  onPressed: _picked.length == all
                      ? null
                      : () => setState(() {
                          _picked = {
                            for (final gap in _writable) gap.unit.path,
                          };
                        }),
                  child: const Text('Todas'),
                ),
                TextButton(
                  key: const Key('gaps-none'),
                  onPressed: _picked.isEmpty
                      ? null
                      : () => setState(_picked.clear),
                  child: const Text('Ninguna'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  key: const Key('gaps-translate'),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                  label: Text(
                    _picked.length == 1
                        ? 'Traducir 1'
                        : 'Traducir ${_picked.length}',
                  ),
                  onPressed: _picked.isEmpty ? null : _translate,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: widget.gaps.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final gap = widget.gaps[index];
              final canWrite = widget.session.canWriteIn(gap.unit.repo);
              return CheckboxListTile(
                key: Key('gap-${gap.unit.path}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _picked.contains(gap.unit.path),
                onChanged: !canWrite
                    ? null
                    : (on) => setState(() {
                        if (on ?? false) {
                          _picked.add(gap.unit.path);
                        } else {
                          _picked.remove(gap.unit.path);
                        }
                      }),
                title: Text(
                  gap.unit.title(widget.language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: Text(
                        gap.unit.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: didactaMuted,
                        ),
                      ),
                    ),
                    // Qué le falta, con su nombre. «va, en» dice más que un
                    // «2 idiomas» y ocupa lo mismo.
                    Text(
                      canWrite
                          ? 'falta ${gap.languages.join(', ')}'
                          : 'solo lectura',
                      style: TextStyle(
                        fontSize: 11,
                        color: canWrite ? didactaTeacher : didactaMuted,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _translate() async {
    final messenger = ScaffoldMessenger.of(context);
    final units = [
      for (final gap in widget.gaps)
        if (_picked.contains(gap.unit.path)) gap.unit,
    ];
    final result = await translateWith(
      context,
      session: widget.session,
      units: units,
    );
    if (result == null || !mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${result.done} traducidos'
          '${result.failed > 0 ? ', ${result.failed} sin hacer' : ''}',
        ),
      ),
    );
  }
}
