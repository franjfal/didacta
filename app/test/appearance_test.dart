/// Claro y oscuro: que se elige, que se recuerda y que se ve.
///
/// Lo que se prueba es la costura, que es donde se rompe: el modo lo decide
/// [Appearance], pero lo que se pinta lo decide la paleta de `theme.dart`, y
/// si una no sigue a la otra la aplicación se queda a medias --el tema de
/// Material en oscuro y las tarjetas todavía blancas--.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/state/appearance.dart';
import 'package:didacta_app/ui/shell.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

GoRouter routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(DidactaShell)));

Future<Appearance> pumpApp(
  WidgetTester tester, {
  String stored = 'light',
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final preferences = MemoryPreferences()
    ..look = stored
    ..scale = scale;
  final appearance = Appearance(preferences: preferences);
  await appearance.load();
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogueWith(defaultUnits()),
    preferencesOverride: preferences,
  );
  await tester.pumpWidget(
    DidactaApp(
      session: session,
      updates: offlineUpdates(),
      appearance: appearance,
    ),
  );
  await settle(tester);
  return appearance;
}

Color cardOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(DidactaShell))).cardColor;

/// Cuánto se agranda el texto dentro de la aplicación.
double scaleOf(WidgetTester tester) =>
    MediaQuery.textScalerOf(
      tester.element(find.byType(DidactaShell)),
    ).scale(10) /
    10;

/// Pulsa [key] con la tecla de los atajos: ⌘ en macOS, Ctrl en los demás.
///
/// [physical] es la tecla del teclado que la da, cuando no es la de un
/// teclado americano: el «+» del español está donde el americano tiene «]».
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  PhysicalKeyboardKey? physical,
}) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key, physicalKey: physical);
  await tester.sendKeyUpEvent(key, physicalKey: physical);
  await tester.sendKeyUpEvent(modifier);
  await settle(tester);
}

/// La paleta del tema en el que se pinta la aplicación.
DidactaPalette paletteOf(WidgetTester tester) =>
    tester.element(find.byType(DidactaShell)).palette;

void main() {
  group('el modo', () {
    test('se lee de lo que se eligió la última vez', () async {
      final appearance = Appearance(
        preferences: MemoryPreferences()..look = 'dark',
      );
      await appearance.load();

      expect(appearance.mode, AppearanceMode.dark);
      expect(appearance.palette, same(DidactaPalette.dark));
      appearance.dispose();
    });

    test('y lo que se elige se apunta', () async {
      final preferences = MemoryPreferences();
      final appearance = Appearance(preferences: preferences);

      await appearance.setMode(AppearanceMode.light);
      expect(preferences.look, 'light');
      // Alternar va al otro de lo que se ve, no de lo que está elegido.
      await appearance.toggle();
      expect(appearance.mode, AppearanceMode.dark);
      expect(preferences.look, 'dark');
      appearance.dispose();
    });

    test('algo que no se entiende es «el del sistema»', () {
      expect(AppearanceMode.parse('sepia'), AppearanceMode.system);
      expect(AppearanceMode.parse(null), AppearanceMode.system);
    });
  });

  group('en la aplicación', () {
    testWidgets('abre en el modo que estaba', (tester) async {
      await pumpApp(tester, stored: 'dark');

      expect(paletteOf(tester).isDark, isTrue);
      expect(cardOf(tester), DidactaPalette.dark.card);
    });

    testWidgets('el botón del carril la pasa a oscuro y la devuelve', (
      tester,
    ) async {
      final appearance = await pumpApp(tester);
      expect(paletteOf(tester).isDark, isFalse);
      expect(cardOf(tester), DidactaPalette.light.card);

      await tester.tap(find.byKey(const Key('appearance-toggle')));
      await settle(tester);

      expect(appearance.mode, AppearanceMode.dark);
      // Las dos mitades a la vez: la paleta de Didacta y el tema de
      // Material. Si solo cambiara una, la pantalla saldría a medias.
      expect(paletteOf(tester).isDark, isTrue);
      expect(cardOf(tester), DidactaPalette.dark.card);
      expect(
        Theme.of(tester.element(find.byType(DidactaShell))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.byKey(const Key('appearance-toggle')));
      await settle(tester);
      expect(paletteOf(tester).isDark, isFalse);
    });

    testWidgets('Ajustes deja volver al del sistema', (tester) async {
      final appearance = await pumpApp(tester, stored: 'dark');
      routerOf(tester).go('/settings?s=apariencia');
      await settle(tester);

      await tester.tap(find.byKey(const Key('appearance-system')));
      await settle(tester);

      expect(appearance.mode, AppearanceMode.system);
    });
  });

  group('el tamaño del texto', () {
    test('va por pasos, y no pasa de los extremos', () async {
      final preferences = MemoryPreferences();
      final appearance = Appearance(preferences: preferences);
      expect(appearance.textScale, 1);

      await appearance.biggerText();
      expect(appearance.textScale, 1.1);
      expect(preferences.scale, 1.1);

      for (var i = 0; i < 10; i += 1) {
        await appearance.biggerText();
      }
      expect(appearance.textScale, Appearance.textScales.last);
      for (var i = 0; i < 10; i += 1) {
        await appearance.smallerText();
      }
      expect(appearance.textScale, Appearance.textScales.first);

      await appearance.normalText();
      expect(appearance.textScale, 1);
      appearance.dispose();
    });

    test('lo guardado cae en el paso más cercano', () async {
      // Un valor que no es un paso --de otra versión, o puesto a mano-- no
      // puede dejar a ⌘+ sin saber cuál es el siguiente.
      final appearance = Appearance(
        preferences: MemoryPreferences()..scale = 1.07,
      );
      await appearance.load();
      expect(appearance.textScale, 1.1);
      await appearance.biggerText();
      expect(appearance.textScale, 1.2);
      appearance.dispose();
    });

    testWidgets('abre con el que estaba', (tester) async {
      await pumpApp(tester, scale: 1.2);
      expect(scaleOf(tester), closeTo(1.2, 0.001));
    });

    testWidgets('Ajustes lo cambia, sin perder la pantalla', (tester) async {
      final appearance = await pumpApp(tester);
      routerOf(tester).go('/settings?s=apariencia');
      await settle(tester);
      expect(find.text('100 %'), findsOneWidget);
      expect(find.byKey(const Key('text-normal')), findsNothing);

      await tester.tap(find.byKey(const Key('text-bigger')));
      await settle(tester);
      expect(appearance.textScale, 1.1);
      expect(scaleOf(tester), closeTo(1.1, 0.001));
      expect(find.text('110 %'), findsOneWidget);
      // Sigue en la misma sección: cambiar el tamaño no rehace el router.
      expect(
        routerOf(tester).routeInformationProvider.value.uri.toString(),
        '/settings?s=apariencia',
      );

      await tester.tap(find.byKey(const Key('text-normal')));
      await settle(tester);
      expect(appearance.textScale, 1);
      expect(scaleOf(tester), 1);
    });

    testWidgets(
      'con el teclado, fuera del Mac',
      (tester) async {
        final appearance = await pumpApp(tester);

        await press(tester, LogicalKeyboardKey.equal);
        expect(appearance.textScale, 1.1);
        // El del teclado numérico. (El «+» español lo prueba el del Mac: el
        // simulador de teclado de Linux no tiene esa tecla.)
        await press(tester, LogicalKeyboardKey.numpadAdd);
        expect(appearance.textScale, 1.2);
        await press(tester, LogicalKeyboardKey.minus);
        expect(appearance.textScale, 1.1);
        await press(tester, LogicalKeyboardKey.digit0);
        expect(appearance.textScale, 1);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'en el Mac, en el menú Ver, y el «+» español también',
      (tester) async {
        final appearance = await pumpApp(tester);
        final bar = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final view = bar.menus.whereType<PlatformMenu>().firstWhere(
          (menu) => menu.label == 'Ver',
        );
        final items = [
          for (final group in view.menus.whereType<PlatformMenuItemGroup>())
            ...group.members.whereType<PlatformMenuItem>(),
        ];
        final bigger = items.firstWhere(
          (item) => item.label == 'Texto más grande',
        );
        bigger.onSelected!();
        await settle(tester);
        expect(appearance.textScale, 1.1);

        // El menú lleva un atajo por elemento; el «+» propio lo atiende el
        // armazón.
        await press(
          tester,
          LogicalKeyboardKey.add,
          physical: PhysicalKeyboardKey.bracketRight,
        );
        expect(appearance.textScale, 1.2);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  group('las secciones de Ajustes', () {
    testWidgets('se ve una a la vez, y cuál lo dice la dirección', (
      tester,
    ) async {
      await pumpApp(tester);
      routerOf(tester).go('/settings');
      await settle(tester);

      // La primera, sin decir nada: la cuenta y los repositorios.
      expect(find.byKey(const Key('add-repository')), findsOneWidget);
      expect(find.text('Con los que trabajas'), findsNothing);

      await tester.tap(find.byKey(const Key('settings-section-idiomas')));
      await settle(tester);

      expect(
        routerOf(tester).routeInformationProvider.value.uri.toString(),
        '/settings?s=idiomas',
      );
      expect(find.text('Con los que trabajas'), findsOneWidget);
      expect(find.byKey(const Key('add-repository')), findsNothing);
    });

    testWidgets('en una ventana estrecha van en una tira, y caben', (
      tester,
    ) async {
      await pumpApp(tester);
      tester.view.physicalSize = const Size(760, 900);
      routerOf(tester).go('/settings?s=apariencia');
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(find.byKey(const Key('appearance-dark')), findsOneWidget);
    });

    testWidgets('una sección que no existe abre la primera', (tester) async {
      await pumpApp(tester);
      routerOf(tester).go('/settings?s=no-existe');
      await settle(tester);

      expect(find.byKey(const Key('add-repository')), findsOneWidget);
    });
  });
}
