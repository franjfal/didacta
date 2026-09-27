/// Lo que se monta en el `builder` de la aplicación, navegando de verdad.
///
/// Existe por un fallo que ningún test veía: el menú del sistema y las franjas
/// de aviso van en el `builder` de `MaterialApp.router`, y ese contexto está
/// **por encima** del `Router`. `GoRouter.of` y `Navigator.of` buscan hacia
/// arriba y no encuentran nada, así que «Ajustes…» del menú, «Abrir Ajustes»
/// y los «Ver» de las franjas no hacían nada --y dejaban una excepción en un
/// log que nadie mira--. Los demás tests navegan desde el contexto del
/// armazón, que sí está por debajo, y por eso no lo cogían.
///
/// Así que aquí se monta [DidactaApp] entera, que es donde está la costura, y
/// se pulsa lo que se pulsaría.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/data/local_clone.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/shell.dart';
import 'package:didacta_app/ui/shortcuts.dart';

import 'fixture.dart';
import 'update_ui_test.dart' show serviceWith, withRelease;

/// El menú del sistema solo se monta en macOS.
final TargetPlatformVariant macOS = TargetPlatformVariant.only(
  TargetPlatform.macOS,
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpApp(
  WidgetTester tester, {
  Catalogue? catalogue,
  UpdateService? updates,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Aquí no hay un macOS al otro lado del canal que dibuje el menú: sin
  // contestarle, `Menu.setMenus` acaba en un `MissingPluginException`.
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.menu, null),
  );

  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue ?? catalogueWith(defaultUnits()),
  );
  await tester.pumpWidget(
    DidactaApp(session: session, updates: updates ?? offlineUpdates()),
  );
  await settle(tester);
}

/// Dónde está la aplicación, tal como se lo dice el router al armazón.
String where(WidgetTester tester) =>
    tester.widget<DidactaShell>(find.byType(DidactaShell)).location;

/// Elige una entrada del menú, como la elegiría macOS.
///
/// Se llama a su `onSelected` y no a través del canal: lo que se prueba es lo
/// que hace la entrada, no cómo le llega a Flutter el clic.
Future<void> choose(WidgetTester tester, String label) async {
  PlatformMenuItem? find_(List<PlatformMenuItem> items) {
    for (final item in items) {
      if (item.label == label) return item;
      final inner = switch (item) {
        PlatformMenu(:final menus) => find_(menus),
        PlatformMenuItemGroup(:final members) => find_(members),
        _ => null,
      };
      if (inner != null) return inner;
    }
    return null;
  }

  final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
  final item = find_(bar.menus);
  expect(item, isNotNull, reason: 'no hay «$label» en el menú');
  expect(item!.onSelected, isNotNull, reason: '«$label» está deshabilitado');
  item.onSelected!();
  await settle(tester);
}

/// Una sesión con un repositorio y un resultado de traer y enviar preparado.
///
/// `pullAll` y `pushAll` no lanzan: devuelven, por repositorio, cuántos
/// commits movieron o el error que les tocó. Aquí se prepara cada caso.
class _SyncSession extends FakeSession {
  _SyncSession({
    required super.catalogue,
    this.pulled = const {},
    this.pushed = const {},
    this.pending = 0,
  }) : super(gatewayOverride: FakeGateway());

  final Map<String, Object> pulled;
  final Map<String, Object> pushed;
  final int pending;
  final List<bool> askedToCommit = [];

  @override
  Workspace get workspace => const Workspace([
    ContentRepo(owner: 'x', name: 'uno', directory: '/tmp/uno'),
  ]);

  @override
  int get pendingCount => pending;

  @override
  Future<Map<String, Object>> pullAll() async => pulled;

  @override
  Future<Map<String, Object>> pushAll(
    String message, {
    bool commitPending = true,
  }) async {
    askedToCommit.add(commitPending);
    return pushed;
  }
}

Future<_SyncSession> _pumpSync(
  WidgetTester tester, {
  Map<String, Object> pulled = const {},
  Map<String, Object> pushed = const {},
  int pending = 0,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.menu, null),
  );
  final session = _SyncSession(
    catalogue: catalogueWith(defaultUnits()),
    pulled: pulled,
    pushed: pushed,
    pending: pending,
  );
  await tester.pumpWidget(
    DidactaApp(session: session, updates: offlineUpdates()),
  );
  await settle(tester);
  return session;
}

void main() {
  group('traer y enviar desde el menú', () {
    testWidgets('«Enviar cambios» no cierra lo que está sin guardar', (
      tester,
    ) async {
      // Sin diálogo no hay mensaje, y cerrarlo con «Enviar» deja en el
      // historial un commit que no dice qué se hizo.
      final session = await _pumpSync(tester, pushed: {'x/uno': 2});
      await choose(tester, 'Enviar cambios');
      expect(session.askedToCommit, [false]);
      expect(find.text('Enviado a GitHub.'), findsOneWidget);
    }, variant: macOS);

    testWidgets('si no sale, no dice «Enviado»', (tester) async {
      // Esperaba una excepción que nunca llega: el fallo viene en el mapa.
      await _pumpSync(
        tester,
        pushed: {'x/uno': const CloneException('rechazado por GitHub')},
      );
      await choose(tester, 'Enviar cambios');
      expect(find.textContaining('Enviado'), findsNothing);
      // Con un solo repositorio, su aviso entero: qué ha pasado y qué hacer.
      expect(find.byKey(const Key('problem')), findsOneWidget);
      expect(find.textContaining('rechazado por GitHub'), findsOneWidget);
    }, variant: macOS);

    testWidgets('con nada guardado, dice dónde se envía lo demás', (
      tester,
    ) async {
      await _pumpSync(tester, pushed: {'x/uno': 0}, pending: 3);
      await choose(tester, 'Enviar cambios');
      expect(find.textContaining('desde la barra de arriba'), findsOneWidget);
    }, variant: macOS);

    testWidgets('«Traer cambios» que falla lo dice', (tester) async {
      await _pumpSync(
        tester,
        pulled: {'x/uno': const CloneException('sin red')},
      );
      await choose(tester, 'Traer cambios');
      expect(find.textContaining('Traído'), findsNothing);
      expect(find.byKey(const Key('problem')), findsOneWidget);
      expect(find.textContaining('sin red'), findsOneWidget);
    }, variant: macOS);
  });

  group('el menú del sistema', () {
    testWidgets('lleva a cada sección', (tester) async {
      await pumpApp(tester);
      expect(where(tester), '/courses');

      await choose(tester, 'Biblioteca');
      expect(where(tester), '/');

      await choose(tester, 'Traducción');
      expect(where(tester), '/translations');

      await choose(tester, 'Asignaturas');
      expect(where(tester), '/courses');

      await choose(tester, 'Ajustes…');
      expect(where(tester), '/settings');
    }, variant: macOS);

    testWidgets('«Configurar el acceso…» lleva a Ajustes', (tester) async {
      await pumpApp(tester);
      await choose(tester, 'Configurar el acceso…');
      expect(where(tester), '/settings');
    }, variant: macOS);

    testWidgets('atrás y adelante recorren lo navegado', (tester) async {
      // Estos dos, además, mueven el historial **antes** de navegar: si
      // navegar fallaba, el historial se quedaba apuntando a un sitio en el
      // que la aplicación no estaba.
      await pumpApp(tester);
      await choose(tester, 'Biblioteca');
      await choose(tester, 'Ajustes…');

      await choose(tester, 'Atrás');
      expect(where(tester), '/');

      await choose(tester, 'Atrás');
      expect(where(tester), '/courses');

      await choose(tester, 'Adelante');
      expect(where(tester), '/');
    }, variant: macOS);

    testWidgets('«atrás» vuelve también a la sección, no solo a la pantalla', (
      tester,
    ) async {
      // El historial guardaba la ruta sin su `?…`: se volvía a Ajustes, pero
      // a la primera sección, y a una lección en otro idioma.
      await pumpApp(tester);
      GoRouter.of(
        tester.element(find.byType(DidactaShell)),
      ).go(Routes.settings(section: 'idiomas'));
      await settle(tester);
      await choose(tester, 'Biblioteca');

      await choose(tester, 'Atrás');
      final shell = tester.widget<DidactaShell>(find.byType(DidactaShell));
      expect(shell.url, '/settings?s=idiomas');
    }, variant: macOS);
  });

  group('las franjas de arriba', () {
    testWidgets('«sin repositorios» abre Ajustes', (tester) async {
      // Sin unidades y sin repositorios, que es cuando sale.
      await pumpApp(tester, catalogue: catalogueWith(const []));
      expect(find.byKey(const Key('go-to-settings')), findsOneWidget);

      await tester.tap(find.byKey(const Key('go-to-settings')));
      await settle(tester);
      expect(where(tester), '/settings');
    });

    testWidgets('la de versión nueva abre su diálogo', (tester) async {
      final updates = serviceWith(withRelease());
      await updates.checkForUpdates();
      await pumpApp(tester, updates: updates);
      expect(find.byKey(const Key('open-update-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-update-dialog')));
      await settle(tester);
      expect(find.text('Hay una versión nueva de Didacta'), findsOneWidget);
    });

    testWidgets('la de errores los enseña todos, y se cierra', (tester) async {
      await pumpApp(
        tester,
        catalogue: catalogueWith(
          defaultUnits(),
          errors: const ['unit.yaml: falta el título', 'unit.yaml: otro'],
        ),
      );

      await tester.tap(find.text('Ver todos'));
      await settle(tester);
      expect(find.text('Problemas al leer el repositorio'), findsOneWidget);
      expect(find.text('unit.yaml: otro'), findsOneWidget);

      await tester.tap(find.text('Cerrar'));
      await settle(tester);
      expect(find.text('Problemas al leer el repositorio'), findsNothing);
    });
  });

  group('los atajos, en una tabla', () {
    test('con ⌘ en macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(labelFor(AppShortcut.pull), '⌘⇧P');
      expect(activatorFor(AppShortcut.save).meta, isTrue);
      expect(activatorFor(AppShortcut.save).control, isFalse);
    });

    test('con Ctrl en los demás, que no tienen ⌘', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(labelFor(AppShortcut.pull), 'Ctrl+Mayús+P');
      expect(labelFor(AppShortcut.back), 'Ctrl+[');
      expect(activatorFor(AppShortcut.save).control, isTrue);
    });

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await settle(tester);
    }

    testWidgets(
      'en Windows y Linux funcionan sin barra de menú',
      (tester) async {
        // Solo existían en el menú del Mac.
        await pumpApp(tester);
        await press(tester, LogicalKeyboardKey.digit2);
        expect(where(tester), '/');
        await press(tester, LogicalKeyboardKey.comma);
        expect(where(tester), '/settings');
        await press(tester, LogicalKeyboardKey.digit1);
        expect(where(tester), '/courses');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'y la hoja de atajos sale con Ctrl+/',
      (tester) async {
        await pumpApp(tester);
        await press(tester, LogicalKeyboardKey.slash);
        expect(find.byKey(const Key('shortcuts-sheet')), findsOneWidget);
        expect(find.text('Ctrl+Mayús+P'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('el menú del Mac tiene Edición, Ventana y Ayuda', (
      tester,
    ) async {
      await pumpApp(tester);
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final labels = [
        for (final menu in bar.menus)
          if (menu is PlatformMenu) menu.label,
      ];
      expect(labels, containsAll(['Edición', 'Ventana', 'Ayuda']));

      await choose(tester, 'Atajos de teclado');
      expect(find.byKey(const Key('shortcuts-sheet')), findsOneWidget);
      expect(find.text('⌘⇧P'), findsOneWidget);
    }, variant: macOS);

    testWidgets('Edición actúa sobre el campo que tiene el foco', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpApp(tester);
      await choose(tester, 'Biblioteca');
      final search = find.byType(TextField).first;
      await tester.tap(search);
      await tester.enterText(search, 'normas');
      await settle(tester);

      await choose(tester, 'Seleccionar todo');
      await choose(tester, 'Copiar');
      expect(copied, 'normas');
    }, variant: macOS);
  });
}
