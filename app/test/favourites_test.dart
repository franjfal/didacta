/// Marcar asignaturas y cursos para tenerlos arriba.
///
/// Con veinte asignaturas y seis cursos cada una, lo que se abre a diario son
/// tres cosas. Marcarlas las sube y deja el resto donde estaba: no es otra
/// lista, es la misma con lo de siempre delante.
///
/// Lo que se fija aquí es el orden, que es todo lo que esto hace, y que las
/// dos marcas son **independientes**: marcar una asignatura no dice nada de
/// cuál de sus cursos se está dando, que es justo lo que hay que tener a mano.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/synced_prefs.dart';

import 'fixture.dart';

Course subject(String id, String title, List<String> years) => Course(
  id: id,
  titles: {'es': title},
  language: 'es',
  years: {
    for (final year in years)
      year: CourseYear(year: year, language: 'es', documents: const []),
  },
);

Catalogue withCourses(List<Course> courses) => Catalogue(
  name: 'Prueba',
  languages: const ['es'],
  defaultLanguage: 'es',
  contentHash: 'abc',
  units: const [],
  profiles: const [],
  errors: const [],
  courses: courses,
);

Future<FakeSession> session() async {
  final catalogue = withCourses([
    subject('zoo', 'Zoología', const ['2024-2025', '2026-2027']),
    subject('am-i', 'Análisis Matemático I', const [
      '2022-2023',
      '2026-2027',
      '2024-2025',
    ]),
    subject('alg', 'Álgebra', const ['2025-2026']),
  ]);
  final made = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
  );
  await made.primeForTest(catalogue);
  return made;
}

void main() {
  group('el orden de salida', () {
    test('las asignaturas van por título, de la A a la Z', () async {
      final it = await session();
      expect(
        it.sortedCourses.map((c) => c.id),
        ['alg', 'am-i', 'zoo'],
        reason: 'ordena por título --Álgebra, Análisis, Zoología-- y no por id',
      );
    });

    test('los cursos van del más reciente al más antiguo', () async {
      // Al revés que las asignaturas a propósito: el curso que se está dando
      // es el que se busca, y una lista ascendente lo entierra al final.
      final it = await session();
      final course = it.catalogue.courses.firstWhere((c) => c.id == 'am-i');
      expect(it.sortedYearsOf(course), ['2026-2027', '2024-2025', '2022-2023']);
    });
  });

  group('lo marcado no cambia el orden', () {
    // Lo cambiaba --las marcadas subían al principio-- y era peor: la lista
    // dejaba de estar donde se aprendió que estaba, y marcar una asignatura
    // movía otras cuatro de sitio. La estrella dice «esta me importa»; para
    // no ver lo que no se da está ocultarla.

    test('una asignatura marcada se queda donde estaba', () async {
      final it = await session();
      await it.setFavouriteCourse('zoo', true);
      expect(it.sortedCourses.map((c) => c.id), ['alg', 'am-i', 'zoo']);
      expect(it.isFavouriteCourse('zoo'), isTrue);
    });

    test('y el orden es siempre por título', () async {
      final it = await session();
      await it.setFavouriteCourse('zoo', true);
      await it.setFavouriteCourse('alg', true);
      expect(it.sortedCourses.map((c) => c.id), ['alg', 'am-i', 'zoo']);
    });

    test('un curso marcado tampoco se mueve', () async {
      // Y así «el primero» vuelve a querer decir «el último que se dio»,
      // que es de lo que se fía la pantalla para marcar el curso actual.
      final it = await session();
      await it.setFavouriteYear('am-i', '2022-2023', true);
      final course = it.catalogue.courses.firstWhere((c) => c.id == 'am-i');
      expect(it.sortedYearsOf(course), ['2026-2027', '2024-2025', '2022-2023']);
    });
  });

  group('ocultar y plegar', () {
    test('ocultar una asignatura no la quita de ningún sitio', () async {
      // Ocultar no es quitar: sigue en el catálogo, sigue compilando y sigue
      // en la biblioteca. Lo que cambia es una lista.
      final it = await session();
      await it.setCourseHidden('zoo', true);
      expect(it.isHiddenCourse('zoo'), isTrue);
      expect(it.sortedCourses.map((c) => c.id), ['alg', 'am-i', 'zoo']);
      expect(it.catalogue.courses, hasLength(3));
    });

    test('un curso académico se oculta por su cuenta', () async {
      // Aparte de la asignatura: la asignatura se sigue dando y lo que sobra
      // en la lista son los seis años anteriores.
      final it = await session();
      await it.setYearHidden('am-i', '2022-2023', true);
      expect(it.isHiddenYear('am-i', '2022-2023'), isTrue);
      expect(it.isHiddenYear('am-i', '2024-2025'), isFalse);
      expect(it.isHiddenCourse('am-i'), isFalse);
    });

    test('plegar es otra cosa que ocultar', () async {
      final it = await session();
      await it.setCourseCollapsed('am-i', true);
      expect(it.isCollapsedCourse('am-i'), isTrue);
      expect(it.isHiddenCourse('am-i'), isFalse);
    });

    test('y todo se recuerda para el próximo arranque', () async {
      final it = await session();
      await it.setCourseHidden('zoo', true);
      await it.setYearHidden('am-i', '2022-2023', true);
      await it.setCourseCollapsed('am-i', true);

      final again = SyncedPrefs.fromJson(it.syncedPrefs.toJson());
      expect(again.isHiddenCourse('zoo'), isTrue);
      expect(again.isHiddenYear('am-i', '2022-2023'), isTrue);
      expect(again.isCollapsedCourse('am-i'), isTrue);
    });
  });

  group('las dos marcas son independientes', () {
    test('marcar la asignatura no marca ninguno de sus cursos', () async {
      final it = await session();
      await it.setFavouriteCourse('am-i', true);
      expect(it.isFavouriteYear('am-i', '2026-2027'), isFalse);
    });

    test('marcar un curso no marca su asignatura', () async {
      final it = await session();
      await it.setFavouriteYear('am-i', '2026-2027', true);
      expect(it.isFavouriteCourse('am-i'), isFalse);
    });

    test('el mismo año de dos asignaturas se marca por separado', () async {
      // La clave lleva la asignatura, así que marcar 2026-2027 en Zoología no
      // marca el de Análisis.
      final it = await session();
      await it.setFavouriteYear('zoo', '2026-2027', true);
      expect(it.isFavouriteYear('am-i', '2026-2027'), isFalse);
    });
  });

  group('se recuerdan', () {
    test('lo marcado se guarda para el próximo arranque', () async {
      final preferences = MemoryPreferences();
      final catalogue = withCourses([
        subject('am-i', 'AM I', const ['2026-2027']),
      ]);
      final it = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        preferencesOverride: preferences,
      );
      await it.primeForTest(catalogue);

      await it.setFavouriteCourse('am-i', true);
      await it.setFavouriteYear('am-i', '2026-2027', true);

      final saved = SyncedPrefs.fromJson(await preferences.syncedPrefs() ?? '');
      expect(saved.isFavouriteCourse('am-i'), isTrue);
      expect(saved.isFavouriteYear('am-i', '2026-2027'), isTrue);
    });

    test('un ida y vuelta por el fichero las conserva', () {
      final prefs = const SyncedPrefs()
          .withFavouriteCourse('am-i', true)
          .withFavouriteYear('am-i', '2026-2027', true);
      final back = SyncedPrefs.fromJson(prefs.toJson());
      expect(back.favouriteCourses, {'am-i'});
      expect(back.favouriteYears, {'am-i@2026-2027'});
    });
  });
}
