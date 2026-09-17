/// Lo que ya se tradujo una vez, para no volver a pagarlo ni a decidirlo.
///
/// Dos razones, y la segunda importa más. La primera es la cuota: un tema son
/// cuarenta párrafos y la mitad se repiten entre asignaturas, así que traducir
/// el repositorio entero dos veces cuesta el doble por el mismo resultado. La
/// segunda es la **consistencia**: si «axioma del supremo» se tradujo de una
/// manera en el Tema 1, tiene que salir igual en el Tema 6, y una máquina
/// llamada dos veces no da por qué la misma respuesta.
///
/// **Es contenido, no configuración.** Va en el repositorio, se versiona y se
/// comparte: la decisión de cómo se dice algo en valenciano es del equipo que
/// da la asignatura, no de la máquina que la escribió. Las credenciales, al
/// revés, no salen del llavero. Los dos ámbitos no se mezclan nunca.
///
/// Y **repartida**: cada repositorio lleva la suya y se juntan al leer, igual
/// que las asignaturas. Quien tenga solo uno traduce con lo que ese sepa; no
/// se queda sin traducir por no tener el otro.
///
/// Sobre qué se guarda: el **segmento protegido**, con sus `<x id="N"/>` en el
/// sitio de las fórmulas. No es un detalle de implementación que se escape,
/// es lo que hace que la memoria sirva: «El conjunto $A$ es abierto» y «El
/// conjunto $B$ es abierto» son el mismo segmento protegido, así que la
/// segunda reutiliza la traducción de la primera y al reconstruir cada una
/// recupera su propia fórmula.
library;

import 'dart:convert';

/// Un segmento traducido, tal como quedó.
class MemoryEntry {
  const MemoryEntry({
    required this.source,
    required this.target,
    this.unit = '',
    this.at,
    this.by = '',
  });

  /// El segmento protegido original.
  final String source;

  /// Su traducción, con las mismas etiquetas.
  final String target;

  /// De qué unidad salió. Para poder ir a mirarla cuando algo no cuadra.
  final String unit;

  final DateTime? at;

  /// Quién la dejó así. Una traducción revisada por alguien vale más que una
  /// recién salida de la máquina, y sin esto no hay forma de distinguirlas.
  final String by;

  Map<String, dynamic> toJson() => {
    'source': source,
    'target': target,
    if (unit.isNotEmpty) 'unit': unit,
    if (at != null) 'at': at!.toUtc().toIso8601String(),
    if (by.isNotEmpty) 'by': by,
  };

  static MemoryEntry? fromJson(Map<String, dynamic> json) {
    final source = json['source'] as String?;
    final target = json['target'] as String?;
    if (source == null || target == null || source.isEmpty) return null;
    return MemoryEntry(
      source: source,
      target: target,
      unit: json['unit'] as String? ?? '',
      at: DateTime.tryParse(json['at'] as String? ?? ''),
      by: json['by'] as String? ?? '',
    );
  }
}

/// La memoria de un par de idiomas, junta de todos los repositorios abiertos.
class TranslationMemory {
  TranslationMemory(Iterable<MemoryEntry> entries) {
    for (final entry in entries) {
      // El último gana. El fichero se lee en orden y se añade al final, así
      // que lo último escrito es la decisión más reciente sobre ese segmento
      // --que es justo lo que hay que reutilizar--.
      _bySource[entry.source] = entry;
    }
  }

  TranslationMemory.empty();

  final Map<String, MemoryEntry> _bySource = {};

  int get length => _bySource.length;

  bool get isEmpty => _bySource.isEmpty;

  /// Lo que se guardó para este segmento, si se guardó algo.
  ///
  /// Coincidencia exacta y nada más. Una parecida --misma frase con una coma
  /// distinta-- tendría que decidir qué hacer con la diferencia, y decidirlo
  /// mal deja un texto que nadie escribió y que parece revisado.
  MemoryEntry? lookup(String source) => _bySource[source];

  /// Si ya está guardado exactamente así. Para no reescribir una línea que
  /// no dice nada nuevo.
  bool lookupSame(String source, String target) =>
      _bySource[source]?.target == target;

  /// Todo lo que hay, en un orden estable.
  List<MemoryEntry> get entries {
    final all = _bySource.values.toList();
    all.sort((a, b) => a.source.compareTo(b.source));
    return all;
  }

  /// Lee un fichero JSONL. Una línea ilegible se salta.
  ///
  /// Se salta y no rompe: el fichero lo escriben varias máquinas y lo fusiona
  /// git, así que una línea a medias de un merge mal resuelto es algo que
  /// puede pasar. Perder un segmento es volver a traducirlo; negarse a leer
  /// el fichero es perderlos todos.
  factory TranslationMemory.parse(String text) {
    final entries = <MemoryEntry>[];
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('{')) continue;
      try {
        final entry = MemoryEntry.fromJson(
          (jsonDecode(trimmed) as Map).cast<String, dynamic>(),
        );
        if (entry != null) entries.add(entry);
      } catch (_) {
        continue;
      }
    }
    return TranslationMemory(entries);
  }

  /// Junta varias, en orden: la última gana.
  factory TranslationMemory.merge(Iterable<TranslationMemory> parts) =>
      TranslationMemory([for (final part in parts) ...part.entries]);

  /// Las líneas que hay que añadir al fichero por lo recién traducido.
  ///
  /// Solo lo que cambia: un segmento que ya estaba con la misma traducción no
  /// se vuelve a escribir. Si no, cada tanda de traducción añadiría cuarenta
  /// líneas idénticas y el fichero crecería sin decir nada nuevo.
  List<String> linesFor(Iterable<MemoryEntry> found) => [
    for (final entry in found)
      if (_bySource[entry.source]?.target != entry.target)
        jsonEncode(entry.toJson()),
  ];
}

/// Dónde vive la memoria de un par de idiomas dentro de un repositorio.
///
/// Un fichero por par y no uno solo: lo que se traduce de castellano a
/// valenciano no se toca al traducir a inglés, así que dos personas que
/// trabajan en idiomas distintos no se pisan el fichero ni se pelean en el
/// merge.
String memoryPath(String from, String to) =>
    'translation/memory/$from-$to.jsonl';
