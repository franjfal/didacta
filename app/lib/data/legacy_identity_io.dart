/// Traer y olvidar la carpeta de datos del nombre de antes, con disco.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/toolchain.dart';
import 'legacy_identity.dart';

/// La marca de que ya se trajo. Dentro de la carpeta de ahora: si alguien la
/// borra entera, lo de antes se vuelve a traer, que es lo que querría.
const String migratedMarker = '.didacta-legacy-migrated';

Future<void> bringLegacyData() async {
  try {
    final now = await getApplicationSupportDirectory();
    final before = legacyDataDirectory(_host, Platform.environment);
    if (before == null || _same(before, now.path)) return;
    final marker = File('${now.path}${Platform.pathSeparator}$migratedMarker');
    if (await marker.exists()) return;
    final old = Directory(before);
    if (await old.exists()) {
      final copied = await copyMissing(old, now);
      debugPrint('Didacta · traídos $copied ficheros de $before');
    }
    // También si no había nada: ya se ha mirado, y no hace falta volver a
    // mirar en cada arranque.
    await marker.writeAsString('$legacyBundleId\n');
  } catch (error) {
    debugPrint('Didacta · no se pudo traer lo de $legacyBundleId: $error');
  }
}

Future<void> forgetLegacyData() async {
  final before = legacyDataDirectory(_host, Platform.environment);
  if (before != null) {
    final old = Directory(before);
    if (await old.exists()) await old.delete(recursive: true);
  }
  if (_host == Host.macos) {
    // Los ajustes de macOS van en su dominio, no en la carpeta.
    try {
      await Process.run('defaults', ['delete', legacyBundleId]);
    } on ProcessException {
      // Sin `defaults` no hay dominio que borrar.
    }
  }
}

/// Dónde guardaba sus datos Didacta con el nombre de antes, en [host].
///
/// `null` si falta la variable que lo dice. Lo que devuelve es la misma
/// ruta que los plugins calculaban, para cada sistema a su manera: en macOS y
/// en Linux, el identificador; en Windows, el editor y el producto.
String? legacyDataDirectory(Host host, Map<String, String> environment) {
  switch (host) {
    case Host.macos:
      final home = environment['HOME'];
      return home == null
          ? null
          : '$home/Library/Application Support/$legacyBundleId';
    case Host.linux:
      final data = environment['XDG_DATA_HOME'];
      final home = environment['HOME'];
      final base = (data != null && data.isNotEmpty)
          ? data
          : (home == null ? null : '$home/.local/share');
      return base == null ? null : '$base/$legacyBundleId';
    case Host.windows:
      final roaming = environment['APPDATA'];
      return roaming == null ? null : '$roaming\\$legacyCompany\\Didacta';
  }
}

/// Copia a [to] lo que haya en [from] y falte en [to]. Devuelve cuántos.
///
/// Nunca encima: lo que ya esté en la carpeta de ahora es más nuevo que lo
/// de antes, o es de alguien que ya ha empezado a usar esta versión.
Future<int> copyMissing(Directory from, Directory to) async {
  var copied = 0;
  await for (final entity in from.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(from.path.length);
    final target = File('${to.path}$relative');
    if (await target.exists()) continue;
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
    copied += 1;
  }
  return copied;
}

bool _same(String a, String b) =>
    Uri.file(a).normalizePath() == Uri.file(b).normalizePath();

Host get _host => switch (true) {
  _ when Platform.isMacOS => Host.macos,
  _ when Platform.isWindows => Host.windows,
  _ => Host.linux,
};
