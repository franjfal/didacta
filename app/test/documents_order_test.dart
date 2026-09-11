/// Mover, añadir y quitar documentos dentro de un `year.yaml`.
///
/// Contra los treinta ficheros del repositorio de verdad, no contra uno
/// inventado. La razón es la de siempre en este proyecto: lo que hay que
/// demostrar no es que el código haga lo que dice, sino que **no pierde nada
/// por el camino**. Un documento son veinte líneas con comentarios, TODO,
/// títulos por idioma y entradas comentadas que alguien dejó ahí a
/// propósito; reescribir el fichero en lugar de mover sus líneas se las
/// llevaría todas sin que nadie se entere hasta meses después.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/composition_file.dart';

/// Los `year.yaml` del repositorio de contenido, si está al lado.
List<File> realYears() {
  for (final root in [
    '${Directory.current.parent.parent.path}/didacta_db',
    '${Platform.environment['HOME']}/didacta_db',
  ]) {
    final directory = Directory('$root/courses');
    if (!directory.existsSync()) continue;
    return [
      for (final file in directory.listSync(recursive: true))
        if (file is File && file.path.endsWith('year.yaml')) file,
    ];
  }
  return const [];
}

const String sample = '''
# Análisis Matemático III -- 2025-2026

course: am-iii
year: 2025-2026

documents:
  - id: tema-1
    kind: theory
    title:
      es: Tema 1. Espacios normados
    profiles: [handout, slides]
    structure:
      - section:
          es: Normas
          # TODO: va
      - unit: analysis/normed/definition
      # - unit: analysis/normed/dedekind

  - id: hoja-1
    kind: problems
    title:
      es: Hoja 1
    structure:
      - problem: analysis/normed/exercises

  - id: seminario-1
    kind: seminar
    title:
      es: Seminario 1
    structure: []
''';

void main() {
  group('reordenar', () {
    test('mueve el bloque entero, comentarios incluidos', () {
      final file = CompositionFile(sample)
        ..setDocumentOrder(['hoja-1', 'tema-1', 'seminario-1']);

      expect(file.documentIds(), ['hoja-1', 'tema-1', 'seminario-1']);
      // Lo que hace que esto no sea una reserialización: la entrada
      // comentada y el TODO siguen ahí, dentro del bloque que se movió.
      expect(file.text, contains('      # - unit: analysis/normed/dedekind'));
      expect(file.text, contains('          # TODO: va'));
      // Y la cabecera del fichero no se ha tocado.
      expect(file.text, startsWith('# Análisis Matemático III -- 2025-2026'));
      expect(file.text, contains('course: am-iii'));
    });

    test('el mismo orden deja el fichero igual', () {
      // La prueba de que mover no es reescribir.
      final file = CompositionFile(sample)
        ..setDocumentOrder(['tema-1', 'hoja-1', 'seminario-1']);
      expect(file.text, sample);
    });

    test('mover y deshacer vuelve al original', () {
      final moved = CompositionFile(sample)
        ..setDocumentOrder(['seminario-1', 'hoja-1', 'tema-1']);
      final back = CompositionFile(moved.text)
        ..setDocumentOrder(['tema-1', 'hoja-1', 'seminario-1']);
      expect(back.text, sample);
    });

    test('un orden que no son los mismos documentos no se aplica', () {
      // Mover no es editar. Si la lista que llega no tiene exactamente lo
      // que hay, es un error de quien llama y no algo que arreglar por las
      // buenas: arreglarlo sería perder un documento en silencio.
      expect(
        () => CompositionFile(sample).setDocumentOrder(['tema-1', 'hoja-1']),
        throwsA(isA<CompositionException>()),
      );
      expect(
        () => CompositionFile(
          sample,
        ).setDocumentOrder(['tema-1', 'hoja-1', 'otro']),
        throwsA(isA<CompositionException>()),
      );
    });

    test('la composición de cada documento se sigue leyendo después', () {
      final file = CompositionFile(sample)
        ..setDocumentOrder(['seminario-1', 'tema-1', 'hoja-1']);
      final block = CompositionFile(file.text).blockFor('tema-1')!;
      expect(block.entries.map((e) => e.toString()), [
        '- section: Normas',
        '- unit: analysis/normed/definition',
        '# - unit: analysis/normed/dedekind',
      ]);
    });
  });

  group('añadir', () {
    test('un documento nuevo va al final, con su título y vacío', () {
      final file = CompositionFile(sample)
        ..addDocument(
          id: 'hoja-2',
          kind: 'problems',
          title: {'es': 'Hoja 2', 'va': 'Full 2'},
          pending: ['en'],
        );

      expect(file.documentIds(), ['tema-1', 'hoja-1', 'seminario-1', 'hoja-2']);
      expect(file.text, contains('  - id: hoja-2'));
      expect(file.text, contains('    kind: problems'));
      expect(file.text, contains('      es: Hoja 2'));
      expect(file.text, contains('      va: Full 2'));
      // Y el que falta, comentado: `en: TODO` sería un título de verdad, y
      // saldría en la lista de documentos y dentro del PDF compilado.
      expect(file.text, contains('      # TODO: en'));
      // Vacío y diciéndolo: un `structure:` pelado se lee como nulo.
      expect(file.text, contains('    structure: []'));
      // Y con una línea en blanco de separación, como los demás.
      expect(file.text, contains('\n\n  - id: hoja-2'));
    });

    test('el nuevo se puede componer inmediatamente', () {
      final file = CompositionFile(sample)
        ..addDocument(id: 'hoja-2', kind: 'problems', title: {'es': 'Hoja 2'});
      final reread = CompositionFile(file.text);
      expect(reread.blockFor('hoja-2'), isNotNull);
      expect(reread.blockFor('hoja-2')!.entries, isEmpty);
    });

    test('un id repetido no se añade', () {
      expect(
        () => CompositionFile(
          sample,
        ).addDocument(id: 'tema-1', kind: 'theory', title: {'es': 'Otro'}),
        throwsA(isA<CompositionException>()),
      );
    });

    test('los perfiles, si se dan', () {
      final file = CompositionFile(sample)
        ..addDocument(
          id: 'tema-2',
          kind: 'theory',
          title: {'es': 'Tema 2'},
          profiles: ['handout', 'slides'],
        );
      expect(file.text, contains('    profiles: [handout, slides]'));
    });
  });

  group('quitar', () {
    test('se lleva el bloque y nada más', () {
      final file = CompositionFile(sample)..removeDocument('hoja-1');
      expect(file.documentIds(), ['tema-1', 'seminario-1']);
      expect(file.text, isNot(contains('Hoja 1')));
      // Los vecinos, intactos.
      expect(file.text, contains('      # - unit: analysis/normed/dedekind'));
      expect(file.text, contains('  - id: seminario-1'));
    });

    test('uno que no existe se dice', () {
      expect(
        () => CompositionFile(sample).removeDocument('no-existe'),
        throwsA(isA<CompositionException>()),
      );
    });
  });

  group('contra el repositorio de verdad', () {
    test('reordenar al mismo orden no cambia ni un byte', () {
      final files = realYears();
      if (files.isEmpty) {
        markTestSkipped('sin didacta_db al lado');
        return;
      }
      for (final file in files) {
        final text = file.readAsStringSync();
        final composition = CompositionFile(text);
        final ids = composition.documentIds();
        if (ids.isEmpty) continue;
        composition.setDocumentOrder(ids);
        expect(composition.text, text, reason: file.path);
      }
    });

    test('dar la vuelta al orden y deshacerlo devuelve el fichero', () {
      final files = realYears();
      if (files.isEmpty) {
        markTestSkipped('sin didacta_db al lado');
        return;
      }
      var checked = 0;
      for (final file in files) {
        final text = file.readAsStringSync();
        final ids = CompositionFile(text).documentIds();
        if (ids.length < 2) continue;
        final reversed = ids.reversed.toList();
        final moved = CompositionFile(text)..setDocumentOrder(reversed);
        expect(
          CompositionFile(moved.text).documentIds(),
          reversed,
          reason: file.path,
        );
        final back = CompositionFile(moved.text)..setDocumentOrder(ids);
        expect(back.text, text, reason: file.path);
        checked += 1;
      }
      expect(checked, greaterThan(10), reason: 'apenas se ha probado nada');
    });
  });
}
