/// Los snippets: verlos todos, ordenarlos, repartirlos y escribirlos.
///
/// Un snippet es lo que la barra del editor escribe alrededor de lo que se
/// marca y sabe quitar después. Había treinta y tantos, fijos, en un menú;
/// ahora cada repositorio dice cuáles ofrece, y esto es donde se decide.
///
/// Tres decisiones:
///
/// **Una lista para todos los repositorios, con un interruptor por cada
/// uno.** El mismo snippet en la teoría y en los problemas es uno, no dos:
/// se edita una vez y se guarda en los que estén marcados. Es como se
/// reparten los bloques, y es lo que permite que «Entre repositorios» diga
/// cuándo dos dicen cosas distintas del mismo.
///
/// **Se ve cómo queda antes de guardarlo.** Una definición con un error deja
/// sin compilar **todo** el repositorio --va al preámbulo de cada PDF--, así
/// que el editor compila lo que hay en la pantalla mientras se escribe, y
/// guardar una definición que no ha compilado se pregunta.
///
/// **Los de Didacta se retocan, no se copian.** Cambiarle el rótulo a
/// «Teorema» escribe el rótulo y nada más; el resto sigue siendo el de
/// serie, y mejora cuando mejore Didacta.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/compiler.dart' show CompileException;
import '../model/latex_snippets.dart';
import '../model/slug.dart';
import '../model/tex_wrap.dart';
import '../model/workspace.dart' show repoColours;
import '../router.dart';
import '../state/session.dart';
import 'problem.dart';
import 'sync_bar.dart';
import 'tex_field.dart';
import 'tex_highlight.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Los colores de `didacta-colours.sty` que puede llevar una caja: el mismo
/// en la pantalla que en el PDF, porque es el del PDF.
List<(String, String, Color)> get snippetBoxColours => [
  ('didactaThm', tr('Azul (teorema)'), Color(0xFF2D5FA0)),
  ('didactaDefn', tr('Gris (definición)'), Color(0xFF5C6470)),
  ('didactaProp', tr('Verde (proposición)'), Color(0xFF3C876E)),
  ('didactaLem', tr('Azul claro (lema)'), Color(0xFF467896)),
  ('didactaCor', tr('Morado (corolario)'), Color(0xFF8C5A96)),
  ('didactaEx', tr('Ocre (ejemplo)'), Color(0xFFBE8237)),
  ('didactaQues', tr('Turquesa (cuestión)'), Color(0xFF1E8C96)),
  ('didactaRem', tr('Gris claro (observación)'), Color(0xFF787D87)),
  ('didactaAxiom', tr('Violeta (axioma)'), Color(0xFF785FAF)),
  ('didactaAlgo', tr('Añil (algoritmo)'), Color(0xFF646EAF)),
  ('didactaTeacher', tr('Rojo (profesor)'), Color(0xFFAA4B4B)),
];

/// Las salidas en que se puede mirar un snippet.
List<(String, String)> get _previewProfiles => [
  ('notes', tr('Apuntes')),
  ('notes-teacher', tr('Profesor')),
  ('slides', tr('Diapositivas')),
];

/// Los nombres de entorno que ya define Didacta: definir uno otra vez con
/// `\newenvironment` es un error que deja el repositorio sin compilar.
final Set<String> _didactaEnvironments = {
  for (final wrapper in didactaWrappers) ...[
    ?wrapper.environment,
    ...wrapper.environmentAliases,
  ],
};

final RegExp _environmentName = RegExp(r'^[A-Za-z@]+\*?$');
final RegExp _commandName = RegExp(r'^[A-Za-z@]+$');
final RegExp _theoremDefinition = RegExp(
  r'^\s*\\DidactaNewTheorem\{([^{}]*)\}\{([^{}]*)\}\{([^{}]*)\}\s*$',
);

// ---------------------------------------------------------------------------
// La sección de Ajustes
// ---------------------------------------------------------------------------

/// El gestor entero, tal como va en Ajustes → Snippets.
class SnippetsManager extends StatefulWidget {
  const SnippetsManager({super.key, required this.session});

  final Session session;

  @override
  State<SnippetsManager> createState() => _SnippetsManagerState();
}

class _SnippetsManagerState extends State<SnippetsManager> {
  final TextEditingController _query = TextEditingController();

  /// Solo los de un repositorio, o null para todos.
  String? _repo;

  /// Solo los de un grupo, o null para todos.
  String? _group;

  /// Solo los que no coinciden entre repositorios.
  bool _diverging = false;

  /// El orden mientras se guarda: la lista no puede volver al de antes
  /// durante los segundos que tarda en reindexarse.
  List<String>? _pendingOrder;

  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Session get _session => widget.session;

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final repos = session.snippetRepos;
    var library = session.snippetLibrary;
    final pending = _pendingOrder;
    if (pending != null) {
      final byId = {for (final entry in library) entry.id: entry};
      library = [
        for (final id in pending)
          if (byId[id] != null) byId[id]!,
        for (final entry in library)
          if (!pending.contains(entry.id)) entry,
      ];
    }
    final conflicts = {for (final c in session.snippetConflicts) c.id};
    final groups = <String>[];
    for (final entry in library) {
      if (!groups.contains(entry.shown.group)) groups.add(entry.shown.group);
    }

    final words = fold(
      _query.text,
    ).toLowerCase().split(' ').where((w) => w.isNotEmpty);
    final shown = [
      for (final entry in library)
        if ((_repo == null || entry.byRepo.containsKey(_repo)) &&
            (_group == null || entry.shown.group == _group) &&
            (!_diverging || conflicts.contains(entry.id)) &&
            words.every(fold(entry.shown.searchable).toLowerCase().contains))
          entry,
    ];
    final filtered =
        words.isNotEmpty || _repo != null || _group != null || _diverging;
    final writable = repos.any(session.canWriteIn);
    final reorderable = !filtered && !_busy && writable;
    final own = library.where((entry) => !entry.fromDidacta).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Un snippet es lo que la barra del editor escribe alrededor de '
                  'lo que marcas --un teorema, un «solo diapositivas», una caja '
                  'tuya-- y lo que sabe quitar después sin tocar lo de dentro. '
                  'Cada repositorio ofrece los suyos, en este orden: se guardan '
                  'en su snippets.yaml, y un snippet que está en dos '
                  'repositorios tiene que decir lo mismo en los dos.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ConflictNote(
                  count: conflicts.length,
                  onShow: () => setState(() => _diverging = true),
                  onBetween: () => context.go(Routes.between()),
                ),
              ],
              if (!writable) ...[
                const SizedBox(height: 10),
                Note(
                  tr(
                    'En ninguno de los repositorios abiertos se puede escribir: '
                    'los snippets se ven, pero no se pueden cambiar.',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Controls(
                query: _query,
                repos: repos,
                repo: _repo,
                groups: groups,
                group: _group,
                diverging: _diverging,
                anyDiverging: conflicts.isNotEmpty,
                session: session,
                onQuery: () => setState(() {}),
                onRepo: (value) => setState(() => _repo = value),
                onGroup: (value) => setState(() => _group = value),
                onDiverging: (value) => setState(() => _diverging = value),
                onNew: writable && !_busy ? () => _edit(null) : null,
              ),
              const SizedBox(height: 8),
              Text(
                [
                  library.length == 1
                      ? tr('1 snippet')
                      : tr('{0} snippets', [library.length]),
                  tr('{0} propios', [own]),
                  if (conflicts.isNotEmpty)
                    tr('{0} no coinciden', [conflicts.length]),
                  if (filtered) tr('{0} con este filtro', [shown.length]),
                ].join(' · '),
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: context.palette.rule),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.control),
                  child: shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            tr('Ningún snippet con este filtro.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.palette.muted),
                          ),
                        )
                      : ReorderableListView.builder(
                          key: const Key('snippet-list'),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: shown.length,
                          onReorderItem: (from, to) =>
                              _reorder(shown, from, to),
                          proxyDecorator: (child, index, animation) => Material(
                            elevation: 2,
                            color: context.palette.card,
                            child: child,
                          ),
                          itemBuilder: (context, index) {
                            final entry = shown[index];
                            return _SnippetRow(
                              key: ValueKey(entry.id),
                              index: index,
                              entry: entry,
                              repos: repos,
                              session: session,
                              diverges: conflicts.contains(entry.id),
                              reorderable: reorderable,
                              first: index == 0,
                              last: index == shown.length - 1,
                              busy: _busy,
                              onEdit: () => _edit(entry),
                              onToggle: (repo) => _toggle(entry, repo),
                              onAction: (action) => _act(entry, action, shown),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                filtered
                    ? tr(
                        'Con un filtro puesto no se puede cambiar el orden: '
                        'quítalo para arrastrar.',
                      )
                    : tr(
                        'Arrastra por el asa para cambiar el orden: es el orden '
                        'en que salen en el selector de la barra, en todos '
                        'los repositorios.',
                      ),
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(Future<int> Function() work, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final written = await work();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written == 0
                ? tr('No había nada que cambiar.')
                : written == 1
                ? tr('{0} en un repositorio.', [done])
                : tr('{0} en {1} repositorios.', [done, written]),
          ),
        ),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pendingOrder = null;
        });
      }
    }
  }

  /// Mueve el de [from] a [to], contados ya sin él.
  void _reorder(List<SnippetEntry> shown, int from, int to) {
    if (from == to) return;
    final order = [for (final entry in shown) entry.id];
    final moved = order.removeAt(from);
    order.insert(to, moved);
    setState(() => _pendingOrder = order);
    unawaited(
      _run(() => _session.reorderSnippets(order), tr('Orden guardado')),
    );
  }

  Future<void> _toggle(SnippetEntry entry, String repo) async {
    final now = entry.byRepo.keys.toSet();
    final wanted = now.contains(repo)
        ? ({...now}..remove(repo))
        : {...now, repo};
    final snippet = entry.byRepo[repo] ?? entry.shown;
    await _run(
      () => _session.saveSnippet(snippet, repos: wanted),
      now.contains(repo) ? tr('Quitado') : tr('Añadido'),
    );
  }

  Future<void> _act(
    SnippetEntry entry,
    _RowAction action,
    List<SnippetEntry> shown,
  ) async {
    switch (action) {
      case _RowAction.edit:
        await _edit(entry);
      case _RowAction.duplicate:
        final copy = entry.shown;
        final label = tr('{0} (copia)', [copy.label]);
        await _edit(
          null,
          template: copy.copyWith(id: _freshId(label), label: label),
        );
      case _RowAction.reset:
        await _run(
          () => _session.saveSnippet(
            LatexSnippet.fromWrapper(entry.base!),
            repos: entry.byRepo.keys.toSet(),
          ),
          tr('Restablecido'),
        );
      case _RowAction.up:
      case _RowAction.down:
        final index = shown.indexOf(entry);
        final target = action == _RowAction.up ? index - 1 : index + 1;
        _reorder(shown, index, target.clamp(0, shown.length - 1));
      case _RowAction.remove:
        final sure = await _confirmRemove(entry);
        if (sure != true) return;
        await _run(() => _session.removeSnippet(entry.shown), tr('Quitado'));
    }
  }

  Future<bool?> _confirmRemove(SnippetEntry entry) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('¿Quitar «{0}»?', [entry.shown.label])),
      content: SizedBox(
        width: 420,
        child: Text(
          entry.fromDidacta
              ? tr(
                  'Deja de salir en la barra de todos los repositorios en que se '
                  'pueda escribir. Es uno de Didacta: el material que ya lo '
                  'usa sigue compilando, y se puede volver a poner cuando '
                  'se quiera.',
                )
              : tr(
                  'Deja de salir en la barra de todos los repositorios en que se '
                  'pueda escribir, y su definición deja de ir al preámbulo. '
                  'El material que ya lo use dejará de compilar hasta que '
                  'se vuelva a poner.',
                ),
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('confirm-remove-snippet'),
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.teacher,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Quitar')),
        ),
      ],
    ),
  );

  /// Un id que no tiene nadie, sacado del rótulo.
  String _freshId(String label) => freshSnippetId(label, {
    for (final entry in _session.snippetLibrary) entry.id,
  });

  Future<void> _edit(SnippetEntry? entry, {LatexSnippet? template}) async {
    final saved = await showSnippetEditor(
      context,
      session: _session,
      entry: entry,
      template: template,
    );
    if (saved == true && mounted) setState(() {});
  }
}

/// El color de un repositorio para sus chips, aunque no tenga uno puesto.
///
/// Un repositorio sin color --uno solo abierto, o uno que se abrió antes de
/// que los hubiera-- da 0, que es el negro transparente: el chip salía sin
/// letras. Se le da el de la paleta que le tocaría por su sitio.
int snippetRepoColour(Session session, String repo) {
  final colour = session.colourOf(repo);
  if (colour != null && colour != 0) return colour;
  final at = session.snippetRepos.indexOf(repo);
  return repoColours[(at < 0 ? 0 : at) % repoColours.length];
}

/// Un id nuevo para [label] que no esté en [taken]: `resumen`, `resumen-2`.
String freshSnippetId(String label, Set<String> taken) {
  var base = slugify(label);
  if (base.isEmpty) base = 'snippet';
  var id = base;
  var n = 2;
  while (taken.contains(id)) {
    id = '$base-$n';
    n += 1;
  }
  return id;
}

class _ConflictNote extends StatelessWidget {
  const _ConflictNote({
    required this.count,
    required this.onShow,
    required this.onBetween,
  });

  final int count;
  final VoidCallback onShow;
  final VoidCallback onBetween;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
    decoration: BoxDecoration(
      color: context.palette.tint(context.palette.teacher),
      borderRadius: BorderRadius.circular(Radii.control),
      border: Border.all(
        color: context.palette.teacher.withValues(alpha: 0.35),
      ),
    ),
    child: Row(
      children: [
        Icon(Icons.call_split, size: 16, color: context.palette.teacher),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            count == 1
                ? tr(
                    'Un snippet no dice lo mismo en todos los repositorios que '
                    'lo tienen: el mismo \\begin puede salir distinto según '
                    'dónde se compile.',
                  )
                : tr(
                    '{0} snippets no dicen lo mismo en todos los '
                    'repositorios que los tienen: el mismo \\begin puede '
                    'salir distinto según dónde se compile.',
                    [count],
                  ),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: context.palette.ink,
            ),
          ),
        ),
        TextButton(onPressed: onShow, child: Text(tr('Verlos'))),
        TextButton(onPressed: onBetween, child: Text(tr('Entre repositorios'))),
      ],
    ),
  );
}

/// El buscador, los filtros y el botón de crear.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.query,
    required this.repos,
    required this.repo,
    required this.groups,
    required this.group,
    required this.diverging,
    required this.anyDiverging,
    required this.session,
    required this.onQuery,
    required this.onRepo,
    required this.onGroup,
    required this.onDiverging,
    required this.onNew,
  });

  final TextEditingController query;
  final List<String> repos;
  final String? repo;
  final List<String> groups;
  final String? group;
  final bool diverging;
  final bool anyDiverging;
  final Session session;
  final VoidCallback onQuery;
  final ValueChanged<String?> onRepo;
  final ValueChanged<String?> onGroup;
  final ValueChanged<bool> onDiverging;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const Key('snippet-filter'),
      controller: query,
      onChanged: (_) => onQuery(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: tr('Buscar por nombre, entorno u orden'),
        prefixIcon: Icon(Icons.search, size: 17, color: context.palette.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        suffixIcon: query.text.isEmpty
            ? null
            : IconButton(
                tooltip: tr('Borrar la búsqueda'),
                icon: const Icon(Icons.close, size: 15),
                onPressed: () {
                  query.clear();
                  onQuery();
                },
              ),
      ),
    );
    final filters = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (repos.length > 1)
          _Filter<String?>(
            key: const Key('snippet-filter-repo'),
            icon: Icons.folder_outlined,
            value: repo,
            options: [
              (null, tr('Todos los repositorios')),
              for (final id in repos)
                (id, session.workspace.byId(id)?.label ?? id),
            ],
            onChanged: onRepo,
          ),
        _Filter<String?>(
          key: const Key('snippet-filter-group'),
          icon: Icons.label_outline,
          value: group,
          options: [
            (null, tr('Todos los grupos')),
            for (final name in groups) (name, name),
          ],
          onChanged: onGroup,
        ),
        if (anyDiverging)
          FilterChip(
            key: const Key('snippet-filter-diverging'),
            label: Text(tr('No coinciden')),
            selected: diverging,
            onSelected: onDiverging,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
    final create = FilledButton.icon(
      key: const Key('new-snippet'),
      icon: const Icon(Icons.add, size: 16),
      label: Text(tr('Nuevo snippet')),
      onPressed: onNew,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  create,
                ],
              ),
              const SizedBox(height: 8),
              filters,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            filters,
            const SizedBox(width: 10),
            create,
          ],
        );
      },
    );
  }
}

/// Un desplegable pequeño, del tamaño de lo que dice.
class _Filter<T> extends StatelessWidget {
  const _Filter({
    super.key,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.firstWhere(
      (option) => option.$1 == value,
      orElse: () => options.first,
    );
    return PopupMenuButton<int>(
      tooltip: '',
      onSelected: (index) => onChanged(options[index].$1),
      itemBuilder: (context) => [
        for (final (index, option) in options.indexed)
          PopupMenuItem<int>(
            key: Key('filter-option-${option.$2}'),
            value: index,
            height: 34,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: option.$1 == value
                      ? const Icon(Icons.check, size: 14)
                      : null,
                ),
                Text(option.$2, style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: value == null ? null : context.palette.selected,
          border: Border.all(color: context.palette.rule),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: context.palette.muted),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                current.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: context.palette.ink),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 17, color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}

enum _RowAction { edit, duplicate, reset, up, down, remove }

/// Un snippet en una fila: qué es, cómo se escribe y dónde está.
class _SnippetRow extends StatelessWidget {
  const _SnippetRow({
    super.key,
    required this.index,
    required this.entry,
    required this.repos,
    required this.session,
    required this.diverges,
    required this.reorderable,
    required this.first,
    required this.last,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
    required this.onAction,
  });

  final int index;
  final SnippetEntry entry;
  final List<String> repos;
  final Session session;
  final bool diverges;
  final bool reorderable;
  final bool first;
  final bool last;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<String> onToggle;
  final ValueChanged<_RowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final snippet = entry.shown;
    final retouched = entry.byRepo.values.any((s) => s.retouched);
    final nowhere = entry.byRepo.isEmpty;
    final badge = !snippet.usable
        ? (tr('Incompleto'), context.palette.teacher)
        : !entry.fromDidacta
        ? (tr('Propio'), context.palette.accentDark)
        : retouched
        ? (tr('Retocado'), context.palette.thm)
        : (tr('Didacta'), context.palette.muted);

    return Material(
      color: context.palette.card,
      child: InkWell(
        key: Key('snippet-row-${entry.id}'),
        onTap: busy ? null : onEdit,
        hoverColor: context.palette.hover,
        child: Container(
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: context.palette.rule)),
          ),
          padding: const EdgeInsets.fromLTRB(4, 7, 4, 7),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: reorderable
                    ? ReorderableDragStartListener(
                        index: index,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Tooltip(
                            message: tr('Arrastra para cambiar el orden'),
                            child: Icon(
                              Icons.drag_indicator,
                              size: 18,
                              color: context.palette.muted,
                            ),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: context.palette.rule,
                      ),
              ),
              Expanded(
                flex: 5,
                child: Opacity(
                  opacity: nowhere ? 0.6 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              snippet.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          _Badge(label: badge.$1, colour: badge.$2),
                          if (diverges) ...[
                            const SizedBox(width: 5),
                            Tooltip(
                              message: tr(
                                'No dice lo mismo en todos los '
                                'repositorios que lo tienen',
                              ),
                              child: _Badge(
                                label: tr('No coincide'),
                                colour: context.palette.teacher,
                                icon: Icons.call_split,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        snippet.usable
                            ? snippet.usage
                            : tr(
                                'No dice qué escribe: ábrelo para completarlo.',
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle.copyWith(
                          fontSize: 11.5,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: Text(
                  snippet.group,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
              ),
              const SizedBox(width: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final repo in repos)
                    _RepoSwitch(
                      key: Key('snippet-${entry.id}-in-$repo'),
                      on: entry.byRepo.containsKey(repo),
                      colour: snippetRepoColour(session, repo),
                      label: session.workspace.byId(repo)?.label ?? repo,
                      enabled: !busy && session.canWriteIn(repo),
                      onTap: () => onToggle(repo),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_RowAction>(
                key: Key('snippet-menu-${entry.id}'),
                tooltip: tr('Más'),
                enabled: !busy,
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: context.palette.muted,
                ),
                onSelected: onAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _RowAction.edit,
                    child: Text(tr('Editar…')),
                  ),
                  PopupMenuItem(
                    value: _RowAction.duplicate,
                    child: Text(tr('Duplicar como uno propio…')),
                  ),
                  if (retouched)
                    PopupMenuItem(
                      value: _RowAction.reset,
                      child: Text(tr('Volver al de Didacta')),
                    ),
                  if (reorderable && !first)
                    PopupMenuItem(
                      value: _RowAction.up,
                      child: Text(tr('Subir')),
                    ),
                  if (reorderable && !last)
                    PopupMenuItem(
                      value: _RowAction.down,
                      child: Text(tr('Bajar')),
                    ),
                  if (!nowhere)
                    PopupMenuItem(
                      value: _RowAction.remove,
                      child: Text(
                        tr('Quitar de todos los repositorios'),
                        style: TextStyle(color: context.palette.teacher),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour, this.icon});

  final String label;
  final Color colour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
    decoration: BoxDecoration(
      color: context.palette.tint(colour, 0.12),
      borderRadius: BorderRadius.circular(Radii.small),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: colour),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: colour,
          ),
        ),
      ],
    ),
  );
}

/// Si un repositorio ofrece el snippet: se pulsa para ponerlo o quitarlo.
class _RepoSwitch extends StatelessWidget {
  const _RepoSwitch({
    super.key,
    required this.on,
    required this.colour,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final bool on;
  final int colour;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.55,
    child: Tooltip(
      message: !enabled
          ? tr('{0}: no se puede escribir en él', [label])
          : on
          ? tr('Sale en la barra de {0}. Púlsalo para quitarlo de ahí.', [
              label,
            ])
          : tr('No sale en la barra de {0}. Púlsalo para ponerlo.', [label]),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(Radii.small),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.check_box : Icons.check_box_outline_blank,
                size: 15,
                color: on
                    ? context.palette.repo(colour)
                    : context.palette.muted,
              ),
              const SizedBox(width: 3),
              RepoChip(colour: colour, label: label, compact: true, muted: !on),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// El editor
// ---------------------------------------------------------------------------

/// Abre el editor de un snippet. Con [entry] null, uno nuevo --vacío, o como
/// [template] si se duplica--. Devuelve true si se guardó.
Future<bool?> showSnippetEditor(
  BuildContext context, {
  required Session session,
  SnippetEntry? entry,
  LatexSnippet? template,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      SnippetEditor(session: session, entry: entry, template: template),
);

enum _Definition { none, theorem, custom }

/// Los atajos se escriben con ⌘ en macOS y con Ctrl en los demás.
bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

class SnippetEditor extends StatefulWidget {
  const SnippetEditor({
    super.key,
    required this.session,
    this.entry,
    this.template,
  });

  final Session session;
  final SnippetEntry? entry;
  final LatexSnippet? template;

  @override
  State<SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<SnippetEditor> {
  late final LatexSnippet _original =
      widget.entry?.shown ??
      widget.template ??
      LatexSnippet(id: '', label: '', group: tr('Propios'));

  bool get _creating => widget.entry == null;

  late final TextEditingController _label = TextEditingController(
    text: _original.label,
  );
  late final TextEditingController _group = TextEditingController(
    text: _original.group,
  );
  late final TextEditingController _description = TextEditingController(
    text: _original.description,
  );
  late final TextEditingController _environment = TextEditingController(
    text: _original.environment ?? '',
  );
  late final TextEditingController _command = TextEditingController(
    text: _original.command ?? '',
  );
  late final TextEditingController _arguments = TextEditingController(
    text: _original.arguments,
  );
  late final TextEditingController _aliases = TextEditingController(
    text: [
      ..._original.environmentAliases,
      for (final name in _original.commandAliases) '\\$name',
    ].join(', '),
  );
  late final TextEditingController _boxTitle = TextEditingController();
  late final TexEditingController _definition = TexEditingController(
    text: _original.definition,
  );
  late final TexEditingController _sample = TexEditingController(
    text: _original.sample,
  );

  late SnippetShape _shape = _original.usable
      ? _original.shape
      : SnippetShape.environment;
  late bool _block = _original.block;
  _Definition _kind = _Definition.none;
  String _colour = 'didactaThm';
  late final Set<String> _repos = widget.entry == null
      ? {
          for (final repo in widget.session.snippetRepos)
            if (widget.session.canWriteIn(repo)) repo,
        }
      : widget.entry!.byRepo.keys.toSet();

  String _profile = 'notes';
  SnippetPreview? _preview;

  /// Qué se compiló la última vez: si ya no es lo que hay, está vieja.
  String? _previewed;
  bool _compiling = false;
  bool _again = false;
  bool _unavailable = false;
  int _revision = 0;
  Timer? _debounce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Sin motor --en la web, o sin TeX-- se sabe desde el principio, y se
    // dice en lugar de esperar a una compilación que no va a llegar.
    _unavailable =
        widget.session.liveCompiler(
          repo: widget.session.snippetRepos.firstOrNull,
        ) ==
        null;
    final theorem = _theoremDefinition.firstMatch(_original.definition);
    if (_original.definition.trim().isEmpty) {
      _kind = _Definition.none;
    } else if (theorem != null) {
      _kind = _Definition.theorem;
      _boxTitle.text = theorem.group(2)!;
      _colour = theorem.group(3)!;
    } else {
      _kind = _Definition.custom;
    }
    for (final controller in [
      _label,
      _environment,
      _command,
      _arguments,
      _aliases,
      _boxTitle,
      _definition,
      _sample,
    ]) {
      controller.addListener(_changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _compile());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in [
      _label,
      _group,
      _description,
      _environment,
      _command,
      _arguments,
      _aliases,
      _boxTitle,
      _definition,
      _sample,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _compile);
  }

  String get _id => _creating
      ? (widget.template?.id.isNotEmpty ?? false)
            ? widget.template!.id
            : freshSnippetId(_label.text, {
                for (final entry in widget.session.snippetLibrary) entry.id,
              })
      : _original.id;

  String get _definitionText => switch (_kind) {
    _Definition.none => '',
    _Definition.theorem =>
      '\\DidactaNewTheorem{${_environment.text.trim()}}'
          '{${_boxTitle.text.trim()}}{$_colour}',
    _Definition.custom => _definition.text,
  };

  /// El snippet tal como está en la pantalla.
  LatexSnippet get _current {
    final aliases = [
      for (final part in _aliases.text.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    final environment = _environment.text.trim();
    final command = _command.text.trim().replaceFirst(RegExp(r'^\\'), '');
    return LatexSnippet(
      id: _id,
      label: _label.text.trim(),
      group: _group.text.trim().isEmpty
          ? snippetGroupNames[TexWrapGroup.custom]!
          : _group.text.trim(),
      description: _description.text.trim(),
      environment: _shape == SnippetShape.command || environment.isEmpty
          ? null
          : environment,
      command: _shape == SnippetShape.environment || command.isEmpty
          ? null
          : command,
      environmentAliases: _shape == SnippetShape.command
          ? const []
          : [
              for (final name in aliases)
                if (!name.startsWith('\\')) name,
            ],
      commandAliases: _shape == SnippetShape.environment
          ? const []
          : [
              for (final name in aliases)
                if (name.startsWith('\\')) name.substring(1),
            ],
      arguments: _arguments.text.trim(),
      block: _shape == SnippetShape.either && _block,
      definition: _definitionText,
      sample: _sample.text,
      base: _original.id == _id ? _original.base : didactaWrapperById(_id),
    );
  }

  /// Lo que impide guardar, en frases.
  List<String> get _problems {
    final snippet = _current;
    final environment = _environment.text.trim();
    final command = _command.text.trim().replaceFirst(RegExp(r'^\\'), '');
    return [
      if (snippet.label.isEmpty)
        tr('Ponle un rótulo: es lo que se busca en la barra.'),
      if (_shape != SnippetShape.command &&
          !_environmentName.hasMatch(environment))
        tr('El entorno solo puede llevar letras, y un asterisco al final.'),
      if (_shape != SnippetShape.environment && !_commandName.hasMatch(command))
        tr('La orden solo puede llevar letras.'),
      for (final name in [...snippet.environmentAliases])
        if (!_environmentName.hasMatch(name))
          tr('«{0}» no vale como nombre de entorno.', [name]),
      for (final name in [...snippet.commandAliases])
        if (!_commandName.hasMatch(name))
          tr('«\\{0}» no vale como nombre de orden.', [name]),
      if (_kind == _Definition.theorem && _shape == SnippetShape.command)
        tr('Una caja como un teorema es un entorno: elige «Entorno».'),
      if (_kind == _Definition.theorem && _boxTitle.text.trim().isEmpty)
        tr('La caja necesita un título: el que sale en su pestaña.'),
      if (_kind != _Definition.none &&
          _didactaEnvironments.contains(environment) &&
          _definesEnvironment(environment))
        tr(
          'Didacta ya define «{0}»: definirlo otra vez deja sin '
          'compilar el repositorio. Elige otro nombre, o «Ya está '
          'definido».',
          [environment],
        ),
      if (_creating && _repos.isEmpty)
        tr(
          'Elige al menos un repositorio: sin ninguno no sale en ninguna barra.',
        ),
    ];
  }

  bool _definesEnvironment(String name) {
    final text = _definitionText;
    return text.contains('\\newenvironment{$name}') ||
        text.contains('\\DidactaNewTheorem{$name}') ||
        text.contains('\\NewDocumentEnvironment{$name}');
  }

  String get _previewKey =>
      '$_definitionText\u0000${_current.previewBody}\u0000$_profile';

  Future<void> _compile() async {
    if (!mounted || _unavailable) return;
    if (_compiling) {
      _again = true;
      return;
    }
    final snippet = _current;
    if (!snippet.usable) return;
    final key = _previewKey;
    setState(() => _compiling = true);
    try {
      final repo = _repos.isNotEmpty
          ? widget.session.snippetRepos.firstWhere(
              _repos.contains,
              orElse: () => _repos.first,
            )
          : null;
      final result = await widget.session.previewSnippet(
        snippet,
        profile: _profile,
        repo: repo,
      );
      if (!mounted) return;
      setState(() {
        if (result == null) {
          _unavailable = true;
        } else {
          _preview = result;
          _previewed = key;
          _revision += 1;
        }
      });
    } catch (error) {
      // El motor no ha llegado a compilar: no es que el LaTeX esté mal, y
      // decir «no compila» haría buscar un error que no está en la definición.
      if (!mounted) return;
      setState(() {
        _preview = SnippetPreview(
          ok: false,
          engineFailed: true,
          errors: [
            error is CompileException && error.detail.isNotEmpty
                ? '${error.message}\n${error.detail}'
                : '$error',
          ],
        );
        _previewed = key;
      });
    } finally {
      if (mounted) setState(() => _compiling = false);
      if (_again && mounted) {
        _again = false;
        unawaited(_compile());
      }
    }
  }

  Future<void> _save() async {
    final problems = _problems;
    if (problems.isNotEmpty) return;
    final snippet = _current;
    final changedDefinition =
        snippet.definition.trim() != _original.definition.trim();
    final checked =
        _preview?.ok == true && _previewed == _previewKey && !_compiling;
    if (changedDefinition && snippet.definition.trim().isNotEmpty && !checked) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('¿Guardar sin haberlo compilado?')),
          content: SizedBox(
            width: 440,
            child: Text(
              _unavailable
                  ? tr(
                      'Aquí no se puede compilar, así que no se ha comprobado '
                      'la definición. Va al preámbulo de todo lo que se '
                      'compile en los repositorios elegidos: si tiene un '
                      'error, no compilará nada de ellos hasta que se '
                      'arregle.',
                    )
                  : tr(
                      'La definición no ha compilado bien, o todavía no se ha '
                      'probado como está ahora. Va al preámbulo de todo lo '
                      'que se compile en los repositorios elegidos: si tiene '
                      'un error, no compilará nada de ellos hasta que se '
                      'arregle.',
                    ),
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Seguir editando')),
            ),
            FilledButton(
              key: const Key('save-unchecked-snippet'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Guardar igualmente')),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final written = await widget.session.saveSnippet(snippet, repos: _repos);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written == 0
                ? tr('No había nada que guardar.')
                : written == 1
                ? tr('«{0}» guardado en un repositorio.', [snippet.label])
                : tr('«{0}» guardado en {1} repositorios.', [
                    snippet.label,
                    written,
                  ]),
          ),
        ),
      );
      navigator.pop(true);
    } catch (error) {
      showProblemIn(messenger, error);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(1180.0, size.width - 48);
    final height = math.min(800.0, size.height - 48);
    final problems = _problems;

    final form = _form();
    final preview = _PreviewPane(
      preview: _preview,
      compiling: _compiling,
      stale: _preview != null && _previewed != _previewKey,
      unavailable: _unavailable,
      profile: _profile,
      revision: _revision,
      body: _current.usable ? _current.previewBody : '',
      onProfile: (value) {
        setState(() => _profile = value);
        unawaited(_compile());
      },
      onCompile: _compile,
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.dialog),
      ),
      clipBehavior: Clip.antiAlias,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _compile,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _compile,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: SizedBox(
          key: const Key('snippet-editor'),
          width: width,
          height: height,
          child: Column(
            children: [
              _EditorHeader(
                title: _creating
                    ? tr('Nuevo snippet')
                    : tr('Editar «{0}»', [_original.label]),
                id: _id,
                fromDidacta: _current.fromDidacta,
                onClose: _saving ? null : () => Navigator.of(context).pop(),
              ),
              Divider(height: 1, color: context.palette.rule),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 860) {
                      return ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          form,
                          const SizedBox(height: 18),
                          SizedBox(height: 360, child: preview),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: math.min(500, constraints.maxWidth * 0.48),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            children: [form],
                          ),
                        ),
                        VerticalDivider(width: 1, color: context.palette.rule),
                        Expanded(child: preview),
                      ],
                    );
                  },
                ),
              ),
              Divider(height: 1, color: context.palette.rule),
              _EditorFooter(
                problems: problems,
                saving: _saving,
                onCancel: _saving ? null : () => Navigator.of(context).pop(),
                onSave: problems.isEmpty && !_saving ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final session = widget.session;
    final groups = <String>{
      for (final entry in session.snippetLibrary) entry.shown.group,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormLabel(tr('Cómo se llama')),
        _Field(
          key: const Key('snippet-label'),
          controller: _label,
          label: tr('Rótulo'),
          hint: tr('Resumen, Solo en clase, Caja de fórmulas…'),
          autofocus: _creating && widget.template == null,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Autocomplete<String>(
                initialValue: TextEditingValue(text: _group.text),
                optionsBuilder: (value) => [
                  for (final name in groups)
                    if (fold(
                      name,
                    ).toLowerCase().contains(fold(value.text).toLowerCase()))
                      name,
                ],
                onSelected: (value) => _group.text = value,
                fieldViewBuilder: (context, controller, focus, submit) {
                  controller.addListener(() => _group.text = controller.text);
                  return _Field(
                    key: const Key('snippet-group'),
                    controller: controller,
                    focusNode: focus,
                    label: tr('Grupo'),
                    hint: tr('Teoría, Problema, Propios…'),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Field(
          key: const Key('snippet-description'),
          controller: _description,
          label: tr('Para qué sirve (opcional)'),
          hint: tr('Sale al pasar por encima en la barra'),
        ),
        const SizedBox(height: 18),
        _FormLabel(tr('Qué escribe')),
        SegmentedButton<SnippetShape>(
          key: const Key('snippet-shape'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: SnippetShape.environment,
              label: Text(tr('Entorno')),
              icon: Icon(Icons.data_object, size: 15),
            ),
            ButtonSegment(
              value: SnippetShape.command,
              label: Text(trAs('LaTeX', 'Orden')),
              icon: Icon(Icons.code, size: 15),
            ),
            ButtonSegment(
              value: SnippetShape.either,
              label: Text(tr('Las dos')),
              icon: Icon(Icons.swap_horiz, size: 15),
            ),
          ],
          selected: {_shape},
          onSelectionChanged: (value) {
            setState(() => _shape = value.single);
            _changed();
          },
        ),
        const SizedBox(height: 6),
        Text(
          switch (_shape) {
            SnippetShape.environment => tr(
              'Envuelve en \\begin{…} … \\end{…}: lo normal para párrafos y '
              'cajas.',
            ),
            SnippetShape.command => tr(
              'Envuelve en \\orden{…}: para una palabra o una frase.',
            ),
            SnippetShape.either => tr(
              'La orden para una frase y el entorno para párrafos, según lo '
              'que marques: como los canales.',
            ),
          },
          style: TextStyle(
            fontSize: 11.5,
            color: context.palette.muted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_shape != SnippetShape.command)
              Expanded(
                child: _Field(
                  key: const Key('snippet-environment'),
                  controller: _environment,
                  label: tr('Entorno'),
                  mono: true,
                  prefix: r'\begin{',
                ),
              ),
            if (_shape == SnippetShape.either) const SizedBox(width: 10),
            if (_shape != SnippetShape.environment)
              Expanded(
                child: _Field(
                  key: const Key('snippet-command'),
                  controller: _command,
                  label: trAs('LaTeX', 'Orden'),
                  mono: true,
                  prefix: r'\',
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Field(
                key: const Key('snippet-arguments'),
                controller: _arguments,
                label: tr('Argumentos (opcional)'),
                hint: tr('[Título]  o  {red}'),
                mono: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Field(
                key: const Key('snippet-aliases'),
                controller: _aliases,
                label: tr('Nombres heredados (opcional)'),
                hint: r'thrm, nthm, \onlybook',
                mono: true,
              ),
            ),
          ],
        ),
        if (_shape == SnippetShape.either)
          CheckboxListTile(
            key: const Key('snippet-block'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _block,
            onChanged: (value) {
              setState(() => _block = value ?? false);
              _changed();
            },
            title: Text(
              tr('Siempre como entorno, aunque marques una frase'),
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 8),
        _Usage(snippet: _current),
        const SizedBox(height: 18),
        _FormLabel(tr('Cómo se define')),
        SegmentedButton<_Definition>(
          key: const Key('snippet-definition-kind'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _Definition.none,
              label: Text(tr('Ya definido')),
            ),
            ButtonSegment(
              value: _Definition.theorem,
              label: Text(tr('Caja de teorema')),
            ),
            ButtonSegment(
              value: _Definition.custom,
              label: Text(tr('LaTeX propio')),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (value) {
            setState(() {
              _kind = value.single;
              if (_kind == _Definition.custom && _definition.text.isEmpty) {
                _definition.text = _skeleton();
              }
              if (_kind == _Definition.theorem && _boxTitle.text.isEmpty) {
                _boxTitle.text = _label.text.trim();
              }
            });
            _changed();
          },
        ),
        const SizedBox(height: 8),
        ...switch (_kind) {
          _Definition.none => [
            Text(
              tr(
                'Lo define Didacta o un paquete que ya se carga: no se añade '
                'nada al preámbulo.',
              ),
              style: TextStyle(
                fontSize: 12,
                color: context.palette.muted,
                height: 1.4,
              ),
            ),
          ],
          _Definition.theorem => [
            Text(
              tr(
                'Una caja como las de Didacta: con su pestaña, su número y el '
                'mismo aspecto en apuntes y en diapositivas.',
              ),
              style: TextStyle(
                fontSize: 12,
                color: context.palette.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            _Field(
              key: const Key('snippet-box-title'),
              controller: _boxTitle,
              label: tr('Título de la caja'),
              hint: tr('Resumen'),
            ),
            const SizedBox(height: 10),
            _ColourChoice(
              value: _colour,
              onChanged: (value) {
                setState(() => _colour = value);
                _changed();
              },
            ),
            const SizedBox(height: 8),
            _CodeBox(text: _definitionText),
          ],
          _Definition.custom => [
            _CodeField(
              key: const Key('snippet-definition'),
              controller: _definition,
              minLines: 4,
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Va al preámbulo de todo lo que se compila en los repositorios '
                'elegidos, antes del de la plantilla.',
              ),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
          ],
        },
        const SizedBox(height: 18),
        _FormLabel(tr('Texto de ejemplo')),
        _CodeField(
          key: const Key('snippet-sample'),
          controller: _sample,
          minLines: 3,
          hint: tr('Lo que se escribe dentro en la vista previa'),
        ),
        const SizedBox(height: 18),
        _FormLabel(tr('En qué repositorios se ofrece')),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            for (final repo in session.snippetRepos)
              _RepoSwitch(
                key: Key('snippet-editor-in-$repo'),
                on: _repos.contains(repo),
                colour: snippetRepoColour(session, repo),
                label: session.workspace.byId(repo)?.label ?? repo,
                enabled: session.canWriteIn(repo),
                onTap: () => setState(() {
                  if (!_repos.remove(repo)) _repos.add(repo);
                }),
              ),
          ],
        ),
        if (!_creating && _repos.isEmpty) ...[
          const SizedBox(height: 8),
          Note(
            tr('Sin ningún repositorio, guardar lo quita de todas las barras.'),
            tone: context.palette.teacher,
          ),
        ],
      ],
    );
  }

  /// El principio de una definición propia, para no empezar de cero.
  String _skeleton() {
    final environment = _environment.text.trim().isEmpty
        ? 'miEntorno'
        : _environment.text.trim();
    final command = _command.text.trim().isEmpty
        ? 'miOrden'
        : _command.text.trim();
    final title = _label.text.trim().isEmpty
        ? tr('Título')
        : _label.text.trim();
    return switch (_shape) {
      SnippetShape.command => '\\newcommand{\\$command}[1]{\\textbf{#1}}',
      _ =>
        '\\newenvironment{$environment}\n'
            '  {\\par\\medskip\\noindent\\textbf{$title.}\\ }\n'
            '  {\\par\\medskip}',
    };
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.title,
    required this.id,
    required this.fromDidacta,
    required this.onClose,
  });

  final String title;
  final String id;
  final bool fromDidacta;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: context.palette.tint(context.palette.accent, 0.16),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Icon(
            Icons.data_object,
            size: 17,
            color: context.palette.accentDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 1),
              Text(
                fromDidacta
                    ? tr(
                        'id: {0} · de Didacta: lo que cambies se guarda como un '
                        'retoque',
                        [id],
                      )
                    : tr('id: {0}', [id]),
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: tr('Cerrar sin guardar'),
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClose,
        ),
      ],
    ),
  );
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.problems,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final List<String> problems;
  final bool saving;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: problems.isEmpty
              ? Text(
                  _mac
                      ? tr('⌘↵ compila la vista previa · ⌘S guarda')
                      : tr(
                          'Ctrl+Intro compila la vista previa · Ctrl+S guarda',
                        ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                )
              : Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 15,
                      color: context.palette.teacher,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        problems.first,
                        key: const Key('snippet-problem'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.teacher,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: onCancel, child: Text(tr('Cancelar'))),
        const SizedBox(width: 6),
        FilledButton.icon(
          key: const Key('save-snippet'),
          icon: saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(tr('Guardar')),
          onPressed: onSave,
        ),
      ],
    ),
  );
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: context.palette.muted,
        letterSpacing: 0.7,
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.mono = false,
    this.prefix,
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool mono;
  final String? prefix;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? monoStyle.copyWith(fontSize: 12.5, color: context.palette.ink)
        : TextStyle(fontSize: 13, color: context.palette.ink);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      autocorrect: !mono,
      enableSuggestions: !mono,
      style: style,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        prefixStyle: style.copyWith(color: context.palette.muted),
      ),
    );
  }
}

/// LaTeX de varias líneas, coloreado como en el editor.
class _CodeField extends StatelessWidget {
  const _CodeField({
    super.key,
    required this.controller,
    this.minLines = 3,
    this.hint,
  });

  final TexEditingController controller;
  final int minLines;
  final String? hint;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.palette.surface,
      border: Border.all(color: context.palette.rule),
      borderRadius: BorderRadius.circular(Radii.control),
    ),
    constraints: const BoxConstraints(maxHeight: 220),
    child: SingleChildScrollView(
      child: TexField(
        controller: controller,
        minLines: minLines,
        hintText: hint,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      ),
    ),
  );
}

/// LaTeX que no se edita: lo que sale de lo elegido.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: context.palette.surface,
      border: Border.all(color: context.palette.rule),
      borderRadius: BorderRadius.circular(Radii.control),
    ),
    child: SelectableText(
      text,
      style: monoStyle.copyWith(fontSize: 12, color: context.palette.ink),
    ),
  );
}

/// Cómo se escribirá, con un trozo de ejemplo dentro.
class _Usage extends StatelessWidget {
  const _Usage({required this.snippet});

  final LatexSnippet snippet;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
    decoration: BoxDecoration(
      color: context.palette.tint(context.palette.accent, 0.07),
      borderRadius: BorderRadius.circular(Radii.control),
    ),
    child: Row(
      children: [
        Text(
          tr('Así se escribe'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.palette.accentDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            snippet.usable ? snippet.usage : '—',
            key: const Key('snippet-usage'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: monoStyle.copyWith(fontSize: 12, color: context.palette.ink),
          ),
        ),
      ],
    ),
  );
}

class _ColourChoice extends StatelessWidget {
  const _ColourChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final (name, label, colour) in snippetBoxColours)
        Tooltip(
          message: label,
          child: InkWell(
            key: Key('snippet-colour-$name'),
            onTap: () => onChanged(name),
            customBorder: const CircleBorder(),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colour,
                shape: BoxShape.circle,
                border: Border.all(
                  color: name == value
                      ? context.palette.ink
                      : context.palette.rule,
                  width: name == value ? 2.5 : 1,
                ),
              ),
              child: name == value
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ),
        ),
    ],
  );
}

/// La vista previa: el PDF, o por qué no lo hay.
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.preview,
    required this.compiling,
    required this.stale,
    required this.unavailable,
    required this.profile,
    required this.revision,
    required this.body,
    required this.onProfile,
    required this.onCompile,
  });

  final SnippetPreview? preview;
  final bool compiling;
  final bool stale;
  final bool unavailable;
  final String profile;
  final int revision;
  final String body;
  final ValueChanged<String> onProfile;
  final VoidCallback onCompile;

  @override
  Widget build(BuildContext context) {
    final result = preview;
    final status = unavailable
        ? tr('Sin compilar')
        : compiling
        ? tr('Compilando…')
        : result == null
        ? ''
        : !result.ok
        ? (result.engineFailed ? tr('Sin compilar') : tr('No compila'))
        : stale
        ? tr('Ha cambiado: se vuelve a compilar al parar de escribir')
        : tr('Compilado en {0} s', [
            result.seconds.toStringAsFixed(1).replaceAll('.', ','),
          ]);
    return Material(
      color: context.palette.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                Text(
                  'VISTA PREVIA',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: context.palette.muted,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    key: const Key('snippet-preview-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: result != null && !result.ok && !compiling
                          ? context.palette.teacher
                          : context.palette.muted,
                    ),
                  ),
                ),
                _Filter<String>(
                  key: const Key('snippet-preview-profile'),
                  icon: Icons.picture_as_pdf_outlined,
                  value: profile,
                  options: _previewProfiles,
                  onChanged: onProfile,
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('snippet-compile'),
                  tooltip: _mac
                      ? tr('Compilar ahora (⌘↵)')
                      : tr('Compilar ahora (Ctrl+Intro)'),
                  onPressed: compiling || unavailable ? null : onCompile,
                  icon: compiling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.rule),
          Expanded(child: _content(context, result)),
          if (body.isNotEmpty) _Compiled(body: body),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, SnippetPreview? result) {
    if (unavailable) {
      return _Empty(
        icon: Icons.desktop_mac_outlined,
        text: tr(
          'Aquí no se puede compilar. La vista previa necesita la '
          'aplicación de escritorio, con el motor de Didacta y TeX: se puede '
          'guardar igual, y se comprueba al compilar.',
        ),
      );
    }
    if (result == null) {
      return _Empty(
        icon: Icons.visibility_outlined,
        text: compiling
            ? tr('Compilando la vista previa…')
            : tr('Aquí se verá cómo queda, con el preámbulo de verdad.'),
      );
    }
    if (!result.ok) {
      return _Errors(errors: result.errors, engine: result.engineFailed);
    }
    final pdf = result.pdf;
    if (pdf == null) {
      return _Empty(
        icon: Icons.help_outline,
        text: tr('Ha compilado, pero no ha dejado ningún PDF.'),
      );
    }
    return Opacity(
      opacity: stale || compiling ? 0.55 : 1,
      child: ColoredBox(
        color: context.palette.pdfBackdrop,
        child: PdfViewer.file(
          pdf,
          key: ValueKey('$pdf#$revision'),
          params: PdfViewerParams(
            margin: 14,
            backgroundColor: context.palette.pdfBackdrop,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: context.palette.faint),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: context.palette.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Lo que dijo LaTeX, que es lo que hay que leer para arreglarlo.
class _Errors extends StatelessWidget {
  const _Errors({required this.errors, this.engine = false});

  final List<String> errors;

  /// Si lo que falló es el motor y no el LaTeX.
  final bool engine;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('snippet-preview-errors'),
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          Icon(Icons.error_outline, size: 17, color: context.palette.teacher),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              engine
                  ? tr(
                      'No se ha podido compilar: el motor no ha arrancado. No es '
                      'un error de la definición.',
                    )
                  : tr(
                      'No compila. Si lo guardas así, no compilará nada de los '
                      'repositorios que lo tengan.',
                    ),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.palette.teacher,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.terminal,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: SelectableText(
          errors.isEmpty
              ? tr('LaTeX no ha dicho por qué.')
              : errors.join('\n\n'),
          style: monoStyle.copyWith(
            fontSize: 12,
            height: 1.4,
            color: didactaOnTerminal,
          ),
        ),
      ),
    ],
  );
}

/// Lo que se compila, plegado: para quien quiera ver el LaTeX de verdad.
class _Compiled extends StatelessWidget {
  const _Compiled({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.palette.rule)),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          tr('Lo que se compila'),
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
        children: [_CodeBox(text: body)],
      ),
    ),
  );
}
