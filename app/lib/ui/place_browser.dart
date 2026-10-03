/// Elegir un sitio de la biblioteca en columnas: categoría, tema y subtema.
///
/// Como las columnas del Finder, y por lo mismo: el material está en un árbol
/// de tres niveles y lo que se quiere al crear o mover una lección es **ver**
/// dónde va, no escribir una ruta. Las rutas escritas a mano eran como acababa
/// una lección en `calculo/limtes`, sola en la biblioteca.
///
/// Es la misma pieza para crear una lección, para moverla y para decidir a
/// dónde va lo que se arrastra; la biblioteca tiene las suyas, más grandes,
/// pero con las mismas reglas: lo declarado en `taxonomy.yaml` sale en su
/// orden y aunque esté vacío, y al pie de cada columna se puede crear lo que
/// falte.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/library_tree.dart';
import '../model/slug.dart';
import '../state/session.dart';
import 'problem.dart' show showProblemIn;
import 'theme.dart';
import '../l10n/tr.dart';

/// El árbol entero de la biblioteca, con lo declarado y vacío incluido.
///
/// Sobre **todas** las lecciones, no sobre las de un repositorio: la
/// clasificación es una sola aunque el material viva en dos, y un subtema que
/// solo tiene teoría es tan buen destino para un problema como cualquiera.
LibraryTree placeTree(Catalogue catalogue, String language) => LibraryTree.of(
  catalogue.units,
  titleOf: (key) => catalogue.taxonomyTitle(key, language),
  declared: catalogue.declaredChildren,
  showEmpty: (_) => true,
);

/// Un sitio: hasta tres niveles, `[categoría, tema, subtema]`.
typedef Place = List<String>;

String placeKey(Place place) => place.join('/');

/// El nombre que se lee de un sitio: «Cálculo › Límites › Concepto».
String placeLabel(LibraryTree tree, Place place) {
  final category = place.isEmpty ? null : tree.category(place[0]);
  final topic = place.length < 2 ? null : category?.topic(place[1]);
  final subtopic = place.length < 3 ? null : topic?.subtopic(place[2]);
  return [
    if (place.isNotEmpty) category?.label ?? humaniseSlug(place[0]),
    if (place.length > 1) topic?.label ?? humaniseSlug(place[1]),
    if (place.length > 2) subtopic?.label ?? humaniseSlug(place[2]),
  ].join(' › ');
}

/// El sitio de una lección, para leerlo: «Cálculo › Límites › Concepto».
///
/// Es lo que se enseña debajo de una lección donde antes salía su ruta. La
/// ruta decía lo mismo con guiones; el id, que es lo que se escribe ahora, no
/// dice nada a quien lo lee.
String unitPlace(Catalogue catalogue, Unit unit, String language) {
  final parts = unit.place.split('/').where((p) => p.isNotEmpty).toList();
  return [
    for (var depth = 1; depth <= parts.length; depth += 1)
      catalogue.taxonomyTitle(parts.sublist(0, depth).join('/'), language) ??
          humaniseSlug(parts[depth - 1]),
  ].join(' › ');
}

/// Pide el nombre de una categoría, un tema o un subtema nuevos dentro de
/// [parent] y los declara en todos los repositorios. Devuelve el sitio nuevo,
/// o null.
Future<Place?> createPlace(
  BuildContext context,
  Session session, {
  required Place parent,
}) async {
  final answer = await showDialog<({String id, Map<String, String> titles})>(
    context: context,
    builder: (context) => NewPlaceDialog(session: session, parent: parent),
  );
  if (answer == null || !context.mounted) return null;
  final place = [...parent, answer.id];
  final messenger = ScaffoldMessenger.of(context);
  try {
    final written = await session.declarePlace(
      key: placeKey(place),
      titles: answer.titles,
    );
    final name = answer.titles[session.language] ?? answer.titles.values.first;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          written == 1
              ? tr('«{0}» creado.', [name])
              : tr('«{0}» creado en {1} repositorios.', [name, written]),
        ),
      ),
    );
    return place;
  } catch (error) {
    showProblemIn(messenger, error);
    return null;
  }
}

/// Si se puede crear algo en la clasificación: hace falta un repositorio en
/// el que escribir.
bool canDeclarePlaces(Session session) =>
    session.workspace.repos.any((repo) => session.canWriteIn(repo.id));

/// El nombre de lo que se crea, en cada idioma de los repositorios.
class NewPlaceDialog extends StatefulWidget {
  const NewPlaceDialog({
    super.key,
    required this.session,
    required this.parent,
  });

  final Session session;
  final Place parent;

  @override
  State<NewPlaceDialog> createState() => _NewPlaceDialogState();
}

class _NewPlaceDialogState extends State<NewPlaceDialog> {
  late final List<String> _languages = () {
    final codes = <String>[widget.session.language];
    for (final code in widget.session.catalogue.languages) {
      if (!codes.contains(code)) codes.add(code);
    }
    return codes;
  }();

  late final Map<String, TextEditingController> _names = {
    for (final code in _languages) code: TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in _names.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Del primer nombre escrito, en el orden de arriba: el del idioma en que
  /// se trabaja, que es el que se escribe primero.
  String get _id {
    for (final code in _languages) {
      final slug = slugify(_names[code]!.text.trim());
      if (slug.isNotEmpty) return slug;
    }
    return '';
  }

  String get _what => switch (widget.parent.length) {
    0 => tr('Nueva categoría'),
    1 => tr('Nuevo tema'),
    _ => tr('Nuevo subtema'),
  };

  String? get _problem {
    if (_id.isEmpty) return tr('Falta el nombre.');
    final siblings = widget.session.catalogue.declaredChildren(
      placeKey(widget.parent),
    );
    final inUse = widget.session.catalogue.units.any(
      (unit) =>
          [
            unit.category,
            unit.topic,
            unit.subtopic,
          ].take(widget.parent.length + 1).join('/') ==
          placeKey([...widget.parent, _id]),
    );
    if (siblings.contains(_id) || inUse) {
      return tr('Ya hay uno que se llama así aquí.');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final tree = placeTree(widget.session.catalogue, widget.session.language);
    return AlertDialog(
      title: Text(_what),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.parent.isNotEmpty) ...[
              Text(
                tr('Dentro de {0}', [placeLabel(tree, widget.parent)]),
                style: TextStyle(fontSize: 12.5, color: context.palette.muted),
              ),
              const SizedBox(height: 12),
            ],
            for (final (index, code) in _languages.indexed) ...[
              TextField(
                key: Key('place-name-$code'),
                controller: _names[code],
                autofocus: index == 0,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('Nombre en {0}', [languageName(code)]),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              problem ?? tr('Identificador: {0}', [_id]),
              key: const Key('place-id'),
              style: TextStyle(
                fontSize: 12,
                fontFamily: problem == null ? 'monospace' : null,
                color: problem == null
                    ? context.palette.muted
                    : context.palette.teacher,
              ),
            ),
            const SizedBox(height: 8),
            Note(
              tr(
                'Se declara en taxonomy.yaml de todos los repositorios abiertos, '
                'para que la teoría y los problemas enseñen las mismas columnas. '
                'Los nombres se pueden cambiar después; el identificador, no: '
                'es también el nombre de la carpeta.',
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
          key: const Key('place-create'),
          onPressed: problem != null
              ? null
              : () => Navigator.of(context).pop((
                  id: _id,
                  titles: {
                    for (final entry in _names.entries)
                      if (entry.value.text.trim().isNotEmpty)
                        entry.key: entry.value.text.trim(),
                  },
                )),
          child: Text(tr('Crear')),
        ),
      ],
    );
  }
}

/// Tres columnas para elegir categoría, tema y subtema.
///
/// [place] es lo elegido --de cero a tres niveles-- y [onChanged] recibe el
/// sitio nuevo cada vez que se pulsa algo, también al crear.
class PlaceBrowser extends StatelessWidget {
  const PlaceBrowser({
    super.key,
    required this.session,
    required this.place,
    required this.onChanged,
    this.height = 260,
  });

  final Session session;
  final Place place;
  final ValueChanged<Place> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final language = session.language;
    final tree = placeTree(session.catalogue, language);
    final category = place.isEmpty ? null : tree.category(place[0]);
    final topic = place.length < 2 ? null : category?.topic(place[1]);
    final create = canDeclarePlaces(session);

    Future<void> add(Place parent) async {
      final created = await createPlace(context, session, parent: parent);
      if (created != null) onChanged(created);
    }

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.card,
          border: Border.all(color: context.palette.rule),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.control),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PlaceColumn(
                  key: const Key('place-categories'),
                  heading: tr('Categoría'),
                  rows: [
                    for (final node in tree.categories)
                      (node.category, node.label, node.count),
                  ],
                  selected: place.isEmpty ? null : place[0],
                  onTap: (id) => onChanged([id]),
                  addLabel: create ? tr('Nueva categoría…') : null,
                  onAdd: () => add(const []),
                ),
              ),
              VerticalDivider(width: 1, color: context.palette.rule),
              Expanded(
                child: _PlaceColumn(
                  key: const Key('place-topics'),
                  heading: tr('Tema'),
                  rows: [
                    for (final node in category?.topics ?? const <TopicNode>[])
                      (node.topic, node.label, node.count),
                  ],
                  selected: place.length < 2 ? null : place[1],
                  onTap: (id) => onChanged([place[0], id]),
                  addLabel: create && category != null
                      ? tr('Nuevo tema…')
                      : null,
                  onAdd: () => add([place[0]]),
                  empty: category == null ? tr('Elige una categoría') : null,
                ),
              ),
              VerticalDivider(width: 1, color: context.palette.rule),
              Expanded(
                child: _PlaceColumn(
                  key: const Key('place-subtopics'),
                  heading: tr('Subtema'),
                  rows: [
                    for (final node
                        in topic?.subtopics ?? const <SubtopicNode>[])
                      if (node.subtopic.isNotEmpty)
                        (node.subtopic, node.label, node.count),
                  ],
                  selected: place.length < 3 ? null : place[2],
                  onTap: (id) => onChanged([place[0], place[1], id]),
                  addLabel: create && topic != null
                      ? tr('Nuevo subtema…')
                      : null,
                  onAdd: () => add([place[0], place[1]]),
                  empty: topic == null ? tr('Elige un tema') : null,
                  last: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceColumn extends StatelessWidget {
  const _PlaceColumn({
    super.key,
    required this.heading,
    required this.rows,
    required this.selected,
    required this.onTap,
    required this.addLabel,
    required this.onAdd,
    this.empty,
    this.last = false,
  });

  final String heading;

  /// Id, nombre y cuántas lecciones.
  final List<(String, String, int)> rows;
  final String? selected;
  final ValueChanged<String> onTap;

  /// Null si no se puede crear aquí.
  final String? addLabel;
  final VoidCallback onAdd;

  /// Lo que se dice en lugar de la lista cuando aún no hay nada que enseñar.
  final String? empty;

  /// La última columna no lleva flecha: no hay nada más a la derecha.
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Text(
            heading.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: context.palette.muted,
            ),
          ),
        ),
        Expanded(
          child: empty != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      empty!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (id, label, count) in rows)
                      Hoverable(
                        key: Key('place-$id'),
                        onTap: () => onTap(id),
                        builder: (context, hovering) => Container(
                          color: selected == id
                              ? context.palette.selected
                              : (hovering ? context.palette.hover : null),
                          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.2,
                                    fontWeight: selected == id
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.palette.muted,
                                ),
                              ),
                              if (!last)
                                Icon(
                                  Icons.chevron_right,
                                  size: 15,
                                  color: selected == id
                                      ? context.palette.accentDark
                                      : context.palette.rule,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (addLabel != null)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.palette.rule)),
            ),
            child: TextButton.icon(
              key: Key('place-add-${heading.toLowerCase()}'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add, size: 15),
              label: Text(
                addLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: onAdd,
            ),
          ),
      ],
    );
  }
}

/// Pide un subtema --los tres niveles-- con un [PlaceBrowser]. Devuelve el
/// sitio, o null.
Future<Place?> pickPlace(
  BuildContext context,
  Session session, {
  required String title,
  required String action,
  Place initial = const [],
  Place? current,
}) => showDialog<Place>(
  context: context,
  builder: (context) => _PickPlaceDialog(
    session: session,
    title: title,
    action: action,
    initial: initial,
    current: current,
  ),
);

class _PickPlaceDialog extends StatefulWidget {
  const _PickPlaceDialog({
    required this.session,
    required this.title,
    required this.action,
    required this.initial,
    this.current,
  });

  final Session session;
  final String title;
  final String action;
  final Place initial;

  /// Donde ya está, si es una lección que se mueve: elegirlo no es moverla.
  final Place? current;

  @override
  State<_PickPlaceDialog> createState() => _PickPlaceDialogState();
}

class _PickPlaceDialogState extends State<_PickPlaceDialog> {
  late Place _place = widget.initial;

  @override
  Widget build(BuildContext context) {
    final same =
        widget.current != null && placeKey(widget.current!) == placeKey(_place);
    final ready = _place.length == 3 && !same;
    final tree = placeTree(widget.session.catalogue, widget.session.language);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 660,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaceBrowser(
              session: widget.session,
              place: _place,
              onChanged: (next) => setState(() => _place = next),
              height: 320,
            ),
            const SizedBox(height: 10),
            Text(
              same
                  ? tr('Es donde ya está.')
                  : _place.length < 3
                  ? tr('Elige un subtema: cada lección vive en uno.')
                  : placeLabel(tree, _place),
              key: const Key('place-chosen'),
              style: TextStyle(
                fontSize: 12.5,
                color: ready ? context.palette.ink : context.palette.muted,
                fontWeight: ready ? FontWeight.w600 : FontWeight.w400,
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
          key: const Key('place-pick'),
          onPressed: ready ? () => Navigator.of(context).pop(_place) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
