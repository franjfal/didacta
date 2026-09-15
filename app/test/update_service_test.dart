/// Lo que hace el actualizador cuando las cosas van mal.
///
/// Que funcione el camino bueno se comprueba en dos tests; el resto del
/// fichero es el camino malo, porque ahí es donde está el requisito de
/// verdad: **un fallo buscando actualizaciones nunca puede impedir usar
/// Didacta.** Sin red, con el token revocado, con GitHub caído o con una
/// descarga corrupta, la aplicación tiene que seguir exactamente igual.
///
/// El canal es el de verdad --se le cambia el `http.Client` por uno de
/// mentira-- así que esto prueba también el manejo de códigos de estado, que
/// es donde estaba la distinción entre «no tienes acceso» y «no hay
/// releases»: GitHub responde 404 a las dos cosas.
library;

import 'dart:convert';

import 'package:didacta_app/data/app_info.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/release_channel.dart';
import 'package:didacta_app/data/update_installer.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String hash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

const AppInfo installed = AppInfo(
  version: AppVersion(1, 4, 1),
  build: 141,
  packageName: 'es.uv.didacta',
  platform: UpdatePlatform.macos,
  architecture: 'arm64',
);

String manifestBody({String version = '1.4.2'}) => jsonEncode({
  'version': version,
  'build': 142,
  'tag': 'v$version',
  'publishedAt': '2026-09-15T10:00:00Z',
  'releaseNotes': '- Algo nuevo',
  'assets': [
    {
      'platform': 'macos',
      'architecture': 'universal',
      'kind': 'update',
      'name': 'Didacta-$version-macos-universal.zip',
      'size': 12,
      'sha256': hash,
      'assetId': 77,
    },
  ],
});

String releaseBody({String tag = 'v1.4.2', bool withManifest = true}) =>
    jsonEncode({
      'tag_name': tag,
      'draft': false,
      'assets': [
        if (withManifest) {'name': 'latest.json', 'id': 5},
        {'name': 'Didacta-1.4.2-macos-universal.zip', 'id': 77},
      ],
    });

/// Un cliente que responde según la ruta. Lo que no esté, 404.
MockClient routed(Map<String, http.Response> routes) =>
    MockClient((request) async {
      for (final entry in routes.entries) {
        if (request.url.path.endsWith(entry.key)) return entry.value;
      }
      return http.Response('{"message":"Not Found"}', 404);
    });

/// Un instalador que no toca el disco.
class FakeInstaller implements UpdateInstaller {
  FakeInstaller({this.reason});

  final String? reason;
  bool staged = false;
  bool discarded = false;
  int applied = 0;
  UpdateException? failDownloadWith;

  @override
  bool get supported => reason == null;

  @override
  String? get unsupportedReason => reason;

  @override
  Future<DownloadedUpdate> download({
    required ReleaseChannel channel,
    required UpdateAsset asset,
    required UpdateManifest manifest,
    void Function(DownloadProgress)? onProgress,
    Future<void>? cancelled,
  }) async {
    if (failDownloadWith != null) throw failDownloadWith!;
    onProgress?.call(DownloadProgress(received: asset.size, total: asset.size));
    return DownloadedUpdate(
      path: '/tmp/${asset.name}',
      asset: asset,
      manifest: manifest,
    );
  }

  @override
  Future<void> stage(DownloadedUpdate update) async => staged = true;

  @override
  Never applyAndExit() {
    applied += 1;
    // En un test no se puede llamar a `exit`, así que se señala igual que
    // haría un fallo de lanzamiento y se comprueba que la interfaz lo cuenta.
    throw const UpdateException(
      UpdateProblem.installFailed,
      'aquí no se cierra el proceso',
    );
  }

  @override
  Future<void> discard(DownloadedUpdate update) async => discarded = true;
}

UpdateService serviceWith(
  http.Client client, {
  AppInfo info = installed,
  String token = 'gho_valido',
  UpdateInstaller? installer,
  Preferences? preferences,
  DateTime Function()? now,
}) => UpdateService(
  info: info,
  preferences: preferences ?? MemoryPreferences(),
  readToken: () async => token,
  openChannel: (token) => ReleaseChannel(
    owner: 'franjfal',
    repo: 'didacta_public',
    token: token,
    client: client,
  ),
  installer: installer ?? FakeInstaller(),
  now: now,
);

void main() {
  group('el camino bueno', () {
    test('hay una versión nueva', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
      );
      await service.checkForUpdates();
      expect(service.stage, UpdateStage.available);
      expect(service.hasUpdate, isTrue);
      expect(service.newVersion.toString(), '1.4.2');
      expect(service.asset!.assetId, 77);
      expect(service.problem, isNull);
    });

    test('la misma versión no es una actualización', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(
            manifestBody(version: '1.4.1'),
            200,
          ),
        }),
      );
      await service.checkForUpdates();
      expect(service.stage, UpdateStage.upToDate);
      expect(service.hasUpdate, isFalse);
    });

    test('una versión más vieja tampoco', () async {
      // Pasa si alguien publica un parche de una serie anterior.
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(
            manifestBody(version: '1.3.9'),
            200,
          ),
        }),
      );
      await service.checkForUpdates();
      expect(service.stage, UpdateStage.upToDate);
    });

    test('descargar deja la actualización lista', () async {
      final installer = FakeInstaller();
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
        installer: installer,
      );
      await service.checkForUpdates();
      await service.downloadUpdate();
      expect(service.stage, UpdateStage.ready);
      // Preparada **antes** de tocar nada: extraída, comprobada y con el
      // script escrito, con la versión que funciona todavía en su sitio.
      expect(installer.staged, isTrue);
      expect(service.progress!.fraction, 1.0);
    });

    test('«más tarde» tira lo descargado y lo sigue ofreciendo', () async {
      final installer = FakeInstaller();
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
        installer: installer,
      );
      await service.checkForUpdates();
      await service.downloadUpdate();
      await service.later();
      expect(installer.discarded, isTrue);
      expect(service.stage, UpdateStage.available);
    });
  });

  group('autorización', () {
    test('sin acceso al repositorio se dice claramente', () async {
      // GitHub responde 404 --no 403-- a un repositorio privado al que no se
      // llega, para no confirmar que existe. Nosotros sabemos que existe.
      final service = serviceWith(routed({}));
      await service.checkForUpdates();
      expect(service.stage, UpdateStage.failed);
      expect(service.problem!.problem, UpdateProblem.notAuthorised);
      expect(service.problem!.message, contains('no tiene acceso'));
      expect(service.problem!.message, contains('franjfal/didacta_public'));
    });

    test('con acceso pero sin releases no es un error', () async {
      final service = serviceWith(
        routed({'repos/franjfal/didacta_public': http.Response('{}', 200)}),
      );
      await service.checkForUpdates();
      expect(service.stage, UpdateStage.upToDate);
      expect(service.problem, isNull);
    });

    test('la autorización se comprueba aparte del login', () async {
      // Poder entrar en GitHub no es poder usar Didacta. Son dos preguntas y
      // alguien puede pasar la primera y no la segunda.
      final concedido = serviceWith(
        routed({'repos/franjfal/didacta_public': http.Response('{}', 200)}),
      );
      await concedido.checkAuthorisation();
      expect(concedido.authorised, isTrue);

      final denegado = serviceWith(routed({}));
      await denegado.checkAuthorisation();
      expect(denegado.authorised, isFalse);
    });

    test('sin poder preguntar, no se acusa a nadie', () async {
      // `null` y no `false`: decirle a alguien que no está autorizado cuando
      // lo que pasa es que no hay wifi es una acusación falsa.
      final service = serviceWith(
        MockClient((_) async => throw const SocketishError()),
      );
      await service.checkAuthorisation();
      expect(service.authorised, isNull);
    });

    test('sin haber entrado tampoco', () async {
      final service = serviceWith(routed({}), token: '');
      await service.checkAuthorisation();
      expect(service.authorised, isNull);
    });

    test('una comprobación que llega al final ya responde que sí', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
      );
      await service.checkForUpdates();
      expect(service.authorised, isTrue);
    });

    test('y una que falla por acceso responde que no', () async {
      final service = serviceWith(routed({}));
      await service.checkForUpdates();
      expect(service.authorised, isFalse);
    });

    test('al salir se olvida lo de la cuenta anterior', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
      );
      await service.checkForUpdates();
      expect(service.hasUpdate, isTrue);

      service.forgetAccount();
      // La siguiente persona puede ser otra con otros permisos: arrastrar lo
      // que se sabía de la anterior sería enseñarle algo que no es suyo.
      expect(service.authorised, isNull);
      expect(service.hasUpdate, isFalse);
      expect(service.stage, UpdateStage.idle);
    });

    test('token revocado o caducado', () async {
      final service = serviceWith(
        routed({'releases/latest': http.Response('{}', 401)}),
      );
      await service.checkForUpdates();
      expect(service.problem!.problem, UpdateProblem.tokenInvalid);
      expect(service.problem!.message, contains('Vuelve a entrar'));
    });

    test('autorización de la OAuth App retirada (403)', () async {
      final service = serviceWith(
        routed({'releases/latest': http.Response('{}', 403)}),
      );
      await service.checkForUpdates();
      expect(service.problem!.problem, UpdateProblem.notAuthorised);
    });

    test('sin haber entrado en GitHub', () async {
      final service = serviceWith(routed({}), token: '');
      await service.checkForUpdates();
      expect(service.problem!.problem, UpdateProblem.tokenInvalid);
      expect(service.problem!.message, contains('Entra en GitHub'));
    });
  });

  group('la red y GitHub', () {
    test('sin conexión', () async {
      final service = serviceWith(
        MockClient((_) async => throw const SocketishError()),
      );
      await service.checkForUpdates();
      expect(service.stage, UpdateStage.failed);
      expect(service.problem!.problem, UpdateProblem.offline);
    });

    test('GitHub caído', () async {
      final service = serviceWith(
        routed({'releases/latest': http.Response('boom', 503)}),
      );
      await service.checkForUpdates();
      expect(service.problem!.problem, UpdateProblem.githubDown);
    });

    test('límite de peticiones', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(
            '{}',
            403,
            headers: {'x-ratelimit-remaining': '0'},
          ),
        }),
      );
      await service.checkForUpdates();
      expect(service.problem!.problem, UpdateProblem.rateLimited);
    });

    test('un release sin manifiesto', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(
            releaseBody(withManifest: false),
            200,
          ),
        }),
      );
      await service.checkForUpdates();
      expect(service.problem!.problem, UpdateProblem.brokenRelease);
    });

    test('un manifiesto que no se entiende', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response('no soy json', 200),
        }),
      );
      await service.checkForUpdates();
      expect(service.problem!.problem, UpdateProblem.brokenRelease);
    });
  });

  group('la comprobación silenciosa no molesta', () {
    test('un fallo de red en la automática no se enseña', () async {
      // El requisito entero: quedarse sin red no puede sacar un aviso en el
      // arranque, y desde luego no puede impedir usar Didacta.
      final service = serviceWith(
        MockClient((_) async => throw const SocketishError()),
      );
      await service.checkForUpdates(silent: true);
      expect(service.stage, UpdateStage.idle);
      expect(service.problem, isNull);
    });

    test('sin acceso tampoco, en la automática', () async {
      final service = serviceWith(routed({}));
      await service.checkForUpdates(silent: true);
      expect(service.stage, UpdateStage.idle);
      expect(service.problem, isNull);
    });
  });

  group('cada siete días', () {
    test('recién mirado no se vuelve a mirar', () async {
      var asked = 0;
      final preferences = MemoryPreferences()..checked = DateTime(2026, 9, 14);
      final service = serviceWith(
        MockClient((_) async {
          asked += 1;
          return http.Response('{}', 404);
        }),
        preferences: preferences,
        now: () => DateTime(2026, 9, 15),
      );
      await service.checkIfDue();
      expect(asked, 0);
    });

    test('pasada la semana sí', () async {
      var asked = 0;
      final preferences = MemoryPreferences()..checked = DateTime(2026, 9, 1);
      final service = serviceWith(
        MockClient((_) async {
          asked += 1;
          return http.Response('{}', 404);
        }),
        preferences: preferences,
        now: () => DateTime(2026, 9, 15),
      );
      await service.checkIfDue();
      expect(asked, greaterThan(0));
    });

    test('la primera vez, sí', () async {
      var asked = 0;
      final service = serviceWith(
        MockClient((_) async {
          asked += 1;
          return http.Response('{}', 404);
        }),
        preferences: MemoryPreferences(),
      );
      await service.checkIfDue();
      expect(asked, greaterThan(0));
    });

    test('la fecha se guarda aunque no hubiera nada nuevo', () async {
      // Lo que se evita es volver a preguntar mañana, y eso vale igual si la
      // respuesta fue «no hay ninguno».
      final preferences = MemoryPreferences();
      final service = serviceWith(
        routed({'repos/franjfal/didacta_public': http.Response('{}', 200)}),
        preferences: preferences,
        now: () => DateTime(2026, 9, 15),
      );
      await service.checkForUpdates();
      expect(await preferences.lastUpdateCheck(), DateTime(2026, 9, 15));
    });

    test('un fallo no adelanta el reloj', () async {
      // Si no se pudo comprobar, no se ha comprobado: hay que volver a
      // intentarlo en el siguiente arranque y no dentro de siete días.
      final preferences = MemoryPreferences();
      final service = serviceWith(
        MockClient((_) async => throw const SocketishError()),
        preferences: preferences,
      );
      await service.checkForUpdates(silent: true);
      expect(await preferences.lastUpdateCheck(), isNull);
    });
  });

  group('la descarga y la instalación', () {
    test(
      'un sistema donde no se puede instalar lo dice y no descarga',
      () async {
        final installer = FakeInstaller(
          reason: 'Didacta no viene de un AppImage.',
        );
        final service = serviceWith(
          routed({
            'releases/latest': http.Response(releaseBody(), 200),
            'releases/assets/5': http.Response(manifestBody(), 200),
          }),
          installer: installer,
        );
        await service.checkForUpdates();
        expect(service.canInstall, isFalse);
        await service.downloadUpdate();
        expect(service.stage, UpdateStage.failed);
        expect(service.problem!.message, contains('AppImage'));
        expect(installer.staged, isFalse);
      },
    );

    test('sin artefacto para este sistema', () async {
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
        info: const AppInfo(
          version: AppVersion(1, 4, 1),
          build: 141,
          packageName: 'es.uv.didacta',
          platform: UpdatePlatform.linux,
          architecture: 'x64',
        ),
      );
      await service.checkForUpdates();
      expect(service.asset, isNull);
      await service.downloadUpdate();
      expect(service.problem!.problem, UpdateProblem.noAssetForPlatform);
    });

    test('un checksum que no cuadra deja el estado en fallo', () async {
      final installer = FakeInstaller()
        ..failDownloadWith = const UpdateException(
          UpdateProblem.checksumMismatch,
          'no coincide',
        );
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
        installer: installer,
      );
      await service.checkForUpdates();
      await service.downloadUpdate();
      expect(service.stage, UpdateStage.failed);
      expect(service.problem!.problem, UpdateProblem.checksumMismatch);
      // Y no se preparó nada: la versión instalada sigue intacta.
      expect(installer.staged, isFalse);
    });

    test('cancelar devuelve a «hay una versión nueva», no a fallo', () async {
      final installer = FakeInstaller()
        ..failDownloadWith = const UpdateException(
          UpdateProblem.cancelled,
          'cancelada',
        );
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
        installer: installer,
      );
      await service.checkForUpdates();
      await service.downloadUpdate();
      expect(service.stage, UpdateStage.available);
    });

    test('instalar sin haber descargado no hace nada raro', () async {
      final service = serviceWith(routed({}));
      await service.installUpdate();
      expect(service.stage, UpdateStage.failed);
      expect(service.problem!.problem, UpdateProblem.installFailed);
    });

    test('si lanzar la instalación falla, se cuenta', () async {
      // La versión anterior sigue en su sitio: nada se ha tocado todavía.
      final installer = FakeInstaller();
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
        installer: installer,
      );
      await service.checkForUpdates();
      await service.downloadUpdate();
      await service.installUpdate();
      expect(installer.applied, 1);
      expect(service.stage, UpdateStage.failed);
      expect(service.problem!.problem, UpdateProblem.installFailed);
    });
  });

  group('cómo fue la anterior', () {
    // El paso que cierra el círculo. Quien sustituye los ficheros es un
    // script externo, y para cuando termina, la aplicación que lo lanzó ya no
    // existe para enterarse de si salió.

    test('sin nada apuntado, no se dice nada', () async {
      final service = serviceWith(routed({}));
      await service.load();
      expect(service.outcome, isNull);
    });

    test('la versión que arrancó es la apuntada: salió bien', () async {
      final preferences = MemoryPreferences()..pending = '1.4.1';
      final service = serviceWith(routed({}), preferences: preferences);
      await service.load();
      expect(service.outcome!.succeeded, isTrue);
      expect(service.outcome!.installed.toString(), '1.4.1');
      // Y la nota se borra: si no, el fallo se contaría en cada arranque.
      expect(await preferences.pendingUpdate(), isNull);
    });

    test('arrancó la de antes: la sustitución falló', () async {
      // El caso que justifica todo esto: alguien creyendo que tiene la 1.4.2
      // cuando lo que se está ejecutando es la 1.4.1.
      final preferences = MemoryPreferences()..pending = '1.4.2';
      final service = serviceWith(routed({}), preferences: preferences);
      await service.load();
      expect(service.outcome!.succeeded, isFalse);
      expect(service.outcome!.installed.toString(), '1.4.2');
      expect(service.outcome!.running.toString(), '1.4.1');
      expect(await preferences.pendingUpdate(), isNull);
    });

    test('una versión más nueva de la apuntada también vale', () async {
      // Pasa si alguien instala a mano por encima mientras tanto.
      final preferences = MemoryPreferences()..pending = '1.0.0';
      final service = serviceWith(routed({}), preferences: preferences);
      await service.load();
      expect(service.outcome!.succeeded, isTrue);
    });

    test('una nota ilegible se ignora, no se cuenta como fallo', () async {
      final preferences = MemoryPreferences()..pending = 'lo que sea';
      final service = serviceWith(routed({}), preferences: preferences);
      await service.load();
      expect(service.outcome, isNull);
    });

    test('instalar apunta la versión antes de cerrar', () async {
      final preferences = MemoryPreferences();
      final service = serviceWith(
        routed({
          'releases/latest': http.Response(releaseBody(), 200),
          'releases/assets/5': http.Response(manifestBody(), 200),
        }),
        preferences: preferences,
      );
      await service.checkForUpdates();
      await service.downloadUpdate();
      await service.installUpdate();
      // El instalador de mentira falla al lanzar, así que la nota se borra:
      // no se ha cerrado nada y contarlo sería contar un fallo que no hubo.
      expect(await preferences.pendingUpdate(), isNull);
      expect(service.stage, UpdateStage.failed);
    });
  });

  test('en web no se ofrece actualizar', () async {
    final service = serviceWith(
      routed({}),
      info: const AppInfo(
        version: AppVersion(1, 4, 1),
        build: 141,
        packageName: 'es.uv.didacta',
        platform: null,
        architecture: 'web',
      ),
    );
    expect(service.canInstall, isFalse);
    await service.checkIfDue();
    // Ni siquiera pregunta: no hay nada que ofrecer.
    expect(service.stage, UpdateStage.idle);
  });
}

/// Lo que lanza un cliente HTTP cuando no hay red.
class SocketishError implements Exception {
  const SocketishError();

  @override
  String toString() => 'SocketException: Failed host lookup';
}
