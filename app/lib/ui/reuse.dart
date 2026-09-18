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

/// Qué se hace con un tema al llevarlo a otro sitio.
enum ReuseMode {
  /// Otra ubicación del mismo contenido. Lo que se edite se ve desde las dos.
  link,

  /// La misma ubicación, en otro sitio. Al acabar hay las mismas que había.
  move,

  /// Contenido nuevo, con identidad propia. Desde ahí, dos vidas separadas.
  duplicate,
}

const Map<ReuseMode, String> reuseNames = {
  ReuseMode.link: 'Añadir vinculado',
  ReuseMode.move: 'Mover',
  ReuseMode.duplicate: 'Duplicar',
};

const Map<ReuseMode, String> reuseExplained = {
  ReuseMode.link:
      'El mismo tema en los dos sitios. Lo que se edite desde cualquiera de '
      'ellos se ve desde el otro, porque es un solo fichero y no dos que '
      'alguien mantiene iguales.',
  ReuseMode.move:
      'Deja de estar aquí y pasa a estar allí. No se copia nada y la '
      'identidad no cambia: lo que estuviera vinculado sigue vinculado.',
  ReuseMode.duplicate:
      'Una copia con identidad propia. A partir de ahí son dos temas y cada '
      'uno va por su lado.',
};

/// A dónde va algo: una asignatura y un curso académico.
class ReuseTarget {
  const ReuseTarget({
    required this.course,
    required this.year,
    required this.mode,
    this.asId = '',
  });

  final String course;
  final String year;
  final ReuseMode mode;

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
                const SectionLabel('Qué operación'),
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
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: didactaMuted,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.medium),
              ],
              const SectionLabel('A qué asignatura'),
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
                            ? '${course.title(session.language)}  (esta)'
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
              const SectionLabel('A qué curso académico'),
              const SizedBox(height: 4),
              if (years.isEmpty)
                const Note(
                  'Esa asignatura no tiene ningún otro curso académico. Crea '
                  'uno primero.',
                  tone: didactaEx,
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
                  labelText: 'Con qué nombre llega',
                  helperText: _clash
                      ? 'Ya hay un tema con ese nombre en el destino.'
                      : 'Es el nombre del fichero que compila.',
                  helperStyle: TextStyle(
                    color: _clash ? didactaTeacher : didactaMuted,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
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
          child: const Text('Cancelar'),
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
      // Duplicar es la copia de siempre: composición, nunca contenido. Lo que
      // cambia respecto a vincular es justo que el destino se lleva su propia
      // entrada y a partir de ahí va por su lado.
      ReuseMode.duplicate => admin.copyDocuments(
        fromCourse: course,
        fromYear: year,
        toCourse: target.course,
        toYear: target.year,
        documents: [document],
      ),
    },
    done: switch (target.mode) {
      ReuseMode.link =>
        '«$document» se da también en ${target.course} ${target.year}. Es el '
            'mismo tema: lo que se edite se ve desde los dos.',
      ReuseMode.move =>
        '«$document» está ahora en ${target.course} ${target.year}.',
      ReuseMode.duplicate =>
        '«$document» copiado a ${target.course} ${target.year}. Son dos temas '
            'independientes.',
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
Future<LessonTarget?> askLessonTarget(
  BuildContext context, {
  required Session session,
  required String title,
  String fromCourse = '',
}) => showDialog<LessonTarget>(
  context: context,
  builder: (context) =>
      _LessonTargetDialog(session: session, title: title, from: fromCourse),
);

class _LessonTargetDialog extends StatefulWidget {
  const _LessonTargetDialog({
    required this.session,
    required this.title,
    required this.from,
  });

  final Session session;
  final String title;
  final String from;

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
    _document = _documents.firstOrNull?.id;
  }

  /// El curso más reciente **que tenga temas**, o el más reciente.
  ///
  /// Preferir uno con temas y no el último a secas: el año que viene suele
  /// estar recién creado y vacío, y abrir el diálogo en un curso donde no se
  /// puede elegir nada obliga a cambiarlo antes de empezar.
  String? get _firstUseful {
    final course = widget.session.courseById(_course);
    for (final year in _years) {
      if ((course?.years[year]?.documents ?? const []).isNotEmpty) return year;
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
              const SectionLabel('A qué asignatura'),
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
                            ? '${course.title(session.language)}  (esta)'
                            : course.title(session.language),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _course = value ?? _course;
                  _year = _firstUseful;
                  _document = _documents.firstOrNull?.id;
                }),
              ),
              const SizedBox(height: Space.medium),
              const SectionLabel('A qué curso académico'),
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
                        _document = _documents.firstOrNull?.id;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: Space.medium),
              const SectionLabel('A qué tema'),
              const SizedBox(height: 4),
              if (documents.isEmpty)
                const Note(
                  'Ese curso no tiene todavía ningún tema donde ponerla.',
                  tone: didactaEx,
                )
              else
                DropdownButtonFormField<String>(
                  key: const Key('lesson-document'),
                  initialValue: _document,
                  isDense: true,
                  items: [
                    for (final document in documents)
                      DropdownMenuItem(
                        value: document.id,
                        child: Text(
                          document.isLinked
                              ? '${document.title(session.language)}  '
                                    '(vinculado)'
                              : document.title(session.language),
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
                title: const Text(
                  'Llevar una copia independiente',
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: const Text(
                  'Con identidad propia: a partir de ahí son dos lecciones. '
                  'Sin marcar es la misma, y corregirla sigue siendo '
                  'corregirla una vez.',
                  style: TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
              ),
              if (_documentIsLinked && !_duplicate) ...[
                const SizedBox(height: Space.small),
                const Note(
                  'Ese tema está vinculado, así que la lección entra en todos '
                  'los cursos que lo dan.',
                  tone: didactaEx,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
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
          child: Text(_duplicate ? 'Duplicar aquí' : 'Añadir vinculada'),
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
                ? 'Se utiliza en 1 ubicación:'
                : 'Se utiliza en ${places.length} ubicaciones:',
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
        child: const Text('Cerrar'),
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
            color: place.here ? didactaMuted : didactaThm,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              place.label,
              style: TextStyle(
                fontSize: 12.5,
                color: place.here ? didactaMuted : didactaAccentDark,
                decoration: place.here ? null : TextDecoration.underline,
                decorationColor: didactaRule,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (place.here)
            const Text(
              'aquí',
              style: TextStyle(fontSize: 11, color: didactaMuted),
            )
          else
            const Icon(Icons.arrow_forward, size: 13, color: didactaMuted),
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
              'Ahora mismo hay ${widget.places.length} ubicaciones '
              'sincronizadas. Reparte cada una en el grupo que le toque: '
              'dentro de cada grupo seguirán sincronizadas, y entre grupos '
              'dejarán de estarlo.',
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
                        label: Text('Grupo ${_letters[_groups]}'),
                        onPressed: () => setState(() => _groups += 1),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: Space.large),
            const SectionLabel('Al confirmar'),
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
                              ? 'Grupo ${_letters[number]}: vacío'
                              : 'Grupo ${_letters[number]}'
                                    '${number == 0 ? ' (conserva la identidad)' : ''}'
                                    ': ${preview[number].map((p) => p.label).join(' · ')}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: preview[number].isEmpty
                                ? didactaTeacher
                                : didactaMuted,
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
                        title: const Text(
                          'Duplicar también las lecciones del tema',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        subtitle: const Text(
                          'Cada rama se lleva su propia copia de cada '
                          'lección. Sin marcar, el tema se separa y el '
                          'material sigue siendo uno.',
                          style: TextStyle(fontSize: 11.5, color: didactaMuted),
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('split-confirm'),
          onPressed: _valid
              ? () => Navigator.of(
                  context,
                ).pop(SplitRequest(groups: _result, deep: _deep))
              : null,
          child: const Text('Dividir'),
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
        color: didactaThm.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link, size: 12, color: didactaThm),
          const SizedBox(width: 3),
          Text(
            '$places',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: didactaThm,
            ),
          ),
        ],
      ),
    );
    return Tooltip(
      message:
          '$what se utiliza en $places ubicaciones. Lo que se edite aquí '
          'se ve en todas.',
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
