/// Lo abierto hace poco y las búsquedas guardadas.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/model/saved_search.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

GoRouter routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(DidactaShell)));

Uri where(WidgetTester tester) =>
    routerOf(tester).routeInformationProvider.value.uri;

Future<FakeSession> pumpApp(
  WidgetTester tester,
  MemoryPreferences preferences,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogueWith(defaultUnits()),
    preferencesOverride: preferences,
  );
  await tester.pumpWidget(
    DidactaApp(session: session, updates: offlineUpdates()),
  );
  await settle(tester);
  routerOf(tester).go(Routes.library());
  await settle(tester);
  return session;
}

void main() {
  group('en la sesión', () {
    test('la más reciente primero, sin repetir, con tope', () async {
      final preferences = MemoryPreferences();
      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        preferencesOverride: preferences,
      );
      await session.primeForTest(catalogue);
      final units = catalogue.units;
      session
        ..noteOpened(units[0])
        ..noteOpened(units[1])
        ..noteOpened(units[0]);
      expect(session.recentUnits.map((u) => u.path), [
        units[0].path,
        units[1].path,
      ]);
      expect(preferences.recent, hasLength(2));
    });

    test('una que ya no existe no sale', () async {
      final preferences = MemoryPreferences()
        ..recent = const ['|content/no/existe', '|$unitPath'];
      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        preferencesOverride: preferences,
      );
      await session.primeForTest(catalogue);
      expect(session.recentUnits.map((u) => u.path), [unitPath]);
    });

    test('guardar y olvidar una búsqueda', () async {
      final preferences = MemoryPreferences();
      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        preferencesOverride: preferences,
      );
      await session.primeForTest(catalogue);
      await session.saveSearch('Banach', '/?q=banach');
      await session.saveSearch('Otra vez', '/?q=banach');
      expect(session.savedSearches.single.name, 'Otra vez');
      expect(
        SavedSearch.listFromJson(preferences.searches).single.url,
        '/?q=banach',
      );
      await session.forgetSearch('/?q=banach');
      expect(session.savedSearches, isEmpty);
    });
  });

  testWidgets('abrir una lección la deja en «abiertas hace poco»', (
    tester,
  ) async {
    await pumpApp(tester, MemoryPreferences());
    expect(find.byKey(const Key('library-shortcuts')), findsNothing);

    routerOf(tester).go(Routes.unit(unitPath));
    await settle(tester);
    routerOf(tester).go(Routes.library());
    await settle(tester);

    final chip = find.byKey(const Key('recent-$unitPath'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await settle(tester);
    expect(where(tester).path, '/unit/$unitPath');
  });

  testWidgets('en la interfaz completa, una búsqueda se guarda y se vuelve', (
    tester,
  ) async {
    final session = await pumpApp(tester, MemoryPreferences());
    await tester.enterText(find.byType(TextField).first, 'banach');
    await settle(tester);
    // En la esencial no se ofrece.
    expect(find.byKey(const Key('save-search')), findsNothing);
    await session.setCompleteInterface(true);
    await settle(tester);

    await tester.tap(find.byKey(const Key('save-search')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('save-search-name')),
      'Lo de Banach',
    );
    await tester.tap(find.byKey(const Key('save-search-confirm')));
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, '');
    await settle(tester);
    final saved = find.byKey(const Key('saved-search-Lo de Banach'));
    expect(saved, findsOneWidget);
    await tester.tap(saved);
    await settle(tester);
    expect(where(tester).queryParameters['q'], 'banach');
  });
}
