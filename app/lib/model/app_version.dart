/// Una versión de Didacta, y cómo se comparan dos.
///
/// Existe porque comparar versiones como cadenas es un error que se paga
/// tarde: `'1.10.0' < '1.9.0'` es cierto como texto y falso como versión, y
/// el síntoma no es un fallo sino algo peor --una actualización que nunca se
/// ofrece-- que nadie nota hasta que alguien pregunta por qué sigue con la
/// de hace tres meses.
///
/// Se ciñe a versionado semántico y a la parte que este proyecto usa:
/// `MAJOR.MINOR.PATCH` con una preliberación opcional (`1.4.2-rc.1`). El
/// `+BUILD` de `pubspec.yaml` **no** entra en la comparación, porque por
/// especificación no ordena nada: es un dato que se enseña, no un criterio.
///
/// La fuente de verdad es una sola: el `version:` de `pubspec.yaml`. De ahí
/// sale el tag (`v1.4.2`), el nombre de los artefactos, lo que la aplicación
/// dice de sí misma y lo que el manifiesto declara. Ningún otro sitio
/// escribe un número de versión a mano.
library;

/// Una versión semántica.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const [],
    this.build,
  });

  final int major;
  final int minor;
  final int patch;

  /// Los identificadores tras el `-`, ya separados por puntos.
  ///
  /// Una lista y no una cadena porque la especificación los compara uno a
  /// uno, y con reglas distintas según sean numéricos o no.
  final List<String> preRelease;

  /// El `+BUILD` de `pubspec.yaml`, si venía. No ordena.
  final int? build;

  bool get isPreRelease => preRelease.isNotEmpty;

  /// Lee `1.4.2`, `1.4.2+142`, `v1.4.2`, `1.4.2-rc.1`.
  ///
  /// Devuelve `null` en vez de lanzar: esto lee lo que diga un manifiesto
  /// que viene de la red, y un manifiesto mal formado es un caso normal que
  /// se maneja, no una excepción que se propaga hasta arriba.
  static AppVersion? tryParse(String? text) {
    if (text == null) return null;
    var rest = text.trim();
    if (rest.isEmpty) return null;
    // El tag lleva `v` delante y la versión no. Se acepta tal cual para que
    // `AppVersion.tryParse(tagName)` funcione sin recortar en cada sitio.
    if (rest.startsWith('v') || rest.startsWith('V')) rest = rest.substring(1);

    int? build;
    final plus = rest.indexOf('+');
    if (plus >= 0) {
      build = int.tryParse(rest.substring(plus + 1));
      rest = rest.substring(0, plus);
    }

    var pre = const <String>[];
    final dash = rest.indexOf('-');
    if (dash >= 0) {
      final tail = rest.substring(dash + 1);
      if (tail.isEmpty) return null;
      pre = tail.split('.');
      // `1.4.2-` o `1.4.2-rc..1`: un identificador vacío no es válido, y
      // dejarlo pasar haría que la comparación ordenase por casualidad.
      if (pre.any((part) => part.isEmpty)) return null;
      rest = rest.substring(0, dash);
    }

    final parts = rest.split('.');
    if (parts.length != 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      // `int.tryParse` acepta `+3` y ` 3`; una versión no.
      if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) return null;
      final value = int.tryParse(part);
      if (value == null) return null;
      numbers.add(value);
    }
    return AppVersion(
      numbers[0],
      numbers[1],
      numbers[2],
      preRelease: pre,
      build: build,
    );
  }

  /// Igual que [tryParse], pero para cuando la entrada es nuestra y un fallo
  /// es un error de programa.
  static AppVersion parse(String text) {
    final parsed = tryParse(text);
    if (parsed == null) {
      throw FormatException('No es una versión semántica', text);
    }
    return parsed;
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Una preliberación va **antes** que la versión que anuncia: 1.4.2-rc.1
    // es anterior a 1.4.2. Es la regla que impide que alguien con una rc
    // se quede sin la final.
    if (isPreRelease && !other.isPreRelease) return -1;
    if (!isPreRelease && other.isPreRelease) return 1;

    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final mine = preRelease[i];
      final theirs = other.preRelease[i];
      final mineNumber = int.tryParse(mine);
      final theirsNumber = int.tryParse(theirs);
      if (mineNumber != null && theirsNumber != null) {
        if (mineNumber != theirsNumber) {
          return mineNumber.compareTo(theirsNumber);
        }
        continue;
      }
      // Numérico antes que alfanumérico, por especificación.
      if (mineNumber != null) return -1;
      if (theirsNumber != null) return 1;
      final byText = mine.compareTo(theirs);
      if (byText != 0) return byText;
    }
    // Menos identificadores es menor: `1.4.2-rc` < `1.4.2-rc.1`.
    return preRelease.length.compareTo(other.preRelease.length);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0 && other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  /// `1.4.2` o `1.4.2-rc.1`. Sin el `+build`: es lo que se enseña.
  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return isPreRelease ? '$base-${preRelease.join('.')}' : base;
  }

  /// El tag del release: `v1.4.2`.
  String get tag => 'v$this';
}
