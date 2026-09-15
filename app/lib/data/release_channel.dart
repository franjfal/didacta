/// De dónde vienen las actualizaciones: los releases de un repositorio
/// **privado** de GitHub.
///
/// Que sea privado es el punto, no un detalle: quién puede actualizar Didacta
/// es exactamente quién tiene acceso al repositorio de distribución. Dar
/// acceso a alguien es añadirlo como colaborador; quitárselo es quitarlo de
/// ahí. No hay una lista de permitidos que mantener en paralelo, ni un
/// servidor de licencias, ni nada que se pueda quedar desincronizado con la
/// realidad.
///
/// De ahí salen las dos reglas de este fichero:
///
/// **Todo pasa por la API con un `Authorization:`.** Nada de
/// `browser_download_url`, que para un repositorio privado ni siquiera
/// funciona sin sesión, y nada de enlaces firmados que sobrevivan a que a
/// alguien se le retire el acceso. Un asset se pide por su `id` con
/// `Accept: application/octet-stream`, y GitHub responde con una redirección
/// firmada de vida corta que se sigue en el momento.
///
/// **El token es el de la persona.** El mismo que ya se usa para clonar, con
/// el mismo `repo` que ya se pidió al entrar. La aplicación no tiene ninguna
/// credencial propia, así que no hay ningún secreto que pudiera filtrarse
/// desde un binario que se reparte.
///
/// Este fichero **no toca el disco**. Devuelve respuestas en streaming y las
/// escribe quien sí puede hacerlo, que es la mitad de `dart:io`. Así la
/// aplicación sigue compilando para web, donde no hay actualizaciones que
/// instalar pero sí hay una pantalla de Ajustes que enseñar.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/update_manifest.dart';

/// Por qué no se pudo comprobar o traer una actualización.
///
/// Un enum y no solo un mensaje porque la interfaz trata unos casos distinto
/// de otros: quedarse sin red es un aviso discreto, y que a alguien le hayan
/// retirado el acceso es algo que hay que decirle claramente.
enum UpdateProblem {
  /// Sin conexión, o GitHub inalcanzable.
  offline,

  /// GitHub responde, pero mal (5xx). No es culpa de nadie de aquí.
  githubDown,

  /// El token ya no vale: caducado, revocado, o la autorización retirada.
  tokenInvalid,

  /// El token vale, pero esta cuenta no tiene acceso al repositorio.
  notAuthorised,

  /// Demasiadas peticiones.
  rateLimited,

  /// No hay ningún release publicado todavía.
  noRelease,

  /// Hay release, pero le falta el manifiesto o no se entiende.
  brokenRelease,

  /// No hay artefacto para este sistema.
  noAssetForPlatform,

  /// Lo descargado no es lo que el manifiesto decía.
  checksumMismatch,

  /// La descarga se cortó a la mitad.
  downloadInterrupted,

  /// No cabe en el disco.
  noSpace,

  /// La instalación falló. La versión anterior sigue en su sitio.
  installFailed,

  /// Falta permiso para escribir donde está instalada la aplicación.
  noPermission,

  /// Lo canceló la persona.
  cancelled,
}

class UpdateException implements Exception {
  const UpdateException(this.problem, this.message, {this.detail});

  final UpdateProblem problem;

  /// Lo que se le enseña a una persona. En castellano y sin jerga.
  final String message;

  /// Lo que ayuda a diagnosticar, si hay algo. No se enseña de entrada.
  final String? detail;

  @override
  String toString() => message;
}

/// Un release del repositorio de distribución.
class ReleaseChannel {
  ReleaseChannel({
    required this.owner,
    required this.repo,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// `franjfal`.
  final String owner;

  /// `didacta_public`.
  final String repo;

  /// El de la persona que ha entrado. Puede estar vacío: entonces no se
  /// llega a preguntar nada y se dice que hace falta entrar.
  final String token;

  final http.Client _client;

  static const String base = 'https://api.github.com';

  /// El nombre del asset que lleva el manifiesto.
  static const String manifestAsset = 'latest.json';

  Map<String, String> _headers({
    String accept = 'application/vnd.github+json',
  }) => {
    'Accept': accept,
    'Authorization': 'Bearer $token',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'Didacta',
  };

  /// Si esta cuenta llega al repositorio de distribución.
  ///
  /// Es la comprobación de autorización de verdad, y es una sola petición:
  /// GitHub responde 404 --no 403-- a un repositorio privado al que no se
  /// tiene acceso, precisamente para no confirmar que existe. Aquí sabemos
  /// que existe, así que un 404 significa «esta cuenta no entra».
  Future<bool> hasAccess() async {
    if (token.isEmpty) {
      throw const UpdateException(
        UpdateProblem.tokenInvalid,
        'Entra en GitHub para poder buscar actualizaciones.',
      );
    }
    final response = await _get('$base/repos/$owner/$repo');
    if (response.statusCode == 200) return true;
    if (response.statusCode == 404) return false;
    throw _problemFor(response);
  }

  /// El manifiesto del último release, o `null` si no hay ninguno.
  Future<UpdateManifest?> latest() async {
    if (token.isEmpty) {
      throw const UpdateException(
        UpdateProblem.tokenInvalid,
        'Entra en GitHub para poder buscar actualizaciones.',
      );
    }
    final response = await _get('$base/repos/$owner/$repo/releases/latest');
    if (response.statusCode == 404) {
      // Puede ser que no haya releases, o que esta cuenta no tenga acceso al
      // repositorio. Son cosas muy distintas para quien lo está leyendo, así
      // que se distingue con una petición más en vez de adivinar.
      if (!await hasAccess()) {
        throw UpdateException(
          UpdateProblem.notAuthorised,
          'Tu cuenta de GitHub no tiene acceso a las versiones de Didacta. '
          'Pídele a quien administre $owner/$repo que te añada.',
        );
      }
      return null;
    }
    if (response.statusCode != 200) throw _problemFor(response);

    final Map<String, dynamic> release;
    try {
      release = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw const UpdateException(
        UpdateProblem.brokenRelease,
        'GitHub devolvió algo que no se entiende.',
      );
    }

    // Un release marcado como borrador o prerelease no se ofrece: el
    // workflow publica en borrador mientras sube los binarios, y ofrecer eso
    // sería ofrecer un release a medio subir.
    if (release['draft'] == true) return null;

    final assets = (release['assets'] as List?) ?? const [];
    int? manifestId;
    for (final item in assets) {
      if (item is Map && item['name'] == manifestAsset) {
        manifestId = (item['id'] as num?)?.toInt();
        break;
      }
    }
    if (manifestId == null) {
      throw UpdateException(
        UpdateProblem.brokenRelease,
        'El último release de Didacta (${release['tag_name']}) no lleva '
        'manifiesto, así que no se puede actualizar automáticamente.',
      );
    }

    final manifest = UpdateManifest.tryParse(await _assetText(manifestId));
    if (manifest == null) {
      throw const UpdateException(
        UpdateProblem.brokenRelease,
        'El manifiesto del último release no se entiende.',
      );
    }
    return manifest;
  }

  /// Abre la descarga de un asset. Quien llame se encarga de escribirla.
  Future<http.StreamedResponse> open(UpdateAsset asset) async {
    final request = http.Request(
      'GET',
      Uri.parse('$base/repos/$owner/$repo/releases/assets/${asset.assetId}'),
    )..followRedirects = true;
    // `octet-stream` es lo que hace que GitHub devuelva el fichero y no los
    // metadatos del asset en JSON.
    request.headers.addAll(_headers(accept: 'application/octet-stream'));
    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (thrown) {
      throw UpdateException(
        UpdateProblem.offline,
        'No se pudo conectar con GitHub.',
        detail: '$thrown',
      );
    }
    if (response.statusCode != 200) {
      throw UpdateException(
        response.statusCode == 401 || response.statusCode == 403
            ? UpdateProblem.tokenInvalid
            : UpdateProblem.brokenRelease,
        'No se pudo descargar ${asset.name} (${response.statusCode}).',
      );
    }
    return response;
  }

  Future<http.Response> _get(String url) async {
    try {
      return await _client.get(Uri.parse(url), headers: _headers());
    } catch (thrown) {
      throw UpdateException(
        UpdateProblem.offline,
        'No hay conexión con GitHub.',
        detail: '$thrown',
      );
    }
  }

  /// El contenido de un asset pequeño, como texto.
  ///
  /// `octet-stream` y no el JSON de siempre: con el `Accept` por defecto la
  /// API devuelve los *metadatos* del asset, no el fichero. Sirve para el
  /// manifiesto, que son dos kilobytes; un binario de 90 MB va por [open],
  /// que no lo trae entero a memoria.
  Future<String> _assetText(int id) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$base/repos/$owner/$repo/releases/assets/$id'),
        headers: _headers(accept: 'application/octet-stream'),
      );
    } catch (thrown) {
      throw UpdateException(
        UpdateProblem.offline,
        'No hay conexión con GitHub.',
        detail: '$thrown',
      );
    }
    if (response.statusCode != 200) throw _problemFor(response);
    // `bodyBytes` y no `body`: sin `charset` en la respuesta, `http` decodifica
    // como latin-1 y una tilde del CHANGELOG se rompe.
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  UpdateException _problemFor(http.Response response) {
    final status = response.statusCode;
    if (status == 401) {
      return const UpdateException(
        UpdateProblem.tokenInvalid,
        'Tu sesión de GitHub ya no vale. Vuelve a entrar desde Ajustes.',
      );
    }
    if (status == 403) {
      // 403 con `x-ratelimit-remaining: 0` es límite de peticiones; el resto
      // suele ser una autorización de la OAuth App revocada por la
      // organización.
      if (response.headers['x-ratelimit-remaining'] == '0') {
        return const UpdateException(
          UpdateProblem.rateLimited,
          'GitHub está limitando las peticiones. Inténtalo dentro de un rato.',
        );
      }
      return const UpdateException(
        UpdateProblem.notAuthorised,
        'GitHub ha rechazado la petición. Puede que se haya revocado la '
        'autorización de Didacta: vuelve a entrar desde Ajustes.',
      );
    }
    if (status == 404) {
      return UpdateException(
        UpdateProblem.notAuthorised,
        'Tu cuenta de GitHub no tiene acceso a las versiones de Didacta. '
        'Pídele a quien administre $owner/$repo que te añada.',
      );
    }
    if (status >= 500) {
      return UpdateException(
        UpdateProblem.githubDown,
        'GitHub no está respondiendo bien ahora mismo ($status). Se volverá '
        'a intentar más adelante.',
      );
    }
    return UpdateException(
      UpdateProblem.brokenRelease,
      'GitHub respondió $status.',
      detail: response.body,
    );
  }

  void close() => _client.close();
}
