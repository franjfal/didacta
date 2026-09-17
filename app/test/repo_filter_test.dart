/// Apagar un repositorio en la interfaz.
///
/// El problema que resuelve: con dos repositorios abiertos, Didacta parecía
/// dos aplicaciones pegadas. Cada pantalla enseñaba lo de uno y cambiar de
/// repositorio parecía navegar a otro sitio, cuando lo que hay son **dos
/// fuentes de una misma biblioteca**. Ahora se juntan siempre, y lo que se
/// elige es qué se está mirando.
///
/// La propiedad que se fija aquí, y que es la que hace el filtro entendible:
/// **apagar un repositorio enseña exactamente lo mismo que no tenerlo.** Por
/// eso sirve para comprobar qué ve un compañero que solo tiene uno.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';

import 'fixture.dart';

Document doc(
  String id, {
  List<String> themes = const [],
  required String repo,
}) => Document(
  id: id,
  kind: 'theory',
  repo: repo,
  language: 'es',
  titles: {'es': id},
  profiles: const [],
  unitRefs: const [],
  themes: themes,
);

/// Una asignatura repartida: la teoría declara el tema, los problemas lo
/// nombran. Es la forma exacta que tiene el material real.
Catalogue split() => Catalogue(
  name: 'Prueba',
  languages: const ['es'],
  defaultLanguage: 'es',
  contentHash: 'abc',
  units: const [],
  profiles: const [],
  errors: const [],
  courses: [
    Course(
      id: 'am-i',
      titles: const {'es': 'Análisis Matemático I'},
      language: 'es',
      years: {
        '2026-2027': CourseYear(
          year: '2026-2027',
          language: 'es',
          themes: const [
            CourseTheme(
              id: 'tema-1',
              titles: {'es': 'Tema 1'},
              repo: 'x/teoria',
            ),
          ],
          documents: [
            doc('practica-1', themes: ['tema-1'], repo: 'x/problemas'),
            doc('tema-1-teoria', themes: ['tema-1'], repo: 'x/teoria'),
          ],
        ),
      },
    ),
  ],
);

void main() {
  group('el catálogo filtrado', () {
    test('sin nada apagado es el mismo', () {
      final full = split();
      expect(identical(full.without(const {}), full), isTrue);
    });

    test('apagar quita los documentos de ese repositorio', () {
      final visible = split().without({'x/teoria'});
      final year = visible.courses.single.years['2026-2027']!;
      expect(year.documents.map((d) => d.id), ['practica-1']);
    });

    test('apagar el que declara el tema deja los documentos sueltos', () {
      // La propiedad que importa: apagar enseña lo mismo que no tener. Quien
      // solo tiene el repositorio de problemas ve la práctica suelta, y quien
      // apaga el de teoría tiene que ver exactamente eso.
      final visible = split().without({'x/teoria'});
      final year = visible.courses.single.years['2026-2027']!;
      expect(year.themes, isEmpty);
      expect(year.byTheme.single.isLoose, isTrue);
      expect(year.byTheme.single.documents.single.id, 'practica-1');
    });

    test('una asignatura que se queda sin nada desaparece', () {
      // No una asignatura vacía: una asignatura que no se está mirando.
      final visible = split().without({'x/teoria', 'x/problemas'});
      expect(visible.courses, isEmpty);
    });

    test('las unidades también se filtran', () {
      final full = Catalogue(
        name: 'Prueba',
        languages: const ['es'],
        defaultLanguage: 'es',
        contentHash: 'abc',
        courses: const [],
        profiles: const [],
        errors: const [],
        units: [
          Unit(
            path: 'content/a/b/c',
            id: 'a.b.c',
            repo: 'x/teoria',
            area: 'content',
            block: 'theory',
            kind: 'theory',
            titles: const {'es': 'C'},
            category: 'a',
            topic: 'b',
            tags: const [],
            reference: 'es',
            statuses: const {},
            prerequisites: const [],
            objectives: const [],
            usedBy: const [],
            warnings: const [],
          ),
        ],
      );
      expect(full.without({'x/teoria'}).units, isEmpty);
    });
  });

  group('en la sesión', () {
    test('lo que ven las pantallas es el catálogo filtrado', () async {
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: split(),
        preferencesOverride: MemoryPreferences(),
      );
      await session.primeForTest(split());

      expect(
        session.catalogue.courses.single.years['2026-2027']!.documents,
        hasLength(2),
      );

      await session.setRepoVisible('x/teoria', false);

      expect(session.isRepoVisible('x/teoria'), isFalse);
      expect(
        session.catalogue.courses.single.years['2026-2027']!.documents,
        hasLength(1),
      );
      // Y el entero sigue ahí, para quien tiene que hablar de repositorios.
      expect(
        session.fullCatalogue!.courses.single.years['2026-2027']!.documents,
        hasLength(2),
      );
    });

    test('volver a encenderlo lo devuelve, sin tocar el disco', () async {
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: split(),
        preferencesOverride: MemoryPreferences(),
      );
      await session.primeForTest(split());
      final before = session.reloads;

      await session.setRepoVisible('x/teoria', false);
      await session.setRepoVisible('x/teoria', true);

      expect(
        session.catalogue.courses.single.years['2026-2027']!.documents,
        hasLength(2),
      );
      expect(
        session.reloads,
        before,
        reason: 'filtrar es de la interfaz: no vuelve a leer el índice',
      );
    });

    test('se recuerda, para no tener que apagarlo cada mañana', () async {
      final preferences = MemoryPreferences();
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: split(),
        preferencesOverride: preferences,
      );
      await session.primeForTest(split());

      await session.setRepoVisible('x/teoria', false);
      expect(await preferences.syncedPrefs(), contains('x/teoria'));
    });
  });
}
