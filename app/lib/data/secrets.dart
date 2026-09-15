/// Dónde se guarda el token de GitHub.
///
/// Separado de quien lo usa a propósito: en escritorio es el llavero del
/// sistema y en un test es un mapa en memoria, y nada de lo que hay encima
/// tiene por qué saber cuál de los dos está debajo.
library;

abstract class SecretStore {
  /// Whether keeping a secret here is actually safe. False in a browser.
  bool get canStoreSafely;

  Future<String?> read();

  Future<void> write(String value);

  Future<void> clear();
}

/// Un guardián que no guarda nada, para las pruebas.
class MemorySecrets implements SecretStore {
  MemorySecrets([this.value]);

  String? value;

  @override
  bool get canStoreSafely => false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String secret) async => value = secret;

  @override
  Future<void> clear() async => value = null;
}
