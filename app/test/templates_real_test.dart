/// Las plantillas, contra los dos repositorios de verdad.
///
/// Lo que fija este fichero son **reglas, no una foto**. Las quince salidas se
/// copiaron a `didacta_db` para poder editarlas, y editarlas es justo lo que
/// se espera que pase: quitar las que no se usan, renombrar una, cambiar con
/// qué compila un bloque. Un test que fijara la lista de aquel día fallaría al
/// primer clic, que es lo contrario de lo que sirve para algo.
///
/// Así que lo que se comprueba es lo que tiene que ser cierto **se configure
/// como se configure**: que nada quede nombrando algo que no existe, que las
/// copias sigan produciendo lo mismo que las de serie, y que quien abra un
/// solo repositorio siga pudiendo compilar.
///
/// Se salta solo si los repositorios no están delante.
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

  void skipWithout() {
    if (catalogue == null) {
      markTestSkipped('sin los repositorios de contenido delante');
    }
  }

  group('las plantillas del material de verdad', () {
    test('hay salidas declaradas, y se compila con ellas', () {
      skipWithout();
      if (catalogue == null) return;
      // Cuántas y cuáles es cosa de quien enseña; que haya alguna y que se
      // pueda compilar con ella, no.
      expect(catalogue.templates, isNotEmpty);
      expect(catalogue.activeTemplates, isNotEmpty);
      expect(catalogue.templatesInUse.length, catalogue.templates.length);
    });

    test('y dicen lo mismo que las que trae el programa', () {
      skipWithout();
      if (catalogue == null) return;
      // El índice trae las dos listas: las declaradas y las de serie. Que
      // coincidan es lo que significa «migrar sin cambiar nada».
      final shipped = {
        for (final profile in catalogue.profiles) profile.id: profile,
      };
      for (final template in catalogue.templates) {
        final reference = shipped[template.id];
        expect(reference, isNotNull, reason: template.id);
        expect(
          template.documentClass,
          reference!.documentClass,
          reason: template.id,
        );
      }
    });

    test('cada una la declara un repositorio, y no se contradicen', () {
      skipWithout();
      if (catalogue == null) return;
      // Una plantilla es un fichero con su cabecera: tenerla en dos sitios es
      // tener dos versiones que pueden discrepar.
      for (final template in catalogue.templates) {
        expect(template.sources, hasLength(1), reason: template.id);
      }
      expect(catalogue.templateConflicts, isEmpty);
    });

    test('nada se compila con una plantilla que no existe', () {
      skipWithout();
      if (catalogue == null) return;
      // Es la única forma de acabar con un documento del que no sale nada, y
      // pasa de verdad: se quita una plantilla y los bloques que la nombraban
      // se quedan apuntando al aire. Se ve, se dice y se arregla.
      expect(
        catalogue.undeclaredTemplates,
        isEmpty,
        reason:
            'algo nombra plantillas que no declara nadie: '
            '${catalogue.undeclaredTemplates.join(', ')}',
      );
    });

    test('cada bloque compila en algo, y en algo que existe', () {
      skipWithout();
      if (catalogue == null) return;
      final live = {for (final t in catalogue.activeTemplates) t.id};
      for (final block in catalogue.blocks) {
        final wanted = catalogue.templatesOfBlock(block.id);
        expect(
          wanted,
          isNotEmpty,
          reason: 'el bloque ${block.id} no compila nada',
        );
        expect(wanted.every(live.contains), isTrue, reason: block.id);
      }
    });

    test('y de cada lección sale algo', () {
      skipWithout();
      if (catalogue == null) return;
      // La que de verdad importa: no hay ninguna lección de la que no salga
      // ningún PDF. Una lección invisible no da ningún error.
      final lost = [
        for (final unit in catalogue.units)
          if (catalogue.templatesFor(unit).isEmpty) unit.path,
      ];
      expect(lost, isEmpty, reason: lost.take(5).join('\n'));
    });

    test('quien solo abra el de teoría sigue compilando', () {
      skipWithout();
      if (catalogue == null) return;
      // Las plantillas las declara el repositorio de problemas, así que con
      // el de teoría solo no queda ninguna declarada -- y entonces valen las
      // quince que trae el programa, que es la red que sostiene esto.
      final alone = catalogue.without({'javier/problemas'});
      expect(alone.templates, isEmpty);
      expect(alone.templatesInUse, hasLength(15));
      expect(alone.undeclaredTemplates, isEmpty);
      expect(alone.templatesOfBlock('theory'), isNotEmpty);
      for (final unit in alone.units) {
        expect(alone.templatesFor(unit), isNotEmpty, reason: unit.path);
      }
    });
  });
}
