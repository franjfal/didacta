/// Google y Azure, por HTTP.
///
/// Los dos hablan JSON y los dos admiten HTML, que es lo que hace posible
/// mandarles un `.tex` protegido: lo opaco viaja como `<x id="N"/>` y las dos
/// documentan que no tocan las etiquetas. Sin eso habría que trocear el
/// fichero en fragmentos sueltos y perder el contexto, que es justo lo que
/// hace que una traducción automática suene a máquina.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/translation.dart';
import 'translator.dart';

/// El de esta credencial, o null si no está completa.
Translator? translatorFor(
  TranslationProvider provider,
  Credentials credentials, {
  http.Client? client,
}) {
  if (!credentials.complete(provider)) return null;
  return switch (provider) {
    TranslationProvider.google => GoogleTranslator(credentials, client: client),
    TranslationProvider.azure => AzureTranslator(credentials, client: client),
  };
}

/// Lo que se le cuenta a alguien de una respuesta que no es 200.
///
/// El código y lo que dijo el servidor, recortado. **Nunca la URL**: los dos
/// proveedores aceptan la clave como parámetro, así que una URL en un mensaje
/// de error es una clave en un registro que alguien pega en un correo.
String _explain(int status, String body) {
  final trimmed = body.trim();
  final detail = trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
  return switch (status) {
    400 => 'La petición no le gustó: $detail',
    401 || 403 =>
      'No aceptó la credencial. Revisa la clave y, en Azure, la región.',
    404 => 'No encontró el servicio. Revisa el endpoint si has puesto uno.',
    429 => 'Estás llamando más rápido de lo que admite. Prueba en un rato.',
    _ => 'Contestó $status: $detail',
  };
}

class GoogleTranslator implements Translator {
  GoogleTranslator(this.credentials, {http.Client? client})
    : _client = client ?? http.Client();

  final Credentials credentials;
  final http.Client _client;

  @override
  TranslationProvider get provider => TranslationProvider.google;

  Uri _uri(String path) {
    final base = credentials.endpoint.trim().isEmpty
        ? 'https://translation.googleapis.com'
        : credentials.endpoint.trim();
    return Uri.parse('$base/language/translate/v2$path');
  }

  /// La clave en una cabecera y no en la URL.
  ///
  /// Google admite las dos; en la cabecera no aparece en los registros de
  /// ningún proxy por el que pase, ni en un mensaje de error que imprima la
  /// dirección.
  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    'X-goog-api-key': credentials.key.trim(),
  };

  @override
  Future<ProviderCheck> check() async {
    try {
      final response = await _client
          .get(_uri('/languages'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return ProviderCheck(
          ok: false,
          message: _explain(response.statusCode, response.body),
        );
      }
      final decoded =
          (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
              .cast<String, dynamic>();
      final languages = [
        for (final item
            in ((decoded['data'] as Map?)?['languages'] as List?) ?? const [])
          '${(item as Map)['language']}',
      ];
      return ProviderCheck(
        ok: true,
        message: 'Responde. Dice traducir a ${languages.length} idiomas.',
        languages: languages,
      );
    } catch (error) {
      return ProviderCheck(ok: false, message: _reach(error));
    }
  }

  @override
  Future<List<String>> translate(
    List<String> pieces, {
    required String from,
    required String to,
  }) async {
    if (pieces.isEmpty) return const [];
    final response = await _client.post(
      _uri(''),
      headers: _headers,
      body: jsonEncode({
        'q': pieces,
        'source': from,
        'target': to,
        // HTML y no `text`: es lo que hace que respete las etiquetas con las
        // que viajan las fórmulas y los `\label`.
        'format': 'html',
      }),
    );
    if (response.statusCode != 200) {
      throw TranslationException(
        _explain(response.statusCode, response.body),
        status: response.statusCode,
      );
    }
    final decoded =
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
            .cast<String, dynamic>();
    final translations =
        ((decoded['data'] as Map?)?['translations'] as List?) ?? const [];
    return [
      for (final item in translations)
        '${(item as Map)['translatedText'] ?? ''}',
    ];
  }
}

class AzureTranslator implements Translator {
  AzureTranslator(this.credentials, {http.Client? client})
    : _client = client ?? http.Client();

  final Credentials credentials;
  final http.Client _client;

  @override
  TranslationProvider get provider => TranslationProvider.azure;

  String get _base => credentials.endpoint.trim().isEmpty
      ? 'https://api.cognitive.microsofttranslator.com'
      : credentials.endpoint.trim();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    'Ocp-Apim-Subscription-Key': credentials.key.trim(),
    // La región es obligatoria con un recurso de varios servicios, y sin ella
    // Azure contesta 401 hablando de la suscripción, que despista.
    'Ocp-Apim-Subscription-Region': credentials.region.trim(),
  };

  @override
  Future<ProviderCheck> check() async {
    try {
      // `languages` no pide credencial, así que comprobarla con eso diría que
      // todo va bien con una clave inventada. Se traduce una palabra: es la
      // llamada más corta que de verdad la usa.
      final response = await _client
          .post(
            Uri.parse('$_base/translate?api-version=3.0&from=es&to=en'),
            headers: _headers,
            body: jsonEncode([
              {'Text': 'hola'},
            ]),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return ProviderCheck(
          ok: false,
          message: _explain(response.statusCode, response.body),
        );
      }
      return const ProviderCheck(ok: true, message: 'Responde y acepta la clave.');
    } catch (error) {
      return ProviderCheck(ok: false, message: _reach(error));
    }
  }

  @override
  Future<List<String>> translate(
    List<String> pieces, {
    required String from,
    required String to,
  }) async {
    if (pieces.isEmpty) return const [];
    final response = await _client.post(
      Uri.parse(
        '$_base/translate?api-version=3.0&from=$from&to=$to&textType=html',
      ),
      headers: _headers,
      body: jsonEncode([
        for (final piece in pieces) {'Text': piece},
      ]),
    );
    if (response.statusCode != 200) {
      throw TranslationException(
        _explain(response.statusCode, response.body),
        status: response.statusCode,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    return [
      for (final item in decoded)
        '${((item as Map)['translations'] as List).first['text'] ?? ''}',
    ];
  }
}

/// Un fallo de red, contado sin repetir lo que se mandó.
String _reach(Object error) {
  final text = '$error';
  // Por si acaso: un `ClientException` de Dart incluye la URI, y aunque las
  // nuestras no llevan la clave, un endpoint privado tampoco tiene por qué
  // salir en un mensaje que alguien va a pegar en un correo.
  final clean = text.contains('uri=') ? text.split('uri=').first.trim() : text;
  return 'No se pudo hablar con el proveedor: $clean';
}
