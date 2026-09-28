/// Qué cambió entre dos versiones de un curso, en palabras de Didacta.
///
/// El diff lo calcula git. Lo que hace este fichero es **traducirlo**: git
/// contesta `M content/analisis/cardinales/countable/es.tex`, y lo que hace
/// falta leer es «la lección *Conjuntos numerables* cambió en castellano».
/// Las dos frases dicen lo mismo y solo una se puede repasar antes de una
/// clase.
///
/// Tres decisiones que dan forma a todo lo demás:
///
/// **La ruta es lo que clasifica.** La estructura del repositorio no es una
/// convención suelta: `content/<...>/<lección>/es.tex` y
/// `courses/<asignatura>/<año>/year.yaml` significan cosas distintas y
/// siempre las mismas. Deducirlo de la ruta es leer lo que el repositorio ya
/// declara, no adivinar.
///
/// **Lo derivado no se cuenta.** `generated/` se regenera con cada cambio, así
/// que aparece en todos los diffs y no dice nada que no diga ya otra fila.
/// Enseñarlo llenaría la pantalla de ruido justo donde hace falta leer.
///
/// **Un fichero movido sale como movido.** Es la diferencia entre
/// «reorganizaron la carpeta» y «perdimos treinta lecciones», y sin decirlo
/// las dos cosas se ven igual.
library;

import '../data/local_clone.dart';
import 'composition_file.dart';
import '../l10n/tr.dart';

/// De qué habla un cambio.
enum ChangedThing {
  /// Un tema: su composición, su título, a qué se compila.
  document,

  /// Una lección: su texto en un idioma, sus metadatos, sus figuras.
  lesson,

  /// La asignatura o el curso en sí: qué temas lleva, cómo se llama.
  course,

  /// Los bloques bajo los que se agrupan los temas.
  theme,

  /// Las propias versiones congeladas.
  freeze,

  /// Cualquier otra cosa del repositorio.
  other,
}

/// Un cambio, ya traducido.
class CourseChange {
  const CourseChange({
    required this.thing,
    required this.kind,
    required this.path,
    this.from = '',
    this.title = '',
    this.detail = '',
    this.course = '',
    this.year = '',
    this.document = '',
    this.lesson = '',
    this.language = '',
  });

  final ChangedThing thing;
  final TreeChangeKind kind;

  /// La ruta en el repositorio. Es lo que se le vuelve a dar a git para
  /// pedirle el diff de esta fila.
  final String path;

  /// De dónde venía, cuando se movió.
  final String from;

  /// Cómo se llama esto para quien lo lee.
  final String title;

  /// Qué parte de ello: «la composición», «los metadatos», «una figura».
  final String detail;

  final String course;
  final String year;
  final String document;

  /// La ruta de la lección, sin el fichero: `content/analisis/.../countable`.
  final String lesson;

  /// El idioma, cuando el cambio es de un `.tex` concreto.
  final String language;

  bool get isMove => kind == TreeChangeKind.renamed;
}

/// La lista entera, con lo que hace falta para pintarla.
class CourseDiff {
  const CourseDiff({
    required this.changes,
    this.documents = const [],
    this.hiddenLessons = 0,
  });

  final List<CourseChange> changes;

  /// Los cambios en lecciones que el curso no usa, y que por eso no están en
  /// [changes]. Se cuentan para decirlo: una comparación que calla lo que
  /// ha quitado parece más pequeña de lo que es.
  final int hiddenLessons;

  /// Solo las lecciones que cumplen [used]; las demás se cuentan en
  /// [hiddenLessons].
  ///
  /// El repositorio tiene dos mil y el curso usa cuarenta. Sin esto, comparar
  /// dos versiones de una asignatura enseñaba los cambios de todas, y lo que
  /// había cambiado en las cuarenta se perdía entre el resto.
  CourseDiff onlyLessons(bool Function(String lesson) used) {
    final kept = <CourseChange>[];
    var hidden = hiddenLessons;
    for (final change in changes) {
      if (change.thing == ChangedThing.lesson && !used(change.lesson)) {
        hidden += 1;
      } else {
        kept.add(change);
      }
    }
    return CourseDiff(
      changes: kept,
      documents: documents,
      hiddenLessons: hidden,
    );
  }

  /// Los temas añadidos y quitados, que no salen de ninguna ruta: quitar un
  /// tema de un curso es **borrar unas líneas de `year.yaml`**, y desde la
  /// ruta eso solo se ve como «el año cambió».
  final List<DocumentChange> documents;

  bool get isEmpty => changes.isEmpty && documents.isEmpty;

  int countOf(ChangedThing thing, TreeChangeKind kind) => changes
      .where((change) => change.thing == thing && change.kind == kind)
      .length;

  List<CourseChange> of(ChangedThing thing) => [
    for (final change in changes)
      if (change.thing == thing) change,
  ];

  /// Un resumen de una línea, que es lo que se lee primero.
  String get summary {
    final pieces = <String>[];
    void count(int number, String one, String many) {
      if (number > 0) pieces.add(number == 1 ? '1 $one' : '$number $many');
    }

    count(
      documents.where((d) => d.kind == TreeChangeKind.added).length,
      tr('tema nuevo'),
      tr('temas nuevos'),
    );
    count(
      documents.where((d) => d.kind == TreeChangeKind.removed).length,
      tr('tema quitado'),
      tr('temas quitados'),
    );
    count(
      documents.where((d) => d.kind == TreeChangeKind.modified).length,
      tr('tema cambiado'),
      tr('temas cambiados'),
    );
    count(
      changes.where((c) => c.thing == ChangedThing.lesson).length,
      tr('lección'),
      tr('lecciones'),
    );
    if (pieces.isEmpty) return tr('Sin diferencias.');
    return pieces.join(' · ');
  }
}

/// Un tema que entró, salió o cambió entre las dos versiones.
class DocumentChange {
  const DocumentChange({
    required this.id,
    required this.kind,
    this.title = '',
    this.wasLinked = false,
    this.isLinked = false,
    this.link = '',
    this.wasLink = '',
  });

  final String id;
  final TreeChangeKind kind;
  final String title;

  /// Si estaba vinculado antes y si lo está ahora.
  ///
  /// Se cuenta aparte porque es el cambio que no se ve en ningún fichero de
  /// contenido: dividir un grupo de sincronización no toca ni una línea de
  /// una lección, y sin embargo cambia qué es ese tema.
  final bool wasLinked;
  final bool isLinked;
  final String link;
  final String wasLink;

  bool get linkChanged => wasLink != link;
}

/// Traduce lo que dijo git.
///
/// [before] y [after] son el `year.yaml` del curso en cada versión, cuando se
/// tienen. Sin ellos la lista sale igual, solo que sin la parte que no está
/// en ninguna ruta: qué temas entraron y cuáles salieron.
/// Las referencias de lección de una composición --`unit:` y `problem:`,
/// activas o desactivadas-- y los contenidos vinculados que nombra.
///
/// Las desactivadas cuentan: son material del curso que este año no se da, y
/// quien compara dos versiones quiere saber si cambió igual.
({Set<String> references, Set<String> links}) referencesIn(
  String? text, {
  bool shared = false,
}) {
  final references = <String>{};
  final links = <String>{};
  if (text == null || text.trim().isEmpty) {
    return (references: references, links: links);
  }
  final file = shared ? CompositionFile.shared(text) : CompositionFile(text);
  final ids = <String>[];
  if (shared) {
    ids.add(CompositionFile.sharedDocument);
  } else {
    for (final draft in file.documentDrafts()) {
      ids.add(draft.id);
      if (draft.link.isNotEmpty) links.add(draft.link);
    }
  }
  for (final id in ids) {
    try {
      for (final entry in file.blockFor(id)?.entries ?? const []) {
        if (entry.isReference) references.add(entry.value);
      }
    } on CompositionException {
      // Escrita de una forma que este lector no reescribe: no se filtra por
      // ella, y lo peor que pasa es enseñar de más.
    }
  }
  return (references: references, links: links);
}

CourseDiff readCourseDiff(
  List<TreeChange> tree, {
  String? before,
  String? after,
}) {
  final changes = <CourseChange>[];
  for (final change in tree) {
    final read = _classify(change);
    if (read != null) changes.add(read);
  }
  changes.sort((a, b) {
    final byThing = a.thing.index.compareTo(b.thing.index);
    if (byThing != 0) return byThing;
    return a.path.compareTo(b.path);
  });
  return CourseDiff(
    changes: changes,
    documents: _documents(before: before, after: after),
  );
}

List<DocumentChange> _documents({String? before, String? after}) {
  if (before == null && after == null) return const [];
  final was = {
    for (final draft in CompositionFile(before ?? '').documentDrafts())
      draft.id: draft,
  };
  final now = {
    for (final draft in CompositionFile(after ?? '').documentDrafts())
      draft.id: draft,
  };

  final found = <DocumentChange>[];
  for (final entry in now.entries) {
    final old = was[entry.key];
    if (old == null) {
      found.add(
        DocumentChange(
          id: entry.key,
          kind: TreeChangeKind.added,
          title: entry.value.title('es'),
          isLinked: entry.value.isLinked,
          link: entry.value.link,
        ),
      );
      continue;
    }
    if (old.link != entry.value.link ||
        old.titles.toString() != entry.value.titles.toString() ||
        old.kind != entry.value.kind ||
        old.themes.join(',') != entry.value.themes.join(',')) {
      found.add(
        DocumentChange(
          id: entry.key,
          kind: TreeChangeKind.modified,
          title: entry.value.title('es'),
          wasLinked: old.isLinked,
          isLinked: entry.value.isLinked,
          link: entry.value.link,
          wasLink: old.link,
        ),
      );
    }
  }
  for (final entry in was.entries) {
    if (now.containsKey(entry.key)) continue;
    found.add(
      DocumentChange(
        id: entry.key,
        kind: TreeChangeKind.removed,
        title: entry.value.title('es'),
        wasLinked: entry.value.isLinked,
        wasLink: entry.value.link,
      ),
    );
  }
  found.sort((a, b) => a.id.compareTo(b.id));
  return found;
}

CourseChange? _classify(TreeChange change) {
  final path = change.path;

  // Lo derivado no se cuenta: se regenera con cada cambio, así que sale en
  // todos los diffs y no dice nada que no diga ya otra fila.
  if (path.startsWith('generated/')) return null;

  final parts = path.split('/');

  if (parts.first == 'courses' && parts.length >= 3) {
    final course = parts[1];
    // `courses/<asignatura>/course.yaml`
    if (parts.length == 3 && parts[2] == 'course.yaml') {
      return CourseChange(
        thing: ChangedThing.course,
        kind: change.kind,
        path: path,
        from: change.from,
        course: course,
        title: course,
        detail: tr('los datos de la asignatura'),
      );
    }
    if (parts.length >= 4) {
      final year = parts[2];
      final name = parts[3];
      if (name == 'year.yaml') {
        return CourseChange(
          thing: ChangedThing.course,
          kind: change.kind,
          path: path,
          from: change.from,
          course: course,
          year: year,
          title: '$course · $year',
          detail: tr('qué temas lleva el curso y en qué orden'),
        );
      }
      if (name == 'themes.yaml') {
        return CourseChange(
          thing: ChangedThing.theme,
          kind: change.kind,
          path: path,
          from: change.from,
          course: course,
          year: year,
          title: '$course · $year',
          detail: tr('los bloques bajo los que se agrupan los temas'),
        );
      }
      if (name == 'freezes.yaml') {
        return CourseChange(
          thing: ChangedThing.freeze,
          kind: change.kind,
          path: path,
          from: change.from,
          course: course,
          year: year,
          title: '$course · $year',
          detail: tr('las versiones congeladas'),
        );
      }
      if (name.endsWith('.tex')) {
        final document = name.substring(0, name.length - 4);
        return CourseChange(
          thing: ChangedThing.document,
          kind: change.kind,
          path: path,
          from: change.from,
          course: course,
          year: year,
          document: document,
          title: document,
          detail: tr('el fichero que compila'),
        );
      }
    }
  }

  // `shared/documents/<id>.yaml`: un tema compartido por varios cursos.
  if (parts.length == 3 &&
      parts[0] == 'shared' &&
      parts[1] == 'documents' &&
      parts[2].endsWith('.yaml')) {
    final id = parts[2].substring(0, parts[2].length - 5);
    return CourseChange(
      thing: ChangedThing.document,
      kind: change.kind,
      path: path,
      from: change.from,
      document: id,
      title: id,
      detail: tr('un tema compartido: su título, su orden y sus apartados'),
    );
  }

  if (parts.first == 'content' || parts.first == 'problems') {
    final name = parts.last;
    // Una figura vive en `<lección>/figures/<fichero>`.
    final isFigure = parts.length >= 3 && parts[parts.length - 2] == 'figures';
    final lesson = parts
        .sublist(0, parts.length - (isFigure ? 2 : 1))
        .join('/');
    if (name == 'unit.yaml') {
      return CourseChange(
        thing: ChangedThing.lesson,
        kind: change.kind,
        path: path,
        from: change.from,
        lesson: lesson,
        title: _lessonName(lesson),
        detail: tr('los metadatos de la lección'),
      );
    }
    if (!isFigure && name.endsWith('.tex')) {
      final language = name.substring(0, name.length - 4);
      return CourseChange(
        thing: ChangedThing.lesson,
        kind: change.kind,
        path: path,
        from: change.from,
        lesson: lesson,
        language: language,
        title: _lessonName(lesson),
        detail: tr('el texto en {0}', [language]),
      );
    }
    return CourseChange(
      thing: ChangedThing.lesson,
      kind: change.kind,
      path: path,
      from: change.from,
      lesson: lesson,
      title: _lessonName(lesson),
      detail: isFigure ? tr('una figura') : name,
    );
  }

  return CourseChange(
    thing: ChangedThing.other,
    kind: change.kind,
    path: path,
    from: change.from,
    title: path,
  );
}

/// El último tramo de la ruta de una lección, que es como se la llama.
String _lessonName(String lesson) {
  final parts = lesson.split('/');
  return parts.isEmpty ? lesson : parts.last;
}
