/// La actualización de verdad, contra el repositorio de verdad.
///
/// No es un test unitario y por eso no vive en `test/`: **sale a la red**,
/// habla con GitHub, se descarga los 27 MB del release publicado y prepara la
/// sustitución. Lo que prueba es justo lo que ningún test con un cliente
/// falso puede probar: que el contrato con la API de GitHub es el que
/// creemos, que el `assetId` del manifiesto descarga de verdad, y que lo
/// descargado cuadra con el SHA-256 publicado.
///
/// Sin token: el repositorio es público, y que se pueda actualizar sin
/// credencial es parte de lo que hay que comprobar.
///
/// **No toca la Didacta instalada.** Se le pasa la ruta de una copia, y es
/// esa la que se sustituye. Lo lanza `packaging/e2e-macos.sh`, que prepara la
/// copia, ejecuta esto y comprueba después que la copia es la versión nueva.
///
///     DIDACTA_E2E_APP=/tmp/e2e/Didacta.app \
///       flutter test tool/e2e_update.dart
///
/// El paso que falta para que sea el flujo entero --pulsar «Actualizar
/// ahora» en la ventana-- es el único que necesita una persona delante, y
/// está cubierto por `test/update_ui_test.dart` contra el mismo servicio.
library;

import 'dart:io';

import 'package:didacta_app/data/app_info.dart';
import 'package:didacta_app/data/release_channel.dart';
import 'package:didacta_app/data/update_installer.dart';
import 'package:didacta_app/model/app_version.dart';
import 'package:didacta_app/model/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

String get _installed {
  final path = Platform.environment['DIDACTA_E2E_APP'] ?? '';
  if (path.isEmpty) {
    throw StateError(
      'Falta DIDACTA_E2E_APP: la ruta de la **copia** que se va a sustituir.\n'
      'No se apunta a la Didacta que estés usando.',
    );
  }
  return path;
}

String get _owner => Platform.environment['DIDACTA_E2E_OWNER'] ?? 'franjfal';
String get _repo => Platform.environment['DIDACTA_E2E_REPO'] ?? 'didacta';

/// La versión que la copia dice ser, leída de su `Info.plist`.
AppVersion? versionOf(String bundle) {
  final result = Process.runSync('/usr/libexec/PlistBuddy', [
    '-c',
    'Print CFBundleShortVersionString',
    '$bundle/Contents/Info.plist',
  ]);
  if (result.exitCode != 0) return null;
  return AppVersion.tryParse('${result.stdout}'.trim());
}

void main() {
  late ReleaseChannel channel;

  setUpAll(() {
    channel = ReleaseChannel(owner: _owner, repo: _repo);
  });

  tearDownAll(() => channel.close());

  test('1 · el repositorio se lee sin ninguna credencial', () async {
    // Lo que se ganó al abrir el código, comprobado contra GitHub y no
    // leyendo el código: sin `Authorization:`, la API contesta.
    final publicado = await channel.latest();
    expect(publicado, isNotNull, reason: 'no hay ningún release publicado');
    stdout.writeln('  $_owner/$_repo se lee sin token: sí');
  });

  test('2 · el release publicado trae un manifiesto que se entiende', () async {
    final manifest = await channel.latest();
    expect(manifest, isNotNull, reason: 'no hay ningún release publicado');
    stdout.writeln(
      '  publicada: ${manifest!.version} (build ${manifest.build}), '
      '${manifest.assets.length} artefactos',
    );
    for (final asset in manifest.assets) {
      stdout.writeln(
        '    ${asset.platform.id} ${asset.architecture} ${asset.kind.id}  '
        '${asset.name}  ${asset.sha256.substring(0, 12)}…',
      );
    }
  });

  test('3 · la copia instalada es más vieja que la publicada', () async {
    final installed = versionOf(_installed);
    expect(installed, isNotNull, reason: 'no encuentro $_installed');
    final manifest = (await channel.latest())!;
    expect(
      manifest.version > installed!,
      isTrue,
      reason:
          'la copia dice ser $installed y lo publicado es ${manifest.version}: '
          'no hay nada que actualizar, así que esta prueba no probaría nada',
    );
    stdout.writeln('  $installed → ${manifest.version}');
  });

  test(
    '5 · se descarga, y el SHA-256 cuadra',
    () async {
      final info = await AppInfo.load();
      final manifest = (await channel.latest())!;
      final asset = manifest.updateFor(
        info.platform ?? UpdatePlatform.macos,
        info.architecture,
      );
      expect(asset, isNotNull, reason: 'no hay artefacto para este sistema');

      final installer = createInstaller(installedAt: _installed);
      expect(installer.supported, isTrue, reason: installer.unsupportedReason);

      var last = -1;
      final downloaded = await installer.download(
        channel: channel,
        asset: asset!,
        manifest: manifest,
        onProgress: (progress) {
          final percent = ((progress.fraction ?? 0) * 100).round();
          // Cada 20%, para no llenar el log con mil líneas.
          if (percent >= last + 20) {
            last = percent;
            stdout.writeln('    $percent%  ${progress.received} bytes');
          }
        },
      );

      // Que haya llegado hasta aquí **es** la comprobación: `download` borra el
      // fichero y lanza si el hash no cuadra.
      final file = File(downloaded.path);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), asset.size);
      stdout.writeln('  descargado y verificado: ${downloaded.path}');

      // Y la sustitución, preparada: se extrae, se comprueba que dentro hay una
      // aplicación de verdad y se escribe el script. Hasta aquí, la copia sigue
      // siendo la vieja.
      await installer.stage(downloaded);
      expect(
        versionOf(_installed).toString(),
        isNot(manifest.version.toString()),
        reason: 'preparar no puede haber sustituido nada todavía',
      );
      stdout.writeln('  preparada. La copia sigue siendo la de antes.');

      // El script se deja escrito para que lo lance el guion de fuera, que es
      // quien puede esperar a que este proceso termine. Llamar aquí a
      // `applyAndExit` mataría el propio test antes de contar nada.
      final script = File('${file.parent.path}/instalar.sh');
      expect(script.existsSync(), isTrue, reason: 'no se escribió el script');
      File(
        Platform.environment['DIDACTA_E2E_SCRIPT'] ?? '/tmp/didacta-e2e-script',
      ).writeAsStringSync('${script.path}\n');
      stdout.writeln('  script listo: ${script.path}');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
