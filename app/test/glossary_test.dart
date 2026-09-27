/// El glosario y lo que la memoria aprende al revisar.
///
/// * el glosario se lee y se escribe como una tabla de tabuladores, y se
///   juntan los de todos los repositorios;
/// * al traducir con la máquina, un término que no sale como se dijo se
///   avisa --no se cambia--;
/// * al aprobar una traducción corregida, la memoria aprende cada párrafo
///   corregido, solo si las dos versiones tienen la misma forma.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/translator.dart';
import 'package:didacta_app/model/glossary.dart';
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/model/translation_memory.dart';
import 'package:didacta_app/model/translation_run.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/glossary_editor.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

/// Traduce palabra por palabra con un diccionario de juguete.
class ToyTranslator implements Translator {
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
  }) async => [
    for (final piece in pieces)
      piece.replaceAll('sucesión', 'seqüència').replaceAll('La ', 'La '),
  ];
}

void main() {
  test('se lee y se escribe como una tabla', () {
    final glossary = Glossary.parse(
      '# comentario\nes\tva\ten\nsucesión\tsuccessió\tsequence\nnorma\tnorma\t\n',
    );
    expect(glossary.languages, ['es', 'va', 'en']);
    expect(glossary.terms, hasLength(2));
    expect(glossary.checksFor('es', 'en'), hasLength(1));
    final again = Glossary.parse(glossary.toTsv());
    expect(again.terms, glossary.terms);
  });

  test('se juntan los de todos, sin repetir', () {
    final merged = Glossary.merge([
      Glossary.parse('es\tva\nsucesión\tsuccessió\n'),
      Glossary.parse('es\ten\nsucesión\tsequence\nnorma\tnorm\n'),
    ]);
    expect(merged.languages, ['es', 'va', 'en']);
    expect(merged.terms, hasLength(2));
  });

  test('al traducir, lo que no sale como se dijo se avisa', () async {
    final gateway = FakeGateway(
      files: {
        '$unitPath/es.tex': 'La sucesión converge.\n',
        glossaryPath: 'es\tva\nsucesión\tsuccessió\n',
      },
    );
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
    await session.primeForTest(catalogue);
    await session.useCloneForTest('/tmp/didacta-test');
    final unit = session.catalogue.units.firstWhere((u) => u.path == unitPath);
    final batch = await session.translateUnits(
      tasks: [(unit: unit, from: 'es', to: 'va')],
      translator: ToyTranslator(),
    );
    expect(batch.warnings.join(), contains('«successió»'));
    // Y no se ha cambiado solo.
    expect(gateway.files['$unitPath/va.tex'], contains('seqüència'));
  });

  test('la memoria aprende los párrafos corregidos', () {
    const original = 'Una frase con \$x\$.\n\nOtra frase.\n';
    const corrected = 'Una frase amb \$x\$.\n\nUna altra frase.\n';
    final learned = learnFromReview(original, corrected);
    expect(learned, hasLength(2));
    expect(learned.first.source, contains('<x id="0"/>'));
    expect(learned.first.target, contains('amb'));
  });

  test('pero no si la forma no coincide', () {
    const original = 'Una frase con \$x\$.\n\nOtra frase.\n';
    expect(learnFromReview(original, 'Una sola frase.\n'), isEmpty);
    expect(
      learnFromReview(original, 'Una frase amb \$y\$.\n\nUna altra.\n'),
      isEmpty,
    );
  });

  test('al aprobar una corregida, la memoria lo guarda aparte', () async {
    final gateway = FakeGateway(
      files: {
        '$unitPath/es.tex': 'Una frase.\n',
        '$unitPath/va.tex': 'Una frasse.\n',
        '$unitPath/unit.yaml': unitYaml,
      },
    );
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
    await session.primeForTest(catalogue);
    final unit = session.catalogue.units.firstWhere((u) => u.path == unitPath);
    await session.approveTranslation(
      unit: unit,
      language: 'va',
      text: 'Una frase.\n',
      sha: 'sha-$unitPath/va.tex',
    );
    final memory = gateway.files[memoryPath('es', 'va')];
    expect(memory, isNull);
    // «Una frase.» es igual en los dos: no hay nada que aprender. Con una
    // corrección de verdad, sí.
    await session.approveTranslation(
      unit: unit,
      language: 'va',
      text: 'Una frase ben feta.\n',
      sha: gateway.commits.isEmpty ? '' : 'nuevo-sha',
    );
    expect(gateway.files[memoryPath('es', 'va')], contains('ben feta'));
  });

  testWidgets('en Ajustes, la tabla guarda en el repositorio', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateway = FakeGateway(files: {});
    final catalogue = catalogueWith(defaultUnits());
    final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
    await session.primeForTest(catalogue);
    await session.useCloneForTest('/tmp/didacta-test');
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: Scaffold(body: GlossarySection(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ningún término todavía.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-glossary')));
    await tester.pumpAndSettle();
    final languages = session.catalogue.languagesOf(session.snippetRepos.first);
    await tester.enterText(
      find.byKey(Key('glossary-0-${languages[0]}')),
      'sucesión',
    );
    await tester.enterText(
      find.byKey(Key('glossary-0-${languages[1]}')),
      'successió',
    );
    await tester.tap(find.byKey(const Key('glossary-save')));
    await tester.pumpAndSettle();
    expect(gateway.files[glossaryPath], contains('sucesión\tsuccessió'));
    expect(
      tester.widget<Text>(find.byKey(const Key('glossary-summary'))).data,
      startsWith('1 término(s)'),
    );
  });
}
