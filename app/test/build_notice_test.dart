/// El aviso del sistema al terminar de compilar: qué dice, cómo se lanza en
/// cada sistema y cuándo sale.
///
/// Lo que se lanza se prueba para los tres sistemas desde cualquiera: es
/// donde se equivoca uno sin darse cuenta --una comilla en el título de un
/// tema que rompe la orden-- en un sistema que no tiene delante.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/model/notification.dart';
import 'package:didacta_app/model/toolchain.dart' show Host;
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

/// La orden de PowerShell, tal como la recibe: `-EncodedCommand` es UTF-16
/// little-endian en base64.
String decodedPowerShell(List<String> arguments) {
  final bytes = base64.decode(arguments.last);
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ]);
}

void main() {
  group('lo que dice', () {
    test('bien, con lo que se compiló', () {
      final notice = buildNotice(
        what: 'Tema 1 · Diapositivas',
        ok: true,
        stopped: false,
      )!;
      expect(notice.title, 'Compilado');
      expect(notice.body, '«Tema 1 · Diapositivas» ya está.');
    });

    test('un lote, con su resumen', () {
      final notice = buildNotice(
        what: 'Todo el curso',
        ok: false,
        stopped: false,
        summary: '36 bien, 2 con errores',
      )!;
      expect(notice.title, 'No ha compilado');
      expect(
        notice.body,
        '36 bien, 2 con errores. Los errores están en Didacta.',
      );
    });

    test('detenida, nada: quien la paró ya lo sabe', () {
      expect(buildNotice(what: 'Tema 1', ok: false, stopped: true), isNull);
    });
  });

  group('cómo se lanza', () {
    const title = 'Compilado';
    const body = 'El tema «Límites» y "sus" ejercicios\nde l\'examen';

    test('en el Mac, con AppleScript y las comillas escapadas', () {
      final command = notificationLaunch(
        title: title,
        body: body,
        host: Host.macos,
      );
      expect(command.executable, '/usr/bin/osascript');
      expect(command.arguments.first, '-e');
      expect(
        command.arguments.last,
        r'display notification "El tema «Límites» y \"sus\" ejercicios '
        'de l\'examen" with title "Didacta" subtitle "Compilado"',
      );
    });

    test('en Linux, con notify-send', () {
      final command = notificationLaunch(
        title: title,
        body: body,
        host: Host.linux,
      );
      expect(command.executable, 'notify-send');
      expect(command.arguments, [
        '--app-name=Didacta',
        'Didacta · Compilado',
        'El tema «Límites» y "sus" ejercicios de l\'examen',
      ]);
    });

    test('en Windows, con PowerShell y la orden codificada', () {
      final command = notificationLaunch(
        title: title,
        body: body,
        host: Host.windows,
      );
      expect(command.executable, 'powershell.exe');
      expect(command.arguments, containsAllInOrder(['-EncodedCommand']));
      final script = decodedPowerShell(command.arguments);
      // La comilla simple, doblada: es la única que hay que escapar ahí.
      expect(
        script,
        contains(
          "CreateTextNode('El tema «Límites» y \"sus\" ejercicios de "
          "l''examen')",
        ),
      );
      expect(script, contains("CreateTextNode('Didacta · Compilado')"));
      expect(script, contains('CreateToastNotifier(\$app)'));
    });
  });

  testWidgets('se enciende en Herramientas', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final preferences = MemoryPreferences();
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogueWith(defaultUnits()),
      preferencesOverride: preferences,
    );
    await tester.pumpWidget(
      DidactaApp(session: session, updates: offlineUpdates()),
    );
    for (var i = 0; i < 12; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    GoRouter.of(
      tester.element(find.byType(DidactaShell)),
    ).go('/settings?s=herramientas');
    for (var i = 0; i < 12; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final toggle = find.byKey(const Key('notify-when-built'));
    await tester.ensureVisible(toggle);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();

    expect(session.notifyWhenBuilt, isTrue);
    expect(preferences.notify, isTrue);
  });

  group('cuándo sale', () {
    Future<(FakeSession, RecordingNotifier)> sessionWith({
      required bool on,
      bool inFront = false,
    }) async {
      final notifier = RecordingNotifier(inFront: inFront);
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
        preferencesOverride: MemoryPreferences()..notify = on,
        notifierOverride: notifier,
      );
      await session.primeForTest(catalogueWith(defaultUnits()));
      return (session, notifier);
    }

    test('apagado, que es como viene, no avisa', () async {
      final (session, notifier) = await sessionWith(on: false);
      await session.runBuild('Tema 1', (console) async => 1);
      expect(notifier.shown, isEmpty);
    });

    test('encendido y con Didacta delante, tampoco', () async {
      final (session, notifier) = await sessionWith(on: true, inFront: true);
      await session.runBuild('Tema 1', (console) async => 1);
      expect(notifier.shown, isEmpty);
    });

    test('encendido y en otra ventana, dice cómo ha ido', () async {
      final (session, notifier) = await sessionWith(on: true);
      expect(session.notifyWhenBuilt, isTrue);

      await session.runBuild('Tema 1', (console) async => 1);
      expect(notifier.shown.single.title, 'Compilado');
      expect(notifier.shown.single.body, '«Tema 1» ya está.');

      await expectLater(
        session.runBuild<int>('Tema 2', (console) async {
          throw StateError('sin motor');
        }),
        throwsStateError,
      );
      expect(notifier.shown.last.title, 'No ha compilado');
    });

    test('detenida, no', () async {
      final (session, notifier) = await sessionWith(on: true);
      await session.runBuild('Tema 1', (console) async {
        console.finish(stopped: true);
        return 1;
      });
      expect(notifier.shown, isEmpty);
    });
  });
}
