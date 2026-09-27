/// Traducir un fichero: qué se manda, qué se reutiliza y qué sale.
///
/// La pieza que junta lo demás. El protector decide qué es prosa y qué es
/// sintaxis; la memoria dice qué de esa prosa ya se tradujo; el proveedor
/// traduce lo que queda. Aquí se ordena, se cuenta y se vuelve a montar el
/// fichero.
///
/// **Sin efectos.** No lee del disco, no escribe, no llama a nadie: recibe el
/// texto y una función que traduce, y devuelve el resultado. Así se puede
/// probar el ciclo entero --incluido el caso que importa, que el fichero no
/// se rompa-- sin red, sin credenciales y sin repositorio.
///
/// Y **nada se aplica a medias**. Si un segmento vuelve con las etiquetas
/// cambiadas, ese segmento se queda en el original y se cuenta como fallo: un
/// `\label` perdido rompe todas las referencias del tema y no se ve hasta que
/// alguien compila la víspera. Mejor un párrafo sin traducir, que se ve.
library;

import 'latex_protect.dart';
import 'translation_memory.dart';
import '../l10n/tr.dart';

/// Lo que se hizo al traducir, para poder contarlo.
class TranslationStats {
  const TranslationStats({
    this.segments = 0,
    this.reused = 0,
    this.translated = 0,
    this.refused = 0,
    this.characters = 0,
  });

  /// Los segmentos de prosa que había.
  final int segments;

  /// Los que salieron de la memoria y no se pagaron.
  final int reused;

  /// Los que hubo que pedir.
  final int translated;

  /// Los que volvieron mal y se dejaron en el original.
  final int refused;

  /// Los caracteres que se mandaron, que es lo que cobran los dos proveedores.
  ///
  /// Tal como salen, etiquetas incluidas: una etiqueta ocupa sitio en la
  /// petición y se factura igual. Lo que no entra aquí es lo que nunca se
  /// manda --las fórmulas, los entornos, los comentarios-- y eso es lo que
  /// hace que traducir un tema de matemáticas cueste mucho menos que su
  /// tamaño en disco.
  final int characters;

  bool get anything => segments > 0;

  /// Qué proporción salió de la memoria. Lo que hace visible que mantenerla
  /// merece la pena.
  double get reuse => segments == 0 ? 0 : reused / segments;

  TranslationStats plus(TranslationStats other) => TranslationStats(
    segments: segments + other.segments,
    reused: reused + other.reused,
    translated: translated + other.translated,
    refused: refused + other.refused,
    characters: characters + other.characters,
  );

  @override
  String toString() => tr(
    '{0} segmentos · {1} de memoria · {2} traducidos'
    '{3}',
    [
      segments,
      reused,
      translated,
      refused > 0 ? tr(' · {0} sin aplicar', [refused]) : '',
    ],
  );
}

/// El resultado de traducir un fichero.
class TranslationResult {
  const TranslationResult({
    required this.text,
    required this.stats,
    required this.learned,
    this.warnings = const [],
  });

  /// El `.tex` traducido, listo para escribir.
  final String text;

  final TranslationStats stats;

  /// Lo nuevo que hay que guardar en la memoria.
  final List<MemoryEntry> learned;

  /// Lo que hay que mirar: términos que no salieron como dice la
  /// terminología, segmentos que volvieron mal.
  final List<String> warnings;

  bool get ok => stats.refused == 0;
}

/// Traduce los trozos que se le pasen. Lo que devuelve tiene que venir en el
/// mismo orden y con la misma cantidad.
typedef TranslateBatch = Future<List<String>> Function(List<String> pieces);

/// Un término y cómo tiene que decirse.
class TermCheck {
  const TermCheck({required this.source, required this.target});

  /// Cómo aparece en el original.
  final String source;

  /// Cómo tiene que aparecer traducido.
  final String target;
}

/// Cuánto costaría traducir algo, antes de pedirlo.
class TranslationEstimate {
  const TranslationEstimate({
    this.files = 0,
    this.segments = 0,
    this.reused = 0,
    this.characters = 0,
    this.unreadable = 0,
  });

  final int files;

  /// Los originales que no se han podido leer: de esos no se sabe cuánto
  /// costarían, y no se puede decir que no cuestan nada.
  final int unreadable;

  /// Los párrafos con texto.
  final int segments;

  /// Los que ya están en la memoria y no se piden.
  final int reused;

  /// Los caracteres que se mandarían al proveedor, que es lo que se paga.
  final int characters;

  TranslationEstimate plus(TranslationEstimate other) => TranslationEstimate(
    files: files + other.files,
    segments: segments + other.segments,
    reused: reused + other.reused,
    characters: characters + other.characters,
    unreadable: unreadable + other.unreadable,
  );
}

/// Lo que se mandaría al traducir [text] con [memory], sin mandarlo.
///
/// La misma cuenta que hace [translateLatex] --los mismos segmentos, la misma
/// memoria--, para que lo que se anuncia antes de pulsar sea lo que se paga
/// después. Los párrafos repetidos dentro del mismo texto se cuentan una vez:
/// la segunda vez ya están en la memoria.
TranslationEstimate estimateLatex(String text, TranslationMemory memory) {
  var segments = 0;
  var reused = 0;
  var characters = 0;
  final asked = <String>{};
  for (final segment in protectLatex(text)) {
    if (segment.verbatim || segment.letters == 0) continue;
    segments += 1;
    if (memory.lookup(segment.text) != null || asked.contains(segment.text)) {
      reused += 1;
      continue;
    }
    asked.add(segment.text);
    characters += segment.text.length;
  }
  return TranslationEstimate(
    files: 1,
    segments: segments,
    reused: reused,
    characters: characters,
  );
}

/// Traduce un `.tex` entero.
///
/// [translate] recibe solo lo que la memoria no sabía. Si no queda nada que
/// pedir no se llama: traducir un fichero que ya estaba entero en la memoria
/// no puede costar una llamada.
Future<TranslationResult> translateLatex(
  String text, {
  required TranslationMemory memory,
  required TranslateBatch translate,
  List<TermCheck> terms = const [],
  String unit = '',
  String by = '',
  DateTime? when,
}) async {
  final segments = protectLatex(text);

  // Qué hay que pedir y qué sale de la memoria. En dos pasadas: primero se
  // mira todo, y solo después se llama una vez con lo que falte. Llamar por
  // segmento serían cuarenta peticiones por fichero.
  final pending = <int>[];
  final resolved = <int, String>{};
  var reused = 0;
  var prose = 0;

  for (var i = 0; i < segments.length; i += 1) {
    final segment = segments[i];
    if (segment.verbatim || segment.letters == 0) continue;
    prose += 1;
    final known = memory.lookup(segment.text);
    if (known != null) {
      resolved[i] = known.target;
      reused += 1;
    } else {
      pending.add(i);
    }
  }

  final warnings = <String>[];
  var characters = 0;

  if (pending.isNotEmpty) {
    final asked = [for (final index in pending) segments[index].text];
    characters = asked.fold<int>(0, (sum, piece) => sum + piece.length);
    final answers = await translate(asked);
    if (answers.length != asked.length) {
      // El proveedor ha devuelto otra cantidad. Emparejarlos por posición
      // pondría cada traducción en el párrafo de al lado, que es peor que no
      // traducir: el fichero quedaría plausible y mal.
      throw StateError(
        tr(
          'El proveedor devolvió {0} traducciones para '
          '{1} trozos. No se aplica nada.',
          [answers.length, asked.length],
        ),
      );
    }
    for (var i = 0; i < pending.length; i += 1) {
      resolved[pending[i]] = answers[i];
    }
  }

  // Montar el fichero. Aquí se comprueba cada segmento antes de aceptarlo.
  final out = StringBuffer();
  final learned = <MemoryEntry>[];
  var refused = 0;
  var translated = 0;

  for (var i = 0; i < segments.length; i += 1) {
    final segment = segments[i];
    final answer = resolved[i];
    if (answer == null) {
      // Verbatim, o sin una letra que traducir: va tal cual.
      out.write(segment.restore(segment.text) ?? segment.text);
      continue;
    }

    final restored = segment.restore(answer);
    if (restored == null) {
      // Etiquetas perdidas, duplicadas o inventadas. Se queda el original.
      refused += 1;
      warnings.add(
        tr(
          'Un párrafo volvió con la sintaxis cambiada y se ha dejado sin '
          'traducir. Empieza por «{0}».',
          [_preview(segment.text)],
        ),
      );
      out.write(segment.restore(segment.text) ?? segment.text);
      continue;
    }

    out.write(restored);
    if (!memory.lookupSame(segment.text, answer)) {
      learned.add(
        MemoryEntry(
          source: segment.text,
          target: answer,
          unit: unit,
          at: when,
          by: by,
        ),
      );
    }
    if (memory.lookup(segment.text) == null) translated += 1;
  }

  // La terminología, después de montar: se avisa, no se corrige.
  //
  // No se corrige a propósito. Sustituir la palabra por la buena deja una
  // frase que nadie ha escrito y que puede no concordar --género, número, un
  // artículo delante-- y encima parece revisada. Lo que hace falta es que
  // alguien lo mire.
  final body = out.toString();
  for (final term in terms) {
    if (!text.toLowerCase().contains(term.source.toLowerCase())) continue;
    if (body.toLowerCase().contains(term.target.toLowerCase())) continue;
    warnings.add(
      tr(
        '«{0}» tendría que decirse «{1}», y no aparece '
        'así en la traducción.',
        [term.source, term.target],
      ),
    );
  }

  return TranslationResult(
    text: body,
    stats: TranslationStats(
      segments: prose,
      reused: reused,
      translated: translated,
      refused: refused,
      characters: characters,
    ),
    learned: learned,
    warnings: warnings,
  );
}

String _preview(String text) {
  final clean = text.replaceAll(RegExp(r'<x id="\d+"/>'), '…').trim();
  return clean.length <= 48 ? clean : '${clean.substring(0, 48)}…';
}

/// Lo que se aprende de una traducción revisada: cada párrafo del original
/// con el suyo corregido.
///
/// Es lo que hace que la memoria aprenda de las personas y no solo de la
/// máquina: la frase que alguien corrigió al revisar sale corregida la
/// próxima vez que aparezca, en cualquier lección. Solo cuando las dos
/// versiones tienen la misma forma --los mismos párrafos, con las mismas
/// fórmulas y órdenes en el mismo orden--: emparejar a ojo una traducción
/// que añadió o quitó un párrafo enseñaría a la memoria frases cambiadas de
/// sitio.
List<MemoryEntry> learnFromReview(
  String original,
  String translation, {
  String unit = '',
  String by = '',
  DateTime? when,
}) {
  final source = [
    for (final segment in protectLatex(original))
      if (!segment.verbatim && segment.letters > 0) segment,
  ];
  final target = [
    for (final segment in protectLatex(translation))
      if (!segment.verbatim && segment.letters > 0) segment,
  ];
  if (source.length != target.length) return const [];
  final learned = <MemoryEntry>[];
  for (var i = 0; i < source.length; i += 1) {
    final a = source[i];
    final b = target[i];
    if (a.parts.length != b.parts.length) return const [];
    for (var k = 0; k < a.parts.length; k += 1) {
      if (a.parts[k].trim() != b.parts[k].trim()) return const [];
    }
    if (a.text == b.text) continue;
    learned.add(
      MemoryEntry(source: a.text, target: b.text, unit: unit, at: when, by: by),
    );
  }
  return learned;
}
