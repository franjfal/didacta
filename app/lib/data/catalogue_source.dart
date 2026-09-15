/// Where the catalogue comes from.
///
/// An interface, because the answer differs by platform and the spec asks for
/// web now and desktop later without rewriting the logic. On the web the index
/// is fetched over HTTP; on desktop it will be read from the checkout on disk;
/// in a test it is handed over directly. Nothing above this layer knows which.
///
/// It deliberately does not know about authentication or GitHub. Those belong
/// to the API layer, and a source that fetches three static JSON files is
/// exactly what a public GitHub Pages deployment can serve with no server at
/// all -- which is worth keeping possible.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/catalogue.dart';
import 'catalogue_source_stub.dart'
    if (dart.library.io) 'catalogue_source_io.dart'
    as platform;

abstract class CatalogueSource {
  const CatalogueSource();

  /// Loads the catalogue, or throws.
  ///
  /// Throwing rather than returning null: a library view with no library is
  /// not a state worth rendering, and the reason it failed is what the reader
  /// needs to see.
  Future<Catalogue> load();

  /// A human-readable description of where this reads from, for the error
  /// message when it fails. "No se pudo cargar" without saying from where is
  /// not something anyone can act on.
  String get describe;

  /// The catalogue inside a local clone, or null where there is no
  /// filesystem to read it from.
  ///
  /// Preferred over HTTP when a clone exists: the clone is the source of
  /// truth on this machine, so reading the index from it means the library
  /// cannot disagree with the files the editor is writing, and it needs no
  /// network.
  static CatalogueSource? inClone(String directory, {String repo = ''}) =>
      platform.fileSource(directory, repo);

  /// Varios repositorios leídos como una sola biblioteca.
  static CatalogueSource merged(List<CatalogueSource> parts) =>
      MergedCatalogueSource(parts);
}

/// Varios orígenes, una biblioteca.
///
/// Cada repositorio trae su propio índice generado --lo escribe el motor en
/// su carpeta-- y aquí se juntan. Lo que se mezcla es la asignatura; las
/// unidades se quedan cada una con la suya, porque dos repositorios pueden
/// tener la misma ruta y son cosas distintas.
class MergedCatalogueSource extends CatalogueSource {
  const MergedCatalogueSource(this.parts);

  final List<CatalogueSource> parts;

  @override
  String get describe => parts.map((each) => each.describe).join(', ');

  @override
  Future<Catalogue> load() async {
    final loaded = <Catalogue>[];
    final failures = <String>[];
    for (final part in parts) {
      try {
        loaded.add(await part.load());
      } catch (thrown) {
        // Un repositorio que no carga no puede llevarse por delante a los
        // demás: quien tenga uno de los dos tiene que ver el suyo.
        failures.add('${part.describe}: $thrown');
      }
    }
    if (loaded.isEmpty && failures.isNotEmpty) {
      throw CatalogueFormatException(failures.join('\n'));
    }
    final merged = Catalogue.merge(loaded);
    if (failures.isEmpty) return merged;
    return Catalogue(
      name: merged.name,
      languages: merged.languages,
      defaultLanguage: merged.defaultLanguage,
      contentHash: merged.contentHash,
      units: merged.units,
      courses: merged.courses,
      profiles: merged.profiles,
      errors: [...merged.errors, ...failures],
    );
  }
}

/// Reads the three generated files over HTTP.
class HttpCatalogueSource extends CatalogueSource {
  const HttpCatalogueSource({this.base = 'generated', this.client});

  /// Where the generated directory is served from, relative to the app or
  /// absolute. Relative by default so a build dropped next to a content
  /// repository works with no configuration.
  final String base;

  /// Injected in tests; created and closed per load when absent, so nothing
  /// holds a socket open for the life of the app.
  final http.Client? client;

  @override
  String get describe => base;

  @override
  Future<Catalogue> load() async {
    final client = this.client ?? http.Client();
    try {
      // Fetched together: three round trips in series would show the reader
      // three separate waits for one screen.
      final responses = await Future.wait([
        _get(client, 'manifest.json'),
        _get(client, 'units.json'),
        _get(client, 'courses.json'),
      ]);
      return Catalogue.fromIndex(
        manifest: responses[0],
        units: responses[1],
        courses: responses[2],
      );
    } finally {
      if (this.client == null) client.close();
    }
  }

  Future<Map<String, dynamic>> _get(http.Client client, String name) async {
    final uri = Uri.parse('$base/$name');
    final response = await client.get(uri);
    if (response.statusCode != 200) {
      throw CatalogueFormatException(
        'no se pudo leer $uri (HTTP ${response.statusCode}). '
        '¿Se ha generado el índice con `didacta index`?',
      );
    }
    // `bodyBytes` decoded explicitly as UTF-8: these titles are Valencian and
    // Castilian, and `response.body` guesses latin-1 when the server sends no
    // charset, which turns every accent into mojibake.
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw CatalogueFormatException('$uri no contiene un objeto JSON');
    }
    return decoded.cast<String, dynamic>();
  }
}

/// A catalogue held in memory, for tests and for the demo build.
class StaticCatalogueSource extends CatalogueSource {
  const StaticCatalogueSource(this.catalogue, {this.label = 'memoria'});

  final Catalogue catalogue;
  final String label;

  @override
  String get describe => label;

  @override
  Future<Catalogue> load() async => catalogue;
}
