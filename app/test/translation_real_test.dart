/// El ciclo de traducción contra el material de verdad.
///
/// Los demás tests usan ejemplos escritos para el caso. Este recorre las
/// unidades del repositorio de teoría --las que se dan en clase-- y comprueba
/// lo único que no se puede negociar: que **traducir no rompa el fichero**.
///
/// Es el test que encontró que el protector alteraba los separadores de
/// párrafo. Un ejemplo escrito a mano no tiene un `\n \n` con un espacio
/// suelto en medio; cincuenta ficheros migrados, sí.
///
/// Se salta si el repositorio no está, para que la suite siga corriendo en una
/// máquina que no lo tenga clonado.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/translation_memory.dart';
import 'package:didacta_app/model/translation_run.dart';

/// Dónde está el repositorio de teoría, subiendo desde el test.
Directory get repo {
  final root = Directory.current.path.endsWith('/app')
      ? Directory.current.parent.path
      : Directory.current.path;
  return Directory('$root/didacta_db_teoria/content');
}

List<File> get units => !repo.existsSync()
    ? const []
    : repo
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('/es.tex'))
          .toList();

/// Un traductor que respeta las etiquetas y cambia el texto de verdad.
///
/// Cambiar el texto importa: con uno que devuelva lo mismo, un fallo en la
/// reconstrucción pasaría desapercibido porque el resultado coincidiría con
/// el original por casualidad.
Future<List<String>> shout(List<String> pieces) async {
  final tag = RegExp(r'<x id="\d+"/>');
  return [
    for (final piece in pieces)
      () {
        final out = StringBuffer();
        var at = 0;
        for (final match in tag.allMatches(piece)) {
          out.write(piece.substring(at, match.start).toUpperCase());
          out.write(match.group(0));
          at = match.end;
        }
        out.write(piece.substring(at).toUpperCase());
        return out.toString();
      }(),
  ];
}

/// El mismo ciclo sin traducir nada: tiene que devolver el fichero igual.
Future<List<String>> same(List<String> pieces) async => pieces;

void main() {
  test('el material de verdad está donde se espera', () {
    if (units.isEmpty) {
      markTestSkipped('sin didacta_db_teoria clonado al lado');
      return;
    }
    expect(units.length, greaterThan(20));
  });

  test('sin tocar nada, cada unidad sale byte a byte igual', () async {
    // La prueba que sostiene todo: si el ciclo no es exacto con una
    // traducción que no cambia nada, no lo va a ser con una que sí.
    if (units.isEmpty) {
      markTestSkipped('sin didacta_db_teoria clonado al lado');
      return;
    }

    final broken = <String>[];
    for (final file in units) {
      final original = file.readAsStringSync();
      final out = await translateLatex(
        original,
        memory: TranslationMemory.empty(),
        translate: same,
      );
      if (out.text != original) broken.add(file.path);
    }
    expect(broken, isEmpty, reason: 'el ciclo alteró estas unidades');
  });

  test('traduciendo de verdad, la sintaxis se queda donde estaba', () async {
    if (units.isEmpty) {
      markTestSkipped('sin didacta_db_teoria clonado al lado');
      return;
    }

    final refused = <String>[];
    var segments = 0;
    for (final file in units) {
      final original = file.readAsStringSync();
      final out = await translateLatex(
        original,
        memory: TranslationMemory.empty(),
        translate: shout,
      );
      segments += out.stats.segments;
      if (!out.ok) refused.add(file.path);

      // Lo que no puede cambiar: las claves de referencia y las fórmulas
      // siguen tal cual, en el mismo número.
      for (final pattern in [
        RegExp(r'\\label\{[^}]*\}'),
        RegExp(r'\\ref\{[^}]*\}'),
        RegExp(r'\\cite\w*(\[[^\]]*\])?\{[^}]*\}'),
        RegExp(r'\\includegraphics(\[[^\]]*\])?\{[^}]*\}'),
      ]) {
        expect(
          pattern.allMatches(out.text).map((m) => m.group(0)).toList(),
          pattern.allMatches(original).map((m) => m.group(0)).toList(),
          reason: '${file.path}: cambió ${pattern.pattern}',
        );
      }
    }

    expect(refused, isEmpty);
    expect(segments, greaterThan(50), reason: 'había prosa que traducir');
  });

  test('la memoria ahorra de verdad entre unidades', () async {
    // El material repite: la misma definición entra en dos asignaturas, y el
    // mismo encabezado en cuarenta unidades. Si la memoria no ahorrase nada
    // sobre material real, no valdría la pena mantenerla.
    if (units.isEmpty) {
      markTestSkipped('sin didacta_db_teoria clonado al lado');
      return;
    }

    var memory = TranslationMemory.empty();
    var pedidos = 0;
    var total = 0;

    for (final file in units) {
      final out = await translateLatex(
        file.readAsStringSync(),
        memory: memory,
        translate: shout,
      );
      pedidos += out.stats.translated;
      total += out.stats.segments;
      memory = TranslationMemory.merge([
        memory,
        TranslationMemory(out.learned),
      ]);
    }

    expect(total, greaterThan(0));
    expect(
      pedidos,
      lessThan(total),
      reason: 'con $total segmentos se pidieron $pedidos: no repite nada',
    );
  });
}
