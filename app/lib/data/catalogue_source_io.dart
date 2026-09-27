/// The catalogue read from disk, which is what a local clone makes possible.
///
/// Worth having rather than fetching over HTTP even when both would work: the
/// clone is already the source of truth on this machine, so reading the index
/// from it means the library can never disagree with the files the editor is
/// writing, and it works with no network at all.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../model/catalogue.dart';
import 'catalogue_source.dart';
import '../l10n/tr.dart';

CatalogueSource? fileSource(String directory, String repo) =>
    FileCatalogueSource(directory: directory, repo: repo);

class FileCatalogueSource extends CatalogueSource {
  const FileCatalogueSource({required this.directory, this.repo = ''});

  /// De qué repositorio es este índice. Viaja con cada unidad y cada
  /// documento: con varios abiertos, la ruta sola no dice de cuál es.
  final String repo;

  /// The clone's root; the index lives in `generated/` inside it.
  final String directory;

  @override
  String get describe => '$directory/generated';

  /// En otro hilo. Leer y descodificar dos megas de JSON y construir dos mil
  /// unidades son cientos de milisegundos, y en el hilo de la interfaz eran
  /// cientos de milisegundos de ventana congelada después de cada guardado.
  @override
  Future<Catalogue> load() {
    final directory = this.directory;
    final repo = this.repo;
    return Isolate.run(() => _loadNow(directory, repo));
  }

  static Catalogue _loadNow(String directory, String repo) =>
      Catalogue.fromIndex(
        manifest: _read(directory, 'manifest.json'),
        units: _read(directory, 'units.json'),
        courses: _read(directory, 'courses.json'),
        repo: repo,
      );

  static Map<String, dynamic> _read(String directory, String name) {
    final file = File('$directory/generated/$name');
    if (!file.existsSync()) {
      throw CatalogueFormatException(
        tr(
          'no existe {0}. El índice lo genera el motor: '
          '`didacta index` desde el repositorio de contenido.',
          [file.path],
        ),
      );
    }
    // Read as bytes and decoded explicitly: these titles are Valencian and
    // Castilian, and guessing the encoding turns every accent into mojibake.
    final decoded = jsonDecode(utf8.decode(file.readAsBytesSync()));
    if (decoded is! Map) {
      throw CatalogueFormatException(
        tr('{0} no contiene un objeto JSON', [file.path]),
      );
    }
    return decoded.cast<String, dynamic>();
  }
}
