/// Traducir una unidad de verdad: qué se escribe y dónde.
///
/// El otro fichero prueba el ciclo --que el `.tex` no se rompa-- sin tocar
/// nada. Este prueba el camino de escritura, que es donde se toca material de
/// alguien: en qué fichero cae la traducción, qué se guarda en la memoria, y
/// qué pasa cuando algo falla a mitad.
///
/// Dos commits separados a propósito: el material por un lado y lo que se
/// aprendió al traducirlo por otro. Quien revise el historial quiere poder
/// mirar uno sin el otro, y si la memoria falla al guardarse la traducción ya
/// está hecha.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/model/translation_memory.dart';
import 'package:didacta_app/data/translator.dart';

import 'fixture.dart';

const String unitPathHere = 'content/analysis/normed/definition';

/// Un traductor de mentira que respeta las etiquetas.
class FakeTranslator implements Translator {
  FakeTranslator({this.fail = false});

  final bool fail;
  final List<List<String>> asked = [];

  @override
  TranslationProvider get provider => TranslationProvider.google;

  @override
  Future<ProviderCheck> check() async =>
      const ProviderCheck(ok: true, message: 'bien');

  @override
  Future<List<String>> translate(
    List<String> pieces, {
    required String from,
    required String to,
  }) async {
    asked.add(pieces);
    if (fail) throw const TranslationException('no contestó');
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
}

Future<(FakeSession, FakeGateway)> ready({
  Map<String, String> files = const {},
}) async {
  final gateway = FakeGateway(
    files: {
      '$unitPathHere/es.tex':
          'La norma de un vector es su longitud.\n\n'
          r'Se escribe $\|x\|$ y cumple \ref{ax:norma}.'
          '\n',
      ...files,
    },
  );
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  return (session, gateway);
}

Unit theUnit(FakeSession session) =>
    session.catalogue.units.firstWhere((u) => u.path == unitPathHere);

void main() {
  test('la traducción cae en el fichero del idioma destino', () async {
    final (session, gateway) = await ready();

    final result = await session.translateUnit(
      unit: theUnit(session),
      from: 'es',
      to: 'va',
      translator: FakeTranslator(),
    );

    expect(result.ok, isTrue);
    final written = gateway.commits.firstWhere(
      (c) => c.path.endsWith('/va.tex'),
    );
    expect(written.text, contains('LA NORMA'));
    // Y la sintaxis, donde estaba.
    expect(written.text, contains(r'$\|x\|$'));
    expect(written.text, contains(r'\ref{ax:norma}'));
  });

  test('el commit dice que es un borrador', () async {
    // Es una traducción que no ha leído nadie, y el historial tiene que
    // decirlo: quien mire el diff mañana no se acuerda de cómo salió.
    final (session, gateway) = await ready();
    await session.translateUnit(
      unit: theUnit(session),
      from: 'es',
      to: 'va',
      translator: FakeTranslator(),
    );

    final written = gateway.commits.firstWhere(
      (c) => c.path.endsWith('/va.tex'),
    );
    expect(written.message, contains('borrador'));
  });

  test('lo aprendido se guarda en la memoria del par de idiomas', () async {
    final (session, gateway) = await ready();
    await session.translateUnit(
      unit: theUnit(session),
      from: 'es',
      to: 'va',
      translator: FakeTranslator(),
    );

    final memory = gateway.commits.firstWhere(
      (c) => c.path == memoryPath('es', 'va'),
    );
    final lines = const LineSplitter().convert(memory.text.trim());
    expect(lines, isNotEmpty);
    for (final line in lines) {
      final entry = jsonDecode(line) as Map;
      expect(entry['source'], isNotEmpty);
      expect(entry['unit'], unitPathHere);
    }
  });

  test('en dos commits, el material y la memoria', () async {
    // Quien revise el historial quiere poder mirar uno sin el otro.
    final (session, gateway) = await ready();
    await session.translateUnit(
      unit: theUnit(session),
      from: 'es',
      to: 'va',
      translator: FakeTranslator(),
    );

    final paths = gateway.commits.map((c) => c.path).toSet();
    expect(paths, contains('$unitPathHere/va.tex'));
    expect(paths, contains(memoryPath('es', 'va')));
  });

  test('la memoria se añade al final, no reescribe lo que hay', () async {
    // Reescribirla entera convierte cada traducción en un conflicto con todo
    // lo que otra persona haya traducido mientras tanto.
    const previo = '{"source":"Otra cosa.","target":"Una altra cosa."}\n';
    final (session, gateway) = await ready(
      files: {memoryPath('es', 'va'): previo},
    );
    await session.translateUnit(
      unit: theUnit(session),
      from: 'es',
      to: 'va',
      translator: FakeTranslator(),
    );

    final memory = gateway.commits.firstWhere(
      (c) => c.path == memoryPath('es', 'va'),
    );
    expect(memory.text, startsWith(previo));
    expect(memory.text.trim().split('\n').length, greaterThan(1));
  });

  test('lo que ya está en la memoria no se vuelve a pedir', () async {
    final translator = FakeTranslator();
    final (first, _) = await ready();
    await first.translateUnit(
      unit: theUnit(first),
      from: 'es',
      to: 'va',
      translator: translator,
    );
    final learned = translator.asked.single.length;

    // Otra sesión, con la memoria que dejó la primera.
    final memoria = StringBuffer();
    for (final piece in translator.asked.single) {
      memoria.writeln(
        jsonEncode({'source': piece, 'target': piece.toUpperCase()}),
      );
    }
    final again = FakeTranslator();
    final (second, _) = await ready(
      files: {memoryPath('es', 'va'): memoria.toString()},
    );
    await second.translateUnit(
      unit: theUnit(second),
      from: 'es',
      to: 'va',
      translator: again,
    );

    expect(learned, greaterThan(0));
    expect(again.asked, isEmpty, reason: 'estaba entero en la memoria');
  });

  test('si el proveedor falla, no se escribe nada', () async {
    // Media traducción escrita es peor que ninguna: parece hecha.
    final (session, gateway) = await ready();

    await expectLater(
      session.translateUnit(
        unit: theUnit(session),
        from: 'es',
        to: 'va',
        translator: FakeTranslator(fail: true),
      ),
      throwsA(isA<TranslationException>()),
    );
    expect(gateway.commits, isEmpty);
  });

  test('en un repositorio de solo lectura se niega antes de llamar', () async {
    final gateway = FakeGateway(writable: false);
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
    await session.primeForTest(catalogue);
    final translator = FakeTranslator();

    await expectLater(
      session.translateUnit(
        unit: theUnit(session),
        from: 'es',
        to: 'va',
        translator: translator,
      ),
      throwsArgumentError,
    );
    expect(translator.asked, isEmpty, reason: 'ni se gastó la cuota');
  });
}
