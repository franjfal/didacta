/// En web no hay nada que instalar.
///
/// La página **es** la última versión: se sirve desde un sitio, y recargar
/// trae lo que haya. Ofrecer «actualizar» en un navegador sería ofrecer un
/// botón que no puede hacer nada distinto de F5.
library;

import '../model/update_manifest.dart';
import 'release_channel.dart';
import 'update_installer.dart';

class WebInstaller implements UpdateInstaller {
  const WebInstaller();

  @override
  bool get supported => false;

  @override
  String? get unsupportedReason =>
      'En el navegador no hace falta actualizar: recarga la página y ya '
      'tienes la última versión.';

  @override
  Future<DownloadedUpdate> download({
    required ReleaseChannel channel,
    required UpdateAsset asset,
    required UpdateManifest manifest,
    void Function(DownloadProgress)? onProgress,
    Future<void>? cancelled,
  }) async => throw const UpdateException(
    UpdateProblem.installFailed,
    'En el navegador no hay nada que descargar.',
  );

  @override
  Future<void> stage(DownloadedUpdate update) async =>
      throw const UpdateException(
        UpdateProblem.installFailed,
        'En el navegador no hay nada que instalar.',
      );

  @override
  Never applyAndExit() => throw const UpdateException(
    UpdateProblem.installFailed,
    'En el navegador no hay nada que instalar.',
  );

  @override
  Future<void> discard(DownloadedUpdate update) async {}
}

UpdateInstaller createInstaller({String? installedAt}) => const WebInstaller();
