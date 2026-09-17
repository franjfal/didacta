/// Las credenciales de traducción: dónde viven y por dónde no pueden salir.
///
/// Dos ámbitos que no se mezclan nunca, y es lo que da forma a todo esto. La
/// configuración lingüística --a qué idiomas se traduce, la memoria
/// terminológica, las decisiones-- es **contenido**: va en el repositorio, se
/// versiona y se comparte. Las credenciales son **configuración privada de
/// esta máquina**: llavero del sistema, y nada más.
///
/// Una clave no puede acabar en un repositorio de contenido, ni en git, ni en
/// un fichero versionado, ni en la memoria de traducción, ni copiada entre
/// repositorios, ni en un log, ni en un mensaje de error, ni en una
/// exportación. La mitad de este fichero prueba justamente eso, porque son
/// fugas que no se ven al escribir el código y se ven en el registro que otra
/// persona pega en un correo.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:didacta_app/data/translation_secrets.dart';
import 'package:didacta_app/data/translator.dart';
import 'package:didacta_app/data/translator_http.dart';
import 'package:didacta_app/model/translation.dart';

const String secreta = 'AIzaSyD-clave-larguisima-de-verdad-1234';

Credentials get google => const Credentials(key: secreta);

Credentials get azure => const Credentials(key: secreta, region: 'westeurope');

void main() {
  group('la forma de una credencial', () {
    test('Google solo pide la clave', () {
      expect(google.complete(TranslationProvider.google), isTrue);
      expect(const Credentials().complete(TranslationProvider.google), isFalse);
    });

    test('Azure pide además la región, y se dice antes de llamar', () {
      // Sin región Azure contesta 401 hablando de la suscripción, que manda a
      // revisar la clave --que está bien-- en vez de la región.
      const sinRegion = Credentials(key: secreta);
      expect(sinRegion.complete(TranslationProvider.azure), isFalse);
      expect(sinRegion.missing(TranslationProvider.azure), contains('región'));
      expect(azure.complete(TranslationProvider.azure), isTrue);
    });

    test('la pista deja reconocerla sin poder usarla', () {
      expect(google.hint, endsWith('1234'));
      expect(google.hint, isNot(contains('AIza')));
    });

    test('y una clave corta no enseña ni el final', () {
      expect(const Credentials(key: 'abc123').hint, '••••');
    });
  });

  group('por dónde no puede salir', () {
    test('el `toString` no lleva la clave', () {
      // El que genera Dart la imprimiría, y un objeto así acaba en un `print`
      // de depuración o dentro de una excepción sin que nadie lo decida.
      expect('$azure', isNot(contains(secreta)));
      expect('$azure', contains('westeurope'));
    });

    test('ni interpolada en un mensaje', () {
      final message = 'No se pudo usar $google al traducir';
      expect(message, isNot(contains(secreta)));
    });

    test('ni el error de un proveedor que la rechaza', () async {
      // El caso real: 401. Es cuando más tentador es incluir lo que se mandó.
      final client = MockClient(
        (_) async => http.Response('{"error":"unauthorized"}', 401),
      );
      final check = await GoogleTranslator(google, client: client).check();

      expect(check.ok, isFalse);
      expect(check.message, isNot(contains(secreta)));
      expect(check.message, contains('credencial'));
    });

    test('ni el error de una petición que no le gusta', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"bad"}', 400),
      );
      final check = await AzureTranslator(azure, client: client).check();
      expect(check.message, isNot(contains(secreta)));
    });

    test('ni el de una red que no llega', () async {
      // `ClientException` lleva la URI dentro, y un endpoint privado tampoco
      // tiene por qué salir en un mensaje que alguien va a pegar en un correo.
      final client = MockClient(
        (request) async => throw http.ClientException('caída', request.url),
      );
      final check = await GoogleTranslator(
        const Credentials(key: secreta, endpoint: 'https://interno.uv.es'),
        client: client,
      ).check();

      expect(check.ok, isFalse);
      expect(check.message, isNot(contains(secreta)));
      expect(check.message, isNot(contains('interno.uv.es')));
    });

    test('ni la excepción al traducir', () async {
      final client = MockClient((_) async => http.Response('nope', 403));
      expect(
        () => GoogleTranslator(
          google,
          client: client,
        ).translate(const ['Hola'], from: 'es', to: 'en'),
        throwsA(
          isA<TranslationException>().having(
            (e) => '$e',
            'el texto del error',
            isNot(contains(secreta)),
          ),
        ),
      );
    });

    test('la clave viaja en una cabecera, no en la dirección', () async {
      // En la URL aparecería en los registros de cualquier proxy por el que
      // pase, y en cualquier mensaje que imprima la dirección.
      Uri? seen;
      Map<String, String>? headers;
      final client = MockClient((request) async {
        seen = request.url;
        headers = request.headers;
        return http.Response('{"data":{"languages":[]}}', 200);
      });

      await GoogleTranslator(google, client: client).check();

      expect('$seen', isNot(contains(secreta)));
      expect(headers!['X-goog-api-key'], secreta);
    });

    test('y en Azure, también', () async {
      Uri? seen;
      Map<String, String>? headers;
      final client = MockClient((request) async {
        seen = request.url;
        headers = request.headers;
        return http.Response('[]', 200);
      });

      await AzureTranslator(azure, client: client).check();

      expect('$seen', isNot(contains(secreta)));
      expect(headers!['Ocp-Apim-Subscription-Key'], secreta);
      expect(headers!['Ocp-Apim-Subscription-Region'], 'westeurope');
    });
  });

  group('el llavero', () {
    test('guarda y devuelve lo que se le da', () async {
      final secrets = MemoryTranslationSecrets();
      await secrets.write(TranslationProvider.azure, azure);

      final back = await secrets.read(TranslationProvider.azure);
      expect(back.key, secreta);
      expect(back.region, 'westeurope');
    });

    test('cada proveedor por su lado', () async {
      // Quitar la de Azure no puede llevarse la de Google.
      final secrets = MemoryTranslationSecrets();
      await secrets.write(TranslationProvider.google, google);
      await secrets.write(TranslationProvider.azure, azure);

      await secrets.clear(TranslationProvider.azure);

      expect((await secrets.read(TranslationProvider.google)).key, secreta);
      expect((await secrets.read(TranslationProvider.azure)).isEmpty, isTrue);
    });

    test('guardar una vacía es quitarla', () async {
      final secrets = MemoryTranslationSecrets();
      await secrets.write(TranslationProvider.google, google);
      await secrets.write(TranslationProvider.google, const Credentials());
      expect((await secrets.read(TranslationProvider.google)).isEmpty, isTrue);
    });

    test('sin sitio seguro no se guarda, y se dice por qué', () async {
      // En un navegador, «almacenamiento seguro» es almacenamiento del
      // navegador, y eso lo lee cualquier script del origen.
      final secrets = MemoryTranslationSecrets(safe: false);
      expect(
        () => secrets.write(TranslationProvider.google, google),
        throwsA(isA<TranslationSecretsException>()),
      );
    });

    test('lo que se guarda es JSON, y solo eso', () {
      // Para que quede claro qué acaba en el llavero: los campos, nada más.
      expect(jsonDecode(jsonEncode(azure.toJson())), {
        'key': secreta,
        'region': 'westeurope',
      });
    });
  });

  group('los códigos de cada proveedor', () {
    test('el valenciano se pide como catalán', () async {
      // El fallo que lo destapó: `va` es un código de Didacta y ningún
      // traductor automático lo conoce. Google contesta `400 Invalid Value`
      // con un JSON de treinta líneas que no nombra el idioma.
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({
            'data': {
              'translations': [
                {'translatedText': 'El conjunt.'},
              ],
            },
          }),
          200,
        );
      });

      await GoogleTranslator(
        google,
        client: client,
      ).translate(const ['El conjunto.'], from: 'es', to: 'va');

      expect(body!['target'], 'ca');
      expect(body!['source'], 'es');
    });

    test('y en Azure igual', () async {
      Uri? seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(
          jsonEncode([
            {
              'translations': [
                {'text': 'El conjunt.'},
              ],
            },
          ]),
          200,
        );
      });

      await AzureTranslator(
        azure,
        client: client,
      ).translate(const ['El conjunto.'], from: 'es', to: 'va');

      expect('$seen', contains('to=ca'));
    });

    test('los demás van tal cual', () async {
      for (final code in [
        'es',
        'ca',
        'gl',
        'eu',
        'en',
        'fr',
        'de',
        'it',
        'pt',
      ]) {
        expect(
          providerCodeFor(TranslationProvider.google, code),
          code,
          reason: code,
        );
      }
    });

    test('y se puede preguntar cuál se va a aproximar', () {
      // Para decirlo **antes** de traducir: quien revise el borrador tiene
      // que saber qué está revisando.
      expect(approximationFor(TranslationProvider.google, 'va'), 'ca');
      expect(approximationFor(TranslationProvider.google, 'ca'), isNull);
      expect(approximationFor(TranslationProvider.azure, 'es'), isNull);
    });
  });

  group('traducir', () {
    test('se manda como HTML, que es lo que respeta las etiquetas', () async {
      // Es lo que permite mandar un `.tex` protegido: las fórmulas y los
      // `\\label` viajan como `<x id="N"/>` y los dos proveedores documentan
      // que no las tocan.
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({
            'data': {
              'translations': [
                {'translatedText': 'The set <x id="0"/> is open.'},
              ],
            },
          }),
          200,
        );
      });

      final out = await GoogleTranslator(google, client: client).translate(
        const ['El conjunto <x id="0"/> es abierto.'],
        from: 'es',
        to: 'en',
      );

      expect(body!['format'], 'html');
      expect(out.single, contains('<x id="0"/>'));
    });

    test('Azure manda el tipo de texto en la dirección', () async {
      Uri? seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(
          jsonEncode([
            {
              'translations': [
                {'text': 'Hello'},
              ],
            },
          ]),
          200,
        );
      });

      final out = await AzureTranslator(
        azure,
        client: client,
      ).translate(const ['Hola'], from: 'es', to: 'en');

      expect('$seen', contains('textType=html'));
      expect(out.single, 'Hello');
    });

    test('nada que traducir no llama a nadie', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      expect(
        await GoogleTranslator(
          google,
          client: client,
        ).translate(const [], from: 'es', to: 'en'),
        isEmpty,
      );
      expect(called, isFalse);
    });

    test('sin credencial completa no hay traductor', () async {
      // Antes de llamar y gastar cuota por una configuración a medias.
      expect(
        translatorFor(TranslationProvider.azure, const Credentials(key: 'x')),
        isNull,
      );
      expect(
        translatorFor(TranslationProvider.azure, azure),
        isA<AzureTranslator>(),
      );
    });
  });
}
