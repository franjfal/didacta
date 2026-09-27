/// Traducir en tanda: cuántos cambios deja, cuándo para y qué aprovecha.
///
/// Una tanda de doscientas lecciones dejaba cuatrocientos commits --el texto
/// y la memoria, por cada una--. Ahora deja uno de material por repositorio y
/// uno de memoria por par de idiomas. Lo que se fija aquí:
///
/// * el material de toda la tanda va en **un** cambio, y la memoria en otro;
/// * «Detener» para antes de la siguiente, y lo ya traducido se guarda;
/// * lo que se pide en la primera lección sale de la memoria en la segunda;
/// * el título de la lección se traduce también, en el mismo cambio;
/// * la estimación cuenta lo mismo que luego se manda.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/data/translator.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/model/translation_memory.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/translate_unit.dart';

import 'fixture.dart';

const String banach = 'content/analysis/normed/banach';

/// Un traductor de mentira que respeta las etiquetas y pasa a mayúsculas.
class UpperTranslator implements Translator {
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
    final tag = RegExp(r'<x id="\d+"/>');
    return [
      for (final piece in pieces)
        piece.splitMapJoin(
          tag,
          onMatch: (m) => m.group(0)!,
          onNonMatch: (text) => text.toUpperCase(),
        ),
    ];
  }
}

const String shared = 'La norma de un vector es su longitud.';

Future<(FakeSession, FakeGateway)> ready() async {
  final gateway = FakeGateway(
    files: {
      '$unitPath/es.tex': '$shared\n\nSe escribe con dos barras.\n',
      '$unitPath/unit.yaml': unitYaml,
      '$banach/es.tex': '$shared\n\nUn espacio completo.\n',
    },
  );
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  return (session, gateway);
}

Unit unitAt(FakeSession session, String path) =>
    session.catalogue.units.firstWhere((u) => u.path == path);

List<TranslationTask> both(FakeSession session) => [
  (unit: unitAt(session, unitPath), from: 'es', to: 'va'),
  (unit: unitAt(session, banach), from: 'es', to: 'va'),
];

void main() {
  test('el material de la tanda va en un solo cambio, y la memoria en '
      'otro', () async {
    final (session, gateway) = await ready();
    final batch = await session.translateUnits(
      tasks: both(session),
      translator: UpperTranslator(),
    );

    expect(batch.written, hasLength(2));
    expect(batch.commits, 1);
    expect(gateway.batches, hasLength(1));
    expect(
      gateway.batches.single,
      unorderedEquals([
        '$unitPath/va.tex',
        '$unitPath/unit.yaml',
        '$banach/va.tex',
        '$banach/unit.yaml',
      ]),
    );
    // Y la memoria, aparte y una vez.
    final memory = gateway.commits
        .where((c) => c.path == memoryPath('es', 'va'))
        .toList();
    expect(memory, hasLength(1));
    expect(
      gateway.commits.where((c) => c.path == '$unitPath/va.tex').single.message,
      contains('2 lecciones'),
    );
  });

  test(
    'lo que se pide en la primera sale de la memoria en la segunda',
    () async {
      final (session, _) = await ready();
      final translator = UpperTranslator();
      await session.translateUnits(
        tasks: both(session),
        translator: translator,
      );
      final everything = [for (final call in translator.asked) ...call];
      expect(everything.where((piece) => piece == shared), hasLength(1));
    },
  );

  test('el título se traduce también, en el mismo cambio', () async {
    final (session, gateway) = await ready();
    await session.translateUnits(
      tasks: [(unit: unitAt(session, unitPath), from: 'es', to: 'va')],
      translator: UpperTranslator(),
    );
    final yaml = gateway.files['$unitPath/unit.yaml']!;
    expect(yaml, contains('va: ESPACIOS NORMADOS'));
    expect(yaml, contains('es: Espacios normados'));
  });

  test('detener para antes de la siguiente y guarda lo hecho', () async {
    final (session, gateway) = await ready();
    var done = 0;
    final batch = await session.translateUnits(
      tasks: both(session),
      translator: UpperTranslator(),
      stop: () => done >= 1,
      onProgress: (count, _) => done = count,
    );
    expect(batch.stopped, isTrue);
    expect(batch.written, hasLength(1));
    expect(gateway.files.containsKey('$unitPath/va.tex'), isTrue);
    expect(gateway.files.containsKey('$banach/va.tex'), isFalse);
  });

  test(
    'la estimación cuenta lo repetido una vez, como luego se manda',
    () async {
      final (session, _) = await ready();
      final estimate = await session.estimateTranslation(both(session));
      expect(estimate.files, 2);
      expect(estimate.segments, 4);
      expect(estimate.reused, 1);

      final translator = UpperTranslator();
      await session.translateUnits(
        tasks: both(session),
        translator: translator,
      );
      final sent = [
        for (final call in translator.asked)
          for (final piece in call)
            // El título va en la misma petición y no está en la estimación.
            if (piece != 'Espacios normados' && piece != 'Espacios de Banach')
              piece,
      ];
      expect(
        sent.fold<int>(0, (sum, piece) => sum + piece.length),
        estimate.characters,
      );
    },
  );

  testWidgets('el diálogo dice cuánto se va a mandar y cuánto costaría', (
    tester,
  ) async {
    final secrets = MemoryTranslationSecrets();
    await secrets.write(
      TranslationProvider.google,
      const Credentials(key: 'AIza-una-clave'),
    );
    final gateway = FakeGateway();
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(
      gatewayOverride: gateway,
      catalogue: catalogue,
      translationSecretsOverride: secrets,
    );
    await session.primeForTest(catalogue);
    await session.useCloneForTest('/tmp/didacta-test');
    session.language = 'va';

    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(
            body: TranslateDialog(
              session: session,
              units: [unitAt(session, unitPath)],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final line = find.byKey(const Key('translate-estimate'));
    expect(line, findsOneWidget);
    expect(
      find.descendant(
        of: line,
        matching: find.textContaining('caracteres que mandar'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: find.textContaining('el millón')),
      findsOneWidget,
    );
  });
}
