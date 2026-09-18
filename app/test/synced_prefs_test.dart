/// Las preferencias que viajan de un ordenador a otro.
///
/// Dos cosas se fijan aquí, y son las dos que hacen que esto se pueda usar en
/// un repositorio compartido:
///
/// **Que dos personas no se pisen.** El fichero lleva el login de GitHub en el
/// nombre, así que un departamento entero comparte repositorio y cada uno
/// escribe el suyo.
///
/// **Que no cueste un commit por clic.** Plegar tres temas seguidos es una
/// escritura, no tres: el historial del material no puede llenarse de ruido
/// por una preferencia de interfaz.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/synced_prefs.dart';

import 'fixture.dart';

void main() {
  group('el fichero', () {
    test('un ida y vuelta conserva lo plegado', () {
      final prefs = const SyncedPrefs()
          .withThemeCollapsed(
            course: 'am-i',
            year: '2026-2027',
            theme: 'tema-3',
            collapsed: true,
          )
          .withThemeCollapsed(
            course: 'am-i',
            year: '2026-2027',
            theme: 'tema-4',
            collapsed: true,
          );

      final back = SyncedPrefs.fromJson(prefs.toJson());
      expect(back.collapsedIn('am-i', '2026-2027'), {'tema-3', 'tema-4'});
    });

    test('desplegar quita, y el curso vacío no se queda escrito', () {
      final prefs = const SyncedPrefs()
          .withThemeCollapsed(
            course: 'am-i',
            year: '2026-2027',
            theme: 'tema-3',
            collapsed: true,
          )
          .withThemeCollapsed(
            course: 'am-i',
            year: '2026-2027',
            theme: 'tema-3',
            collapsed: false,
          );
      expect(prefs.isEmpty, isTrue);
      expect(prefs.toJson(), isNot(contains('am-i')));
    });

    test('se escribe siempre igual, para no dar un commit por nada', () {
      // Un fichero cuyas claves salen en otro orden cada vez da un diff que
      // no dice nada y un commit que no cambia nada.
      final uno = const SyncedPrefs()
          .withThemeCollapsed(
            course: 'b',
            year: '2026-2027',
            theme: 'z',
            collapsed: true,
          )
          .withThemeCollapsed(
            course: 'a',
            year: '2026-2027',
            theme: 'y',
            collapsed: true,
          );
      final dos = const SyncedPrefs()
          .withThemeCollapsed(
            course: 'a',
            year: '2026-2027',
            theme: 'y',
            collapsed: true,
          )
          .withThemeCollapsed(
            course: 'b',
            year: '2026-2027',
            theme: 'z',
            collapsed: true,
          );
      expect(uno.toJson(), dos.toJson());
    });

    test('un fichero roto son las preferencias por defecto, no un fallo', () {
      // No abrir la aplicación porque un JSON de ajustes está a medias sería
      // desproporcionado: lo que se pierde es un panel plegado.
      expect(SyncedPrefs.fromJson('{ esto no es json').isEmpty, isTrue);
      expect(SyncedPrefs.fromJson('').isEmpty, isTrue);
      expect(SyncedPrefs.fromJson('[]').isEmpty, isTrue);
    });

    test('una versión que no se entiende se ignora entera', () {
      expect(
        SyncedPrefs.fromJson(
          '{"version": 99, "collapsedThemes": {"am-i@2026-2027": ["x"]}}',
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('en la sesión', () {
    test('plegar un tema se recuerda en la máquina', () async {
      final preferences = MemoryPreferences();
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        preferencesOverride: preferences,
      );

      await session.setThemeCollapsed(
        course: 'am-i',
        year: '2026-2027',
        theme: 'tema-1',
        collapsed: true,
      );

      expect(session.collapsedThemes('am-i', '2026-2027'), {'tema-1'});
      expect(await preferences.syncedPrefs(), contains('tema-1'));
    });

    test('sin repositorio elegido no se escribe en ninguno', () async {
      // Es el estado de salida y tiene que funcionar: las preferencias se
      // quedan aquí, como todas las de antes.
      final gateway = FakeGateway();
      final session = FakeSession(
        gatewayOverride: gateway,
        catalogue: catalogueWith(defaultUnits()),
      );

      await session.setThemeCollapsed(
        course: 'am-i',
        year: '2026-2027',
        theme: 'tema-1',
        collapsed: true,
      );
      await session.pushSyncedPrefs();

      expect(gateway.commits, isEmpty);
    });

    test('sin saber quién ha entrado tampoco se escribe', () async {
      // El nombre del fichero es el login: sin login no hay fichero que
      // escribir, y escribir uno compartido sería pisar el de otro.
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );
      await session.setPrefsRepo('x/uno');
      expect(session.prefsPath, isNull);
    });
  });

  group('los idiomas con los que se trabaja', () {
    const all = ['es', 'va', 'en'];

    test('sin elegir ninguno se ofrecen todos', () {
      // Vacío es «todos» y no «ninguno». Es lo que permite añadir esto sin
      // cambiar nada para quien no lo toque.
      const prefs = SyncedPrefs();
      for (final code in all) {
        expect(prefs.isLanguageEnabled(code), isTrue);
      }
    });

    test('apagar uno deja los demás', () {
      final prefs = const SyncedPrefs().withLanguageEnabled(
        'en',
        false,
        all: all,
      );

      expect(prefs.isLanguageEnabled('en'), isFalse);
      expect(prefs.isLanguageEnabled('es'), isTrue);
      expect(prefs.isLanguageEnabled('va'), isTrue);
    });

    test('un ida y vuelta lo conserva', () {
      final prefs = const SyncedPrefs().withLanguageEnabled(
        'en',
        false,
        all: all,
      );

      expect(SyncedPrefs.fromJson(prefs.toJson()).enabledLanguages, {
        'es',
        'va',
      });
    });

    test('volver a marcarlos todos no deja una lista que mantener', () {
      // Si se guardara la lista entera, añadir un idioma al repositorio
      // mañana lo dejaría apagado sin que nadie lo apagara.
      final prefs = const SyncedPrefs()
          .withLanguageEnabled('en', false, all: all)
          .withLanguageEnabled('en', true, all: all);

      expect(prefs.enabledLanguages, isEmpty);
      expect(prefs.isEmpty, isTrue);
    });

    test('apagarlos todos es no filtrar', () {
      var prefs = const SyncedPrefs();
      for (final code in all) {
        prefs = prefs.withLanguageEnabled(code, false, all: all);
      }

      expect(prefs.enabledLanguages, isEmpty);
      for (final code in all) {
        expect(prefs.isLanguageEnabled(code), isTrue);
      }
    });

    test('un fichero de antes de que esto existiera se lee igual', () {
      // No se sube la versión por añadir un campo: un fichero escrito por una
      // versión anterior no está mal, solo es anterior.
      const older =
          '{"version": 1, "hiddenRepos": [], "favouriteCourses": ["am-i"]}';

      final prefs = SyncedPrefs.fromJson(older);
      expect(prefs.isFavouriteCourse('am-i'), isTrue);
      expect(prefs.enabledLanguages, isEmpty);
      expect(prefs.isLanguageEnabled('en'), isTrue);
    });
  });

  group('la vista de las asignaturas', () {
    test('viaja con lo demás', () {
      // Es la lista con la que se trabaja, no una forma de buscar un rato:
      // quien ordena sus asignaturas se queda en «las ocultas» un buen rato.
      final prefs = const SyncedPrefs().withCoursesView('hidden');

      expect(prefs.isEmpty, isFalse);
      expect(SyncedPrefs.fromJson(prefs.toJson()).coursesView, 'hidden');
    });

    test('sin elegir nada son las que se dan', () {
      expect(const SyncedPrefs().coursesView, 'visible');
      // Y eso no es una preferencia que haya que escribir: un fichero vacío
      // sigue estando vacío.
      expect(const SyncedPrefs().withCoursesView('visible').isEmpty, isTrue);
    });

    test('se guarda el nombre, tal cual', () {
      // El enumerado es de la pantalla y este fichero se lee dentro de un
      // año: lo que no se reconozca lo resuelve quien lo dibuja, no esto.
      const written = '{"version": 1, "coursesView": "loquesea"}';

      expect(SyncedPrefs.fromJson(written).coursesView, 'loquesea');
    });
  });
}
