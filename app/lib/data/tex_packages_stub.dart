/// En el navegador no hay TeX al que añadirle paquetes.
library;

import '../model/tex_packages.dart';
import 'tex_packages.dart';
import '../l10n/tr.dart';

bool get supported => false;

TexPackages makeTexPackages({String? texPath}) => const _NoTexPackages();

class _NoTexPackages implements TexPackages {
  const _NoTexPackages();

  @override
  Future<TexPackageManager> manager() async => TexPackageManager.none;

  @override
  Future<String?> locate(String file) async => null;

  @override
  Future<String?> packageFor(
    String file,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  }) async => null;

  @override
  Future<void> install(
    String package,
    TexPackageManager manager, {
    void Function(String line)? onOutput,
  }) async => throw TexPackageException(
    tr('En el navegador no se puede instalar nada.'),
  );
}
