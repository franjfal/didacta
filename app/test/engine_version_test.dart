/// El motor frente a la aplicación: qué se dice en Ajustes, y que la sesión
/// mueve sola el que instaló Didacta y no el de nadie más.
@TestOn('mac-os || linux')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:didacta_app/data/engine_pin.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/ui/engine_version_line.dart';
import 'package:didacta_app/ui/theme.dart';

import 'engine_pin_test.dart' show git;
import 'fixture.dart';

const app = AppVersion(0, 2, 1);

Future<void> pumpLine(
  WidgetTester tester,
  EngineVersion version, {
  Future<void> Function()? onPin,
}) => tester.pumpWidget(
  MaterialApp(
    theme: didactaTheme(),
    home: Scaffold(
      body: EngineVersionLine(version: version, onPin: onPin ?? () async {}),
    ),
  ),
);

/// Un «GitHub» con la 0.2.1 publicada y un clon de `main` que parece un
/// motor: tiene `cli/didacta`.
String engineClone() {
  final root = Directory.systemTemp.createTempSync('didacta-engine-v-');
  addTearDown(() => root.deleteSync(recursive: true));
  final work = '${root.path}/work';
  Directory('$work/cli').createSync(recursive: true);
  git(work, ['init', '-q', '-b', 'main']);
  git(work, ['config', 'user.email', 'a@b.c']);
  git(work, ['config', 'user.name', 'A']);
  File('$work/cli/didacta').writeAsStringSync('#!/bin/sh\n');
  File('$work/VERSION').writeAsStringSync('0.2.1');
  git(work, ['add', '.']);
  git(work, ['commit', '-q', '-m', '0.2.1']);
  git(work, ['tag', 'v0.2.1']);
  File('$work/VERSION').writeAsStringSync('main');
  git(work, ['commit', '-q', '-am', 'main']);
  git(root.path, ['clone', '-q', '--bare', work, '${root.path}/origin.git']);
  final engine = '${root.path}/didacta';
  git(root.path, [
    'clone',
    '-q',
    '--no-tags',
    '${root.path}/origin.git',
    engine,
  ]);
  return engine;
}

void main() {
  group('lo que dice', () {
    testWidgets('el de esta versión', (tester) async {
      await pumpLine(tester, const EngineVersion(app: app, engine: app));
      expect(
        find.text('Motor de la 0.2.1, la versión de la aplicación.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('engine-pin')), findsNothing);
    });

    testWidgets('uno de desarrollo, con su commit y el botón', (tester) async {
      await pumpLine(tester, const EngineVersion(app: app, commit: 'abc1234'));
      expect(
        find.textContaining('Motor en desarrollo (abc1234)'),
        findsOneWidget,
      );
      expect(find.text('Poner el de la 0.2.1'), findsOneWidget);
    });

    testWidgets('con cambios sin guardar no ofrece moverlo', (tester) async {
      await pumpLine(
        tester,
        const EngineVersion(
          app: app,
          engine: AppVersion(0, 2, 0),
          blocked: 'tiene cambios sin guardar',
        ),
      );
      expect(
        find.text('Motor de la 0.2.0; la aplicación es la 0.2.1.'),
        findsOneWidget,
      );
      expect(
        find.text('No lo muevo: tiene cambios sin guardar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('engine-pin')), findsNothing);
    });

    testWidgets('el de otro se pregunta antes; el suyo, no', (tester) async {
      var pinned = 0;
      Future<void> pin() async => pinned += 1;
      await pumpLine(
        tester,
        const EngineVersion(app: app, engine: AppVersion(0, 2, 0)),
        onPin: pin,
      );
      await tester.tap(find.byKey(const Key('engine-pin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('engine-pin-confirm')), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(pinned, 0);
      await tester.tap(find.byKey(const Key('engine-pin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('engine-pin-go')));
      await tester.pumpAndSettle();
      expect(pinned, 1);

      await pumpLine(
        tester,
        const EngineVersion(
          app: app,
          engine: AppVersion(0, 2, 0),
          managed: true,
        ),
        onPin: pin,
      );
      await tester.tap(find.byKey(const Key('engine-pin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('engine-pin-confirm')), findsNothing);
      expect(pinned, 2);
    });

    testWidgets('si no se pudo, lo dice', (tester) async {
      await pumpLine(
        tester,
        const EngineVersion(app: app, managed: true),
        onPin: () async =>
            throw const EnginePinException('GitHub no tiene la versión v0.2.1'),
      );
      await tester.tap(find.byKey(const Key('engine-pin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('engine-pin-problem')), findsOneWidget);
    });
  });

  group('la sesión', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Didacta',
        packageName: 'io.github.franjfal.didacta',
        version: '0.2.1',
        buildNumber: '4',
        buildSignature: '',
      );
    });

    Future<FakeSession> withEngine(String engine) async {
      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
        preferencesOverride: MemoryPreferences()..engine = engine,
      );
      await session.primeForTest(catalogue);
      await session.findEngine();
      expect(session.enginePath, engine);
      return session;
    }

    test('el que instaló Didacta lo pone sola en su versión', () async {
      final engine = engineClone();
      await markManaged(engine);
      final session = await withEngine(engine);
      await session.checkEngineVersion();
      expect(session.engineVersion!.matches, isTrue);
      expect(File('$engine/VERSION').readAsStringSync(), '0.2.1');
    });

    test('el de otro no lo toca, y el botón sí', () async {
      final engine = engineClone();
      final session = await withEngine(engine);
      await session.checkEngineVersion();
      expect(session.engineVersion!.matches, isFalse);
      expect(session.engineVersion!.canPin, isTrue);
      expect(File('$engine/VERSION').readAsStringSync(), 'main');

      await session.pinEngineNow();
      expect(session.engineVersion!.matches, isTrue);
      expect(session.engineVersion!.managed, isTrue);
    });
  });
}
