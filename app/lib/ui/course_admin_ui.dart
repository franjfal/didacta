/// Los diálogos de crear, duplicar y borrar asignaturas y años.
///
/// En un fichero propio porque son cuatro operaciones que comparten la misma
/// forma —comprobar que se puede, preguntar, lanzar el motor, contar qué
/// pasó— y repartirlas entre la pantalla de asignaturas y la de un curso
/// dejaría dos mitades de lo mismo.
///
/// Lo que tienen en común, y es lo que importa:
///
/// **Borrar dice qué se lleva, contado.** «Esta asignatura tiene dos años y
/// setenta y siete documentos» es lo que permite decidir; «¿seguro?» no lo
/// es. El recuento lo da el motor en seco, sin borrar nada, y por eso es el
/// de verdad.
///
/// **Y dice qué *no* se lleva.** Las unidades no se tocan: lo que se pierde
/// es la selección y el orden. Sin esa frase, borrar una asignatura parece
/// borrar el material, y nadie lo pulsaría.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../model/slug.dart';

import '../data/course_admin.dart';
import '../model/catalogue.dart';
import '../state/session.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Lanza una operación y cuenta el resultado.
///
/// Devuelve true cuando algo cambió, para que quien llame recargue el
/// catálogo: el índice se genera aparte, así que después de crear un año la
/// pantalla no lo ve hasta que se vuelve a leer.
/// Pregunta en qué repositorio se crea algo.
///
/// Con uno solo no pregunta: no hay nada que elegir. Con varios **sí**, y no
/// elige por su cuenta: crear una asignatura en el repositorio equivocado es
/// de las cosas que cuesta media tarde deshacer, porque hay que mover
/// ficheros y rehacer dos historiales.
Future<String?> pickRepository(BuildContext context, Session session) async {
  final repos = session.workspace.repos;
  // Sin repositorios abiertos no hay nada que preguntar y tampoco nada que
  // impedir: quien llame ya se encontrará con que no hay dónde escribir.
  if (repos.isEmpty) return '';
  if (repos.length == 1) return repos.single.id;
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('¿En qué repositorio?')),
      children: [
        for (final repo in repos)
          SimpleDialogOption(
            key: Key('pick-repo-${repo.id}'),
            onPressed: () => Navigator.of(context).pop(repo.id),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: context.palette.repo(repo.colour),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Text(repo.id),
              ],
            ),
          ),
      ],
    ),
  );
}

Future<bool> runAdmin(
  BuildContext context,
  Session session,
  Future<void> Function(CourseAdmin admin) action, {
  required String done,
  String? repo,
}) => runAdminIn(
  context,
  session,
  [repo],
  (admin, _) => action(admin),
  done: done,
);

/// Lo mismo en cada repositorio de [repos], uno detrás de otro.
///
/// Una asignatura puede estar repartida --la teoría en uno, los problemas en
/// otro-- y duplicar un curso, quitarlo o congelarlo en solo uno de ellos
/// deja la otra mitad atrás sin decir nada. Esto lo hace en todos con una
/// sola espera y un solo aviso.
///
/// Se comprueba que se pueden tocar todos **antes** de tocar ninguno. Si uno
/// falla a medio camino, se dice en cuáles ya se hizo: cada repositorio es su
/// propio commit y entre dos no hay forma de deshacer a la vez.
Future<bool> runAdminIn(
  BuildContext context,
  Session session,
  List<String?> repos,
  Future<void> Function(CourseAdmin admin, String? repo) action, {
  required String done,

  /// Deshacer lo que se acaba de hacer, como acción del aviso de «hecho».
  VoidCallback? onUndo,
}) async {
  final admins = [
    for (final repo in repos) (repo: repo, admin: session.admin(repo: repo)),
  ];
  final messenger = ScaffoldMessenger.of(context);
  // Los dos, antes del primer `await`: después, el `context` de la pantalla
  // puede haber dejado de valer, y son lo que hace falta para decir cómo ha
  // ido y para tapar la pantalla mientras dura.
  final navigator = Navigator.of(context, rootNavigator: true);
  if (admins.isEmpty || admins.any((entry) => entry.admin == null)) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Esto necesita la copia del repositorio en tu ordenador y el motor. Los dos se '
            'eligen en Ajustes.',
          ),
        ),
        duration: Duration(seconds: 6),
      ),
    );
    return false;
  }

  String name(String? repo) => repo == null || repo.isEmpty
      ? tr('el repositorio')
      : session.workspace.byId(repo)?.label ?? repo;

  // Con la pantalla bloqueada mientras dura. No es un adorno: la operación
  // regenera el índice de dos mil unidades y tarda unos segundos, y una
  // interfaz que no responde y no dice nada se lee como que se ha colgado.
  // Además evita el segundo clic, que sobre un repositorio a medio escribir
  // no es inofensivo.
  //
  // Antes de comprobar si se puede, y no después, para no usar un `context`
  // al otro lado de un `await`. La comprobación es un fichero en el disco:
  // el parpadeo no se ve.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _Working(),
    ),
  );

  final finished = <String?>[];
  try {
    for (final entry in admins) {
      final status = await entry.admin!.status();
      if (!status.ready) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              admins.length == 1
                  ? status.problem ?? tr('No se puede.')
                  : 'En ${name(entry.repo)}: ${status.problem ?? tr('no se puede.')}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
        return false;
      }
    }
    for (final entry in admins) {
      await action(entry.admin!, entry.repo);
      finished.add(entry.repo);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(done),
        duration: Duration(seconds: onUndo == null ? 4 : 10),
        action: onUndo == null
            ? null
            : SnackBarAction(
                key: const Key('admin-undo'),
                label: tr('Deshacer'),
                onPressed: onUndo,
              ),
      ),
    );
    return true;
  } on AdminException catch (error) {
    final partial = finished.isEmpty
        ? ''
        : tr('\n\nEn {0} sí se hizo.', [finished.map(name).join(' y ')]);
    messenger.showSnackBar(
      SnackBar(
        content: Text('$error$partial'),
        backgroundColor: messenger.context.palette.teacher,
        duration: const Duration(seconds: 10),
      ),
    );
    // Lo que sí se hizo ya está en el disco: que se vea.
    return finished.isNotEmpty;
  } finally {
    // Por el navigator guardado y no por el `context` de la pantalla: la
    // pantalla puede haberse ido mientras esto duraba, y entonces su
    // contexto ya no sirve para cerrar nada.
    navigator.pop();
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: Key('admin-working'),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Guardando…'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          LinearProgressIndicator(minHeight: 3),
          SizedBox(height: 12),
          // Decir por qué tarda. «Cargando» sin más, cuatro segundos, se
          // lee como que algo va mal.
          Text(
            tr(
              'Se regenera el índice del catálogo, que es lo que hace que el '
              'cambio se vea. Tarda unos segundos.',
            ),
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ],
      ),
    ),
  );
}

/// Deshace una operación de administración que acaba de hacerse.
///
/// [heads] es el HEAD de cada repositorio justo antes de la operación: lo que
/// había en [paths] en ese commit vuelve, como un commit nuevo en cada uno.
/// Con el contexto del navegador raíz, que sigue valiendo aunque la pantalla
/// desde la que se quitó ya no exista --quitar un curso académico se va de
/// su página--.
Future<void> undoAdminIn(
  BuildContext context,
  Session session,
  Map<String?, String> heads, {
  required List<String> paths,
  required String message,
  required String done,
}) async {
  final ok = await runAdminIn(
    context,
    session,
    [...heads.keys],
    (admin, repo) =>
        admin.undo(sha: heads[repo]!, paths: paths, message: message),
    done: done,
  );
  if (ok) await session.reloadCatalogue();
}

/// Pregunta antes de borrar, con el recuento delante.
///
/// [freezes] son las versiones congeladas que se van con ello: viven en la
/// carpeta del curso, así que quitarlo se las lleva, y eso no lo cuenta el
/// motor porque no son documentos.
Future<bool> confirmRemoval(
  BuildContext context, {
  required String title,
  required Future<RemovalPreview> Function() preview,
  required String warning,
  int freezes = 0,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => _RemovalDialog(
          title: title,
          preview: preview,
          warning: warning,
          freezes: freezes,
        ),
      ) ??
      false;
}

/// «1 curso académico», «2 cursos académicos».
///
/// Con la concordancia hecha, y por eso está: «se van 1 curso académicos» se
/// lee como un descuido, y en el diálogo que pregunta si borrar setenta y
/// siete documentos, un descuido hace dudar del recuento. La frase entera va
/// en tercera persona del singular --«esto se lleva...»-- justo para no tener
/// que concordar el verbo con lo que venga detrás.
String _count(int number, String singular, String plural) =>
    '$number ${number == 1 ? singular : plural}';

class _RemovalDialog extends StatefulWidget {
  const _RemovalDialog({
    required this.title,
    required this.preview,
    required this.warning,
    this.freezes = 0,
  });

  final String title;
  final Future<RemovalPreview> Function() preview;
  final String warning;
  final int freezes;

  @override
  State<_RemovalDialog> createState() => _RemovalDialogState();
}

class _RemovalDialogState extends State<_RemovalDialog> {
  RemovalPreview? _preview;
  Object? _problem;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget
          .preview()
          .then((found) {
            if (mounted) setState(() => _preview = found);
          })
          .catchError((Object error) {
            if (mounted) setState(() => _problem = error);
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_problem != null)
              Text(
                '$_problem',
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.palette.teacher,
                ),
              )
            else if (preview == null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  tr('Contando qué se llevaría…'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.muted,
                  ),
                ),
              )
            else ...[
              // El recuento del motor, no uno propio: es el que sabe escanear
              // el repositorio, y dos recuentos que pueden discrepar son
              // peores que uno.
              Text(
                preview.years > 0
                    ? tr(
                        'Esto se lleva {0} y '
                        '{1}.',
                        [
                          _count(
                            preview.years,
                            tr(
                              'curso '
                              'académico',
                            ),
                            tr('cursos académicos'),
                          ),
                          _count(preview.documents, 'documento', 'documentos'),
                        ],
                      )
                    : tr(
                        'Esto se lleva '
                        '{0}.',
                        [_count(preview.documents, 'documento', 'documentos')],
                      ),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Y lo que **no** se va. Sin esta frase, borrar una asignatura
            // parece borrar el material.
            Note(widget.warning),
            // Y lo que sí se va aunque no sea material: las versiones
            // congeladas viven en la carpeta del curso.
            if (widget.freezes > 0) ...[
              const SizedBox(height: 8),
              Note(
                tr(
                  'También se lleva '
                  '{0}. '
                  'Siguen en el historial, pero dejan de tener '
                  'nombre y ya no se pueden abrir desde Didacta.',
                  [
                    _count(
                      widget.freezes,
                      tr('versión congelada'),
                      tr('versiones congeladas'),
                    ),
                  ],
                ),
                tone: context.palette.teacher,
              ),
            ],
            const SizedBox(height: 8),
            // Lo que es verdad: se deshace desde el aviso, y después desde
            // «Cambios recientes» mientras nadie lo haya vuelto a tocar.
            Text(
              tr(
                'Se puede deshacer justo después, desde el aviso, y más tarde '
                'desde «Cambios recientes». Lo que había no se pierde: sigue en '
                'la historia del repositorio.',
              ),
              key: const Key('removal-undo-note'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('confirm-removal'),
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.teacher,
          ),
          onPressed: preview == null
              ? null
              : () => Navigator.of(context).pop(true),
          child: Text(tr('Quitar')),
        ),
      ],
    );
  }
}

/// Pide el año nuevo y de cuál copiarlo.
class DuplicateYearDialog extends StatefulWidget {
  const DuplicateYearDialog({super.key, required this.course});

  final Course course;

  @override
  State<DuplicateYearDialog> createState() => _DuplicateYearDialogState();
}

class _DuplicateYearDialogState extends State<DuplicateYearDialog> {
  late final List<String> _years = widget.course.years.keys.toList()
    ..sort((a, b) => b.compareTo(a));

  /// De qué curso se copia, o vacío para empezar en blanco.
  ///
  /// En blanco por defecto cuando no hay ninguno --una asignatura recién
  /// creada-- y copiando del más reciente cuando lo hay, que es lo que se
  /// quiere el 95% de las veces. Pero **se puede elegir no copiar**: un año
  /// que se compone desde cero no quiere arrastrar lo del anterior para ir
  /// borrándolo.
  late String _from = _years.isEmpty ? '' : _years.first;

  /// Si se congela el curso de origen antes de copiarlo. Marcado: el curso
  /// que se acaba es justo el que alguien querrá volver a ver --«¿cómo lo
  /// di el año pasado?»-- y, con los documentos vinculados, lo que se cambie
  /// en el nuevo cambia también en él.
  bool _freeze = true;

  late final TextEditingController _year = TextEditingController(
    text: _years.isEmpty ? '' : _nextAfter(_years.first),
  );

  /// El año siguiente al más reciente, ya escrito.
  ///
  /// Es lo que se va a teclear el 95% de las veces, y `2025-2026` es
  /// suficientemente fácil de escribir mal como para que valga la pena.
  static String _nextAfter(String year) {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(year);
    if (match == null) return '';
    final start = int.parse(match.group(1)!) + 1;
    return '$start-${start + 1}';
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  /// Cuántos documentos vinculados tiene un curso: los que el nuevo va a
  /// compartir con él en lugar de copiar.
  int _linkedIn(String year) => (widget.course.years[year]?.documents ?? [])
      .where((document) => document.isLinked)
      .length;

  bool get _valid =>
      RegExp(r'^\d{4}-\d{4}$').hasMatch(_year.text.trim()) &&
      !widget.course.years.containsKey(_year.text.trim());

  /// Si los dos años no son consecutivos.
  ///
  /// Un aviso y no un bloqueo: `2024-2026` cumple el formato y es
  /// casi seguro un dedazo --pasó, y salieron dos cursos que nadie quería--
  /// pero quien lo escriba a propósito sabrá por qué, y no soy yo quien
  /// decide qué es un curso académico en su universidad.
  String? get _oddSpan {
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(_year.text.trim());
    if (match == null) return null;
    final from = int.parse(match.group(1)!);
    final to = int.parse(match.group(2)!);
    if (to == from + 1) return null;
    return tr(
      'Un curso académico suele ser {0}-{1}. '
      'Se puede crear así, pero comprueba que es lo que quieres.',
      [from, from + 1],
    );
  }

  @override
  Widget build(BuildContext context) {
    final exists = widget.course.years.containsKey(_year.text.trim());
    return AlertDialog(
      title: Text(tr('Nuevo curso académico')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Se puede empezar en blanco o copiando la selección y el orden '
                'de un curso que ya existe. Las unidades no se copian nunca: el '
                'curso nuevo referencia las mismas, que es la razón de que el '
                'material y las asignaturas estén separados.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('new-year'),
              controller: _year,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('El curso nuevo'),
                hintText: '2026-2027',
                errorText: exists
                    ? tr('Ya existe')
                    : (_year.text.trim().isEmpty || _valid
                          ? null
                          : tr('Se escribe 2026-2027')),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_oddSpan != null) ...[
              const SizedBox(height: 10),
              Note(_oddSpan!, tone: context.palette.teacher),
            ],
            const SizedBox(height: 12),
            Text(
              tr('Qué lleva dentro'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                ChoiceChip(
                  key: const Key('start-empty'),
                  label: Text(tr('Nada, empiezo de cero')),
                  selected: _from.isEmpty,
                  onSelected: (_) => setState(() => _from = ''),
                ),
                for (final year in _years)
                  ChoiceChip(
                    key: Key('copy-from-$year'),
                    label: Text(
                      tr(
                        'Lo de {0} · '
                        '{1} doc.',
                        [year, widget.course.years[year]!.documents.length],
                      ),
                    ),
                    selected: year == _from,
                    onSelected: (_) => setState(() => _from = year),
                  ),
              ],
            ),
            if (_from.isNotEmpty) ...[
              const SizedBox(height: 10),
              CheckboxListTile(
                key: const Key('freeze-source-year'),
                value: _freeze,
                onChanged: (value) => setState(() => _freeze = value ?? true),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  tr('Congelar {0} tal como quedó', [_from]),
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  tr(
                    'Para poder volver a verlo y compilarlo como se dio, pase '
                    'lo que pase después. No copia nada: apunta a lo último '
                    'guardado.',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
              if (_linkedIn(_from) case final linked when linked > 0) ...[
                const SizedBox(height: 6),
                Note(
                  key: const Key('linked-in-source-year'),
                  tr(
                    '{0} de '
                    '{1} {2}'
                    ', y el curso nuevo {3}: '
                    'lo que cambies ahí en {4} '
                    'cambia también en {5}. En el curso nuevo, «Crear copia '
                    'independiente» {6}.',
                    [
                      linked == 1
                          ? tr('Un documento')
                          : tr('{0} documentos', [linked]),
                      _from,
                      linked == 1
                          ? tr('está vinculado')
                          : tr('están vinculados'),
                      linked == 1 ? tr('lo comparte') : tr('los comparte'),
                      _year.text.trim().isEmpty
                          ? tr('el nuevo')
                          : _year.text.trim(),
                      _from,
                      linked == 1 ? tr('lo separa') : tr('los separa'),
                    ],
                  ),
                  tone: context.palette.teacher,
                ),
              ],
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
          key: const Key('confirm-duplicate'),
          onPressed: _valid
              ? () => Navigator.of(context).pop((
                  year: _year.text.trim(),
                  from: _from,
                  freeze: _from.isNotEmpty && _freeze,
                ))
              : null,
          child: Text(tr('Crear')),
        ),
      ],
    );
  }
}

/// Pide los datos de una asignatura nueva.
class NewCourseDialog extends StatefulWidget {
  const NewCourseDialog({
    super.key,
    required this.courses,
    required this.languages,
    required this.defaultLanguage,
  });

  final List<Course> courses;
  final List<String> languages;
  final String defaultLanguage;

  @override
  State<NewCourseDialog> createState() => _NewCourseDialogState();
}

class _NewCourseDialogState extends State<NewCourseDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _id = TextEditingController();
  String? _from;
  late String _language = widget.defaultLanguage;

  /// Si el id lo escribió la persona. Mientras no, se deduce del título:
  /// «Análisis Matemático III (grupo B)» da `analisis-matematico-iii-grupo-b`,
  /// que es lo que se habría escrito a mano.
  bool _idTyped = false;

  @override
  void dispose() {
    _title.dispose();
    _id.dispose();
    super.dispose();
  }

  bool get _valid {
    final id = _id.text.trim();
    return RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(id) &&
        !widget.courses.any((course) => course.id == id) &&
        _title.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final id = _id.text.trim();
    final taken = widget.courses.any((course) => course.id == id);
    return AlertDialog(
      title: Text(tr('Nueva asignatura')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('new-course-title'),
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Título')),
              onChanged: (value) => setState(() {
                if (!_idTyped) _id.text = slugify(value);
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('new-course-id'),
              controller: _id,
              decoration: InputDecoration(
                labelText: tr('Identificador'),
                helperText: tr(
                  'El nombre de la carpeta y lo que se referencia',
                ),
                errorText: taken
                    ? tr('Ya existe')
                    : (id.isEmpty || _valid
                          ? null
                          : tr('Minúsculas, dígitos y guiones')),
              ),
              onChanged: (_) => setState(() => _idTyped = true),
            ),
            const SizedBox(height: 14),
            Text(
              tr('Idioma en el que se da'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              children: [
                for (final code in widget.languages)
                  ChoiceChip(
                    label: Text(code),
                    selected: code == _language,
                    onSelected: (_) => setState(() => _language = code),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              tr('Copiar los datos de'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
            const SizedBox(height: 5),
            // El caso que de verdad ocurre: la misma asignatura en otro grupo
            // o en otro idioma, donde todo menos el título y el código es lo
            // mismo. Copiar se queda con los TODO de los campos, que son la
            // lista de trabajo.
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                ChoiceChip(
                  label: Text(tr('nada, en blanco')),
                  selected: _from == null,
                  onSelected: (_) => setState(() => _from = null),
                ),
                for (final course in widget.courses)
                  ChoiceChip(
                    label: Text(course.id),
                    selected: _from == course.id,
                    onSelected: (_) => setState(() => _from = course.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Note(
              tr(
                'Se crea sin cursos académicos. El siguiente paso es añadir '
                'uno, copiándolo del de otra asignatura o del de otro año.',
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
          key: const Key('confirm-new-course'),
          onPressed: _valid
              ? () => Navigator.of(context).pop((
                  id: _id.text.trim(),
                  title: _title.text.trim(),
                  from: _from,
                  language: _language,
                ))
              : null,
          child: Text(tr('Crear')),
        ),
      ],
    );
  }
}

/// Copiar documentos de un curso a otro.
///
/// Dos preguntas en una pantalla porque son una sola decisión: a qué curso, y
/// qué de este. Lo segundo con la lista delante y casillas, porque lo normal
/// no es llevarse el curso entero --eso ya lo hace duplicar un año-- sino el
/// tema que se vuelve a dar.
///
/// Lo que se copia es **la composición**. Las unidades siguen siendo las
/// mismas, y se dice en la pantalla: es la propiedad por la que este botón
/// existe, y la que hace que corregir una errata siga siendo corregirla en un
/// sitio.
class CopyYearDialog extends StatefulWidget {
  const CopyYearDialog({
    super.key,
    required this.course,
    required this.year,
    required this.entry,
    required this.language,
    this.courses = const [],
  });

  final Course course;
  final String year;
  final CourseYear entry;
  final String language;

  /// A qué asignaturas se puede copiar. Vacía es «solo esta», que es como se
  /// comportaba antes de que se pudiera elegir otra.
  final List<Course> courses;

  @override
  State<CopyYearDialog> createState() => _CopyYearDialogState();
}

/// Lo que la pantalla decide: a dónde, y qué.
class CopyRequest {
  const CopyRequest({
    required this.toYear,
    required this.documents,
    this.toCourse = '',
  });

  /// La asignatura de destino. Vacía es la misma desde la que se copia, que
  /// es el caso corriente.
  final String toCourse;

  final String toYear;

  /// Vacía significa «el curso entero».
  final List<String> documents;
}

class _CopyYearDialogState extends State<CopyYearDialog> {
  String? _target;
  late String _course = widget.course.id;
  late final Set<String> _chosen = {
    for (final document in widget.entry.documents) document.id,
  };

  /// Las asignaturas a las que se puede copiar, con la actual delante.
  ///
  /// La actual por defecto porque es lo que se hace casi siempre --volver a
  /// dar el mismo tema el curso que viene-- y obligar a elegirla cada vez
  /// convertiría lo corriente en un formulario.
  List<Course> get _subjects {
    final all = widget.courses.isEmpty ? [widget.course] : widget.courses;
    final here = all.where((c) => c.id == widget.course.id).toList();
    final rest =
        [
          for (final course in all)
            if (course.id != widget.course.id) course,
        ]..sort(
          (a, b) =>
              a.title(widget.language).compareTo(b.title(widget.language)),
        );
    return [...here, ...rest];
  }

  Course? get _destination =>
      _subjects.where((course) => course.id == _course).firstOrNull;

  /// Los cursos académicos a los que se puede copiar. Dentro de la misma
  /// asignatura, todos menos este; en otra, todos los que tenga.
  List<String> get _targets => [
    for (final year in _destination?.years.keys ?? const <String>[])
      if (!(_course == widget.course.id && year == widget.year)) year,
  ]..sort();

  Widget _subjectPicker() {
    final subjects = _subjects;
    if (subjects.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('A qué asignatura'),
          style: TextStyle(fontSize: 11.5, color: context.palette.muted),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          key: const Key('copy-to-course'),
          initialValue: _course,
          isDense: true,
          items: [
            for (final course in subjects)
              DropdownMenuItem(
                value: course.id,
                child: Text(
                  course.id == widget.course.id
                      ? tr('{0}  (esta)', [course.title(widget.language)])
                      : course.title(widget.language),
                ),
              ),
          ],
          onChanged: (value) => setState(() {
            _course = value ?? _course;
            _target = null;
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    return AlertDialog(
      title: Text(tr('Copiar de {0}', [widget.year])),
      content: SizedBox(
        width: 540,
        height: 460,
        child: targets.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _subjectPicker(),
                  const SizedBox(height: Space.medium),
                  Note(
                    tr(
                      'Esa asignatura no tiene ningún curso académico al que '
                      'copiar. Crea uno primero, o elige otra.',
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _subjectPicker(),
                  const SizedBox(height: Space.medium),
                  Text(
                    tr('A qué curso académico'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final year in targets)
                        ChoiceChip(
                          key: Key('copy-to-$year'),
                          label: Text(year),
                          selected: _target == year,
                          onSelected: (_) => setState(() => _target = year),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        tr('Qué se copia'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.palette.muted,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        key: const Key('copy-none'),
                        onPressed: () => setState(_chosen.clear),
                        child: Text(tr('Ninguno')),
                      ),
                      TextButton(
                        key: const Key('copy-all'),
                        onPressed: () => setState(() {
                          _chosen.addAll(
                            widget.entry.documents.map((d) => d.id),
                          );
                        }),
                        child: Text(tr('Todos')),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final document in widget.entry.documents)
                          CheckboxListTile(
                            key: Key('copy-doc-${document.id}'),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _chosen.contains(document.id),
                            onChanged: (on) => setState(() {
                              if (on ?? false) {
                                _chosen.add(document.id);
                              } else {
                                _chosen.remove(document.id);
                              }
                            }),
                            title: Text(document.title(widget.language)),
                            subtitle: Text(
                              [
                                document.kind,
                                tr('{0} unidades', [document.unitRefs.length]),
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Note(
                    _course == widget.course.id
                        ? tr(
                            'Se copia la composición: qué unidades lleva y en '
                            'qué orden. Las unidades no se duplican '
                            '--siguen siendo las mismas-- así que '
                            'corregirlas sigue siendo corregirlas una vez.',
                          )
                        : tr(
                            'Se copia la composición a otra asignatura. Las '
                            'unidades siguen siendo las mismas, así que '
                            'tienen que estar en el mismo repositorio que '
                            'el curso de destino: un documento y lo que '
                            'llama viven juntos.',
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
          key: const Key('copy-confirm'),
          onPressed: _target == null || _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  CopyRequest(
                    toCourse: _course,
                    toYear: _target!,
                    documents: [
                      for (final document in widget.entry.documents)
                        if (_chosen.contains(document.id)) document.id,
                    ],
                  ),
                ),
          child: Text(
            _chosen.length == 1
                ? tr('Copiar 1')
                : tr('Copiar {0}', [_chosen.length]),
          ),
        ),
      ],
    );
  }
}
