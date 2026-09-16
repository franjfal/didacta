/// Los temas: agrupar los documentos de un curso sin poder romper nada.
///
/// Lo que se prueba aquí es sobre todo **lo que pasa cuando falta la mitad**.
/// Un tema se declara en un repositorio y sus documentos pueden estar en
/// otro, así que hay gente que tendrá las etiquetas sin la declaración. Eso no
/// puede esconder material, ni vaciar una pantalla, ni pedir un repositorio
/// que no se tiene: tiene que quedar exactamente como estaba antes de que los
/// temas existieran, que es una lista de documentos.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';

Document doc(String id, {List<String> themes = const [], String repo = 'uno'}) =>
    Document(
      id: id,
      kind: 'theory',
      repo: repo,
      language: 'es',
      titles: {'es': id},
      profiles: const [],
      unitRefs: const [],
      themes: themes,
    );

CourseYear year({
  List<CourseTheme> themes = const [],
  required List<Document> documents,
}) => CourseYear(
  year: '2026-2027',
  language: 'es',
  themes: themes,
  documents: documents,
);

const tema1 = CourseTheme(
  id: 'tema-1',
  titles: {'es': 'Tema 1: el número real'},
  repo: 'teoria',
);
const tema2 = CourseTheme(id: 'tema-2', titles: {'es': 'Tema 2: sucesiones'});

void main() {
  group('agrupar', () {
    test('cada documento va al tema que nombra', () {
      final entry = year(
        themes: const [tema1, tema2],
        documents: [
          doc('practica-1', themes: ['tema-1']),
          doc('tema-1-teoria', themes: ['tema-1']),
          doc('practica-2', themes: ['tema-2']),
        ],
      );

      final groups = entry.byTheme;
      expect(groups.length, 2);
      expect(groups.first.theme?.id, 'tema-1');
      expect(
        groups.first.documents.map((d) => d.id),
        ['practica-1', 'tema-1-teoria'],
      );
      expect(groups.last.documents.map((d) => d.id), ['practica-2']);
    });

    test('el orden de las tarjetas es el de la declaración', () {
      // No el de los documentos: el orden en que se dan los temas lo decide
      // quien escribe `themes.yaml`, y es lo único que lo decide.
      final entry = year(
        themes: const [tema2, tema1],
        documents: [
          doc('a', themes: ['tema-1']),
          doc('b', themes: ['tema-2']),
        ],
      );
      expect(entry.byTheme.map((g) => g.theme?.id), ['tema-2', 'tema-1']);
    });

    test('un documento puede estar en varios temas, y sale en todos', () {
      final entry = year(
        themes: const [tema1, tema2],
        documents: [
          doc('apendice', themes: ['tema-1', 'tema-2']),
        ],
      );
      final groups = entry.byTheme;
      expect(groups.length, 2);
      for (final group in groups) {
        expect(group.documents.single.id, 'apendice');
      }
    });

    test('un tema sin documentos también sale, vacío', () {
      // Un tema vacío es, casi siempre, uno que se acaba de crear. Si no sale
      // no hay por dónde meterle el primero: se creaba y desaparecía.
      final entry = year(
        themes: const [tema1, tema2],
        documents: [
          doc('a', themes: ['tema-1']),
        ],
      );
      expect(entry.byTheme.map((g) => g.theme?.id), ['tema-1', 'tema-2']);
      expect(entry.byTheme.last.documents, isEmpty);
    });
  });

  group('lo que no está en ningún tema', () {
    test('sale suelto, al final', () {
      final entry = year(
        themes: const [tema1],
        documents: [
          doc('suelto'),
          doc('a', themes: ['tema-1']),
        ],
      );
      final groups = entry.byTheme;
      expect(groups.length, 2);
      expect(groups.last.isLoose, isTrue);
      expect(groups.last.documents.single.id, 'suelto');
    });

    test('un tema que nadie declara deja su documento suelto', () {
      // **La prueba que importa.** Es lo que ve quien tiene el repositorio de
      // problemas y no el de teoría: la práctica nombra un tema del que no
      // sabe nada. No desaparece, no da error: sale como salía antes.
      final entry = year(
        documents: [
          doc('practica-1', themes: ['tema-1']),
        ],
      );
      final groups = entry.byTheme;
      expect(groups.single.isLoose, isTrue);
      expect(groups.single.documents.single.id, 'practica-1');
    });

    test('estar en un tema conocido y en otro que no, agrupa por el conocido', () {
      final entry = year(
        themes: const [tema1],
        documents: [
          doc('a', themes: ['tema-1', 'tema-de-otro-repositorio']),
        ],
      );
      final groups = entry.byTheme;
      expect(groups.length, 1, reason: 'no puede salir además como suelto');
      expect(groups.single.theme?.id, 'tema-1');
    });

    test('sin temas declarados, todo sale como antes', () {
      final entry = year(documents: [doc('a'), doc('b'), doc('c')]);
      final groups = entry.byTheme;
      expect(groups.single.isLoose, isTrue);
      expect(groups.single.documents.length, 3);
    });
  });

  group('con dos repositorios', () {
    test('el tema de uno agrupa los documentos del otro', () {
      // El caso real: la teoría declara el Tema 1 y los problemas solo lo
      // nombran. Juntos, salen en la misma tarjeta.
      final problemas = year(
        documents: [doc('practica-1', themes: ['tema-1'], repo: 'problemas')],
      );
      final teoria = year(
        themes: const [tema1],
        documents: [doc('tema-1-teoria', themes: ['tema-1'], repo: 'teoria')],
      );

      final conflicts = <String>[];
      final merged = problemas.mergedWith(teoria, conflicts);

      expect(conflicts, isEmpty);
      final groups = merged.byTheme;
      expect(groups.single.theme?.id, 'tema-1');
      expect(
        groups.single.documents.map((d) => d.id),
        ['practica-1', 'tema-1-teoria'],
      );
    });

    test('que los dos declaren el mismo tema no es un conflicto', () {
      // Es un tema del curso, no de ninguno de los dos repositorios: que los
      // dos lo escriban es que los dos saben cómo se llama.
      final conflicts = <String>[];
      final merged = year(
        themes: const [tema1],
        documents: [doc('a', themes: ['tema-1'])],
      ).mergedWith(
        year(
          themes: const [
            CourseTheme(id: 'tema-1', titles: {'es': 'Otro título'}),
            tema2,
          ],
          documents: [doc('b', themes: ['tema-2'], repo: 'dos')],
        ),
        conflicts,
      );

      expect(conflicts, isEmpty);
      expect(merged.themes.map((t) => t.id), ['tema-1', 'tema-2']);
      expect(
        merged.themes.first.title('es'),
        'Tema 1: el número real',
        reason: 'el primero en abrirse se queda con el título',
      );
    });
  });

  group('desde el índice', () {
    test('un índice sin temas no rompe nada', () {
      // Un repositorio que todavía no se ha reindexado con la versión nueva.
      final entry = CourseYear.fromJson({
        'year': '2026-2027',
        'language': 'es',
        'documents': [
          {'id': 'a', 'kind': 'theory', 'title': {'es': 'A'}},
        ],
      }, repo: 'uno');
      expect(entry.themes, isEmpty);
      expect(entry.documents.single.themes, isEmpty);
      expect(entry.byTheme.single.isLoose, isTrue);
    });

    test('se leen los temas y las etiquetas', () {
      final entry = CourseYear.fromJson({
        'year': '2026-2027',
        'language': 'es',
        'themes': [
          {
            'id': 'tema-1',
            'title': {'es': 'Tema 1'},
          },
        ],
        'documents': [
          {
            'id': 'a',
            'kind': 'theory',
            'title': {'es': 'A'},
            'themes': ['tema-1'],
          },
        ],
      }, repo: 'uno');

      expect(entry.themes.single.id, 'tema-1');
      expect(entry.themes.single.repo, 'uno');
      expect(entry.byTheme.single.theme?.title('es'), 'Tema 1');
    });
  });
}
