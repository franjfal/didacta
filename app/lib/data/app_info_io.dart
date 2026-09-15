/// Qué sistema y qué arquitectura, donde hay `dart:io`.
library;

import 'dart:io';

import '../model/update_manifest.dart';

UpdatePlatform? currentPlatform() {
  if (Platform.isMacOS) return UpdatePlatform.macos;
  if (Platform.isWindows) return UpdatePlatform.windows;
  if (Platform.isLinux) return UpdatePlatform.linux;
  // Android o iOS: no hay distribución por GitHub para ellos, y decir que sí
  // la hay llevaría a ofrecer un DMG en un teléfono.
  return null;
}

/// La arquitectura **del binario**, no la de la máquina.
///
/// `Platform.version` termina en el objetivo con el que se construyó el
/// runtime de Dart, entre comillas:
///
///     3.12.2 (stable) (Tue Jul 8 ...) on "macos_arm64"
///
/// Es la única forma de saberlo sin dependencias, y además responde a la
/// pregunta correcta: una copia x64 bajo Rosetta necesita el artefacto x64,
/// aunque la máquina sea arm64.
String currentArchitecture() {
  final match = RegExp(r'"(\w+)_(\w+)"').firstMatch(Platform.version);
  final arch = match?.group(2);
  return switch (arch) {
    'arm64' => 'arm64',
    'x64' => 'x64',
    'arm' => 'arm',
    'ia32' => 'ia32',
    // Desconocida: `universal` es el valor que hace que un artefacto
    // universal siga sirviendo, en vez de dejar la máquina sin ninguno.
    _ => 'universal',
  };
}
