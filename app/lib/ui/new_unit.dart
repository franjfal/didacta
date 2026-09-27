/// Crear una lección desde la aplicación.
///
/// No existía: había que ir al terminal a escribir `didacta new unit`, que el
/// motor tenía desde el principio. Se pide lo mínimo --el título, el tema y el
/// tipo-- y el resto sale de dónde se está: la categoría es la que se está
/// mirando, y el nombre de la carpeta se saca del título.
library;

import 'package:flutter/material.dart';

import '../data/course_admin.dart';
import '../model/catalogue.dart';
import '../model/slug.dart';
import '../router.dart';
import '../state/session.dart';
import 'course_admin_ui.dart';
import 'document_properties.dart' show languageNameOf;
import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que se decide en el diálogo.
typedef NewUnitRequest = ({
  String title,
  String category,
  String topic,
  String slug,
  String kind,
  String? repo,
});

extension on NewUnitRequest {
  String get path => '$category/$topic/$slug';
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
  String kind = 'theory',
  bool open = true,
  String? onlyIn,
  bool askCategory = false,
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
      kind: kind,
      repos: writable,
      askCategory: askCategory,
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

class NewUnitDialog extends StatefulWidget {
  const NewUnitDialog({
    super.key,
    required this.session,
    required this.category,
    required this.topic,
    required this.kind,
    required this.repos,
    this.askCategory = false,
  });

  final Session session;
  final String category;
  final String topic;
  final String kind;

  /// Los repositorios donde se puede escribir. Con más de uno, se pregunta.
  final List<String> repos;

  /// Si se deja cambiar la categoría aunque venga dada: desde una
  /// composición es una suposición, desde la biblioteca es la que se mira.
  final bool askCategory;

  @override
  State<NewUnitDialog> createState() => _NewUnitDialogState();
}

class _NewUnitDialogState extends State<NewUnitDialog> {
  final TextEditingController _title = TextEditingController();
  late final TextEditingController _category = TextEditingController(
    text: widget.category,
  );
  late final TextEditingController _topic = TextEditingController(
    text: widget.topic,
  );
  late String _kind = widget.kind;
  late String? _repo = widget.repos.firstOrNull;

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _topic.dispose();
    super.dispose();
  }

  String get _slug => slugify(_title.text);
  String get _topicSlug => slugify(_topic.text);
  String get _categorySlug => slugify(_category.text);

  String get _where =>
      '${CourseAdmin.unitAreaFor(_kind)}/$_categorySlug/$_topicSlug/$_slug';

  /// Qué impide crearla, o null.
  String? get _problem {
    if (_title.text.trim().isEmpty) return tr('Falta el título.');
    if (_categorySlug.isEmpty) return tr('Falta la categoría.');
    if (_topicSlug.isEmpty) return tr('Falta el tema.');
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
        width: 480,
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
            Row(
              children: [
                // La categoría, solo si no se sabe: desde la biblioteca es la
                // que se está mirando, y preguntarla sería hacer repetirla.
                if (widget.askCategory || widget.category.isEmpty) ...[
                  Expanded(
                    child: TextField(
                      key: const Key('new-unit-category'),
                      controller: _category,
                      decoration: InputDecoration(
                        labelText: tr('Categoría'),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    key: const Key('new-unit-topic'),
                    controller: _topic,
                    decoration: InputDecoration(
                      labelText: widget.askCategory || widget.category.isEmpty
                          ? tr('Tema')
                          : tr('Tema, dentro de {0}', [widget.category]),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    key: const Key('new-unit-kind'),
                    initialValue: _kind,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Tipo'),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final kind in unitKinds)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(kindName(kind)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _kind = value ?? _kind),
                  ),
                ),
              ],
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
                  category: _categorySlug,
                  topic: _topicSlug,
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

/// Lleva [unit] a otra carpeta, o le cambia el nombre de la suya, y la abre
/// allí. Devuelve la ruta nueva, o null.
///
/// Es la misma lección en otro sitio: lo que la nombra se reescribe, y su id
/// y sus traducciones no cambian. Con algo sin guardar en ella no se ofrece:
/// el editor abierto escribiría en la carpeta que ya no existe.
Future<String?> moveUnitFrom(
  BuildContext context,
  Session session,
  Unit unit,
) async {
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
  final to = await showDialog<String>(
    context: context,
    builder: (context) => MoveUnitDialog(session: session, unit: unit),
  );
  if (to == null || !context.mounted) return null;

  final title = unit.title(session.language);
  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.moveUnit(unit: unit.path, to: to, title: title),
    done: tr('Lección «{0}» movida a {1}/{2}.', [title, unit.area, to]),
    repo: unit.repo.isEmpty ? null : unit.repo,
  );
  if (!ok) return null;
  final moved = '${unit.area}/$to';
  if (context.mounted) goTo(context, Routes.unit(moved));
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
  late final TextEditingController _path = TextEditingController(
    text: widget.unit.reference_,
  );

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  /// La ruta escrita, carpeta a carpeta con el nombre que tendrá en disco.
  String get _to => [
    for (final part in _path.text.split('/'))
      if (slugify(part).isNotEmpty) slugify(part),
  ].join('/');

  String get _where => '${widget.unit.area}/$_to';

  String? get _problem {
    if (_to.isEmpty) return tr('Falta la carpeta.');
    if (_where == widget.unit.path) return tr('Es donde ya está.');
    if (widget.session.unitByPath(_where, repo: widget.unit.repo) != null) {
      return tr('Ya hay una lección en {0}.', [_where]);
    }
    return null;
  }

  /// Los documentos que la nombran, que son los que se van a reescribir.
  int get _documents => {
    for (final use in widget.unit.usedBy)
      '${use.course}/${use.year}/${use.document}',
  }.length;

  /// Los cursos de esos documentos, con su nombre: «Análisis · 2025-2026».
  ///
  /// Mover está para todos, y quien mueve una lección suya puede no saber que
  /// otro curso --el de un compañero, el del año pasado-- la usa también. Lo
  /// que se reescribe se nombra antes de confirmar, no después.
  List<String> get _courses {
    final session = widget.session;
    final seen = <String>{};
    final named = <String>[];
    for (final use in widget.unit.usedBy) {
      if (!seen.add('${use.course}/${use.year}')) continue;
      final title =
          session.courseById(use.course)?.title(session.language) ?? use.course;
      named.add('$title · ${use.year}');
    }
    named.sort();
    return named;
  }

  /// Las otras lecciones que la tienen de prerrequisito, que también se
  /// reescriben.
  int get _prerequisiteOf {
    final unit = widget.unit;
    final names = {unit.id, unit.path, unit.reference_};
    var count = 0;
    for (final other in widget.session.catalogue.units) {
      if (identical(other, unit) || other.repo != unit.repo) continue;
      if (other.prerequisites.any(names.contains)) count += 1;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final documents = _documents;
    final courses = _courses;
    final prerequisiteOf = _prerequisiteOf;
    return AlertDialog(
      title: Text(tr('Mover o renombrar')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('move-unit-path'),
              controller: _path,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Carpeta, dentro de {0}/', [widget.unit.area]),
                helperText: tr('categoría/tema/nombre'),
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              problem ?? tr('Pasará a {0}', [_where]),
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
            // Lo que más asusta de mover algo es romper lo que lo usa, así
            // que se dice antes: cuántos documentos se tocan, y que su id y
            // sus traducciones siguen siendo los mismos.
            Text(
              documents == 0
                  ? tr(
                      'Ningún documento la usa. Su id y sus traducciones no '
                      'cambian.',
                    )
                  : tr(
                      'Se reescribirá{0} {1} '
                      'documento{2} que la '
                      'usa{3}, en el mismo '
                      'cambio. Su id y sus traducciones no cambian.',
                      [
                        documents == 1 ? '' : 'n',
                        documents,
                        documents == 1 ? '' : 's',
                        documents == 1 ? '' : 'n',
                      ],
                    ),
              key: const Key('move-unit-uses'),
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
            if (courses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                courses.length == 1
                    ? 'En ${courses.single}.'
                    : tr(
                        'En {0} cursos: '
                        '{1}. El cambio les llega a '
                        'todos, también a los que no das tú.',
                        [courses.length, _listed(courses)],
                      ),
                key: const Key('move-unit-courses'),
                style: TextStyle(
                  fontSize: 13,
                  color: courses.length == 1
                      ? context.palette.muted
                      : context.palette.teacher,
                ),
              ),
            ],
            if (prerequisiteOf > 0) ...[
              const SizedBox(height: 8),
              Text(
                prerequisiteOf == 1
                    ? tr('Y otra lección que la tiene de prerrequisito.')
                    : tr(
                        'Y {0} lecciones que la tienen de '
                        'prerrequisito.',
                        [prerequisiteOf],
                      ),
                key: const Key('move-unit-prerequisites'),
                style: TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ],
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

/// «a, b y c», o las cinco primeras y cuántas más.
String _listed(List<String> items) {
  if (items.length > 5) {
    return tr('{0} y {1} más', [items.take(5).join(', '), items.length - 5]);
  }
  if (items.length == 1) return items.single;
  return '${items.take(items.length - 1).join(', ')} y ${items.last}';
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
