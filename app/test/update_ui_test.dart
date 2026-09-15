/// La pantalla de Ajustes → Actualizaciones, y el aviso.
///
/// Comprueba lo que un test unitario no puede: que lo que se decide en el
/// servicio llega a la pantalla, y sobre todo **que no molesta**. Sin versión
/// nueva no hay franja, sin poder instalar no hay botón de instalar, y un
/// fallo de red sale como una nota y no como una pantalla rota.
library;

import 'package:didacta_app/data/app_info.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/release_channel.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/update_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'update_service_test.dart' show FakeInstaller, manifestBody, releaseBody;

const AppInfo installed = AppInfo(
  version: AppVersion(1, 4, 1),
  build: 141,
  packageName: 'es.uv.didacta',
  platform: UpdatePlatform.macos,
  architecture: 'arm64',
);

UpdateService serviceWith(
  http.Client client, {
  String? cannotInstall,
  DateTime? checked,
}) => UpdateService(
  info: installed,
  preferences: MemoryPreferences()..checked = checked,
  readToken: () async => 'gho_valido',
  openChannel: (token) => ReleaseChannel(
    owner: 'franjfal',
    repo: 'didacta_public',
    token: token,
    client: client,
  ),
  installer: FakeInstaller(reason: cannotInstall),
);

MockClient withRelease() => MockClient((request) async {
  if (request.url.path.endsWith('releases/latest')) {
    return http.Response(releaseBody(), 200);
  }
  if (request.url.path.endsWith('releases/assets/5')) {
    return http.Response(manifestBody(), 200);
  }
  return http.Response('{}', 404);
});

Future<void> pumpSection(WidgetTester tester, UpdateService service) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<UpdateService>.value(
      value: service,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: UpdateSection())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('enseña la versión instalada y que nunca se ha comprobado', (
    tester,
  ) async {
    await pumpSection(
      tester,
      serviceWith(MockClient((_) async => http.Response('{}', 404))),
    );

    expect(find.textContaining('1.4.1 (141)'), findsOneWidget);
    expect(find.textContaining('macOS arm64'), findsOneWidget);
    expect(find.text('Todavía no se ha comprobado'), findsOneWidget);
    // Sin haber preguntado, no se dice ni que hay ni que no hay.
    expect(find.textContaining('versión nueva'), findsNothing);
    expect(find.text('Estás al día.'), findsNothing);
  });

  testWidgets('al no haber nada nuevo lo dice, y nada más', (tester) async {
    final service = serviceWith(
      MockClient(
        (request) async => request.url.path.endsWith('didacta_public')
            ? http.Response('{}', 200)
            : http.Response('{}', 404),
      ),
    );
    await pumpSection(tester, service);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();

    expect(find.text('Estás al día.'), findsOneWidget);
    expect(find.byKey(const Key('install-update')), findsNothing);
  });

  testWidgets('con versión nueva ofrece actualizar', (tester) async {
    final service = serviceWith(withRelease());
    await pumpSection(tester, service);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hay una versión nueva'), findsOneWidget);
    expect(find.text('Actualizar a 1.4.2'), findsOneWidget);
  });

  testWidgets('donde no se puede instalar sola, lo dice y no ofrece el botón', (
    tester,
  ) async {
    // El caso de un Linux donde Didacta no viene de un AppImage: el gestor de
    // paquetes manda, y el botón sería una promesa que no se puede cumplir.
    final service = serviceWith(
      withRelease(),
      cannotInstall: 'Didacta no se está ejecutando desde un AppImage.',
    );
    await pumpSection(tester, service);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();

    expect(find.textContaining('AppImage'), findsOneWidget);
    expect(find.byKey(const Key('install-update')), findsNothing);
  });

  testWidgets('un fallo sale como nota, no como pantalla rota', (tester) async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{}', 401)),
    );
    await pumpSection(tester, service);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vuelve a entrar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin acceso al repositorio se explica qué pedir', (tester) async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{}', 404)),
    );
    await pumpSection(tester, service);
    await tester.tap(find.byKey(const Key('check-for-updates')));
    await tester.pumpAndSettle();

    expect(find.textContaining('no tiene acceso'), findsOneWidget);
    expect(find.textContaining('franjfal/didacta_public'), findsOneWidget);
  });

  testWidgets('sin acceso, la tarjeta lo dice y explica qué pedir', (
    tester,
  ) async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{}', 404)),
    );
    await service.checkAuthorisation();
    await pumpSection(tester, service);

    expect(
      find.textContaining('no tiene acceso a las versiones'),
      findsOneWidget,
    );
    expect(find.textContaining('franjfal/didacta_public'), findsOneWidget);
  });

  testWidgets('con acceso, lo dice y no molesta más', (tester) async {
    final service = serviceWith(
      MockClient(
        (request) async => request.url.path.endsWith('didacta_public')
            ? http.Response('{}', 200)
            : http.Response('{}', 404),
      ),
    );
    await service.checkAuthorisation();
    await pumpSection(tester, service);

    expect(find.text('Tu cuenta de GitHub está autorizada'), findsOneWidget);
    expect(find.textContaining('no tiene acceso'), findsNothing);
  });

  group('la franja de aviso', () {
    Future<void> pumpBanner(WidgetTester tester, UpdateService service) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<UpdateService>.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(body: Column(children: [UpdateBanner()])),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('no aparece si no hay nada nuevo', (tester) async {
      await pumpBanner(
        tester,
        serviceWith(MockClient((_) async => http.Response('{}', 404))),
      );
      expect(find.byKey(const Key('open-update-dialog')), findsNothing);
    });

    testWidgets('aparece con versión nueva, y se puede cerrar', (tester) async {
      final service = serviceWith(withRelease());
      await pumpBanner(tester, service);
      await service.checkForUpdates();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open-update-dialog')), findsOneWidget);
      expect(find.textContaining('1.4.2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dismiss-update-banner')));
      await tester.pumpAndSettle();

      // Cerrada la franja, pero la versión sigue estando: Ajustes la ofrece.
      expect(find.byKey(const Key('open-update-dialog')), findsNothing);
      expect(service.hasUpdate, isTrue);
    });
  });

  group('el diálogo', () {
    testWidgets('enseña las novedades y los dos caminos', (tester) async {
      final service = serviceWith(withRelease());
      await tester.pumpWidget(
        ChangeNotifierProvider<UpdateService>.value(
          value: service,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showUpdateDialog(context),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await service.checkForUpdates();
      await tester.pumpAndSettle();

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Hay una versión nueva de Didacta'), findsOneWidget);
      expect(find.text('Novedades'), findsOneWidget);
      // La viñeta del CHANGELOG, sin el guion de Markdown delante.
      expect(find.text('Algo nuevo'), findsOneWidget);
      expect(find.byKey(const Key('update-later')), findsOneWidget);
      expect(find.byKey(const Key('update-now')), findsOneWidget);
    });

    testWidgets('descargar lo deja listo para cerrar e instalar', (
      tester,
    ) async {
      final service = serviceWith(withRelease());
      await tester.pumpWidget(
        ChangeNotifierProvider<UpdateService>.value(
          value: service,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showUpdateDialog(context),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await service.checkForUpdates();
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('update-now')));
      await tester.pumpAndSettle();

      expect(find.text('Cerrar e instalar'), findsOneWidget);
      expect(find.textContaining('volverá a abrirse'), findsOneWidget);
    });
  });
}
