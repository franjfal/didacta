/// Descargar la actualización, comprobarla y ponerla en su sitio.
///
/// La regla que gobierna todo este fichero: **una actualización que falla
/// tiene que dejar la versión anterior funcionando.** Didacta es la
/// herramienta con la que alguien da clase mañana; una instalación a medias
/// no es un incidente, es una clase sin material. De ahí vienen las tres
/// decisiones:
///
/// **Se comprueba antes de tocar nada.** El SHA-256 del fichero descargado
/// contra el del manifiesto, y el contenido del paquete --que dentro hay de
/// verdad una aplicación-- antes de mover un solo fichero de la instalación
/// que funciona. Un binario cuyo checksum no cuadra no se instala nunca, y da
/// igual de dónde venga.
///
/// **No se sustituye a sí misma.** Un ejecutable no puede reemplazarse
/// mientras está corriendo --en Windows el fichero está bloqueado, y en macOS
/// borrar el `.app` bajo los pies de la aplicación la deja sin sus
/// recursos--, así que la sustitución la hace un script externo que espera a
/// que Didacta termine. Es lo que hacen Sparkle y las demás: el programa que
/// se actualiza no puede ser el que actualiza.
///
/// **Hay marcha atrás.** La versión anterior se aparta, no se borra, y solo
/// desaparece cuando la nueva ya está en su sitio. Si algo falla entre medias,
/// el script la devuelve.
library;

import 'dart:async';

import '../model/update_manifest.dart';
import 'release_channel.dart';
import 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart'
    as platform;

/// Un fichero descargado y ya comprobado.
class DownloadedUpdate {
  const DownloadedUpdate({
    required this.path,
    required this.asset,
    required this.manifest,
  });

  /// Dónde ha quedado, en una carpeta temporal.
  final String path;

  final UpdateAsset asset;
  final UpdateManifest manifest;
}

/// Cómo va la descarga.
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});

  final int received;

  /// `0` si el servidor no dijo cuánto pesa. El manifiesto sí lo sabe, así
  /// que la interfaz tiene de dónde sacarlo igualmente.
  final int total;

  double? get fraction =>
      total <= 0 ? null : (received / total).clamp(0.0, 1.0).toDouble();
}

/// Lo que se puede hacer en este sistema.
abstract class UpdateInstaller {
  /// Si aquí se puede instalar una actualización.
  ///
  /// Falso en web, y falso en un Linux donde Didacta no venga de un
  /// AppImage: allí la instalación la gobierna el gestor de paquetes, y
  /// sobrescribirle los ficheros sería romperle la base de datos.
  bool get supported;

  /// Por qué no se puede, cuando no se puede. Se enseña tal cual.
  String? get unsupportedReason;

  /// Descarga el asset y **comprueba su SHA-256** antes de devolverlo.
  ///
  /// Lanza [UpdateException] con [UpdateProblem.checksumMismatch] si no
  /// cuadra, y borra el fichero: dejarlo ahí sería dejar un binario sin
  /// verificar en el disco de alguien.
  Future<DownloadedUpdate> download({
    required ReleaseChannel channel,
    required UpdateAsset asset,
    required UpdateManifest manifest,
    void Function(DownloadProgress)? onProgress,
    Future<void>? cancelled,
  });

  /// Deja preparada la sustitución y devuelve sin haberla hecho.
  ///
  /// Quien llame tiene que cerrar la aplicación a continuación: el script ya
  /// está esperando a que este proceso termine. Separarlo en dos pasos es lo
  /// que permite que la interfaz avise («Didacta se va a cerrar») en lugar de
  /// desaparecer de golpe.
  Future<void> stage(DownloadedUpdate update);

  /// Lanza la sustitución y termina este proceso.
  Never applyAndExit();

  /// Limpia lo que se hubiera descargado y no se vaya a usar.
  Future<void> discard(DownloadedUpdate update);
}

/// El de este sistema.
UpdateInstaller createInstaller() => platform.createInstaller();
