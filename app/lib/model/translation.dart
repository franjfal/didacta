/// Los proveedores de traducción automática, y cómo se les demuestra quién eres.
///
/// **Dos ámbitos que no se mezclan nunca**, y es la regla que da forma a este
/// fichero. Por un lado la configuración lingüística --a qué idiomas se
/// traduce, la memoria terminológica, las decisiones-- que es contenido: va en
/// el repositorio, se versiona y se comparte. Por otro las credenciales, que
/// son configuración privada de esta máquina: llavero del sistema, y nada más.
///
/// Una credencial no puede acabar en un repositorio de contenido, ni en git, ni
/// en un fichero versionado, ni en la memoria de traducción, ni copiada entre
/// repositorios, ni en un log, ni en un mensaje de error, ni en una
/// exportación. Por eso aquí solo vive la **forma** de una credencial --qué
/// campos tiene, si está completa-- y nunca el valor: quien lo guarda es el
/// llavero y quien lo usa lo pide en el momento.
///
/// De ahí que [Credentials.toString] esté escrito a mano. El `toString` que
/// Dart genera imprimiría la clave, y un objeto así acaba en un `print` de
/// depuración o dentro del mensaje de una excepción sin que nadie lo decida.
library;

/// Quién traduce.
enum TranslationProvider {
  google('google', 'Google Cloud Translation'),
  azure('azure', 'Azure AI Translator');

  const TranslationProvider(this.id, this.label);

  final String id;
  final String label;

  static TranslationProvider? byId(String? id) {
    for (final provider in values) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}

/// Lo que hace falta para hablar con un proveedor.
///
/// Los dos piden una clave; Azure pide además la región, y el endpoint solo
/// cuando se usa un recurso privado. Un objeto por proveedor y no un mapa
/// suelto para que [complete] pueda decir si falta algo antes de intentar una
/// llamada que iba a fallar.
class Credentials {
  const Credentials({this.key = '', this.region = '', this.endpoint = ''});

  /// La clave de API. Nunca sale de aquí más que hacia el proveedor.
  final String key;

  /// La región de Azure: `westeurope`, `global`. Google no la usa.
  final String region;

  /// El endpoint, cuando no es el público. Opcional en los dos.
  final String endpoint;

  bool get isEmpty => key.trim().isEmpty;

  /// Si se puede intentar una llamada con esto.
  bool complete(TranslationProvider provider) => switch (provider) {
    TranslationProvider.google => key.trim().isNotEmpty,
    // Azure rechaza la petición sin región y el error que devuelve habla de
    // la suscripción, no de la región: mejor decirlo aquí.
    TranslationProvider.azure =>
      key.trim().isNotEmpty && region.trim().isNotEmpty,
  };

  /// Qué falta, para poder decirlo antes de llamar.
  String? missing(TranslationProvider provider) {
    if (key.trim().isEmpty) return 'Falta la clave.';
    if (provider == TranslationProvider.azure && region.trim().isEmpty) {
      return 'Falta la región. Azure la pide, y sin ella el error que '
          'devuelve habla de la suscripción y despista.';
    }
    return null;
  }

  Credentials copyWith({String? key, String? region, String? endpoint}) =>
      Credentials(
        key: key ?? this.key,
        region: region ?? this.region,
        endpoint: endpoint ?? this.endpoint,
      );

  /// Cómo se guarda en el llavero. **Nunca en ningún otro sitio.**
  Map<String, String> toJson() => {
    'key': key,
    if (region.isNotEmpty) 'region': region,
    if (endpoint.isNotEmpty) 'endpoint': endpoint,
  };

  factory Credentials.fromJson(Map<String, dynamic> json) => Credentials(
    key: json['key'] as String? ?? '',
    region: json['region'] as String? ?? '',
    endpoint: json['endpoint'] as String? ?? '',
  );

  /// Lo que se puede enseñar sin enseñar la clave.
  ///
  /// Los últimos cuatro caracteres, que es lo justo para reconocer cuál de las
  /// tuyas has puesto sin que sirva para usarla. Si es corta, ni eso.
  String get hint {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 8) return '••••';
    return '••••${trimmed.substring(trimmed.length - 4)}';
  }

  /// Escrito a mano y sin la clave dentro.
  ///
  /// El que genera Dart la imprimiría, y un objeto así acaba en un `print` de
  /// depuración o dentro de una excepción sin que nadie lo decida. Es la clase
  /// de fuga que no se ve al escribirla y se ve en el log de otra persona.
  @override
  String toString() =>
      'Credentials(${isEmpty ? 'sin clave' : hint}'
      '${region.isEmpty ? '' : ', $region'})';
}
