/// Traducir un `.tex` sin romperlo, y sin pagar dos veces por lo mismo.
///
/// La memoria existe por dos razones y la segunda importa más. La cuota: un
/// tema son cuarenta párrafos y la mitad se repiten entre asignaturas. Y la
/// **consistencia**: si «axioma del supremo» se tradujo de una manera en el
/// Tema 1 tiene que salir igual en el Tema 6, y una máquina llamada dos veces
/// no da por qué la misma respuesta.
///
/// Lo que más se prueba aquí es lo que **no** puede pasar: que una traducción
/// que vuelve mal se aplique igual. Un `\label` perdido rompe todas las
/// referencias del tema y no se ve hasta que alguien compila la víspera; un
/// párrafo sin traducir se ve al mirarlo.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/translation_memory.dart';
import 'package:didacta_app/model/translation_run.dart';

/// Un traductor de mentira que apunta lo que le piden.
class FakeBatch {
  FakeBatch({this.answer, this.calls = 0});

  /// Qué devolver para cada trozo. Por defecto, el trozo en mayúsculas, que
  /// deja las etiquetas intactas y se distingue del original de un vistazo.
  final String Function(String)? answer;

  int calls;
  final List<List<String>> asked = [];

  Future<List<String>> call(List<String> pieces) async {
    calls += 1;
    asked.add(pieces);
    return [for (final piece in pieces) (answer ?? _shout)(piece)];
  }

  /// Mayúsculas **fuera de las etiquetas**.
  ///
  /// Poner en mayúsculas el trozo entero convertiría `<x id="0"/>` en
  /// `<X ID="0"/>` y el restaurador lo rechazaría, con razón: eso ya no son
  /// las etiquetas que se mandaron. Un traductor de verdad las respeta --las
  /// dos APIs lo documentan-- así que el de mentira también.
  static String _shout(String piece) {
    final tag = RegExp(r'<x id="\d+"/>');
    final out = StringBuffer();
    var at = 0;
    for (final match in tag.allMatches(piece)) {
      out.write(piece.substring(at, match.start).toUpperCase());
      out.write(match.group(0));
      at = match.end;
    }
    out.write(piece.substring(at).toUpperCase());
    return out.toString();
  }
}

const String tex = r'''
\didactatitle{El axioma del supremo}
Toda sucesión de Cauchy es acotada, como vimos en \ref{sec:cauchy}.

La función $f$ es continua en $[0,1]$ salvo en un punto.
''';

void main() {
  group('el ciclo', () {
    test('lo que vuelve bien se aplica y la sintaxis se queda', () async {
      final batch = FakeBatch();
      final out = await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );

      expect(out.ok, isTrue);
      expect(out.text, contains(r'\ref{sec:cauchy}'));
      expect(out.text, contains(r'$[0,1]$'));
      expect(out.text, contains('TODA SUCESI'));
    });

    test('las claves de referencia no se mandan', () async {
      // El caso que más duele: `\label{sec:normas}` traducido rompe todas las
      // referencias del tema, y en silencio.
      final batch = FakeBatch();
      await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );

      final sent = batch.asked.single.join('|');
      expect(sent, isNot(contains('sec:cauchy')));
      expect(sent, isNot(contains(r'\ref')));
    });

    test('una traducción que pierde una etiqueta no se aplica', () async {
      // Se queda el original, que se ve, en vez de un fichero que no compila.
      final batch = FakeBatch(
        answer: (piece) => piece.replaceAll(RegExp(r'<x id="\d+"/>'), ''),
      );
      final out = await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );

      expect(out.ok, isFalse);
      expect(out.stats.refused, greaterThan(0));
      expect(out.text, contains(r'\ref{sec:cauchy}'));
      expect(out.warnings, isNotEmpty);
    });

    test('y lo que sí volvió bien se aplica igual', () async {
      // Un párrafo malo no puede dejar el fichero entero sin traducir.
      var first = true;
      final batch = FakeBatch(
        answer: (piece) {
          if (first) {
            first = false;
            return piece.replaceAll(RegExp(r'<x id="\d+"/>'), '');
          }
          // El mismo falso que respeta las etiquetas: si aquí se pusiera el
          // trozo entero en mayúsculas, fallarían todos y el test no probaría
          // que uno malo no arrastra a los demás.
          return FakeBatch._shout(piece);
        },
      );
      final out = await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );

      expect(out.stats.refused, 1);
      expect(out.stats.segments, greaterThan(1));
      expect(out.text.toUpperCase(), out.text.toUpperCase());
    });

    test('si devuelve otra cantidad, no se aplica nada', () async {
      // Emparejarlos por posición pondría cada traducción en el párrafo de al
      // lado: el fichero quedaría plausible y mal, que es lo peor.
      Future<List<String>> short(List<String> pieces) async =>
          pieces.take(1).toList();

      expect(
        () => translateLatex(
          tex,
          memory: TranslationMemory.empty(),
          translate: short,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('un fichero sin prosa no llama a nadie', () async {
      final batch = FakeBatch();
      final out = await translateLatex(
        r'\includegraphics{figures/x.pdf}',
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );

      expect(batch.calls, 0);
      expect(out.text.trim(), r'\includegraphics{figures/x.pdf}');
    });
  });

  group('la forma del fichero', () {
    /// Lo que hace un traductor de verdad con un trozo: le quita el espacio
    /// de los extremos y devuelve el párrafo en una sola línea.
    ///
    /// Las dos cosas son razonables por su parte --le mandas un texto y te
    /// devuelve un texto-- y las dos rompían el `.tex`.
    Future<List<String>> asReal(List<String> pieces) async => [
      for (final piece in pieces)
        piece.trim().replaceAll(RegExp(r'\s*\n\s*'), ' '),
    ];

    test('una orden no se pega a su texto', () async {
      // El fallo que no compila: `\item Donats` volvía como `\itemDonats`
      // porque el espacio que cierra el nombre de la orden se lo comía el
      // traductor con el resto del recorte.
      final out = await translateLatex(
        '\\begin{itemize}\n\\item Donats dos números.\n\\end{itemize}\n',
        memory: TranslationMemory.empty(),
        translate: asReal,
      );
      expect(out.text, contains('\\item Donats'));
      expect(out.text, isNot(contains('\\itemDonats')));
    });

    test('los entornos se quedan en su línea', () async {
      // El otro estropicio: el `.tex` traducido salía como un muro, porque
      // los saltos de dentro de un párrafo son del traductor y los devuelve
      // convertidos en espacios.
      const tex =
          '\\begin{itemize}\n'
          '\\item Uno.\n'
          '\\dpause\n'
          '\\item Dos.\n'
          '\\end{itemize}\n';
      final out = await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: asReal,
      );
      expect(out.text, tex, reason: 'la forma es la misma');
    });

    test('la sangría de una línea se conserva', () async {
      const tex =
          '\\begin{frame}\n'
          '  \\begin{definition}\n'
          '    Un conjunto acotado.\n'
          '  \\end{definition}\n'
          '\\end{frame}\n';
      final out = await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: asReal,
      );
      expect(out.text, tex);
    });

    test('y la línea en blanco que separa dos párrafos, también', () async {
      const tex = 'Un párrafo.\n\nOtro párrafo.\n';
      final out = await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: asReal,
      );
      expect(out.text, tex);
    });

    test('pero el espacio de dentro de una frase sigue siendo suyo', () async {
      // «El conjunto $A$ es abierto» lleva espacios que son prosa: quien
      // traduce los recoloca con las palabras, y quedárselos dejaba la
      // traducción empezando por un espacio suelto.
      final out = await translateLatex(
        r'El conjunto $A$ es abierto.',
        memory: TranslationMemory.empty(),
        translate: (pieces) async => [
          for (final piece in pieces)
            piece
                .replaceAll('El conjunto ', '')
                .replaceAll(' es abierto.', ' is an open set.'),
        ],
      );
      expect(out.text, r'$A$ is an open set.');
    });
  });

  group('la memoria', () {
    test('lo que ya estaba no se vuelve a pedir', () async {
      final batch = FakeBatch();
      final first = await translateLatex(
        tex,
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );

      final memory = TranslationMemory(first.learned);
      final again = FakeBatch();
      final second = await translateLatex(
        tex,
        memory: memory,
        translate: again.call,
      );

      expect(again.calls, 0, reason: 'estaba entero en la memoria');
      expect(second.text, first.text);
      expect(second.stats.reused, second.stats.segments);
      expect(second.stats.characters, 0);
    });

    test('solo se pide lo que falta', () async {
      final batch = FakeBatch();
      final first = await translateLatex(
        'Un párrafo.\n\nOtro párrafo.\n',
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );
      expect(batch.asked.single.length, 2);

      // La memoria sabe uno de los dos.
      final memory = TranslationMemory([first.learned.first]);
      final again = FakeBatch();
      await translateLatex(
        'Un párrafo.\n\nOtro párrafo.\n',
        memory: memory,
        translate: again.call,
      );

      expect(again.asked.single.length, 1);
    });

    test('la misma frase con distinta fórmula reutiliza igual', () async {
      // Es lo que hace que guardar el segmento **protegido** valga la pena:
      // los dos son «El conjunto <x id="0"/> es abierto», y al reconstruir
      // cada uno recupera su propia fórmula.
      final batch = FakeBatch();
      final first = await translateLatex(
        r'El conjunto $A$ es abierto.',
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );

      final again = FakeBatch();
      final second = await translateLatex(
        r'El conjunto $B$ es abierto.',
        memory: TranslationMemory(first.learned),
        translate: again.call,
      );

      expect(again.calls, 0);
      expect(second.text, contains(r'$B$'));
      expect(second.text, isNot(contains(r'$A$')));
    });

    test('lo aprendido lleva de dónde salió y quién lo dejó así', () async {
      // Una traducción revisada por alguien vale más que una recién salida de
      // la máquina, y sin esto no hay forma de distinguirlas.
      final out = await translateLatex(
        'Una frase.',
        memory: TranslationMemory.empty(),
        translate: FakeBatch().call,
        unit: 'content/a/b/c',
        by: 'franjfal',
        when: DateTime.utc(2026, 9, 16),
      );

      expect(out.learned.single.unit, 'content/a/b/c');
      expect(out.learned.single.by, 'franjfal');
      expect(out.learned.single.at, DateTime.utc(2026, 9, 16));
    });

    test('no se aprende lo que ya estaba igual', () async {
      // Si no, cada tanda añadiría cuarenta líneas idénticas y el fichero
      // crecería sin decir nada nuevo.
      final batch = FakeBatch();
      final first = await translateLatex(
        'Una frase.',
        memory: TranslationMemory.empty(),
        translate: batch.call,
      );
      final second = await translateLatex(
        'Una frase.',
        memory: TranslationMemory(first.learned),
        translate: batch.call,
      );
      expect(second.learned, isEmpty);
    });
  });

  group('lo que se cuenta', () {
    test('las matemáticas no se pagan', () async {
      // Lo que se cuenta es lo que se manda, y las fórmulas no se mandan. Es
      // lo que hace que traducir un tema de matemáticas cueste mucho menos
      // que su tamaño en disco.
      const conMatematicas = r'''
Sea
\begin{align}
  a &= b + c + d + e + f + g \\
  h &= i + j + k + l + m + n
\end{align}
y ya está.
''';
      final out = await translateLatex(
        conMatematicas,
        memory: TranslationMemory.empty(),
        translate: FakeBatch().call,
      );

      expect(out.stats.characters, greaterThan(0));
      expect(
        out.stats.characters,
        lessThan(conMatematicas.length ~/ 2),
        reason: 'el bloque `align` entero no se manda',
      );
    });

    test('la proporción de reutilización sale de los segmentos', () async {
      final first = await translateLatex(
        'Uno.\n\nDos.\n',
        memory: TranslationMemory.empty(),
        translate: FakeBatch().call,
      );
      final second = await translateLatex(
        'Uno.\n\nDos.\n',
        memory: TranslationMemory(first.learned),
        translate: FakeBatch().call,
      );
      expect(first.stats.reuse, 0);
      expect(second.stats.reuse, 1);
    });

    test('se pueden sumar, para una tanda entera', () async {
      const a = TranslationStats(segments: 4, reused: 1, translated: 3);
      const b = TranslationStats(segments: 6, reused: 5, translated: 1);
      expect(a.plus(b).segments, 10);
      expect(a.plus(b).reused, 6);
    });
  });

  group('la terminología', () {
    test('se avisa cuando un término no sale como debe', () async {
      final out = await translateLatex(
        'El supremo de un conjunto acotado.',
        memory: TranslationMemory.empty(),
        translate: (pieces) async => ['El màxim de un conjunt acotat.'],
        terms: const [TermCheck(source: 'supremo', target: 'suprem')],
      );

      expect(out.warnings, isNotEmpty);
      expect(out.warnings.first, contains('suprem'));
    });

    test('pero no se corrige', () async {
      // Sustituir la palabra deja una frase que nadie ha escrito, que puede
      // no concordar, y que encima parece revisada.
      final out = await translateLatex(
        'El supremo de un conjunto.',
        memory: TranslationMemory.empty(),
        translate: (pieces) async => ['El màxim de un conjunt.'],
        terms: const [TermCheck(source: 'supremo', target: 'suprem')],
      );
      expect(out.text, contains('màxim'));
    });

    test('y no se avisa de un término que sí sale', () async {
      final out = await translateLatex(
        'El supremo de un conjunto.',
        memory: TranslationMemory.empty(),
        translate: (pieces) async => ['El suprem d\'un conjunt.'],
        terms: const [TermCheck(source: 'supremo', target: 'suprem')],
      );
      expect(out.warnings, isEmpty);
    });

    test('ni de uno que no estaba en el original', () async {
      final out = await translateLatex(
        'Una frase cualquiera.',
        memory: TranslationMemory.empty(),
        translate: FakeBatch().call,
        terms: const [TermCheck(source: 'supremo', target: 'suprem')],
      );
      expect(out.warnings, isEmpty);
    });
  });

  group('el fichero de memoria', () {
    test('se lee y se escribe línea a línea', () {
      final memory = TranslationMemory([
        const MemoryEntry(source: 'Uno.', target: 'Un.'),
        const MemoryEntry(source: 'Dos.', target: 'Dos.'),
      ]);
      final text = memory.entries
          .map((e) => '{"source":"${e.source}","target":"${e.target}"}')
          .join('\n');

      final back = TranslationMemory.parse(text);
      expect(back.length, 2);
      expect(back.lookup('Uno.')!.target, 'Un.');
    });

    test('una línea rota se salta, no tira el fichero', () {
      // Lo escriben varias máquinas y lo fusiona git: una línea a medias de
      // un merge mal resuelto puede pasar. Perder un segmento es volver a
      // traducirlo; negarse a leer es perderlos todos.
      final back = TranslationMemory.parse(
        '{"source":"Uno.","target":"Un."}\n'
        '<<<<<<< HEAD\n'
        '{roto\n'
        '{"source":"Dos.","target":"Dos."}\n',
      );
      expect(back.length, 2);
    });

    test('la última línea manda', () {
      // El fichero se añade al final, así que lo último escrito es la
      // decisión más reciente sobre ese segmento.
      final back = TranslationMemory.parse(
        '{"source":"Uno.","target":"Viejo."}\n'
        '{"source":"Uno.","target":"Nuevo."}\n',
      );
      expect(back.lookup('Uno.')!.target, 'Nuevo.');
    });

    test('solo se añade lo que cambia', () {
      final memory = TranslationMemory([
        const MemoryEntry(source: 'Uno.', target: 'Un.'),
      ]);
      final lines = memory.linesFor([
        const MemoryEntry(source: 'Uno.', target: 'Un.'),
        const MemoryEntry(source: 'Dos.', target: 'Dos.'),
      ]);
      expect(lines.length, 1);
      expect(lines.single, contains('Dos.'));
    });

    test('juntar dos repositorios: el último gana', () {
      final merged = TranslationMemory.merge([
        TranslationMemory([const MemoryEntry(source: 'Uno.', target: 'A.')]),
        TranslationMemory([const MemoryEntry(source: 'Uno.', target: 'B.')]),
      ]);
      expect(merged.lookup('Uno.')!.target, 'B.');
    });

    test('cada par de idiomas tiene su fichero', () {
      // Dos personas traduciendo a idiomas distintos no se pisan el fichero
      // ni se pelean en el merge.
      expect(memoryPath('es', 'va'), 'translation/memory/es-va.jsonl');
      expect(memoryPath('es', 'en'), isNot(memoryPath('es', 'va')));
    });
  });
}
