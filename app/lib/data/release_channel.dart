/// De dónde vienen las actualizaciones: los releases del propio repositorio.
///
/// Didacta se publica en `franjfal/didacta`, que es público, así que este
/// fichero **no manda ninguna credencial**. Antes sí: las versiones vivían en
/// un repositorio privado y quién podía actualizar era quién tenía acceso
/// allí, de modo que cada petición iba con el token de la persona. Al abrir el
/// código esa lista dejó de existir, y con ella la mitad de este fichero.
///
/// Lo que queda es más simple y conviene dejar dicho por qué:
///
/// **Sin `Authorization:`.** La API pública de GitHub permite 60 peticiones
/// por hora y dirección IP, y Didacta hace una cada siete días. Mandar el
/// token de alguien subiría ese límite a 5000 y no compraría nada más, así
/// que no se manda: una credencial que no hace falta es una credencial que no
/// se arriesga.
///
/// **Se sigue descargando por `assetId` y no por `browser_download_url`.**
/// La dirección del asset en la API vale para un repositorio público y para
/// uno privado, así que el manifiesto no tiene que cambiar de forma si algún
/// día se vuelve a cerrar, y lo que se comprueba --el SHA-256 de lo que llega,
/// contra lo que el manifiesto dice-- es lo mismo en los dos casos.
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
  ReleaseChannel({required this.owner, required this.repo, http.Client? client})
    : _client = client ?? http.Client();

  /// `franjfal`.
  final String owner;

  /// `didacta`.
  final String repo;

  final http.Client _client;

  static const String base = 'https://api.github.com';

  /// El nombre del asset que lleva el manifiesto.
  static const String manifestAsset = 'latest.json';

  Map<String, String> _headers({
    String accept = 'application/vnd.github+json',
  }) => {
    'Accept': accept,
    'X-GitHub-Api-Version': '2022-11-28',
    // GitHub rechaza una petición sin `User-Agent`, así que no es cortesía:
    // es lo que hace que la API conteste.
    'User-Agent': 'Didacta',
  };

  /// El manifiesto del último release, o `null` si no hay ninguno.
  Future<UpdateManifest?> latest() async {
    final response = await _get('$base/repos/$owner/$repo/releases/latest');
    // Sin release publicado todavía. Con el repositorio público es el único
    // significado que puede tener un 404 aquí, que es justo lo que se ganó al
    // abrirlo: antes había que preguntar otra vez para saber si lo que
    // faltaba era el release o el permiso.
    if (response.statusCode == 404) return null;
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
        response.statusCode == 403
            ? UpdateProblem.rateLimited
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
    // Sin credencial, un 403 de la API pública es casi siempre el límite de
    // peticiones por dirección IP. Se distingue igualmente por la cabecera,
    // porque el mensaje que hay que dar es distinto: esperar un rato es algo
    // que alguien puede hacer, y «GitHub ha dicho que no» no lo es.
    if (status == 403 || status == 429) {
      if (response.headers['x-ratelimit-remaining'] == '0' || status == 429) {
        return const UpdateException(
          UpdateProblem.rateLimited,
          'GitHub está limitando las peticiones. Inténtalo dentro de un rato.',
        );
      }
      return const UpdateException(
        UpdateProblem.githubDown,
        'GitHub ha rechazado la petición.',
      );
    }
    if (status == 404) {
      return UpdateException(
        UpdateProblem.noRelease,
        'No encuentro las versiones de Didacta en $owner/$repo.',
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
