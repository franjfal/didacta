/// Crear una lección desde la aplicación.
///
/// No existía: había que ir al terminal a escribir `didacta new unit`, que el
/// motor tenía desde el principio. Se pide lo mínimo --el título, el sitio y
/// el tipo-- y el resto sale de dónde se está: el sitio es el que se está
/// mirando en la biblioteca, elegido en las mismas columnas, y el nombre de la
/// carpeta se saca del título.
library;

import 'package:flutter/material.dart';

import '../data/course_admin.dart';
import '../model/catalogue.dart';
import '../model/slug.dart';
import '../router.dart';
import '../state/session.dart';
import 'course_admin_ui.dart';
import 'document_properties.dart' show languageNameOf;
import 'place_browser.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que se decide en el diálogo.
typedef NewUnitRequest = ({
  String title,
  String category,
  String topic,
  String subtopic,
  String slug,
  String kind,
  String? repo,
});

extension on NewUnitRequest {
  /// Su carpeta, que es su sitio: `categoría/tema/subtema/nombre`.
  String get path => '$category/$topic/$subtopic/$slug';
}

/// Pregunta, crea la lección y la abre. Devuelve su ruta, o null.
///
/// [open] la abre al acabar, que es lo que se quiere desde la biblioteca; desde
/// una composición no, porque se vuelve a ella para añadirla. [onlyIn] la deja
/// en ese repositorio sin preguntar: un documento y sus lecciones viven en el
/// mismo.
Future<String?> createUnitFrom(
  BuildContext context,
  Session session, {
  required String category,
  String? topic,
  String? subtopic,
  String kind = 'theory',
  bool open = true,
  String? onlyIn,
}) async {
  final writable = onlyIn != null
      ? [onlyIn]
      : [
          for (final repo in session.workspace.repos)
            if (session.canWriteIn(repo.id)) repo.id,
        ];
  final request = await showDialog<NewUnitRequest>(
    context: context,
    builder: (context) => NewUnitDialog(
      session: session,
      category: category,
      topic: topic ?? '',
      subtopic: subtopic ?? '',
      kind: kind,
      repos: writable,
      preferredRepo: repoWithMost(session, writable, category, topic),
    ),
  );
  if (request == null || !context.mounted) return null;

  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.createUnit(
      path: request.path,
      kind: request.kind,
      title: request.title,
    ),
    done: tr('Lección «{0}» creada.', [request.title]),
    repo: request.repo,
  );
  if (!ok) return null;
  await session.reloadCatalogue();
  final created = '${CourseAdmin.unitAreaFor(request.kind)}/${request.path}';
  if (open && context.mounted) goTo(context, Routes.unit(created));
  return created;
}

/// El repositorio que ya tiene más lecciones de [category] (y de [topic],
/// si lo hay), de entre [repos]: donde va lo nuevo de ese tema.
///
/// Proponer el primero de la lista era proponer el del ejemplo para una
/// lección de álgebra que vive, con todas las demás, en el del departamento.
String? repoWithMost(
  Session session,
  List<String> repos,
  String category,
  String? topic,
) {
  final counts = <String, int>{};
  for (final unit in session.catalogue.units) {
    if (unit.category != category) continue;
    if (topic != null && topic.isNotEmpty && unit.topic != topic) continue;
    if (!repos.contains(unit.repo)) continue;
    counts[unit.repo] = (counts[unit.repo] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

class NewUnitDialog extends StatefulWidget {
  const NewUnitDialog({
    super.key,
    required this.session,
    required this.category,
    required this.topic,
    this.subtopic = '',
    required this.kind,
    required this.repos,
    this.preferredRepo,
  });

  final Session session;
  final String category;
  final String topic;
  final String subtopic;
  final String kind;

  /// Los repositorios donde se puede escribir. Con más de uno, se pregunta.
  final List<String> repos;

  /// El que viene elegido: el de las lecciones de al lado, si lo hay.
  final String? preferredRepo;

  @override
  State<NewUnitDialog> createState() => _NewUnitDialogState();
}

class _NewUnitDialogState extends State<NewUnitDialog> {
  final TextEditingController _title = TextEditingController();

  /// Dónde va: lo que se miraba al pulsar, hasta donde se sepa.
  late Place _place = [
    widget.category,
    widget.topic,
    widget.subtopic,
  ].takeWhile((part) => part.isNotEmpty).toList();
  late String _kind = widget.kind;
  late String? _repo = widget.repos.contains(widget.preferredRepo)
      ? widget.preferredRepo
      : widget.repos.firstOrNull;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _slug => slugify(_title.text);

  String get _where =>
      '${CourseAdmin.unitAreaFor(_kind)}/${placeKey(_place)}/$_slug';

  /// Qué impide crearla, o null.
  String? get _problem {
    if (_title.text.trim().isEmpty) return tr('Falta el título.');
    if (_place.length < 3) {
      return tr('Elige un subtema: cada lección vive en uno.');
    }
    if (_slug.isEmpty) return tr('El título no da un nombre de carpeta.');
    if (widget.session.unitByPath(_where, repo: _repo) != null) {
      return tr('Ya hay una lección en {0}.', [_where]);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return AlertDialog(
      title: Text(tr('Nueva lección')),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('new-unit-title'),
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Título'),
                hintText: tr('Espacios de Banach'),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PlaceBrowser(
              key: const Key('new-unit-place'),
              session: widget.session,
              place: _place,
              onChanged: (next) => setState(() => _place = next),
              height: 220,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('new-unit-kind'),
              initialValue: _kind,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('Tipo'),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final kind in unitKinds)
                  DropdownMenuItem(value: kind, child: Text(kindName(kind))),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            if (widget.repos.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('new-unit-repo'),
                initialValue: _repo,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Repositorio'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final repo in widget.repos)
                    DropdownMenuItem(
                      value: repo,
                      child: Text(
                        widget.session.workspace.byId(repo)?.label ?? repo,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _repo = value),
              ),
            ],
            const SizedBox(height: 12),
            // Dónde va a quedar, antes de crearla: es la ruta con la que se
            // la va a nombrar en las composiciones.
            Text(
              problem ?? tr('Se creará en {0}', [_where]),
              key: const Key('new-unit-where'),
              style: TextStyle(
                fontSize: 12,
                fontFamily: problem == null ? 'monospace' : null,
                color: problem == null
                    ? context.palette.muted
                    : context.palette.teacher,
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
          key: const Key('new-unit-create'),
          onPressed: problem != null
              ? null
              : () => Navigator.of(context).pop((
                  title: _title.text.trim(),
                  category: _place[0],
                  topic: _place[1],
                  subtopic: _place[2],
                  slug: _slug,
                  kind: _kind,
                  repo: _repo,
                )),
          child: Text(tr('Crear')),
        ),
      ],
    );
  }
}

/// Duplica [unit] con otro título, al lado de la original, y abre la copia.
///
/// Para cuando lo que se va a escribir se parece a algo que ya existe: el
/// mismo esquema de problema con otros números, la misma lección para otro
/// público. Al lado y no en otro sitio porque es lo que se quiere casi
/// siempre, y lo que haga falta después --reclasificarla-- está en sus
/// metadatos. Devuelve la ruta de la copia, o null.
Future<String?> duplicateUnitFrom(
  BuildContext context,
  Session session,
  Unit unit,
) async {
  // El título, en el idioma que se mira si la lección lo tiene; si no, en el
  // de referencia, que es el que tiene seguro.
  final language = unit.statusIn(session.language).exists
      ? session.language
      : unit.reference;
  final title = await showDialog<String>(
    context: context,
    builder: (context) =>
        DuplicateUnitDialog(session: session, unit: unit, language: language),
  );
  if (title == null || !context.mounted) return null;

  final folder = duplicateFolderOf(unit);
  final path = '$folder/${slugify(title)}';
  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.duplicateUnit(
      from: unit.path,
      path: path.substring(path.indexOf('/') + 1),
      title: title,
      fromTitle: unit.title(language),
      language: language,
    ),
    done: tr('Lección «{0}» creada a partir de «{1}».', [
      title,
      unit.title(language),
    ]),
    repo: unit.repo.isEmpty ? null : unit.repo,
  );
  if (!ok) return null;
  await session.reloadCatalogue();
  if (context.mounted) goTo(context, Routes.unit(path));
  return path;
}

/// La carpeta donde va la copia: la misma que la de la original.
String duplicateFolderOf(Unit unit) => unit.path.contains('/')
    ? unit.path.substring(0, unit.path.lastIndexOf('/'))
    : unit.path;

class DuplicateUnitDialog extends StatefulWidget {
  const DuplicateUnitDialog({
    super.key,
    required this.session,
    required this.unit,
    required this.language,
  });

  final Session session;
  final Unit unit;

  /// En qué idioma se escribe el título nuevo.
  final String language;

  @override
  State<DuplicateUnitDialog> createState() => _DuplicateUnitDialogState();
}

class _DuplicateUnitDialogState extends State<DuplicateUnitDialog> {
  // Con el título de la original seleccionado: casi siempre se va a cambiar
  // entero, y así basta con empezar a escribir.
  late final TextEditingController _title = () {
    final text = widget.unit.title(widget.language);
    return TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _where =>
      '${duplicateFolderOf(widget.unit)}/${slugify(_title.text)}';

  String? get _problem {
    if (_title.text.trim().isEmpty) return tr('Falta el título.');
    if (slugify(_title.text).isEmpty) {
      return tr('El título no da un nombre de carpeta.');
    }
    // Con el mismo título serían dos filas iguales en la biblioteca, y no
    // habría forma de saber cuál es la copia sin abrirlas.
    if (_title.text.trim() == widget.unit.title(widget.language)) {
      return tr('Ponle otro título, para distinguirla de la original.');
    }
    if (widget.session.unitByPath(_where, repo: widget.unit.repo) != null) {
      return tr('Ya hay una lección en {0}.', [_where]);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return AlertDialog(
      title: Text(tr('Duplicar la lección')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Una lección nueva que empieza siendo una copia de '
                '«{0}»: sus idiomas, sus '
                'figuras y sus metadatos. Desde ese momento son dos, y cambiar '
                'una no cambia la otra.',
                [widget.unit.title(widget.language)],
              ),
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('duplicate-unit-title'),
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr(
                  'Título '
                  '({0})',
                  [languageNameOf(widget.session, widget.language)],
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_problem == null) {
                  Navigator.of(context).pop(_title.text.trim());
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              problem ?? tr('Se creará en {0}', [_where]),
              key: const Key('duplicate-unit-where'),
              style: TextStyle(
                fontSize: 12,
                fontFamily: problem == null ? 'monospace' : null,
                color: problem == null
                    ? context.palette.muted
                    : context.palette.teacher,
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
          key: const Key('duplicate-unit-create'),
          onPressed: problem != null
              ? null
              : () => Navigator.of(context).pop(_title.text.trim()),
          child: Text(tr('Duplicar')),
        ),
      ],
    );
  }
}

/// Lleva [unit] a otro sitio de la biblioteca --otra categoría, tema o
/// subtema, que es otra carpeta-- o le cambia el nombre de la suya, y la abre
/// allí si [open]. Con [to] no pregunta: es lo que pasa al arrastrarla a un
/// subtema. Devuelve la ruta nueva, o null.
///
/// Es la misma lección en otro sitio: lo que la usa la nombra por su id, así
/// que no hay nada que reescribir, y su id y sus traducciones no cambian. Con algo sin guardar en ella no se ofrece:
/// el editor abierto escribiría en la carpeta que ya no existe.
Future<String?> moveUnitFrom(
  BuildContext context,
  Session session,
  Unit unit, {
  Place? to,
  bool open = true,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final pending = session.unsaved.whatAt(Routes.unit(unit.path));
  if (pending.isNotEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Guarda o descarta antes lo que tienes sin guardar: '
            '{0}.',
            [pending.join(', ')],
          ),
        ),
      ),
    );
    return null;
  }
  final String? target;
  if (to != null) {
    target = '${placeKey(to)}/${unit.path.split('/').last}';
    if (session.unitByPath('${unit.area}/$target', repo: unit.repo) != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr('Ya hay una lección en {0}.', ['${unit.area}/$target']),
          ),
        ),
      );
      return null;
    }
  } else {
    target = await showDialog<String>(
      context: context,
      builder: (context) => MoveUnitDialog(session: session, unit: unit),
    );
  }
  if (target == null || !context.mounted) return null;

  final title = unit.title(session.language);
  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.moveUnit(unit: unit.path, to: target!, title: title),
    done: tr('Lección «{0}» movida a {1}/{2}.', [title, unit.area, target]),
    repo: unit.repo.isEmpty ? null : unit.repo,
  );
  if (!ok) return null;
  final moved = '${unit.area}/$target';
  if (open && context.mounted) goTo(context, Routes.unit(moved));
  await session.reloadCatalogue();
  return moved;
}

class MoveUnitDialog extends StatefulWidget {
  const MoveUnitDialog({super.key, required this.session, required this.unit});

  final Session session;
  final Unit unit;

  @override
  State<MoveUnitDialog> createState() => _MoveUnitDialogState();
}

class _MoveUnitDialogState extends State<MoveUnitDialog> {
  /// Donde está ahora: el sitio de su `unit.yaml`.
  late final Place _from = [
    widget.unit.category,
    widget.unit.topic,
    widget.unit.subtopic,
  ].takeWhile((part) => part.isNotEmpty).toList();

  late Place _place = _from;

  late final TextEditingController _name = TextEditingController(
    text: widget.unit.path.split('/').last,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _slug => slugify(_name.text);

  /// A dónde, sin el árbol: `categoría/tema/subtema/nombre`.
  String get _to => '${placeKey(_place)}/$_slug';

  String get _where => '${widget.unit.area}/$_to';

  String? get _problem {
    if (_place.length < 3) {
      return tr('Elige un subtema: cada lección vive en uno.');
    }
    if (_slug.isEmpty) return tr('Falta el nombre de la carpeta.');
    if (_where == widget.unit.path) return tr('Es donde ya está.');
    if (widget.session.unitByPath(_where, repo: widget.unit.repo) != null) {
      return tr('Ya hay una lección en {0}.', [_where]);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final uses = {
      for (final use in widget.unit.usedBy)
        '${use.course}/${use.year}/${use.document}',
    }.length;
    return AlertDialog(
      title: Text(
        tr('Mover «{0}»', [widget.unit.title(widget.session.language)]),
      ),
      content: SizedBox(
        width: 660,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaceBrowser(
              key: const Key('move-unit-place'),
              session: widget.session,
              place: _place,
              onChanged: (next) => setState(() => _place = next),
              height: 300,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('move-unit-path'),
              controller: _name,
              decoration: InputDecoration(
                isDense: true,
                labelText: tr('Nombre de la carpeta'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Text(
              problem ?? tr('Irá a {0}', [_where]),
              key: const Key('move-unit-where'),
              style: TextStyle(
                fontSize: 12,
                fontFamily: problem == null ? 'monospace' : null,
                color: problem == null
                    ? context.palette.muted
                    : context.palette.teacher,
              ),
            ),
            const SizedBox(height: 10),
            // Lo que más asusta de mover algo es romper lo que lo usa. Ya no
            // puede pasar: los temas la nombran por su id, que no cambia, y
            // es el motor quien le dice a LaTeX dónde está ahora.
            Text(
              uses == 0
                  ? tr(
                      'Ningún documento la usa. Su id y sus traducciones no '
                      'cambian.',
                    )
                  : uses == 1
                  ? tr(
                      'La usa 1 documento, y no hay que tocarlo: la nombra '
                      'por su id, que no cambia.',
                    )
                  : tr(
                      'La usan {0} documentos, y no hay que tocar ninguno: la '
                      'nombran por su id, que no cambia.',
                      [uses],
                    ),
              key: const Key('move-unit-uses'),
              style: TextStyle(fontSize: 13, color: context.palette.muted),
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
          key: const Key('move-unit-apply'),
          onPressed: problem != null
              ? null
              : () => Navigator.of(context).pop(_to),
          child: Text(tr('Mover')),
        ),
      ],
    );
  }
}

/// Los tipos que acepta el motor, en el orden en que se ofrecen.
const List<String> unitKinds = [
  'theory',
  'problem',
  'example',
  'handout',
  'practical',
  'seminar',
  'activity',
  'experiment',
  'history',
];
