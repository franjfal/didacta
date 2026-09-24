/// Qué versión de Didacta es esta, y dónde se está ejecutando.
///
/// La versión sale de `pubspec.yaml` y de ningún otro sitio. No está escrita
/// aquí, ni generada en un fichero Dart, ni pasada por `--dart-define`: la lee
/// `package_info_plus` **del paquete ya construido** --el `Info.plist` en
/// macOS, el `version.json` de los assets en Windows y en Linux-- que es lo
/// único que garantiza que lo que la aplicación dice de sí misma es lo que de
/// verdad se instaló. Una constante en el código puede quedarse atrás de la
/// compilación; el `Info.plist` del binario que se está ejecutando, no.
///
/// La arquitectura se saca de `Platform.version`, que termina en el objetivo
/// con el que se compiló el runtime de Dart (`macos_arm64`, `windows_x64`).
/// No hay una API que la dé, y el resto de caminos --preguntar al sistema por
/// `uname`, mirar variables de entorno-- responden por la *máquina* y no por
/// el *binario*, que no es lo mismo: una Didacta x64 bajo Rosetta en un Mac
/// con Apple Silicon tiene que decir que es x64, porque es el artefacto x64
/// el que le sirve.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../model/app_version.dart';
import '../model/update_manifest.dart';
import 'app_info_stub.dart' if (dart.library.io) 'app_info_io.dart' as host;

/// Lo que esta copia de Didacta sabe de sí misma.
class AppInfo {
  const AppInfo({
    required this.version,
    required this.build,
    required this.packageName,
    required this.platform,
    required this.architecture,
  });

  /// La versión instalada.
  final AppVersion version;

  /// El `+BUILD` de `pubspec.yaml`.
  final int build;

  /// `io.github.franjfal.didacta`.
  final String packageName;

  /// `null` en web, donde no hay nada que actualizar: la página se recarga.
  final UpdatePlatform? platform;

  /// `arm64`, `x64`, o `universal` si no se pudo determinar.
  final String architecture;

  /// Si aquí tiene sentido buscar actualizaciones.
  bool get canUpdate => platform != null;

  /// Para enseñar: `1.4.2 (142) · macOS arm64`.
  String get describe {
    final where = platform == null
        ? 'web'
        : '${_platformName(platform!)} $architecture';
    return '$version ($build) · $where';
  }

  static String _platformName(UpdatePlatform value) => switch (value) {
    UpdatePlatform.macos => 'macOS',
    UpdatePlatform.windows => 'Windows',
    UpdatePlatform.linux => 'Linux',
  };

  /// Lee la versión del paquete construido.
  ///
  /// Nunca lanza. Si `package_info_plus` no responde --pasa en un test de
  /// widget sin canal de plataforma-- devuelve `0.0.0`, que es una versión
  /// que siempre es menor que cualquier publicada y por tanto no esconde
  /// ninguna actualización. Fallar aquí dejaría la aplicación sin arrancar
  /// por no poder leer un número.
  static Future<AppInfo> load() async {
    var version = const AppVersion(0, 0, 0);
    var build = 0;
    var package = 'io.github.franjfal.didacta';
    try {
      final info = await PackageInfo.fromPlatform();
      version = AppVersion.tryParse(info.version) ?? version;
      build = int.tryParse(info.buildNumber) ?? 0;
      if (info.packageName.isNotEmpty) package = info.packageName;
    } catch (_) {
      // Sin canal de plataforma: se sigue con 0.0.0.
    }
    return AppInfo(
      version: version,
      build: build,
      packageName: package,
      platform: kIsWeb ? null : host.currentPlatform(),
      architecture: kIsWeb ? 'web' : host.currentArchitecture(),
    );
  }
}
