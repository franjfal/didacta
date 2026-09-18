/// Traducir lo que dice git a lo que se lee antes de una clase.
///
/// git contesta `M content/analisis/cardinales/countable/es.tex`. Lo que hace
/// falta leer es «la lección *countable* cambió en castellano». Este es el
/// único sitio donde se hace esa traducción, así que es el único sitio donde
/// se puede romper.
///
/// Lo que se fija aquí:
///
/// * que la ruta clasifique, porque la estructura del repositorio ya la
///   declara: `content/.../es.tex` y `courses/<c>/<año>/year.yaml` significan
///   cosas distintas y siempre las mismas;
/// * que lo derivado no se cuente: `generated/` sale en todos los diffs y no
///   dice nada que no diga ya otra fila;
/// * que un fichero movido salga como movido, que es la diferencia entre
///   «reorganizaron la carpeta» y «perdimos treinta lecciones»;
/// * que los temas que entran y salen se vean, aunque **no salgan de ninguna
///   ruta**: quitar un tema es borrar unas líneas de `year.yaml`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/model/course_diff.dart';

TreeChange change(TreeChangeKind kind, String path, {String from = ''}) =>
    TreeChange(kind: kind, path: path, from: from);

const String yearBefore = '''
course: am-i
year: 2026-2027
language: es

documents:
  - id: tema-1
    kind: theory
    title:
      es: Tema 1
      # TODO: va
    structure:
      - unit: a/b/c

  - id: tema-2
    kind: theory
    link: d-111111111111
''';

const String yearAfter = '''
course: am-i
year: 2026-2027
language: es

documents:
  - id: tema-1
    kind: theory
    link: d-222222222222

  - id: tema-3
    kind: handout
    title:
      es: Tema 3
    structure:
      - unit: a/b/d
''';

void main() {
  group('clasificar por la ruta', () {
    test('una lección cambiada dice en qué idioma', () {
      final diff = readCourseDiff([
        change(
          TreeChangeKind.modified,
          'content/analisis/card/countable/es.tex',
        ),
      ]);
      final found = diff.of(ChangedThing.lesson).single;
      expect(found.title, 'countable');
      expect(found.language, 'es');
      expect(found.lesson, 'content/analisis/card/countable');
      expect(found.detail, contains('es'));
    });

    test('los metadatos de una lección son otra cosa que su texto', () {
      final diff = readCourseDiff([
        change(
          TreeChangeKind.modified,
          'content/analisis/card/countable/unit.yaml',
        ),
      ]);
      expect(diff.of(ChangedThing.lesson).single.detail, contains('metadatos'));
    });

    test('una figura se reconoce como una figura', () {
      final diff = readCourseDiff([
        change(TreeChangeKind.added, 'content/a/b/c/figures/cantor.pdf'),
      ]);
      final found = diff.of(ChangedThing.lesson).single;
      expect(found.detail, 'una figura');
      expect(found.lesson, 'content/a/b/c');
    });

    test('los problemas son lecciones como las demás', () {
      final diff = readCourseDiff([
        change(
          TreeChangeKind.modified,
          'problems/analisis/sup/ejercicio/es.tex',
        ),
      ]);
      expect(diff.of(ChangedThing.lesson), hasLength(1));
    });

    test('el `year.yaml` habla del curso, no de un tema', () {
      final diff = readCourseDiff([
        change(TreeChangeKind.modified, 'courses/am-i/2026-2027/year.yaml'),
      ]);
      final found = diff.of(ChangedThing.course).single;
      expect(found.course, 'am-i');
      expect(found.year, '2026-2027');
    });

    test('un master es el fichero de un tema', () {
      final diff = readCourseDiff([
        change(TreeChangeKind.modified, 'courses/am-i/2026-2027/tema-1.tex'),
      ]);
      final found = diff.of(ChangedThing.document).single;
      expect(found.document, 'tema-1');
    });

    test('un tema compartido se reconoce por dónde vive', () {
      final diff = readCourseDiff([
        change(TreeChangeKind.modified, 'shared/documents/d-abc123456789.yaml'),
      ]);
      final found = diff.of(ChangedThing.document).single;
      expect(found.document, 'd-abc123456789');
      expect(found.detail, contains('compartido'));
    });

    test('los bloques de temas y las congelaciones van aparte', () {
      final diff = readCourseDiff([
        change(TreeChangeKind.modified, 'courses/am-i/2026-2027/themes.yaml'),
        change(TreeChangeKind.modified, 'courses/am-i/2026-2027/freezes.yaml'),
      ]);
      expect(diff.of(ChangedThing.theme), hasLength(1));
      expect(diff.of(ChangedThing.freeze), hasLength(1));
    });

    test('lo derivado no se cuenta', () {
      final diff = readCourseDiff([
        change(TreeChangeKind.modified, 'generated/units.json'),
        change(TreeChangeKind.modified, 'generated/courses.json'),
      ]);
      expect(diff.changes, isEmpty);
    });

    test('un fichero movido sale como movido y dice de dónde', () {
      final diff = readCourseDiff([
        change(
          TreeChangeKind.renamed,
          'content/analisis/nuevo/countable/es.tex',
          from: 'content/analisis/viejo/countable/es.tex',
        ),
      ]);
      final found = diff.of(ChangedThing.lesson).single;
      expect(found.isMove, isTrue);
      expect(found.from, 'content/analisis/viejo/countable/es.tex');
    });

    test('lo que no encaja en nada sale igual, sin inventarse un sitio', () {
      final diff = readCourseDiff([
        change(TreeChangeKind.modified, 'didacta.yaml'),
      ]);
      expect(diff.of(ChangedThing.other).single.title, 'didacta.yaml');
    });
  });

  group('los temas que entran y salen', () {
    test('un tema nuevo se ve aunque no salga de ninguna ruta', () {
      final diff = readCourseDiff(
        const [],
        before: yearBefore,
        after: yearAfter,
      );
      final added = diff.documents
          .where((d) => d.kind == TreeChangeKind.added)
          .single;
      expect(added.id, 'tema-3');
    });

    test('y uno que se ha quitado, también', () {
      final diff = readCourseDiff(
        const [],
        before: yearBefore,
        after: yearAfter,
      );
      final gone = diff.documents
          .where((d) => d.kind == TreeChangeKind.removed)
          .single;
      expect(gone.id, 'tema-2');
      expect(gone.wasLinked, isTrue);
    });

    test('vincular un tema es un cambio, aunque su contenido no se toque', () {
      final diff = readCourseDiff(
        const [],
        before: yearBefore,
        after: yearAfter,
      );
      final changed = diff.documents
          .where((d) => d.kind == TreeChangeKind.modified)
          .single;
      expect(changed.id, 'tema-1');
      expect(changed.wasLinked, isFalse);
      expect(changed.isLinked, isTrue);
      expect(changed.linkChanged, isTrue);
    });

    test('sin los dos ficheros no se inventa nada', () {
      final diff = readCourseDiff(const []);
      expect(diff.documents, isEmpty);
      expect(diff.isEmpty, isTrue);
    });

    test('dos años iguales no producen ningún cambio', () {
      final diff = readCourseDiff(
        const [],
        before: yearBefore,
        after: yearBefore,
      );
      expect(diff.documents, isEmpty);
    });
  });

  group('el resumen', () {
    test('cuenta en palabras, no en rutas', () {
      final diff = readCourseDiff(
        [
          change(TreeChangeKind.modified, 'content/a/b/c/es.tex'),
          change(TreeChangeKind.modified, 'content/a/b/d/es.tex'),
        ],
        before: yearBefore,
        after: yearAfter,
      );
      expect(diff.summary, contains('1 tema nuevo'));
      expect(diff.summary, contains('1 tema quitado'));
      expect(diff.summary, contains('2 lecciones'));
    });

    test('sin diferencias lo dice', () {
      expect(readCourseDiff(const []).summary, 'Sin diferencias.');
    });
  });
}
