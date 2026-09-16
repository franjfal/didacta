/// Every route, at every size, without an overflow.
///
/// This exists because of a bug it would have caught: the editor bar's row
/// fitted on a desktop and, below about a thousand pixels, pushed its own
/// save button off the edge -- so the screen looked fine and could not be
/// used. Overflows are layout assertions, which means a test can simply
/// insist there are none.
///
/// Three sizes rather than one: a phone, a tablet and a desktop sit on
/// different sides of both breakpoints in the app (700 for the shell's rail,
/// 1000 for the editor's side panel), so between them every branch of the
/// responsive layout is built. The requirement was Flutter Web first with
/// desktop and mobile later *without rewriting the logic*; this is what keeps
/// that true while it is still cheap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/main.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

/// The sizes, in logical pixels.
const Map<String, Size> sizes = {
  'móvil': Size(390, 844),
  'tableta': Size(834, 1112),
  'escritorio': Size(1440, 900),
};

/// Every route the router serves, with arguments that resolve against the
/// fixture -- and two that deliberately do not.
const Map<String, String> routes = {
  'la biblioteca': '/',
  'una unidad': '/unit/content/analysis/normed/definition',
  'una unidad con traducciones a medias':
      '/unit/content/analysis/normed/banach',
  'una unidad que no existe': '/unit/content/no/such/unit',
  'las asignaturas': '/courses',
  'un curso': '/courses/am-iii/2025-2026',
  'un documento': '/courses/am-iii/2025-2026/tema-1',
  'una hoja de problemas': '/courses/am-iii/2025-2026/hoja-1',
  'un documento que no existe': '/courses/am-iii/2025-2026/no-existe',
  'traducciones': '/translations',
  'entre repositorios': '/between',
  'ajustes': '/settings',
  'una dirección inventada': '/no/existe',
};

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  for (final size in sizes.entries) {
    group('en ${size.key} (${size.value.width.toInt()}px)', () {
      for (final route in routes.entries) {
        testWidgets('${route.key} cabe en la pantalla', (tester) async {
          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final session = FakeSession(
            gatewayOverride: FakeGateway(),
            catalogue: catalogueWith(defaultUnits()),
          );

          await tester.pumpWidget(
            DidactaApp(session: session, updates: offlineUpdates()),
          );
          await settle(tester);

          // Reached by navigating rather than by mounting the screen alone,
          // so the shell, the banners and the route's own chrome are all in
          // the layout being measured.
          GoRouter.of(
            tester.element(find.byType(DidactaShell)),
          ).go(route.value);
          await settle(tester);

          // An overflow arrives as a layout assertion, so "no exception" is
          // exactly the claim being made.
          expect(
            tester.takeException(),
            isNull,
            reason: '${route.value} desborda en ${size.key}',
          );
        });
      }
    });
  }
}
