/// Reutilizar contenido: mover, vincular, duplicar y dividir.
///
/// Cuatro operaciones que la interfaz ofrece por separado porque son cuatro
/// cosas distintas, y confundirlas es cómo se pierde material:
///
///     Mover               cambia de sitio esta ubicación
///     Añadir vinculado    otra ubicación del mismo contenido
///     Duplicar            contenido nuevo, con identidad propia
///     Dividir             parte un grupo sincronizado en varios
///
/// Lo que las distingue está escrito en el propio diálogo, debajo de cada
/// opción, y no en una ayuda aparte: la diferencia entre «vincular» y
/// «duplicar» solo importa **en el momento de elegir**, y ahí es donde tiene
/// que estar.
///
/// El destino empieza en la asignatura actual. Es lo que se hace casi
/// siempre --volver a dar el mismo tema el curso que viene-- y obligar a
/// elegirla cada vez convertiría lo corriente en un formulario.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../router.dart';
import '../state/session.dart';
import 'course_admin_ui.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Qué se hace con un tema al llevarlo a otro sitio.
enum ReuseMode {
  /// Otra ubicación del mismo contenido. Lo que se edite se ve desde las dos.
  link,

  /// La misma ubicación, en otro sitio. Al acabar hay las mismas que había.
  move,

  /// Contenido nuevo, con identidad propia. Desde ahí, dos vidas separadas.
  duplicate,
}

Map<ReuseMode, String> get reuseNames => {
  ReuseMode.link: tr('Añadir vinculado'),
  ReuseMode.move: tr('Mover'),
  ReuseMode.duplicate: tr('Duplicar'),
};

Map<ReuseMode, String> get reuseExplained => {
  ReuseMode.link: tr(
    'El mismo tema en los dos sitios. Lo que se edite desde cualquiera de '
    'ellos se ve desde el otro, porque es un solo fichero y no dos que '
    'alguien mantiene iguales.',
  ),
  ReuseMode.move: tr(
    'Deja de estar aquí y pasa a estar allí. No se copia nada y la '
    'identidad no cambia: lo que estuviera vinculado sigue vinculado.',
  ),
  ReuseMode.duplicate: tr(
    'Una copia de la composición, con identidad propia: a partir de ahí '
    'son dos temas, y cambiar el orden o los apartados de uno no toca el '
    'otro. Las lecciones siguen siendo las mismas --corregir una se ve en '
    'los dos-- salvo que se dupliquen también.',
  ),
};

/// A dónde va algo: una asignatura y un curso académico.
class ReuseTarget {
  const ReuseTarget({
    required this.course,
    required this.year,
    required this.mode,
    this.asId = '',
    this.withUnits = false,
  });

  final String course;
  final String year;
  final ReuseMode mode;

  /// Al duplicar, si las lecciones se duplican también.
  final bool withUnits;

  /// Con qué nombre llega, cuando hay que cambiárselo.
  final String asId;
}

/// Pregunta a dónde y de qué manera.
Future<ReuseTarget?> askReuseTarget(
  BuildContext context, {
  required Session session,
  required String title,
  required String fromCourse,
  required String fromYear,
  required String documentId,
  ReuseMode mode = ReuseMode.link,
  Set<ReuseMode> modes = const {
    ReuseMode.link,
    ReuseMode.move,
    ReuseMode.duplicate,
  },
}) => showDialog<ReuseTarget>(
  context: context,
  builder: (context) => _TargetDialog(
    session: session,
    title: title,
    fromCourse: fromCourse,
    fromYear: fromYear,
    documentId: documentId,
    mode: mode,
    modes: modes,
  ),
);

class _TargetDialog extends StatefulWidget {
  const _TargetDialog({
    required this.session,
    required this.title,
    required this.fromCourse,
    required this.fromYear,
    required this.documentId,
    required this.mode,
    required this.modes,
  });

  final Session session;
  final String title;
  final String fromCourse;
  final String fromYear;
  final String documentId;
  final ReuseMode mode;
  final Set<ReuseMode> modes;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late String _course = widget.fromCourse;
  String? _year;
  late ReuseMode _mode = widget.mode;
  bool _withUnits = false;
  late final TextEditingController _as = TextEditingController(
    text: widget.documentId,
  );

  @override
  void initState() {
    super.initState();
    _year = _years.firstOrNull;
  }

  @override
  void dispose() {
    _as.dispose();
    super.dispose();
  }

  List<Course> get _courses => [...widget.session.catalogue.courses]
    ..sort(
      (a, b) => a.id == widget.fromCourse
          ? -1
          : b.id == widget.fromCourse
          ? 1
          : a
                .title(widget.session.language)
                .compareTo(b.title(widget.session.language)),
    );

  /// Los cursos académicos del destino, menos el de origen cuando es la misma
  /// asignatura: llevarse algo al sitio donde ya está no es nada.
  List<String> get _years {
    final course = widget.session.courseById(_course);
    if (course == null) return const [];
    return [
      for (final year in course.years.keys)
        if (!(_course == widget.fromCourse && year == widget.fromYear)) year,
    ]..sort((a, b) => b.compareTo(a));
  }

  /// Si el nombre ya está cogido en el destino.
  bool get _clash {
    final course = widget.session.courseById(_course);
    final entry = course?.years[_year];
    if (entry == null) return false;
    return entry.documents.any((document) => document.id == _as.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final years = _years;
    final session = widget.session;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.modes.length > 1) ...[
                SectionLabel(tr('Qué operación')),
                const SizedBox(height: 4),
                RadioGroup<ReuseMode>(
                  groupValue: _mode,
                  onChanged: (value) => setState(() => _mode = value ?? _mode),
                  child: Column(
                    children: [
                      for (final mode in ReuseMode.values)
                        if (widget.modes.contains(mode))
                          RadioListTile<ReuseMode>(
                            key: Key('reuse-mode-${mode.name}'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: mode,
                            title: Text(
                              reuseNames[mode]!,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              reuseExplained[mode]!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.palette.muted,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.medium),
              ],
              SectionLabel(tr('A qué asignatura')),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                key: const Key('reuse-course'),
                initialValue: _course,
                items: [
                  for (final course in _courses)
                    DropdownMenuItem(
                      value: course.id,
                      child: Text(
                        course.id == widget.fromCourse
                            ? tr('{0}  (esta)', [
                                course.title(session.language),
                              ])
                            : course.title(session.language),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _course = value ?? _course;
                  _year = _years.firstOrNull;
                }),
              ),
              const SizedBox(height: Space.medium),
              SectionLabel(tr('A qué curso académico')),
              const SizedBox(height: 4),
              if (years.isEmpty)
                Note(
                  tr(
                    'Esa asignatura no tiene ningún otro curso académico. Crea '
                    'uno primero.',
                  ),
                  tone: context.palette.ex,
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final year in years)
                      ChoiceChip(
                        key: Key('reuse-year-$year'),
                        label: Text(year),
                        selected: _year == year,
                        onSelected: (_) => setState(() => _year = year),
                      ),
                  ],
                ),
              const SizedBox(height: Space.medium),
              TextField(
                key: const Key('reuse-as'),
                controller: _as,
                decoration: InputDecoration(
                  labelText: tr('Con qué nombre llega'),
                  helperText: _clash
                      ? tr('Ya hay un tema con ese nombre en el destino.')
                      : tr('Es el nombre del fichero que compila.'),
                  helperStyle: TextStyle(
                    color: _clash
                        ? context.palette.teacher
                        : context.palette.muted,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_mode == ReuseMode.duplicate) ...[
                const SizedBox(height: Space.medium),
                CheckboxListTile(
                  key: const Key('reuse-with-units'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _withUnits,
                  onChanged: (on) => setState(() => _withUnits = on ?? false),
                  title: Text(
                    tr('Duplicar también las lecciones'),
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    tr(
                      'Cada lección del tema, copiada con su propia identidad: '
                      'lo que se corrija en una copia no se ve en la otra. Son '
                      'carpetas nuevas en el repositorio.',
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.muted,
                    ),
                  ),
                ),
              ],
              // La explicación de lo elegido, y solo cuando no hay nada que
              // elegir: con el selector delante ya está escrita debajo de cada
              // opción, y repetirla abajo la convierte en ruido.
              if (widget.modes.length == 1) ...[
                const SizedBox(height: Space.medium),
                Note(reuseExplained[_mode]!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('reuse-confirm'),
          onPressed: _year == null || _as.text.trim().isEmpty || _clash
              ? null
              : () => Navigator.of(context).pop(
                  ReuseTarget(
                    course: _course,
                    year: _year!,
                    mode: _mode,
                    asId: _as.text.trim(),
                    withUnits: _mode == ReuseMode.duplicate && _withUnits,
                  ),
                ),
          child: Text(reuseNames[_mode]!),
        ),
      ],
    );
  }
}

/// Lleva un tema a otro sitio, de la manera que se haya elegido.
Future<bool> reuseDocument(
  BuildContext context, {
  required Session session,
  required String course,
  required String year,
  required String document,
  required ReuseTarget target,
  String? repo,
}) async {
  final ok = await runAdmin(
    context,
    session,
    (admin) => switch (target.mode) {
      ReuseMode.link => admin.linkDocument(
        fromCourse: course,
        fromYear: year,
        document: document,
        toCourse: target.course,
        toYear: target.year,
        asId: target.asId,
      ),
      ReuseMode.move => admin.moveDocument(
        fromCourse: course,
        fromYear: year,
        document: document,
        toCourse: target.course,
        toYear: target.year,
        asId: target.asId,
      ),
      // Duplicar es la copia de siempre, pero de verdad independiente: un
      // tema vinculado deja de estarlo en la copia --antes se llevaba su
      // `link:` y seguía siendo el mismo-- y, si se pide, con sus propias
      // lecciones.
      ReuseMode.duplicate => admin.copyDocuments(
        fromCourse: course,
        fromYear: year,
        toCourse: target.course,
        toYear: target.year,
        documents: [document],
        asId: target.asId == document ? '' : target.asId,
        independent: true,
        withUnits: target.withUnits,
      ),
    },
    done: switch (target.mode) {
      ReuseMode.link => tr(
        '«{0}» se da también en {1} {2}. Es el '
        'mismo tema: lo que se edite se ve desde los dos.',
        [document, target.course, target.year],
      ),
      ReuseMode.move => tr('«{0}» está ahora en {1} {2}.', [
        document,
        target.course,
        target.year,
      ]),
      ReuseMode.duplicate =>
        target.withUnits
            ? tr(
                '«{0}» duplicado en {1} {2}, con '
                'sus propias lecciones.',
                [document, target.course, target.year],
              )
            : tr(
                '«{0}» duplicado en {1} {2}. Son '
                'dos temas; las lecciones siguen siendo las mismas.',
                [document, target.course, target.year],
              ),
    },
    repo: repo,
  );
  if (ok) await session.reloadCatalogue();
  return ok;
}

/// A qué tema va una lección: asignatura, curso y tema.
class LessonTarget {
  const LessonTarget({
    required this.course,
    required this.year,
    required this.document,
    required this.duplicate,
  });

  final String course;
  final String year;
  final String document;

  /// Si llega como copia con identidad propia en vez de como la misma.
  final bool duplicate;
}

/// Pregunta en qué tema se da una lección.
///
/// Tres niveles y en este orden --asignatura, curso, tema-- porque es el
/// orden en que se piensa: «esto lo quiero también en Matemáticas, en el que
/// viene, en el tema de series».
///
/// [usedBy] son los temas que ya la llevan: el diálogo no los propone de
/// salida, y si se elige uno lo dice.
Future<LessonTarget?> askLessonTarget(
  BuildContext context, {
  required Session session,
  required String title,
  String fromCourse = '',
  Iterable<UnitUsage> usedBy = const [],
}) => showDialog<LessonTarget>(
  context: context,
  builder: (context) => _LessonTargetDialog(
    session: session,
    title: title,
    from: fromCourse,
    already: {
      for (final use in usedBy) '${use.course}|${use.year}|${use.document}',
    },
  ),
);

class _LessonTargetDialog extends StatefulWidget {
  const _LessonTargetDialog({
    required this.session,
    required this.title,
    required this.from,
    this.already = const {},
  });

  final Session session;
  final String title;
  final String from;

  /// Dónde está ya, como `curso|año|tema`.
  final Set<String> already;

  @override
  State<_LessonTargetDialog> createState() => _LessonTargetDialogState();
}

class _LessonTargetDialogState extends State<_LessonTargetDialog> {
  late String _course =
      widget.from.isNotEmpty && widget.session.courseById(widget.from) != null
      ? widget.from
      : (widget.session.catalogue.courses.firstOrNull?.id ?? '');
  String? _year;
  String? _document;
  bool _duplicate = false;

  @override
  void initState() {
    super.initState();
    _year = _firstUseful;
    _document = _firstFree;
  }

  /// Si el tema [document] del curso elegido ya lleva la lección.
  bool _has(String document, {String? year}) =>
      widget.already.contains('$_course|${year ?? _year}|$document');

  /// El primer tema que todavía no la lleva, o el primero.
  ///
  /// Proponer uno donde ya está era proponer que saliera dos veces: al
  /// darla en el curso que viene, el primer tema era justo el suyo.
  String? get _firstFree =>
      (_documents.where((document) => !_has(document.id)).firstOrNull ??
              _documents.firstOrNull)
          ?.id;

  /// El curso más reciente **con algún tema que no la lleve**; si no hay,
  /// el más reciente con temas, o el más reciente.
  ///
  /// Preferir uno con temas y no el último a secas: el año que viene suele
  /// estar recién creado y vacío, y abrir el diálogo en un curso donde no se
  /// puede elegir nada obliga a cambiarlo antes de empezar.
  String? get _firstUseful {
    final course = widget.session.courseById(_course);
    List<Document> documentsOf(String year) =>
        course?.years[year]?.documents ?? const [];
    for (final year in _years) {
      if (documentsOf(year).any((d) => !_has(d.id, year: year))) return year;
    }
    for (final year in _years) {
      if (documentsOf(year).isNotEmpty) return year;
    }
    return _years.firstOrNull;
  }

  List<Course> get _courses {
    final all = [...widget.session.catalogue.courses];
    all.sort((a, b) {
      if (a.id == widget.from) return -1;
      if (b.id == widget.from) return 1;
      return a
          .title(widget.session.language)
          .compareTo(b.title(widget.session.language));
    });
    return all;
  }

  List<String> get _years {
    final course = widget.session.courseById(_course);
    if (course == null) return const [];
    return course.years.keys.toList()..sort((a, b) => b.compareTo(a));
  }

  List<Document> get _documents {
    final course = widget.session.courseById(_course);
    return course?.years[_year]?.documents ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final documents = _documents;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(tr('A qué asignatura')),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                key: const Key('lesson-course'),
                initialValue: _course,
                isDense: true,
                items: [
                  for (final course in _courses)
                    DropdownMenuItem(
                      value: course.id,
                      child: Text(
                        course.id == widget.from
                            ? tr('{0}  (esta)', [
                                course.title(session.language),
                              ])
                            : course.title(session.language),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _course = value ?? _course;
                  _year = _firstUseful;
                  _document = _firstFree;
                }),
              ),
              const SizedBox(height: Space.medium),
              SectionLabel(tr('A qué curso académico')),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final year in _years)
                    ChoiceChip(
                      key: Key('lesson-year-$year'),
                      label: Text(year),
                      selected: _year == year,
                      onSelected: (_) => setState(() {
                        _year = year;
                        _document = _firstFree;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: Space.medium),
              SectionLabel(tr('A qué tema')),
              const SizedBox(height: 4),
              if (documents.isEmpty)
                Note(
                  tr('Ese curso no tiene todavía ningún tema donde ponerla.'),
                  tone: context.palette.ex,
                )
              else
                DropdownButtonFormField<String>(
                  key: const Key('lesson-document'),
                  initialValue: _document,
                  isDense: true,
                  // Un título largo, con «(ya la lleva)» detrás, se corta
                  // en vez de salirse del diálogo.
                  isExpanded: true,
                  items: [
                    for (final document in documents)
                      DropdownMenuItem(
                        value: document.id,
                        child: Text(
                          _has(document.id)
                              ? tr('{0}  (ya la lleva)', [
                                  document.title(session.language),
                                ])
                              : document.isLinked
                              ? tr(
                                  '{0}  '
                                  '(vinculado)',
                                  [document.title(session.language)],
                                )
                              : document.title(session.language),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _document = value ?? _document),
                ),
              const SizedBox(height: Space.medium),
              CheckboxListTile(
                key: const Key('lesson-duplicate'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _duplicate,
                onChanged: (value) =>
                    setState(() => _duplicate = value ?? false),
                title: Text(
                  tr('Llevar una copia independiente'),
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  tr(
                    'Con identidad propia: a partir de ahí son dos lecciones. '
                    'Sin marcar es la misma, y corregirla sigue siendo '
                    'corregirla una vez.',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
              if (_document case final chosen?
                  when _has(chosen) && !_duplicate) ...[
                const SizedBox(height: Space.small),
                Note(
                  key: const Key('lesson-already-there'),
                  tr(
                    'Ese tema ya la lleva: añadida otra vez, saldría dos '
                    'veces.',
                  ),
                  tone: context.palette.teacher,
                ),
              ],
              if (_documentIsLinked && !_duplicate) ...[
                const SizedBox(height: Space.small),
                Note(
                  tr(
                    'Ese tema está vinculado, así que la lección entra en todos '
                    'los cursos que lo dan.',
                  ),
                  tone: context.palette.ex,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('lesson-confirm'),
          onPressed: _year == null || _document == null
              ? null
              : () => Navigator.of(context).pop(
                  LessonTarget(
                    course: _course,
                    year: _year!,
                    document: _document!,
                    duplicate: _duplicate,
                  ),
                ),
          child: Text(
            _duplicate ? tr('Duplicar aquí') : tr('Añadir vinculada'),
          ),
        ),
      ],
    );
  }

  bool get _documentIsLinked => _documents
      .where((document) => document.id == _document)
      .any((document) => document.isLinked);
}

/// Una ubicación de la lista: cómo se lee y a dónde lleva.
class PlaceLink {
  const PlaceLink({
    required this.label,
    required this.course,
    required this.year,
    required this.document,
    this.here = false,
  });

  /// «Análisis Matemático I · 2026-2027 · practica-1».
  final String label;

  final String course;
  final String year;
  final String document;

  /// Si es la ubicación desde la que se está preguntando. Se enseña igual
  /// --«se da en cuatro sitios» quiere decir cuatro-- pero no lleva a ninguna
  /// parte, porque ya se está en ella.
  final bool here;
}

/// Dónde más se usa un contenido.
///
/// La pregunta que un repositorio no contesta barato --«¿esto dónde más
/// está?»-- y sin la cual cambiar algo es apostar.
///
/// Y cada una **lleva a su sitio**. Saber que un tema se da también en el
/// doble grado y tener que buscarlo a mano por la lista de asignaturas
/// convierte la respuesta en otra tarea; el siguiente gesto después de leer
/// esta lista es casi siempre «llévame allí».
Future<void> showPlaces(
  BuildContext context, {
  required String title,
  required List<PlaceLink> places,
  String explanation = '',
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            places.length == 1
                ? tr('Se utiliza en 1 ubicación:')
                : tr('Se utiliza en {0} ubicaciones:', [places.length]),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: Space.small),
          for (final place in places) _PlaceRow(place: place),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: Space.medium),
            Note(explanation),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Cerrar')),
      ),
    ],
  ),
);

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place});

  final PlaceLink place;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(
            place.here ? Icons.my_location : Icons.link,
            size: 14,
            color: place.here ? context.palette.muted : context.palette.thm,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              place.label,
              style: TextStyle(
                fontSize: 12.5,
                color: place.here
                    ? context.palette.muted
                    : context.palette.accentDark,
                decoration: place.here ? null : TextDecoration.underline,
                decorationColor: context.palette.rule,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (place.here)
            Text(
              tr('aquí'),
              style: TextStyle(fontSize: 11, color: context.palette.muted),
            )
          else
            Icon(Icons.arrow_forward, size: 13, color: context.palette.muted),
        ],
      ),
    );

    if (place.here) return row;
    return InkWell(
      key: Key('place-${place.course}-${place.year}-${place.document}'),
      borderRadius: BorderRadius.circular(Radii.small),
      onTap: () {
        // El diálogo se cierra antes de navegar: dejarlo abierto encima de la
        // pantalla a la que se acaba de llegar obliga a cerrarlo para ver
        // dónde se ha aterrizado.
        Navigator.of(context).pop();
        goTo(
          context,
          Routes.document(place.course, place.year, place.document),
        );
      },
      child: row,
    );
  }
}

/// Una ubicación, tal como se elige y se nombra al dividir.
class SyncPlace {
  const SyncPlace({required this.key, required this.label});

  /// Cómo la nombra el motor: `asignatura@año/documento`, o con `#posición`
  /// para una lección.
  final String key;

  /// Cómo se lee: «Análisis I · 2025-26 · Series».
  final String label;
}

/// Parte un grupo de ubicaciones sincronizadas en varios.
///
/// Lo que devuelve son los grupos **nuevos**: el primero se queda con la
/// entidad de siempre, y cada uno de los demás recibe una copia con identidad
/// propia. Un grupo que se queda con una sola ubicación deja de ser un grupo,
/// y su contenido vuelve a estar escrito donde se da.
Future<SplitRequest?> askSplit(
  BuildContext context, {
  required String title,
  required List<SyncPlace> places,
  String explanation = '',
  bool offerDeep = false,
}) => showDialog<SplitRequest>(
  context: context,
  builder: (context) => _SplitDialog(
    title: title,
    places: places,
    explanation: explanation,
    offerDeep: offerDeep,
  ),
);

/// Lo que la pantalla decide al dividir.
class SplitRequest {
  const SplitRequest({required this.groups, this.deep = false});

  /// Los grupos que **se separan**. El primero no está: se queda con la
  /// entidad de siempre.
  final List<List<String>> groups;

  /// Si además se duplican las lecciones que el tema lleva dentro.
  final bool deep;
}

class _SplitDialog extends StatefulWidget {
  const _SplitDialog({
    required this.title,
    required this.places,
    required this.explanation,
    this.offerDeep = false,
  });

  final String title;
  final List<SyncPlace> places;
  final String explanation;

  /// Si se ofrece duplicar también lo que el tema lleva dentro. Solo para un
  /// tema: una lección no lleva nada.
  final bool offerDeep;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  /// A qué grupo va cada ubicación. 0 es «el de siempre».
  late final Map<String, int> _group = {
    for (final place in widget.places) place.key: 0,
  };

  int _groups = 2;

  /// Duplicar también las lecciones. Apagado por defecto y con intención:
  /// separar dos temas casi nunca quiere decir separar las cuarenta lecciones
  /// que llevan dentro, y generar cuarenta identidades que nadie pidió no se
  /// deshace con un botón.
  bool _deep = false;

  static const List<String> _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

  List<List<String>> get _result => [
    for (var number = 1; number < _groups; number += 1)
      [
        for (final place in widget.places)
          if (_group[place.key] == number) place.key,
      ],
  ];

  /// Qué grupos quedan al acabar, incluido el que conserva la identidad.
  List<List<SyncPlace>> get _preview => [
    for (var number = 0; number < _groups; number += 1)
      [
        for (final place in widget.places)
          if (_group[place.key] == number) place,
      ],
  ];

  bool get _valid {
    final groups = _preview;
    // Todos los grupos declarados tienen que llevar algo, y tiene que haber
    // al menos dos con contenido: partir en uno no parte nada.
    final withSomething = groups.where((group) => group.isNotEmpty).length;
    return withSomething >= 2 && groups.every((group) => group.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Ahora mismo hay {0} ubicaciones '
                'sincronizadas. Reparte cada una en el grupo que le toque: '
                'dentro de cada grupo seguirán sincronizadas, y entre grupos '
                'dejarán de estarlo.',
                [widget.places.length],
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: Space.medium),
            Expanded(
              child: ListView(
                children: [
                  for (final place in widget.places)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              place.label,
                              style: const TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          for (var number = 0; number < _groups; number += 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: ChoiceChip(
                                key: Key('split-${place.key}-$number'),
                                label: Text(_letters[number]),
                                selected: _group[place.key] == number,
                                onSelected: (_) =>
                                    setState(() => _group[place.key] = number),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_groups < _letters.length &&
                      _groups < widget.places.length)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('split-add-group'),
                        icon: const Icon(Icons.add, size: 15),
                        label: Text(tr('Grupo {0}', [_letters[_groups]])),
                        onPressed: () => setState(() => _groups += 1),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: Space.large),
            SectionLabel(tr('Al confirmar')),
            const SizedBox(height: 4),
            SizedBox(
              height: widget.offerDeep ? 160 : 92,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var number = 0; number < preview.length; number += 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          preview[number].isEmpty
                              ? tr('Grupo {0}: vacío', [_letters[number]])
                              : tr(
                                  'Grupo {0}'
                                  '{1}'
                                  ': {2}',
                                  [
                                    _letters[number],
                                    number == 0
                                        ? tr(' (conserva la identidad)')
                                        : '',
                                    preview[number]
                                        .map((p) => p.label)
                                        .join(' · '),
                                  ],
                                ),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: preview[number].isEmpty
                                ? context.palette.teacher
                                : context.palette.muted,
                          ),
                        ),
                      ),
                    if (widget.offerDeep) ...[
                      const SizedBox(height: Space.tight),
                      CheckboxListTile(
                        key: const Key('split-deep'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _deep,
                        onChanged: (value) =>
                            setState(() => _deep = value ?? false),
                        title: Text(
                          tr('Duplicar también las lecciones del tema'),
                          style: TextStyle(fontSize: 12.5),
                        ),
                        subtitle: Text(
                          tr(
                            'Cada rama se lleva su propia copia de cada '
                            'lección. Sin marcar, el tema se separa y el '
                            'material sigue siendo uno.',
                          ),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.palette.muted,
                          ),
                        ),
                      ),
                    ],
                    if (widget.explanation.isNotEmpty) ...[
                      const SizedBox(height: Space.small),
                      Note(widget.explanation),
                    ],
                  ],
                ),
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
          key: const Key('split-confirm'),
          onPressed: _valid
              ? () => Navigator.of(
                  context,
                ).pop(SplitRequest(groups: _result, deep: _deep))
              : null,
          child: Text(tr('Dividir')),
        ),
      ],
    );
  }
}

/// El indicador de que algo se usa en varios sitios.
///
/// Discreto: un icono y un número. Lo que hace falta es **que se vea que hay
/// algo que mirar**, no explicarlo en la fila -- la explicación está a un
/// clic, en el menú.
class LinkBadge extends StatelessWidget {
  const LinkBadge({
    super.key,
    required this.places,
    required this.what,
    this.onPressed,
  });

  /// Cuántas ubicaciones. Una no se enseña: no hay vínculo que señalar.
  final int places;

  /// Qué es, para el tooltip.
  final String what;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (places < 2) return const SizedBox.shrink();
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.palette.thm.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 12, color: context.palette.thm),
          const SizedBox(width: 3),
          Text(
            '$places',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.palette.thm,
            ),
          ),
        ],
      ),
    );
    return Tooltip(
      message: tr(
        '{0} se utiliza en {1} ubicaciones. Lo que se edite aquí '
        'se ve en todas.',
        [what, places],
      ),
      child: onPressed == null
          ? chip
          : InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(Radii.chip),
              child: chip,
            ),
    );
  }
}
