/// El registro de diagnóstico: lo que apunta, lo que nunca apunta y dónde.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/diagnostics.dart';
import 'package:didacta_app/data/diagnostics_io.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';

import 'fixture.dart';

void main() {
  setUp(() => Diagnostics.instance.recent.clear());

  test('nunca lleva un secreto', () {
    const token = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
    final scrubbed = scrubSecrets(
      'git push https://x-access-token:$token@github.com/a/b.git '
      'Authorization: token $token '
      'key=AIzaSyA1234567890abcdefghijklmnopqrstu',
    );
    expect(scrubbed, isNot(contains(token)));
    expect(scrubbed, isNot(contains('AIzaSy')));
    expect(scrubbed, contains('github.com/a/b.git'));
  });

  test('un proceso, con su salida, su tiempo y la cola del error', () {
    Diagnostics.instance.process(
      program: '/usr/bin/git',
      arguments: const ['push', 'origin', 'main'],
      exitCode: 128,
      took: const Duration(milliseconds: 420),
      stderr: 'fatal: Authentication failed\n',
    );
    final entry = Diagnostics.instance.recent.single;
    expect(entry.message, 'git push origin main');
    expect(entry.detail['exit'], 128);
    expect(entry.detail['ms'], 420);
    expect(entry.detail['stderr'], contains('Authentication failed'));
  });

  test('lo que se repite es una línea con un número', () {
    for (var i = 0; i < 5; i += 1) {
      Diagnostics.instance.note('session.watchDisk', 'sin permiso');
    }
    expect(Diagnostics.instance.recent, hasLength(1));
    expect(Diagnostics.instance.recent.single.repeated, 5);
  });

  test('el fichero pasa a ser el anterior al llenarse', () async {
    final folder = await Directory.systemTemp.createTemp('didacta-diag-');
    addTearDown(() => folder.delete(recursive: true));
    final sink = RotatingFileSink(directory: folder.path, limit: 200);
    for (var i = 0; i < 20; i += 1) {
      sink.write(
        DiagnosticEntry(
          when: DateTime(2026, 9, 27),
          kind: 'error',
          message: 'fallo número $i',
        ),
      );
    }
    final names = folder.listSync().map((e) => e.path.split('/').last).toSet();
    expect(names, {'diagnostics.log', 'diagnostics.1.log'});
    // Nunca más de dos: el nuevo y el anterior.
    expect(File('${folder.path}/diagnostics.log').lengthSync(), lessThan(600));
  });

  test('el informe dice de dónde y lo último que ha pasado', () {
    Diagnostics.instance.github(method: 'GET', path: '/user', status: 401);
    final report = Diagnostics.instance.report(
      about: const {'Didacta': '0.2.1', 'sistema': 'macos'},
    );
    expect(report, contains('- Didacta: 0.2.1'));
    expect(report, contains('[github] GET /user status=401'));
  });

  testWidgets('en Ajustes → Ayuda, se copia', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    Diagnostics.instance.note('prueba', 'algo que falló');
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<McpService>(
            create: (_) => McpService(
              openRunner: () => const UnavailableRunner('Sin servidor.'),
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
          home: const Scaffold(body: SettingsPage(section: 'ayuda')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('copy-diagnostics')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copied, contains('informe de diagnóstico'));
    expect(copied, contains('algo que falló'));
    expect(find.byKey(const Key('diagnostics-copied')), findsOneWidget);
  });
}
