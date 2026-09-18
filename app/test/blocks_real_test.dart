/// Los bloques, contra los dos repositorios de verdad.
///
/// Lo que fija este fichero es la promesa de la migración: **nada de lo que
/// ya estaba clasificado se ha quedado sin clasificar**. Las 99 lecciones del
/// material real llevaban `block: theory` o `block: problems` escrito desde
/// que se migró, y ahora los dos bloques están declarados en el
/// `taxonomy.yaml` de cada repositorio. Que se pueda renombrar «Teoría» no
/// vale de nada si al hacerlo se pierde de vista media asignatura.
///
/// Los otros tests montan catálogos de mentira, que es lo correcto para
/// probar reglas. Este mira lo que hay en el disco, que es lo único que
/// contesta «¿y con mi material?».
///
/// Se salta solo si los repositorios no están delante -- en el CI no están, y
/// un test que exige el material de una persona concreta no es un test que
/// pueda correr nadie más.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';

const Map<String, String> repos = {
  'javier/teoria': '/Users/javier/didacta/didacta_db_teoria',
  'javier/problemas': '/Users/javier/didacta_db',
};

Map<String, dynamic> _json(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

Catalogue? _load() {
  final parts = <Catalogue>[];
  for (final entry in repos.entries) {
    final generated = '${entry.value}/generated';
    if (!File('$generated/manifest.json').existsSync()) return null;
    parts.add(
      Catalogue.fromIndex(
        manifest: _json('$generated/manifest.json'),
        units: _json('$generated/units.json'),
        courses: _json('$generated/courses.json'),
        repo: entry.key,
      ),
    );
  }
  return Catalogue.merge(parts);
}

void main() {
  final catalogue = _load();

  group('el material de verdad', () {
    test('sigue teniendo sus dos bloques, y con nombre', () {
      if (catalogue == null) {
        markTestSkipped('sin los repositorios de contenido delante');
        return;
      }
      expect(catalogue.blocks.map((block) => block.id), ['theory', 'problems']);
      expect(catalogue.blocks.first.title('es'), 'Teoría');
      expect(catalogue.blocks.last.title('es'), 'Problemas');
      // Y en valenciano y en inglés, que es a lo que traducen los dos
      // repositorios: un bloque a medio traducir sale en la pantalla de
      // traducciones, no en la de material.
      expect(catalogue.blocks.first.titleIsFallback('va'), isFalse);
      expect(catalogue.blocks.first.titleIsFallback('en'), isFalse);
    });

    test('cada uno lo declara alguien, y los que se repiten no discrepan', () {
      if (catalogue == null) {
        markTestSkipped('sin los repositorios de contenido delante');
        return;
      }
      // Quién declara qué es una decisión de quien enseña: la migración los
      // puso en los dos repositorios y luego se pueden repartir. Lo que no
      // puede pasar es que dos digan cosas distintas del mismo bloque, porque
      // entonces lo que se enseña depende de en qué orden se abrieron.
      for (final block in catalogue.blocks) {
        expect(block.sources, isNotEmpty, reason: block.id);
      }
      expect(catalogue.blockConflicts, isEmpty);
    });

    test('y ninguna lección se ha quedado sin bloque', () {
      if (catalogue == null) {
        markTestSkipped('sin los repositorios de contenido delante');
        return;
      }
      expect(catalogue.units, isNotEmpty);
      expect(catalogue.undeclaredBlocks, isEmpty);

      // Una por una, que es lo que de verdad se prometió: cada lección
      // pertenece a un bloque que alguien declara.
      final declared = {for (final block in catalogue.blocks) block.id};
      final lost = [
        for (final unit in catalogue.units)
          if (!declared.contains(unit.block)) '${unit.repo}:${unit.path}',
      ];
      expect(lost, isEmpty, reason: lost.take(5).join('\n'));
    });

    test('con la teoría en un repositorio y los problemas en el otro', () {
      if (catalogue == null) {
        markTestSkipped('sin los repositorios de contenido delante');
        return;
      }
      // El reparto que hace falta que siga funcionando: las lecciones de un
      // bloque viven en un repositorio y el otro también lo declara, que es
      // lo que permite abrir solo uno y seguir viendo su material con nombre.
      final theory = catalogue.unitsInBlock('theory');
      final problems = catalogue.unitsInBlock('problems');
      expect(theory, isNotEmpty);
      expect(problems, isNotEmpty);
      expect({for (final unit in theory) unit.repo}, {'javier/teoria'});
      expect({for (final unit in problems) unit.repo}, {'javier/problemas'});
    });

    test('y abrir uno solo sigue enseñándolo todo con su nombre', () {
      if (catalogue == null) {
        markTestSkipped('sin los repositorios de contenido delante');
        return;
      }
      // La propiedad que sostiene el diseño: apagar un repositorio tiene que
      // dar lo mismo que no tenerlo, y quien solo tenga el de teoría tiene
      // que ver su bloque con su nombre y ninguna lección huérfana.
      final alone = catalogue.without({'javier/problemas'});
      expect(alone.undeclaredBlocks, isEmpty);
      expect(alone.blockNamed('theory').title('es'), 'Teoría');
      expect(alone.units, isNotEmpty);
    });
  });
}
