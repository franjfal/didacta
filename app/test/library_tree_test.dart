/// Tests for the tree the library is browsed through.
///
/// The arithmetic is the part worth testing: a count that is quietly wrong is
/// invisible in an interface, and these counts are what tell someone where
/// the material is and how much of it is translated.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/library_tree.dart';

Unit unit({
  required String path,
  String kind = 'theory',
  Map<String, dynamic>? languages,
  List<Map<String, String>> usedBy = const [],
}) {
  final parts = path.split('/');
  return Unit.fromJson({
    'id': parts.skip(1).join('.'),
    'path': path,
    'area': parts.first,
    'kind': kind,
    'category': parts[1],
    'topic': parts[2],
    'tags': const <String>[],
    'title': {'es': parts.last},
    'reference': 'es',
    'languages':
        languages ??
        const {
          'es': {'status': 'source', 'exists': true},
          'va': {'status': 'missing', 'exists': false},
        },
    'prerequisites': const <String>[],
    'objectives': const <String>[],
    'usedBy': usedBy,
    'warnings': const <String>[],
  });
}

/// Un árbol con las formas que tiene el repositorio real: una categoría con
/// teoría y problemas a la vez, categorías de tamaños muy distintos, y un
/// tema con una sola unidad al lado de uno con varias.
LibraryTree treeFixture() => LibraryTree.of([
  unit(path: 'content/analysis/normed/definition'),
  unit(path: 'content/analysis/normed/banach'),
  unit(path: 'content/analysis/normed/hilbert'),
  unit(path: 'content/analysis/metric/definition'),
  unit(path: 'content/algebra/matrices/rank'),
  unit(path: 'problems/analysis/normed/exercises', kind: 'problem'),
]);

void main() {
  group('la forma', () {
    test('agrupa por categoría y tema, sin partir por bloque', () {
      // El área NO es un nivel: `analysis` tiene teoría y problemas y es una
      // sola categoría. La primera versión la partía en dos con el mismo
      // nombre, y la interfaz decía «63 categorías» donde hay 51.
      final tree = treeFixture();
      expect(tree.unitCount, 6);
      expect(tree.categoryCount, 2);
      expect(tree.topicCount, 3);

      final analysis = tree.category('analysis')!;
      expect(analysis.count, 5);
      expect(analysis.blocks, {'theory', 'problems'});
      expect(analysis.problems, 1);
      expect(analysis.topics.map((t) => t.topic), ['normed', 'metric']);
      expect(analysis.topic('normed')!.count, 4);
    });

    test('un tema junta la teoría con sus ejercicios', () {
      // «¿Qué tengo de espacios normados?» quiere las dos cosas: se preparan
      // juntas, y separarlas obliga a mirar en dos sitios.
      final normed = treeFixture().topic('analysis', 'normed')!;
      expect(normed.blocks, {'theory', 'problems'});
      expect(normed.kinds, {'theory', 'problem'});
    });

    test('las categorías y los temas van de mayor a menor', () {
      // 51 categorías en orden alfabético entierran las que se están dando.
      final tree = treeFixture();
      expect(tree.categories.map((c) => c.category), ['analysis', 'algebra']);
      expect(tree.categories.map((c) => c.count), [5, 1]);
    });

    test('el orden es estable cuando hay empate', () {
      // Alfabético dentro de un tamaño, para que la lista no se reordene
      // entre recargas según qué unidad se leyó primero.
      final tree = LibraryTree.of([
        unit(path: 'content/zeta/a/one'),
        unit(path: 'content/alpha/a/one'),
        unit(path: 'content/mu/a/one'),
      ]);
      expect(tree.categories.map((c) => c.category), ['alpha', 'mu', 'zeta']);
    });

    test('las unidades de un tema van en orden de ruta', () {
      final topic = treeFixture().topic('analysis', 'normed')!;
      expect(topic.units.map((u) => u.path), [
        'content/analysis/normed/banach',
        'content/analysis/normed/definition',
        'content/analysis/normed/hilbert',
        'problems/analysis/normed/exercises',
      ]);
    });

    test('cuenta cuántas unidades hay de cada bloque', () {
      // Para que el filtro pueda decir qué daría pulsarlo.
      expect(treeFixture().byBlock, {'theory': 5, 'problems': 1});
    });

    test('construido sobre un bloque, solo tiene ese bloque', () {
      // Así es como el filtro funciona: el árbol se hace con las unidades ya
      // filtradas, en lugar de llevar el área como nivel.
      final problems = LibraryTree.of(
        treeFixture().byPath.values.where((u) => u.area == 'problems'),
      );
      expect(problems.unitCount, 1);
      expect(problems.categoryCount, 1);
      expect(problems.category('analysis')!.problems, 1);
    });

    test('lo que no existe es null, no una excepción', () {
      final tree = treeFixture();
      expect(tree.category('nada'), isNull);
      expect(tree.topic('analysis', 'nada'), isNull);
      expect(tree.topic('nada', 'normed'), isNull);
    });

    test('un catálogo vacío es un árbol vacío', () {
      final tree = LibraryTree.of(const []);
      expect(tree.categories, isEmpty);
      expect(tree.unitCount, 0);
      expect(tree.byBlock, isEmpty);
    });
  });

  group('el progreso de traducción', () {
    test('separa lo hecho, lo que falta y lo que está a medias', () {
      // Three states rather than a percentage: "nothing written" and
      // "written but out of date" need different work, and a single number
      // flattens them into the same bar.
      final tree = LibraryTree.of([
        unit(
          path: 'content/a/b/uno',
          languages: const {
            'es': {'status': 'source', 'exists': true},
            'va': {'status': 'translated', 'exists': true},
          },
        ),
        unit(
          path: 'content/a/b/dos',
          languages: const {
            'es': {'status': 'source', 'exists': true},
            'va': {'status': 'outdated', 'exists': true},
          },
        ),
        unit(
          path: 'content/a/b/tres',
          languages: const {
            'es': {'status': 'source', 'exists': true},
            'va': {'status': 'missing', 'exists': false},
          },
        ),
      ]);

      final va = tree.category('a')!.progressIn('va');
      expect(va.total, 3);
      expect(va.done, 1);
      expect(va.needsWork, 1);
      expect(va.missing, 1);
      expect(va.fractionDone, closeTo(1 / 3, 0.001));
      expect(va.isComplete, isFalse);
      expect(va.isUntouched, isFalse);

      final es = tree.category('a')!.progressIn('es');
      expect(es.done, 3);
      expect(es.isComplete, isTrue);
    });

    test('nada escrito es «sin empezar», que no es lo mismo que a medias', () {
      final tree = LibraryTree.of([unit(path: 'content/a/b/uno')]);
      final progress = tree.category('a')!.progressIn('va');
      expect(progress.isUntouched, isTrue);
      expect(progress.fractionDone, 0);
    });

    test('un grupo vacío no está ni completo ni sin empezar', () {
      const progress = TranslationProgress(
        total: 0,
        done: 0,
        needsWork: 0,
        missing: 0,
      );
      expect(progress.isComplete, isFalse);
      expect(progress.isUntouched, isFalse);
      expect(progress.fractionDone, 0);
    });
  });

  group('las unidades sin usar', () {
    test('se cuentan por categoría', () {
      // After a migration this is the number that matters most: material
      // that arrived and is not being taught.
      final tree = LibraryTree.of([
        unit(
          path: 'content/a/b/usada',
          usedBy: const [
            {'course': 'c', 'year': '2025-2026', 'document': 'tema-1'},
          ],
        ),
        unit(path: 'content/a/b/huerfana'),
        unit(path: 'content/a/b/otra'),
      ]);
      expect(tree.category('a')!.unused, 2);
    });
  });

  group('los nombres', () {
    test('un slug se lee como una frase', () {
      expect(humaniseSlug('normed-spaces'), 'Normed spaces');
      expect(humaniseSlug('cipher_cards'), 'Cipher cards');
    });

    test('devuelve los acentos que el slug perdió', () {
      // Sin esto la interfaz enseña `analisis-real-una-variable`, que es
      // exactamente lo que el usuario no debería ver.
      expect(
        humaniseSlug('analisis-real-una-variable'),
        'Análisis real una variable',
      );
      expect(humaniseSlug('trigonometria'), 'Trigonometría');
      expect(
        humaniseSlug('secciones-conicas-y-orbitas-planetarias'),
        'Secciones cónicas y órbitas planetarias',
      );
    });

    test('una palabra que no está en la tabla se deja como está', () {
      // Mejor sin acento que con uno inventado en el sitio equivocado.
      expect(humaniseSlug('functional'), 'Functional');
      expect(humaniseSlug('otherprofesors'), 'Otherprofesors');
    });

    test('vacío se queda vacío en lugar de reventar', () {
      expect(humaniseSlug(''), '');
    });
  });
}
