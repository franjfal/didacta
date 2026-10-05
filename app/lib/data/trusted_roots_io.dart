/// Las raíces de Mozilla sumadas a las del sistema, en Windows.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'diagnostics.dart';
import 'trusted_roots.dart' show trustedRootsAsset;

Future<void> trustBundledRoots() async {
  if (!Platform.isWindows) return;
  try {
    final pem = await rootBundle.loadString(trustedRootsAsset);
    final context = SecurityContext(withTrustedRoots: true);
    final added = addCertificates(context, pem);
    HttpOverrides.global = BundledRootsOverrides(context);
    debugPrint(
      'Didacta · raíces de Mozilla: $added añadidas a las del sistema',
    );
  } catch (error, stack) {
    // Sin el conjunto, las del sistema: lo de antes, que casi siempre vale.
    Diagnostics.instance.note('certificados', error, stack);
  }
}

/// Añade a [context] cada certificado de [pem] y dice cuántos entraron.
///
/// Uno a uno, porque una raíz que ya estaba en el almacén de Windows hace
/// fallar la suma y, si fueran todas juntas, se perderían las de detrás.
int addCertificates(SecurityContext context, String pem) {
  var added = 0;
  for (final certificate in pemCertificates(pem)) {
    try {
      context.setTrustedCertificatesBytes(utf8.encode(certificate));
      added++;
    } on TlsException {
      // Ya la tenía.
    }
  }
  return added;
}

/// Los bloques `BEGIN CERTIFICATE` de [pem], cada uno entero.
Iterable<String> pemCertificates(String pem) sync* {
  const begin = '-----BEGIN CERTIFICATE-----';
  const end = '-----END CERTIFICATE-----';
  var from = pem.indexOf(begin);
  while (from >= 0) {
    final to = pem.indexOf(end, from);
    if (to < 0) return;
    yield '${pem.substring(from, to + end.length)}\n';
    from = pem.indexOf(begin, to);
  }
}

/// Todos los `HttpClient` de la aplicación --los de `package:http` también,
/// que los crean sin contexto-- con [context] en vez del de por defecto.
class BundledRootsOverrides extends HttpOverrides {
  BundledRootsOverrides(this.context);

  final SecurityContext context;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? this.context);
}
