/// The catalogue read from disk, which is what a local clone makes possible.
///
/// Worth having rather than fetching over HTTP even when both would work: the
/// clone is already the source of truth on this machine, so reading the index
/// from it means the library can never disagree with the files the editor is
/// writing, and it works with no network at all.
library;

import 'dart:convert';
import 'dart:io';

import '../model/catalogue.dart';
import 'catalogue_source.dart';

CatalogueSource? fileSource(String directory) =>
    FileCatalogueSource(directory: directory);

class FileCatalogueSource extends CatalogueSource {
  const FileCatalogueSource({required this.directory});

  /// The clone's root; the index lives in `generated/` inside it.
  final String directory;

  @override
  String get describe => '$directory/generated';

  @override
  Future<Catalogue> load() async {
    return Catalogue.fromIndex(
      manifest: await _read('manifest.json'),
      units: await _read('units.json'),
      courses: await _read('courses.json'),
    );
  }

  Future<Map<String, dynamic>> _read(String name) async {
    final file = File('$directory/generated/$name');
    if (!await file.exists()) {
      throw CatalogueFormatException(
        'no existe ${file.path}. El índice lo genera el motor: '
        '`didacta index` desde el repositorio de contenido.',
      );
    }
    // Read as bytes and decoded explicitly: these titles are Valencian and
    // Castilian, and guessing the encoding turns every accent into mojibake.
    final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
    if (decoded is! Map) {
      throw CatalogueFormatException('${file.path} no contiene un objeto JSON');
    }
    return decoded.cast<String, dynamic>();
  }
}
