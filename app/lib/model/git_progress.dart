/// Lo que dice git mientras trabaja, entendido lo justo para pintarlo.
///
/// Clonar un repositorio de contenido con años de PDFs y figuras son minutos,
/// y en esos minutos lo único que se veía era «Cloning into '.'...»: desde
/// fuera no se distingue de una aplicación colgada. git sabe perfectamente
/// por dónde va --cuántos objetos lleva, cuántos megas, a qué velocidad-- y
/// lo escribe en cuanto se le pide `--progress`.
///
/// Lo que se saca de cada línea es poco a propósito: la fase, el porcentaje
/// y lo que venga detrás. **No se reconoce ninguna fase por su nombre**,
/// porque git traduce sus mensajes («Receiving objects» es «Recibiendo
/// objetos» en un git en castellano) y la aplicación no le fuerza el inglés.
/// Se reconoce la forma, que es la misma en todos los idiomas:
///
///     remote: Counting objects:  13% (280/2151)
///     Receiving objects:  45% (450/1000), 12.00 MiB | 3.00 MiB/s
///     Resolving deltas: 100% (1200/1200), done.
library;

/// Una línea de progreso de git.
class GitProgress {
  const GitProgress({
    required this.phase,
    required this.percent,
    required this.done,
    required this.total,
    this.transfer = '',
  });

  /// Qué está haciendo, como lo dice git y sin el «remote:» delante.
  final String phase;

  /// De 0 a 100.
  final int percent;

  /// Cuántos lleva, y de cuántos.
  final int done;
  final int total;

  /// Cuánto se ha bajado y a qué velocidad, cuando git lo dice:
  /// «12.00 MiB | 3.00 MiB/s». Vacío si no.
  final String transfer;

  /// Para la barra: de 0 a 1.
  double get fraction => percent.clamp(0, 100) / 100;

  /// La línea, recogida: la fase, cuánto va y lo que se ha bajado.
  String get summary => [
    '$phase: $percent % ($done/$total)',
    if (transfer.isNotEmpty) transfer,
  ].join(' · ');

  /// La fase y el recuento, con lo que vaya detrás.
  ///
  /// El `.+?` es perezoso para que la fase acabe en los primeros dos puntos
  /// que van seguidos de un porcentaje, y no en los del «remote:».
  static final RegExp _shape = RegExp(
    r'^(.+?):\s+(\d{1,3})%\s+\((\d+)/(\d+)\)(.*)$',
  );

  /// El «remote: » del principio, en el idioma que sea: una palabra y dos
  /// puntos. Lo que hace GitHub y lo que hace esta máquina se cuentan igual.
  static final RegExp _prefix = RegExp(r'^[^\s:]+:\s+');

  /// La interpreta, o `null` si no es una línea de progreso.
  ///
  /// Las que no lo son --«Cloning into…», «remote: Total 2151 (delta…)», un
  /// error-- se enseñan tal cual, así que aquí no hace falta entenderlas.
  static GitProgress? parse(String line) {
    final match = _shape.firstMatch(line.trim());
    if (match == null) return null;

    var phase = match.group(1)!.trim();
    // Solo si queda algo detrás: una fase que fuera una palabra sola con dos
    // puntos no tiene prefijo que quitar.
    final bare = phase.replaceFirst(_prefix, '');
    if (bare.isNotEmpty) phase = bare;

    return GitProgress(
      phase: phase,
      percent: int.parse(match.group(2)!),
      done: int.parse(match.group(3)!),
      total: int.parse(match.group(4)!),
      transfer: _transferIn(match.group(5)!),
    );
  }

  /// Lo que va detrás del recuento: «, 12.00 MiB | 3.00 MiB/s, done.».
  ///
  /// Se queda con los trozos que llevan cifras. El «done» del final también
  /// lo traduce git, así que se reconoce por no tener ninguna; y que la fase
  /// ha terminado ya lo dice el 100 %.
  static String _transferIn(String rest) => rest
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.contains(RegExp(r'\d')))
      .join(', ');
}
