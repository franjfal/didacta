/// Dónde se guarda el token de GitHub, y qué comprueba antes de guardarlo.
///
/// Lo que había aquí antes eran **dos** formas de llegar al repositorio --un
/// token directo a la API desde el navegador, y un Worker que guardaba el
/// token por ti y aplicaba un `access.json`-- porque un navegador no puede
/// guardar un secreto. Las dos se han ido con Firebase: la aplicación es de
/// escritorio y trabaja sobre clones, y quién puede escribir lo dice GitHub.
///
/// Queda lo único que sigue siendo cierto: un token es una credencial y va al
/// llavero del sistema.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secrets.dart';

/// Lo que puede fallar al guardar una credencial.
class RepositoryAccessException implements Exception {
  const RepositoryAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TokenStore implements SecretStore {
  TokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Not synchronised to iCloud: a repository credential should
            // stay on the machine it was authorised for.
            iOptions: IOSOptions(synchronizable: false),
            mOptions: MacOsOptions(
              synchronizable: false,
              // El llavero de siempre, no el «data protection keychain».
              //
              // Esto es un fallo que costó una sesión entera de entrar en
              // GitHub: el llavero moderno **exige el entitlement
              // `keychain-access-groups`**, y ese entitlement exige a su vez
              // firmar con un equipo de Apple. Didacta se firma ad hoc
              // --`CODE_SIGN_IDENTITY = "-"`-- porque se instala a mano y no
              // va a la Mac App Store (D46), así que no hay prefijo de equipo
              // que poner. El resultado era que el device flow terminaba
              // bien, GitHub devolvía el token, y guardarlo fallaba con
              // `-34018: A required entitlement isn't present`, justo en el
              // último paso y sin decir de qué entitlement hablaba.
              //
              // El llavero de siempre no pide entitlement y guarda en el
              // llavero de inicio de sesión, que es donde alguien esperaría
              // encontrar esto si va a mirarlo. Lo que se pierde es compartir
              // la credencial entre aplicaciones del mismo equipo, que aquí
              // no se usa: hay una aplicación.
              usesDataProtectionKeychain: false,
            ),
          );

  static const String _key = 'didacta.github.token';

  final FlutterSecureStorage _storage;

  /// Whether storing a token here is safe at all.
  ///
  /// False on the web, where "secure storage" is browser storage and browser
  /// storage is readable by any script on the origin. The app must not offer
  /// to keep a token it cannot actually protect.
  @override
  bool get canStoreSafely => !kIsWeb;

  @override
  Future<String?> read() async {
    if (!canStoreSafely) return null;
    return _storage.read(key: _key);
  }

  @override
  Future<void> write(String token) async {
    if (!canStoreSafely) {
      throw const RepositoryAccessException(
        'Un navegador no puede guardar un token de forma segura. En web el '
        'acceso va por la API, que lo guarda por ti.',
      );
    }
    await _storage.write(key: _key, value: token.trim());
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
