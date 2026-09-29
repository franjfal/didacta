/// Apertium: el valenciano de verdad, gratis y sin clave.
///
/// Google y Azure no distinguen el valenciano del catalán central; Apertium
/// sí (`cat_valencia`). Traduce un texto por petición, así que los trozos van
/// juntos con un separador que respeta, y se parten a la vuelta. Lo que se
/// fija aquí es eso, y lo que no puede hacer: un par que no tiene se dice
/// antes de llamar.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/data/translator.dart';
import 'package:didacta_app/data/translator_http.dart';
import 'package:didacta_app/model/translation.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/translation_settings.dart';

/// Un Apertium de mentira que «traduce» a mayúsculas y apunta lo pedido.
MockClient apertium(List<http.Request> asked) =>
    MockClient((request) async => answer(asked, request));

/// Lo que contesta [apertium] a [request].
Future<http.Response> answer(
  List<http.Request> asked,
  http.Request request,
) async {
  asked.add(request);
  if (request.url.path.endsWith('/listPairs')) {
    return http.Response(
      jsonEncode({
        'responseData': [
          {'sourceLanguage': 'spa', 'targetLanguage': 'cat_valencia'},
        ],
      }),
      200,
    );
  }
  final q = request.bodyFields['q']!;
  return http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'responseData': {'translatedText': q.toUpperCase()},
        'responseStatus': 200,
      }),
    ),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  const on = Credentials(key: 'on');

  test('los trozos van juntos, al valenciano, y vuelven partidos', () async {
    final asked = <http.Request>[];
    final translator =
        translatorFor(
              TranslationProvider.apertium,
              on,
              client: apertium(asked),
            )!
            as ApertiumTranslator;
    final out = await translator.translate(
      ['uno <x id="1"/>', 'dos', 'tres'],
      from: 'es',
      to: 'va',
    );
    expect(out, ['UNO <X ID="1"/>', 'DOS', 'TRES']);
    expect(asked, hasLength(1));
    expect(asked.single.bodyFields['langpair'], 'spa|cat_valencia');
    expect(asked.single.bodyFields['format'], 'html');
  });

  test('si la conexión se cae antes de contestar, se repite una vez', () async {
    // El cliente reutiliza la conexión entre lecciones, y el servidor puede
    // haberla cerrado mientras se guardaba la anterior: en una tanda de
    // verdad, una de cada tres volvía así.
    final asked = <http.Request>[];
    var dropped = 0;
    final flaky = MockClient((request) async {
      if (dropped == 0) {
        dropped += 1;
        throw http.ClientException(
          'Connection closed before full header was received',
          request.url,
        );
      }
      return answer(asked, request);
    });
    final translator = translatorFor(
      TranslationProvider.apertium,
      on,
      client: flaky,
    )!;
    final out = await translator.translate(['uno'], from: 'es', to: 'va');
    expect(out, ['UNO']);
    expect(dropped, 1);
  });

  test('una respuesta con error no se repite', () async {
    var calls = 0;
    final failing = MockClient((request) async {
      calls += 1;
      return http.Response('mal', 500);
    });
    final translator = translatorFor(
      TranslationProvider.apertium,
      on,
      client: failing,
    )!;
    await expectLater(
      translator.translate(['uno'], from: 'es', to: 'va'),
      throwsA(isA<TranslationException>()),
    );
    expect(calls, 1);
  });

  test('un texto largo va en varias peticiones', () async {
    final asked = <http.Request>[];
    final translator = translatorFor(
      TranslationProvider.apertium,
      on,
      client: apertium(asked),
    )!;
    final pieces = [for (var i = 0; i < 5; i += 1) 'x' * 2500];
    final out = await translator.translate(pieces, from: 'es', to: 'va');
    expect(out, hasLength(5));
    expect(asked.length, greaterThan(1));
  });

  test('un par que no tiene se dice sin llamar', () async {
    final asked = <http.Request>[];
    final translator = translatorFor(
      TranslationProvider.apertium,
      on,
      client: apertium(asked),
    )!;
    expect(
      () => translator.translate(['hola'], from: 'es', to: 'de'),
      throwsA(isA<TranslationException>()),
    );
    expect(asked, isEmpty);
  });

  test('los pares y las variantes', () {
    expect(supportsPair(TranslationProvider.apertium, 'es', 'va'), isTrue);
    expect(supportsPair(TranslationProvider.apertium, 'va', 'es'), isTrue);
    expect(supportsPair(TranslationProvider.apertium, 'es', 'de'), isFalse);
    expect(supportsPair(TranslationProvider.google, 'es', 'de'), isTrue);
    // El valenciano es valenciano: no hay aproximación que avisar.
    expect(approximationFor(TranslationProvider.apertium, 'va'), isNull);
    expect(approximationFor(TranslationProvider.google, 'va'), 'ca');
  });

  test('sin encender no hay traductor', () {
    expect(
      translatorFor(TranslationProvider.apertium, const Credentials()),
      isNull,
    );
  });

  testWidgets('en Ajustes, apagado de salida y un interruptor para '
      'encenderlo', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final secrets = MemoryTranslationSecrets();
    await tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TranslationSection(secrets: secrets),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('translation-apertium-on'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      (await secrets.read(
        TranslationProvider.apertium,
      )).complete(TranslationProvider.apertium),
      isTrue,
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
}
