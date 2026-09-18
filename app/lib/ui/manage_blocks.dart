/// Los bloques: verlos, declararlos, renombrarlos y quitarlos.
///
/// Un bloque es una parte de la asignatura --la teoría, los problemas, las
/// prácticas de ordenador-- y cada lección dice a cuál pertenece. Eran dos y
/// estaban escritos en el código; ahora se declaran en `taxonomy.yaml`, así
/// que se pueden renombrar y se les pueden añadir otros.
///
/// **Quién declara qué importa.** Un bloque lo declara un repositorio y las
/// unidades de cualquier otro lo nombran; con que uno lo declare, todos lo ven
/// con su nombre. Declararlo en varios no rompe nada --se juntan por id-- pero
/// es lo que hace que luego discrepen, y por eso aquí se ve y se toca en qué
/// repositorios está cada uno.
///
/// Y nada de esto puede esconder material. Un bloque que no declara ningún
/// repositorio abierto no hace desaparecer sus lecciones: salen igual, con el
/// bloque enseñado por su id, y «Entre repositorios» dice que falta
/// declararlo. Por eso quitar un bloque pregunta antes qué se hace con sus
/// lecciones en vez de dejarlas calladas en ninguna parte.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/library_tree.dart' show languageName;
import '../model/slug.dart';
import '../state/session.dart';
import 'sync_bar.dart';
import 'theme.dart';

Future<void> showBlocks(BuildContext context, Session session) =>
    showDialog<void>(
      context: context,
      builder: (context) => BlocksDialog(session: session),
    );

/// Declarar un bloque que alguna lección ya nombra, desde donde se ve el
/// problema.
///
/// Aquí y no solo en Ajustes porque el sitio donde alguien se entera de que
/// un bloque no está declarado es «Entre repositorios», y mandarle a otra
/// pantalla a repetir el id que acaba de leer es la forma más segura de que
/// lo escriba mal.
///
/// Devuelve si se declaró.
Future<bool> declareNamedBlock(
  BuildContext context,
  Session session,
  String id,
) async {
  final writable = [
    for (final repo in session.workspace.repos)
      if (session.canWriteIn(repo.id)) repo.id,
  ];
  if (writable.isEmpty) return false;

  final answer = await showDialog<_NewBlock>(
    context: context,
    builder: (context) =>
        _NewBlockDialog(repos: writable, session: session, fixedId: id),
  );
  if (answer == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    for (final repo in answer.repos) {
      await session.declareBlock(
        repo: repo,
        id: answer.id,
        titles: answer.titles,
      );
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Bloque «${answer.id}» declarado.')),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
    return false;
  }
}

/// Mover a otro bloque las lecciones que nombren [from].
///
/// La otra salida para un bloque huérfano: si nadie va a declararlo, sus
/// lecciones tienen que ir a alguno que exista. Devuelve cuántas se movieron,
/// o null si no se llegó a hacer nada.
Future<int?> moveBlockLessons(
  BuildContext context,
  Session session,
  String from,
) async {
  final others = [
    for (final block in session.catalogue.blocks)
      if (block.id != from) block,
  ];
  if (others.isEmpty) return null;

  final to = await showDialog<String>(
    context: context,
    builder: (context) => _MoveLessonsDialog(
      from: from,
      lessons: session.catalogue.unitsInBlock(from).length,
      others: others,
      language: session.language,
    ),
  );
  if (to == null || !context.mounted) return null;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final moved = await session.moveUnitsBetweenBlocks(from: from, to: to);
    messenger.showSnackBar(
      SnackBar(content: Text('${_lessons(moved)} movidas a «$to».')),
    );
    return moved;
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
    return null;
  }
}

class BlocksDialog extends StatefulWidget {
  const BlocksDialog({super.key, required this.session});

  final Session session;

  @override
  State<BlocksDialog> createState() => _BlocksDialogState();
}

class _BlocksDialogState extends State<BlocksDialog> {
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final catalogue = session.catalogue;
    final blocks = catalogue.blocks;
    final missing = catalogue.undeclaredBlocks;
    final writable = [
      for (final repo in session.workspace.repos)
        if (session.canWriteIn(repo.id)) repo.id,
    ];

    return AlertDialog(
      title: const Text('Bloques'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: ListView(
          children: [
            const Text(
              'Un bloque es una parte de la asignatura, y cada lección dice a '
              'cuál pertenece. Lo declara un repositorio y las lecciones de '
              'cualquier otro lo nombran: con que uno lo declare, todos lo '
              'ven con su nombre.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            if (blocks.isEmpty && missing.isEmpty)
              const Note('Todavía no hay ninguno declarado.')
            else
              for (final block in blocks)
                _BlockRow(
                  session: session,
                  block: block,
                  writable: writable,
                  busy: _busy == block.id,
                  onRename: () => _rename(block),
                  onRemove: () => _remove(block),
                  onToggle: (repo, declared) =>
                      _toggle(block, repo, declared: declared),
                ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Nombrados y sin declarar',
                style: TextStyle(fontSize: 11.5, color: didactaTeacher),
              ),
              const SizedBox(height: 2),
              const Text(
                'Alguna lección dice pertenecer a estos y ningún repositorio '
                'abierto los declara. Se ven enteras, con el bloque enseñado '
                'por su id. Decláralos aquí, o abre el repositorio donde '
                'estén.',
                style: TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
              const SizedBox(height: 6),
              for (final id in missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$id · ${_lessons(catalogue.unitsInBlock(id).length)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (writable.isNotEmpty)
                        TextButton(
                          key: Key('declare-block-$id'),
                          onPressed: () => _create(writable, id: id),
                          child: const Text('Declarar'),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (writable.isNotEmpty)
          TextButton.icon(
            key: const Key('new-block'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nuevo bloque'),
            onPressed: () => _create(writable),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Future<void> _create(List<String> writable, {String? id}) async {
    final answer = await showDialog<_NewBlock>(
      context: context,
      builder: (context) => _NewBlockDialog(
        repos: writable,
        session: widget.session,
        fixedId: id,
      ),
    );
    if (answer == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = answer.id);
    try {
      var written = 0;
      for (final repo in answer.repos) {
        await widget.session.declareBlock(
          repo: repo,
          id: answer.id,
          titles: answer.titles,
        );
        written += 1;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Bloque «${answer.id}» declarado en '
            '${written == 1 ? 'un repositorio' : '$written repositorios'}.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _rename(CourseBlock block) async {
    final options = widget.session.catalogue.languageOptions;
    final answer = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _BlockTitlesDialog(
        languages: [for (final option in options) option.code],
        names: {for (final option in options) option.code: option.name},
        titles: block.titles,
      ),
    );
    if (answer == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = block.id);
    try {
      final written = await widget.session.setBlockTitles(
        id: block.id,
        titles: answer,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written == 0
                ? 'No ha cambiado nada.'
                : 'Nombre cambiado en $written repositorio(s).',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Quitar un bloque, decidiendo antes qué pasa con sus lecciones.
  ///
  /// La pregunta no se puede saltar: un bloque borrado deja sus lecciones
  /// nombrando algo que ya no declara nadie, y eso es material que sigue ahí
  /// pero clasificado en ninguna parte. Se ofrece moverlas, y quien prefiera
  /// dejarlas huérfanas tiene que decirlo.
  Future<void> _remove(CourseBlock block) async {
    final catalogue = widget.session.catalogue;
    final lessons = catalogue.unitsInBlock(block.id).length;
    final answer = await showDialog<_RemoveBlock>(
      context: context,
      builder: (context) => _RemoveBlockDialog(
        block: block,
        lessons: lessons,
        others: [
          for (final other in catalogue.blocks)
            if (other.id != block.id) other,
        ],
        language: widget.session.language,
      ),
    );
    if (answer == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = block.id);
    try {
      final moved = await widget.session.removeBlock(
        id: block.id,
        moveTo: answer.moveTo,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            answer.moveTo == null
                ? 'Bloque «${block.id}» quitado. Sus lecciones quedan sin '
                      'bloque declarado; salen en Entre repositorios.'
                : 'Bloque «${block.id}» quitado y '
                      '${_lessons(moved)} movidas a «${answer.moveTo}».',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Declarar o dejar de declarar un bloque en un repositorio concreto.
  ///
  /// Quitarlo del **último** que lo declara es quitar el bloque, así que
  /// pregunta lo mismo que quitarlo: qué pasa con sus lecciones. Sin eso, una
  /// casilla que parece un ajuste dejaría noventa lecciones clasificadas en
  /// ninguna parte sin decir nada.
  Future<void> _toggle(
    CourseBlock block,
    String repo, {
    required bool declared,
  }) async {
    final lessons = widget.session.catalogue.unitsInBlock(block.id).length;
    if (declared && block.sources.length == 1 && lessons > 0) {
      return _remove(block);
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = block.id);
    try {
      if (declared) {
        await widget.session.undeclareBlock(repo: repo, id: block.id);
      } else {
        await widget.session.declareBlock(
          repo: repo,
          id: block.id,
          titles: block.titles,
        );
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}

String _lessons(int count) => count == 1 ? '1 lección' : '$count lecciones';

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.session,
    required this.block,
    required this.writable,
    required this.busy,
    required this.onRename,
    required this.onRemove,
    required this.onToggle,
  });

  final Session session;
  final CourseBlock block;
  final List<String> writable;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onRemove;
  final void Function(String repo, bool declared) onToggle;

  @override
  Widget build(BuildContext context) {
    final lessons = session.catalogue.unitsInBlock(block.id).length;
    final canWrite = block.sources.keys.any(session.canWriteIn);
    return Container(
      key: Key('block-${block.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: didactaSurface,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.title(session.language),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${block.id} · ${_lessons(lessons)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: didactaMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                IconButton(
                  key: Key('rename-block-${block.id}'),
                  tooltip: canWrite
                      ? 'Nombre en todos los idiomas'
                      : 'Solo lectura: lo declara un repositorio en el que no '
                            'puedes escribir',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  onPressed: canWrite ? onRename : null,
                ),
                IconButton(
                  key: Key('remove-block-${block.id}'),
                  tooltip: canWrite
                      ? 'Quitar este bloque'
                      : 'Solo lectura: lo declara un repositorio en el que no '
                            'puedes escribir',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 15),
                  onPressed: canWrite ? onRemove : null,
                ),
              ],
            ],
          ),
          // En qué repositorios está declarado, y para tocarlo.
          //
          // Con uno solo abierto no se enseña: sería una casilla que solo
          // puede estar marcada, y desmarcarla dejaría todas sus lecciones
          // sin bloque. Con varios sí importa, porque es justo lo que decide
          // a quién le llega el cambio si se renombra.
          if (writable.length > 1 || block.sources.length > 1) ...[
            const SizedBox(height: 8),
            const Text(
              'Declarado en',
              style: TextStyle(fontSize: 11, color: didactaMuted),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final repo in _reposToShow())
                  _RepoToggle(
                    id: 'block-${block.id}-$repo',
                    colour: session.colourOf(repo) ?? 0xFF62697A,
                    label: session.workspace.byId(repo)?.label ?? repo,
                    declared: block.sources.containsKey(repo),
                    enabled: !busy && session.canWriteIn(repo),
                    onTap: () =>
                        onToggle(repo, block.sources.containsKey(repo)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Los que se ofrecen: en los que se puede escribir, más aquellos donde ya
  /// está declarado aunque sean de solo lectura --que se vea que está ahí,
  /// aunque no se pueda quitar.
  List<String> _reposToShow() => [
    ...writable,
    for (final repo in block.sources.keys)
      if (!writable.contains(repo) && repo.isNotEmpty) repo,
  ];
}

/// Una ficha de repositorio que se pulsa: declarado o no.
class _RepoToggle extends StatelessWidget {
  const _RepoToggle({
    required this.id,
    required this.colour,
    required this.label,
    required this.declared,
    required this.enabled,
    required this.onTap,
  });

  final String id;
  final int colour;
  final String label;
  final bool declared;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.55,
    child: Hoverable(
      onTap: enabled ? onTap : null,
      builder: (context, hovering) => Tooltip(
        message: declared
            ? 'Lo declara. Púlsalo para dejar de declararlo aquí.'
            : 'No lo declara. Púlsalo para declararlo aquí también.',
        child: Row(
          key: Key(id),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              declared ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: declared ? Color(colour) : didactaMuted,
            ),
            const SizedBox(width: 4),
            RepoChip(colour: colour, label: label, compact: true),
          ],
        ),
      ),
    ),
  );
}

/// Lo que hace falta para declarar un bloque.
class _NewBlock {
  const _NewBlock({
    required this.repos,
    required this.id,
    required this.titles,
  });

  /// En cuáles se declara. Varios a la vez es corriente aquí y no lo era con
  /// los grados: la teoría y los problemas están repartidos en dos
  /// repositorios y las dos mitades necesitan el mismo bloque.
  final List<String> repos;
  final String id;
  final Map<String, String> titles;
}

class _NewBlockDialog extends StatefulWidget {
  const _NewBlockDialog({
    required this.repos,
    required this.session,
    this.fixedId,
  });

  final List<String> repos;
  final Session session;

  /// Cuando se declara uno que ya se nombra: el id no se elige, es el que las
  /// lecciones ya escribieron.
  final String? fixedId;

  @override
  State<_NewBlockDialog> createState() => _NewBlockDialogState();
}

class _NewBlockDialogState extends State<_NewBlockDialog> {
  final _name = TextEditingController();
  final _id = TextEditingController();
  late final Set<String> _chosen = {...widget.repos};
  bool _touchedId = false;

  @override
  void initState() {
    super.initState();
    if (widget.fixedId != null) {
      _id.text = widget.fixedId!;
      _touchedId = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    super.dispose();
  }

  String get _identifier =>
      _touchedId ? _id.text.trim() : slugify(_name.text.trim());

  @override
  Widget build(BuildContext context) {
    final language = widget.session.language;
    final taken = widget.session.catalogue.blocks.any(
      (block) => block.id == _identifier,
    );
    return AlertDialog(
      title: const Text('Nuevo bloque'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('block-name'),
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre en ${languageName(language)}',
                hintText: 'Prácticas de ordenador',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('block-id'),
              controller: _id,
              enabled: widget.fixedId == null,
              onChanged: (value) => setState(() => _touchedId = true),
              decoration: InputDecoration(
                labelText: 'Identificador',
                hintText: _identifier.isEmpty ? 'practicas' : _identifier,
                isDense: true,
                errorText: taken && widget.fixedId == null
                    ? 'ya hay un bloque con este id'
                    : null,
                helperText:
                    'Es lo que escribe cada lección en su `unit.yaml` y lo '
                    'que junta los repositorios. No se traduce.',
                helperMaxLines: 3,
              ),
            ),
            if (widget.repos.length > 1) ...[
              const SizedBox(height: 12),
              const Text(
                'En qué repositorios se declara',
                style: TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
              const SizedBox(height: 4),
              for (final repo in widget.repos)
                CheckboxListTile(
                  key: Key('block-repo-$repo'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _chosen.contains(repo),
                  title: Text(
                    widget.session.workspace.byId(repo)?.label ?? repo,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  onChanged: (on) => setState(() {
                    if (on ?? false) {
                      _chosen.add(repo);
                    } else {
                      _chosen.remove(repo);
                    }
                  }),
                ),
              const Note(
                'En todos los que vayan a tener lecciones de este bloque. '
                'Declararlo en varios no rompe nada --se juntan por id-- pero '
                'entonces el nombre hay que cambiarlo en todos a la vez, y de '
                'eso se encarga el botón de renombrar.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('block-create'),
          onPressed:
              _name.text.trim().isEmpty ||
                  _identifier.isEmpty ||
                  _chosen.isEmpty ||
                  (taken && widget.fixedId == null)
              ? null
              : () => Navigator.of(context).pop(
                  _NewBlock(
                    repos: [
                      for (final repo in widget.repos)
                        if (_chosen.contains(repo)) repo,
                    ],
                    id: _identifier,
                    titles: {language: _name.text.trim()},
                  ),
                ),
          child: const Text('Declarar'),
        ),
      ],
    );
  }
}

/// Qué se hace con las lecciones de un bloque que se quita.
class _RemoveBlock {
  const _RemoveBlock({this.moveTo});

  /// A dónde van sus lecciones. Null es dejarlas donde están, nombrando un
  /// bloque que ya no declara nadie.
  final String? moveTo;
}

class _RemoveBlockDialog extends StatefulWidget {
  const _RemoveBlockDialog({
    required this.block,
    required this.lessons,
    required this.others,
    required this.language,
  });

  final CourseBlock block;
  final int lessons;
  final List<CourseBlock> others;
  final String language;

  @override
  State<_RemoveBlockDialog> createState() => _RemoveBlockDialogState();
}

class _RemoveBlockDialogState extends State<_RemoveBlockDialog> {
  late String? _moveTo = widget.others.isEmpty ? null : widget.others.first.id;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Quitar «${widget.block.title(widget.language)}»'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.lessons == 0
                ? 'No lo usa ninguna lección, así que quitarlo solo borra su '
                      'declaración.'
                : 'Lo usan ${_lessons(widget.lessons)}. Quitar el bloque no '
                      'las borra ni las esconde: se ven igual. Pero dejarían '
                      'de tener un bloque declarado al que pertenecer.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
          if (widget.lessons > 0) ...[
            const SizedBox(height: 12),
            const Text(
              'Qué se hace con ellas',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 4),
            RadioGroup<String?>(
              groupValue: _moveTo,
              onChanged: (value) => setState(() => _moveTo = value),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final other in widget.others)
                    RadioListTile<String?>(
                      key: Key('move-to-${other.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: other.id,
                      title: Text(
                        'Moverlas a «${other.title(widget.language)}»',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  const RadioListTile<String?>(
                    key: Key('move-to-nowhere'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: null,
                    title: Text(
                      'Dejarlas sin bloque declarado',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    subtitle: Text(
                      'Salen en Entre repositorios, para arreglarlas cuando '
                      'toque.',
                      style: TextStyle(fontSize: 11, color: didactaMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Note(
            'Se quita de todos los repositorios que lo declaren y en los que '
            'se pueda escribir. Uno de solo lectura se queda como está, y '
            'entonces el bloque sigue existiendo por él.',
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
        key: const Key('block-remove'),
        onPressed: () =>
            Navigator.of(context).pop(_RemoveBlock(moveTo: _moveTo)),
        child: const Text('Quitar'),
      ),
    ],
  );
}

/// Un nombre en todos los idiomas. Como el de los grados, con sus nombres.
class _BlockTitlesDialog extends StatefulWidget {
  const _BlockTitlesDialog({
    required this.languages,
    required this.names,
    required this.titles,
  });

  final List<String> languages;
  final Map<String, String> names;
  final Map<String, String> titles;

  @override
  State<_BlockTitlesDialog> createState() => _BlockTitlesDialogState();
}

class _BlockTitlesDialogState extends State<_BlockTitlesDialog> {
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
    title: const Text('Nombre del bloque'),
    content: SizedBox(
      width: 460,
      height: 400,
      child: ListView(
        children: [
          for (final code in widget.languages)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: Key('block-title-$code'),
                controller: _fields[code],
                decoration: InputDecoration(
                  labelText: widget.names[code] ?? code,
                  isDense: true,
                  helperText: (widget.titles[code] ?? '').isEmpty
                      ? 'sin traducir'
                      : null,
                  helperStyle: const TextStyle(
                    fontSize: 11.5,
                    color: didactaTeacher,
                  ),
                ),
              ),
            ),
          const Note(
            'Un idioma en blanco se queda marcado como pendiente en el '
            'fichero, no se borra el bloque. Y el cambio va a todos los '
            'repositorios que lo declaren: si solo se cambiara en uno, los '
            'dos dejarían de decir lo mismo.',
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
        key: const Key('block-titles-save'),
        onPressed: () => Navigator.of(context).pop({
          for (final entry in _fields.entries)
            entry.key: entry.value.text.trim(),
        }),
        child: const Text('Aceptar'),
      ),
    ],
  );
}

/// A qué bloque van las lecciones de otro.
class _MoveLessonsDialog extends StatefulWidget {
  const _MoveLessonsDialog({
    required this.from,
    required this.lessons,
    required this.others,
    required this.language,
  });

  final String from;
  final int lessons;
  final List<CourseBlock> others;
  final String language;

  @override
  State<_MoveLessonsDialog> createState() => _MoveLessonsDialogState();
}

class _MoveLessonsDialogState extends State<_MoveLessonsDialog> {
  late String _to = widget.others.first.id;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Mover las lecciones de «${widget.from}»'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_lessons(widget.lessons)} nombran «${widget.from}», que no '
            'declara ningún repositorio abierto. Moverlas les cambia el '
            '`block:` de su `unit.yaml`.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _to,
            onChanged: (value) =>
                setState(() => _to = value ?? widget.others.first.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final other in widget.others)
                  RadioListTile<String>(
                    key: Key('move-lessons-to-${other.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: other.id,
                    title: Text(
                      other.title(widget.language),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),
          const Note(
            'Un commit por repositorio, no uno por lección: es un solo '
            'cambio, y noventa commits seguidos diciendo lo mismo dejan el '
            'historial sin servir para ver qué cambió de verdad.',
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
        key: const Key('move-lessons'),
        onPressed: () => Navigator.of(context).pop(_to),
        child: const Text('Mover'),
      ),
    ],
  );
}
