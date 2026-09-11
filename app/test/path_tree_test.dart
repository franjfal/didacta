/// El árbol de carpetas del material.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/path_tree.dart';

import 'fixture.dart';

Catalogue get catalogue => catalogueWith(defaultUnits());

/// El índice del repositorio de verdad, si está al lado.
List<Unit>? realUnits() {
  final file = File(
    '${Directory.current.parent.parent.path}'
    '/didacta_db/generated/units.json',
  );
  if (!file.existsSync()) return null;
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return Catalogue.fromIndex(
    manifest: {
      'schemaVersion': supportedSchemaVersion,
      'name': 'x',
      'languages': const ['es', 'va', 'en'],
      'defaultLanguage': 'es',
      'contentHash': '',
      'profiles': const [],
      'errors': const <String>[],
    },
    units: data,
    courses: {'schemaVersion': supportedSchemaVersion, 'courses': const []},
  ).units;
}

void main() {
  test('las áreas son el primer nivel, como en el disco', () {
    final tree = buildPathTree(catalogue.units);
    expect(
      [for (final child in tree.children) child.name],
      ['content', 'problems'],
    );
  });

  test('debajo van categoría y tema, y las unidades al final', () {
    final tree = buildPathTree(catalogue.units);
    final content = tree.children.firstWhere((c) => c.name == 'content');
    final analysis = content.children.firstWhere((c) => c.name == 'analysis');
    expect(analysis.path, 'content/analysis');

    final normed = analysis.children.single;
    expect(normed.name, 'normed');
    expect(
      [for (final unit in normed.units('es')) unit.path],
      ['content/analysis/normed/banach', 'content/analysis/normed/definition'],
      reason: 'ordenadas por título',
    );
    expect(normed.children, isEmpty);
  });

  test('una carpeta cerrada dice cuántas lleva dentro', () {
    // Es lo que responde a «¿merece la pena abrir esta?».
    final tree = buildPathTree(catalogue.units);
    final content = tree.children.firstWhere((c) => c.name == 'content');
    expect(content.count, 3);
    expect(content.children.firstWhere((c) => c.name == 'analysis').count, 2);
    expect(tree.count, catalogue.units.length);
  });

  test('el nombre visible no es el de la carpeta', () {
    final tree = buildPathTree(catalogue.units);
    final content = tree.children.firstWhere((c) => c.name == 'content');
    final algebra = content.children.firstWhere((c) => c.name == 'algebra');
    expect(algebra.label, 'Algebra');
    expect(algebra.children.single.label, 'Matrices');
  });

  test('la rama hasta una unidad son sus carpetas', () {
    expect(branchTo('content/analysis/normed/definition'), [
      'content',
      'content/analysis',
      'content/analysis/normed',
    ]);
  });

  test('todo lo de una rama, en el orden del árbol', () {
    final tree = buildPathTree(catalogue.units);
    final content = tree.children.firstWhere((c) => c.name == 'content');
    expect(
      [for (final unit in content.everything('es')) unit.path],
      [
        'content/algebra/matrices/rank',
        'content/analysis/normed/banach',
        'content/analysis/normed/definition',
      ],
    );
  });

  test('contra el repositorio de verdad, no se pierde ninguna', () {
    // La propiedad que importa: el árbol tiene **todas** las unidades. Una
    // que no salga en ninguna carpeta es una que no se puede añadir a un
    // tema, y nadie se daría cuenta hasta buscarla.
    final units = realUnits();
    if (units == null) {
      markTestSkipped('sin didacta_db al lado');
      return;
    }
    final tree = buildPathTree(units);
    expect(tree.count, units.length);
    expect(tree.everything('es').length, units.length);
    expect(
      tree.everything('es').map((u) => u.path).toSet(),
      units.map((u) => u.path).toSet(),
    );
  });
}
