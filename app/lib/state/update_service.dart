/// Buscar, descargar e instalar una versión nueva de Didacta.
///
/// Separado de la interfaz a propósito, y con una regla por encima de todas:
/// **fallar buscando actualizaciones nunca puede impedir usar Didacta.** De
/// aquí no sale ninguna excepción. Lo que falla se guarda en [problem] y la
/// aplicación sigue exactamente igual, porque quedarse sin red no puede
/// significar quedarse sin poder dar clase.
///
/// La comprobación automática es cada siete días y en segundo plano, después
/// de que la aplicación esté en pie. Ni al arrancar --que retrasaría la
/// primera pantalla por una petición que a nadie le urge-- ni cada vez, que
/// es cómo un aviso útil se convierte en ruido que se cierra sin leer.
///
/// Y si no hay nada nuevo, no se dice nada. Un «ya estás al día» que nadie ha
/// pedido es una interrupción.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_info.dart';
import '../data/preferences.dart';
import '../data/release_channel.dart';
import '../data/update_installer.dart';
import '../model/app_version.dart';
import '../model/update_manifest.dart';

/// El repositorio desde el que se distribuye.
///
/// Configurable al compilar para poder probar contra otro sin tocar código,
/// pero con el de verdad por defecto: una constante vacía aquí sería una
/// aplicación que no sabe de dónde actualizarse si alguien compila sin la
/// define, y eso es un fallo silencioso.
const String releaseOwner = String.fromEnvironment(
  'DIDACTA_RELEASE_OWNER',
  defaultValue: 'franjfal',
);
const String releaseRepo = String.fromEnvironment(
  'DIDACTA_RELEASE_REPO',
  defaultValue: 'didacta',
);

/// En qué punto está.
enum UpdateStage {
  /// Nada que contar.
  idle,

  /// Preguntando a GitHub.
  checking,

  /// Se preguntó y no hay nada nuevo.
  upToDate,

  /// Hay una versión nueva esperando a que alguien diga que sí.
  available,

  downloading,

  /// Descargada, comprobada y lista para sustituir.
  ready,

  /// Se está sustituyendo; la aplicación va a cerrarse.
  installing,

  /// Algo falló. [UpdateService.problem] dice qué.
  failed,
}

/// Cómo acabó la actualización anterior.
class UpdateOutcome {
  const UpdateOutcome({
    required this.installed,
    required this.succeeded,
    this.running,
  });

  /// La versión que se estaba instalando.
  final AppVersion installed;

  final bool succeeded;

  /// La que de verdad arrancó, cuando no salió.
  final AppVersion? running;
}

class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.info,
    required this.preferences,
    ReleaseChannel Function()? openChannel,
    UpdateInstaller? installer,
    DateTime Function()? now,
    this.owner = releaseOwner,
    this.repo = releaseRepo,
  }) : _openChannel =
           openChannel ??
           (() => ReleaseChannel(owner: releaseOwner, repo: releaseRepo)),
       installer = installer ?? createInstaller(),
       _now = now ?? DateTime.now;

  /// Cada cuánto se mira sola.
  static const Duration interval = Duration(days: 7);

  final AppInfo info;
  final Preferences preferences;
  final UpdateInstaller installer;
  final String owner;
  final String repo;

  final ReleaseChannel Function() _openChannel;
  final DateTime Function() _now;

  UpdateStage _stage = UpdateStage.idle;
  UpdateStage get stage => _stage;

  UpdateException? _problem;

  /// Lo último que salió mal, si salió algo.
  UpdateException? get problem => _problem;

  UpdateManifest? _manifest;

  /// Lo que hay publicado, si se llegó a leer.
  UpdateManifest? get manifest => _manifest;

  DownloadedUpdate? _downloaded;

  DownloadProgress? _progress;
  DownloadProgress? get progress => _progress;

  DateTime? _lastCheck;
  DateTime? get lastCheck => _lastCheck;

  /// Cómo fue la actualización anterior, si hubo una.
  ///
  /// Se rellena al arrancar comparando la versión que se está ejecutando con
  /// la que se apuntó antes de cerrar. Es el paso que cierra el círculo: sin
  /// esto, una sustitución que falló deja a alguien creyendo que tiene una
  /// versión que no tiene.
  UpdateOutcome? _outcome;
  UpdateOutcome? get outcome => _outcome;

  bool _bannerDismissed = false;

  /// Si toca enseñar la franja de aviso de arriba.
  ///
  /// Separado de [hasUpdate] a propósito: cerrar el aviso no es decir que no
  /// se quiere actualizar, es decir «ahora no». La versión sigue estando y
  /// Ajustes la sigue ofreciendo; lo que no vuelve es la franja, hasta que
  /// se publique otra versión distinta.
  bool get showBanner => hasUpdate && canInstall && !_bannerDismissed;

  /// Quitar la franja sin olvidar que hay versión nueva.
  void dismissBanner() {
    _bannerDismissed = true;
    notifyListeners();
  }

  Completer<void>? _cancel;

  /// Si hay una versión nueva que además se puede instalar aquí.
  bool get hasUpdate {
    final published = _manifest;
    if (published == null) return false;
    return published.version > info.version;
  }

  /// La versión publicada, cuando es más nueva que ésta.
  AppVersion? get newVersion => hasUpdate ? _manifest!.version : null;

  /// El artefacto que le toca a esta máquina, si lo hay.
  UpdateAsset? get asset {
    final published = _manifest;
    final platform = info.platform;
    if (published == null || platform == null) return null;
    return published.updateFor(platform, info.architecture);
  }

  /// Si aquí se puede instalar sola.
  bool get canInstall => installer.supported && info.canUpdate;

  /// Por qué no, cuando no.
  String? get cannotInstallReason => info.canUpdate
      ? installer.unsupportedReason
      : 'En el navegador no hay nada que actualizar.';

  /// Lee cuándo se miró por última vez, y cómo fue la última actualización.
  ///
  /// Se llama al arrancar, y es aquí donde se cierra el círculo de la
  /// actualización anterior: quien sustituye los ficheros es un script
  /// externo, y para cuando termina, la aplicación que lo lanzó ya no existe
  /// para enterarse de si salió. Lo que sí queda es una nota en las
  /// preferencias, y la versión que se está ejecutando ahora.
  Future<void> load() async {
    _lastCheck = await preferences.lastUpdateCheck();

    final pending = AppVersion.tryParse(await preferences.pendingUpdate());
    if (pending != null) {
      // La nota se borra pase lo que pase: si no, un fallo se contaría en
      // cada arranque a partir de ahora.
      await preferences.setPendingUpdate(null);
      _outcome = info.version >= pending
          ? UpdateOutcome(installed: pending, succeeded: true)
          : UpdateOutcome(
              installed: pending,
              succeeded: false,
              running: info.version,
            );
    }
    notifyListeners();
  }

  /// Quitar el aviso de cómo fue la última actualización.
  void dismissOutcome() {
    _outcome = null;
    notifyListeners();
  }

  /// La comprobación automática, si toca.
  ///
  /// Silenciosa en los dos sentidos: no avisa de que está mirando, y si algo
  /// falla no se enseña nada. Un aviso de red que nadie pidió, en el
  /// arranque, es ruido.
  Future<void> checkIfDue() async {
    if (!info.canUpdate) return;
    final last = _lastCheck ?? await preferences.lastUpdateCheck();
    _lastCheck = last;
    if (last != null && _now().difference(last) < interval) return;
    await checkForUpdates(silent: true);
  }

  /// Mirar ahora.
  ///
  /// Con [silent], un fallo no se enseña: es la comprobación de fondo, y
  /// quedarse sin red no es algo de lo que haya que informar a nadie.
  Future<void> checkForUpdates({bool silent = false}) async {
    if (_stage == UpdateStage.checking ||
        _stage == UpdateStage.downloading ||
        _stage == UpdateStage.installing) {
      return;
    }
    _problem = null;
    _set(UpdateStage.checking);

    ReleaseChannel? channel;
    try {
      channel = _openChannel();
      final published = await channel.latest();

      // Se apunta la fecha aunque no hubiera nada: lo que se está evitando es
      // volver a preguntar mañana, y eso vale igual si la respuesta fue «no
      // hay ninguno».
      _lastCheck = _now();
      await preferences.setLastUpdateCheck(_lastCheck!);

      // Una versión distinta de la que se descartó vuelve a avisar: haber
      // dicho «ahora no» a la 1.4.2 no es haberlo dicho a la 1.5.0.
      if (published != null && published.version != _manifest?.version) {
        _bannerDismissed = false;
      }
      _manifest = published;
      if (published == null || published.version <= info.version) {
        _set(UpdateStage.upToDate);
        return;
      }
      _set(UpdateStage.available);
    } on UpdateException catch (thrown) {
      _manifest = null;
      if (silent) {
        // Sin ruido, pero sin fingir que se comprobó: la fecha no se toca, así
        // que se volverá a intentar en el siguiente arranque.
        _set(UpdateStage.idle);
        return;
      }
      _problem = thrown;
      _set(UpdateStage.failed);
    } catch (thrown) {
      _manifest = null;
      if (silent) {
        _set(UpdateStage.idle);
        return;
      }
      _problem = UpdateException(
        UpdateProblem.offline,
        'No se pudo comprobar si hay una versión nueva.',
        detail: '$thrown',
      );
      _set(UpdateStage.failed);
    } finally {
      channel?.close();
    }
  }

  /// Descargar la que hay, comprobando el SHA-256.
  Future<void> downloadUpdate() async {
    final published = _manifest;
    final wanted = asset;
    if (published == null || wanted == null) {
      _problem = const UpdateException(
        UpdateProblem.noAssetForPlatform,
        'Esta versión de Didacta no trae un paquete para tu sistema.',
      );
      _set(UpdateStage.failed);
      return;
    }
    if (!canInstall) {
      _problem = UpdateException(
        UpdateProblem.installFailed,
        cannotInstallReason ?? 'Aquí no se puede instalar automáticamente.',
      );
      _set(UpdateStage.failed);
      return;
    }
    if (published.needsFullReinstallFrom(info.version)) {
      _problem = UpdateException(
        UpdateProblem.installFailed,
        'Tu versión (${info.version}) es demasiado antigua para actualizarse '
        'sola a la ${published.version}. Descarga el instalador e instálala '
        'encima.',
      );
      _set(UpdateStage.failed);
      return;
    }

    _problem = null;
    _progress = DownloadProgress(received: 0, total: wanted.size);
    _cancel = Completer<void>();
    _set(UpdateStage.downloading);

    ReleaseChannel? channel;
    try {
      channel = _openChannel();
      final downloaded = await installer.download(
        channel: channel,
        asset: wanted,
        manifest: published,
        cancelled: _cancel!.future,
        onProgress: (value) {
          _progress = value;
          notifyListeners();
        },
      );
      // Extraer, comprobar la firma si procede y dejar el script escrito.
      // Todo esto pasa **antes** de tocar la instalación que funciona.
      await installer.stage(downloaded);
      _downloaded = downloaded;
      _set(UpdateStage.ready);
    } on UpdateException catch (thrown) {
      _problem = thrown;
      _set(
        thrown.problem == UpdateProblem.cancelled
            ? UpdateStage.available
            : UpdateStage.failed,
      );
    } catch (thrown) {
      _problem = UpdateException(
        UpdateProblem.downloadInterrupted,
        'No se pudo descargar la actualización.',
        detail: '$thrown',
      );
      _set(UpdateStage.failed);
    } finally {
      channel?.close();
      _cancel = null;
    }
  }

  /// Cerrar Didacta y dejar que el script la sustituya.
  ///
  /// No vuelve: el proceso termina aquí. Quien llama tiene que haber avisado
  /// antes de que la aplicación se va a cerrar.
  Future<void> installUpdate() async {
    final ready = _downloaded;
    if (ready == null) {
      _problem = const UpdateException(
        UpdateProblem.installFailed,
        'No hay ninguna actualización descargada.',
      );
      _set(UpdateStage.failed);
      return;
    }
    _set(UpdateStage.installing);
    try {
      // Apuntado **antes** de lanzar nada: a partir de la línea siguiente
      // este proceso puede desaparecer en cualquier momento, y entonces ya no
      // hay quien escriba nada.
      await preferences.setPendingUpdate(ready.manifest.version.toString());
      installer.applyAndExit();
    } on UpdateException catch (thrown) {
      // No se llegó a cerrar nada, así que la nota sobraría: dejarla haría
      // que el siguiente arranque contase un fallo que no hubo.
      await preferences.setPendingUpdate(null);
      _problem = thrown;
      _set(UpdateStage.failed);
    } catch (thrown) {
      await preferences.setPendingUpdate(null);
      _problem = UpdateException(
        UpdateProblem.installFailed,
        'No se pudo lanzar la actualización. Tu versión sigue intacta.',
        detail: '$thrown',
      );
      _set(UpdateStage.failed);
    }
  }

  /// Cancelar la descarga en curso.
  void cancel() {
    if (!(_cancel?.isCompleted ?? true)) _cancel!.complete();
  }

  /// Dejarlo para más tarde: se olvida lo descargado y se vuelve a lo de
  /// antes. La versión sigue publicada, así que se volverá a ofrecer.
  Future<void> later() async {
    final ready = _downloaded;
    _downloaded = null;
    _progress = null;
    if (ready != null) await installer.discard(ready);
    _set(hasUpdate ? UpdateStage.available : UpdateStage.idle);
  }

  /// Quitar el aviso de la pantalla sin olvidar que hay versión nueva.
  void dismiss() {
    if (_stage == UpdateStage.upToDate || _stage == UpdateStage.failed) {
      _set(UpdateStage.idle);
    }
  }

  void _set(UpdateStage value) {
    _stage = value;
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
