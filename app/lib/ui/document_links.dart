/// Dónde está vinculado un tema, y cómo partir esa vinculación.
///
/// Un tema puede darse en varios sitios a la vez --el mismo tema en el grupo
/// A y en el grupo B, o en dos titulaciones-- y entonces no son copias: es
/// uno, y lo que se edita desde cualquiera se ve en los demás. Partirlo es
/// decir «estos tres siguen juntos y estos dos van por su lado».
///
/// Esto vivía dentro del menú de reutilizar de la pantalla del año, que es
/// donde se decide mover o duplicar. Pero la pregunta «¿dónde más se da
/// esto?» se hace también **con el tema abierto**, y desde ahí no había forma
/// de contestarla ni de partirlo. Así que las tres cosas que no son de
/// reutilizar --dónde está, cómo se llama cada sitio y partir-- salen aquí y
/// las usan los dos.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/composition_file.dart';
import '../state/session.dart';
import 'course_admin_ui.dart';
import 'reuse.dart';

/// Los sitios donde se da este tema. Vacío cuando no está vinculado: uno
/// solo no es una lista, es donde estás.
List<ContentPlacement> placementsOf(Session session, Document document) =>
    session.catalogue.sharedById(document.content)?.placements ?? const [];

/// Cómo se llama un sitio: con el nombre de la asignatura y no con su id,
/// que es lo que hace que la lista se pueda leer sin saberse el catálogo.
String placementLabel(Session session, ContentPlacement place) {
  final course = session.courseById(place.course);
  return '${course?.title(session.language) ?? place.course} · '
      '${place.year} · ${place.document}';
}

/// Dónde está escrita la composición de un tema, y con qué nombre buscarla.
///
/// El `year.yaml` de su curso, o el fichero compartido cuando el tema está
/// vinculado. **Es la diferencia que hace que editarlo desde cualquiera de
/// los cursos que lo dan lo cambie en todos**, y olvidarla es lo que dejaba
/// el editor de composición en blanco: el tema estaba en el `year.yaml`, sí,
/// pero con una línea `link:` y sin composición que enseñar.
({String path, String document}) compositionFileOf(
  Document document,
  String courseId,
  String year,
) => document.isLinked
    ? (
        path: 'shared/documents/${document.content}.yaml',
        document: CompositionFile.sharedDocument,
      )
    : (path: 'courses/$courseId/$year/year.yaml', document: document.id);

/// Los sitios donde se da un tema, como una lista que lleva a cada uno.
///
/// [here] es la ubicación desde la que se pregunta: sale en la lista --«se da
/// en cuatro sitios» quiere decir cuatro-- pero no lleva a ninguna parte,
/// porque ya se está en ella.
List<PlaceLink> placementLinks(
  Session session,
  List<ContentPlacement> places, {
  String? course,
  String? year,
  String? document,
}) => [
  for (final place in places)
    PlaceLink(
      label: placementLabel(session, place),
      course: place.course,
      year: place.year,
      document: place.document,
      here:
          place.course == course &&
          place.year == year &&
          place.document == document,
    ),
];

/// Parte la vinculación de un tema en varios grupos.
///
/// No hace nada con menos de dos sitios: partir uno no significa nada, y un
/// diálogo que se abre para decir eso es peor que un botón que no está.
Future<void> splitDocumentLinks(
  BuildContext context,
  Session session,
  Document document,
) async {
  final places = placementsOf(session, document);
  if (places.length < 2) return;
  final request = await askSplit(
    context,
    title: 'Dividir la vinculación de «${document.title(session.language)}»',
    places: [
      for (final place in places)
        SyncPlace(key: place.key, label: placementLabel(session, place)),
    ],
    offerDeep: true,
  );
  if (request == null || !context.mounted) return;
  final groups = request.groups;
  final ok = await runAdmin(
    context,
    session,
    (admin) => admin.splitContent(
      content: document.content,
      groups: groups,
      deep: request.deep,
      paths: [
        for (final place in places) 'courses/${place.course}/${place.year}',
      ],
      message:
          'Dividir la vinculación de «${document.title(session.language)}» '
          'en ${groups.length + 1} grupo(s)'
          '${request.deep ? ', con sus lecciones' : ''}',
    ),
    done: 'Vinculación dividida. Cada grupo sigue sincronizado por dentro.',
    repo: document.repo,
  );
  if (ok) await session.reloadCatalogue();
}
