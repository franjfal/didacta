/// Quién avisa de qué: lo de una pieza, por la pieza; lo que cambia lo que se
/// ve en todas las pantallas, también por la sesión.
///
/// La sesión se ha dividido en piezas que avisan solas. Mientras todo avisaba
/// por ella, abrir una lección --que la apunta entre las recientes--, cambiar
/// la versión que se ojea o que empezara una compilación redibujaban todas
/// las pantallas que la miraban. Esto fija la regla, en las dos direcciones:
/// lo que no le importa a todas no despierta a la sesión, y lo que sí, sí.
library;

import 'package:didacta_app/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/ui/library_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<({FakeSession session, int Function() count})> _counted() async {
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
  );
  await session.primeForTest(catalogue);
  var calls = 0;
  session.addListener(() => calls += 1);
  return (session: session, count: () => calls);
}

void main() {
  group('no despierta a la sesión', () {
    test('abrir una lección, que la apunta entre las recientes', () async {
      final (:session, :count) = await _counted();

      session.noteOpened(session.catalogue.units.first);

      expect(count(), 0);
      expect(session.recentUnits, [session.catalogue.units.first]);
    });

    test('marcar y plegar en la lista de asignaturas', () async {
      final (:session, :count) = await _counted();
      final course = session.catalogue.courses.first.id;

      await session.setFavouriteCourse(course, true);
      await session.setCourseCollapsed(course, true);

      expect(count(), 0);
      expect(session.isFavouriteCourse(course), isTrue);
    });

    test('los ajustes de trabajo', () async {
      final (:session, :count) = await _counted();
      var settings = 0;
      session.settings.addListener(() => settings += 1);

      await session.setPreviewProfile('notes');
      await session.setCompleteInterface(true);
      await session.setUnitPanelVisible(false);
      await session.setQuickBuild(true);

      expect(settings, 4);
      expect(count(), 0);
      expect(session.previewProfile, 'notes');
      expect(session.completeInterface, isTrue);
    });

    test('una compilación que empieza y acaba', () async {
      final (:session, :count) = await _counted();
      var builds = 0;
      session.builds.addListener(() => builds += 1);

      await session.runBuild('Algo', (console) async => 1);

      expect(builds, greaterThan(0));
      expect(count(), 0);
    });
  });

  group('sí despierta a la sesión', () {
    test('ocultar un repositorio: cambia el catálogo que se enseña', () async {
      final (:session, :count) = await _counted();
      await session.setRepoVisible('test/repo', false);
      expect(count(), greaterThan(0));
    });

    test('apagar un idioma: cambia lo que ofrece cada selector', () async {
      final (:session, :count) = await _counted();
      final code = session.catalogue.languages.last;
      await session.setLanguageEnabled(code, false);
      expect(count(), greaterThan(0));
    });

    test('cambiar el idioma que se mira', () async {
      final (:session, :count) = await _counted();
      session.language = session.catalogue.languages.last;
      expect(count(), 1);
    });
  });

  testWidgets('la biblioteca se entera igual de la versión que se ojea', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      preferencesOverride: MemoryPreferences(),
    );
    await session.primeForTest(catalogue);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await settle(tester);

    // Si la página no escuchara a los ajustes, el botón se quedaría diciendo
    // la versión de antes: el cambio ya no pasa por la sesión.
    String shown() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('preview-picker')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    final other = session.previewProfile == 'slides' ? 'notes' : 'slides';
    final name = session.catalogue.profiles
        .firstWhere((profile) => profile.id == other)
        .name;
    expect(shown(), isNot(name));

    await session.setPreviewProfile(other);
    await settle(tester);

    expect(shown(), name);
  });
}
