/// El manifiesto de actualización: qué versión hay publicada y con qué
/// ficheros.
///
/// Va como **asset del release**, no como fichero del repositorio ni en una
/// página. Tres razones, y las tres importan:
///
/// **Hereda la privacidad del repositorio.** Un asset de un release privado
/// solo se descarga con un token que tenga acceso; un fichero en `main` o una
/// GitHub Page no dan esa garantía. El manifiesto dice dónde están los
/// binarios, así que si el manifiesto es público el inventario de lo privado
/// también lo es.
///
/// **Se publica en el mismo acto que los binarios.** Un fichero en la rama
/// principal se puede quedar apuntando a un release que falló a la mitad; un
/// asset del release o está con él o no está.
///
/// **No hay URL que se pueda saltar la autenticación.** Aquí se guarda el
/// `id` numérico del asset, que es lo que la API pide para descargarlo con un
/// `Authorization:`. No se guarda ningún `browser_download_url`, que caduca,
/// ni ningún enlace firmado, que persistiría más de la cuenta.
library;

import 'dart:convert';

import 'app_version.dart';

/// Los sistemas para los que se publica.
enum UpdatePlatform {
  macos('macos'),
  windows('windows'),
  linux('linux');

  const UpdatePlatform(this.id);

  final String id;

  static UpdatePlatform? fromId(String? id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// Qué se hace con el fichero descargado.
///
/// Un release lleva **dos** artefactos por sistema en macOS --el DMG que
/// instala una persona y el ZIP con el que se actualiza la aplicación-- y sin
/// esto no habría forma de distinguirlos: los dos son «el de macOS». El
/// campo dice para qué sirve cada uno, y el actualizador coge el suyo.
enum UpdateKind {
  /// Lo que se le da a alguien que todavía no tiene Didacta.
  installer('installer'),

  /// Lo que usa el actualizador automático.
  update('update');

  const UpdateKind(this.id);

  final String id;

  static UpdateKind? fromId(String? id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// Un artefacto publicado.
class UpdateAsset {
  const UpdateAsset({
    required this.platform,
    required this.architecture,
    required this.kind,
    required this.name,
    required this.size,
    required this.sha256,
    required this.assetId,
  });

  final UpdatePlatform platform;

  /// `universal`, `x64`, `arm64`. En macOS es siempre `universal`: Flutter
  /// produce un binario para las dos arquitecturas en un solo paso, y
  /// publicar dos DMG idénticos en contenido sería inventar una elección que
  /// nadie tiene que hacer.
  final String architecture;

  final UpdateKind kind;

  /// `Didacta-1.4.2-macos-universal.dmg`.
  final String name;

  /// En bytes. Se enseña antes de descargar y se comprueba después: un
  /// fichero del tamaño equivocado ya es una descarga rota, y saberlo
  /// ahorra calcular un SHA-256 de 90 MB para llegar a la misma conclusión.
  final int size;

  /// En minúsculas y sin prefijo.
  final String sha256;

  /// El identificador del asset en la API de GitHub.
  ///
  /// Esto y no una URL: se descarga con
  /// `GET /repos/{owner}/{repo}/releases/assets/{id}` y un `Authorization:`,
  /// que es el único camino que respeta que el repositorio sea privado.
  final int assetId;

  /// Si esta arquitectura sirve para [target].
  ///
  /// `universal` vale para todo: es literalmente lo que significa.
  bool runsOn(String target) =>
      architecture == 'universal' || architecture == target;

  static UpdateAsset? fromJson(Map<String, dynamic> json) {
    final platform = UpdatePlatform.fromId(json['platform'] as String?);
    final kind = UpdateKind.fromId(json['kind'] as String?);
    final name = json['name'] as String?;
    final sha = (json['sha256'] as String?)?.toLowerCase();
    final id = (json['assetId'] as num?)?.toInt();
    if (platform == null || kind == null || name == null || id == null) {
      return null;
    }
    // Un asset sin SHA-256 no se acepta en vez de aceptarse sin comprobar:
    // el manifiesto es de donde sale la única garantía de integridad que hay,
    // y «no venía» no puede significar «pues adelante».
    if (sha == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
    return UpdateAsset(
      platform: platform,
      architecture: json['architecture'] as String? ?? 'x64',
      kind: kind,
      name: name,
      size: (json['size'] as num?)?.toInt() ?? 0,
      sha256: sha,
      assetId: id,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform': platform.id,
    'architecture': architecture,
    'kind': kind.id,
    'name': name,
    'size': size,
    'sha256': sha256,
    'assetId': assetId,
  };
}

/// Lo que se publica junto a los binarios.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.build,
    required this.publishedAt,
    required this.releaseNotes,
    required this.assets,
    this.minimumSupportedVersion,
    this.tag,
  });

  final AppVersion version;
  final int build;
  final DateTime publishedAt;

  /// La sección del CHANGELOG de esta versión, en Markdown.
  final String releaseNotes;

  /// Desde qué versión se puede actualizar sin reinstalar.
  ///
  /// Está para el día que haga falta: si una versión cambia el formato de lo
  /// que hay en disco, alguien que venga de antes no puede saltar sin más, y
  /// hay que decírselo en vez de dejarle una instalación a medias.
  final AppVersion? minimumSupportedVersion;

  /// El tag del release, para enseñarlo y para abrir la página.
  final String? tag;

  final List<UpdateAsset> assets;

  /// El artefacto con el que se actualiza [platform] en [architecture].
  ///
  /// Devuelve `null` --y no lanza-- cuando no hay ninguno: publicar sin el
  /// de Linux es un release incompleto, no un fallo de la aplicación, y lo
  /// que toca es decir «no hay versión para tu sistema» y seguir.
  UpdateAsset? updateFor(UpdatePlatform platform, String architecture) =>
      _pick(platform, architecture, UpdateKind.update) ??
      // Sin uno específico de actualización sirve el instalador: en Windows
      // y en Linux es el mismo fichero, y allí no hay dos.
      _pick(platform, architecture, UpdateKind.installer);

  /// El que se le da a quien todavía no tiene Didacta.
  UpdateAsset? installerFor(UpdatePlatform platform, String architecture) =>
      _pick(platform, architecture, UpdateKind.installer);

  UpdateAsset? _pick(
    UpdatePlatform platform,
    String architecture,
    UpdateKind kind,
  ) {
    UpdateAsset? fallback;
    for (final asset in assets) {
      if (asset.platform != platform || asset.kind != kind) continue;
      // Exacta primero: en una máquina arm64 con un `arm64` y un `universal`
      // publicados, el nativo es el que hay que coger.
      if (asset.architecture == architecture) return asset;
      if (asset.runsOn(architecture)) fallback ??= asset;
    }
    return fallback;
  }

  /// Si [installed] se queda corta para actualizar directamente.
  bool needsFullReinstallFrom(AppVersion installed) {
    final minimum = minimumSupportedVersion;
    return minimum != null && installed < minimum;
  }

  static UpdateManifest? tryParse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      // Un manifiesto que no se entiende es un release roto, y la aplicación
      // tiene que seguir funcionando con la versión que ya tiene.
      return null;
    }
  }

  static UpdateManifest? fromJson(Map<String, dynamic> json) {
    final version = AppVersion.tryParse(json['version'] as String?);
    if (version == null) return null;
    final assets = <UpdateAsset>[];
    final raw = json['assets'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final asset = UpdateAsset.fromJson(item.cast<String, dynamic>());
        // Un asset ilegible se descarta y los demás siguen valiendo: que el
        // de Windows venga mal no puede dejar sin actualización a macOS.
        if (asset != null) assets.add(asset);
      }
    }
    return UpdateManifest(
      version: version,
      build: (json['build'] as num?)?.toInt() ?? 0,
      publishedAt:
          DateTime.tryParse(json['publishedAt'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      releaseNotes: json['releaseNotes'] as String? ?? '',
      minimumSupportedVersion: AppVersion.tryParse(
        json['minimumSupportedVersion'] as String?,
      ),
      tag: json['tag'] as String?,
      assets: assets,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version.toString(),
    'build': build,
    'tag': tag ?? version.tag,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'releaseNotes': releaseNotes,
    if (minimumSupportedVersion != null)
      'minimumSupportedVersion': minimumSupportedVersion.toString(),
    'assets': [for (final asset in assets) asset.toJson()],
  };
}
