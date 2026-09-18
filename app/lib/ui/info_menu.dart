/// El icono de información: de qué depende esto y qué se ha guardado de ello.
///
/// Las dos preguntas que se hacen con una lección o un tema delante no son de
/// su contenido, y hasta ahora se contestaban en sitios distintos y lejos:
///
/// - **«¿Dónde más está esto?»** Vivía en el panel de metadatos de la
///   lección, que se puede tener cerrado, y no existía en un tema.
/// - **«¿Qué versiones tengo guardadas?»** Vivía en la pantalla de
///   Asignaturas, a dos pantallas de distancia, que es justo donde no estás
///   cuando te lo preguntas: te lo preguntas mirando lo que ibas a cambiar.
///
/// Así que van juntas, detrás de una ⓘ que está siempre en la cabecera. No
/// sustituye al panel --que enseña todo lo demás de una lección-- sino que
/// saca de él lo que hay que poder alcanzar con el panel cerrado.
///
/// **Las congelaciones son de un curso académico, no de un fichero.** Una
/// lección que se da en cuatro asignaturas tiene cuatro juegos de versiones
/// congeladas, y fingir que tiene uno sería mentir sobre lo que se está
/// abriendo. Por eso salen por sitio, con el nombre de la asignatura delante.
/// Y crear una sólo se ofrece cuando hay un sitio y no hay duda de cuál se
/// está congelando.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../state/session.dart';
import 'freezes.dart';
import 'theme.dart';

/// Un sitio donde está lo que se mira: una asignatura, un curso académico y
/// --cuando lo que se mira es una lección-- el tema que la llama.
class InfoPlace {
  const InfoPlace({required this.course, required this.year, this.document});

  final String course;
  final String year;
  final String? document;

  /// Dos sitios son el mismo a efectos de congelar cuando comparten curso y
  /// año: las versiones congeladas no bajan al tema.
  String get yearKey => '$course/$year';
}

class InfoMenu extends StatelessWidget {
  const InfoMenu({
    super.key,
    required this.session,
    required this.places,
    required this.placesLabel,
    this.placesEmpty,
    this.belongsTo = const [],
    this.belongsToLabel = '',
    this.onSplit,
    this.splitLabel,
    this.onUse,
    this.onRestore,
  });

  final Session session;

  /// Dónde está esto. Para una lección, las composiciones que la llaman; para
  /// un tema, el curso académico en el que vive.
  final List<InfoPlace> places;

  final String placesLabel;

  /// Qué decir cuando no está en ninguno. Una lección que no referencia nadie
  /// es material que llegó y no se está dando, y eso merece una frase.
  final String? placesEmpty;

  /// Los temas a los que pertenece un documento. Pueden estar declarados en
  /// otro repositorio, que es la razón de enseñarlos: el vínculo cruza el
  /// clon y desde el fichero no se ve.
  final List<String> belongsTo;
  final String belongsToLabel;

  /// Partir en dos lo que está enlazado en varios sitios. Nulo cuando no
  /// aplica --un solo sitio, sin permiso de escritura, o mirando una versión
  /// congelada-- y entonces la entrada no sale.
  final VoidCallback? onSplit;
  final String? splitLabel;

  /// Darla también en otro tema. Se piensa **mirando la lección** --«esto lo
  /// quiero también en Matemáticas»--, así que está donde se la mira.
  final VoidCallback? onUse;

  /// Traerse esto tal como estaba. Sólo con una versión congelada abierta:
  /// es lo único que se puede hacer desde una foto, y no ofrecerlo dejaría a
  /// alguien con la versión buena delante y sin forma de recuperarla.
  final VoidCallback? onRestore;

  /// Los curso-año distintos, en el orden en que aparecen.
  List<InfoPlace> get _years {
    final seen = <String>{};
    return [
      for (final place in places)
        if (seen.add(place.yearKey)) place,
    ];
  }

  String _courseName(String id) =>
      session.courseById(id)?.title(session.language) ?? id;

  @override
  Widget build(BuildContext context) {
    final years = _years;
    return MenuAnchor(
      // Ancho fijo. Un menú que se mide por su línea más larga da una
      // columna de trescientos y pico píxeles con un tema de nombre largo, y
      // la línea siguiente, más corta, se desborda contra ese ancho.
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(_menuWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(_menuWidth, 560)),
      ),
      builder: (context, controller, child) => IconButton(
        key: const Key('info-menu'),
        tooltip: 'Dónde está y qué hay guardado',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.info_outline, size: 18),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        _Label('$placesLabel (${places.length})'),
        if (places.isEmpty && placesEmpty != null)
          _Note(placesEmpty!, key: const Key('info-places-empty'))
        else
          for (final place in places)
            MenuItemButton(
              key: Key(
                'info-place-${place.course}-${place.year}'
                '-${place.document ?? ''}',
              ),
              leadingIcon: Icon(
                place.document == null
                    ? Icons.school_outlined
                    : Icons.description_outlined,
                size: 15,
              ),
              onPressed: () => context.go(
                place.document == null
                    ? Routes.year(place.course, place.year)
                    : Routes.document(
                        place.course,
                        place.year,
                        place.document!,
                      ),
              ),
              child: _Line(
                title: place.document ?? _courseName(place.course),
                detail: place.document == null
                    ? place.year
                    : '${_courseName(place.course)} · ${place.year}',
              ),
            ),

        if (belongsTo.isNotEmpty) ...[
          const Divider(height: 9),
          _Label(belongsToLabel),
          for (final theme in belongsTo)
            MenuItemButton(
              key: Key('info-theme-$theme'),
              leadingIcon: const Icon(Icons.folder_outlined, size: 15),
              onPressed: places.isEmpty
                  ? null
                  : () => context.go(
                      Routes.year(places.first.course, places.first.year),
                    ),
              child: _Line(title: theme),
            ),
        ],

        const Divider(height: 9),
        _Label('Versiones congeladas'),
        if (years.isEmpty)
          const _Note(
            key: Key('info-freezes-none'),
            'Las versiones congeladas son de una asignatura, y esto no está '
            'en ninguna todavía.',
          )
        else
          for (final place in years)
            MenuItemButton(
              key: Key('info-freezes-${place.course}-${place.year}'),
              leadingIcon: const Icon(Icons.history_toggle_off, size: 15),
              onPressed: () {
                final course = session.courseById(place.course);
                if (course == null) return;
                showFreezes(context, session, course, place.year);
              },
              child: _Line(
                title: years.length == 1
                    ? 'Ver versiones congeladas…'
                    : '${_courseName(place.course)} · ${place.year}',
                detail: _countOf(place),
              ),
            ),
        // Crear sólo con un sitio: con cuatro, «crear una congelación» no
        // dice de cuál, y preguntarlo en un menú es empezar un formulario.
        if (years.length == 1 && !session.isFrozen)
          MenuItemButton(
            key: const Key('info-freeze-create'),
            leadingIcon: const Icon(Icons.ac_unit, size: 15),
            onPressed: () {
              final place = years.single;
              final course = session.courseById(place.course);
              if (course == null) return;
              createFreeze(context, session, course, place.year);
            },
            child: const _Line(title: 'Crear versión congelada…'),
          ),

        if (onRestore != null)
          MenuItemButton(
            key: const Key('info-restore'),
            leadingIcon: const Icon(Icons.restore, size: 15),
            onPressed: onRestore,
            child: const _Line(
              title: 'Restaurar esta lección…',
              detail: 'Traerla como estaba, sin reescribir nada',
            ),
          ),

        if (onSplit != null || onUse != null) ...[
          const Divider(height: 9),
          _Label('Vinculación'),
          if (onUse != null)
            MenuItemButton(
              key: const Key('info-use'),
              leadingIcon: const Icon(Icons.add_link, size: 15),
              onPressed: onUse,
              child: const _Line(
                title: 'Darla en otro tema…',
                detail: 'La misma lección, también allí',
              ),
            ),
          if (onSplit != null)
            MenuItemButton(
              key: const Key('info-split'),
              leadingIcon: const Icon(Icons.call_split, size: 15),
              onPressed: onSplit,
              child: _Line(
                title: splitLabel ?? 'Gestionar vinculación…',
                detail: 'Separar unos sitios del resto',
              ),
            ),
        ],
      ],
    );
  }

  /// Cuántas versiones congeladas tiene ese curso académico, o nada cuando
  /// no tiene ninguna: un «(0)» ocupa el mismo sitio y no dice más que el
  /// diálogo que se va a abrir.
  String? _countOf(InfoPlace place) {
    final many = session.freezesOf(place.course, place.year).length;
    return many == 0 ? null : '$many guardada${many == 1 ? '' : 's'}';
  }
}

/// El rótulo de una sección del menú. No es pulsable a propósito: un
/// `MenuItemButton` apagado se lee como algo que hoy no se puede hacer.
/// El ancho del menú, y de lo que va dentro. Fijo porque lo que entra son
/// nombres de asignatura y de tema, que no tienen longitud máxima.
const double _menuWidth = 332;
const double _lineWidth = 236;

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
        color: didactaMuted,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: _menuWidth - 24,
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11.5, color: didactaMuted),
    ),
  );
}

/// Una línea del menú: lo que es, y debajo de dónde.
class _Line extends StatelessWidget {
  const _Line({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _lineWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5),
        ),
        if (detail != null)
          Text(
            detail!,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: didactaMuted),
          ),
      ],
    ),
  );
}
