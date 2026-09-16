/// La regla que sostiene que Didacta funcione con varios repositorios.
///
/// **Un documento y las unidades que llama viven en el mismo repositorio.**
/// LaTeX las busca bajo la raíz del suyo, así que una lección tomada del
/// repositorio de al lado compila en la máquina que tiene los dos abiertos y
/// no compila en la de quien solo tiene uno. Eso no se descubre editando: se
/// descubre cuando otra persona va a dar la clase.
///
/// Lo que sí se comparte es la clasificación --asignaturas, cursos, temas--,
/// que se junta entre repositorios y no se compila.
///
/// El motor no puede verlo: `didacta check` mira un repositorio, y desde allí
/// la unidad del otro simplemente no existe, que es otro error distinto y con
/// otro arreglo. Quien tiene los dos delante es la aplicación.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';


Unit unit(String path, {required String repo}) => Unit(
  id: path.replaceAll('/', '.'),
  path: path,
  repo: repo,
  area: 'content',
  block: 'theory',
  kind: 'theory',
  titles: const {'es': 'Una lección'},
  category: 'a',
  topic: 'b',
  tags: const [],
  reference: 'es',
  statuses: const {},
  prerequisites: const [],
  objectives: const [],
  usedBy: const [],
  warnings: const [],
);

Catalogue withA({
  required String documentRepo,
  required List<String> references,
  required List<Unit> units,
}) => Catalogue(
  name: 'Prueba',
  languages: const ['es'],
  defaultLanguage: 'es',
  contentHash: 'abc',
  units: units,
  profiles: const [],
  errors: const [],
  courses: [
    Course(
      id: 'am-i',
      titles: const {'es': 'AM I'},
      language: 'es',
      years: {
        '2026-2027': CourseYear(
          year: '2026-2027',
          language: 'es',
          documents: [
            Document(
              id: 'tema-1',
              kind: 'theory',
              repo: documentRepo,
              language: 'es',
              titles: const {'es': 'Tema 1'},
              profiles: const [],
              unitRefs: references,
            ),
          ],
        ),
      },
    ),
  ],
);

void main() {
  group('la regla', () {
    test('un documento con sus unidades en su repositorio está bien', () {
      final catalogue = withA(
        documentRepo: 'x/teoria',
        references: const ['a/b/c'],
        units: [unit('content/a/b/c', repo: 'x/teoria')],
      );
      expect(catalogue.crossRepoUses, isEmpty);
    });

    test('llamar a una unidad de otro repositorio se detecta', () {
      // El caso que rompe la clase de otra persona.
      final catalogue = withA(
        documentRepo: 'x/problemas',
        references: const ['a/b/c'],
        units: [unit('content/a/b/c', repo: 'x/teoria')],
      );

      final found = catalogue.crossRepoUses.single;
      expect(found.document, 'tema-1');
      expect(found.documentRepo, 'x/problemas');
      expect(found.unitRepo, 'x/teoria');
      expect(found.reference, 'a/b/c');
    });

    test('una referencia rota no cuenta como cruce', () {
      // Son dos problemas distintos y se arreglan de forma distinta: una
      // apunta a algo que no existe en ninguna parte, y la otra a algo que
      // existe en el sitio equivocado.
      final catalogue = withA(
        documentRepo: 'x/teoria',
        references: const ['a/b/no-existe'],
        units: [unit('content/a/b/c', repo: 'x/teoria')],
      );
      expect(catalogue.crossRepoUses, isEmpty);
    });

    test('con un solo repositorio no hay cruces posibles', () {
      final catalogue = withA(
        documentRepo: '',
        references: const ['a/b/c'],
        units: [unit('content/a/b/c', repo: '')],
      );
      expect(catalogue.crossRepoUses, isEmpty);
    });
  });

  group('resolver una referencia', () {
    test('se resuelve dentro del repositorio que se pida', () {
      final catalogue = withA(
        documentRepo: 'x/problemas',
        references: const ['a/b/c'],
        units: [unit('content/a/b/c', repo: 'x/teoria')],
      );

      expect(
        catalogue.unitByReference('a/b/c', repo: 'x/problemas'),
        isNull,
        reason: 'ahí no está, y decir que sí es lo que esconde el problema',
      );
      expect(catalogue.unitByReference('a/b/c', repo: 'x/teoria'), isNotNull);
      // Sin pedir repositorio, se encuentra: es lo que permite decir dónde
      // está de verdad al informar del cruce.
      expect(catalogue.unitByReference('a/b/c'), isNotNull);
    });

    test('la misma ruta en dos repositorios son dos unidades', () {
      final catalogue = withA(
        documentRepo: 'x/teoria',
        references: const ['a/b/c'],
        units: [
          unit('content/a/b/c', repo: 'x/teoria'),
          unit('content/a/b/c', repo: 'x/problemas'),
        ],
      );
      expect(
        catalogue.unitByReference('a/b/c', repo: 'x/problemas')?.repo,
        'x/problemas',
      );
      expect(catalogue.crossRepoUses, isEmpty);
    });
  });
}
