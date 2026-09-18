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

/// El código del proveedor, o un error que dice cuál es el problema.
///
/// Antes de gastar la llamada: un idioma que el proveedor no conoce vuelve
/// como `400 Invalid Value` con un JSON de treinta líneas que no nombra el
/// idioma por ninguna parte.
String _codeOr(TranslationProvider provider, String language) {
  final code = providerCodeFor(provider, language);
  if (code == null) {
    throw TranslationException(
      '${provider.label} no traduce a «$language».',
      status: 400,
    );
  }
  return code;
}

/// Lo que se le cuenta a alguien de una respuesta que no es 200.
///
/// El código y lo que dijo el servidor, recortado. **Nunca la URL**: los dos
/// proveedores aceptan la clave como parámetro, así que una URL en un mensaje
/// de error es una clave en un registro que alguien pega en un correo.
String _explain(int status, String body) {
  final trimmed = body.trim();
  final detail = trimmed.length > 300
      ? '${trimmed.substring(0, 300)}…'
      : trimmed;
  return switch (status) {
    // El 400 más probable con diferencia es un idioma que el proveedor no
    // conoce. Su JSON no lo nombra --dice «Invalid Value» y ya-- así que se
    // dice aquí antes de pegar el volcado.
    400 =>
      'La petición no le gustó. Suele ser un idioma que no conoce.'
          '\n\n$detail',
    401 ||
    403 => 'No aceptó la credencial. Revisa la clave y, en Azure, la región.',
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
      final decoded = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
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
    // Los códigos del proveedor, no los de Didacta: `va` no existe para
    // Google y la respuesta es un `400 Invalid Value` que no dice cuál de los
    // cinco campos estaba mal.
    final source = _codeOr(provider, from);
    final target = _codeOr(provider, to);
    final response = await _client.post(
      _uri(''),
      headers: _headers,
      body: jsonEncode({
        'q': pieces,
        'source': source,
        'target': target,
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
    final decoded = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
        .cast<String, dynamic>();
    final translations =
        ((decoded['data'] as Map?)?['translations'] as List?) ?? const [];
    return [
      for (final item in translations)
        unescapeHtml('${(item as Map)['translatedText'] ?? ''}'),
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
      return const ProviderCheck(
        ok: true,
        message: 'Responde y acepta la clave.',
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
    final source = _codeOr(provider, from);
    final target = _codeOr(provider, to);
    final response = await _client.post(
      Uri.parse(
        '$_base/translate?api-version=3.0&from=$source&to=$target'
        '&textType=html',
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
        unescapeHtml(
          '${((item as Map)['translations'] as List).first['text'] ?? ''}',
        ),
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

/// Deshace el escapado HTML de lo que devuelve un traductor.
///
/// Se pide la traducción en formato HTML --es la única manera de que los dos
/// proveedores respeten las etiquetas `<x id="N"/>` con las que viaja
/// protegido el LaTeX-- y en HTML lo que vuelve viene escapado. Un apóstrofo,
/// que en valenciano y en catalán está en una palabra de cada cinco, vuelve
/// como `&#39;`.
///
/// Sin deshacerlo, `l'operació` se guardaba en el `.tex` como
/// `l&#39;operació`, y eso **no compila**: en LaTeX `&` es el separador de
/// columnas de una tabla, así que fuera de una da un error y dentro de una
/// parte la fila en dos.
///
/// De una pasada y no entidad por entidad: encadenando sustituciones,
/// `&amp;lt;` --que es el texto literal «&lt;»-- acabaría convertido en `<`,
/// porque la segunda pasada vería el `&lt;` que acaba de crear la primera.
String unescapeHtml(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(_entity, (match) {
    final named = match.group(1);
    if (named != null) return _named[named] ?? match.group(0)!;
    final digits = match.group(2);
    if (digits != null) {
      final code = int.tryParse(digits);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    final hex = match.group(3);
    final code = int.tryParse(hex!, radix: 16);
    return code == null ? match.group(0)! : String.fromCharCode(code);
  });
}

final RegExp _entity = RegExp(
  r'&(?:([a-zA-Z][a-zA-Z0-9]{1,9})|#([0-9]{1,7})|#[xX]([0-9a-fA-F]{1,6}));',
);

/// Las que usan los dos proveedores. Una que no esté aquí se queda como está,
/// que es mejor que convertirla en el carácter equivocado.
const Map<String, String> _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};
