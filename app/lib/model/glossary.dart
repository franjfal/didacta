/// El glosario: los términos que una traducción tiene que respetar.
///
/// «Sucesión» es «successió» y no «seqüència»; «norma» no se traduce. Una
/// máquina no lo sabe, y una persona que revisa treinta lecciones se cansa de
/// corregirlo treinta veces. Con el glosario, cada traducción automática avisa
/// de los términos que no han salido como se dijo --«"sucesión" tendría que
/// decirse "successió"»--, y el aviso lleva a mirarlo.
///
/// **Avisa, no corrige.** Sustituir la palabra por la buena deja una frase que
/// nadie ha escrito y que puede no concordar --género, número, un artículo
/// delante--, y encima parece revisada. Es la regla de [translateLatex].
///
/// Un fichero de texto separado por tabuladores, `translation/glossary.tsv`,
/// con una columna por idioma y la primera fila diciendo cuál es cuál:
///
///     es	va	en
///     sucesión	successió	sequence
///     norma	norma	norm
///
/// Así se abre y se edita en cualquier hoja de cálculo, y un cambio es una
/// línea en el diff. Uno por repositorio, y se juntan: lo que decidió el
/// departamento vale en la teoría y en los problemas.
library;

import 'translation_run.dart' show TermCheck;
import '../l10n/tr.dart';

/// Dónde vive el glosario dentro de un repositorio.
const String glossaryPath = 'translation/glossary.tsv';

class Glossary {
  Glossary({List<String>? languages, List<Map<String, String>>? terms})
    : languages = languages ?? [],
      terms = terms ?? [];

  /// Los idiomas de las columnas, en orden.
  final List<String> languages;

  /// Cada término, por idioma. Un hueco es que en ese idioma no se ha dicho.
  final List<Map<String, String>> terms;

  bool get isEmpty => terms.isEmpty;

  factory Glossary.parse(String text) {
    final lines = [
      for (final line in text.replaceAll('\r\n', '\n').split('\n'))
        if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line,
    ];
    if (lines.isEmpty) return Glossary();
    final languages = [
      for (final cell in lines.first.split('\t')) cell.trim().toLowerCase(),
    ];
    final terms = <Map<String, String>>[];
    for (final line in lines.skip(1)) {
      final cells = line.split('\t');
      final term = <String, String>{
        for (var i = 0; i < languages.length && i < cells.length; i += 1)
          if (cells[i].trim().isNotEmpty) languages[i]: cells[i].trim(),
      };
      if (term.length >= 2) terms.add(term);
    }
    return Glossary(languages: languages, terms: terms);
  }

  /// Junta varios: los idiomas de todos, y un término repetido --el mismo en
  /// el primer idioma que tengan en común-- una vez, con lo que diga el
  /// primero.
  factory Glossary.merge(Iterable<Glossary> parts) {
    final languages = <String>[];
    final terms = <Map<String, String>>[];
    final seen = <String>{};
    for (final part in parts) {
      for (final code in part.languages) {
        if (!languages.contains(code)) languages.add(code);
      }
      for (final term in part.terms) {
        final key = [
          for (final code in part.languages)
            if (term[code] != null) '$code=${term[code]!.toLowerCase()}',
        ].take(1).join();
        if (seen.add(key)) terms.add(term);
      }
    }
    return Glossary(languages: languages, terms: terms);
  }

  /// Lo que hay que comprobar al traducir de [from] a [to].
  List<TermCheck> checksFor(String from, String to) => [
    for (final term in terms)
      if (term[from] != null && term[to] != null)
        TermCheck(source: term[from]!, target: term[to]!),
  ];

  String toTsv() {
    final out = StringBuffer()
      ..writeln(
        tr('# Glosario de traducción: un término por fila, un idioma por'),
      )
      ..writeln(tr('# columna, separados por tabuladores. Se edita en Didacta'))
      ..writeln(
        tr('# (Ajustes → Traducción automática) o en una hoja de cálculo.'),
      )
      ..writeln(languages.join('\t'));
    for (final term in terms) {
      out.writeln([for (final code in languages) term[code] ?? ''].join('\t'));
    }
    return out.toString();
  }
}
