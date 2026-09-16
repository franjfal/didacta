/// Dónde viven las credenciales de traducción: en el llavero y en ningún sitio más.
///
/// Separado del token de GitHub aunque el mecanismo sea el mismo, porque son
/// cosas distintas: salir de GitHub no puede llevarse por delante la clave de
/// Azure, y quitar la clave de Azure no puede cerrarte la sesión.
///
/// **Nunca en las preferencias.** `shared_preferences` es un fichero de texto
/// en el disco: en macOS un `.plist` que se lee con `defaults read` y que entra
/// en cualquier copia de seguridad de la carpeta de usuario. Ahí no va una
/// clave de API, y que sea cómodo no lo cambia.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../model/translation.dart';

/// Lo que sabe guardar y devolver credenciales.
abstract class TranslationSecrets {
  /// Si guardar aquí es seguro de verdad.
  bool get canStoreSafely;

  Future<Credentials> read(TranslationProvider provider);

  Future<void> write(TranslationProvider provider, Credentials credentials);

  Future<void> clear(TranslationProvider provider);
}

class KeychainTranslationSecrets implements TranslationSecrets {
  KeychainTranslationSecrets({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Sin sincronizar con iCloud: una clave de API autorizada en esta
            // máquina se queda en esta máquina.
            iOptions: IOSOptions(synchronizable: false),
            mOptions: MacOsOptions(
              synchronizable: false,
              // El llavero de siempre, por lo mismo que el token de GitHub: el
              // moderno exige el entitlement `keychain-access-groups`, que
              // exige firmar con un equipo de Apple, y Didacta se firma ad hoc.
              // Con el otro, guardar falla con `-34018` en el último paso y
              // sin decir de qué entitlement habla.
              usesDataProtectionKeychain: false,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _keyFor(TranslationProvider provider) =>
      'didacta.translation.${provider.id}';

  /// Falso en un navegador, donde «almacenamiento seguro» es almacenamiento
  /// del navegador, y eso lo lee cualquier script del origen. La aplicación no
  /// puede ofrecerse a guardar algo que no puede proteger.
  @override
  bool get canStoreSafely => !kIsWeb;

  @override
  Future<Credentials> read(TranslationProvider provider) async {
    if (!canStoreSafely) return const Credentials();
    final raw = await _storage.read(key: _keyFor(provider));
    if (raw == null || raw.isEmpty) return const Credentials();
    try {
      return Credentials.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      // Algo ilegible en el llavero: se trata como si no hubiera nada. Lo que
      // no se hace es incluirlo en el error para enseñar qué había.
      return const Credentials();
    }
  }

  @override
  Future<void> write(
    TranslationProvider provider,
    Credentials credentials,
  ) async {
    if (!canStoreSafely) {
      throw const TranslationSecretsException(
        'Un navegador no puede guardar una clave de API de forma segura. '
        'Usa la aplicación de escritorio.',
      );
    }
    if (credentials.isEmpty) {
      await clear(provider);
      return;
    }
    await _storage.write(
      key: _keyFor(provider),
      value: jsonEncode(credentials.toJson()),
    );
  }

  @override
  Future<void> clear(TranslationProvider provider) =>
      _storage.delete(key: _keyFor(provider));
}

/// Lo que no se puede hacer con el llavero.
class TranslationSecretsException implements Exception {
  const TranslationSecretsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Un llavero en memoria, para las pruebas.
class MemoryTranslationSecrets implements TranslationSecrets {
  MemoryTranslationSecrets({this.safe = true});

  final bool safe;
  final Map<TranslationProvider, Credentials> stored = {};

  @override
  bool get canStoreSafely => safe;

  @override
  Future<Credentials> read(TranslationProvider provider) async =>
      stored[provider] ?? const Credentials();

  @override
  Future<void> write(
    TranslationProvider provider,
    Credentials credentials,
  ) async {
    if (!safe) {
      throw const TranslationSecretsException('aquí no se puede guardar');
    }
    if (credentials.isEmpty) {
      stored.remove(provider);
      return;
    }
    stored[provider] = credentials;
  }

  @override
  Future<void> clear(TranslationProvider provider) async =>
      stored.remove(provider);
}
