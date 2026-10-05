// Las raíces de Mozilla que Didacta suma en Windows a las del sistema
// (issue #1): que el fichero va empaquetado, que se leen todas y que una
// raíz repetida no hace fallar a las demás.
import 'dart:io';

import 'package:didacta_app/data/trusted_roots.dart';
import 'package:didacta_app/data/trusted_roots_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pem = File(trustedRootsAsset).readAsStringSync();
  final total = '-----BEGIN CERTIFICATE-----'.allMatches(pem).length;

  test('el conjunto va declarado entre los recursos', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/certificados/'));
  });

  test('se separan todos los certificados del fichero', () {
    final certificates = pemCertificates(pem).toList();
    expect(total, greaterThan(100));
    expect(certificates, hasLength(total));
    for (final certificate in certificates) {
      expect(certificate, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(certificate.trim(), endsWith('-----END CERTIFICATE-----'));
    }
  });

  test('entran todos, y repetirlos no rompe nada', () {
    final context = SecurityContext(withTrustedRoots: false);
    expect(addCertificates(context, pem), total);
    // Lo que pasa en Windows con las raíces que ya estaban en el almacén.
    expect(() => addCertificates(context, pem), returnsNormally);
  });
}
