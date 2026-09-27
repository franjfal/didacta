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

import '../l10n/tr.dart';

/// Quién traduce.
enum TranslationProvider {
  google('google', 'Google Cloud Translation'),
  azure('azure', 'Azure AI Translator'),

  /// Libre y gratuito, sin clave, y el único que distingue el valenciano del
  /// catalán central. Traduce menos pares que los otros dos --ver
  /// [supportsPair]-- pero justo los que más se usan aquí.
  apertium('apertium', 'Apertium');

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
    // Sin clave: lo que se guarda es que está encendido.
    TranslationProvider.apertium => key.trim().isNotEmpty,
    // Azure rechaza la petición sin región y el error que devuelve habla de
    // la suscripción, no de la región: mejor decirlo aquí.
    TranslationProvider.azure =>
      key.trim().isNotEmpty && region.trim().isNotEmpty,
  };

  /// Qué falta, para poder decirlo antes de llamar.
  String? missing(TranslationProvider provider) {
    if (provider == TranslationProvider.apertium) {
      return key.trim().isEmpty ? tr('Está apagado.') : null;
    }
    if (key.trim().isEmpty) return tr('Falta la clave.');
    if (provider == TranslationProvider.azure && region.trim().isEmpty) {
      return tr(
        'Falta la región. Azure la pide, y sin ella el error que '
        'devuelve habla de la suscripción y despista.',
      );
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
      'Credentials(${isEmpty ? tr('sin clave') : hint}'
      '${region.isEmpty ? '' : ', $region'})';
}

/// Cómo se llama cada idioma de Didacta para cada proveedor.
///
/// **No son los mismos códigos**, y descubrirlo cuesta una llamada fallida con
/// un `400 Invalid Value` que no dice cuál de los cinco campos estaba mal.
///
/// El caso que hay: `va`. El valenciano es una variedad del catalán y ningún
/// traductor automático lo distingue; Google y Azure conocen `ca` y no `va`.
/// Es la misma decisión que toma la parte de LaTeX, donde el valenciano carga
/// babel con `catalan` --y es lo que da la partición de palabras correcta--
/// mientras las cadenas visibles se escriben en valenciano.
///
/// Lo que sale de ahí es catalán central: «Qüestió» donde el valenciano dice
/// «Questió». Es una traducción de máquina, o sea un borrador que alguien va a
/// leer de todas formas, y tener que ajustar unas formas es muchísimo mejor
/// que no poder traducir. Pero se avisa antes, porque quien lo revise tiene
/// que saber qué está revisando.
const Map<String, String> _asCatalan = {'va': 'ca'};

/// Los idiomas de Didacta que un proveedor **no** conoce de ninguna manera.
///
/// Vacío en los dos hoy: con `va` traducido a `ca`, los diez que Didacta trae
/// están en las dos listas. Existe para poder decirlo el día que se añada uno
/// que no.
const Map<TranslationProvider, Set<String>> _unsupported = {
  TranslationProvider.google: {},
  TranslationProvider.azure: {},
  TranslationProvider.apertium: {},
};

/// Los códigos de Apertium, que son de tres letras y distinguen la variante:
/// `cat_valencia` es el valenciano, con «seua» y «duració».
const Map<String, String> _apertiumCodes = {
  'es': 'spa',
  'va': 'cat_valencia',
  'ca': 'cat',
  'gl': 'glg',
  'en': 'eng',
  'fr': 'fra',
  'pt': 'por',
  'it': 'ita',
  'eu': 'eus',
};

/// Los pares que traduce el servidor público de Apertium entre los idiomas
/// de Didacta, tal como los lista `listPairs`.
const Set<String> _apertiumPairs = {
  'cat>eng', 'cat>fra', 'cat>ita', 'cat>por', 'cat>spa', //
  'eng>cat', 'eng>cat_valencia', 'eng>glg', 'eng>spa', //
  'eus>eng', 'eus>spa', 'fra>cat', 'fra>spa', //
  'glg>eng', 'glg>por', 'glg>spa', 'ita>cat', 'ita>spa', //
  'por>cat', 'por>glg', 'por>spa', //
  'spa>cat', 'spa>cat_valencia', 'spa>eng', 'spa>fra', 'spa>glg', //
  'spa>ita', 'spa>por',
};

/// El código que entiende [provider], o null si no conoce este idioma.
///
/// [asSource] porque en Apertium el valenciano como **origen** es catalán:
/// traduce hacia la variante, no desde ella.
String? providerCodeFor(
  TranslationProvider provider,
  String language, {
  bool asSource = false,
}) {
  if ((_unsupported[provider] ?? const {}).contains(language)) return null;
  if (provider == TranslationProvider.apertium) {
    if (asSource && language == 'va') return 'cat';
    return _apertiumCodes[language];
  }
  return _asCatalan[language] ?? language;
}

/// Si [provider] traduce de [from] a [to]. Google y Azure, todo lo de
/// Didacta; Apertium, lo que diga su lista.
bool supportsPair(TranslationProvider provider, String from, String to) {
  if (provider != TranslationProvider.apertium) {
    return providerCodeFor(provider, from) != null &&
        providerCodeFor(provider, to) != null;
  }
  final source = providerCodeFor(provider, from, asSource: true);
  final target = providerCodeFor(provider, to);
  return source != null &&
      target != null &&
      _apertiumPairs.contains('$source>$target');
}

/// Si lo que se le va a pedir no es exactamente el idioma que se pidió.
///
/// Para poder decirlo antes de traducir en vez de después de revisarlo.
String? approximationFor(TranslationProvider provider, String language) {
  // Los códigos de Apertium son otros, pero dicen el mismo idioma: el
  // valenciano es valenciano.
  if (provider == TranslationProvider.apertium) return null;
  final code = providerCodeFor(provider, language);
  if (code == null || code == language) return null;
  return code;
}
