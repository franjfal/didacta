/// Que traducir no pueda romper un `.tex`.
///
/// Es la pieza de la que depende todo lo demás del sistema de traducción, y
/// la que más daño hace si falla en silencio: un `\label` traducido rompe
/// todas las referencias del tema, y no se nota hasta que alguien compila la
/// víspera.
///
/// Por eso la regla es al revés de lo natural: **se protege por defecto y se
/// traduce por lista**. Estos tests fijan sobre todo lo que NO puede salir de
/// aquí.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/latex_protect.dart';

/// Lo que se le mandaría al traductor, junto.
String sent(String tex) =>
    protectLatex(tex).where((s) => !s.verbatim).map((s) => s.text).join('|');

/// El ida y vuelta completo, con una «traducción» que no toca las etiquetas.
String roundTrip(String tex, {String Function(String)? translate}) {
  final out = StringBuffer();
  for (final segment in protectLatex(tex)) {
    if (segment.verbatim || segment.letters == 0) {
      out.write(segment.restore(segment.text) ?? segment.text);
      continue;
    }
    final translated = (translate ?? (t) => t)(segment.text);
    final restored = segment.restore(translated);
    expect(restored, isNotNull, reason: 'no se pudo reconstruir: $translated');
    out.write(restored);
  }
  return out.toString();
}

void main() {
  group('lo que no sale de aquí', () {
    test('las matemáticas en línea', () {
      expect(
        sent(r'La raíz $\sqrt{2}$ es irracional.'),
        isNot(contains(r'\sqrt')),
      );
    });

    test('las matemáticas en bloque', () {
      const tex = 'Sea\n\\[ x = \\frac{a}{b} \\]\ny entonces.';
      expect(sent(tex), isNot(contains(r'\frac')));
    });

    test('un entorno matemático entero', () {
      const tex =
          'Antes.\n\\begin{align}\n  a &= b \\\\\n  c &= d\n\\end{align}\nDespués.';
      final out = sent(tex);
      expect(out, isNot(contains('align')));
      expect(out, contains('Antes'));
      expect(out, contains('Después'));
    });

    test('las claves de referencia', () {
      // El caso que más duele: `\label{sec:normas}` traducido rompe todas las
      // referencias del tema, y en silencio.
      const tex = r'Como vimos en \ref{sec:normas}, y \label{sec:otro} aquí.';
      final out = sent(tex);
      expect(out, isNot(contains('sec:normas')));
      expect(out, isNot(contains('sec:otro')));
      expect(out, contains('Como vimos en'));
    });

    test('las citas', () {
      const tex = r'Está en \cite[Theorem 1.1.1]{Abbott}.';
      expect(sent(tex), isNot(contains('Abbott')));
      expect(sent(tex), isNot(contains('Theorem 1.1.1')));
    });

    test('las figuras y sus medidas', () {
      const tex = r'\includegraphics[width=.85\textwidth]{figures/corte1.png}';
      final out = sent(tex);
      expect(out, isNot(contains('figures/corte1.png')));
      expect(out, isNot(contains('width')));
      // Viaja, pero como etiqueta: no lleva ni una letra que traducir.
      expect(protectLatex(tex).every((s) => s.letters == 0), isTrue);
    });

    test('el código y los dibujos', () {
      const tex =
          'Mira:\n\\begin{tikzpicture}\n  \\draw (0,0) -- (1,1);\n\\end{tikzpicture}';
      expect(sent(tex), isNot(contains('draw')));
    });

    test('los comentarios', () {
      // Prosa tachada a propósito: el material migrado está lleno.
      const tex =
          'Visible.\n% Esto estaba comentado y no se da este año.\nMás.';
      final out = sent(tex);
      expect(out, contains('Visible'));
      expect(out, isNot(contains('comentado')));
    });

    test('un comando desconocido viaja entero', () {
      // Lo que no está en la lista se protege: perder una frase se ve y se
      // arregla; un argumento traducido que era una clave, no.
      const tex = r'Antes \comandoraro{valor-interno} después.';
      final out = sent(tex);
      expect(out, isNot(contains('valor-interno')));
      expect(out, contains('después'));
    });
  });

  group('lo que sí se traduce', () {
    test('la prosa suelta', () {
      expect(
        sent('Toda sucesión de Cauchy es acotada.'),
        contains('Toda sucesión de Cauchy es acotada.'),
      );
    });

    test('lo que va dentro de un comando de texto', () {
      const tex = r'\textbf{Conceptos estudiados:} y más.';
      final out = sent(tex);
      expect(out, contains('Conceptos estudiados:'));
      expect(out, isNot(contains('textbf')));
    });

    test('un título de unidad', () {
      expect(
        sent(r'\didactatitle{El principio de inducción}'),
        contains('El principio de inducción'),
      );
    });

    test('prosa con matemáticas dentro, sin perder ninguna de las dos', () {
      const tex = r'La función $f$ es continua en $[0,1]$ salvo en un punto.';
      final out = sent(tex);
      expect(out, contains('La función'));
      expect(out, contains('es continua en'));
      expect(out, contains('salvo en un punto'));
      expect(out, isNot(contains('[0,1]')));
    });
  });

  group('el ida y vuelta', () {
    test('sin tocar nada, el fichero sale idéntico', () {
      // La prueba que sostiene todo: si el ciclo no es exacto con una
      // traducción que no cambia nada, no lo va a ser con una que sí.
      const tex = r'''
\didactatitle{La función de Dirichlet}
En 1829 Dirichlet propuso la función con dominio $\mathbb R$:
\[
g(x) := \begin{cases} 1 & x\in\mathbb Q \\ 0 & x\notin\mathbb Q \end{cases}
\]
% una nota comentada
Esta función \textbf{no es continua} en ningún punto \cite[p. 12]{Abbott}.
\includegraphics[width=.8\textwidth]{figures/dirichlet.pdf}
''';
      expect(roundTrip(tex), tex);
    });

    test('traduciendo de verdad, la sintaxis se queda donde estaba', () {
      const tex =
          r'La raíz $\sqrt{2}$ es irracional \label{raiz}, como en \cite{Tao}.';
      final out = roundTrip(
        tex,
        translate: (text) => text
            .replaceAll('La raíz', 'The root')
            .replaceAll('es irracional', 'is irrational')
            .replaceAll('como en', 'as in'),
      );
      expect(out, contains(r'$\sqrt{2}$'));
      expect(out, contains(r'\label{raiz}'));
      expect(out, contains(r'\cite{Tao}'));
      expect(out, contains('The root'));
      expect(out, contains('is irrational'));
    });

    test('una traducción que se come una etiqueta no se aplica', () {
      // Es el fallo que hay que atrapar: una etiqueta perdida es un `\ref`
      // que desapareció, y adivinar dónde iba es peor que no traducir.
      final segment = protectLatex(
        r'Ver $x$ y $y$ aquí.',
      ).firstWhere((s) => s.letters > 0);
      final broken = segment.text.replaceFirst(RegExp(r'<x id="\d+"/>'), '');
      expect(segment.restore(broken), isNull);
    });

    test('una etiqueta inventada tampoco', () {
      final segment = protectLatex(
        r'Ver $x$ aquí.',
      ).firstWhere((s) => s.letters > 0);
      expect(segment.restore('${segment.text}<x id="9"/>'), isNull);
    });

    test(
      'las etiquetas pueden cambiar de orden, que es lo que hace un idioma',
      () {
        // «el conjunto $A$» pasa a «set $A$»: el orden de las palabras cambia y
        // la etiqueta se mueve con ellas. Eso tiene que valer.
        final segment = protectLatex(
          r'El conjunto $A$ es abierto.',
        ).firstWhere((s) => s.letters > 0);
        final tag = RegExp(
          r'<x id="\d+"/>',
        ).firstMatch(segment.text)!.group(0)!;
        final moved = '$tag is an open set.';
        expect(segment.restore(moved), r'$A$ is an open set.');
      },
    );
  });

  group('cuánto se manda', () {
    test('un fichero sin prosa no manda nada', () {
      const tex = r'\includegraphics{figures/x.pdf}';
      expect(protectLatex(tex).every((s) => s.letters == 0), isTrue);
    });

    test('se cuenta la prosa, no las etiquetas', () {
      final segment = protectLatex(
        r'Hola $x$.',
      ).firstWhere((s) => s.letters > 0);
      expect(segment.letters, lessThan(segment.text.length));
    });
  });
}
