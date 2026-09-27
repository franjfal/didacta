/// El índice se lee en otro hilo, y con varios repositorios, a la vez.
///
/// Lo que se comprueba es que el catálogo llega entero --que todo lo que
/// lleva dentro se puede pasar de un hilo a otro-- y que un repositorio que
/// no carga se sigue diciendo sin llevarse a los demás.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/catalogue_source_io.dart';
import 'package:didacta_app/model/catalogue.dart';

void main() {
  const example = 'assets/ejemplo';

  test('el del ejemplo llega entero desde otro hilo', () async {
    final catalogue = await const FileCatalogueSource(
      directory: example,
      repo: 'ejemplo',
    ).load();
    expect(catalogue.units, isNotEmpty);
    expect(catalogue.courses, isNotEmpty);
    expect(catalogue.units.every((unit) => unit.repo == 'ejemplo'), isTrue);
  });

  test('sin índice lo dice, también desde otro hilo', () async {
    final empty = await Directory.systemTemp.createTemp('didacta-noindex-');
    addTearDown(() => empty.delete(recursive: true));
    await expectLater(
      FileCatalogueSource(directory: empty.path).load(),
      throwsA(isA<CatalogueFormatException>()),
    );
  });

  test(
    'buscar por ruta, con el índice, contesta lo mismo que recorrer',
    () async {
      // Dos repositorios con la misma ruta: sin decir cuál, el primero; diciendo
      // cuál, el suyo; y de uno que no la tiene, nada.
      final a = await const FileCatalogueSource(
        directory: example,
        repo: 'a',
      ).load();
      final b = await const FileCatalogueSource(
        directory: example,
        repo: 'b',
      ).load();
      final merged = Catalogue.merge([a, b]);
      final path = a.units.first.path;
      expect(merged.unitByPath(path)!.repo, 'a');
      expect(merged.unitByPath(path, repo: 'b')!.repo, 'b');
      expect(merged.unitByPath(path, repo: 'c'), isNull);
      expect(merged.unitByPath('content/no/existe'), isNull);
      // Y la referencia, sin el árbol delante, igual.
      final reference = path.substring(path.indexOf('/') + 1);
      expect(merged.unitByReference(reference, repo: 'b')!.repo, 'b');
    },
  );

  test('dos a la vez, y el que falla no se lleva al otro', () async {
    final empty = await Directory.systemTemp.createTemp('didacta-noindex-');
    addTearDown(() => empty.delete(recursive: true));
    final merged = await MergedCatalogueSource([
      const FileCatalogueSource(directory: example, repo: 'a'),
      FileCatalogueSource(directory: empty.path, repo: 'b'),
      const FileCatalogueSource(directory: example, repo: 'c'),
    ]).load();
    expect({for (final unit in merged.units) unit.repo}, {'a', 'c'});
    // Su queja, una; las demás son de juntar dos veces el mismo ejemplo.
    expect(
      merged.errors.where((error) => error.contains(empty.path)),
      hasLength(1),
    );
  });
}
