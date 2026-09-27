/// Las versiones de prueba: solo para quien las pide, y la final después.
library;

import 'dart:convert';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/release_channel.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/update_section.dart';

import 'update_service_test.dart'
    show FakeInstaller, installed, manifestBody, routed;

String release(
  String tag,
  int manifest, {
  bool draft = false,
  bool pre = false,
}) => jsonEncode(_release(tag, manifest, draft: draft, pre: pre));

Map<String, dynamic> _release(
  String tag,
  int manifest, {
  bool draft = false,
  bool pre = false,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': pre,
  'assets': [
    {'name': 'latest.json', 'id': manifest},
  ],
};

/// GitHub con la 1.4.2 publicada, una prueba 1.5.0-rc.1 y un borrador.
MockClient github({bool finalOut = false}) {
  final all = [
    if (finalOut) _release('v1.5.0', 8),
    _release('v1.5.0-rc.2', 9, draft: true),
    _release('v1.5.0-rc.1', 6, pre: true),
    _release('v1.4.2', 5),
  ];
  return routed({
    'releases/latest': http.Response(
      finalOut ? release('v1.5.0', 8) : release('v1.4.2', 5),
      200,
    ),
    'releases': http.Response(jsonEncode(all), 200),
    'releases/assets/5': http.Response(manifestBody(), 200),
    'releases/assets/6': http.Response(
      manifestBody(version: '1.5.0-rc.1'),
      200,
    ),
    'releases/assets/8': http.Response(manifestBody(version: '1.5.0'), 200),
    'releases/assets/9': http.Response(
      manifestBody(version: '1.5.0-rc.2'),
      200,
    ),
  });
}

UpdateService service(http.Client client, MemoryPreferences preferences) =>
    UpdateService(
      info: installed,
      preferences: preferences,
      openChannel: () =>
          ReleaseChannel(owner: 'franjfal', repo: 'didacta', client: client),
      installer: FakeInstaller(),
    );

void main() {
  test('sin pedirlas, la última publicada para todos', () async {
    final updates = service(github(), MemoryPreferences());
    await updates.load();
    await updates.checkForUpdates();
    expect(updates.newVersion, const AppVersion(1, 4, 2));
  });

  test('pidiéndolas, la prueba; un borrador nunca', () async {
    final preferences = MemoryPreferences();
    final updates = service(github(), preferences);
    await updates.load();
    await updates.setTestVersions(true);
    expect(preferences.tests, isTrue);
    expect(updates.newVersion.toString(), '1.5.0-rc.1');
    expect(updates.newVersion!.isPreRelease, isTrue);
  });

  test('y en cuanto sale la final, la final', () async {
    final preferences = MemoryPreferences()..tests = true;
    final updates = service(github(finalOut: true), preferences);
    await updates.load();
    await updates.checkForUpdates();
    expect(updates.newVersion.toString(), '1.5.0');
  });

  testWidgets('el interruptor, en Actualizaciones', (tester) async {
    final preferences = MemoryPreferences();
    final updates = service(github(), preferences);
    await updates.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<UpdateService>.value(
        value: updates,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: UpdateSection()),
          ),
        ),
      ),
    );
    expect(find.text('Versiones de prueba'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('update-tests')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(preferences.tests, isTrue);
    expect(find.textContaining('1.5.0-rc.1, de prueba'), findsOneWidget);
  });
}
