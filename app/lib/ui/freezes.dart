/// Las versiones congeladas de un curso: crearlas, abrirlas, compararlas,
/// restaurar desde ellas y quitarlas.
///
/// Una congelación es **un commit con nombre**. No se copia nada: git ya
/// guarda el contenido de cada commit, y lo que falta es lo que git no sabe
/// -- que ese commit concreto es «Antes del primer parcial». Toda la pantalla
/// está escrita alrededor de esa frase, porque es la que evita las dos
/// preguntas que llegarían si no se dijera: «¿esto ocupa el doble?» y «¿si la
/// borro, pierdo aquello?».
///
/// Tres reglas que se ven en la interfaz:
///
/// **Lo que está sin guardar no entra.** Una congelación apunta a un commit,
/// así que se dice antes de crearla y no después.
///
/// **Quitarla no borra nada.** Ni commits, ni historia, ni el curso, ni otra
/// congelación del mismo commit. El diálogo lo dice con esas palabras.
///
/// **Restaurar deja un cambio pendiente.** Nunca un `reset`, nunca un force
/// push. Lo que sale es un commit más, encima, como cualquier edición.
library;

import 'package:flutter/material.dart';

import '../data/frozen.dart';
import '../data/local_clone.dart';
import '../model/catalogue.dart';
import '../state/session.dart';
import 'compare_view.dart';
import 'course_admin_ui.dart';
import 'theme.dart';

/// La lista de versiones congeladas de un curso.
Future<void> showFreezes(
  BuildContext context,
  Session session,
  Course course,
  String year,
) => showDialog<void>(
  context: context,
  builder: (context) =>
      FreezesDialog(session: session, course: course, year: year),
);

class FreezesDialog extends StatefulWidget {
  const FreezesDialog({
    super.key,
    required this.session,
    required this.course,
    required this.year,
  });

  final Session session;
  final Course course;
  final String year;

  @override
  State<FreezesDialog> createState() => _FreezesDialogState();
}

class _FreezesDialogState extends State<FreezesDialog> {
  List<Freeze> get _freezes =>
      widget.session.freezesOf(widget.course.id, widget.year);

  String? get _repo =>
      widget.course.years[widget.year]?.repos.firstOrNull ??
      widget.course.sources.keys.firstOrNull;

  @override
  Widget build(BuildContext context) {
    final freezes = _freezes;
    final session = widget.session;
    return AlertDialog(
      title: Text(
        'Versiones congeladas · ${widget.course.title(session.language)} '
        '${widget.year}',
      ),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Note(
              'Cada una es un commit con nombre: el estado exacto del '
              'material en ese punto. No hay ninguna copia detrás, así que '
              'tener diez no ocupa diez veces más -- y quitar una no borra '
              'ningún commit.',
            ),
            const SizedBox(height: Space.medium),
            Expanded(
              child: freezes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Este curso no tiene ninguna versión congelada '
                          'todavía.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: didactaMuted),
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final freeze in freezes)
                          _FreezeTile(
                            key: Key('freeze-${freeze.id}'),
                            freeze: freeze,
                            session: session,
                            course: widget.course,
                            year: widget.year,
                            onChanged: () => setState(() {}),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('freeze-cache'),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final count = await session.clearFrozenCache();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  count == 0
                      ? 'No había nada guardado en la caché.'
                      : 'Caché vaciada: $count versión(es). Se vuelven a '
                            'preparar solas al abrirlas.',
                ),
              ),
            );
          },
          child: const Text('Vaciar la caché'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          key: const Key('freeze-new'),
          icon: const Icon(Icons.ac_unit, size: 16),
          onPressed: () async {
            final made = await createFreeze(
              context,
              session,
              widget.course,
              widget.year,
              repo: _repo,
            );
            if (made && mounted) setState(() {});
          },
          label: const Text('Congelar esto ahora…'),
        ),
      ],
    );
  }
}

class _FreezeTile extends StatelessWidget {
  const _FreezeTile({
    super.key,
    required this.freeze,
    required this.session,
    required this.course,
    required this.year,
    required this.onChanged,
  });

  final Freeze freeze;
  final Session session;
  final Course course;
  final String year;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final open = session.frozen?.freeze.id == freeze.id;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.small),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: open ? didactaSelected : didactaCard,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 10),
            child: Icon(Icons.ac_unit, size: 16, color: didactaThm),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  freeze.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (freeze.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    freeze.description,
                    style: const TextStyle(fontSize: 12, color: didactaMuted),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  [
                    freeze.shortCommit,
                    if (freeze.created.isNotEmpty)
                      describeWhen(freeze.when)
                    else
                      '',
                  ].where((piece) => piece.isNotEmpty).join('  ·  '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: didactaMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          MenuAnchor(
            builder: (context, controller, child) => IconButton(
              key: Key('freeze-menu-${freeze.id}'),
              tooltip: 'Qué hacer con esta versión',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_horiz, size: 18),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              MenuItemButton(
                key: Key('freeze-open-${freeze.id}'),
                leadingIcon: const Icon(Icons.visibility_outlined, size: 15),
                onPressed: () => _open(context),
                child: const Text('Abrir'),
              ),
              MenuItemButton(
                key: Key('freeze-compare-head-${freeze.id}'),
                leadingIcon: const Icon(Icons.compare_arrows, size: 15),
                onPressed: () => _compare(context, against: null),
                child: const Text('Comparar con la versión actual'),
              ),
              MenuItemButton(
                key: Key('freeze-compare-other-${freeze.id}'),
                leadingIcon: const Icon(Icons.difference_outlined, size: 15),
                onPressed: () => _compareWith(context),
                child: const Text('Comparar con…'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                key: Key('freeze-year-${freeze.id}'),
                leadingIcon: const Icon(Icons.add, size: 15),
                onPressed: () => _newYear(context),
                child: const Text('Crear un curso desde aquí…'),
              ),
              MenuItemButton(
                key: Key('freeze-restore-${freeze.id}'),
                leadingIcon: const Icon(Icons.restore, size: 15),
                onPressed: () => _restore(context),
                child: const Text('Restaurar…'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                key: Key('freeze-rename-${freeze.id}'),
                leadingIcon: const Icon(Icons.edit_outlined, size: 15),
                onPressed: () => _rename(context),
                child: const Text('Renombrar…'),
              ),
              MenuItemButton(
                key: Key('freeze-remove-${freeze.id}'),
                leadingIcon: const Icon(
                  Icons.delete_outline,
                  size: 15,
                  color: didactaTeacher,
                ),
                onPressed: () => _remove(context),
                child: const Text('Quitar esta versión…'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();
    try {
      await session.openFreeze(freeze);
    } on FrozenException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.message),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _compare(BuildContext context, {Freeze? against}) =>
      showComparison(
        context,
        session: session,
        course: course,
        year: year,
        from: freeze,
        to: against,
      );

  Future<void> _compareWith(BuildContext context) async {
    final others = [
      for (final other in session.freezesOf(course.id, year))
        if (other.id != freeze.id) other,
    ];
    final chosen = await showDialog<Freeze>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Comparar con'),
        children: [
          SimpleDialogOption(
            key: const Key('compare-with-head'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('La versión actual'),
          ),
          if (others.isNotEmpty) const Divider(height: 1),
          for (final other in others)
            SimpleDialogOption(
              key: Key('compare-with-${other.id}'),
              onPressed: () => Navigator.of(context).pop(other),
              child: Text('${other.name}  ·  ${other.shortCommit}'),
            ),
        ],
      ),
    );
    if (!context.mounted) return;
    await _compare(context, against: chosen);
  }

  Future<void> _newYear(BuildContext context) async {
    final navigator = Navigator.of(context);
    final made = await showYearFromFreeze(context, session, course, freeze);
    if (made && navigator.mounted) navigator.pop();
  }

  Future<void> _restore(BuildContext context) => showRestore(
    context,
    session: session,
    course: course,
    year: year,
    freeze: freeze,
  );

  Future<void> _rename(BuildContext context) async {
    final done = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => _NameDialog(
        title: 'Renombrar la versión congelada',
        name: freeze.name,
        description: freeze.description,
        confirm: 'Guardar',
      ),
    );
    if (done == null || !context.mounted) return;
    final ok = await runAdmin(
      context,
      session,
      (admin) => admin.renameFreeze(
        course: course.id,
        year: year,
        id: freeze.id,
        name: done.name,
        description: done.description,
      ),
      done: 'Versión congelada renombrada.',
      repo: freeze.repo.isEmpty ? null : freeze.repo,
    );
    if (ok) {
      await session.reloadCatalogue();
      onChanged();
    }
  }

  Future<void> _remove(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Quitar «${freeze.name}»?'),
        content: const SizedBox(
          width: 460,
          child: Note(
            'Se quita su entrada y su carpeta de la caché, y nada más.\n\n'
            'El commit sigue donde estaba, la historia no se toca, el curso '
            'no cambia y las demás versiones congeladas siguen igual -- '
            'también las que apunten a este mismo commit.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-remove-freeze'),
            style: FilledButton.styleFrom(backgroundColor: didactaTeacher),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;

    final ok = await runAdmin(
      context,
      session,
      (admin) => admin.removeFreeze(
        course: course.id,
        year: year,
        id: freeze.id,
        name: freeze.name,
      ),
      done: 'Versión congelada quitada. Ningún commit se ha borrado.',
      repo: freeze.repo.isEmpty ? null : freeze.repo,
    );
    if (!ok) return;
    // El árbol, después de la metadata: si el commit lo usa otra
    // congelación, se queda.
    final service = session.frozenIn(freeze.repo.isEmpty ? null : freeze.repo);
    if (service != null) {
      await service.close(freeze, others: session.freezesOf(course.id, year));
    }
    if (session.frozen?.freeze.id == freeze.id) session.leaveFreeze();
    await session.reloadCatalogue();
    onChanged();
  }
}

/// Crea una congelación del estado que hay ahora mismo.
Future<bool> createFreeze(
  BuildContext context,
  Session session,
  Course course,
  String year, {
  String? repo,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  // Lo que está sin guardar no entra: una congelación apunta a un commit.
  // Decirlo antes y no después es la diferencia entre una foto incompleta y
  // una decisión.
  final pending = await session.pendingIn(repo);
  if (!context.mounted) return false;

  final String head;
  try {
    head = await session.headOf(repo);
  } on FrozenException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  }
  if (!context.mounted) return false;

  final done = await showDialog<({String name, String description})>(
    context: context,
    builder: (context) => _NameDialog(
      title: 'Congelar ${course.title(session.language)} $year',
      name: '',
      description: '',
      confirm: 'Congelar',
      hint: head,
      pending: pending,
    ),
  );
  if (done == null || !context.mounted) return false;

  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.addFreeze(
      course: course.id,
      year: year,
      name: done.name,
      commit: head,
      description: done.description,
    ),
    done:
        'Congelada «${done.name}». No se ha copiado nada: es el commit el '
        'que guarda el estado.',
    repo: repo,
  );
  if (ok) await session.reloadCatalogue();
  return ok;
}

/// Un nombre y una descripción. Se usa al crear y al renombrar.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.name,
    required this.description,
    required this.confirm,
    this.hint = '',
    this.pending = const [],
  });

  final String title;
  final String name;
  final String description;
  final String confirm;

  /// El commit al que apuntará, para poder verlo antes.
  final String hint;

  /// Lo que hay sin guardar y por tanto no entra.
  final List<String> pending;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.description,
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('freeze-name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Inicio curso 2026-27',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.medium),
          TextField(
            key: const Key('freeze-description'),
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              hintText: 'Como se repartió el primer día.',
            ),
          ),
          if (widget.hint.isNotEmpty) ...[
            const SizedBox(height: Space.medium),
            Text(
              'Apuntará al commit ${widget.hint.substring(0, 7)}, que es el '
              'que hay ahora.',
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
          ],
          if (widget.pending.isNotEmpty) ...[
            const SizedBox(height: Space.medium),
            Note(
              widget.pending.length == 1
                  ? 'Hay 1 fichero sin guardar, y no entra en la versión '
                        'congelada: una congelación apunta a un commit. '
                        'Guárdalo antes si quieres que forme parte de esta.'
                  : 'Hay ${widget.pending.length} ficheros sin guardar, y no '
                        'entran en la versión congelada: una congelación '
                        'apunta a un commit. Guárdalos antes si quieres que '
                        'formen parte de esta.',
              tone: didactaEx,
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
        key: const Key('freeze-confirm'),
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop((
                name: _name.text.trim(),
                description: _description.text.trim(),
              )),
        child: Text(widget.confirm),
      ),
    ],
  );
}

/// Crea un curso académico a partir de una versión congelada.
Future<bool> showYearFromFreeze(
  BuildContext context,
  Session session,
  Course course,
  Freeze freeze,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = session.frozenIn(freeze.repo.isEmpty ? null : freeze.repo);
  if (service == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Esto necesita el clon del repositorio.')),
    );
    return false;
  }

  final FrozenView view;
  try {
    view = await service.open(freeze);
  } on FrozenException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  }
  if (!context.mounted) return false;

  final target = await showDialog<({String course, String year})>(
    context: context,
    builder: (context) =>
        _YearFromFreezeDialog(session: session, course: course, freeze: freeze),
  );
  if (target == null || !context.mounted) return false;

  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.duplicateYear(
      course: target.course,
      year: target.year,
      fromDirectory:
          '${view.directory}/courses/${freeze.course}/${freeze.year}',
      fromLabel: freeze.name,
    ),
    done: 'Curso ${target.year} creado desde «${freeze.name}».',
    repo: freeze.repo.isEmpty ? null : freeze.repo,
  );
  if (ok) await session.reloadCatalogue();
  return ok;
}

class _YearFromFreezeDialog extends StatefulWidget {
  const _YearFromFreezeDialog({
    required this.session,
    required this.course,
    required this.freeze,
  });

  final Session session;
  final Course course;
  final Freeze freeze;

  @override
  State<_YearFromFreezeDialog> createState() => _YearFromFreezeDialogState();
}

class _YearFromFreezeDialogState extends State<_YearFromFreezeDialog> {
  late String _course = widget.course.id;
  late final TextEditingController _year = TextEditingController(
    text: _nextAfter(widget.freeze.year),
  );

  /// `2025-2026` -> `2026-2027`. El caso corriente, escrito ya.
  static String _nextAfter(String year) {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(year);
    if (match == null) return '';
    final first = int.parse(match.group(1)!) + 1;
    return '$first-${first + 1}';
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final courses = session.catalogue.courses;
    final taken = session.courseById(_course)?.years.keys ?? const <String>[];
    final clash = taken.contains(_year.text.trim());
    return AlertDialog(
      title: Text('Crear un curso desde «${widget.freeze.name}»'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'En qué asignatura',
              style: TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              key: const Key('from-freeze-course'),
              initialValue: _course,
              items: [
                for (final other in courses)
                  DropdownMenuItem(
                    value: other.id,
                    child: Text(other.title(session.language)),
                  ),
              ],
              onChanged: (value) => setState(() => _course = value ?? _course),
            ),
            const SizedBox(height: Space.medium),
            TextField(
              key: const Key('from-freeze-year'),
              controller: _year,
              decoration: const InputDecoration(
                labelText: 'Curso académico',
                hintText: '2026-2027',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.medium),
            const Note(
              'Se copia la composición tal como estaba en esa versión: qué '
              'temas lleva y en qué orden. Las lecciones son las de ahora, no '
              'copias de las de entonces -- para eso está restaurar.',
            ),
            if (clash) ...[
              const SizedBox(height: Space.small),
              const Note(
                'Esa asignatura ya tiene ese curso académico.',
                tone: didactaTeacher,
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
          key: const Key('from-freeze-confirm'),
          onPressed: _year.text.trim().isEmpty || clash
              ? null
              : () => Navigator.of(
                  context,
                ).pop((course: _course, year: _year.text.trim())),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

/// Restaurar contenido desde una versión congelada.
Future<void> showRestore(
  BuildContext context, {
  required Session session,
  required Course course,
  required String year,
  required Freeze freeze,
  RestoreScope scope = RestoreScope.course,
  String path = '',
  String label = '',
  String content = '',
}) => showDialog<void>(
  context: context,
  builder: (context) => RestoreDialog(
    session: session,
    course: course,
    year: year,
    freeze: freeze,
    scope: scope,
    path: path,
    label: label,
    content: content,
  ),
);

/// Qué se restaura.
enum RestoreScope {
  /// El curso entero: su composición y sus temas.
  course,

  /// Un tema: su fichero y su parte de la composición.
  document,

  /// Una lección: su carpeta entera.
  lesson,
}

class RestoreDialog extends StatefulWidget {
  const RestoreDialog({
    super.key,
    required this.session,
    required this.course,
    required this.year,
    required this.freeze,
    this.scope = RestoreScope.course,
    this.path = '',
    this.label = '',
    this.content = '',
  });

  final Session session;
  final Course course;
  final String year;
  final Freeze freeze;
  final RestoreScope scope;

  /// La ruta de la lección, o el id del tema.
  final String path;
  final String label;

  /// El contenido compartido del tema, cuando está vinculado: su fichero
  /// vuelve también, y eso lo cambia en todos los cursos que lo dan.
  final String content;

  @override
  State<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<RestoreDialog> {
  List<TreeChange>? _preview;
  List<String> _pending = const [];
  Object? _problem;
  bool _working = false;

  List<String> get _paths => switch (widget.scope) {
    RestoreScope.course => ['courses/${widget.course.id}/${widget.year}'],
    RestoreScope.document => [widget.path],
    RestoreScope.lesson => [widget.path],
  };

  String? get _repo => widget.freeze.repo.isEmpty ? null : widget.freeze.repo;

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    final service = widget.session.frozenIn(_repo);
    if (service == null) {
      setState(() => _problem = 'Esto necesita el clon del repositorio.');
      return;
    }
    try {
      final pending = await widget.session.pendingIn(_repo);
      final found = await service.previewRestore(
        freeze: widget.freeze,
        paths: _paths,
      );
      if (!mounted) return;
      setState(() {
        _preview = found;
        _pending = pending;
      });
    } catch (thrown) {
      if (!mounted) return;
      setState(() => _problem = thrown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final what = switch (widget.scope) {
      RestoreScope.course =>
        'el curso ${widget.course.title(widget.session.language)} '
            '${widget.year}',
      RestoreScope.document => 'el tema «${widget.label}»',
      RestoreScope.lesson => 'la lección «${widget.label}»',
    };
    return AlertDialog(
      title: Text('Restaurar $what desde «${widget.freeze.name}»'),
      content: SizedBox(
        width: 620,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Note(
              'Restaurar trae el contenido de aquel commit al estado de ahora '
              'y lo deja como un cambio pendiente. No se reescribe la '
              'historia, no se borra ningún commit y no se pierde nada de lo '
              'que hay publicado: lo que sale es un commit más, encima.',
            ),
            if (_pending.isNotEmpty) ...[
              const SizedBox(height: Space.small),
              Note(
                _pending.length == 1
                    ? 'Hay 1 fichero sin guardar en el repositorio. Si está '
                          'entre los de abajo, se perderá lo que tenga sin '
                          'confirmar.'
                    : 'Hay ${_pending.length} ficheros sin guardar en el '
                          'repositorio. Si alguno está entre los de abajo, se '
                          'perderá lo que tenga sin confirmar.',
                tone: didactaEx,
              ),
            ],
            const SizedBox(height: Space.medium),
            Expanded(
              child: _problem != null
                  ? Center(
                      child: Text(
                        '$_problem',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: didactaTeacher,
                        ),
                      ),
                    )
                  : preview == null
                  ? const Center(child: CircularProgressIndicator())
                  : preview.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay ninguna diferencia: lo que hay ahora ya es lo '
                        'que había entonces.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: didactaMuted),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final change in preview)
                          _ChangeRow(change: change),
                      ],
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
          key: const Key('confirm-restore'),
          onPressed: preview == null || preview.isEmpty || _working
              ? null
              : _restore,
          child: Text(
            preview == null || preview.isEmpty
                ? 'Restaurar'
                : 'Restaurar ${preview.length} fichero(s)',
          ),
        ),
      ],
    );
  }

  Future<void> _restore() async {
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final service = widget.session.frozenIn(_repo);
    if (service == null) return;
    try {
      // Un tema no es una carpeta: hay que sustituir su bloque del
      // `year.yaml` y dejar los de los demás donde estaban, y eso no es
      // copiar ficheros. Lo hace el motor.
      if (widget.scope == RestoreScope.document) {
        await _restoreDocument();
        return;
      }
      final done = await service.restore(freeze: widget.freeze, paths: _paths);
      // El cambio queda escrito y sin confirmar, que es lo que se ha dicho
      // que iba a pasar. Confirmarlo es la decisión de siempre, con la barra
      // de sincronización de siempre.
      await widget.session.reloadCatalogue();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restaurados ${done.length} fichero(s) desde '
            '«${widget.freeze.name}». Están sin confirmar: revísalos y '
            'guárdalos como un cambio más.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (thrown) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _problem = thrown;
      });
    }
  }
}

extension on _RestoreDialogState {
  /// Un tema, por el motor y no copiando ficheros.
  Future<void> _restoreDocument() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final view = await widget.session.frozenIn(_repo)!.open(widget.freeze);
    if (!mounted) return;
    final ok = await runAdmin(
      context,
      widget.session,
      (admin) => admin.restoreDocument(
        course: widget.course.id,
        year: widget.year,
        document: widget.path,
        fromDirectory: view.directory,
        fromLabel: widget.freeze.name,
      ),
      done:
          '«${widget.label}» restaurado desde «${widget.freeze.name}». Está '
          'sin confirmar: revísalo y guárdalo como un cambio más.',
      repo: _repo,
    );
    if (!ok || !mounted) return;
    await widget.session.reloadCatalogue();
    navigator.pop();
    messenger.removeCurrentSnackBar();
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final TreeChange change;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color colour, String what) = switch (change.kind) {
      TreeChangeKind.added => (Icons.add, didactaProp, 'vuelve'),
      TreeChangeKind.removed => (Icons.remove, didactaTeacher, 'se quita'),
      TreeChangeKind.modified => (Icons.edit_outlined, didactaThm, 'cambia'),
      TreeChangeKind.renamed => (
        Icons.drive_file_move_outlined,
        didactaEx,
        'se mueve',
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              change.path,
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(what, style: TextStyle(fontSize: 11, color: colour)),
        ],
      ),
    );
  }
}
