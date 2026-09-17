/// La descarga de verdad: la que escribe en el disco y calcula el SHA-256.
///
/// No usa un instalador de mentira. Coge el de este sistema y le pasa un
/// cliente HTTP falso, así que lo que se comprueba es el código que de
/// verdad va a correr en la máquina de alguien: el streaming a fichero, el
/// hash incremental y, sobre todo, **qué pasa cuando no cuadra**.
///
/// La afirmación que sostiene el sistema entero es una: un binario cuyo
/// checksum no coincide no se instala nunca y además no se queda en el
/// disco. Si eso falla, todo lo demás --el repositorio privado, el token en
/// el llavero, la firma-- da igual.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:didacta_app/data/release_channel.dart';
import 'package:didacta_app/data/update_installer.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Un cuerpo de ejemplo, y su hash de verdad.
final List<int> payload = utf8.encode('esto es un paquete de Didacta' * 40);
final String payloadHash = sha256.convert(payload).toString();

UpdateAsset assetWith({
  required String sha,
  int size = 0,
  String name = 'Didacta-1.4.2-macos-universal.zip',
}) => UpdateAsset(
  platform: UpdatePlatform.macos,
  architecture: 'universal',
  kind: UpdateKind.update,
  name: name,
  size: size,
  sha256: sha,
  assetId: 77,
);

UpdateManifest manifestWith(UpdateAsset asset) => UpdateManifest(
  version: AppVersion.parse('1.4.2'),
  build: 142,
  publishedAt: DateTime.utc(2026, 9, 15),
  releaseNotes: '- Algo nuevo',
  assets: [asset],
);

ReleaseChannel channelServing(List<int> bytes, {int status = 200}) =>
    ReleaseChannel(
      owner: 'franjfal',
      repo: 'didacta',
      client: MockClient((request) async => http.Response.bytes(bytes, status)),
    );

void main() {
  final installer = createInstaller();

  test('una descarga buena se guarda, y se puede tirar', () async {
    final asset = assetWith(sha: payloadHash, size: payload.length);
    final downloaded = await installer.download(
      channel: channelServing(payload),
      asset: asset,
      manifest: manifestWith(asset),
    );

    final file = File(downloaded.path);
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), payload);
    // El nombre es el del asset: es lo que el instalador de Windows ejecuta.
    expect(file.path, endsWith(asset.name));

    await installer.discard(downloaded);
    expect(file.existsSync(), isFalse);
  });

  test('el progreso llega hasta el final', () async {
    final asset = assetWith(sha: payloadHash, size: payload.length);
    final seen = <DownloadProgress>[];
    final downloaded = await installer.download(
      channel: channelServing(payload),
      asset: asset,
      manifest: manifestWith(asset),
      onProgress: seen.add,
    );
    expect(seen, isNotEmpty);
    expect(seen.last.received, payload.length);
    expect(seen.last.fraction, 1.0);
    await installer.discard(downloaded);
  });

  test('un checksum que no cuadra no se instala **y no se queda**', () async {
    // El test que sostiene el sistema entero.
    const mentira =
        '0000000000000000000000000000000000000000000000000000000000000000';
    final asset = assetWith(sha: mentira, size: payload.length);

    try {
      await installer.download(
        channel: channelServing(payload),
        asset: asset,
        manifest: manifestWith(asset),
      );
      fail('debería haber rechazado la descarga');
    } on UpdateException catch (thrown) {
      expect(thrown.problem, UpdateProblem.checksumMismatch);
      expect(thrown.message, contains('no se va a instalar'));
      // El hash real va en el detalle: es lo que distingue una descarga
      // corrupta de un release mal publicado.
      expect(thrown.detail, contains(payloadHash));
      expect(thrown.detail, contains(mentira));
    }
  });

  test('y el fichero rechazado no se queda en el disco', () async {
    const mentira =
        '1111111111111111111111111111111111111111111111111111111111111111';
    final asset = assetWith(sha: mentira, size: payload.length);
    // La carpeta temporal lleva la versión del manifiesto en el nombre, así
    // que se puede comprobar que se borró entera.
    final before = Directory.systemTemp.listSync().length;
    await expectLater(
      installer.download(
        channel: channelServing(payload),
        asset: asset,
        manifest: manifestWith(asset),
      ),
      throwsA(isA<UpdateException>()),
    );
    // Nada acumulado: un binario sin verificar no se deja en el disco de
    // nadie, ni siquiera en un temporal.
    expect(
      Directory.systemTemp
          .listSync()
          .where((entry) => entry.path.contains('didacta-update-1.4.2'))
          .toList(),
      isEmpty,
    );
    expect(
      Directory.systemTemp.listSync().length,
      lessThanOrEqualTo(before + 1),
    );
  });

  test('una descarga cortada se detecta por el tamaño', () async {
    // El hash ya la cogería, pero el tamaño lo dice antes y más claro.
    final corto = payload.sublist(0, 10);
    final asset = assetWith(
      sha: sha256.convert(corto).toString(),
      size: payload.length, // el manifiesto dice que pesa más
    );
    await expectLater(
      installer.download(
        channel: channelServing(corto),
        asset: asset,
        manifest: manifestWith(asset),
      ),
      throwsA(
        isA<UpdateException>().having(
          (each) => each.problem,
          'problema',
          UpdateProblem.downloadInterrupted,
        ),
      ),
    );
  });

  test('si GitHub no da el fichero, no se inventa uno', () async {
    final asset = assetWith(sha: payloadHash);
    await expectLater(
      installer.download(
        channel: channelServing(payload, status: 404),
        asset: asset,
        manifest: manifestWith(asset),
      ),
      throwsA(isA<UpdateException>()),
    );
  });

  test('instalar sin haber preparado nada no hace nada', () {
    // `applyAndExit` mataría el proceso del test si hubiera algo preparado;
    // sin nada preparado tiene que quejarse, que es lo que se comprueba.
    expect(
      () => createInstaller().applyAndExit(),
      throwsA(
        isA<UpdateException>().having(
          (each) => each.problem,
          'problema',
          UpdateProblem.installFailed,
        ),
      ),
    );
  });
}
