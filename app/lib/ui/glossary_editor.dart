/// El glosario, en Ajustes: los términos que una traducción tiene que respetar.
///
/// Una tabla y no un fichero: un término por fila y un idioma por columna,
/// que es como se piensa en él --«sucesión, successió, sequence»-- y como
/// queda guardado, en `translation/glossary.tsv`. Uno por repositorio; al
/// traducir se juntan los de todos. Ver `model/glossary.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../model/glossary.dart';
import '../state/session.dart';
import 'problem.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// El resumen en Ajustes, con el botón que abre la tabla.
class GlossarySection extends StatefulWidget {
  const GlossarySection({super.key, required this.session});

  final Session session;

  @override
  State<GlossarySection> createState() => _GlossarySectionState();
}

class _GlossarySectionState extends State<GlossarySection> {
  Glossary? _all;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final all = await widget.session.glossary();
    if (mounted) setState(() => _all = all);
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final writable = [
      for (final repo in widget.session.snippetRepos)
        if (widget.session.canWriteIn(repo)) repo,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Los términos que una traducción tiene que respetar: '
                  '«sucesión» es «successió» y no «seqüència». Al traducir con '
                  'la máquina, lo que no salga así se avisa para mirarlo. No se '
                  'cambia solo: una palabra sustituida puede no concordar con '
                  'el resto de la frase.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              Text(
                all == null
                    ? tr('Leyendo…')
                    : all.isEmpty
                    ? tr('Ningún término todavía.')
                    : tr(
                        '{0} término(s), en '
                        '{1}.',
                        [all.terms.length, all.languages.join(', ')],
                      ),
                key: const Key('glossary-summary'),
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('open-glossary'),
                icon: const Icon(Icons.menu_book_outlined, size: 15),
                label: Text(tr('Editar el glosario')),
                onPressed: writable.isEmpty
                    ? null
                    : () async {
                        await showDialog<void>(
                          context: context,
                          builder: (context) => GlossaryDialog(
                            session: widget.session,
                            repos: writable,
                          ),
                        );
                        await _load();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La tabla: un término por fila, un idioma por columna.
class GlossaryDialog extends StatefulWidget {
  const GlossaryDialog({super.key, required this.session, required this.repos});

  final Session session;

  /// Los repositorios en los que se puede escribir: de cuál es el glosario.
  final List<String> repos;

  @override
  State<GlossaryDialog> createState() => _GlossaryDialogState();
}

class _GlossaryDialogState extends State<GlossaryDialog> {
  late String _repo = widget.repos.first;
  List<String> _languages = const [];
  final List<Map<String, TextEditingController>> _rows = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final row in _rows) {
      for (final controller in row.values) {
        controller.dispose();
      }
    }
    _rows.clear();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final found = await widget.session.glossaryIn(_repo);
    if (!mounted) return;
    // Los idiomas del repositorio, y detrás los que ya tuviera el fichero.
    final own = widget.session.catalogue.languagesOf(_repo);
    final languages = [
      ...own,
      for (final code in found.languages)
        if (!own.contains(code)) code,
    ];
    setState(() {
      _clear();
      _languages = languages;
      for (final term in found.terms) {
        _rows.add({
          for (final code in languages)
            code: TextEditingController(text: term[code] ?? ''),
        });
      }
      if (_rows.isEmpty) _addRow();
      _loading = false;
    });
  }

  void _addRow() =>
      _rows.add({for (final code in _languages) code: TextEditingController()});

  Glossary get _current => Glossary(
    languages: _languages,
    terms: [
      for (final row in _rows)
        {
          for (final entry in row.entries)
            if (entry.value.text.trim().isNotEmpty)
              entry.key: entry.value.text.trim(),
        },
    ].where((term) => term.length >= 2).toList(),
  );

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final glossary = _current;
      await widget.session.saveGlossary(_repo, glossary);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr('Glosario guardado: {0} término(s).', [glossary.terms.length]),
          ),
        ),
      );
      navigator.pop();
    } catch (error) {
      showProblemIn(messenger, error);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AlertDialog(
      title: Text(tr('Glosario de traducción')),
      content: SizedBox(
        width: 760,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.repos.length > 1)
                    Row(
                      children: [
                        Text(
                          tr('De'),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          key: const Key('glossary-repo'),
                          value: _repo,
                          isDense: true,
                          items: [
                            for (final repo in widget.repos)
                              DropdownMenuItem(
                                value: repo,
                                child: Text(
                                  session.workspace.byId(repo)?.label ?? repo,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _repo = value;
                            unawaited(_load());
                          },
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      'Un término por fila. Una fila con un solo idioma no dice '
                      'nada y no se guarda.',
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final code in _languages)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              code,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            for (final code in _languages)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: TextField(
                                    key: Key('glossary-$index-$code'),
                                    controller: _rows[index][code],
                                    style: const TextStyle(fontSize: 13),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: 40,
                              child: IconButton(
                                tooltip: tr('Quitar este término'),
                                icon: const Icon(Icons.close, size: 15),
                                onPressed: () => setState(() {
                                  for (final controller
                                      in _rows[index].values) {
                                    controller.dispose();
                                  }
                                  _rows.removeAt(index);
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('glossary-add'),
                      icon: const Icon(Icons.add, size: 15),
                      label: Text(tr('Otro término')),
                      onPressed: () => setState(_addRow),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('glossary-save'),
          onPressed: _loading || _saving ? null : _save,
          child: Text(tr('Guardar')),
        ),
      ],
    );
  }
}
