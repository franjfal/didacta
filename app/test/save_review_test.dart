/// «Revisar los cambios antes de guardar», en Ajustes.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';
import 'package:didacta_app/data/mcp_process.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('apagado de salida, y se guarda al encenderlo', (tester) async {
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final preferences = MemoryPreferences();
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
      preferencesOverride: preferences,
    );
    await session.primeForTest(catalogue);
    await session.useClonesForTest(['/tmp/didacta-0']);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<McpService>(
            create: (_) => McpService(
              openRunner: () =>
                  const UnavailableRunner('Sin servidor en las pruebas.'),
            ),
          ),
          ChangeNotifierProvider<UpdateService>(
            create: (_) => offlineUpdates(),
          ),
          ChangeNotifierProvider<TourController>(
            create: (_) => TourController(),
          ),
        ],
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(body: SettingsPage(section: 'guardar')),
        ),
      ),
    );
    await settle(tester);

    final toggle = find.byKey(const Key('review-before-save'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(session.reviewBeforeSave, isFalse);

    await tester.tap(toggle);
    await settle(tester);
    expect(session.reviewBeforeSave, isTrue);
    expect(preferences.review, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.textContaining('enseña lo que cambia'), findsOneWidget);
  });
}
